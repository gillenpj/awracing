# p4_data_summaries.R
#
# Paper 4 — the data-section summaries.
#
# These recompute, as `{targets}` in the paper-4 store, the descriptive
# findings that `scripts/p4_audit_forecast_price.R` established as the
# P4-0 gate. The duplication is deliberate and the two are kept honest
# against each other by `scripts/verify_p4_data_targets.R`:
#
#   * the audit script is the standalone record of the P4-0 gate, run
#     once and reported as a fixed artefact, and
#   * these targets are what the paper's prose reads, so that every
#     number in the paper is live rather than transcribed.
#
# Everything distributional here is TRAINING SPLIT ONLY, per the series'
# standing convention. Coverage is reported on both splits because the
# question "is this column usable where we intend to use it" is about
# the test universe.

#' Build the runner-level price panel over the whole in-scope window
#'
#' The paper-4 modelling panel covers only the test universe. The data
#' section needs the full 2006-2015 window — coverage by year, and the
#' training-split distributional work — so this assembles the same three
#' price columns over every qualifying runner.
#'
#' @param qualifying_runners,qualifying_races,races_train The frozen
#'   pipeline targets.
#' @param raw_all Output of `read_p4_price_sources()` over every
#'   qualifying race.
#' @return A runner-level tibble with prices, usability flags, split and
#'   year.
build_p4_full_panel <- function(qualifying_runners, qualifying_races,
                                races_train, raw_all) {
  qualifying_runners |>
    dplyr::select(race_id, runner_id, won) |>
    dplyr::left_join(
      raw_all |> dplyr::select(race_id, runner_id, fp_feed, feed_lag_days,
                               fp_arch, sp),
      by = c("race_id", "runner_id")
    ) |>
    dplyr::left_join(qualifying_races |> dplyr::select(race_id, meeting_date),
                     by = "race_id") |>
    dplyr::mutate(
      year  = as.integer(format(meeting_date, "%Y")),
      split = dplyr::if_else(race_id %in% races_train$race_id, "train", "test"),
      ok_A  = !is.na(fp_feed) & fp_feed > 1 &
              !is.na(feed_lag_days) & feed_lag_days < 0,
      ok_B  = !is.na(sp)      & sp      > 1,
      ok_C  = !is.na(fp_arch) & fp_arch > 1
    )
}

#' Coverage of each price column, by year and by split
#'
#' "Usable" is non-NA and strictly greater than 1: a decimal price of 1
#' or below implies a probability of 1 or more and cannot be normalised.
#' The pre-race feed column additionally requires its feed row to have
#' been written before the meeting date.
#'
#' @param panel Output of `build_p4_full_panel()`.
#' @return A list of two tibbles, `by_year` and `by_split`.
summarise_p4_coverage <- function(panel) {
  by_year <- panel |>
    dplyr::group_by(year) |>
    dplyr::summarise(
      races       = dplyr::n_distinct(race_id),
      runner_rows = dplyr::n(),
      archive_pct = mean(ok_C),
      feed_pct    = mean(ok_A),
      sp_pct      = mean(ok_B),
      .groups     = "drop"
    )

  by_split <- panel |>
    dplyr::group_by(split) |>
    dplyr::summarise(
      races       = dplyr::n_distinct(race_id),
      runner_rows = dplyr::n(),
      archive_pct = mean(ok_C),
      feed_pct    = mean(ok_A),
      sp_pct      = mean(ok_B),
      .groups     = "drop"
    )

  list(by_year = by_year, by_split = by_split)
}

