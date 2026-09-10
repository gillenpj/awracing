# _targets_p6.R
#
# Paper 6 — EXPLORATORY ROI SWEEP, validation to test.
#
# NOT a hypothesis-testing paper and not published. There is no declaration
# rule, no bar to clear and no interval gating what reaches the test split.
# The purpose is to stress-test whether test-split ROI can be moved by a
# different betting rule, to generate ideas to return to when betting goes
# live. Output is a working report, `papers/06_betting_strategy/
# EXPLORATION.md`, written from a `format = "file"` target so every number in
# it is a function of the targets rather than a transcription. No Quarto
# paper is rendered and `docs/` is untouched.
#
# Paper 6 was twice attempted as a declaration paper and both drafts are kept,
# unrendered, in `papers/06_betting_strategy/SUPERSEDED/` with a README saying
# why each was set aside. Their declaration chain is no longer on this graph.
# `tar_make()` does not delete a dropped target's stored object, so removing
# it destroyed nothing.
#
# A SEPARATE pipeline with a SEPARATE store, following papers 4 and 5, so
# nothing here can touch papers 1-5. Run it with the script and store passed
# explicitly rather than through `_targets.yaml`, which papers 1-3's qmd setup
# chunks own:
#
#   targets::tar_make(script = "_targets_p6.R", store = "_targets_p6")
#   targets::tar_read(p6_val_sweep, store = "_targets_p6")
#
# or, from the project root, `Rscript scripts/run_p6_pipeline.R`, optionally
# naming a target to build up to.
#
# `tar_config_set()` is never called anywhere in paper 6.
#
# WHAT IS VARIED: the bet selection and staking rule, and nothing else. Paper
# 6 fits no model and refits nothing. Both prediction sets are paper 5's own
# stored targets:
#
#   SEARCH SET   the validation slice, 1,505 races scored by the
#                FITTING-PARTITION fit, which never saw them.
#   TEST SPLIT   2,183 races scored by the FULL-TRAINING-SPLIT refit, the
#                model paper 5 published.
#
# The 3,517 fitting races are not used anywhere: the model memorised them.
#
# Upstream inputs come from the PAPER-5 and MAIN stores, READ-ONLY, with their
# content hashes recorded in `p6_upstream_fingerprint` so an upstream change
# invalidates downstream work rather than going stale silently.

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
tar_source("R/p6_ledger.R")
tar_source("R/p6_rules.R")
tar_source("R/p6_predictions.R")
tar_source("R/p6_reports.R")
tar_source("R/p6_declaration.R")
tar_source("R/p6_test_report.R")
tar_source("R/p6_plots.R")
tar_source("R/p6_explore.R")
tar_source("R/p6_explore_report.R")
tar_source("R/p6_racechar.R")
tar_source("R/p6_paper.R")

# Read-only reuse. Paper 6 adds no variant of any of these: the settlement is
# paper 2b's, the market-probability construction paper 1's, the price query
# paper 4's, the softmax paper 3's.
tar_source("R/db.R")
tar_source("R/pl_objective.R")
tar_source("R/gbt_data.R")
tar_source("R/scoring.R")
tar_source("R/ranking_eval_p2b.R")
tar_source("R/value_bets_p2b.R")
tar_source("R/model_fitting_p2.R")
tar_source("R/gbt_results.R")
tar_source("R/market_blend_p4.R")
tar_source("R/build_going_features.R")

MAIN_STORE <- "_targets"
P5_STORE   <- "_targets_p5"

# The four settlement tables. `eachway` is paper 5's flat 1/5-top-3 terms;
# `eachway_corrected` the industry handicap ladder. Both are reported
# everywhere. `P6_BETS` is kept for the ledger gate; the exploration reads
# `p6_explore_bets`.
P6_BETS <- c(win = "win", place = "place", eachway = "eachway",
             eachway_corrected = "eachway_corrected")

# Paper 5's published rung-3b validation PL loss. A blocker: the search set is
# only attributable to that fit if the stored loss matches.
P6_P5_VAL_LOSS <- 5.718496

