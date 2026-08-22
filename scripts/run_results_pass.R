# scripts/run_results_pass.R
# Paper-3 results pass (2026-08-22). THE ONLY TEST-SET CONTACT. Every
# modelling decision (feature set, hyperparameters, nrounds, the fitted
# gbt_final_model.xgb) is already fixed by the training-side tuning pass;
# nothing here feeds back into model selection.
#
# Stage A builds the GBT test predictions and gates on the race-universe
# check: if paper 3's test race set does not exactly match paper 2b's
# (not just the count -- the actual race_id set), this script stops with
# diagnostics rather than continuing into B-E, so a mismatch is caught in
# the one run rather than silently producing incomparable numbers.
#
# Run with:
#   "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" scripts/run_results_pass.R

source("renv/activate.R")
suppressPackageStartupMessages({
  library(targets)
  library(xgboost)
  library(dplyr)
})
source("R/pl_objective.R")
source("R/build_going_features.R")
source("R/build_extended_features.R")
source("R/model_fitting_p2.R")
source("R/gbt_data.R")
source("R/gbt_folds.R")
source("R/gbt_tuning.R")
source("R/scoring.R")
source("R/ranking_eval_p2b.R")
source("R/value_bets_p2b.R")

log_msg <- function(...) {
  cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " ", ..., "\n", sep = "")
  flush(stdout())
}

RACE_LEVEL_FEATS <- c("going_ordinal", "course_Kempton", "course_Lingfield",
                       "course_Southwell", "course_Wolverhampton")
HORSE_LEVEL_FEATS <- setdiff(FEATURE_COLS, RACE_LEVEL_FEATS)
stopifnot(length(HORSE_LEVEL_FEATS) == 19L, length(RACE_LEVEL_FEATS) == 5L)

# =============================================================================
# STAGE A: predictions
# =============================================================================
log_msg("==== STAGE A: building GBT test predictions ====")

qualifying_runners <- targets::tar_read(qualifying_runners)
qualifying_races   <- targets::tar_read(qualifying_races)
full_history        <- targets::tar_read(full_history)
runners_augmented   <- targets::tar_read(runners_augmented)
races_train         <- targets::tar_read(races_train)
gf <- build_going_features(qualifying_runners, qualifying_races, full_history)
ra_new  <- runners_augmented |> dplyr::left_join(gf, by = c("race_id", "runner_id"))
rmr_new <- build_model_ready(ra_new, qualifying_races, races_train)
ri_new  <- build_interaction_features(rmr_new, qualifying_races)

built_test <- build_gbt_matrix(ri_new, qualifying_runners, "test")
log_msg("Paper 3 test build: ", nrow(built_test$X), " rows, ",
    length(built_test$group_sizes), " races.")

test_predictions_2b <- targets::tar_read(test_predictions_2b)
ranking_eval_runners_2b <- targets::tar_read(ranking_eval_runners_2b)
p3_races  <- unique(built_test$key$race_id)
b2_races  <- unique(ranking_eval_runners_2b$race_id)
n_p3      <- length(p3_races)
n_2b      <- length(b2_races)
only_p3   <- setdiff(p3_races, b2_races)
only_2b   <- setdiff(b2_races, p3_races)

log_msg("Paper 3 test race count: ", n_p3)
log_msg("Paper 2b RANKING-universe test race count (ranking_eval_runners_2b, distinct race_id): ", n_2b)
log_msg("(Reference is 2b's ranking universe, not its 2193-race win-backtest universe",
    " test_predictions_2b -- a depth-3 model needs a clean top-3, exactly as",
    " prepare_exploded_data() requires, so this is the correct like-for-like reference.)")
log_msg("Races in paper 3 but not in 2b's ranking universe: ", length(only_p3))
log_msg("Races in 2b's ranking universe but not in paper 3: ", length(only_2b))

n_2b_win_universe <- dplyr::n_distinct(test_predictions_2b$race_id)
log_msg("For reference, 2b's WIN-BACKTEST universe (test_predictions_2b) has ",
    n_2b_win_universe, " races -- ", n_2b_win_universe - n_2b,
    " more than the ranking universe (the messy-top-3 races a depth-3 model cannot use).")

