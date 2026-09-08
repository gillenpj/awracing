# papers/05_encoder/_helpers.R
# Accessors and formatters for paper 5.
#
# Every number in the prose comes through these, so a mistyped contrast or
# metric label is an error rather than a silently wrong figure. Nothing here
# computes a result: the targets already hold them.

# ---- formatters -----------------------------------------------------------
# Deliberately prefixed. Short names would be shadowed by same-named columns
# inside dplyr verbs.

fmt_sci <- function(x, digits = 3) {
  formatC(x, format = "e", digits = digits, flag = if (x > 0) "+" else "")
}
fmt_sci_ci <- function(lo, hi, digits = 3) {
  sprintf("[%s, %s]", fmt_sci(lo, digits), fmt_sci(hi, digits))
}
fmt_loss <- function(x) sprintf("%.6f", x)
fmt_metric <- function(x) sprintf("%.5f", x)
fmt_gain <- function(x) sprintf("%.6f", x)
fmt_pct <- function(x, digits = 2) sprintf("%.*f%%", digits, 100 * x)
fmt_pts <- function(x, digits = 2) sprintf("%+.*f", digits, 100 * x)
fmt_pts_ci <- function(lo, hi, digits = 2) {
  sprintf("[%+.*f, %+.*f]", digits, 100 * lo, digits, 100 * hi)
}
fmt_r2 <- function(x) sprintf("%.3f", x)
p5_comma <- function(x) format(x, big.mark = ",", trim = TRUE)

# ---- accessors ------------------------------------------------------------

#' One row of a ranking-contrast tibble
#'
#' @param tbl A `bootstrap_ranking_metrics()` output.
#' @param metric_id "P1_rank", "Brier_place" or "test_pl_r2".
#' @param contrast_grep Optional regex, needed when the tibble holds more
#'   than one contrast.
p5_ct <- function(tbl, metric_id, contrast_grep = NULL) {
  out <- dplyr::filter(tbl, metric == metric_id)
  if (!is.null(contrast_grep)) {
    out <- dplyr::filter(out, stringr::str_detect(contrast, contrast_grep))
  }
  if (nrow(out) != 1L) {
    stop("p5_ct(): expected 1 row for ", metric_id, "/",
         contrast_grep %||% "any", ", got ", nrow(out), call. = FALSE)
  }
  out
}

#' One row of the ROI contrast tibble
p5_roi <- function(tbl, contrast_grep, bet_id) {
  out <- tbl |>
    dplyr::filter(stringr::str_detect(contrast, contrast_grep),
                  bet == bet_id)
  if (nrow(out) != 1L) {
    stop("p5_roi(): expected 1 row for ", contrast_grep, "/", bet_id,
         ", got ", nrow(out), call. = FALSE)
  }
  out
}

#' One row of the single-bet backtest table
p5_bt <- function(tbl, arm_id, bet_id) {
  out <- dplyr::filter(tbl, arm == arm_id, bet == bet_id)
  if (nrow(out) != 1L) {
    stop("p5_bt(): expected 1 row for ", arm_id, "/", bet_id,
         ", got ", nrow(out), call. = FALSE)
  }
  out
}

#' One arm's validation PL loss from the ladder decomposition
p5_arm_loss <- function(tbl, arm_grep) {
  out <- dplyr::filter(tbl, stringr::str_detect(arm, arm_grep))
  if (nrow(out) != 1L) {
    stop("p5_arm_loss(): expected 1 row for ", arm_grep, ", got ", nrow(out),
         call. = FALSE)
  }
  out$val_pl_loss
}

#' One feature's linear recovery R-squared
p5_rec <- function(tbl, feature_id) {
  out <- dplyr::filter(tbl, feature == feature_id)
  if (nrow(out) != 1L) stop("p5_rec(): bad feature ", feature_id, call. = FALSE)
  out$r_squared
}

#' One row of the sequence-length table
p5_seqlen <- function(tbl, len) {
  out <- dplyr::filter(tbl, max_len == len)
  if (nrow(out) != 1L) stop("p5_seqlen(): bad length ", len, call. = FALSE)
  out
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# ---- table builders -------------------------------------------------------

#' A ranking-contrast tibble rendered for print
#'
#' @param tbl A `bootstrap_ranking_metrics()` output.
#' @param labels Named character vector mapping metric ids to display names.
#' @param a_name,b_name Column headings for the two arms.
p5_contrast_table <- function(tbl, a_name, b_name,
                              metrics = c("P1_rank", "Brier_place",
                                          "test_pl_r2")) {
  tbl |>
    dplyr::filter(metric %in% metrics, !is.na(diff_point)) |>
    dplyr::mutate(
      Metric = dplyr::recode(
        metric,
        P1_rank = "P1_rank (higher better)",
        Brier_place = "Brier_place (lower better)",
        test_pl_r2 = "pseudo-R² (higher better)"
      ),
      a = sprintf("%.5f", point_a),
      b = sprintf("%.5f", point_b),
      Difference = purrr::map_chr(diff_point, fmt_sci),
      `90% interval` = purrr::map2_chr(ci_lo, ci_hi, fmt_sci_ci),
      Favours = dplyr::if_else(
        (ci_lo > 0 & ci_hi > 0) | (ci_lo < 0 & ci_hi < 0),
        dplyr::if_else(
          (metric == "P1_rank" & diff_point > 0) |
            (metric != "P1_rank" & metric == "Brier_place" &
               diff_point < 0) |
            (metric == "test_pl_r2" & diff_point > 0),
          a_name, b_name
        ),
        "neither"
      )
    ) |>
    dplyr::select(Metric, !!a_name := a, !!b_name := b, Difference,
                  `90% interval`, Favours)
}

#' The single-bet backtest table rendered for print
p5_backtest_table <- function(tbl, arm_labels) {
  tbl |>
    dplyr::mutate(
      Arm = dplyr::recode(arm, !!!arm_labels),
      Bet = dplyr::recode(bet, win = "win", place = "place",
                          eachway = "each-way"),
      Bets = p5_comma(n_bets),
      Wins = p5_comma(n_wins),
      Profit = sprintf("%.2f", profit),
      ROI = purrr::map_chr(roi, \(x) fmt_pct(x, 2)),
      `ROI less top winner` = purrr::map_chr(roi_drop_top1,
                                             \(x) fmt_pct(x, 2))
    ) |>
    dplyr::select(Arm, Bet, Bets, Wins, Profit, ROI,
                  `ROI less top winner`)
}
