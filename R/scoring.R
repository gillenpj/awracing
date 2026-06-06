# scoring.R
# Out-of-sample evaluation helpers for the AW conditional-logit model:
# test-set per-runner predictions, market-probability construction,
# the model/market probability ratio, the betting backtest, and the
# race-level bootstrap for ROI confidence intervals.
#
# All five functions are pure (inputs -> outputs, no side effects) and
# get wired into `_targets.R` as their own targets.

#' Identify model terms whose every level is non-significant
#'
#' For each term in the full fit's coefficient table, returns the term
#' if at least one of its levels reaches p < 0.05. Factor terms
#' (`position1`, `position2`, `position3`) are grouped on the leading
#' name; plain numeric / binary terms map to themselves.
#'
#' @param model_diagnostics The list returned by
#'   `extract_model_diagnostics()` — specifically its `coefficients`
#'   tibble.
#' @return A list with two character vectors: `kept` (terms with at
#'   least one significant level) and `dropped` (terms with every
#'   level NS at the 0.05 threshold).
identify_significant_terms <- function(model_diagnostics) {
  term_of <- function(coef_name) {
    if (grepl("^position1[1-4]$", coef_name)) return("position1")
    if (grepl("^position2[1-4]$", coef_name)) return("position2")
    if (grepl("^position3[1-4]$", coef_name)) return("position3")
    coef_name
  }

  summary_tbl <- model_diagnostics$coefficients |>
    dplyr::mutate(term = vapply(parameter, term_of, character(1))) |>
    dplyr::group_by(term) |>
    dplyr::summarise(
      any_sig = any(!is.na(p.value) & p.value < 0.05),
      .groups = "drop"
    )

  list(
    kept    = summary_tbl$term[ summary_tbl$any_sig],
    dropped = summary_tbl$term[!summary_tbl$any_sig]
  )
}

#' Fit the reduced (post-pruning) conditional-logit
#'
#' Applies the standard p > 0.05 reduction rule to the full fit's
#' coefficient table and refits on the same training data. The
#' three-part `| 0 | 0` matches Owen's reference script and matches
#' the formula used by `fit_conditional_logit()` in the full fit.
#'
#' @param mlogit_train_data  Output of `prepare_mlogit_data()` for the
#'   training subset.
#' @param model_diagnostics  As above.
#' @return The fitted `mlogit` object for the reduced specification.
fit_reduced_model <- function(mlogit_train_data, model_diagnostics) {
  terms <- identify_significant_terms(model_diagnostics)
  if (length(terms$kept) == 0L) {
    stop("All terms were non-significant at p > 0.05; cannot build reduced model.")
  }

  final_formula <- stats::as.formula(
    paste("won ~", paste(terms$kept, collapse = " + "), "| 0 | 0")
  )

  mlogit::mlogit(final_formula, data = mlogit_train_data)
}

#' Build the per-runner test-set predictions tibble
#'
#' Joins the test-set fitted probabilities (from `predict.mlogit`) to
#' the per-runner test rows, attaches the runner's starting price, and
#' computes the over-round-adjusted market-implied probability for
#' each runner. The output is the canonical tibble consumed by §3.3
#' calibration / scoring chunks and by every §3.4 backtest step.
#'
#' Padded slots (the `max_field_size − n_runners_in_race` zero-
#' probability columns inside `predict.mlogit`'s output) are stripped
#' by filtering on `model_prob > 0`.
#'
#' @param fitted_final       The reduced mlogit fit (trained on the
#'   training set).
#' @param mlogit_test_data   Output of `prepare_mlogit_data()` for the
#'   test subset.
#' @param qualifying_runners The runner-level tibble; supplies
#'   `starting_price_decimal` and `won`.
#' @return A tibble keyed by (race_id, runner_id) with columns
#'   `race_id`, `runner_id`, `horse_ref`, `won`, `model_prob`,
#'   `starting_price_decimal`, `market_prob`. Rows with NA / missing
#'   SP are kept (so the table is comparable across §3.3 / §3.4
#'   chunks) but `market_prob` is NA for them; downstream filters
#'   handle.
build_test_predictions <- function(fitted_final, mlogit_test_data,
                                   qualifying_runners) {
  loadNamespace("mlogit")

  probs_mat <- stats::predict(fitted_final, newdata = mlogit_test_data)

  model_probs_long <- probs_mat |>
    as.data.frame() |>
    tibble::rownames_to_column("race_id") |>
    tidyr::pivot_longer(
      cols      = -race_id,
      names_to  = "horse_ref",
      values_to = "model_prob"
    ) |>
    dplyr::filter(!is.na(model_prob), model_prob > 0) |>
    dplyr::mutate(
      race_id   = as.integer(race_id),
      horse_ref = as.integer(horse_ref)
    )

  mldat_df <- as.data.frame(mlogit_test_data)
  class(mldat_df) <- "data.frame"
  attr(mldat_df, "index")    <- NULL
  attr(mldat_df, "clseries") <- NULL

  base <- mldat_df |>
    dplyr::select(race_id, runner_id, horse_ref, won) |>
    dplyr::mutate(
      race_id   = as.integer(race_id),
      horse_ref = as.integer(horse_ref),
      won       = as.integer(won)
    ) |>
    dplyr::inner_join(model_probs_long, by = c("race_id", "horse_ref"))

  sp_lookup <- qualifying_runners |>
    dplyr::select(race_id, runner_id, starting_price_decimal)

  base |>
    dplyr::left_join(sp_lookup, by = c("race_id", "runner_id")) |>
    dplyr::group_by(race_id) |>
    dplyr::mutate(
      implied_raw = dplyr::if_else(
        !is.na(starting_price_decimal) & starting_price_decimal > 1,
        1 / starting_price_decimal,
        NA_real_
      ),
      market_prob = implied_raw / sum(implied_raw, na.rm = TRUE)
    ) |>
    dplyr::ungroup() |>
    dplyr::select(-implied_raw)
}

