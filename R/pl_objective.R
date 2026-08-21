# pl_objective.R
# Custom Plackett-Luce top-k listwise objective for {xgboost} (paper 3).
#
# Notation follows notes/Notes on Trees-based Methods.pdf and carries
# through from papers 1/2a/2b: race i is the chooser, horse j the
# alternative, z_ij is horse j's latent score in race i (a GBT score, not a
# fitted value -- it estimates nothing observable on its own, it only feeds
# the softmax). C_is is the set of horses not yet ranked at stage s. Given
# the top-k finishers j_1, ..., j_k of race i in order, the stage-s softmax
# over the surviving set is
#
#   p_sj = exp(z_ij) / sum_{r in C_is} exp(z_ir),   j in C_is, else 0
#
# and the per-race negative log-likelihood, S = min(k, J - 1) (J = field
# size; stage J contributes zero, its denominator having one term), is
#
#   L_i = - sum_{s=1}^{S} ( z_{i,j_s} - log sum_{r in C_is} exp(z_ir) )
#
# Term-for-term this is the ListMLE objective from the learning-to-rank
# literature; paper 2b's exploded conditional logit is the k = 3 case of
# the same likelihood with a linear-predictor z. The structural fact that
# drives every complication below: one term of this loss spans every
# runner in the field, so it does not factorise per observation the way a
# per-row loss (squared error, log loss, ...) does.
#
# XGBoost's custom-objective interface takes a first derivative (grad) and
# a DIAGONAL second derivative (hess) per row -- the true Hessian of this
# grouped likelihood is not diagonal (a runner's second derivative depends
# on every other runner still in its race at each surviving stage), and
# XGBoost consumes the diagonal only. That is a standard approximation of
# XGBoost's, not something introduced here; flagged again on
# pl_grad_hess() below.

#' Arrange runner rows for the grouped Plackett-Luce objective
#'
#' `{xgboost}` group info requires rows contiguous by race, and this
#' objective additionally requires that each race's S = min(k, J - 1)
#' finishers occupy rows 1..S of their block in finishing order, so the
#' objective can index positionally (the s-th finisher is the s-th row)
#' rather than doing a label lookup at every call. Rows are sorted by
#' `race_id`, then finishing position ascending (placed horses first, in
#' order), with unplaced or tied rows sorted after the placed ones, broken
#' deterministically by `runner_id`. Every caller that builds an
#' `xgb.DMatrix` for this objective must sort through this function first.
#'
#' @param df A tibble with `race_id`, `runner_id`, and `finish_pos`
#'   (finishing position, `NA` for unplaced/non-finishing rows).
#' @return `df`, re-ordered; no columns added or removed.
arrange_for_xgb <- function(df) {
  df |>
    dplyr::arrange(
      race_id,
      dplyr::coalesce(finish_pos, .Machine$integer.max),
      runner_id
    )
}

