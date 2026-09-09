# papers/06_betting_strategy/_helpers.R
# Accessors and formatters for paper 6.
#
# Every number in the prose comes through these, so a mistyped arm or bet
# label is an error rather than a silently wrong figure. Nothing here computes
# a result: the targets already hold them.

# ---- formatters -----------------------------------------------------------
# Deliberately prefixed. Short names would be shadowed by same-named columns
# inside dplyr verbs.

p6_fmt_pct <- function(x, digits = 2) {
  ifelse(is.na(x), "—", sprintf("%.*f%%", digits, 100 * x))
}
p6_fmt_pts <- function(x, digits = 1) {
  ifelse(is.na(x), "—", sprintf("%+.*f", digits, 100 * x))
}
p6_fmt_pts_ci <- function(lo, hi, digits = 1) {
  sprintf("[%+.*f, %+.*f]", digits, 100 * lo, digits, 100 * hi)
}
p6_fmt_pct_ci <- function(lo, hi, digits = 1) {
  sprintf("[%s, %s]", p6_fmt_pct(lo, digits), p6_fmt_pct(hi, digits))
}
p6_comma <- function(x) format(x, big.mark = ",", trim = TRUE)

# ---- accessors ------------------------------------------------------------

#' One row of the test-results table
#'
#' @param tbl The `p6_test_results` target.
#' @param arm_grep Regex matching the arm label.
#' @param bet_id Settlement column: "win", "place", "eachway",
#'   "eachway_corrected".
p6_res <- function(tbl, arm_grep, bet_id) {
  out <- tbl |>
    dplyr::filter(stringr::str_detect(arm, arm_grep), bet == bet_id)
  if (nrow(out) != 1L) {
    stop("p6_res(): expected 1 row for ", arm_grep, "/", bet_id, ", got ",
         nrow(out), call. = FALSE)
  }
  out
}

#' One row of the test-contrast table
#'
#' @param tbl The `p6_test_contrasts` target.
#' @param bet_id Settlement column.
#' @param against_grep Regex matching the comparator arm.
p6_con <- function(tbl, bet_id, against_grep) {
  out <- tbl |>
    dplyr::filter(bet == bet_id,
                  stringr::str_detect(against, against_grep))
  if (nrow(out) != 1L) {
    stop("p6_con(): expected 1 row for ", bet_id, "/", against_grep, ", got ",
         nrow(out), call. = FALSE)
  }
  out
}

#' One row of the training-split search grid
#'
#' @param tbl The `p6_stage1_grid` target.
#' @param sel,stk,bet_id Selection, staking and settlement column.
p6_grid <- function(tbl, sel, stk, bet_id) {
  out <- tbl |>
    dplyr::filter(selection == sel, staking == stk, bet == bet_id)
  if (nrow(out) != 1L) {
    stop("p6_grid(): expected 1 row for ", sel, "/", stk, "/", bet_id,
         ", got ", nrow(out), call. = FALSE)
  }
  out
}

#' One row of the declaration
#'
#' @param tbl The `p6_declaration` target.
#' @param bet_id Settlement column the declaration ran on.
p6_decl <- function(tbl, bet_id) {
  out <- dplyr::filter(tbl, bet == bet_id)
  if (nrow(out) != 1L) {
    stop("p6_decl(): expected 1 row for ", bet_id, ", got ", nrow(out),
         call. = FALSE)
  }
  out
}

#' Whether a contrast's 90% interval excludes zero
p6_excludes_zero <- function(row) {
  (row$ci_lo > 0 & row$ci_hi > 0) | (row$ci_lo < 0 & row$ci_hi < 0)
}

# ---- table builders -------------------------------------------------------

P6_BET_LABEL <- c(win = "win", place = "place",
                  eachway = "each-way, paper 5 terms",
                  eachway_corrected = "each-way, corrected terms")

P6_ARM_ORDER <- c("S1/K0 (paper 5 incumbent)", "S4/K0 (market-only control)")

#' The test-results table rendered for print
#'
#' @param tbl The `p6_test_results` target.
#' @param bets Settlement columns to include, in order.
p6_results_table <- function(tbl, bets = names(P6_BET_LABEL)) {
  tbl |>
    dplyr::filter(bet %in% bets) |>
    dplyr::mutate(
      ord_bet = match(bet, bets),
      ord_arm = dplyr::if_else(stringr::str_detect(arm, "^declared"), 0L,
                               match(arm, P6_ARM_ORDER))
    ) |>
    dplyr::arrange(ord_bet, ord_arm) |>
    dplyr::transmute(
      Bet = P6_BET_LABEL[bet], Arm = arm,
      Bets = p6_comma(n_bets), Wins = p6_comma(n_wins),
      Staked = sprintf("%.0f", total_stake),
      Profit = sprintf("%.2f", profit),
      ROI = p6_fmt_pct(roi),
      `ROI, fair book` = p6_fmt_pct(roi_fair),
      `ROI less top winner` = p6_fmt_pct(roi_drop_top1),
      `90% interval` = purrr::map2_chr(ci_lo, ci_hi, p6_fmt_pct_ci)
    )
}

#' The margin decomposition rendered for print
p6_margin_table <- function(tbl, bets = names(P6_BET_LABEL)) {
  tbl |>
    dplyr::filter(bet %in% bets) |>
    dplyr::mutate(
      ord_bet = match(bet, bets),
      ord_arm = dplyr::if_else(stringr::str_detect(arm, "^declared"), 0L,
                               match(arm, P6_ARM_ORDER))
    ) |>
    dplyr::arrange(ord_bet, ord_arm) |>
    dplyr::transmute(
      Bet = P6_BET_LABEL[bet], Arm = arm,
      ROI = p6_fmt_pct(roi), `ROI, fair book` = p6_fmt_pct(roi_fair),
      `Margin paid` = p6_fmt_pct(margin_paid),
      `Mean stake` = sprintf("%.2f", mean_stake),
      `SD unit return` = sprintf("%.2f", sd_unit_return),
      `Max drawdown` = sprintf("%.0f", max_drawdown)
    )
}

#' The paired-contrast table rendered for print
p6_contrast_table <- function(tbl, bets = names(P6_BET_LABEL)) {
  tbl |>
    dplyr::filter(bet %in% bets) |>
    dplyr::arrange(match(bet, bets), against) |>
    dplyr::transmute(
      Bet = P6_BET_LABEL[bet], Declared = declared, Against = against,
      Difference = p6_fmt_pts(diff_point),
      `Bootstrap SE` = p6_fmt_pts(se),
      `90% interval` = purrr::map2_chr(ci_lo, ci_hi, p6_fmt_pts_ci),
      `Excludes zero` = dplyr::if_else(
        (ci_lo > 0 & ci_hi > 0) | (ci_lo < 0 & ci_hi < 0), "yes", "no"),
      Races = p6_comma(n_races)
    )
}

#' The training-split search grid rendered for print, one bet type
p6_grid_table <- function(tbl, bet_id) {
  tbl |>
    dplyr::filter(bet == bet_id) |>
    dplyr::arrange(dplyr::desc(roi)) |>
    dplyr::transmute(
      Selection = selection, Staking = staking,
      Bets = p6_comma(n_bets), Wins = p6_comma(n_wins),
      ROI = p6_fmt_pct(roi), `ROI, fair book` = p6_fmt_pct(roi_fair),
      `Mean stake` = sprintf("%.2f", mean_stake),
      `SD unit return` = sprintf("%.2f", sd_unit_return),
      `Max drawdown` = sprintf("%.0f", max_drawdown)
    )
}
