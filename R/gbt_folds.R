# gbt_folds.R
# Race-grouped cross-validation folds for paper-3 GBT hyperparameter
# tuning.

#' Race-grouped CV folds for GBT tuning (training races only)
#'
#' Folds are RANDOM group-assignments of races to `v` folds via
#' `rsample::group_vfold_cv()` — NOT a second chronological split. The
#' chronological train/test boundary (2012-12-30) already does the
#' temporal out-of-sample work for the paper's headline comparisons
#' (Q1/Q2/Q3 vs 2b, all scored on the held-out test races); these folds
#' exist only to select hyperparameters WITHIN the training era via
#' ordinary (grouped, not time-series) cross-validation. No race is split
#' across an analysis/assessment pair — every runner-row of a race stays
#' together, since a race is the PL objective's grouping unit too, and
#' letting part of a race's field leak into the assessment set of its own
#' fold would understate the held-out loss.
#'
#' @param race_ids Integer vector of training race_ids to fold (may
#'   contain duplicates, e.g. the runner-row race_id column; deduplicated
#'   internally — one fold assignment per race, not per runner-row).
#' @param v Integer, number of folds (default 5).
#' @param seed Integer, RNG seed for the fold assignment (default 42).
#' @return A tibble: `race_id`, `fold` (integer 1..`v`, the fold in which
#'   that race sits in the assessment/held-out set).
make_race_folds <- function(race_ids, v = 5, seed = 42) {
  race_ids <- unique(race_ids)
  set.seed(seed)
  splits <- rsample::group_vfold_cv(
    tibble::tibble(race_id = race_ids),
    group = race_id,
    v = v
  )

  purrr::map2_dfr(splits$splits, seq_len(v), function(split, fold) {
    tibble::tibble(
      race_id = rsample::assessment(split)$race_id,
      fold    = fold
    )
  })
}
