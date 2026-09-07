# _targets_p5.R
#
# Paper 5 — sequence encoding of run histories.
#
# A SEPARATE pipeline with a SEPARATE store, following paper 4, so nothing
# here can touch papers 1-4. Run it with the script and store passed
# explicitly rather than through `_targets.yaml`, which the paper qmd setup
# chunks own — writing that file would point papers 1-3 at the wrong store
# on their next render:
#
#   targets::tar_make(script = "_targets_p5.R", store = "_targets_p5")
#   targets::tar_read(p5_rung1_comparison, store = "_targets_p5")
#
# `tar_config_set()` is never called anywhere in paper 5.
#
# Upstream inputs come from the MAIN store, READ-ONLY, with their content
# hashes recorded in `p5_upstream_fingerprint` so that an upstream change
# invalidates everything downstream rather than going stale silently.
#
# THIS TASK IS THE PIPELINE AND RUNG 1 ONLY. The sequences are built and
# verified here because rungs 2 and 3 need them, but rung 1 does not consume
# them: the MLP control scores paper 3's 24 tabular features. The encoder
# and the entity embeddings are not built.
#
# THE TEST SPLIT IS NOT SCORED ANYWHERE IN THIS FILE.

Sys.setenv(R_LIBS   = paste(.libPaths(), collapse = .Platform$path.sep))
Sys.setenv(QUARTO_R = file.path(R.home("bin"), "Rscript.exe"))
if (Sys.getenv("QUARTO_PATH") == "") {
  candidates <- c(
    "C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe",
    "C:/Program Files/Quarto/bin/quarto.exe",
    file.path(Sys.getenv("LOCALAPPDATA"), "Programs/Quarto/bin/quarto.exe")
  )
  found <- candidates[file.exists(candidates)]
  if (length(found)) Sys.setenv(QUARTO_PATH = found[[1]])
}

library(targets)
library(tarchetypes)

tar_option_set(
  packages = c("dplyr", "tidyr", "tibble", "purrr", "stringr", "readr",
               "lubridate", "ggplot2", "DBI", "RMariaDB", "torch", "mlogit"),
  format   = "rds"
)

tar_source("R/db.R")
tar_source("R/p5_sequences.R")
tar_source("R/p5_torch.R")
tar_source("R/p5_mlp.R")
tar_source("R/p5_baseline_2b.R")

# Paper 3's and paper 2b's own code, sourced READ-ONLY and reused unchanged:
# the feature list and matrix contract, the PL objective and its ordering
# contract, the ranking metrics and paired bootstrap, the going lookup, and
# the exploded conditional logit. Paper 5 adds no variant of any of them.
tar_source("R/pl_objective.R")
tar_source("R/gbt_data.R")
tar_source("R/gbt_results.R")
tar_source("R/scoring.R")
tar_source("R/build_going_features.R")
tar_source("R/model_fitting_p2.R")
tar_source("R/ranking_eval_p2b.R")

MAIN_STORE <- "_targets"
P5_TRAIN_CUTOFF <- as.Date("2012-12-30")

