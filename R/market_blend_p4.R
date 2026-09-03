# market_blend_p4.R
#
# Paper 4 — the two-stage conditional-logit blend of a market price and a
# model probability (Benter's construction):
#
#     V_ij = b_mkt * log(P_mkt_ij) + b_mod * log(P_mod_ij)
#
# fitted with BOTH coefficients free. `b_mod` is the output: it asks
# whether the model carries information the market price does not.
#
# Three price arms, all on one common race set:
#   A  `daily_runners.forecast_price_decimal`, feed rows written
#      strictly before the meeting date — a genuinely pre-race price.
#   B  `historic_runners.starting_price_decimal` — the series' SP.
#   C  `historic_runners.forecast_price_decimal` — the archived forecast
#      price, written post-race and shown by the P4-0 audit to have
#      drifted toward SP. Carried so the contamination is measured
#      rather than assumed.
#
# Two model arms, both reused from the frozen store, neither refitted:
# paper 2b's exploded conditional logit and paper 3's GBT.

# -- Market probability construction --------------------------------------

#' Proportionally overround-adjusted win probabilities
#'
#' The single implementation of the market-probability construction used
#' throughout paper 4. It is deliberately the same arithmetic the series
#' already applies to SP inside
#' `R/scoring.R::build_test_predictions()` — implied probability
#' `1 / price`, renormalised to sum to one over the race's field —
#' rather than a second, independently written version of it.
#' `scripts/verify_p4_market_probs.R` is the standing gate on that
#' equivalence: it asserts this function reproduces the stored
#' `win_market` column of `test_predictions_3` exactly.
#'
#' Applied within a race (i.e. under `dplyr::group_by(race_id)`), over
#' the runners the series' pipeline actually uses. Races are dropped
#' whole upstream if any runner lacks a price, so no `na.rm` special
#' case is needed here: an NA in, an NA out, loudly.
#'
#' @param price Numeric vector of decimal odds (stake included) for the
#'   runners in one race.
#' @return Numeric vector the same length as `price`, summing to 1.
normalise_overround <- function(price) {
  implied <- 1 / price
  implied / sum(implied)
}

#' Pull every paper-4 price column for a set of runner-races
#'
#' Opens and closes its own connection. Returns one row per
#' (race_id, runner_id) supplied, with all three price columns and the
#' daily-feed row's load lag so the pre-race restriction on arm A can be
#' applied downstream rather than silently inside the query.
#'
#' `daily_runners` holds exactly one row per (runner_id, race_id) — the
#' P4-0 audit checked this (1,064,594 rows over 1,064,594 distinct keys),
#' so the LEFT JOIN cannot fan out.
#'
#' @param race_ids Integer vector of race_id values.
#' @return A tibble with `race_id`, `runner_id`, `meeting_date`,
#'   `fp_feed`, `feed_lag_days`, `fp_arch`, `sp`.
read_p4_price_sources <- function(race_ids) {
  stopifnot(length(race_ids) > 0)

  con <- connect_smartform()
  on.exit(disconnect_smartform(con), add = TRUE)

  sql <- sprintf(
    "SELECT h.race_id, h.runner_id, r.meeting_date,
            d.forecast_price_decimal AS fp_feed,
            DATEDIFF(d.loaded_at, r.meeting_date) AS feed_lag_days,
            h.forecast_price_decimal AS fp_arch,
            h.starting_price_decimal AS sp
       FROM historic_runners AS h
       INNER JOIN historic_races AS r ON r.race_id = h.race_id
       LEFT  JOIN daily_runners  AS d
              ON d.runner_id = h.runner_id AND d.race_id = h.race_id
      WHERE h.race_id IN (%s)",
    paste(race_ids, collapse = ", ")
  )

  tibble::as_tibble(DBI::dbGetQuery(con, sql))
}

