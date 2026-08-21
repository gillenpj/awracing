# gbt_tuning.R
# Paper-3 GBT hyperparameter tuning: grid definition, one-fold fit, and
# selection. Training races only (R/gbt_data.R's complete-case, 5,022-race
# universe) -- the test split is never touched by anything in this file.

#' The paper-3 tuning grid
#'
#' Fixed 2026-08-20, before any test-set number, per CLAUDE.md "Tuning grid
#' budget". Full factorial over `max_depth`, `eta`, `min_child_weight`,
#' `subsample`; `colsample_bytree` fixed at 0.7 (fallback ladder step 1,
#' applied because the unreduced 144-point grid projected ~12.9 hours --
#' see CLAUDE.md). 72 points.
#'
#' @return A tibble, one row per grid point: `max_depth`, `eta`,
#'   `min_child_weight`, `subsample`, `colsample_bytree`.
build_tuning_grid <- function() {
  tidyr::expand_grid(
    max_depth        = c(2L, 3L, 4L, 6L),
    eta              = c(0.01, 0.03, 0.1),
    min_child_weight = c(1L, 5L, 20L),
    subsample        = c(0.7, 1.0),
    colsample_bytree = c(0.7)
  )
}

#' Fit one (grid point, fold) combination
#'
#' Trains on the fold's analysis rows, early-stops on the fold's own
#' assessment-set `pl_r2` (`early_stopping_rounds = 50`, `nrounds` capped
#' at 2000), and returns that fold's best validation `pl_r2` plus the
#' iteration it was achieved at. `nthread` is set explicitly (never left
#' to the xgboost default).
#'
#' Divergence during boosting is logged, not just floored (2026-08-20):
#' a non-finite `pl_r2` means a config diverged (scores blew up until
#' `exp(z)` overflowed, or a leaf value ran away against the Hessian
#' floor). `R/pl_objective.R`'s `make_pl_objective()`/`make_pl_eval()`
#' both accept a `diag_env` for exactly this — one fresh environment per
#' fold-fit here, shared between the two closures so every floored event
#' (objective or eval, whichever round) lands in one list. Whether
#' divergence is confined to the expected corner (high `eta`, high
#' `max_depth`) or appears at low `eta` too (which would mean the
#' objective has a numerical problem at scale, not just at extremes) is
#' exactly what this log is for — see CLAUDE.md "Paper 3 plan".
#'
#' @param X_train,y_train,train_group Fold analysis-set matrix, label,
#'   and race group sizes (rows arranged via `arrange_for_xgb()`).
#' @param X_val,y_val,val_group Fold assessment-set matrix, label, and
#'   race group sizes.
#' @param params Named list: `max_depth`, `eta`, `min_child_weight`,
#'   `subsample`, `colsample_bytree` (one grid point's values).
#' @param k Plackett-Luce depth (3, per the paper-3 objective).
#' @param nthread Integer, passed to `xgb.train()` explicitly.
#' @return A list: `best_iteration`, `best_pl_r2`, `divergence_events`
#'   (tibble, possibly zero rows: `round`, `source`, `n_grad_floored`,
#'   `n_hess_floored`, `raw_value` — see `make_pl_objective()` /
#'   `make_pl_eval()`'s roxygen for the columns each `source` populates).
fit_one_fold <- function(X_train, y_train, train_group,
                          X_val, y_val, val_group,
                          params, k = 3L, nthread = parallel::detectCores()) {
  dtrain <- xgboost::xgb.DMatrix(data = X_train, label = y_train)
  dval   <- xgboost::xgb.DMatrix(data = X_val,   label = y_val)
  xgboost::setinfo(dtrain, "group", train_group)
  xgboost::setinfo(dval,   "group", val_group)

  diag_env <- new.env(parent = emptyenv())
  diag_env$events <- list()

  obj_fn  <- make_pl_objective(train_group, k, diag_env = diag_env)
  eval_fn <- make_pl_eval(val_group, k, diag_env = diag_env)

  full_params <- c(
    list(
      max_depth        = params$max_depth,
      eta              = params$eta,
      min_child_weight = params$min_child_weight,
      subsample        = params$subsample,
      colsample_bytree = params$colsample_bytree,
      base_score       = 0,
      objective        = obj_fn,
      nthread          = nthread,
      seed             = 42L
    )
  )

  # Seed 42 throughout (original tuning-grid spec). R's set.seed() only
  # controls R-level RNG -- xgb.train()'s own `subsample`/`colsample_bytree`
  # row/column draws are governed by xgboost's OWN internal RNG, which is
  # NOT reset by R's set.seed() unless `seed` is also passed inside
  # `params` (see CLAUDE.md "Divergence guard" for the discovery story:
  # an earlier fix here set only R's seed, which looked verified because
  # xgboost's un-seeded internal RNG happens to be process-constant across
  # sequential calls in the SAME R session -- reproducible within a
  # session, not across sessions). `params$seed` above is the actual fix;
  # this call keeps R-level randomness (nothing else in this function uses
  # it directly, but xgboost's R binding may still consult it) pinned too.
  set.seed(42L)
  bst <- xgboost::xgb.train(
    params                = full_params,
    data                  = dtrain,
    nrounds               = 2000L,
    evals                 = list(val = dval),
    custom_metric         = eval_fn,
    maximize              = TRUE,
    early_stopping_rounds = 50L,
    verbose               = 0
  )

  best_iter <- as.integer(xgboost::xgb.attr(bst, "best_iteration"))
  eval_log  <- attr(bst, "evaluation_log")
  best_r2   <- as.numeric(eval_log$val_pl_r2[eval_log$iter == (best_iter + 1L)])

  divergence_events <- if (length(diag_env$events) == 0L) {
    tibble::tibble(round = integer(), source = character(),
                    n_grad_floored = integer(), n_hess_floored = integer(),
                    raw_value = double())
  } else {
    purrr::map_dfr(diag_env$events, function(e) {
      tibble::tibble(
        round          = e$round,
        source         = e$source,
        n_grad_floored = e$n_grad_floored %||% NA_integer_,
        n_hess_floored = e$n_hess_floored %||% NA_integer_,
        raw_value      = if (is.null(e$raw_value)) NA_real_ else e$raw_value
      )
    })
  }

  list(best_iteration = best_iter, best_pl_r2 = best_r2,
       divergence_events = divergence_events)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

#' Run 5-fold CV for one grid point
#'
#' @param X,y,key,group_sizes Full training-split matrix/label/key/group
#'   sizes from `build_gbt_matrix()`.
#' @param folds Tibble from `make_race_folds()` (`race_id`, `fold`).
#' @param params One grid point (see `fit_one_fold()`).
#' @param k Plackett-Luce depth.
#' @param nthread Integer, passed through to `fit_one_fold()`/`xgb.train()`
#'   for every fold. Default `parallel::detectCores()`, matching
#'   `fit_one_fold()`'s own default -- exposed here (2026-08-20) so a
#'   determinism diagnostic can force a fixed thread count without editing
#'   the function body. See CLAUDE.md "Paper 3 plan" divergence-guard note.
#' @return A list: `summary` (one-row tibble — the grid point's params,
#'   `fold_mean_pl_r2`, `fold_sd_pl_r2`, `mean_best_iteration`, and
#'   `fold_r2_1`..`fold_r2_5`) and `divergence_events` (tibble, possibly
#'   zero rows, one row per floored event across all 5 folds: the grid
#'   point's params, `fold`, plus `fit_one_fold()`'s `divergence_events`
#'   columns).
run_grid_point <- function(X, y, key, folds, params, k = 3L,
                            nthread = parallel::detectCores()) {
  v <- max(folds$fold)
  fold_results <- vector("list", v)

  for (f in seq_len(v)) {
    val_race_ids   <- folds$race_id[folds$fold == f]
    train_idx <- which(!(key$race_id %in% val_race_ids))
    val_idx   <- which(key$race_id %in% val_race_ids)

    train_group <- rle(as.character(key$race_id[train_idx]))$lengths
    val_group   <- rle(as.character(key$race_id[val_idx]))$lengths

    fold_results[[f]] <- fit_one_fold(
      X[train_idx, ], y[train_idx], train_group,
      X[val_idx, ],   y[val_idx],   val_group,
      params = params, k = k, nthread = nthread
    )
  }

  r2s   <- vapply(fold_results, function(r) r$best_pl_r2,       numeric(1))
  iters <- vapply(fold_results, function(r) r$best_iteration,   numeric(1))

  summary_tbl <- tibble::tibble(
    max_depth           = params$max_depth,
    eta                 = params$eta,
    min_child_weight    = params$min_child_weight,
    subsample           = params$subsample,
    colsample_bytree    = params$colsample_bytree,
    fold_mean_pl_r2     = mean(r2s),
    fold_sd_pl_r2       = stats::sd(r2s),
    mean_best_iteration = mean(iters),
    fold_r2_1 = r2s[1], fold_r2_2 = r2s[2], fold_r2_3 = r2s[3],
    fold_r2_4 = r2s[4], fold_r2_5 = r2s[5]
  )

  divergence_events <- purrr::imap_dfr(fold_results, function(r, f) {
    if (nrow(r$divergence_events) == 0L) return(NULL)
    tibble::tibble(
      max_depth = params$max_depth, eta = params$eta,
      min_child_weight = params$min_child_weight, subsample = params$subsample,
      colsample_bytree = params$colsample_bytree, fold = f
    ) |>
      dplyr::cross_join(r$divergence_events)
  })
  if (is.null(divergence_events) || nrow(divergence_events) == 0L) {
    divergence_events <- tibble::tibble(
      max_depth = integer(), eta = double(), min_child_weight = integer(),
      subsample = double(), colsample_bytree = double(), fold = integer(),
      round = integer(), source = character(),
      n_grad_floored = integer(), n_hess_floored = integer(), raw_value = double()
    )
  }

  list(summary = summary_tbl, divergence_events = divergence_events)
}

#' Select the winning grid point, applying the fixed tie-break rule
#'
#' Highest `fold_mean_pl_r2`; among points within 0.001 of the maximum,
#' prefer the simplest: lowest `max_depth`, then lowest
#' `mean_best_iteration` (nrounds). Rule fixed in advance (CLAUDE.md
#' "Tuning grid budget"), not chosen after seeing results.
#'
#' @param results Tibble from `run_grid_point()`, one row per grid point.
#' @return A one-row tibble: the selected grid point, plus `tie_break`
#'   (logical, whether more than one point was within 0.001 of the max).
select_best_config <- function(results) {
  best_val <- max(results$fold_mean_pl_r2)
  contenders <- results[results$fold_mean_pl_r2 >= best_val - 0.001, ]
  contenders <- contenders[order(contenders$max_depth, contenders$mean_best_iteration), ]
  selected <- contenders[1, ]
  selected$tie_break <- nrow(contenders) > 1L
  selected
}

#' Fit the final GBT on all training data at the selected hyperparameters
#'
#' Stage E. `nrounds` is `round(mean_best_iteration)` -- the MEAN
#' best-iteration across the winning grid point's 5 CV folds, rounded to
#' the nearest integer. This is a decision, not a default: fold-median or
#' the fold-maximum are both defensible alternatives (median is less
#' sensitive to one fold's outlier stopping point; the max avoids ever
#' under-fitting the eventual full-training-data model, which typically
#' benefits from a few more rounds than any individual 4/5-sized fold
#' needed). Fold-mean was chosen as the standard CV-then-refit convention
#' and for consistency with `fold_mean_pl_r2` already being the grid's own
#' selection criterion. No early stopping here: refitting on the full
#' training split leaves no held-out data to early-stop against, and the
#' test split must not be touched at this stage (see `R/gbt_data.R`).
#'
#' `seed = 42L` is set inside `full_params` (xgboost's own RNG, not just
#' R's `set.seed()`) -- see CLAUDE.md's paper-3 divergence-guard note for
#' why this is the one that actually matters for `subsample`/
#' `colsample_bytree` reproducibility.
#'
#' @param X,y,group_sizes Full training-split matrix/label/group sizes
#'   from `build_gbt_matrix()`.
#' @param selected One-row tibble from `select_best_config()`.
#' @param k Plackett-Luce depth.
#' @return A list: `bst` (the fitted `xgb.Booster`), `nrounds` (integer,
#'   the rounds actually used), `train_pl_r2` (in-sample, from
#'   `make_pl_eval()` scored on the same data the model was fit on --
#'   label this in-sample everywhere it is reported).
fit_final_model <- function(X, y, group_sizes, selected, k = 3L) {
  dtrain <- xgboost::xgb.DMatrix(data = X, label = y)
  xgboost::setinfo(dtrain, "group", group_sizes)

  obj_fn  <- make_pl_objective(group_sizes, k)
  eval_fn <- make_pl_eval(group_sizes, k)

  nrounds <- as.integer(round(selected$mean_best_iteration))

  full_params <- list(
    max_depth        = selected$max_depth,
    eta              = selected$eta,
    min_child_weight = selected$min_child_weight,
    subsample        = selected$subsample,
    colsample_bytree = selected$colsample_bytree,
    base_score       = 0,
    objective        = obj_fn,
    nthread          = parallel::detectCores(),
    seed             = 42L
  )
  set.seed(42L)
  bst <- xgboost::xgb.train(
    params  = full_params,
    data    = dtrain,
    nrounds = nrounds,
    verbose = 0
  )

  train_preds <- predict(bst, X, outputmargin = TRUE)
  train_pl_r2 <- eval_fn(train_preds, NULL)$value

  list(bst = bst, nrounds = nrounds, train_pl_r2 = train_pl_r2)
}

#' Within-race permutation feature importance
#'
#' For each feature, `n_repeats` times: shuffle that feature's values
#' WITHIN each race (which horse holds which value), leaving every race's
#' set of values and every other feature untouched, re-predict, and record
#' the drop in `pl_r2` versus the unpermuted baseline. A global (across-race)
#' permutation would destroy field composition and confound "does this
#' feature matter" with "does having a coherent field matter" -- within-race
#' permutation isolates the former, which is what feature importance is
#' supposed to measure here.
#'
#' Deliberately run on the TRAINING split only. The test split is not
#' touched by this function or anywhere else in Stage E -- an out-of-sample
#' permutation run belongs in the results/analysis pass alongside the
#' Q1-Q3 comparisons, on a common race set with everything else that
#' touches the test split, not brought forward into tuning.
#'
#' `set.seed(42L)` is called once, before the first permutation, so the
#' entire feature x repeat sequence is reproducible as a whole (not
#' re-seeded per feature, which would make every feature's repeats
#' identical to each other).
#'
#' @param bst Fitted `xgb.Booster` (from `fit_final_model()`).
#' @param X Numeric feature matrix, `build_gbt_matrix()` row order.
#' @param race_id Character/integer vector, one per `X` row, same order.
#' @param group_sizes Integer vector, per-race sizes in `X` row order.
#' @param feature_names Character vector, `X`'s column names.
#' @param k Plackett-Luce depth.
#' @param n_repeats Integer, permutation repeats per feature (30, per the
#'   paper-3 Stage E spec -- enough to report a mean and sd per feature,
#'   not just a single noisy draw).
#' @return Tibble, one row per feature, sorted by `mean_drop` descending:
#'   `feature`, `mean_drop`, `sd_drop`, `rank`.
permutation_importance_within_race <- function(bst, X, race_id, group_sizes,
                                                feature_names, k = 3L,
                                                n_repeats = 30L) {
  eval_fn <- make_pl_eval(group_sizes, k)
  baseline_preds <- predict(bst, X, outputmargin = TRUE)
  baseline_r2    <- eval_fn(baseline_preds, NULL)$value

  permute_within_race <- function(x, race_id) {
    perm_idx <- ave(seq_along(x), race_id,
                     FUN = function(idx) idx[sample.int(length(idx))])
    x[perm_idx]
  }

  set.seed(42L)
  results <- vector("list", length(feature_names))
  for (fi in seq_along(feature_names)) {
    feat  <- feature_names[fi]
    drops <- numeric(n_repeats)
    for (r in seq_len(n_repeats)) {
      X_perm <- X
      X_perm[, feat] <- permute_within_race(X_perm[, feat], race_id)
      perm_preds <- predict(bst, X_perm, outputmargin = TRUE)
      perm_r2    <- eval_fn(perm_preds, NULL)$value
      drops[r]   <- baseline_r2 - perm_r2
    }
    results[[fi]] <- tibble::tibble(
      feature   = feat,
      mean_drop = mean(drops),
      sd_drop   = stats::sd(drops)
    )
  }

  out <- dplyr::bind_rows(results) |> dplyr::arrange(dplyr::desc(mean_drop))
  out$rank <- seq_len(nrow(out))
  out
}

#' Paper 2b's own training-split PL pseudo-R^2 (k = 3), for direct comparison
#'
#' Reconstructs `model_2b_exploded_draw_final`'s implied full-field z scores
#' and group sizes from the `depth == 1` subset of
#' `exploded_interactions_data` -- the same reconstruction
#' `scripts/verify_pl_objective.R`'s assertion (6) verifies matches the
#' model's own `logLik()` to 1e-6 -- then scores it with the identical
#' `make_pl_eval()` k = 3 metric Stage E uses for the GBT. This gives a
#' number on the same scale as the GBT's `train_pl_r2`, not just "both are
#' called a pseudo-R^2" -- see `R/gbt_data.R`'s `FEATURE_COLS` roxygen for
#' why this comparison is the point of keeping `days_LTO_log` in log form.
#'
#' @param model_2b_exploded_draw_final Fitted mlogit model (paper 2b).
#' @param exploded_interactions_data mlogit long-form training data.
#' @return Numeric, paper 2b's training pl_r2 (k = 3).
paper2b_training_pl_r2 <- function(model_2b_exploded_draw_final, exploded_interactions_data) {
  df <- as.data.frame(exploded_interactions_data)
  class(df) <- "data.frame"
  attr(df, "index")    <- NULL
  attr(df, "clseries") <- NULL
  df <- dplyr::filter(df, depth == 1)

  coefs <- stats::coef(model_2b_exploded_draw_final)
  terms <- names(coefs)
  stopifnot(all(terms %in% names(df)), all(c("race_id", "won") %in% names(df)))

  X    <- as.matrix(df[, terms, drop = FALSE])
  df$z <- as.vector(X %*% coefs)
  df$runner_id <- if ("runner_id" %in% names(df)) df$runner_id else df$horse_ref
  if (!"finish_pos" %in% names(df)) {
    df$finish_pos <- ifelse(df$won == 1L, 1L, NA_integer_)
  }

  ordered     <- arrange_for_xgb(df)
  group_sizes <- rle(as.character(ordered$race_id))$lengths
  stopifnot(length(ordered$z) == sum(group_sizes))

  eval_fn <- make_pl_eval(group_sizes, k = 3L)
  eval_fn(ordered$z, NULL)$value
}
