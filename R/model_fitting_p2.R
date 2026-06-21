# model_fitting_p2.R
# Paper-2 extended conditional-logit win model. Mirrors the paper-1
# fitting pattern in R/fit_mlogit_model.R but on the extended feature set
# with the Model-S position encoding (CLAUDE.md "Paper 2 feature
# decisions"). Paper-1 code is left untouched; this is a parallel set of
# pure functions. Fitting is training-only; evaluation (elsewhere) is
# test-only.

#' The paper-2 full-model variable vector
#'
#' Single source of truth for the 19 modelling columns of the paper-2
#' full specification, so the formula and `prepare_mlogit_data_p2()` stay
#' in sync. Every term is a single numeric/binary covariate (no
#' multi-level factors), so each contributes exactly one coefficient.
#' `days_LTO_log` is the log-transformed daysLTO (consistent with paper
#' 1); the Model-S position encoding replaces paper 1's position1/2/3
#' factors.
#'
#' @return Character vector of the 19 paper-2 model variables.
model_fitting_p2_vars <- function() {
  c(
    "pos_lag1_zero", "pos_lag1_nonzero",
    "pos_lag2_zero", "pos_lag2_nonzero",
    "pos_lag3_zero", "pos_lag3_nonzero",
    "age_diff", "days_LTO_log", "trainerSR", "sireSR", "jockeySR",
    "entire", "gelding", "cheekpieces",
    "rel_weight", "or_relative", "or_missing", "trainer_aw_premium", "has_wins"
  )
}

#' Reshape the paper-2 feature tibble to {mlogit} long-form choice data
#'
#' Paper-2 analogue of `prepare_mlogit_data()` (R/fit_mlogit_model.R),
#' written separately so the paper-1 version is untouched. The only
#' difference is the modelling-column set used for the NA check: the 19
#' paper-2 variables (Model-S position encoding + extended features)
#' rather than paper 1's 13. Behaviour is otherwise identical —
#' whole-race drop on any NA in a modelling column (preserving the
#' one-winner-per-race invariant), a per-race `horse_ref` alternative
#' index (a low-cardinality `alt.var`; see CLAUDE.md), and a post-drop
#' guard.
#'
#' Note `or_relative` is already NULL-imputed to 0 in `runners_model_ready`
#' (paired with `or_missing`), so it contributes no NA drops here — the
#' coverage cost flagged in the feature evaluation section is paid by the
#' imputation, not by dropping races.
#'
#' @param features_df A split of `runners_model_ready` (one row per
#'   runner-race). Must carry `race_id`, `won`, and the 19 paper-2
#'   modelling columns.
#' @param extra_na_vars Additional columns to include in the race-level
#'   NA drop (default none). Used by the interaction diagnostics to drop
#'   the draw-less race so the final model's columns are all non-NA.
#' @return An mlogit-formatted (`dfidx`) indexed data frame.
prepare_mlogit_data_p2 <- function(features_df, extra_na_vars = character(0)) {
  model_vars <- c(model_fitting_p2_vars(), extra_na_vars)

  bad_races <- features_df |>
    dplyr::filter(dplyr::if_any(dplyr::all_of(model_vars), is.na)) |>
    dplyr::pull(race_id) |>
    unique()

  if (length(bad_races) > 0L) {
    n_bad_runners <- features_df |>
      dplyr::filter(race_id %in% bad_races) |>
      nrow()
    message(
      "prepare_mlogit_data_p2: dropping ", length(bad_races),
      " race(s) (", n_bad_runners, " runner-rows) with NAs in modelling ",
      "columns. Most likely cause: trainerSR / sireSR / jockeySR NA for ",
      "debut trainers / first-time sires / debut jockeys."
    )
  }

  cleaned <- features_df |>
    dplyr::filter(!race_id %in% bad_races) |>
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

  na_cols <- purrr::keep(model_vars, \(v) anyNA(cleaned[[v]]))
  if (length(na_cols) > 0L) {
    stop(
      "NAs remain in paper-2 mlogit data after race-level drop: ",
      paste(na_cols, collapse = ", "), ". Investigate."
    )
  }

  mlogit_data
}

