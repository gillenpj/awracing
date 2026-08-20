# scripts/diagnose_eta01_divergence.R
# One-off diagnostic (2026-08-20): is the complete divergence of all 6
# max_depth=2, eta=0.01 grid points (see gbt_tuning_checkpoint.csv) caused
# by xgb.train()'s multi-threaded histogram building defeating the
# set.seed(42L) fix (R's RNG is seeded, but threaded floating-point
# summation order is not deterministic across runs), or is it a genuine
# numerical fragility of the PL objective at this hyperparameter corner
# (shallow trees, very slow learning)?
#
# Runs run_grid_point() three times for the single worst-offending point
# (max_depth=2, eta=0.01, min_child_weight=1, subsample=0.7,
# colsample_bytree=0.7):
#   run A: nthread = 1
#   run B: nthread = 1   (repeat, to test determinism)
#   run C: nthread = detectCores() (the default fit_one_fold() has been
#          using all along -- to confirm the divergence still reproduces
#          under the same conditions as the real run before concluding
#          anything)
#
# Run with:
#   "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" scripts/diagnose_eta01_divergence.R

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

log <- function(...) {
  cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " ", ..., "\n", sep = "")
  flush(stdout())
}

log("Building training data (same as scripts/run_gbt_tuning.R)...")
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
stopifnot(nrow(built$key) == length(built$y), length(race_ids) == 5022L)
log("Training data ready: ", nrow(built$X), " rows, ", length(race_ids), " races.")

params <- list(max_depth = 2L, eta = 0.01, min_child_weight = 1L,
                subsample = 0.7, colsample_bytree = 0.7)
n_cores <- parallel::detectCores()
log("detectCores() on this machine: ", n_cores)

summarise_run <- function(label, result, elapsed) {
  s <- result$summary
  n_div <- nrow(result$divergence_events)
  log(sprintf(
    "%s: elapsed=%.1fs fold_mean_pl_r2=%s fold_r2=[%s] n_divergence_events=%d",
    label, elapsed, format(s$fold_mean_pl_r2, digits = 10),
    paste(round(c(s$fold_r2_1, s$fold_r2_2, s$fold_r2_3, s$fold_r2_4, s$fold_r2_5), 6),
          collapse = ", "),
    n_div
  ))
  s
}

log("==== Run A: nthread = 1 ====")
t0 <- Sys.time()
res_a <- run_grid_point(built$X, built$y, built$key, folds, params = params, k = 3L, nthread = 1L)
sum_a <- summarise_run("Run A (nthread=1)", res_a, as.numeric(difftime(Sys.time(), t0, units = "secs")))

log("==== Run B: nthread = 1 (repeat) ====")
t0 <- Sys.time()
res_b <- run_grid_point(built$X, built$y, built$key, folds, params = params, k = 3L, nthread = 1L)
sum_b <- summarise_run("Run B (nthread=1)", res_b, as.numeric(difftime(Sys.time(), t0, units = "secs")))

log("==== Run C: nthread = detectCores() = ", n_cores, " (the default fit_one_fold() has been using) ====")
t0 <- Sys.time()
res_c <- run_grid_point(built$X, built$y, built$key, folds, params = params, k = 3L, nthread = n_cores)
sum_c <- summarise_run(paste0("Run C (nthread=", n_cores, ")"), res_c, as.numeric(difftime(Sys.time(), t0, units = "secs")))

log("==== Summary ====")
log("A vs B identical fold_mean_pl_r2: ", identical(sum_a$fold_mean_pl_r2, sum_b$fold_mean_pl_r2))
log("A vs B identical per-fold r2:     ",
    identical(c(sum_a$fold_r2_1, sum_a$fold_r2_2, sum_a$fold_r2_3, sum_a$fold_r2_4, sum_a$fold_r2_5),
              c(sum_b$fold_r2_1, sum_b$fold_r2_2, sum_b$fold_r2_3, sum_b$fold_r2_4, sum_b$fold_r2_5)))
log("A/B diverged (sentinel -1e10)?    ", sum_a$fold_mean_pl_r2 <= -1e9, " / ", sum_b$fold_mean_pl_r2 <= -1e9)
log("C diverged (sentinel -1e10)?      ", sum_c$fold_mean_pl_r2 <= -1e9)

saveRDS(list(params = params, n_cores = n_cores,
             run_a = res_a, run_b = res_b, run_c = res_c),
        "gbt_diagnose_eta01_result.rds")
log("Saved gbt_diagnose_eta01_result.rds. DONE.")
