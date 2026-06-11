# db.R
# Functions for connecting to and disconnecting from the Smartform MySQL
# database, and for reading SQL files from disk.

#' Load database configuration from .env file
connect_smartform <- function() {
  dotenv::load_dot_env(here::here(".env"))

  required_vars <- c("DB_HOST", "DB_PORT", "DB_NAME", "DB_USER", "DB_PASSWORD")
  missing <- required_vars[!nzchar(Sys.getenv(required_vars))]
  if (length(missing) > 0) {
    stop("Missing required environment variables: ", paste(missing, collapse = ", "))
  }

  DBI::dbConnect(
    RMariaDB::MariaDB(),
    host     = Sys.getenv("DB_HOST"),
    port     = as.integer(Sys.getenv("DB_PORT")),
    dbname   = Sys.getenv("DB_NAME"),
    user     = Sys.getenv("DB_USER"),
    password = Sys.getenv("DB_PASSWORD")
  )
}

#' Disconnect from the Smartform database
disconnect_smartform <- function(con) {
  DBI::dbDisconnect(con)
  message("Disconnected from Smartform database.")
}

#' Read a SQL file from the sql/ directory
read_sql_file <- function(filename) {
  readr::read_file(here::here("sql", filename))
}

#' Pull pre-aggregated trainer/sire/jockey cumulative wins and races
#'
#' Returns one row per (entity, meeting_date) where entity is a sire,
#' a trainer, or a jockey (distinguished by the `kind` column). Within
#' each entity, `wins_thru_date` and `races_thru_date` are cumulative
#' totals through end of `meeting_date` (inclusive); `aw_wins_thru_date`
#' and `aw_races_thru_date` are the same totals restricted to the
#' All-Weather Flat surface. All are computed in SQL via window
#' functions over the full historic_runners universe. This is the
#' input to `build_strike_rates()` (trainer/sire overall columns) and
#' to `build_jockey_sr_and_premiums()` (jockey rows + AW columns).
#' Window-function aggregation in SQL replaces an earlier in-R
#' `cumsum()` step that took >21 hours on the unaggregated 1.72M-row
#' source.
#'
#' Manages its own DB connection internally — no `con` parameter,
#' unlike the other extractors in `R/extract_runners.R`.
#'
#' @return A tibble with columns kind, entity_id, meeting_date,
#'   wins_thru_date, races_thru_date, aw_wins_thru_date,
#'   aw_races_thru_date.
extract_trainer_sire_cumulative <- function() {
  con <- connect_smartform()
  on.exit(disconnect_smartform(con))

  sql <- read_sql_file("trainer_sire_cumulative.sql")
  tibble::as_tibble(DBI::dbGetQuery(con, sql))
}
