# gbt_results.R
# Paper-3 results-pass / diagnostics helpers, wired as pure functions for
# _targets.R (mirrors the logic originally run ad hoc in
# scripts/run_results_pass.R and scripts/run_diagnostics_pass{2,3,4}.R, so
# `tar_make()` from clean reproduces those same numbers as targets rather
# than as one-off script output). Test-split functions here are only ever
# called on the test split from _targets.R; nothing in this file enforces
# that itself (same convention as R/scoring.R and R/ranking_eval_p2b.R).

#' Race-level feature names in paper 3's FEATURE_COLS (R/gbt_data.R)
#'
#' Split into race-level (constant within every race: today's going, which
#' course) and horse-level (varies within a race) — the distinction that
#' decides which permutation-importance null applies to each feature (see
#' `permutation_importance_within_race()` / `permutation_importance_across_races()`
#' in R/gbt_tuning.R).
#' @format Character vectors.
RACE_LEVEL_FEATS_3 <- c("going_ordinal", "course_Kempton", "course_Lingfield",
                         "course_Southwell", "course_Wolverhampton")
HORSE_LEVEL_FEATS_3 <- setdiff(FEATURE_COLS, RACE_LEVEL_FEATS_3)

#' Gate: paper 3's test race universe must exactly match paper 2b's ranking universe
#'
#' A depth-3 model needs a clean top-3 (`prepare_exploded_data()`'s
#' requirement), so paper 3's test build can only ever use paper 2b's
#' RANKING universe (`ranking_eval_runners_2b`, 2,183 races), not its larger
#' win-only backtest universe (`test_predictions_2b`, 2,193 races) -- see
#' CLAUDE.md "Two test universes exist for paper 2b". `stopifnot()`s rather
#' than returning a logical so a mismatch halts the pipeline at this target
#' with a clear error, the same behaviour `scripts/run_results_pass.R`'s
#' Stage A gate had as a standalone script.
#'
#' @param gbt_test_data Output of `build_gbt_matrix(..., "test")`.
#' @param ranking_eval_runners_2b The `ranking_eval_runners_2b` target.
#' @return TRUE, invisibly, if the check passes (only called for its
#'   assertion side effect).
check_gbt_race_universe <- function(gbt_test_data, ranking_eval_runners_2b) {
  p3_races <- unique(gbt_test_data$key$race_id)
  b2_races <- unique(ranking_eval_runners_2b$race_id)
  stopifnot(
    "paper 3 test race count must equal paper 2b's ranking universe" =
      length(p3_races) == length(b2_races),
    "paper 3 test races must be identical to paper 2b's ranking universe" =
      length(setdiff(p3_races, b2_races)) == 0L,
    length(setdiff(b2_races, p3_races)) == 0L
  )
  invisible(TRUE)
}

#' Assemble paper-3 test predictions on paper 2b's runner interface
#'
#' Turns the GBT's raw margin scores into within-race softmax win
#' probabilities, then joins on `won` / `win_market` / `starting_price_decimal`
#' from paper 2b's own test predictions (safe once `check_gbt_race_universe()`
#' has confirmed the two race sets are identical).
#'
#' @param margin Numeric vector, GBT `predict(..., outputmargin = TRUE)`
#'   output, `gbt_test_data$key` row order.
#' @param gbt_test_data Output of `build_gbt_matrix(..., "test")`.
#' @param test_predictions_2b The `test_predictions_2b` target.
#' @return Tibble: `race_id`, `runner_id`, `horse_ref`, `win_model`, `won`,
#'   `win_market`, `starting_price_decimal`.
build_test_predictions_3 <- function(margin, gbt_test_data, test_predictions_2b) {
  softmax_test <- pl_softmax_by_race(margin, gbt_test_data$key$race_id, gbt_test_data$key$runner_id)
  psum <- softmax_test |> dplyr::group_by(race_id) |> dplyr::summarise(s = sum(p_win), .groups = "drop")
  stopifnot(all(abs(psum$s - 1) < 1e-6))

  out <- softmax_test |>
    dplyr::rename(win_model = p_win) |>
    dplyr::inner_join(
      test_predictions_2b |>
        dplyr::select(race_id, runner_id, horse_ref, won, win_market, starting_price_decimal),
      by = c("race_id", "runner_id")
    )
  stopifnot(nrow(out) == nrow(softmax_test))
  out
}