#' Shared per-race denominator computation (internal, hot-path)
#'
#' The common prefix `pl_neg_loglik()` and `pl_grad_hess()` both need: the
#' per-race max-subtracted scores and their surviving-set (suffix) sums.
#' `z` must already be arranged by `arrange_for_xgb()` and contiguous by
#' race per `group_sizes`. Vectorised via `{data.table}`'s grouped
#' operations — no `dplyr::group_by()` — for performance: profiled at
#' ~900ms/call on a ~40,000-row / ~4,000-race training fold under the
#' original `dplyr::group_by() |> mutate()` implementation (retained as
#' `pl_core_reference()` below), prohibitive for a hyperparameter grid
#' that calls this twice per boosting round.
#'
#' `{data.table}`, not a hand-rolled vectorisation, deliberately: an
#' earlier attempt computed the suffix sum via a single global `cumsum()`
#' with a per-group offset subtraction (`cs[end] - cs[i] + x[i]`, or a
#' mirrored variant of the same idea). Both forms subtract two numbers
#' that both include the accumulated total of every PRECEDING race —
#' for a race late in the (arbitrary) processing order this recovers a
#' small suffix sum by cancelling two large, nearly-equal numbers, and
#' degraded `scripts/verify_pl_objective.R` assertion (4)'s
#' Hessian-vs-`numDeriv` agreement from ~7e-8 (the original `dplyr`
#' implementation) to ~1.6e-6 (over its 1e-6 tolerance) on the standard
#' 20-race verification fixture — a real, reproducible precision
#' regression, not noise (confirmed: the two implementations agreed with
#' EACH OTHER to ~1e-14, so the discrepancy is in the finite-difference
#' comparison's sensitivity to which floating-point path produced that
#' near-identical value). `dplyr::group_by()` never has this problem
#' because it fits each group's `rev(cumsum(rev(x)))` on an isolated,
#' group-local vector — no cross-race magnitude ever enters the
#' arithmetic. `{data.table}`'s `by =` grouped operations have the same
#' property (genuinely local per-group computation, not a global
#' cumulative sum offset against a large running total) while running in
#' C rather than R, which is what restores both the speed and the
#' precision of the original `dplyr` computation at once.
#'
#' Per-race max-subtraction (`zc = z - max(z)` within each race) is exact,
#' not an approximation — see `pl_core()`'s roxygen for why it changes
#' neither the loss, gradient, nor Hessian.
#'
#' @param z Numeric vector of latent scores, one per runner-race row.
#' @param group_sizes Integer vector, field size (number of runners) for
#'   each race, in the same order as the contiguous blocks of `z`.
#' @param k Integer, requested finishing-order depth (`k = 1` recovers the
#'   conditional logit -- win only).
#' @return A list: `race` (race index, 1-based), `pos` (1-indexed row
#'   position within its race), `J` (race field size), `S`
#'   (`min(k, J - 1)`), `zc` (max-subtracted score), `e` (`exp(zc)`),
#'   `denom` (suffix sum of `e` from `pos` to the race's last row),
#'   `group_sizes` (passed through).
pl_denom <- function(z, group_sizes, k) {
  n <- length(z)
  stopifnot(n == sum(group_sizes))
  R <- length(group_sizes)
  race <- rep.int(seq_len(R), group_sizes)
  J    <- rep.int(group_sizes, group_sizes)
  S    <- pmin(k, J - 1L)
  pos  <- sequence(group_sizes)

  dt <- data.table::data.table(race = race, z = z)
  dt[, zc := z - max(z), by = race]
  dt[, e := exp(zc)]
  dt[, denom := rev(cumsum(rev(e))), by = race]

  list(race = race, pos = pos, J = J, S = S,
       zc = dt$zc, e = dt$e, denom = dt$denom, group_sizes = group_sizes)
}

#' Plackett-Luce top-k negative log-likelihood
#'
#' Loss-only hot path: unlike `pl_core()` / `pl_grad_hess()`, never
#' computes `cuminv`/`cuminv2`/gradient/Hessian, since `make_pl_eval()`
#' (the only per-round caller) needs the loss alone.
#'
#' @inheritParams pl_denom
#' @return Scalar total negative log-likelihood, summed over races and
#'   stages 1..S (S = min(k, J - 1) per race).
pl_neg_loglik <- function(z, group_sizes, k) {
  d <- pl_denom(z, group_sizes, k)
  stage_term <- ifelse(d$pos <= d$S, d$zc - base::log(d$denom), 0)
  -sum(stage_term)
}