#' Compute the model / market probability ratio per test runner
#'
#' Drops rows where either probability is unavailable (missing SP, or
#' a runner that the model could not score). Required input for the
#' bet-selection step.
#'
#' @param test_predictions Output of `build_test_predictions()`.
#' @return The same tibble filtered to rows with both probabilities
#'   defined, plus a `ratio = model_prob / market_prob` column.
compute_model_market_ratio <- function(test_predictions) {
  test_predictions |>
    dplyr::filter(
      !is.na(model_prob),  model_prob  > 0,
      !is.na(market_prob), market_prob > 0
    ) |>
    dplyr::mutate(ratio = model_prob / market_prob)
}

#' Single-threshold backtest
#'
#' Selects runner-rows where `model_prob > prob_threshold` AND
#' `ratio > ratio_threshold`, stakes one unit on each, computes total
#' return and ROI. Returns are decimal odds × win indicator (so SP =
#' 5.0 on a winning horse returns 5 units, of which 1 was the stake).
#'
#' @param ratio_df          Output of `compute_model_market_ratio()`.
#' @param prob_threshold    Lower bound on model probability (Owen
#'   uses 0.15 in §3.4 of the paper).
#' @param ratio_threshold   Lower bound on model/market ratio (Owen
#'   uses 1.3 in §3.4).
#' @return A one-row tibble: `prob_threshold`, `ratio_threshold`,
#'   `n_bets`, `n_wins`, `gross_return`, `profit`, `roi`. ROI is
#'   `(gross_return - n_bets) / n_bets`; NA if no bets selected.
run_backtest <- function(ratio_df, prob_threshold, ratio_threshold) {
  bets <- ratio_df |>
    dplyr::filter(model_prob > prob_threshold,
                  ratio       > ratio_threshold)

  n_bets <- nrow(bets)

  if (n_bets == 0L) {
    return(tibble::tibble(
      prob_threshold  = prob_threshold,
      ratio_threshold = ratio_threshold,
      n_bets          = 0L,
      n_wins          = 0L,
      gross_return    = 0,
      profit          = 0,
      roi             = NA_real_
    ))
  }

  bets <- bets |>
    dplyr::mutate(
      return_unit = dplyr::if_else(
        won == 1L,
        starting_price_decimal,
        0
      )
    )

  gross_return <- sum(bets$return_unit)
  profit       <- gross_return - n_bets

  tibble::tibble(
    prob_threshold  = prob_threshold,
    ratio_threshold = ratio_threshold,
    n_bets          = as.integer(n_bets),
    n_wins          = sum(bets$won == 1L),
    gross_return    = gross_return,
    profit          = profit,
    roi             = profit / n_bets
  )
}