list(

  # =======================================================================
  # Upstream, read-only
  # =======================================================================

  tar_target(
    p6_upstream_fingerprint,
    dplyr::bind_rows(
      targets::tar_meta(
        names = c("qualifying_runners", "runners_interactions",
                  "gbt_train_data", "gbt_test_data"),
        fields = c("name", "data"), store = MAIN_STORE
      ) |> dplyr::mutate(store = "main"),
      targets::tar_meta(
        names = c("p5_scored_v7", "p5_rung3b_selected", "p5_arm_data",
                  "p5_slice", "p5_test_predictions", "p5_test_fit_rung3b",
                  "p5_test_backtests", "p5_backend"),
        fields = c("name", "data"), store = P5_STORE
      ) |> dplyr::mutate(store = "paper5")
    )
  ),

  tar_target(p6_qualifying_runners, {
    p6_upstream_fingerprint
    targets::tar_read(qualifying_runners, store = MAIN_STORE)
  }),
  tar_target(p6_race_dates, {
    p6_upstream_fingerprint
    targets::tar_read(runners_interactions, store = MAIN_STORE) |>
      dplyr::distinct(race_id, race_date, split)
  }),
  tar_target(p6_gbt_test_data, {
    p6_upstream_fingerprint
    targets::tar_read(gbt_test_data, store = MAIN_STORE)
  }),

  # -- Paper 5, read-only --------------------------------------------------
  tar_target(p6_p5_scored_val, {
    p6_upstream_fingerprint
    targets::tar_read(p5_scored_v7, store = P5_STORE)
  }),
  tar_target(p6_p5_rung3b_selected, {
    p6_upstream_fingerprint
    targets::tar_read(p5_rung3b_selected, store = P5_STORE)
  }),
  tar_target(p6_p5_val_key, {
    p6_upstream_fingerprint
    targets::tar_read(p5_arm_data, store = P5_STORE)$val$key
  }),
  tar_target(p6_p5_slice, {
    p6_upstream_fingerprint
    targets::tar_read(p5_slice, store = P5_STORE)
  }),
  tar_target(p6_p5_test_predictions, {
    p6_upstream_fingerprint
    targets::tar_read(p5_test_predictions, store = P5_STORE)$rung3b
  }),
  tar_target(p6_p5_test_fit, {
    p6_upstream_fingerprint
    tf <- targets::tar_read(p5_test_fit_rung3b, store = P5_STORE)
    tf$scores <- NULL   # metadata only; paper 6 reads the stored predictions
    tf
  }),
  tar_target(p6_p5_backtests, {
    p6_upstream_fingerprint
    targets::tar_read(p5_test_backtests, store = P5_STORE)
  }),

  # =======================================================================
  # STAGE 0 — the two frames, the gate, and the descriptive reports
  # =======================================================================

  # The search set, with paper 5's published validation loss asserted before
  # anything is read off it. BLOCKER if it does not match.
  tar_target(
    p6_val_predictions,
    p6_validation_predictions(p6_p5_scored_val, p6_p5_rung3b_selected,
                              p6_p5_val_key,
                              published_val_loss = P6_P5_VAL_LOSS)
  ),

  tar_target(
    p6_val_frame,
    p6_build_bet_frame(p6_val_predictions, p6_qualifying_runners,
                       dplyr::select(p6_race_dates, race_id, race_date))
  ),
  tar_target(
    p6_test_frame,
    p6_build_bet_frame(p6_p5_test_predictions, p6_qualifying_runners,
                       dplyr::select(p6_race_dates, race_id, race_date))
  ),

  tar_target(
    p6_search_set_check,
    p6_assert_search_set(p6_val_frame, p6_p5_val_key,
                         p6_p5_slice$fit_race_ids, p6_gbt_test_data$key)
  ),

  tar_target(
    p6_fit_provenance_tbl,
    p6_fit_provenance(p6_p5_rung3b_selected, p6_p5_test_fit, p6_p5_slice)
  ),

  tar_target(
    p6_universe,
    tibble::tibble(
      n_val_races  = dplyr::n_distinct(p6_val_frame$race_id),
      n_val_rows   = nrow(p6_val_frame),
      n_test_races = dplyr::n_distinct(p6_test_frame$race_id),
      n_test_rows  = nrow(p6_test_frame),
      projection   = dplyr::n_distinct(p6_test_frame$race_id) /
        dplyr::n_distinct(p6_val_frame$race_id)
    )
  ),

  # -- Settlement ---------------------------------------------------------
  tar_target(
    p6_val_settle,
    p6_settlement_tables(p6_val_frame, p6_val_predictions,
                         p6_qualifying_runners)
  ),
  tar_target(
    p6_test_settle,
    p6_settlement_tables(p6_test_frame, p6_p5_test_predictions,
                         p6_qualifying_runners)
  ),

  # -- THE GATE: rebuild paper 5's test ledger through p6_ledger() ---------
  # S1/K0, paper 5's each-way terms, asserted against the encoder rows of
  # paper 5's own `p5_test_backtests`. A blocker in the brief, so it is an
  # assertion and not a report. Unchanged from the first attempt.
  tar_target(
    p6_ledger_gate,
    {
      sels <- p6_selection_rules(p6_thresholds(p6_test_frame))
      stks <- p6_staking_rules()
      got <- purrr::imap(c(win = "win", place = "place", eachway = "eachway"),
                         function(tbl, nm) {
                           led <- p6_ledger(p6_test_frame, p6_test_settle,
                                            sels$S1$fn, stks$K0$fn, tbl)
                           dplyr::mutate(p6_summarise_ledger(led), bet = nm,
                                         .before = 1)
                         }) |> purrr::list_rbind()

      want <- p6_p5_backtests |>
        dplyr::filter(arm == "rung3b") |>
        dplyr::select(bet, n_bets, n_wins, profit, roi)

      cmp <- got |>
        dplyr::select(bet, n_bets, n_wins, profit, roi) |>
        dplyr::left_join(want, by = "bet", suffix = c("_p6", "_p5")) |>
        dplyr::mutate(
          d_n = n_bets_p6 - n_bets_p5,
          d_w = n_wins_p6 - n_wins_p5,
          d_profit = profit_p6 - profit_p5,
          d_roi = roi_p6 - roi_p5
        )

      stopifnot(
        nrow(cmp) == 3L,
        all(cmp$d_n == 0L), all(cmp$d_w == 0L),
        max(abs(cmp$d_profit)) < 1e-9,
        max(abs(cmp$d_roi)) < 1e-12
      )
      cmp
    }
  ),

  # -- Descriptive reports -------------------------------------------------

  # Price coverage by year — the one target that touches the database.
  tar_target(
    p6_val_raw_prices,
    read_p4_price_sources(sort(unique(p6_val_frame$race_id)))
  ),
  tar_target(
    p6_price_coverage_val,
    p6_price_coverage(dplyr::select(p6_val_frame, race_id, runner_id),
                      dplyr::select(p6_race_dates, race_id, race_date),
                      p6_val_raw_prices)
  ),

  tar_target(p6_overround_val, p6_overround_by_field(p6_val_frame)),

  tar_target(p6_field_sizes_val, p6_field_size_report(p6_val_frame)),
  tar_target(p6_field_sizes_test, p6_field_size_report(p6_test_frame)),
  tar_target(
    p6_eachway_terms_decision,
    tibble::tibble(
      share_4_to_7_val = p6_field_sizes_val$share_4_to_7,
      share_4_to_7_test = p6_field_sizes_test$share_4_to_7,
      share_mispriced_val = p6_field_sizes_val$share_wrong,
      share_mispriced_test = p6_field_sizes_test$share_wrong,
      threshold = 0.10,
      correct_terms = p6_field_sizes_val$share_4_to_7 > 0.10
    )
  ),

  # The two-fit mismatch, quantified: deciles and Owen's cuts on both splits.
  tar_target(p6_positions,
             p6_threshold_position_both(p6_val_frame, p6_test_frame)),

  # =======================================================================
  # THE EXPLORATION
  #
  # An exploratory sweep, NOT a hypothesis test: no declaration rule, no bar
  # to clear, no interval gating what reaches the test split. The previous
  # draft's declaration chain — stages A and B, `p6_declare_step()`, the
  # frozen `DECLARED_RULES.md` and the arms derived from it — is gone from
  # this pipeline, because paper 6 no longer declares anything. Its code is
  # untouched in `R/p6_rules.R` and `R/p6_declaration.R` (the ledger gate and
  # the markdown helpers still use them), and its results are recorded in
  # `papers/06_betting_strategy/SUPERSEDED/attempt2_declaration/`. Objects
  # already in the store are left where they are: `tar_make()` does not delete
  # a dropped target's object, so nothing recorded is destroyed by this edit.
  # =======================================================================

  tar_target(p6_explore_bets,
             c("win", "place", "eachway", "eachway_corrected")),

  tar_target(p6_explore_grid, p6_filter_grid()),

  # The compiled frames: every settlement join and every filter-independent
  # within-race argmax, done once per split.
  tar_target(p6_val_cf, p6_compile_frame(p6_val_frame, p6_val_settle)),
  tar_target(p6_test_cf, p6_compile_frame(p6_test_frame, p6_test_settle)),

  # -- THE SWEEP GATE -----------------------------------------------------
  # The sweep is a SECOND implementation of the selection and settlement
  # arithmetic — indices and sums, not `dplyr` verbs, because it scores 25,220
  # combinations. So it is asserted against `p6_ledger()` on the three rules
  # that exist in both languages, on the validation slice:
  #
  #   P5 at 0.15 / 1.30 == S1   Owen's rule
  #   P1 at no filter    == S0   the model's top-rated horse, every race
  #   P2 at no filter    == S4   the market favourite, every race
  #
  # Bet set as well as ROI, and on the each-way corrected table as well as
  # win, so the settlement matrices are covered too. A blocker in the brief,
  # so it is an assertion and not a report.
  tar_target(
    p6_sweep_gate,
    {
      sels <- p6_selection_rules(p6_thresholds(p6_val_frame))
      stks <- p6_staking_rules()
      spec <- tibble::tribble(
        ~picker, ~p_cut, ~r_cut, ~arm,  ~bet,
        "P5",      0.15,   1.30, "S1",  "win",
        "P1",      -Inf,   -Inf, "S0",  "win",
        "P2",      -Inf,   -Inf, "S4",  "win",
        "P5",      0.15,   1.30, "S1",  "eachway_corrected",
        "P1",      -Inf,   -Inf, "S0",  "eachway_corrected"
      )
      out <- purrr::pmap(spec, function(picker, p_cut, r_cut, arm, bet) {
        rows <- p6_rule_rows(p6_val_cf, picker, p_cut, r_cut)
        a <- p6_score_rule_tbl(p6_val_cf, rows, bet)
        led <- p6_ledger(p6_val_frame, p6_val_settle, sels[[arm]]$fn,
                         stks$K0$fn, bet)
        b <- p6_summarise_ledger(led)
        key_a <- sort(paste(p6_val_frame$race_id[rows],
                            p6_val_frame$runner_id[rows]))
        key_b <- sort(paste(led$race_id, led$runner_id))
        tibble::tibble(
          rule = p6_rule_label(picker, p_cut, r_cut, !is.finite(p_cut)),
          ledger_arm = paste0(arm, "/K0"), bet = bet,
          bets = a$n_bets, bets_ledger = b$n_bets,
          roi = a$roi, roi_ledger = b$roi, roi_diff = a$roi - b$roi,
          stake_diff = a$total_stake - b$total_stake,
          same_bet_set = identical(key_a, key_b)
        )
      }) |> purrr::list_rbind()

      stopifnot(
        nrow(out) == nrow(spec),
        all(out$same_bet_set),
        all(out$bets == out$bets_ledger),
        max(abs(out$roi_diff)) < 1e-12,
        max(abs(out$stake_diff)) < 1e-9
      )
      out
    }
  ),

  # -- STAGE 1: the sweep, and whether the pickers differ ------------------
  tar_target(
    p6_val_sweep,
    {
      p6_sweep_gate  # do not sweep on unverified arithmetic
      p6_sweep(p6_val_cf, p6_explore_grid)
    }
  ),

  tar_target(p6_agree_nofilter,
             p6_picker_agreement(p6_val_cf, -Inf, -Inf, "no filter")),
  tar_target(p6_agree_owen,
             p6_picker_agreement(p6_val_cf, 0.15, 1.30,
                                 "P>0.15, ratio>1.30")),
  tar_target(p6_agree_max,
             p6_picker_agreement_max(p6_val_cf, p6_explore_grid)),

  # -- STAGE 2: the shortlist, and one pass over the test split ------------
  tar_target(
    p6_shortlists,
    purrr::map(p6_explore_bets,
               function(b) p6_shortlist(p6_val_sweep, b, min_bets = 300L,
                                        n_top = 5L)) |>
      purrr::list_rbind()
  ),

  tar_target(p6_explore_val,
             p6_score_shortlist(p6_val_cf, p6_shortlists,
                                n_boot = 2000L, seed = 42L)),

  # THE ONE PASS OVER THE TEST SPLIT. Read-only against paper 5: the test
  # frame is built from `p5_test_predictions` as stored, and nothing here
  # writes to the paper-5 store or invalidates a paper-5 target.
  tar_target(p6_explore_test,
             p6_score_shortlist(p6_test_cf, p6_shortlists,
                                n_boot = 2000L, seed = 42L)),

  tar_target(p6_explore_ranks,
             p6_rank_comparison(p6_explore_val, p6_explore_test)),

  # -- STAGE 3: staking, on a fixed selection ------------------------------
  tar_target(
    p6_stage3_rules,
    {
      best <- p6_explore_test |>
        dplyr::filter(!is.na(roi)) |>
        dplyr::group_by(bet) |>
        dplyr::arrange(dplyr::desc(roi), .by_group = TRUE) |>
        dplyr::slice(1) |>
        dplyr::ungroup() |>
        dplyr::transmute(bet, rule, picker, p_cut, r_cut,
                         role = "best test rule from stage 2")
      owen <- tibble::tibble(bet = p6_explore_bets) |>
        dplyr::mutate(picker = "P5", p_cut = 0.15, r_cut = 1.30,
                      rule = p6_rule_label("P5", 0.15, 1.30, FALSE),
                      role = "S1/K0, Owen's rule")
      dplyr::bind_rows(best, owen) |>
        dplyr::group_by(bet, rule, picker, p_cut, r_cut) |>
        dplyr::summarise(role = paste(sort(unique(role)), collapse = "; "),
                         .groups = "drop") |>
        dplyr::arrange(match(bet, p6_explore_bets), picker, p_cut)
    }
  ),

  tar_target(p6_staking_test,
             p6_staking_sweep(p6_test_cf, p6_stage3_rules)),
  tar_target(p6_staking_val,
             p6_staking_sweep(p6_val_cf, p6_stage3_rules)),

  # -- THE REPORT ----------------------------------------------------------
  tar_target(
    p6_exploration_file,
    p6_write_exploration(
      path = "papers/06_betting_strategy/EXPLORATION.md",
      universe = p6_universe,
      grid = p6_explore_grid,
      sweep = p6_val_sweep,
      agree_nofilter = p6_agree_nofilter,
      agree_owen = p6_agree_owen,
      agree_max = p6_agree_max,
      shortlists = p6_shortlists,
      val_scores = p6_explore_val,
      test_scores = p6_explore_test,
      ranks = p6_explore_ranks,
      staking_test = p6_staking_test,
      staking_val = p6_staking_val,
      stage3_rules = p6_stage3_rules,
      gate = p6_sweep_gate,
      search_set = p6_search_set_check,
      bets = p6_explore_bets
    ),
    format = "file"
  ),

  # =======================================================================
  # ROUND 3 — RACE-CHARACTERISTIC FILTERS, AND A STABILITY GUARD
  #
  # Rounds 1 and 2 searched two families: which horse (the picker) and where
  # to cut on the model-probability / model-to-market-ratio plane. That plane
  # is largely a price-band dial (`DIAGNOSTICS.md`), so the search was dense
  # in one dimension and absent everywhere else. This round adds the third
  # family — filters on conditions known the night before the race, which
  # select races rather than reacting to a settled price — and then puts
  # every candidate in all three families through a half-window stability
  # guard before anything reaches the test split.
  #
  # The new upstream read (`qualifying_races`) has its OWN fingerprint target
  # rather than joining `p6_upstream_fingerprint`, so adding it does not
  # invalidate round 2's chain.
  # =======================================================================

  tar_target(
    p6_rc_fingerprint,
    targets::tar_meta(names = "qualifying_races",
                      fields = c("name", "data"), store = MAIN_STORE) |>
      dplyr::mutate(store = "main")
  ),
  tar_target(p6_qualifying_races, {
    p6_rc_fingerprint
    targets::tar_read(qualifying_races, store = MAIN_STORE)
  }),

  # -- Race attributes, aligned to each split's compiled frame -------------
  tar_target(p6_val_attrs,
             p6_race_attributes(p6_val_frame, p6_qualifying_races)),
  tar_target(p6_test_attrs,
             p6_race_attributes(p6_test_frame, p6_qualifying_races)),

  # Field size per FRAME ROW, for the mean-field-size column.
  tar_target(p6_val_field_size, p6_val_frame$field_size),
  tar_target(p6_test_field_size, p6_test_frame$field_size),

  # The half index, and the two window masks over the validation races.
  tar_target(p6_val_half, p6_half_index(p6_val_attrs)),
  tar_target(p6_val_window_h1, p6_val_half == 1L),
  tar_target(p6_val_window_h2, p6_val_half == 2L),

  # -- The specifications, declared on the search set ---------------------
  # Distance terciles are computed on the validation slice and applied to the
  # test split unchanged: they are part of the filter's definition.
  tar_target(p6_rc_terciles, p6_distance_terciles(p6_val_attrs)),
  tar_target(p6_rc_all_specs, p6_rc_specs(p6_val_attrs, p6_rc_terciles)),
  tar_target(p6_val_rc_masks,
             p6_rc_masks(p6_val_cf, p6_val_attrs, p6_rc_all_specs)),
  tar_target(p6_test_rc_masks,
             p6_rc_masks(p6_test_cf, p6_test_attrs, p6_rc_all_specs)),
  tar_target(p6_rc_pruned,
             p6_rc_prune(p6_rc_all_specs, p6_val_rc_masks, p6_val_half,
                         min_races = 300L, min_half = 150L)),
  tar_target(p6_rc_kept, dplyr::filter(p6_rc_pruned, kept)),

  # -- STAGE 1a: the race-characteristic family, on three windows ---------
  tar_target(p6_rc_sweep_full,
             p6_rc_sweep(p6_val_cf, p6_val_rc_masks, p6_rc_kept,
                         p6_val_field_size)),
  tar_target(p6_rc_sweep_h1,
             p6_rc_sweep(p6_val_cf, p6_val_rc_masks, p6_rc_kept,
                         p6_val_field_size, window = p6_val_window_h1)),
  tar_target(p6_rc_sweep_h2,
             p6_rc_sweep(p6_val_cf, p6_val_rc_masks, p6_rc_kept,
                         p6_val_field_size, window = p6_val_window_h2)),

  # -- STAGE 1b: the threshold family, re-scored on the two halves --------
  # Round 2's family. `p6_val_sweep` already holds the full-window result but
  # without the `mean_field_size` / `n_filter_races` columns the guard reads,
  # so the full window is re-swept through the same function. It must
  # reproduce round 2's ROIs exactly, which `p6_round3_gate` asserts.
  tar_target(p6_thr_sweep_full,
             p6_threshold_sweep_window(p6_val_cf, p6_explore_grid,
                                       p6_val_field_size)),
  tar_target(p6_thr_sweep_h1,
             p6_threshold_sweep_window(p6_val_cf, p6_explore_grid,
                                       p6_val_field_size,
                                       window = p6_val_window_h1)),
  tar_target(p6_thr_sweep_h2,
             p6_threshold_sweep_window(p6_val_cf, p6_explore_grid,
                                       p6_val_field_size,
                                       window = p6_val_window_h2)),

  # -- ROUND-3 GATE -------------------------------------------------------
  # Two assertions, both blockers. (1) The windowed threshold sweep
  # reproduces round 2's `p6_val_sweep` ROI on every shared row, so the new
  # scoring path is not a second, different implementation. (2) The two half
  # windows partition the validation races exactly: no race in both, none in
  # neither.
  tar_target(
    p6_round3_gate,
    {
      j <- p6_thr_sweep_full |>
        dplyr::select(picker, p_cut, r_cut, bet, roi_new = roi,
                      n_new = n_bets) |>
        dplyr::inner_join(
          dplyr::select(p6_val_sweep, picker, p_cut, r_cut, bet,
                        roi_old = roi, n_old = n_bets),
          by = c("picker", "p_cut", "r_cut", "bet")
        )
      d <- abs(j$roi_new - j$roi_old)
      stopifnot(
        nrow(j) == nrow(p6_val_sweep),
        all(j$n_new == j$n_old),
        max(d, na.rm = TRUE) < 1e-12,
        sum(is.na(j$roi_new) != is.na(j$roi_old)) == 0L,
        all(xor(p6_val_window_h1, p6_val_window_h2)),
        sum(p6_val_window_h1) + sum(p6_val_window_h2) == p6_val_cf$n_races,
        identical(p6_val_attrs$race_id, p6_val_cf$races),
        identical(p6_test_attrs$race_id, p6_test_cf$races)
      )
      tibble::tibble(
        rows_compared = nrow(j),
        max_abs_roi_diff = max(d, na.rm = TRUE),
        n_races_h1 = sum(p6_val_window_h1),
        n_races_h2 = sum(p6_val_window_h2),
        h1_cut = "2012-01-15"
      )
    }
  ),

  # -- STAGE 1c: the combined layer ---------------------------------------
  # The best race-characteristic filter per picker per bet type, crossed with
  # the full probability / ratio grid, so it is visible whether the two
  # families are additive or redundant. "field size any" is excluded as a
  # best filter: it is the no-filter row and would make the layer a copy of
  # the threshold family.
  tar_target(
    p6_rc_best_pairs,
    p6_rc_sweep_full |>
      dplyr::filter(!is.na(roi), n_bets >= 300L,
                    filter != "field size any") |>
      dplyr::group_by(picker, bet) |>
      dplyr::arrange(dplyr::desc(roi), .by_group = TRUE) |>
      dplyr::slice(1) |>
      dplyr::ungroup() |>
      dplyr::select(picker, bet, rc_id, filter, rc_roi = roi)
  ),
  tar_target(
    p6_comb_sweep_full,
    {
      p6_round3_gate
      p6_combined_sweep(p6_val_cf, p6_val_rc_masks, p6_rc_best_pairs,
                        p6_explore_grid, p6_val_field_size)
    }
  ),
  tar_target(p6_comb_sweep_h1,
             p6_combined_sweep(p6_val_cf, p6_val_rc_masks, p6_rc_best_pairs,
                               p6_explore_grid, p6_val_field_size,
                               window = p6_val_window_h1)),
  tar_target(p6_comb_sweep_h2,
             p6_combined_sweep(p6_val_cf, p6_val_rc_masks, p6_rc_best_pairs,
                               p6_explore_grid, p6_val_field_size,
                               window = p6_val_window_h2)),

  # -- STAGE 2: the guard, per family -------------------------------------
  tar_target(p6_rc_guard,
             p6_stability_guard(p6_rc_sweep_full, p6_rc_sweep_h1,
                                p6_rc_sweep_h2)),
  tar_target(p6_thr_guard,
             p6_stability_guard(p6_thr_sweep_full, p6_thr_sweep_h1,
                                p6_thr_sweep_h2)),
  tar_target(p6_comb_guard,
             p6_stability_guard(p6_comb_sweep_full, p6_comb_sweep_h1,
                                p6_comb_sweep_h2)),

  tar_target(
    p6_guard_summary,
    dplyr::bind_rows(
      p6_half_correlations(p6_rc_guard),
      p6_half_correlations(p6_thr_guard),
      p6_half_correlations(p6_comb_guard)
    )
  ),
  tar_target(
    p6_guard_summary_sub,
    dplyr::bind_rows(
      p6_half_correlations(p6_rc_guard, by = "subfamily"),
      p6_half_correlations(p6_thr_guard, by = "subfamily"),
      p6_half_correlations(p6_comb_guard, by = "subfamily")
    )
  ),

  # Owen's cell against the guard, named explicitly because the brief asks.
  tar_target(
    p6_owen_guard,
    p6_thr_guard |>
      dplyr::filter(picker == "P5", filter == "P5 / P>0.15, ratio>1.30") |>
      dplyr::select(bet, roi, roi_h1, roi_h2, n_bets, n_bets_h1, n_bets_h2,
                    rank_full, rank_h1, rank_h2, n_eligible, cutoff,
                    survives, struck_because, mean_sp)
  ),

  # -- STAGE 3: the test split, scored once -------------------------------
  tar_target(
    p6_round3_shortlists,
    purrr::map(p6_explore_bets,
               function(b) p6_round3_shortlist(p6_rc_guard, p6_comb_guard,
                                               p6_thr_guard, b)) |>
      purrr::list_rbind()
  ),
  tar_target(
    p6_round3_val,
    p6_score_round3(p6_val_cf, p6_val_rc_masks, p6_rc_all_specs,
                    p6_round3_shortlists, p6_val_field_size)
  ),
  tar_target(
    p6_round3_test,
    p6_score_round3(p6_test_cf, p6_test_rc_masks, p6_rc_all_specs,
                    p6_round3_shortlists, p6_test_field_size)
  ),
  tar_target(
    p6_round3_ranks,
    {
      j <- p6_round3_shortlists |>
        dplyr::select(bet, rule, family, subfamily, roles, val_roi,
                      val_roi_h1, val_roi_h2, val_bets, val_mean_sp) |>
        dplyr::left_join(
          dplyr::select(p6_round3_test, bet, rule, test_roi = roi,
                        test_bets = n_bets, test_wins = n_wins,
                        test_mean_sp = mean_sp, test_fair = roi_fair,
                        test_drop1 = roi_drop_top1, ci_lo, ci_hi),
          by = c("bet", "rule")
        )
      list(
        table = j |>
          dplyr::group_by(bet) |>
          dplyr::mutate(val_rank = rank(-val_roi, ties.method = "min"),
                        test_rank = rank(-test_roi, ties.method = "min"),
                        rank_move = test_rank - val_rank) |>
          dplyr::ungroup() |>
          dplyr::arrange(bet, val_rank),
        by_bet = j |>
          dplyr::group_by(bet) |>
          dplyr::summarise(
            n_rules = dplyr::n(),
            spearman = suppressWarnings(stats::cor(val_roi, test_roi,
                                                   method = "spearman")),
            pearson = suppressWarnings(stats::cor(val_roi, test_roi)),
            .groups = "drop"),
        by_family = j |>
          dplyr::group_by(family) |>
          dplyr::summarise(
            n_rules = dplyr::n(),
            spearman = suppressWarnings(stats::cor(val_roi, test_roi,
                                                   method = "spearman")),
            pearson = suppressWarnings(stats::cor(val_roi, test_roi)),
            mean_val_roi = mean(val_roi), mean_test_roi = mean(test_roi),
            .groups = "drop")
      )
    }
  ),

  # Mean prices the paper's prose compares against, as a target rather than
  # three numbers typed into a sentence.
  tar_target(
    p6_price_context,
    tibble::tibble(
      mean_sp_all = mean(p6_val_frame$starting_price_decimal),
      median_sp_all = stats::median(p6_val_frame$starting_price_decimal),
      mean_sp_top_rated = mean(p6_top_rated(p6_val_frame)$starting_price_decimal),
      mean_sp_all_11_12 = mean(
        p6_val_frame$starting_price_decimal[p6_val_frame$field_size %in% 11:12]),
      n_runners_11_12 = sum(p6_val_frame$field_size %in% 11:12)
    )
  ),

  # -- The price-band regression, promoted out of the diagnostics file ----
  # Paper section 3 needs it as a live number, not a transcription from
  # `DIAGNOSTICS.md`.
  tar_target(
    p6_price_band_fit,
    p6_price_band_regression(p6_val_sweep, min_bets = 300L)
  ),

  # -- THE PAPER ----------------------------------------------------------
  # Rendered locally. NOT published: `docs/` is untouched, the site index is
  # not updated, and `scripts/publish_docs.R` has no paper-6 row.
  tar_quarto(
    paper_6_betting_strategy,
    path = "papers/06_betting_strategy",
    quiet = FALSE,
    extra_files = c(
      "papers/06_betting_strategy/_01_searched.qmd",
      "papers/06_betting_strategy/_02_found.qmd",
      "papers/06_betting_strategy/_03_priceband.qmd",
      "papers/06_betting_strategy/_04_staking.qmd",
      "papers/06_betting_strategy/_05_forward.qmd",
      "papers/06_betting_strategy/_06_limitations.qmd",
      "papers/06_betting_strategy/_helpers.R",
      "papers/06_betting_strategy/references.bib",
      "papers/06_betting_strategy/_quarto.yml"
    )
  )
)
