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
  )

)
