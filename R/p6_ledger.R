# p6_ledger.R
# Paper 6 — the betting ledger.
#
# ONE function turns (per-runner model probabilities, starting prices,
# finishing positions, field size) plus a SELECTION rule and a STAKING rule
# into one row per bet. Neither rule is hard-coded: both arrive as arguments,
# which is the whole point of the paper — papers 1 to 5 wired Owen's rule into
# the backtest, so no other rule could be priced on the same footing.
#
# SETTLEMENT IS PAPER 5'S, NOT A RE-DERIVATION. The place and each-way payout
# tables come from `R/value_bets_p2b.R` — `build_value_bet_runners()`,
# `build_place_value_bets()`, `build_eachway_value_bets()` — called unchanged.
# The one thing paper 6 adds is a second each-way payout table under CORRECTED
# place terms (see `p6_eachway_returns()`), and that function is asserted
# against paper 5's own under paper 5's terms rather than trusted.
#
# A NEW FILE, DELIBERATELY: nothing under `R/p5_*.R` is edited (see CLAUDE.md
# on the `p5_gru_module` recompute trap).

# ---------------------------------------------------------------------------
# The per-runner frame every rule reads
# ---------------------------------------------------------------------------

#' Assemble the per-runner betting frame for one split
#'
#' The single input every selection rule sees. Rows are filtered exactly as
#' `compute_model_market_ratio_p2()` filters them — both probabilities present
#' and strictly positive — so a rule reading this frame sees the same rows the
#' series' published backtest saw, and S1 reproduces `select_single_win_bet()`
#' by construction.
#'
#' @param pred A test-predictions-shaped tibble: `race_id`, `runner_id`,
#'   `horse_ref`, `won`, `win_model`, `win_market`, `starting_price_decimal`.
#' @param qualifying_runners The series' runner table, for finishing position.
#' @param race_dates Tibble of `race_id` / `race_date`, for drawdown ordering.
#' @return One row per scorable runner, with `ratio`, `field_size`,
#'   `finish_pos`, `placed`, and the within-race model and price ranks.
p6_build_bet_frame <- function(pred, qualifying_runners, race_dates) {
  fp <- qualifying_runners |>
    dplyr::transmute(
      race_id, runner_id,
      finish_pos = dplyr::coalesce(amended_position, finish_position)
    )

  pred |>
    dplyr::filter(
      !is.na(win_model),  win_model  > 0,
      !is.na(win_market), win_market > 0
    ) |>
    dplyr::left_join(fp, by = c("race_id", "runner_id")) |>
    dplyr::left_join(race_dates, by = "race_id") |>
    dplyr::group_by(race_id) |>
    dplyr::mutate(
      ratio      = win_model / win_market,
      field_size = dplyr::n(),
      mod_rank   = rank(dplyr::desc(win_model), ties.method = "first"),
      sp_rank    = rank(starting_price_decimal, ties.method = "first")
    ) |>
    dplyr::ungroup() |>
    dplyr::mutate(placed = as.integer(!is.na(finish_pos) & finish_pos %in% 1:3))
}

#' The model's top-rated horse in each race
#'
#' Highest `win_model`, ties broken by the lower `runner_id` — the same
#' tie-break `select_single_win_bet()` uses.
#'
#' @param frame Output of `p6_build_bet_frame()`.
#' @return One row per race.
p6_top_rated <- function(frame) {
  frame |>
    dplyr::group_by(race_id) |>
    dplyr::arrange(dplyr::desc(win_model), runner_id, .by_group = TRUE) |>
    dplyr::slice(1) |>
    dplyr::ungroup()
}

# ---------------------------------------------------------------------------
# Settlement
# ---------------------------------------------------------------------------

#' Standard UK place terms for a handicap of a given field size
#'
#' Paper 5 settled every each-way bet at one fifth the odds on a top-three
#' finish, whatever the field. The real industry terms for a handicap are a
#' ladder in field size. Paper 6's Section 2 reports the share of races where
#' the two disagree; where they do, both are reported side by side.
#'
#' @param field_size Integer vector of runners per race.
#' @return A tibble with `n_places` (0 = win-only) and `place_fraction`.
p6_place_terms <- function(field_size) {
  tibble::tibble(
    n_places = dplyr::case_when(
      field_size <= 4L  ~ 0L,
      field_size <= 7L  ~ 2L,
      field_size <= 11L ~ 3L,
      field_size <= 15L ~ 3L,
      TRUE              ~ 4L
    ),
    place_fraction = dplyr::case_when(
      field_size <= 4L  ~ NA_real_,
      field_size <= 7L  ~ 1 / 4,
      field_size <= 11L ~ 1 / 5,
      field_size <= 15L ~ 1 / 4,
      TRUE              ~ 1 / 4
    )
  )
}

