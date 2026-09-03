# p4_audit_forecast_price.R
#
# Paper 4, stage P4-0 — HARD GATE audit of `forecast_price_decimal`.
#
# Read-only. Hits the Smartform DB and reads (never writes) the main
# `_targets` store. Writes a markdown report to
# `scripts/p4_audit_forecast_price_output.md` and a machine-readable
# handoff to `scripts/p4_audit_forecast_price.rds`.
#
# Run:  "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" scripts/p4_audit_forecast_price.R
#
# Five items, per the P4-0 spec:
#   1. Schema location / type / timing semantics of the column.
#   2. Coverage — runner-rows, races, the 2,183-race ranking test
#      universe, and by year.
#   3. Overround — sum(1 / forecast_price_decimal) per race, vs SP.
#   4. Shape vs SP — within-race regression of log p_forecast on
#      log p_SP after proportional overround normalisation.
#   5. Non-runner behaviour — declared field or final field?
#
# Distributional work (items 3 and 4) is TRAINING SPLIT ONLY, per the
# project's standing rule. Coverage (item 2) is reported on both splits
# because the abort conditions are stated against the test universe.

source("renv/activate.R")
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(stringr)
  library(readr)
})
source("R/db.R")

OUT <- "scripts/p4_audit_forecast_price_output.md"
out_con <- file(OUT, open = "wt", encoding = "UTF-8")
emit <- function(...) cat(..., "\n", sep = "", file = out_con)
emit_tbl <- function(df, digits = 4) {
  df <- as.data.frame(df)
  df[] <- lapply(df, function(x) {
    if (is.numeric(x) && !is.integer(x)) formatC(x, format = "fg", digits = digits)
    else format(x)
  })
  emit("| ", paste(names(df), collapse = " | "), " |")
  emit("|", paste(rep("---", ncol(df)), collapse = "|"), "|")
  for (i in seq_len(nrow(df))) {
    emit("| ", paste(trimws(unlist(df[i, ])), collapse = " | "), " |")
  }
  emit("")
}
pct <- function(x) sprintf("%.2f%%", 100 * x)

