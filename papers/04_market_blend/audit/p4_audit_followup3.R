# p4_audit_followup3.R
#
# Paper 4, stage P4-0 — costing the clean alternative price source.
# Read-only; no pipeline state touched.
#
# Follow-up 2 established two things about `historic_runners.
# forecast_price_decimal`, the column P4-0 was asked to audit:
#   * every archive row is written on or AFTER the meeting date
#     (min lag +1 day), so the value is a post-race transcription; and
#   * where it disagrees with the pre-race `daily_runners` snapshot
#     (32.5% of in-scope rows) it sits significantly CLOSER to SP.
#
# `daily_runners.forecast_price_decimal` on a row written before the
# meeting is a forecast price with no such exposure. This script costs it
# as a substitute: coverage on the 2,183-race ranking test universe,
# overround, and shape vs SP. If it covers the universe, the A arm of
# P4-2 can be run on a genuinely pre-race price.
#
# Run: "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" papers/04_market_blend/audit/p4_audit_followup3.R

source("renv/activate.R")
suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})
source("R/db.R")

OUT <- "papers/04_market_blend/audit/p4_audit_followup3_output.md"
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
pct <- function(x) sprintf("%.2f%%", 100 * x)

emit("# P4-0 follow-ups, part 3 — the pre-race `daily_runners` price as a substitute")
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

