# scripts/audit_smartform_2.R
#
# Two more read-only audits against the Smartform MySQL database, follow-ups
# to scripts/audit_smartform.R:
#   Audit C - weight identity: does weight_pounds - penalty_weight -
#             over_weight + jockey_claim - long_handicap reproduce
#             official_rating (both centred on the race minimum), the
#             mechanical relationship a handicap should have if
#             official_rating is the pre-race mark?
#   Audit D - how much career history exists (all race types, from 2003)
#             for each qualifying-universe runner-row, and how that compares
#             to prior QUALIFYING runs alone (the previous audit's B5).
#
# Standalone script, not a {targets} target. Read-only throughout: no writes
# to the database, and this script does not modify anything under R/, sql/,
# or _targets.R. Reuses the DB helpers (R/db.R) and qualifying-race
# extraction functions (R/extract_qualifying_races.R, R/extract_runners.R)
# so the universe matches _targets.R exactly, same as audit_smartform.R.
#
# Run from the project root:
#   & "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" scripts/audit_smartform_2.R
# Output is printed to console and written to
# scripts/audit_smartform_2_output.md.

source("renv/activate.R")

suppressPackageStartupMessages({
  library(DBI)
  library(dplyr)
  library(stringr)
  library(tibble)
  library(purrr)
})

source(here::here("R", "db.R"))
source(here::here("R", "extract_qualifying_races.R"))
source(here::here("R", "extract_runners.R"))

# ---- report accumulation -------------------------------------------------

out_lines <- character(0)

emit <- function(...) {
  txt <- paste0(...)
  cat(txt, "\n", sep = "")
  out_lines <<- c(out_lines, txt)
}

md_table <- function(df, max_rows = NULL) {
  df <- as.data.frame(df)
  if (!is.null(max_rows)) df <- utils::head(df, max_rows)
  df[] <- lapply(df, function(col) {
    if (is.numeric(col)) {
      format(round(col, 4), big.mark = ",", trim = TRUE, scientific = FALSE)
    } else {
      as.character(col)
    }
  })
  header <- paste0("| ", paste(names(df), collapse = " | "), " |")
  sep    <- paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|")
  rows   <- apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |"))
  paste(c(header, sep, rows), collapse = "\n")
}

pct <- function(x) round(100 * mean(x), 3)

quantile_table <- function(x, value_name, na.rm = FALSE) {
  qs <- stats::quantile(x, probs = c(0, .1, .25, .5, .75, .9, .99, 1), na.rm = na.rm, type = 7)
  tibble::tibble(quantile = c("min", "p10", "p25", "median", "p75", "p90", "p99", "max"),
                 value = as.numeric(qs)) |>
    dplyr::rename(!!value_name := value)
}

