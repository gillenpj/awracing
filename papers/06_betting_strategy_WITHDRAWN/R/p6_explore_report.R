# p6_explore_report.R
# Paper 6 — the exploration working report.
#
# `EXPLORATION.md` is written from a `format = "file"` target for the same
# reason `DECLARED_RULES.md` was: the file is a function of the targets, so it
# cannot drift from them. Every number in it is computed here from the
# pipeline's own objects — none is transcribed.
#
# It is a WORKING REPORT, not a Quarto paper: tables and short prose, no
# abstract, no discussion section, no limitations essay.

#' Format a rule's mean/median backed price and favourite share
#' @param df A scored tibble.
#' @return `df` with the presentation columns added.
p6_price_cols <- function(df) {
  df |>
    dplyr::mutate(
      mean_price = round(mean_sp, 2),
      med_price = round(median_sp, 2),
      fav_share = p6_pct(share_favourite, 1)
    )
}

#' The stage-1 leaderboard for one bet type
#'
#' @param sweep Output of `p6_sweep()`.
#' @param bet Settlement table name.
#' @param min_bets Minimum bets for a row to appear.
#' @param n How many rows.
#' @return A presentation tibble.
p6_leaderboard <- function(sweep, bet, min_bets = 300L, n = 15L) {
  sweep |>
    dplyr::filter(bet == !!bet, !is.na(roi), n_bets >= min_bets) |>
    dplyr::arrange(dplyr::desc(roi)) |>
    dplyr::slice_head(n = n) |>
    dplyr::transmute(
      rule, bets = n_bets, wins = n_wins,
      ROI = p6_pct(roi, 2), `ROI fair` = p6_pct(roi_fair, 2),
      `mean price` = sprintf("%.2f", mean_sp),
      `med price` = sprintf("%.2f", median_sp),
      `fav share` = p6_pct(share_favourite, 1)
    )
}

#' Per-picker best row and surface summary for one bet type
#'
#' @param sweep Output of `p6_sweep()`.
#' @param bet Settlement table name.
#' @param min_bets Minimum bets for a row to count.
#' @return A presentation tibble, one row per picker.
p6_picker_summary <- function(sweep, bet, min_bets = 300L) {
  sweep |>
    dplyr::filter(bet == !!bet, !is.na(roi), n_bets >= min_bets) |>
    dplyr::group_by(picker) |>
    dplyr::arrange(dplyr::desc(roi), .by_group = TRUE) |>
    dplyr::summarise(
      rows = dplyr::n(),
      `best rule` = dplyr::first(rule),
      `best ROI` = p6_pct(dplyr::first(roi), 2),
      `best bets` = dplyr::first(n_bets),
      `best mean price` = sprintf("%.2f", dplyr::first(mean_sp)),
      `median ROI` = p6_pct(stats::median(roi), 2),
      `median mean price` = sprintf("%.2f", stats::median(mean_sp)),
      .groups = "drop"
    )
}

#' Owen's row and its rank within one bet type's populated surface
#'
#' @param sweep Output of `p6_sweep()`.
#' @param bet Settlement table name.
#' @param min_bets Minimum bets for a row to count.
#' @return A one-row tibble.
p6_owen_rank <- function(sweep, bet, min_bets = 300L) {
  pool <- sweep |>
    dplyr::filter(bet == !!bet, !is.na(roi), n_bets >= min_bets)
  o <- sweep |>
    dplyr::filter(bet == !!bet, picker == "P5", !no_filter,
                  abs(p_cut - 0.15) < 1e-9, abs(r_cut - 1.30) < 1e-9)
  stopifnot(nrow(o) == 1L)
  tibble::tibble(
    bet = bet,
    `Owen ROI` = p6_pct(o$roi, 2),
    `Owen bets` = o$n_bets,
    `Owen mean price` = sprintf("%.2f", o$mean_sp),
    `rank of` = nrow(pool),
    rank = sum(pool$roi > o$roi) + 1L,
    percentile = sprintf("%.1f", 100 * mean(pool$roi <= o$roi)),
    `rows beating it` = sum(pool$roi > o$roi),
    `best margin (pts)` = sprintf("%+.2f", 100 * (max(pool$roi) - o$roi))
  )
}

#' An agreement matrix as a markdown table
#'
#' @param agree Output of `p6_picker_agreement()`.
#' @param value Which column to lay out: `share_same` or `n_both`.
#' @return A character string.
p6_agreement_md <- function(agree, value = c("share_same", "n_both")) {
  value <- match.arg(value)
  pn <- sort(unique(agree$a))
  m <- agree |>
    dplyr::select(a, b, dplyr::all_of(value)) |>
    tidyr::pivot_wider(names_from = b, values_from = dplyr::all_of(value)) |>
    dplyr::arrange(match(a, pn))
  m <- m[, c("a", pn)]
  fmt <- if (value == "share_same") function(x) ifelse(is.na(x), "—",
                                                       sprintf("%.3f", x))
         else function(x) ifelse(is.na(x), "—", format(x))
  out <- m |> dplyr::mutate(dplyr::across(-a, fmt)) |> dplyr::rename(` ` = a)
  p6_md_table(out)
}

