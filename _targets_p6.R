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
#   targets::tar_read(p6_stage_a_grid, store = "_targets_p6")
#
# or, from the project root, `Rscript scripts/run_p6_pipeline.R`, optionally
# naming a target to build up to.
#
# `tar_config_set()` is never called anywhere in paper 6.
#
# WHAT THIS PAPER CHANGES: the bet selection and staking rule, and nothing
# else. Paper 6 fits no model and refits nothing. Both prediction sets are
# paper 5's own stored targets:
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

MAIN_STORE <- "_targets"
P5_STORE   <- "_targets_p5"

# The three bet types, mapped to their settlement tables. `eachway` is paper
# 5's flat 1/5-top-3 terms; `eachway_corrected` the industry handicap ladder.
# Both are reported everywhere; only the corrected column declares anything.
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
  # STAGE A — selection, at a flat stake, on the validation slice
  # =======================================================================

  tar_target(p6_thresholds_val, p6_thresholds(p6_val_frame)),
  tar_target(p6_thresholds_test, p6_thresholds(p6_test_frame)),
  tar_target(p6_selections_val, p6_selection_rules(p6_thresholds_val)),
  tar_target(p6_selections_test, p6_selection_rules(p6_thresholds_test)),
  tar_target(p6_stakings, p6_staking_rules()),

  tar_target(
    p6_stage_a_arms,
    tibble::tibble(selection = names(p6_selections_val), staking = "K0")
  ),

  # Paper 5's rung-1 rule, enforced before anything is scored: every pair the
  # paper reads differs in exactly one term. Stage A varies selection at fixed
  # K0; stage B varies staking at a fixed selection.
  tar_target(
    p6_contrast_check,
    {
      a_pairs <- p6_stage_a_arms |>
        dplyr::filter(selection != "S1") |>
        dplyr::transmute(a_selection = selection, a_staking = staking,
                         b_selection = "S1", b_staking = "K0", stage = "A")
      b_pairs <- tibble::tibble(
        a_selection = "<declared>", a_staking = c("K1", "K2"),
        b_selection = "<declared>", b_staking = "K0", stage = "B"
      )
      walk_pairs <- function(d) {
        purrr::pwalk(
          list(d$a_selection, d$a_staking, d$b_selection, d$b_staking),
          function(a1, a2, b1, b2)
            p6_assert_one_difference(c(a1, a2), c(b1, b2))
        )
      }
      walk_pairs(a_pairs)
      walk_pairs(b_pairs)
      dplyr::mutate(dplyr::bind_rows(a_pairs, b_pairs), ok = TRUE)
    }
  ),

  tar_target(
    p6_stage_a_ledgers,
    p6_build_ledgers(p6_val_frame, p6_val_settle, p6_stage_a_arms,
                     p6_selections_val, p6_stakings, P6_BETS)
  ),
  tar_target(
    p6_stage_a_grid,
    p6_apply_eligibility(
      p6_score_arms(p6_val_frame, p6_val_settle, p6_stage_a_arms,
                    p6_selections_val, p6_stakings, P6_BETS),
      n_val = p6_universe$n_val_races, n_test = p6_universe$n_test_races
    )
  ),

  tar_target(
    p6_stage_a_contrasts,
    {
      keys <- tidyr::expand_grid(selection = p6_stage_a_arms$selection,
                                 bet = names(P6_BETS))
      purrr::pmap(keys, function(selection, bet) {
        a <- p6_stage_a_ledgers[[paste(selection, "K0", bet, sep = "|")]]
        b <- p6_stage_a_ledgers[[paste("S1", "K0", bet, sep = "|")]]
        races <- intersect(unique(a$race_id), unique(b$race_id))
        if (length(races) == 0L || nrow(a) == 0L) {
          return(tibble::tibble(selection = selection, bet = bet,
                                diff_point = NA_real_, se = NA_real_,
                                ci_lo = NA_real_, ci_hi = NA_real_,
                                n_races = 0L))
        }
        dplyr::mutate(
          p6_paired_roi_se(p6_units(a), p6_units(b), races,
                           n_boot = 2000L, seed = 42L),
          selection = selection, bet = bet, .before = 1
        )
      }) |> purrr::list_rbind()
    }
  ),

  # -- Does the gate have teeth? A diagnostic, declaring nothing -----------
  # Stage A runs at K0, where every selected race is staked by construction,
  # and stage B runs on whatever stage A declared. The gate can therefore
  # strike nothing in either pool without that meaning it is inert. This
  # scores the full nine-by-three cross-product on the VALIDATION SLICE and
  # applies the same gate to it, purely to show what it would strike. Nothing
  # in the declaration reads this target: `p6_declare_step()` is passed the
  # stage grids, never this one.
  tar_target(
    p6_gate_demo_arms,
    tidyr::expand_grid(selection = names(p6_selections_val),
                       staking = names(p6_stakings))
  ),
  tar_target(
    p6_gate_demonstration,
    p6_apply_eligibility(
      p6_score_arms(p6_val_frame, p6_val_settle, p6_gate_demo_arms,
                    p6_selections_val, p6_stakings, P6_BETS),
      n_val = p6_universe$n_val_races, n_test = p6_universe$n_test_races
    )
  ),

  # The three bet types a rule is declared for. Each-way declares on the
  # corrected terms — those are the terms a bet settles on — and its
  # comparator is recomputed on the same terms.
  tar_target(p6_declared_bets, c("win", "place", "eachway_corrected")),

  tar_target(
    p6_declaration_a,
    purrr::map(p6_declared_bets, function(b)
      p6_declare_step(p6_stage_a_grid, p6_stage_a_ledgers, b,
                      comparator = c("S1", "K0"), stage = "A",
                      n_boot = 2000L, seed = 42L)) |>
      purrr::list_rbind()
  ),

  # =======================================================================
  # STAGE B — staking, on the declared selection only
  # =======================================================================

  tar_target(
    p6_stage_b_arms,
    tidyr::expand_grid(
      selection = unique(p6_declaration_a$selection),
      staking = names(p6_stakings)
    )
  ),
  tar_target(
    p6_stage_b_ledgers,
    p6_build_ledgers(p6_val_frame, p6_val_settle, p6_stage_b_arms,
                     p6_selections_val, p6_stakings, P6_BETS)
  ),
  tar_target(
    p6_stage_b_grid,
    p6_apply_eligibility(
      p6_score_arms(p6_val_frame, p6_val_settle, p6_stage_b_arms,
                    p6_selections_val, p6_stakings, P6_BETS),
      n_val = p6_universe$n_val_races, n_test = p6_universe$n_test_races
    )
  ),

  tar_target(
    p6_declaration_b,
    purrr::map(p6_declared_bets, function(b) {
      sel <- p6_declaration_a$selection[p6_declaration_a$bet == b]
      stopifnot(length(sel) == 1L)
      g <- dplyr::filter(p6_stage_b_grid, selection == sel)
      p6_declare_step(g, p6_stage_b_ledgers, b, comparator = c(sel, "K0"),
                      stage = "B", n_boot = 2000L, seed = 42L)
    }) |> purrr::list_rbind()
  ),

  tar_target(
    p6_declaration,
    dplyr::bind_rows(p6_declaration_a, p6_declaration_b)
  ),

  tar_target(
    p6_declared_rules_file,
    p6_write_declared_rules(
      path = "papers/06_betting_strategy/DECLARED_RULES.md",
      declaration = p6_declaration,
      grid_a = p6_stage_a_grid,
      grid_b = p6_stage_b_grid,
      contrasts_a = p6_stage_a_contrasts,
      thresholds = p6_thresholds_val,
      selections = p6_selections_val,
      stakings = p6_stakings,
      terms_decision = p6_eachway_terms_decision,
      gate = p6_ledger_gate,
      search_set = p6_search_set_check,
      provenance = p6_fit_provenance_tbl,
      positions = p6_positions,
      gate_demo = p6_gate_demonstration
    ),
    format = "file"
  ),

  # =======================================================================
  # STAGE 2 - the test split, scored once
  #
  # The arms that reach the test split, and no others:
  #   * the declared SELECTION at K0, per bet type (stage A's result)
  #   * the declared STAKE on that selection, where stage B declared
  #     something other than K0
  #   * S1/K0, paper 5's incumbent
  #   * S4/K0, the market-only control
  #
  # The declaration file is committed before any target below exists, and
  # `p6_declaration_frozen` re-reads it from disk and matches it against the
  # declaration target, so a later change to either is caught rather than
  # absorbed.
  # =======================================================================

  tar_target(
    p6_declaration_frozen,
    {
      txt <- readLines(p6_declared_rules_file, warn = FALSE)
      # Section 1's table only: later sections carry a `bet` column too, and
      # matching across the whole file would pick up other tables as well.
      from <- grep("^## 1[.] The declaration", txt)
      to   <- grep("^## 2[.] ", txt)
      stopifnot(length(from) == 1L, length(to) == 1L, to > from)
      txt <- txt[seq(from, to)]

      row <- function(stage, bet) {
        pat <- switch(
          bet,
          win = "^[|] %s [|] win [|]",
          place = "^[|] %s [|] place [|]",
          eachway_corrected = "^[|] %s [|] each-way [(]corrected terms[)] [|]"
        )
        line <- grep(sprintf(pat, stage), txt, value = TRUE)
        stopifnot(length(line) == 1L)
        cells <- trimws(strsplit(line, "|", fixed = TRUE)[[1]])
        cells <- cells[nzchar(cells)]
        parts <- strsplit(cells[3], "/", fixed = TRUE)[[1]]
        stopifnot(length(parts) == 2L)
        tibble::tibble(stage = stage, bet = bet,
                       selection = parts[1], staking = parts[2])
      }

      from_file <- purrr::map(c("A", "B"), function(st)
        purrr::map(p6_declared_bets, function(b) row(st, b)) |>
          purrr::list_rbind()) |> purrr::list_rbind()
      from_target <- p6_declaration |>
        dplyr::select(stage, bet, selection, staking)
      stopifnot(identical(as.data.frame(from_file),
                          as.data.frame(from_target)))
      from_file
    }
  ),

  # The entire test contact, enumerated. Anything not on this list is not
  # scored on test. Where stage B declared K0 the staking arm coincides with
  # the selection arm and adds no row; where stage A declared S1 the selection
  # arm coincides with the incumbent and adds no row. Those coincidences are
  # recorded rather than hidden: `roles` says what each arm stands for.
  tar_target(
    p6_test_arms,
    {
      decl_a <- p6_declaration_frozen |> dplyr::filter(stage == "A")
      decl_b <- p6_declaration_frozen |> dplyr::filter(stage == "B")

      rows <- dplyr::bind_rows(
        decl_a |>
          dplyr::transmute(bet, selection, staking = "K0",
                           role = "declared selection, flat stake"),
        decl_b |>
          dplyr::filter(staking != "K0") |>
          dplyr::transmute(bet, selection, staking,
                           role = "declared selection, declared stake"),
        tidyr::expand_grid(bet = p6_declared_bets, selection = "S1",
                           staking = "K0") |>
          dplyr::mutate(role = "S1/K0, paper 5 incumbent"),
        tidyr::expand_grid(bet = p6_declared_bets, selection = "S4",
                           staking = "K0") |>
          dplyr::mutate(role = "S4/K0, market-only control")
      )

      # Collapse coincident arms: one ledger per distinct rule, with every
      # role it plays recorded on it.
      rows |>
        dplyr::group_by(selection, staking) |>
        dplyr::summarise(roles = paste(sort(unique(role)), collapse = "; "),
                         .groups = "drop") |>
        dplyr::mutate(arm = paste0(selection, "/", staking))
    }
  ),

  tar_target(
    p6_test_ledgers,
    p6_build_ledgers(p6_test_frame, p6_test_settle, p6_test_arms,
                     p6_selections_test, p6_stakings, P6_BETS)
  ),

  tar_target(
    p6_test_results,
    {
      races <- sort(unique(p6_test_frame$race_id))
      purrr::imap(p6_test_ledgers, function(led, key) {
        parts <- strsplit(key, "|", fixed = TRUE)[[1]]
        arm <- paste(parts[1], parts[2], sep = "/")
        s <- p6_summarise_ledger(led)
        bs <- p6_bootstrap_roi(led, races, n_boot = 2000L, seed = 42L)
        dplyr::mutate(s, arm = arm, bet = parts[3],
                      ci_lo = bs$ci_lo, ci_hi = bs$ci_hi, .before = 1)
      }) |>
        purrr::list_rbind() |>
        dplyr::left_join(dplyr::select(p6_test_arms, arm, roles), by = "arm")
    }
  ),

  # The four contrasts the brief names, run whether or not they are
  # degenerate. Where two arms coincide the difference is identically zero by
  # construction and is reported as such rather than omitted.
  tar_target(
    p6_test_contrasts,
    {
      decl_a <- p6_declaration_frozen |> dplyr::filter(stage == "A")
      decl_b <- p6_declaration_frozen |> dplyr::filter(stage == "B")

      arm_of <- function(sel, stk) paste(sel, stk, sep = "/")
      bet_of <- function(b) if (b == "eachway_corrected")
        c("eachway", "eachway_corrected") else b

      spec <- purrr::map(p6_declared_bets, function(b) {
        sel <- decl_a$selection[decl_a$bet == b]
        stk <- decl_b$staking[decl_b$bet == b]
        tidyr::expand_grid(
          bet_col = bet_of(b),
          question = c("did selection help?", "did staking help?",
                       "does the declared rule beat a rule with no model?",
                       "does the incumbent beat a rule with no model?")
        ) |>
          dplyr::mutate(
            a = dplyr::case_when(
              question == "did selection help?" ~ arm_of(sel, "K0"),
              question == "did staking help?" ~ arm_of(sel, stk),
              question == "does the declared rule beat a rule with no model?" ~
                arm_of(sel, "K0"),
              TRUE ~ arm_of("S1", "K0")
            ),
            b = dplyr::case_when(
              question == "did selection help?" ~ arm_of("S1", "K0"),
              question == "did staking help?" ~ arm_of(sel, "K0"),
              TRUE ~ arm_of("S4", "K0")
            )
          )
      }) |> purrr::list_rbind()

      key_of <- function(arm, bet_col) {
        parts <- strsplit(arm, "/", fixed = TRUE)[[1]]
        paste(parts[1], parts[2], bet_col, sep = "|")
      }

      purrr::pmap(spec, function(bet_col, question, a, b) {
        la <- p6_test_ledgers[[key_of(a, bet_col)]]
        lb <- p6_test_ledgers[[key_of(b, bet_col)]]
        stopifnot(!is.null(la), !is.null(lb))
        if (identical(a, b)) {
          return(tibble::tibble(
            diff_point = 0, se = 0, ci_lo = 0, ci_hi = 0,
            n_races = length(unique(la$race_id)),
            bet = bet_col, question = question, a_arm = a, b_arm = b,
            degenerate = TRUE
          ))
        }
        races <- intersect(unique(la$race_id), unique(lb$race_id))
        dplyr::mutate(
          p6_paired_roi_se(p6_units(la), p6_units(lb), races,
                           n_boot = 2000L, seed = 42L),
          bet = bet_col, question = question, a_arm = a, b_arm = b,
          degenerate = FALSE
        )
      }) |> purrr::list_rbind()
    }
  ),

  # The margin decomposition: what each arm returns at the real starting
  # price, at a zero-margin fair book, and the gap between them - the margin
  # that arm pays. A rule that improves ROI by betting shorter prices has
  # reduced the margin it pays, not demonstrated skill.
  tar_target(
    p6_margin_decomposition,
    p6_test_results |>
      dplyr::transmute(arm, bet, n_bets, roi, roi_fair,
                       margin_paid = roi_fair - roi,
                       mean_stake, sd_unit_return, max_drawdown)
  ),

  # How many races each test arm's selection picks before staking is applied.
  tar_target(
    p6_test_selection_sizes,
    p6_test_arms |>
      dplyr::rowwise() |>
      dplyr::mutate(
        n_races_selected =
          nrow(p6_selections_test[[selection]]$fn(p6_test_frame))
      ) |>
      dplyr::ungroup()
  ),

  # The incumbent's own validation-slice interval, for the power discussion.
  # Descriptive and computed after the freeze: it declares nothing, and the
  # declaration file it would have to change is already committed. It is here
  # because the paper needs to say how much the validation slice could see,
  # and a point estimate cannot say that.
  tar_target(
    p6_val_incumbent,
    {
      races <- sort(unique(p6_val_frame$race_id))
      purrr::imap(P6_BETS, function(tbl, nm) {
        led <- p6_ledger(p6_val_frame, p6_val_settle,
                         p6_selections_val$S1$fn, p6_stakings$K0$fn, tbl)
        s <- p6_summarise_ledger(led)
        bs <- p6_bootstrap_roi(led, races, n_boot = 2000L, seed = 42L)
        dplyr::mutate(s, bet = nm, ci_lo = bs$ci_lo, ci_hi = bs$ci_hi,
                      .before = 1)
      }) |> purrr::list_rbind()
    }
  ),

  # -- Figures -------------------------------------------------------------
  tar_target(p6_fig_cumulative, p6_plot_cumulative_profit(p6_test_ledgers)),
  tar_target(p6_fig_val_vs_test,
             p6_plot_val_vs_test(p6_stage_a_grid, p6_test_results, "win")),

  tar_target(
    p6_test_report_file,
    p6_write_test_report(
      path = "papers/06_betting_strategy/P6_TEST_REPORT.md",
      results = p6_test_results,
      contrasts = p6_test_contrasts,
      margins = p6_margin_decomposition,
      declaration = p6_declaration_frozen,
      arms = p6_test_arms,
      selection_sizes = p6_test_selection_sizes
    ),
    format = "file"
  ),

  # =======================================================================
  # THE PAPER
  #
  # Rendered inside this pipeline, as papers 4 and 5 are. `quiet = FALSE` so
  # quarto's own error output surfaces instead of a bare "System command
  # failed". NOT published: `docs/` is untouched by this pipeline and the
  # site index is not updated.
  # =======================================================================
  tar_quarto(
    paper_6_betting_strategy,
    path = "papers/06_betting_strategy",
    quiet = FALSE,
    extra_files = c(
      "papers/06_betting_strategy/_01_result.qmd",
      "papers/06_betting_strategy/_02_method.qmd",
      "papers/06_betting_strategy/_03_search.qmd",
      "papers/06_betting_strategy/_04_test.qmd",
      "papers/06_betting_strategy/_05_discussion.qmd",
      "papers/06_betting_strategy/_appx_a_settlement.qmd",
      "papers/06_betting_strategy/_appx_b_software.qmd",
      "papers/06_betting_strategy/_helpers.R",
      "papers/06_betting_strategy/references.bib",
      "papers/06_betting_strategy/_quarto.yml"
    )
  )
)
