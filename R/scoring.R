# scoring.R
# Out-of-sample evaluation helpers for the AW conditional-logit model:
# test-set per-runner predictions, market-probability construction,
# the model/market probability ratio, the betting backtest, and the
# race-level bootstrap for ROI confidence intervals.
#
# All five functions are pure (inputs -> outputs, no side effects) and
# get wired into `_targets.R` as their own targets.

#' Identify model terms whose every level is non-significant
#'
#' For each term in the full fit's coefficient table, returns the term
#' if at least one of its levels reaches p < 0.05. Factor terms
#' (`position1`, `position2`, `position3`) are grouped on the leading
#' name; plain numeric / binary terms map to themselves.
#'
#' @param model_diagnostics The list returned by
#'   `extract_model_diagnostics()` — specifically its `coefficients`
#'   tibble.
#' @return A list with two character vectors: `kept` (terms with at
#'   least one significant level) and `dropped` (terms with every
#'   level NS at the 0.05 threshold).
identify_significant_terms <- function(model_diagnostics) {
  term_of <- function(coef_name) {
    if (grepl("^position1[1-4]$", coef_name)) return("position1")
    if (grepl("^position2[1-4]$", coef_name)) return("position2")
    if (grepl("^position3[1-4]$", coef_name)) return("position3")
    coef_name
  }

  summary_tbl <- model_diagnostics$coefficients |>
    dplyr::mutate(term = vapply(parameter, term_of, character(1))) |>
    dplyr::group_by(term) |>
    dplyr::summarise(
      any_sig = any(!is.na(p.value) & p.value < 0.05),
      .groups = "drop"
    )

  list(
    kept    = summary_tbl$term[ summary_tbl$any_sig],
    dropped = summary_tbl$term[!summary_tbl$any_sig]
  )
}

#' Fit the reduced (post-pruning) conditional-logit
#'
#' Applies the standard p > 0.05 reduction rule to the full fit's
#' coefficient table and refits on the same training data. The
#' three-part `| 0 | 0` matches Owen's reference script and matches
#' the formula used by `fit_conditional_logit()` in the full fit.
#'
#' @param mlogit_train_data  Output of `prepare_mlogit_data()` for the
#'   training subset.
#' @param model_diagnostics  As above.
#' @return The fitted `mlogit` object for the reduced specification.
fit_reduced_model <- function(mlogit_train_data, model_diagnostics) {
  terms <- identify_significant_terms(model_diagnostics)
  if (length(terms$kept) == 0L) {
    stop("All terms were non-significant at p > 0.05; cannot build reduced model.")
  }

  final_formula <- stats::as.formula(
    paste("won ~", paste(terms$kept, collapse = " + "), "| 0 | 0")
  )

  mlogit::mlogit(final_formula, data = mlogit_train_data)
}

#' Build the per-runner test-set predictions tibble
#'
#' Joins the test-set fitted probabilities (from `predict.mlogit`) to
#' the per-runner test rows, attaches the runner's starting price, and
#' computes the over-round-adjusted market-implied probability for
#' each runner. The output is the canonical tibble consumed by §3.3
#' calibration / scoring chunks and by every §3.4 backtest step.
#'
#' Padded slots (the `max_field_size − n_runners_in_race` zero-
#' probability columns inside `predict.mlogit`'s output) are stripped
#' by filtering on `model_prob > 0`.
#'
#' @param fitted_final       The reduced mlogit fit (trained on the
#'   training set).
#' @param mlogit_test_data   Output of `prepare_mlogit_data()` for the
#'   test subset.
#' @param qualifying_runners The runner-level tibble; supplies
#'   `starting_price_decimal` and `won`.
#' @return A tibble keyed by (race_id, runner_id) with columns
#'   `race_id`, `runner_id`, `horse_ref`, `won`, `model_prob`,
#'   `starting_price_decimal`, `market_prob`. Rows with NA / missing
#'   SP are kept (so the table is comparable across §3.3 / §3.4
#'   chunks) but `market_prob` is NA for them; downstream filters
#'   handle.
build_test_predictions <- function(fitted_final, mlogit_test_data,
                                   qualifying_runners) {
  loadNamespace("mlogit")

  probs_mat <- stats::predict(fitted_final, newdata = mlogit_test_data)

  model_probs_long <- probs_mat |>
    as.data.frame() |>
    tibble::rownames_to_column("race_id") |>
    tidyr::pivot_longer(
      cols      = -race_id,
      names_to  = "horse_ref",
      values_to = "model_prob"
    ) |>
    dplyr::filter(!is.na(model_prob), model_prob > 0) |>
    dplyr::mutate(
      race_id   = as.integer(race_id),
      horse_ref = as.integer(horse_ref)
    )

  mldat_df <- as.data.frame(mlogit_test_data)
  class(mldat_df) <- "data.frame"
  attr(mldat_df, "index")    <- NULL
  attr(mldat_df, "clseries") <- NULL

  base <- mldat_df |>
    dplyr::select(race_id, runner_id, horse_ref, won) |>
    dplyr::mutate(
      race_id   = as.integer(race_id),
      horse_ref = as.integer(horse_ref),
      won       = as.integer(won)
    ) |>
    dplyr::inner_join(model_probs_long, by = c("race_id", "horse_ref"))

  sp_lookup <- qualifying_runners |>
    dplyr::select(race_id, runner_id, starting_price_decimal)

  base |>
    dplyr::left_join(sp_lookup, by = c("race_id", "runner_id")) |>
    dplyr::group_by(race_id) |>
    dplyr::mutate(
      implied_raw = dplyr::if_else(
        !is.na(starting_price_decimal) & starting_price_decimal > 1,
        1 / starting_price_decimal,
        NA_real_
      ),
      market_prob = implied_raw / sum(implied_raw, na.rm = TRUE)
    ) |>
    dplyr::ungroup() |>
    dplyr::select(-implied_raw)
}

