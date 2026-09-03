# verify_p4_market_probs.R
#
# Standing gate on paper 4's market-probability construction.
#
# P4-1 requires the same proportional overround adjustment the series
# already applies to SP (paper 1 §5.1), NOT a second implementation of
# it. That adjustment lives inline inside
# `R/scoring.R::build_test_predictions()`; paper 4 needs it as a callable
# function, so `R/market_blend_p4.R::normalise_overround()` states it
# once. This script is the proof that the two are the same arithmetic:
# it rebuilds `win_market` from raw starting prices using the paper-4
# helper and asserts it reproduces the stored column of
# `test_predictions_3` to floating-point tolerance.
#
# Run after any change to `normalise_overround()` or to
# `build_test_predictions()`:
#   "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" scripts/verify_p4_market_probs.R
#
# Read-only: reads the main `_targets` store and the database, writes
# nothing.

source("renv/activate.R")
suppressPackageStartupMessages({
  library(dplyr)
})
source("R/db.R")
source("R/market_blend_p4.R")

cat("verify_p4_market_probs: start\n")

preds_3 <- targets::tar_read(test_predictions_3)
race_ids <- sort(unique(preds_3$race_id))

# ---- 1. The helper reproduces the stored SP market probabilities --------
rebuilt <- preds_3 |>
  select(race_id, runner_id, starting_price_decimal, win_market) |>
  group_by(race_id) |>
  mutate(win_market_rebuilt = normalise_overround(starting_price_decimal)) |>
  ungroup()

stopifnot(
  "normalise_overround() left NAs where the stored column has none" =
    sum(is.na(rebuilt$win_market_rebuilt)) == sum(is.na(rebuilt$win_market))
)

max_abs_diff <- max(abs(rebuilt$win_market_rebuilt - rebuilt$win_market),
                    na.rm = TRUE)
cat(sprintf("  [1] max |rebuilt - stored| over %d runner-rows: %.3e\n",
            nrow(rebuilt), max_abs_diff))
stopifnot(
  "normalise_overround() does not reproduce build_test_predictions()'s market_prob" =
    max_abs_diff < 1e-12
)

# ---- 2. Probabilities sum to one within every race ----------------------
race_sums <- rebuilt |>
  group_by(race_id) |>
  summarise(s = sum(win_market_rebuilt), .groups = "drop")
cat(sprintf("  [2] race probability sums in [%.15f, %.15f]\n",
            min(race_sums$s), max(race_sums$s)))
stopifnot(
  "market probabilities do not sum to 1 within race" =
    max(abs(race_sums$s - 1)) < 1e-12
)

# ---- 3. The helper is scale-invariant in the overround ------------------
# Doubling every price in a race must leave the normalised probabilities
# unchanged: the construction removes the book's margin, whatever it is.
one_race <- rebuilt |> filter(race_id == race_ids[1])
stopifnot(
  "normalise_overround() is not invariant to a uniform rescaling of prices" =
    max(abs(normalise_overround(one_race$starting_price_decimal * 2) -
            normalise_overround(one_race$starting_price_decimal))) < 1e-14
)
cat("  [3] uniform price rescaling leaves probabilities unchanged\n")

# ---- 4. The DB pull agrees with the stored prices -----------------------
# Paper 4 re-pulls SP from the database rather than trusting the stored
# column; assert the two agree before anything is fitted on the pull.
raw <- read_p4_price_sources(race_ids)
joined <- preds_3 |>
  select(race_id, runner_id, sp_stored = starting_price_decimal) |>
  inner_join(raw |> select(race_id, runner_id, sp), by = c("race_id", "runner_id"))

stopifnot(
  "the SP pull does not cover every stored runner-row" =
    nrow(joined) == nrow(preds_3)
)
max_sp_diff <- max(abs(joined$sp - joined$sp_stored), na.rm = TRUE)
cat(sprintf("  [4] max |SP pulled - SP stored| over %d rows: %.3e\n",
            nrow(joined), max_sp_diff))
stopifnot(
  "the freshly pulled SP disagrees with the stored SP" = max_sp_diff < 1e-9
)

# ---- 5. The DB pull does not fan out ------------------------------------
# `daily_runners` must hold at most one row per (runner_id, race_id), or
# the LEFT JOIN in read_p4_price_sources() would duplicate runner-rows.
stopifnot(
  "read_p4_price_sources() returned duplicate (race_id, runner_id) rows" =
    nrow(raw) == nrow(distinct(raw, race_id, runner_id))
)
cat(sprintf("  [5] price pull is one row per runner-race (%d rows)\n", nrow(raw)))

cat("verify_p4_market_probs: ALL CHECKS PASSED\n")