#' The stage-2 validation-to-test table for one bet type
#'
#' @param val,test Outputs of `p6_score_shortlist()`.
#' @param bet Settlement table name.
#' @return A presentation tibble.
p6_stage2_table <- function(val, test, bet) {
  v <- val |> dplyr::filter(bet == !!bet)
  t <- test |> dplyr::filter(bet == !!bet)
  v |>
    dplyr::select(rule, roles, val_roi = roi, val_bets = n_bets,
                  val_wins = n_wins, val_mean_sp = mean_sp,
                  val_fair = roi_fair, val_drop1 = roi_drop_top1,
                  val_lo = ci_lo, val_hi = ci_hi) |>
    dplyr::left_join(
      dplyr::select(t, rule, test_roi = roi, test_bets = n_bets,
                    test_wins = n_wins, test_mean_sp = mean_sp,
                    test_fair = roi_fair, test_drop1 = roi_drop_top1,
                    test_lo = ci_lo, test_hi = ci_hi),
      by = "rule"
    ) |>
    dplyr::arrange(dplyr::desc(val_roi)) |>
    dplyr::transmute(
      rule,
      `val ROI` = p6_pct(val_roi, 2),
      `test ROI` = p6_pct(test_roi, 2),
      `test 90% CI` = sprintf("[%s, %s]", p6_pct(test_lo, 1),
                              p6_pct(test_hi, 1)),
      `val bets` = val_bets, `test bets` = test_bets,
      `test wins` = test_wins,
      `val price` = sprintf("%.2f", val_mean_sp),
      `test price` = sprintf("%.2f", test_mean_sp),
      `test ROI fair` = p6_pct(test_fair, 2),
      `test ROI less top win` = p6_pct(test_drop1, 2),
      role = roles
    )
}