#' Fit the full paper-2 extended conditional logit (training)
#'
#' Fits the 19-term no-intercept (`| 0 | 0`) multinomial logit on the
#' prepared training data. Validity is checked on the returned object
#' itself (mlogit does not reliably populate a convergence code).
#'
#' @param mlogit_data Output of `prepare_mlogit_data_p2()` on the
#'   training split.
#' @return The fitted full `mlogit` object.
fit_extended_full <- function(mlogit_data) {
  formula <- stats::as.formula(
    paste("won ~", paste(model_fitting_p2_vars(), collapse = " + "), "| 0 | 0")
  )
  fitted <- mlogit::mlogit(formula, data = mlogit_data)

  if (!inherits(fitted, "mlogit") || is.null(fitted$coefficients)) {
    stop("paper-2 full mlogit fit failed: no coefficients returned")
  }
  pvals   <- summary(fitted)$CoefTable[, "Pr(>|z|)"]
  aliased <- names(pvals)[!is.na(pvals) & pvals == 1]
  if (length(aliased) > 0L) {
    warning(
      "Possible coefficient aliasing — p-value exactly 1.0 for: ",
      paste(aliased, collapse = ", ")
    )
  }
  fitted
}

#' Fit the reduced paper-2 model by backward elimination (one iteration)
#'
#' Drops every term with `p > 0.05` in the full fit and refits on the same
#' training data (all paper-2 terms are single coefficients, so "every
#' level non-significant" reduces to "the term is non-significant"). Then,
#' as specified, iterates **once**: if dropping those terms leaves any
#' newly non-significant term in the refit, drop it too and refit a final
#' time. Capped at one extra iteration.
#'
#' @param mlogit_data Output of `prepare_mlogit_data_p2()` on the
#'   training split (the reduced model is fitted on the same races as the
#'   full model, so the two are nested and directly comparable).
#' @param model_p2_full The fitted full model from `fit_extended_full()`.
#' @return The fitted reduced `mlogit` object.
fit_extended_reduced <- function(mlogit_data, model_p2_full) {
  loadNamespace("mlogit")

  sig_terms <- function(fit) {
    ct <- summary(fit)$CoefTable
    p  <- ct[, "Pr(>|z|)"]
    rownames(ct)[!is.na(p) & p <= 0.05]
  }
  refit <- function(terms) {
    if (length(terms) == 0L) {
      stop("paper-2 reduced model: no terms significant at p <= 0.05")
    }
    f <- stats::as.formula(
      paste("won ~", paste(terms, collapse = " + "), "| 0 | 0")
    )
    mlogit::mlogit(f, data = mlogit_data)
  }

  keep1 <- sig_terms(model_p2_full)
  fit1  <- refit(keep1)

  keep2 <- sig_terms(fit1)
  if (setequal(keep2, keep1)) {
    return(fit1)
  }
  refit(keep2)  # iterate once
}

#' Full / reduced paper-2 fit diagnostics
#'
#' Returns a two-row tibble (full, reduced) with the log-likelihood, null
#' (equal-probability) log-likelihood, depth-1 Plackett–Luce R²
#' (`1 - loglik / null_loglik`), race count and runner-row count. The null
#' log-likelihood and counts come from the fitted `$probabilities` matrix:
#' padded alternatives are zero, real ones strictly positive, so `> 0`
#' selects actual alternatives (matching paper 1's diagnostic).
#'
#' @param model_p2_full Fitted full model.
#' @param model_p2_reduced Fitted reduced model.
#' @return Tibble: `model`, `loglik`, `null_loglik`, `pl_r2`, `n_races`,
#'   `n_runners`.
extract_p2_diagnostics <- function(model_p2_full, model_p2_reduced) {
  loadNamespace("mlogit")

  one <- function(fit, label) {
    probs      <- fit$probabilities
    n_per_race <- rowSums(probs > 0)
    ll         <- as.numeric(stats::logLik(fit))
    ll_null    <- -sum(log(n_per_race))
    tibble::tibble(
      model       = label,
      loglik      = ll,
      null_loglik = ll_null,
      pl_r2       = 1 - ll / ll_null,
      n_races     = length(fit$fitted.values),
      n_runners   = sum(probs > 0)
    )
  }

  dplyr::bind_rows(
    one(model_p2_full,    "full"),
    one(model_p2_reduced, "reduced")
  )
}

