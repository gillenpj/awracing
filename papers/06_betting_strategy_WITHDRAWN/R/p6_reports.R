# p6_reports.R
# Paper 6 — the stage-0 descriptive reports.
#
# What the search set looks like before any rule is searched on it: what
# prices exist and when, what margin the book carries at each field size, how
# many races are small enough that paper 5's flat each-way terms are wrong,
# where the incumbent rule's absolute thresholds sit in the validation-slice
# distribution and in the test split's, and what the incumbent itself returns
# on the search set at the real price and at a zero-margin book.
#
# Descriptive only. Nothing here selects anything.

#' Price coverage by year, runner-row and race level
#'
#' The starting price is in the results archive for every runner the series
#' uses; the pre-race racecard forecast lives in `daily_runners` and, per paper
#' 4's Appendix A, does not exist before March 2008 and is patchy for about a
#' year after. "Pre-race" means the daily-feed row was written strictly before
#' the meeting date — paper 4's `ok_A`, reused rather than re-derived.
#'
#' @param key A `race_id` / `runner_id` tibble for the split.
#' @param race_dates Tibble of `race_id` / `race_date`.
#' @param raw_prices Output of `read_p4_price_sources()` on the same races.
#' @return A tibble, one row per year, with runner-row and race-level coverage.
p6_price_coverage <- function(key, race_dates, raw_prices) {
  d <- key |>
    dplyr::left_join(race_dates, by = "race_id") |>
    dplyr::left_join(raw_prices, by = c("race_id", "runner_id")) |>
    dplyr::mutate(
      year = lubridate::year(race_date),
      ok_sp = !is.na(sp) & sp > 1,
      ok_fp = !is.na(fp_feed) & fp_feed > 1 &
        !is.na(feed_lag_days) & feed_lag_days < 0
    )

  rows <- d |>
    dplyr::group_by(year) |>
    dplyr::summarise(n_rows = dplyr::n(),
                     rows_sp = sum(ok_sp), rows_fp = sum(ok_fp),
                     .groups = "drop")

  races <- d |>
    dplyr::group_by(year, race_id) |>
    dplyr::summarise(all_sp = all(ok_sp), all_fp = all(ok_fp), .groups = "drop") |>
    dplyr::group_by(year) |>
    dplyr::summarise(n_races = dplyr::n(),
                     races_sp = sum(all_sp), races_fp = sum(all_fp),
                     .groups = "drop")

  rows |>
    dplyr::left_join(races, by = "year") |>
    dplyr::mutate(
      pct_rows_sp  = rows_sp / n_rows,
      pct_rows_fp  = rows_fp / n_rows,
      pct_races_sp = races_sp / n_races,
      pct_races_fp = races_fp / n_races
    ) |>
    dplyr::select(year, n_rows, n_races, rows_sp, pct_rows_sp, races_sp,
                  pct_races_sp, rows_fp, pct_rows_fp, races_fp, pct_races_fp)
}

#' Over-round by field size
#'
#' The raw starting-price book summed within race, averaged over races of each
#' field size. This is the margin a flat SP bettor pays before any skill; the
#' fair-book columns elsewhere in the paper are what remains when it is
#' removed.
#'
#' @param frame Output of `p6_build_bet_frame()`.
#' @return A tibble, one row per field size.
p6_overround_by_field <- function(frame) {
  frame |>
    dplyr::group_by(race_id, field_size) |>
    dplyr::summarise(book = sum(1 / starting_price_decimal), .groups = "drop") |>
    dplyr::group_by(field_size) |>
    dplyr::summarise(
      n_races = dplyr::n(),
      mean_book = mean(book),
      median_book = stats::median(book),
      mean_margin_pct = 100 * (mean(book) - 1) / mean(book),
      .groups = "drop"
    )
}

#' Field-size distribution, and the share paper 5's each-way terms misprice
#'
#' Paper 5 settles every each-way bet at one fifth the odds on a top-three
#' finish. The real handicap terms are a ladder (`p6_place_terms()`): win-only
#' at four runners, a quarter the odds on the first two at five to seven, and
#' a quarter rather than a fifth on the first three from twelve. `share_wrong`
#' is the share of races where paper 5's terms differ from the real ones in
#' either the number of places or the fraction.
#'
#' @param frame Output of `p6_build_bet_frame()`.
#' @return A list: the per-field-size table, and the summary shares.
p6_field_size_report <- function(frame) {
  races <- frame |>
    dplyr::distinct(race_id, field_size)

  counts <- dplyr::count(races, field_size, name = "n_races")

  tbl <- counts |>
    dplyr::bind_cols(p6_place_terms(counts$field_size)) |>
    dplyr::mutate(
      p5_matches = n_places == 3L & !is.na(place_fraction) &
        abs(place_fraction - 1 / 5) < 1e-12,
      share = n_races / sum(n_races)
    )

  list(
    by_field_size = tbl,
    n_races = nrow(races),
    share_4_to_7 = mean(races$field_size <= 7L),
    share_wrong = sum(tbl$n_races[!tbl$p5_matches]) / sum(tbl$n_races)
  )
}

#' Deciles of the two filtered quantities on both splits, side by side
#'
#' The search set and the test split are scored by different fits of the same
#' architecture, on different amounts of data, so their score distributions
#' differ in scale. This is the evidence for that claim, and the reason every
#' candidate threshold in the paper is a within-split quantile rather than an
#' absolute number.
#'
#' @param val_frame,test_frame The two `p6_build_bet_frame()` outputs.
#' @return A list: `deciles` (long, both splits), `s1_position` (where Owen's
#'   absolute cuts fall on each split), and `summary` (medians and pass rates).
p6_threshold_position_both <- function(val_frame, test_frame) {
  probs <- seq(0.1, 0.9, by = 0.1)

  one_dec <- function(frame, split) {
    top <- p6_top_rated(frame)
    tibble::tibble(
      split = split, decile = probs,
      p_mod = stats::quantile(top$win_model, probs, names = FALSE),
      ratio = stats::quantile(top$ratio, probs, names = FALSE)
    )
  }
  one_pos <- function(frame, split) {
    top <- p6_top_rated(frame)
    tibble::tibble(
      split = split,
      quantity = c("P_mod", "P_mod / P_mkt"),
      s1_threshold = c(0.15, 1.3),
      quantile_of_top_rated = c(mean(top$win_model <= 0.15),
                                mean(top$ratio <= 1.3)),
      share_passing = c(mean(top$win_model > 0.15), mean(top$ratio > 1.3))
    )
  }
  one_sum <- function(frame, split) {
    top <- p6_top_rated(frame)
    tibble::tibble(
      split = split, n_races = nrow(top),
      median_p_mod = stats::median(top$win_model),
      median_ratio = stats::median(top$ratio),
      median_sp = stats::median(top$starting_price_decimal),
      share_positive_kelly_edge =
        mean(top$win_model > 1 / top$starting_price_decimal)
    )
  }

  list(
    deciles = dplyr::bind_rows(one_dec(val_frame, "validation"),
                               one_dec(test_frame, "test")),
    s1_position = dplyr::bind_rows(one_pos(val_frame, "validation"),
                                   one_pos(test_frame, "test")),
    summary = dplyr::bind_rows(one_sum(val_frame, "validation"),
                               one_sum(test_frame, "test"))
  )
}