#' Compute the model / market probability ratio per test runner
#'
#' Drops rows where either probability is unavailable (missing SP, or
#' a runner that the model could not score). Required input for the
#' bet-selection step.
#'
#' @param test_predictions Output of `build_test_predictions()`.
#' @return The same tibble filtered to rows with both probabilities
#'   defined, plus a `ratio = model_prob / market_prob` column.
compute_model_market_ratio <- function(test_predictions) {
  test_predictions |>
    dplyr::filter(
      !is.na(model_prob),  model_prob  > 0,
      !is.na(market_prob), market_prob > 0
    ) |>
    dplyr::mutate(ratio = model_prob / market_prob)
}

#' Single-threshold backtest
#'
#' Selects runner-rows where `model_prob > prob_threshold` AND
#' `ratio > ratio_threshold`, stakes one unit on each, computes total
#' return and ROI. Returns are decimal odds × win indicator (so SP =
#' 5.0 on a winning horse returns 5 units, of which 1 was the stake).
#'
#' @param ratio_df          Output of `compute_model_market_ratio()`.
#' @param prob_threshold    Lower bound on model probability (Owen
#'   uses 0.15 in §3.4 of the paper).
#' @param ratio_threshold   Lower bound on model/market ratio (Owen
#'   uses 1.3 in §3.4).
#' @return A one-row tibble: `prob_threshold`, `ratio_threshold`,
#'   `n_bets`, `n_wins`, `gross_return`, `profit`, `roi`. ROI is
#'   `(gross_return - n_bets) / n_bets`; NA if no bets selected.
run_backtest <- function(ratio_df, prob_threshold, ratio_threshold) {
  bets <- ratio_df |>
    dplyr::filter(model_prob > prob_threshold,
                  ratio       > ratio_threshold)

  n_bets <- nrow(bets)

  if (n_bets == 0L) {
    return(tibble::tibble(
      prob_threshold  = prob_threshold,
      ratio_threshold = ratio_threshold,
      n_bets          = 0L,
      n_wins          = 0L,
      gross_return    = 0,
      profit          = 0,
      roi             = NA_real_
    ))
  }

  bets <- bets |>
    dplyr::mutate(
      return_unit = dplyr::if_else(
        won == 1L,
        starting_price_decimal,
        0
      )
    )

  gross_return <- sum(bets$return_unit)
  profit       <- gross_return - n_bets

  tibble::tibble(
    prob_threshold  = prob_threshold,
    ratio_threshold = ratio_threshold,
    n_bets          = as.integer(n_bets),
    n_wins          = sum(bets$won == 1L),
    gross_return    = gross_return,
    profit          = profit,
    roi             = profit / n_bets
  )
}

