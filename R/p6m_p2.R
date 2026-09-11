# p6m_p2.R
# Paper 6, Section 2 — the P2 scoring rule, refined.
#
# Owen's paper 1 reports two scoring rules over runner-rows whose probability
# exceeds a threshold t:
#
#   P1(t)  geometric mean of the probability assigned to winners
#   P2(t)  geometric mean of the per-row Bernoulli likelihood
#
# P1 is dropped. It reads only the winning rows, so a source can raise it by
# inflating every probability it publishes, and nothing in the rule penalises
# that. P2 reads the losing rows too and is the proper rule of the pair.
#
# THREE CHANGES TO P2.
#
#   1  DISJOINT BINS instead of nested thresholds. Under `P2(t)` the subset at
#      t = 0.15 still contains every row above 0.15, so no band can be read on
#      its own and consecutive thresholds are almost the same set of rows.
#      Here each row falls in exactly one bin.
#
#   2  FINER RESOLUTION BELOW 0.10. The nested form's bottom subset pools
#      everything, and a 0.10 threshold pools every price longer than 9/1,
#      which is where the models' long-priced statements sit. The bins below
#      0.10 are 2, 2, 2 and 4 points wide.
#
#   3  TWO BENCHMARKS. P2 is reported against the over-round-adjusted settled
#      starting price, as the series has always done, and against the
#      overnight racecard forecast price from `daily_runners`, renormalised
#      per race the same way. Paper 4's finding is that the model ties the
#      first and beats the second, so a single benchmark cannot say whether a
#      model's probabilities are good or bad.
#
# BINS ARE CUT ON THE SCORED SOURCE'S OWN PROBABILITY. A bin therefore answers
# "when this source says 4 to 6 per cent, how good are those statements?",
# which is the question a disjoint bin exists to answer. The consequence is
# that a bin holds different rows for different sources, so P2 is comparable
# BETWEEN SOURCES WITHIN A BIN only in the loose sense that both are scoring
# statements of the same stated strength. Across bins P2 is not comparable at
# all: the best attainable value depends on the win rate in the bin, and a bin
# with no winners scores close to 1 for any source. Win counts are reported
# beside every score for that reason.

# ---------------------------------------------------------------------------
# The panel
# ---------------------------------------------------------------------------

#' The disjoint bin edges, and their labels
#'
#' Finer than any threshold the series has used below 0.10, and 5 points wide
#' above 0.15. The bottom bin is kept at 0 to 0.02 rather than merged upward:
#' it is thin, and that thinness is itself the reportable fact that the models
#' almost never state a probability that low.
#'
#' @return A list with `breaks` and `labels`.
p6m_p2_bins_spec <- function() {
  list(
    breaks = c(0, 0.02, 0.04, 0.06, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 1),
    labels = c("0-2%", "2-4%", "4-6%", "6-10%", "10-15%", "15-20%",
               "20-25%", "25-30%", "30-35%", "35%+")
  )
}

#' The five sources P2 is computed for, and their labels
#' @return A named character vector, column name to label.
p6m_p2_sources <- function() {
  c(p_2b = "Paper 2b logit",
    p_3 = "Paper 3 GBT",
    p_5 = "Paper 5 encoder",
    p_sp = "Starting price",
    p_fc = "Forecast price")
}

