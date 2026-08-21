# scripts/diagnose_pl_root_cause.R
# One-off diagnostic (2026-08-20), coordinator-directed follow-up to
# scripts/diagnose_eta01_divergence.R (which ruled out threading: nthread=1
# reproduces the identical 100%-divergence result bit-for-bit).
#
# Four checks, in order:
#  (1) Selection-effect check: one point at eta=0.1, max_depth=3,
#      min_child_weight=5, subsample=0.7, colsample_bytree=0.7, ONE fold
#      only. Does it diverge too, or is eta=0.01 special?
#  (2) [done separately from gbt_tuning_divergence.csv -- all 1530 events
#      are source="eval", round 1..51, zero source="objective" events.]
#  (3a) Group-size / row-order integrity check on the diverging point's
#       fold split: group sizes sum to fold row count, groups contiguous,
#       first S rows of each group are the race's actual top-S finishers.
#  (3b) Round-1 internals: instrument obj_fn/eval_fn to record z/e/denom
#       range and NaN/Inf counts each round; dump the first tree's
#       per-leaf Cover (summed Hessian) and leaf Value via
#       xgb.model.dt.tree() after nrounds=1.
#
# Run with:
#   "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" scripts/diagnose_pl_root_cause.R

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

log_msg("Building training data (same as scripts/run_gbt_tuning.R)...")
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
log_msg("Training data ready: ", nrow(built$X), " rows, ", length(race_ids), " races.")

# ---------------------------------------------------------------------------
# (1) Selection-effect check
# ---------------------------------------------------------------------------
log_msg("==== (1) Selection-effect check: eta=0.1, max_depth=3, mcw=5, fold 1 only ====")

f <- 1L
val_race_ids <- folds$race_id[folds$fold == f]
train_idx <- which(!(built$key$race_id %in% val_race_ids))
val_idx   <- which(built$key$race_id %in% val_race_ids)
train_group <- rle(as.character(built$key$race_id[train_idx]))$lengths
val_group   <- rle(as.character(built$key$race_id[val_idx]))$lengths

params_sel <- list(max_depth = 3L, eta = 0.1, min_child_weight = 5L,
                     subsample = 0.7, colsample_bytree = 0.7)
t0 <- Sys.time()
res_sel <- fit_one_fold(
  built$X[train_idx, ], built$y[train_idx], train_group,
  built$X[val_idx, ],   built$y[val_idx],   val_group,
  params = params_sel, k = 3L
)
elapsed_sel <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
log_msg(sprintf(
  "Selection check: elapsed=%.1fs best_iteration=%d best_pl_r2=%s n_divergence_events=%d",
  elapsed_sel, res_sel$best_iteration, format(res_sel$best_pl_r2, digits = 10),
  nrow(res_sel$divergence_events)
))
log_msg("Selection check DIVERGED (sentinel)? ", res_sel$best_pl_r2 <= -1e9)
if (nrow(res_sel$divergence_events) > 0L) {
  log_msg("Selection check divergence rounds: ",
      paste(res_sel$divergence_events$round, collapse = ", "))
}

# ---------------------------------------------------------------------------
# (3a) Group-size / row-order integrity check on the diverging point's fold
#      split -- reuses the SAME train_idx/val_idx construction
#      run_grid_point()/fit_one_fold() use, for the diverging point
#      (max_depth=2, eta=0.01, min_child_weight=1, subsample=0.7).
# ---------------------------------------------------------------------------
log_msg("==== (3a) Group-size / row-order integrity check, diverging point, all 5 folds ====")

key_all <- built$key |> dplyr::mutate(row_idx = dplyr::row_number())
# finish_pos needed for the top-S check -- reconstruct exactly as build_gbt_matrix() does
qr_fp <- qualifying_races  # placeholder, not used directly; finish_pos comes via ri_new join below
finish_lookup <- ri_new |>
  dplyr::filter(split == "train") |>
  dplyr::left_join(
    dplyr::select(qualifying_runners, race_id, runner_id, finish_position, amended_position),
    by = c("race_id", "runner_id")
  ) |>
  dplyr::mutate(finish_pos = dplyr::coalesce(amended_position, finish_position)) |>
  dplyr::select(race_id, runner_id, finish_pos)

key_fp <- built$key |>
  dplyr::left_join(finish_lookup, by = c("race_id", "runner_id"))
stopifnot(nrow(key_fp) == nrow(built$key))

all_ok <- TRUE
for (f in 1:5) {
  val_race_ids <- folds$race_id[folds$fold == f]
  train_idx <- which(!(built$key$race_id %in% val_race_ids))
  val_idx   <- which(built$key$race_id %in% val_race_ids)

  for (label_idx in list(list(name = "train", idx = train_idx),
                          list(name = "val",   idx = val_idx))) {
    idx <- label_idx$idx
    sub_race_id <- built$key$race_id[idx]
    grp <- rle(as.character(sub_race_id))$lengths

    ok_sum <- sum(grp) == length(idx)
    n_distinct_races <- dplyr::n_distinct(sub_race_id)
    ok_contig <- length(grp) == n_distinct_races

    sub_fp <- key_fp[idx, ]
    sub_fp$row_in_race <- ave(seq_len(nrow(sub_fp)), sub_fp$race_id, FUN = seq_along)
    sub_fp <- sub_fp |>
      dplyr::group_by(race_id) |>
      dplyr::mutate(J = dplyr::n(), S = pmin(3L, J - 1L)) |>
      dplyr::ungroup()
    top_s_rows <- sub_fp |> dplyr::filter(row_in_race <= S)
    ok_topS <- all(top_s_rows$finish_pos == top_s_rows$row_in_race, na.rm = FALSE) &&
      !any(is.na(top_s_rows$finish_pos))

    ok_all <- ok_sum && ok_contig && ok_topS
    all_ok <- all_ok && ok_all
    log_msg(sprintf(
      "  fold=%d %s: n_rows=%d n_groups=%d sum(group_sizes)==n_rows: %s | groups_contiguous: %s | top-S rows == actual finish order: %s",
      f, label_idx$name, length(idx), length(grp), ok_sum, ok_contig, ok_topS
    ))
  }
}
log_msg("(3a) Overall integrity check: ", ifelse(all_ok, "ALL PASS", "*** FAILURE DETECTED ***"))