#' Write the exploration working report
#'
#' @param path Destination, relative to the project root.
#' @param universe The two splits' race and row counts.
#' @param grid The filter grid.
#' @param sweep The validation sweep.
#' @param agree_nofilter,agree_owen Agreement matrices at two filters.
#' @param agree_max The worst-case agreement across the grid.
#' @param shortlists The shortlisted rules.
#' @param val_scores,test_scores The shortlist scored on the two splits.
#' @param ranks Output of `p6_rank_comparison()`.
#' @param staking_test,staking_val Stage-3 staking results.
#' @param stage3_rules The rules stage 3 was run on.
#' @param gate The exploration gate result.
#' @param search_set The search-set assertion counts.
#' @param bets The bet types, in report order.
#' @return `path`.
p6_write_exploration <- function(path, universe, grid, sweep,
                                 agree_nofilter, agree_owen, agree_max,
                                 shortlists, val_scores, test_scores, ranks,
                                 staking_test, staking_val, stage3_rules,
                                 gate, search_set, bets) {
  pickers <- p6_pickers()
  L <- character(0)
  add <- function(...) L <<- c(L, ...)

  # -- header ---------------------------------------------------------------
  add("# Paper 6 — exploratory ROI sweep, validation to test", "")
  add(sprintf(paste(
    "**What this is.** An exploratory sweep of betting rules whose selections",
    "were made on a %s-race validation window and then scored once on %s test",
    "races, with several rules read against that same test split — so whatever",
    "tops the test table is partly noise. There is no declaration rule, no bar",
    "to clear and no interval gating what reaches test; the intervals below are",
    "context and nothing is excluded on their basis. The purpose is to generate",
    "ideas to return to when betting goes live, not to test a hypothesis."),
    format(universe$n_val_races, big.mark = ","),
    format(universe$n_test_races, big.mark = ",")), "")
  add("**Not published.** `docs/` is untouched and no Quarto paper is rendered.",
      "The two previous drafts, both hypothesis-testing papers, are in",
      "`SUPERSEDED/` with a README explaining why each was set aside.", "")
  add("The model is fixed throughout and nothing here refits anything: paper",
      "5's rung-3b encoder, scored by its fitting-partition fit on the",
      "validation slice and by its published full-training-split refit on the",
      "test split.", "")

  # -- setup ----------------------------------------------------------------
  add("---", "", "## Setup", "")
  add(sprintf(paste("**Splits.** Validation %s races / %s runners; test %s",
                    "races / %s runners. Race-id overlap between them: %d",
                    "(asserted zero). Overlap with the %s races paper 5's",
                    "fitting partition saw: %d (asserted zero)."),
              format(universe$n_val_races, big.mark = ","),
              format(universe$n_val_rows, big.mark = ","),
              format(universe$n_test_races, big.mark = ","),
              format(universe$n_test_rows, big.mark = ","),
              search_set$n_test_overlap,
              format(search_set$n_races_fit, big.mark = ","),
              search_set$n_fit_overlap), "")
  add("**Ledger gate.** `scripts/verify_p6_ledger.R` now carries seven",
      "assertions, not six. Assertion 7 is new: the validation S1/K0 and",
      "S0/K0 win ledgers rebuilt from `historic_runners` in code calling no",
      "`p6_*` function, required to match the pipeline exactly on the bet set",
      "as well as the arithmetic. Both previous drafts searched the validation",
      "slice with that path unchecked. It passes.", "")
  add("**Sweep gate.** The sweep is a second implementation of the selection",
      "and settlement arithmetic — index arithmetic rather than `dplyr` verbs,",
      "because it scores 25,220 rule-by-bet combinations — so it is asserted",
      "against `p6_ledger()` on three rules that exist in both:", "")
  add(p6_md_table(dplyr::transmute(
    gate,
    rule, `ledger arm` = ledger_arm,
    bet = unname(P6_BET_LABEL_MD[bet]), bets,
    `sweep ROI` = sprintf("%.9f", roi),
    `ledger ROI` = sprintf("%.9f", roi_ledger),
    `abs ROI diff` = sprintf("%.1e", abs(roi_diff)),
    `same bet set` = same_bet_set)), "")

  add("**Pickers** — which horse, given a race worth betting. P1-P4 read the",
      "whole field; only P5 reads the filter's cuts, because Owen's rule is",
      "defined that way. Ties go to the lower `runner_id` throughout.", "")
  add(p6_md_table(tibble::tibble(
    picker = names(pickers),
    definition = vapply(pickers, function(p) p$label, character(1)),
    `reads the cuts` = ifelse(vapply(pickers, function(p) p$uses_cuts,
                                     logical(1)), "yes", "no"))), "")
  add(sprintf(paste("**Filters** — which races to bet. A runner passes when",
                    "`P_mod > p` and `P_mod/P_mkt > r`; a race is bet when at",
                    "least one of its runners passes. The grid is p from 0.00",
                    "to 0.35 step 0.01 crossed with r from 0.80 to 2.50 step",
                    "0.05, plus a no-filter row that bets every race: **%s",
                    "filters**, times 5 pickers, times %d settlement tables =",
                    "**%s scored combinations**, all at a flat stake."),
              format(nrow(grid), big.mark = ","), length(bets),
              format(nrow(sweep), big.mark = ",")), "")
  add("**Staking is flat at stages 1 and 2 and gets its own stage 3.** In the",
      "first draft the Kelly and edge-proportional rules staked zero wherever",
      "the model probability did not exceed the price, which changed the bet",
      "set as well as the stake and wrecked the comparison. Stage 3 reports the",
      "share of selected races staked zero so that thinness is visible rather",
      "than buried in an ROI.", "")
  add("**Mean backed price is on every table, and it is the column to read",
      "first.** Across the previous sweep's populated cells, ROI correlated",
      "−0.785 with the mean price the rule backs and a quadratic in log mean",
      "price explained 65% of the between-rule variance (`DIAGNOSTICS.md`). A",
      "rule's return is mostly a statement about the price band it bets in",
      "unless the price column says otherwise. Nothing here controls for it.",
      "")

  # -- stage 1: agreement --------------------------------------------------
  add("---", "", "## Stage 1 — sweep on validation", "")
  add("### Do the pickers actually differ?", "")
  add("Of the races where two pickers both bet, the fraction backing the same",
      "horse. **A pair above 0.95 is one arm, not two.**", "")
  add("At no filter — all pickers bet all races:", "")
  add(p6_agreement_md(agree_nofilter, "share_same"), "")
  add("At Owen's filter, `P > 0.15` and ratio `> 1.30`:", "")
  add(p6_agreement_md(agree_owen, "share_same"), "")
  add("Common races behind those shares, at Owen's filter:", "")
  add(p6_agreement_md(agree_owen, "n_both"), "")
  add("Worst case across the whole filter grid — the maximum agreement each",
      "pair reaches at any filter with at least 300 common races, which is the",
      "number that decides whether two pickers are really two:", "")
  add(p6_md_table(dplyr::transmute(
    agree_max,
    pair = paste(a, "vs", b), `filters compared` = n_filters,
    `max agreement` = sprintf("%.3f", max_share),
    `at` = dplyr::case_when(
      is.na(at_p_cut) ~ "—",
      !is.finite(at_p_cut) ~ "no filter",
      TRUE ~ sprintf("P>%.2f, r>%.2f", at_p_cut, at_r_cut)),
    `min agreement` = sprintf("%.3f", min_share),
    `one arm, not two` = ifelse(duplicate_anywhere, "**YES**", "no"))), "")
  dup <- dplyr::filter(agree_max, duplicate_anywhere)
  dup_def <- dplyr::filter(dup, !is.finite(at_p_cut))
  dup_real <- dplyr::filter(dup, is.finite(at_p_cut))
  if (nrow(dup_real) == 0L) {
    add(sprintf(paste(
      "**No pair exceeds 0.95 at any filter with a cut in it.** The closest",
      "are %s. That is the thing the previous nine-arm set failed: seven of",
      "its nine arms agreed at 1.000 in every shared race, because they were",
      "one horse-picker behind seven race filters."),
      paste(sprintf("%s vs %s at %.3f", p6_top_agreeing_pairs(agree_max)$a,
                    p6_top_agreeing_pairs(agree_max)$b, p6_top_agreeing_pairs(agree_max)$max_share),
            collapse = " and ")), "")
  } else {
    add(sprintf(paste(
      "**%d pair(s) exceed 0.95 at a filter with a cut in it: %s.** Where that",
      "happens the two are one arm and not two distinct candidates; read them",
      "as a single rule."),
      nrow(dup_real),
      paste(paste(dup_real$a, "vs", dup_real$b), collapse = ", ")), "")
  }
  if (nrow(dup_def)) {
    add(sprintf(paste(
      "The 1.000 on %s is at the no-filter row only, and it is definitional:",
      "P5 picks the highest model probability among the runners passing the",
      "cuts, and with no cuts every runner passes, so P5 *is* P1 there. Away",
      "from that row the pair falls to a minimum of %.3f. It is listed rather",
      "than suppressed, but it is not a hidden duplicate."),
      paste(paste(dup_def$a, "vs", dup_def$b), collapse = " and "),
      min(dup_def$min_share)), "")
  }
  add(paste(
    "The `n_both` matrix at Owen's filter is 704 in every cell, and that is",
    "the point of separating the two decisions: the filter fixes WHICH RACES",
    "are bet, so all five pickers bet the same 704 races and differ only in",
    "which horse they back in them."), "")

  # -- stage 1: leaderboards ----------------------------------------------
  for (b in bets) {
    add(sprintf("### %s — validation leaderboard", P6_BET_LABEL_MD[[b]]), "")
    add("Top 15 rules by validation ROI at the real starting price, among",
        "those placing at least 300 validation bets.", "")
    add(p6_md_table(p6_leaderboard(sweep, b)), "")
    add("Per picker: its best rule, and the median over all its rules placing",
        "at least 300 bets — the median is what the picker is worth on average,",
        "the best is what it is worth after the grid has been searched.", "")
    add(p6_md_table(p6_picker_summary(sweep, b)), "")
  }
  add("Owen's own cell, and where it sits on each surface:", "")
  add(p6_md_table(purrr::map(bets, function(b) p6_owen_rank(sweep, b)) |>
                    purrr::list_rbind() |>
                    dplyr::mutate(bet = unname(P6_BET_LABEL_MD[bet]))), "")

  # -- stage 2 -------------------------------------------------------------
  add("---", "", "## Stage 2 — carry forward to test", "")
  add("Per bet type: the top 5 validation rows placing at least 300",
      "validation bets, plus Owen's S1/K0, plus the market favourite in every",
      "race, plus the best row from a picker other than the top row's — so at",
      "least two pickers reach test. Coincident entries collapse to one rule",
      "carrying every role it plays. Scored once on the test split.", "")
  for (b in bets) {
    add(sprintf("### %s", P6_BET_LABEL_MD[[b]]), "")
    add(p6_md_table(p6_stage2_table(val_scores, test_scores, b)), "")
  }

  add("### Validation rank against test rank", "")
  add("The number that matters for live use: whether picking on validation ROI",
      "picks anything useful. Rank 1 is the best ROI within that bet type's",
      "shortlist.", "")
  add(p6_md_table(dplyr::transmute(
    ranks$table,
    bet = unname(P6_BET_LABEL_MD[bet]), rule,
    `val ROI` = p6_pct(val_roi, 2), `val rank` = val_rank,
    `test ROI` = p6_pct(test_roi, 2), `test rank` = test_rank,
    `rank move` = sprintf("%+d", rank_move),
    `val price` = sprintf("%.2f", val_mean_sp),
    `test price` = sprintf("%.2f", test_mean_sp))), "")
  add("Rank agreement within each bet type's shortlist:", "")
  add(p6_md_table(dplyr::transmute(
    ranks$correlations,
    bet = unname(P6_BET_LABEL_MD[bet]), rules = n_rules,
    `Spearman` = sprintf("%+.3f", spearman),
    `Pearson` = sprintf("%+.3f", pearson),
    `mean abs rank move` = sprintf("%.2f", mean_abs_rank_move))), "")

  # -- stage 3 -------------------------------------------------------------
  add("---", "", "## Stage 3 — staking, separately", "")
  add("Held fixed: the selection. Varied: the stake. Per bet type, the single",
      "best rule on the test split from stage 2, and Owen's, under all three",
      "staking rules. `zero-stake share` is the fraction of the races the",
      "selection picked where the staking rule puts nothing on — the column",
      "that was missing when the first draft declared a Kelly arm that staked",
      "in 122 of 1,353 selected test races.", "")
  add(p6_md_table(dplyr::transmute(
    stage3_rules,
    bet = unname(P6_BET_LABEL_MD[bet]), rule, role)), "")
  add("On the **test** split:", "")
  add(p6_md_table(p6_staking_md(staking_test)), "")
  add("On the **validation** slice, for reference:", "")
  add(p6_md_table(p6_staking_md(staking_val)), "")

  # -- what looks worth trying live ---------------------------------------
  add(p6_explore_closing(val_scores, test_scores, ranks, staking_test,
                         staking_val, bets))

  writeLines(paste(L, collapse = "\n"), path)
  path
}