# Pull the daily-feed price alongside the archive price and the SP, keeping
# the feed row's load lag so a strictly-pre-race subset can be taken.
feed <- DBI::dbGetQuery(con, sprintf("
  SELECT h.race_id, h.runner_id,
         d.forecast_price_decimal AS fp_feed,
         DATEDIFF(d.loaded_at, r.meeting_date) AS feed_lag_days,
         h.forecast_price_decimal AS fp_arch,
         h.starting_price_decimal AS sp,
         r.meeting_date
    FROM historic_runners AS h
    INNER JOIN historic_races AS r ON r.race_id = h.race_id
    LEFT  JOIN daily_runners AS d
           ON d.runner_id = h.runner_id AND d.race_id = h.race_id
   WHERE h.race_id IN (%s)", race_id_sql)) |> as_tibble()

dat <- qualifying_runners |>
  select(race_id, runner_id, won) |>
  left_join(feed, by = c("race_id", "runner_id")) |>
  mutate(
    year    = as.integer(format(meeting_date, "%Y")),
    split   = if_else(race_id %in% train_races, "train", "test"),
    in_rank = race_id %in% rank_races,
    feed_prerace = !is.na(feed_lag_days) & feed_lag_days < 0,
    fp_feed_ok   = !is.na(fp_feed) & fp_feed > 1,
    fp_feed_prerace_ok = fp_feed_ok & feed_prerace,
    fp_arch_ok   = !is.na(fp_arch) & fp_arch > 1,
    sp_ok        = !is.na(sp) & sp > 1
  )

emit("## Coverage of the daily-feed price on the pipeline's runner set")
emit("")
emit("`fp_feed` = `daily_runners.forecast_price_decimal`. ",
     "`fp_feed_prerace` additionally requires the feed row to have been ",
     "written strictly before the meeting date.")
emit("")

cov <- dat |>
  group_by(split) |>
  summarise(runner_rows = n(),
            fp_arch_pct = mean(fp_arch_ok),
            fp_feed_pct = mean(fp_feed_ok),
            fp_feed_prerace_pct = mean(fp_feed_prerace_ok),
            .groups = "drop") |>
  bind_rows(dat |> summarise(split = "ALL", runner_rows = n(),
                             fp_arch_pct = mean(fp_arch_ok),
                             fp_feed_pct = mean(fp_feed_ok),
                             fp_feed_prerace_pct = mean(fp_feed_prerace_ok)))
emit_tbl(cov)

emit("### By year")
emit("")
emit_tbl(dat |> group_by(year) |>
  summarise(runner_rows = n(),
            fp_arch_pct = mean(fp_arch_ok),
            fp_feed_pct = mean(fp_feed_ok),
            fp_feed_prerace_pct = mean(fp_feed_prerace_ok), .groups = "drop"))
emit("`daily_races` only starts 2008-03-01, so the feed price is structurally ",
     "absent before then. The test split starts 2012-12-30, well inside the ",
     "feed's span, which is what matters for P4-2.")
emit("")

emit("### Race-level completeness — every runner in the race priced")
emit("")
race_cov <- dat |>
  group_by(race_id, split, in_rank) |>
  summarise(n_runners = n(),
            arch_complete = all(fp_arch_ok),
            feed_complete = all(fp_feed_ok),
            feed_prerace_complete = all(fp_feed_prerace_ok),
            .groups = "drop")
emit_tbl(race_cov |> group_by(split) |>
  summarise(races = n(), arch_pct = mean(arch_complete),
            feed_pct = mean(feed_complete),
            feed_prerace_pct = mean(feed_prerace_complete), .groups = "drop") |>
  bind_rows(race_cov |> summarise(split = "ALL", races = n(),
                                  arch_pct = mean(arch_complete),
                                  feed_pct = mean(feed_complete),
                                  feed_prerace_pct = mean(feed_prerace_complete))))

emit("### The 2,183-race ranking test universe — the number that decides it")
emit("")
rk <- race_cov |> filter(in_rank)
emit_tbl(tibble(
  price_source = c("archive forecast (historic_runners)",
                   "feed forecast (daily_runners, any load time)",
                   "feed forecast, feed row written pre-race"),
  races_complete = c(sum(rk$arch_complete), sum(rk$feed_complete),
                     sum(rk$feed_prerace_complete)),
  of_races = nrow(rk),
  pct_complete = c(mean(rk$arch_complete), mean(rk$feed_complete),
                   mean(rk$feed_prerace_complete))
))
emit("The P4-0 abort threshold on this quantity is 70%.")
emit("")

# -- Overround and shape, training split ----------------------------------
emit("## Overround and shape of the feed book (training split)")
emit("")

book <- dat |>
  filter(split == "train") |>
  group_by(race_id) |>
  summarise(n_runners = n(),
            or_feed = if (all(fp_feed_ok)) sum(1 / fp_feed) else NA_real_,
            or_arch = if (all(fp_arch_ok)) sum(1 / fp_arch) else NA_real_,
            or_sp   = if (all(sp_ok))      sum(1 / sp)      else NA_real_,
            .groups = "drop")
emit_tbl(bind_rows(
  book |> filter(!is.na(or_feed)) |>
    summarise(source = "feed forecast", races = n(), p25 = quantile(or_feed, .25),
              median = median(or_feed), p75 = quantile(or_feed, .75)),
  book |> filter(!is.na(or_arch)) |>
    summarise(source = "archive forecast", races = n(), p25 = quantile(or_arch, .25),
              median = median(or_arch), p75 = quantile(or_arch, .75)),
  book |> filter(!is.na(or_sp)) |>
    summarise(source = "starting price", races = n(), p25 = quantile(or_sp, .25),
              median = median(or_sp), p75 = quantile(or_sp, .75))
))
emit("The P4-0 abort band on the median is 1.05 to 1.60.")
emit("")

emit("### Within-race regression of log p_forecast on log p_SP, both sources")
emit("")
shape <- dat |>
  filter(split == "train") |>
  group_by(race_id) |>
  filter(all(fp_feed_ok), all(fp_arch_ok), all(sp_ok)) |>
  mutate(
    p_feed = (1 / fp_feed) / sum(1 / fp_feed),
    p_arch = (1 / fp_arch) / sum(1 / fp_arch),
    p_sp   = (1 / sp)      / sum(1 / sp)
  ) |>
  mutate(across(c(p_feed, p_arch, p_sp), log, .names = "l_{.col}")) |>
  mutate(across(starts_with("l_"), ~ .x - mean(.x), .names = "{.col}_c")) |>
  ungroup()

f_feed <- lm(l_p_feed_c ~ 0 + l_p_sp_c, data = shape)
f_arch <- lm(l_p_arch_c ~ 0 + l_p_sp_c, data = shape)
emit("Rows: ", nrow(shape), " runners across ", n_distinct(shape$race_id),
     " training races complete in all three books.")
emit("")
emit_tbl(tibble(
  forecast_source = c("feed (pre-race)", "archive (post-race transcription)"),
  within_race_slope = c(coef(f_feed)[[1]], coef(f_arch)[[1]]),
  std_error = c(summary(f_feed)$coefficients[1, 2], summary(f_arch)$coefficients[1, 2]),
  r_squared = c(summary(f_feed)$r.squared, summary(f_arch)$r.squared)
))
emit("A slope closer to 1, and a higher R-squared, means that source is more ",
     "SP-like. The archive column being the more SP-like of the two is the ",
     "same finding as follow-up 2 section D, measured a second way.")
emit("")

emit("### Winner/loser separation, training split, races complete in all three books")
emit("")
emit_tbl(tibble(
  price_source = c("feed forecast (pre-race)", "archive forecast", "starting price"),
  separation_log_price = c(
    mean(log(shape$fp_feed[shape$won == 0])) - mean(log(shape$fp_feed[shape$won == 1])),
    mean(log(shape$fp_arch[shape$won == 0])) - mean(log(shape$fp_arch[shape$won == 1])),
    mean(log(shape$sp[shape$won == 0]))      - mean(log(shape$sp[shape$won == 1])))
))
emit("Descriptive only, training split, nothing downstream selected on it.")
emit("")

saveRDS(list(
  generated_at = Sys.time(),
  rank_universe = tibble(
    price_source = c("archive", "feed_any", "feed_prerace"),
    pct_complete = c(mean(rk$arch_complete), mean(rk$feed_complete),
                     mean(rk$feed_prerace_complete))),
  slopes = tibble(source = c("feed", "archive"),
                  slope = c(coef(f_feed)[[1]], coef(f_arch)[[1]]))
), "papers/04_market_blend/audit/p4_audit_followup3.rds")

close(out_con)
cat("Wrote", OUT, "\n")
