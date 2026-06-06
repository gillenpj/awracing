# fit_mlogit_model.R
# Fits Owen's conditional-logit (multinomial logit, choice set = race)
# model on the joined features tibble. Three pure functions, one per
# pipeline target: prepare data, fit, summarise.

#' Reshape the features tibble to {mlogit}'s long-form choice-data
#'
#' Calls `mlogit::mlogit.data(shape = "long", choice = "won",
#' chid.var = "race_id", alt.var = "horse_ref")`. The input is already
#' long (one row per runner-race), so the call simply attaches the
#' chooser/alternative index attributes that `mlogit::mlogit()` needs.
#' `horse_ref` is a per-race index `1..n_runners` added by this
#' function — using the population-wide `runner_id` as `alt.var`
#' would make `nlevels(alt.var)` ~10,000 and cause mlogit's internal
#' matrices to blow up (the previous 16GB / hang failure mode).
#'
#' Before reshaping, **entire races** are dropped where any runner has
#' any NA in a modelling column. Dropping at the race level (not the
#' runner level) preserves the "exactly one chosen alternative per
#' choice set" invariant that {mlogit} requires — removing an
#' individual NA runner could otherwise leave a race with zero or
#' two winners. The typical cause of NAs is `sireSR` / `trainerSR`
#' for first-time-starter sires or debut trainers (project's strict-
#' no-leakage rule returns NA, not 0, in those cases). A diagnostic
#' message reports the count of dropped races / runners.
#'
#' @param features_df Tibble from the `features` target. Must contain
#'   `race_id`, `runner_id`, `won`, and all 13 modelling features
#'   (`age_diff`, `sireSR`, `trainerSR`, `days_LTO_log`,
#'   `position1`-`3`, plus the six binary tack indicators).
#' @return An mlogit-formatted data object (`dfidx`-class indexed
#'   data frame in modern {mlogit}) ready for `mlogit::mlogit()`.
prepare_mlogit_data <- function(features_df) {
  model_vars <- c(
    "age_diff",
    "sireSR", "trainerSR", "days_LTO_log",
    "position1", "position2", "position3",
    "entire", "gelding", "cheekpieces", "blinkers", "visor", "tonguetie"
  )

  bad_races <- features_df |>
    dplyr::filter(dplyr::if_any(dplyr::all_of(model_vars), is.na)) |>
    dplyr::pull(race_id) |>
    unique()

  if (length(bad_races) > 0L) {
    n_bad_runners <- features_df |>
      dplyr::filter(race_id %in% bad_races) |>
      nrow()
    message(
      "prepare_mlogit_data: dropping ", length(bad_races),
      " race(s) (", n_bad_runners, " runner-rows) with NAs in ",
      "modelling columns. Most likely cause: sireSR / trainerSR ",
      "NA for first-time-starter sires or debut trainers."
    )
  }

  # alt.var must be a low-cardinality per-race index, not the
  # population-wide runner_id. mlogit dimensions its internal
  # design / Hessian matrices by `nlevels(alt.var)`; passing
  # runner_id (~10k+ distinct horses) makes those matrices ~600x
  # larger than necessary and is the root cause of the 16GB hang
  # in earlier runs. Per Owen's reference script we generate
  # horse_ref = 1..n within each race, giving at most ~16 levels.
  cleaned <- features_df |>
    dplyr::filter(!race_id %in% bad_races) |>
    dplyr::group_by(race_id) |>
    dplyr::mutate(horse_ref = dplyr::row_number()) |>
    dplyr::ungroup()

  mlogit_data <- mlogit::mlogit.data(
    cleaned,
    shape    = "long",
    choice   = "won",
    chid.var = "race_id",
    alt.var  = "horse_ref"
  )

  na_cols <- purrr::keep(model_vars, \(v) anyNA(cleaned[[v]]))
  if (length(na_cols) > 0L) {
    stop(
      "NAs remain in mlogit data after race-level drop: ",
      paste(na_cols, collapse = ", "),
      ". This should not happen — investigate."
    )
  }

  mlogit_data
}