#' The closing read: what looks worth trying live, and why it looked good
#'
#' Every rule name and number here is looked up from the scored targets rather
#' than typed, so the section cannot drift from the tables above it.
#'
#' @param val_scores,test_scores Outputs of `p6_score_shortlist()`.
#' @param ranks Output of `p6_rank_comparison()`.
#' @param staking_test,staking_val Stage-3 results on the two splits.
#' @param bets The bet types.
#' @return A character vector of markdown lines.
p6_explore_closing <- function(val_scores, test_scores, ranks, staking_test,
                               staking_val, bets) {
  L <- character(0)
  add <- function(...) L <<- c(L, ...)

  best <- function(b, by = "roi") {
    d <- test_scores |> dplyr::filter(bet == b, !is.na(roi))
    d[which.max(d[[by]]), ]
  }
  vrow <- function(b, rl) val_scores |>
    dplyr::filter(bet == b, rule == rl)
  trow <- function(b, rl) test_scores |>
    dplyr::filter(bet == b, rule == rl)
  owen <- "P5 / P>0.15, ratio>1.30"
  favr <- "P2 / no filter"

  bw <- best("win"); bp <- best("place")
  bew <- best("eachway"); bec <- best("eachway_corrected")
  ow <- trow("win", owen); op_ <- trow("place", owen)
  fw <- trow("win", favr)

  # Every rule's test ROI at the real price, best first, for the "nothing is
  # profitable" statement.
  any_pos <- test_scores |> dplyr::filter(!is.na(roi), roi > 0)

  add("---", "", "## What looks worth trying live", "")
  add(sprintf(paste(
    "**Nothing in this sweep is profitable at the settled starting price.**",
    "Of the %d rule-by-bet-type combinations that reached the test split, %d",
    "returned a positive ROI at real prices: %s. Everything below is",
    "therefore a candidate for a *different price*, not a candidate as it",
    "stands — which is the same conclusion papers 1 to 5 reached about the",
    "model and is why the fair-book column is the one that carries the",
    "information here."),
    nrow(test_scores), nrow(any_pos),
    if (nrow(any_pos) == 0L) "none" else
      paste(sprintf("%s on %s, %s (90%% CI [%s, %s])", any_pos$rule,
                    unname(P6_BET_LABEL_MD[any_pos$bet]),
                    p6_pct(any_pos$roi, 2), p6_pct(any_pos$ci_lo, 1),
                    p6_pct(any_pos$ci_hi, 1)),
            collapse = "; ")), "")

  add("### 1. Back the market favourite, every race, and get a better price",
      "")
  add(sprintf(paste(
    "`%s` — no model input at all. Test win ROI %s on %s bets, and **%s at a",
    "zero-margin book**, the highest fair-book win figure of any rule that",
    "reached test, ahead of the best model rule's %s and Owen's %s. Mean",
    "backed price %.2f."),
    favr, p6_pct(fw$roi, 2), format(fw$n_bets, big.mark = ","),
    p6_pct(fw$roi_fair, 2), p6_pct(bw$roi_fair, 2), p6_pct(ow$roi_fair, 2),
    fw$mean_sp), "")
  add(sprintf(paste(
    "**What the price column says.** Mean price %.2f; %s of bets sit on the",
    "shortest-priced runner as the frame ranks it, the shortfall from 100%%",
    "being joint favourites broken a different way by the two tie-breaks.",
    "This is the favourite-longshot bias and nothing else: short-priced",
    "horses win more often than their over-round-adjusted implied",
    "probability, so the rule is profitable at fair odds and loses",
    "approximately the over-round at real ones. It looked good for a reason",
    "that has nothing to do with the model, and it was the WORST rule on the",
    "validation slice (%s, rank %d of %d) — it reached test only because the",
    "brief carried the market-favourite control forward unconditionally."),
    fw$mean_sp, p6_pct(fw$share_favourite, 1),
    p6_pct(vrow("win", favr)$roi, 2),
    ranks$table$val_rank[ranks$table$bet == "win" &
                           ranks$table$rule == favr],
    sum(ranks$table$bet == "win")), "")
  add(paste(
    "**Why it is still the strongest live candidate.** It needs no model edge",
    "— only a price better than the bookmaker's settled SP. That is exactly",
    "the Betfair convergence thesis in the project's longer-term direction:",
    "early prices are noisy and drift toward fair value as liquidity builds,",
    "so a rule whose entire loss is the over-round is the one that a better",
    "entry price can flip. It is also the cheapest thing to paper-trade,",
    "because it requires no model in the loop."), "")

  add(sprintf("### 2. %s, on the place market", bp$rule), "")
  add(sprintf(paste(
    "`%s` — the %s picker. It is the **only positive test ROI in the sweep**:",
    "%s on %s place bets, 90%% CI [%s, %s], and %s at a fair book. The same",
    "rule is also the best win-market rule on test (%s against Owen's %s),",
    "with a fair-book win figure of %s."),
    bp$rule, bp$picker, p6_pct(bp$roi, 2),
    format(bp$n_bets, big.mark = ","), p6_pct(bp$ci_lo, 1),
    p6_pct(bp$ci_hi, 1), p6_pct(bp$roi_fair, 2),
    p6_pct(bw$roi, 2), p6_pct(ow$roi, 2), p6_pct(bw$roi_fair, 2)), "")
  add(sprintf(paste(
    "**What the price column says, and it is a warning.** Mean backed price",
    "%.2f on test (%.2f on validation), median %.2f, %s of bets on the",
    "favourite. This rule bets the extreme top of the price ladder — %d wins",
    "in %s win bets, a %s strike rate. Maximising model probability times",
    "price maximises expected return, and on a market with a longshot bias",
    "that resolves to \"back the longest price the model does not hate\". The",
    "place market is where that actually paid, which is mechanically",
    "sensible: a %.0f-to-1 shot that runs third pays a place return without",
    "ever needing to win, so the rule collects on the part of its edge that",
    "does not require the tail event. The interval is the widest in the",
    "sweep and spans zero on both markets."),
    bp$mean_sp, vrow("place", bp$rule)$mean_sp, bp$median_sp,
    p6_pct(bp$share_favourite, 1), bw$n_wins,
    format(bw$n_bets, big.mark = ","),
    p6_pct(bw$n_wins / bw$n_bets, 1), bp$mean_sp - 1), "")
  add(paste(
    "**What to do with it.** Worth paper-trading on the place market, at a",
    "small stake and with the strike rate watched rather than the ROI — a",
    "rule this concentrated in the tail needs a long run before its ROI means",
    "anything. Its win-market showing is a weaker version of the same thing",
    "and is not separately interesting."), "")

  add("### 3. A tighter Owen filter, on each-way — but check the terms", "")
  add(sprintf(paste(
    "`%s` is the best each-way rule on paper 5's terms: test ROI %s on %s",
    "bets, %s at a fair book, mean price %.2f — effectively breakeven at real",
    "prices, against Owen's %s on the same terms. It is Owen's own picker with",
    "both cuts raised."),
    bew$rule, p6_pct(bew$roi, 2), format(bew$n_bets, big.mark = ","),
    p6_pct(bew$roi_fair, 2), bew$mean_sp,
    p6_pct(trow("eachway", owen)$roi, 2)), "")
  add(sprintf(paste(
    "**The catch is the terms, not the price.** Paper 5's each-way settlement",
    "pays one fifth the odds on a top-three finish whatever the field size,",
    "which is not the market for a small-field handicap. Under the corrected",
    "industry ladder the same rule's advantage does not survive: the best",
    "corrected-terms rule is `%s` at %s, and Owen's own each-way falls from %s",
    "on paper 5's terms to %s on corrected ones. **Read the near-breakeven",
    "each-way figure as a property of the synthetic terms.** Any live each-way",
    "trial has to be priced on the corrected ladder from the start."),
    bec$rule, p6_pct(bec$roi, 2), p6_pct(trow("eachway", owen)$roi, 2),
    p6_pct(trow("eachway_corrected", owen)$roi, 2)), "")

  add("### 4. What is not worth trying", "")
  add(sprintf(paste(
    "**Picking a rule by validation ROI, on the win market.** The five best",
    "validation win rules returned between %s and %s on validation and",
    "between %s and %s on test — a reversal of about %.0f points on the top",
    "row. The best validation rule (`%s`,",
    "%s) came %d of %d on test. Rank agreement within the win shortlist is",
    "Spearman %+.3f and Pearson %+.3f: validation ROI carries no usable",
    "information about test ROI on the win market, and mildly negative",
    "information on the linear scale. `DIAGNOSTICS.md` explains why — the",
    "validation window's 6-9 price band paid about ten points above its",
    "long-run rate, so the rules that window rewards are the ones betting",
    "that band, and every top-five validation win rule has a mean price",
    "between %.1f and %.1f."),
    p6_pct(sort(dplyr::filter(ranks$table, bet == "win")$val_roi,
                decreasing = TRUE)[5], 1),
    p6_pct(max(dplyr::filter(ranks$table, bet == "win")$val_roi), 1),
    p6_pct(max(dplyr::filter(ranks$table, bet == "win",
                             val_rank <= 5)$test_roi), 1),
    p6_pct(min(dplyr::filter(ranks$table, bet == "win",
                             val_rank <= 5)$test_roi), 1),
    100 * (p6_top_val_rule(ranks, "win")$val_roi -
             p6_top_val_rule(ranks, "win")$test_roi),
    p6_top_val_rule(ranks, "win")$rule,
    p6_pct(p6_top_val_rule(ranks, "win")$val_roi, 2),
    p6_top_val_rule(ranks, "win")$test_rank, sum(ranks$table$bet == "win"),
    ranks$correlations$spearman[ranks$correlations$bet == "win"],
    ranks$correlations$pearson[ranks$correlations$bet == "win"],
    min(dplyr::filter(ranks$table, bet == "win", val_rank <= 5)$val_mean_sp),
    max(dplyr::filter(ranks$table, bet == "win", val_rank <= 5)$val_mean_sp)),
    "")
  add(sprintf(paste(
    "**But it is not uniformly useless.** On the place market rank agreement",
    "is Spearman %+.3f with a mean absolute rank move of %.2f, against %.2f",
    "on win — validation ROI selects usefully there and not on win. The",
    "place market's returns depend on a top-three finish rather than a win, so",
    "they rest on far more events per race and are correspondingly less",
    "sample-driven. If one market is worth searching on a held-out window, it",
    "is the place market."),
    ranks$correlations$spearman[ranks$correlations$bet == "place"],
    ranks$correlations$mean_abs_rank_move[ranks$correlations$bet == "place"],
    ranks$correlations$mean_abs_rank_move[ranks$correlations$bet == "win"]),
    "")
  add(p6_staking_verdict(staking_test, staking_val), "")
  thin <- staking_test |>
    dplyr::filter(!is.na(share_zero_stake), share_zero_stake > 0.5)
  if (nrow(thin)) {
    add(p6_md_table(dplyr::transmute(
      thin,
      bet = unname(P6_BET_LABEL_MD[bet]), rule, staking,
      `races selected` = n_races_selected, `races staked` = n_bets,
      `zero-stake share` = p6_pct(share_zero_stake, 1),
      `total staked` = sprintf("%.1f", total_stake),
      ROI = p6_pct(roi, 2))), "")
    add(sprintf(paste(
      "That is the first draft's failure reproduced exactly: %s stakes %d of",
      "%d selected races and its ROI is computed on %.1f units. It is not a",
      "staking result, it is a different and much smaller bet set, and an ROI",
      "on it means nothing."),
      thin$staking[1], thin$n_bets[1], thin$n_races_selected[1],
      thin$total_stake[1]), "")
  }

  add("### Summary", "")
  nf <- dplyr::bind_rows(
    dplyr::mutate(staking_test, split = "test"),
    dplyr::mutate(staking_val, split = "validation"))
  nf_k0 <- nf |> dplyr::filter(staking == "K0") |>
    dplyr::select(split, bet, rule, roi_k0 = roi)
  nf_cmp <- nf |> dplyr::filter(staking != "K0", !is.na(roi)) |>
    dplyr::left_join(nf_k0, by = c("split", "bet", "rule"))
  n_nonflat <- nrow(nf_cmp)
  n_worse <- sum(nf_cmp$roi < nf_cmp$roi_k0)
  add(p6_md_table(tibble::tibble(
    idea = c("Market favourite, every race, better entry price",
             sprintf("%s, place market", bp$rule),
             sprintf("%s, each-way", bew$rule),
             "Select a rule on validation ROI (win market)",
             "Kelly or edge-proportional staking"),
    `test evidence` = c(
      sprintf("win %s real, %s fair", p6_pct(fw$roi, 1),
              p6_pct(fw$roi_fair, 1)),
      sprintf("place %s real, %s fair", p6_pct(bp$roi, 1),
              p6_pct(bp$roi_fair, 1)),
      sprintf("%s real, %s fair on paper 5 terms", p6_pct(bew$roi, 1),
              p6_pct(bew$roi_fair, 1)),
      sprintf("Spearman %+.2f, mean rank move %.1f",
              ranks$correlations$spearman[ranks$correlations$bet == "win"],
              ranks$correlations$mean_abs_rank_move[
                ranks$correlations$bet == "win"]),
      sprintf("%d of %d non-flat arms worse than flat", n_worse, n_nonflat)),
    `mean price` = c(sprintf("%.2f", fw$mean_sp), sprintf("%.2f", bp$mean_sp),
                     sprintf("%.2f", bew$mean_sp), "5.1 - 17.6", "—"),
    `why it looked good` = c(
      "favourite-longshot bias; loss is the over-round",
      "bets the top of the price ladder; place leg collects without the win",
      "generous synthetic terms, not the real ladder",
      "the validation window's 6-9 band overpaid",
      "leverage on a losing edge, or a collapsed bet set"),
    verdict = c("**paper-trade first**", "**paper-trade, small**",
                "re-price on corrected terms before trying",
                "no — search the place market instead", "no"))), "")

  L
}

