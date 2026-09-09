# scripts/verify_p6_ledger.R
# STANDING GATE on paper 6's betting ledger (`R/p6_ledger.R`).
#
# Paper 6 replaces the series' hard-wired backtest with a ledger that takes
# the selection and staking rules as arguments. If that generalisation changed
# any arithmetic, every number in the paper would be measured against a
# comparator it no longer reproduces. So the first thing the ledger does is
# rebuild paper 5's published test backtest and match it to the printed digit.
#
# Six assertions:
#   1-3. Under S1/K0 and paper 5's each-way terms, the ledger reproduces the
#        encoder rows of paper 5 Table 16 exactly — bets, wins, profit and ROI
#        for win, place and each-way.
#     4. `p6_eachway_returns()` under `terms = "paper5"` reproduces
#        `build_eachway_value_bets()`'s real-SP and fair-book returns exactly,
#        so the corrected-terms table is a generalisation of paper 5's payout
#        rather than a second implementation of it.
#     5. The corrected terms differ from paper 5's on exactly the races the
#        place-terms ladder says they should, and nowhere else.
#     6. Staking is neutral where it should be: S1/K0 and S1/K1 select the
#        same races, so a staking rule changes stakes and not the bet set.
#
# Read-only: it opens no database connection, acquires no `{targets}` lock and
# writes nothing. Run after any change to `R/p6_ledger.R` or `R/p6_rules.R`:
#   "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" scripts/verify_p6_ledger.R

source("renv/activate.R")
suppressMessages({
  library(dplyr)
  library(targets)
})

for (f in c("R/scoring.R", "R/value_bets_p2b.R", "R/model_fitting_p2.R",
            "R/p6_ledger.R", "R/p6_rules.R")) source(f)

P5_STORE   <- "_targets_p5"
MAIN_STORE <- "_targets"

pred        <- tar_read(p5_test_predictions, store = P5_STORE)$rung3b
qr          <- tar_read(p5_qualifying_runners, store = P5_STORE)
p5_backtest <- tar_read(p5_test_backtests, store = P5_STORE)
race_dates  <- tar_read(runners_interactions, store = MAIN_STORE) |>
  distinct(race_id, race_date)

frame  <- p6_build_bet_frame(pred, qr, race_dates)
settle <- p6_settlement_tables(frame, pred, qr)
sels   <- p6_selection_rules(p6_thresholds(frame))
stks   <- p6_staking_rules()

# -- 1-3. Paper 5 Table 16, encoder rows ------------------------------------

want <- p5_backtest |>
  filter(arm == "rung3b") |>
  select(bet, n_bets, n_wins, profit, roi)

got <- purrr::imap(c(win = "win", place = "place", eachway = "eachway"),
                   function(tbl, nm) {
                     led <- p6_ledger(frame, settle, sels$S1$fn, stks$K0$fn, tbl)
                     mutate(p6_summarise_ledger(led), bet = nm, .before = 1)
                   }) |> purrr::list_rbind()

cmp <- got |>
  select(bet, n_bets, n_wins, profit, roi) |>
  left_join(want, by = "bet", suffix = c("_p6", "_p5"))

cat("Paper 5 Table 16, rebuilt through p6_ledger() under S1/K0:\n")
print(as.data.frame(cmp), digits = 8)

stopifnot(
  nrow(cmp) == 3L,
  all(cmp$n_bets_p6 == cmp$n_bets_p5),
  all(cmp$n_wins_p6 == cmp$n_wins_p5),
  max(abs(cmp$profit_p6 - cmp$profit_p5)) < 1e-9,
  max(abs(cmp$roi_p6 - cmp$roi_p5)) < 1e-12
)

