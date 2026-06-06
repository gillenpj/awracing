# extract_runners.R
# Functions for pulling runner-level data from the Smartform database.
#
# `tar_source()` recursively sources every file in R/, so `db.R` is
# already loaded when these functions run inside the pipeline; the
# explicit source() here just lets the file be used standalone in an
# interactive session.

source(here::here("R", "db.R"))

#' Pull all runner rows for a set of races
#'
#' Returns every column from historic_runners for the supplied race_ids,
#' with the following adjustments applied before returning:
#'   * Rows where `unfinished == "Non-Runner"` are dropped (the horse was
#'     declared but did not start, so it has no place in the choice set).
#'   * A `won` column (integer 0/1) is added alongside `finish_position`.
#'     `won` is 1 iff the horse's official finishing position is 1,
#'     i.e. `coalesce(amended_position, finish_position) == 1`. This
#'     handles the 7 disqualified-winner races in scope where Smartform
#'     records the promoted winner via `amended_position = 1` while the
#'     DQ'd horse has `finish_position` NA'd and a note in `unfinished`.
#'     Empirically `amended_position` is NULL for unamended races (no
#'     literal 0 in any of 1.7M historic_runners rows), so a plain
#'     coalesce is safe.
#'   * Two race-level filters are applied after Non-Runner removal:
#'       - field size >= 4 *actual* starters (the SQL HAVING clause
#'         counts declared runners, so some races dip below 4 once
#'         Non-Runners are dropped — review C5).
#'       - exactly one winner per race (drops the 35 dead-heat races
#'         and any residual zero-winner races; mlogit cannot fit a
#'         choice set with !=1 chosen alternatives — review C1/C2).
#'
#' @param con      A database connection returned by connect_smartform().
#' @param race_ids Integer vector of race_id values to fetch.
#' @return A tibble of runner rows, race-level filters already applied.
extract_runners_for_races <- function(con, race_ids) {
  stopifnot(length(race_ids) > 0)

  sql <- read_sql_file("runners_for_races.sql")

  query <- DBI::sqlInterpolate(
    con,
    sql,
    race_ids = DBI::SQL(paste(race_ids, collapse = ", "))
  )

  DBI::dbGetQuery(con, query) |>
    tibble::as_tibble() |>
    dplyr::filter(is.na(unfinished) | unfinished != "Non-Runner") |>
    dplyr::mutate(
      won = dplyr::if_else(
        dplyr::coalesce(amended_position, finish_position) == 1L,
        1L, 0L,
        missing = 0L
      )
    ) |>
    dplyr::relocate(won, .after = finish_position) |>
    # Race-level filters: re-apply field-size cut after Non-Runner removal
    # (C5) and require exactly one winner per race (C1/C2 — drops the 35
    # dead-heat races and any zero-winner residue from disqualifications).
    dplyr::group_by(race_id) |>
    dplyr::filter(dplyr::n() >= 4L, sum(won) == 1L) |>
    dplyr::ungroup()
}

#' Pull the complete cross-surface career history for a set of horses
#'
#' Fetches all runs from historic_runners for the supplied runner_ids,
#' joining to historic_races to bring back race-level context. This gives
#' us each horse's full career record regardless of surface or course,
#' which is needed to build form features for the qualifying AW population.
#'
#' @param con        A database connection returned by connect_smartform().
#' @param runner_ids Integer vector of runner_id values to fetch.
#' @return A tibble with one row per career run, including race context.
extract_career_history <- function(con, runner_ids) {
  stopifnot(length(runner_ids) > 0)

  sql <- read_sql_file("horse_full_history.sql")

  query <- DBI::sqlInterpolate(
    con,
    sql,
    runner_ids = DBI::SQL(paste(runner_ids, collapse = ", "))
  )

  tibble::as_tibble(DBI::dbGetQuery(con, query))
}

#' Get the unique runner IDs from qualifying All Weather races
#'
#' These are the horses that have run at least once in a qualifying AW race.
#' All downstream analysis — career history, form features, modelling — is
#' anchored to this set of horses.
#'
#' @param qualifying_runners A tibble of runners from qualifying AW races,
#'   as returned by extract_runners_for_races().
#' @return An integer vector of unique runner_ids.
get_aw_runner_ids <- function(qualifying_runners) {
  unique(qualifying_runners$runner_id)
}
