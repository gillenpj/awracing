# p6_rules.R
# Paper 6 — the selection and staking candidates, and the declaration rule.
#
# Every threshold except S1's is a QUANTILE of the training-split distribution
# of the quantity filtered on, computed over the model's top-rated horse in
# each race. A rule declared on training therefore selects the same FRACTION
# of races on test rather than the same absolute cut, so a shift in the level
# of the model's probabilities between splits cannot silently change how much
# a rule bets. S1 keeps its published absolute form (0.15 / 1.3) because it is
# the incumbent being tested, not a candidate being tuned.
#
# Staking constants are round numbers fixed a priori, not fitted: a five-point
# probability edge stakes one unit under K1, and a quarter-Kelly fraction of
# five per cent of bankroll stakes one unit under K2. ROI is invariant to that
# scale except through the three-unit cap, so the constants matter only in
# where the cap bites; they are recorded so the cap is reproducible.

P6_EDGE_UNIT   <- 0.05  # K1: probability edge that stakes one unit
P6_KELLY_UNIT  <- 0.05  # K2: quarter-Kelly fraction that stakes one unit
P6_STAKE_CAP   <- 3     # both: maximum units on one leg

#' Quantile cuts for the selection candidates
#'
#' Computed once on the training split over the model's top-rated horse in
#' each race, then carried to test unchanged.
#'
#' @param train_frame Training-split output of `p6_build_bet_frame()`.
#' @return A list with the ratio and starting-price quantile vectors, plus the
#'   top-rated tibble the cuts were taken from.
p6_thresholds <- function(train_frame) {
  top <- p6_top_rated(train_frame)
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
#' Each element is a list with `label`, `family` (the term that varies inside
#' a family), and `fn`, a function of the frame returning at most one row per
#' race.
#'
#' @param thr Output of `p6_thresholds()`.
#' @return A named list of nine selection rules.
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
#' win-side quantities, whatever the bet type being settled, so staking is one
#' rule across the three markets rather than three.
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
#' exists to test. A paper-6 combination is a (selection, staking) pair, so
#' "exactly one term" means exactly one of the two names differs.
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

#' Score every selection x staking combination on one split
#'
#' @param frame Output of `p6_build_bet_frame()`.
#' @param settle Output of `p6_settlement_tables()`.
#' @param selections,stakings Rule registries.
#' @param bets Named character vector mapping a reported bet name to a
#'   settlement table name.
#' @return A long tibble, one row per (selection, staking, bet).
p6_score_grid <- function(frame, settle, selections, stakings, bets) {
  purrr::imap(selections, function(sel, sname) {
    purrr::imap(stakings, function(stk, kname) {
      purrr::imap(bets, function(tbl, bname) {
        led <- p6_ledger(frame, settle, sel$fn, stk$fn, tbl)
        dplyr::mutate(p6_summarise_ledger(led),
                      selection = sname, staking = kname, bet = bname,
                      .before = 1)
      }) |> purrr::list_rbind()
    }) |> purrr::list_rbind()
  }) |> purrr::list_rbind()
}

#' Build every ledger on one split, keyed by combination
#'
#' Kept separate from `p6_score_grid()` so the bootstrap can reach the bets
#' themselves without rebuilding them.
#'
#' @inheritParams p6_score_grid
#' @return A named list, `"<selection>|<staking>|<bet>"` to ledger.
p6_build_ledgers <- function(frame, settle, selections, stakings, bets) {
  out <- list()
  for (sname in names(selections)) {
    for (kname in names(stakings)) {
      for (bname in names(bets)) {
        key <- paste(sname, kname, bname, sep = "|")
        out[[key]] <- p6_ledger(frame, settle, selections[[sname]]$fn,
                                stakings[[kname]]$fn, bets[[bname]])
      }
    }
  }
  out
}

#' The declaration: mechanical, no judgement
#'
#' For one bet type: take the highest training-split ROI at real SP; paired
#' race-level bootstrap of its difference from S1/K0 on their common races;
#' declare it only if the point difference exceeds one bootstrap standard
#' error of the difference, otherwise declare S1/K0. Ties on ROI to four
#' decimals prefer the lower-numbered selection arm, then K0 over K1 over K2.
#'
#' @param grid Output of `p6_score_grid()`, one split.
#' @param ledgers Output of `p6_build_ledgers()`, same split.
#' @param bet The bet name to declare for.
#' @param n_boot,seed Bootstrap replicates and RNG seed.
#' @return A one-row tibble recording the candidate, the contrast and the call.
p6_declare <- function(grid, ledgers, bet, n_boot = 2000L, seed = 42L) {
  sel_order <- c("S0", "S1", "S2a", "S2b", "S2c", "S3a", "S3b", "S3c", "S4")
  stk_order <- c("K0", "K1", "K2")

  cand <- grid |>
    dplyr::filter(bet == !!bet, !is.na(roi)) |>
    dplyr::mutate(roi4 = round(roi, 4),
                  s_ord = match(selection, sel_order),
                  k_ord = match(staking, stk_order)) |>
    dplyr::arrange(dplyr::desc(roi4), s_ord, k_ord) |>
    dplyr::slice(1)

  inc_key <- paste("S1", "K0", bet, sep = "|")
  cnd_key <- paste(cand$selection, cand$staking, bet, sep = "|")

  incumbent <- ledgers[[inc_key]]
  challenger <- ledgers[[cnd_key]]

  if (identical(cnd_key, inc_key)) {
    return(tibble::tibble(
      bet = bet, selection = "S1", staking = "K0",
      cand_selection = "S1", cand_staking = "K0",
      cand_roi = cand$roi, incumbent_roi = cand$roi,
      diff_point = 0, se = NA_real_, exceeds_one_se = FALSE,
      n_common = NA_integer_, n_bets = cand$n_bets,
      note = "top candidate is the incumbent"
    ))
  }

  races <- intersect(unique(challenger$race_id), unique(incumbent$race_id))
  bs <- p6_paired_roi_se(p6_units(challenger), p6_units(incumbent), races,
                         n_boot = n_boot, seed = seed)
  take <- !is.na(bs$se) && abs(bs$diff_point) > bs$se && bs$diff_point > 0

  tibble::tibble(
    bet = bet,
    selection = if (take) cand$selection else "S1",
    staking   = if (take) cand$staking   else "K0",
    cand_selection = cand$selection, cand_staking = cand$staking,
    cand_roi = cand$roi,
    incumbent_roi = grid$roi[grid$selection == "S1" & grid$staking == "K0" &
                               grid$bet == bet],
    diff_point = bs$diff_point, se = bs$se,
    exceeds_one_se = take,
    n_common = bs$n_races,
    n_bets = if (take) cand$n_bets else
      grid$n_bets[grid$selection == "S1" & grid$staking == "K0" &
                    grid$bet == bet],
    note = if (take) "declared candidate" else
      "difference within one bootstrap SE — incumbent declared"
  )
}
