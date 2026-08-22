# scripts/run_diagnostics_pass3.R
# Paper-3 pre-drafting diagnostics, round 3 (2026-08-22): paired race-level
# bootstrap intervals on the test ranking metrics (P1_rank, Brier_place,
# test pl_r2), and on the disagreement-set win-rate / SP differences.
# Test-side only; the depth-1 fit's ALREADY-KNOWN nrounds (1795, from
# diag2_item2.rds) is reused directly -- only the cheap final refit is
# redone, not the expensive 5-fold CV. Depth-1 remains a diagnostic; its
# test numbers were already seen in the prior pass, so it cannot become a
# candidate model (see CLAUDE.md).
#
# Run with:
#   "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" scripts/run_diagnostics_pass3.R

source("renv/activate.R")
suppressPackageStartupMessages({
  library(targets); library(xgboost); library(dplyr)
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

log_msg("Rebuilding data (identical to prior passes)...")
qualifying_runners <- targets::tar_read(qualifying_runners)
qualifying_races   <- targets::tar_read(qualifying_races)
full_history        <- targets::tar_read(full_history)
runners_augmented   <- targets::tar_read(runners_augmented)
races_train         <- targets::tar_read(races_train)
gf <- build_going_features(qualifying_runners, qualifying_races, full_history)
ra_new  <- runners_augmented |> dplyr::left_join(gf, by = c("race_id", "runner_id"))
rmr_new <- build_model_ready(ra_new, qualifying_races, races_train)
ri_new  <- build_interaction_features(rmr_new, qualifying_races)

built_test  <- build_gbt_matrix(ri_new, qualifying_runners, "test")
built_train <- build_gbt_matrix(ri_new, qualifying_runners, "train")

bst_d3 <- xgboost::xgb.load("gbt_final_model.xgb")
preds_test_d3 <- predict(bst_d3, built_test$X, outputmargin = TRUE)

test_predictions_2b <- targets::tar_read(test_predictions_2b)

# --- Depth-1 diagnostic: reuse the ALREADY-KNOWN nrounds (1795), redo only
# the cheap final refit, not the expensive CV. -------------------------------
diag2 <- readRDS("diag2_item2.rds")
log_msg("Depth-1: refitting at the already-known nrounds=", diag2$depth1_nrounds,
    " (CV not re-run).")
depth1_selected <- tibble::tibble(
  max_depth = 1L, eta = 0.03, min_child_weight = 1L,
  subsample = 0.7, colsample_bytree = 0.7,
  mean_best_iteration = diag2$depth1_nrounds
)
final_depth1 <- fit_final_model(built_train$X, built_train$y,
                                 rle(as.character(built_train$key$race_id))$lengths,
                                 depth1_selected, k = 3L)
stopifnot(abs(final_depth1$train_pl_r2 - diag2$depth1_train_pl_r2) < 1e-9)
log_msg("Depth-1 refit reproduced train_pl_r2 exactly: ", final_depth1$train_pl_r2)
preds_test_d1 <- predict(final_depth1$bst, built_test$X, outputmargin = TRUE)

# =============================================================================
# Build per-race contributions for all three models, aligned on race_id
# =============================================================================
log_msg("==== Building per-race contributions (P1_rank, Brier_place, pl_r2) ====")

fp_lookup <- qualifying_runners |>
  dplyr::transmute(race_id, runner_id,
                    finish_pos = dplyr::coalesce(amended_position, finish_position))

# Depth-3 GBT
softmax_d3 <- pl_softmax_by_race(preds_test_d3, built_test$key$race_id, built_test$key$runner_id)
tp_d3 <- softmax_d3 |> dplyr::rename(win_model = p_win) |>
  dplyr::inner_join(test_predictions_2b |> dplyr::select(race_id, runner_id, horse_ref, won, win_market, starting_price_decimal),
                     by = c("race_id", "runner_id"))
rer_d3 <- build_ranking_eval_runners(tp_d3, qualifying_runners)

# Depth-1 GBT (diagnostic)
softmax_d1 <- pl_softmax_by_race(preds_test_d1, built_test$key$race_id, built_test$key$runner_id)
tp_d1 <- softmax_d1 |> dplyr::rename(win_model = p_win) |>
  dplyr::inner_join(test_predictions_2b |> dplyr::select(race_id, runner_id, horse_ref, won, win_market, starting_price_decimal),
                     by = c("race_id", "runner_id"))
rer_d1 <- build_ranking_eval_runners(tp_d1, qualifying_runners)

# Paper 2b
rer_2b <- targets::tar_read(ranking_eval_runners_2b)

n_d3 <- dplyr::n_distinct(rer_d3$race_id); n_d1 <- dplyr::n_distinct(rer_d1$race_id); n_2b <- dplyr::n_distinct(rer_2b$race_id)
log_msg("Scorable race counts -- depth-3: ", n_d3, "  depth-1: ", n_d1, "  2b: ", n_2b)
common_races <- Reduce(intersect, list(unique(rer_d3$race_id), unique(rer_d1$race_id), unique(rer_2b$race_id)))
log_msg("Common scorable race set across all three: ", length(common_races))

# --- Per-race P1_rank ingredient: order_prob (pure PL/Harville, alpha=1) ----
order_prob_for <- function(rer) {
  rer |> dplyr::filter(race_id %in% common_races) |>
    dplyr::transmute(race_id, win_prob = win_model, finish_pos) |>
    compute_pl_order_probs(alpha_2nd = 1, alpha_3rd = 1)
}
op_d3 <- order_prob_for(rer_d3) |> dplyr::rename(order_prob_d3 = order_prob)
op_d1 <- order_prob_for(rer_d1) |> dplyr::rename(order_prob_d1 = order_prob)
op_2b <- order_prob_for(rer_2b) |> dplyr::rename(order_prob_2b = order_prob)

# --- Per-race Brier_place ingredients: SSE and n_r (pure Harville place, alpha=1) ---
brier_ingredients_for <- function(rer) {
  pp <- compute_harville_place_probs(
    rer |> dplyr::transmute(race_id, horse_ref, market_prob = win_model),
    alpha_2nd = 1, alpha_3rd = 1
  )
  rer |> dplyr::left_join(pp, by = c("race_id", "horse_ref")) |>
    dplyr::group_by(race_id) |>
    dplyr::summarise(sse = sum((placed - harville_place_prob)^2), n_r = dplyr::n(), .groups = "drop")
}
br_d3 <- brier_ingredients_for(rer_d3) |> dplyr::rename(sse_d3 = sse, n_d3 = n_r)
br_d1 <- brier_ingredients_for(rer_d1) |> dplyr::rename(sse_d1 = sse, n_d1 = n_r)
br_2b <- brier_ingredients_for(rer_2b) |> dplyr::rename(sse_2b = sse, n_2b = n_r)

# --- Per-race pl_r2 ingredients: ll (log-lik) and nll (null log-lik) -------
pl_race_contributions <- function(z, group_sizes, race_ids_ordered, k = 3L) {
  d <- pl_denom(z, group_sizes, k)
  stage_term <- ifelse(d$pos <= d$S, d$zc - base::log(d$denom), 0)
  ll_by_race <- as.numeric(tapply(stage_term, d$race, sum))
  J <- group_sizes; S <- pmin(k, J - 1L)
  nll_by_race <- vapply(seq_along(J), function(i) {
    j <- J[i]; s <- S[i]
    if (s < 1L) return(0)
    -sum(base::log(j - (seq_len(s) - 1L)))
  }, numeric(1))
  tibble::tibble(race_id = race_ids_ordered, ll = ll_by_race, nll = nll_by_race)
}

rle_d3 <- rle(as.character(built_test$key$race_id))
pc_d3 <- pl_race_contributions(preds_test_d3, rle_d3$lengths, as.integer(rle_d3$values)) |>
  dplyr::rename(ll_d3 = ll, nll_d3 = nll)
pc_d1 <- pl_race_contributions(preds_test_d1, rle_d3$lengths, as.integer(rle_d3$values)) |>
  dplyr::rename(ll_d1 = ll, nll_d1 = nll)

fp_2b <- qualifying_runners |>
  dplyr::transmute(race_id, runner_id, finish_pos = dplyr::coalesce(amended_position, finish_position))
ordered_2b_test <- test_predictions_2b |>
  dplyr::filter(!is.na(win_model), win_model > 0, race_id %in% common_races) |>
  dplyr::left_join(fp_2b, by = c("race_id", "runner_id")) |>
  arrange_for_xgb()
rle_2b <- rle(as.character(ordered_2b_test$race_id))
z_2b <- log(ordered_2b_test$win_model)
pc_2b <- pl_race_contributions(z_2b, rle_2b$lengths, as.integer(rle_2b$values)) |>
  dplyr::rename(ll_2b = ll, nll_2b = nll)

# --- Join everything on the common race set --------------------------------
per_race <- tibble::tibble(race_id = common_races) |>
  dplyr::left_join(op_d3, by = "race_id") |> dplyr::left_join(op_d1, by = "race_id") |> dplyr::left_join(op_2b, by = "race_id") |>
  dplyr::left_join(br_d3, by = "race_id") |> dplyr::left_join(br_d1, by = "race_id") |> dplyr::left_join(br_2b, by = "race_id") |>
  dplyr::left_join(pc_d3, by = "race_id") |> dplyr::left_join(pc_d1, by = "race_id") |> dplyr::left_join(pc_2b, by = "race_id")
per_race <- per_race |> tidyr::drop_na()
log_msg("Aligned per-race table: ", nrow(per_race), " races (after dropping any race missing an ingredient for any model).")

saveRDS(per_race, "diag3_per_race.rds")

# =============================================================================
# ITEM 1: paired race-level bootstrap, B=2000, seed=42
# =============================================================================
log_msg("==== ITEM 1: paired race-level bootstrap on P1_rank, Brier_place, test pl_r2 ====")

paired_boot <- function(per_race, suffix_a, suffix_b, label, n_boot = 2000L, seed = 42L) {
  n <- nrow(per_race)
  op_a <- per_race[[paste0("order_prob_", suffix_a)]]; op_b <- per_race[[paste0("order_prob_", suffix_b)]]
  sse_a <- per_race[[paste0("sse_", suffix_a)]]; nr_a <- per_race[[paste0("n_", suffix_a)]]
  sse_b <- per_race[[paste0("sse_", suffix_b)]]; nr_b <- per_race[[paste0("n_", suffix_b)]]
  ll_a <- per_race[[paste0("ll_", suffix_a)]]; nll_a <- per_race[[paste0("nll_", suffix_a)]]
  ll_b <- per_race[[paste0("ll_", suffix_b)]]; nll_b <- per_race[[paste0("nll_", suffix_b)]]

  p1_a_point <- exp(mean(log(op_a))); p1_b_point <- exp(mean(log(op_b)))
  brier_a_point <- sum(sse_a) / sum(nr_a); brier_b_point <- sum(sse_b) / sum(nr_b)
  plr2_a_point <- 1 - sum(ll_a) / sum(nll_a); plr2_b_point <- 1 - sum(ll_b) / sum(nll_b)

  set.seed(seed)
  diffs <- matrix(NA_real_, nrow = n_boot, ncol = 3)
  for (b in seq_len(n_boot)) {
    idx <- sample.int(n, n, replace = TRUE)
    p1_a <- exp(mean(log(op_a[idx]))); p1_b <- exp(mean(log(op_b[idx])))
    br_a <- sum(sse_a[idx]) / sum(nr_a[idx]); br_b <- sum(sse_b[idx]) / sum(nr_b[idx])
    pl_a <- 1 - sum(ll_a[idx]) / sum(nll_a[idx]); pl_b <- 1 - sum(ll_b[idx]) / sum(nll_b[idx])
    diffs[b, ] <- c(p1_a - p1_b, br_a - br_b, pl_a - pl_b)
  }
  tibble::tibble(
    contrast = label,
    metric = c("P1_rank", "Brier_place", "test_pl_r2"),
    point_a = c(p1_a_point, brier_a_point, plr2_a_point),
    point_b = c(p1_b_point, brier_b_point, plr2_b_point),
    diff_point = c(p1_a_point - p1_b_point, brier_a_point - brier_b_point, plr2_a_point - plr2_b_point),
    ci_lo = apply(diffs, 2, stats::quantile, probs = 0.05, names = FALSE),
    ci_hi = apply(diffs, 2, stats::quantile, probs = 0.95, names = FALSE),
    n_races = n, n_boot = n_boot
  )
}

boot_d3_vs_2b <- paired_boot(per_race, "d3", "2b", "depth-3 (selected) - paper 2b")
boot_d3_vs_d1 <- paired_boot(per_race, "d3", "d1", "depth-3 (selected) - depth-1 (diagnostic)")

log_msg("Paired bootstrap, depth-3 vs paper 2b:")
print(boot_d3_vs_2b)
log_msg("Paired bootstrap, depth-3 vs depth-1 (THE ONE THE PAPER TURNS ON):")
print(boot_d3_vs_d1)

saveRDS(list(boot_d3_vs_2b = boot_d3_vs_2b, boot_d3_vs_d1 = boot_d3_vs_d1),
        "diag3_item1.rds")
log_msg("Item 1 complete and saved.")

# =============================================================================
# ITEM 2: interval on the disagreement-set win-rate / SP differences
# =============================================================================
log_msg("==== ITEM 2: bootstrap on the disagreement-set win-rate and SP differences ====")

diag2_item4 <- readRDS("diag2_item4.rds")
dis <- diag2_item4$picks |> dplyr::filter(disagree)
n_dis <- nrow(dis)
log_msg("Disagreement set size: ", n_dis)

set.seed(42L)
n_boot <- 2000L
boot_winrate_diff <- numeric(n_boot)
boot_sp_diff <- numeric(n_boot)
won_p3 <- as.numeric(dis$won_p3 == 1L); won_2b <- as.numeric(dis$won_2b == 1L)
sp_p3 <- dis$sp_p3; sp_2b <- dis$sp_2b
for (b in seq_len(n_boot)) {
  idx <- sample.int(n_dis, n_dis, replace = TRUE)
  boot_winrate_diff[b] <- mean(won_p3[idx]) - mean(won_2b[idx])
  boot_sp_diff[b] <- mean(sp_p3[idx], na.rm = TRUE) - mean(sp_2b[idx], na.rm = TRUE)
}
winrate_diff_point <- mean(won_p3) - mean(won_2b)
sp_diff_point <- mean(sp_p3, na.rm = TRUE) - mean(sp_2b, na.rm = TRUE)

winrate_ci <- stats::quantile(boot_winrate_diff, c(0.05, 0.95), names = FALSE)
sp_ci <- stats::quantile(boot_sp_diff, c(0.05, 0.95), names = FALSE)

log_msg("Win-rate difference (GBT - 2b), disagreement set: point=", round(winrate_diff_point, 4),
    " 90% CI [", round(winrate_ci[1], 4), ", ", round(winrate_ci[2], 4), "]")
log_msg("Mean SP difference (GBT - 2b), disagreement set: point=", round(sp_diff_point, 4),
    " 90% CI [", round(sp_ci[1], 4), ", ", round(sp_ci[2], 4), "]")

saveRDS(list(winrate_diff_point = winrate_diff_point, winrate_ci = winrate_ci,
             sp_diff_point = sp_diff_point, sp_ci = sp_ci, n_dis = n_dis),
        "diag3_item2.rds")
log_msg("Item 2 complete and saved.")

log_msg("ALL DONE.")