#' Assemble the Section 2 panel: three models and two benchmarks, one row set
#'
#' Paper 4's price panel already carries the two benchmark probabilities and
#' papers 2b and 3's stored predictions, all renormalised within race by the
#' series' own `normalise_overround()`. The encoder is joined on from paper
#' 5's stored test predictions. Nothing is refitted and no price is
#' renormalised a second time.
#'
#' Every source is scored on the SAME rows. That matters because one benchmark
#' could otherwise be available on fewer races than the other, which would make
#' the model ordering depend on the benchmark through the row set rather than
#' through the models.
#'
#' @param p4_probs Paper 4's `p4_probs` target.
#' @param encoder Paper 5's stored rung-3b test predictions.
#' @return A tibble, one row per scorable test runner.
p6m_p2_panel <- function(p4_probs, encoder) {
  panel <- p4_probs |>
    dplyr::filter(ok_A, ok_B) |>
    dplyr::select(race_id, runner_id, won, field_size,
                  p_2b = p_mod_2b, p_3 = p_mod_3,
                  p_sp = p_mkt_B, p_fc = p_mkt_A) |>
    dplyr::inner_join(
      dplyr::select(encoder, race_id, runner_id, p_5 = win_model),
      by = c("race_id", "runner_id")
    )

  cols <- names(p6m_p2_sources())

  # Every probability must be usable as a Bernoulli likelihood, and every
  # source must be a genuine within-race distribution.
  for (cl in cols) {
    v <- panel[[cl]]
    stopifnot(!anyNA(v), all(v > 0), all(v < 1))
  }
  sums <- panel |>
    dplyr::group_by(race_id) |>
    dplyr::summarise(dplyr::across(dplyr::all_of(cols), sum), .groups = "drop")
  stopifnot(max(abs(as.matrix(sums[cols]) - 1)) < 1e-9)

  # Exactly one winner per race, as everywhere in the series.
  wins <- panel |>
    dplyr::group_by(race_id) |>
    dplyr::summarise(w = sum(won), .groups = "drop")
  stopifnot(all(wins$w == 1L))

  panel
}

#' What the panel costs against the full test split
#'
#' The panel is the intersection of paper 4's price panel and paper 5's test
#' predictions. Reported rather than absorbed, so the reader can see how many
#' rows the forecast-price requirement removes.
#'
#' @param panel Output of `p6m_p2_panel()`.
#' @param encoder Paper 5's stored rung-3b test predictions.
#' @return A one-row tibble.
p6m_p2_coverage <- function(panel, encoder) {
  tibble::tibble(
    rows_test = nrow(encoder),
    races_test = dplyr::n_distinct(encoder$race_id),
    rows_panel = nrow(panel),
    races_panel = dplyr::n_distinct(panel$race_id),
    rows_dropped = nrow(encoder) - nrow(panel),
    races_dropped = dplyr::n_distinct(encoder$race_id) -
      dplyr::n_distinct(panel$race_id)
  )
}

# ---------------------------------------------------------------------------
# The rule
# ---------------------------------------------------------------------------

#' P2: the geometric mean of the per-row Bernoulli likelihood
#'
#' `exp(mean(log(p) on winners, log(1 - p) on losers))`. Higher is better.
#'
#' @param p Numeric vector of probabilities, strictly inside (0, 1).
#' @param won Integer 0/1 win indicator.
#' @return A scalar, or `NA_real_` on an empty input.
p6m_p2 <- function(p, won) {
  if (length(p) == 0L) return(NA_real_)
  exp(mean(dplyr::if_else(won == 1L, log(p), log1p(-p))))
}

#' Race-level bootstrap of a set of P2 statistics computed on one panel
#'
#' Races are the resampling unit, as everywhere else in the series. One set of
#' race draws is shared across every statistic in `f`, so differences between
#' statistics are paired by race and their intervals are comparable.
#'
#' @param panel A tibble carrying `race_id`.
#' @param f A named list of functions of a resampled panel, each returning a
#'   scalar.
#' @param n_boot,seed Replicates and RNG seed.
#' @return A tibble: `statistic`, `point`, `ci_lo`, `ci_hi`, `n_races`.
p6m_p2_bootstrap <- function(panel, f, n_boot = 2000L, seed = 42L) {
  races <- sort(unique(panel$race_id))
  n <- length(races)
  by_race <- split(seq_len(nrow(panel)), match(panel$race_id, races))

  point <- vapply(f, function(g) g(panel), numeric(1))

  set.seed(seed)
  reps <- matrix(NA_real_, nrow = n_boot, ncol = length(f),
                 dimnames = list(NULL, names(f)))
  for (b in seq_len(n_boot)) {
    idx <- unlist(by_race[sample.int(n, n, replace = TRUE)], use.names = FALSE)
    d <- panel[idx, , drop = FALSE]
    reps[b, ] <- vapply(f, function(g) g(d), numeric(1))
  }

  tibble::tibble(
    statistic = names(f),
    point = unname(point),
    ci_lo = apply(reps, 2, stats::quantile, 0.05, na.rm = TRUE, names = FALSE),
    ci_hi = apply(reps, 2, stats::quantile, 0.95, na.rm = TRUE, names = FALSE),
    n_races = n
  )
}

