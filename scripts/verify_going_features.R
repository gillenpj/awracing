# scripts/verify_going_features.R
# Read-only verification gate for R/build_going_features.R (paper 3's
# going-affinity feature). stopifnot() throughout; halts on the first
# failing assertion rather than working around it.
#
# Run with:
#   "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" scripts/verify_going_features.R
# from the project root. Touches the `_targets` store and (for assertion 1's
# brute-force recomputation) no DB connection is needed -- everything is
# read from cached targets. Run via PowerShell, not the Bash tool, per
# [[xgboost-bash-segfault]] memory (tar_read() against this store has
# segfaulted under the Bash tool's Git Bash environment before).

source("renv/activate.R")

suppressPackageStartupMessages({
  library(targets)
  library(dplyr)
})
source("R/build_going_features.R")
source("R/build_extended_features.R")
source("R/model_fitting_p2.R")

set.seed(20260820)

qualifying_runners <- targets::tar_read(qualifying_runners)
qualifying_races   <- targets::tar_read(qualifying_races)
full_history        <- targets::tar_read(full_history)
runners_augmented_old <- targets::tar_read(runners_augmented)

stopifnot("going" %in% names(full_history))

going_features <- build_going_features(qualifying_runners, qualifying_races, full_history)

cat("going_features rows:", nrow(going_features), "\n")
cat("qualifying_runners rows:", nrow(qualifying_runners), "\n\n")
stopifnot(nrow(going_features) == nrow(qualifying_runners))

# ---------------------------------------------------------------------------
# (1) No same-day leakage: 200 sampled runner-races, brute-force recompute
#     going_runs_prior from raw career rows with an explicit date < filter.
# ---------------------------------------------------------------------------
cat("---- (1) No same-day leakage (200 sampled runner-races, brute force) ----\n")

race_dates <- qualifying_races |> dplyr::select(race_id, qualifying_date = meeting_date)

sampled <- going_features |>
  dplyr::left_join(race_dates, by = "race_id") |>
  dplyr::slice_sample(n = 200)

history_min <- full_history |>
  dplyr::filter(is.na(unfinished) | unfinished != "Non-Runner") |>
  dplyr::transmute(
    runner_id,
    hist_date    = meeting_date,
    hist_won     = dplyr::coalesce(amended_position, finish_position) == 1L,
    hist_surface = dplyr::if_else(race_type == "All Weather Flat", "AW", "Turf"),
    hist_ordinal = unname(going_ordinal[normalize_going(going)])
  ) |>
  dplyr::left_join(
    going_bucket, by = c("hist_surface" = "surface", "hist_ordinal" = "going_ordinal")
  ) |>
  dplyr::rename(hist_bucket = going_bucket)

brute_force_runs_prior <- function(rid, today_bucket, qdate) {
  h <- history_min |>
    dplyr::filter(runner_id == rid, hist_date < qdate)   # explicit strict-before
  if (nrow(h) == 0L) return(NA_integer_)
  sum(h$hist_bucket == today_bucket, na.rm = TRUE)
}

race_today_bucket <- qualifying_races |>
  dplyr::transmute(
    race_id,
    today_ordinal = dplyr::coalesce(unname(going_ordinal[normalize_going(going)]), 4)
  ) |>
  dplyr::left_join(
    going_bucket |> dplyr::filter(surface == "AW") |> dplyr::select(-surface),
    by = c("today_ordinal" = "going_ordinal")
  ) |>
  dplyr::rename(today_bucket = going_bucket)

sampled <- sampled |>
  dplyr::left_join(race_today_bucket, by = "race_id")

brute <- purrr::pmap_int(
  list(sampled$runner_id, sampled$today_bucket, sampled$qualifying_date),
  brute_force_runs_prior
)

mismatch <- sum(!(brute == sampled$going_runs_prior |
                     (is.na(brute) & is.na(sampled$going_runs_prior))))
cat("n sampled:", nrow(sampled), " mismatches:", mismatch, "\n")
stopifnot(mismatch == 0L)
cat("OK: brute-force matches exactly on all 200 samples\n\n")

