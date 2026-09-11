# p6_paper.R
# Paper 6 — targets and helpers the Quarto document reads.
#
# ONE job: the price-band regression, promoted out of `DIAGNOSTICS.md` so
# section 3 of the paper cites a live target rather than a transcribed number.
#
# The paper's formatting and lookup helpers deliberately live in
# `papers/06_betting_strategy/_helpers.R` instead, not here. Files under `R/`
# are `source()`d into the caller's global environment and `_helpers.R` is
# `source()`d by the qmd's setup chunk, so a helper defined in both places
# would exist twice and the two copies could silently diverge (CLAUDE.md,
# "Standing conventions", on same-named helpers). One definition, in the file
# the renderer actually reads.

# ---------------------------------------------------------------------------
# The price-band regression
# ---------------------------------------------------------------------------

#' How much of the search surface is a price band rather than picking
#'
#' Regresses each rule's ROI on the mean starting price it backs, across the
#' threshold family's rules that place at least `min_bets` bets. Reported per
#' bet type. Owen's own row is located on the fit so its residual — the part
#' of its return the price band does NOT explain — is reportable.
#'
#' @param sweep The threshold-family sweep on the validation slice.
#' @param min_bets Minimum bets for a rule to enter the regression.
#' @return A tibble, one row per bet type.
p6_price_band_regression <- function(sweep, min_bets = 300L) {
  bets <- unique(sweep$bet)
  purrr::map(bets, function(b) {
    d <- sweep |>
      dplyr::filter(bet == b, !is.na(roi), !is.na(mean_sp),
                    n_bets >= min_bets, mean_sp > 0)
    if (nrow(d) < 20L) {
      return(tibble::tibble(bet = b, n_rules = nrow(d)))
    }
    fit <- stats::lm(roi ~ stats::poly(log(mean_sp), 2), data = d)
    d$fitted <- stats::predict(fit)
    d$resid <- stats::resid(fit)
    o <- d |>
      dplyr::filter(picker == "P5", !no_filter,
                    abs(p_cut - 0.15) < 1e-9, abs(r_cut - 1.30) < 1e-9)
    tibble::tibble(
      bet = b,
      n_rules = nrow(d),
      cor_roi_price = stats::cor(d$roi, d$mean_sp),
      cor_roi_logprice = stats::cor(d$roi, log(d$mean_sp)),
      r_squared = summary(fit)$r.squared,
      resid_sd = stats::sd(d$resid),
      price_at_fitted_peak = d$mean_sp[which.max(d$fitted)],
      median_roi = stats::median(d$roi),
      owen_roi = if (nrow(o) == 1L) o$roi else NA_real_,
      owen_price = if (nrow(o) == 1L) o$mean_sp else NA_real_,
      owen_fitted = if (nrow(o) == 1L) o$fitted else NA_real_,
      owen_resid = if (nrow(o) == 1L) o$resid else NA_real_,
      owen_resid_sd_units = if (nrow(o) == 1L)
        o$resid / stats::sd(d$resid) else NA_real_,
      owen_rank = if (nrow(o) == 1L) sum(d$roi > o$roi) + 1L else NA_integer_
    )
  }) |> purrr::list_rbind()
}
