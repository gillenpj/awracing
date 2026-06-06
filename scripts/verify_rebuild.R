# scripts/verify_rebuild.R
# Read-only integrity checks against the cached qualifying_races /
# qualifying_runners / candidate_races targets. Run after any change
# to the SQL or R-side filters.

source("renv/activate.R")

suppressPackageStartupMessages({
  library(targets)
  library(dplyr)
})

qr <- targets::tar_read(qualifying_runners)
races <- targets::tar_read(qualifying_races)
cands <- targets::tar_read(candidate_races)

cat("---- (a) Date range ----\n")
cat("min meeting_date: ", as.character(min(races$meeting_date)), "\n")
cat("max meeting_date: ", as.character(max(races$meeting_date)), "\n")
stopifnot(min(races$meeting_date) >= as.Date("2006-01-01"))
cat("OK: min >= 2006-01-01\n\n")

cat("---- (b) Race type ----\n")
print(table(races$race_type, useNA = "ifany"))
stopifnot(length(setdiff(races$race_type, "All Weather Flat")) == 0L)
cat("OK: only 'All Weather Flat'\n\n")

cat("---- (c) Courses ----\n")
print(table(races$course))
stopifnot(setequal(
  unique(races$course),
  c("Kempton", "Lingfield", "Southwell", "Wolverhampton")
))
cat("OK: only the four AW courses\n\n")

cat("---- (d) Winner integrity (qualifying_runners) ----\n")
nw <- qr |>
  dplyr::group_by(race_id) |>
  dplyr::summarise(n_winners = sum(won), .groups = "drop") |>
  dplyr::count(n_winners)
print(nw)
stopifnot(identical(nw$n_winners, 1L), nrow(nw) == 1L)
cat("OK: every race has exactly one winner\n\n")

cat("---- (e) Field sizes ----\n")
fs <- qr |>
  dplyr::count(race_id, name = "n_runners")
cat("min n_runners: ", min(fs$n_runners), "\n")
cat("max n_runners: ", max(fs$n_runners), "\n")
stopifnot(min(fs$n_runners) >= 4L)
cat("OK: min field size >= 4\n\n")

cat("---- (f) Row counts ----\n")
cat("candidate_races       (SQL output): ", nrow(cands), " races\n", sep = "")
cat("qualifying_races (final): ", nrow(races), " races\n", sep = "")
cat("qualifying_runners (final): ", nrow(qr), " runners\n", sep = "")
cat("races dropped by R-level filters: ", nrow(cands) - nrow(races), "\n\n", sep = "")

cat("---- (g) Consistency: qualifying_races vs qualifying_runners ----\n")
stopifnot(setequal(unique(qr$race_id), unique(races$race_id)))
cat("OK: both targets agree on the race set\n\n")

cat("---- (h) Class distribution (sanity) ----\n")
print(table(races$class, useNA = "ifany"))
cat("\nAll checks passed.\n")
