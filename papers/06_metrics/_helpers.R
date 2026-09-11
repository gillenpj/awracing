# _helpers.R
# Paper 6 — formatting helpers for the Quarto sections.
#
# These live here rather than under `R/` because the qmd setup chunk
# `source()`s this file directly. Defining a helper in both places would
# create two copies that could silently diverge.

#' A proportion as a percentage string
#' @param x Numeric vector.
#' @param digits Decimal places.
#' @param signed Prefix a `+` on positives.
#' @return Character vector.
p6m_pct <- function(x, digits = 1, signed = FALSE) {
  fmt <- paste0(if (signed) "%+." else "%.", digits, "f%%")
  ifelse(is.na(x), "---", sprintf(fmt, 100 * x))
}

#' A difference in ROI, in percentage points
#' @param x Numeric vector on the proportion scale.
#' @param digits Decimal places.
#' @return Character vector.
p6m_pp <- function(x, digits = 2) {
  ifelse(is.na(x), "---", sprintf("%+.*f pp", digits, 100 * x))
}

#' A 90% interval in percentage points
#' @param lo,hi Numeric vectors on the proportion scale.
#' @param digits Decimal places.
#' @return Character vector.
p6m_ci_pp <- function(lo, hi, digits = 2) {
  ifelse(is.na(lo) | is.na(hi), "---",
         sprintf("[%+.*f, %+.*f]", digits, 100 * lo, digits, 100 * hi))
}

#' A count with thousands separators
#' @param x Numeric vector.
#' @return Character vector.
p6m_n <- function(x) ifelse(is.na(x), "---", format(x, big.mark = ","))

#' Yes or no, for an interval that excludes zero
#' @param x Logical vector.
#' @return Character vector.
p6m_yn <- function(x) ifelse(is.na(x), "---", ifelse(x, "yes", "no"))

#' One row of a table, looked up by a key column
#'
#' Every figure the prose quotes goes through this, so a prose number cannot
#' drift from the table beside it.
#'
#' @param d A tibble.
#' @param col The key column name.
#' @param value The value to match.
#' @return A one-row tibble; errors if the row is not unique.
p6m_row <- function(d, col, value) {
  out <- d[d[[col]] == value, , drop = FALSE]
  if (nrow(out) != 1L) {
    stop(sprintf("p6m_row(): %d rows where %s == '%s'", nrow(out), col, value))
  }
  out
}

#' Render a tibble as a paper table
#' @param d A tibble.
#' @param caption Table caption.
#' @param ... Passed to `knitr::kable()`.
#' @return A knitr kable.
p6m_tbl <- function(d, caption, ...) {
  knitr::kable(d, caption = caption, booktabs = TRUE, linesep = "", ...)
}