#' Model / market probability ratio on the paper-2 test predictions
#'
#' Paper-2 analogue of `compute_model_market_ratio()`: keeps test rows
#' with both a positive model probability and a positive market
#' probability, and adds the ratio. Also exposes the model probability as
#' `model_prob` so the existing `run_backtest()` / `run_backtest_sweep()`
#' helpers in R/scoring.R apply unchanged.
#'
#' @param test_predictions_p2 Output of the `test_predictions_p2` target
#'   (carries `predicted_prob`, `market_prob`, `won`,
#'   `starting_price_decimal`).
#' @return The filtered tibble with `model_prob` (= `predicted_prob`) and
#'   `ratio = predicted_prob / market_prob` added.
compute_model_market_ratio_p2 <- function(test_predictions_p2) {
  test_predictions_p2 |>
    dplyr::filter(
      !is.na(predicted_prob), predicted_prob > 0,
      !is.na(market_prob),    market_prob    > 0
    ) |>
    dplyr::mutate(
      model_prob = predicted_prob,
      ratio      = predicted_prob / market_prob
    )
}

#' Build the exploded (Plackett–Luce) training data, truncated at depth k
#'
#' Implements the exploded conditional logit (notes/paper2_seed_plackett_luce.md,
#' @henery1981 truncation): each race's finishing order is turned into `k`
#' nested choice problems. Choice set `s` (s = 1..k) is the horse that
#' finished `s`th plus every horse not yet ranked — i.e. all finishers
#' placed `s`-or-worse, together with any non-finishers (which never get
#' ranked and stay in the pool at every depth). The "winner" of set `s` is
#' the horse that finished `s`th. Pooling the k*n_races sets and fitting a
#' single conditional logit maximises the depth-k Plackett–Luce likelihood.
#'
#' Depth-1 sub-races are exactly the win model's choice sets (the full
#' field, winner = 1st), so the exploded fit is nested-comparable with the
#' win model at depth 1.
#'
#' Filtering, in order:
#' * Races with any NA in the 19 paper-2 modelling columns are dropped —
#'   the same rule and race set as `prepare_mlogit_data_p2()`, so depth-1
#'   is comparable to the win model.
#' * Races whose top-`k` finishing positions are not each recorded exactly
#'   once (a tie or a gap in positions 1..k) are dropped — an ambiguous
#'   top-k cannot be exploded. Finishing position uses the project-wide
#'   `coalesce(amended_position, finish_position)`.
#' A `stopifnot` then asserts exactly one winner per exploded choice set.
#'
#' Feature columns are unchanged from the reduced win model (Model-S
#' position encoding, imputed `or_relative`, `or_missing`); no new
#' features. The composite `exploded_race_id = "<race_id>_<s>"` is the
#' `chid.var` and a per-set `horse_ref` is the `alt.var`.
#'
#' @param runners_train Training-split rows of `runners_model_ready`,
#'   joined to `finish_position` and `amended_position` (so finishing
#'   order is available). Must also carry the 19 paper-2 modelling columns.
#' @param k Truncation depth (default 3): model positions 1..k only.
#' @param extra_na_vars Additional columns to include in the race-level
#'   NA drop (default none). Used by the mixed-interaction models to drop
#'   races whose interaction features are NA (e.g. a draw-less runner's
#'   `stall_x_*`), so every interaction model shares one common sample.
#' @return An mlogit-formatted (`dfidx`) indexed data frame of the pooled
#'   exploded choice sets; `race_id`, `depth` and `exploded_race_id` are
#'   retained as columns.
prepare_exploded_data <- function(runners_train, k = 3, extra_na_vars = character(0)) {
  model_vars <- c(model_fitting_p2_vars(), extra_na_vars)

  ranked <- runners_train |>
    dplyr::mutate(finish_pos = dplyr::coalesce(amended_position, finish_position))

  # (1) Same modelling-NA race drop as the win model (matched race set).
  bad_races <- ranked |>
    dplyr::filter(dplyr::if_any(dplyr::all_of(model_vars), is.na)) |>
    dplyr::pull(race_id) |>
    unique()

  # (2) Keep races whose top-k positions are each recorded exactly once.
  topk_ok <- ranked |>
    dplyr::filter(!is.na(finish_pos), finish_pos %in% seq_len(k)) |>
    dplyr::count(race_id, finish_pos) |>
    dplyr::group_by(race_id) |>
    dplyr::summarise(
      ok = setequal(finish_pos, seq_len(k)) && all(n == 1L),
      .groups = "drop"
    ) |>
    dplyr::filter(ok) |>
    dplyr::pull(race_id)

  keep_races <- setdiff(topk_ok, bad_races)
  if (length(keep_races) == 0L) {
    stop("prepare_exploded_data: no races survive filtering.")
  }
  ranked <- dplyr::filter(ranked, race_id %in% keep_races)

  # (3) Explode into k nested choice sets. Non-finishers (NA position) stay
  #     in every pool as never-ranked alternatives.
  exploded <- purrr::map_dfr(seq_len(k), function(s) {
    ranked |>
      dplyr::filter(finish_pos >= s | is.na(finish_pos)) |>
      dplyr::mutate(
        won              = as.integer(!is.na(finish_pos) & finish_pos == s),
        depth            = s,
        exploded_race_id = paste(race_id, s, sep = "_")
      )
  })

  exploded <- exploded |>
    dplyr::group_by(exploded_race_id) |>
    dplyr::mutate(horse_ref = dplyr::row_number()) |>
    dplyr::ungroup()

  winners <- exploded |>
    dplyr::count(exploded_race_id, wt = won, name = "n_winners")
  stopifnot(all(winners$n_winners == 1L))

  mlogit::mlogit.data(
    exploded,
    shape    = "long",
    choice   = "won",
    chid.var = "exploded_race_id",
    alt.var  = "horse_ref"
  )
}