#' Assemble the paper-4 price / model panel
#'
#' Joins the three price columns onto the frozen test-set predictions of
#' papers 2b and 3, and flags each price as usable or not. "Usable" is
#' non-NA and strictly greater than 1: a decimal price of 1 or below
#' implies a probability of 1 or more and cannot be normalised. Arm A
#' additionally requires the daily-feed row to have been written strictly
#' before the meeting date.
#'
#' No rows are dropped here — selection happens in
#' `select_p4_common_races()`, so the cost of each column stays visible.
#'
#' @param preds_3   The `test_predictions_3` target (paper 3's GBT).
#' @param preds_2b  The `test_predictions_2b` target (paper 2b).
#' @param raw_prices Output of `read_p4_price_sources()`.
#' @return A tibble keyed by (race_id, runner_id) with `won`, the two
#'   model probabilities, the three prices, and a usability flag each.
build_p4_price_panel <- function(preds_3, preds_2b, raw_prices) {
  model_probs <- preds_3 |>
    dplyr::select(race_id, runner_id, won, p_mod_3 = win_model,
                  win_market_stored = win_market) |>
    dplyr::inner_join(
      preds_2b |> dplyr::select(race_id, runner_id, p_mod_2b = win_model),
      by = c("race_id", "runner_id")
    )

  stopifnot(
    nrow(model_probs) == nrow(preds_3),
    !anyNA(model_probs$p_mod_2b),
    !anyNA(model_probs$p_mod_3)
  )

  model_probs |>
    dplyr::left_join(raw_prices, by = c("race_id", "runner_id")) |>
    dplyr::mutate(
      feed_prerace = !is.na(feed_lag_days) & feed_lag_days < 0,
      ok_A = !is.na(fp_feed) & fp_feed > 1 & feed_prerace,
      ok_B = !is.na(sp)      & sp      > 1,
      ok_C = !is.na(fp_arch) & fp_arch > 1
    )
}

#' Choose the race set every arm is fitted on
#'
#' A paired comparison of `b_mod` across arms is void if the arms sit on
#' different races, so all three arms use the intersection: races where
#' every runner the pipeline uses has a usable price in *all three*
#' columns. Returns both the chosen set and the per-column accounting, so
#' P4-3 can report what each column cost.
#'
#' @param panel Output of `build_p4_price_panel()`.
#' @return A list with `race_ids` (integer vector) and `accounting`
#'   (tibble, one row per price column plus the intersection).
select_p4_common_races <- function(panel) {
  by_race <- panel |>
    dplyr::group_by(race_id) |>
    dplyr::summarise(
      n_runners  = dplyr::n(),
      complete_A = all(ok_A),
      complete_B = all(ok_B),
      complete_C = all(ok_C),
      .groups    = "drop"
    ) |>
    dplyr::mutate(complete_all = complete_A & complete_B & complete_C)

  accounting <- tibble::tibble(
    price_set = c("A — pre-race racecard forecast",
                  "B — industry starting price",
                  "C — archived racecard forecast",
                  "intersection (all three)"),
    races_complete = c(sum(by_race$complete_A), sum(by_race$complete_B),
                       sum(by_race$complete_C), sum(by_race$complete_all)),
    races_offered  = nrow(by_race)
  ) |>
    dplyr::mutate(
      pct_complete = races_complete / races_offered,
      races_lost   = races_offered - races_complete
    )

  list(
    race_ids   = sort(by_race$race_id[by_race$complete_all]),
    accounting = accounting,
    by_race    = by_race
  )
}