#' Plackett-Luce gradient and Hessian diagonal
#'
#' Grad/Hessian-only hot path: unlike `pl_core()`, never computes
#' `stage_term` (the loss), since `make_pl_objective()` (the only
#' per-round caller) needs the derivatives alone.
#'
#' The Hessian returned is the DIAGONAL of the true (non-diagonal) Hessian
#' of the grouped Plackett-Luce negative log-likelihood -- XGBoost's
#' custom-objective interface only accepts a diagonal second-order term, so
#' the off-diagonal cross-runner terms are discarded. Standard for any
#' listwise objective fitted this way; not specific to this
#' implementation. Floored at `1e-16` (XGBoost's leaf-value update divides
#' by the Hessian sum, and can produce non-finite results from an
#' exact-zero Hessian).
#'
#' For row `pos` (1-indexed within its race) let `t = min(S, pos)`. Because
#' `p_sj = 0` for stages `s` after row `pos` has already been ranked
#' (`s > pos`), both the gradient sum and the Hessian sum over `s = 1..S`
#' collapse to `s = 1..t`, which are computed via cumulative sums of
#' `1 / denom_s` and `1 / denom_s^2` rather than materialising the full
#' `p_sj` matrix:
#'
#' \eqn{g_{ij} = \sum_{s=1}^{S} p_{sj} - 1\{j \in \text{top } S\}}
#' \eqn{h_{ij} = \sum_{s=1}^{S} p_{sj}(1 - p_{sj})}
#'
#' `cuminv`/`cuminv2` (the running `sum(1/denom_s)` / `sum(1/denom_s^2)`
#' each row needs) are `{data.table}` grouped cumulative sums, for the
#' same reason `pl_denom()` uses `{data.table}` rather than a hand-rolled
#' global-cumsum-with-offset — see its roxygen.
#'
#' Non-finite guard (added 2026-08-20, alongside `make_pl_eval()`'s —
#' see there for the discovery story): `denom` can underflow to exactly
#' `0.0` for a runner far enough behind the field after enough boosting
#' rounds (its `e = exp(zc)` term negligible next to the leader's), making
#' `invd = 1/denom` (and hence `cuminv`/`grad`/`hess`) `Inf` or `NaN` for
#' that row. Rather than let a non-finite gradient/Hessian reach XGBoost's
#' tree-building silently (worse than a crash — a silently corrupted
#' split), any non-finite `grad` is floored to 0 (no push, in either
#' direction, for that row) and any non-finite `hess` to the same `1e-16`
#' floor already used for a legitimately tiny Hessian.
#'
#' @inheritParams pl_denom
#' @return A list with `grad` and `hess`, numeric vectors the same length
#'   and order as `z`.
pl_grad_hess <- function(z, group_sizes, k) {
  d <- pl_denom(z, group_sizes, k)

  dt <- data.table::data.table(race = d$race, pos = d$pos, S = d$S, denom = d$denom)
  dt[, invd  := ifelse(pos <= S, 1 / denom,   0)]
  dt[, invd2 := ifelse(pos <= S, 1 / denom^2, 0)]
  dt[, cuminv  := cumsum(invd),  by = race]
  dt[, cuminv2 := cumsum(invd2), by = race]

  indicator <- as.numeric(d$pos <= d$S)
  grad <- d$e * dt$cuminv - indicator
  hess <- pmax(d$e * dt$cuminv - d$e^2 * dt$cuminv2, 1e-16)

  n_grad_floored <- sum(!is.finite(grad))
  n_hess_floored <- sum(!is.finite(hess))
  grad[!is.finite(grad)] <- 0
  hess[!is.finite(hess)] <- 1e-16

  list(grad = grad, hess = hess,
       n_grad_floored = n_grad_floored, n_hess_floored = n_hess_floored)
}

#' Grouped Plackett-Luce core computation — full (race, pos, grad, hess,
#' stage_term) result
#'
#' NOT used in the fitting hot path (`make_pl_objective()` /
#' `make_pl_eval()` call the leaner `pl_grad_hess()` / `pl_neg_loglik()`
#' directly). Kept for direct testing (`scripts/verify_pl_objective.R`'s
#' gradient-sums-to-zero and numDeriv checks) and as the assembly point
#' when both the loss and the derivatives are wanted together. Composes
#' `pl_grad_hess()` (recomputing `pl_denom()` a second time internally —
#' fine here, since this function is never called per boosting round).
#'
#' @inheritParams pl_denom
#' @return A tibble, one row per input row, in input order: `race` (race
#'   index, 1-based), `pos` (row position within its race, 1 = winner),
#'   `grad`, `hess`, `stage_term` (this row's contribution to the negative
#'   log-likelihood; 0 for rows past the scored depth S).
pl_core <- function(z, group_sizes, k) {
  d  <- pl_denom(z, group_sizes, k)
  gh <- pl_grad_hess(z, group_sizes, k)
  stage_term <- ifelse(d$pos <= d$S, d$zc - base::log(d$denom), 0)
  tibble::tibble(
    race = d$race, pos = d$pos,
    grad = gh$grad, hess = gh$hess, stage_term = stage_term
  )
}

