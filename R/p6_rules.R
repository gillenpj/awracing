# p6_rules.R
# Paper 6 — the selection and staking candidates, the eligibility gate, and
# the two-stage declaration.
#
# THRESHOLDS ARE QUANTILES, AND HAVE TO BE. The search set and the test split
# are scored by different fits of the same architecture — one trained on 3,517
# races, one on 5,022 — so their probability distributions differ in scale. An
# absolute cut declared on one would select a different fraction of races on
# the other, and the difference between the two arms would then be partly a
# difference in how much they bet. Every candidate threshold is therefore a
# quantile of the WITHIN-SPLIT distribution of the quantity filtered on, taken
# over the model's top-rated horse in each race. S1 keeps its published
# absolute form (0.15 / 1.3) because it is the incumbent being tested, not a
# candidate being tuned.
#
# Staking constants are round numbers fixed a priori, not fitted: a five-point
# probability edge stakes one unit under K1, and a quarter-Kelly fraction of
# five per cent of bankroll stakes one unit under K2. ROI is invariant to that
# scale except through the three-unit cap, so the constants matter only in
# where the cap bites; they are recorded so the cap is reproducible.

P6_EDGE_UNIT   <- 0.05  # K1: probability edge that stakes one unit
P6_KELLY_UNIT  <- 0.05  # K2: quarter-Kelly fraction that stakes one unit
P6_STAKE_CAP   <- 3     # both: maximum units on one leg

# Eligibility, applied BEFORE the argmax rather than after it.
P6_MIN_PROJECTED_TEST_BETS <- 300   # projected = val bets x (n_test / n_val)
P6_MIN_STAKED_SHARE        <- 0.60  # share of selected races actually staked

#' Quantile cuts for the selection candidates
#'
#' Computed on whichever split is passed, over the model's top-rated horse in
#' each race. The search set's cuts are the ones declared; the test split's
#' are recomputed from the test split's own distribution, which is what makes
#' a declared rule select the same fraction of races on both.
#'
#' @param frame A `p6_build_bet_frame()` output.
#' @return A list with the ratio and starting-price quantile vectors.
p6_thresholds <- function(frame) {
  top <- p6_top_rated(frame)
  list(
    ratio_q = stats::quantile(top$ratio, c(0.25, 0.30, 0.40, 0.60, 0.70, 0.75),
                              names = TRUE),
    sp_q    = stats::quantile(top$starting_price_decimal, c(0.25, 0.50, 0.75),
                              names = TRUE),
    n_races = nrow(top)
  )
}

