# p6m_p2.R
# Paper 6, Section 2 — Owen's two scoring rules, recomputed.
#
# Paper 1 reports two rules over the runner-rows whose probability exceeds a
# threshold t:
#
#   P1(t)  geometric mean of the probability assigned to winners
#   P2(t)  geometric mean of the per-row Bernoulli likelihood
#
# BOTH ARE KEPT. Every source here is a distribution over the race: the model
# probabilities come from a softmax or a conditional logit over the race's
# runners, and both price columns are renormalised within race by
# `normalise_overround()`. Under that constraint the two rules score two
# different outcomes, and each is proper for the one it scores.
#
#   P1 at t = 0 is the exponentiated mean, over races, of the log probability
#   assigned to the horse that won. There is exactly one winner per race, so
#   the mean over winning rows is a mean over races. That is the log score for
#   the race-level categorical outcome.
#
#   P2 sums a Bernoulli log-likelihood over every runner-row and divides by
#   the row count, so it scores each runner's marginal win probability as an
#   independent binary event and does not use the one-winner constraint.
#
# `score_p1_rank()` in `R/scoring.R` — the series' headline ranking measure in
# papers 3 and 5 — is `exp(mean(log(P(observed top-3 order))))`, the same
# construction at depth three. Its own documentation calls it "the ranking
# analogue of Owen's P1".
#
# TWO CHANGES, and they are the section's subject.
#
#   1  DISJOINT BINS instead of nested thresholds. Subsetting rows on the
#      source's own probability before scoring affects P1 and P2 equally:
#      under `P1(t)` and `P2(t)` the subset at t = 0.15 still contains every
#      row above 0.15, so consecutive thresholds are nearly the same rows and
#      no band can be read on its own. Disjoint bins are what address that.
#
#   2  TWO BENCHMARKS. The over-round-adjusted settled starting price, as the
#      series has always used, and the overnight racecard forecast price from
#      `daily_runners`, renormalised per race the same way.
#
# P1 IS NOT REPORTED BY BIN. It reads only the winning rows, and four of the
# fifty source-by-bin cells contain no winner, so a per-bin P1 table would
# have holes in it. The bins carry calibration instead: what a source states
# against what happens, which is the only within-bin reading that does not
# depend on which rows the bin holds.

# ---------------------------------------------------------------------------
# The panel
# ---------------------------------------------------------------------------

#' The disjoint bin edges, and their labels
#'
#' Finer than any threshold the series has used below 0.10, and 5 points wide
#' above 0.15.
#'
#' @return A list with `breaks` and `labels`.
p6m_p2_bins_spec <- function() {
  list(
    breaks = c(0, 0.02, 0.04, 0.06, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 1),
    labels = c("0-2%", "2-4%", "4-6%", "6-10%", "10-15%", "15-20%",
               "20-25%", "25-30%", "30-35%", "35%+")
  )
}

#' The five sources the rules are computed for, and their labels
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
#' Every source is scored on the SAME rows, so the ordering cannot depend on a
#' benchmark through the row set rather than through the sources.
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

  # Every probability must be usable as a likelihood, and every source must be
  # a genuine within-race distribution — which is what makes P1 the log score
  # for the race rather than an arbitrary average over winners.
  for (cl in cols) {
    v <- panel[[cl]]
    stopifnot(!anyNA(v), all(v > 0), all(v < 1))
  }
  sums <- panel |>
    dplyr::group_by(race_id) |>
    dplyr::summarise(dplyr::across(dplyr::all_of(cols), sum), .groups = "drop")
  stopifnot(max(abs(as.matrix(sums[cols]) - 1)) < 1e-9)

  # Exactly one winner per race, so P1's mean over winning rows is a mean over
  # races.
  wins <- panel |>
    dplyr::group_by(race_id) |>
    dplyr::summarise(w = sum(won), .groups = "drop")
  stopifnot(all(wins$w == 1L))

  panel
}

#' What the panel costs against the full test split
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
# The rules
# ---------------------------------------------------------------------------

