# p6_declaration.R
# Paper 6 — the frozen declaration artefact.
#
# `DECLARED_RULES.md` records the three rules, the training-split numbers that
# produced them and the evidence the search rested on, and is committed BEFORE
# any test target is built. Nothing after that point may alter it. Writing it
# from a `format = "file"` target rather than by hand is the point: the file
# is a function of the training-split targets, so it cannot drift from them.

#' Format a proportion as a percentage
#' @param x Numeric vector.
#' @param digits Decimal places.
#' @return Character vector.
p6_pct <- function(x, digits = 2) {
  ifelse(is.na(x), "—", sprintf(paste0("%.", digits, "f%%"), 100 * x))
}

#' Render a tibble as a GitHub-flavoured markdown table
#'
#' A small local formatter rather than a `{knitr}` dependency inside a
#' `{targets}` target: the artefact must render identically whatever is
#' attached to the session that builds it.
#'
#' @param df A tibble.
#' @return A single character string.
p6_md_table <- function(df) {
  cols <- names(df)
  body <- vapply(seq_len(nrow(df)), function(i) {
    cells <- vapply(cols, function(cl) {
      v <- df[[cl]][i]
      if (is.numeric(v) && !is.integer(v)) sprintf("%.4f", v) else as.character(v)
    }, character(1))
    paste0("| ", paste(cells, collapse = " | "), " |")
  }, character(1))
  paste(c(
    paste0("| ", paste(cols, collapse = " | "), " |"),
    paste0("|", paste(rep("---", length(cols)), collapse = "|"), "|"),
    body
  ), collapse = "\n")
}

