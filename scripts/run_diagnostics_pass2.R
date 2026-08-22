# scripts/run_diagnostics_pass2.R
# Paper-3 pre-drafting diagnostics (2026-08-22). All test-side and
# descriptive except item 2 (an explicitly-authorized training-side
# diagnostic fit, depth-1, that does NOT enter model selection). No
# refits feed back into the selected model; all reported numbers are
# read-only characterisation for the drafting pass.
#
# Run with:
#   "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" scripts/run_diagnostics_pass2.R

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

log_msg("Loading cached inputs and rebuilding test features (identical to results pass)...")
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
bst <- xgboost::xgb.load("gbt_final_model.xgb")
preds_test <- predict(bst, built_test$X, outputmargin = TRUE)

stageA <- readRDS("results_pass_stageA.rds")
test_predictions_p3 <- stageA$test_predictions_p3
test_predictions_2b <- targets::tar_read(test_predictions_2b)

# 2b's implied z on the test split: log(win_model) is exact up to a
# race-constant shift (see CLAUDE.md / Stage B of the results pass),
# which within-race centering removes anyway.
fp_lookup <- qualifying_runners |>
  dplyr::transmute(race_id, runner_id,
                    finish_pos = dplyr::coalesce(amended_position, finish_position))
ordered_2b_test <- test_predictions_2b |>
  dplyr::filter(!is.na(win_model), win_model > 0) |>
  dplyr::left_join(fp_lookup, by = c("race_id", "runner_id")) |>
  arrange_for_xgb() |>
  dplyr::filter(race_id %in% unique(built_test$key$race_id))
z_2b_test <- log(ordered_2b_test$win_model)

# =============================================================================
# ITEM 1: score agreement between GBT and 2b, test split
# =============================================================================
log_msg("==== ITEM 1: score agreement, GBT vs paper 2b, test split ====")

p3_df <- tibble::tibble(
  race_id = built_test$key$race_id, runner_id = built_test$key$runner_id, z_p3 = preds_test
)
p2b_df <- tibble::tibble(
  race_id = ordered_2b_test$race_id, runner_id = ordered_2b_test$runner_id, z_2b = z_2b_test
)
agree <- dplyr::inner_join(p3_df, p2b_df, by = c("race_id", "runner_id"))
stopifnot(nrow(agree) == nrow(p3_df))  # both built on the identical 2183-race universe

agree <- agree |>
  dplyr::group_by(race_id) |>
  dplyr::mutate(
    zc_p3  = z_p3  - mean(z_p3),
    zc_2b  = z_2b  - mean(z_2b),
    rank_p3  = rank(-z_p3,  ties.method = "first"),
    rank_2b  = rank(-z_2b,  ties.method = "first")
  ) |>
  dplyr::ungroup()

pearson_r  <- cor(agree$zc_p3, agree$zc_2b, method = "pearson")
spearman_r <- cor(agree$zc_p3, agree$zc_2b, method = "spearman")
log_msg("Pearson r (within-race-centred z):  ", round(pearson_r, 4))
log_msg("Spearman r (within-race-centred z): ", round(spearman_r, 4))

top_pick <- agree |>
  dplyr::group_by(race_id) |>
  dplyr::summarise(
    top_p3 = runner_id[which.max(z_p3)],
    top_2b = runner_id[which.max(z_2b)],
    .groups = "drop"
  ) |>
  dplyr::mutate(same_top = top_p3 == top_2b)
share_same_top <- mean(top_pick$same_top)
log_msg("Share of races where GBT and 2b pick the same top horse: ", round(share_same_top, 4),
    " (", sum(top_pick$same_top), " of ", nrow(top_pick), ")")

mad_rank <- mean(abs(agree$rank_p3 - agree$rank_2b))
log_msg("Mean absolute difference in within-race rank: ", round(mad_rank, 4))

saveRDS(list(pearson_r = pearson_r, spearman_r = spearman_r,
             share_same_top = share_same_top, n_races = nrow(top_pick),
             mad_rank = mad_rank, top_pick = top_pick, agree = agree),
        "diag2_item1.rds")
log_msg("Item 1 complete and saved.")

# =============================================================================
# ITEM 2: depth-1 diagnostic fit (does NOT enter selection)
# =============================================================================
log_msg("==== ITEM 2: depth-1 diagnostic fit (stumps, additive by construction) ====")

built_train <- build_gbt_matrix(ri_new, qualifying_runners, "train")
race_ids_train <- unique(built_train$key$race_id)
folds <- make_race_folds(race_ids_train, v = 5, seed = 42)

depth1_params <- list(max_depth = 1L, eta = 0.03, min_child_weight = 1L,
                       subsample = 0.7, colsample_bytree = 0.7)