#' Build the floored log-probability regressors for every arm
#'
#' Restricts to the common race set, normalises each price column within
#' race via `normalise_overround()`, floors every probability — market
#' and model alike — at `floor_at` before taking logs, and reports how
#' many rows the floor binds on.
#'
#' The floor is a guard, not a correction: on this data it is expected to
#' bind on nothing, and the count is carried into the report so that
#' "expected" is checked rather than assumed.
#'
#' @param panel Output of `build_p4_price_panel()`.
#' @param common_race_ids Integer vector from `select_p4_common_races()`.
#' @param floor_at Lower bound applied before `log()`. Default 1e-6.
#' @return A tibble of the modelling rows, with `p_mkt_A/B/C`,
#'   `p_mod_2b/3`, their logs, `field_size`, and a `floor_binds` attribute.
build_p4_market_probs <- function(panel, common_race_ids, floor_at = 1e-6) {
  dat <- panel |>
    dplyr::filter(race_id %in% common_race_ids) |>
    dplyr::group_by(race_id) |>
    dplyr::mutate(
      field_size = dplyr::n(),
      p_mkt_A    = normalise_overround(fp_feed),
      p_mkt_B    = normalise_overround(sp),
      p_mkt_C    = normalise_overround(fp_arch)
    ) |>
    dplyr::ungroup()

  prob_cols <- c("p_mkt_A", "p_mkt_B", "p_mkt_C", "p_mod_2b", "p_mod_3")

  floor_binds <- tibble::tibble(
    column = prob_cols,
    n_rows_floored = vapply(prob_cols,
                            \(v) sum(dat[[v]] < floor_at, na.rm = TRUE),
                            integer(1)),
    min_value = vapply(prob_cols, \(v) min(dat[[v]], na.rm = TRUE), numeric(1))
  )

  out <- dat |>
    dplyr::mutate(dplyr::across(dplyr::all_of(prob_cols),
                                \(p) pmax(p, floor_at))) |>
    dplyr::mutate(
      log_p_mkt_A  = log(p_mkt_A),
      log_p_mkt_B  = log(p_mkt_B),
      log_p_mkt_C  = log(p_mkt_C),
      log_p_mod_2b = log(p_mod_2b),
      log_p_mod_3  = log(p_mod_3)
    )

  stopifnot(all(is.finite(out$log_p_mkt_A)), all(is.finite(out$log_p_mkt_B)),
            all(is.finite(out$log_p_mkt_C)), all(is.finite(out$log_p_mod_2b)),
            all(is.finite(out$log_p_mod_3)))

  attr(out, "floor_binds") <- floor_binds
  attr(out, "floor_at")    <- floor_at
  out
}

# -- The chronological test-A / test-B split ------------------------------

#' Split the common race set chronologically 50/50
#'
#' Test-A (earlier) is fitted and reported on; test-B (later) is reserved
#' untouched for a later performance evaluation and is not scored here.
#'
#' The boundary is a calendar date, not a row index, so the split is
#' reproducible against an exact date irrespective of upstream changes —
#' the same convention the series' main 2012-12-30 train/test cutoff
#' follows. All races on the cutoff date fall in test-A. The cutoff is
#' the earliest date at which at least half the races have been reached.
#'
#' @param probs Output of `build_p4_market_probs()`.
#' @return The same tibble with a `split_ab` column ("A" or "B"), and a
#'   `cutoff` attribute.
split_test_ab <- function(probs) {
  race_dates <- probs |>
    dplyr::distinct(race_id, meeting_date) |>
    dplyr::arrange(meeting_date, race_id)

  per_date <- race_dates |>
    dplyr::count(meeting_date, name = "n_races") |>
    dplyr::arrange(meeting_date) |>
    dplyr::mutate(cum = cumsum(n_races))

  target  <- nrow(race_dates) / 2
  cutoff  <- per_date$meeting_date[which(per_date$cum >= target)[1]]

  out <- probs |>
    dplyr::mutate(split_ab = dplyr::if_else(meeting_date <= cutoff, "A", "B"))

  attr(out, "cutoff") <- cutoff
  out
}

# -- Fitting --------------------------------------------------------------

#' Shape a paper-4 modelling tibble for `{mlogit}`
#'
#' Race is the chooser (`chid.var`); `horse_ref` is a per-race index
#' `1..n_runners` used as `alt.var`, never the population-wide
#' `runner_id` — see CLAUDE.md, "`{mlogit}` `alt.var` must be a per-race
#' index".
#'
#' @param df A subset of `build_p4_market_probs()`'s output.
#' @return An `mlogit.data` object.
prepare_blend_mlogit_data <- function(df) {
  cleaned <- df |>
    dplyr::arrange(race_id, runner_id) |>
    dplyr::group_by(race_id) |>
    dplyr::mutate(horse_ref = dplyr::row_number()) |>
    dplyr::ungroup()

  stopifnot(all(
    cleaned |>
      dplyr::group_by(race_id) |>
      dplyr::summarise(ok = sum(won) == 1L, .groups = "drop") |>
      dplyr::pull(ok)
  ))

  mlogit::mlogit.data(
    as.data.frame(cleaned),
    shape    = "long",
    choice   = "won",
    chid.var = "race_id",
    alt.var  = "horse_ref"
  )
}