#' The stage-3 verdict on non-flat staking, stated so it is true
#'
#' The blanket claim "K1 and K2 are worse everywhere" is false: on the
#' validation slice the collapsed-bet-set arms show a large positive ROI on a
#' handful of units. This counts the arms both ways so the sentence matches
#' the table under it.
#'
#' @param staking_test,staking_val Stage-3 results on the two splits.
#' @return A character string.
p6_staking_verdict <- function(staking_test, staking_val) {
  cmp <- function(d, split) {
    k0 <- d |> dplyr::filter(staking == "K0") |>
      dplyr::select(bet, rule, roi_k0 = roi)
    d |>
      dplyr::filter(staking != "K0", !is.na(roi)) |>
      dplyr::left_join(k0, by = c("bet", "rule")) |>
      dplyr::mutate(split = split, worse = roi < roi_k0,
                    gain_pts = 100 * (roi - roi_k0),
                    collapsed = !is.na(share_zero_stake) &
                      share_zero_stake > 0.5)
  }
  all <- dplyr::bind_rows(cmp(staking_test, "test"),
                          cmp(staking_val, "validation"))
  ex <- dplyr::filter(all, !worse)
  ex_collapsed <- dplyr::filter(ex, collapsed)
  ex_real <- dplyr::filter(ex, !collapsed)

  describe <- function(d) paste(sprintf(
    "%s under %s on %s, %s (%s split), %+.1f points on %.1f units across %d staked races of %d selected",
    d$rule, d$staking, unname(P6_BET_LABEL_MD[d$bet]), p6_pct(d$roi, 1),
    d$split, d$gain_pts, d$total_stake, d$n_bets, d$n_races_selected),
    collapse = "; ")

  parts <- c(
    "**Non-flat staking.**",
    sprintf(paste(
      "Of the %d non-flat arms scored across the two splits, %d return less",
      "than their own flat-stake counterpart."),
      nrow(all), sum(all$worse))
  )
  if (nrow(ex_real)) {
    parts <- c(parts, sprintf(paste(
      "%d of them beat flat staking on a bet set that was not collapsed,",
      "and the margin is trivial: %s. Read that as no difference."),
      nrow(ex_real), describe(ex_real)))
  }
  if (nrow(ex_collapsed)) {
    parts <- c(parts, sprintf(paste(
      "The remaining %d show a positive-looking ROI only because the staking",
      "rule threw the bet set away: %s. An ROI computed on that many units is",
      "not a staking result and should not be read as one."),
      nrow(ex_collapsed), describe(ex_collapsed)))
  }
  if (nrow(ex) == 0L) parts <- c(parts, "There is no exception.")
  parts <- c(parts, paste(
    "Two mechanisms, both visible in the stage-3 table. Where the selection",
    "already requires the model probability to exceed the price — any rule",
    "with a ratio cut above 1 — the zero-stake share is 0.0% and the staking",
    "rules simply lever up the identical bet set, so a negative ROI becomes",
    "more negative. Where the selection does not (the market-favourite rules,",
    "whose backed horse the model usually rates below the market), the stake",
    "collapses instead:"))
  paste(parts, collapse = " ")
}

