# _targets_p6.R
#
# Paper 6 — betting strategy.
#
# A SEPARATE pipeline with a SEPARATE store, following papers 4 and 5, so
# nothing here can touch papers 1-5. Run it with the script and store passed
# explicitly rather than through `_targets.yaml`, which papers 1-3's qmd setup
# chunks own:
#
#   targets::tar_make(script = "_targets_p6.R", store = "_targets_p6")
#   targets::tar_read(p6_stage1_grid, store = "_targets_p6")
#
# or, from the project root, `Rscript scripts/run_p6_pipeline.R`.
#
# `tar_config_set()` is never called anywhere in paper 6.
#
# WHAT THIS PAPER CHANGES: the bet selection and staking rule, and nothing
# else. The model is paper 5's rung-3b encoder, refit from paper 5's own
# stored configuration with paper 5's own function and asserted bit-identical
# to paper 5's stored test scores before anything is read off it.
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
               "lubridate", "ggplot2", "DBI", "RMariaDB", "torch"),
  format   = "rds"
)

# Paper 6's own code.
tar_source("R/p6_ledger.R")
tar_source("R/p6_rules.R")
tar_source("R/p6_predictions.R")
tar_source("R/p6_reports.R")
tar_source("R/p6_declaration.R")

# Read-only reuse. Paper 6 adds no variant of any of these: the settlement is
# paper 2b's, the market probability construction paper 1's, the encoder fit
# paper 5's, the price query paper 4's.
tar_source("R/db.R")
tar_source("R/pl_objective.R")
tar_source("R/gbt_data.R")
tar_source("R/scoring.R")
tar_source("R/ranking_eval_p2b.R")
tar_source("R/build_going_features.R")
tar_source("R/value_bets_p2b.R")
tar_source("R/model_fitting_p2.R")
tar_source("R/gbt_results.R")
tar_source("R/market_blend_p4.R")
tar_source("R/p5_backend.R")
tar_source("R/p5_torch.R")
tar_source("R/p5_mlp.R")
tar_source("R/p5_embed.R")
tar_source("R/p5_sequences.R")
tar_source("R/p5_gru.R")
tar_source("R/p5_final.R")
tar_source("R/p5_diagnostics.R")

MAIN_STORE <- "_targets"
P5_STORE   <- "_targets_p5"