#' Bootstrap ROI confidence interval at one ratio threshold
#'
#' Resamples **races** (not runner-rows) with replacement `n_boot`
#' times, computes ROI on the resampled bet set for each draw, and
#' returns the bootstrap distribution. Race-level resampling
#' preserves the one-winner-per-race structure that runner-level
#' resampling would destroy.
#'
#' If a race contains no bets at the given thresholds it contributes
#' nothing to the ROI denominator; if the resample selects zero bets
#' overall, ROI for that draw is NA and excluded from percentile
#' summaries.
#'
#' @param ratio_df         Output of `compute_model_market_ratio()`.
#' @param prob_threshold   As above.
#' @param ratio_threshold  As above.
#' @param n_boot           Number of bootstrap draws. Default 2000.
#' @return A numeric vector of length `n_boot` of bootstrap ROI
#'   replicates (NA where no bets in the draw).
bootstrap_roi <- function(ratio_df, prob_threshold, ratio_threshold,
                          n_boot = 2000L) {
  bets <- ratio_df |>
    dplyr::filter(model_prob > prob_threshold,
                  ratio       > ratio_threshold) |>
    dplyr::mutate(
      return_unit = dplyr::if_else(won == 1L, starting_price_decimal, 0)
    ) |>
    dplyr::select(race_id, return_unit)

  if (nrow(bets) == 0L) return(rep(NA_real_, n_boot))

  per_race <- bets |>
    dplyr::group_by(race_id) |>
    dplyr::summarise(
      n_bets       = dplyr::n(),
      gross_return = sum(return_unit),
      .groups      = "drop"
    )

  race_ids <- per_race$race_id
  n_races  <- length(race_ids)

  # Index lookup so we can vectorise per-race contributions.
  n_bets_vec <- per_race$n_bets
  gross_vec  <- per_race$gross_return

  out <- vapply(seq_len(n_boot), function(b) {
    idx       <- sample.int(n_races, size = n_races, replace = TRUE)
    nb        <- sum(n_bets_vec[idx])
    if (nb == 0L) return(NA_real_)
    gr        <- sum(gross_vec[idx])
    (gr - nb) / nb
  }, numeric(1))

  out
}

#' Bootstrap-CI ROI sweep across ratio thresholds
#'
#' For each `tau` in `tau_seq`, runs the point-estimate backtest plus
#' a `n_boot`-replicate race-level bootstrap, returning point ROI and
#' the 5th / 95th percentiles of the bootstrap distribution (a 90%
#' CI). The `seed` is set once at the top of the sweep so the entire
#' sweep is reproducible.
#'
#' @param ratio_df        Output of `compute_model_market_ratio()`.
#' @param prob_threshold  Lower bound on model probability held fixed
#'   across the sweep.
#' @param tau_seq         Numeric vector of ratio thresholds.
#' @param n_boot          Number of bootstrap draws per threshold.
#' @param seed            RNG seed; default 42.
#' @return A long tibble with columns `tau`, `n_bets`, `n_wins`,
#'   `roi`, `ci_lo`, `ci_hi`.
run_backtest_sweep <- function(ratio_df, prob_threshold, tau_seq,
                               n_boot = 2000L, seed = 42L) {
  set.seed(seed)

  point <- purrr::map_dfr(tau_seq, \(tau) {
    run_backtest(ratio_df,
                 prob_threshold  = prob_threshold,
                 ratio_threshold = tau) |>
      dplyr::transmute(tau = tau, n_bets, n_wins, roi)
  })

  ci <- purrr::map_dfr(tau_seq, \(tau) {
    boot <- bootstrap_roi(ratio_df,
                          prob_threshold  = prob_threshold,
                          ratio_threshold = tau,
                          n_boot          = n_boot)
    tibble::tibble(
      tau   = tau,
      ci_lo = stats::quantile(boot, 0.05, na.rm = TRUE, names = FALSE),
      ci_hi = stats::quantile(boot, 0.95, na.rm = TRUE, names = FALSE)
    )
  })

  dplyr::left_join(point, ci, by = "tau")
}