#' Fit one blend by conditional logit
#'
#' No intercept: an alternative-invariant constant cancels in the
#' softmax, so the three-part formula is `won ~ <terms> | 0 | 0`. The
#' `| 0 | 0` shape is load-bearing on this project — see CLAUDE.md.
#'
#' @param mlogit_data Output of `prepare_blend_mlogit_data()`.
#' @param terms Character vector of regressor names.
#' @return A fitted `mlogit` object.
fit_blend <- function(mlogit_data, terms) {
  stopifnot(length(terms) > 0)
  f <- stats::as.formula(
    paste("won ~", paste(terms, collapse = " + "), "| 0 | 0")
  )
  mlogit::mlogit(f, data = mlogit_data)
}

#' Equal-probability null log-likelihood for a set of races
#'
#' The reference for McFadden's pseudo-R-squared under a no-intercept
#' conditional logit: every runner in a race of size n gets 1/n, so the
#' null log-likelihood is -sum(log(n_j)) over races.
#'
#' `{mlogit}`'s own reported R-squared is taken against an
#' intercept-only model, which does not exist here; computing the null
#' explicitly avoids relying on that.
#'
#' @param df A modelling tibble with a `race_id` column.
#' @return A single numeric.
null_loglik <- function(df) {
  sizes <- df |>
    dplyr::count(race_id, name = "n_runners") |>
    dplyr::pull(n_runners)
  -sum(log(sizes))
}

#' Tabulate one fitted blend
#'
#' Confidence intervals are Wald: estimate +/- 1.96 * SE. They are the
#' interval matching the z-statistics reported alongside, so a coefficient
#' whose interval excludes zero is exactly one whose z-test rejects.
#'
#' @param fit A fitted `mlogit` object.
#' @param df The tibble the fit was built from (for the null and counts).
#' @param label Short arm label, e.g. "A1".
#' @param model_source,price_source Descriptive strings for the report.
#' @param sample Which race set the fit was built on, e.g. "test-A".
#' @return A one-row-per-coefficient tibble.
summarise_blend_fit <- function(fit, df, label, model_source, price_source,
                                sample = "test-A") {
  loadNamespace("mlogit")
  ct <- summary(fit)$CoefTable
  ll <- as.numeric(stats::logLik(fit))
  ll0 <- null_loglik(df)
  crit <- stats::qnorm(0.975)

  tibble::tibble(
    arm          = label,
    sample       = sample,
    model_source = model_source,
    price_source = price_source,
    term         = rownames(ct),
    estimate     = ct[, "Estimate"],
    std_error    = ct[, "Std. Error"],
    conf_low     = ct[, "Estimate"] - crit * ct[, "Std. Error"],
    conf_high    = ct[, "Estimate"] + crit * ct[, "Std. Error"],
    z            = ct[, "z-value"],
    p_value      = ct[, "Pr(>|z|)"],
    logLik       = ll,
    null_logLik  = ll0,
    mcfadden_r2  = 1 - ll / ll0,
    n_races      = dplyr::n_distinct(df$race_id),
    n_runners    = nrow(df)
  )
}

#' Likelihood-ratio test of a nested pair of `mlogit` fits
#'
#' @param fit_full,fit_reduced Fitted `mlogit` objects, reduced nested in
#'   full.
#' @param label Character describing the contrast.
#' @return A one-row tibble.
lr_test_blend <- function(fit_full, fit_reduced, label) {
  ll_f <- as.numeric(stats::logLik(fit_full))
  ll_r <- as.numeric(stats::logLik(fit_reduced))
  df_diff <- length(stats::coef(fit_full)) - length(stats::coef(fit_reduced))
  stat <- 2 * (ll_f - ll_r)

  tibble::tibble(
    contrast   = label,
    logLik_full = ll_f,
    logLik_reduced = ll_r,
    lr_stat    = stat,
    df         = df_diff,
    p_value    = stats::pchisq(stat, df = df_diff, lower.tail = FALSE)
  )
}

# -- Amendment 2: is the archive a revision, or is the feed noisy? --------