#' Reference (original `dplyr`-based) implementation — verification only
#'
#' RETAINED SOLELY AS A VERIFICATION REFERENCE for
#' `scripts/verify_pl_objective.R`'s equivalence check against the
#' vectorised `pl_core()` above. NOT called anywhere in the fitting hot
#' path, and not used by `pl_neg_loglik()` / `pl_grad_hess()` / `pl_core()`
#' any more. This is the original implementation
#' (`dplyr::group_by() |> mutate()`), benchmarked at ~900ms/call on a
#' ~40,000-row / ~4,000-race training fold — with two calls per boosting
#' round (objective + eval metric), that made the paper-3 tuning grid
#' (144 points x 5 folds, up to 2,000 rounds each) an estimated 9-180+
#' hours depending on rounds/fit. See CLAUDE.md "Paper 3 plan" for the
#' full timing writeup.
#'
#' Uses one max-subtraction per race for numerical stability: `zc = z -
#' max(z)` within each race. This is exact, not an approximation -- every
#' stage's softmax over a race is invariant to a constant shift applied to
#' the whole race's scores (the shift appears in both the numerator and
#' `log sum exp` term of every surviving stage and cancels), so a single
#' per-race shift stabilises every stage at once without changing the loss,
#' gradient, or Hessian.
#'
#' @inheritParams pl_denom
#' @return Identical shape/semantics to `pl_core()`.
pl_core_reference <- function(z, group_sizes, k) {
  stopifnot(length(z) == sum(group_sizes))
  race <- rep.int(seq_along(group_sizes), group_sizes)

  tibble::tibble(z = z, race = race) |>
    dplyr::group_by(race) |>
    dplyr::mutate(
      pos        = dplyr::row_number(),
      J          = dplyr::n(),
      S          = pmin(k, J - 1L),
      zc         = z - max(z),
      e          = exp(zc),
      denom      = rev(cumsum(rev(e))),
      invd       = dplyr::if_else(pos <= S, 1 / denom, 0),
      invd2      = dplyr::if_else(pos <= S, 1 / denom^2, 0),
      cuminv     = cumsum(invd),
      cuminv2    = cumsum(invd2),
      grad       = e * cuminv - as.numeric(pos <= S),
      hess       = pmax(e * cuminv - e^2 * cuminv2, 1e-16),
      stage_term = dplyr::if_else(pos <= S, zc - base::log(denom), 0)
    ) |>
    dplyr::ungroup() |>
    dplyr::select(race, pos, grad, hess, stage_term)
}

#' Build an XGBoost custom objective closure for the Plackett-Luce loss
#'
#' `group_sizes` is captured in the closure rather than read back from the
#' `xgb.DMatrix` at call time. This matters:
#' `xgboost::setinfo(dtrain, "group", sizes)` takes group SIZES, but
#' `xgboost::getinfo(dtrain, "group")` returns the cumulative group
#' POINTER, not the sizes -- e.g. `setinfo(dtrain, "group", c(3, 4, 3))`
#' then `getinfo(dtrain, "group")` returns `c(0, 3, 7, 10)`. Verified
#' empirically against the installed xgboost version (see
#' `scripts/verify_pl_objective.R`). Round-tripping through `getinfo()`
#' inside the objective would silently feed a group POINTER into
#' `pl_grad_hess()`'s `group_sizes` argument, which expects sizes.
#'
#' `xgb.train()` should be called with `base_score = 0` for this
#' objective. It cancels in every stage's softmax (a constant shift in
#' every race's scores changes neither the loss nor the gradient, per
#' `pl_core()`), but the fitting code should still set it explicitly
#' rather than rely on the library default.
#'
#' Optional `diag_env`: divergence event logging (added 2026-08-20, see
#' `make_pl_eval()`'s roxygen for the discovery story). If supplied (an
#' environment with a `events` list element), every call that floors a
#' non-finite `grad`/`hess` value appends one record — `round` (this
#' closure's own call counter, since XGBoost does not pass a round number
#' to a custom objective), `source = "objective"`, `n_grad_floored`,
#' `n_hess_floored` — to `diag_env$events`. `NULL` (the default) disables
#' logging entirely, at no extra cost (skips the check).
#'
#' @param group_sizes Integer vector of field sizes, one per race, in the
#'   race order of the training data (rows arranged by `arrange_for_xgb()`).
#' @param k Integer, finishing-order depth.
#' @param diag_env Optional environment for divergence-event logging; see
#'   above. Default `NULL` (no logging).
#' @return A function `function(preds, dtrain)` returning
#'   `list(grad = , hess = )`, for `xgboost::xgb.train(obj = ...)`.
make_pl_objective <- function(group_sizes, k, diag_env = NULL) {
  force(group_sizes)
  force(k)
  round_counter <- 0L
  function(preds, dtrain) {
    round_counter <<- round_counter + 1L
    gh <- pl_grad_hess(preds, group_sizes, k)
    if (!is.null(diag_env) && (gh$n_grad_floored > 0L || gh$n_hess_floored > 0L)) {
      diag_env$events[[length(diag_env$events) + 1L]] <- list(
        round = round_counter, source = "objective",
        n_grad_floored = gh$n_grad_floored, n_hess_floored = gh$n_hess_floored
      )
    }
    list(grad = gh$grad, hess = gh$hess)
  }
}

