# p4_schema_probe.R
# P4-0 item 1: where forecast_price_decimal lives, its type, and any
# sibling columns that speak to the timing semantics of the forecast price.
# Read-only. Run: Rscript papers/04_market_blend/audit/p4_schema_probe.R

source("renv/activate.R")
suppressPackageStartupMessages({
  library(DBI)
})
source("R/db.R")

con <- connect_smartform()
on.exit(disconnect_smartform(con))

dbname <- DBI::dbGetQuery(con, "SELECT DATABASE() AS db")$db
cat("## Database:", dbname, "\n\n")

cat("### Tables in schema\n")
tabs <- DBI::dbGetQuery(con, sprintf(
  "SELECT table_name, table_rows, engine
     FROM information_schema.tables
    WHERE table_schema = '%s'
    ORDER BY table_name", dbname))
print(tabs, row.names = FALSE)

cat("\n### Every column named like a price / forecast / odds, anywhere in the schema\n")
cols <- DBI::dbGetQuery(con, sprintf(
  "SELECT table_name, column_name, column_type, is_nullable, column_default, column_comment
     FROM information_schema.columns
    WHERE table_schema = '%s'
      AND (column_name LIKE '%%price%%'
        OR column_name LIKE '%%forecast%%'
        OR column_name LIKE '%%odds%%'
        OR column_name LIKE '%%sp%%'
        OR column_name LIKE '%%market%%'
        OR column_name LIKE '%%bet%%')
    ORDER BY table_name, ordinal_position", dbname))
print(cols, row.names = FALSE)

cat("\n### Full column list for historic_runners\n")
hr <- DBI::dbGetQuery(con, sprintf(
  "SELECT ordinal_position, column_name, column_type, is_nullable, column_comment
     FROM information_schema.columns
    WHERE table_schema = '%s' AND table_name = 'historic_runners'
    ORDER BY ordinal_position", dbname))
print(hr, row.names = FALSE)

cat("\n### Full column list for historic_races\n")
hrc <- DBI::dbGetQuery(con, sprintf(
  "SELECT ordinal_position, column_name, column_type, is_nullable, column_comment
     FROM information_schema.columns
    WHERE table_schema = '%s' AND table_name = 'historic_races'
    ORDER BY ordinal_position", dbname))
print(hrc, row.names = FALSE)

cat("\n### Table-level comments (may name the feed / source doc)\n")
tc <- DBI::dbGetQuery(con, sprintf(
  "SELECT table_name, table_comment FROM information_schema.tables
    WHERE table_schema = '%s' AND table_comment <> ''", dbname))
print(tc, row.names = FALSE)

cat("\n### Raw value shape of forecast_price_decimal (whole table, no filters)\n")
shape <- DBI::dbGetQuery(con, "
  SELECT COUNT(*) AS n_rows,
         SUM(forecast_price_decimal IS NULL) AS n_null,
         SUM(forecast_price_decimal = 0)     AS n_zero,
         SUM(forecast_price_decimal < 0)     AS n_negative,
         SUM(forecast_price_decimal = 1)     AS n_exactly_one,
         SUM(forecast_price_decimal > 0 AND forecast_price_decimal < 1) AS n_between_0_1,
         MIN(NULLIF(forecast_price_decimal, 0)) AS min_nonzero,
         MAX(forecast_price_decimal)            AS max_val
    FROM historic_runners")
print(t(shape))

cat("\n### 30 most common forecast_price_decimal values (whole table)\n")
common <- DBI::dbGetQuery(con, "
  SELECT forecast_price_decimal AS v, COUNT(*) AS n
    FROM historic_runners
   WHERE forecast_price_decimal IS NOT NULL
   GROUP BY forecast_price_decimal
   ORDER BY n DESC
   LIMIT 30")
print(common, row.names = FALSE)

cat("\n### Same for starting_price_decimal, for comparison\n")
common_sp <- DBI::dbGetQuery(con, "
  SELECT starting_price_decimal AS v, COUNT(*) AS n
    FROM historic_runners
   WHERE starting_price_decimal IS NOT NULL
   GROUP BY starting_price_decimal
   ORDER BY n DESC
   LIMIT 30")
print(common_sp, row.names = FALSE)
