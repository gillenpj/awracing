# scripts/audit_smartform.R
#
# Two read-only exploratory audits against the Smartform MySQL database,
# ahead of paper 4 scoping:
#   Audit A - is `historic_runners.official_rating` the mark a horse
#             carries INTO a race, or one assigned AFTER it (leakage
#             risk for papers 1-3)?
#   Audit B - population and comment vocabulary of columns paper 4 might
#             draw features from, restricted to the existing qualifying
#             modelling universe.
#
# Standalone script, not a {targets} target. Read-only throughout: no
# writes to the database, and this script does not modify anything
# under R/, sql/, or _targets.R. It sources the existing DB helpers
# (R/db.R) and qualifying-race extraction functions (R/extract_qualifying_races.R,
# R/extract_runners.R) so Audit B's universe is built by the same code
# the pipeline itself uses, not re-derived.
#
# Run from the project root:
#   & "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" scripts/audit_smartform.R
# Output is printed to console and written to
# scripts/audit_smartform_output.md.

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

grep_project <- function(pattern, dirs = c("sql", "R")) {
  files <- unlist(lapply(dirs, function(d) list.files(d, full.names = TRUE, recursive = TRUE)))
  files <- files[grepl("\\.(R|sql)$", files)]
  purrr::map_dfr(files, function(f) {
    lines <- readLines(f, warn = FALSE)
    hits <- grep(pattern, lines)
    if (length(hits) == 0) return(NULL)
    tibble::tibble(file = f, line = hits, text = trimws(lines[hits]))
  })
}

col_population <- function(x, table, column) {
  n <- length(x)
  if (is.character(x)) {
    n_pop <- sum(!is.na(x) & trimws(x) != "")
  } else {
    n_pop <- sum(!is.na(x))
  }
  tibble::tibble(
    table = table, column = column, n = n, n_populated = n_pop,
    pct_populated = round(100 * n_pop / n, 2)
  )
}