#' Per-race ranking ingredients for one model's scores (paired bootstrap infra)
#'
#' `order_prob` (P1_rank ingredient), `sse`/`n_r` (Brier_place ingredient),
#' and, when a z/margin scale is supplied, `ll`/`nll` (test pl_r2 ingredient)
#' -- the three per-race statistics `bootstrap_ranking_metrics()` resamples
#' together, preserving within-race structure exactly as
#' `bootstrap_roi_difference()` does for ROI. An arm with no natural z scale
#' (the market) gets `ll`/`nll` set to `NA`, which
#' `bootstrap_ranking_metrics()` reads as "no pl_r2 comparison for this arm".
#'
#' @param rer A ranking-eval-runners tibble (`build_ranking_eval_runners()`
#'   output): `race_id`, `horse_ref`, `finish_pos`, `placed`, and a
#'   win-probability column named `win_col`.
#' @param win_col Name of the win-probability column in `rer` to score.
#' @param alpha_2nd,alpha_3rd Harville discount exponents (1/1 = pure
#'   Harville, a model's own PL implication; 0.80/0.65 = the Lo &
#'   Bacon-Shone market baseline).
#' @param z,group_sizes,race_ids_ordered Optional: this arm's scores on the
#'   z (margin) scale, `arrange_for_xgb()` order, plus the matching
#'   race-group sizes and per-race-block race ids (`rle()$lengths` /
#'   `rle()$values` on the same ordering) -- needed only for the `ll`/`nll`
#'   pl_r2 ingredient.
#' @param k Plackett-Luce depth.
#' @return Tibble: `race_id`, `order_prob`, `sse`, `n_r`, `ll`, `nll`.
build_ranking_per_race <- function(rer, win_col, alpha_2nd = 1, alpha_3rd = 1,
                                    z = NULL, group_sizes = NULL,
                                    race_ids_ordered = NULL, k = 3L) {
  op <- rer |>
    dplyr::transmute(race_id, win_prob = .data[[win_col]], finish_pos) |>
    compute_pl_order_probs(alpha_2nd = alpha_2nd, alpha_3rd = alpha_3rd)

  pp <- compute_harville_place_probs(
    rer |> dplyr::transmute(race_id, horse_ref, market_prob = .data[[win_col]]),
    alpha_2nd = alpha_2nd, alpha_3rd = alpha_3rd
  )
  br <- rer |>
    dplyr::left_join(pp, by = c("race_id", "horse_ref")) |>
    dplyr::group_by(race_id) |>
    dplyr::summarise(sse = sum((placed - harville_place_prob)^2), n_r = dplyr::n(), .groups = "drop")

  out <- op |> dplyr::left_join(br, by = "race_id")

  if (!is.null(z)) {
    pc <- pl_race_contributions(z, group_sizes, race_ids_ordered, k = k)
    out <- out |> dplyr::left_join(pc, by = "race_id")
  } else {
    out$ll  <- NA_real_
    out$nll <- NA_real_
  }
  out
}

#' Per-race Plackett-Luce log-likelihood and null log-likelihood
#'
#' The `pl_r2` ingredient at race grain: `ll` (this race's contribution to
#' the model log-likelihood, from `pl_denom()`) and `nll` (this race's
#' contribution to the null/chance log-likelihood, the same closed form
#' `make_pl_eval()` uses). Kept separate from `make_pl_eval()` because that
#' function returns only the AGGREGATE `pl_r2`; the paired bootstrap needs
#' the per-race pieces so it can resample races and recompute
#' `1 - sum(ll)/sum(nll)` on each resample.
#'
#' @param z Numeric vector, scores on the margin scale, `arrange_for_xgb()`
#'   order.
#' @param group_sizes Integer vector, per-race field sizes, same order.
#' @param race_ids_ordered Vector, one race id per race-block (i.e.
#'   `rle(...)$values` on the same ordering as `group_sizes`).
#' @param k Plackett-Luce depth.
#' @return Tibble: `race_id`, `ll`, `nll`.
pl_race_contributions <- function(z, group_sizes, race_ids_ordered, k = 3L) {
  d <- pl_denom(z, group_sizes, k)
  stage_term  <- ifelse(d$pos <= d$S, d$zc - base::log(d$denom), 0)
  ll_by_race  <- as.numeric(tapply(stage_term, d$race, sum))
  J <- group_sizes; S <- pmin(k, J - 1L)
  nll_by_race <- vapply(seq_along(J), function(i) {
    j <- J[i]; s <- S[i]
    if (s < 1L) return(0)
    -sum(base::log(j - (seq_len(s) - 1L)))
  }, numeric(1))
  tibble::tibble(race_id = race_ids_ordered, ll = ll_by_race, nll = nll_by_race)
}