#' Build an XGBoost custom eval-metric closure: Plackett-Luce pseudo-R2
#'
#' McFadden pseudo-R-squared, \eqn{1 - \log L(\text{model}) / \log
#' L(\text{null})}. The null model is uniform over the surviving set at
#' every stage, \eqn{\log L_{\text{null}} = -\sum_i \sum_{s=1}^{S_i} \log
#' |\mathcal{C}_{is}|}, computed once from `group_sizes` and `k` (constant
#' across boosting rounds, so it is precomputed in the closure rather than
#' recomputed on every call). Higher is better -- register with
#' `maximize = TRUE` on the `xgb.train()` watchlist.
#'
#' `group_sizes` is captured in the closure for the same reason as in
#' `make_pl_objective()` -- see its documentation for the group-size vs
#' group-pointer trap.
#'
#' Non-finite guard (added 2026-08-20, discovered mid-tuning-grid):
#' during boosting, especially at extreme grid points (low `eta`, high
#' `max_depth`, many rounds), raw scores can grow large enough that
#' `exp(zc)` overflows or `denom` underflows to a value whose `log()`
#' isn't finite, making `pl_r2` `NaN`/`-Inf`/`Inf`. XGBoost's
#' early-stopping callback does `if (score > best_score)` on the raw
#' returned value with no `NA`-handling of its own, and a non-finite
#' `score` crashes the ENTIRE `xgb.train()` call ("missing value where
#' TRUE/FALSE needed") rather than just marking that round as
#' non-improving. Any non-finite `pl_r2` is therefore floored to a large
#' negative FINITE sentinel (`-1e10`, not `-Inf`, so no round is ever
#' compared against another `-Inf` and no comparison is ever
#' `NA`) -- unambiguously worse than any real `pl_r2` (which is bounded
#' above by 1), so early stopping and grid selection both still behave
#' correctly: a round or grid point that diverges numerically is scored
#' as bad, not as a crash.
#'
#' Optional `diag_env`: divergence event logging, same mechanism as
#' `make_pl_objective()`'s. Every call that floors a non-finite `pl_r2`
#' appends one record — `round` (this closure's own call counter),
#' `source = "eval"`, `raw_value` (the pre-floor value, for diagnosis:
#' `NaN`, `Inf`, or `-Inf`) — to `diag_env$events`.
#'
#' @inheritParams make_pl_objective
#' @return A function `function(preds, dtrain)` returning
#'   `list(metric = "pl_r2", value = )`.
make_pl_eval <- function(group_sizes, k, diag_env = NULL) {
  force(group_sizes)
  force(k)
  J <- group_sizes
  S <- pmin(k, J - 1L)
  logl_null <- -sum(unlist(purrr::map2(J, S, function(j, s) {
    if (s < 1L) return(0)
    sum(base::log(j - (seq_len(s) - 1L)))
  })))
  round_counter <- 0L
  function(preds, dtrain) {
    round_counter <<- round_counter + 1L
    logl_model <- -pl_neg_loglik(preds, group_sizes, k)
    value <- 1 - logl_model / logl_null
    if (!is.finite(value)) {
      if (!is.null(diag_env)) {
        diag_env$events[[length(diag_env$events) + 1L]] <- list(
          round = round_counter, source = "eval", raw_value = value
        )
      }
      value <- -1e10
    }
    list(metric = "pl_r2", value = value)
  }
}

#' Per-race softmax win probabilities from raw Plackett-Luce scores
#'
#' `predict()` on a Plackett-Luce booster returns raw scores z. Win
#' probabilities always come from this function -- never from a built-in
#' objective transform, since this is a custom objective and XGBoost has no
#' softmax-over-a-variable-size-group transform of its own.
#'
#' @param preds Numeric vector of raw scores z, one per runner-race row.
#' @param race_id,runner_id Vectors the same length as `preds` identifying
#'   each row's race and runner.
#' @return A tibble with `race_id`, `runner_id`, `z`, `p_win`; `p_win` sums
#'   to exactly 1 (up to floating-point error) within each `race_id`.
pl_softmax_by_race <- function(preds, race_id, runner_id) {
  tibble::tibble(race_id = race_id, runner_id = runner_id, z = preds) |>
    dplyr::group_by(race_id) |>
    dplyr::mutate(p_win = exp(z - max(z)) / sum(exp(z - max(z)))) |>
    dplyr::ungroup()
}
