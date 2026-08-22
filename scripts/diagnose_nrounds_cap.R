# scripts/diagnose_nrounds_cap.R
# One-off diagnostic (2026-08-22), results-pass gap #1: for the 72-point
# grid's 4 points with mean_best_iteration >= 1900 (near the nrounds=2000
# cap), report each fold's individual best_iteration -- the checkpoint only
# stores the fold MEAN, not per-fold values, so this re-runs just those 4
# points (deterministic given the seed fix, so it reproduces the original
# run's fold_mean_pl_r2 exactly) to check whether any fold hit exactly 2000
# without early stopping ever triggering (truncated, understated score) or
# whether all folds stopped short of the cap on their own (converged).
# Training split only; the test split is not touched.
#
# Run with:
#   "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" scripts/diagnose_nrounds_cap.R

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

log_msg <- function(...) {
  cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " ", ..., "\n", sep = "")
  flush(stdout())
}

log_msg("Building training data (identical to scripts/run_gbt_tuning.R)...")
qualifying_runners <- targets::tar_read(qualifying_runners)
qualifying_races   <- targets::tar_read(qualifying_races)
full_history        <- targets::tar_read(full_history)
runners_augmented   <- targets::tar_read(runners_augmented)
races_train         <- targets::tar_read(races_train)

gf <- build_going_features(qualifying_runners, qualifying_races, full_history)
ra_new  <- runners_augmented |> dplyr::left_join(gf, by = c("race_id", "runner_id"))
rmr_new <- build_model_ready(ra_new, qualifying_races, races_train)
ri_new  <- build_interaction_features(rmr_new, qualifying_races)

built <- build_gbt_matrix(ri_new, qualifying_runners, "train")
race_ids <- unique(built$key$race_id)
folds <- make_race_folds(race_ids, v = 5, seed = 42)
log_msg("Training data ready.")

near_cap_points <- list(
  list(max_depth = 2L, eta = 0.01, min_child_weight = 1L,  subsample = 0.7, colsample_bytree = 0.7),
  list(max_depth = 2L, eta = 0.01, min_child_weight = 5L,  subsample = 0.7, colsample_bytree = 0.7),
  list(max_depth = 2L, eta = 0.01, min_child_weight = 20L, subsample = 0.7, colsample_bytree = 0.7),
  list(max_depth = 3L, eta = 0.01, min_child_weight = 1L,  subsample = 0.7, colsample_bytree = 0.7)
)

for (params in near_cap_points) {
  log_msg("==== depth=", params$max_depth, " eta=", params$eta,
      " mcw=", params$min_child_weight, " sub=", params$subsample, " ====")
  v <- max(folds$fold)
  fold_iters <- integer(v)
  fold_r2s   <- numeric(v)
  for (f in seq_len(v)) {
    val_race_ids <- folds$race_id[folds$fold == f]
    train_idx <- which(!(built$key$race_id %in% val_race_ids))
    val_idx   <- which(built$key$race_id %in% val_race_ids)
    train_group <- rle(as.character(built$key$race_id[train_idx]))$lengths
    val_group   <- rle(as.character(built$key$race_id[val_idx]))$lengths

    res <- fit_one_fold(
      built$X[train_idx, ], built$y[train_idx], train_group,
      built$X[val_idx, ],   built$y[val_idx],   val_group,
      params = params, k = 3L
    )
    fold_iters[f] <- res$best_iteration
    fold_r2s[f]   <- res$best_pl_r2
    log_msg("  fold=", f, " best_iteration=", res$best_iteration,
        " AT_CAP=", res$best_iteration >= 2000L,
        " best_pl_r2=", round(res$best_pl_r2, 5))
  }
  log_msg("  fold_mean_pl_r2=", round(mean(fold_r2s), 5),
      " mean_best_iteration=", round(mean(fold_iters), 1),
      " n_folds_at_cap=", sum(fold_iters >= 2000L), " of ", v)
}
log_msg("DONE.")
