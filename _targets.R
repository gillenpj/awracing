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
  tar_target(
    full_history,
    {
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

  # -- Augmented runners (paper 2 modelling input) ---------------------------
  # Single tibble carrying paper 1's modelling columns plus every new
  # paper-2 candidate feature. This is the one augmented runners target
  # that paper 2's prepare_mlogit_data() will consume; paper 1 continues
  # to read the narrower `features` target, so its fit is unchanged.
  tar_target(
    runners_augmented,
    features |>
      dplyr::left_join(jockey_sr_premiums,   by = c("race_id", "runner_id")) |>
      dplyr::left_join(within_race_features, by = c("race_id", "runner_id")) |>
      dplyr::left_join(career_form_features, by = c("race_id", "runner_id"))
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
    model_p2_exploded,
    fit_exploded_model(exploded_train_data, model_p2_reduced)
  ),
  tar_target(
    model_p2_exploded_diagnostics,
    extract_p2_exploded_diagnostics(model_p2_exploded, mlogit_train_data_p2)
  ),

  # Depth-1 (win) test predictions from the exploded coefficients, then the
  # same backtest suite as the win model for a like-for-like comparison.
  tar_target(
    test_predictions_p2_exploded,
    build_test_predictions(model_p2_exploded, mlogit_test_data_p2, qualifying_runners) |>
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

  # -- Paper 2 mixed-logit interactions --------------------------------------
  # Two race-level x horse-level interactions tested on top of the exploded
  # model: weight x distance (Benter) and draw x course. All four models
  # (E/EW/ED/EWD) are fitted on ONE common exploded sample so the LR tests
  # are valid; the common sample drops the single training race with
  # draw-less runners (NA stall_x_*), hence a fresh Model E rather than
  # reusing model_p2_exploded (which differs by that 1 race).
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
  tar_target(
    model_p2_e,
    fit_exploded_interaction(exploded_interactions_data, model_p2_reduced)
  ),
  tar_target(
    model_p2_ew,
    fit_exploded_interaction(exploded_interactions_data, model_p2_reduced,
                             extra_terms = "rel_weight_x_dist")
  ),
  tar_target(
    model_p2_ed,
    fit_exploded_interaction(exploded_interactions_data, model_p2_reduced,
                             extra_terms = c("stall_x_kempton", "stall_x_lingfield",
                                             "stall_x_southwell", "stall_x_wolverhampton"))
  ),
  tar_target(
    model_p2_ewd,
    fit_exploded_interaction(exploded_interactions_data, model_p2_reduced,
                             extra_terms = c("rel_weight_x_dist",
                                             "stall_x_kempton", "stall_x_lingfield",
                                             "stall_x_southwell", "stall_x_wolverhampton"))
  ),
  tar_target(
    interaction_lr_tests,
    build_interaction_lr_tests(model_p2_e, model_p2_ew, model_p2_ed, model_p2_ewd)
  ),

  # -- Paper 2 final model: exploded + draw x course, Lingfield dropped ------
  # The LR tests select ED (draw x course) over E/EW/EWD. Within ED the
  # Lingfield draw term is individually non-significant (Wald p = 0.91), so
  # the reduced final model drops it (keeping Kempton/Southwell/
  # Wolverhampton); final_reduction_lr confirms the 1-df drop. _final
  # targets point at this reduced model. Depth-1 (win) test evaluation; the
  # test split has no draw-less runners, so no extra drop is needed.
  tar_target(
    model_p2_final,
    fit_exploded_interaction(
      exploded_interactions_data, model_p2_reduced,
      extra_terms = c("stall_x_kempton", "stall_x_southwell", "stall_x_wolverhampton")
    )
  ),
  tar_target(
    final_reduction_lr,
    lr_test_pair(model_p2_ed, model_p2_final,
                 "ED (4 courses)", "Final (3 courses, Lingfield dropped)")
  ),

  # Non-exploded training data carrying the draw-course columns (drops the
  # one draw-less race), so the final model's depth-1 PL-R² is computable
  # and directly comparable to the win / exploded diagnostics.
  tar_target(
    mlogit_train_data_interactions,
    prepare_mlogit_data_p2(
      runners_interactions |> dplyr::filter(split == "train"),
      extra_na_vars = c("stall_x_kempton", "stall_x_southwell", "stall_x_wolverhampton")
    )
  ),
  tar_target(
    model_p2_final_diagnostics,
    extract_p2_exploded_diagnostics(model_p2_final, mlogit_train_data_interactions,
                                    label = "final")
  ),
  tar_target(
    mlogit_test_data_interactions,
    prepare_mlogit_data_p2(
      runners_interactions |> dplyr::filter(split == "test")
    )
  ),
  tar_target(
    test_predictions_p2_final,
    build_test_predictions(model_p2_final, mlogit_test_data_interactions, qualifying_runners) |>
      dplyr::rename(predicted_prob = model_prob)
  ),
  tar_target(
    model_market_ratio_p2_final,
    compute_model_market_ratio_p2(test_predictions_p2_final)
  ),
  tar_target(
    backtest_naive_p2_final,
    run_backtest(model_market_ratio_p2_final,
                 prob_threshold  = 0.15,
                 ratio_threshold = 1.3)
  ),
  tar_target(
    backtest_sweep_p2_final,
    run_backtest_sweep(
      model_market_ratio_p2_final,
      prob_threshold = 0.13,
      tau_seq        = seq(0.9, 2.0, by = 0.05),
      n_boot         = 2000L,
      seed           = 42L
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
  )

)
