# build_age_transformation.R
# Age feature transformation for Owen's conditional-logit model.

#' Build Owen-style symmetric-distance age feature keyed by (race_id, runner_id)
#'
#' Owen (2019) models the age effect via a symmetric "distance from
#' peak" representation: `age_diff = |age - peak|`. The fitted effect
#' is V-shaped in the linear predictor (peak win rate at the chosen
#' age, declining symmetrically either side), at the cost of forcing
#' the same falloff on both sides.
#'
#' Owen takes the peak as **age 4.5**, citing published thoroughbred
#' peak-age evidence. For UK All-Weather Flat we deviate in two
#' ways: the empirical AW peak sits closer to
#' **age 3** (AW campaigns are disproportionately run by
#' faster-maturing horses), and we **cap** the unsigned offset at 5
#' so the effect does not extrapolate into thin-support ages (>= 9);
#' above age 8 the empirical bins carry too few starters to anchor
#' the slope, so we hold `age_diff` fixed there. Concretely:
#' `age_diff = pmin(|age - 3|, 5)`.
#'
#' An earlier version of this function also returned
#' `age_diff_sq = age_diff^2` for a quadratic bowl-shape; the
#' squared term was dropped after diagnostics showed the linear
#' `age_diff` alone gave a more sensible fit.
#'
#' @param raw_easy_features Tibble from the raw_easy_features target.
#'   Must carry `race_id`, `runner_id`, and `age`.
#' @return A tibble keyed by (race_id, runner_id) with one numeric
#'   column `age_diff`. NA in input `age` propagates through `pmin()`.
build_age_transformation <- function(raw_easy_features) {
  raw_easy_features |>
    dplyr::transmute(
      race_id,
      runner_id,
      age_diff = pmin(abs(age - 3), 5)
    )
}
