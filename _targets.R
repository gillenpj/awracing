# _targets.R
#
# Pipeline definition for the awracing project.
#
# Each target that hits the database opens and closes its own connection
# inside the target body, so connections are never serialised to disk
# between targets.

# -- Subprocess environment for `tar_quarto()` ----------------------------
# `tarchetypes::tar_quarto()` launches `quarto.exe` as a child process,
# which in turn launches a fresh R session to execute the qmd's code
# chunks. That child session only inherits *environment variables* — not
# the parent's `.libPaths()` — so without the variables set below it
# resolves `Rscript` from PATH (R 4.2.2 on this machine, no `targets` /
# `rmarkdown` installed) and never sees the renv-managed library that
# the parent loaded via `source("renv/activate.R")`. The result is
# `tar_make()` failing with a cryptic "System command 'quarto.exe'
# failed" while a direct `quarto render` works.
#
# Two env vars fix it portably:
#   R_LIBS    — passes the parent's library paths (renv lib + sandbox
#               + system) to the child R session as a path-separated
#               list (`;` on Windows, `:` elsewhere).
#   QUARTO_R  — pins the child R session to the same R binary the
#               parent is running, so package availability is
#               guaranteed identical.
# The QUARTO_PATH fallback searches the common install locations for
# the Quarto CLI on this machine (RStudio bundles its own copy at the
# first path); on machines where Quarto is on PATH it can be left
# unset.
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
library(conflicted)
conflict_prefer("filter", "dplyr")
conflict_prefer("lag",    "dplyr")

tar_source()

# -- Project-wide date constants -------------------------------------------
# Window bounds and the chronological train/test cutoff. The split is 70%
# / 30% of `qualifying_races` by race count chronologically; the cutoff
# date is frozen to 2012-12-30 so the split is reproducible against an
# exact date irrespective of upstream changes (Session decision).
date_from   <- "2006-01-01"
date_to     <- "2015-10-14"
cutoff_date <- as.Date("2012-12-30")