#' Each-way returns per unit of the win-leg stake
#'
#' Generalises `build_eachway_value_bets()`'s payout arithmetic over the number
#' of places and the odds fraction, so the corrected terms and paper 5's flat
#' 1/5-top-3 terms run through one function. With `terms = "paper5"` the output
#' is asserted equal to `build_eachway_value_bets()`'s in
#' `scripts/verify_p6_ledger.R`; nothing about the payout is re-derived by
#' guesswork.
#'
#' A win-only race (field size 4 under the corrected terms) stakes the win leg
#' alone: `stake_mult` is 1 rather than 2 and the place leg pays nothing.
#'
#' @param frame Output of `p6_build_bet_frame()`.
#' @param terms `"paper5"` (1/5 odds, top 3, every field) or `"corrected"`
#'   (the industry handicap ladder in `p6_place_terms()`).
#' @return `race_id`, `horse_ref`, `stake_mult`, `ret_unit`, `ret_unit_fair`.
p6_eachway_returns <- function(frame, terms = c("paper5", "corrected")) {
  terms <- match.arg(terms)

  t <- if (terms == "paper5") {
    tibble::tibble(n_places = rep(3L, nrow(frame)),
                   place_fraction = rep(1 / 5, nrow(frame)))
  } else {
    p6_place_terms(frame$field_size)
  }

  frame |>
    dplyr::mutate(
      n_places       = t$n_places,
      place_fraction = t$place_fraction,
      in_places      = as.integer(!is.na(finish_pos) & finish_pos <= n_places),
      win_odds_real  = starting_price_decimal,
      win_odds_fair  = 1 / win_market,
      pl_odds_real   = 1 + (win_odds_real - 1) * place_fraction,
      pl_odds_fair   = 1 + (win_odds_fair - 1) * place_fraction
    ) |>
    dplyr::transmute(
      race_id, horse_ref,
      stake_mult = dplyr::if_else(n_places == 0L, 1, 2),
      ret_unit = win_odds_real * (won == 1L) +
        dplyr::if_else(n_places == 0L, 0, pl_odds_real * in_places),
      ret_unit_fair = win_odds_fair * (won == 1L) +
        dplyr::if_else(n_places == 0L, 0, pl_odds_fair * in_places)
    )
}

#' Build every settlement table for one split
#'
#' Four tables, each giving the return per `stake_mult` units staked at the
#' real starting price and at a zero-margin fair book:
#'   `win`               settled directly at SP.
#'   `place`             paper 5's Harville-priced place market, from
#'                       `build_place_value_bets()` unchanged.
#'   `eachway`           paper 5's terms, from `build_eachway_value_bets()`
#'                       unchanged.
#'   `eachway_corrected` the industry handicap ladder, `p6_eachway_returns()`.
#'
#' The place and each-way universes are paper 5's own: `build_value_bet_runners()`
#' drops races without a complete price vector and the builders drop races
#' without a clean three-horse place set. A bet in a dropped race is dropped —
#' the same inner join `single_bet_units()` performs.
#'
#' @param frame Output of `p6_build_bet_frame()`.
#' @param pred The predictions tibble `frame` was built from.
#' @param qualifying_runners The series' runner table.
#' @return A named list of settlement tables.
p6_settlement_tables <- function(frame, pred, qualifying_runners) {
  vbr <- build_value_bet_runners(pred, qualifying_runners)

  win <- frame |>
    dplyr::transmute(
      race_id, horse_ref, stake_mult = 1,
      ret_unit      = starting_price_decimal * (won == 1L),
      ret_unit_fair = (1 / win_market) * (won == 1L)
    )

  place <- build_place_value_bets(vbr) |>
    dplyr::transmute(race_id, horse_ref, stake_mult = stake,
                     ret_unit = ret, ret_unit_fair = ret_fair)

  eachway <- build_eachway_value_bets(vbr) |>
    dplyr::transmute(race_id, horse_ref, stake_mult = stake,
                     ret_unit = ret, ret_unit_fair = ret_fair)

  # The corrected table inherits the each-way universe, so the two each-way
  # columns are priced on the identical bets and differ only in the terms.
  ew_universe <- eachway |> dplyr::select(race_id, horse_ref)
  eachway_corrected <- p6_eachway_returns(frame, "corrected") |>
    dplyr::inner_join(ew_universe, by = c("race_id", "horse_ref"))

  list(win = win, place = place, eachway = eachway,
       eachway_corrected = eachway_corrected)
}

