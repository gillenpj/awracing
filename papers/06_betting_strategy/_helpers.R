# _helpers.R
# Paper 6 — formatting and lookup helpers for the Quarto sections.
#
# These live here rather than under `R/` because the qmd setup chunk
# `source()`s this file directly. Defining them in both places would create
# two copies that could silently diverge, which CLAUDE.md's convention on
# same-named helpers exists to prevent. The one paper-6 function that IS a
# target — `p6_price_band_regression()` — stays in `R/p6_paper.R`.

#' A proportion as a percentage string
#' @param x Numeric vector.
#' @param digits Decimal places.
#' @param signed Prefix a `+` on positives.
#' @return Character vector.
p6_fpct <- function(x, digits = 1, signed = FALSE) {
  fmt <- paste0(if (signed) "%+." else "%.", digits, "f%%")
  ifelse(is.na(x), "---", sprintf(fmt, 100 * x))
}

#' A price to two decimals
#' @param x Numeric vector.
#' @return Character vector.
p6_fprice <- function(x) ifelse(is.na(x), "---", sprintf("%.2f", x))

#' A count with thousands separators
#' @param x Numeric vector.
#' @return Character vector.
p6_fn <- function(x) ifelse(is.na(x), "---", format(x, big.mark = ","))

#' A 90% interval as a bracketed percentage range
#' @param lo,hi Numeric vectors.
#' @return Character vector.
p6_fci <- function(lo, hi) {
  ifelse(is.na(lo) | is.na(hi), "---",
         sprintf("[%s, %s]", p6_fpct(lo, 1, TRUE), p6_fpct(hi, 1, TRUE)))
}

#' A correlation to three decimals, signed
#' @param x Numeric vector.
#' @return Character vector.
p6_fcor <- function(x) ifelse(is.na(x), "---", sprintf("%+.3f", x))

#' The bet-type labels used in the paper's tables
#' @return A named character vector.
p6_bet_labels <- function() {
  c(win = "Win", place = "Place",
    eachway = "Each-way (paper 5 terms)",
    eachway_corrected = "Each-way (corrected terms)")
}

#' One row of a scored table, looked up by rule and bet
#'
#' Every figure the paper's prose quotes goes through this, so a prose number
#' cannot drift from the table beside it.
#'
#' @param d A scored tibble carrying `bet` and `rule`.
#' @param bet,rule The row to fetch.
#' @return A one-row tibble; errors if the row is not unique.
p6_row <- function(d, bet, rule) {
  out <- d |> dplyr::filter(.data$bet == .env$bet, .data$rule == .env$rule)
  if (nrow(out) != 1L) {
    stop(sprintf("p6_row(): %d rows for bet '%s', rule '%s'",
                 nrow(out), bet, rule))
  }
  out
}

#' The best row of a scored table within one bet type
#' @param d A scored tibble.
#' @param bet The bet type.
#' @param by The column to maximise.
#' @return A one-row tibble.
p6_best <- function(d, bet, by = "roi") {
  out <- d |> dplyr::filter(.data$bet == .env$bet, !is.na(.data[[by]]))
  stopifnot(nrow(out) > 0L)
  out[which.max(out[[by]]), ]
}

#' A leaderboard for one bet type, optionally within one sub-family
#'
#' @param sweep A sweep output carrying `rule`, `roi`, `mean_sp` and friends.
#' @param bet The bet type.
#' @param subfamily Optional sub-family filter.
#' @param n How many rows.
#' @return A presentation tibble.
p6_leader <- function(sweep, bet, subfamily = NULL, n = 10L) {
  d <- sweep |> dplyr::filter(.data$bet == .env$bet, !is.na(.data$roi))
  if (!is.null(subfamily)) {
    d <- dplyr::filter(d, .data$subfamily == .env$subfamily)
  }
  d |>
    dplyr::arrange(dplyr::desc(.data$roi)) |>
    dplyr::slice_head(n = n) |>
    dplyr::transmute(
      Rule = rule,
      Bets = n_bets, Wins = n_wins,
      ROI = p6_fpct(roi, 1, TRUE),
      `Fair book` = p6_fpct(roi_fair, 1, TRUE),
      `Mean price` = p6_fprice(mean_sp),
      `Med price` = p6_fprice(median_sp),
      `Fav %` = p6_fpct(share_favourite, 1),
      `Mean field` = sprintf("%.1f", mean_field_size)
    )
}

#' The guard's per-family counts
#' @param guards A list of `p6_stability_guard()` outputs.
#' @param labels The bet labels.
#' @return A presentation tibble.
p6_guard_counts <- function(guards, labels = p6_bet_labels()) {
  purrr::list_rbind(guards) |>
    dplyr::group_by(family, bet) |>
    dplyr::summarise(
      candidates = dplyr::n(),
      eligible = sum(eligible),
      struck_bets = sum(!eligible),
      struck_decile = sum(eligible & !survives),
      survivors = sum(survives),
      .groups = "drop"
    ) |>
    dplyr::transmute(
      Family = family, Bet = unname(labels[bet]),
      Candidates = candidates, Eligible = eligible,
      `Struck: too few bets` = struck_bets,
      `Struck: not top decile` = struck_decile,
      Survivors = survivors
    ) |>
    dplyr::arrange(Family, Bet)
}

#' A round-3 validation-to-test table for one bet type
#' @param ranks The `p6_round3_ranks$table` tibble.
#' @param bet The bet type.
#' @return A presentation tibble.
p6_r3_table <- function(ranks, bet) {
  ranks |>
    dplyr::filter(.data$bet == .env$bet) |>
    dplyr::arrange(dplyr::desc(val_roi)) |>
    dplyr::transmute(
      Rule = rule,
      Family = family,
      `Val ROI` = p6_fpct(val_roi, 1, TRUE),
      `H1` = p6_fpct(val_roi_h1, 1, TRUE),
      `H2` = p6_fpct(val_roi_h2, 1, TRUE),
      `Test ROI` = p6_fpct(test_roi, 1, TRUE),
      `Test 90% CI` = p6_fci(ci_lo, ci_hi),
      `Test fair` = p6_fpct(test_fair, 1, TRUE),
      `Test less top win` = p6_fpct(test_drop1, 1, TRUE),
      `Val bets` = val_bets, `Test bets` = test_bets,
      `Val price` = p6_fprice(val_mean_sp),
      `Test price` = p6_fprice(test_mean_sp),
      `Val rank` = val_rank, `Test rank` = test_rank
    )
}

#' Render a tibble as a paper table
#' @param d A tibble.
#' @param caption Table caption.
#' @param ... Passed to `knitr::kable()`.
#' @return A knitr kable.
p6_tbl <- function(d, caption, ...) {
  knitr::kable(d, caption = caption, align = NULL, ...)
}
