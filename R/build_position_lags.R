# build_position_lags.R
# Prior-finish-position lag features for Owen's conditional-logit model.

#' Build prior-finish-position lag features (Owen's position1/2/3)
#'
#' For each (race_id, runner_id) in `qualifying_runners`, finds the
#' runner's three most recent runs in `full_history` strictly before the
#' qualifying race's meeting_date (Non-Runners excluded). Each lag is
#' encoded as the integer position when it falls in {1,2,3,4}; otherwise
#' (worse finish, no prior run, or unknown position) it is set to 0.
#' Encoded values are then converted to factors so {mlogit} treats them
#' as categorical and dummy-codes them automatically, with level "0"
#' serving as the (omitted) reference category. Output contains no NAs.
#'
#' @param qualifying_runners Tibble from the qualifying_runners target.
#'   Provides the (race_id, runner_id) spine.
#' @param full_history Tibble from the full_history target. Source of
#'   prior runs; uses `meeting_date` for ordering, `unfinished` to drop
#'   Non-Runners, and `coalesce(amended_position, finish_position)` for
#'   the actual finish (consistent with the `won` rule elsewhere).
#' @param qualifying_races Tibble from the qualifying_races target.
#'   Needed because `qualifying_runners` does not carry `meeting_date`;
#'   joined on `race_id` to date each runner-race observation.
#' @return Tibble keyed by (race_id, runner_id) with factor columns
#'   position1, position2, position3 with levels c("0","1","2","3","4").
#'   Level "0" is the reference (no prior run, or finished worse than
#'   4th).
build_position_lags <- function(qualifying_runners, full_history, qualifying_races) {
  encode_position <- function(p) {
    dplyr::if_else(!is.na(p) & p >= 1L & p <= 4L, as.integer(p), 0L)
  }

  spine <- qualifying_runners |>
    dplyr::select(race_id, runner_id) |>
    dplyr::inner_join(
      dplyr::select(qualifying_races, race_id, qualifying_date = meeting_date),
      by = "race_id"
    )

  history <- full_history |>
    dplyr::filter(is.na(unfinished) | unfinished != "Non-Runner") |>
    dplyr::transmute(
      runner_id,
      hist_date = meeting_date,
      position  = dplyr::coalesce(amended_position, finish_position)
    )

  lags_wide <- spine |>
    dplyr::inner_join(history, by = "runner_id", relationship = "many-to-many") |>
    dplyr::filter(hist_date < qualifying_date) |>
    dplyr::group_by(race_id, runner_id) |>
    dplyr::arrange(dplyr::desc(hist_date), .by_group = TRUE) |>
    dplyr::mutate(lag_index = dplyr::row_number()) |>
    dplyr::ungroup() |>
    dplyr::filter(lag_index <= 3L) |>
    dplyr::mutate(lag_index = paste0("position", lag_index)) |>
    tidyr::pivot_wider(
      id_cols     = c(race_id, runner_id),
      names_from  = lag_index,
      values_from = position
    )

  for (col in setdiff(c("position1", "position2", "position3"), names(lags_wide))) {
    lags_wide[[col]] <- NA_integer_
  }

  spine |>
    dplyr::select(race_id, runner_id) |>
    dplyr::left_join(lags_wide, by = c("race_id", "runner_id")) |>
    dplyr::transmute(
      race_id,
      runner_id,
      position1 = encode_position(position1),
      position2 = encode_position(position2),
      position3 = encode_position(position3)
    ) |>
    dplyr::mutate(
      position1 = factor(position1, levels = c("0", "1", "2", "3", "4")),
      position2 = factor(position2, levels = c("0", "1", "2", "3", "4")),
      position3 = factor(position3, levels = c("0", "1", "2", "3", "4"))
    )
}