#' Write the frozen declaration artefact
#'
#' @param path Destination, relative to the project root.
#' @param declaration The `p6_declaration` target.
#' @param grid The `p6_stage1_grid` target.
#' @param contrasts The `p6_stage1_contrasts` target.
#' @param thresholds The `p6_thresholds_train` target.
#' @param selections,stakings The rule registries, for their labels.
#' @param terms_decision The `p6_eachway_terms_decision` target.
#' @param gate The `p6_ledger_gate` target.
#' @param search_set The `p6_search_set_check` target.
#' @return `path`, invisibly for `{targets}`' `format = "file"`.
p6_write_declared_rules <- function(path, declaration, grid, contrasts,
                                    thresholds, selections, stakings,
                                    terms_decision, gate, search_set) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)

  bet_label <- c(win = "win", place = "place",
                 eachway = "each-way (paper 5's terms)",
                 eachway_corrected = "each-way (corrected terms)")

  decl_tbl <- declaration |>
    dplyr::transmute(
      `bet type` = bet_label[bet],
      `declared selection` = selection,
      `declared staking` = staking,
      `top candidate` = paste0(cand_selection, "/", cand_staking),
      `candidate ROI` = p6_pct(cand_roi),
      `S1/K0 ROI` = p6_pct(incumbent_roi),
      `paired difference` = p6_pct(diff_point),
      `bootstrap SE` = p6_pct(se),
      `exceeds one SE` = ifelse(exceeds_one_se, "yes", "no"),
      `bets on training` = n_bets
    )

  grid_tbl <- grid |>
    dplyr::transmute(
      selection, staking, bet = bet_label[bet], n_bets, n_wins,
      `ROI (SP)` = p6_pct(roi), `ROI (fair book)` = p6_pct(roi_fair),
      `mean stake` = sprintf("%.3f", mean_stake),
      `sd unit return` = sprintf("%.3f", sd_unit_return),
      `max drawdown` = sprintf("%.1f", max_drawdown)
    )

  contrast_tbl <- contrasts |>
    dplyr::transmute(
      selection, staking, bet = bet_label[bet],
      `difference vs S1/K0` = p6_pct(diff_point),
      `bootstrap SE` = p6_pct(se),
      `90% interval` = ifelse(is.na(ci_lo), "—",
                              sprintf("[%s, %s]", p6_pct(ci_lo), p6_pct(ci_hi))),
      `common races` = n_races
    )

  rule_tbl <- tibble::tibble(
    rule = c(names(selections), names(stakings)),
    definition = c(vapply(selections, function(s) s$label, character(1)),
                   vapply(stakings, function(s) s$label, character(1)))
  )

  lines <- c(
    "# Paper 6 — declared betting rules",
    "",
    "**Frozen before any test target was built.** Nothing in this file may be",
    "altered after the commit that introduced it. Every number below is from",
    "the training split alone.",
    "",
    sprintf("Search set: %s runner-rows over %s races, the paper-5 training",
            format(search_set$n_rows_frame, big.mark = ","),
            format(search_set$n_races_frame, big.mark = ",")),
    sprintf("split. %s rows of paper 5's training frame carry no usable price and",
            format(search_set$n_rows_dropped, big.mark = ",")),
    sprintf("are dropped; %d test races appear in it.", search_set$n_test_overlap),
    "",
    "Model: paper 5's rung-3b encoder, refit from paper 5's stored",
    "configuration with paper 5's own function and asserted bit-identical to",
    "paper 5's stored test scores before any training score was read.",
    "",
    "**The training-split probabilities are IN-SAMPLE.** The encoder was",
    "fitted on these races, so its win probabilities here are sharper than",
    "anything it will produce out of sample, and every ROI below that uses a",
    "model probability is inflated by that. The scale of it is visible in the",
    "grid: S4/K0 — the market favourite, flat stake, no model input at all and",
    sprintf("therefore not inflated — returns %s on the training split, while",
            p6_pct(grid$roi[grid$selection == "S4" & grid$staking == "K0" &
                              grid$bet == "win"], 1)),
    sprintf("S1/K0 returns %s on the same races against paper 5's %s on test.",
            p6_pct(grid$roi[grid$selection == "S1" & grid$staking == "K0" &
                              grid$bet == "win"], 1), "-12.19%"),
    "No training-split ROI here is an estimate of what a rule will return.",
    "They are a ranking device and nothing more, which is all the declaration",
    "rule uses them for. The test split settles the levels.",
    "",
    "## 1. The declaration",
    "",
    "For each bet type independently: take the highest training-split ROI at",
    "the real starting price; paired race-level bootstrap (B = 2000, seed 42)",
    "of its ROI difference against S1/K0 on their common races; declare the",
    "candidate only if the point difference exceeds one bootstrap standard",
    "error of the difference, otherwise declare S1/K0. Ties on ROI to four",
    "decimals prefer the lower-numbered selection arm, then K0 over K1 over",
    "K2. No judgement enters at any step.",
    "",
    p6_md_table(decl_tbl),
    "",
    "The each-way declaration runs on the **corrected** place terms, and its",
    "comparator is S1/K0 recomputed on those same terms. Paper 5's flat",
    "one-fifth-top-three terms are reported alongside throughout but declare",
    "nothing.",
    "",
    "## 2. Each-way terms",
    "",
    sprintf("Races with four to seven runners: %s of the training split, %s of",
            p6_pct(terms_decision$share_4_to_7_train, 1),
            p6_pct(terms_decision$share_4_to_7_test, 1)),
    sprintf("the test split. The threshold in the brief is %s, so the terms are",
            p6_pct(terms_decision$threshold, 0)),
    "corrected. Correcting only the four-to-seven band would leave the",
    "twelve-and-up band wrong as well, so the full industry handicap ladder is",
    "used: win-only at four runners; a quarter the odds on the first two from",
    "five to seven; a fifth on the first three from eight to eleven; a quarter",
    "on the first three from twelve to fifteen; a quarter on the first four",
    "from sixteen. Paper 5's terms differ from these on",
    sprintf("%s of training races.", p6_pct(terms_decision$share_mispriced_train, 1)),
    "",
    "## 3. The reproduction gate",
    "",
    "Paper 5's test ledger, rebuilt through paper 6's ledger function under",
    "S1/K0 and paper 5's each-way terms, against the encoder rows of paper 5's",
    "`p5_test_backtests`:",
    "",
    p6_md_table(gate |> dplyr::transmute(
      bet, `p6 bets` = n_bets_p6, `p5 bets` = n_bets_p5,
      `p6 wins` = n_wins_p6, `p5 wins` = n_wins_p5,
      `p6 profit` = sprintf("%.2f", profit_p6),
      `p5 profit` = sprintf("%.2f", profit_p5),
      `ROI difference` = sprintf("%.1e", d_roi)
    )),
    "",
    "## 4. The candidates",
    "",
    p6_md_table(rule_tbl),
    "",
    sprintf("Quantile cuts, taken over the model's top-rated horse in each of the"),
    sprintf("%s training races: ratio q25 %.3f, q30 %.3f, q40 %.3f, q60 %.3f,",
            format(thresholds$n_races, big.mark = ","),
            thresholds$ratio_q[["25%"]], thresholds$ratio_q[["30%"]],
            thresholds$ratio_q[["40%"]], thresholds$ratio_q[["60%"]]),
    sprintf("q70 %.3f, q75 %.3f; starting price q25 %.2f, q50 %.2f, q75 %.2f.",
            thresholds$ratio_q[["70%"]], thresholds$ratio_q[["75%"]],
            thresholds$sp_q[["25%"]], thresholds$sp_q[["50%"]],
            thresholds$sp_q[["75%"]]),
    "",
    "## 5. The full search grid, training split",
    "",
    p6_md_table(grid_tbl),
    "",
    "## 6. Every candidate against S1/K0, paired on common races",
    "",
    p6_md_table(contrast_tbl),
    ""
  )

  writeLines(lines, path)
  path
}