# ---------------------------------------------------------------------------
# (3b) Round-1 internals for the diverging point (max_depth=2, eta=0.01,
#      min_child_weight=1, subsample=0.7, colsample_bytree=0.7), fold 1.
#      Instrumented obj_fn/eval_fn wrappers log z/e/denom range and
#      non-finite counts every round; xgb.model.dt.tree() dumps the first
#      tree's per-leaf Cover (summed Hessian) and Value (leaf weight) after
#      nrounds = 3 (enough to see the trend, not just one point).
# ---------------------------------------------------------------------------
log_msg("==== (3b) Round-1 internals: diverging point, fold 1, nrounds=5 (instrumented) ====")

f <- 1L
val_race_ids <- folds$race_id[folds$fold == f]
train_idx <- which(!(built$key$race_id %in% val_race_ids))
val_idx   <- which(built$key$race_id %in% val_race_ids)
train_group <- rle(as.character(built$key$race_id[train_idx]))$lengths
val_group   <- rle(as.character(built$key$race_id[val_idx]))$lengths

X_train <- built$X[train_idx, ]; y_train <- built$y[train_idx]
X_val   <- built$X[val_idx, ];   y_val   <- built$y[val_idx]

dtrain <- xgboost::xgb.DMatrix(data = X_train, label = y_train)
dval   <- xgboost::xgb.DMatrix(data = X_val,   label = y_val)
xgboost::setinfo(dtrain, "group", train_group)
xgboost::setinfo(dval,   "group", val_group)

k <- 3L
round_ctr <- 0L
instrumented_obj <- function(preds, dtrain) {
  round_ctr <<- round_ctr + 1L
  d <- pl_denom(preds, train_group, k)
  gh <- pl_grad_hess(preds, train_group, k)
  log_msg(sprintf(
    "  [objective] round=%d preds range=[%s, %s] n_nonfinite_preds=%d e range=[%s, %s] denom range=[%s, %s] n_zero_denom=%d grad_nonfinite=%d hess_nonfinite=%d",
    round_ctr, format(min(preds), digits=6), format(max(preds), digits=6),
    sum(!is.finite(preds)),
    format(min(d$e, na.rm=TRUE), digits=6), format(max(d$e, na.rm=TRUE), digits=6),
    format(min(d$denom, na.rm=TRUE), digits=6), format(max(d$denom, na.rm=TRUE), digits=6),
    sum(d$denom == 0, na.rm = TRUE),
    gh$n_grad_floored, gh$n_hess_floored
  ))
  list(grad = gh$grad, hess = gh$hess)
}
instrumented_eval <- function(preds, dtrain) {
  logl_model <- -pl_neg_loglik(preds, val_group, k)
  J <- val_group; S <- pmin(k, J - 1L)
  logl_null <- -sum(unlist(purrr::map2(J, S, function(j, s) {
    if (s < 1L) return(0)
    sum(base::log(j - (seq_len(s) - 1L)))
  })))
  value <- 1 - logl_model / logl_null
  log_msg(sprintf("  [eval]      logl_model=%s logl_null=%s value=%s finite=%s",
              format(logl_model, digits=10), format(logl_null, digits=10),
              format(value, digits=10), is.finite(value)))
  if (!is.finite(value)) value <- -1e10
  list(metric = "pl_r2", value = value)
}

full_params <- list(
  max_depth = 2L, eta = 0.01, min_child_weight = 1L,
  subsample = 0.7, colsample_bytree = 0.7,
  base_score = 0, objective = instrumented_obj, nthread = 1L
)

set.seed(42L)
bst <- xgboost::xgb.train(
  params = full_params, data = dtrain, nrounds = 5L,
  evals = list(val = dval), custom_metric = instrumented_eval,
  maximize = TRUE, early_stopping_rounds = 50L, verbose = 0
)

log_msg("---- xgb.model.dt.tree() dump, round 1 (tree_idx 0) ----")
tree_dt <- xgboost::xgb.model.dt.tree(model = bst)
tree0 <- tree_dt[tree_dt$Tree == 0, ]
print(tree0)
leaves0 <- tree0[tree0$Feature == "Leaf" | is.na(tree0$Feature), ]
if (nrow(leaves0) == 0L) leaves0 <- tree0[is.na(tree0$Split), ]
log_msg("Round-1 (tree 0) leaves -- Cover (summed Hessian) and leaf Value:")
print(leaves0[, intersect(c("Node", "Cover", "Quality"), names(leaves0))])
log_msg("Min Cover (tree0 leaves): ", min(leaves0$Cover, na.rm = TRUE))
log_msg("Max |Quality| (tree0 leaves, this xgboost's leaf-value column): ",
    max(abs(leaves0$Quality), na.rm = TRUE))

log_msg("DONE.")
