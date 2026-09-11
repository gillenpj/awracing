# p6m_metrics.R
# Paper 6 — "What the metrics can and cannot tell us".
#
# Section 1: what ROI can and cannot establish about one model against the
# next. Two demonstrations, both on stored predictions with nothing refitted.
#
#   1a  The published record. Four paired race-level bootstraps of the
#       difference in single-bet win ROI between consecutive models.
#   1b  One model, one rule, three sets of races.
#
# WHY THE CONTRASTS ARE RECOMPUTED HERE. The series has published four such
# contrasts, and they do not share a bet rule: the 2b-2a and 3-2b bootstraps
# were computed on the bet-every-qualifier rule, while paper 5's two were
# computed on the single-bet rule. Their point differences move by about three
# points between the two rules, so the four cannot be read as a sequence as
# they stand. This file recomputes all four on the single-bet rule using the
# series' own paired bootstrap, `p5_bootstrap_single_bet_roi()`, so one basis
# and one bootstrap implementation runs through the whole table. The published
# figures are reported alongside, unchanged, so the difference is visible.
#
# Paper 1 has no single-bet win backtest: it published only the
# bet-every-qualifier rule. It is therefore absent from the single-bet series
# rather than converted, and `p6m_single_bet_series()` records that.

# ---------------------------------------------------------------------------
# Row and race identity
# ---------------------------------------------------------------------------

#' Assert the model frames this paper reads share a race universe
#'
#' Paper 5 asserts row identity against paper 3's frame before computing
#' anything; this does the same one level up. Every metric in Sections 1 and 2
#' is a paired comparison across models, so a silent difference in which races
#' each model covers would move every contrast.
#'
#' @param frames A named list of tibbles carrying `race_id`.
#' @param expect_common Expected number of common races, or `NULL`.
#' @return A tibble, one row per frame, plus the common-race count.
p6m_assert_race_identity <- function(frames, expect_common = NULL) {
  ids <- purrr::map(frames, ~ sort(unique(.x$race_id)))
  common <- Reduce(intersect, ids)

  out <- tibble::tibble(
    frame = names(frames),
    n_races = purrr::map_int(ids, length),
    n_rows = purrr::map_int(frames, nrow),
    n_common = length(common),
    n_outside_common = purrr::map_int(ids, ~ length(setdiff(.x, common)))
  )

  stopifnot(length(common) > 0L)
  if (!is.null(expect_common)) stopifnot(length(common) == expect_common)
  out
}

# ---------------------------------------------------------------------------
# Section 1a — the published record, and the same contrasts on one basis
# ---------------------------------------------------------------------------

#' Single-bet win ROI for one model, from a ratio tibble
#'
#' Owen's naive rule at the series-standard thresholds, one bet per race on
#' the highest model probability among the qualifiers, settled at the real
#' starting price. `single_bet_units()` and `summarise_single_bets()` are the
#' series' own helpers, used unchanged.
#'
#' @param ratio_df A `compute_model_market_ratio()`-shaped tibble.
#' @param label The model's label for the output row.
#' @return A one-row tibble.
p6m_single_bet_roi <- function(ratio_df, label) {
  units <- single_bet_units(ratio_df)
  dplyr::mutate(summarise_single_bets(units), model = label, .before = 1)
}

#' The single-bet win ROI series across the papers that have one
#'
#' @param ratios A named list of ratio tibbles, in series order.
#' @param p5_units Paper 5's stored per-race win units for the encoder.
#' @return A tibble, one row per model.
p6m_single_bet_series <- function(ratios, p5_units) {
  from_ratios <- purrr::imap(ratios, function(r, nm) p6m_single_bet_roi(r, nm)) |>
    purrr::list_rbind()
  dplyr::bind_rows(
    from_ratios,
    dplyr::mutate(summarise_single_bets(p5_units), model = "5", .before = 1)
  )
}

#' One paired single-bet ROI contrast between two models
#'
#' Wraps the series' own paired race-level bootstrap so every contrast in this
#' paper shares one implementation with paper 5's published pair.
#'
#' THE RACE UNIVERSE IS EVERY RACE BOTH MODELS COULD HAVE BET, not every race
#' both did bet. Owen's rule declines most races, and the two models decline
#' different ones, so conditioning on both having bet would drop about half
#' the universe and change both arms' ROIs. Filling with zeros over the full
#' common universe is what paper 5's published contrasts do, and it is the
#' only treatment under which the recomputed rows are comparable to them.
#'
#' @param units_a,units_b Per-race unit tibbles (`race_id`, `stake`, `ret`).
#' @param races The common race universe.
#' @param label The contrast label.
#' @param n_boot,seed Replicates and RNG seed.
#' @return A one-row tibble.
p6m_roi_contrast <- function(units_a, units_b, races, label, n_boot = 2000L,
                             seed = 42L) {
  p5_bootstrap_single_bet_roi(units_a, units_b, sort(races), label, "win",
                              n_boot = n_boot, seed = seed)
}