#' P1: the geometric mean of the probability assigned to winners
#'
#' `exp(mean(log(p)))` over the winning rows. With one winner per race this is
#' the exponentiated mean per-race log probability of the observed winner.
#' Higher is better.
#'
#' @param p Numeric vector of probabilities, strictly inside (0, 1).
#' @param won Integer 0/1 win indicator.
#' @return A scalar, or `NA_real_` if the input holds no winner.
p6m_p1 <- function(p, won) {
  w <- p[won == 1L]
  if (length(w) == 0L) return(NA_real_)
  exp(mean(log(w)))
}

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

#' One of the two rules, by name
#' @param p,won As for `p6m_p1()`.
#' @param rule `"P1"` or `"P2"`.
#' @return A scalar.
p6m_score <- function(p, won, rule) {
  switch(rule, P1 = p6m_p1(p, won), P2 = p6m_p2(p, won),
         stop("unknown rule: ", rule))
}

#' The two rules, in report order
#' @return A character vector.
p6m_rules <- function() c("P1", "P2")

#' Race-level bootstrap of a set of statistics computed on one panel
#'
#' Races are the resampling unit, as everywhere else in the series. ONE set of
#' race draws is shared across every statistic in `f`, so both rules and every
#' source are paired by race and their intervals are comparable.
#'
#' @param panel A tibble carrying `race_id`.
#' @param f A named list of functions of a resampled panel, each returning a
#'   scalar.
#' @param n_boot,seed Replicates and RNG seed.
#' @return A tibble: `statistic`, `point`, `ci_lo`, `ci_hi`, `n_races`.
p6m_score_bootstrap <- function(panel, f, n_boot = 2000L, seed = 42L) {
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

#' Both rules, every source, with intervals
#'
#' @param panel Output of `p6m_p2_panel()`.
#' @param n_boot,seed Replicates and RNG seed.
#' @return A tibble, one row per (rule, source).
p6m_scores_overall <- function(panel, n_boot = 2000L, seed = 42L) {
  src <- p6m_p2_sources()
  keys <- tidyr::expand_grid(rule = p6m_rules(), column = names(src))
  f <- purrr::map(
    rlang::set_names(paste(keys$rule, keys$column, sep = "|")),
    function(key) {
      parts <- strsplit(key, "|", fixed = TRUE)[[1]]
      function(d) p6m_score(d[[parts[2]]], d$won, parts[1])
    }
  )
  p6m_score_bootstrap(panel, f, n_boot, seed) |>
    tidyr::separate_wider_delim(statistic, "|", names = c("rule", "column")) |>
    dplyr::transmute(rule, source = unname(src[column]), column,
                     score = point, ci_lo, ci_hi, n_races,
                     n_rows = nrow(panel)) |>
    dplyr::arrange(match(rule, p6m_rules()), dplyr::desc(score))
}

#' Every model against every benchmark, on both rules, paired by race
#'
#' @param panel Output of `p6m_p2_panel()`.
#' @param models,benchmarks Column names.
#' @param n_boot,seed Replicates and RNG seed.
#' @return A tibble, one row per (rule, model, benchmark).
p6m_scores_vs_benchmark <- function(panel, models = c("p_2b", "p_3", "p_5"),
                                    benchmarks = c("p_sp", "p_fc"),
                                    n_boot = 2000L, seed = 42L) {
  src <- p6m_p2_sources()
  spec <- tidyr::expand_grid(rule = p6m_rules(), model = models,
                             benchmark = benchmarks)
  f <- purrr::map(
    rlang::set_names(paste(spec$rule, spec$model, spec$benchmark, sep = "|")),
    function(key) {
      p <- strsplit(key, "|", fixed = TRUE)[[1]]
      function(d) p6m_score(d[[p[2]]], d$won, p[1]) -
        p6m_score(d[[p[3]]], d$won, p[1])
    }
  )
  p6m_score_bootstrap(panel, f, n_boot, seed) |>
    tidyr::separate_wider_delim(statistic, "|",
                                names = c("rule", "model", "benchmark")) |>
    dplyr::transmute(
      rule, model = unname(src[model]), benchmark = unname(src[benchmark]),
      diff_point = point, ci_lo, ci_hi, n_races,
      excludes_zero = ci_lo > 0 | ci_hi < 0
    ) |>
    dplyr::arrange(match(rule, p6m_rules()), benchmark, model)
}

#' The three models against each other, on both rules, paired by race
#'
#' @param panel Output of `p6m_p2_panel()`.
#' @param models Model column names.
#' @param n_boot,seed Replicates and RNG seed.
#' @return A tibble, one row per (rule, unordered model pair).
p6m_scores_model_pairs <- function(panel, models = c("p_5", "p_2b", "p_3"),
                                   n_boot = 2000L, seed = 42L) {
  src <- p6m_p2_sources()
  pairs <- tidyr::expand_grid(ai = seq_along(models), bi = seq_along(models)) |>
    dplyr::filter(ai < bi) |>
    dplyr::transmute(a = models[ai], b = models[bi])
  spec <- tidyr::expand_grid(rule = p6m_rules(), i = seq_len(nrow(pairs))) |>
    dplyr::mutate(a = pairs$a[i], b = pairs$b[i])
  f <- purrr::map(
    rlang::set_names(paste(spec$rule, spec$a, spec$b, sep = "|")),
    function(key) {
      p <- strsplit(key, "|", fixed = TRUE)[[1]]
      function(d) p6m_score(d[[p[2]]], d$won, p[1]) -
        p6m_score(d[[p[3]]], d$won, p[1])
    }
  )
  p6m_score_bootstrap(panel, f, n_boot, seed) |>
    tidyr::separate_wider_delim(statistic, "|", names = c("rule", "a", "b")) |>
    dplyr::transmute(
      rule, contrast = paste(unname(src[a]), "-", unname(src[b])),
      diff_point = point, ci_lo, ci_hi, n_races,
      excludes_zero = ci_lo > 0 | ci_hi < 0
    ) |>
    dplyr::arrange(match(rule, p6m_rules()), contrast)
}

#' Whether the two rules agree on the ordering of the sources
#'
#' A single fact, reported in a clause rather than a table.
#'
#' @param overall Output of `p6m_scores_overall()`.
#' @return A one-row tibble.
p6m_rules_agree <- function(overall) {
  ord_of <- function(d) d |>
    dplyr::group_by(rule) |>
    dplyr::arrange(dplyr::desc(score), .by_group = TRUE) |>
    dplyr::summarise(order = paste(source, collapse = " > "), .groups = "drop")

  all_src <- ord_of(overall)
  models <- ord_of(dplyr::filter(overall,
                                 column %in% c("p_2b", "p_3", "p_5")))
  tibble::tibble(
    all_sources_order = all_src$order[1],
    all_sources_agree = dplyr::n_distinct(all_src$order) == 1L,
    models_order = models$order[1],
    models_agree = dplyr::n_distinct(models$order) == 1L
  )
}

# ---------------------------------------------------------------------------
# The bins
# ---------------------------------------------------------------------------

#' Calibration by disjoint bin: what a source states against what happens
#'
#' No bootstrap and no score. Bins are cut on the scored source's own
#' probability, so a bin holds different rows for different sources and a
#' score computed inside one is largely set by the bin's win rate. Mean stated
#' probability against observed win rate is the reading that survives that,
#' and it is the only one the bins are used for.
#'
#' @param panel Output of `p6m_p2_panel()`.
#' @param spec Output of `p6m_p2_bins_spec()`.
#' @return A long tibble: one row per (source, bin).
p6m_bin_calibration <- function(panel, spec = p6m_p2_bins_spec()) {
  src <- p6m_p2_sources()
  purrr::map(names(src), function(cl) {
    panel |>
      dplyr::mutate(bin = cut(.data[[cl]], spec$breaks, labels = spec$labels,
                              right = FALSE, include.lowest = TRUE)) |>
      dplyr::group_by(bin) |>
      dplyr::summarise(n = dplyr::n(), wins = sum(won),
                       mean_p = mean(.data[[cl]]), .groups = "drop") |>
      dplyr::mutate(source = unname(src[cl]), column = cl)
  }) |>
    purrr::list_rbind() |>
    dplyr::mutate(win_rate = wins / n, calib_gap = win_rate - mean_p) |>
    dplyr::transmute(source, column, bin, n, wins, mean_p, win_rate,
                     calib_gap) |>
    dplyr::arrange(match(column, names(src)), match(bin, spec$labels))
}
