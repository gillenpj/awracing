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
#' @param selection_sizes The `p6_test_selection_sizes` target.
#' @return `path`.
p6_write_test_report <- function(path, results, contrasts, margins,
                                 declaration, arms, selection_sizes) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)

  res_tbl <- results |>
    dplyr::arrange(match(bet, names(P6_BET_LABEL_MD)), arm) |>
    dplyr::transmute(
      bet = P6_BET_LABEL_MD[bet], arm, bets = n_bets, wins = n_wins,
      staked = sprintf("%.0f", total_stake),
      profit = sprintf("%.2f", profit),
      `ROI (SP)` = p6_pct(roi),
      `ROI (fair book)` = p6_pct(roi_fair),
      `ROI less top winner` = p6_pct(roi_drop_top1),
      `90% interval` = sprintf("[%s, %s]", p6_pct(ci_lo), p6_pct(ci_hi))
    )

  con_tbl <- contrasts |>
    dplyr::arrange(match(bet, names(P6_BET_LABEL_MD)), question) |>
    dplyr::transmute(
      bet = P6_BET_LABEL_MD[bet], question,
      contrast = paste(a_arm, "-", b_arm),
      `ROI a (common)` = ifelse(degenerate, "—", p6_pct(roi_a)),
      `ROI b (common)` = ifelse(degenerate, "—", p6_pct(roi_b)),
      difference = ifelse(degenerate, "0 (same arm)", p6_pct(diff_point)),
      `bootstrap SE` = ifelse(degenerate, "—", p6_pct(se)),
      `90% interval` = ifelse(degenerate, "—",
                              sprintf("[%s, %s]", p6_pct(ci_lo),
                                      p6_pct(ci_hi))),
      `excludes zero` = dplyr::case_when(
        degenerate ~ "—",
        (ci_lo > 0 & ci_hi > 0) | (ci_lo < 0 & ci_hi < 0) ~ "yes",
        TRUE ~ "no"
      ),
      `common races` = n_races
    )

  mar_tbl <- margins |>
    dplyr::arrange(match(bet, names(P6_BET_LABEL_MD)), arm) |>
    dplyr::transmute(
      bet = P6_BET_LABEL_MD[bet], arm, bets = n_bets,
      `ROI (SP)` = p6_pct(roi), `ROI (fair book)` = p6_pct(roi_fair),
      `margin paid` = p6_pct(margin_paid),
      `mean stake` = sprintf("%.3f", mean_stake),
      `sd unit return` = sprintf("%.3f", sd_unit_return),
      `max drawdown` = sprintf("%.1f", max_drawdown)
    )

  decl_tbl <- declaration |>
    dplyr::transmute(stage, `bet type` = P6_BET_LABEL_MD[bet],
                     declared = paste0(selection, "/", staking))

  arm_tbl <- arms |>
    dplyr::left_join(dplyr::select(selection_sizes, arm, n_races_selected),
                     by = "arm") |>
    dplyr::transmute(arm, `races selected on test` = n_races_selected, roles)

  lines <- c(
    "# Paper 6 — the test split, scored once",
    "",
    "The arms below are the entire test contact. The declaration was",
    "committed before any target in this report existed, and",
    "`p6_declaration_frozen` re-reads the file from disk and matches it",
    "against the declaration target on every build.",
    "",
    "The comparator for every headline number is paper 5's encoder under",
    "Owen's rule on the same 2,183 test races: win -12.19%, place -10.20%,",
    "each-way -5.96% (paper 5's terms).",
    "",
    "## 1. What was declared",
    "",
    p6_md_table(decl_tbl),
    "",
    "Both stages declared the incumbent for every bet type. The declared",
    "selection at a flat stake is therefore the same rule as S1/K0, and the",
    "declared stake is the same rule again, so the arms coincide and two of",
    "the four contrasts below are identically zero by construction. That is",
    "reported rather than hidden.",
    "",
    "## 2. The arms",
    "",
    p6_md_table(arm_tbl),
    "",
    "## 3. Results",
    "",
    p6_md_table(res_tbl),
    "",
    "## 4. Contrasts on common races",
    "",
    "B = 2000, seed 42, resampling races rather than bets so an arm that did",
    "not bet a drawn race contributes zero to that draw.",
    "",
    p6_md_table(con_tbl),
    "",
    "## 5. Margin decomposition",
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