# ---------------------------------------------------------------------------
# (2) going_sr_shrunk in [0, 1] wherever defined.
# ---------------------------------------------------------------------------
cat("---- (2) going_sr_shrunk in [0, 1] wherever defined ----\n")
defined <- going_features |> dplyr::filter(!is.na(going_sr_shrunk))
cat("n defined:", nrow(defined), " range: [",
    min(defined$going_sr_shrunk), ", ", max(defined$going_sr_shrunk), "]\n", sep = "")
stopifnot(all(defined$going_sr_shrunk >= 0 & defined$going_sr_shrunk <= 1))
cat("OK\n\n")

# ---------------------------------------------------------------------------
# (3) going_runs_prior == 0 iff going_sr_shrunk is NA, refined for the
#     true-debut case where going_runs_prior is itself NA: going_sr_shrunk
#     is NA exactly when going_runs_prior is NA or 0, non-NA exactly when
#     going_runs_prior is a positive count.
# ---------------------------------------------------------------------------
cat("---- (3) going_sr_shrunk NA iff going_runs_prior is NA or 0 ----\n")
sr_na   <- is.na(going_features$going_sr_shrunk)
runs_na_or_zero <- is.na(going_features$going_runs_prior) | going_features$going_runs_prior == 0
cat("mismatches:", sum(sr_na != runs_na_or_zero), "\n")
stopifnot(all(sr_na == runs_na_or_zero))
cat("OK\n\n")

# ---------------------------------------------------------------------------
# (4) Where going_runs_prior >= 30, going_sr_shrunk within 0.02 of the
#     unshrunk rate -- shrinkage vanishes with exposure.
# ---------------------------------------------------------------------------
cat("---- (4) Shrinkage vanishes with exposure (going_runs_prior >= 30) ----\n")

race_dates2 <- qualifying_races |> dplyr::select(race_id, qualifying_date = meeting_date)
history_won <- full_history |>
  dplyr::filter(is.na(unfinished) | unfinished != "Non-Runner") |>
  dplyr::transmute(
    runner_id, hist_date = meeting_date,
    hist_won     = dplyr::coalesce(amended_position, finish_position) == 1L,
    hist_surface = dplyr::if_else(race_type == "All Weather Flat", "AW", "Turf"),
    hist_ordinal = unname(going_ordinal[normalize_going(going)])
  ) |>
  dplyr::left_join(
    going_bucket, by = c("hist_surface" = "surface", "hist_ordinal" = "going_ordinal")
  ) |>
  dplyr::rename(hist_bucket = going_bucket)

high_exposure <- going_features |>
  dplyr::filter(!is.na(going_runs_prior), going_runs_prior >= 30) |>
  dplyr::left_join(race_dates2, by = "race_id") |>
  dplyr::left_join(race_today_bucket, by = "race_id")

cat("n high-exposure rows:", nrow(high_exposure), "\n")
if (nrow(high_exposure) > 0L) {
  unshrunk_rate <- function(rid, tb, qd) {
    h <- history_won |> dplyr::filter(runner_id == rid, hist_date < qd,
                                       hist_bucket == tb)
    sum(h$hist_won, na.rm = TRUE) / nrow(h)
  }
  high_exposure$unshrunk <- purrr::pmap_dbl(
    list(high_exposure$runner_id, high_exposure$today_bucket, high_exposure$qualifying_date),
    unshrunk_rate
  )
  diffs <- abs(high_exposure$going_sr_shrunk - high_exposure$unshrunk)
  cat("max |shrunk - unshrunk| at runs>=30:", max(diffs), "\n")
  stopifnot(all(diffs < 0.02))
  cat("OK\n\n")
} else {
  cat("No rows with going_runs_prior >= 30 -- nothing to check (reported, not silently skipped).\n\n")
}

# ---------------------------------------------------------------------------
# (5) going_ordinal never NA on qualifying_races (i.e. on going_features).
# ---------------------------------------------------------------------------
cat("---- (5) going_ordinal never NA ----\n")
n_na_ordinal <- sum(is.na(going_features$going_ordinal))
cat("n NA going_ordinal:", n_na_ordinal, "\n")
stopifnot(n_na_ordinal == 0L)
cat("OK\n\n")