#' Fit Owen's conditional logit on AW handicap data
#'
#' Fits a race-conditional (no-intercept) multinomial logit on the
#' 14 features defined by the project. The `| 0` in the formula
#' suppresses alternative-specific intercepts — appropriate because
#' alternatives (runner_ids) have no intrinsic ordering or value;
#' the model identifies coefficient effects purely from within-race
#' variation across runners.
#'
#' @details
#' Formula:
#' \preformatted{
#' won ~ age_diff + sireSR + trainerSR + days_LTO_log +
#'       position1 + position2 + position3 +
#'       entire + gelding + cheekpieces + blinkers +
#'       visor + tonguetie | 0 | 0
#' }
#'
#' The three-part `| 0 | 0` (matching Owen's reference script)
#' unambiguously suppresses alternative-specific intercepts. A
#' two-part `| 0` interacted badly with a high-cardinality
#' `alt.var` in `prepare_mlogit_data()`'s earlier shape and
#' caused mlogit to fit one intercept per alt level — the
#' original 16GB-hang failure mode.
#'
#' Validity is checked by `inherits(fitted, "mlogit")` plus a
#' non-null `$coefficients` slot — mlogit doesn't reliably populate
#' a convergence exit code, so the object itself is the source of
#' truth. Non-fatal convergence messages in `fitted$message` are
#' surfaced as warnings, not stops. A separate aliasing warning
#' fires when any coefficient's p-value is exactly 1.0 (a sign of
#' perfect collinearity, e.g. a factor level absent from the fitted
#' subset).
#'
#' @param mlogit_data Output of `prepare_mlogit_data()`.
#' @return The fitted `mlogit` object.
fit_conditional_logit <- function(mlogit_data) {
  # Three-part formula `| 0 | 0` matches Owen's reference script and
  # unambiguously suppresses alternative-specific intercepts. The
  # two-part `| 0` left the second / third positions ambiguous,
  # which interacted badly with a high-cardinality alt.var. Solver
  # method, iteration limit, and verbosity are left at mlogit's
  # defaults — the reference script runs in <1 min with no overrides.

  fitted <- mlogit::mlogit(
    won ~ age_diff + sireSR + trainerSR + days_LTO_log +
          position1 + position2 + position3 +
          entire + gelding + cheekpieces + blinkers + visor + tonguetie | 0 | 0,
    data = mlogit_data
  )

  # mlogit doesn't always populate $code; trust the fit object itself
  if (!inherits(fitted, "mlogit") || is.null(fitted$coefficients)) {
    stop("mlogit fit failed: no coefficients returned")
  }
  if (!is.null(fitted$message) && grepl("error|failed|no convergence", fitted$message, ignore.case=TRUE)) {
    warning("mlogit convergence warning: ", fitted$message)
  }

  pvals <- summary(fitted)$CoefTable[, "Pr(>|z|)"]
  aliased <- names(pvals)[!is.na(pvals) & pvals == 1]
  if (length(aliased) > 0L) {
    warning(
      "Possible coefficient aliasing — p-value exactly 1.0 for: ",
      paste(aliased, collapse = ", ")
    )
  }

  fitted
}

#' Extract diagnostic summary from a fitted mlogit model
#'
#' Returns the coefficient table and a small set of fit statistics
#' suitable for tabulation against Owen (2019) Table 3.
#'
#' Null-model log-likelihood is recovered from the likelihood-ratio
#' statistic stored on `summary(fitted_model)$lratio`, which is
#' `2 * (logLik_fitted - logLik_null)`. McFadden R^2 is then
#' `1 - logLik_fitted / logLik_null`; deviance is `-2 * logLik` for
#' each. Race count comes from the length of `fitted$fitted.values`
#' (one entry per chooser = race).
#'
#' @param fitted_model An `mlogit` model object, e.g. from
#'   `fit_conditional_logit()`.
#' @return A list with two components:
#'   \describe{
#'     \item{`coefficients`}{Tibble with columns `parameter`,
#'       `estimate`, `std.error`, `p.value`.}
#'     \item{`fit_stats`}{Named numeric vector with elements
#'       `McFadden`, `null.deviance`, `residual.deviance`, `nobs`
#'       (total runner-race rows), `nraces` (choice sets).}
#'   }
extract_model_diagnostics <- function(fitted_model) {
  # mlogit's S3 methods (`summary.mlogit`, `vcov.mlogit`, ...) are
  # only added to the S3 dispatch table once the mlogit namespace
  # is loaded. The pipeline does not `library(mlogit)` — all usage
  # is qualified `mlogit::...` — so dispatch only happens by side
  # effect after the first `mlogit::mlogit()` call. This target
  # runs against a cached fit and never makes such a call itself,
  # so without an explicit load, `summary(fitted_model)` falls back
  # to `summary.default` and silently returns an atomic vector.
  # Forcing the namespace load here makes dispatch deterministic.
  loadNamespace("mlogit")

  summ       <- summary(fitted_model)
  coef_table <- summ$CoefTable

  coefficients <- tibble::tibble(
    parameter = rownames(coef_table),
    estimate  = coef_table[, "Estimate"],
    std.error = coef_table[, "Std. Error"],
    p.value   = coef_table[, "Pr(>|z|)"]
  )

  # Under the null model (all coefficients = 0), every alternative in a
  # race has probability 1/n_runners, so the winner's contribution is
  # log(1/n_r) = -log(n_r) and the null log-likelihood is just
  # -sum_r log(n_r). Computing it from the choice-set sizes alone is
  # robust to the fact that `summary(mlogit_fit)$lratio` is not always
  # populated (the earlier route via `lratio$statistic / 2` was the
  # source of NA McFadden R² / Null deviance in the full-fit diagnostics
  # table).
  #
  # The probabilities matrix has dimensions (n_races x max_field_size),
  # with **zero** (not NA) in the padded alternatives below the actual
  # field size — softmax-derived probabilities for real alternatives are
  # strictly positive, so `> 0` cleanly discriminates real from padded
  # slots. rowSums(probs > 0) therefore gives the actual choice-set
  # size per race, and summing over the whole matrix gives the total
  # number of runner-race observations the model was fitted to. The
  # earlier `nrow(fitted_model$model)` route returned the padded count
  # `n_races * max_field_size` (e.g. 5,150 * 16 = 82,400), over-counting
  # by ~70%.
  probs_mat          <- fitted_model$probabilities
  is_real            <- probs_mat > 0
  n_runners_per_race <- rowSums(is_real)
  ll_fitted          <- as.numeric(stats::logLik(fitted_model))
  ll_null            <- -sum(log(n_runners_per_race))

  nobs_total   <- sum(is_real)
  nraces_total <- length(fitted_model$fitted.values)

  fit_stats <- c(
    McFadden          = unname(1 - ll_fitted / ll_null),
    null.deviance     = unname(-2 * ll_null),
    residual.deviance = unname(-2 * ll_fitted),
    nobs              = as.numeric(nobs_total),
    nraces            = as.numeric(nraces_total)
  )

  list(
    coefficients = coefficients,
    fit_stats    = fit_stats
  )
}