#' Discounted-Harville market place probabilities (paper 2b)
#'
#' Converts over-round-adjusted starting-price *win* probabilities into
#' market-implied *place* (top-3) probabilities, for use as the market
#' baseline in paper 2b's ranking evaluation.
#'
#' Under pure Harville (1973), the probability that horse \eqn{j} finishes
#' second given horse \eqn{i} won is \eqn{p_j / (1 - p_i)}, third given
#' \eqn{i, m} placed first and second is \eqn{p_k / (1 - p_i - p_m)}, and
#' so on. Pure Harville is the Plackett–Luce model, so it would be a
#' circular baseline for a PL-fitted model. The **discounted** Harville of
#' Lo & Bacon-Shone (1994, 2008) replaces \eqn{p_k} with \eqn{p_k^{\alpha}}
#' in the conditional steps — \eqn{\alpha_2} (`alpha_2nd`) for the
#' second-place conditional and a smaller \eqn{\alpha_3} (`alpha_3rd`) for
#' the third — which both breaks the PL equivalence and corrects the
#' favourite–longshot bias in the place dimension. The marginal place
#' probability returned for horse \eqn{j} is
#' \eqn{P(j\,1\text{st}) + P(j\,2\text{nd}) + P(j\,3\text{rd})}.
#'
#' @param market_probs Tibble with `race_id`, `horse_ref`, and
#'   `market_prob` (the over-round-adjusted SP win probability, summing to
#'   one within each race) — as produced by `build_test_predictions()`.
#' @param alpha_2nd Discount exponent on the second-place conditional
#'   (default 0.80, Lo & Bacon-Shone's recommended value for
#'   SP-derived inputs).
#' @param alpha_3rd Discount exponent on the third-place conditional
#'   (default 0.65).
#' @return Tibble with `race_id`, `horse_ref`, and `harville_place_prob`
#'   (marginal probability of a top-3 finish).
compute_harville_place_probs <- function(market_probs,
                                         alpha_2nd = 0.80,
                                         alpha_3rd = 0.65) {
  # Discounted-Harville top-3 marginal for a single race's win-prob vector.
  one_race <- function(p) {
    n <- length(p)
    if (n < 3L) return(rep(1, n))   # fewer than 3 runners: all place
    q2 <- p^alpha_2nd
    q3 <- p^alpha_3rd
    place <- numeric(n)
    for (j in seq_len(n)) {
      p1 <- p[j]                                   # P(j 1st)
      p2 <- 0                                      # P(j 2nd)
      for (i in seq_len(n)) {
        if (i == j) next
        p2 <- p2 + p[i] * q2[j] / sum(q2[-i])
      }
      p3 <- 0                                      # P(j 3rd)
      for (i in seq_len(n)) {
        if (i == j) next
        denom2_i <- sum(q2[-i])
        for (m in seq_len(n)) {
          if (m == i || m == j) next
          p3 <- p3 + p[i] * (q2[m] / denom2_i) * (q3[j] / sum(q3[-c(i, m)]))
        }
      }
      place[j] <- p1 + p2 + p3
    }
    place
  }

  market_probs |>
    dplyr::group_by(race_id) |>
    dplyr::mutate(harville_place_prob = one_race(market_prob)) |>
    dplyr::ungroup() |>
    dplyr::select(race_id, horse_ref, harville_place_prob)
}

#' Discounted-Harville probability of ordered finishing tuples (paper 2b)
#'
#' The single Harville / Plackett–Luce *order*-probability formula, shared by
#' every paper-2b consumer (the P1_rank order metric and the exacta / trifecta
#' value backtests) so the discounting logic lives in exactly one place.
#' Vectorised over a set of ordered index tuples *within one race*: given the
#' race's win-probability vector `p` and equal-length index vectors picking
#' the 1st (`i1`), 2nd (`i2`) and optionally 3rd (`i3`) finisher of each tuple,
#' returns the sequential-conditional probability
#' \eqn{\frac{p_{i_1}}{S}\cdot\frac{q^{(2)}_{i_2}}{S_{q2}-q^{(2)}_{i_1}}\cdot
#' \frac{q^{(3)}_{i_3}}{S_{q3}-q^{(3)}_{i_1}-q^{(3)}_{i_2}}}, where
#' \eqn{S=\sum_k p_k}, \eqn{q^{(m)}=p^{\alpha_m}} and the denominators are the
#' field strength not yet placed. `i3 = NULL` gives the depth-2 (exacta)
#' truncation. With `alpha_2nd = alpha_3rd = 1` this is the pure
#' PL / Harville order probability; `alpha < 1` the Lo & Bacon-Shone
#' discounted form.
#'
#' @param p Numeric win-probability vector for one race (summing to one).
#' @param i1,i2 Integer index vectors (into `p`) of the 1st / 2nd finishers.
#' @param i3 Integer index vector of the 3rd finisher, or `NULL` for depth-2.
#' @param alpha_2nd,alpha_3rd Discount exponents on the 2nd / 3rd conditionals.
#' @return Numeric vector of order probabilities, one per input tuple.
harville_order_probs_vec <- function(p, i1, i2, i3 = NULL,
                                     alpha_2nd = 0.80, alpha_3rd = 0.65) {
  q2  <- p^alpha_2nd
  S   <- sum(p)
  Sq2 <- sum(q2)
  out <- (p[i1] / S) * (q2[i2] / (Sq2 - q2[i1]))
  if (!is.null(i3)) {
    q3  <- p^alpha_3rd
    Sq3 <- sum(q3)
    out <- out * (q3[i3] / (Sq3 - q3[i1] - q3[i2]))
  }
  out
}