#' Overall P2 for every source, with intervals
#'
#' @param panel Output of `p6m_p2_panel()`.
#' @param n_boot,seed Replicates and RNG seed.
#' @return A tibble, one row per source, best first.
p6m_p2_overall <- function(panel, n_boot = 2000L, seed = 42L) {
  src <- p6m_p2_sources()
  f <- purrr::map(rlang::set_names(names(src)),
                  function(cl) function(d) p6m_p2(d[[cl]], d$won))
  p6m_p2_bootstrap(panel, f, n_boot, seed) |>
    dplyr::transmute(source = unname(src[statistic]), column = statistic,
                     p2 = point, ci_lo, ci_hi, n_races,
                     n_rows = nrow(panel)) |>
    dplyr::arrange(dplyr::desc(p2))
}

#' Every model against every benchmark, paired by race
#'
#' @param panel Output of `p6m_p2_panel()`.
#' @param models Model column names.
#' @param benchmarks Benchmark column names.
#' @param n_boot,seed Replicates and RNG seed.
#' @return A tibble, one row per (model, benchmark).
p6m_p2_contrasts <- function(panel, models = c("p_2b", "p_3", "p_5"),
                             benchmarks = c("p_sp", "p_fc"),
                             n_boot = 2000L, seed = 42L) {
  src <- p6m_p2_sources()
  spec <- tidyr::expand_grid(model = models, benchmark = benchmarks)
  f <- purrr::map(
    rlang::set_names(paste(spec$model, spec$benchmark, sep = "|")),
    function(key) {
      parts <- strsplit(key, "|", fixed = TRUE)[[1]]
      function(d) p6m_p2(d[[parts[1]]], d$won) - p6m_p2(d[[parts[2]]], d$won)
    }
  )
  p6m_p2_bootstrap(panel, f, n_boot, seed) |>
    tidyr::separate_wider_delim(statistic, "|",
                                names = c("model", "benchmark")) |>
    dplyr::transmute(
      model = unname(src[model]), benchmark = unname(src[benchmark]),
      diff_point = point, ci_lo, ci_hi, n_races,
      excludes_zero = ci_lo > 0 | ci_hi < 0
    )
}

#' The three models against each other on P2, paired by race
#'
#' Section 1 showed the single-bet ROI difference between papers 2b and 3 has
#' an interval far too wide to separate them. This asks the same question of
#' P2, which is the point of preferring it: it is computed over every
#' runner-row rather than over the races a betting rule selects.
#'
#' @param panel Output of `p6m_p2_panel()`.
#' @param models Model column names, best-first order not required.
#' @param n_boot,seed Replicates and RNG seed.
#' @return A tibble, one row per unordered model pair.
p6m_p2_model_pairs <- function(panel, models = c("p_5", "p_2b", "p_3"),
                               n_boot = 2000L, seed = 42L) {
  src <- p6m_p2_sources()
  spec <- tidyr::expand_grid(ai = seq_along(models), bi = seq_along(models)) |>
    dplyr::filter(ai < bi) |>
    dplyr::transmute(a = models[ai], b = models[bi])
  f <- purrr::map(
    rlang::set_names(paste(spec$a, spec$b, sep = "|")),
    function(key) {
      parts <- strsplit(key, "|", fixed = TRUE)[[1]]
      function(d) p6m_p2(d[[parts[1]]], d$won) - p6m_p2(d[[parts[2]]], d$won)
    }
  )
  p6m_p2_bootstrap(panel, f, n_boot, seed) |>
    tidyr::separate_wider_delim(statistic, "|", names = c("a", "b")) |>
    dplyr::transmute(
      contrast = paste(unname(src[a]), "-", unname(src[b])),
      diff_point = point, ci_lo, ci_hi, n_races,
      excludes_zero = ci_lo > 0 | ci_hi < 0
    )
}