#' Every Section 1a contrast, on the single-bet rule
#'
#' @param units A named list of per-race unit tibbles, one per model.
#' @param universes A named list of each model's full race universe.
#' @param n_boot,seed Replicates and RNG seed.
#' @return A tibble, one row per contrast, in series order.
p6m_roi_contrasts <- function(units, universes, n_boot = 2000L, seed = 42L) {
  spec <- tibble::tribble(
    ~label,              ~a,       ~b,
    "2b - 2a",           "2b",     "2a",
    "3 - 2b",            "3",      "2b",
    "5 - 3",             "5",      "3",
    "5 - hand-built",    "5",      "hand_built"
  )
  purrr::pmap(spec, function(label, a, b)
    p6m_roi_contrast(units[[a]], units[[b]],
                     intersect(universes[[a]], universes[[b]]),
                     label, n_boot, seed)) |>
    purrr::list_rbind() |>
    dplyr::mutate(excludes_zero = ci_lo > 0 | ci_hi < 0)
}

#' Assert the recomputation reproduces paper 5's two published contrasts
#'
#' A blocker. The 5-3 and 5-hand-built rows exist in both the published table
#' and the recomputed one, because paper 5 already used the single-bet rule.
#' They must agree exactly. If they do, the two recomputed pre-paper-5 rows
#' were produced by the same procedure as the published pair and the four can
#' be read as one sequence; if they do not, they cannot.
#'
#' @param recomputed Output of `p6m_roi_contrasts()`.
#' @param published Output of `p6m_published_contrasts()`.
#' @param tol Absolute tolerance.
#' @return A tibble of the two overlapping rows and their differences.
p6m_assert_recompute_matches <- function(recomputed, published, tol = 1e-12) {
  chk <- recomputed |>
    dplyr::filter(contrast %in% c("5 - 3", "5 - hand-built")) |>
    dplyr::select(contrast, new_diff = diff_point, new_lo = ci_lo,
                  new_hi = ci_hi, new_races = n_races) |>
    dplyr::left_join(
      published |>
        dplyr::select(contrast = label, pub_diff = diff_point,
                      pub_lo = ci_lo, pub_hi = ci_hi, pub_races = n_races),
      by = "contrast"
    ) |>
    dplyr::mutate(d_diff = abs(new_diff - pub_diff),
                  d_lo = abs(new_lo - pub_lo), d_hi = abs(new_hi - pub_hi))

  stopifnot(
    nrow(chk) == 2L,
    all(chk$new_races == chk$pub_races),
    max(chk$d_diff) < tol, max(chk$d_lo) < tol, max(chk$d_hi) < tol
  )
  chk
}

#' The published contrasts, read from the stores unchanged
#'
#' Reported beside the recomputed table so the change of basis is visible
#' rather than absorbed. `basis` records which bet rule each published figure
#' was computed on; both facts were confirmed by matching each stored
#' `diff_point` against the underlying backtests.
#'
#' @param roi_2b_vs_2a,roi_3_vs_2b The main store's published bootstraps.
#' @param p5_contrasts Paper 5's published contrast table.
#' @return A tibble, one row per contrast.
p6m_published_contrasts <- function(roi_2b_vs_2a, roi_3_vs_2b, p5_contrasts) {
  p5w <- p5_contrasts |> dplyr::filter(bet == "win")
  enc_v_gbt <- p5w |>
    dplyr::filter(contrast == "rung 3b (encoder) - paper 3 (GBT)")
  enc_v_mlp <- p5w |>
    dplyr::filter(contrast == "rung 3b (encoder) - rung 1 (summaries)")
  stopifnot(nrow(enc_v_gbt) == 1L, nrow(enc_v_mlp) == 1L)

  tibble::tibble(
    label = c("2b - 2a", "3 - 2b", "5 - 3", "5 - hand-built"),
    basis = c("bet every qualifier", "bet every qualifier",
              "single bet per race", "single bet per race"),
    diff_point = c(roi_2b_vs_2a$diff_point, roi_3_vs_2b$diff_point,
                   enc_v_gbt$diff_point, enc_v_mlp$diff_point),
    ci_lo = c(roi_2b_vs_2a$ci_lo, roi_3_vs_2b$ci_lo,
              enc_v_gbt$ci_lo, enc_v_mlp$ci_lo),
    ci_hi = c(roi_2b_vs_2a$ci_hi, roi_3_vs_2b$ci_hi,
              enc_v_gbt$ci_hi, enc_v_mlp$ci_hi),
    n_races = c(roi_2b_vs_2a$n_common, roi_3_vs_2b$n_common,
                enc_v_gbt$n_races, enc_v_mlp$n_races)
  ) |>
    dplyr::mutate(excludes_zero = ci_lo > 0 | ci_hi < 0)
}