#' Plackett–Luce probability of the observed top-3 order (paper 2b)
#'
#' Per race, the depth-3 Plackett–Luce probability of the observed top-3
#' finishing order, built from a win-probability vector via the sequential
#' conditional (Harville) form (the shared `harville_order_probs_vec()`
#' applied to the single observed tuple). With `alpha_2nd = alpha_3rd = 1`
#' this is the pure PL / Harville order probability — the exploded model's own
#' depth-3 likelihood; `alpha < 1` gives the Lo & Bacon-Shone discounted form,
#' used for the paper-2b market baseline.
#'
#' Only races with a clean top-3 (positions 1, 2, 3 each present exactly
#' once) are scored; any other race is dropped (returns no row). This is the
#' same race condition the exploded fit imposes.
#'
#' @param predictions Tibble, one row per runner-race: `race_id`,
#'   `win_prob` (model- or market-implied win probability, summing to one
#'   within race) and `finish_pos` (integer; 1/2/3 mark the observed order).
#' @param alpha_2nd,alpha_3rd Discount exponents on the 2nd / 3rd
#'   conditionals (default 1 = pure PL/Harville order probability).
#' @return Tibble, one row per scored race: `race_id`, `order_prob`.
compute_pl_order_probs <- function(predictions, alpha_2nd = 1, alpha_3rd = 1) {
  predictions |>
    dplyr::group_by(race_id) |>
    dplyr::summarise(
      order_prob = {
        p  <- win_prob
        f  <- finish_pos
        i1 <- which(f == 1L); i2 <- which(f == 2L); i3 <- which(f == 3L)
        if (length(i1) != 1L || length(i2) != 1L || length(i3) != 1L) {
          NA_real_
        } else {
          harville_order_probs_vec(p, i1, i2, i3,
                                   alpha_2nd = alpha_2nd, alpha_3rd = alpha_3rd)
        }
      },
      .groups = "drop"
    ) |>
    dplyr::filter(!is.na(order_prob))
}

#' P1_rank: ranking discrimination on the observed top-3 order (paper 2b)
#'
#' Geometric mean, over the scored test races, of the depth-3 Plackett–Luce
#' probability assigned to the observed top-3 finishing order — computed as
#' the exponentiated mean per-race log-probability to avoid underflow:
#' \eqn{\exp\!\big(\frac{1}{n}\sum_i \log P(j_1, j_2, j_3)\big)}. Higher is
#' better. The ranking analogue of Owen's P1.
#'
#' Column contract (one row per race, the order probability pre-computed by
#' `compute_pl_order_probs()` — symmetric with `score_brier_place()`, and it
#' keeps the choice of order-probability model, e.g. pure vs discounted
#' Harville for the market baseline, in the caller rather than the metric):
#'
#' @param order_predictions Tibble with one row per scored race: `race_id`
#'   (int) and `order_prob` (dbl in (0, 1], the predicted probability of the
#'   observed top-3 finishing order under the model or market).
#' @return A scalar P1_rank.
score_p1_rank <- function(order_predictions) {
  exp(mean(log(order_predictions$order_prob)))
}

