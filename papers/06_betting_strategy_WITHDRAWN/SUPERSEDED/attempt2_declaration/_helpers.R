# papers/06_betting_strategy/_helpers.R
# Accessors and formatters for paper 6.
#
# Every number in the prose comes through these, so a mistyped arm, stage or
# bet label is an error rather than a silently wrong figure. Nothing here
# computes a result: the targets already hold them.

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
#' @param arm_id Arm label, e.g. "S1/K0".
#' @param bet_id Settlement column: "win", "place", "eachway",
#'   "eachway_corrected".
p6_res <- function(tbl, arm_id, bet_id) {
  out <- dplyr::filter(tbl, arm == arm_id, bet == bet_id)
  if (nrow(out) != 1L) {
    stop("p6_res(): expected 1 row for ", arm_id, "/", bet_id, ", got ",
         nrow(out), call. = FALSE)
  }
  out
}

#' One row of the test-contrast table
#'
#' @param tbl The `p6_test_contrasts` target.
#' @param bet_id Settlement column.
#' @param question_grep Regex matching the contrast's question.
p6_con <- function(tbl, bet_id, question_grep) {
  out <- tbl |>
    dplyr::filter(bet == bet_id,
                  stringr::str_detect(question, question_grep))
  if (nrow(out) != 1L) {
    stop("p6_con(): expected 1 row for ", bet_id, "/", question_grep,
         ", got ", nrow(out), call. = FALSE)
  }
  out
}

#' One row of a validation-slice grid
#'
#' @param tbl `p6_stage_a_grid`, `p6_stage_b_grid` or `p6_gate_demonstration`.
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

#' One row of the validation-slice incumbent table
p6_valinc <- function(tbl, bet_id) {
  out <- dplyr::filter(tbl, bet == bet_id)
  if (nrow(out) != 1L) {
    stop("p6_valinc(): expected 1 row for ", bet_id, ", got ", nrow(out),
         call. = FALSE)
  }
  out
}

#' One row of the declaration
#'
#' @param tbl The `p6_declaration` target.
#' @param stage_id "A" or "B".
#' @param bet_id Settlement column the declaration ran on.
p6_decl <- function(tbl, stage_id, bet_id) {
  out <- dplyr::filter(tbl, stage == stage_id, bet == bet_id)
  if (nrow(out) != 1L) {
    stop("p6_decl(): expected 1 row for ", stage_id, "/", bet_id, ", got ",
         nrow(out), call. = FALSE)
  }
  out
}

#' One split's row of the threshold-position summary
p6_pos <- function(positions, split_id) {
  out <- dplyr::filter(positions$summary, split == split_id)
  if (nrow(out) != 1L) stop("p6_pos(): bad split ", split_id, call. = FALSE)
  out
}

# ---- table builders -------------------------------------------------------

P6_BET_LABEL <- c(win = "win", place = "place",
                  eachway = "each-way, paper 5 terms",
                  eachway_corrected = "each-way, corrected terms")

#' The test-results table rendered for print
p6_results_table <- function(tbl, bets = names(P6_BET_LABEL)) {
  tbl |>
    dplyr::filter(bet %in% bets) |>
    dplyr::arrange(match(bet, bets), arm) |>
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
    dplyr::arrange(match(bet, bets), arm) |>
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
#'
#' Degenerate contrasts — where the two arms are the same rule — are kept and
#' labelled, not dropped.
p6_contrast_table <- function(tbl, bets = names(P6_BET_LABEL)) {
  tbl |>
    dplyr::filter(bet %in% bets) |>
    dplyr::arrange(match(bet, bets), question) |>
    dplyr::transmute(
      Bet = P6_BET_LABEL[bet], Question = question,
      Contrast = paste(a_arm, "−", b_arm),
      A = dplyr::if_else(degenerate, "—", p6_fmt_pct(roi_a)),
      B = dplyr::if_else(degenerate, "—", p6_fmt_pct(roi_b)),
      Difference = dplyr::if_else(degenerate, "0, same rule",
                                  p6_fmt_pts(diff_point)),
      `90% interval` = dplyr::if_else(
        degenerate, "—", purrr::map2_chr(ci_lo, ci_hi, p6_fmt_pts_ci)),
      `Excludes zero` = dplyr::case_when(
        degenerate ~ "—",
        (ci_lo > 0 & ci_hi > 0) | (ci_lo < 0 & ci_hi < 0) ~ "yes",
        TRUE ~ "no"
      ),
      Races = p6_comma(n_races)
    )
}

#' A validation-slice grid rendered for print, one bet type
p6_grid_table <- function(tbl, bet_id, show_staking = FALSE) {
  out <- tbl |>
    dplyr::filter(bet == bet_id) |>
    dplyr::arrange(dplyr::desc(roi)) |>
    dplyr::transmute(
      Selection = selection, Staking = staking,
      Selected = p6_comma(n_races_selected), Bets = p6_comma(n_bets),
      Wins = p6_comma(n_wins),
      ROI = p6_fmt_pct(roi), `ROI, fair book` = p6_fmt_pct(roi_fair),
      `Staked share` = p6_fmt_pct(staked_share, 0),
      `Projected test bets` = sprintf("%.0f", projected_test_bets),
      Eligible = dplyr::if_else(eligible, "yes", "no"),
      `Struck because` = dplyr::coalesce(struck_because, "—")
    )
  if (!show_staking) out <- dplyr::select(out, -Staking)
  out
}
