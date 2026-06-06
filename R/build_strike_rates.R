# build_strike_rates.R
# Computes trainer and sire prior-career strike rate features for each
# qualifying runner-race. Cumulative wins/races are pre-aggregated in
# SQL (sql/trainer_sire_cumulative.sql); this function only does the
# per-runner lookup join, which replaces the previous in-R cumsum +
# closest-join pipeline that took >21 hours on 1.72M rows.

#' Build trainer and sire strike-rate features (Owen's trainerSR / sireSR)
#'
#' For each qualifying runner-race, looks up the trainer's and sire's
#' cumulative wins and races at the **latest meeting_date strictly
#' before** the runner's race date, then divides to get the strike rate.
#'
#' **Strictly no leakage.** If no cumulative row exists strictly before
#' the race date for that trainer or sire (first-time-starter's sire,
#' debut trainer, or unknown id), the corresponding strike rate is
#' returned as `NA` — never 0, never the closest row at-or-after, never
#' a lifetime total. NA is preferred over 0 because the downstream
#' harness `summarise_win_rate()` routes NAs to a `(missing)` bin via
#' `forcats::fct_na_value_to_level()`, keeping no-prior cases visible
#' and distinguishable from genuinely low rates in feature exploration.
#'
#' Output is raw / uncapped — any winsorisation belongs downstream.
#'
#' @param qualifying_runners Tibble from the qualifying_runners target.
#'   Provides (race_id, runner_id, trainer_id, sire_id) for the spine.
#' @param qualifying_races Tibble from the qualifying_races target.
#'   Joined on race_id to surface `meeting_date` (the race date).
#' @param trainer_sire_cumulative Tibble from the
#'   trainer_sire_cumulative target. Columns: kind ('sire' or
#'   'trainer'), entity_id, meeting_date, wins_thru_date,
#'   races_thru_date.
#' @return Tibble keyed by (race_id, runner_id) with numeric columns
#'   sireSR and trainerSR. NA where no cumulative row exists strictly
#'   before the race date.
build_strike_rates <- function(qualifying_runners,
                                qualifying_races,
                                trainer_sire_cumulative) {
  spine <- qualifying_runners |>
    dplyr::select(race_id, runner_id, trainer_id, sire_id) |>
    dplyr::inner_join(
      dplyr::select(qualifying_races, race_id, qualifying_date = meeting_date),
      by = "race_id"
    )

  # Cast wins/races to double here: RMariaDB returns SQL BIGINT as
  # `integer64` by default and `{bit64}` overloads `/` to do integer
  # division (10/100 -> 0), which would silently corrupt strike rates.
  sire_cum <- trainer_sire_cumulative |>
    dplyr::filter(kind == "sire") |>
    dplyr::transmute(
      sire_id     = entity_id,
      result_date = meeting_date,
      wins        = as.numeric(wins_thru_date),
      races       = as.numeric(races_thru_date)
    )

  trainer_cum <- trainer_sire_cumulative |>
    dplyr::filter(kind == "trainer") |>
    dplyr::transmute(
      trainer_id  = entity_id,
      result_date = meeting_date,
      wins        = as.numeric(wins_thru_date),
      races       = as.numeric(races_thru_date)
    )

  sire_sr <- spine |>
    dplyr::select(race_id, runner_id, sire_id, qualifying_date) |>
    dplyr::left_join(
      sire_cum,
      by = dplyr::join_by(sire_id, closest(qualifying_date > result_date))
    ) |>
    dplyr::transmute(
      race_id,
      runner_id,
      sireSR = wins / races
    )

  trainer_sr <- spine |>
    dplyr::select(race_id, runner_id, trainer_id, qualifying_date) |>
    dplyr::left_join(
      trainer_cum,
      by = dplyr::join_by(trainer_id, closest(qualifying_date > result_date))
    ) |>
    dplyr::transmute(
      race_id,
      runner_id,
      trainerSR = wins / races
    )

  dplyr::inner_join(sire_sr, trainer_sr, by = c("race_id", "runner_id"))
}
