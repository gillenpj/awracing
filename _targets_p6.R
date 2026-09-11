# _targets_p6.R
#
# Paper 6 — "What the metrics can and cannot tell us".
#
# A SEPARATE pipeline with a SEPARATE store, following papers 4 and 5, so
# nothing here can touch papers 1-5:
#
#   targets::tar_make(script = "_targets_p6.R", store = "_targets_p6")
#   targets::tar_read(p6m_contrasts, store = "_targets_p6")
#
# or, from the project root, `Rscript scripts/run_p6_pipeline.R`, optionally
# naming a target to build up to.
#
# `tar_config_set()` is never called anywhere in paper 6.
#
# WHAT THIS PAPER DOES: it fits nothing and refits nothing. Everything runs on
# stored predictions read read-only from the MAIN and PAPER-5 stores, with
# their content hashes recorded in `p6m_upstream_fingerprint` so an upstream
# change invalidates downstream work rather than going stale.
#
# Scope is fixed and narrow: win market only, single bet per race, Owen's
# naive rule at the series-standard thresholds, real starting prices. No rule
# search, no staking rules, no race-characteristic filters.
#
# THE PREVIOUS PAPER 6 IS WITHDRAWN. Its draft, code, gate and pipeline are
# archived under `papers/06_betting_strategy_WITHDRAWN/`, and its store was
# renamed to `_targets_p6_withdrawn` rather than deleted. Nothing from it is
# sourced or read here.

Sys.setenv(R_LIBS   = paste(.libPaths(), collapse = .Platform$path.sep))
Sys.setenv(QUARTO_R = file.path(R.home("bin"), "Rscript.exe"))
if (Sys.getenv("QUARTO_PATH") == "") {
  candidates <- c(
    "C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe",
    "C:/Program Files/Quarto/bin/quarto.exe",
    file.path(Sys.getenv("LOCALAPPDATA"), "Programs/Quarto/bin/quarto.exe")
  )
  found <- candidates[file.exists(candidates)]
  if (length(found)) Sys.setenv(QUARTO_PATH = found[[1]])
}

library(targets)
library(tarchetypes)

tar_option_set(
  packages = c("dplyr", "tidyr", "tibble", "purrr", "stringr", "readr",
               "lubridate", "ggplot2", "DBI", "RMariaDB"),
  format   = "rds"
)

# Paper 6's own code.
tar_source("R/p6m_metrics.R")
tar_source("R/p6m_p2.R")
tar_source("R/p6m_beta.R")

# Read-only reuse of the series' own helpers. The single-bet selection and
# settlement is paper 2b's, the market-probability construction paper 1's, the
# paired ROI bootstrap paper 5's.
tar_source("R/db.R")
tar_source("R/scoring.R")
tar_source("R/value_bets_p2b.R")
tar_source("R/model_fitting_p2.R")
tar_source("R/ranking_eval_p2b.R")
tar_source("R/p5_diagnostics.R")
tar_source("R/market_blend_p4.R")

MAIN_STORE <- "_targets"
P4_STORE   <- "_targets_p4"
P5_STORE   <- "_targets_p5"

# Owen's naive thresholds, paper 1 section 3.4. Fixed, not searched.
P6M_PROB_CUT  <- 0.15
P6M_RATIO_CUT <- 1.3

# The chronological split of paper 5's validation slice used in Section 1b.
P6M_HALF_CUT <- as.Date("2012-01-15")

