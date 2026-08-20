# scripts/run_gbt_tuning.R
# Paper-3 GBT hyperparameter tuning driver. Training races only (5,022
# complete-case races, per R/gbt_data.R) -- the test split is never
# touched. Runs the 72-point grid (R/gbt_tuning.R::build_tuning_grid())
# x 5-fold CV, checkpointing each grid point's result to
# gbt_tuning_checkpoint.csv as it completes, so a crash mid-run does not
# cost the whole grid: re-running this script skips grid points already
# present in the checkpoint file.
#
# Run via PowerShell (native xgboost calls), detached:
#   Start-Process Rscript.exe -ArgumentList "scripts/run_gbt_tuning.R" ...
# Estimated wall-clock ~6.5-8 hours (fallback ladder step 1 applied,
# CLAUDE.md "Tuning grid budget" -- projected under the 12-hour bar).

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

checkpoint_path   <- "gbt_tuning_checkpoint.csv"
divergence_path   <- "gbt_tuning_divergence.csv"  # one row per floored event, see R/gbt_tuning.R
key_path          <- "gbt_tuning_key.rds"   # so Stage D can reuse the exact same data

log <- function(...) {
  cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " ", ..., "\n", sep = "")
  flush(stdout())
}

log("Building training data (going features, interactions, GBT matrix)...")
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

saveRDS(list(feature_names = built$feature_names, folds = folds), key_path)
log("Training data ready: ", nrow(built$X), " rows, ", length(race_ids), " races.")

grid <- build_tuning_grid()
stopifnot(nrow(grid) == 72L)
log("Grid: ", nrow(grid), " points x 5 folds = ", nrow(grid) * 5, " fits.")

# Resume support: skip grid points already checkpointed.
done <- NULL
if (file.exists(checkpoint_path)) {
  done <- readr::read_csv(checkpoint_path, show_col_types = FALSE)
  log("Resuming: ", nrow(done), " grid points already checkpointed.")
}

for (i in seq_len(nrow(grid))) {
  params <- as.list(grid[i, ])

  already_done <- FALSE
  if (!is.null(done) && nrow(done) > 0) {
    match_row <- done |>
      dplyr::filter(
        max_depth == params$max_depth, eta == params$eta,
        min_child_weight == params$min_child_weight,
        subsample == params$subsample, colsample_bytree == params$colsample_bytree
      )
    already_done <- nrow(match_row) > 0
  }
  if (already_done) {
    log("Grid point ", i, "/", nrow(grid), " already done, skipping.")
    next
  }

  t0 <- Sys.time()
  result <- run_grid_point(built$X, built$y, built$key, folds, params = params, k = 3L)
  elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  summary_row <- result$summary
  summary_row$elapsed_secs <- elapsed

  readr::write_csv(summary_row, checkpoint_path, append = file.exists(checkpoint_path))

  if (nrow(result$divergence_events) > 0L) {
    readr::write_csv(result$divergence_events, divergence_path,
                      append = file.exists(divergence_path))
    log("Grid point ", i, "/", nrow(grid), ": ", nrow(result$divergence_events),
        " DIVERGENCE EVENT(S) logged (max_depth=", params$max_depth,
        " eta=", params$eta, " mcw=", params$min_child_weight,
        " subsample=", params$subsample, ") -- see ", divergence_path)
  }

  log("Grid point ", i, "/", nrow(grid), " done in ", round(elapsed, 1),
      "s: max_depth=", params$max_depth, " eta=", params$eta,
      " mcw=", params$min_child_weight, " subsample=", params$subsample,
      " -> fold_mean_pl_r2=", round(summary_row$fold_mean_pl_r2, 5))
}

log("Grid complete. Reading checkpoint for final selection...")
all_results <- readr::read_csv(checkpoint_path, show_col_types = FALSE)
stopifnot(nrow(all_results) == 72L)
selected <- select_best_config(all_results)

all_divergence <- if (file.exists(divergence_path)) {
  readr::read_csv(divergence_path, show_col_types = FALSE)
} else {
  tibble::tibble()
}
n_grid_points_with_divergence <- if (nrow(all_divergence) > 0L) {
  dplyr::n_distinct(all_divergence[, c("max_depth", "eta", "min_child_weight",
                                        "subsample", "colsample_bytree")])
} else 0L
log("Divergence events: ", nrow(all_divergence), " total, across ",
    n_grid_points_with_divergence, " of 72 grid points.")

selected_boundary <- selected$max_depth == 6L || selected$eta == 0.1
if (selected_boundary) {
  log("*** FLAG: selected configuration sits on a grid boundary ",
      "(max_depth=", selected$max_depth, ", eta=", selected$eta,
      ") -- the optimum may lie outside the tested range. ***")
}

saveRDS(list(all_results = all_results, selected = selected,
             all_divergence = all_divergence,
             n_grid_points_with_divergence = n_grid_points_with_divergence,
             selected_boundary = selected_boundary),
        "gbt_tuning_final.rds")
log("DONE. Selected: max_depth=", selected$max_depth, " eta=", selected$eta,
    " mcw=", selected$min_child_weight, " subsample=", selected$subsample,
    " colsample_bytree=", selected$colsample_bytree,
    " mean_best_iteration=", round(selected$mean_best_iteration, 1),
    " fold_mean_pl_r2=", round(selected$fold_mean_pl_r2, 5),
    " tie_break=", selected$tie_break)