#' Collinearity diagnostics for the three market columns
#'
#' Amendment 2 puts two market columns in one conditional logit. If they
#' are near-collinear the individual coefficients are unstable and can
#' take signs that do not survive as a statement about either column on
#' its own, so the correlation between them has to be on the table
#' alongside the fit.
#'
#' Correlations are reported both raw and within-race demeaned. The
#' demeaned version is the relevant one: a conditional logit is invariant
#' to race-constant shifts of a regressor, so only within-race variation
#' identifies a coefficient.
#'
#' @param probs Output of `build_p4_market_probs()`.
#' @return A tibble, one row per column pair.
market_column_correlations <- function(probs) {
  demeaned <- probs |>
    dplyr::group_by(race_id) |>
    dplyr::mutate(dplyr::across(
      c(log_p_mkt_A, log_p_mkt_B, log_p_mkt_C, log_p_mod_2b, log_p_mod_3),
      \(x) x - mean(x), .names = "{.col}_c"
    )) |>
    dplyr::ungroup()

  pairs <- list(
    c("log_p_mkt_A", "log_p_mkt_C"),
    c("log_p_mkt_A", "log_p_mkt_B"),
    c("log_p_mkt_C", "log_p_mkt_B"),
    c("log_p_mkt_A", "log_p_mod_2b"),
    c("log_p_mkt_B", "log_p_mod_2b"),
    c("log_p_mkt_A", "log_p_mod_3"),
    c("log_p_mkt_B", "log_p_mod_3")
  )

  purrr::map_dfr(pairs, \(p) tibble::tibble(
    x = p[1], y = p[2],
    corr_raw = stats::cor(probs[[p[1]]], probs[[p[2]]]),
    corr_within_race = stats::cor(demeaned[[paste0(p[1], "_c")]],
                                  demeaned[[paste0(p[2], "_c")]])
  ))
}

#' Discriminate genuine revision from transcription noise
#'
#' Fits a conditional logit carrying BOTH `log(p_archive)` and
#' `log(p_feed)` on the common race set, and tests it against the
#' feed-only model.
#'
#' The two readings of the P4-0 divergence make opposite predictions:
#'   * If the archive is a genuine later revision, it holds information
#'     the feed does not, its coefficient is distinguishable from zero,
#'     and arm C is a contamination estimate.
#'   * If the divergence is transcription noise around one morning
#'     price, the archive adds nothing once the feed is in, its
#'     coefficient is indistinguishable from zero, and arm A carries an
#'     errors-in-variables attenuation that inflates `b_mod`.
#'
#' @param probs Output of `build_p4_market_probs()`.
#' @return A list of the two fits, the coefficient table and the LR test.
run_amendment2_test <- function(probs) {
  md <- prepare_blend_mlogit_data(probs)

  fit_both <- fit_blend(md, c("log_p_mkt_C", "log_p_mkt_A"))
  fit_feed <- fit_blend(md, "log_p_mkt_A")
  fit_arch <- fit_blend(md, "log_p_mkt_C")

  list(
    coefficients = summarise_blend_fit(
      fit_both, probs, "AMD2",
      "none (market columns only)", "archive + pre-race feed"
    ),
    feed_only = summarise_blend_fit(
      fit_feed, probs, "AMD2-feed", "none", "pre-race feed only"
    ),
    archive_only = summarise_blend_fit(
      fit_arch, probs, "AMD2-arch", "none", "archive only"
    ),
    lr = dplyr::bind_rows(
      lr_test_blend(fit_both, fit_feed,
                    "archive + feed vs feed only (does the archive add?)"),
      lr_test_blend(fit_both, fit_arch,
                    "archive + feed vs archive only (does the feed add?)")
    )
  )
}

# -- Amendment 4: does b_mod survive a more flexible market term? --------