#' Paired race-level bootstrap of a ranking-metric difference between two models
#'
#' Restricts to the two arms' common race set (inner join on `race_id`),
#' then resamples races with replacement (preserving within-race
#' structure), recomputing all three metrics on each resample -- the same
#' convention `bootstrap_roi_difference()` uses for ROI. If either arm lacks
#' the `ll`/`nll` pl_r2 ingredient (e.g. the market arm), the `test_pl_r2`
#' row is `NA` throughout rather than omitted, so every contrast returns the
#' same three-metric shape.
#'
#' @param per_race_a,per_race_b Output of `build_ranking_per_race()` for
#'   each arm ("a" is conventionally the paper-3 GBT in this pipeline).
#' @param label Contrast label, stored in the `contrast` column.
#' @param n_boot,seed Bootstrap replicates and RNG seed (2000 / 42, the
#'   series-wide convention).
#' @return Tibble, one row per metric (`P1_rank`, `Brier_place`,
#'   `test_pl_r2`): `contrast`, `metric`, `point_a`, `point_b`,
#'   `diff_point`, `ci_lo`, `ci_hi`, `n_races`, `n_boot`.
bootstrap_ranking_metrics <- function(per_race_a, per_race_b, label,
                                       n_boot = 2000L, seed = 42L) {
  per_race <- dplyr::inner_join(per_race_a, per_race_b, by = "race_id", suffix = c("_a", "_b"))
  n <- nrow(per_race)
  has_pl <- !anyNA(per_race$ll_a) && !anyNA(per_race$ll_b)

  metric_stats <- function(idx) {
    p1_a <- exp(mean(base::log(per_race$order_prob_a[idx])))
    p1_b <- exp(mean(base::log(per_race$order_prob_b[idx])))
    br_a <- sum(per_race$sse_a[idx]) / sum(per_race$n_r_a[idx])
    br_b <- sum(per_race$sse_b[idx]) / sum(per_race$n_r_b[idx])
    if (has_pl) {
      pl_a <- 1 - sum(per_race$ll_a[idx]) / sum(per_race$nll_a[idx])
      pl_b <- 1 - sum(per_race$ll_b[idx]) / sum(per_race$nll_b[idx])
    } else {
      pl_a <- NA_real_; pl_b <- NA_real_
    }
    c(p1_a, p1_b, br_a, br_b, pl_a, pl_b)
  }

  # Only the metrics that are actually defined for both arms get bootstrap
  # replicates -- an arm with no z scale (e.g. the market) has no pl_r2
  # ingredient, and quantile() errors on an all-NA column. That row's
  # ci_lo/ci_hi (and point/diff, from metric_stats() above) stay NA
  # instead, rather than being computed over nothing.
  point <- metric_stats(seq_len(n))
  n_boot_metrics <- if (has_pl) 3L else 2L
  set.seed(seed)
  diffs <- matrix(NA_real_, nrow = n_boot, ncol = n_boot_metrics)
  for (b in seq_len(n_boot)) {
    idx <- sample.int(n, n, replace = TRUE)
    s <- metric_stats(idx)
    diffs[b, 1] <- s[1] - s[2]
    diffs[b, 2] <- s[3] - s[4]
    if (has_pl) diffs[b, 3] <- s[5] - s[6]
  }
  ci <- apply(diffs, 2, stats::quantile, probs = c(0.05, 0.95), names = FALSE)
  ci_lo <- c(ci[1, 1], ci[1, 2], if (has_pl) ci[1, 3] else NA_real_)
  ci_hi <- c(ci[2, 1], ci[2, 2], if (has_pl) ci[2, 3] else NA_real_)

  tibble::tibble(
    contrast   = label,
    metric     = c("P1_rank", "Brier_place", "test_pl_r2"),
    point_a    = c(point[1], point[3], point[5]),
    point_b    = c(point[2], point[4], point[6]),
    diff_point = c(point[1] - point[2], point[3] - point[4], point[5] - point[6]),
    ci_lo      = ci_lo,
    ci_hi      = ci_hi,
    n_races    = n, n_boot = n_boot
  )
}