#' Race-level overround, by price source
#'
#' Overround is the sum of `1 / price` over the field, computed only on
#' races where every runner the pipeline uses carries a usable price, so
#' the sum is over a complete set of prices.
#'
#' `by_source` puts all three prices on ONE race set — the races complete
#' in all three — because the pre-race forecast does not exist before
#' March 2008 and comparing its median against the other two on their own
#' larger sets is not like for like. `by_source_own` keeps each price on
#' its own complete set; that is the quantity the P4-0 audit computed and
#' it exists so `scripts/verify_p4_data_targets.R` can tie the two
#' together.
#'
#' Overround is measured over the FINAL field — the runners that started.
#' The forecast price is struck against the declared field, so a race that
#' loses runners to withdrawals shows a lower figure here than the book it
#' was struck at. That is the field changing, not a malformed price, and
#' proportional renormalisation is unaffected either way.
#'
#' Training split only.
#'
#' @param panel Output of `build_p4_full_panel()`.
#' @return A list with `by_source`, `by_source_own`, `by_field_size`,
#'   `race_level` and `common`.
summarise_p4_overround <- function(panel) {
  race_level <- panel |>
    dplyr::filter(split == "train") |>
    dplyr::group_by(race_id) |>
    dplyr::summarise(
      field_size   = dplyr::n(),
      complete_all = all(ok_A) & all(ok_B) & all(ok_C),
      or_feed      = if (all(ok_A)) sum(1 / fp_feed) else NA_real_,
      or_sp        = if (all(ok_B)) sum(1 / sp)      else NA_real_,
      or_archive   = if (all(ok_C)) sum(1 / fp_arch) else NA_real_,
      .groups      = "drop"
    )

  common <- race_level |> dplyr::filter(complete_all)

  one <- function(df, col, label) {
    v <- df[[col]]
    v <- v[!is.na(v)]
    tibble::tibble(
      source = label, races = length(v),
      p25 = stats::quantile(v, 0.25), median = stats::median(v),
      p75 = stats::quantile(v, 0.75), iqr = stats::IQR(v)
    )
  }

  summarise_set <- function(df) {
    dplyr::bind_rows(
      one(df, "or_feed",    "Pre-race forecast"),
      one(df, "or_archive", "Archived forecast"),
      one(df, "or_sp",      "Starting price")
    )
  }

  by_field_size <- common |>
    dplyr::group_by(field_size) |>
    dplyr::summarise(
      races          = dplyr::n(),
      median_feed    = stats::median(or_feed),
      median_archive = stats::median(or_archive),
      median_sp      = stats::median(or_sp),
      .groups        = "drop"
    ) |>
    dplyr::filter(races >= 10L)

  list(
    by_source     = summarise_set(common),
    by_source_own = summarise_set(race_level),
    by_field_size = by_field_size,
    race_level    = race_level,
    common        = common
  )
}

#' Within-race compression of the forecast book against SP
#'
#' Both books are proportionally overround-normalised within race, then
#' each log-probability is centred on its own race mean. Regressing the
#' centred forecast log-probability on the centred SP log-probability
#' gives the compression slope: below 1 means the forecast book is
#' flatter than SP — favourites too long, longshots too short.
#'
#' Race-mean centring is the right specification rather than a
#' refinement: a conditional logit is invariant to race-constant shifts
#' of a regressor, so only within-race variation is identified, and the
#' slope reported here is the one the market coefficient in @sec-method
#' is expected to invert.
#'
#' Training split, races complete in both books.
#'
#' @param panel Output of `build_p4_full_panel()`.
#' @return A list with `fit_summary`, `by_decile` and `points`.
compute_p4_compression <- function(panel) {
  dat <- panel |>
    dplyr::filter(split == "train") |>
    dplyr::group_by(race_id) |>
    dplyr::filter(all(ok_C), all(ok_B)) |>
    dplyr::mutate(
      p_fc = normalise_overround(fp_arch),
      p_sp = normalise_overround(sp),
      l_fc = log(p_fc),
      l_sp = log(p_sp),
      l_fc_c = l_fc - mean(l_fc),
      l_sp_c = l_sp - mean(l_sp)
    ) |>
    dplyr::ungroup()

  fit <- stats::lm(l_fc_c ~ 0 + l_sp_c, data = dat)
  ct  <- summary(fit)$coefficients

  fit_summary <- tibble::tibble(
    slope     = ct[1, 1],
    std_error = ct[1, 2],
    conf_low  = ct[1, 1] - stats::qnorm(0.975) * ct[1, 2],
    conf_high = ct[1, 1] + stats::qnorm(0.975) * ct[1, 2],
    r_squared = summary(fit)$r.squared,
    n_runners = nrow(dat),
    n_races   = dplyr::n_distinct(dat$race_id)
  )

  by_decile <- dat |>
    dplyr::mutate(sp_decile = dplyr::ntile(p_sp, 10)) |>
    dplyr::group_by(sp_decile) |>
    dplyr::summarise(
      n = dplyr::n(),
      median_p_sp = stats::median(p_sp),
      median_p_fc = stats::median(p_fc),
      mean_log_ratio = mean(l_fc - l_sp),
      .groups = "drop"
    )

  list(
    fit_summary = fit_summary,
    by_decile   = by_decile,
    points      = dat |> dplyr::select(race_id, l_sp_c, l_fc_c)
  )
}