#' Refit an arm with a more flexible market term
#'
#' A single `b_mkt` absorbs a power-law miscalibration of the market but
#' not one that varies with field size, and the P4-0 audit found the
#' forecast book's overround running from 1.071 at four runners to 1.323
#' at sixteen. If `b_mod` is really residual recalibration rather than
#' information, it should collapse once the market term is free to bend.
#'
#' Two flexible specifications are fitted, both against a matching
#' market-only model so the likelihood-ratio test isolates the model
#' term:
#'   * a natural spline in `log(P_mkt)` (`df` basis columns), and
#'   * `log(P_mkt)` interacted with mean-centred field size.
#'
#' The spline basis is built once on the supplied data so its knots are
#' fixed across the nested pair.
#'
#' @param df Modelling tibble (test-A).
#' @param mkt_col,mod_col Column names of the market and model log-probs.
#' @param label Arm label for the output.
#' @param spline_df Degrees of freedom for the natural spline.
#' @return A list with a coefficient tibble and an LR tibble.
fit_flexible_market <- function(df, mkt_col, mod_col, label, spline_df = 4L) {
  basis <- splines::ns(df[[mkt_col]], df = spline_df)
  basis_cols <- paste0("mkt_ns_", seq_len(ncol(basis)))

  aug <- df
  aug[basis_cols] <- as.data.frame(unclass(basis))
  aug$field_size_c  <- aug$field_size - mean(aug$field_size)
  aug$mkt_x_field   <- aug[[mkt_col]] * aug$field_size_c

  md <- prepare_blend_mlogit_data(aug)

  fit_spline_full <- fit_blend(md, c(basis_cols, mod_col))
  fit_spline_mkt  <- fit_blend(md, basis_cols)
  fit_inter_full  <- fit_blend(md, c(mkt_col, "mkt_x_field", mod_col))
  fit_inter_mkt   <- fit_blend(md, c(mkt_col, "mkt_x_field"))

  list(
    coefficients = dplyr::bind_rows(
      summarise_blend_fit(fit_spline_full, aug, paste0(label, "-spline"),
                          mod_col, paste0(mkt_col, " (natural spline, df=",
                                          spline_df, ")")),
      summarise_blend_fit(fit_inter_full, aug, paste0(label, "-fieldint"),
                          mod_col, paste0(mkt_col, " x field size"))
    ),
    lr = dplyr::bind_rows(
      lr_test_blend(fit_spline_full, fit_spline_mkt,
                    paste0(label, " spline: blend vs market-only")),
      lr_test_blend(fit_inter_full, fit_inter_mkt,
                    paste0(label, " field interaction: blend vs market-only"))
    )
  )
}

# -- The full P4-2 arm grid ----------------------------------------------

#' Fit every P4-2 arm on test-A
#'
#' Six blends — two model sources by three price sources — plus the
#' three market-only reference models they are tested against. All arms
#' sit on one `mlogit.data` object built from one race set, so the
#' cross-arm comparison of `b_mod` is paired by construction.
#'
#' @param test_a The race subset to fit on.
#' @param sample Label for the race set, carried into the output.
#' @return A list with `coefficients`, `lr`, and `fits`.
fit_p4_arm_grid <- function(test_a, sample = "test-A") {
  md <- prepare_blend_mlogit_data(test_a)

  price_cols <- c(A = "log_p_mkt_A", B = "log_p_mkt_B", C = "log_p_mkt_C")
  price_desc <- c(A = "pre-race feed forecast",
                  B = "starting price",
                  C = "archived forecast")
  model_cols <- c(`1` = "log_p_mod_2b", `2` = "log_p_mod_3")
  model_desc <- c(`1` = "paper 2b (exploded conditional logit)",
                  `2` = "paper 3 (gradient boosted trees)")

  market_only <- lapply(names(price_cols), \(p) fit_blend(md, price_cols[[p]]))
  names(market_only) <- names(price_cols)

  coefs <- list()
  lrs   <- list()
  fits  <- list()

  for (p in names(price_cols)) {
    for (m in names(model_cols)) {
      arm <- paste0(p, m)
      fit <- fit_blend(md, c(price_cols[[p]], model_cols[[m]]))
      fits[[arm]] <- fit
      coefs[[arm]] <- summarise_blend_fit(fit, test_a, arm,
                                          model_desc[[m]], price_desc[[p]],
                                          sample = sample)
      lrs[[arm]] <- lr_test_blend(
        fit, market_only[[p]],
        paste0(arm, ": blend vs market-only (", price_desc[[p]], ")")
      ) |> dplyr::mutate(arm = arm, sample = sample, .before = 1)
    }
  }

  market_only_coefs <- dplyr::bind_rows(lapply(names(price_cols), \(p) {
    summarise_blend_fit(market_only[[p]], test_a, paste0(p, "-mktonly"),
                        "none (market only)", price_desc[[p]], sample = sample)
  }))

  list(
    coefficients      = dplyr::bind_rows(coefs),
    market_only       = market_only_coefs,
    lr                = dplyr::bind_rows(lrs),
    fits              = fits,
    market_only_fits  = market_only
  )
}