#' Brier_place: place-market calibration (paper 2b)
#'
#' Mean squared error between the predicted top-3 (place) probability and
#' the binary place outcome, over all runner-race observations in the test
#' set: \eqn{\frac{1}{N}\sum_{i,j}(\text{place}_{ij} - p_{ij})^2}. Lower is
#' better; a proper scoring rule. The place analogue of Owen's P2.
#'
#' Generic by design: the caller supplies `place_prob` — discounted-Harville
#' from market win probabilities (via `compute_harville_place_probs()`), or
#' pure-Harville (\eqn{\alpha = 1}) from model win probabilities — so model
#' and market are scored on the identical metric and compared directly.
#'
#' @param place_predictions Tibble, one row per runner-race: `placed`
#'   (int 0/1, 1 if the horse finished top-3) and `place_prob` (dbl in
#'   \eqn{[0, 1]}, the predicted probability of a top-3 finish).
#' @return A scalar Brier_place.
score_brier_place <- function(place_predictions) {
  mean((place_predictions$placed - place_predictions$place_prob)^2)
}

#' Paired race-level bootstrap of the ROI *difference* between two models
#'
#' The marginal ROI bootstrap CIs of two models cannot tell us whether
#' their ROIs differ, because the two are evaluated on the same races and
#' are therefore correlated. This resamples races once per replicate and
#' computes both models' ROI on that *same* resample, so the difference is
#' paired and the correlation cancels.
#'
#' The two models are first restricted to their **common** race set
#' (intersection of `race_id`), because different feature sets drop
#' different test races to NA (e.g. paper 1's 2,224 test races vs paper
#' 2a's 2,193). Owen's naive rule — `model_prob > prob_threshold` and
#' `ratio > ratio_threshold` — selects bets per model; a winning unit
#' stake returns the decimal starting price. ROI is `(gross − stake) /
#' stake`; the difference is model A minus model B.
#'
#' @param ratio_df_a,ratio_df_b Model/market ratio tibbles (as produced by
#'   `compute_model_market_ratio()` / `compute_model_market_ratio_p2()`),
#'   each with `race_id`, `model_prob`, `ratio`, `won`,
#'   `starting_price_decimal`.
#' @param prob_threshold,ratio_threshold Owen's naive bet-selection
#'   thresholds (0.15 and 1.3).
#' @param n_boot Number of race-level resamples (default 2000).
#' @param seed RNG seed (default 42).
#' @return One-row tibble: `diff_point` (point ROI difference, A − B),
#'   `ci_lo` / `ci_hi` (5th / 95th percentiles of the bootstrap
#'   distribution = a 90% CI), `n_common` (races in the intersection),
#'   `n_boot`.
bootstrap_roi_difference <- function(ratio_df_a, ratio_df_b,
                                     prob_threshold  = 0.15,
                                     ratio_threshold = 1.3,
                                     n_boot = 2000L, seed = 42L) {
  common <- intersect(unique(ratio_df_a$race_id), unique(ratio_df_b$race_id))

  # Per-race bet count and gross return on the common races, in a fixed
  # race order (races with no qualifying bet contribute zeros).
  per_race <- function(df) {
    bets <- df |>
      dplyr::filter(race_id %in% common,
                    model_prob > prob_threshold,
                    ratio > ratio_threshold) |>
      dplyr::mutate(
        return_unit = dplyr::if_else(won == 1L, starting_price_decimal, 0)
      ) |>
      dplyr::group_by(race_id) |>
      dplyr::summarise(n_bets = dplyr::n(),
                       gross  = sum(return_unit), .groups = "drop")
    tibble::tibble(race_id = common) |>
      dplyr::left_join(bets, by = "race_id") |>
      dplyr::mutate(dplyr::across(c(n_bets, gross), \(x) tidyr::replace_na(x, 0)))
  }

  pa <- per_race(ratio_df_a)
  pb <- per_race(ratio_df_b)
  nbets_a <- pa$n_bets; gross_a <- pa$gross
  nbets_b <- pb$n_bets; gross_b <- pb$gross
  n <- length(common)

  roi <- function(nb, gr) if (nb == 0L) NA_real_ else (gr - nb) / nb
  point <- roi(sum(nbets_a), sum(gross_a)) - roi(sum(nbets_b), sum(gross_b))

  set.seed(seed)
  diffs <- vapply(seq_len(n_boot), function(b) {
    idx <- sample.int(n, n, replace = TRUE)
    roi(sum(nbets_a[idx]), sum(gross_a[idx])) -
      roi(sum(nbets_b[idx]), sum(gross_b[idx]))
  }, numeric(1))

  tibble::tibble(
    diff_point = point,
    ci_lo      = stats::quantile(diffs, 0.05, na.rm = TRUE, names = FALSE),
    ci_hi      = stats::quantile(diffs, 0.95, na.rm = TRUE, names = FALSE),
    n_common   = n,
    n_boot     = n_boot
  )
}