race_universe_ok <- (n_p3 == n_2b) && length(only_p3) == 0L && length(only_2b) == 0L

if (!race_universe_ok) {
  log_msg("*** STOP CONDITION: race universe mismatch between paper 3's test build",
      " and paper 2b's RANKING-universe test predictions. Halting before Stage B. ***")
  saveRDS(
    list(stopped_at = "Stage A", n_p3 = n_p3, n_2b = n_2b,
         only_p3 = only_p3, only_2b = only_2b),
    "results_pass_STOPPED.rds"
  )
  stop("Race universe mismatch -- see results_pass_STOPPED.rds and the log above.")
}
log_msg("Race universe check PASSED: paper 3's test race set is identical to",
    " paper 2b's test predictions' race set (", n_p3, " races).")

bst <- xgboost::xgb.load("gbt_final_model.xgb")
preds_test <- predict(bst, built_test$X, outputmargin = TRUE)

softmax_test <- pl_softmax_by_race(preds_test, built_test$key$race_id, built_test$key$runner_id)
psum <- softmax_test |> dplyr::group_by(race_id) |> dplyr::summarise(s = sum(p_win), .groups = "drop")
stopifnot(all(abs(psum$s - 1) < 1e-6))
log_msg("p_win sums to 1 within every race: PASSED (", nrow(psum), " races checked).")

test_predictions_p3 <- softmax_test |>
  dplyr::rename(win_model = p_win) |>
  dplyr::inner_join(
    test_predictions_2b |>
      dplyr::select(race_id, runner_id, horse_ref, won, win_market, starting_price_decimal),
    by = c("race_id", "runner_id")
  )
stopifnot(nrow(test_predictions_p3) == nrow(softmax_test))
log_msg("test_predictions_p3 assembled: ", nrow(test_predictions_p3), " runner-rows.",
    " (win_model from the GBT; won/win_market/starting_price_decimal joined from test_predictions_2b,",
    " since both share the identical race universe just verified.)")

# Cross-check: paper 3's own `won` (from build_gbt_matrix) against 2b's `won`
# (joined above), as an extra validity check the two independently-derived
# builds agree on outcomes for the same runners.
key_won <- built_test$key |> dplyr::mutate(y_p3 = built_test$y)
cross_check <- test_predictions_p3 |>
  dplyr::inner_join(key_won, by = c("race_id", "runner_id"))
stopifnot(all(cross_check$won == cross_check$y_p3))
log_msg("Cross-check: paper 3's own `won` matches 2b's `won` for every joined runner: PASSED.")

saveRDS(list(test_predictions_p3 = test_predictions_p3,
             built_test = built_test, race_universe_ok = TRUE,
             n_p3 = n_p3, n_2b = n_2b),
        "results_pass_stageA.rds")
log_msg("Stage A complete and saved.")

# =============================================================================
# STAGE B: Q1, ranking (test split)
# =============================================================================
log_msg("==== STAGE B: Q1 ranking metrics ====")

ranking_eval_runners_p3 <- build_ranking_eval_runners(test_predictions_p3, qualifying_runners)
ranking_metrics_p3 <- compute_ranking_metrics_2b(ranking_eval_runners_p3)
log_msg("Paper 3 ranking metrics computed.")
print(ranking_metrics_p3)

ranking_metrics_2b <- targets::tar_read(ranking_metrics_2b)
log_msg("Paper 2b ranking metrics (stored target, not refit):")
print(ranking_metrics_2b)

# Paper 2a has no stored ranking-metric target (P1_rank/Brier_place were
# introduced in 2b). Computed fresh here from 2a's OWN already-fitted test
# predictions (test_predictions_w_final) -- a pure evaluation of a fixed
# model on an existing metric, not a refit -- and labelled as such.
test_predictions_w_final <- targets::tar_read(test_predictions_w_final)
ranking_eval_runners_2a <- build_ranking_eval_runners(
  test_predictions_w_final |>
    dplyr::rename(win_model = predicted_prob, win_market = market_prob),
  qualifying_runners
)
ranking_metrics_2a <- compute_ranking_metrics_2b(ranking_eval_runners_2a)
log_msg("Paper 2a ranking metrics -- COMPUTED FRESH for this comparison,",
    " NOT part of 2a's original published results (2a never reported P1_rank/Brier_place):")