emit("# Smartform DB audit 2: weight identity & full-history sequence length")
emit("")
emit(paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")))
emit("")

# ---------------------------------------------------------------------------
# Connect and rebuild the qualifying universe exactly as _targets.R does
# ---------------------------------------------------------------------------

con <- connect_smartform()
on.exit(disconnect_smartform(con), add = TRUE)

b_date_from <- "2006-01-01"
b_date_to   <- "2015-10-14"
b_courses   <- c("Kempton", "Lingfield", "Southwell", "Wolverhampton")

b_candidate_races <- extract_qualifying_races(con, date_from = b_date_from, date_to = b_date_to, aw_courses = b_courses)
b_runners <- extract_runners_for_races(con, b_candidate_races$race_id)
b_races <- dplyr::filter(b_candidate_races, race_id %in% unique(b_runners$race_id))

emit("Universe: rebuilt via `R/extract_qualifying_races.R::extract_qualifying_races()` and ")
emit(paste0(
  "`R/extract_runners.R::extract_runners_for_races()` with the `_targets.R` parameters ",
  "(date_from = \"2006-01-01\", date_to = \"2015-10-14\", aw_courses = c(\"Kempton\", ",
  "\"Lingfield\", \"Southwell\", \"Wolverhampton\")), replicating candidate_races -> ",
  "qualifying_runners -> qualifying_races."
))
emit(sprintf("qualifying_races: %d races. qualifying_runners: %d runner-rows.", nrow(b_races), nrow(b_runners)))
emit("")

race_id_list <- paste(b_races$race_id, collapse = ",")

# ---------------------------------------------------------------------------
# Audit C: weight identity
# ---------------------------------------------------------------------------

emit("## Audit C: weight identity")
emit("")
emit(paste0(
  "Identity tested: `adj_weight = weight_pounds - penalty_weight - over_weight + ",
  "jockey_claim - long_handicap` (NULL treated as 0 on the four adjustment terms), ",
  "compared to `official_rating`, both centred on their race minimum among eligible ",
  "runners (non-null official_rating and weight_pounds)."
))
emit("")

c_query <- sprintf("
SELECT race_id, runner_id, unfinished, official_rating, weight_pounds,
       penalty_weight, over_weight, jockey_claim, long_handicap
FROM historic_runners
WHERE race_id IN (%s)
", race_id_list)

c_raw <- DBI::dbGetQuery(con, c_query) |> tibble::as_tibble() |>
  dplyr::filter(is.na(unfinished) | unfinished != "Non-Runner") |>
  dplyr::select(-unfinished)

c_data <- c_raw |>
  dplyr::inner_join(dplyr::select(b_runners, race_id, runner_id, won), by = c("race_id", "runner_id"))

emit(sprintf(
  "Rows after Non-Runner removal and joining to qualifying_runners' `won` flag: %d (vs qualifying_runners: %d).",
  nrow(c_data), nrow(b_runners)
))

c_elig <- c_data |> dplyr::filter(!is.na(official_rating), !is.na(weight_pounds))
emit(sprintf(
  "Rows with non-null official_rating AND weight_pounds: %d of %d (%.2f%%).",
  nrow(c_elig), nrow(c_data), 100 * nrow(c_elig) / nrow(c_data)
))
emit("")

compute_identity <- function(df, use_penalty = TRUE, use_over = TRUE, use_claim = TRUE, use_long = TRUE) {
  df |>
    dplyr::mutate(
      adj_weight = weight_pounds -
        (if (use_penalty) dplyr::coalesce(penalty_weight, 0) else 0) -
        (if (use_over)    dplyr::coalesce(over_weight, 0)    else 0) +
        (if (use_claim)   dplyr::coalesce(jockey_claim, 0)   else 0) -
        (if (use_long)    dplyr::coalesce(long_handicap, 0)  else 0)
    ) |>
    dplyr::group_by(race_id) |>
    dplyr::mutate(
      centred_adj = adj_weight - min(adj_weight),
      centred_or  = official_rating - min(official_rating),
      discrepancy = centred_adj - centred_or,
      match       = discrepancy == 0
    ) |>
    dplyr::ungroup()
}

bucket_order <- c("< -5", as.character(-5:5), "> 5")
disc_bucket_table <- function(df) {
  df |>
    dplyr::mutate(bucket = dplyr::case_when(
      discrepancy < -5 ~ "< -5",
      discrepancy > 5  ~ "> 5",
      TRUE ~ as.character(discrepancy)
    )) |>
    dplyr::count(bucket, name = "n") |>
    dplyr::mutate(pct = round(100 * n / sum(n), 3), bucket = factor(bucket, levels = bucket_order)) |>
    dplyr::arrange(bucket)
}

c_full <- compute_identity(c_elig)

emit("### (a) Row-level exact match")
emit("")
emit(sprintf("%d of %d rows match exactly (%.3f%%).", sum(c_full$match), nrow(c_full), pct(c_full$match)))
emit("")

emit("### (b) Discrepancy in pounds")
emit("")
emit(md_table(quantile_table(c_full$discrepancy, "discrepancy")))
emit("")
emit(md_table(disc_bucket_table(c_full)))
emit("")

race_level <- c_full |>
  dplyr::group_by(race_id) |>
  dplyr::summarise(n_elig = dplyr::n(), all_match = all(match), .groups = "drop")

emit("### (c) Races where every eligible runner matches exactly")
emit("")
emit(sprintf(
  "%d of %d races (%.3f%%).", sum(race_level$all_match), nrow(race_level), pct(race_level$all_match)
))
multi <- dplyr::filter(race_level, n_elig > 1)
n_single <- sum(race_level$n_elig == 1)
emit(sprintf(
  "%d of those races have only one eligible runner, which trivially matches (min of one value equals itself); restricting to races with >=2 eligible runners: %d of %d match exactly (%.3f%%).",
  n_single, sum(multi$all_match), nrow(multi), pct(multi$all_match)
))
emit("")

emit("### (d) Effect of omitting each adjustment term")
emit("")
variant_flags <- list(
  full             = c(TRUE, TRUE, TRUE, TRUE),
  no_penalty       = c(FALSE, TRUE, TRUE, TRUE),
  no_over_weight   = c(TRUE, FALSE, TRUE, TRUE),
  no_jockey_claim  = c(TRUE, TRUE, FALSE, TRUE),
  no_long_handicap = c(TRUE, TRUE, TRUE, FALSE)
)
d_rows <- purrr::imap_dfr(variant_flags, function(flags, nm) {
  d <- compute_identity(c_elig, flags[1], flags[2], flags[3], flags[4])
  race_lvl <- d |> dplyr::group_by(race_id) |> dplyr::summarise(all_match = all(match), .groups = "drop")
  tibble::tibble(
    variant = nm,
    row_exact_pct = pct(d$match),
    median_abs_discrepancy = stats::median(abs(d$discrepancy)),
    race_all_exact_pct = pct(race_lvl$all_match)
  )
})
emit(md_table(d_rows))
emit("")

emit("### (a)-(c) split by winner status (full identity)")
emit("")
for (grp in c(1L, 0L)) {
  sub <- dplyr::filter(c_full, won == grp)
  label <- if (grp == 1) "Winners (won == 1)" else "Non-winners (won == 0)"
  emit(sprintf("**%s** — %d rows", label, nrow(sub)))
  emit("")
  emit(sprintf("(a) Row-level exact match: %.3f%%", pct(sub$match)))
  emit("")
  emit(md_table(quantile_table(sub$discrepancy, "discrepancy")))
  emit("")
  emit(md_table(disc_bucket_table(sub)))
  emit("")
}

race_c_winner <- c_full |> dplyr::filter(won == 1) |> dplyr::group_by(race_id) |>
  dplyr::summarise(winner_matches = all(match), .groups = "drop")
race_c_nonwinner <- c_full |> dplyr::filter(won == 0) |> dplyr::group_by(race_id) |>
  dplyr::summarise(all_nonwinners_match = all(match), .groups = "drop")

emit(paste0(
  "(c) split by winner status: since (c) is a race-level statistic, split here as \"does the ",
  "winner's own row match exactly\" vs \"does every non-winning runner's row match exactly\", ",
  "each restricted to races where that group has at least one eligible row."
))
emit("")
emit(sprintf(
  "Races with an eligible winner row: %d, of which the winner's row matches exactly: %.3f%%.",
  nrow(race_c_winner), pct(race_c_winner$winner_matches)
))
emit(sprintf(
  "Races with >=1 eligible non-winner row: %d, of which every non-winner row matches exactly: %.3f%%.",
  nrow(race_c_nonwinner), pct(race_c_nonwinner$all_nonwinners_match)
))
emit("")

# ---------------------------------------------------------------------------
# Audit D: sequence length on full history
# ---------------------------------------------------------------------------

emit("## Audit D: sequence length on full history")
emit("")
emit(paste0(
  "Horse identity: `runner_id`, not `name`. This is the field the pipeline already keys on -- ",
  "`R/extract_runners.R::extract_career_history()` fetches full career history by `runner_id`, ",
  "and `get_aw_runner_ids()` derives the horse population as `unique(qualifying_runners$runner_id)`. ",
  "`historic_runners` has no separate horse_id column; `runner_id` is the persistent per-horse ",
  "identifier reused across every race row for that horse (already evident in audit_smartform.R's ",
  "Audit A, where individual runner_ids carry dozens of race rows spanning years)."
))
emit("")

name_collisions <- DBI::dbGetQuery(con, "
SELECT name, COUNT(DISTINCT runner_id) AS n_runner_ids
FROM historic_runners
GROUP BY name
HAVING COUNT(DISTINCT runner_id) > 1
") |> tibble::as_tibble()

total_names <- as.numeric(DBI::dbGetQuery(con, "SELECT COUNT(DISTINCT name) AS n FROM historic_runners")$n[1])

renamed_horses <- DBI::dbGetQuery(con, "
SELECT runner_id, COUNT(DISTINCT name) AS n_names
FROM historic_runners
GROUP BY runner_id
HAVING COUNT(DISTINCT name) > 1
") |> tibble::as_tibble()

emit(sprintf(
  "Name collisions (full historic_runners table, not just this universe): %d of %d distinct names are shared by more than one runner_id (%.3f%%) -- name alone is not a safe join key. %d distinct runner_ids are recorded under more than one name over their career (renames/retagging). `runner_id` avoids both problems.",
  nrow(name_collisions), total_names, 100 * nrow(name_collisions) / total_names, nrow(renamed_horses)
))
emit("")
if (nrow(name_collisions) > 0) {
  emit("Sample of colliding names, by number of runner_ids sharing the name (top 10):")
  emit("")
  emit(md_table(dplyr::arrange(name_collisions, dplyr::desc(n_runner_ids)), max_rows = 10))
  emit("")
}

runner_ids <- unique(b_runners$runner_id)
full_hist <- extract_career_history(con, runner_ids)
full_hist_2003 <- dplyr::filter(full_hist, meeting_date >= as.Date("2003-01-01"))

emit(sprintf(
  "Full cross-surface history (>=2003-01-01, all race types/courses) pulled for %d horses: %d rows.",
  length(runner_ids), nrow(full_hist_2003)
))
emit("")

b_runners_dates <- b_runners |>
  dplyr::inner_join(dplyr::select(b_races, race_id, meeting_date), by = "race_id") |>
  dplyr::select(race_id, runner_id, meeting_date) |>
  dplyr::arrange(runner_id, meeting_date)

hist_dates_by_horse <- split(full_hist_2003$meeting_date, full_hist_2003$runner_id)
hist_dates_by_horse <- lapply(hist_dates_by_horse, sort)

prior_full_runs <- purrr::map2_int(
  b_runners_dates$runner_id, b_runners_dates$meeting_date,
  function(rid, dt) {
    dates <- hist_dates_by_horse[[as.character(rid)]]
    if (is.null(dates)) return(0L)
    sum(dates < dt)
  }
)

b_runners_dates <- b_runners_dates |>
  dplyr::mutate(prior_full_runs = prior_full_runs) |>
  dplyr::group_by(runner_id) |>
  dplyr::mutate(prior_qualifying_runs = dplyr::row_number() - 1L) |>
  dplyr::ungroup()

bucket_order2 <- c("0", "1-2", "3-5", "6-10", "11-20", "21+")
bucket_prior <- function(x) {
  dplyr::case_when(
    x == 0 ~ "0", x <= 2 ~ "1-2", x <= 5 ~ "3-5",
    x <= 10 ~ "6-10", x <= 20 ~ "11-20", TRUE ~ "21+"
  )
}
bucket_table <- function(df) {
  df |>
    dplyr::mutate(bucket = factor(bucket_prior(prior_full_runs), levels = bucket_order2)) |>
    dplyr::count(bucket, .drop = FALSE, name = "n") |>
    dplyr::mutate(pct = round(100 * n / sum(n), 3))
}

emit("### Prior full-history runs (>=2003, strictly before meeting_date, all race types/courses)")
emit("")
emit(md_table(quantile_table(b_runners_dates$prior_full_runs, "prior_full_runs")))
emit("")
emit(md_table(bucket_table(b_runners_dates)))
emit("")

emit("### Same breakdown, split by whether the horse has any prior QUALIFYING run")
emit("")
for (has_prior in c(FALSE, TRUE)) {
  sub <- dplyr::filter(b_runners_dates, (prior_qualifying_runs > 0) == has_prior)
  label <- if (has_prior) "Has >=1 prior qualifying run" else "Zero prior qualifying runs"
  emit(sprintf("**%s** — %d rows (%.3f%% of universe)", label, nrow(sub), 100 * nrow(sub) / nrow(b_runners_dates)))
  emit("")
  emit(md_table(quantile_table(sub$prior_full_runs, "prior_full_runs")))
  emit("")
  emit(md_table(bucket_table(sub)))
  emit("")
}

emit("### Distribution of days_since_ran (qualifying universe)")
emit("")
dsr <- b_runners$days_since_ran
emit(sprintf("Non-null days_since_ran: %d of %d (%.2f%%).", sum(!is.na(dsr)), length(dsr), 100 * mean(!is.na(dsr))))
emit("")
emit(md_table(quantile_table(dsr, "days_since_ran", na.rm = TRUE)))
emit("")

emit("### Race-type composition of prior runs")
emit("")
emit(paste0(
  "Operational definition: for each horse, take its full-history rows (>=2003) with meeting_date ",
  "strictly before that horse's LAST qualifying appearance in this universe -- i.e. every historical ",
  "run that counts as \"prior\" to at least one of its qualifying rows, counted once each (not once ",
  "per qualifying row it precedes)."
))
emit("")

max_qual_date_by_horse <- b_runners_dates |>
  dplyr::group_by(runner_id) |>
  dplyr::summarise(max_qual_date = max(meeting_date), .groups = "drop")

prior_pool <- full_hist_2003 |>
  dplyr::inner_join(max_qual_date_by_horse, by = "runner_id") |>
  dplyr::filter(meeting_date < max_qual_date)

emit(sprintf("Prior-run pool size: %d rows.", nrow(prior_pool)))
emit("")

race_types_full <- DBI::dbGetQuery(con, "SELECT DISTINCT race_type FROM historic_races") |> tibble::as_tibble()
emit(paste0("Distinct race_type values on historic_races: ", paste(sort(race_types_full$race_type), collapse = ", ")))
emit("")

prior_pool <- prior_pool |>
  dplyr::mutate(race_type_bucket = dplyr::case_when(
    race_type == "Flat" ~ "Flat",
    race_type == "All Weather Flat" ~ "AW Flat",
    grepl("Hurdle", race_type, ignore.case = TRUE) ~ "Hurdle",
    grepl("Chase", race_type, ignore.case = TRUE) ~ "Chase",
    TRUE ~ "Other"
  ))
rt_tab <- prior_pool |>
  dplyr::count(race_type_bucket, sort = TRUE, name = "n") |>
  dplyr::mutate(pct = round(100 * n / sum(n), 3))
emit(md_table(rt_tab))
emit("")
if (any(prior_pool$race_type_bucket == "Other")) {
  other_detail <- prior_pool |>
    dplyr::filter(race_type_bucket == "Other") |>
    dplyr::count(race_type, sort = TRUE, name = "n")
  emit("Breakdown of \"Other\":")
  emit("")
  emit(md_table(other_detail))
  emit("")
}

# ---------------------------------------------------------------------------
# Write report
# ---------------------------------------------------------------------------

writeLines(out_lines, "scripts/audit_smartform_2_output.md")
cat("\nWrote scripts/audit_smartform_2_output.md\n")
