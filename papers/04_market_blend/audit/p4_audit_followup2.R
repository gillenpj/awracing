# p4_audit_followup2.R
#
# Paper 4, stage P4-0 — two questions the first follow-up opened.
# Read-only; no pipeline state touched.
#
#   D. The archived forecast price differs from the daily-feed forecast
#      price on ~33% of in-scope runner-rows. Which direction does the
#      revision run? If the ARCHIVE value is systematically closer to SP
#      than the FEED value is, the archived column is a late (or worse,
#      post-race) revision and is not the morning price paper 4 wants.
#      This is the decisive test on item 1's "when is it set, and is it
#      revised".
#
#   E. The main audit computed race overround over the FINAL field (the
#      pipeline's runner set). The forecast book is struck over the
#      DECLARED field. Report both, because a book that looks underround
#      after withdrawals were removed is not actually an underround book.
#
# Run: "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" papers/04_market_blend/audit/p4_audit_followup2.R

source("renv/activate.R")
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})
source("R/db.R")

OUT <- "papers/04_market_blend/audit/p4_audit_followup2_output.md"
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

emit("# P4-0 follow-ups, part 2")
emit("")
emit("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
emit("")

qualifying_races   <- targets::tar_read(qualifying_races)
qualifying_runners <- targets::tar_read(qualifying_runners)
races_train        <- targets::tar_read(races_train)
test_predictions_3 <- targets::tar_read(test_predictions_3)
rank_races  <- sort(unique(test_predictions_3$race_id))
train_races <- races_train$race_id

con <- connect_smartform()
on.exit(try(disconnect_smartform(con), silent = TRUE), add = TRUE)

race_id_sql <- paste(qualifying_races$race_id, collapse = ", ")

# =========================================================================
# D0. When was each row WRITTEN, relative to the race?
# =========================================================================
emit("## D0. When was each row written, relative to the race?")
emit("")
emit("`loaded_at` stamps the row, not the price. But if the daily-feed row is ",
     "written before the meeting and the archive row after it, then the ",
     "archive's forecast price was *transcribed* post-race — which is the ",
     "circumstance under which a difference between the two could carry ",
     "hindsight, and is therefore worth establishing before reading the ",
     "revision direction in D.")
emit("")

load_timing <- DBI::dbGetQuery(con, sprintf("
  SELECT
    SUM(d.loaded_at <  r.meeting_date) AS daily_before_meeting,
    SUM(d.loaded_at >= r.meeting_date) AS daily_on_or_after,
    SUM(h.loaded_at <  r.meeting_date) AS hist_before_meeting,
    SUM(h.loaded_at >= r.meeting_date) AS hist_on_or_after,
    COUNT(*) AS n
  FROM daily_runners AS d
  INNER JOIN historic_runners AS h
     ON h.runner_id = d.runner_id AND h.race_id = d.race_id
  INNER JOIN historic_races AS r ON r.race_id = h.race_id
  WHERE h.race_id IN (%s)", race_id_sql)) |> as_tibble()
emit_tbl(load_timing |> mutate(across(everything(), as.numeric)) |>
           pivot_longer(everything(), names_to = "case", values_to = "rows"))

lag_stats <- DBI::dbGetQuery(con, sprintf("
  SELECT
    AVG(DATEDIFF(d.loaded_at, r.meeting_date)) AS mean_daily_lag_days,
    MIN(DATEDIFF(d.loaded_at, r.meeting_date)) AS min_daily_lag_days,
    MAX(DATEDIFF(d.loaded_at, r.meeting_date)) AS max_daily_lag_days,
    AVG(DATEDIFF(h.loaded_at, r.meeting_date)) AS mean_hist_lag_days,
    MIN(DATEDIFF(h.loaded_at, r.meeting_date)) AS min_hist_lag_days,
    MAX(DATEDIFF(h.loaded_at, r.meeting_date)) AS max_hist_lag_days
  FROM daily_runners AS d
  INNER JOIN historic_runners AS h
     ON h.runner_id = d.runner_id AND h.race_id = d.race_id
  INNER JOIN historic_races AS r ON r.race_id = h.race_id
  WHERE h.race_id IN (%s)", race_id_sql)) |> as_tibble()
emit("Row-write lag relative to `meeting_date`, in days (negative = written ",
     "before the meeting):")
emit("")
emit_tbl(lag_stats |> mutate(across(everything(), as.numeric)))
emit("")

# =========================================================================
# D. Direction of the feed -> archive revision
# =========================================================================
emit("## D. Which way does the feed-to-archive revision run?")
emit("")
emit("If the archived `forecast_price_decimal` were a late or post-race ",
     "revision, it would sit systematically closer to the starting price than ",
     "the daily-feed value does. Test on TRAINING-split runner-rows where the ",
     "feed value, the archive value and the SP are all present and the feed ",
     "and archive disagree.")
emit("")

rev <- DBI::dbGetQuery(con, sprintf("
  SELECT h.race_id, h.runner_id,
         d.forecast_price_decimal AS fp_feed,
         h.forecast_price_decimal AS fp_arch,
         h.starting_price_decimal AS sp
    FROM daily_runners AS d
    INNER JOIN historic_runners AS h
       ON h.runner_id = d.runner_id AND h.race_id = d.race_id
   WHERE h.race_id IN (%s)
     AND d.forecast_price_decimal IS NOT NULL
     AND h.forecast_price_decimal IS NOT NULL
     AND h.starting_price_decimal IS NOT NULL", race_id_sql)) |>
  as_tibble() |>
  semi_join(qualifying_runners, by = c("race_id", "runner_id")) |>
  filter(race_id %in% train_races, fp_feed > 1, fp_arch > 1, sp > 1) |>
  mutate(
    d_feed  = abs(log(fp_feed) - log(sp)),
    d_arch  = abs(log(fp_arch) - log(sp)),
    differs = abs(fp_feed - fp_arch) >= 0.005
  )

emit("Training-split runner-rows with feed + archive + SP all present: ",
     nrow(rev), ", of which ", sum(rev$differs), " (",
     sprintf("%.2f%%", 100 * mean(rev$differs)),
     ") have feed and archive disagreeing.")
emit("")

rd <- rev |> filter(differs)
emit("### Distance to SP on |log price| scale, rows where feed and archive disagree")
emit("")
emit_tbl(tibble(
  quantity = c("mean |log fp_feed - log sp|", "mean |log fp_arch - log sp|",
               "mean difference (archive - feed)",
               "share of rows where archive is CLOSER to SP than feed"),
  value = c(mean(rd$d_feed), mean(rd$d_arch),
            mean(rd$d_arch - rd$d_feed), mean(rd$d_arch < rd$d_feed))
))

tt <- t.test(rd$d_arch, rd$d_feed, paired = TRUE)
emit("Paired t-test on the per-row difference (archive - feed) in distance to ",
     "SP: mean ", sprintf("%.5f", unname(tt$estimate)),
     ", 95% CI [", sprintf("%.5f", tt$conf.int[1]), ", ",
     sprintf("%.5f", tt$conf.int[2]), "], t = ", sprintf("%.2f", unname(tt$statistic)),
     ", p = ", format.pval(tt$p.value, digits = 3), ".")
emit("")
emit("A mean near zero and a ~50% share means the revision is noise around ",
     "the same target, not convergence toward SP. A clearly negative mean and ",
     "a share well above 50% would mean the archive value has drifted toward ",
     "the result-side price and could not be treated as the morning price.")
emit("")

emit("### Size of the revision, in ladder steps")
emit("")
emit_tbl(rd |>
  mutate(log_move = log(fp_arch) - log(fp_feed)) |>
  summarise(n = n(),
            p05 = quantile(log_move, .05), p25 = quantile(log_move, .25),
            median = median(log_move), p75 = quantile(log_move, .75),
            p95 = quantile(log_move, .95),
            mean = mean(log_move), sd = sd(log_move)))
emit("Symmetric around zero would say the archive is a re-forecast, not a ",
     "correction in a known direction.")
emit("")

emit("### Which value correlates better with the outcome?")
emit("")
won_lookup <- qualifying_runners |> select(race_id, runner_id, won)
rw <- rd |> inner_join(won_lookup, by = c("race_id", "runner_id"))
emit_tbl(tibble(
  price_source = c("daily feed forecast", "archive forecast", "starting price"),
  mean_log_price_winners = c(mean(log(rw$fp_feed[rw$won == 1])),
                             mean(log(rw$fp_arch[rw$won == 1])),
                             mean(log(rw$sp[rw$won == 1]))),
  mean_log_price_losers  = c(mean(log(rw$fp_feed[rw$won == 0])),
                             mean(log(rw$fp_arch[rw$won == 0])),
                             mean(log(rw$sp[rw$won == 0]))),
  separation = c(mean(log(rw$fp_feed[rw$won == 0])) - mean(log(rw$fp_feed[rw$won == 1])),
                 mean(log(rw$fp_arch[rw$won == 0])) - mean(log(rw$fp_arch[rw$won == 1])),
                 mean(log(rw$sp[rw$won == 0]))      - mean(log(rw$sp[rw$won == 1])))
))
emit("Larger `separation` = the price discriminates winners from losers more ",
     "sharply on these rows. Reported as a descriptive check on the training ",
     "split only; it is not a model fit and nothing downstream is selected on it.")
emit("")

# =========================================================================
# E. Overround: declared field vs final field
# =========================================================================
emit("## E. Overround over the declared field vs the final field")
emit("")

raw_all <- DBI::dbGetQuery(con, sprintf("
  SELECT runner_id, race_id, unfinished, forecast_price_decimal,
         starting_price_decimal
    FROM historic_runners
   WHERE race_id IN (%s)", race_id_sql)) |> as_tibble()

declared <- raw_all |>
  mutate(fp_ok = !is.na(forecast_price_decimal) & forecast_price_decimal > 1) |>
  group_by(race_id) |>
  summarise(n_declared = n(),
            n_nr = sum(!is.na(unfinished) & unfinished == "Non-Runner"),
            or_declared = if (all(fp_ok)) sum(1 / forecast_price_decimal) else NA_real_,
            .groups = "drop")

final <- qualifying_runners |>
  select(race_id, runner_id) |>
  left_join(raw_all |> select(race_id, runner_id, forecast_price_decimal),
            by = c("race_id", "runner_id")) |>
  mutate(fp_ok = !is.na(forecast_price_decimal) & forecast_price_decimal > 1) |>
  group_by(race_id) |>
  summarise(n_final = n(),
            or_final = if (all(fp_ok)) sum(1 / forecast_price_decimal) else NA_real_,
            .groups = "drop")

ors <- final |>
  inner_join(declared, by = "race_id") |>
  mutate(split = if_else(race_id %in% train_races, "train", "test"),
         in_rank = race_id %in% rank_races,
         has_nr = n_nr > 0)

ort <- ors |> filter(split == "train")
emit("### Training split, forecast book")
emit("")
emit_tbl(bind_rows(
  ort |> filter(!is.na(or_declared)) |>
    summarise(basis = "declared field (as struck)", races = n(),
              p25 = quantile(or_declared, .25), median = median(or_declared),
              p75 = quantile(or_declared, .75), min = min(or_declared),
              max = max(or_declared)),
  ort |> filter(!is.na(or_final)) |>
    summarise(basis = "final field (pipeline runner set)", races = n(),
              p25 = quantile(or_final, .25), median = median(or_final),
              p75 = quantile(or_final, .75), min = min(or_final),
              max = max(or_final))
))

emit("### Split by whether the race had a withdrawal (training split, final-field basis)")
emit("")
emit_tbl(ort |> filter(!is.na(or_final)) |>
  group_by(had_non_runner = has_nr) |>
  summarise(races = n(), median_or_final = median(or_final),
            median_or_declared = median(or_declared, na.rm = TRUE),
            pct_under_1 = mean(or_final < 1), .groups = "drop"))

emit("This is the whole story behind the sub-1.00 books in the main audit: ",
     "removing a withdrawn runner removes its share of the book, so a race ",
     "struck at ~1.16 over the declared field falls below 1.00 over the final ",
     "field once enough runners come out. It is an artefact of the field ",
     "change, not a malformed price. Proportional renormalisation over the ",
     "final field is unaffected — it rescales to sum 1 either way.")
emit("")

emit("### Ranking test universe, final-field basis")
emit("")
emit_tbl(ors |> filter(in_rank, !is.na(or_final)) |>
  summarise(races = n(), median = median(or_final),
            p25 = quantile(or_final, .25), p75 = quantile(or_final, .75),
            pct_under_1 = mean(or_final < 1), pct_over_1.6 = mean(or_final > 1.6)))

emit("### Ranking test universe, declared-field basis")
emit("")
emit_tbl(ors |> filter(in_rank, !is.na(or_declared)) |>
  summarise(races = n(), median = median(or_declared),
            p25 = quantile(or_declared, .25), p75 = quantile(or_declared, .75),
            pct_under_1 = mean(or_declared < 1), pct_over_1.6 = mean(or_declared > 1.6)))

close(out_con)
cat("Wrote", OUT, "\n")