#' Fit the exploded conditional logit (reduced specification)
#'
#' Fits the **same 17-term reduced formula** as the paper-2 win model,
#' on the pooled exploded choice sets. The specification is identical;
#' mlogit simply sees more (and smaller) choice problems, so the
#' coefficients are the depth-k Plackett–Luce estimates of the same
#' parameters.
#'
#' @param exploded_data Output of `prepare_exploded_data()`.
#' @param model_p2_reduced The reduced win model; its coefficient names
#'   define the 17-term formula (single source of truth).
#' @return The fitted exploded `mlogit` object.
fit_exploded_model <- function(exploded_data, model_p2_reduced) {
  loadNamespace("mlogit")
  terms   <- names(stats::coef(model_p2_reduced))
  formula <- stats::as.formula(
    paste("won ~", paste(terms, collapse = " + "), "| 0 | 0")
  )
  fitted <- mlogit::mlogit(formula, data = exploded_data)
  if (!inherits(fitted, "mlogit") || is.null(fitted$coefficients)) {
    stop("exploded mlogit fit failed: no coefficients returned")
  }
  fitted
}

#' Diagnostics for the exploded model, depth-1 comparable to the win model
#'
#' Reports the exploded model on the same footing as `model_p2_diagnostics`
#' so the two are directly comparable. PL-R² is computed **at depth 1 on
#' the original (non-exploded) win-model training races** using the
#' exploded model's coefficients: per race, the softmax over the full field
#' gives each runner's win probability, and the depth-1 log-likelihood is
#' the sum of log winner-probabilities. This is the win problem the win
#' model's PL-R² also scores, on identical races/runners.
#'
#' `pl_loglik_depth3` additionally reports the fitted exploded model's own
#' (depth-1..k) Plackett–Luce log-likelihood, for reference — it is on the
#' pooled exploded data, not comparable to the depth-1 figures.
#'
#' @param model_p2_exploded Fitted exploded (or exploded+interaction)
#'   model.
#' @param mlogit_train_data The non-exploded training data whose columns
#'   include every term of the fitted model (`mlogit_train_data_p2` for
#'   the plain exploded model; `mlogit_train_data_interactions` for the
#'   final model, which carries the draw-course columns).
#' @param label Value for the `model` column (default "exploded").
#' @return Tibble: `model`, `loglik` (depth-1), `null_loglik`, `pl_r2`
#'   (depth-1), `n_races`, `n_runners`, `pl_loglik_depth3`.
extract_p2_exploded_diagnostics <- function(model_p2_exploded, mlogit_train_data,
                                            label = "exploded") {
  loadNamespace("mlogit")
  beta  <- stats::coef(model_p2_exploded)
  terms <- names(beta)

  df <- as.data.frame(mlogit_train_data)
  class(df) <- "data.frame"
  attr(df, "index")    <- NULL
  attr(df, "clseries") <- NULL

  X <- as.matrix(df[, terms, drop = FALSE])
  df$.z   <- as.vector(X %*% beta)
  df$.won <- as.integer(df$won)
  df$.rid <- as.integer(as.character(df$race_id))

  per_race <- df |>
    dplyr::group_by(.rid) |>
    dplyr::mutate(.p = exp(.z - max(.z)) / sum(exp(.z - max(.z)))) |>
    dplyr::summarise(
      n_alt = dplyr::n(),
      ll    = log(.p[.won == 1L]),
      .groups = "drop"
    )

  ll1     <- sum(per_race$ll)
  ll_null <- -sum(log(per_race$n_alt))

  tibble::tibble(
    model            = label,
    loglik           = ll1,
    null_loglik      = ll_null,
    pl_r2            = 1 - ll1 / ll_null,
    n_races          = nrow(per_race),
    n_runners        = sum(per_race$n_alt),
    pl_loglik_depth3 = as.numeric(stats::logLik(model_p2_exploded))
  )
}