log_msg("Running 5-fold CV for the depth-1 diagnostic point (same folds, same other hyperparameters as the selected model)...")
t0 <- Sys.time()
depth1_cv <- run_grid_point(built_train$X, built_train$y, built_train$key, folds,
                             params = depth1_params, k = 3L)
log_msg("Depth-1 CV elapsed: ", round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1), "s")
print(depth1_cv$summary)

depth1_selected <- depth1_cv$summary
final_depth1 <- fit_final_model(built_train$X, built_train$y,
                                 rle(as.character(built_train$key$race_id))$lengths,
                                 depth1_selected, k = 3L)
log_msg("Depth-1 final fit: nrounds=", final_depth1$nrounds,
    " train_pl_r2 (in-sample)=", final_depth1$train_pl_r2)

preds_test_d1 <- predict(final_depth1$bst, built_test$X, outputmargin = TRUE)
test_pl_r2_d1 <- make_pl_eval(built_test$group_sizes, k = 3L)(preds_test_d1, NULL)$value

softmax_test_d1 <- pl_softmax_by_race(preds_test_d1, built_test$key$race_id, built_test$key$runner_id)
test_predictions_d1 <- softmax_test_d1 |>
  dplyr::rename(win_model = p_win) |>
  dplyr::inner_join(
    test_predictions_2b |> dplyr::select(race_id, runner_id, horse_ref, won, win_market, starting_price_decimal),
    by = c("race_id", "runner_id")
  )
stopifnot(nrow(test_predictions_d1) == nrow(softmax_test_d1))

ranking_eval_runners_d1 <- build_ranking_eval_runners(test_predictions_d1, qualifying_runners)
ranking_metrics_d1 <- compute_ranking_metrics_2b(ranking_eval_runners_d1)
log_msg("Depth-1 diagnostic test ranking metrics (DIAGNOSTIC ONLY, not a candidate model):")
print(ranking_metrics_d1)
log_msg("Depth-1 test pl_r2 (k=3): ", test_pl_r2_d1)

stageB <- readRDS("results_pass_stageB.rds")
log_msg("For comparison, depth-3 (selected) test ranking metrics and pl_r2:")
print(stageB$ranking_metrics_p3)
log_msg("Depth-3 test pl_r2: ", stageB$test_pl_r2_p3)

saveRDS(list(depth1_cv_summary = depth1_cv$summary,
             depth1_nrounds = final_depth1$nrounds,
             depth1_train_pl_r2 = final_depth1$train_pl_r2,
             ranking_metrics_d1 = ranking_metrics_d1,
             test_pl_r2_d1 = test_pl_r2_d1),
        "diag2_item2.rds")
log_msg("Item 2 complete and saved.")

# =============================================================================
# ITEM 3: partial dependence, depth-3 model, test split
# =============================================================================
log_msg("==== ITEM 3: partial dependence (or_relative, going_sr_delta, stall_normalised) ====")

compute_pdp <- function(bst, X, feature, n_grid = 25) {
  vals <- X[, feature]
  grid <- stats::quantile(vals, probs = seq(0, 1, length.out = n_grid), na.rm = TRUE, names = FALSE)
  grid <- unique(grid)
  purrr::map_dfr(grid, function(v) {
    Xg <- X
    Xg[, feature] <- v
    preds <- predict(bst, Xg, outputmargin = TRUE)
    tibble::tibble(feature = feature, value = v, mean_z = mean(preds))
  })
}

pdp_or_relative       <- compute_pdp(bst, built_test$X, "or_relative")
pdp_going_sr_delta    <- compute_pdp(bst, built_test$X, "going_sr_delta")
pdp_stall_normalised  <- compute_pdp(bst, built_test$X, "stall_normalised")

log_msg("PDP or_relative:"); print(pdp_or_relative, n = 30)
log_msg("PDP going_sr_delta:"); print(pdp_going_sr_delta, n = 30)
log_msg("PDP stall_normalised:"); print(pdp_stall_normalised, n = 30)

saveRDS(list(pdp_or_relative = pdp_or_relative,
             pdp_going_sr_delta = pdp_going_sr_delta,
             pdp_stall_normalised = pdp_stall_normalised),
        "diag2_item3.rds")
log_msg("Item 3 complete and saved.")

# =============================================================================
# ITEM 4: why the ROI gap -- disagreement-set analysis
# =============================================================================
log_msg("==== ITEM 4: disagreement-set analysis (SP, win rate) ====")

sp_lookup <- test_predictions_2b |> dplyr::select(race_id, runner_id, starting_price_decimal)