list(

  # =======================================================================
  # Upstream, read-only
  # =======================================================================

  tar_target(
    p6m_upstream_fingerprint,
    dplyr::bind_rows(
      targets::tar_meta(
        names = c("model_market_ratio_w_final", "model_market_ratio_2b_win",
                  "model_market_ratio_3_win", "qualifying_runners",
                  "runners_interactions", "roi_difference_2b_vs_2a",
                  "roi_diff_3_vs_2b", "boot_ranking_3_vs_2b",
                  "ranking_metrics_2b", "backtest_single_win_2a",
                  "backtest_single_win_2b", "backtest_single_win_3",
                  "backtest_single_win_2b_restricted_3",
                  "backtest_single_win_2a_restricted_3", "backtest_naive",
                  "backtest_naive_w_final", "backtest_naive_2b_win",
                  "backtest_naive_2b_win_restricted_3", "backtest_naive_3_win"),
        fields = c("name", "data"), store = MAIN_STORE
      ) |> dplyr::mutate(store = "main"),
      targets::tar_meta(
        names = c("p5_scored_v7", "p5_roi_units", "p5_test_backtests",
                  "p5_roi_contrasts", "p5_test_predictions",
                  "p5_rung3b_selected", "p5_arm_data", "p5_slice"),
        fields = c("name", "data"), store = P5_STORE
      ) |> dplyr::mutate(store = "paper5")
    )
  ),

  # -- Main store ---------------------------------------------------------
  tar_target(p6m_ratio_2a, {
    p6m_upstream_fingerprint
    targets::tar_read(model_market_ratio_w_final, store = MAIN_STORE)
  }),
  tar_target(p6m_ratio_2b, {
    p6m_upstream_fingerprint
    targets::tar_read(model_market_ratio_2b_win, store = MAIN_STORE)
  }),
  tar_target(p6m_ratio_3, {
    p6m_upstream_fingerprint
    targets::tar_read(model_market_ratio_3_win, store = MAIN_STORE)
  }),
  tar_target(p6m_race_dates, {
    p6m_upstream_fingerprint
    targets::tar_read(runners_interactions, store = MAIN_STORE) |>
      dplyr::distinct(race_id, race_date)
  }),

  # The series' published contrasts and metrics, unchanged.
  tar_target(p6m_pub_2b_vs_2a, {
    p6m_upstream_fingerprint
    targets::tar_read(roi_difference_2b_vs_2a, store = MAIN_STORE)
  }),
  tar_target(p6m_pub_3_vs_2b, {
    p6m_upstream_fingerprint
    targets::tar_read(roi_diff_3_vs_2b, store = MAIN_STORE)
  }),
  tar_target(p6m_boot_ranking_3_vs_2b, {
    p6m_upstream_fingerprint
    targets::tar_read(boot_ranking_3_vs_2b, store = MAIN_STORE)
  }),
  tar_target(p6m_ranking_metrics_2b, {
    p6m_upstream_fingerprint
    targets::tar_read(ranking_metrics_2b, store = MAIN_STORE)
  }),

  # The stored backtests, for the basis assertion and the series table.
  tar_target(p6m_backtests_main, {
    p6m_upstream_fingerprint
    purrr::map(
      c("backtest_single_win_2a", "backtest_single_win_2b",
        "backtest_single_win_3", "backtest_single_win_2a_restricted_3",
        "backtest_single_win_2b_restricted_3", "backtest_naive",
        "backtest_naive_w_final", "backtest_naive_2b_win",
        "backtest_naive_2b_win_restricted_3", "backtest_naive_3_win"),
      function(n) targets::tar_read_raw(n, store = MAIN_STORE)
    ) |>
      rlang::set_names(c("single_2a", "single_2b", "single_3",
                         "single_2a_r", "single_2b_r", "naive_1",
                         "naive_2a", "naive_2b", "naive_2b_r", "naive_3"))
  }),

  # -- Paper 5, read-only -------------------------------------------------
  tar_target(p6m_p5_scored_val, {
    p6m_upstream_fingerprint
    targets::tar_read(p5_scored_v7, store = P5_STORE)
  }),
  tar_target(p6m_p5_roi_units, {
    p6m_upstream_fingerprint
    targets::tar_read(p5_roi_units, store = P5_STORE)
  }),
  tar_target(p6m_p5_backtests, {
    p6m_upstream_fingerprint
    targets::tar_read(p5_test_backtests, store = P5_STORE)
  }),
  tar_target(p6m_p5_contrasts, {
    p6m_upstream_fingerprint
    targets::tar_read(p5_roi_contrasts, store = P5_STORE)
  }),
  tar_target(p6m_p5_backtests_universe, {
    p6m_upstream_fingerprint
    targets::tar_read(p5_gbt_test_data, store = P5_STORE)$key$race_id
  }),

  # =======================================================================
  # Identity, asserted before anything is computed
  # =======================================================================

  tar_target(
    p6m_race_identity,
    p6m_assert_race_identity(
      list(`2a` = p6m_ratio_2a, `2b` = p6m_ratio_2b, `3` = p6m_ratio_3)
    )
  ),

  # BLOCKER: the two published pre-paper-5 contrasts are on the
  # bet-every-qualifier rule, not the single-bet rule. Asserted, so the
  # paper's `basis` column is a fact and not a comment.
  tar_target(
    p6m_basis_check,
    p6m_assert_published_basis(
      p6m_pub_2b_vs_2a, p6m_pub_3_vs_2b,
      naive = list(roi_2a = p6m_backtests_main$naive_2a$roi,
                   roi_2b = p6m_backtests_main$naive_2b$roi,
                   roi_2b_r = p6m_backtests_main$naive_2b_r$roi,
                   roi_3 = p6m_backtests_main$naive_3$roi),
      single = list(roi_2a = p6m_backtests_main$single_2a$roi,
                    roi_2b = p6m_backtests_main$single_2b$roi,
                    roi_2b_r = p6m_backtests_main$single_2b_r$roi,
                    roi_3 = p6m_backtests_main$single_3$roi)
    )
  ),

  # =======================================================================
  # SECTION 1a
  # =======================================================================

  # Per-race single-bet win units, one entry per model. Papers 2a, 2b and 3
  # come from their ratio tibbles through the series' own helper; paper 5's
  # encoder and the hand-built-summary MLP come from paper 5's stored units,
  # which are what its published contrasts were computed from.
  tar_target(
    p6m_units,
    {
      p6m_race_identity
      list(
        `2a` = single_bet_units(p6m_ratio_2a),
        `2b` = single_bet_units(p6m_ratio_2b),
        `3` = single_bet_units(p6m_ratio_3),
        `5` = p6m_p5_roi_units$rung3b$win,
        hand_built = p6m_p5_roi_units$rung1$win
      )
    }
  ),

  tar_target(
    p6m_series,
    p6m_single_bet_series(
      list(`2a` = p6m_ratio_2a, `2b` = p6m_ratio_2b, `3` = p6m_ratio_3),
      p6m_units[["5"]]
    )
  ),

  # Each model's full race universe: every race it could have bet, which is
  # what the paired bootstrap resamples over.
  tar_target(
    p6m_universes,
    list(
      `2a` = sort(unique(p6m_ratio_2a$race_id)),
      `2b` = sort(unique(p6m_ratio_2b$race_id)),
      `3` = sort(unique(p6m_ratio_3$race_id)),
      `5` = sort(unique(p6m_p5_backtests_universe)),
      hand_built = sort(unique(p6m_p5_backtests_universe))
    )
  ),

  tar_target(
    p6m_contrasts,
    {
      p6m_basis_check
      p6m_roi_contrasts(p6m_units, p6m_universes, n_boot = 2000L, seed = 42L)
    }
  ),

  # BLOCKER: the two rows that exist in both tables must agree exactly.
  tar_target(
    p6m_recompute_check,
    p6m_assert_recompute_matches(p6m_contrasts, p6m_published)
  ),

  tar_target(
    p6m_published,
    p6m_published_contrasts(p6m_pub_2b_vs_2a, p6m_pub_3_vs_2b,
                            p6m_p5_contrasts)
  ),

  tar_target(
    p6m_resolution,
    p6m_resolution_table(
      p6m_boot_ranking_3_vs_2b, p6m_ranking_metrics_2b,
      single_2b = p6m_backtests_main$single_2b,
      single_3 = p6m_backtests_main$single_3,
      roi_contrast = dplyr::filter(p6m_contrasts, contrast == "3 - 2b")
    )
  ),

  # =======================================================================
  # SECTION 1b
  # =======================================================================

  tar_target(
    p6m_val_halves,
    p6m_validation_halves(p6m_p5_scored_val, p6m_race_dates,
                          cut = P6M_HALF_CUT)
  ),

  tar_target(
    p6m_race_sets,
    p6m_three_race_sets(p6m_val_halves, p6m_p5_backtests)
  ),

  # =======================================================================
  # SECTION 2 — P1 out, P2 refined
  #
  # The two benchmark probabilities and papers 2b and 3's stored predictions
  # come from paper 4's own price panel, read read-only: it already carries
  # the pre-race forecast price from `daily_runners` and the settled starting
  # price, both renormalised within race by `normalise_overround()`. Paper 5's
  # encoder is joined on from its stored test predictions. No price is
  # renormalised a second time and nothing is refitted.
  # =======================================================================

  tar_target(
    p6m_p4_fingerprint,
    targets::tar_meta(names = c("p4_probs", "p4_common", "p4_arm_grid",
                                "p4_arm_grid_b", "p4_arm_grid_pooled"),
                      fields = c("name", "data"), store = P4_STORE) |>
      dplyr::mutate(store = "paper4")
  ),
  tar_target(p6m_p4_probs, {
    p6m_p4_fingerprint
    targets::tar_read(p4_probs, store = P4_STORE)
  }),
  tar_target(p6m_encoder_test, {
    p6m_upstream_fingerprint
    targets::tar_read(p5_test_predictions, store = P5_STORE)$rung3b
  }),

  tar_target(p6m_p2_frame, p6m_p2_panel(p6m_p4_probs, p6m_encoder_test)),
  tar_target(p6m_p2_cover, p6m_p2_coverage(p6m_p2_frame, p6m_encoder_test)),

  tar_target(p6m_p2_all,
             p6m_p2_overall(p6m_p2_frame, n_boot = 2000L, seed = 42L)),
  tar_target(p6m_p2_diffs,
             p6m_p2_contrasts(p6m_p2_frame, n_boot = 2000L, seed = 42L)),
  tar_target(p6m_p2_bins,
             p6m_p2_by_bin(p6m_p2_frame, n_boot = 2000L, seed = 42L)),
  tar_target(p6m_p2_pairs,
             p6m_p2_model_pairs(p6m_p2_frame, n_boot = 2000L, seed = 42L)),
  tar_target(p6m_p2_order, p6m_p2_ordering(p6m_p2_all, p6m_p2_diffs)),

  # =======================================================================
  # SECTION 3 — the pooled coefficient
  #
  # Speculative. Same rows as Section 2, the encoder's stored predictions, and
  # a race-level bootstrap for the standard error.
  # =======================================================================

  # Paper 4's own published coefficients, read live rather than transcribed.
  tar_target(p6m_p4_cited, {
    p6m_p4_fingerprint
    p6m_p4_cited_fits(
      targets::tar_read(p4_arm_grid_pooled, store = P4_STORE)$coefficients,
      targets::tar_read(p4_arm_grid, store = P4_STORE)$coefficients,
      targets::tar_read(p4_arm_grid_b, store = P4_STORE)$coefficients
    )
  }),

  tar_target(p6m_beta,
             p6m_beta_fit(p6m_p2_frame, n_boot = 2000L, seed = 42L)),

  # =======================================================================
  # THE PAPER
  #
  # Rendered inside this pipeline, as papers 4 and 5 are. HTML and PDF.
  # =======================================================================
  tar_quarto(
    paper_6_metrics,
    path = "papers/06_metrics",
    quiet = FALSE,
    extra_files = c(
      "papers/06_metrics/_01_roi.qmd",
      "papers/06_metrics/_02_p2.qmd",
      "papers/06_metrics/_03_beta.qmd",
      "papers/06_metrics/_04_limitations.qmd",
      "papers/06_metrics/_helpers.R",
      "papers/06_metrics/references.bib",
      "papers/06_metrics/_quarto.yml"
    )
  )
)