#' The nine selection candidates
#'
#' @param thr Output of `p6_thresholds()` on the split being scored.
#' @return A named list of nine selection rules, each with `label` and `fn`.
p6_selection_rules <- function(thr) {
  band <- function(lo, hi) {
    force(lo); force(hi)
    function(frame) {
      p6_top_rated(frame) |> dplyr::filter(ratio >= lo, ratio <= hi)
    }
  }
  sp_cut <- function(cut) {
    force(cut)
    function(frame) {
      p6_top_rated(frame) |> dplyr::filter(starting_price_decimal <= cut)
    }
  }

  list(
    S0 = list(
      label = "S0 — model's top-rated horse, every race",
      fn = function(frame) p6_top_rated(frame)
    ),
    S1 = list(
      label = "S1 — Owen: P_mod > 0.15 and P_mod/P_mkt > 1.3, highest P_mod",
      fn = function(frame) {
        frame |>
          dplyr::filter(win_model > 0.15, ratio > 1.3) |>
          dplyr::group_by(race_id) |>
          dplyr::arrange(dplyr::desc(win_model), runner_id, .by_group = TRUE) |>
          dplyr::slice(1) |>
          dplyr::ungroup()
      }
    ),
    S2a = list(label = sprintf("S2a — top-rated, ratio in [q25, q75] = [%.3f, %.3f]",
                               thr$ratio_q[["25%"]], thr$ratio_q[["75%"]]),
               fn = band(thr$ratio_q[["25%"]], thr$ratio_q[["75%"]])),
    S2b = list(label = sprintf("S2b — top-rated, ratio in [q30, q60] = [%.3f, %.3f]",
                               thr$ratio_q[["30%"]], thr$ratio_q[["60%"]]),
               fn = band(thr$ratio_q[["30%"]], thr$ratio_q[["60%"]])),
    S2c = list(label = sprintf("S2c — top-rated, ratio in [q40, q70] = [%.3f, %.3f]",
                               thr$ratio_q[["40%"]], thr$ratio_q[["70%"]]),
               fn = band(thr$ratio_q[["40%"]], thr$ratio_q[["70%"]])),
    S3a = list(label = sprintf("S3a — top-rated, SP <= q25 = %.2f", thr$sp_q[["25%"]]),
               fn = sp_cut(thr$sp_q[["25%"]])),
    S3b = list(label = sprintf("S3b — top-rated, SP <= q50 = %.2f", thr$sp_q[["50%"]]),
               fn = sp_cut(thr$sp_q[["50%"]])),
    S3c = list(label = sprintf("S3c — top-rated, SP <= q75 = %.2f", thr$sp_q[["75%"]]),
               fn = sp_cut(thr$sp_q[["75%"]])),
    S4 = list(
      label = "S4 — market favourite, every race, no model input",
      fn = function(frame) {
        frame |>
          dplyr::group_by(race_id) |>
          dplyr::arrange(starting_price_decimal, runner_id, .by_group = TRUE) |>
          dplyr::slice(1) |>
          dplyr::ungroup()
      }
    )
  )
}

#' The three staking candidates
#'
#' Each returns the stake on the WIN leg, in units. An each-way bet stakes the
#' same on each leg, so its total stake is twice this (once, where the
#' corrected terms make a race win-only). All three read the selected runner's
#' win-side quantities whatever the bet type, so staking is one rule across
#' the three markets rather than three.
#'
#' K1 and K2 both stake zero where the model's probability does not exceed the
#' price. That makes them selection rules as well as staking rules, which is
#' what `P6_MIN_STAKED_SHARE` exists to catch.
#'
#' @return A named list of three staking rules.
p6_staking_rules <- function() {
  list(
    K0 = list(
      label = "K0 — flat, 1 unit",
      fn = function(sel) rep(1, nrow(sel))
    ),
    K1 = list(
      label = sprintf("K1 — (P_mod - P_mkt) / %.2f, capped at %d units",
                      P6_EDGE_UNIT, P6_STAKE_CAP),
      fn = function(sel) {
        pmin(P6_STAKE_CAP,
             pmax(0, (sel$win_model - sel$win_market) / P6_EDGE_UNIT))
      }
    ),
    K2 = list(
      label = sprintf("K2 — quarter-Kelly at P_mod against SP / %.2f, capped at %d units",
                      P6_KELLY_UNIT, P6_STAKE_CAP),
      fn = function(sel) {
        b <- sel$starting_price_decimal - 1
        f <- (sel$win_model * b - (1 - sel$win_model)) / b
        pmin(P6_STAKE_CAP, pmax(0, 0.25 * f / P6_KELLY_UNIT))
      }
    )
  )
}

#' Assert two rule specifications differ in exactly one term
#'
#' Paper 5's rung-1 standing lesson, enforced in code: an arm that differs
#' from its comparator in two respects at once cannot test what the contrast
#' exists to test. A paper-6 arm is a (selection, staking) pair, so "exactly
#' one term" means exactly one of the two names differs. Splitting the
#' declaration into two stages is what makes every contrast in this paper of
#' that shape — stage A varies selection at fixed K0, stage B varies staking
#' at a fixed selection.
#'
#' @param a,b Length-two character vectors, `c(selection, staking)`.
#' @return `TRUE`, invisibly; errors otherwise.
p6_assert_one_difference <- function(a, b) {
  stopifnot(length(a) == 2L, length(b) == 2L)
  n_diff <- sum(a != b)
  if (n_diff != 1L) {
    stop(sprintf(
      "Contrast %s/%s vs %s/%s differs in %d terms, not exactly one.",
      a[1], a[2], b[1], b[2], n_diff
    ))
  }
  invisible(TRUE)
}

