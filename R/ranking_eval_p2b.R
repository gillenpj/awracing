# ranking_eval_p2b.R
# Paper-2b ranking evaluation: assemble the test-set runner data needed for
# the ranking metrics, then score the final exploded model against the
# discounted-Harville market baseline on P1_rank and Brier_place.
#
# Pure functions (inputs -> outputs, no side effects); wired into
# _targets.R as their own targets. Test-split only — the win probabilities
# come from build_test_predictions() on the held-out races, mirroring the
# mlogit_test_data_interactions pattern used by paper 2a.

#' Assemble the per-runner-race ranking-evaluation tibble (paper 2b)
#'
#' Joins finishing positions onto the test-set win-probability predictions,
#' flags the binary place outcome, and keeps only the races that can be
#' scored: those with (a) a complete, strictly-positive model **and** market
#' win-probability vector (the Harville recursion needs a full field summing
#' to one), and (b) a clean top-3 (finishing positions 1, 2, 3 each present
#' exactly once). Finishing position uses the project-wide
#' `coalesce(amended_position, finish_position)`.
#'
#' @param test_predictions_2b The final-model test predictions, one row per
#'   runner-race, carrying `race_id`, `runner_id`, `horse_ref`, `won`,
#'   `win_model` (model win prob) and `win_market` (over-round-adjusted SP
#'   win prob).
#' @param qualifying_runners Runner-level tibble supplying `finish_position`
#'   and `amended_position`.
#' @return A tibble (subset of `test_predictions_2b` rows) with
#'   `race_id`, `horse_ref`, `won`, `win_model`, `win_market`,
#'   `finish_pos`, `placed` (1 if top-3), restricted to scorable races.
build_ranking_eval_runners <- function(test_predictions_2b, qualifying_runners) {
  fp <- qualifying_runners |>
    dplyr::transmute(
      race_id, runner_id,
      finish_pos = dplyr::coalesce(amended_position, finish_position)
    )

  base <- test_predictions_2b |>
    dplyr::left_join(fp, by = c("race_id", "runner_id")) |>
    dplyr::mutate(placed = as.integer(!is.na(finish_pos) & finish_pos %in% 1:3))

  scorable <- base |>
    dplyr::group_by(race_id) |>
    dplyr::summarise(
      complete  = all(!is.na(win_model)  & win_model  > 0 &
                      !is.na(win_market) & win_market > 0),
      cleantop3 = setequal(intersect(finish_pos, 1:3), 1:3) &&
                  sum(finish_pos %in% 1:3, na.rm = TRUE) == 3L,
      .groups = "drop"
    ) |>
    dplyr::filter(complete, cleantop3) |>
    dplyr::pull(race_id)

  base |>
    dplyr::filter(race_id %in% scorable) |>
    dplyr::select(race_id, horse_ref, won, win_model, win_market,
                  finish_pos, placed)
}

#' Score the final exploded model vs the Harville market baseline (paper 2b)
#'
#' Computes P1_rank (depth-3 PL order discrimination) and Brier_place (top-3
#' calibration) for both the model and the market, on the scorable test
#' races from `build_ranking_eval_runners()`.
#'
#' * Order probabilities (for P1_rank) use pure PL/Harville
#'   (\eqn{\alpha = 1}) for both model and market — the paper-2b spec for the
#'   order metric.
#' * Place probabilities (for Brier_place) use pure Harville
#'   (\eqn{\alpha = 1}) on the **model** win probs (the exploded model's own
#'   PL place implication) and discounted Harville (`alpha_2nd`,
#'   `alpha_3rd`) on the **market** win probs (the Lo & Bacon-Shone
#'   baseline).
#'
#' @param ranking_eval_runners_2b Output of `build_ranking_eval_runners()`.
#' @param alpha_2nd,alpha_3rd Market place-probability discount exponents
#'   (defaults 0.80 / 0.65).
#' @return A tibble, one row per metric: `metric` ("P1_rank" /
#'   "Brier_place"), `model`, `market`, `n_races`, `n_runners`. P1_rank:
#'   higher is better; Brier_place: lower is better.
compute_ranking_metrics_2b <- function(ranking_eval_runners_2b,
                                        alpha_2nd = 0.80, alpha_3rd = 0.65) {
  er <- ranking_eval_runners_2b

  # --- P1_rank: order probabilities (pure Harville, alpha = 1, both sides)
  ord_model <- compute_pl_order_probs(
    er |> dplyr::transmute(race_id, win_prob = win_model, finish_pos)
  )
  ord_market <- compute_pl_order_probs(
    er |> dplyr::transmute(race_id, win_prob = win_market, finish_pos)
  )
  p1_model  <- score_p1_rank(ord_model)
  p1_market <- score_p1_rank(ord_market)

  # --- Brier_place: place probabilities (model pure, market discounted)
  place_model <- compute_harville_place_probs(
    er |> dplyr::transmute(race_id, horse_ref, market_prob = win_model),
    alpha_2nd = 1, alpha_3rd = 1
  ) |> dplyr::rename(place_model = harville_place_prob)
  place_market <- compute_harville_place_probs(
    er |> dplyr::transmute(race_id, horse_ref, market_prob = win_market),
    alpha_2nd = alpha_2nd, alpha_3rd = alpha_3rd
  ) |> dplyr::rename(place_market = harville_place_prob)

  brier_tbl <- er |>
    dplyr::left_join(place_model,  by = c("race_id", "horse_ref")) |>
    dplyr::left_join(place_market, by = c("race_id", "horse_ref"))
  brier_model  <- score_brier_place(
    dplyr::transmute(brier_tbl, placed, place_prob = place_model))
  brier_market <- score_brier_place(
    dplyr::transmute(brier_tbl, placed, place_prob = place_market))

  tibble::tibble(
    metric    = c("P1_rank", "Brier_place"),
    model     = c(p1_model, brier_model),
    market    = c(p1_market, brier_market),
    n_races   = c(nrow(ord_model), dplyr::n_distinct(brier_tbl$race_id)),
    n_runners = c(NA_integer_, nrow(brier_tbl))
  )
}
