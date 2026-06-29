# value_bets_p2b.R
# Paper-2b betting application (Q3): place and each-way value bets, evaluated
# on the SAME real-SP basis as the Q2 win backtest so all three questions sit
# on one footing.
#
# SELECTION (which bets to place) — discounted Harville (alpha 0.80/0.65) value
# ratio on the model vs market win probabilities, swept threshold. UNCHANGED
# from the earlier draft; the bet set and counts do not move.
#
# PAYOUT (what a winning bet returns) — the REAL industry-SP book, with the
# over-round in it, the same raw SP-implied win prices Q2 bets against:
#   * Place: the place price is the Harville (pure, alpha = 1) place
#     probability of the RAW SP-implied win probabilities (1 / SP, NOT
#     renormalised), so it inherits the win book's real margin; payout
#     1 / place_prob.
#   * Each-way: the win leg pays the raw SP win odds (Q2's basis) and the place
#     leg one fifth of those odds on a top-3 finish (standard terms); both legs
#     carry the real SP margin.
# Because the payout now carries the real over-round, the bet-all baseline is
# NEGATIVE (like Q2), and the model's selection ROI is read against that
# realistic baseline. A pure-Harville fair-book payout (zero margin) is kept
# alongside as `ret_fair`, a secondary reference that isolates model skill from
# the margin.
#
# Exacta and trifecta are out of scope for paper 2b: their real price is the
# CSF / computer-straight-forecast dividend (and the Tote pool for the
# trifecta), not a Harville construction, and we do not have those dividends —
# so they are dropped rather than reported on a made-up baseline.
#
# Pure functions, wired into _targets.R. Test split only. Harville place logic
# is reused from R/scoring.R (compute_harville_place_probs) — not duplicated.

#' Assemble the per-runner test tibble for the value bets (paper 2b)
#'
#' Joins finishing positions and the runner's starting price onto the
#' final-model test win probabilities, flags the binary place outcome, and
#' keeps only races with a complete, strictly-positive model **and** market win
#' vector (the Harville recursion needs a full field). The per-bet-type
#' outcome-determinability filter (a clean three-horse place set, a unique
#' winner) is applied in the builders below, not here.
#'
#' @param test_predictions_2b Final-model test predictions: `race_id`,
#'   `runner_id`, `horse_ref`, `won`, `win_model`, `win_market`,
#'   `starting_price_decimal`.
#' @param qualifying_runners Runner-level tibble supplying `finish_position` /
#'   `amended_position`.
#' @return Tibble: `race_id`, `runner_id`, `horse_ref`, `won`, `win_model`,
#'   `win_market`, `starting_price_decimal`, `finish_pos`, `placed`.
build_value_bet_runners <- function(test_predictions_2b, qualifying_runners) {
  fp <- qualifying_runners |>
    dplyr::transmute(
      race_id, runner_id,
      finish_pos = dplyr::coalesce(amended_position, finish_position)
    )

  base <- test_predictions_2b |>
    dplyr::left_join(fp, by = c("race_id", "runner_id")) |>
    dplyr::mutate(placed = as.integer(!is.na(finish_pos) & finish_pos %in% 1:3))

  complete_races <- base |>
    dplyr::group_by(race_id) |>
    dplyr::summarise(
      ok = all(!is.na(win_model)  & win_model  > 0 &
               !is.na(win_market) & win_market > 0 &
               !is.na(starting_price_decimal) & starting_price_decimal > 1),
      .groups = "drop"
    ) |>
    dplyr::filter(ok) |>
    dplyr::pull(race_id)

  base |>
    dplyr::filter(race_id %in% complete_races) |>
    dplyr::select(race_id, runner_id, horse_ref, won,
                  win_model, win_market, starting_price_decimal, finish_pos, placed)
}