emit("# Paper 4 / stage P4-0 — audit of `forecast_price_decimal`")
emit("")
emit("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
emit("")
emit("Read-only. Source: Smartform `historic_runners` / `daily_runners`, ",
     "plus the main `_targets` store (read, never written).")
emit("")

# -- Inputs from the frozen pipeline --------------------------------------
qualifying_races   <- targets::tar_read(qualifying_races)
qualifying_runners <- targets::tar_read(qualifying_runners)
races_train        <- targets::tar_read(races_train)
races_test         <- targets::tar_read(races_test)
test_predictions_3 <- targets::tar_read(test_predictions_3)

rank_universe_races <- sort(unique(test_predictions_3$race_id))
emit("Universe anchors: `qualifying_races` = ", nrow(qualifying_races),
     " races, `qualifying_runners` = ", nrow(qualifying_runners),
     " runner-rows; ranking test universe (races in `test_predictions_3`) = ",
     length(rank_universe_races), " races.")
emit("")

split_lookup <- bind_rows(
  races_train |> transmute(race_id, split = "train"),
  races_test  |> transmute(race_id, split = "test")
)

# -- Raw DB pull: every runner row for every qualifying race ---------------
con <- connect_smartform()
on.exit(try(disconnect_smartform(con), silent = TRUE), add = TRUE)

race_id_sql <- paste(qualifying_races$race_id, collapse = ", ")
raw <- DBI::dbGetQuery(con, sprintf("
  SELECT runner_id, race_id, unfinished, finish_position, amended_position,
         forecast_price, forecast_price_decimal,
         starting_price, starting_price_decimal,
         position_in_betting, loaded_at
    FROM historic_runners
   WHERE race_id IN (%s)", race_id_sql)) |>
  as_tibble()

emit("Raw `historic_runners` rows pulled for those races (Non-Runners still in): ",
     nrow(raw), ".")
emit("")

# =========================================================================
# ITEM 1 — schema, type, timing semantics
# =========================================================================
emit("## Item 1 — where the column lives, its type, and its timing semantics")
emit("")

schema_cols <- DBI::dbGetQuery(con, "
  SELECT table_name, column_name, column_type, is_nullable
    FROM information_schema.columns
   WHERE table_schema = DATABASE()
     AND column_name IN ('forecast_price','forecast_price_decimal',
                         'starting_price','starting_price_decimal',
                         'position_in_betting','loaded_at')
   ORDER BY table_name, column_name") |> as_tibble()
emit("### Schema location of the price columns")
emit("")
emit_tbl(schema_cols)

emit("**Timing evidence 1 — which tables carry which price.** ",
     "`starting_price` / `starting_price_decimal` exist ONLY on ",
     "`historic_runners`. `forecast_price` / `forecast_price_decimal` exist ",
     "on BOTH `historic_runners` and `daily_runners`. `daily_runners` is the ",
     "forward-looking feed table (today's declared cards), so the forecast ",
     "price is a field the feed publishes *before* the race and the starting ",
     "price is not.")
emit("")

daily_cols <- DBI::dbGetQuery(con, "
  SELECT column_name FROM information_schema.columns
   WHERE table_schema = DATABASE() AND table_name = 'daily_runners'
   ORDER BY ordinal_position")[[1]]
hist_cols <- DBI::dbGetQuery(con, "
  SELECT column_name FROM information_schema.columns
   WHERE table_schema = DATABASE() AND table_name = 'historic_runners'
   ORDER BY ordinal_position")[[1]]
emit("Columns in `historic_runners` but NOT in `daily_runners` ",
     "(the post-race additions): `",
     paste(setdiff(hist_cols, daily_cols), collapse = "`, `"), "`.")
emit("")
emit("Columns in `daily_runners` but NOT in `historic_runners`: `",
     paste(setdiff(daily_cols, hist_cols), collapse = "`, `"), "`.")
emit("")

daily_range <- DBI::dbGetQuery(con, "
  SELECT MIN(meeting_date) AS min_date, MAX(meeting_date) AS max_date,
         COUNT(*) AS n_races FROM daily_races") |> as_tibble()
emit("### `daily_races` date span")
emit("")
emit_tbl(daily_range |> mutate(n_races = as.numeric(n_races),
                               min_date = as.character(min_date),
                               max_date = as.character(max_date)))

overlap <- DBI::dbGetQuery(con, "
  SELECT COUNT(*) AS n_matched,
         SUM(d.forecast_price_decimal <=> h.forecast_price_decimal) AS n_identical,
         SUM(d.forecast_price <=> h.forecast_price)                 AS n_identical_char
    FROM daily_runners  AS d
    INNER JOIN historic_runners AS h
       ON h.runner_id = d.runner_id AND h.race_id = d.race_id") |> as_tibble()
emit("**Timing evidence 2 — daily feed vs archive, same runner-race.** ",
     "Rows appearing in both `daily_runners` and `historic_runners` on ",
     "(runner_id, race_id): ", as.numeric(overlap$n_matched), ". Of those, ",
     as.numeric(overlap$n_identical), " carry an identical ",
     "`forecast_price_decimal` and ", as.numeric(overlap$n_identical_char),
     " an identical `forecast_price` string.")
emit("")

fp_char <- raw |>
  filter(!is.na(forecast_price)) |>
  count(forecast_price, sort = TRUE)
emit("### `forecast_price` (char) value ladder, in-scope races")
emit("")
emit("Distinct `forecast_price` strings: ", nrow(fp_char),
     ". Distinct `starting_price` strings on the same rows: ",
     n_distinct(raw$starting_price[!is.na(raw$starting_price)]), ".")
emit("")
emit("Top 25 `forecast_price` strings:")
emit("")
emit_tbl(fp_char |> slice_head(n = 25) |> mutate(n = as.numeric(n)))

odd <- fp_char |> filter(!str_detect(forecast_price, "^\\s*[0-9]+/[0-9]+\\s*$"))
emit("Non-fractional / non-numeric `forecast_price` strings ",
     "(e.g. 'NR', 'SP', 'EVS'): ",
     if (nrow(odd) == 0) "none — every string is a plain `n/d` fraction."
     else paste0(nrow(odd), " distinct: ",
                 paste(sprintf("`%s` (n=%s)", odd$forecast_price, odd$n),
                       collapse = ", ")))
emit("")

fp_consistency <- raw |>
  filter(!is.na(forecast_price), !is.na(forecast_price_decimal),
         str_detect(forecast_price, "^\\s*[0-9]+/[0-9]+\\s*$")) |>
  mutate(
    num = as.numeric(str_extract(forecast_price, "^\\s*[0-9]+")),
    den = as.numeric(str_extract(forecast_price, "[0-9]+\\s*$")),
    implied_dec = num / den + 1,
    agrees = abs(implied_dec - forecast_price_decimal) < 0.011
  )
emit("`forecast_price_decimal` = fraction + 1 (stake included)? ",
     sum(fp_consistency$agrees), " of ", nrow(fp_consistency),
     " rows agree to within 0.011 (", pct(mean(fp_consistency$agrees)),
     "). Confirms decimal-odds semantics, not net odds.")
emit("")

emit("### Granularity: distinct values in scope")
emit("")
emit_tbl(tibble(
  column = c("forecast_price_decimal", "starting_price_decimal"),
  n_distinct_values = c(
    n_distinct(raw$forecast_price_decimal[!is.na(raw$forecast_price_decimal)]),
    n_distinct(raw$starting_price_decimal[!is.na(raw$starting_price_decimal)]))
))

emit("### `loaded_at` on the archive rows")
emit("")
la <- raw |> summarise(min = as.character(min(loaded_at, na.rm = TRUE)),
                       max = as.character(max(loaded_at, na.rm = TRUE)),
                       n_distinct_days = n_distinct(as.Date(loaded_at)))
emit_tbl(la)
emit("`loaded_at` is an archive-load stamp, not a price stamp: it carries no ",
     "information about when the forecast price itself was set, and is ",
     "reported here only to rule it out as a timing source.")
emit("")

# =========================================================================
# ITEM 2 — coverage
# =========================================================================
emit("## Item 2 — coverage")
emit("")
emit("\"Usable\" = non-NA and strictly greater than 1 (a decimal price of 1 ",
     "or below implies a probability of 1 or more and cannot be normalised).")
emit("")

runners <- qualifying_runners |>
  select(race_id, runner_id, won, sp_pipeline = starting_price_decimal) |>
  left_join(raw |> select(race_id, runner_id, forecast_price_decimal,
                          starting_price_decimal, position_in_betting),
            by = c("race_id", "runner_id")) |>
  left_join(split_lookup, by = "race_id") |>
  left_join(qualifying_races |> select(race_id, meeting_date), by = "race_id") |>
  mutate(
    year    = as.integer(format(meeting_date, "%Y")),
    fp_ok   = !is.na(forecast_price_decimal) & forecast_price_decimal > 1,
    sp_ok   = !is.na(starting_price_decimal) & starting_price_decimal > 1,
    in_rank = race_id %in% rank_universe_races
  )

emit("### Runner-row coverage")
emit("")
cov_rows <- runners |>
  group_by(split) |>
  summarise(runner_rows = n(),
            fp_usable = sum(fp_ok), fp_pct = mean(fp_ok),
            sp_usable = sum(sp_ok), sp_pct = mean(sp_ok), .groups = "drop") |>
  bind_rows(runners |> summarise(split = "ALL", runner_rows = n(),
                                 fp_usable = sum(fp_ok), fp_pct = mean(fp_ok),
                                 sp_usable = sum(sp_ok), sp_pct = mean(sp_ok)))
emit_tbl(cov_rows)

emit("### Race-level coverage — every runner priced")
emit("")
race_cov <- runners |>
  group_by(race_id, split, year, in_rank) |>
  summarise(n_runners = n(), n_fp = sum(fp_ok), n_sp = sum(sp_ok), .groups = "drop") |>
  mutate(fp_complete = n_fp == n_runners, sp_complete = n_sp == n_runners)

# NOTE: `summarise()` evaluates its expressions in order and later ones see
# the columns earlier ones created. Naming the count `fp_complete` and then
# writing `fp_pct = mean(fp_complete)` would average the count, not the
# logical. Compute the percentage from `fp_complete` BEFORE shadowing it.
race_cov_summary <- race_cov |>
  group_by(split) |>
  summarise(races = n(),
            fp_pct = mean(fp_complete), fp_races = sum(fp_complete),
            sp_pct = mean(sp_complete), sp_races = sum(sp_complete),
            .groups = "drop") |>
  bind_rows(race_cov |> summarise(split = "ALL", races = n(),
                                  fp_pct = mean(fp_complete), fp_races = sum(fp_complete),
                                  sp_pct = mean(sp_complete), sp_races = sum(sp_complete))) |>
  relocate(fp_races, .before = fp_pct) |>
  relocate(sp_races, .before = sp_pct)
emit_tbl(race_cov_summary)

rank_cov <- race_cov |> filter(in_rank)
rank_fp_pct <- mean(rank_cov$fp_complete)
emit("### The 2,183-race ranking test universe (the abort-condition target)")
emit("")
emit_tbl(tibble(
  races                 = nrow(rank_cov),
  every_runner_forecast = sum(rank_cov$fp_complete),
  pct_forecast_complete = rank_fp_pct,
  every_runner_sp       = sum(rank_cov$sp_complete),
  pct_sp_complete       = mean(rank_cov$sp_complete)
))

emit("### Coverage by year (all in-scope races, both splits)")
emit("")
cov_year <- runners |>
  group_by(year) |>
  summarise(runner_rows = n(), fp_row_pct = mean(fp_ok), sp_row_pct = mean(sp_ok),
            .groups = "drop") |>
  left_join(race_cov |> group_by(year) |>
              summarise(races = n(), fp_race_complete_pct = mean(fp_complete),
                        sp_race_complete_pct = mean(sp_complete), .groups = "drop"),
            by = "year") |>
  relocate(races, .after = year)
emit_tbl(cov_year)

pre13  <- runners |> filter(year <  2013) |> summarise(p = mean(fp_ok)) |> pull(p)
post13 <- runners |> filter(year >= 2013) |> summarise(p = mean(fp_ok)) |> pull(p)
emit("Pre-2013 runner-row coverage ", pct(pre13), " vs 2013-onward ",
     pct(post13), " — difference ",
     sprintf("%.2f percentage points", 100 * abs(post13 - pre13)), ".")
emit("")

# =========================================================================
# ITEM 3 — overround
# =========================================================================
emit("## Item 3 — overround")
emit("")
emit("Race overround = sum over the field of 1 / price, computed on races ",
     "where EVERY runner is priced so the sum is over a complete book. ",
     "Distributional statistics are TRAINING split only.")
emit("")

book <- runners |>
  group_by(race_id, split, year) |>
  summarise(
    n_runners   = n(),
    fp_complete = all(fp_ok),
    sp_complete = all(sp_ok),
    or_fp = if (all(fp_ok)) sum(1 / forecast_price_decimal) else NA_real_,
    or_sp = if (all(sp_ok)) sum(1 / starting_price_decimal) else NA_real_,
    .groups = "drop"
  )

book_train <- book |> filter(split == "train")

or_summary <- bind_rows(
  book_train |> filter(!is.na(or_fp)) |>
    summarise(source = "forecast price", races = n(),
              min = min(or_fp), p25 = quantile(or_fp, .25),
              median = median(or_fp), p75 = quantile(or_fp, .75),
              iqr = IQR(or_fp), max = max(or_fp), mean = mean(or_fp)),
  book_train |> filter(!is.na(or_sp)) |>
    summarise(source = "starting price", races = n(),
              min = min(or_sp), p25 = quantile(or_sp, .25),
              median = median(or_sp), p75 = quantile(or_sp, .75),
              iqr = IQR(or_sp), max = max(or_sp), mean = mean(or_sp))
)
emit("### Overround distribution — TRAINING split, complete books")
emit("")
emit_tbl(or_summary)

paired <- book_train |> filter(!is.na(or_fp), !is.na(or_sp))
emit("Races complete in both books (training split): ", nrow(paired),
     ". Median paired difference (forecast - SP): ",
     sprintf("%.4f", median(paired$or_fp - paired$or_sp)),
     "; mean ", sprintf("%.4f", mean(paired$or_fp - paired$or_sp)), ".")
emit("")

emit("### Overround trend across the window (all races, complete books)")
emit("")
or_year <- book |>
  group_by(year) |>
  summarise(races_fp     = sum(!is.na(or_fp)),
            median_or_fp = median(or_fp, na.rm = TRUE),
            iqr_or_fp    = IQR(or_fp, na.rm = TRUE),
            races_sp     = sum(!is.na(or_sp)),
            median_or_sp = median(or_sp, na.rm = TRUE),
            iqr_or_sp    = IQR(or_sp, na.rm = TRUE),
            .groups = "drop")
emit_tbl(or_year)

or_field <- book_train |> filter(!is.na(or_fp)) |>
  group_by(n_runners) |>
  summarise(races = n(), median_or_fp = median(or_fp),
            median_or_sp = median(or_sp, na.rm = TRUE), .groups = "drop")
emit("### Overround by field size (training split)")
emit("")
emit_tbl(or_field)

med_or_fp_train <- median(book_train$or_fp, na.rm = TRUE)

# =========================================================================
# ITEM 4 — shape vs SP
# =========================================================================
emit("## Item 4 — shape of the forecast book versus SP")
emit("")
emit("Both books proportionally overround-normalised within race (the same ",
     "adjustment `build_test_predictions()` applies to SP: ",
     "p_i = (1/price_i) / sum_j (1/price_j)). Restricted to TRAINING-split ",
     "races complete in both books. Regression of log p_forecast on log p_SP.")
emit("")

shape_dat <- runners |>
  filter(split == "train") |>
  group_by(race_id) |>
  filter(all(fp_ok), all(sp_ok)) |>
  mutate(
    p_fp = (1 / forecast_price_decimal) / sum(1 / forecast_price_decimal),
    p_sp = (1 / starting_price_decimal) / sum(1 / starting_price_decimal),
    lfp  = log(p_fp),
    lsp  = log(p_sp)
  ) |>
  mutate(lfp_c = lfp - mean(lfp), lsp_c = lsp - mean(lsp)) |>
  ungroup()

fit_pooled <- lm(lfp ~ lsp, data = shape_dat)
fit_within <- lm(lfp_c ~ 0 + lsp_c, data = shape_dat)

emit("Rows: ", nrow(shape_dat), " runners across ",
     n_distinct(shape_dat$race_id), " training races.")
emit("")
emit_tbl(tibble(
  specification = c("pooled OLS (with intercept)", "within-race (race FE, demeaned)"),
  slope = c(coef(fit_pooled)[["lsp"]], coef(fit_within)[["lsp_c"]]),
  std_error = c(summary(fit_pooled)$coefficients["lsp", "Std. Error"],
                summary(fit_within)$coefficients["lsp_c", "Std. Error"]),
  r_squared = c(summary(fit_pooled)$r.squared, summary(fit_within)$r.squared)
))
emit("The within-race specification is the one P4-0 asks for; the pooled fit ",
     "is reported alongside as a sanity check.")
emit("")

emit("### Within-race comparison by SP-probability decile (training split)")
emit("")
dec <- shape_dat |>
  mutate(sp_decile = ntile(p_sp, 10)) |>
  group_by(sp_decile) |>
  summarise(n = n(),
            median_p_sp = median(p_sp),
            median_p_fp = median(p_fp),
            mean_log_ratio = mean(lfp - lsp), .groups = "drop")
emit_tbl(dec)
emit("`mean_log_ratio` > 0 in a decile means the forecast book assigns MORE ",
     "probability there than SP does.")
emit("")

# =========================================================================
# ITEM 5 — non-runner behaviour
# =========================================================================
emit("## Item 5 — declared field or final field?")
emit("")

nr <- raw |>
  left_join(split_lookup, by = "race_id") |>
  mutate(
    is_nr = !is.na(unfinished) & unfinished == "Non-Runner",
    fp_ok = !is.na(forecast_price_decimal) & forecast_price_decimal > 1,
    sp_ok = !is.na(starting_price_decimal) & starting_price_decimal > 1
  )

nr_rates <- nr |>
  group_by(is_nr) |>
  summarise(rows = n(), fp_priced = sum(fp_ok), fp_pct = mean(fp_ok),
            sp_priced = sum(sp_ok), sp_pct = mean(sp_ok), .groups = "drop") |>
  mutate(row_class = if_else(is_nr, "Non-Runner", "starter"), .before = 1) |>
  select(-is_nr)
emit("### Are Non-Runners priced?")
emit("")
emit_tbl(nr_rates)
emit("A Non-Runner carrying a forecast price but no starting price is the ",
     "signature of a price stated against the DECLARED field: the forecast is ",
     "published before withdrawals are known; the SP is returned only for ",
     "horses that actually started.")
emit("")

pipeline_set <- qualifying_runners |> select(race_id, runner_id) |>
  mutate(in_pipeline = TRUE)
priced_set <- nr |> filter(fp_ok) |> select(race_id, runner_id) |>
  mutate(fp_priced = TRUE)

setcmp <- full_join(pipeline_set, priced_set, by = c("race_id", "runner_id")) |>
  filter(race_id %in% qualifying_races$race_id) |>
  mutate(in_pipeline = coalesce(in_pipeline, FALSE),
         fp_priced   = coalesce(fp_priced, FALSE)) |>
  group_by(race_id) |>
  summarise(
    n_pipeline         = sum(in_pipeline),
    n_priced           = sum(fp_priced),
    priced_not_in_pipe = sum(fp_priced & !in_pipeline),
    in_pipe_not_priced = sum(in_pipeline & !fp_priced),
    .groups = "drop"
  ) |>
  mutate(exact_match = priced_not_in_pipe == 0 & in_pipe_not_priced == 0,
         superset_ok = in_pipe_not_priced == 0) |>
  left_join(split_lookup, by = "race_id") |>
  mutate(in_rank = race_id %in% rank_universe_races)

emit("### Runner-set comparison: forecast-priced set vs the pipeline's field")
emit("")
emit_tbl(tibble(
  scope = c("all in-scope races", "training split", "test split",
            "ranking test universe"),
  races = c(nrow(setcmp), sum(setcmp$split == "train"),
            sum(setcmp$split == "test"), sum(setcmp$in_rank)),
  exact_set_match_pct = c(mean(setcmp$exact_match),
                          mean(setcmp$exact_match[setcmp$split == "train"]),
                          mean(setcmp$exact_match[setcmp$split == "test"]),
                          mean(setcmp$exact_match[setcmp$in_rank])),
  every_used_runner_priced_pct = c(mean(setcmp$superset_ok),
                                   mean(setcmp$superset_ok[setcmp$split == "train"]),
                                   mean(setcmp$superset_ok[setcmp$split == "test"]),
                                   mean(setcmp$superset_ok[setcmp$in_rank])),
  mismatch_pct = c(1 - mean(setcmp$exact_match),
                   1 - mean(setcmp$exact_match[setcmp$split == "train"]),
                   1 - mean(setcmp$exact_match[setcmp$split == "test"]),
                   1 - mean(setcmp$exact_match[setcmp$in_rank]))
))

emit("Decomposition of the mismatch (all in-scope races):")
emit("")
emit_tbl(tibble(
  condition = c("priced runner NOT in the pipeline field (a withdrawal, or a row the pipeline dropped)",
                "pipeline runner NOT priced (a genuine coverage hole)"),
  races_affected = c(sum(setcmp$priced_not_in_pipe > 0),
                     sum(setcmp$in_pipe_not_priced > 0)),
  pct_of_races = c(mean(setcmp$priced_not_in_pipe > 0),
                   mean(setcmp$in_pipe_not_priced > 0))
))

emit("The two conditions are materially different. The first is expected and ",
     "harmless *given* proportional renormalisation over the runners actually ",
     "used: it means the morning book was struck over a larger field. The ",
     "second is what actually costs races in P4-1.")
emit("")

extra <- nr |>
  anti_join(pipeline_set, by = c("race_id", "runner_id")) |>
  filter(fp_ok) |>
  summarise(rows = n(), pct_non_runner = mean(is_nr))
emit("Priced runner-rows not used by the pipeline: ", extra$rows,
     ", of which ", pct(extra$pct_non_runner),
     " are flagged `unfinished = 'Non-Runner'` (the remainder are rows the ",
     "pipeline's own race-level filters removed).")
emit("")

# =========================================================================
# ABORT CONDITIONS
# =========================================================================
emit("## Abort conditions")
emit("")

mismatch_rate <- 1 - mean(setcmp$exact_match)
cov_gap_pp    <- 100 * abs(post13 - pre13)

abort <- tibble(
  condition = c(
    "< 70% of the 2,183 test-universe races have every runner priced",
    "median race overround outside 1.05 to 1.60",
    "pre-2013 coverage differs from 2013-onward by > 20 percentage points",
    "runner-set mismatch (item 5) above 5% of races"
  ),
  observed = c(
    sprintf("%.2f%% of races complete", 100 * rank_fp_pct),
    sprintf("median = %.4f", med_or_fp_train),
    sprintf("%.2f pp", cov_gap_pp),
    sprintf("%.2f%%", 100 * mismatch_rate)
  ),
  fires = c(
    rank_fp_pct < 0.70,
    med_or_fp_train < 1.05 || med_or_fp_train > 1.60,
    cov_gap_pp > 20,
    mismatch_rate > 0.05
  )
)
abort$verdict <- if_else(abort$fires, "**ABORT**", "pass")
emit_tbl(abort |> select(condition, observed, verdict))

emit("")
if (any(abort$fires)) {
  emit("**AT LEAST ONE ABORT CONDITION FIRED. P4-1 must not proceed on the ",
       "stated design.**")
} else {
  emit("No abort condition fired. P4-1 proceeds.")
}
emit("")

saveRDS(
  list(
    generated_at    = Sys.time(),
    abort           = abort,
    rank_fp_pct     = rank_fp_pct,
    median_or_fp    = med_or_fp_train,
    coverage_gap_pp = cov_gap_pp,
    mismatch_rate   = mismatch_rate,
    cov_rows        = cov_rows,
    race_cov        = race_cov_summary,
    cov_year        = cov_year,
    or_summary      = or_summary,
    or_year         = or_year,
    shape_slopes    = tibble(
      spec  = c("pooled", "within_race"),
      slope = c(coef(fit_pooled)[["lsp"]], coef(fit_within)[["lsp_c"]])
    ),
    setcmp_summary = setcmp |> summarise(races = n(),
                                         exact = mean(exact_match),
                                         superset = mean(superset_ok))
  ),
  "scripts/p4_audit_forecast_price.rds"
)

close(out_con)
cat("Wrote", OUT, "\n")
cat("Abort conditions firing:", sum(abort$fires), "of 4\n")
print(as.data.frame(abort[, c("condition", "observed", "verdict")]))