#' Zero-skill SP baseline: back every test runner at SP (paper 2b context)
#'
#' Backs every runner in the test set at its starting price, flat one-unit
#' stake — no selection at all. The ROI is the structural floor any SP bettor
#' faces from the over-round alone, before skill; it is approximately
#' \eqn{-(B-1)/B} for a book summing to \eqn{B}. Used in paper 2b's discussion
#' to contextualise the win backtest's loss.
#'
#' @param test_predictions Per-runner test tibble carrying `won` and
#'   `starting_price_decimal` (e.g. `test_predictions_2b`).
#' @return One-row tibble: `n_bets`, `n_wins`, `gross_return`, `profit`, `roi`.
run_betall_win_backtest <- function(test_predictions) {
  bets <- test_predictions |>
    dplyr::filter(!is.na(starting_price_decimal), starting_price_decimal > 1)
  n     <- nrow(bets)
  gross <- sum(dplyr::if_else(bets$won == 1L, bets$starting_price_decimal, 0))
  tibble::tibble(
    n_bets       = as.integer(n),
    n_wins       = as.integer(sum(bets$won == 1L)),
    gross_return = gross,
    profit       = gross - n,
    roi          = (gross - n) / n
  )
}

#' Back-the-favourite SP baseline (paper 2b context)
#'
#' Backs the SP favourite (lowest decimal odds) in each test race at SP, flat
#' one-unit stake. Ties for favourite are broken by the lower `runner_id`, and
#' the number of tied-favourite races is reported (`n_tie_races`) so the
#' tie-handling can be judged.
#'
#' @param test_predictions As `run_betall_win_backtest()` (also needs
#'   `race_id`, `runner_id`).
#' @return One-row tibble: `n_bets`, `n_wins`, `gross_return`, `profit`, `roi`,
#'   `n_tie_races`.
run_favourite_win_backtest <- function(test_predictions) {
  fav <- test_predictions |>
    dplyr::filter(!is.na(starting_price_decimal), starting_price_decimal > 1) |>
    dplyr::group_by(race_id) |>
    dplyr::mutate(n_at_min = sum(starting_price_decimal == min(starting_price_decimal))) |>
    dplyr::arrange(starting_price_decimal, runner_id, .by_group = TRUE) |>
    dplyr::slice(1) |>
    dplyr::ungroup()
  n     <- nrow(fav)
  gross <- sum(dplyr::if_else(fav$won == 1L, fav$starting_price_decimal, 0))
  tibble::tibble(
    n_bets       = as.integer(n),
    n_wins       = as.integer(sum(fav$won == 1L)),
    gross_return = gross,
    profit       = gross - n,
    roi          = (gross - n) / n,
    n_tie_races  = as.integer(sum(fav$n_at_min > 1))
  )
}

# -- Generic value-bet backtest (paper 2b exotic markets) -------------------
# A small generalisation of run_backtest() / run_backtest_sweep() /
# bootstrap_roi() for the place / each-way / exacta / trifecta value bets,
# where the stake is not always one unit (each-way stakes two) and the gross
# return on a bet is not always `won * starting_price_decimal` (a placed
# horse, a matched pair / triple, paid at the market's Harville-derived fair
# odds). Each builder in R/value_bets_p2b.R emits a tibble of *bet units*
# with the columns these functions consume — `race_id`, `model_prob` (for the
# floor), `ratio` (model / market fair value, for selection), `stake`, and
# `ret` (the realised gross return on the bet, already 0 on a loser) — so the
# selection, ROI and race-level bootstrap logic stays in one place.

