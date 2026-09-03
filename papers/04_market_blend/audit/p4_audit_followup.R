# p4_audit_followup.R
#
# Paper 4, stage P4-0 — follow-ups the main audit surfaced but did not
# resolve. Read-only; no pipeline state touched.
#
#   A. Is the forecast price REVISED? The daily-feed vs archive comparison
#      in the main audit found 847,109 of 1,017,161 matched runner-rows
#      identical. Characterise the other 170k: NULL-vs-value, or a genuine
#      change of price?
#   B. The two `forecast_price = '-214748364'` rows (INT_MIN sentinel).
#   C. Degenerate books: the training-split forecast overround ranges down
#      to 0.33 and up to 2.42. How many races are pathological, and do any
#      of them fall in the ranking test universe?
#
# Run: "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" papers/04_market_blend/audit/p4_audit_followup.R

source("renv/activate.R")
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})
source("R/db.R")

OUT <- "papers/04_market_blend/audit/p4_audit_followup_output.md"
out_con <- file(OUT, open = "wt", encoding = "UTF-8")
emit <- function(...) cat(..., "\n", sep = "", file = out_con)
emit_tbl <- function(df, digits = 5) {
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

emit("# P4-0 follow-ups")
emit("")
emit("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
emit("")

qualifying_races   <- targets::tar_read(qualifying_races)
qualifying_runners <- targets::tar_read(qualifying_runners)
races_train        <- targets::tar_read(races_train)
test_predictions_3 <- targets::tar_read(test_predictions_3)
rank_races <- sort(unique(test_predictions_3$race_id))

con <- connect_smartform()
on.exit(try(disconnect_smartform(con), silent = TRUE), add = TRUE)

# -- A. Is the forecast price revised? ------------------------------------
emit("## A. Is the forecast price revised between the daily feed and the archive?")
emit("")

dup <- DBI::dbGetQuery(con, "
  SELECT COUNT(*) AS n_rows, COUNT(DISTINCT runner_id, race_id) AS n_keys
    FROM daily_runners") |> as_tibble()
emit("`daily_runners`: ", as.numeric(dup$n_rows), " rows over ",
     as.numeric(dup$n_keys), " distinct (runner_id, race_id) keys — ",
     if (as.numeric(dup$n_rows) == as.numeric(dup$n_keys))
       "one row per runner-race, so the feed table is a snapshot, not a version log."
     else "duplicated keys present, so the feed table retains multiple loads.")
emit("")

cmp <- DBI::dbGetQuery(con, "
  SELECT
    SUM(d.forecast_price_decimal IS NULL AND h.forecast_price_decimal IS NULL) AS both_null,
    SUM(d.forecast_price_decimal IS NULL AND h.forecast_price_decimal IS NOT NULL) AS daily_null_only,
    SUM(d.forecast_price_decimal IS NOT NULL AND h.forecast_price_decimal IS NULL) AS hist_null_only,
    SUM(d.forecast_price_decimal IS NOT NULL AND h.forecast_price_decimal IS NOT NULL
        AND ABS(d.forecast_price_decimal - h.forecast_price_decimal) < 0.005) AS both_equal,
    SUM(d.forecast_price_decimal IS NOT NULL AND h.forecast_price_decimal IS NOT NULL
        AND ABS(d.forecast_price_decimal - h.forecast_price_decimal) >= 0.005) AS both_differ,
    COUNT(*) AS n_matched
  FROM daily_runners AS d
  INNER JOIN historic_runners AS h
     ON h.runner_id = d.runner_id AND h.race_id = d.race_id") |> as_tibble()
emit("### Daily-feed value vs archive value, all matched runner-rows")
emit("")
emit_tbl(cmp |> mutate(across(everything(), as.numeric)) |>
           pivot_longer(everything(), names_to = "case", values_to = "rows") |>
           mutate(pct = rows / rows[case == "n_matched"]))

emit("Read: `both_equal` is the archive reproducing the pre-race feed value ",
     "unchanged. `daily_null_only` / `hist_null_only` are coverage gaps on one ",
     "side, not revisions. `both_differ` is the only cell that could be a ",
     "revision.")
emit("")

diffs <- DBI::dbGetQuery(con, "
  SELECT d.forecast_price_decimal AS daily_fp,
         h.forecast_price_decimal AS hist_fp,
         COUNT(*) AS n
    FROM daily_runners AS d
    INNER JOIN historic_runners AS h
       ON h.runner_id = d.runner_id AND h.race_id = d.race_id
   WHERE d.forecast_price_decimal IS NOT NULL
     AND h.forecast_price_decimal IS NOT NULL
     AND ABS(d.forecast_price_decimal - h.forecast_price_decimal) >= 0.005
   GROUP BY d.forecast_price_decimal, h.forecast_price_decimal
   ORDER BY n DESC
   LIMIT 20") |> as_tibble()
emit("### Twenty most common (daily, archive) disagreeing pairs")
emit("")
if (nrow(diffs) == 0) {
  emit("None — the archive never disagrees with the feed on a value both hold.")
} else {
  emit_tbl(diffs |> mutate(n = as.numeric(n),
                           steps_apart = NA_character_) |> select(-steps_apart))
}

# Same question restricted to the in-scope AW races.
race_id_sql <- paste(qualifying_races$race_id, collapse = ", ")
cmp_scope <- DBI::dbGetQuery(con, sprintf("
  SELECT
    SUM(d.forecast_price_decimal IS NOT NULL AND h.forecast_price_decimal IS NOT NULL
        AND ABS(d.forecast_price_decimal - h.forecast_price_decimal) < 0.005) AS both_equal,
    SUM(d.forecast_price_decimal IS NOT NULL AND h.forecast_price_decimal IS NOT NULL
        AND ABS(d.forecast_price_decimal - h.forecast_price_decimal) >= 0.005) AS both_differ,
    COUNT(*) AS n_matched
  FROM daily_runners AS d
  INNER JOIN historic_runners AS h
     ON h.runner_id = d.runner_id AND h.race_id = d.race_id
  WHERE d.race_id IN (%s)", race_id_sql)) |> as_tibble()
emit("### Restricted to the ", nrow(qualifying_races), " in-scope AW races")
emit("")
emit_tbl(cmp_scope |> mutate(across(everything(), as.numeric)))

# -- B. The INT_MIN sentinel rows -----------------------------------------
emit("## B. The `forecast_price = '-214748364'` rows")
emit("")
sentinel <- DBI::dbGetQuery(con, sprintf("
  SELECT runner_id, race_id, unfinished, forecast_price,
         forecast_price_decimal, starting_price, starting_price_decimal
    FROM historic_runners
   WHERE race_id IN (%s)
     AND forecast_price = '-214748364'", race_id_sql)) |> as_tibble()
emit_tbl(sentinel |> mutate(across(everything(), as.character)))
emit("`-214748364` is a truncated INT_MIN sentinel written into the char ",
     "column. What matters for P4-1 is only whether the *decimal* column on ",
     "those rows is usable.")
emit("")
sentinel_in_pipeline <- sentinel |>
  semi_join(qualifying_runners, by = c("race_id", "runner_id"))
emit("Of those rows, ", nrow(sentinel_in_pipeline),
     " are in the pipeline's runner set; ",
     sum(sentinel_in_pipeline$race_id %in% rank_races),
     " are in the ranking test universe.")
emit("")

# Whole-table sweep for any other sentinel-looking decimal values.
weird <- DBI::dbGetQuery(con, "
  SELECT COUNT(*) AS n
    FROM historic_runners
   WHERE forecast_price_decimal IS NOT NULL
     AND (forecast_price_decimal <= 1 OR forecast_price_decimal > 1001)") |> as_tibble()
emit("Whole-table `historic_runners` rows with a non-NULL ",
     "`forecast_price_decimal` outside (1, 1001]: ", as.numeric(weird$n), ".")
emit("")

# -- C. Degenerate books --------------------------------------------------
emit("## C. Degenerate books")
emit("")

raw <- DBI::dbGetQuery(con, sprintf("
  SELECT runner_id, race_id, forecast_price_decimal, starting_price_decimal
    FROM historic_runners
   WHERE race_id IN (%s)", race_id_sql)) |> as_tibble()

book <- qualifying_runners |>
  select(race_id, runner_id) |>
  left_join(raw, by = c("race_id", "runner_id")) |>
  mutate(fp_ok = !is.na(forecast_price_decimal) & forecast_price_decimal > 1) |>
  group_by(race_id) |>
  summarise(n_runners = n(), complete = all(fp_ok),
            or_fp = if (all(fp_ok)) sum(1 / forecast_price_decimal) else NA_real_,
            .groups = "drop") |>
  mutate(split = if_else(race_id %in% races_train$race_id, "train", "test"),
         in_rank = race_id %in% rank_races)

emit("Complete-book races with an implausible overround, by band:")
emit("")
bands <- book |>
  filter(!is.na(or_fp)) |>
  mutate(band = case_when(
    or_fp < 0.90 ~ "below 0.90 (an underround the market would never strike)",
    or_fp < 1.00 ~ "0.90 to 1.00",
    or_fp <= 1.60 ~ "1.00 to 1.60 (plausible)",
    TRUE ~ "above 1.60")) |>
  count(band, split) |>
  pivot_wider(names_from = split, values_from = n, values_fill = 0L)
emit_tbl(bands)

emit("Ranking-test-universe races outside 1.00 to 1.60: ",
     sum(book$in_rank & !is.na(book$or_fp) & (book$or_fp < 1 | book$or_fp > 1.6)),
     " of ", sum(book$in_rank), ".")
emit("")

emit("Ten most extreme complete-book overrounds (any split):")
emit("")
emit_tbl(book |> filter(!is.na(or_fp)) |> arrange(desc(abs(or_fp - 1.15))) |>
           slice_head(n = 10) |>
           select(race_id, split, in_rank, n_runners, or_fp))

close(out_con)
cat("Wrote", OUT, "\n")