#' Assert the published multi-bet contrasts are what they are claimed to be
#'
#' A blocker, not a report. Each published `diff_point` is matched against the
#' difference of the two underlying backtests on both bet rules, so the
#' `basis` column in `p6m_published_contrasts()` is asserted rather than
#' asserted-by-comment.
#'
#' @param roi_2b_vs_2a,roi_3_vs_2b The published bootstraps.
#' @param naive,single Named lists of the naive and single-bet backtest rows.
#' @return A tibble recording each match.
p6m_assert_published_basis <- function(roi_2b_vs_2a, roi_3_vs_2b,
                                       naive, single) {
  chk <- tibble::tibble(
    label = c("2b - 2a", "3 - 2b"),
    published = c(roi_2b_vs_2a$diff_point, roi_3_vs_2b$diff_point),
    multi_bet = c(naive$roi_2b - naive$roi_2a, naive$roi_3 - naive$roi_2b_r),
    single_bet = c(single$roi_2b - single$roi_2a,
                   single$roi_3 - single$roi_2b_r)
  ) |>
    dplyr::mutate(
      d_multi = abs(published - multi_bet),
      d_single = abs(published - single_bet),
      basis = dplyr::if_else(d_multi < 1e-8, "bet every qualifier",
                             dplyr::if_else(d_single < 1e-8,
                                            "single bet per race", "neither"))
    )
  stopifnot(all(chk$basis == "bet every qualifier"))
  chk
}

# ---------------------------------------------------------------------------
# Section 1b — one model, one rule, three sets of races
# ---------------------------------------------------------------------------

#' Single-bet win ROI on the paper-5 validation slice and its two halves
#'
#' The validation slice is the 1,505 races carved out of the training split at
#' 2010-12-15 for paper 5's model selection. It is split chronologically here
#' only to show how far the number moves between two sets of races the same
#' model and the same rule are applied to.
#'
#' The slice is scored by the encoder's fitting-partition fit and the test
#' split by the full-training-split refit: two fits of one architecture.
#'
#' @param scored Paper 5's `p5_scored_v7` (encoder, validation slice).
#' @param race_dates Race dates for the chronological split.
#' @param cut The split date.
#' @return A tibble, one row per race set.
p6m_validation_halves <- function(scored, race_dates,
                                  cut = as.Date("2012-01-15")) {
  frame <- scored |>
    dplyr::select(race_id, runner_id, horse_ref, won, win_model, win_market,
                  starting_price_decimal) |>
    dplyr::filter(!is.na(win_model), win_model > 0,
                  !is.na(win_market), win_market > 0) |>
    dplyr::left_join(race_dates, by = "race_id") |>
    dplyr::rename(model_prob = win_model, market_prob = win_market) |>
    dplyr::mutate(ratio = model_prob / market_prob)

  stopifnot(!anyNA(frame$race_date))

  one <- function(d, label) {
    dplyr::mutate(
      summarise_single_bets(single_bet_units(d)),
      race_set = label, n_races = dplyr::n_distinct(d$race_id), .before = 1
    )
  }

  dplyr::bind_rows(
    one(frame, "validation slice, all"),
    one(dplyr::filter(frame, race_date <= cut), "validation slice, first half"),
    one(dplyr::filter(frame, race_date > cut), "validation slice, second half")
  ) |>
    dplyr::mutate(cut_date = as.character(cut))
}

#' The three race sets of Section 1b, one table
#'
#' @param halves Output of `p6m_validation_halves()`.
#' @param p5_backtests Paper 5's published test backtests.
#' @param arm The paper-5 arm to read (the published encoder).
#' @return A tibble, one row per race set.
p6m_three_race_sets <- function(halves, p5_backtests, arm = "rung3b") {
  test <- p5_backtests |>
    dplyr::filter(arm == !!arm, bet == "win")
  stopifnot(nrow(test) == 1L)

  dplyr::bind_rows(
    halves |>
      dplyr::filter(race_set != "validation slice, all") |>
      dplyr::transmute(race_set, fit = "fitting partition", n_races,
                       n_bets, n_wins, roi),
    tibble::tibble(race_set = "test split", fit = "full training split",
                   n_races = NA_integer_, n_bets = as.integer(test$n_bets),
                   n_wins = as.integer(test$n_wins), roi = test$roi)
  )
}

# ---------------------------------------------------------------------------
# The ranking measures that do resolve
# ---------------------------------------------------------------------------