# ---------------------------------------------------------------------------
# Scoring a set of arms
# ---------------------------------------------------------------------------

#' Score a set of (selection, staking) arms on one split
#'
#' @param frame A `p6_build_bet_frame()` output.
#' @param settle A `p6_settlement_tables()` output.
#' @param arms A tibble with `selection` and `staking` columns.
#' @param selections,stakings Rule registries.
#' @param bets Named character vector: reported bet name to settlement table.
#' @return A long tibble, one row per (selection, staking, bet), carrying the
#'   eligibility ingredients alongside the summary.
p6_score_arms <- function(frame, settle, arms, selections, stakings, bets) {
  purrr::pmap(arms, function(selection, staking, ...) {
    n_selected <- nrow(selections[[selection]]$fn(frame))
    purrr::imap(bets, function(tbl, bname) {
      led <- p6_ledger(frame, settle, selections[[selection]]$fn,
                       stakings[[staking]]$fn, tbl)
      dplyr::mutate(p6_summarise_ledger(led),
                    selection = selection, staking = staking, bet = bname,
                    n_races_selected = n_selected, .before = 1)
    }) |> purrr::list_rbind()
  }) |> purrr::list_rbind()
}

#' Build the ledgers for a set of arms, keyed by combination
#'
#' @inheritParams p6_score_arms
#' @return A named list, `"<selection>|<staking>|<bet>"` to ledger.
p6_build_ledgers <- function(frame, settle, arms, selections, stakings, bets) {
  out <- list()
  for (i in seq_len(nrow(arms))) {
    sname <- arms$selection[i]
    kname <- arms$staking[i]
    for (bname in names(bets)) {
      key <- paste(sname, kname, bname, sep = "|")
      out[[key]] <- p6_ledger(frame, settle, selections[[sname]]$fn,
                              stakings[[kname]]$fn, bets[[bname]])
    }
  }
  out
}

# ---------------------------------------------------------------------------
# Eligibility
# ---------------------------------------------------------------------------

#' Apply the eligibility gate to a scored grid
#'
#' Two conditions, both of which must hold before a candidate can be taken by
#' the argmax:
#'
#'   (i)  projected test bets >= `min_projected`, where the projection scales
#'        validation bets placed by the ratio of split sizes. This asks
#'        whether the arm would bet often enough on test for the result to
#'        mean anything.
#'   (ii) the arm places a positive stake in at least `min_share` of the races
#'        its selection rule selects. This is the direct guard against a
#'        staking rule that is secretly a selection rule: K1 and K2 stake zero
#'        where the model probability does not exceed the price, which happens
#'        far more often out of sample than in.
#'
#' A struck candidate is removed before the argmax, not after, and the reason
#' is recorded.
#'
#' @param grid Output of `p6_score_arms()`.
#' @param n_val,n_test Race counts of the two splits, for the projection.
#' @param min_projected,min_share The two thresholds.
#' @return `grid` with `projected_test_bets`, `staked_share`, `eligible` and
#'   `struck_because` columns added.
p6_apply_eligibility <- function(grid, n_val, n_test,
                                 min_projected = P6_MIN_PROJECTED_TEST_BETS,
                                 min_share = P6_MIN_STAKED_SHARE) {
  grid |>
    dplyr::mutate(
      projected_test_bets = n_bets * (n_test / n_val),
      staked_share = dplyr::if_else(n_races_selected > 0,
                                    n_bets / n_races_selected, NA_real_),
      ok_projected = !is.na(projected_test_bets) &
        projected_test_bets >= min_projected,
      ok_share = !is.na(staked_share) & staked_share >= min_share,
      eligible = ok_projected & ok_share,
      struck_because = dplyr::case_when(
        eligible ~ NA_character_,
        !ok_projected & !ok_share ~ "too few projected test bets; stakes too few of its selected races",
        !ok_projected ~ "too few projected test bets",
        TRUE ~ "stakes too few of its selected races"
      )
    )
}