#' Place value bets: top-3, real-SP payout (paper 2b)
#'
#' Selection (discounted Harville place ratio) is unchanged; the payout is the
#' real SP book.
#'
#' @param runners Output of `build_value_bet_runners()`.
#' @param alpha_2nd,alpha_3rd Discounted-Harville place exponents (selection).
#' @param prob_floor Model place-probability floor.
#' @return Bet units: `race_id`, `horse_ref`, `model_prob`, `market_prob`,
#'   `ratio`, `stake`, `ret` (real-SP payout), `ret_fair` (fair-book payout).
build_place_value_bets <- function(runners,
                                   alpha_2nd = 0.80, alpha_3rd = 0.65,
                                   prob_floor = 0) {
  clean <- runners |>
    dplyr::group_by(race_id) |>
    dplyr::filter(sum(placed) == 3L) |>
    dplyr::ungroup() |>
    dplyr::mutate(raw_win = 1 / starting_price_decimal)

  # selection probabilities: discounted Harville (unchanged)
  mp <- compute_harville_place_probs(
    clean |> dplyr::transmute(race_id, horse_ref, market_prob = win_model),
    alpha_2nd = alpha_2nd, alpha_3rd = alpha_3rd
  ) |> dplyr::rename(model_place = harville_place_prob)
  kp <- compute_harville_place_probs(
    clean |> dplyr::transmute(race_id, horse_ref, market_prob = win_market),
    alpha_2nd = alpha_2nd, alpha_3rd = alpha_3rd
  ) |> dplyr::rename(market_place = harville_place_prob)

  # payout place probabilities: pure Harville (alpha = 1). Headline = raw SP
  # book (carries the real margin); reference = normalised fair book.
  pr <- compute_harville_place_probs(
    clean |> dplyr::transmute(race_id, horse_ref, market_prob = raw_win),
    alpha_2nd = 1, alpha_3rd = 1
  ) |> dplyr::rename(place_real = harville_place_prob)
  pf <- compute_harville_place_probs(
    clean |> dplyr::transmute(race_id, horse_ref, market_prob = win_market),
    alpha_2nd = 1, alpha_3rd = 1
  ) |> dplyr::rename(place_fair = harville_place_prob)

  clean |>
    dplyr::left_join(mp, by = c("race_id", "horse_ref")) |>
    dplyr::left_join(kp, by = c("race_id", "horse_ref")) |>
    dplyr::left_join(pr, by = c("race_id", "horse_ref")) |>
    dplyr::left_join(pf, by = c("race_id", "horse_ref")) |>
    dplyr::transmute(
      race_id, horse_ref,
      model_prob  = model_place,                 # discounted: selection + floor
      market_prob = market_place,                # discounted: selection
      ratio       = model_place / market_place,  # discounted / discounted (unchanged)
      stake       = 1,
      ret         = (1 / place_real) * placed,   # headline: real SP book
      ret_fair    = (1 / place_fair) * placed    # reference: fair book
    ) |>
    dplyr::filter(model_prob > prob_floor)
}

#' Each-way value bets: win + place at 1/5 terms, real-SP payout (paper 2b)
#'
#' Selection (the discounted-Harville expected-value ratio) is unchanged. The
#' payout win leg pays the raw SP win odds (Q2's basis) and the place leg one
#' fifth of those odds on a top-3 finish; both carry the real margin. The
#' fair-book reference (`ret_fair`) prices both legs off the normalised win
#' probability instead.
#'
#' @param runners Output of `build_value_bet_runners()`.
#' @param alpha_2nd,alpha_3rd Discounted-Harville place exponents (selection).
#' @param place_fraction Each-way place-odds fraction (default 1/5).
#' @param prob_floor Model place-probability floor.
#' @return Bet units: `race_id`, `horse_ref`, `model_prob`, `market_prob`,
#'   `ratio`, `stake` (= 2), `ret` (real-SP), `ret_fair` (fair-book).
build_eachway_value_bets <- function(runners,
                                     alpha_2nd = 0.80, alpha_3rd = 0.65,
                                     place_fraction = 1 / 5,
                                     prob_floor = 0) {
  clean <- runners |>
    dplyr::group_by(race_id) |>
    dplyr::filter(sum(placed) == 3L, sum(won == 1L) == 1L) |>
    dplyr::ungroup()

  mp <- compute_harville_place_probs(
    clean |> dplyr::transmute(race_id, horse_ref, market_prob = win_model),
    alpha_2nd = alpha_2nd, alpha_3rd = alpha_3rd
  ) |> dplyr::rename(model_place = harville_place_prob)
  kp <- compute_harville_place_probs(
    clean |> dplyr::transmute(race_id, horse_ref, market_prob = win_market),
    alpha_2nd = alpha_2nd, alpha_3rd = alpha_3rd
  ) |> dplyr::rename(market_place = harville_place_prob)

  clean |>
    dplyr::left_join(mp, by = c("race_id", "horse_ref")) |>
    dplyr::left_join(kp, by = c("race_id", "horse_ref")) |>
    dplyr::mutate(
      # selection (unchanged): fair win odds + discounted place probs
      win_odds_fair   = 1 / win_market,
      place_odds_fair = 1 + (win_odds_fair - 1) * place_fraction,
      model_ev        = win_model  * win_odds_fair + model_place  * place_odds_fair,
      market_ev       = win_market * win_odds_fair + market_place * place_odds_fair,
      # payout (headline): real SP win odds + 1/5 terms
      win_odds_real   = starting_price_decimal,
      place_odds_real = 1 + (win_odds_real - 1) * place_fraction
    ) |>
    dplyr::transmute(
      race_id, horse_ref,
      model_prob  = model_place,
      market_prob = market_place,
      ratio       = model_ev / market_ev,                               # selection (unchanged)
      stake       = 2,
      ret         = win_odds_real * (won == 1L) + place_odds_real * placed,  # headline: real SP
      ret_fair    = win_odds_fair * (won == 1L) + place_odds_fair * placed   # reference: fair book
    ) |>
    dplyr::filter(model_prob > prob_floor)
}