#' Single-threshold value-bet backtest (paper 2b)
#'
#' Selects bet units with `model_prob > prob_floor` AND `ratio >
#' ratio_threshold`, then computes ROI = `(sum(ret) - sum(stake)) /
#' sum(stake)`. The `prob_floor` is a model-probability floor that screens out
#' near-impossible combinations (load-bearing for trifecta, where most ordered
#' triples have tiny probability and the ratio is dominated by estimation
#' noise).
#'
#' @param bet_df Tibble of bet units: `race_id`, `model_prob`, `ratio`,
#'   `stake`, `ret`.
#' @param prob_floor Lower bound on the model probability of the bet.
#' @param ratio_threshold Lower bound on the model / market fair-value ratio.
#' @return One-row tibble: `prob_floor`, `ratio_threshold`, `n_bets`,
#'   `n_wins`, `total_stake`, `gross_return`, `profit`, `roi` (NA if no bets).
run_value_backtest <- function(bet_df, prob_floor, ratio_threshold) {
  bets <- bet_df |>
    dplyr::filter(model_prob > prob_floor, ratio > ratio_threshold)

  n_bets <- nrow(bets)

  if (n_bets == 0L) {
    return(tibble::tibble(
      prob_floor      = prob_floor,
      ratio_threshold = ratio_threshold,
      n_bets          = 0L,
      n_wins          = 0L,
      total_stake     = 0,
      gross_return    = 0,
      profit          = 0,
      roi             = NA_real_
    ))
  }

  total_stake  <- sum(bets$stake)
  gross_return <- sum(bets$ret)
  profit       <- gross_return - total_stake

  tibble::tibble(
    prob_floor      = prob_floor,
    ratio_threshold = ratio_threshold,
    n_bets          = as.integer(n_bets),
    n_wins          = as.integer(sum(bets$ret > 0)),
    total_stake     = total_stake,
    gross_return    = gross_return,
    profit          = profit,
    roi             = profit / total_stake
  )
}

#' Race-level bootstrap of value-bet ROI at one threshold (paper 2b)
#'
#' Resamples races (not bet units) with replacement, summing stake and return
#' per race so the within-race correlation is preserved, exactly as
#' `bootstrap_roi()` does for the win backtest.
#'
#' @param bet_df,prob_floor,ratio_threshold As `run_value_backtest()`.
#' @param n_boot Number of resamples (default 2000).
#' @return Numeric vector of `n_boot` bootstrap ROI replicates (NA where a
#'   draw selects zero stake).
bootstrap_value_roi <- function(bet_df, prob_floor, ratio_threshold,
                                n_boot = 2000L) {
  per_race <- bet_df |>
    dplyr::filter(model_prob > prob_floor, ratio > ratio_threshold) |>
    dplyr::group_by(race_id) |>
    dplyr::summarise(stake = sum(stake), ret = sum(ret), .groups = "drop")

  if (nrow(per_race) == 0L) return(rep(NA_real_, n_boot))

  stake_vec <- per_race$stake
  ret_vec   <- per_race$ret
  n_races   <- nrow(per_race)

  vapply(seq_len(n_boot), function(b) {
    idx <- sample.int(n_races, size = n_races, replace = TRUE)
    st  <- sum(stake_vec[idx])
    if (st == 0) return(NA_real_)
    (sum(ret_vec[idx]) - st) / st
  }, numeric(1))
}

#' Bootstrap-CI value-bet ROI sweep across ratio thresholds (paper 2b)
#'
#' The exotic-market analogue of `run_backtest_sweep()`: for each `tau` in
#' `tau_seq`, the point ROI plus a `n_boot`-replicate race-level bootstrap
#' (5th / 95th percentiles = a 90% CI), the model-probability floor held
#' fixed. Seed set once so the whole sweep is reproducible.
#'
#' @param bet_df Tibble of bet units (see `run_value_backtest()`).
#' @param prob_floor Model-probability floor, held fixed across the sweep.
#' @param tau_seq Numeric vector of ratio thresholds.
#' @param n_boot,seed Bootstrap replicate count and RNG seed.
#' @return Long tibble: `tau`, `n_bets`, `n_wins`, `total_stake`, `roi`,
#'   `ci_lo`, `ci_hi`.
run_value_backtest_sweep <- function(bet_df, prob_floor, tau_seq,
                                     n_boot = 2000L, seed = 42L) {
  set.seed(seed)

  point <- purrr::map_dfr(tau_seq, \(tau) {
    run_value_backtest(bet_df, prob_floor = prob_floor, ratio_threshold = tau) |>
      dplyr::transmute(tau = tau, n_bets, n_wins, total_stake, roi)
  })

  ci <- purrr::map_dfr(tau_seq, \(tau) {
    boot <- bootstrap_value_roi(bet_df, prob_floor = prob_floor,
                                ratio_threshold = tau, n_boot = n_boot)
    tibble::tibble(
      tau   = tau,
      ci_lo = stats::quantile(boot, 0.05, na.rm = TRUE, names = FALSE),
      ci_hi = stats::quantile(boot, 0.95, na.rm = TRUE, names = FALSE)
    )
  })

  dplyr::left_join(point, ci, by = "tau")
}