# ---------------------------------------------------------------------------
# The two-stage declaration
# ---------------------------------------------------------------------------

P6_SELECTION_ORDER <- c("S0", "S1", "S2a", "S2b", "S2c", "S3a", "S3b", "S3c",
                        "S4")
P6_STAKING_ORDER <- c("K0", "K1", "K2")

#' One declaration step: mechanical, no judgement
#'
#' Among eligible candidates take the highest validation ROI at the real
#' starting price; paired race-level bootstrap of its difference from the
#' stage comparator on their common races; declare it only if the point
#' difference exceeds one bootstrap standard error of the difference,
#' otherwise declare the comparator. Ties on ROI to four decimals prefer the
#' lower-numbered selection arm, then K0 over K1 over K2.
#'
#' @param grid An eligibility-annotated `p6_score_arms()` output.
#' @param ledgers The matching `p6_build_ledgers()` output.
#' @param bet The settlement column to declare for.
#' @param comparator Length-two character vector, `c(selection, staking)`.
#' @param stage Label recorded on the output row.
#' @param n_boot,seed Bootstrap replicates and RNG seed.
#' @return A one-row tibble.
p6_declare_step <- function(grid, ledgers, bet, comparator, stage,
                            n_boot = 2000L, seed = 42L) {
  pool <- grid |>
    dplyr::filter(bet == !!bet, eligible, !is.na(roi))
  if (nrow(pool) == 0L) {
    stop(sprintf(
      "No candidate survives the eligibility gate for bet '%s' at stage %s.",
      bet, stage
    ))
  }

  cand <- pool |>
    dplyr::mutate(roi4 = round(roi, 4),
                  s_ord = match(selection, P6_SELECTION_ORDER),
                  k_ord = match(staking, P6_STAKING_ORDER)) |>
    dplyr::arrange(dplyr::desc(roi4), s_ord, k_ord) |>
    dplyr::slice(1)

  cmp_key <- paste(comparator[1], comparator[2], bet, sep = "|")
  cnd_key <- paste(cand$selection, cand$staking, bet, sep = "|")
  cmp_row <- grid |>
    dplyr::filter(selection == comparator[1], staking == comparator[2],
                  bet == !!bet)
  stopifnot(nrow(cmp_row) == 1L)

  if (identical(cnd_key, cmp_key)) {
    return(tibble::tibble(
      stage = stage, bet = bet,
      selection = comparator[1], staking = comparator[2],
      cand_selection = cand$selection, cand_staking = cand$staking,
      cand_roi = cand$roi, comparator_roi = cmp_row$roi,
      diff_point = 0, se = NA_real_, exceeds_one_se = FALSE,
      n_common = NA_integer_, n_bets = cand$n_bets,
      n_eligible = nrow(pool),
      note = "top eligible candidate is the comparator"
    ))
  }

  p6_assert_one_difference(c(cand$selection, cand$staking), comparator)

  a <- ledgers[[cnd_key]]
  b <- ledgers[[cmp_key]]
  races <- intersect(unique(a$race_id), unique(b$race_id))
  bs <- p6_paired_roi_se(p6_units(a), p6_units(b), races,
                         n_boot = n_boot, seed = seed)
  take <- !is.na(bs$se) && bs$diff_point > bs$se

  tibble::tibble(
    stage = stage, bet = bet,
    selection = if (take) cand$selection else comparator[1],
    staking   = if (take) cand$staking   else comparator[2],
    cand_selection = cand$selection, cand_staking = cand$staking,
    cand_roi = cand$roi, comparator_roi = cmp_row$roi,
    diff_point = bs$diff_point, se = bs$se,
    exceeds_one_se = take,
    n_common = bs$n_races,
    n_bets = if (take) cand$n_bets else cmp_row$n_bets,
    n_eligible = nrow(pool),
    note = if (take) "declared candidate" else
      "difference within one bootstrap SE — comparator declared"
  )
}