list(

  # -- AW course constant ----------------------------------------------------
  # Single source of truth for the four AW course names. Consumed by
  # candidate_races (interpolated into the SQL) and by the cross-surface
  # notebook (for its inline daysLTO diagnostic).
  tar_target(
    aw_courses,
    c("Kempton", "Lingfield", "Southwell", "Wolverhampton")
  ),

  # -- SQL file dependency ---------------------------------------------------
  # Tracks sql/qualifying_races.sql as a file target so edits to the SQL
  # invalidate candidate_races automatically. Without this, targets has no
  # visibility into the SQL file and rebuilds must be forced manually via
  # tar_invalidate(candidate_races).
  tar_target(
    qualifying_races_sql,
    "sql/qualifying_races.sql",
    format = "file"
  ),

  # -- Candidate races --------------------------------------------------------
  # Raw SQL output from qualifying_races.sql: races passing the DB-level
  # filters (race_type, course, maiden, class, date, declared field size).
  # Lower date bound is 2006-01-01: the British class system was
  # restructured 1 Jan 2006 and pre-2006 multi-digit class codes
  # (11, 42, 53, ...) are not comparable with the 2006+ 1-7 scheme.
  #
  # Some of these races will be removed by the R-level filters in
  # extract_runners_for_races (post-Non-Runner field-size cut; one-winner
  # requirement). The downstream `qualifying_races` target is this set
  # filtered to match.
  tar_target(
    candidate_races,
    {
      qualifying_races_sql  # force dependency on the SQL file target
      con <- connect_smartform()
      on.exit(disconnect_smartform(con))
      extract_qualifying_races(con,
        date_from  = date_from,
        date_to    = date_to,
        aw_courses = aw_courses
      )
    }
  ),

  # -- Runners in qualifying races --------------------------------------------
  # Applies Non-Runner removal, the `won` rule (coalesce amended_position
  # over finish_position), and the post-Non-Runner race-level filters:
  # >= 4 actual starters and exactly one winner per race.
  tar_target(
    qualifying_runners,
    {
      con <- connect_smartform()
      on.exit(disconnect_smartform(con))
      extract_runners_for_races(con, candidate_races$race_id)
    }
  ),

  # -- Qualifying races -------------------------------------------------------
  # Candidate races filtered to races that survived the R-level cuts in
  # qualifying_runners. This keeps the two targets agreeing on the set of
  # races (review bundle: "The two targets must agree on the set of races").
  tar_target(
    qualifying_races,
    dplyr::filter(candidate_races, race_id %in% unique(qualifying_runners$race_id))
  ),

  # -- Train/test split (chronological 70/30 by race count) ------------------
  # Cutoff frozen at 2012-12-30 (see top-of-file constant). All races on or
  # before the cutoff go to training; everything after goes to test. The
  # split is on race date, so every runner in a race stays together in one
  # set — no leakage of within-race information across the split.
  tar_target(
    races_train,
    dplyr::filter(qualifying_races, meeting_date <= cutoff_date)
  ),

  tar_target(
    races_test,
    dplyr::filter(qualifying_races, meeting_date >  cutoff_date)
  ),

  # -- AW runner population --------------------------------------------------
  # Unique horses that have started in at least one qualifying AW race.
  # All downstream targets are anchored to this set.
  tar_target(
    aw_runner_ids,
    get_aw_runner_ids(qualifying_runners)
  ),

  # -- Full cross-surface career history -------------------------------------
  # File-tracked so edits to horse_full_history.sql (e.g. paper 3's addition
  # of r.going) invalidate full_history automatically, matching the
  # qualifying_races_sql / trainer_sire_cumulative_sql pattern.
  tar_target(
    full_history_sql,
    "sql/horse_full_history.sql",
    format = "file"
  ),
  tar_target(
    full_history,
    {
      full_history_sql  # force dep on SQL file target
      con <- connect_smartform()
      on.exit(disconnect_smartform(con))
      extract_career_history(con, aw_runner_ids)
    }
  ),

  # -- Raw easy features (Phase 1a) ------------------------------------------
  tar_target(
    raw_easy_features,
    build_raw_easy_features(qualifying_runners)
  ),

  # -- Prior-finish position lags (Owen's position1/2/3) ---------------------
  # For each (race_id, runner_id) finds the three most recent runs in
  # full_history strictly before that race's meeting_date (Non-Runners
  # excluded), encoded so positions 1..4 keep their value and everything
  # else (no prior run, worse finish, unknown) maps to 0.
  tar_target(
    position_lags,
    build_position_lags(qualifying_runners, full_history, qualifying_races)
  ),

  # -- Trainer + sire cumulative wins/races (SQL window functions) -----------
  # Pre-aggregated cumulative wins and races per (entity, meeting_date),
  # entity being either a sire or trainer (distinguished by `kind`).
  # Computing this in SQL via window functions replaces an earlier
  # in-R cumsum step that took >21 hours on the 1.72M-row source.
  # The SQL file target wires the
  # query file as a dependency so edits invalidate the cumulative
  # target automatically.
  tar_target(
    trainer_sire_cumulative_sql,
    "sql/trainer_sire_cumulative.sql",
    format = "file"
  ),

  tar_target(
    trainer_sire_cumulative,
    {
      trainer_sire_cumulative_sql  # force dep on SQL file target
      extract_trainer_sire_cumulative()
    },
    format = "qs"
  ),

  # -- Trainer + sire strike rates (Owen's trainerSR / sireSR) ---------------
  # For each qualifying runner-race, the win rate of that horse's
  # trainer and sire over runs strictly before the race's meeting_date.
  # Strictly no leakage: NA when no prior cumulative row exists for the
  # entity (first-time-starter's sire, debut trainer, or unknown id).
  # NA propagates cleanly through summarise_win_rate()'s "(missing)"
  # bin downstream. Raw / uncapped.
  tar_target(
    strike_rates,
    build_strike_rates(qualifying_runners, qualifying_races, trainer_sire_cumulative)
  ),

  # -- Age transformation (Owen's age_diff) ----------------------------------
  # Symmetric-distance encoding of age around a peak of 3 for the AW
  # population. `age_diff = min(|age - 3|, 5)`, with the cap chosen to
  # avoid extrapolating into thin-support ages (>= 9). See
  # R/build_age_transformation.R for the full rationale.
  tar_target(
    age_transformation,
    build_age_transformation(raw_easy_features)
  ),

  # -- Modelling feature tibble (joined) -------------------------------------
  # Single canonical features table consumed by downstream notebooks
  # and modelling targets. Keyed by (race_id, runner_id). Left joins
  # are safe because every spine row (raw_easy_features) has matching
  # rows in position_lags and age_transformation by construction, and
  # strike_rates returns NA cleanly where no prior cumulative row
  # exists.
  tar_target(
    features,
    raw_easy_features |>
      dplyr::left_join(position_lags,      by = c("race_id", "runner_id")) |>
      dplyr::left_join(strike_rates,       by = c("race_id", "runner_id")) |>
      dplyr::left_join(age_transformation, by = c("race_id", "runner_id"))
  ),

  # -- Paper 2 candidate features --------------------------------------------
  # Three extended-feature builders, each keyed by (race_id, runner_id),
  # joined onto paper 1's `features` to form the single augmented runners
  # tibble below. They consume targets that already exist for paper 1
  # (qualifying_runners, qualifying_races, full_history,
  # trainer_sire_cumulative) and do not feed into any paper 1 target, so
  # the replication fit is untouched. See R/build_extended_features.R for
  # the per-feature definitions and leakage / NA notes.

  # jockeySR + trainer/sire/jockey AW premiums (cumulative, pre-race).
  tar_target(
    jockey_sr_premiums,
    build_jockey_sr_and_premiums(
      qualifying_runners, qualifying_races, trainer_sire_cumulative
    )
  ),

  # stall_normalised, rel_weight, or_relative (within-race relative).
  tar_target(
    within_race_features,
    build_within_race_features(qualifying_runners)
  ),

  # class_delta, weight_delta_lbs, first_time_aw, has_wins (career-form
  # lags off full cross-surface history).
  tar_target(
    career_form_features,
    build_career_form_features(
      qualifying_runners, full_history, qualifying_races,
      class_era_floor = date_from
    )
  ),

  # -- Paper 3 going-affinity feature -----------------------------------------
  # going_runs_prior, going_sr_shrunk, going_sr_delta, going_ordinal. Not a
  # paper-2 candidate feature (going was deliberately deferred from paper 2 —
  # see CLAUDE.md "Going interaction — deferred to paper 3"); added here
  # alongside the other runners_augmented builders because it is keyed the
  # same way (race_id, runner_id) and needs the same full_history +
  # qualifying_races inputs. See R/build_going_features.R.
  tar_target(
    going_features,
    build_going_features(qualifying_runners, qualifying_races, full_history)
  ),

  # -- Augmented runners (paper 2 modelling input) ---------------------------
  # Single tibble carrying paper 1's modelling columns plus every new
  # paper-2 candidate feature, plus paper 3's going-affinity feature. This
  # is the one augmented runners target that paper 2's prepare_mlogit_data()
  # and paper 3's GBT feature matrix both consume; paper 1 continues to
  # read the narrower `features` target, so its fit is unchanged. The
  # going_* columns are exempt from paper 2/2a/2b's complete-case NA-drop
  # rule (they are never listed in model_fitting_p2_vars()) since no
  # paper-2/2a/2b formula references them — so their NA-bearing values do
  # not affect any conditional-logit fit's race universe.
  tar_target(
    runners_augmented,
    features |>
      dplyr::left_join(jockey_sr_premiums,   by = c("race_id", "runner_id")) |>
      dplyr::left_join(within_race_features, by = c("race_id", "runner_id")) |>
      dplyr::left_join(career_form_features, by = c("race_id", "runner_id")) |>
      dplyr::left_join(going_features,       by = c("race_id", "runner_id"))
  ),

  # -- Modelling-ready runners (paper 2) -------------------------------------
  # runners_augmented + the settled paper-2 data decisions: or_missing
  # companion + or_relative NULL->0 imputation, plus race_date and the
  # train/test split label. THIS is the canonical tibble every paper-2
  # modelling / exploratory target consumes (not runners_augmented
  # directly). See R/build_extended_features.R::build_model_ready() and
  # the "Paper 2 feature decisions" section of CLAUDE.md.
  tar_target(
    runners_model_ready,
    build_model_ready(runners_augmented, qualifying_races, races_train)
  ),

  # -- Univariate PL-R^2 feature screen (paper 2, training only) -------------
  # One standalone conditional logit per candidate feature, scored by the
  # depth-1 Plackett-Luce R^2 (1 - logL_model / logL_null). Input is
  # runners_augmented restricted to the training races; each feature is
  # scored on its own complete-choice-set subset (see R/feature_screen.R).
  # No test-set data enters this step.
  tar_target(
    feature_screen,
    run_feature_screen(
      dplyr::filter(runners_augmented, race_id %in% races_train$race_id)
    )
  ),

  # -- Position-encoding parsimony test (paper 2, training only) -------------
  # LR test of the parsimonious 2-coefficient position encoding (Model P:
  # equal-weight + lag-weighted score) against paper 1's ~12-coefficient
  # factor encoding (Model F), position lags only. Nested models on one
  # shared mlogit dataset. See R/feature_screen.R::test_position_parsimony().
  tar_target(
    position_parsimony_test,
    test_position_parsimony(
      runners_model_ready |> dplyr::filter(split == "train")
    )
  ),

  # -- Paper 2 extended win model -------------------------------------------
  # Conditional logit on the extended feature set with the Model-S
  # position encoding. Training-only fit; test-only evaluation. Mirrors
  # the paper-1 fitting / diagnostic pattern (R/model_fitting_p2.R reuses
  # the paper-1 prepare/predict/backtest idioms without touching paper-1
  # code). `or_relative` is pre-imputed in runners_model_ready, so the
  # NA-driven race drop here is small (debut trainers/sires/jockeys).
  tar_target(
    mlogit_train_data_p2,
    prepare_mlogit_data_p2(
      runners_model_ready |> dplyr::filter(split == "train")
    )
  ),
  tar_target(
    mlogit_test_data_p2,
    prepare_mlogit_data_p2(
      runners_model_ready |> dplyr::filter(split == "test")
    )
  ),

  # Full (19-term) and reduced (backward-elimination, one iteration) fits.
  tar_target(
    model_p2_full,
    fit_extended_full(mlogit_train_data_p2)
  ),
  tar_target(
    model_p2_reduced,
    fit_extended_reduced(mlogit_train_data_p2, model_p2_full)
  ),

  # Full / reduced fit diagnostics (logLik, null, PL-R², n_races, n_runners).
  tar_target(
    model_p2_diagnostics,
    extract_p2_diagnostics(model_p2_full, model_p2_reduced)
  ),

  # Test-set predictions from the reduced model. build_test_predictions()
  # (paper-1 helper) returns `model_prob`; renamed to `predicted_prob`
  # for the paper-2 interface.
  tar_target(
    test_predictions_p2,
    build_test_predictions(model_p2_reduced, mlogit_test_data_p2, qualifying_runners) |>
      dplyr::rename(predicted_prob = model_prob)
  ),

  # Model/market ratio + betting backtests on the test set, reusing the
  # paper-1 scoring helpers (Owen's exact naive thresholds; the same
  # 0.9-2.0 ratio sweep with the 0.13 prob filter and B=2000 seed-42
  # race-level bootstrap) so the paper-2 ROI is directly comparable to
  # paper 1's -28.2%.
  tar_target(
    model_market_ratio_p2,
    compute_model_market_ratio_p2(test_predictions_p2)
  ),
  tar_target(
    backtest_naive_p2,
    run_backtest(model_market_ratio_p2,
                 prob_threshold  = 0.15,
                 ratio_threshold = 1.3)
  ),
  tar_target(
    backtest_sweep_p2,
    run_backtest_sweep(
      model_market_ratio_p2,
      prob_threshold = 0.13,
      tau_seq        = seq(0.9, 2.0, by = 0.05),
      n_boot         = 2000L,
      seed           = 42L
    )
  ),

  # -- Paper 2 exploded conditional logit (Plackett–Luce, depth k = 3) -------
  # Each training race's finishing order is exploded into k=3 nested choice
  # sets and pooled; a single conditional logit on the same 17-term reduced
  # spec maximises the depth-3 PL likelihood. Finishing positions come from
  # qualifying_runners (runners_model_ready carries only the win
  # indicator), joined in here. Evaluation is depth-1 (win) only, so it is
  # directly comparable to the win model and to paper 1.
  tar_target(
    exploded_train_data,
    prepare_exploded_data(
      runners_model_ready |>
        dplyr::filter(split == "train") |>
        dplyr::left_join(
          dplyr::select(qualifying_runners,
                        race_id, runner_id, finish_position, amended_position),
          by = c("race_id", "runner_id")
        )
    )
  ),
  tar_target(
    model_2b_exploded_base,
    fit_exploded_model(exploded_train_data, model_p2_reduced)
  ),
  tar_target(
    model_2b_exploded_base_diagnostics,
    extract_p2_exploded_diagnostics(model_2b_exploded_base, mlogit_train_data_p2)
  ),

  # Depth-1 (win) test predictions from the exploded coefficients, then the
  # same backtest suite as the win model for a like-for-like comparison.
  tar_target(
    test_predictions_p2_exploded,
    build_test_predictions(model_2b_exploded_base, mlogit_test_data_p2, qualifying_runners) |>
      dplyr::rename(predicted_prob = model_prob)
  ),
  tar_target(
    model_market_ratio_p2_exploded,
    compute_model_market_ratio_p2(test_predictions_p2_exploded)
  ),
  tar_target(
    backtest_naive_p2_exploded,
    run_backtest(model_market_ratio_p2_exploded,
                 prob_threshold  = 0.15,
                 ratio_threshold = 1.3)
  ),
  tar_target(
    backtest_sweep_p2_exploded,
    run_backtest_sweep(
      model_market_ratio_p2_exploded,
      prob_threshold = 0.13,
      tau_seq        = seq(0.9, 2.0, by = 0.05),
      n_boot         = 2000L,
      seed           = 42L
    )
  ),

  # -- Shared interaction features + exploded interaction data ---------------
  # Race-level x horse-level interaction columns (draw x course, weight x
  # distance) on the runner table, and the exploded (depth-3) training data
  # carrying them. Consumed by paper 2b's draw fits above and paper 2a's win
  # interaction fits further down. The exploded sample drops the single
  # training race with draw-less runners (NA stall_x_*) so all draw models
  # share one sample.
  tar_target(
    runners_interactions,
    build_interaction_features(runners_model_ready, qualifying_races)
  ),
  tar_target(
    exploded_interactions_data,
    prepare_exploded_data(
      runners_interactions |>
        dplyr::filter(split == "train") |>
        dplyr::left_join(
          dplyr::select(qualifying_runners,
                        race_id, runner_id, finish_position, amended_position),
          by = c("race_id", "runner_id")
        ),
      extra_na_vars = c("rel_weight_x_dist", "stall_x_kempton", "stall_x_lingfield",
                        "stall_x_southwell", "stall_x_wolverhampton")
    )
  ),
  # -- Paper 2b: exploded draw x course, fresh per-term reduction ------------
  # Draw x course enters as the full four-course block on the exploded
  # (Plackett-Luce, depth-3) fit, then is reduced by the same per-term Wald
  # p < 0.05 rule paper 2a uses on its win model -- run FRESH here, NOT
  # inherited from 2a. On the exploded fit Wolverhampton's draw slope is
  # significant (p ~ 0.0003) where it was marginal (p ~ 0.066) and dropped
  # in 2a's win model, so the 2b surviving set is Kempton + Southwell +
  # Wolverhampton (3 courses) vs 2a's Kempton + Southwell (2 courses); only
  # Lingfield drops. model_2b_draw_reduction_steps records the Wald/LR
  # sequence and model_2b_exploded_draw_final is the reduced fit.
  tar_target(
    model_2b_exploded_draw_full,
    fit_exploded_interaction(
      exploded_interactions_data, model_p2_reduced,
      extra_terms = c("stall_x_kempton", "stall_x_lingfield",
                      "stall_x_southwell", "stall_x_wolverhampton")
    )
  ),
  tar_target(
    model_2b_draw_reduction,
    reduce_exploded_draw_block(
      model_2b_exploded_draw_full, exploded_interactions_data, model_p2_reduced,
      draw_terms = c("stall_x_kempton", "stall_x_lingfield",
                     "stall_x_southwell", "stall_x_wolverhampton")
    )
  ),
  tar_target(
    model_2b_exploded_draw_final,
    model_2b_draw_reduction$fit
  ),
  tar_target(
    model_2b_draw_reduction_steps,
    model_2b_draw_reduction$steps
  ),

  # -- Paper 2b: ranking evaluation (test split) -----------------------------
  # Final-model test win probabilities on the draw-carrying test data
  # (mlogit_test_data_interactions, defined below), then the ranking
  # metrics: P1_rank (depth-3 PL order discrimination) and Brier_place
  # (top-3 calibration), model vs discounted-Harville market baseline
  # (alpha 0.80 / 0.65). Order probabilities use pure Harville (alpha = 1)
  # for both sides per the 2b spec.
  tar_target(
    test_predictions_2b,
    build_test_predictions(model_2b_exploded_draw_final,
                           mlogit_test_data_interactions, qualifying_runners) |>
      dplyr::rename(win_model = model_prob, win_market = market_prob)
  ),
  tar_target(
    ranking_eval_runners_2b,
    build_ranking_eval_runners(test_predictions_2b, qualifying_runners)
  ),
  tar_target(
    ranking_metrics_2b,
    compute_ranking_metrics_2b(ranking_eval_runners_2b)
  ),

  # -- Paper 2b Q2: win performance of the ranking-fitted model --------------
  # The same fully-specified 3-course exploded model evaluated on the
  # depth-1 WIN metric (Owen's naive backtest), to ask whether ranking
  # (depth-3) supervision helps or hurts win-picking vs 2a's win-fitted
  # model (headline -25.4%). Reuses test_predictions_2b, built on the same
  # mlogit_test_data_interactions test set 2a's test_predictions_w_final
  # uses, so roi_difference_2b_vs_2a intersects on a near-identical race
  # set (the top-3-clean filter bit only the ranking eval above, not this).
  tar_target(
    model_market_ratio_2b_win,
    compute_model_market_ratio_p2(
      test_predictions_2b |>
        dplyr::rename(predicted_prob = win_model, market_prob = win_market)
    )
  ),
  tar_target(
    backtest_naive_2b_win,
    run_backtest(model_market_ratio_2b_win, prob_threshold = 0.15, ratio_threshold = 1.3)
  ),
  tar_target(
    backtest_sweep_2b_win,
    run_backtest_sweep(model_market_ratio_2b_win, prob_threshold = 0.15,
                       tau_seq = seq(0.9, 2.0, by = 0.05), n_boot = 2000L, seed = 42L)
  ),
  tar_target(
    roi_difference_2b_vs_2a,
    bootstrap_roi_difference(model_market_ratio_2b_win, model_market_ratio_w_final) |>
      dplyr::mutate(contrast = "2b ranking-fitted - 2a win-fitted", .before = 1)
  ),

  # -- Paper 2b Q3: place / each-way value bets ------------------------------
  # Selection is the discounted-Harville (alpha 0.80/0.65) model-vs-market
  # value ratio, swept; the payout is the REAL industry-SP book (with its
  # over-round), the same raw SP prices Q2 bets against, so Q3 sits on one
  # footing with Q2. The bet-all baseline is therefore negative (it carries
  # the real margin), and the model ROI is read against it. A zero-margin
  # pure-Harville fair-book payout is retained alongside (ret_fair) as a
  # secondary reference. Exacta / trifecta are out of scope: their real price
  # is the CSF / Tote-pool dividend, not a Harville construction, and we have
  # no dividend data. value_bet_runners_2b is the base (complete win vectors +
  # SP); each builder needs a clean 3-horse place set (each-way also a unique
  # winner). Model place-probability floor 0.15 (standardised across paper 2b).
  tar_target(
    value_bet_runners_2b,
    build_value_bet_runners(test_predictions_2b, qualifying_runners)
  ),
  # Place
  tar_target(
    value_bets_place_2b,
    build_place_value_bets(value_bet_runners_2b)
  ),
  tar_target(
    backtest_place_2b,
    run_value_backtest(value_bets_place_2b, prob_floor = 0.15, ratio_threshold = 1.3)
  ),
  tar_target(
    backtest_sweep_place_2b,
    run_value_backtest_sweep(value_bets_place_2b, prob_floor = 0.15,
                             tau_seq = seq(0.9, 2.0, by = 0.05),
                             n_boot = 2000L, seed = 42L)
  ),
  # Each-way (1/5 odds, top-3)
  tar_target(
    value_bets_eachway_2b,
    build_eachway_value_bets(value_bet_runners_2b)
  ),
  tar_target(
    backtest_eachway_2b,
    run_value_backtest(value_bets_eachway_2b, prob_floor = 0.15, ratio_threshold = 1.3)
  ),
  tar_target(
    backtest_sweep_eachway_2b,
    run_value_backtest_sweep(value_bets_eachway_2b, prob_floor = 0.15,
                             tau_seq = seq(0.9, 2.0, by = 0.05),
                             n_boot = 2000L, seed = 42L)
  ),
  # Neutral baselines (bet-all on real-SP and fair-book bases, drop-top-payout
  # robustness, max payout, universe Ns, observed SP over-round) — Q3 reads
  # model ROIs against these.
  tar_target(
    value_bet_baselines_2b,
    build_value_bet_baselines(value_bets_place_2b, value_bets_eachway_2b,
                              value_bet_runners_2b)
  ),
  # Context benchmarks for the _04 discussion: the zero-skill SP floor
  # (back every runner) and back-the-favourite, both on the same test set as
  # the Q2 win backtest, for direct comparability with the model's win ROI.
  tar_target(
    backtest_betall_win,
    run_betall_win_backtest(test_predictions_2b)
  ),
  tar_target(
    backtest_favourite_win,
    run_favourite_win_backtest(test_predictions_2b)
  ),
  # Zero-skill each-way floor: back every horse each-way at real SP (the same
  # 1/5-odds top-3, stake-2 payout build_eachway_value_bets() uses), no
  # selection — bet-all over the each-way bet units.
  tar_target(
    backtest_betall_eachway,
    run_value_backtest(value_bets_eachway_2b, prob_floor = -Inf, ratio_threshold = -Inf)
  ),
  # Single-bet-per-race robustness: back only the highest-model-win-prob horse
  # among Owen's naive qualifiers (win prob > 0.15, ratio > 1.3) in each race,
  # settled win / place / each-way at real SP.
  tar_target(
    backtest_single_win_2b,
    run_single_win_backtest(model_market_ratio_2b_win)
  ),
  tar_target(
    backtest_single_place_2b,
    run_single_settled_backtest(model_market_ratio_2b_win, value_bets_place_2b)
  ),
  tar_target(
    backtest_single_eachway_2b,
    run_single_settled_backtest(model_market_ratio_2b_win, value_bets_eachway_2b)
  ),
  # Single-bet ROI sweeps (win / place / each-way) with race-level bootstrap CI,
  # for the single-vs-multi overlay figure in Q3.
  tar_target(
    backtest_single_win_sweep_2b,
    run_single_sweep(model_market_ratio_2b_win)
  ),
  tar_target(
    backtest_single_place_sweep_2b,
    run_single_sweep(model_market_ratio_2b_win, value_bets_place_2b)
  ),
  tar_target(
    backtest_single_eachway_sweep_2b,
    run_single_sweep(model_market_ratio_2b_win, value_bets_eachway_2b)
  ),

  # Non-exploded train/test data carrying the draw-course columns (drops the
  # one draw-less race). Consumed by paper 2a's win interaction fits below
  # and paper 2b's test predictions above.
  tar_target(
    mlogit_train_data_interactions,
    prepare_mlogit_data_p2(
      runners_interactions |> dplyr::filter(split == "train"),
      extra_na_vars = c("stall_x_kempton", "stall_x_southwell", "stall_x_wolverhampton")
    )
  ),
  tar_target(
    mlogit_test_data_interactions,
    prepare_mlogit_data_p2(
      runners_interactions |> dplyr::filter(split == "test")
    )
  ),
  # -- Paper 2a: interactions refit on the WIN model (not exploded) ----------
  # Paper 2a is a win-model paper, so its mixed-logit interactions are fitted
  # on the extended *win* model, not the exploded ranking fit. fit_exploded_
  # interaction() just fits the supplied formula on the supplied data, so we
  # reuse it (and the LR / diagnostics / backtest helpers) on the
  # non-exploded mlogit_train_data_interactions. All four models share that
  # one common sample, so the LR tests are nested and valid. The exploded
  # interaction targets above are retained for reference (paper 2b uses the
  # plain exploded model).
  tar_target(
    model_w,
    fit_exploded_interaction(mlogit_train_data_interactions, model_p2_reduced)
  ),
  tar_target(
    model_w_ew,
    fit_exploded_interaction(mlogit_train_data_interactions, model_p2_reduced,
                             extra_terms = "rel_weight_x_dist")
  ),
  tar_target(
    model_w_ed,
    fit_exploded_interaction(mlogit_train_data_interactions, model_p2_reduced,
                             extra_terms = c("stall_x_kempton", "stall_x_lingfield",
                                             "stall_x_southwell", "stall_x_wolverhampton"))
  ),
  tar_target(
    model_w_ewd,
    fit_exploded_interaction(mlogit_train_data_interactions, model_p2_reduced,
                             extra_terms = c("rel_weight_x_dist",
                                             "stall_x_kempton", "stall_x_lingfield",
                                             "stall_x_southwell", "stall_x_wolverhampton"))
  ),
  tar_target(
    interaction_lr_tests_w,
    build_interaction_lr_tests(model_w, model_w_ew, model_w_ed, model_w_ewd)
  ),
  # Paper-2a final model: the draw x course BLOCK is selected via the
  # W+draw vs W likelihood-ratio test in `interaction_lr_tests_w` (it adds
  # signal). Within the block we then apply the SAME per-term Wald
  # reduction rule paper 1 / Owen / the position-lag block in §3.2 use:
  # course slopes individually non-significant at p < 0.05 are dropped. In
  # `model_w_ed` (the full 4-course block) Kempton (p ~ 0.009) and
  # Southwell (p ~ 0.025) are significant; Lingfield (p ~ 0.35) and
  # Wolverhampton (p ~ 0.066) are not, and are dropped. The final paper-2a
  # model therefore carries two course draw terms (Kempton, Southwell),
  # 19 coefficients. `final_reduction_lr_w` confirms the two sequential
  # 1-df drops (neither rejected). The `_w_final` diagnostics /
  # test-prediction targets read off `model_w_final`. (This reverses the
  # earlier four-course-block decision; see CLAUDE.md "Paper 2a
  # corrections".)
  tar_target(
    model_w_ed_noling,
    fit_exploded_interaction(mlogit_train_data_interactions, model_p2_reduced,
                             extra_terms = c("stall_x_kempton", "stall_x_southwell",
                                             "stall_x_wolverhampton"))
  ),
  tar_target(
    model_w_final,
    fit_exploded_interaction(mlogit_train_data_interactions, model_p2_reduced,
                             extra_terms = c("stall_x_kempton", "stall_x_southwell"))
  ),
  tar_target(
    final_reduction_lr_w,
    dplyr::bind_rows(
      lr_test_pair(model_w_ed, model_w_ed_noling,
                   "W+draw (4 courses)", "drop Lingfield (3 courses)"),
      lr_test_pair(model_w_ed_noling, model_w_final,
                   "3 courses", "Final (2 courses: Kempton + Southwell)")
    )
  ),
  tar_target(
    model_w_final_diagnostics,
    extract_p2_exploded_diagnostics(model_w_final, mlogit_train_data_interactions,
                                    label = "final")
  ),
  tar_target(
    test_predictions_w_final,
    build_test_predictions(model_w_final, mlogit_test_data_interactions, qualifying_runners) |>
      dplyr::rename(predicted_prob = model_prob)
  ),
  tar_target(
    model_market_ratio_w_final,
    compute_model_market_ratio_p2(test_predictions_w_final)
  ),
  tar_target(
    backtest_naive_w_final,
    run_backtest(model_market_ratio_w_final,
                 prob_threshold  = 0.15,
                 ratio_threshold = 1.3)
  ),
  # Single-bet-per-race win backtest: among each race's naive qualifiers
  # (win prob > 0.15, ratio > 1.3), back only the highest-model-win-prob horse.
  # Adopted as the primary rule from paper 2a onwards; same test set as
  # backtest_naive_w_final.
  tar_target(
    backtest_single_win_2a,
    run_single_win_backtest(model_market_ratio_w_final)
  ),
  tar_target(
    backtest_sweep_w_final,
    run_backtest_sweep(
      model_market_ratio_w_final,
      prob_threshold = 0.13,
      tau_seq        = seq(0.9, 2.0, by = 0.05),
      n_boot         = 2000L,
      seed           = 42L
    )
  ),
  # Paired race-level bootstrap of the ROI *difference* between models,
  # restricted to each pair's common test races (paper 1 and paper 2a drop
  # different races to NA). Three contrasts: final vs paper 1, final vs the
  # extended win model, and the extended win model vs paper 1. The naive
  # rule (P > 0.15, ratio > 1.3) is applied per model per resample.
  tar_target(
    roi_difference_bootstrap,
    dplyr::bind_rows(
      bootstrap_roi_difference(model_market_ratio_w_final, model_market_ratio) |>
        dplyr::mutate(contrast = "Final − Paper 1", .before = 1),
      bootstrap_roi_difference(model_market_ratio_w_final, model_market_ratio_p2) |>
        dplyr::mutate(contrast = "Final − Extended win", .before = 1),
      bootstrap_roi_difference(model_market_ratio_p2, model_market_ratio) |>
        dplyr::mutate(contrast = "Extended win − Paper 1", .before = 1)
    )
  ),

  # -- mlogit-ready data: train and test -------------------------------------
  # Reshape `features` into mlogit's long-form choice data, restricted to
  # training or test races respectively. The NA-bearing-race filter inside
  # prepare_mlogit_data() runs per-subset, so the two outputs have
  # independent NA accounting (typically more NAs early in the window
  # where strike-rate denominators are thin — those end up in train).
  tar_target(
    mlogit_train_data,
    prepare_mlogit_data(
      dplyr::filter(features, race_id %in% races_train$race_id)
    )
  ),

  tar_target(
    mlogit_test_data,
    prepare_mlogit_data(
      dplyr::filter(features, race_id %in% races_test$race_id)
    )
  ),

  # -- Fitted conditional logit (Owen's model, training only) ----------------
  # No-intercept multinomial logit fitted on the training subset only.
  # Race is the choice set, winner is the chosen alternative. Validates
  # convergence and warns on coefficient aliasing.
  tar_target(
    fitted_mlogit,
    fit_conditional_logit(mlogit_train_data)
  ),

  # -- Model diagnostics for Owen Table 3 comparison -------------------------
  # Coefficients tibble plus a small fit-statistics vector (McFadden
  # R^2, null/residual deviance, nobs, nraces).
  tar_target(
    model_diagnostics,
    extract_model_diagnostics(fitted_mlogit)
  ),

  # -- Reduced (post-pruning) fit -------------------------------------------
  # Owen-style reduction: drop any term whose every level has p > 0.05
  # in the full fit, refit on the same training data. This is the
  # headline AW model and the analogue of Owen's Table 3. Exposed as a
  # target so paper section 3.4 (Future Predictive Performance) and the
  # existing calibration / scoring chunks in section 3.3 can read it via
  # tar_load() rather than refitting inline.
  tar_target(
    fitted_final,
    fit_reduced_model(mlogit_train_data, model_diagnostics)
  ),

  # -- Per-runner test-set predictions --------------------------------------
  # Canonical test-set tibble: race_id, runner_id, horse_ref, won,
  # model_prob (from predict(fitted_final, newdata = mlogit_test_data)),
  # starting_price_decimal, and the over-round-adjusted market_prob.
  # Used by paper sections 3.3 (calibration / scoring) and 3.4 (betting
  # backtest).
  tar_target(
    test_predictions,
    build_test_predictions(fitted_final, mlogit_test_data, qualifying_runners)
  ),

  # -- Model / market ratio + betting backtest (section 3.4) ----------------
  # ratio = model_prob / market_prob, then Owen's bet-selection rule
  # (model_prob > 0.15 AND ratio > 1.3), then a 0.05-step ratio-threshold
  # sweep with a 2000-replicate race-level bootstrap for 90% CIs. The
  # prob_threshold in the sweep is 0.13 — chosen on the AW scoring
  # picture rather than copied from Owen's 0.15.
  tar_target(
    model_market_ratio,
    compute_model_market_ratio(test_predictions)
  ),

  tar_target(
    backtest_naive,
    run_backtest(model_market_ratio,
                 prob_threshold  = 0.15,
                 ratio_threshold = 1.3)
  ),

  tar_target(
    backtest_sweep,
    run_backtest_sweep(
      model_market_ratio,
      prob_threshold = 0.13,
      tau_seq        = seq(0.9, 2.0, by = 0.05),
      n_boot         = 2000L,
      seed           = 42L
    )
  ),

  # -- Paper 3: gradient boosted trees (Plackett-Luce, depth k = 3) ----------
  # See CLAUDE.md "Paper 3 plan" for the full design history. The 72-point x
  # 5-fold hyperparameter grid search (~6.5-8h wall-clock) is deliberately
  # NOT a live target: gbt_tuning_final.rds is a FROZEN, git-committed
  # artefact (same convention as renv.lock -- a pinned empirical result, not
  # a build product), produced once by the standalone
  # scripts/run_gbt_tuning.R and re-generated only by a deliberate, manual
  # re-run of that script followed by re-committing the file. Everything
  # downstream of the SELECTED hyperparameters (the final fit, every
  # importance table, every test-set prediction and bootstrap) is cheap
  # (seconds to a few minutes) and IS a live target, so `tar_make()` from
  # clean reproduces all of it deterministically (seed 42 throughout,
  # inherited from R/gbt_tuning.R).

  # -- Feature matrices + CV folds (training races only for folds) ----------
  tar_target(
    gbt_train_data,
    build_gbt_matrix(runners_interactions, qualifying_runners, "train")
  ),
  tar_target(
    gbt_test_data,
    build_gbt_matrix(runners_interactions, qualifying_runners, "test")
  ),
  tar_target(
    gbt_race_folds,
    make_race_folds(unique(gbt_train_data$key$race_id), v = 5, seed = 42)
  ),

  # -- Frozen tuning-grid result (file-tracked, committed) -------------------
  tar_target(
    gbt_tuning_grid_file,
    "gbt_tuning_final.rds",
    format = "file"
  ),
  tar_target(
    gbt_tuning_results,
    readRDS(gbt_tuning_grid_file)
  ),
  tar_target(
    gbt_selected_config,
    gbt_tuning_results$selected
  ),

  # -- Final model fit at the selected hyperparameters (live, ~2-4 min) -----
  # xgb.Booster objects are saved via xgboost::xgb.save() rather than R's
  # own serialisation (targets' default "rds"/"qs" formats) -- the
  # established, version-safe way to persist an xgb.Booster, and already
  # this project's own convention in scripts/run_gbt_tuning.R. format =
  # "file" is `{targets}`' standard idiom for a target whose product is a
  # bespoke-serialised external file (the same accepted side-effect
  # tar_quarto() targets already have); returning two paths lets one target
  # track both the model file and its small metadata sidecar.
  tar_target(
    model_3_gbt_path,
    {
      fit <- fit_final_model(gbt_train_data$X, gbt_train_data$y,
                             gbt_train_data$group_sizes, gbt_selected_config, k = 3L)
      xgboost::xgb.save(fit$bst, "gbt_final_model.xgb")
      saveRDS(list(nrounds = fit$nrounds, train_pl_r2 = fit$train_pl_r2),
              "gbt_final_model_meta.rds")
      c("gbt_final_model.xgb", "gbt_final_model_meta.rds")
    },
    format = "file"
  ),
  tar_target(
    model_3_gbt_meta,
    readRDS(model_3_gbt_path[2])
  ),

  # -- Training-side importance (in-sample gain; within-race and ---------
  # across-race permutation, training split) --------------------------------
  tar_target(
    gbt_gain_importance_train,
    {
      bst <- xgboost::xgb.load(model_3_gbt_path[1])
      imp <- xgboost::xgb.importance(model = bst) |> tibble::as_tibble()
      imp$rank <- seq_len(nrow(imp))
      imp
    }
  ),
  tar_target(
    gbt_perm_importance_within_train,
    {
      bst <- xgboost::xgb.load(model_3_gbt_path[1])
      permutation_importance_within_race(
        bst, gbt_train_data$X, gbt_train_data$key$race_id,
        gbt_train_data$group_sizes, gbt_train_data$feature_names,
        k = 3L, n_repeats = 30L
      )
    }
  ),
  tar_target(
    gbt_perm_importance_across_train,
    {
      bst <- xgboost::xgb.load(model_3_gbt_path[1])
      permutation_importance_across_races(
        bst, gbt_train_data$X, gbt_train_data$key$race_id,
        gbt_train_data$group_sizes, RACE_LEVEL_FEATS_3,
        k = 3L, n_repeats = 30L
      )
    }
  ),
  # Paper 2b's own training pl_r2 (k=3), for the in-sample comparison table.
  tar_target(
    paper2b_train_pl_r2,
    paper2b_training_pl_r2(model_2b_exploded_draw_final, exploded_interactions_data)
  ),

  # -- Depth-1 diagnostic fit (stumps) -- PERMANENTLY A DIAGNOSTIC -----------
  # Exists to test whether depth-3's interactions generalise; once its test
  # numbers are known it can never be promoted to a candidate model (that
  # would be model selection on the test set). Same tuning-grid convention
  # as the selected model: fit at fixed max_depth=1 with the selected
  # model's other hyperparameters, own 5-fold CV to find its own nrounds
  # (no CV result is frozen for this point -- it was never part of the
  # 72-point grid), then a full-training-data refit.
  tar_target(
    model_3_depth1_diag_path,
    {
      depth1_params <- list(max_depth = 1L, eta = 0.03, min_child_weight = 1L,
                            subsample = 0.7, colsample_bytree = 0.7)
      cv <- run_grid_point(gbt_train_data$X, gbt_train_data$y, gbt_train_data$key,
                           gbt_race_folds, params = depth1_params, k = 3L)
      fit <- fit_final_model(gbt_train_data$X, gbt_train_data$y,
                             gbt_train_data$group_sizes, cv$summary, k = 3L)
      xgboost::xgb.save(fit$bst, "gbt_depth1_diagnostic.xgb")
      saveRDS(list(cv_summary = cv$summary, nrounds = fit$nrounds,
                   train_pl_r2 = fit$train_pl_r2),
              "gbt_depth1_diagnostic_meta.rds")
      c("gbt_depth1_diagnostic.xgb", "gbt_depth1_diagnostic_meta.rds")
    },
    format = "file"
  ),
  tar_target(
    model_3_depth1_diag_meta,
    readRDS(model_3_depth1_diag_path[2])
  ),

  # -- Test-set predictions (THE test-split contact point) -------------------
  # check_gbt_race_universe() halts the pipeline here (stopifnot) if paper
  # 3's test race set ever diverges from paper 2b's ranking universe --
  # see CLAUDE.md "Two test universes exist for paper 2b".
  tar_target(
    gbt_test_margin,
    {
      check_gbt_race_universe(gbt_test_data, ranking_eval_runners_2b)
      bst <- xgboost::xgb.load(model_3_gbt_path[1])
      predict(bst, gbt_test_data$X, outputmargin = TRUE)
    }
  ),
  tar_target(
    test_predictions_3,
    build_test_predictions_3(gbt_test_margin, gbt_test_data, test_predictions_2b)
  ),
  tar_target(
    gbt_depth1_test_margin,
    {
      bst <- xgboost::xgb.load(model_3_depth1_diag_path[1])
      predict(bst, gbt_test_data$X, outputmargin = TRUE)
    }
  ),
  tar_target(
    test_predictions_3_depth1,
    build_test_predictions_3(gbt_depth1_test_margin, gbt_test_data, test_predictions_2b)
  ),

  # -- Q1: ranking performance (test split) ----------------------------------
  tar_target(
    ranking_eval_runners_3,
    build_ranking_eval_runners(test_predictions_3, qualifying_runners)
  ),
  tar_target(
    ranking_metrics_3,
    compute_ranking_metrics_2b(ranking_eval_runners_3)
  ),
  # Paper 2a has no stored ranking-metric target (P1_rank / Brier_place were
  # introduced in 2b); computed fresh here, purely as an evaluation of 2a's
  # already-fitted test predictions, for a three-way comparison table. NOT
  # part of 2a's own published results.
  tar_target(
    ranking_metrics_2a_fresh,
    compute_ranking_metrics_2b(
      build_ranking_eval_runners(
        test_predictions_w_final |> dplyr::rename(win_model = predicted_prob, win_market = market_prob),
        qualifying_runners
      )
    )
  ),
  tar_target(
    test_pl_r2_3,
    make_pl_eval(gbt_test_data$group_sizes, k = 3L)(gbt_test_margin, NULL)$value
  ),
  # Paper 2b's implied z on the test split: log(win_model) is exact up to a
  # race-constant shift that cancels in pl_denom()'s per-race
  # max-subtraction (see R/gbt_tuning.R::paper2b_training_pl_r2() roxygen
  # for the training-side version of the same argument).
  tar_target(
    test_pl_r2_2b,
    {
      fp_lookup <- qualifying_runners |>
        dplyr::transmute(race_id, runner_id,
                         finish_pos = dplyr::coalesce(amended_position, finish_position))
      ordered <- test_predictions_2b |>
        dplyr::filter(!is.na(win_model), win_model > 0) |>
        dplyr::left_join(fp_lookup, by = c("race_id", "runner_id")) |>
        arrange_for_xgb()
      gs <- rle(as.character(ordered$race_id))$lengths
      z  <- base::log(ordered$win_model)
      make_pl_eval(gs, k = 3L)(z, NULL)$value
    }
  ),

  # -- Q2: win-picking (test split), three-column published/restricted/paper-3
  tar_target(
    model_market_ratio_3_win,
    compute_model_market_ratio_p2(
      test_predictions_3 |> dplyr::rename(predicted_prob = win_model, market_prob = win_market)
    )
  ),
  tar_target(
    backtest_naive_3_win,
    run_backtest(model_market_ratio_3_win, prob_threshold = 0.15, ratio_threshold = 1.3)
  ),
  tar_target(
    backtest_naive_2b_win_restricted_3,
    run_backtest(
      model_market_ratio_2b_win |> dplyr::filter(race_id %in% unique(gbt_test_data$key$race_id)),
      prob_threshold = 0.15, ratio_threshold = 1.3
    )
  ),
  tar_target(
    backtest_naive_w_final_restricted_3,
    run_backtest(
      model_market_ratio_w_final |> dplyr::filter(race_id %in% unique(gbt_test_data$key$race_id)),
      prob_threshold = 0.15, ratio_threshold = 1.3
    )
  ),
  tar_target(
    roi_diff_3_vs_2b,
    bootstrap_roi_difference(model_market_ratio_3_win, model_market_ratio_2b_win) |>
      dplyr::mutate(contrast = "paper 3 GBT - paper 2b exploded logit", .before = 1)
  ),
  tar_target(
    roi_diff_3_vs_2a,
    bootstrap_roi_difference(model_market_ratio_3_win, model_market_ratio_w_final) |>
      dplyr::mutate(contrast = "paper 3 GBT - paper 2a win model", .before = 1)
  ),

  # -- Q3: betting value (test split), single-bet primary --------------------
  tar_target(
    value_bet_runners_3,
    build_value_bet_runners(test_predictions_3, qualifying_runners)
  ),
  tar_target(value_bets_place_3,   build_place_value_bets(value_bet_runners_3)),
  tar_target(value_bets_eachway_3, build_eachway_value_bets(value_bet_runners_3)),
  tar_target(backtest_single_win_3,     run_single_win_backtest(model_market_ratio_3_win)),
  tar_target(backtest_single_place_3,   run_single_settled_backtest(model_market_ratio_3_win, value_bets_place_3)),
  tar_target(backtest_single_eachway_3, run_single_settled_backtest(model_market_ratio_3_win, value_bets_eachway_3)),
  tar_target(
    backtest_single_win_2b_restricted_3,
    run_single_win_backtest(
      model_market_ratio_2b_win |> dplyr::filter(race_id %in% unique(gbt_test_data$key$race_id))
    )
  ),
  tar_target(
    backtest_single_place_2b_restricted_3,
    run_single_settled_backtest(
      model_market_ratio_2b_win |> dplyr::filter(race_id %in% unique(gbt_test_data$key$race_id)),
      value_bets_place_2b |> dplyr::filter(race_id %in% unique(gbt_test_data$key$race_id))
    )
  ),
  tar_target(
    backtest_single_eachway_2b_restricted_3,
    run_single_settled_backtest(
      model_market_ratio_2b_win |> dplyr::filter(race_id %in% unique(gbt_test_data$key$race_id)),
      value_bets_eachway_2b |> dplyr::filter(race_id %in% unique(gbt_test_data$key$race_id))
    )
  ),
  tar_target(
    backtest_single_win_2a_restricted_3,
    run_single_win_backtest(
      model_market_ratio_w_final |> dplyr::filter(race_id %in% unique(gbt_test_data$key$race_id))
    )
  ),
  tar_target(sweep_single_win_3,     run_single_sweep(model_market_ratio_3_win)),
  tar_target(sweep_single_place_3,   run_single_sweep(model_market_ratio_3_win, value_bets_place_3)),
  tar_target(sweep_single_eachway_3, run_single_sweep(model_market_ratio_3_win, value_bets_eachway_3)),

  # -- Out-of-sample importance (test split), both nulls ---------------------
  tar_target(
    gbt_perm_importance_within_test,
    {
      bst <- xgboost::xgb.load(model_3_gbt_path[1])
      permutation_importance_within_race(
        bst, gbt_test_data$X, gbt_test_data$key$race_id, gbt_test_data$group_sizes,
        HORSE_LEVEL_FEATS_3, k = 3L, n_repeats = 30L
      )
    }
  ),
  tar_target(
    gbt_perm_importance_across_test,
    {
      bst <- xgboost::xgb.load(model_3_gbt_path[1])
      permutation_importance_across_races(
        bst, gbt_test_data$X, gbt_test_data$key$race_id, gbt_test_data$group_sizes,
        RACE_LEVEL_FEATS_3, k = 3L, n_repeats = 30L
      )
    }
  ),

  # -- Paired race-level bootstraps on the ranking metrics --------------------
  # depth-3 (selected) vs paper 2b, vs the depth-1 diagnostic, and vs the
  # discounted-Harville market -- the market comparison is the one contrast
  # in the whole battery whose CIs exclude zero (see CLAUDE.md).
  tar_target(
    ranking_per_race_3,
    build_ranking_per_race(
      ranking_eval_runners_3, "win_model", alpha_2nd = 1, alpha_3rd = 1,
      z = gbt_test_margin, group_sizes = gbt_test_data$group_sizes,
      race_ids_ordered = as.integer(rle(as.character(gbt_test_data$key$race_id))$values)
    )
  ),
  tar_target(
    ranking_per_race_market_3,
    build_ranking_per_race(ranking_eval_runners_3, "win_market", alpha_2nd = 0.80, alpha_3rd = 0.65)
  ),
  tar_target(
    ranking_per_race_2b_for_3,
    {
      fp_lookup <- qualifying_runners |>
        dplyr::transmute(race_id, runner_id,
                         finish_pos = dplyr::coalesce(amended_position, finish_position))
      test_race_ids <- unique(gbt_test_data$key$race_id)
      ordered <- test_predictions_2b |>
        dplyr::filter(!is.na(win_model), win_model > 0, race_id %in% test_race_ids) |>
        dplyr::left_join(fp_lookup, by = c("race_id", "runner_id")) |>
        arrange_for_xgb()
      rl  <- rle(as.character(ordered$race_id))
      z2b <- base::log(ordered$win_model)
      rer_2b_subset <- ranking_eval_runners_2b |> dplyr::filter(race_id %in% test_race_ids)
      build_ranking_per_race(rer_2b_subset, "win_model", alpha_2nd = 1, alpha_3rd = 1,
                             z = z2b, group_sizes = rl$lengths, race_ids_ordered = as.integer(rl$values))
    }
  ),
  tar_target(
    ranking_per_race_depth1_3,
    build_ranking_per_race(
      build_ranking_eval_runners(test_predictions_3_depth1, qualifying_runners),
      "win_model", alpha_2nd = 1, alpha_3rd = 1,
      z = gbt_depth1_test_margin, group_sizes = gbt_test_data$group_sizes,
      race_ids_ordered = as.integer(rle(as.character(gbt_test_data$key$race_id))$values)
    )
  ),
  tar_target(
    boot_ranking_3_vs_2b,
    bootstrap_ranking_metrics(ranking_per_race_3, ranking_per_race_2b_for_3,
                              "depth-3 (selected) - paper 2b")
  ),
  tar_target(
    boot_ranking_3_vs_depth1,
    bootstrap_ranking_metrics(ranking_per_race_3, ranking_per_race_depth1_3,
                              "depth-3 (selected) - depth-1 (diagnostic)")
  ),
  tar_target(
    boot_ranking_3_vs_market,
    bootstrap_ranking_metrics(ranking_per_race_3, ranking_per_race_market_3,
                              "depth-3 (selected) - discounted-Harville market")
  ),

  # -- Pre-drafting diagnostics: score agreement, disagreement set, PDP ------
  tar_target(
    aligned_2b_z_3,
    align_2b_z_to_key(test_predictions_2b, gbt_test_data$key)
  ),
  tar_target(
    score_agreement_3_vs_2b,
    {
      joined <- gbt_test_data$key |>
        dplyr::mutate(z_p3 = gbt_test_margin) |>
        dplyr::inner_join(aligned_2b_z_3, by = c("race_id", "runner_id"))
      compute_score_agreement(joined$race_id, joined$runner_id, joined$z_p3, joined$z_2b)
    }
  ),
  tar_target(
    disagreement_set_3_vs_2b,
    {
      joined <- gbt_test_data$key |>
        dplyr::mutate(z_p3 = gbt_test_margin) |>
        dplyr::inner_join(aligned_2b_z_3, by = c("race_id", "runner_id")) |>
        dplyr::inner_join(
          test_predictions_3 |> dplyr::select(race_id, runner_id, starting_price_decimal, won),
          by = c("race_id", "runner_id")
        )
      build_disagreement_set(joined$race_id, joined$runner_id, joined$z_p3, joined$z_2b,
                             joined$starting_price_decimal, joined$won)
    }
  ),
  tar_target(
    boot_disagreement_3_vs_2b,
    bootstrap_disagreement_diff(disagreement_set_3_vs_2b)
  ),
  tar_target(
    gbt_pdp_or_relative,
    {
      bst <- xgboost::xgb.load(model_3_gbt_path[1])
      compute_partial_dependence(bst, gbt_test_data$X, "or_relative")
    }
  ),
  tar_target(
    gbt_pdp_going_sr_delta,
    {
      bst <- xgboost::xgb.load(model_3_gbt_path[1])
      compute_partial_dependence(bst, gbt_test_data$X, "going_sr_delta")
    }
  ),
  tar_target(
    gbt_pdp_stall_normalised,
    {
      bst <- xgboost::xgb.load(model_3_gbt_path[1])
      compute_partial_dependence(bst, gbt_test_data$X, "stall_normalised")
    }
  ),

  # -- Paper 1 render --------------------------------------------------------
  # tarchetypes::tar_quarto parses the master index.qmd (and its included
  # section files) for tar_read() / tar_load() calls and turns the
  # referenced targets into dependencies, so the paper re-renders exactly
  # when its inputs change. `extra_files` carries the included section
  # files and the plotting helpers so edits to them also trigger a
  # re-render.
  tar_quarto(
    paper_1_replication,
    path = "papers/01_replication",
    quiet = FALSE,
    extra_files = c(
      "papers/01_replication/_01_data.qmd",
      "papers/01_replication/_02_exploratory.qmd",
      "papers/01_replication/_03_results.qmd",
      "papers/01_replication/_04_future_predictive.qmd",
      "papers/01_replication/_appx_derivation.qmd",
      "papers/01_replication/_appx_software.qmd",
      "papers/01_replication/_helpers.R",
      "papers/01_replication/references.bib",
      "papers/01_replication/_quarto.yml"
    )
  ),

  # -- Paper 2 render (SPLIT into 2a + 2b) -----------------------------------
  # The combined pre-split paper-2 draft now lives, unmodified, at
  # papers/02_extended_features_ARCHIVE/ for reference. The target below is
  # COMMENTED OUT (its path no longer exists) and replaced by paper_2a and
  # paper_2b. Kept here rather than deleted as a record of the split.
  # tar_quarto(
  #   paper_2_extended_features,
  #   path = "papers/02_extended_features",
  #   quiet = FALSE,
  #   extra_files = c(
  #     "papers/02_extended_features/_01_data.qmd",
  #     "papers/02_extended_features/_02_feature_evaluation.qmd",
  #     "papers/02_extended_features/_03_extended_win_model.qmd",
  #     "papers/02_extended_features/_04_exploded_logit.qmd",
  #     "papers/02_extended_features/_05_mixed_interactions.qmd",
  #     "papers/02_extended_features/_06_discussion.qmd",
  #     "papers/02_extended_features/_appx_derivations.qmd",
  #     "papers/02_extended_features/_appx_software.qmd",
  #     "papers/02_extended_features/_helpers.R",
  #     "papers/02_extended_features/references.bib",
  #     "papers/02_extended_features/_quarto.yml"
  #   )
  # ),

  # -- Paper 2a render: extended win model (+ mixed-logit interactions) ------
  # Same pattern as paper_1_replication. Currently a full copy of the
  # pre-split draft; trimming the ranking / exploded-logit material out to
  # paper 2b is follow-up work.
  tar_quarto(
    paper_2a_extended_win_model,
    path = "papers/02a_extended_win_model",
    quiet = FALSE,
    extra_files = c(
      "papers/02a_extended_win_model/_01_data.qmd",
      "papers/02a_extended_win_model/_02_feature_evaluation.qmd",
      "papers/02a_extended_win_model/_03_extended_win_model.qmd",
      "papers/02a_extended_win_model/_05_mixed_interactions.qmd",
      "papers/02a_extended_win_model/_06_discussion.qmd",
      "papers/02a_extended_win_model/_appx_derivations.qmd",
      "papers/02a_extended_win_model/_appx_software.qmd",
      "papers/02a_extended_win_model/_helpers.R",
      "papers/02a_extended_win_model/references.bib",
      "papers/02a_extended_win_model/_quarto.yml"
    )
  ),

  # -- Paper 2b render: exploded conditional logit as a ranking model --------
  # Scaffold only; the section partials are stubs.
  tar_quarto(
    paper_2b_ranking_model,
    path = "papers/02b_ranking_model",
    quiet = FALSE,
    extra_files = c(
      "papers/02b_ranking_model/_01_data.qmd",
      "papers/02b_ranking_model/_02_exploded_model.qmd",
      "papers/02b_ranking_model/_03_evaluation.qmd",
      "papers/02b_ranking_model/_04_discussion.qmd",
      "papers/02b_ranking_model/_appx_derivations.qmd",
      "papers/02b_ranking_model/_appx_software.qmd",
      "papers/02b_ranking_model/_helpers.R",
      "papers/02b_ranking_model/references.bib",
      "papers/02b_ranking_model/_quarto.yml"
    )
  ),

  # -- Paper 3 render: gradient boosted trees --------------------------------
  # Scaffold only; the section partials are headings + one-line placeholders
  # (structure/wiring pass, CLAUDE.md "Paper 3 plan" -- section content is
  # drafted one section at a time in a later pass).
  tar_quarto(
    paper_3_gradient_boosted_trees,
    path = "papers/03_gradient_boosted_trees",
    quiet = FALSE,
    extra_files = c(
      "papers/03_gradient_boosted_trees/_01_data.qmd",
      "papers/03_gradient_boosted_trees/_02_method.qmd",
      "papers/03_gradient_boosted_trees/_03_model.qmd",
      "papers/03_gradient_boosted_trees/_04_results.qmd",
      "papers/03_gradient_boosted_trees/_05_discussion.qmd",
      "papers/03_gradient_boosted_trees/_appx_derivations.qmd",
      "papers/03_gradient_boosted_trees/_appx_software.qmd",
      "papers/03_gradient_boosted_trees/_helpers.R",
      "papers/03_gradient_boosted_trees/references.bib",
      "papers/03_gradient_boosted_trees/_quarto.yml"
    )
  )

)