# ---------------------------------------------------------------------------
# The ledger
# ---------------------------------------------------------------------------

#' One row per bet
#'
#' @param frame Output of `p6_build_bet_frame()`.
#' @param settle Output of `p6_settlement_tables()`.
#' @param selection A function of `frame` returning at most one row per race,
#'   carrying `frame`'s columns.
#' @param staking A function of the selected rows returning the per-leg stake
#'   in units, one element per row.
#' @param bet One of `names(settle)`.
#' @return Tibble: `race_id`, `runner_id`, `race_date`, `bet`, `stake`, `ret`,
#'   `ret_fair`, `profit`.
p6_ledger <- function(frame, settle, selection, staking, bet) {
  stopifnot(bet %in% names(settle))

  sel <- selection(frame)
  stopifnot(!anyDuplicated(sel$race_id))
  if (nrow(sel) == 0L) {
    return(tibble::tibble(race_id = integer(), runner_id = integer(),
                          race_date = as.Date(character()), bet = character(),
                          stake = numeric(), ret = numeric(),
                          ret_fair = numeric(), profit = numeric()))
  }

  sel |>
    dplyr::mutate(unit_stake = staking(sel)) |>
    dplyr::inner_join(settle[[bet]], by = c("race_id", "horse_ref")) |>
    dplyr::transmute(
      race_id, runner_id, race_date, bet = bet,
      stake    = unit_stake * stake_mult,
      ret      = unit_stake * ret_unit,
      ret_fair = unit_stake * ret_unit_fair,
      profit   = ret - stake
    ) |>
    dplyr::arrange(race_date, race_id)
}

#' Summarise a ledger
#'
#' `roi_drop_top1` removes the single largest return, as the series' own
#' `summarise_single_bets()` does. `sd_unit_return` is the standard deviation
#' of profit per unit staked across bets — the dispersion a staking rule is
#' meant to change. `max_drawdown` is the largest peak-to-trough fall in
#' cumulative profit, in stake units, over the ledger in race-date order.
#'
#' @param led Output of `p6_ledger()`.
#' @return A one-row tibble.
p6_summarise_ledger <- function(led) {
  led <- dplyr::filter(led, stake > 0)
  n   <- nrow(led)
  if (n == 0L) {
    return(tibble::tibble(n_bets = 0L, n_wins = 0L, total_stake = 0,
                          gross_return = 0, profit = 0, roi = NA_real_,
                          roi_fair = NA_real_, roi_drop_top1 = NA_real_,
                          mean_stake = NA_real_, sd_unit_return = NA_real_,
                          max_drawdown = NA_real_))
  }
  ts    <- sum(led$stake)
  gross <- sum(led$ret)
  cum   <- cumsum(led$profit)
  drop1 <- if (n <= 1L) NA_real_ else {
    keep <- dplyr::slice(led, -which.max(led$ret))
    (sum(keep$ret) - sum(keep$stake)) / sum(keep$stake)
  }
  tibble::tibble(
    n_bets         = as.integer(n),
    n_wins         = as.integer(sum(led$ret > 0)),
    total_stake    = ts,
    gross_return   = gross,
    profit         = gross - ts,
    roi            = (gross - ts) / ts,
    roi_fair       = (sum(led$ret_fair) - ts) / ts,
    roi_drop_top1  = drop1,
    mean_stake     = mean(led$stake),
    sd_unit_return = stats::sd(led$profit / led$stake),
    max_drawdown   = max(cummax(c(0, cum)) - c(0, cum))
  )
}