print(ranking_metrics_2a)

# Test-split McFadden pseudo-R^2 (k=3 PL objective), GBT vs 2b, out-of-sample
# counterpart to the training-side 0.092 vs 0.054 in-sample comparison.
test_pl_r2_p3 <- make_pl_eval(built_test$group_sizes, k = 3L)(preds_test, NULL)$value
log_msg("Paper 3 GBT test pl_r2 (k=3, out-of-sample): ", test_pl_r2_p3)

fp_lookup <- qualifying_runners |>
  dplyr::transmute(race_id, runner_id,
                    finish_pos = dplyr::coalesce(amended_position, finish_position))
ordered_2b_test <- test_predictions_2b |>
  dplyr::filter(!is.na(win_model), win_model > 0) |>
  dplyr::left_join(fp_lookup, by = c("race_id", "runner_id")) |>
  arrange_for_xgb()
group_sizes_2b_test <- rle(as.character(ordered_2b_test$race_id))$lengths
stopifnot(sum(group_sizes_2b_test) == nrow(ordered_2b_test))
z_2b_test <- log(ordered_2b_test$win_model)  # monotonic transform of p_win; the
  # race-constant additive shift this introduces on the z scale cancels
  # exactly in pl_denom()'s per-race max-subtraction, so this is an exact
  # (not approximate) way to get 2b's implied z from its win probabilities.
test_pl_r2_2b <- make_pl_eval(group_sizes_2b_test, k = 3L)(z_2b_test, NULL)$value
log_msg("Paper 2b test pl_r2 (k=3, out-of-sample, derived from win_model via log()): ", test_pl_r2_2b)

saveRDS(list(ranking_metrics_p3 = ranking_metrics_p3,
             ranking_metrics_2b = ranking_metrics_2b,
             ranking_metrics_2a = ranking_metrics_2a,
             test_pl_r2_p3 = test_pl_r2_p3, test_pl_r2_2b = test_pl_r2_2b),
        "results_pass_stageB.rds")
log_msg("Stage B complete and saved.")

# =============================================================================
# STAGE C: Q2, win-picking (test split)
# =============================================================================
log_msg("==== STAGE C: Q2 win-picking backtest ====")
log_msg("Universe note: paper 3 runs on its 2183-race ranking-compatible universe.",
    " 2a/2b's PUBLISHED naive-backtest figures run on their own, larger win-only",
    " universes. Reporting three columns per model: published (own universe),",
    " restricted (recomputed on paper 3's 2183 races, same stored predictions,",
    " no refit), and paper 3 (2183). The restricted column is the like-for-like",
    " comparison; published is shown so a reader can see whether restriction",
    " changed anything.")

model_market_ratio_p3_win <- compute_model_market_ratio_p2(
  test_predictions_p3 |>
    dplyr::rename(predicted_prob = win_model, market_prob = win_market)
)
backtest_naive_p3_win <- run_backtest(model_market_ratio_p3_win,
                                       prob_threshold = 0.15, ratio_threshold = 1.3)
log_msg("Paper 3 naive win backtest (prob>0.15, ratio>1.3), 2183 races:")
print(backtest_naive_p3_win)

backtest_naive_2b_win <- targets::tar_read(backtest_naive_2b_win)
backtest_naive_w_final <- targets::tar_read(backtest_naive_w_final)
model_market_ratio_2b_win <- targets::tar_read(model_market_ratio_2b_win)
model_market_ratio_w_final <- targets::tar_read(model_market_ratio_w_final)

backtest_naive_2b_win_restricted <- run_backtest(
  model_market_ratio_2b_win |> dplyr::filter(race_id %in% p3_races),
  prob_threshold = 0.15, ratio_threshold = 1.3
)
backtest_naive_w_final_restricted <- run_backtest(
  model_market_ratio_w_final |> dplyr::filter(race_id %in% p3_races),
  prob_threshold = 0.15, ratio_threshold = 1.3
)