emit("# Smartform DB audit: official_rating timing & column population")
emit("")
emit(paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")))
emit("")

# ---------------------------------------------------------------------------
# Section 0: current sourcing of official_rating in the pipeline
# ---------------------------------------------------------------------------

emit("## 0. Current sourcing of `official_rating` in the pipeline")
emit("")
emit("Grep of `sql/` and `R/` for `official_rating`:")
emit("")
emit("```")
or_hits <- grep_project("official_rating")
for (i in seq_len(nrow(or_hits))) {
  emit(sprintf("%s:%d: %s", or_hits$file[i], or_hits$line[i], or_hits$text[i]))
}
emit("```")
emit("")
emit(paste0(
  "`official_rating` is selected as-is from `historic_runners` in two ",
  "places: `sql/runners_for_races.sql` (the runner's own rating for its ",
  "qualifying race) and `sql/horse_full_history.sql` (career history rows, ",
  "same column). `R/build_extended_features.R::build_within_race_features()` ",
  "computes `or_relative` as this runner's `official_rating` for the current ",
  "race minus the race-mean `official_rating` over the field — i.e. the ",
  "pipeline treats the value on a runner's own qualifying-race row as the ",
  "rating that horse carried INTO that race. No lag or as-of adjustment is ",
  "applied anywhere in `R/` or `sql/`. Audit A below tests whether that ",
  "assumption holds."
))
emit("")

# ---------------------------------------------------------------------------
# Connect
# ---------------------------------------------------------------------------

con <- connect_smartform()
on.exit(disconnect_smartform(con), add = TRUE)

schema_cols <- function(con, table) {
  # information_schema.columns comes back with uppercase COLUMN_NAME /
  # DATA_TYPE regardless of query casing on this MariaDB server; DESCRIBE
  # is more predictable (Field / Type) and renamed here for downstream use.
  DBI::dbGetQuery(con, sprintf("DESCRIBE %s", table)) |>
    tibble::as_tibble() |>
    dplyr::transmute(column_name = Field, data_type = Type)
}

runners_schema <- schema_cols(con, "historic_runners")
races_schema   <- schema_cols(con, "historic_races")
tack_cols      <- runners_schema$column_name[grepl("^tack_", runners_schema$column_name, ignore.case = TRUE)]

# ---------------------------------------------------------------------------
# Audit A: official_rating timing
# ---------------------------------------------------------------------------

emit("## Audit A: official_rating timing")
emit("")

date_from_a <- "2006-01-01"
date_to_a   <- "2015-12-31"

race_types <- DBI::dbGetQuery(con, "SELECT DISTINCT race_type FROM historic_races") |> tibble::as_tibble()
flat_like  <- race_types$race_type[grepl("flat", race_types$race_type, ignore.case = TRUE)]
flat_types <- intersect(race_types$race_type, c("Flat", "All Weather Flat"))

emit(paste0(
  "Distinct `historic_races.race_type` values matching /flat/i: ",
  paste(flat_like, collapse = ", "), ". Used for this audit: ",
  paste(flat_types, collapse = ", "),
  " (others containing \"Flat\", e.g. National Hunt Flat / bumpers, are a ",
  "different racing code and excluded)."
))
emit(paste0("Date window: ", date_from_a, " to ", date_to_a, "."))
emit("")

rt_list <- DBI::SQL(paste(DBI::dbQuoteString(con, flat_types), collapse = ", "))

candidates_sql <- sprintf("
SELECT rn.runner_id,
       MIN(rn.name) AS name,
       COUNT(*) AS n_runs,
       SUM(CASE WHEN COALESCE(rn.amended_position, rn.finish_position) = 1 THEN 1 ELSE 0 END) AS n_wins,
       MIN(r.meeting_date) AS first_date,
       MAX(r.meeting_date) AS last_date
FROM historic_runners rn
INNER JOIN historic_races r ON r.race_id = rn.race_id
WHERE r.race_type IN (%s)
  AND r.meeting_date BETWEEN '%s' AND '%s'
GROUP BY rn.runner_id
HAVING COUNT(*) >= 6 AND n_wins >= 1
", rt_list, date_from_a, date_to_a)

candidates <- DBI::dbGetQuery(con, candidates_sql) |> tibble::as_tibble() |> dplyr::arrange(first_date)

emit(paste0(
  "Candidate pool (>=6 runs, >=1 win, in window): ", nrow(candidates), " horses. ",
  "Selecting 20 spread evenly across the pool ordered by first run date."
))
emit("")

n_cand <- nrow(candidates)
idx <- unique(round(seq(1, n_cand, length.out = min(20, n_cand))))
selected <- candidates[idx, ]

runs_sql <- sprintf("
SELECT rn.runner_id, r.meeting_date, r.course, r.class,
       rn.finish_position, rn.amended_position, rn.official_rating,
       rn.weight_pounds, rn.starting_price_decimal
FROM historic_runners rn
INNER JOIN historic_races r ON r.race_id = rn.race_id
WHERE rn.runner_id IN (%s)
  AND r.race_type IN (%s)
  AND r.meeting_date BETWEEN '%s' AND '%s'
ORDER BY rn.runner_id, r.meeting_date
", paste(selected$runner_id, collapse = ","), rt_list, date_from_a, date_to_a)

all_runs <- DBI::dbGetQuery(con, runs_sql) |> tibble::as_tibble()

classify_horse <- function(runs) {
  runs <- dplyr::arrange(runs, meeting_date)
  runs$is_win <- as.integer(dplyr::coalesce(runs$amended_position, runs$finish_position) == 1)
  n <- nrow(runs)
  win_positions <- which(runs$is_win == 1)
  purrr::map_dfr(win_positions, function(i) {
    prior <- if (i > 1) runs$official_rating[i - 1] else NA_real_
    win   <- runs$official_rating[i]
    nxt   <- if (i < n) runs$official_rating[i + 1] else NA_real_
    verdict <- dplyr::case_when(
      is.na(win)                                              ~ "ambiguous (win row OR missing)",
      is.na(prior)                                             ~ "ambiguous (no prior run in pool)",
      win > prior                                              ~ "post-race (rose on win row)",
      win == prior & !is.na(nxt) & nxt > win                   ~ "pre-race (rose only on next run)",
      win == prior & (is.na(nxt) | nxt <= win)                 ~ "ambiguous (no rise observed)",
      win < prior                                              ~ "ambiguous (rating fell)",
      TRUE                                                     ~ "ambiguous (other)"
    )
    tibble::tibble(win_date = runs$meeting_date[i], prior_or = prior, win_or = win, next_or = nxt, verdict = verdict)
  })
}

horse_verdict <- function(instances) {
  if (nrow(instances) == 0) return("ambiguous (no classifiable win)")
  clean <- instances$verdict[!grepl("^ambiguous", instances$verdict)]
  if (length(clean) == 0) return("ambiguous (insufficient data)")
  u <- unique(clean)
  if (length(u) == 1) return(u) else return("mixed (both patterns observed)")
}

horse_summaries <- tibble::tibble()
all_instances <- tibble::tibble()

for (rid in selected$runner_id) {
  runs <- dplyr::filter(all_runs, runner_id == rid) |> dplyr::arrange(meeting_date)
  runs$win_flag <- ifelse(
    dplyr::coalesce(runs$amended_position, runs$finish_position) == 1, "WIN", ""
  )
  display <- runs |>
    dplyr::transmute(
      meeting_date, course, class, finish_position, official_rating,
      weight_pounds, starting_price_decimal, note = win_flag
    )

  name <- candidates$name[candidates$runner_id == rid]
  emit(sprintf("### Horse runner_id=%d (%s) — %d runs, %d wins in pool",
               rid, name, nrow(runs), sum(runs$win_flag == "WIN")))
  emit("")
  emit(md_table(display))
  emit("")

  instances <- classify_horse(runs)
  if (nrow(instances) > 0) {
    emit("Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):")
    emit("")
    emit(md_table(instances))
    emit("")
  }
  v <- horse_verdict(instances)
  emit(paste0("**Horse verdict: ", v, "**"))
  emit("")

  horse_summaries <- dplyr::bind_rows(
    horse_summaries,
    tibble::tibble(runner_id = rid, name = name, n_runs = nrow(runs),
                    n_win_instances = nrow(instances), verdict = v)
  )
  if (nrow(instances) > 0) {
    all_instances <- dplyr::bind_rows(all_instances, dplyr::mutate(instances, runner_id = rid, .before = 1))
  }
}

emit("### Audit A summary")
emit("")
emit(md_table(horse_summaries))
emit("")
verdict_counts <- dplyr::count(horse_summaries, verdict, sort = TRUE)
emit(md_table(verdict_counts))
emit("")
ambiguous <- dplyr::filter(horse_summaries, grepl("^ambiguous|^mixed", verdict))
if (nrow(ambiguous) > 0) {
  emit(paste0("Ambiguous/mixed horses: ", paste(ambiguous$runner_id, collapse = ", ")))
} else {
  emit("No ambiguous or mixed horses.")
}
emit("")

emit("Instance-level counts (every classifiable win, not deduplicated to one verdict per horse):")
emit("")
instance_counts <- dplyr::count(all_instances, verdict, sort = TRUE)
emit(md_table(instance_counts))
emit("")

n_clean_post <- sum(grepl("^post-race", all_instances$verdict))
n_clean_pre  <- sum(grepl("^pre-race", all_instances$verdict))
n_fell       <- sum(grepl("rating fell", all_instances$verdict))
emit(paste0(
  "At the horse level the classifier does not resolve to a single clean pattern: ",
  sum(horse_summaries$verdict == "post-race (rose on win row)"), " horses read cleanly post-race, ",
  sum(horse_summaries$verdict == "pre-race (rose only on next run)"), " read cleanly pre-race, ",
  sum(grepl("^mixed", horse_summaries$verdict)), " show both patterns on different wins, and ",
  sum(grepl("^ambiguous", horse_summaries$verdict)), " are ambiguous (no prior run in pool, missing rating, or no ",
  "change either way). At the win-instance level: ", n_clean_post, " instances rose on the win row itself, ",
  n_clean_pre, " rose only on the following run, and ", n_fell, " instances show the rating falling on or after ",
  "a win — which a simple \"post-race credit\" story does not predict at all."
))
emit("")
emit(paste0(
  "Structural point independent of the above: these are handicap races, and `historic_races`/`historic_runners` ",
  "carry `weight_pounds` alongside `official_rating` on the same runner row, with weight in a handicap being a ",
  "function of the rating assigned before the race (that is what \"handicap\" means — the weight is how the ",
  "rating is applied to the race). A rating recorded as a post-race assessment would have no mechanical link to ",
  "the weight shown on the same row for the same run. This favours reading the value as the mark carried INTO ",
  "the race, with the rise/fall/no-change pattern around wins reflecting the BHA's own review cadence (ratings ",
  "are revised periodically, not race-by-race) rather than this table recording pre- vs post-race values ",
  "inconsistently. This is inference from schema structure, not a query result, and does not override the ",
  "empirical counts above."
))
emit("")

# ---------------------------------------------------------------------------
# Audit B: column population and comment vocabulary
# ---------------------------------------------------------------------------

emit("## Audit B: column population and comment vocabulary")
emit("")
emit(paste0(
  "Universe: existing qualifying modelling universe as built by ",
  "`R/extract_qualifying_races.R::extract_qualifying_races()` (races, per ",
  "`sql/qualifying_races.sql`) and `R/extract_runners.R::extract_runners_for_races()` ",
  "(runners, R-level Non-Runner / field-size / one-winner filters), called ",
  "with the same parameters as `_targets.R` (`date_from = \"2006-01-01\"`, ",
  "`date_to = \"2015-10-14\"`, `aw_courses = c(\"Kempton\", \"Lingfield\", ",
  "\"Southwell\", \"Wolverhampton\")`), replicating the `candidate_races` -> ",
  "`qualifying_runners` -> `qualifying_races` chain exactly."
))
emit("")

b_date_from <- "2006-01-01"
b_date_to   <- "2015-10-14"
b_courses   <- c("Kempton", "Lingfield", "Southwell", "Wolverhampton")

b_candidate_races <- extract_qualifying_races(con, date_from = b_date_from, date_to = b_date_to, aw_courses = b_courses)
b_runners <- extract_runners_for_races(con, b_candidate_races$race_id)
b_races <- dplyr::filter(b_candidate_races, race_id %in% unique(b_runners$race_id))

emit(sprintf(
  "candidate_races: %d races. qualifying_runners: %d runner-rows. qualifying_races (post R-level filters): %d races.",
  nrow(b_candidate_races), nrow(b_runners), nrow(b_races)
))
emit("")

race_id_list <- paste(b_races$race_id, collapse = ",")

expected_runner_cols <- c("in_race_comment", "days_since_ran", "long_handicap",
                           "last_race_beaten_fav", "speed_rating",
                           "distance_travelled", "distance_behind_winner")
missing_runner_cols  <- setdiff(expected_runner_cols, runners_schema$column_name)
present_runner_cols  <- intersect(expected_runner_cols, runners_schema$column_name)

expected_race_cols <- c("winning_time_secs", "standard_time_secs")
missing_race_cols  <- setdiff(expected_race_cols, races_schema$column_name)
present_race_cols  <- intersect(expected_race_cols, races_schema$column_name)

emit(paste0("Discovered `tack_*` columns on `historic_runners` (", length(tack_cols), "): ", paste(tack_cols, collapse = ", ")))
if (length(missing_runner_cols) > 0) {
  emit(paste0("Expected runner-level columns NOT found on `historic_runners`: ", paste(missing_runner_cols, collapse = ", ")))
}
if (length(missing_race_cols) > 0) {
  emit(paste0("Expected race-level columns NOT found on `historic_races`: ", paste(missing_race_cols, collapse = ", ")))
}
emit("")

runner_select_cols <- unique(c("race_id", "runner_id", "unfinished", present_runner_cols, tack_cols))
b1_query <- sprintf(
  "SELECT %s FROM historic_runners WHERE race_id IN (%s)",
  paste(runner_select_cols, collapse = ", "), race_id_list
)
b_runners_full <- DBI::dbGetQuery(con, b1_query) |> tibble::as_tibble() |>
  dplyr::filter(is.na(unfinished) | unfinished != "Non-Runner")

emit(sprintf(
  "Sanity check: row count from direct query matching qualifying_runners' Non-Runner filter = %d (vs qualifying_runners = %d).",
  nrow(b_runners_full), nrow(b_runners)
))
emit("")

b_races_full <- DBI::dbGetQuery(con, sprintf(
  "SELECT race_id, %s FROM historic_races WHERE race_id IN (%s)",
  paste(present_race_cols, collapse = ", "), race_id_list
)) |> tibble::as_tibble()

emit("### B1. Column population")
emit("")
b1_runner_pop <- purrr::map_dfr(c(present_runner_cols, tack_cols), function(cn) {
  col_population(b_runners_full[[cn]], "historic_runners", cn)
})
b1_race_pop <- purrr::map_dfr(present_race_cols, function(cn) {
  col_population(b_races_full[[cn]], "historic_races", cn)
})
b1 <- dplyr::bind_rows(b1_runner_pop, b1_race_pop)
emit(md_table(b1))
emit("")

emit("### B2. 50 randomly sampled non-empty in_race_comment values (seed 42)")
emit("")
comments <- b_runners_full$in_race_comment
comments_nonempty <- comments[!is.na(comments) & trimws(comments) != ""]
set.seed(42)
sample_comments <- sample(comments_nonempty, min(50, length(comments_nonempty)))
for (i in seq_along(sample_comments)) {
  emit(sprintf("%d. %s", i, sample_comments[i]))
}
emit("")

emit("### B3. First-three-words frequency (top 60, raw case, no normalisation)")
emit("")
first3 <- function(x) {
  words <- stringr::str_split(stringr::str_squish(x), " ")
  purrr::map_chr(words, ~ paste(utils::head(.x, 3), collapse = " "))
}
f3 <- first3(comments_nonempty)
freq3 <- tibble::tibble(first3 = f3) |>
  dplyr::count(first3, sort = TRUE, name = "count") |>
  dplyr::mutate(
    pct = round(100 * count / length(comments_nonempty), 3),
    cum_pct = round(cumsum(pct), 3)
  )
emit(md_table(freq3, max_rows = 60))
emit("")

emit("### B4. Riding-style pattern counts (case-insensitive substring match)")
emit("")
emit(paste0(
  "Caveat: these are raw substring matches, not word-boundaried, so some ",
  "counts include false positives — e.g. \"led\" also matches inside ",
  "\"travelled\"/\"settled\". Reported as an upper bound on true occurrence ",
  "of the term, per the literal pattern list requested."
))
emit("")
patterns <- c("made all", "led", "prominent", "chased leaders", "mid-division",
              "held up", "in rear", "headway", "hampered", "short of room",
              "not clear run", "switched", "every chance", "stayed on",
              "weakened", "no extra")
b4 <- purrr::map_dfr(patterns, function(p) {
  cnt <- sum(stringr::str_detect(comments_nonempty, stringr::regex(p, ignore_case = TRUE)))
  tibble::tibble(pattern = p, count = cnt, pct_of_nonempty = round(100 * cnt / length(comments_nonempty), 3))
})
emit(md_table(b4))
emit("")

emit("### B5. Runs-per-horse (prior qualifying runs) distribution")
emit("")
b_runners_dates <- b_runners |>
  dplyr::inner_join(dplyr::select(b_races, race_id, meeting_date), by = "race_id") |>
  dplyr::select(runner_id, race_id, meeting_date)

prior_counts <- b_runners_dates |>
  dplyr::arrange(runner_id, meeting_date) |>
  dplyr::group_by(runner_id) |>
  dplyr::mutate(prior_runs = dplyr::row_number() - 1L) |>
  dplyr::ungroup()

qs <- stats::quantile(prior_counts$prior_runs, probs = c(0, .1, .25, .5, .75, .9, 1), type = 7)
pct_zero <- round(100 * mean(prior_counts$prior_runs == 0), 3)

qtab <- tibble::tibble(
  quantile = c("min", "p10", "p25", "median", "p75", "p90", "max"),
  prior_runs = as.numeric(qs)
)
emit(md_table(qtab))
emit("")
emit(sprintf(
  "Runner-rows with zero prior qualifying runs: %d of %d (%s%%).",
  sum(prior_counts$prior_runs == 0), nrow(prior_counts), pct_zero
))
emit("")

# ---------------------------------------------------------------------------
# Appendix: schema listings
# ---------------------------------------------------------------------------

emit("## Appendix: schema")
emit("")
emit("### historic_runners")
emit("")
emit(md_table(runners_schema))
emit("")
emit("### historic_races")
emit("")
emit(md_table(races_schema))
emit("")

# ---------------------------------------------------------------------------
# Write report
# ---------------------------------------------------------------------------

writeLines(out_lines, "scripts/audit_smartform_output.md")
cat("\nWrote scripts/audit_smartform_output.md\n")