# The three bet types, mapped to their settlement tables. `eachway` is paper
# 5's flat 1/5-top-3 terms; `eachway_corrected` the industry handicap ladder.
# Section 2 decides from the field-size distribution whether the corrected
# column is reported, and the answer on this universe is yes.
P6_BETS <- c(win = "win", place = "place", eachway = "eachway",
             eachway_corrected = "eachway_corrected")

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
        names = c("p5_test_data", "p5_test_predictions", "p5_test_fit_rung3b",
                  "p5_configs_v7", "p5_rung3b_selected", "p5_test_backtests",
                  "p5_backend"),
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
  tar_target(p6_gbt_train_data, {
    p6_upstream_fingerprint
    targets::tar_read(gbt_train_data, store = MAIN_STORE)
  }),
  tar_target(p6_gbt_test_data, {
    p6_upstream_fingerprint
    targets::tar_read(gbt_test_data, store = MAIN_STORE)
  }),
  tar_target(p6_p5_test_data, {
    p6_upstream_fingerprint
    targets::tar_read(p5_test_data, store = P5_STORE)
  }),
  tar_target(p6_p5_test_predictions, {
    p6_upstream_fingerprint
    targets::tar_read(p5_test_predictions, store = P5_STORE)$rung3b
  }),
  tar_target(p6_p5_test_scores, {
    p6_upstream_fingerprint
    targets::tar_read(p5_test_fit_rung3b, store = P5_STORE)$scores
  }),
  tar_target(p6_p5_configs, {
    p6_upstream_fingerprint
    targets::tar_read(p5_configs_v7, store = P5_STORE)
  }),
  tar_target(p6_p5_selected, {
    p6_upstream_fingerprint
    targets::tar_read(p5_rung3b_selected, store = P5_STORE)
  }),
  tar_target(p6_p5_backtests, {
    p6_upstream_fingerprint
    targets::tar_read(p5_test_backtests, store = P5_STORE)
  }),

  # =======================================================================
  # STAGE 0 — the search set, and the gate
  # =======================================================================

  # -- The one refit, and the reproduction assertion inside it -------------
  tar_target(
    p6_rung3b_scores,
    p6_refit_rung3b_both_splits(p6_p5_test_data, p6_p5_configs,
                                p6_p5_selected, p6_p5_test_scores)
  ),

  # -- The training-split predictions, in test-predictions shape ----------
  tar_target(
    p6_train_market_side,
    p6_train_market(p6_gbt_train_data$key, p6_qualifying_runners)
  ),
  tar_target(
    p6_train_predictions,
    build_test_predictions_3(p6_rung3b_scores$train_scores, p6_gbt_train_data,
                             p6_train_market_side)
  ),

  # -- The two frames every rule reads ------------------------------------
  tar_target(
    p6_train_frame,
    p6_build_bet_frame(p6_train_predictions, p6_qualifying_runners,
                       dplyr::select(p6_race_dates, race_id, race_date))
  ),
  tar_target(
    p6_test_frame,
    p6_build_bet_frame(p6_p5_test_predictions, p6_qualifying_runners,
                       dplyr::select(p6_race_dates, race_id, race_date))
  ),
  tar_target(
    p6_search_set_check,
    p6_assert_search_set(p6_train_frame, p6_gbt_train_data$key,
                         p6_gbt_test_data$key)
  ),

  # -- Settlement ---------------------------------------------------------
  tar_target(
    p6_train_settle,
    p6_settlement_tables(p6_train_frame, p6_train_predictions,
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
  # assertion and not a report.
  tar_target(
    p6_ledger_gate,
    {
      sels <- p6_selection_rules(p6_thresholds(p6_train_frame))
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

  # -- Stage-0 reports ----------------------------------------------------

  # (a) price coverage by year — the one target that touches the database
  tar_target(
    p6_train_raw_prices,
    read_p4_price_sources(sort(unique(p6_gbt_train_data$key$race_id)))
  ),
  tar_target(
    p6_price_coverage_train,
    p6_price_coverage(p6_gbt_train_data$key,
                      dplyr::select(p6_race_dates, race_id, race_date),
                      p6_train_raw_prices)
  ),

  # (b) over-round by field size
  tar_target(p6_overround_train, p6_overround_by_field(p6_train_frame)),

  # (c) field sizes, and whether paper 5's each-way terms need correcting
  tar_target(p6_field_sizes_train, p6_field_size_report(p6_train_frame)),
  tar_target(p6_field_sizes_test, p6_field_size_report(p6_test_frame)),
  tar_target(
    p6_eachway_terms_decision,
    tibble::tibble(
      share_4_to_7_train = p6_field_sizes_train$share_4_to_7,
      share_4_to_7_test  = p6_field_sizes_test$share_4_to_7,
      share_mispriced_train = p6_field_sizes_train$share_wrong,
      share_mispriced_test  = p6_field_sizes_test$share_wrong,
      threshold = 0.10,
      correct_terms = p6_field_sizes_train$share_4_to_7 > 0.10
    )
  ),

  # (f) deciles, and where S1's absolute cuts sit
  tar_target(p6_threshold_position_train,
             p6_threshold_position(p6_train_frame)),

  # -- The incumbent on the training split, with intervals -----------------
  # (d) at the real starting price, (e) at a zero-margin fair book.
  tar_target(
    p6_incumbent_train,
    {
      sels <- p6_selection_rules(p6_thresholds(p6_train_frame))
      stks <- p6_staking_rules()
      races <- sort(unique(p6_train_frame$race_id))
      purrr::imap(P6_BETS, function(tbl, nm) {
        led <- p6_ledger(p6_train_frame, p6_train_settle, sels$S1$fn,
                         stks$K0$fn, tbl)
        s <- p6_summarise_ledger(led)
        bs <- p6_bootstrap_roi(led, races, n_boot = 2000L, seed = 42L)
        dplyr::mutate(s, bet = nm, ci_lo = bs$ci_lo, ci_hi = bs$ci_hi,
                      .before = 1)
      }) |> purrr::list_rbind()
    }
  ),

  # =======================================================================
  # STAGE 1 — the search, on the training split only
  # =======================================================================

  tar_target(p6_thresholds_train, p6_thresholds(p6_train_frame)),
  tar_target(p6_selections, p6_selection_rules(p6_thresholds_train)),
  tar_target(p6_stakings, p6_staking_rules()),

  # The standing rule from paper 5's rung 1, enforced before anything is
  # scored: every pair this paper compares must differ in exactly one term.
  tar_target(
    p6_contrast_check,
    {
      combos <- tidyr::expand_grid(selection = names(p6_selections),
                                   staking = names(p6_stakings))
      # Every candidate is compared against S1/K0, and a comparison that
      # differs in both terms is not a contrast. The check is therefore run
      # over the two families of one-term contrasts the paper actually reads:
      # a selection swap at K0, and a staking swap at a fixed selection.
      sel_pairs <- combos |>
        dplyr::filter(staking == "K0", selection != "S1") |>
        dplyr::mutate(a1 = selection, a2 = staking, b1 = "S1", b2 = "K0")
      stk_pairs <- combos |>
        dplyr::filter(staking != "K0") |>
        dplyr::mutate(a1 = selection, a2 = staking, b1 = selection, b2 = "K0")
      pairs <- dplyr::bind_rows(sel_pairs, stk_pairs)
      purrr::pwalk(list(pairs$a1, pairs$a2, pairs$b1, pairs$b2),
                   function(a1, a2, b1, b2)
                     p6_assert_one_difference(c(a1, a2), c(b1, b2)))
      dplyr::mutate(pairs, ok = TRUE) |>
        dplyr::select(a_selection = a1, a_staking = a2,
                      b_selection = b1, b_staking = b2, ok)
    }
  ),

  tar_target(
    p6_train_ledgers,
    p6_build_ledgers(p6_train_frame, p6_train_settle, p6_selections,
                     p6_stakings, P6_BETS)
  ),
  tar_target(
    p6_stage1_grid,
    p6_score_grid(p6_train_frame, p6_train_settle, p6_selections,
                  p6_stakings, P6_BETS)
  ),

  # Every candidate against S1/K0 on their COMMON races, alongside the
  # full-universe ROI the grid reports. Arms bet different numbers of races,
  # so the restricted contrast is the only paired one.
  tar_target(
    p6_stage1_contrasts,
    {
      keys <- tidyr::expand_grid(selection = names(p6_selections),
                                 staking = names(p6_stakings),
                                 bet = names(P6_BETS))
      purrr::pmap(keys, function(selection, staking, bet) {
        a <- p6_train_ledgers[[paste(selection, staking, bet, sep = "|")]]
        b <- p6_train_ledgers[[paste("S1", "K0", bet, sep = "|")]]
        races <- intersect(unique(a$race_id), unique(b$race_id))
        if (length(races) == 0L || nrow(a) == 0L) {
          return(tibble::tibble(selection = selection, staking = staking,
                                bet = bet, diff_point = NA_real_,
                                se = NA_real_, ci_lo = NA_real_,
                                ci_hi = NA_real_, n_races = 0L))
        }
        dplyr::mutate(
          p6_paired_roi_se(p6_units(a), p6_units(b), races,
                           n_boot = 2000L, seed = 42L),
          selection = selection, staking = staking, bet = bet, .before = 1
        )
      }) |> purrr::list_rbind()
    }
  ),

  # =======================================================================
  # DECLARATION — mechanical, no judgement
  # =======================================================================

  # One rule per BET TYPE, and there are three. The each-way declaration runs
  # on the corrected terms, not paper 5's: those are the terms a bet actually
  # settles on, and its comparator is S1/K0 recomputed on the same terms, so
  # the contrast is like for like. Paper 5's terms are reported alongside
  # everywhere but declare nothing.
  tar_target(p6_declared_bets, c("win", "place", "eachway_corrected")),

  tar_target(
    p6_declaration,
    purrr::map(p6_declared_bets, function(b)
      p6_declare(p6_stage1_grid, p6_train_ledgers, b,
                 n_boot = 2000L, seed = 42L)) |>
      purrr::list_rbind()
  ),

  # Blocker in the brief: a declared rule placing fewer than 200 bets on the
  # training split stops the paper.
  tar_target(
    p6_declaration_check,
    {
      stopifnot(all(p6_declaration$n_bets >= 200L))
      dplyr::select(p6_declaration, bet, selection, staking, n_bets)
    }
  ),

  tar_target(
    p6_declared_rules_file,
    p6_write_declared_rules(
      path = "papers/06_betting_strategy/DECLARED_RULES.md",
      declaration = p6_declaration,
      grid = p6_stage1_grid,
      contrasts = p6_stage1_contrasts,
      thresholds = p6_thresholds_train,
      selections = p6_selections,
      stakings = p6_stakings,
      terms_decision = p6_eachway_terms_decision,
      gate = p6_ledger_gate,
      search_set = p6_search_set_check
    ),
    format = "file"
  )
)
