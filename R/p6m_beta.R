# p6m_beta.R
# Paper 6, Section 3 — how much of the model's disagreement with the overnight
# price the market later accepts.
#
# Speculative. Nothing else in the paper rests on it.
#
# The regression, on the test split and on the encoder's stored predictions:
#
#   logit(p_close) - logit(p_fcst) ~ logit(p_hat) - logit(p_fcst)
#
# where `p_close` is the over-round-adjusted settled starting price, `p_fcst`
# the renormalised overnight racecard forecast price, and `p_hat` the
# encoder's probability. All three are the same columns Section 2 scores, on
# the same rows, so the forecast-price requirement bites in exactly the same
# place.
#
# Standard errors are a RACE-LEVEL BOOTSTRAP, B = 2000, seed 42, which is the
# resampling unit and the replicate count used everywhere else in the series.
# The alternative was race-clustered analytic errors; the bootstrap is chosen
# for consistency with every other interval in this paper.
#
# The pooled coefficient only. No breakdown by price band, field size or
# anything else.

#' The logit of a probability
#' @param p Numeric vector strictly inside (0, 1).
#' @return Numeric vector.
p6m_logit <- function(p) {
  stopifnot(all(p > 0), all(p < 1))
  log(p / (1 - p))
}

#' Ordinary-least-squares intercept and slope, in closed form
#'
#' A single-predictor fit, so the closed form is used rather than `lm()`: the
#' bootstrap refits it 2000 times. `p6m_beta_fit()` asserts it agrees with
#' `stats::lm()` on the full sample before the bootstrap runs.
#'
#' @param x,y Numeric vectors of equal length.
#' @return A length-two numeric vector, intercept then slope.
p6m_ols <- function(x, y) {
  mx <- mean(x)
  my <- mean(y)
  sxx <- sum((x - mx)^2)
  slope <- if (sxx == 0) NA_real_ else sum((x - mx) * (y - my)) / sxx
  c(intercept = my - slope * mx, slope = slope)
}

#' Fit the Section 3 regression, with race-level bootstrap standard errors
#'
#' @param panel The Section 2 panel: `race_id`, `p_5`, `p_sp`, `p_fc`.
#' @param n_boot,seed Bootstrap replicates and RNG seed.
#' @return A tibble, one row per coefficient, plus the sample counts.
p6m_beta_fit <- function(panel, n_boot = 2000L, seed = 42L) {
  y <- p6m_logit(panel$p_sp) - p6m_logit(panel$p_fc)
  x <- p6m_logit(panel$p_5)  - p6m_logit(panel$p_fc)

  point <- p6m_ols(x, y)

  # The closed form must agree with lm() on the full sample, or the 2000
  # bootstrap refits are not fits of the stated regression.
  ref <- stats::coef(stats::lm(y ~ x))
  stopifnot(max(abs(unname(point) - unname(ref))) < 1e-9)

  races <- sort(unique(panel$race_id))
  n <- length(races)
  by_race <- split(seq_along(y), match(panel$race_id, races))

  set.seed(seed)
  reps <- matrix(NA_real_, nrow = n_boot, ncol = 2L,
                 dimnames = list(NULL, c("intercept", "slope")))
  for (b in seq_len(n_boot)) {
    idx <- unlist(by_race[sample.int(n, n, replace = TRUE)], use.names = FALSE)
    reps[b, ] <- p6m_ols(x[idx], y[idx])
  }

  tibble::tibble(
    term = c("intercept", "slope"),
    estimate = unname(point),
    se = c(stats::sd(reps[, "intercept"]), stats::sd(reps[, "slope"])),
    ci_lo = c(stats::quantile(reps[, "intercept"], 0.05, names = FALSE),
              stats::quantile(reps[, "slope"], 0.05, names = FALSE)),
    ci_hi = c(stats::quantile(reps[, "intercept"], 0.95, names = FALSE),
              stats::quantile(reps[, "slope"], 0.95, names = FALSE)),
    n_rows = nrow(panel),
    n_races = n,
    n_boot = n_boot,
    se_method = "race-level bootstrap"
  )
}

#' Paper 4's published coefficients, read live from its own store
#'
#' Section 3 cites paper 4's result rather than re-arguing it. The figures are
#' pulled from paper 4's stored fits instead of transcribed, so the citation
#' cannot drift from the paper it cites. Arm B is the settled starting price,
#' arm A the pre-race feed forecast price; the SP figure paper 4 leads on is
#' the pooled fit, the forecast figures are the two test halves.
#'
#' @param pooled Paper 4's `p4_arm_grid_pooled$coefficients`.
#' @param half_a,half_b Paper 4's `p4_arm_grid$coefficients` and
#'   `p4_arm_grid_b$coefficients`.
#' @return A tibble of the cited coefficients.
p6m_p4_cited_fits <- function(pooled, half_a, half_b) {
  pick <- function(d, arm_prefix, label) {
    d |>
      dplyr::filter(grepl(paste0("^", arm_prefix), arm),
                    grepl("^log_p_mod_", term)) |>
      dplyr::transmute(
        benchmark = label,
        sample = sample,
        model = dplyr::if_else(grepl("2b$", term), "paper 2b logit",
                               "paper 3 GBT"),
        estimate, std_error, conf_low, conf_high, n_races
      )
  }
  out <- dplyr::bind_rows(
    pick(pooled, "B", "settled starting price"),
    pick(half_a, "A", "overnight forecast price"),
    pick(half_b, "A", "overnight forecast price")
  )
  stopifnot(nrow(out) == 6L)
  out
}