#' Provenance facts about the two forecast-price columns
#'
#' The evidence behind @sec-appx-provenance, computed as a target so the
#' appendix reads live numbers rather than transcribing them from the
#' P4-0 follow-up scripts.
#'
#' Three quantities:
#'   * when each table's row is written relative to the meeting date,
#'     over every in-scope runner row;
#'   * how often the archived and pre-race feed values disagree; and
#'   * where they disagree, which of the two sits closer to the starting
#'     price on the log scale.
#'
#' The distance comparison is TRAINING SPLIT ONLY, per the series'
#' convention: it is a distributional claim about the columns. The
#' load-timing counts are over the whole window, since they are a
#' property of the database rather than of the sample.
#'
#' @param race_ids Integer vector of in-scope race_id values.
#' @param train_race_ids Integer vector of training-split race_id values.
#' @param qualifying_runners The frozen runner-level target, used to
#'   restrict to the runners the pipeline actually uses.
#' @return A list of scalars and small tibbles.
compute_p4_provenance_facts <- function(race_ids, train_race_ids,
                                        qualifying_runners) {
  con <- connect_smartform()
  on.exit(disconnect_smartform(con), add = TRUE)

  id_sql <- paste(race_ids, collapse = ", ")

  timing <- DBI::dbGetQuery(con, sprintf("
    SELECT
      SUM(d.loaded_at <  r.meeting_date) AS daily_before,
      SUM(h.loaded_at >= r.meeting_date) AS archive_on_or_after,
      MIN(DATEDIFF(h.loaded_at, r.meeting_date)) AS min_archive_lag_days,
      COUNT(*) AS n
    FROM daily_runners AS d
    INNER JOIN historic_runners AS h
       ON h.runner_id = d.runner_id AND h.race_id = d.race_id
    INNER JOIN historic_races AS r ON r.race_id = h.race_id
    WHERE h.race_id IN (%s)", id_sql)) |>
    tibble::as_tibble() |>
    dplyr::mutate(dplyr::across(dplyr::everything(), as.numeric))

  rows <- DBI::dbGetQuery(con, sprintf("
    SELECT h.race_id, h.runner_id,
           d.forecast_price_decimal AS fp_feed,
           h.forecast_price_decimal AS fp_arch,
           h.starting_price_decimal AS sp
      FROM daily_runners AS d
      INNER JOIN historic_runners AS h
         ON h.runner_id = d.runner_id AND h.race_id = d.race_id
     WHERE h.race_id IN (%s)
       AND d.forecast_price_decimal IS NOT NULL
       AND h.forecast_price_decimal IS NOT NULL
       AND h.starting_price_decimal IS NOT NULL", id_sql)) |>
    tibble::as_tibble() |>
    dplyr::semi_join(qualifying_runners, by = c("race_id", "runner_id")) |>
    dplyr::filter(race_id %in% train_race_ids,
                  fp_feed > 1, fp_arch > 1, sp > 1) |>
    dplyr::mutate(
      differs = abs(fp_feed - fp_arch) >= 0.005,
      d_feed  = abs(log(fp_feed) - log(sp)),
      d_arch  = abs(log(fp_arch) - log(sp))
    )

  disagreeing <- rows |> dplyr::filter(differs)

  list(
    timing = timing,
    pct_daily_before_meeting = timing$daily_before / timing$n,
    pct_archive_on_or_after  = timing$archive_on_or_after / timing$n,
    min_archive_lag_days     = timing$min_archive_lag_days,
    n_compared               = nrow(rows),
    n_disagreeing            = nrow(disagreeing),
    pct_disagreeing          = mean(rows$differs),
    mean_dist_feed           = mean(disagreeing$d_feed),
    mean_dist_arch           = mean(disagreeing$d_arch),
    pct_archive_closer_to_sp = mean(disagreeing$d_arch < disagreeing$d_feed)
  )
}