log_msg("Paper 2b naive win backtest -- PUBLISHED (", n_2b_win_universe, " races, stored target):")
print(backtest_naive_2b_win)
log_msg("Paper 2b naive win backtest -- RESTRICTED to paper 3's 2183 races (recomputed, no refit):")
print(backtest_naive_2b_win_restricted)
log_msg("Paper 2a naive win backtest -- PUBLISHED (stored target, backtest_naive_w_final):")
print(backtest_naive_w_final)
log_msg("Paper 2a naive win backtest -- RESTRICTED to paper 3's 2183 races (recomputed, no refit):")
print(backtest_naive_w_final_restricted)

roi_diff_p3_vs_2b <- bootstrap_roi_difference(model_market_ratio_p3_win, model_market_ratio_2b_win) |>
  dplyr::mutate(contrast = "paper 3 GBT - paper 2b exploded logit", .before = 1)
roi_diff_p3_vs_2a <- bootstrap_roi_difference(model_market_ratio_p3_win, model_market_ratio_w_final) |>
  dplyr::mutate(contrast = "paper 3 GBT - paper 2a win model", .before = 1)
log_msg("Paired race-level ROI bootstrap, GBT vs 2b (bootstrap intersects automatically;",
    " n_common races used, from the bootstrap's own output, reported below):")
print(roi_diff_p3_vs_2b)
log_msg("Paired race-level ROI bootstrap, GBT vs 2a (n_common races used, reported below):")
print(roi_diff_p3_vs_2a)

saveRDS(list(backtest_naive_p3_win = backtest_naive_p3_win,
             backtest_naive_2b_win = backtest_naive_2b_win,
             backtest_naive_2b_win_restricted = backtest_naive_2b_win_restricted,
             backtest_naive_w_final = backtest_naive_w_final,
             backtest_naive_w_final_restricted = backtest_naive_w_final_restricted,
             roi_diff_p3_vs_2b = roi_diff_p3_vs_2b,
             roi_diff_p3_vs_2a = roi_diff_p3_vs_2a),
        "results_pass_stageC.rds")
log_msg("Stage C complete and saved.")

# =============================================================================
# STAGE D: Q3, betting value (test split), single-bet primary
# =============================================================================
log_msg("==== STAGE D: Q3 betting value, single-bet-per-race ====")

value_bet_runners_p3 <- build_value_bet_runners(test_predictions_p3, qualifying_runners)
value_bets_place_p3   <- build_place_value_bets(value_bet_runners_p3)
value_bets_eachway_p3 <- build_eachway_value_bets(value_bet_runners_p3)

backtest_single_win_p3     <- run_single_win_backtest(model_market_ratio_p3_win)
backtest_single_place_p3   <- run_single_settled_backtest(model_market_ratio_p3_win, value_bets_place_p3)
backtest_single_eachway_p3 <- run_single_settled_backtest(model_market_ratio_p3_win, value_bets_eachway_p3)

log_msg("Paper 3 single-bet win:"); print(backtest_single_win_p3)
log_msg("Paper 3 single-bet place:"); print(backtest_single_place_p3)
log_msg("Paper 3 single-bet each-way:"); print(backtest_single_eachway_p3)

backtest_single_win_2b     <- targets::tar_read(backtest_single_win_2b)
backtest_single_place_2b   <- targets::tar_read(backtest_single_place_2b)
backtest_single_eachway_2b <- targets::tar_read(backtest_single_eachway_2b)
backtest_single_win_2a     <- targets::tar_read(backtest_single_win_2a)
value_bets_place_2b        <- targets::tar_read(value_bets_place_2b)
value_bets_eachway_2b      <- targets::tar_read(value_bets_eachway_2b)

log_msg("Paper 2b single-bet win/place/each-way -- PUBLISHED (own universe, stored targets):")
print(backtest_single_win_2b); print(backtest_single_place_2b); print(backtest_single_eachway_2b)
log_msg("Paper 2a single-bet win -- PUBLISHED (stored target, backtest_single_win_2a):")
print(backtest_single_win_2a)