#' Fit an exploded model with the reduced base plus optional interaction terms
#'
#' Fits the 17-term reduced specification (base, from `model_p2_reduced`)
#' plus any `extra_terms`, on pooled exploded choice sets. Used for the
#' mixed-interaction models E / EW / ED / EWD, which must all be fitted on
#' the **same** exploded data so the likelihood-ratio tests between them
#' are valid (nested models, identical sample).
#'
#' @param exploded_data Output of `prepare_exploded_data()` built from the
#'   interaction features (so the `extra_terms` columns are present).
#' @param model_p2_reduced The reduced win model; its coefficient names
#'   define the 17-term base formula.
#' @param extra_terms Character vector of additional interaction columns to
#'   add to the formula (default none -> Model E baseline).
#' @return The fitted `mlogit` object.
fit_exploded_interaction <- function(exploded_data, model_p2_reduced,
                                     extra_terms = character(0)) {
  loadNamespace("mlogit")
  terms   <- c(names(stats::coef(model_p2_reduced)), extra_terms)
  formula <- stats::as.formula(
    paste("won ~", paste(terms, collapse = " + "), "| 0 | 0")
  )
  fitted <- mlogit::mlogit(formula, data = exploded_data)
  if (!inherits(fitted, "mlogit") || is.null(fitted$coefficients)) {
    stop("exploded interaction fit failed: no coefficients returned")
  }
  fitted
}

#' One nested likelihood-ratio test between two fitted mlogit models
#'
#' For nested models on the **same** sample, the LR statistic is
#' `2 * (logLik_larger - logLik_smaller)`, chi-squared with `df` = the
#' difference in free parameters. `decision` flags whether the larger
#' model is preferred at p < 0.05 ("significant") or not ("ns").
#'
#' @param model_larger,model_smaller The two nested fits (larger nests
#'   smaller, on identical observations).
#' @param name_larger,name_smaller Labels for the output row.
#' @return One-row tibble: `model_a` (larger), `model_b` (smaller),
#'   `lr_stat`, `df`, `p_value`, `decision`.
lr_test_pair <- function(model_larger, model_smaller, name_larger, name_smaller) {
  loadNamespace("mlogit")
  ll <- function(m) as.numeric(stats::logLik(m))
  np <- function(m) length(stats::coef(m))
  lr <- 2 * (ll(model_larger) - ll(model_smaller))
  df <- np(model_larger) - np(model_smaller)
  p  <- stats::pchisq(lr, df = df, lower.tail = FALSE)
  tibble::tibble(
    model_a  = name_larger, model_b = name_smaller,
    lr_stat  = lr, df = df, p_value = p,
    decision = if (p < 0.05) "significant" else "ns"
  )
}

