# p6_declaration.R
# Paper 6 — the frozen declaration artefact.
#
# `DECLARED_RULES.md` records both stages, the eligibility gate and what it
# struck, and the validation numbers that produced the declarations. It is
# committed BEFORE any test target exists. Nothing after that point may alter
# it. Writing it from a `format = "file"` target rather than by hand is the
# point: the file is a function of the validation-slice targets, so it cannot
# drift from them.

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
      if (is.na(v)) return("—")
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

P6_BET_LABEL_MD <- c(win = "win", place = "place",
                     eachway = "each-way (paper 5 terms)",
                     eachway_corrected = "each-way (corrected terms)")

#' Write the frozen declaration artefact
#'
#' @param path Destination, relative to the project root.
#' @param declaration The combined two-stage declaration tibble.
#' @param grid_a,grid_b The stage-A and stage-B eligibility-annotated grids.
#' @param contrasts_a The stage-A contrasts against S1/K0.
#' @param thresholds The validation-slice quantile cuts.
#' @param selections,stakings The rule registries, for their labels.
#' @param terms_decision The each-way terms decision.
#' @param gate The paper-5 reproduction gate result.
#' @param search_set The search-set assertion counts.
#' @param provenance The two-fit provenance table.
#' @param positions The two-split threshold-position report.
#' @param gate_demo The nine-by-three gate demonstration (declares nothing).
#' @return `path`.
p6_write_declared_rules <- function(path, declaration, grid_a, grid_b,
                                    contrasts_a, thresholds, selections,
                                    stakings, terms_decision, gate,
                                    search_set, provenance, positions,
                                    gate_demo) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)

  decl_tbl <- declaration |>
    dplyr::transmute(
      stage,
      `bet type` = P6_BET_LABEL_MD[bet],
      `declared` = paste0(selection, "/", staking),
      `top eligible candidate` = paste0(cand_selection, "/", cand_staking),
      `candidate ROI` = p6_pct(cand_roi),
      `comparator ROI` = p6_pct(comparator_roi),
      `paired difference` = p6_pct(diff_point),
      `bootstrap SE` = p6_pct(se),
      `exceeds one SE` = ifelse(exceeds_one_se, "yes", "no"),
      `eligible candidates` = n_eligible
    )

  fmt_grid <- function(g) {
    g |>
      dplyr::transmute(
        selection, staking, bet = P6_BET_LABEL_MD[bet],
        `races selected` = n_races_selected, `bets placed` = n_bets,
        `staked share` = p6_pct(staked_share, 1),
        `projected test bets` = sprintf("%.0f", projected_test_bets),
        wins = n_wins,
        `ROI (SP)` = p6_pct(roi), `ROI (fair book)` = p6_pct(roi_fair),
        `mean stake` = sprintf("%.3f", mean_stake),
        `sd unit return` = sprintf("%.3f", sd_unit_return),
        `max drawdown` = sprintf("%.1f", max_drawdown),
        eligible = ifelse(eligible, "yes", "no"),
        `struck because` = dplyr::coalesce(struck_because, "—")
      )
  }

  struck <- grid_a |>
    dplyr::bind_rows(grid_b) |>
    dplyr::filter(!eligible) |>
    dplyr::transmute(
      arm = paste0(selection, "/", staking), bet = P6_BET_LABEL_MD[bet],
      `races selected` = n_races_selected, `bets placed` = n_bets,
      `staked share` = p6_pct(staked_share, 1),
      `projected test bets` = sprintf("%.0f", projected_test_bets),
      reason = struck_because
    )

  rule_tbl <- tibble::tibble(
    rule = c(names(selections), names(stakings)),
    definition = c(vapply(selections, function(s) s$label, character(1)),
                   vapply(stakings, function(s) s$label, character(1)))
  )

  pos_tbl <- positions$s1_position |>
    dplyr::transmute(
      split, quantity, `S1 threshold` = s1_threshold,
      `quantile it sits at` = p6_pct(quantile_of_top_rated, 1),
      `share of top-rated passing` = p6_pct(share_passing, 1)
    )

  sum_tbl <- positions$summary |>
    dplyr::transmute(
      split, races = n_races,
      `median P_mod` = sprintf("%.4f", median_p_mod),
      `median ratio` = sprintf("%.4f", median_ratio),
      `median SP` = sprintf("%.2f", median_sp),
      `share with positive Kelly edge` = p6_pct(share_positive_kelly_edge, 1)
    )

  lines <- c(
    "# Paper 6 — declared betting rules",
    "",
    "**Frozen before any test target was built.** Nothing in this file may be",
    "altered after the commit that introduced it. Every number below is from",
    "the validation slice alone.",
    "",
    "## 0. The search set",
    "",
    sprintf("Paper 5's validation slice: %s runner-rows over %s races, carved",
            format(search_set$n_rows_frame, big.mark = ","),
            format(search_set$n_races_frame, big.mark = ",")),
    sprintf("out of the training period at 2010-12-15. The %s fitting races are",
            format(search_set$n_races_fit, big.mark = ",")),
    "not used: the model was fitted on them and memorised them.",
    "",
    sprintf("Overlap with the test split: %d races. Overlap with the fitting",
            search_set$n_test_overlap),
    sprintf("partition: %d races. Rows dropped for want of a usable price: %d.",
            search_set$n_fit_overlap, search_set$n_rows_dropped),
    "",
    "The search set is scored by the **fitting-partition** fit, which never saw",
    "these races. The test split is scored by the **full-training-split**",
    "refit, the model paper 5 published. Two fits of one architecture:",
    "",
    p6_md_table(
      provenance |>
        dplyr::transmute(
          fit, scores, `training races` = n_train_races, config, epochs,
          `validation PL loss` = ifelse(is.na(val_pl_loss), "—",
                                        sprintf("%.6f", val_pl_loss)),
          source
        )
    ),
    "",
    "Their score distributions differ in scale, so every candidate threshold",
    "below is a within-split quantile rather than an absolute number:",
    "",
    p6_md_table(sum_tbl),
    "",
    p6_md_table(pos_tbl),
    "",
    "## 1. The declaration",
    "",
    "Two stages, because selection and staking are two questions and a single",
    "grid confounds them.",
    "",
    "**Stage A — selection, at a flat stake.** All nine selection rules at K0.",
    "Comparator S1/K0.",
    "",
    "**Stage B — staking, on the declared selection only.** K0, K1 and K2 on",
    "whatever stage A declared. Comparator: that selection at K0.",
    "",
    "Each stage varies exactly one term against its comparator, asserted in",
    "code by `p6_assert_one_difference()`.",
    "",
    "Within a stage, and with no judgement at any step: among **eligible**",
    "candidates take the highest validation ROI at the real starting price;",
    "paired race-level bootstrap (B = 2000, seed 42) of its ROI difference",
    "against the stage comparator on their common races; declare it only if",
    "the point difference exceeds one bootstrap standard error of the",
    "difference, otherwise declare the comparator. Ties on ROI to four",
    "decimals prefer the lower-numbered selection arm, then K0 over K1 over",
    "K2.",
    "",
    p6_md_table(decl_tbl),
    "",
    "The each-way declaration runs on the **corrected** place terms, and its",
    "comparator is recomputed on those same terms. Paper 5's flat",
    "one-fifth-top-three terms are reported alongside throughout but declare",
    "nothing.",
    "",
    "## 2. Eligibility",
    "",
    "Two conditions, both applied **before** the argmax rather than after it:",
    "",
    sprintf("1. projected test bets >= %d, where projected = validation bets",
            P6_MIN_PROJECTED_TEST_BETS),
    "   placed x (test races / validation races). Would the arm bet often",
    "   enough on test for the result to mean anything?",
    sprintf("2. the arm places a positive stake in at least %s of the races its",
            p6_pct(P6_MIN_STAKED_SHARE, 0)),
    "   selection rule selects. K1 and K2 stake zero where the model",
    "   probability does not exceed the price, which makes them selection",
    "   rules as well as staking rules; this is the direct guard.",
    "",
    if (nrow(struck) == 0L)
      c("No candidate was struck from either stage's pool.") else
      c(paste0("Struck candidates (", nrow(struck),
               " arm-bet combinations):"), "", p6_md_table(struck)),
    "",
    "Stage A runs at K0, where every selected race is staked by construction,",
    "and stage B runs on whatever stage A declared, so the gate can strike",
    "nothing in either pool without being inert. The diagnostic below applies",
    "the same gate to the full nine-by-three cross-product on the validation",
    "slice, to show what it would strike. **Nothing in the declaration reads",
    "it**: the declaration is passed the stage grids, never this one.",
    "",
    p6_md_table(
      gate_demo |>
        dplyr::filter(bet == "win") |>
        dplyr::transmute(
          arm = paste0(selection, "/", staking),
          `races selected` = n_races_selected, `bets placed` = n_bets,
          `staked share` = p6_pct(staked_share, 1),
          `projected test bets` = sprintf("%.0f", projected_test_bets),
          `ROI (SP)` = p6_pct(roi),
          eligible = ifelse(eligible, "yes", "no"),
          `struck because` = dplyr::coalesce(struck_because, "—")
        )
    ),
    "",
    "(Win market shown; the other three settlement columns select the same",
    "races and differ only in what a bet returns.)",
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
    "## 4. Each-way terms",
    "",
    sprintf("Races with four to seven runners: %s of the validation slice, %s of",
            p6_pct(terms_decision$share_4_to_7_val, 1),
            p6_pct(terms_decision$share_4_to_7_test, 1)),
    sprintf("the test split. The threshold is %s, so the terms are corrected.",
            p6_pct(terms_decision$threshold, 0)),
    "Correcting only the four-to-seven band would leave the twelve-and-up band",
    "wrong as well, so the full industry handicap ladder is used: win-only at",
    "four runners; a quarter the odds on the first two from five to seven; a",
    "fifth on the first three from eight to eleven; a quarter on the first",
    "three from twelve to fifteen; a quarter on the first four from sixteen.",
    sprintf("Paper 5's terms differ from these on %s of validation races.",
            p6_pct(terms_decision$share_mispriced_val, 1)),
    "",
    "## 5. The candidates",
    "",
    p6_md_table(rule_tbl),
    "",
    "Quantile cuts, taken over the model's top-rated horse in each of the",
    sprintf("%s validation races: ratio q25 %.3f, q30 %.3f, q40 %.3f, q60 %.3f,",
            format(thresholds$n_races, big.mark = ","),
            thresholds$ratio_q[["25%"]], thresholds$ratio_q[["30%"]],
            thresholds$ratio_q[["40%"]], thresholds$ratio_q[["60%"]]),
    sprintf("q70 %.3f, q75 %.3f; starting price q25 %.2f, q50 %.2f, q75 %.2f.",
            thresholds$ratio_q[["70%"]], thresholds$ratio_q[["75%"]],
            thresholds$sp_q[["25%"]], thresholds$sp_q[["50%"]],
            thresholds$sp_q[["75%"]]),
    "The same quantiles are recomputed on the test split from its own",
    "distribution, so a declared rule selects the same fraction of races there.",
    "",
    "## 6. Stage A — every selection rule at a flat stake, validation slice",
    "",
    p6_md_table(fmt_grid(grid_a)),
    "",
    "### Stage A, paired against S1/K0 on common races",
    "",
    p6_md_table(
      contrasts_a |>
        dplyr::transmute(
          selection, bet = P6_BET_LABEL_MD[bet],
          `difference vs S1/K0` = p6_pct(diff_point),
          `bootstrap SE` = p6_pct(se),
          `90% interval` = ifelse(is.na(ci_lo), "—",
                                  sprintf("[%s, %s]", p6_pct(ci_lo),
                                          p6_pct(ci_hi))),
          `common races` = n_races
        )
    ),
    "",
    "## 7. Stage B — staking on the declared selection, validation slice",
    "",
    p6_md_table(fmt_grid(grid_b)),
    ""
  )

  writeLines(lines, path)
  path
}