#' Baselines and over-round for the place / each-way value bets (paper 2b)
#'
#' One row per bet type. `*_real` columns are on the real-SP payout (headline),
#' `*_fair` on the pure-Harville fair-book payout (reference). `betall_roi`,
#' `roi_drop_top1`, `max_payout` are the real-SP basis (kept under those names
#' for the inline prose). `over_round` is the observed average SP win-book
#' over-round across the place universe (sum of 1 / SP per race, averaged) —
#' descriptive, not assumed.
#'
#' @param value_bets_place_2b,value_bets_eachway_2b The two builder outputs.
#' @param value_bet_runners_2b The base per-runner test tibble.
#' @param floors Named model-probability floors matching the backtest targets.
#' @return One row per bet type: `bet_type`, `n_universe`, `n_bet_races`,
#'   `model_real`, `betall_roi`, `model_fair`, `betall_fair`, `roi_drop_top1`,
#'   `max_payout`, `over_round`.
build_value_bet_baselines <- function(value_bets_place_2b, value_bets_eachway_2b,
                                      value_bet_runners_2b,
                                      floors = c(place = 0.10, eachway = 0.10)) {
  roi_on <- function(b, retcol, floor, thr) {
    sel <- dplyr::filter(b, model_prob > floor, ratio > thr)
    if (nrow(sel) == 0L) return(NA_real_)
    (sum(sel[[retcol]]) - sum(sel$stake)) / sum(sel$stake)
  }
  betall <- function(b, retcol) roi_on(b, retcol, -Inf, -Inf)
  naive  <- function(b, retcol, floor) roi_on(b, retcol, floor, 1.3)

  drop1 <- function(b, floor) {
    sel <- dplyr::filter(b, model_prob > floor, ratio > 1.3)
    if (nrow(sel) <= 1L) return(NA_real_)
    s <- sel[-which.max(sel$ret), ]
    (sum(s$ret) - sum(s$stake)) / sum(s$stake)
  }
  max_pay <- function(b, floor) {
    sel <- dplyr::filter(b, model_prob > floor, ratio > 1.3)
    if (nrow(sel) == 0L) return(NA_real_)
    max(sel$ret)
  }

  # observed average SP win-book over-round over the place universe
  over_round <- value_bet_runners_2b |>
    dplyr::group_by(race_id) |>
    dplyr::filter(sum(placed) == 3L) |>
    dplyr::summarise(book = sum(1 / starting_price_decimal), .groups = "drop") |>
    dplyr::pull(book) |>
    mean()

  uni <- value_bet_runners_2b |>
    dplyr::group_by(race_id) |>
    dplyr::summarise(placed3 = sum(placed) == 3L,
                     win1    = sum(won == 1L) == 1L, .groups = "drop")

  tibble::tibble(
    bet_type      = c("place", "eachway"),
    n_universe    = c(sum(uni$placed3), sum(uni$placed3 & uni$win1)),
    n_bet_races   = c(dplyr::n_distinct(value_bets_place_2b$race_id),
                      dplyr::n_distinct(value_bets_eachway_2b$race_id)),
    model_real    = c(naive(value_bets_place_2b,   "ret", floors[["place"]]),
                      naive(value_bets_eachway_2b, "ret", floors[["eachway"]])),
    betall_roi    = c(betall(value_bets_place_2b,   "ret"),
                      betall(value_bets_eachway_2b, "ret")),
    model_fair    = c(naive(value_bets_place_2b,   "ret_fair", floors[["place"]]),
                      naive(value_bets_eachway_2b, "ret_fair", floors[["eachway"]])),
    betall_fair   = c(betall(value_bets_place_2b,   "ret_fair"),
                      betall(value_bets_eachway_2b, "ret_fair")),
    roi_drop_top1 = c(drop1(value_bets_place_2b,   floors[["place"]]),
                      drop1(value_bets_eachway_2b, floors[["eachway"]])),
    max_payout    = c(max_pay(value_bets_place_2b,   floors[["place"]]),
                      max_pay(value_bets_eachway_2b, floors[["eachway"]])),
    over_round    = over_round
  )
}