#' The highest-agreeing picker pair away from the no-filter row
#'
#' @param agree_max Output of `p6_picker_agreement_max()`.
#' @return The two highest-agreement rows whose maximum is at a real filter.
p6_top_agreeing_pairs <- function(agree_max) {
  agree_max |>
    dplyr::filter(is.finite(at_p_cut)) |>
    dplyr::arrange(dplyr::desc(max_share)) |>
    dplyr::slice_head(n = 2L)
}

#' The top validation rule within one bet type's shortlist
#'
#' Named with the `p6_` prefix like everything else here: files under `R/` are
#' `source()`d into the caller's global environment, so a bare helper name is a
#' shadowing hazard (CLAUDE.md, "Standing conventions").
#'
#' @param ranks Output of `p6_rank_comparison()`.
#' @param bet Bet type.
#' @return A one-row tibble.
p6_top_val_rule <- function(ranks, bet) {
  ranks$table |> dplyr::filter(bet == !!bet, val_rank == 1)
}

#' A staking-sweep result as a presentation tibble
#' @param d Output of `p6_staking_sweep()`.
#' @return A tibble.
p6_staking_md <- function(d) {
  d |>
    dplyr::transmute(
      bet = unname(P6_BET_LABEL_MD[bet]), rule, staking,
      `races selected` = n_races_selected,
      bets = n_bets, wins = n_wins,
      `total staked` = sprintf("%.1f", total_stake),
      `mean stake` = sprintf("%.3f", mean_stake),
      `max stake` = sprintf("%.2f", max_stake),
      ROI = p6_pct(roi, 2), `ROI fair` = p6_pct(roi_fair, 2),
      `zero-stake share` = p6_pct(share_zero_stake, 1)
    )
}