#' Per-race stake / return units, for the bootstrap
#'
#' `p5_bootstrap_single_bet_roi()` consumes `race_id` / `stake` / `ret`. This
#' puts a paper-6 ledger into that shape, optionally on the fair-book returns.
#'
#' @param led Output of `p6_ledger()`.
#' @param basis `"real"` (starting price) or `"fair"` (zero-margin book).
#' @return Tibble: `race_id`, `stake`, `ret`.
p6_units <- function(led, basis = c("real", "fair")) {
  basis <- match.arg(basis)
  led |>
    dplyr::transmute(race_id, stake,
                     ret = if (basis == "real") ret else ret_fair)
}

#' Marginal race-level bootstrap interval on one arm's ROI
#'
#' The single-arm counterpart of `p5_bootstrap_single_bet_roi()`, resampling
#' races rather than bets so a race that carries no bet can be drawn and
#' contribute zero — the same universe convention the paired version uses.
#'
#' @param led Output of `p6_ledger()`.
#' @param races The race universe to resample.
#' @param n_boot,seed Replicates and RNG seed.
#' @return A one-row tibble: `roi`, `ci_lo`, `ci_hi`, `n_races`, `n_boot`.
p6_bootstrap_roi <- function(led, races, n_boot = 2000L, seed = 42L) {
  agg <- p6_units(led) |>
    dplyr::filter(race_id %in% races) |>
    dplyr::group_by(race_id) |>
    dplyr::summarise(stake = sum(stake), ret = sum(ret), .groups = "drop")
  d <- tibble::tibble(race_id = races) |>
    dplyr::left_join(agg, by = "race_id") |>
    dplyr::mutate(stake = dplyr::coalesce(stake, 0),
                  ret   = dplyr::coalesce(ret, 0))

  roi <- function(st, rt) if (sum(st) == 0) NA_real_ else (sum(rt) - sum(st)) / sum(st)
  n <- nrow(d)
  set.seed(seed)
  reps <- vapply(seq_len(n_boot), function(i) {
    idx <- sample.int(n, n, replace = TRUE)
    roi(d$stake[idx], d$ret[idx])
  }, numeric(1))

  tibble::tibble(
    roi     = roi(d$stake, d$ret),
    ci_lo   = stats::quantile(reps, 0.05, na.rm = TRUE, names = FALSE),
    ci_hi   = stats::quantile(reps, 0.95, na.rm = TRUE, names = FALSE),
    n_races = n,
    n_boot  = n_boot
  )
}

#' Bootstrap standard error of a paired ROI difference
#'
#' The declaration rule in `DECLARED_RULES.md` compares a point difference
#' against one bootstrap standard error of that difference, so the SE is
#' returned alongside the interval rather than read off it.
#'
#' @param units_a,units_b Per-race unit tibbles (`p6_units()` output).
#' @param races Common race universe.
#' @param n_boot,seed Replicates and RNG seed.
#' @return A one-row tibble: `diff_point`, `se`, `ci_lo`, `ci_hi`, `n_races`.
p6_paired_roi_se <- function(units_a, units_b, races, n_boot = 2000L,
                             seed = 42L) {
  fill <- function(u) {
    agg <- u |>
      dplyr::filter(race_id %in% races) |>
      dplyr::group_by(race_id) |>
      dplyr::summarise(stake = sum(stake), ret = sum(ret), .groups = "drop")
    tibble::tibble(race_id = races) |>
      dplyr::left_join(agg, by = "race_id") |>
      dplyr::mutate(stake = dplyr::coalesce(stake, 0),
                    ret   = dplyr::coalesce(ret, 0))
  }
  a <- fill(units_a); b <- fill(units_b)
  roi <- function(st, rt) if (sum(st) == 0) NA_real_ else (sum(rt) - sum(st)) / sum(st)
  n <- length(races)

  set.seed(seed)
  diffs <- vapply(seq_len(n_boot), function(i) {
    idx <- sample.int(n, n, replace = TRUE)
    roi(a$stake[idx], a$ret[idx]) - roi(b$stake[idx], b$ret[idx])
  }, numeric(1))

  tibble::tibble(
    diff_point = roi(a$stake, a$ret) - roi(b$stake, b$ret),
    se         = stats::sd(diffs, na.rm = TRUE),
    ci_lo      = stats::quantile(diffs, 0.05, na.rm = TRUE, names = FALSE),
    ci_hi      = stats::quantile(diffs, 0.95, na.rm = TRUE, names = FALSE),
    n_races    = n
  )
}
