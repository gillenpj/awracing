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

log_msg <- function(...) {
  cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " ", ..., "\n", sep = "")
  flush(stdout())
}

log_msg("Building training data (going features, interactions, GBT matrix)...")
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
log_msg("Training data ready: ", nrow(built$X), " rows, ", length(race_ids), " races.")

grid <- build_tuning_grid()
stopifnot(nrow(grid) == 72L)
log_msg("Grid: ", nrow(grid), " points x 5 folds = ", nrow(grid) * 5, " fits.")

# Resume support: skip grid points already checkpointed.
done <- NULL
if (file.exists(checkpoint_path)) {
  done <- readr::read_csv(checkpoint_path, show_col_types = FALSE)
  log_msg("Resuming: ", nrow(done), " grid points already checkpointed.")
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
    log_msg("Grid point ", i, "/", nrow(grid), " already done, skipping.")
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
    log_msg("Grid point ", i, "/", nrow(grid), ": ", nrow(result$divergence_events),
        " DIVERGENCE EVENT(S) logged (max_depth=", params$max_depth,
        " eta=", params$eta, " mcw=", params$min_child_weight,
        " subsample=", params$subsample, ") -- see ", divergence_path)
  }

  log_msg("Grid point ", i, "/", nrow(grid), " done in ", round(elapsed, 1),
      "s: max_depth=", params$max_depth, " eta=", params$eta,
      " mcw=", params$min_child_weight, " subsample=", params$subsample,
      " -> fold_mean_pl_r2=", round(summary_row$fold_mean_pl_r2, 5))
}

log_msg("Grid complete. Reading checkpoint for final selection...")
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
log_msg("Divergence events: ", nrow(all_divergence), " total, across ",
    n_grid_points_with_divergence, " of 72 grid points.")

selected_boundary <- selected$max_depth == 6L || selected$eta == 0.1
if (selected_boundary) {
  log_msg("*** FLAG: selected configuration sits on a grid boundary ",
      "(max_depth=", selected$max_depth, ", eta=", selected$eta,
      ") -- the optimum may lie outside the tested range. ***")
}

saveRDS(list(all_results = all_results, selected = selected,
             all_divergence = all_divergence,
             n_grid_points_with_divergence = n_grid_points_with_divergence,
             selected_boundary = selected_boundary),
        "gbt_tuning_final.rds")
log_msg("Stage D done. Selected: max_depth=", selected$max_depth, " eta=", selected$eta,
    " mcw=", selected$min_child_weight, " subsample=", selected$subsample,
    " colsample_bytree=", selected$colsample_bytree,
    " mean_best_iteration=", round(selected$mean_best_iteration, 1),
    " fold_mean_pl_r2=", round(selected$fold_mean_pl_r2, 5),
    " tie_break=", selected$tie_break)

# -----------------------------------------------------------------------
# Divergence table split by failure type (objective grad/hess floor vs
# eval non-finite pl_r2), reported before Stage E so a low-eta anomaly is
# visible even if Stage E fails.
# -----------------------------------------------------------------------
if (nrow(all_divergence) > 0L) {
  divergence_typed <- all_divergence |>
    dplyr::mutate(
      failure_type = dplyr::case_when(
        source == "objective" & n_grad_floored > 0L & n_hess_floored > 0L ~ "objective: grad+hess floored",
        source == "objective" & n_grad_floored > 0L ~ "objective: grad floored",
        source == "objective" & n_hess_floored > 0L ~ "objective: hess floored",
        source == "eval" & is.nan(raw_value) ~ "eval: NaN pl_r2",
        source == "eval" & is.infinite(raw_value) & raw_value > 0 ~ "eval: +Inf pl_r2",
        source == "eval" & is.infinite(raw_value) & raw_value < 0 ~ "eval: -Inf pl_r2",
        TRUE ~ paste0(source, ": other")
      )
    )
  type_counts <- divergence_typed |> dplyr::count(failure_type, sort = TRUE)
  log_msg("Divergence by failure type:")
  for (i in seq_len(nrow(type_counts))) {
    log_msg("  ", type_counts$failure_type[i], ": ", type_counts$n[i], " events")
  }

  low_eta_events <- divergence_typed |> dplyr::filter(eta == 0.01)
  if (nrow(low_eta_events) > 0L) {
    log_msg("*** FLAG: ", nrow(low_eta_events), " divergence event(s) at eta=0.01 ",
        "-- inspect before trusting the grid at scale. ***")
  }

  first_by_point <- divergence_typed |>
    dplyr::group_by(max_depth, eta, min_child_weight, subsample, colsample_bytree, fold) |>
    dplyr::summarise(first_round = min(round), n_events = dplyr::n(), .groups = "drop") |>
    dplyr::arrange(max_depth, eta, min_child_weight, subsample, fold)
  readr::write_csv(first_by_point, "gbt_tuning_divergence_by_point.csv")
  log_msg("Per-(grid point, fold) first-divergence-round table written to gbt_tuning_divergence_by_point.csv (",
      nrow(first_by_point), " rows).")
} else {
  log_msg("No divergence events logged across the seeded grid.")
}

