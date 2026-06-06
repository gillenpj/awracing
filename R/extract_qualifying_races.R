# extract_qualifying_races.R
# Extracts qualifying All Weather races from the Smartform database.
#
# `tar_source()` recursively sources every file in R/, so `db.R` is
# already loaded when this function runs inside the pipeline; the
# explicit source() here just lets the file be used standalone in an
# interactive session.

source(here::here("R", "db.R"))

#' Extract qualifying races from the Smartform database
#'
#' Pulls the All Weather Flat races meeting the qualifying criteria
#' defined in `sql/qualifying_races.sql`. The course list is passed in
#' (rather than hard-coded in the SQL) so it lives in one place — the
#' `aw_courses` target in `_targets.R`.
#'
#' @param con        A database connection returned by connect_smartform().
#' @param date_from  Start of the date window (character "YYYY-MM-DD" or Date).
#' @param date_to    End of the date window   (character "YYYY-MM-DD" or Date).
#' @param aw_courses Character vector of AW course names to include.
#' @return A tibble of qualifying races.
extract_qualifying_races <- function(con, date_from, date_to, aw_courses) {
  stopifnot(length(aw_courses) > 0)

  sql <- read_sql_file("qualifying_races.sql")

  course_list <- DBI::SQL(paste(
    DBI::dbQuoteString(con, aw_courses),
    collapse = ", "
  ))

  query <- DBI::sqlInterpolate(
    con,
    sql,
    date_from  = as.character(date_from),
    date_to    = as.character(date_to),
    aw_courses = course_list
  )

  tibble::as_tibble(DBI::dbGetQuery(con, query))
}
