# feature_screen.R
# Univariate Plackett-Luce (depth-1) R^2 screen for paper-2 feature
# selection. For each candidate feature we fit a standalone no-intercept
# conditional logit (won ~ feature, race = choice set) on the TRAINING
# races only and score it by
#   R2_PL = 1 - logL_model / logL_null
# where logL_null assigns every runner 1 / field_size. "Depth 1" means
# the likelihood is taken over the winner only (the plain conditional-
# logit likelihood) — the univariate analogue of the exploded
# Plackett-Luce fit planned for paper 2 section 4. Training set only:
# no test-set race ever enters this step.

#' Fit one univariate conditional logit and return its PL (depth-1) R^2
#'
#' Scores a single candidate feature — or a group of columns treated as
#' one conceptual feature, e.g. the three position-lag factors — by the
#' depth-1 Plackett-Luce R^2 of a standalone conditional logit fitted on
#' the supplied training runners.
#'
#' **NA handling — feature-only, race-level.** The fit is restricted to
#' races where every runner is non-NA across `feature_cols`, so each
#' feature is scored on its own complete-choice-set subset and coverage
#' differences show up in `n_races`. We deliberately do *not* route
#' through `prepare_mlogit_data()`: that helper drops races on NAs in
#' the paper-1 13-variable model set, which would couple every feature's
#' race subset to paper-1 completeness rather than to the feature under
#' test (and it is paper-1 code we are asked to leave untouched).
#' Instead we replicate its mlogit reshape — the per-race `horse_ref`
#' alternative index plus the `mlogit.data()` call; see CLAUDE.md on why
#' `alt.var` must be a low-cardinality per-race index, not the
#' population-wide `runner_id` — with the feature-only filter. Filtering
#' is at the race level (whole races kept or dropped), so the
#' one-winner-per-race choice-set structure is preserved.
#'
#' **R^2 definition.** `log_l_model` is `logLik()` of the fitted
#' conditional logit (the sum of log winner-probabilities across the
#' retained races). `log_l_null` is `-sum(log(field_size))` over those
#' same races (every runner equally likely). Both are negative, and
#' because a fitted MLE cannot do worse than the null on its own
#' training data, `pl_r2 = 1 - log_l_model / log_l_null` lies in [0, 1].
#'
#' **Robustness.** Warnings from `mlogit::mlogit()` (e.g.
#' non-convergence) are captured into `notes` rather than raised, so one
#' ill-behaved feature cannot abort the whole screen; a hard error is
#' caught and yields an NA-`pl_r2` row carrying the error text in
#' `notes`.
#'
#' @param runners_train Training-set runner rows (one per runner-race),
#'   e.g. `runners_augmented` filtered to `races_train`. Must carry
#'   `race_id`, `won`, and every column named in `feature_cols`.
#' @param feature_name Character label for the output row (e.g.
#'   "position_lags").
#' @param feature_cols Character vector of the column(s) entered on the
#'   model's right-hand side. Length > 1 fits them together as one
#'   conceptual feature.
#' @return A one-row tibble: `feature`, `pl_r2`, `n_races`,
#'   `log_l_model`, `log_l_null`, `notes` (warning / error text, or NA).
fit_univariate_screen <- function(runners_train, feature_name, feature_cols) {
  # Keep only races with a complete choice set for this feature. The
  # condition is constant within a race, so filter() drops whole races,
  # never individual runners — the single winner per race is preserved.
  complete <- runners_train |>
    dplyr::group_by(race_id) |>
    dplyr::filter(!any(dplyr::if_any(dplyr::all_of(feature_cols), is.na))) |>
    dplyr::ungroup()

  n_races <- dplyr::n_distinct(complete$race_id)

  # Equal-probability null over the retained races: each runner has
  # probability 1 / n_r, so log_l_null = sum_r log(1/n_r) = -sum_r log(n_r).
  field_sizes <- dplyr::count(complete, race_id, name = "field_size")
  log_l_null  <- -sum(log(field_sizes$field_size))

  # Reshape to mlogit long form. horse_ref is a per-race 1..n index used
  # as alt.var; the population-wide runner_id would blow mlogit's
  # internal matrices up by ~600x (the documented 16GB-hang failure).
  cleaned <- complete |>
    dplyr::group_by(race_id) |>
    dplyr::mutate(horse_ref = dplyr::row_number()) |>
    dplyr::ungroup()

  mlogit_data <- mlogit::mlogit.data(
    cleaned,
    shape    = "long",
    choice   = "won",
    chid.var = "race_id",
    alt.var  = "horse_ref"
  )

  # Three-part `| 0 | 0` suppresses alternative-specific intercepts,
  # matching fit_conditional_logit() / Owen's reference script.
  form <- stats::as.formula(
    paste("won ~", paste(feature_cols, collapse = " + "), "| 0 | 0")
  )

  notes  <- character(0)
  fitted <- tryCatch(
    withCallingHandlers(
      mlogit::mlogit(form, data = mlogit_data),
      warning = function(w) {
        notes <<- c(notes, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    ),
    error = function(e) {
      notes <<- c(notes, paste0("ERROR: ", conditionMessage(e)))
      NULL
    }
  )

  log_l_model <- if (is.null(fitted)) NA_real_ else as.numeric(stats::logLik(fitted))
  pl_r2       <- 1 - log_l_model / log_l_null

  tibble::tibble(
    feature     = feature_name,
    pl_r2       = pl_r2,
    n_races     = n_races,
    log_l_model = log_l_model,
    log_l_null  = log_l_null,
    notes       = if (length(notes)) paste(unique(notes), collapse = " | ") else NA_character_
  )
}

#' Run the univariate PL-R^2 screen over every candidate feature
#'
#' Maps `fit_univariate_screen()` over the paper-2 candidate list — the
#' Owen-baseline features re-tested on the current AW data / encodings,
#' plus the new paper-2 candidates — binds the one-row results, and
#' sorts by descending `pl_r2`. The three position-lag factors are
#' screened together as a single conceptual feature labelled
#' `position_lags` (splitting them individually is not meaningful). The
#' binary flags `first_time_aw` / `has_wins` are entered as-is.
#'
#' @param runners_train Training-set rows: `runners_augmented` filtered
#'   to `races_train`.
#' @return Ranked tibble, one row per feature, with the columns returned
#'   by `fit_univariate_screen()`.
run_feature_screen <- function(runners_train) {
  screen_spec <- list(
    # -- Group A: Owen baseline, re-tested with current AW encodings ----------
    list(name = "age_diff",      cols = "age_diff"),
    list(name = "daysLTO",       cols = "days_LTO_log"),
    list(name = "trainerSR",     cols = "trainerSR"),
    list(name = "sireSR",        cols = "sireSR"),
    list(name = "gelding",       cols = "gelding"),
    list(name = "entire",        cols = "entire"),
    list(name = "cheekpieces",   cols = "cheekpieces"),
    list(name = "position_lags", cols = c("position1", "position2", "position3")),
    # -- Group B: new paper-2 candidates --------------------------------------
    list(name = "jockeySR",           cols = "jockeySR"),
    list(name = "trainer_aw_premium", cols = "trainer_aw_premium"),
    list(name = "sire_aw_premium",    cols = "sire_aw_premium"),
    list(name = "jockey_aw_premium",  cols = "jockey_aw_premium"),
    list(name = "stall_normalised",   cols = "stall_normalised"),
    list(name = "rel_weight",         cols = "rel_weight"),
    list(name = "class_delta",        cols = "class_delta"),
    list(name = "weight_delta_lbs",   cols = "weight_delta_lbs"),
    list(name = "first_time_aw",      cols = "first_time_aw"),
    list(name = "has_wins",           cols = "has_wins"),
    list(name = "or_relative",        cols = "or_relative")
  )

  screen_spec |>
    purrr::map(\(s) fit_univariate_screen(runners_train, s$name, s$cols)) |>
    purrr::list_rbind() |>
    dplyr::arrange(dplyr::desc(pl_r2))
}

#' Likelihood-ratio test: parsimonious vs factor position encoding
#'
#' Compares two encodings of the prior-finish lag features on the
#' training races, **position lags only** (no other covariates), so the
#' result isolates the encoding question rather than confounding it with
#' the rest of the model.
#'
#' \describe{
#'   \item{Model F (factor)}{Paper 1's encoding: the three lag factors
#'     `position1 + position2 + position3` (levels 0--4, reference 0),
#'     ~12 free coefficients.}
#'   \item{Model P (parsimonious)}{Two numeric scores built from the raw
#'     lag positions `p_k` (0 = no prior run at that lag):
#'     `position_score = p1 + p2 + p3` (equal-weight sum) and
#'     `decay_score = 1*p1 + 2*p2 + 3*p3` (lag-weighted sum), fitted as
#'     `won ~ position_score + decay_score`, 2 coefficients.}
#'   \item{Model S (semi-parsimonious)}{Per lag, split the factor into a
#'     zero indicator `pos_lagN_zero` (1 if the lag-N position is 0 — the
#'     "no prior run / worse than 4th" category) and a graded value
#'     `pos_lagN_nonzero` (the raw 1--4 finishing position, 0 otherwise),
#'     fitted as the six-term `won ~ pos_lag1_zero + pos_lag1_nonzero +
#'     ... | 0 | 0`, 6 coefficients. Unlike Model P this separates the
#'     categorical zero effect from a linear trend across 1--4, so the
#'     S-vs-F test isolates whether positions 1--4 are non-linear.}
#' }
#'
#' Both Model P's scores and Model S's per-lag terms are fixed linear
#' combinations of Model F's level dummies (e.g.
#' `p_k = sum_v v * I(position_k = v)`, and the zero indicator
#' `I(p_k = 0)` is a global constant minus those dummies, the constant
#' being immaterial to the no-intercept conditional logit), so both P and
#' S are nested in Model F and their LR tests are valid. The lag features
#' carry no NAs, so no races are dropped; all three models are fitted on a
#' single shared mlogit dataset and therefore on identical observations.
#'
#' Decision rule (each test): `p_value > 0.05` does not reject the
#' restricted encoding (→ "parsimonious" / "semi-parsimonious");
#' otherwise the factor encoding is retained (→ "factor").
#'
#' @param runners_train Training-split rows from `runners_model_ready`
#'   (one per runner-race); must carry `race_id`, `won`, and the factor
#'   columns `position1`, `position2`, `position3`.
#' @return A named list. P-vs-F fields: `model_f`, `model_p`, `loglik_f`,
#'   `loglik_p`, `df_f`, `df_p` (free parameters), `lr_stat`, `df`
#'   (= `df_f - df_p`), `p_value`, `decision` ("parsimonious"/"factor").
#'   S-vs-F fields: `model_s`, `loglik_s`, `df_s` (6 free params),
#'   `lr_stat_s`, `lr_df_s` (= `df_f - df_s`), `p_value_s`, `decision_s`
#'   ("semi-parsimonious"/"factor").
test_position_parsimony <- function(runners_train) {
  # factor "0".."4" -> numeric 0..4 (NOT as.integer(factor), which would
  # return the 1-based level index rather than the finishing position).
  as_pos <- function(f) as.integer(as.character(f))

  cleaned <- runners_train |>
    dplyr::transmute(
      race_id, won,
      position1, position2, position3,
      pos1 = as_pos(position1),
      pos2 = as_pos(position2),
      pos3 = as_pos(position3)
    ) |>
    dplyr::mutate(
      # Model P: two summary scores.
      position_score = pos1 + pos2 + pos3,
      decay_score    = 1L * pos1 + 2L * pos2 + 3L * pos3,
      # Model S: per-lag zero indicator + graded 1-4 value (0 when zero).
      pos_lag1_zero = as.integer(pos1 == 0L), pos_lag1_nonzero = pos1,
      pos_lag2_zero = as.integer(pos2 == 0L), pos_lag2_nonzero = pos2,
      pos_lag3_zero = as.integer(pos3 == 0L), pos_lag3_nonzero = pos3
    ) |>
    dplyr::group_by(race_id) |>
    dplyr::mutate(horse_ref = dplyr::row_number()) |>
    dplyr::ungroup()

  mlogit_data <- mlogit::mlogit.data(
    cleaned,
    shape    = "long",
    choice   = "won",
    chid.var = "race_id",
    alt.var  = "horse_ref"
  )

  # Both fits share mlogit_data -> identical choice sets / observations.
  model_f <- mlogit::mlogit(
    won ~ position1 + position2 + position3 | 0 | 0,
    data = mlogit_data
  )
  model_p <- mlogit::mlogit(
    won ~ position_score + decay_score | 0 | 0,
    data = mlogit_data
  )
  model_s <- mlogit::mlogit(
    won ~ pos_lag1_zero + pos_lag1_nonzero +
          pos_lag2_zero + pos_lag2_nonzero +
          pos_lag3_zero + pos_lag3_nonzero | 0 | 0,
    data = mlogit_data
  )

  loglik_f <- as.numeric(stats::logLik(model_f))
  loglik_p <- as.numeric(stats::logLik(model_p))
  loglik_s <- as.numeric(stats::logLik(model_s))
  df_f     <- length(model_f$coefficients)
  df_p     <- length(model_p$coefficients)
  df_s     <- length(model_s$coefficients)

  # Model P vs Model F.
  df       <- df_f - df_p
  lr_stat  <- -2 * (loglik_p - loglik_f)
  p_value  <- stats::pchisq(lr_stat, df = df, lower.tail = FALSE)
  decision <- if (p_value > 0.05) "parsimonious" else "factor"

  # Model S vs Model F.
  lr_df_s    <- df_f - df_s
  lr_stat_s  <- -2 * (loglik_s - loglik_f)
  p_value_s  <- stats::pchisq(lr_stat_s, df = lr_df_s, lower.tail = FALSE)
  decision_s <- if (p_value_s > 0.05) "semi-parsimonious" else "factor"

  list(
    model_f    = model_f,
    model_p    = model_p,
    model_s    = model_s,
    loglik_f   = loglik_f,
    loglik_p   = loglik_p,
    loglik_s   = loglik_s,
    df_f       = df_f,
    df_p       = df_p,
    df_s       = df_s,
    lr_stat    = lr_stat,
    df         = df,
    p_value    = p_value,
    decision   = decision,
    lr_stat_s  = lr_stat_s,
    lr_df_s    = lr_df_s,
    p_value_s  = p_value_s,
    decision_s = decision_s
  )
}