# The published figures themselves, not just internal agreement: a change to
# the paper-5 store that moved them would otherwise pass silently.
published <- tibble::tibble(
  bet = c("win", "place", "eachway"),
  n_bets = c(1064L, 1064L, 1064L),
  n_wins = c(131L, 475L, 475L),
  profit = c(-129.75, -108.51, -126.83),
  roi = c(-0.1219, -0.1020, -0.0596)
)
chk <- cmp |> left_join(published, by = "bet", suffix = c("", "_pub"))
stopifnot(
  all(chk$n_bets_p6 == chk$n_bets),
  all(chk$n_wins_p6 == chk$n_wins),
  max(abs(chk$profit_p6 - chk$profit)) < 0.005,
  max(abs(chk$roi_p6 - chk$roi)) < 0.00005
)
cat("\n[1-3] OK: win / place / each-way reproduce paper 5's printed digits.\n")

# -- 4. The corrected-terms function generalises paper 5's payout -----------

vbr    <- build_value_bet_runners(pred, qr)
p5_ew  <- build_eachway_value_bets(vbr) |>
  select(race_id, horse_ref, stake, ret, ret_fair) |>
  arrange(race_id, horse_ref)
p6_ew  <- p6_eachway_returns(frame, "paper5") |>
  inner_join(select(p5_ew, race_id, horse_ref), by = c("race_id", "horse_ref")) |>
  arrange(race_id, horse_ref)

stopifnot(
  nrow(p5_ew) == nrow(p6_ew),
  identical(p5_ew$race_id, p6_ew$race_id),
  identical(p5_ew$horse_ref, p6_ew$horse_ref),
  all(p6_ew$stake_mult == p5_ew$stake),
  max(abs(p6_ew$ret_unit - p5_ew$ret)) < 1e-12,
  max(abs(p6_ew$ret_unit_fair - p5_ew$ret_fair)) < 1e-12
)
cat(sprintf(
  "[4] OK: p6_eachway_returns(terms = 'paper5') reproduces build_eachway_value_bets() on %s rows (max |diff| %.2e).\n",
  format(nrow(p6_ew), big.mark = ","),
  max(abs(p6_ew$ret_unit - p5_ew$ret))
))

# -- 5. The corrected terms move exactly the races the ladder says ----------

terms <- p6_place_terms(frame$field_size)
should_differ <- !(terms$n_places == 3L &
                     !is.na(terms$place_fraction) &
                     abs(terms$place_fraction - 1 / 5) < 1e-12)

corr <- p6_eachway_returns(frame, "corrected")
flat <- p6_eachway_returns(frame, "paper5")
differs <- abs(corr$ret_unit - flat$ret_unit) > 1e-12 |
  corr$stake_mult != flat$stake_mult

stopifnot(all(differs <= should_differ))  # nothing moves that should not
cat(sprintf(
  "[5] OK: corrected terms differ on %s of %s rows, all inside the %s rows the ladder marks (field size 4-7 or 12+).\n",
  format(sum(differs), big.mark = ","), format(nrow(frame), big.mark = ","),
  format(sum(should_differ), big.mark = ",")
))

# -- 6. A staking rule changes stakes, not the bet set ---------------------

led_k0 <- p6_ledger(frame, settle, sels$S1$fn, stks$K0$fn, "win")
led_k1 <- p6_ledger(frame, settle, sels$S1$fn, stks$K1$fn, "win")
led_k2 <- p6_ledger(frame, settle, sels$S1$fn, stks$K2$fn, "win")
stopifnot(
  identical(led_k0$race_id, led_k1$race_id),
  identical(led_k0$race_id, led_k2$race_id),
  identical(led_k0$runner_id, led_k1$runner_id),
  all(led_k0$stake == 1)
)
cat(sprintf(
  "[6] OK: K0 / K1 / K2 select the identical %s races under S1; mean stakes %.3f / %.3f / %.3f.\n",
  format(nrow(led_k0), big.mark = ","),
  mean(led_k0$stake), mean(led_k1$stake), mean(led_k2$stake)
))

cat("\nAll paper-6 ledger assertions passed.\n")