list(

  # -- Upstream, from the frozen main store, read-only ---------------------
  tar_target(
    p5_upstream_fingerprint,
    targets::tar_meta(
      names = c("full_history", "runners_interactions", "qualifying_runners",
                "qualifying_races", "gbt_train_data", "gbt_test_data",
                "model_p2_reduced"),
      fields = c("name", "data"),
      store  = MAIN_STORE
    )
  ),

  tar_target(p5_full_history, {
    p5_upstream_fingerprint
    targets::tar_read(full_history, store = MAIN_STORE)
  }),
  tar_target(p5_runners_interactions, {
    p5_upstream_fingerprint
    targets::tar_read(runners_interactions, store = MAIN_STORE)
  }),
  tar_target(p5_qualifying_runners, {
    p5_upstream_fingerprint
    targets::tar_read(qualifying_runners, store = MAIN_STORE)
  }),
  tar_target(p5_model_p2_reduced, {
    p5_upstream_fingerprint
    targets::tar_read(model_p2_reduced, store = MAIN_STORE)
  }),

  # Paper 3's frame, taken from the matrices paper 3 was fitted and scored
  # on rather than re-derived from the complete-case rule.
  tar_target(p5_frame, {
    p5_upstream_fingerprint
    dates <- targets::tar_read(runners_interactions, store = MAIN_STORE) |>
      dplyr::select(race_id, runner_id, race_date, split)
    train_key <- targets::tar_read(gbt_train_data, store = MAIN_STORE)$key
    test_key <- targets::tar_read(gbt_test_data, store = MAIN_STORE)$key
    dplyr::bind_rows(train_key, test_key) |>
      dplyr::left_join(dates, by = c("race_id", "runner_id"))
  }),

  # -- Prior-run sequences -------------------------------------------------
  # One race-level column the cached career-history query does not carry.
  # Not a second career-history query: one column, keyed on race id, no join
  # to runners and no filters.
  tar_target(p5_field_sizes, {
    con <- connect_smartform()
    on.exit(disconnect_smartform(con))
    p5_fetch_field_sizes(con, unique(p5_full_history$race_id))
  }),

  tar_target(
    p5_run_vectors,
    build_p5_run_vectors(p5_full_history, p5_field_sizes)
  ),

  tar_target(
    p5_sequences,
    build_p5_sequences(p5_frame, p5_run_vectors)
  ),

  tar_target(
    p5_sequence_summary,
    summarise_p5_sequences(p5_sequences, p5_frame, which_split = "train")
  ),

  # Row identity with paper 3's frame: the same rows, as a sorted set, not
  # merely the same race count.
  tar_target(
    p5_sequence_identity,
    {
      key_sorted <- function(d) {
        as.data.frame(dplyr::arrange(dplyr::select(d, race_id, runner_id),
                                     race_id, runner_id))
      }
      stopifnot(
        nrow(p5_sequences$key) == nrow(p5_frame),
        identical(key_sorted(p5_sequences$key), key_sorted(p5_frame)),
        anyDuplicated(p5_sequences$key) == 0L,
        dim(p5_sequences$x)[1] == nrow(p5_frame),
        dim(p5_sequences$x)[2] == P5_SEQ_MAX_LEN,
        dim(p5_sequences$x)[3] == length(P5_SEQ_FEATURES),
        length(p5_sequences$seq_len) == nrow(p5_frame),
        all(p5_sequences$seq_len <= P5_SEQ_MAX_LEN),
        all(p5_sequences$seq_len <= p5_sequences$career_runs_prior),
        !anyNA(p5_sequences$x)
      )
      tibble::tibble(
        check = c("rows", "row-identical to paper 3's frame on (race_id, runner_id)",
                  "array dims", "seq_len within cap", "no NA in the array"),
        value = c(nrow(p5_sequences$key), "TRUE",
                  paste(dim(p5_sequences$x), collapse = " x "),
                  max(p5_sequences$seq_len), "TRUE")
      )
    }
  ),

  # -- The validation slice ------------------------------------------------
  # The series splits train from test 70/30 by race count against a frozen
  # calendar date. The same rule one level down: the date at which 70% of
  # the TRAINING period's races have been run. A calendar date rather than a
  # race index, so it stays reproducible if the race universe changes.
  tar_target(
    p5_slice,
    {
      races <- p5_frame |>
        dplyr::filter(split == "train") |>
        dplyr::distinct(race_id, race_date) |>
        dplyr::arrange(race_date, race_id)
      cutoff <- races$race_date[ceiling(nrow(races) * 0.70)]
      fit <- dplyr::filter(races, race_date <= cutoff)
      val <- dplyr::filter(races, race_date > cutoff)
      list(
        boundary = cutoff,
        fit_race_ids = fit$race_id, val_race_ids = val$race_id,
        n_races_fit = nrow(fit), n_races_val = nrow(val),
        share_fit = nrow(fit) / nrow(races),
        fit_date_range = range(fit$race_date),
        val_date_range = range(val$race_date)
      )
    }
  ),

  # -- Matrices for the two arms -------------------------------------------
  # Rows arranged by `arrange_for_xgb()`, the ordering contract the PL
  # objective requires: within each race the first S = min(3, J-1) rows are
  # the top finishers in order.
  tar_target(
    p5_arm_data,
    {
      build_part <- function(ids) {
        keep <- p5_frame |>
          dplyr::filter(race_id %in% ids) |>
          dplyr::select(race_id, runner_id)
        fp <- p5_qualifying_runners |>
          dplyr::select(race_id, runner_id, finish_position, amended_position)
        ordered <- p5_runners_interactions |>
          dplyr::inner_join(keep, by = c("race_id", "runner_id")) |>
          dplyr::left_join(fp, by = c("race_id", "runner_id")) |>
          dplyr::mutate(
            finish_pos = dplyr::coalesce(amended_position, finish_position)
          ) |>
          arrange_for_xgb()
        stopifnot(nrow(ordered) == nrow(keep))

        gs <- rle(as.character(ordered$race_id))$lengths
        stopifnot(sum(gs) == nrow(ordered),
                  length(gs) == dplyr::n_distinct(ordered$race_id))
        check <- ordered |>
          dplyr::mutate(J = rep.int(gs, gs)) |>
          dplyr::group_by(race_id) |>
          dplyr::mutate(pos = dplyr::row_number(), S = pmin(3L, J - 1L)) |>
          dplyr::ungroup() |>
          dplyr::filter(pos <= S)
        stopifnot(all(check$finish_pos == check$pos))

        x <- ordered |>
          dplyr::mutate(
            course_Kempton = as.numeric(course == "Kempton"),
            course_Lingfield = as.numeric(course == "Lingfield"),
            course_Southwell = as.numeric(course == "Southwell"),
            course_Wolverhampton = as.numeric(course == "Wolverhampton")
          ) |>
          dplyr::select(dplyr::all_of(FEATURE_COLS)) |>
          as.matrix()

        list(rows = ordered, x = x, group_sizes = gs,
             key = dplyr::select(ordered, race_id, runner_id))
      }
      list(fit = build_part(p5_slice$fit_race_ids),
           val = build_part(p5_slice$val_race_ids))
    }
  ),

  tar_target(
    p5_standardised,
    {
      x_all <- rbind(p5_arm_data$fit$x, p5_arm_data$val$x)
      fit_rows <- seq_len(nrow(p5_arm_data$fit$x))
      st <- p5_standardise(x_all, fit_rows)
      list(
        fit = st$x[fit_rows, , drop = FALSE],
        val = st$x[-fit_rows, , drop = FALSE],
        centre = st$centre, scale = st$scale, na_share = st$na_share
      )
    }
  ),

  # -- Rung 1: the nine declared configurations ----------------------------
  tar_target(p5_configs, p5_mlp_configs()),

  tar_target(
    p5_mlp_runs,
    purrr::map(seq_len(nrow(p5_configs)), function(i) {
      p5_fit_mlp(
        p5_standardised$fit, p5_standardised$val,
        p5_arm_data$fit$group_sizes, p5_arm_data$val$group_sizes,
        p5_configs[i, ], seed = 42L, k = 3L
      )
    })
  ),

  tar_target(
    p5_config_scores,
    purrr::map(p5_mlp_runs, function(r) {
      tibble::tibble(config = r$config, widths = r$width_label, lr = r$lr,
                     best_val_pl_loss = r$best_val_loss,
                     best_epoch = r$best_epoch,
                     final_epoch_val_pl_loss = r$final_val_loss)
    }) |>
      purrr::list_rbind() |>
      dplyr::arrange(best_val_pl_loss)
  ),

  # -- The one permitted remediation pass ----------------------------------
  # The declared nine all overfit within about six epochs and none reached
  # the refitted paper-2b baseline. The rung's pre-registered reading allows
  # one pass over learning rate, epochs, batching and layer widths — never
  # the loss, features, split, metric or seed — and then a stop either way.
  tar_target(p5_configs_remediation, p5_mlp_configs_remediation()),

  tar_target(
    p5_mlp_runs_remediation,
    purrr::map(seq_len(nrow(p5_configs_remediation)), function(i) {
      p5_fit_mlp(
        p5_standardised$fit, p5_standardised$val,
        p5_arm_data$fit$group_sizes, p5_arm_data$val$group_sizes,
        p5_configs_remediation[i, ], seed = 42L, k = 3L
      )
    })
  ),

  tar_target(
    p5_remediation_scores,
    purrr::map(p5_mlp_runs_remediation, function(r) {
      tibble::tibble(config = r$config, widths = r$width_label, lr = r$lr,
                     best_val_pl_loss = r$best_val_loss,
                     best_epoch = r$best_epoch,
                     final_epoch_val_pl_loss = r$final_val_loss)
    }) |>
      purrr::list_rbind() |>
      dplyr::arrange(best_val_pl_loss)
  ),

  # Selection on validation PL loss and nothing else, over the declared nine
  # and the remediation pass together.
  tar_target(
    p5_mlp_selected,
    {
      all_runs <- c(p5_mlp_runs, p5_mlp_runs_remediation)
      all_runs[[which.min(purrr::map_dbl(all_runs, "best_val_loss"))]]
    }
  ),

  # -- The paper-2b baseline, refitted on the fitting partition ------------
  tar_target(
    p5_baseline,
    p5_fit_2b_baseline(p5_runners_interactions, p5_qualifying_runners,
                       p5_slice$fit_race_ids, p5_model_p2_reduced, k = 3L)
  ),

  tar_target(
    p5_baseline_scores,
    p5_score_2b_baseline(p5_baseline, p5_arm_data$val$rows)
  ),

  # -- Scoring both arms on the validation slice ---------------------------
  tar_target(
    p5_scored,
    {
      score_arm <- function(z, label) {
        sm <- pl_softmax_by_race(z, p5_arm_data$val$key$race_id,
                                 p5_arm_data$val$key$runner_id)
        sm |>
          dplyr::rename(win_model = p_win) |>
          dplyr::mutate(arm = label)
      }
      sp <- p5_qualifying_runners |>
        dplyr::select(race_id, runner_id, starting_price_decimal,
                      finish_position, amended_position, won)
      base <- p5_arm_data$val$key |>
        dplyr::left_join(sp, by = c("race_id", "runner_id")) |>
        dplyr::mutate(
          finish_pos = dplyr::coalesce(amended_position, finish_position)
        ) |>
        dplyr::group_by(race_id) |>
        dplyr::mutate(
          horse_ref = dplyr::row_number(),
          implied = dplyr::if_else(
            !is.na(starting_price_decimal) & starting_price_decimal > 1,
            1 / starting_price_decimal, NA_real_
          ),
          win_market = implied / sum(implied, na.rm = TRUE)
        ) |>
        dplyr::ungroup()

      list(
        mlp = dplyr::bind_cols(base, dplyr::select(
          score_arm(p5_mlp_selected$val_scores, "mlp"), win_model)),
        p2b = dplyr::bind_cols(base, dplyr::select(
          score_arm(p5_baseline_scores, "p2b"), win_model))
      )
    }
  ),

  tar_target(
    p5_scorable,
    {
      scorable <- function(d) {
        d |>
          dplyr::mutate(placed = as.integer(!is.na(finish_pos) &
                                              finish_pos %in% 1:3)) |>
          dplyr::group_by(race_id) |>
          dplyr::summarise(
            ok = all(!is.na(win_model) & win_model > 0 &
                       !is.na(win_market) & win_market > 0) &&
              setequal(intersect(finish_pos, 1:3), 1:3) &&
              sum(finish_pos %in% 1:3, na.rm = TRUE) == 3L,
            .groups = "drop"
          ) |>
          dplyr::filter(ok) |>
          dplyr::pull(race_id)
      }
      a <- scorable(p5_scored$mlp)
      b <- scorable(p5_scored$p2b)
      stopifnot(setequal(a, b))
      sort(a)
    }
  ),

  tar_target(
    p5_per_race,
    {
      per_race <- function(d) {
        rer <- d |>
          dplyr::filter(race_id %in% p5_scorable) |>
          dplyr::mutate(placed = as.integer(!is.na(finish_pos) &
                                              finish_pos %in% 1:3)) |>
          dplyr::select(race_id, horse_ref, won, win_model, win_market,
                        finish_pos, placed)
        build_ranking_per_race(rer, "win_model")
      }
      list(mlp = per_race(p5_scored$mlp), p2b = per_race(p5_scored$p2b))
    }
  ),

  # -- Rung 1: the comparison ----------------------------------------------
  tar_target(
    p5_rung1_comparison,
    bootstrap_ranking_metrics(p5_per_race$mlp, p5_per_race$p2b,
                              "MLP - paper 2b (refit)")
  ),

  # =======================================================================
  # P5-1b: rung 1 respecified.
  #
  # The control is paper 2b's 17 terms plus paper 3's four going features
  # and four course indicators — the same information as paper 3's 24,
  # encoded for a model that is not a tree. The remediation allowance
  # resets: the earlier pass was spent on a specification that no longer
  # exists.
  # =======================================================================

  tar_target(p5_control_terms, P5_CONTROL_TERMS),

  tar_target(
    p5_control_data,
    {
      stopifnot(length(p5_control_terms) == 26L)
      add_course <- function(d) {
        d |>
          dplyr::mutate(
            course_Kempton = as.numeric(course == "Kempton"),
            course_Lingfield = as.numeric(course == "Lingfield"),
            course_Southwell = as.numeric(course == "Southwell"),
            course_Wolverhampton = as.numeric(course == "Wolverhampton")
          )
      }
      x_fit <- add_course(p5_arm_data$fit$rows) |>
        dplyr::select(dplyr::all_of(p5_control_terms)) |> as.matrix()
      x_val <- add_course(p5_arm_data$val$rows) |>
        dplyr::select(dplyr::all_of(p5_control_terms)) |> as.matrix()
      st <- p5_standardise(rbind(x_fit, x_val), seq_len(nrow(x_fit)))
      list(
        fit = st$x[seq_len(nrow(x_fit)), , drop = FALSE],
        val = st$x[-seq_len(nrow(x_fit)), , drop = FALSE],
        na_share = st$na_share
      )
    }
  ),

  tar_target(p5_configs_v2, p5_mlp_configs()),

  tar_target(
    p5_mlp_runs_v2,
    purrr::map(seq_len(nrow(p5_configs_v2)), function(i) {
      p5_fit_mlp(
        p5_control_data$fit, p5_control_data$val,
        p5_arm_data$fit$group_sizes, p5_arm_data$val$group_sizes,
        p5_configs_v2[i, ], seed = 42L, k = 3L
      )
    })
  ),

  tar_target(
    p5_config_scores_v2,
    purrr::map(p5_mlp_runs_v2, function(r) {
      tibble::tibble(config = r$config, widths = r$width_label, lr = r$lr,
                     best_val_pl_loss = r$best_val_loss,
                     best_epoch = r$best_epoch,
                     final_epoch_val_pl_loss = r$final_val_loss)
    }) |>
      purrr::list_rbind() |>
      dplyr::arrange(best_val_pl_loss)
  ),

  tar_target(
    p5_mlp_selected_v2,
    p5_mlp_runs_v2[[which.min(purrr::map_dbl(p5_mlp_runs_v2, "best_val_loss"))]]
  ),

  tar_target(
    p5_scored_v2,
    {
      sp <- p5_qualifying_runners |>
        dplyr::select(race_id, runner_id, starting_price_decimal,
                      finish_position, amended_position, won)
      base <- p5_arm_data$val$key |>
        dplyr::left_join(sp, by = c("race_id", "runner_id")) |>
        dplyr::mutate(
          finish_pos = dplyr::coalesce(amended_position, finish_position)
        ) |>
        dplyr::group_by(race_id) |>
        dplyr::mutate(
          horse_ref = dplyr::row_number(),
          implied = dplyr::if_else(
            !is.na(starting_price_decimal) & starting_price_decimal > 1,
            1 / starting_price_decimal, NA_real_
          ),
          win_market = implied / sum(implied, na.rm = TRUE)
        ) |>
        dplyr::ungroup()
      add_scores <- function(z) {
        sm <- pl_softmax_by_race(z, p5_arm_data$val$key$race_id,
                                 p5_arm_data$val$key$runner_id)
        dplyr::bind_cols(base, dplyr::select(
          dplyr::rename(sm, win_model = p_win), win_model))
      }
      list(mlp = add_scores(p5_mlp_selected_v2$val_scores),
           p2b = add_scores(p5_baseline_scores))
    }
  ),

  tar_target(
    p5_per_race_v2,
    {
      per_race <- function(d) {
        rer <- d |>
          dplyr::filter(race_id %in% p5_scorable) |>
          dplyr::mutate(placed = as.integer(!is.na(finish_pos) &
                                              finish_pos %in% 1:3)) |>
          dplyr::select(race_id, horse_ref, won, win_model, win_market,
                        finish_pos, placed)
        build_ranking_per_race(rer, "win_model")
      }
      list(mlp = per_race(p5_scored_v2$mlp), p2b = per_race(p5_scored_v2$p2b))
    }
  ),

  tar_target(
    p5_rung1_comparison_v2,
    bootstrap_ranking_metrics(p5_per_race_v2$mlp, p5_per_race_v2$p2b,
                              "MLP (respecified) - paper 2b (refit)")
  ),

  tar_target(
    p5_rung1_reading_v2,
    {
      b <- p5_rung1_comparison_v2 |>
        dplyr::filter(metric %in% c("P1_rank", "Brier_place")) |>
        dplyr::mutate(
          excludes_zero = (ci_lo > 0 & ci_hi > 0) | (ci_lo < 0 & ci_hi < 0),
          favours = dplyr::case_when(
            !excludes_zero ~ "neither",
            metric == "P1_rank" & diff_point > 0 ~ "MLP",
            metric == "P1_rank" & diff_point < 0 ~ "paper 2b",
            metric == "Brier_place" & diff_point < 0 ~ "MLP",
            TRUE ~ "paper 2b"
          )
        )
      reading <- if (all(b$favours == "neither")) {
        "tie - both CIs straddle zero, as expected; proceed to rung 2"
      } else if (any(b$favours == "paper 2b")) {
        "implementation fault - a CI favours paper 2b; one remediation pass, then stop"
      } else {
        "MLP favoured - proceed, and record that the control claim is weakened"
      }
      list(table = b, reading = reading)
    }
  ),

  # =======================================================================
  # P5-1c: the control claim, on identical features.
  #
  # A linear scorer on the SAME 26 terms as the MLP, through the same loss,
  # loop, slice and seed. Every previous rung-1 contrast differed in two
  # ways at once — function class AND feature set — so none of them could
  # test the claim the rung exists for. This one changes only the function
  # class.
  # =======================================================================

  tar_target(
    p5_linear_v3,
    {
      config <- tibble::tibble(
        config = 1L, widths = list(integer(0)), width_label = "linear",
        lr = 1e-3, dropout = 0.1, batch_races = 64L, max_epochs = 200L,
        weight_decay = 1e-5
      )
      p5_fit_mlp(
        p5_control_data$fit, p5_control_data$val,
        p5_arm_data$fit$group_sizes, p5_arm_data$val$group_sizes,
        config, seed = 42L, k = 3L
      )
    }
  ),

  tar_target(
    p5_scored_v3,
    {
      sp <- p5_qualifying_runners |>
        dplyr::select(race_id, runner_id, starting_price_decimal,
                      finish_position, amended_position, won)
      base <- p5_arm_data$val$key |>
        dplyr::left_join(sp, by = c("race_id", "runner_id")) |>
        dplyr::mutate(
          finish_pos = dplyr::coalesce(amended_position, finish_position)
        ) |>
        dplyr::group_by(race_id) |>
        dplyr::mutate(
          horse_ref = dplyr::row_number(),
          implied = dplyr::if_else(
            !is.na(starting_price_decimal) & starting_price_decimal > 1,
            1 / starting_price_decimal, NA_real_
          ),
          win_market = implied / sum(implied, na.rm = TRUE)
        ) |>
        dplyr::ungroup()
      sm <- pl_softmax_by_race(p5_linear_v3$val_scores,
                               p5_arm_data$val$key$race_id,
                               p5_arm_data$val$key$runner_id)
      dplyr::bind_cols(base, dplyr::select(
        dplyr::rename(sm, win_model = p_win), win_model))
    }
  ),

  tar_target(
    p5_per_race_v3,
    {
      rer <- p5_scored_v3 |>
        dplyr::filter(race_id %in% p5_scorable) |>
        dplyr::mutate(placed = as.integer(!is.na(finish_pos) &
                                            finish_pos %in% 1:3)) |>
        dplyr::select(race_id, horse_ref, won, win_model, win_market,
                      finish_pos, placed)
      build_ranking_per_race(rer, "win_model")
    }
  ),

  # THE HEADLINE: identical features, function class the only difference.
  tar_target(
    p5_mlp_vs_linear,
    bootstrap_ranking_metrics(p5_per_race_v2$mlp, p5_per_race_v3,
                              "MLP - linear (identical 26 terms)")
  ),

  tar_target(
    p5_control_claim,
    {
      b <- p5_mlp_vs_linear |>
        dplyr::filter(metric %in% c("P1_rank", "Brier_place")) |>
        dplyr::mutate(
          excludes_zero = (ci_lo > 0 & ci_hi > 0) | (ci_lo < 0 & ci_hi < 0),
          favours = dplyr::case_when(
            !excludes_zero ~ "neither",
            metric == "P1_rank" & diff_point > 0 ~ "MLP",
            metric == "P1_rank" & diff_point < 0 ~ "linear",
            metric == "Brier_place" & diff_point < 0 ~ "MLP",
            TRUE ~ "linear"
          )
        )
      verdict <- if (all(b$favours == "neither")) {
        paste("control claim HOLDS - MLP and linear tie on identical",
              "features; a rung 3 gain can be attributed to sequence",
              "representation")
      } else if (any(b$favours == "MLP")) {
        paste("control claim does NOT hold - the nonlinearity is buying",
              "something; a rung 3 gain must be read against an",
              "already-improved baseline")
      } else {
        paste("linear favoured on identical features - unexpected;",
              "the MLP is underfitting and rung 2 should not proceed")
      }
      list(table = b, verdict = verdict)
    }
  ),

  # -- P5-1a: one diagnostic fit -------------------------------------------
  # A linear scorer in torch on paper 2b's OWN 17 terms, including the
  # `pos_lag*_zero` companion indicators paper 3 drops. Identical loss,
  # loop, slice, seed and hyperparameters to the linear anchor in the
  # remediation pass — the only thing that changes is which columns it sees.
  #
  # If this reaches mlogit's 5.8143 the machinery is sound and rung 1's gap
  # is the feature encoding. If it does not, the fault is in the torch
  # implementation and the objective gate missed it.
  #
  # Fits nothing else, changes no rung-1 arm, and re-runs no comparison.
  tar_target(
    p5_diag_linear,
    {
      terms <- p5_baseline$terms
      stopifnot(all(terms %in% names(p5_arm_data$fit$rows)))

      x_fit <- as.matrix(p5_arm_data$fit$rows[, terms, drop = FALSE])
      x_val <- as.matrix(p5_arm_data$val$rows[, terms, drop = FALSE])
      x_all <- rbind(x_fit, x_val)
      fit_rows <- seq_len(nrow(x_fit))
      st <- p5_standardise(x_all, fit_rows)

      # Same configuration as the remediation pass's linear anchor.
      config <- tibble::tibble(
        config = 1L, widths = list(integer(0)), width_label = "linear",
        lr = 1e-3, dropout = 0.1, batch_races = 64L, max_epochs = 200L,
        weight_decay = 1e-5
      )

      run <- p5_fit_mlp(
        st$x[fit_rows, , drop = FALSE], st$x[-fit_rows, , drop = FALSE],
        p5_arm_data$fit$group_sizes, p5_arm_data$val$group_sizes,
        config, seed = 42L, k = 3L
      )

      list(
        terms = terms, n_terms = length(terms),
        na_share = st$na_share[st$na_share > 0],
        best_val_pl_loss = run$best_val_loss,
        best_epoch = run$best_epoch,
        final_val_pl_loss = run$final_val_loss,
        trace = run$trace
      )
    }
  ),

  tar_target(
    p5_rung1_reading,
    {
      b <- p5_rung1_comparison |>
        dplyr::filter(metric %in% c("P1_rank", "Brier_place")) |>
        dplyr::mutate(
          excludes_zero = (ci_lo > 0 & ci_hi > 0) | (ci_lo < 0 & ci_hi < 0),
          # P1_rank: higher is better, so a positive difference favours the
          # MLP. Brier_place: lower is better, so a negative difference does.
          favours = dplyr::case_when(
            !excludes_zero ~ "neither",
            metric == "P1_rank" & diff_point > 0 ~ "MLP",
            metric == "P1_rank" & diff_point < 0 ~ "paper 2b",
            metric == "Brier_place" & diff_point < 0 ~ "MLP",
            TRUE ~ "paper 2b"
          )
        )
      reading <- if (all(b$favours == "neither")) {
        "tie - both CIs straddle zero, as expected; proceed to rung 2"
      } else if (any(b$favours == "paper 2b")) {
        "implementation fault - a CI favours paper 2b; one remediation pass, then stop"
      } else {
        "MLP favoured - proceed, and record that the control claim is weakened"
      }
      list(table = b, reading = reading)
    }
  ),

  # =======================================================================
  # P5-1d: the equal selection budget, and the close of rung 1.
  #
  # P5-1c's verdict rested on a comparison in which the MLP was selected
  # over 9 configurations x 60 epochs = 540 evaluations and the linear arm
  # over 1 x 200 = 200. The minimum of more noisy evaluations is lower for
  # that reason alone, so part of the 0.013 gap could be search rather than
  # function class.
  #
  # Both arms now get 9 configurations x 200 epochs, selected on best
  # validation PL loss at any epoch. The MLP grid is REFITTED rather than
  # reused: matching only the configuration count would leave the epoch
  # allowance asymmetric in the other direction.
  #
  # THE TEST SPLIT IS NOT SCORED. Rung 2 is not started.
  # =======================================================================

  tar_target(p5_configs_v4_mlp, p5_mlp_configs_equal_budget()),
  tar_target(p5_configs_v4_lin, p5_linear_configs_equal_budget()),

  tar_target(
    p5_budget_check,
    {
      stopifnot(
        nrow(p5_configs_v4_mlp) == 9L,
        nrow(p5_configs_v4_lin) == 9L,
        all(p5_configs_v4_mlp$max_epochs == 200L),
        all(p5_configs_v4_lin$max_epochs == 200L),
        # The MLP grid is the declared one, unchanged but for the epochs.
        identical(p5_configs_v4_mlp$width_label, p5_configs_v2$width_label),
        identical(p5_configs_v4_mlp$lr, p5_configs_v2$lr),
        all(p5_configs_v4_lin$width_label == "linear")
      )
      tibble::tibble(
        arm = c("MLP", "linear"),
        configs = 9L,
        epochs = 200L,
        evaluations = 1800L
      )
    }
  ),

  tar_target(
    p5_mlp_runs_v4,
    purrr::map(seq_len(nrow(p5_configs_v4_mlp)), function(i) {
      p5_fit_mlp(
        p5_control_data$fit, p5_control_data$val,
        p5_arm_data$fit$group_sizes, p5_arm_data$val$group_sizes,
        p5_configs_v4_mlp[i, ], seed = 42L, k = 3L
      )
    })
  ),

  tar_target(
    p5_linear_runs_v4,
    purrr::map(seq_len(nrow(p5_configs_v4_lin)), function(i) {
      p5_fit_mlp(
        p5_control_data$fit, p5_control_data$val,
        p5_arm_data$fit$group_sizes, p5_arm_data$val$group_sizes,
        p5_configs_v4_lin[i, ], seed = 42L, k = 3L
      )
    })
  ),

  tar_target(p5_mlp_scores_v4,
             p5_run_table(p5_mlp_runs_v4, p5_configs_v4_mlp$batch_races)),
  tar_target(p5_linear_scores_v4,
             p5_run_table(p5_linear_runs_v4, p5_configs_v4_lin$batch_races)),

  tar_target(
    p5_mlp_selected_v4,
    p5_mlp_runs_v4[[which.min(purrr::map_dbl(p5_mlp_runs_v4, "best_val_loss"))]]
  ),
  tar_target(
    p5_linear_selected_v4,
    p5_linear_runs_v4[[
      which.min(purrr::map_dbl(p5_linear_runs_v4, "best_val_loss"))]]
  ),

  tar_target(
    p5_scored_v4,
    {
      base <- p5_val_base(p5_arm_data$val$key, p5_qualifying_runners)
      list(
        mlp = p5_attach_scores(base, p5_mlp_selected_v4$val_scores,
                               p5_arm_data$val$key),
        lin = p5_attach_scores(base, p5_linear_selected_v4$val_scores,
                               p5_arm_data$val$key)
      )
    }
  ),

  tar_target(
    p5_per_race_v4,
    list(
      mlp = p5_per_race_metrics(p5_scored_v4$mlp, p5_scorable),
      lin = p5_per_race_metrics(p5_scored_v4$lin, p5_scorable)
    )
  ),

  # THE HEADLINE: identical 26 terms, identical budget, function class the
  # only difference.
  tar_target(
    p5_mlp_vs_linear_v4,
    bootstrap_ranking_metrics(
      p5_per_race_v4$mlp, p5_per_race_v4$lin,
      "MLP - linear (identical 26 terms, equal budget)")
  ),

  tar_target(
    p5_control_claim_v4,
    {
      b <- p5_mlp_vs_linear_v4 |>
        dplyr::filter(metric %in% c("P1_rank", "Brier_place")) |>
        dplyr::mutate(
          excludes_zero = (ci_lo > 0 & ci_hi > 0) | (ci_lo < 0 & ci_hi < 0),
          favours = dplyr::case_when(
            !excludes_zero ~ "neither",
            metric == "P1_rank" & diff_point > 0 ~ "MLP",
            metric == "P1_rank" & diff_point < 0 ~ "linear",
            metric == "Brier_place" & diff_point < 0 ~ "MLP",
            TRUE ~ "linear"
          )
        )
      verdict <- if (all(b$favours == "neither")) {
        paste("control claim HOLDS at an equal budget - MLP and linear tie",
              "on identical features")
      } else if (any(b$favours == "MLP")) {
        paste("control claim does NOT hold at an equal budget - the",
              "nonlinearity is buying something")
      } else {
        paste("linear favoured at an equal budget - the MLP is underfitting")
      }
      list(table = b, verdict = verdict)
    }
  ),

  # What the nonlinearity buys, on the one scale the arms are directly
  # comparable on. Paper 2b's refitted mlogit loss is carried alongside as
  # the series reference point; it is not refitted here.
  tar_target(
    p5_budget_decomposition,
    {
      p2b <- p5_pl_loss_value(p5_baseline_scores,
                              p5_arm_data$val$group_sizes, 3L)
      tibble::tibble(
        arm = c("paper 2b, mlogit", "linear in torch", "MLP"),
        terms = c(17L, 26L, 26L),
        budget = c("closed form", "9 x 200", "9 x 200"),
        val_pl_loss = c(p2b, p5_linear_selected_v4$best_val_loss,
                        p5_mlp_selected_v4$best_val_loss)
      ) |>
        dplyr::mutate(gain_vs_prev = dplyr::lag(val_pl_loss) - val_pl_loss)
    }
  ),

  # -- beaten_dist, the last flagged channel -------------------------------
  # Reported from the raw column, before cleaning, so the bound can be
  # judged against what it actually cuts.
  tar_target(
    p5_beaten_audit,
    {
      raw <- p5_full_history |>
        dplyr::filter(is.na(unfinished) | unfinished != "Non-Runner") |>
        dplyr::mutate(
          finish_pos = dplyr::coalesce(amended_position, finish_position),
          bd = dplyr::if_else(!is.na(finish_pos) & finish_pos == 1,
                              0, distance_behind_winner)
        )
      real <- raw |> dplyr::filter(!is.na(bd))
      qs <- stats::quantile(real$bd, c(0, .5, .75, .9, .95, .99, .999, 1))

      list(
        n_rows = nrow(raw),
        n_missing = sum(is.na(raw$bd)),
        pct_missing = round(100 * mean(is.na(raw$bd)), 4),
        quantiles = tibble::tibble(q = names(qs),
                                   lengths = round(unname(qs), 2)),
        thresholds = tibble::tibble(
          above = c(30, 50, 75, 100, 150, 200, 300),
          n = purrr::map_int(c(30, 50, 75, 100, 150, 200, 300),
                             ~ sum(real$bd > .x)),
          pct = purrr::map_dbl(c(30, 50, 75, 100, 150, 200, 300),
                               ~ round(100 * mean(real$bd > .x), 4))
        ),
        by_race_type = real |>
          dplyr::group_by(race_type) |>
          dplyr::summarise(
            n = dplyr::n(), median = stats::median(bd),
            p99 = stats::quantile(bd, .99), max = max(bd),
            n_over_100 = sum(bd > 100), .groups = "drop"
          ),
        tail_composition = real |>
          dplyr::filter(bd > P5_MAX_BEATEN) |>
          dplyr::count(race_type, sort = TRUE) |>
          dplyr::mutate(pct = round(100 * n / sum(n), 2)),
        tail_non_finishers = real |>
          dplyr::filter(bd > P5_MAX_BEATEN) |>
          dplyr::summarise(
            n = dplyr::n(),
            n_unfinished = sum(!is.na(unfinished)),
            pct_unfinished = round(100 * mean(!is.na(unfinished)), 2)
          ),
        bound = P5_MAX_BEATEN
      )
    }
  )
)