# -- Follow-up: independent replication on test-B -------------------------

#' Compare the same arm fitted on two disjoint race sets
#'
#' Test-A and test-B are disjoint sets of races, so the two estimates of
#' a coefficient are independent and the difference between them has
#' variance `se_A^2 + se_B^2`. That gives a direct test of whether the
#' halves agree, rather than the eyeball comparison of two intervals —
#' which is the weaker check, since two intervals can overlap while the
#' difference is still distinguishable from zero, and vice versa.
#'
#' Note on what this costs: running it consumes test-B. After this, no
#' held-out race set remains in the paper-4 universe.
#'
#' @param grid_a,grid_b Outputs of `fit_p4_arm_grid()` on the two halves.
#' @param term_role "mod" or "mkt" — which coefficient to compare.
#' @return One row per arm.
compare_halves <- function(grid_a, grid_b, term_role = "mod") {
  pick <- function(g, sample_label) {
    g$coefficients |>
      dplyr::filter(stringr::str_detect(term, term_role)) |>
      dplyr::select(arm, model_source, price_source,
                    estimate, std_error, conf_low, conf_high, z) |>
      dplyr::rename_with(\(nm) paste0(nm, "_", sample_label),
                         c(estimate, std_error, conf_low, conf_high, z))
  }

  dplyr::inner_join(pick(grid_a, "A"), pick(grid_b, "B"),
                    by = c("arm", "model_source", "price_source")) |>
    dplyr::mutate(
      difference = estimate_A - estimate_B,
      se_diff    = sqrt(std_error_A^2 + std_error_B^2),
      z_diff     = difference / se_diff,
      p_diff     = 2 * stats::pnorm(-abs(z_diff)),
      halves_agree = p_diff >= 0.05
    )
}

#' The arm A to arm C gap, read as an errors-in-variables bracket
#'
#' Standalone `b_mkt(A)` below 1 says the pre-race feed price is
#' over-dispersed — measured with noise — which attenuates the market
#' term and leaves `b_mod` on arm A carrying signal that belongs to the
#' market. Arm C prices the same races with a less noisy column, so the
#' A-to-C gap in `b_mod` measures how much of arm A's model coefficient
#' is that attenuation.
#'
#' The gap is an *upper* bound on the attenuation rather than a point
#' estimate of it, because arm C differs from arm A in two ways at once:
#' it is less noisy, and (per amendment 2) it genuinely knows more. Both
#' push `b_mod(C)` down. So the value a clean, well-measured *morning*
#' price would give sits between the two, and the honest object is the
#' bracket, not either endpoint.
#'
#' @param grid A `fit_p4_arm_grid()` output.
#' @return One row per model source.
attenuation_bracket <- function(grid) {
  b <- grid$coefficients |>
    dplyr::filter(stringr::str_detect(term, "mod")) |>
    dplyr::select(arm, sample, model_source, estimate, std_error,
                  conf_low, conf_high)

  mkt_a_only <- grid$market_only |>
    dplyr::filter(arm == "A-mktonly") |>
    dplyr::pull(estimate)

  tibble::tibble(
    model_source   = b$model_source[b$arm %in% c("A1", "A2")],
    sample         = b$sample[b$arm %in% c("A1", "A2")],
    b_mod_A        = b$estimate[b$arm %in% c("A1", "A2")],
    b_mod_C        = b$estimate[b$arm %in% c("C1", "C2")],
    b_mod_B        = b$estimate[b$arm %in% c("B1", "B2")]
  ) |>
    dplyr::mutate(
      gap_A_minus_C     = b_mod_A - b_mod_C,
      pct_of_A_that_is_gap = gap_A_minus_C / b_mod_A,
      b_mkt_A_standalone = mkt_a_only
    )
}