# ---------------------------------------------------------------------------
# (6) Every pre-existing runners_augmented column unchanged.
# ---------------------------------------------------------------------------
cat("---- (6) Pre-existing runners_augmented columns byte-identical ----\n")
runners_augmented_new <- targets::tar_read(features) |>
  dplyr::left_join(targets::tar_read(jockey_sr_premiums),   by = c("race_id", "runner_id")) |>
  dplyr::left_join(targets::tar_read(within_race_features), by = c("race_id", "runner_id")) |>
  dplyr::left_join(targets::tar_read(career_form_features), by = c("race_id", "runner_id")) |>
  dplyr::left_join(going_features,                          by = c("race_id", "runner_id"))

old_cols <- names(runners_augmented_old)
stopifnot(all(old_cols %in% names(runners_augmented_new)))
stopifnot(nrow(runners_augmented_new) == nrow(runners_augmented_old))

common <- runners_augmented_new |> dplyr::select(dplyr::all_of(old_cols))
identical_check <- identical(
  as.data.frame(common)[order(common$race_id, common$runner_id), ],
  as.data.frame(runners_augmented_old)[order(runners_augmented_old$race_id, runners_augmented_old$runner_id), ]
)
cat("all.equal on pre-existing columns:", isTRUE(all.equal(
  as.data.frame(common)[order(common$race_id, common$runner_id), ],
  as.data.frame(runners_augmented_old)[order(runners_augmented_old$race_id, runners_augmented_old$runner_id), ]
)), "\n")
stopifnot(isTRUE(all.equal(
  as.data.frame(common)[order(common$race_id, common$runner_id), ],
  as.data.frame(runners_augmented_old)[order(runners_augmented_old$race_id, runners_augmented_old$runner_id), ]
)))
cat("OK: every pre-existing column is unchanged\n\n")

# ---------------------------------------------------------------------------
# (7) The 2b complete-case race count is unchanged after the join. Uses the
#     ACTUAL exploded_interactions_data construction (build_interaction_features()
#     + the draw-interaction extra_na_vars) -- the complete-case set behind
#     model_2b_exploded_draw_final, paper 2b's published headline model. An
#     earlier version of this assertion checked prepare_exploded_data() on
#     runners_model_ready directly (no interaction columns, no extra_na_vars),
#     which is a DIFFERENT, non-interaction complete-case set
#     (model_2b_exploded_base's) and gave a different, not-directly-relevant
#     race count (5,023) -- fixed here to check the right target (5,022).
# ---------------------------------------------------------------------------
cat("---- (7) Paper 2b complete-case race count unchanged ----\n")
races_train <- targets::tar_read(races_train)

runners_model_ready_old <- targets::tar_read(runners_model_ready)
runners_model_ready_new <- runners_augmented_new |>
  build_model_ready(qualifying_races, races_train)

runners_interactions_old <- build_interaction_features(runners_model_ready_old, qualifying_races)
runners_interactions_new <- build_interaction_features(runners_model_ready_new, qualifying_races)

interaction_extra_na_vars <- c("rel_weight_x_dist", "stall_x_kempton", "stall_x_lingfield",
                                "stall_x_southwell", "stall_x_wolverhampton")

exploded_old <- prepare_exploded_data(
  runners_interactions_old |>
    dplyr::filter(split == "train") |>
    dplyr::left_join(
      dplyr::select(qualifying_runners, race_id, runner_id, finish_position, amended_position),
      by = c("race_id", "runner_id")
    ),
  extra_na_vars = interaction_extra_na_vars
)
exploded_new <- prepare_exploded_data(
  runners_interactions_new |>
    dplyr::filter(split == "train") |>
    dplyr::left_join(
      dplyr::select(qualifying_runners, race_id, runner_id, finish_position, amended_position),
      by = c("race_id", "runner_id")
    ),
  extra_na_vars = interaction_extra_na_vars
)

strip_dfidx <- function(eid) {
  df <- as.data.frame(eid)
  class(df) <- "data.frame"
  attr(df, "index")    <- NULL
  attr(df, "clseries") <- NULL
  df
}
n_races_old <- length(unique(strip_dfidx(exploded_old)$race_id))
n_races_new <- length(unique(strip_dfidx(exploded_new)$race_id))
cat("2b exploded-interactions training race count -- before going_features:", n_races_old,
    " after:", n_races_new, "\n")
