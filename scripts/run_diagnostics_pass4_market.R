setwd("C:/Users/gille/projects/awracing")
source("renv/activate.R")
suppressPackageStartupMessages({library(targets); library(dplyr)})
source("R/pl_objective.R")
source("R/scoring.R")
source("R/ranking_eval_p2b.R")

per_race <- readRDS("diag3_per_race.rds")
test_predictions_2b <- targets::tar_read(test_predictions_2b)
ranking_eval_runners_2b <- targets::tar_read(ranking_eval_runners_2b)

common_races <- per_race$race_id
cat("Common races (from prior pass):", length(common_races), "\n")

# Market per-race P1_rank ingredient: discounted-Harville order prob (0.80/0.65)
rer_market_base <- ranking_eval_runners_2b |> dplyr::filter(race_id %in% common_races)
op_market <- rer_market_base |>
  dplyr::transmute(race_id, win_prob = win_market, finish_pos) |>
  compute_pl_order_probs(alpha_2nd = 0.80, alpha_3rd = 0.65) |>
  dplyr::rename(order_prob_market = order_prob)

# Market per-race Brier ingredient: discounted-Harville place prob (0.80/0.65)
pp_market <- compute_harville_place_probs(
  rer_market_base |> dplyr::transmute(race_id, horse_ref, market_prob = win_market),
  alpha_2nd = 0.80, alpha_3rd = 0.65
)
br_market <- rer_market_base |>
  dplyr::left_join(pp_market, by = c("race_id", "horse_ref")) |>
  dplyr::group_by(race_id) |>
  dplyr::summarise(sse_market = sum((placed - harville_place_prob)^2), n_market = dplyr::n(), .groups = "drop")

per_race2 <- per_race |>
  dplyr::left_join(op_market, by = "race_id") |>
  dplyr::left_join(br_market, by = "race_id") |>
  tidyr::drop_na(order_prob_market, sse_market, n_market)
cat("Aligned races (depth-3 + market):", nrow(per_race2), "\n")

paired_boot_2metric <- function(per_race, suffix_a, suffix_b, label, n_boot = 2000L, seed = 42L) {
  n <- nrow(per_race)
  op_a <- per_race[[paste0("order_prob_", suffix_a)]]; op_b <- per_race[[paste0("order_prob_", suffix_b)]]
  sse_a <- per_race[[paste0("sse_", suffix_a)]]; nr_a <- per_race[[paste0("n_", suffix_a)]]
  sse_b <- per_race[[paste0("sse_", suffix_b)]]; nr_b <- per_race[[paste0("n_", suffix_b)]]

  p1_a_point <- exp(mean(log(op_a))); p1_b_point <- exp(mean(log(op_b)))
  brier_a_point <- sum(sse_a) / sum(nr_a); brier_b_point <- sum(sse_b) / sum(nr_b)

  set.seed(seed)
  diffs <- matrix(NA_real_, nrow = n_boot, ncol = 2)
  for (b in seq_len(n_boot)) {
    idx <- sample.int(n, n, replace = TRUE)
    p1_a <- exp(mean(log(op_a[idx]))); p1_b <- exp(mean(log(op_b[idx])))
    br_a <- sum(sse_a[idx]) / sum(nr_a[idx]); br_b <- sum(sse_b[idx]) / sum(nr_b[idx])
    diffs[b, ] <- c(p1_a - p1_b, br_a - br_b)
  }
  tibble::tibble(
    contrast = label,
    metric = c("P1_rank", "Brier_place"),
    point_a = c(p1_a_point, brier_a_point),
    point_b = c(p1_b_point, brier_b_point),
    diff_point = c(p1_a_point - p1_b_point, brier_a_point - brier_b_point),
    ci_lo = apply(diffs, 2, stats::quantile, probs = 0.05, names = FALSE),
    ci_hi = apply(diffs, 2, stats::quantile, probs = 0.95, names = FALSE),
    n_races = n, n_boot = n_boot
  )
}

boot_d3_vs_market <- paired_boot_2metric(per_race2, "d3", "market", "depth-3 (selected) - discounted-Harville market")
cat("Paired bootstrap, depth-3 vs market:\n")
print(boot_d3_vs_market)

saveRDS(boot_d3_vs_market, "diag4_market.rds")
cat("DONE.\n")
