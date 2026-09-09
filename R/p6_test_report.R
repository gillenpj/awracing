# p6_test_report.R
# Paper 6 — the stage report on the one scoring of the test split.
#
# Written from a `format = "file"` target so the report cannot drift from the
# targets it describes. Uses `p6_md_table()` / `p6_pct()` from
# `R/p6_declaration.R`.

#' Write the paper-6 test-split stage report
#'
#' @param path Destination, relative to the project root.
#' @param results The `p6_test_results` target.
#' @param contrasts The `p6_test_contrasts` target.
#' @param margins The `p6_margin_decomposition` target.
#' @param declaration The `p6_declaration_frozen` target.
#' @param arms The `p6_test_arms` target.
#' @return `path`.
p6_write_test_report <- function(path, results, contrasts, margins,
                                 declaration, arms) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)

  bet_label <- c(win = "win", place = "place",
                 eachway = "each-way (paper 5 terms)",
                 eachway_corrected = "each-way (corrected terms)")

  res_tbl <- results |>
    dplyr::arrange(match(bet, names(bet_label)), arm) |>
    dplyr::transmute(
      bet = bet_label[bet], arm, bets = n_bets, wins = n_wins,
      `total stake` = sprintf("%.0f", total_stake),
      profit = sprintf("%.2f", profit),
      `ROI (SP)` = p6_pct(roi),
      `ROI (fair book)` = p6_pct(roi_fair),
      `ROI less top winner` = p6_pct(roi_drop_top1),
      `90% interval` = sprintf("[%s, %s]", p6_pct(ci_lo), p6_pct(ci_hi))
    )

  con_tbl <- contrasts |>
    dplyr::arrange(match(bet, names(bet_label)), against) |>
    dplyr::transmute(
      bet = bet_label[bet], declared, against,
      difference = p6_pct(diff_point), `bootstrap SE` = p6_pct(se),
      `90% interval` = sprintf("[%s, %s]", p6_pct(ci_lo), p6_pct(ci_hi)),
      `excludes zero` = ifelse((ci_lo > 0 & ci_hi > 0) | (ci_lo < 0 & ci_hi < 0),
                               "yes", "no"),
      `common races` = n_races
    )

  mar_tbl <- margins |>
    dplyr::arrange(match(bet, names(bet_label)), arm) |>
    dplyr::transmute(
      bet = bet_label[bet], arm, bets = n_bets,
      `ROI (SP)` = p6_pct(roi), `ROI (fair book)` = p6_pct(roi_fair),
      `margin paid` = p6_pct(margin_paid),
      `mean stake` = sprintf("%.3f", mean_stake),
      `sd unit return` = sprintf("%.3f", sd_unit_return),
      `max drawdown` = sprintf("%.1f", max_drawdown)
    )

  decl_tbl <- declaration |>
    dplyr::transmute(`bet type` = bet_label[bet], selection, staking)

  lines <- c(
    "# Paper 6 — the test split, scored once",
    "",
    "Five rules reached the test split and no others: the three declared in",
    "`DECLARED_RULES.md`, S1/K0 (paper 5's incumbent) and S4/K0 (the",
    "market-only control). The declaration was committed before any target in",
    "this report existed, and `p6_declaration_frozen` re-reads the file from",
    "disk and matches it against the declaration target on every build.",
    "",
    "The comparator for every headline number is paper 5's encoder under",
    "Owen's rule on the same 2,183 test races: win -12.19%, place -10.20%,",
    "each-way -5.96% (paper 5's terms).",
    "",
    "## 1. The declared rules",
    "",
    p6_md_table(decl_tbl),
    "",
    "## 2. Results",
    "",
    p6_md_table(res_tbl),
    "",
    "## 3. Paired contrasts on common races",
    "",
    "B = 2000, seed 42, resampling races rather than bets so an arm that did",
    "not bet a drawn race contributes zero to that draw.",
    "",
    p6_md_table(con_tbl),
    "",
    "## 4. Margin decomposition",
    "",
    "`margin paid` is the fair-book ROI less the real-SP ROI: the share of",
    "stake the over-round takes on the horses that arm actually backs. A rule",
    "that improves ROI by backing shorter prices has reduced the margin it",
    "pays, which is not the same thing as picking better.",
    "",
    p6_md_table(mar_tbl),
    ""
  )

  writeLines(lines, path)
  path
}