#' Bootstrap ROI confidence interval at one ratio threshold
#'
#' Resamples **races** (not runner-rows) with replacement `n_boot`
#' times, computes ROI on the resampled bet set for each draw, and
#' returns the bootstrap distribution. Race-level resampling
#' preserves the one-winner-per-race structure that runner-level
#' resampling would destroy.
#'
#' If a race contains no bets at the given thresholds it contributes
#' nothing to the ROI denominator; if the resample selects zero bets
#' overall, ROI for that draw is NA and excluded from percentile
#' summaries.
#'
#' @param ratio_df         Output of `compute_model_market_ratio()`.
#' @param prob_threshold   As above.
#' @param ratio_threshold  As above.
#' @param n_boot           Number of bootstrap draws. Default 2000.
#' @return A numeric vector of length `n_boot` of bootstrap ROI
#'   replicates (NA where no bets in the draw).
bootstrap_roi <- function(ratio_df, prob_threshold, ratio_threshold,
                          n_boot = 2000L) {
  bets <- ratio_df |>
    dplyr::filter(model_prob > prob_threshold,
                  ratio       > ratio_threshold) |>
    dplyr::mutate(
      return_unit = dplyr::if_else(won == 1L, starting_price_decimal, 0)
    ) |>
    dplyr::select(race_id, return_unit)

  if (nrow(bets) == 0L) return(rep(NA_real_, n_boot))

  per_race <- bets |>
    dplyr::group_by(race_id) |>
    dplyr::summarise(
      n_bets       = dplyr::n(),
      gross_return = sum(return_unit),
      .groups      = "drop"
    )

  race_ids <- per_race$race_id
  n_races  <- length(race_ids)

  # Index lookup so we can vectorise per-race contributions.
  n_bets_vec <- per_race$n_bets
  gross_vec  <- per_race$gross_return

  out <- vapply(seq_len(n_boot), function(b) {
    idx       <- sample.int(n_races, size = n_races, replace = TRUE)
    nb        <- sum(n_bets_vec[idx])
    if (nb == 0L) return(NA_real_)
    gr        <- sum(gross_vec[idx])
    (gr - nb) / nb
  }, numeric(1))

  out
}

#' Bootstrap-CI ROI sweep across ratio thresholds
#'
#' For each `tau` in `tau_seq`, runs the point-estimate backtest plus
#' a `n_boot`-replicate race-level bootstrap, returning point ROI and
#' the 5th / 95th percentiles of the bootstrap distribution (a 90%
#' CI). The `seed` is set once at the top of the sweep so the entire
#' sweep is reproducible.
#'
#' @param ratio_df        Output of `compute_model_market_ratio()`.
#' @param prob_threshold  Lower bound on model probability held fixed
#'   across the sweep.
#' @param tau_seq         Numeric vector of ratio thresholds.
#' @param n_boot          Number of bootstrap draws per threshold.
#' @param seed            RNG seed; default 42.
#' @return A long tibble with columns `tau`, `n_bets`, `n_wins`,
#'   `roi`, `ci_lo`, `ci_hi`.
run_backtest_sweep <- function(ratio_df, prob_threshold, tau_seq,
                               n_boot = 2000L, seed = 42L) {
  set.seed(seed)

  point <- purrr::map_dfr(tau_seq, \(tau) {
    run_backtest(ratio_df,
                 prob_threshold  = prob_threshold,
                 ratio_threshold = tau) |>
      dplyr::transmute(tau = tau, n_bets, n_wins, roi)
  })

  ci <- purrr::map_dfr(tau_seq, \(tau) {
    boot <- bootstrap_roi(ratio_df,
                          prob_threshold  = prob_threshold,
                          ratio_threshold = tau,
                          n_boot          = n_boot)
    tibble::tibble(
      tau   = tau,
      ci_lo = stats::quantile(boot, 0.05, na.rm = TRUE, names = FALSE),
      ci_hi = stats::quantile(boot, 0.95, na.rm = TRUE, names = FALSE)
    )
  })

  dplyr::left_join(point, ci, by = "tau")
}

#' Plot ROI vs ratio threshold with bootstrap CI band
#'
#' Owen's Figure 9 analogue: x = ratio threshold, y = ROI, point
#' estimate as a solid line, 90% CI as a shaded ribbon. A horizontal
#' reference line at zero marks break-even.
#'
#' @param sweep_df  Output of `run_backtest_sweep()`.
#' @return A ggplot object.
plot_roi_sweep <- function(sweep_df) {
  ggplot2::ggplot(sweep_df, ggplot2::aes(x = tau, y = roi)) +
    ggplot2::geom_hline(yintercept = 0, linetype = "dashed", colour = "grey50") +
    ggplot2::geom_ribbon(
      ggplot2::aes(ymin = ci_lo, ymax = ci_hi),
      fill  = "steelblue", alpha = 0.20
    ) +
    ggplot2::geom_line(linewidth = 0.8, colour = "steelblue") +
    ggplot2::scale_y_continuous(labels = scales::percent_format(accuracy = 1)) +
    ggplot2::labs(
      x = "Ratio threshold (model_prob / market_prob)",
      y = "ROI"
    ) +
    ggplot2::theme_minimal()
}