pick_p3 <- agree |>
  dplyr::group_by(race_id) |>
  dplyr::slice_max(z_p3, n = 1, with_ties = FALSE) |>
  dplyr::ungroup() |>
  dplyr::select(race_id, runner_id) |>
  dplyr::left_join(sp_lookup, by = c("race_id", "runner_id")) |>
  dplyr::left_join(test_predictions_2b |> dplyr::select(race_id, runner_id, won), by = c("race_id","runner_id")) |>
  dplyr::rename(sp_p3 = starting_price_decimal, won_p3 = won)

pick_2b <- agree |>
  dplyr::group_by(race_id) |>
  dplyr::slice_max(z_2b, n = 1, with_ties = FALSE) |>
  dplyr::ungroup() |>
  dplyr::select(race_id, runner_id) |>
  dplyr::left_join(sp_lookup, by = c("race_id", "runner_id")) |>
  dplyr::left_join(test_predictions_2b |> dplyr::select(race_id, runner_id, won), by = c("race_id","runner_id")) |>
  dplyr::rename(sp_2b = starting_price_decimal, won_2b = won)

picks <- dplyr::inner_join(pick_p3, pick_2b, by = "race_id", suffix = c("_p3", "_2b")) |>
  dplyr::mutate(disagree = runner_id_p3 != runner_id_2b)

n_disagree <- sum(picks$disagree)
log_msg("Races where GBT and 2b pick a different top horse: ", n_disagree, " of ", nrow(picks),
    " (", round(mean(picks$disagree), 4), ")")

dis <- picks |> dplyr::filter(disagree)
win_rate_p3_dis <- mean(dis$won_p3 == 1L, na.rm = TRUE)
win_rate_2b_dis <- mean(dis$won_2b == 1L, na.rm = TRUE)
log_msg("Within disagreement set -- GBT pick win rate: ", round(win_rate_p3_dis, 4),
    "  2b pick win rate: ", round(win_rate_2b_dis, 4))

sp_summary <- tibble::tibble(
  model    = c("GBT (overall)", "2b (overall)", "GBT (disagreement set)", "2b (disagreement set)"),
  mean_sp  = c(mean(picks$sp_p3, na.rm = TRUE), mean(picks$sp_2b, na.rm = TRUE),
               mean(dis$sp_p3, na.rm = TRUE),   mean(dis$sp_2b, na.rm = TRUE)),
  median_sp = c(median(picks$sp_p3, na.rm = TRUE), median(picks$sp_2b, na.rm = TRUE),
                median(dis$sp_p3, na.rm = TRUE),   median(dis$sp_2b, na.rm = TRUE))
)
log_msg("SP summary, GBT vs 2b, overall and within the disagreement set:")
print(sp_summary)

saveRDS(list(n_disagree = n_disagree, n_total = nrow(picks),
             win_rate_p3_dis = win_rate_p3_dis, win_rate_2b_dis = win_rate_2b_dis,
             sp_summary = sp_summary, picks = picks),
        "diag2_item4.rds")
log_msg("Item 4 complete and saved.")

# =============================================================================
# ITEM 5: attenuation check -- confirm like-for-like, train vs test
# =============================================================================
log_msg("==== ITEM 5: across-race permutation, train vs test, like-for-like check ====")

RACE_LEVEL_FEATS <- c("going_ordinal", "course_Kempton", "course_Lingfield",
                       "course_Southwell", "course_Wolverhampton")

perm_across_train <- permutation_importance_across_races(
  bst, built_train$X, built_train$key$race_id,
  rle(as.character(built_train$key$race_id))$lengths,
  RACE_LEVEL_FEATS, k = 3L, n_repeats = 30L
)
stageE <- readRDS("results_pass_stageE.rds")
perm_across_test <- stageE$perm_across_test

log_msg("Same function (permutation_importance_across_races), same n_repeats=30, same seed=42",
    " (set inside the function each call); only the split (train vs test matrix/group_sizes/race_id) differs.")
log_msg("Training-side (recomputed just now, same model, for exact side-by-side):")
print(perm_across_train)
log_msg("Test-side (from the results pass, Stage E):")
print(perm_across_test)

side_by_side <- dplyr::full_join(
  perm_across_train |> dplyr::select(feature, train_mean_drop = mean_drop, train_sd_drop = sd_drop),
  perm_across_test  |> dplyr::select(feature, test_mean_drop = mean_drop, test_sd_drop = sd_drop),
  by = "feature"
) |> dplyr::arrange(dplyr::desc(train_mean_drop))
log_msg("Side by side:")
print(side_by_side)

saveRDS(list(perm_across_train = perm_across_train, perm_across_test = perm_across_test,
             side_by_side = side_by_side),
        "diag2_item5.rds")
log_msg("Item 5 complete and saved.")

log_msg("ALL DONE.")