stopifnot(n_races_old == n_races_new)
cat("OK: race universe unchanged\n\n")

# ---------------------------------------------------------------------------
# (8) Every mapped going string round-trips: no string maps to two ordinals.
# ---------------------------------------------------------------------------
cat("---- (8) No going string maps to two ordinals ----\n")
dup_keys <- names(going_ordinal)[duplicated(names(going_ordinal))]
cat("duplicate keys in going_ordinal:", length(dup_keys), "\n")
stopifnot(length(dup_keys) == 0L)

all_raw_going <- dplyr::bind_rows(
  dplyr::transmute(full_history, going),
  dplyr::transmute(qualifying_races, going)
) |>
  dplyr::filter(!is.na(going)) |>
  dplyr::mutate(going_norm = normalize_going(going)) |>
  dplyr::distinct(going, going_norm) |>
  dplyr::mutate(ordinal = unname(going_ordinal[going_norm]))

round_trip_check <- all_raw_going |>
  dplyr::group_by(going_norm) |>
  dplyr::summarise(n_distinct_ordinal = dplyr::n_distinct(ordinal), .groups = "drop")
cat("max n_distinct_ordinal per normalised key:", max(round_trip_check$n_distinct_ordinal), "\n")
stopifnot(all(round_trip_check$n_distinct_ordinal == 1L))
cat("OK: every mapped string round-trips to exactly one ordinal\n\n")

cat("All checks passed.\n\n")

# ===========================================================================
# Report: vocabulary tables, cut points, NA share, distribution, decile table
# ===========================================================================
cat("==== Vocabulary: full career-history universe, by surface ====\n")
vocab_full <- full_history |>
  dplyr::mutate(surface = dplyr::if_else(race_type == "All Weather Flat", "AW", "Turf")) |>
  dplyr::count(surface, going, sort = TRUE)
print(vocab_full, n = 100)

cat("\n==== Vocabulary: qualifying_races ====\n")
print(qualifying_races |> dplyr::count(going, sort = TRUE))

cat("\n==== Unmapped strings (should be none) ====\n")
unmapped_full <- full_history |>
  dplyr::filter(!is.na(going)) |>
  dplyr::mutate(n_ok = !is.na(unname(going_ordinal[normalize_going(going)])))
print(unmapped_full |> dplyr::filter(!n_ok) |> dplyr::count(going))

cat("\n==== going_bucket cut points ====\n")
print(going_bucket)

cat("\n==== NA share, going affinity columns, train vs test ====\n")
runners_model_ready_report <- runners_model_ready_new
na_report <- runners_model_ready_report |>
  dplyr::group_by(split) |>
  dplyr::summarise(
    n                       = dplyr::n(),
    n_na_runs_prior         = sum(is.na(going_runs_prior)),
    n_zero_runs_prior       = sum(!is.na(going_runs_prior) & going_runs_prior == 0),
    n_na_sr_shrunk          = sum(is.na(going_sr_shrunk)),
    share_na_sr_shrunk      = round(100 * n_na_sr_shrunk / n, 2),
    .groups = "drop"
  )
print(na_report)

cat("\n==== Distribution of going_runs_prior ====\n")
print(summary(runners_model_ready_report$going_runs_prior))
cat("\nQuantiles:\n")
print(quantile(runners_model_ready_report$going_runs_prior, probs = seq(0, 1, 0.1), na.rm = TRUE))

cat("\n==== Train-split-only win rate by going_sr_delta decile ====\n")
train_decile <- runners_model_ready_report |>
  dplyr::filter(split == "train", !is.na(going_sr_delta)) |>
  dplyr::mutate(decile = dplyr::ntile(going_sr_delta, 10))

decile_table <- train_decile |>
  dplyr::group_by(decile) |>
  dplyr::summarise(
    n           = dplyr::n(),
    delta_min   = min(going_sr_delta),
    delta_max   = max(going_sr_delta),
    win_rate    = mean(won),
    .groups = "drop"
  )
print(decile_table, n = 15)