#' P2 by disjoint bin, for every source
#'
#' Bins are cut on the scored source's own probability, so a source's row
#' counts differ from another's. `n` and `wins` are reported beside every
#' score because P2 is not comparable across bins: a bin with few or no
#' winners scores close to 1 whatever the source.
#'
#' @param panel Output of `p6m_p2_panel()`.
#' @param spec Output of `p6m_p2_bins_spec()`.
#' @param n_boot,seed Replicates and RNG seed.
#' @param min_rows Bins with fewer rows than this get no interval; their
#'   point estimate is still reported.
#' @return A long tibble: one row per (source, bin).
p6m_p2_by_bin <- function(panel, spec = p6m_p2_bins_spec(),
                          n_boot = 2000L, seed = 42L, min_rows = 30L) {
  src <- p6m_p2_sources()

  binned <- panel |>
    dplyr::mutate(dplyr::across(
      dplyr::all_of(names(src)),
      ~ cut(.x, spec$breaks, labels = spec$labels, right = FALSE,
            include.lowest = TRUE),
      .names = "bin_{.col}"
    ))

  f <- list()
  for (cl in names(src)) {
    for (lb in spec$labels) {
      key <- paste(cl, lb, sep = "|")
      f[[key]] <- local({
        cl_ <- cl; lb_ <- lb
        function(d) {
          keep <- d[[paste0("bin_", cl_)]] == lb_
          p6m_p2(d[[cl_]][keep], d$won[keep])
        }
      })
    }
  }

  # Row and win counts, and the mean probability the source states inside the
  # bin. `mean_p` against `win_rate` is the calibration comparison: it is the
  # only within-bin reading that does not depend on which rows the bin holds.
  counts <- purrr::map(names(src), function(cl)
    binned |>
      dplyr::group_by(bin = .data[[paste0("bin_", cl)]]) |>
      dplyr::summarise(n = dplyr::n(), wins = sum(won),
                       mean_p = mean(.data[[cl]]), .groups = "drop") |>
      dplyr::mutate(column = cl)) |>
    purrr::list_rbind()

  p6m_p2_bootstrap(binned, f, n_boot, seed) |>
    tidyr::separate_wider_delim(statistic, "|", names = c("column", "bin")) |>
    dplyr::left_join(counts, by = c("column", "bin")) |>
    dplyr::mutate(
      source = unname(src[column]),
      n = dplyr::coalesce(n, 0L), wins = dplyr::coalesce(wins, 0L),
      win_rate = dplyr::if_else(n > 0L, wins / n, NA_real_),
      calib_gap = win_rate - mean_p,
      thin = n < min_rows,
      ci_lo = dplyr::if_else(thin, NA_real_, ci_lo),
      ci_hi = dplyr::if_else(thin, NA_real_, ci_hi)
    ) |>
    dplyr::transmute(source, column, bin, n, wins, mean_p, win_rate,
                     calib_gap, p2 = point, ci_lo, ci_hi, thin) |>
    dplyr::arrange(match(column, names(src)), match(bin, spec$labels))
}

#' The model ordering under each benchmark, and whether it differs
#'
#' The prompt's question. Both benchmarks are scored on the same rows here, so
#' the models' own P2 cannot change between them; what can change is whether a
#' model beats the benchmark. This records both facts explicitly rather than
#' leaving the reader to infer them.
#'
#' @param overall Output of `p6m_p2_overall()`.
#' @param contrasts Output of `p6m_p2_contrasts()`.
#' @return A tibble, one row per benchmark.
p6m_p2_ordering <- function(overall, contrasts) {
  models <- overall |>
    dplyr::filter(column %in% c("p_2b", "p_3", "p_5")) |>
    dplyr::arrange(dplyr::desc(p2))
  order_str <- paste(models$source, collapse = " > ")

  contrasts |>
    dplyr::group_by(benchmark) |>
    dplyr::summarise(
      `model ordering` = order_str,
      n_models_above = sum(diff_point > 0),
      n_above_excluding_zero = sum(diff_point > 0 & excludes_zero),
      n_below_excluding_zero = sum(diff_point < 0 & excludes_zero),
      .groups = "drop"
    )
}