#' Align paper 2b's implied z scores to a paper-3 row key
#'
#' Paper 2b's z (`log(win_model)`) is only defined where `win_model > 0`.
#' Returns an INNER join (not a left join returning `NA`s) so downstream
#' callers (`compute_score_agreement()`, `build_disagreement_set()`) never
#' silently see an unaligned row.
#'
#' @param test_predictions_2b The `test_predictions_2b` target.
#' @param key A tibble with `race_id`, `runner_id` columns (e.g.
#'   `gbt_test_data$key`).
#' @return Tibble: `race_id`, `runner_id`, `z_2b`.
align_2b_z_to_key <- function(test_predictions_2b, key) {
  z2b <- test_predictions_2b |>
    dplyr::filter(!is.na(win_model), win_model > 0) |>
    dplyr::transmute(race_id, runner_id, z_2b = base::log(win_model))
  dplyr::inner_join(key, z2b, by = c("race_id", "runner_id"))
}

#' Score agreement between two models' within-race-centred z scores
#'
#' Centres each model's scores within race first (the PL softmax is
#' translation-invariant within a race, so raw z levels aren't comparable
#' across models), then reports Pearson/Spearman correlation, the share of
#' races where both models pick the same top horse, and the mean absolute
#' within-race rank difference.
#'
#' @param race_id,runner_id,z_a,z_b Equal-length vectors, one row per
#'   runner: race id, runner id, and each model's z score for that runner.
#' @return A list: `pearson_r`, `spearman_r`, `share_same_top`, `n_races`,
#'   `mad_rank`, `top_pick` (tibble: `race_id`, `top_a`, `top_b`,
#'   `same_top`).
compute_score_agreement <- function(race_id, runner_id, z_a, z_b) {
  agree <- tibble::tibble(race_id = race_id, runner_id = runner_id, z_a = z_a, z_b = z_b) |>
    dplyr::group_by(race_id) |>
    dplyr::mutate(
      zc_a = z_a - mean(z_a), zc_b = z_b - mean(z_b),
      rank_a = rank(-z_a, ties.method = "first"),
      rank_b = rank(-z_b, ties.method = "first")
    ) |>
    dplyr::ungroup()

  pearson_r  <- stats::cor(agree$zc_a, agree$zc_b, method = "pearson")
  spearman_r <- stats::cor(agree$zc_a, agree$zc_b, method = "spearman")

  top_pick <- agree |>
    dplyr::group_by(race_id) |>
    dplyr::summarise(
      top_a = runner_id[which.max(z_a)],
      top_b = runner_id[which.max(z_b)],
      .groups = "drop"
    ) |>
    dplyr::mutate(same_top = top_a == top_b)

  list(
    pearson_r = pearson_r, spearman_r = spearman_r,
    share_same_top = mean(top_pick$same_top), n_races = nrow(top_pick),
    mad_rank = mean(abs(agree$rank_a - agree$rank_b)),
    top_pick = top_pick
  )
}

