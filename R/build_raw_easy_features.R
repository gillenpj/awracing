# build_raw_easy_features.R
# Simple per-runner features (gender flags, tack indicators, age,
# daysLTO) for Owen's conditional-logit model. Each feature comes
# straight off the qualifying-runner row; the age polynomial,
# position-lag, and strike-rate transformations live in their own
# builders (`build_age_transformation()`, `build_position_lags()`,
# `build_strike_rates()`).

#' Build the easy features: gender, tack, age, daysLTO
#'
#' Extracts the per-runner features that don't need any
#' history-dependent computation: age (passed through raw — the
#' polynomial encoding is in `build_age_transformation()`), gender
#' flags (`entire`, `gelding`), tack indicators (`blinkers`,
#' `cheekpieces`, `visor`, `tonguetie`), and days since last run in
#' both raw (`days_LTO`) and log-transformed (`days_LTO_log =
#' log(days_LTO + 1)`) form so downstream modelling can pick whichever
#' fits. NA in `days_LTO` propagates to NA in `days_LTO_log`.
#'
#' @param qualifying_runners Tibble from the qualifying_runners target.
#' @return A tibble keyed by (race_id, runner_id) with columns
#'   `name`, `won`, `age`, `days_LTO`, `days_LTO_log`, plus the
#'   integer 0/1 indicators `entire`, `gelding`, `blinkers`,
#'   `cheekpieces`, `visor`, `tonguetie`.
build_raw_easy_features <- function(qualifying_runners) {
  qualifying_runners |>
    dplyr::transmute(
      race_id,
      runner_id,
      name,
      won,
      age         = age,
      days_LTO    = days_since_ran,
      entire      = as.integer(gender %in% c("C", "H")),
      gelding     = as.integer(gender == "G"),
      blinkers    = as.integer(tidyr::replace_na(tack_blinkers, 0) == 1),
      cheekpieces = as.integer(tidyr::replace_na(tack_cheek_piece, 0) == 1),
      visor       = as.integer(tidyr::replace_na(tack_visor, 0) == 1),
      tonguetie   = as.integer(tidyr::replace_na(tack_tongue_strap, 0) == 1)
    ) |>
    dplyr::mutate(days_LTO_log = log(days_LTO + 1))
}