#' The five likelihood-ratio tests among the interaction models
#'
#' All four models are fitted on one common exploded sample, so each pair
#' is nested. The final-model choice (most parsimonious model not
#' rejected) is made from this table downstream.
#'
#' @param model_p2_e,model_p2_ew,model_p2_ed,model_p2_ewd The four fitted
#'   models: baseline, +weight*distance, +draw*course, +both.
#' @return Tibble with columns `model_a` (larger), `model_b` (smaller),
#'   `lr_stat`, `df`, `p_value`, `decision`.
build_interaction_lr_tests <- function(model_p2_e, model_p2_ew,
                                       model_p2_ed, model_p2_ewd) {
  dplyr::bind_rows(
    lr_test_pair(model_p2_ew,  model_p2_e,  "EW",  "E"),   # weight*distance vs baseline (df 1)
    lr_test_pair(model_p2_ed,  model_p2_e,  "ED",  "E"),   # draw*course vs baseline (df 4)
    lr_test_pair(model_p2_ewd, model_p2_e,  "EWD", "E"),   # both vs baseline (df 5)
    lr_test_pair(model_p2_ewd, model_p2_ew, "EWD", "EW"),  # draw | weight (df 4)
    lr_test_pair(model_p2_ewd, model_p2_ed, "EWD", "ED")   # weight | draw (df 1)
  )
}

#' Per-term Wald reduction of the exploded draw-course block (paper 2b)
#'
#' Backward elimination on the draw-course slopes of an exploded
#' (Plackett–Luce, depth-3) fit, by the same per-term Wald p < 0.05 rule
#' paper 2a applies to its win model: at each step the **single** least
#' significant draw slope with Wald p \eqn{\geq} `alpha` is dropped, the
#' model refit on the same exploded sample, and the step recorded (the
#' dropped term's Wald p plus the 1-df likelihood-ratio drop-test between
#' the before/after fits). It stops when every surviving draw slope is
#' significant at `alpha` (or none remain). The 17 base feature terms are
#' held fixed throughout (they were reduced upstream into
#' `model_p2_reduced`), so only the draw block is pruned.
#'
#' Run **fresh** for paper 2b — it does not assume paper 2a's surviving
#' set. On the exploded fit the draw block is estimated more sharply than on
#' the win-only model, so the surviving courses can differ from 2a's; the
#' difference is itself a finding (e.g. Wolverhampton, marginal and dropped
#' in 2a's win model, is significant here and retained).
#'
#' @param model_full The fitted full-block model (all `draw_terms` present),
#'   from `fit_exploded_interaction()`; used as the starting fit.
#' @param exploded_data The pooled exploded choice data the block was fit
#'   on (so refits share the identical sample and the LR tests are nested).
#' @param model_p2_reduced The reduced win model defining the 17-term base.
#' @param draw_terms Character vector of the candidate draw-course columns
#'   (the full block, e.g. the four `stall_x_*` terms).
#' @param alpha Wald significance threshold for retention (default 0.05).
#' @return A list: `fit` (the final reduced exploded fit), `surviving`
#'   (character vector of retained draw terms), and `steps` (a tibble, one
#'   row per dropped term: `step`, `dropped`, `wald_p`, `n_before`,
#'   `n_after`, `lr_stat`, `lr_df`, `lr_p`).
reduce_exploded_draw_block <- function(model_full, exploded_data,
                                       model_p2_reduced, draw_terms,
                                       alpha = 0.05) {
  loadNamespace("mlogit")
  current <- draw_terms
  fit     <- model_full
  steps   <- list()

  repeat {
    ct <- summary(fit)$CoefTable
    p  <- ct[current, "Pr(>|z|)"]
    if (length(current) == 0L || max(p) < alpha) break
    worst   <- current[which.max(p)]
    reduced <- setdiff(current, worst)
    fit_red <- fit_exploded_interaction(exploded_data, model_p2_reduced,
                                        extra_terms = reduced)
    lr <- lr_test_pair(fit, fit_red,
                       paste0(length(current), "-course"),
                       paste0(length(reduced), "-course"))
    steps[[length(steps) + 1L]] <- tibble::tibble(
      step     = length(steps) + 1L,
      dropped  = sub("stall_x_", "", worst),
      wald_p   = unname(p[which.max(p)]),
      n_before = length(current),
      n_after  = length(reduced),
      lr_stat  = lr$lr_stat, lr_df = lr$df, lr_p = lr$p_value
    )
    current <- reduced
    fit     <- fit_red
  }

  list(
    fit       = fit,
    surviving = current,
    steps     = if (length(steps)) dplyr::bind_rows(steps) else
      tibble::tibble(step = integer(), dropped = character(),
                     wald_p = double(), n_before = integer(),
                     n_after = integer(), lr_stat = double(),
                     lr_df = integer(), lr_p = double())
  )
}