#' Disagreement-set analysis: races where two models pick a different top horse
#'
#' For each race, each model's single highest-z pick, its starting price and
#' whether it won; then splits into the agreement / disagreement set and
#' summarises win rate and SP within each.
#'
#' @param race_id,runner_id,z_a,z_b As `compute_score_agreement()`.
#' @param starting_price_decimal,won Vectors, same row order as `race_id`.
#' @return A list: `n_disagree`, `n_total`, `win_rate_a_dis`, `win_rate_b_dis`,
#'   `sp_summary` (tibble: `model`, `mean_sp`, `median_sp`, overall and
#'   disagreement-set rows for each arm), `picks` (per-race pick tibble,
#'   with a `disagree` flag, for downstream bootstrapping).
build_disagreement_set <- function(race_id, runner_id, z_a, z_b,
                                    starting_price_decimal, won) {
  base <- tibble::tibble(race_id = race_id, runner_id = runner_id, z_a = z_a, z_b = z_b,
                          sp = starting_price_decimal, won = won)

  pick_one <- function(zcol) {
    base |>
      dplyr::group_by(race_id) |>
      dplyr::slice_max(.data[[zcol]], n = 1, with_ties = FALSE) |>
      dplyr::ungroup() |>
      dplyr::select(race_id, runner_id, sp, won)
  }
  pick_a <- pick_one("z_a"); pick_b <- pick_one("z_b")

  picks <- dplyr::inner_join(pick_a, pick_b, by = "race_id", suffix = c("_a", "_b")) |>
    dplyr::mutate(disagree = runner_id_a != runner_id_b)

  dis <- dplyr::filter(picks, disagree)
  win_rate_a_dis <- mean(dis$won_a == 1L, na.rm = TRUE)
  win_rate_b_dis <- mean(dis$won_b == 1L, na.rm = TRUE)

  sp_summary <- tibble::tibble(
    model = c("A (overall)", "B (overall)", "A (disagreement set)", "B (disagreement set)"),
    mean_sp = c(mean(picks$sp_a, na.rm = TRUE), mean(picks$sp_b, na.rm = TRUE),
                mean(dis$sp_a, na.rm = TRUE),   mean(dis$sp_b, na.rm = TRUE)),
    median_sp = c(stats::median(picks$sp_a, na.rm = TRUE), stats::median(picks$sp_b, na.rm = TRUE),
                  stats::median(dis$sp_a, na.rm = TRUE),   stats::median(dis$sp_b, na.rm = TRUE))
  )

  list(n_disagree = sum(picks$disagree), n_total = nrow(picks),
       win_rate_a_dis = win_rate_a_dis, win_rate_b_dis = win_rate_b_dis,
       sp_summary = sp_summary, picks = picks)
}

#' Bootstrap the disagreement-set win-rate and mean-SP differences
#'
#' @param disagreement_set Output of `build_disagreement_set()`.
#' @param n_boot,seed Bootstrap replicates and RNG seed (2000 / 42).
#' @return A list: `winrate_diff_point`, `winrate_ci`, `sp_diff_point`,
#'   `sp_ci`, `n_dis`.
bootstrap_disagreement_diff <- function(disagreement_set, n_boot = 2000L, seed = 42L) {
  dis <- dplyr::filter(disagreement_set$picks, disagree)
  n_dis <- nrow(dis)
  won_a <- as.numeric(dis$won_a == 1L); won_b <- as.numeric(dis$won_b == 1L)
  sp_a <- dis$sp_a; sp_b <- dis$sp_b

  set.seed(seed)
  boot_winrate_diff <- numeric(n_boot)
  boot_sp_diff <- numeric(n_boot)
  for (b in seq_len(n_boot)) {
    idx <- sample.int(n_dis, n_dis, replace = TRUE)
    boot_winrate_diff[b] <- mean(won_a[idx]) - mean(won_b[idx])
    boot_sp_diff[b] <- mean(sp_a[idx], na.rm = TRUE) - mean(sp_b[idx], na.rm = TRUE)
  }

  list(
    winrate_diff_point = mean(won_a) - mean(won_b),
    winrate_ci = stats::quantile(boot_winrate_diff, c(0.05, 0.95), names = FALSE),
    sp_diff_point = mean(sp_a, na.rm = TRUE) - mean(sp_b, na.rm = TRUE),
    sp_ci = stats::quantile(boot_sp_diff, c(0.05, 0.95), names = FALSE),
    n_dis = n_dis
  )
}

#' Partial dependence (mean margin) over a feature's quantile grid
#'
#' @param bst Fitted `xgb.Booster`.
#' @param X Feature matrix (`build_gbt_matrix()` column order).
#' @param feature Column name in `X` to vary.
#' @param n_grid Number of quantile points (default 25; duplicates from
#'   coincident quantiles are dropped).
#' @return Tibble: `feature`, `value`, `mean_z`.
compute_partial_dependence <- function(bst, X, feature, n_grid = 25) {
  vals <- X[, feature]
  grid <- stats::quantile(vals, probs = seq(0, 1, length.out = n_grid), na.rm = TRUE, names = FALSE)
  grid <- unique(grid)
  purrr::map_dfr(grid, function(v) {
    Xg <- X
    Xg[, feature] <- v
    preds <- predict(bst, Xg, outputmargin = TRUE)
    tibble::tibble(feature = feature, value = v, mean_z = mean(preds))
  })
}