# -----------------------------------------------------------------------
# Stage E: final fit at the selected hyperparameters on all training data,
# training pl_r2 (in-sample), gain + within-race permutation importance,
# and the paper 2b comparison. Test split is not touched anywhere here.
# -----------------------------------------------------------------------
log_msg("Stage E: fitting final model (max_depth=", selected$max_depth,
    " eta=", selected$eta, " mcw=", selected$min_child_weight,
    " subsample=", selected$subsample, " colsample_bytree=", selected$colsample_bytree,
    " nrounds=", round(selected$mean_best_iteration), ")...")

final_fit <- fit_final_model(built$X, built$y, rle(as.character(built$key$race_id))$lengths,
                              selected, k = 3L)
log_msg("Stage E final fit done: nrounds=", final_fit$nrounds,
    " train_pl_r2 (in-sample)=", round(final_fit$train_pl_r2, 5))

gain_importance <- xgboost::xgb.importance(model = final_fit$bst) |> tibble::as_tibble()
gain_importance$rank <- seq_len(nrow(gain_importance))
log_msg("Gain importance computed (in-sample decomposition of the fitted loss -- ",
    "answers whether the model USED a feature, not whether it helps out of sample).")

log_msg("Stage E: within-race permutation importance, training split, 30 repeats, seed 42...")
perm_importance <- permutation_importance_within_race(
  final_fit$bst, built$X, built$key$race_id,
  rle(as.character(built$key$race_id))$lengths,
  built$feature_names, k = 3L, n_repeats = 30L
)
log_msg("Permutation importance done.")

going_cols <- c("going_runs_prior", "going_sr_shrunk", "going_sr_delta", "going_ordinal")
going_in_gain <- tibble::tibble(Feature = going_cols) |>
  dplyr::left_join(dplyr::select(gain_importance, Feature, rank, Gain), by = "Feature")
going_in_perm <- perm_importance |> dplyr::filter(feature %in% going_cols) |>
  dplyr::select(feature, rank, mean_drop, sd_drop)
log_msg("Going features in gain-importance ranking (", nrow(gain_importance),
    " of ", length(built$feature_names), " total features actually split on):")
for (i in seq_len(nrow(going_in_gain))) {
  if (is.na(going_in_gain$rank[i])) {
    log_msg("  ", going_in_gain$Feature[i], ": NOT SPLIT ON (absent from xgb.importance(), no rank)")
  } else {
    log_msg("  ", going_in_gain$Feature[i], ": rank ", going_in_gain$rank[i],
        " (Gain=", round(going_in_gain$Gain[i], 6), ")")
  }
}
log_msg("Going features in permutation-importance ranking:")
for (i in seq_len(nrow(going_in_perm))) {
  log_msg("  ", going_in_perm$feature[i], ": rank ", going_in_perm$rank[i],
      " (mean_drop=", round(going_in_perm$mean_drop[i], 6),
      " sd_drop=", round(going_in_perm$sd_drop[i], 6), ")")
}

log_msg("Computing paper 2b's training pl_r2 (k=3) for direct comparison...")
model_2b_exploded_draw_final <- targets::tar_read(model_2b_exploded_draw_final)
exploded_interactions_data   <- targets::tar_read(exploded_interactions_data)
paper2b_train_pl_r2 <- paper2b_training_pl_r2(model_2b_exploded_draw_final, exploded_interactions_data)
log_msg("Paper 2b training pl_r2 (k=3): ", round(paper2b_train_pl_r2, 5),
    " | GBT training pl_r2 (in-sample, k=3): ", round(final_fit$train_pl_r2, 5))

saveRDS(
  list(
    all_results = all_results, selected = selected,
    all_divergence = all_divergence,
    n_grid_points_with_divergence = n_grid_points_with_divergence,
    selected_boundary = selected_boundary,
    final_nrounds = final_fit$nrounds,
    train_pl_r2 = final_fit$train_pl_r2,
    paper2b_train_pl_r2 = paper2b_train_pl_r2,
    gain_importance = gain_importance,
    perm_importance = perm_importance,
    going_in_gain = going_in_gain,
    going_in_perm = going_in_perm
  ),
  "gbt_tuning_final.rds"
)
xgboost::xgb.save(final_fit$bst, "gbt_final_model.xgb")

log_msg("ALL DONE. Selected: max_depth=", selected$max_depth, " eta=", selected$eta,
    " mcw=", selected$min_child_weight, " subsample=", selected$subsample,
    " colsample_bytree=", selected$colsample_bytree,
    " nrounds=", final_fit$nrounds,
    " fold_mean_pl_r2=", round(selected$fold_mean_pl_r2, 5),
    " tie_break=", selected$tie_break,
    " train_pl_r2=", round(final_fit$train_pl_r2, 5),
    " paper2b_train_pl_r2=", round(paper2b_train_pl_r2, 5))