backtest_single_win_2b_restricted <- run_single_win_backtest(
  model_market_ratio_2b_win |> dplyr::filter(race_id %in% p3_races)
)
backtest_single_place_2b_restricted <- run_single_settled_backtest(
  model_market_ratio_2b_win |> dplyr::filter(race_id %in% p3_races),
  value_bets_place_2b |> dplyr::filter(race_id %in% p3_races)
)
backtest_single_eachway_2b_restricted <- run_single_settled_backtest(
  model_market_ratio_2b_win |> dplyr::filter(race_id %in% p3_races),
  value_bets_eachway_2b |> dplyr::filter(race_id %in% p3_races)
)
backtest_single_win_2a_restricted <- run_single_win_backtest(
  model_market_ratio_w_final |> dplyr::filter(race_id %in% p3_races)
)
log_msg("Paper 2b single-bet win/place/each-way -- RESTRICTED to paper 3's 2183 races (recomputed, no refit):")
print(backtest_single_win_2b_restricted); print(backtest_single_place_2b_restricted); print(backtest_single_eachway_2b_restricted)
log_msg("Paper 2a single-bet win -- RESTRICTED to paper 3's 2183 races (recomputed, no refit):")
print(backtest_single_win_2a_restricted)

sweep_single_win_p3     <- run_single_sweep(model_market_ratio_p3_win)
sweep_single_place_p3   <- run_single_sweep(model_market_ratio_p3_win, value_bets_place_p3)
sweep_single_eachway_p3 <- run_single_sweep(model_market_ratio_p3_win, value_bets_eachway_p3)

saveRDS(list(
  backtest_single_win_p3 = backtest_single_win_p3,
  backtest_single_place_p3 = backtest_single_place_p3,
  backtest_single_eachway_p3 = backtest_single_eachway_p3,
  backtest_single_win_2b = backtest_single_win_2b,
  backtest_single_place_2b = backtest_single_place_2b,
  backtest_single_eachway_2b = backtest_single_eachway_2b,
  backtest_single_win_2a = backtest_single_win_2a,
  backtest_single_win_2b_restricted = backtest_single_win_2b_restricted,
  backtest_single_place_2b_restricted = backtest_single_place_2b_restricted,
  backtest_single_eachway_2b_restricted = backtest_single_eachway_2b_restricted,
  backtest_single_win_2a_restricted = backtest_single_win_2a_restricted,
  sweep_single_win_p3 = sweep_single_win_p3,
  sweep_single_place_p3 = sweep_single_place_p3,
  sweep_single_eachway_p3 = sweep_single_eachway_p3
), "results_pass_stageD.rds")
log_msg("Stage D complete and saved.")

# =============================================================================
# STAGE E: out-of-sample permutation importance (test split), both variants
# =============================================================================
log_msg("==== STAGE E: out-of-sample permutation importance ====")

perm_within_test <- permutation_importance_within_race(
  bst, built_test$X, built_test$key$race_id, built_test$group_sizes,
  HORSE_LEVEL_FEATS, k = 3L, n_repeats = 30L
)
log_msg("Within-race (horse-level, 19 features) permutation importance, test split:")
print(perm_within_test, n = 19)

perm_across_test <- permutation_importance_across_races(
  bst, built_test$X, built_test$key$race_id, built_test$group_sizes,
  RACE_LEVEL_FEATS, k = 3L, n_repeats = 30L
)
log_msg("Across-race (race-level, 5 features) permutation importance, test split:")
print(perm_across_test)

going_in_within_test <- perm_within_test |> dplyr::filter(feature %in% c("going_runs_prior","going_sr_shrunk","going_sr_delta"))
going_in_across_test <- perm_across_test |> dplyr::filter(feature == "going_ordinal")
log_msg("Going features, within-race test-split ranks:"); print(going_in_within_test)
log_msg("going_ordinal, across-race test-split rank:"); print(going_in_across_test)

saveRDS(list(perm_within_test = perm_within_test, perm_across_test = perm_across_test),
        "results_pass_stageE.rds")
log_msg("Stage E complete and saved.")

log_msg("ALL DONE. Results pass complete -- this was the only test-set contact.")
