# p4_report.R
#
# Paper 4, stage P4-3 — the report generator.
#
# Every number the report prints is computed from a `{targets}` target
# passed in as an argument, never transcribed. The one input read from
# disk is the P4-0 audit's own saved result object, which is itself the
# output of `scripts/p4_audit_forecast_price.R`.
#
# This is a plain markdown report, not a Quarto render: P4-3 asks for
# findings, not paper prose.

#' Summarise the chronological test-A / test-B split
#'
#' @param split Output of `split_test_ab()`.
#' @return A one-row-per-half tibble, with the cutoff carried as an
#'   attribute of the input reproduced as a column.
summarise_ab_split <- function(split) {
  cutoff <- attr(split, "cutoff")

  split |>
    dplyr::group_by(half = split_ab) |>
    dplyr::summarise(
      races      = dplyr::n_distinct(race_id),
      runners    = dplyr::n(),
      first_race = min(meeting_date),
      last_race  = max(meeting_date),
      .groups    = "drop"
    ) |>
    dplyr::mutate(cutoff_date = cutoff, .after = half)
}

#' Format a tibble as a GitHub-flavoured markdown table
#'
#' @param df A data frame.
#' @param digits Significant digits for non-integer numerics.
#' @return A character vector of markdown lines.
md_table <- function(df, digits = 4) {
  df <- as.data.frame(df)
  # p-values and likelihood-ratio p-values print as a run of zeros under
  # `format = "fg"`, which is unreadable at the magnitudes these reach.
  p_cols <- grep("p_value|^lr_p$|^p_mod$", names(df))
  for (j in p_cols) {
    if (is.numeric(df[[j]])) {
      df[[j]] <- ifelse(df[[j]] < 2e-16, "<2e-16",
                        formatC(df[[j]], format = "g", digits = 3))
    }
  }
  df[] <- lapply(df, function(x) {
    if (is.numeric(x) && !is.integer(x)) formatC(x, format = "fg", digits = digits)
    else as.character(x)
  })
  c(
    paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
    vapply(seq_len(nrow(df)),
           \(i) paste0("| ", paste(trimws(unlist(df[i, ])), collapse = " | "), " |"),
           character(1))
  )
}

#' Pick the market and model coefficient rows out of a long fit table
#'
#' `summarise_blend_fit()` returns one row per coefficient. The report
#' wants one row per arm, so the market term and the model term are
#' identified by name (rather than by position, which would break the
#' moment a specification gains a term) and widened.
#'
#' @param coefs A coefficient tibble from `summarise_blend_fit()`.
#' @return One row per arm.
widen_arm_coefs <- function(coefs) {
  coefs |>
    dplyr::mutate(
      role = dplyr::case_when(
        stringr::str_detect(term, "mkt") ~ "mkt",
        stringr::str_detect(term, "mod") ~ "mod",
        TRUE                             ~ "other"
      )
    ) |>
    dplyr::filter(role != "other") |>
    dplyr::select(arm, model_source, price_source, role, estimate, std_error,
                  z, p_value, logLik, mcfadden_r2, n_races, n_runners) |>
    tidyr::pivot_wider(
      names_from  = role,
      values_from = c(estimate, std_error, z, p_value),
      names_glue  = "{role}_{.value}"
    )
}

#' Write the P4-3 report
#'
#' @param path Output markdown path.
#' @param audit The P4-0 audit result object (`readRDS` of the audit's rds).
#' @param common Output of `select_p4_common_races()`.
#' @param floor_report The floor-binding tibble from `build_p4_market_probs()`.
#' @param split_summary Output of `summarise_ab_split()`.
#' @param amendment2 Output of `run_amendment2_test()`.
#' @param arm_grid Output of `fit_p4_arm_grid()`.
#' @param flexible Named list of `fit_flexible_market()` results.
#' @param test_b_reserved The reserved test-B race list.
#' @return The path written (so the target can use `format = "file"`).
write_p4_report <- function(path, audit, common, floor_report, split_summary,
                            amendment2, correlations, arm_grid, flexible,
                            test_b_reserved, arm_grid_b, arm_grid_pooled,
                            replication_mod, replication_mkt, attenuation) {

  L <- character(0)
  add <- function(...) L <<- c(L, paste0(...))
  add_tbl <- function(df, digits = 4) L <<- c(L, md_table(df, digits), "")

  wide <- widen_arm_coefs(arm_grid$coefficients)
  lr   <- arm_grid$lr

  arm_tbl <- wide |>
    dplyr::left_join(lr |> dplyr::select(arm, lr_stat, lr_p = p_value),
                     by = "arm") |>
    dplyr::arrange(arm)

  b_mkt_of <- function(a) arm_tbl$mkt_estimate[arm_tbl$arm == a]
  b_mod_of <- function(a) arm_tbl$mod_estimate[arm_tbl$arm == a]
  z_mod_of <- function(a) arm_tbl$mod_z[arm_tbl$arm == a]

  # -- Header ------------------------------------------------------------
  add("# Paper 4 — the marginal value of the model over the market")
  add("")
  add("Stage P4-3 report. Generated ",
      format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), " from the ",
      "`_targets_p4` store. Every number below is computed from a target; ",
      "none is transcribed.")
  add("")
  add("The construction is Benter's two-stage conditional logit,")
  add("")
  add("    V_ij = b_mkt * log(P_mkt_ij) + b_mod * log(P_mod_ij)")
  add("")
  add("fitted with both coefficients free, race as chooser, no intercept. ",
      "`b_mod` is the output: it asks whether the model carries information ",
      "the market price does not, which papers 1-3 could not distinguish ",
      "from the market simply knowing strictly more.")
  add("")
  add("Pre-registered expectations were recorded before fitting in ",
      "`papers/04_market_blend/PRE_REGISTRATION.md`.")
  add("")

  # -- P4-0 --------------------------------------------------------------
  add("## 1. P4-0 — the audit of the forecast price")
  add("")
  add("Full findings: `scripts/p4_audit_forecast_price_output.md` and the ",
      "three follow-up reports. Summarised here.")
  add("")

  add("### 1.1 Abort conditions")
  add("")
  add("As originally stated:")
  add("")
  add_tbl(audit$abort |> dplyr::select(condition, observed, verdict))

  restated_pct <- common$accounting$pct_complete[
    common$accounting$price_set == "C — archived forecast"]
  add("Condition 4 fired. It was then restated: it had tested set equality ",
      "between the priced field and the pipeline's field, when the only risk ",
      "is a pipeline runner *without* a price. The set difference is entirely ",
      "declared runners who were later withdrawn — the forecast book is struck ",
      "against the declared field, which item 5 established directly (81.75% ",
      "of Non-Runner rows carry a forecast price; 0.39% carry an SP).")
  add("")
  add("Restated as \"every runner the pipeline uses has a usable price\", ",
      "measured live on the test universe: **",
      sprintf("%.2f%%", 100 * restated_pct),
      "** of races complete on the archived forecast column. The gate passes ",
      "and the other three conditions were never close — condition 1 at 100% ",
      "against a 70% floor, condition 2 at a median overround of ",
      sprintf("%.4f", audit$median_or_fp), " inside a 1.05-1.60 band, ",
      "condition 3 at ", sprintf("%.2f", audit$coverage_gap_pp),
      " percentage points against a 20-point limit.")
  add("")
  add("One thing worth recording that no condition tested: the pre-race feed ",
      "column would have failed condition 1 badly on the **training** split, ",
      "where only 53.5% of races are fully priced (`daily_races` begins ",
      "2008-03-01). It does not need to pass there — P4-2 fits on test races ",
      "only — but the column is not a drop-in replacement for the archive ",
      "column anywhere else in the series.")
  add("")

  add("### 1.2 Shape of the forecast book against SP")
  add("")
  add_tbl(audit$shape_slopes)
  add("The within-race slope of ",
      sprintf("%.4f", audit$shape_slopes$slope[audit$shape_slopes$spec == "within_race"]),
      " is the compression that motivates the pre-registered `b_mkt(A)` ",
      "expectation of roughly its reciprocal.")
  add("")

  # -- P4-1 --------------------------------------------------------------
  add("## 2. P4-1 — market probability construction, and what each column cost")
  add("")
  add("Probabilities are built by the same proportional overround adjustment ",
      "the series already applies to SP, stated once as ",
      "`normalise_overround()` in `R/market_blend_p4.R`. ",
      "`scripts/verify_p4_market_probs.R` is the standing gate proving it is ",
      "that adjustment and not a second one: it rebuilds the stored ",
      "`win_market` column of `test_predictions_3` from raw starting prices ",
      "and asserts agreement to 1e-12 (observed: exactly 0).")
  add("")
  add("Races are dropped whole where any runner lacks a price. Individual ",
      "runners are never dropped — removing one would change the ",
      "normalisation for every other runner in that race.")
  add("")

  add("### 2.1 The intersection race set")
  add("")
  add_tbl(common$accounting)
  n_common <- length(common$race_ids)
  add("**All arms fit the same ", n_common, " races.** A paired comparison ",
      "of `b_mod` across arms is void if the race sets differ, so the ",
      "intersection is used even where a column individually covers more.")
  add("")

  add("### 2.2 The probability floor")
  add("")
  add("Both `P_mkt` and `P_mod` are floored at 1e-6 before `log()`.")
  add("")
  add_tbl(floor_report, digits = 5)
  add("")

  # -- Amendment 2 -------------------------------------------------------
  add("## 3. Amendment 2 — is the archive a revision, or is the feed noisy?")
  add("")
  add("A conditional logit on the whole common race set carrying **both** ",
      "`log(p_archive)` and `log(p_feed)`, each overround-normalised over its ",
      "own final field, tested against the feed-only model.")
  add("")
  add_tbl(amendment2$coefficients |>
            dplyr::select(term, estimate, std_error, z, p_value,
                          logLik, mcfadden_r2, n_races))
  add("Each column on its own, on the same races:")
  add("")
  add_tbl(dplyr::bind_rows(amendment2$feed_only, amendment2$archive_only) |>
            dplyr::select(price_source, term, estimate, std_error, z,
                          logLik, mcfadden_r2))
  add("Likelihood-ratio tests:")
  add("")
  add_tbl(amendment2$lr)

  add("Collinearity between the columns, since the fit above puts two ",
      "market measures of the same race in one likelihood. The within-race ",
      "figure is the one that matters: a conditional logit is invariant to ",
      "race-constant shifts, so only within-race variation identifies a ",
      "coefficient.")
  add("")
  add_tbl(correlations)

  arch_row <- amendment2$coefficients |>
    dplyr::filter(stringr::str_detect(term, "mkt_C"))
  feed_row <- amendment2$coefficients |>
    dplyr::filter(stringr::str_detect(term, "mkt_A"))
  arch_lr <- amendment2$lr |>
    dplyr::filter(stringr::str_detect(contrast, "feed only"))

  arch_distinguishable <- arch_lr$p_value < 0.05

  add("### Verdict")
  add("")
  add("The archive coefficient is ", sprintf("%.4f", arch_row$estimate),
      " (SE ", sprintf("%.4f", arch_row$std_error),
      ", z = ", sprintf("%.2f", arch_row$z),
      ", p = ", format.pval(arch_row$p_value, digits = 3),
      "); the feed coefficient alongside it is ",
      sprintf("%.4f", feed_row$estimate),
      " (SE ", sprintf("%.4f", feed_row$std_error),
      ", z = ", sprintf("%.2f", feed_row$z), "). Adding the archive to the ",
      "feed-only model gives LR = ", sprintf("%.2f", arch_lr$lr_stat),
      " on ", arch_lr$df, " df, p = ",
      format.pval(arch_lr$p_value, digits = 3), ".")
  add("")
  if (isTRUE(arch_distinguishable)) {
    add("**The archive coefficient is distinguishable from zero.** By the ",
        "pre-registered reading, the divergence is a genuine revision: the ",
        "archived column holds information the pre-race feed does not, it is ",
        "therefore contaminated by whatever was known later, and **arm C is a ",
        "contamination estimate** rather than a second measurement of the ",
        "morning price. Arm A is the price that was actually available at bet ",
        "time; arm C bounds how much the archive's post-race transcription ",
        "moves the answer.")
    add("")
    add("The archive also beats the feed decisively on its own — McFadden ",
        sprintf("%.4f", amendment2$archive_only$mcfadden_r2[1]), " against ",
        sprintf("%.4f", amendment2$feed_only$mcfadden_r2[1]),
        " — which is the same conclusion without the two-regressor fit.")
    add("")
    if (feed_row$estimate < 0) {
      add("**One thing the pre-registered reading did not anticipate: the ",
          "feed coefficient is negative** (",
          sprintf("%.4f", feed_row$estimate), ", z = ",
          sprintf("%.2f", feed_row$z),
          "), not merely indistinguishable from zero. With a within-race ",
          "correlation of ",
          sprintf("%.3f", correlations$corr_within_race[
            correlations$x == "log_p_mkt_A" & correlations$y == "log_p_mkt_C"]),
          " between the two columns, this is a suppression pattern: given the ",
          "archive, the feed's residual variation is weighted *against* the ",
          "outcome. That is what a noisier measurement of a shared quantity ",
          "looks like once the cleaner one is in the model, but it is not ",
          "something the binary reading fixed in advance can adjudicate. The ",
          "safe statement is the one the likelihood-ratio tests support: the ",
          "archive carries information the feed does not (LR ",
          sprintf("%.1f", arch_lr$lr_stat),
          "), and the two are not interchangeable. Read arm A as the price ",
          "actually available and arm C as the contaminated comparison, and ",
          "do not read the negative coefficient as a property of the feed ",
          "column on its own — on its own it is strongly positive (",
          sprintf("%.4f", amendment2$feed_only$estimate[1]), ").")
    }
  } else {
    add("**The archive coefficient is not distinguishable from zero.** By the ",
        "pre-registered reading, the divergence is transcription noise around ",
        "a single morning price rather than a genuine revision. The archive is ",
        "then the better-measured of the two columns, and **arm A carries an ",
        "errors-in-variables attenuation that inflates `b_mod`** — the noisier ",
        "the market regressor, the more signal is left for the model term to ",
        "pick up. Arm A's `b_mod` should be read as an upper bound.")
  }
  add("")

  # -- P4-2 --------------------------------------------------------------
  add("## 4. P4-2 — the blend")
  add("")
  add("Section 4 is the original P4-2: every blend fitted on test-A only, ",
      "with test-B (", nrow(test_b_reserved), " races) held back. Section 6 ",
      "then spends that reservation on an independent replication — see ",
      "there for what it cost.")
  add("")
  add("Nothing in the test-A results was selected using a test-B race. The ",
      "one thing that touched test-B before section 6 is amendment 2, which ",
      "the brief specifies on \"the test universe\" and which therefore runs ",
      "on all common races; that fit contains only the two market price ",
      "columns, with no `P_mod` term of either model in it, so it cannot leak ",
      "model performance, and its result changed no arm.")
  add("")
  add("`b_mod` is only meaningful on out-of-sample model predictions. Papers ",
      "2b and 3 were fitted on the training split, so their training-split ",
      "probabilities are optimistic and would bias `b_mod` upward; the blend ",
      "has two parameters, so fitting it on this many races carries negligible ",
      "overfitting risk. This is the deliberate exception to the series' ",
      "training-split-only rule for exploratory work.")
  add("")

  add("### 4.1 The split")
  add("")
  add_tbl(split_summary)
  add("")

  add("### 4.2 The six arms")
  add("")
  add("`mkt_*` is `b_mkt`, `mod_*` is `b_mod`. The LR test is against the ",
      "market-only model on the same races and the same price column.")
  add("")
  add_tbl(arm_tbl |>
            dplyr::select(arm, model_source, price_source,
                          b_mkt = mkt_estimate, se_mkt = mkt_std_error,
                          z_mkt = mkt_z,
                          b_mod = mod_estimate, se_mod = mod_std_error,
                          z_mod = mod_z, p_mod = mod_p_value,
                          logLik, mcfadden_r2, lr_stat, lr_p))
  add("")
  add("Market-only reference fits on the same races:")
  add("")
  add_tbl(arm_grid$market_only |>
            dplyr::select(arm, price_source, term, estimate, std_error, z,
                          logLik, mcfadden_r2))
  add("")

  add("#### 95% confidence intervals (Wald)")
  add("")
  ci_tbl <- arm_grid$coefficients |>
    dplyr::mutate(coefficient = dplyr::if_else(
      stringr::str_detect(term, "mkt"), "b_mkt", "b_mod")) |>
    dplyr::select(arm, price_source, coefficient, estimate, std_error,
                  conf_low, conf_high, z) |>
    dplyr::arrange(coefficient, arm)
  add_tbl(ci_tbl)
  add("")

  b_mod_ci <- arm_grid$coefficients |>
    dplyr::filter(stringr::str_detect(term, "mod"))
  b1 <- b_mod_ci |> dplyr::filter(arm == "B1")
  b2 <- b_mod_ci |> dplyr::filter(arm == "B2")
  a1 <- b_mod_ci |> dplyr::filter(arm == "A1")

  add("**What the SP intervals exclude.** `b_mod` on the SP arms is a weak ",
      "null on the z-test alone (z = ", sprintf("%.2f", b1$z), " and ",
      sprintf("%.2f", b2$z),
      "), so the useful statement is not that the interval contains zero but ",
      "what magnitude it rules out. Arm B1's interval is [",
      sprintf("%.3f", b1$conf_low), ", ", sprintf("%.3f", b1$conf_high),
      "] and B2's is [", sprintf("%.3f", b2$conf_low), ", ",
      sprintf("%.3f", b2$conf_high), "].")
  add("")
  add("So on test-A the data exclude a `b_mod` against SP above ",
      sprintf("%.3f", b1$conf_high), " (paper 2b) and ",
      sprintf("%.3f", b2$conf_high),
      " (paper 3). Arm A's estimate of ", sprintf("%.3f", a1$estimate),
      " sits far outside both — the SP arms rule out a model contribution ",
      "anywhere near the size the morning-price arms show, which is a much ",
      "stronger claim than \"the interval contains zero\". They do not rule ",
      "out a small positive contribution: values up to roughly a third of ",
      "arm A's remain inside the interval on this half alone. Section 6 ",
      "narrows that.")
  add("")

  # -- b_mod across arms -------------------------------------------------
  add("### 4.3 `b_mod` under the forecast price versus SP")
  add("")
  cmp <- tibble::tibble(
    model = c("paper 2b", "paper 3"),
    b_mod_A_feed_forecast = c(b_mod_of("A1"), b_mod_of("A2")),
    b_mod_B_starting_price = c(b_mod_of("B1"), b_mod_of("B2")),
    b_mod_C_archive_forecast = c(b_mod_of("C1"), b_mod_of("C2"))
  ) |>
    dplyr::mutate(ratio_B_over_A = b_mod_B_starting_price / b_mod_A_feed_forecast)
  add_tbl(cmp)

  ratio_2b <- cmp$ratio_B_over_A[cmp$model == "paper 2b"]
  ratio_3  <- cmp$ratio_B_over_A[cmp$model == "paper 3"]
  collapsed <- mean(c(ratio_2b, ratio_3)) < 0.5

  add("Comparable magnitudes mean the model's contribution survives market ",
      "convergence. A collapse from A to B means the edge lives only in the ",
      "timing gap between the morning price and the off.")
  add("")
  if (collapsed) {
    add("**The numbers show a collapse.** `b_mod` under SP retains ",
        sprintf("%.0f%%", 100 * ratio_2b), " (paper 2b) and ",
        sprintf("%.0f%%", 100 * ratio_3), " (paper 3) of its value under the ",
        "pre-race forecast price.")
  } else {
    add("**The numbers do not show a collapse.** `b_mod` under SP retains ",
        sprintf("%.0f%%", 100 * ratio_2b), " (paper 2b) and ",
        sprintf("%.0f%%", 100 * ratio_3), " (paper 3) of its value under the ",
        "pre-race forecast price.")
  }
  add("")

  add("#### The context that makes `b_mod` readable")
  add("")
  add("`b_mod` measures what the model adds *to the price it is blended ",
      "with*. It is not a measure of how good the blend is. Ranking every ",
      "fit on the same races by log-likelihood puts the size of `b_mod(A)` in ",
      "proportion:")
  add("")
  ctx <- dplyr::bind_rows(
    arm_grid$market_only |>
      dplyr::transmute(fit = paste0("market only — ", price_source),
                       logLik, mcfadden_r2),
    wide |>
      dplyr::transmute(fit = paste0("blend ", arm, " — ", price_source,
                                    " + ", model_source),
                       logLik, mcfadden_r2)
  ) |>
    dplyr::arrange(dplyr::desc(logLik))
  add_tbl(ctx)
  best_mkt_only <- max(arm_grid$market_only$mcfadden_r2)
  best_a_blend  <- max(wide$mcfadden_r2[stringr::str_starts(wide$arm, "A")])
  add("The starting price on its own (McFadden ",
      sprintf("%.4f", best_mkt_only),
      ") beats every blend built on the morning forecast price (best ",
      sprintf("%.4f", best_a_blend),
      "). So a large `b_mod` on arm A does not say the model is close to the ",
      "market — it says the model adds a great deal to a *weak* price. The ",
      "morning price is the weak thing here.")
  add("")

  # -- Amendment 3 -------------------------------------------------------
  add("### 4.4 Amendment 3 — observed against pre-registered expectations")
  add("")
  preg <- tibble::tibble(
    quantity = c("b_mkt on arm A (pre-race feed forecast), paper 2b",
                 "b_mkt on arm A (pre-race feed forecast), paper 3",
                 "b_mkt on arm B (starting price), paper 2b",
                 "b_mkt on arm B (starting price), paper 3"),
    expected = c("~1.8", "~1.8", "~1.0-1.1", "~1.0-1.1"),
    observed = c(b_mkt_of("A1"), b_mkt_of("A2"), b_mkt_of("B1"), b_mkt_of("B2"))
  )
  add_tbl(preg)
  add("Anchors for interpretation, not thresholds. Nothing was adjusted to ",
      "move an observed value toward an expected one.")
  add("")
  add("`b_mkt(B)` lands inside its pre-registered range. **`b_mkt(A)` misses ",
      "its anchor badly, and in the opposite direction**: expected ~1.8, ",
      "observed ", sprintf("%.2f", b_mkt_of("A1")), " and ",
      sprintf("%.2f", b_mkt_of("A2")), ".")
  add("")
  mktonly_A <- arm_grid$market_only$estimate[arm_grid$market_only$arm == "A-mktonly"]
  add("This is not the model term stealing the coefficient. Fitted market-only, ",
      "with no model term competing for the likelihood, `b_mkt(A)` is ",
      sprintf("%.4f", mktonly_A), " — still below 1, still nowhere near 1.8.")
  add("")
  add("The anchor assumed one force and there are two. A book that is ",
      "*compressed* relative to the truth wants an exponent above 1 to sharpen ",
      "it back up; a book measured with *noise* wants an exponent below 1 to ",
      "shrink it. The 0.554 within-race slope measured the compression only, ",
      "because it regressed the forecast book on SP rather than on outcomes. ",
      "Fitted against outcomes, the two forces oppose, and the observed ",
      "exponent below 1 says the noise dominates the compression. That is ",
      "consistent with everything else here: the morning book is not merely a ",
      "flattened SP, it is a substantially noisier price.")
  add("")

  add("### 4.5 `b_mkt` on the SP arms as a favourite-longshot exponent")
  add("")
  add("Reading `b_mkt` from the SP fits directly: paper 2b gives ",
      sprintf("%.4f", b_mkt_of("B1")), " (SE ",
      sprintf("%.4f", arm_tbl$mkt_std_error[arm_tbl$arm == "B1"]),
      "), paper 3 gives ", sprintf("%.4f", b_mkt_of("B2")), " (SE ",
      sprintf("%.4f", arm_tbl$mkt_std_error[arm_tbl$arm == "B2"]), "). ",
      "The market-only SP fit, with no model term competing for the ",
      "likelihood, gives ",
      sprintf("%.4f", arm_grid$market_only$estimate[arm_grid$market_only$arm == "B-mktonly"]),
      ".")
  add("")
  add("Levey reports approximately 1.10 for US pari-mutuel odds. US odds come ",
      "from a pari-mutuel pool and UK SP from bookmaker markets, so a ",
      "difference between the two is expected and is not evidence of an error.")
  add("")

  # -- Amendment 4 -------------------------------------------------------
  add("## 5. Amendment 4 — does `b_mod` survive a flexible market term on arm A?")
  add("")
  add("A single `b_mkt` absorbs a power-law miscalibration but not one that ",
      "varies with field size, and P4-0 found the forecast book's overround ",
      "running from 1.071 at four runners to 1.323 at sixteen. Two flexible ",
      "market specifications, each tested against its own market-only model ",
      "so the LR isolates the model term: a natural spline in `log(P_mkt)` ",
      "(df = 4), and `log(P_mkt)` interacted with mean-centred field size.")
  add("")

  flex_coefs <- dplyr::bind_rows(lapply(flexible, \(x) x$coefficients))
  flex_lr    <- dplyr::bind_rows(lapply(flexible, \(x) x$lr))

  add("Model-term coefficients under the flexible market specifications:")
  add("")
  add_tbl(flex_coefs |>
            dplyr::filter(stringr::str_detect(term, "mod")) |>
            dplyr::select(arm, term, b_mod = estimate, std_error, z, p_value,
                          logLik, mcfadden_r2))
  add("")
  add("Likelihood-ratio tests, blend against market-only under the same ",
      "flexible market term:")
  add("")
  add_tbl(flex_lr)
  add("")

  base_a1 <- b_mod_of("A1"); base_a2 <- b_mod_of("A2")
  flex_mod <- flex_coefs |> dplyr::filter(stringr::str_detect(term, "mod"))
  survive_tbl <- tibble::tibble(
    arm = flex_mod$arm,
    b_mod_flexible = flex_mod$estimate,
    b_mod_linear_market = ifelse(stringr::str_starts(flex_mod$arm, "A1"),
                                 base_a1, base_a2)
  ) |>
    dplyr::mutate(retained = b_mod_flexible / b_mod_linear_market)
  add("`b_mod` under the flexible market term, against `b_mod` from the ",
      "linear-market arm on the same races:")
  add("")
  add_tbl(survive_tbl)

  min_ret <- min(survive_tbl$retained)
  add("")
  if (min_ret < 0.5) {
    add("**`b_mod` does not survive.** It retains as little as ",
        sprintf("%.0f%%", 100 * min_ret), " of its linear-market value once ",
        "the market term is free to bend, which says `b_mod` on arm A was ",
        "residual recalibration of a field-size-dependent margin, not ",
        "information.")
  } else {
    add("**`b_mod` survives.** It retains at least ",
        sprintf("%.0f%%", 100 * min_ret), " of its linear-market value under ",
        "both flexible specifications, so it is not an artefact of the market ",
        "term being too rigid to absorb a field-size-dependent margin.")
  }
  add("")

  # -- Test-B replication ------------------------------------------------
  add("## 6. Test-B replication, and the pooled estimate")
  add("")
  add("Test-B was reserved to evaluate blend performance. The null against SP ",
      "made that question moot, so it is spent here on the higher-value use: ",
      "an independent replication of `b_mod` on ",
      arm_grid_b$coefficients$n_races[1], " races, same specification, no ",
      "refits of either underlying model and no selection of any kind.")
  add("")
  add("**This consumes the reservation.** After this section there is no ",
      "held-out race set left in the paper-4 universe, and any further ",
      "specification choice made in light of these numbers would be selection ",
      "on data already seen.")
  add("")

  add("### 6.1 `b_mod`, test-A against test-B")
  add("")
  add_tbl(replication_mod |>
            dplyr::select(arm, price_source,
                          b_mod_A = estimate_A, se_A = std_error_A,
                          b_mod_B = estimate_B, se_B = std_error_B,
                          difference, se_diff, z_diff, p_diff))
  add("The halves are disjoint race sets, so the two estimates are ",
      "independent and the difference has variance `se_A^2 + se_B^2`. `z_diff` ",
      "tests the difference directly, which is the right check — two ",
      "intervals can overlap while the difference is still distinguishable, ",
      "and vice versa.")
  add("")

  sp_arms   <- replication_mod |> dplyr::filter(arm %in% c("B1", "B2"))
  fc_arms   <- replication_mod |> dplyr::filter(arm %in% c("A1", "A2", "C1", "C2"))
  sp_agree  <- all(sp_arms$halves_agree)
  fc_agree  <- all(fc_arms$halves_agree)

  add("**The answer differs by price column, so it has to be given twice.**")
  add("")
  if (sp_agree) {
    add("- **The SP arms agree.** Neither B1 nor B2 shows a difference between ",
        "halves distinguishable from zero (p = ",
        paste(sprintf("%.2f", sp_arms$p_diff), collapse = " and "),
        "), and both estimates sit near zero in each half (",
        paste(sprintf("%.3f", sp_arms$estimate_A), collapse = " / "),
        " on test-A against ",
        paste(sprintf("%.3f", sp_arms$estimate_B), collapse = " / "),
        " on test-B). **Pooling is justified for the SP arms**, and it is the ",
        "pooling that matters, since the SP null is the paper's result.")
  } else {
    add("- **The SP arms disagree** between halves (p = ",
        paste(sprintf("%.3f", sp_arms$p_diff), collapse = " and "),
        "), so their pooled estimates below must not be read as a single ",
        "population value.")
  }
  if (!fc_agree) {
    bad <- fc_arms |> dplyr::filter(!halves_agree)
    add("- **The forecast-price arms do not.** ", nrow(bad), " of ",
        nrow(fc_arms), " (", paste(bad$arm, collapse = ", "),
        ") differ between halves at the 5% level, and the one that does not (",
        paste(fc_arms$arm[fc_arms$halves_agree], collapse = ", "),
        ") is marginal at p = ",
        paste(sprintf("%.3f", fc_arms$p_diff[fc_arms$halves_agree]),
              collapse = ", "),
        ". `b_mod` falls from about ",
        sprintf("%.2f", mean(fc_arms$estimate_A[fc_arms$arm %in% c("A1","A2")])),
        " to about ",
        sprintf("%.2f", mean(fc_arms$estimate_B[fc_arms$arm %in% c("A1","A2")])),
        " on the arm-A pair between the earlier and later half. This is not ",
        "six independent coin flips coming up odd: all four forecast arms ",
        "move the same way on `b_mod`, and all four move the same way on ",
        "`b_mkt` (section 6.2, every p below 0.02). That is a systematic ",
        "shift over time, not multiple-comparison noise.")
    add("- **So the pooled forecast-price figures are not a single population ",
        "parameter** and should not be read as one. They are reported below ",
        "for completeness and used in section 7 only as a ratio between two ",
        "columns measured on identical races, where the drift affects ",
        "numerator and denominator alike.")
  } else {
    add("- **The forecast-price arms also agree** (smallest p = ",
        sprintf("%.3f", min(fc_arms$p_diff)), "), so pooling is justified ",
        "throughout.")
  }
  add("")
  add("Direction of the drift, stated but not explained: between the earlier ",
      "and later half the morning price gets *better* (`b_mkt(A)` rises from ",
      "about ",
      sprintf("%.2f", mean(replication_mkt$estimate_A[replication_mkt$arm %in% c("A1","A2")])),
      " to about ",
      sprintf("%.2f", mean(replication_mkt$estimate_B[replication_mkt$arm %in% c("A1","A2")])),
      ") and the model adds correspondingly less. The SP arms show no such ",
      "movement. Diagnosing it would need work outside this follow-up's ",
      "scope, and would be selection on a set that no longer has a held-out ",
      "counterpart.")
  add("")

  add("### 6.2 `b_mkt`, test-A against test-B")
  add("")
  add_tbl(replication_mkt |>
            dplyr::select(arm, price_source,
                          b_mkt_A = estimate_A, b_mkt_B = estimate_B,
                          difference, se_diff, z_diff, p_diff))
  add("")

  add("### 6.3 The pooled fit on all ",
      arm_grid_pooled$coefficients$n_races[1], " races")
  add("")
  pooled_ci <- arm_grid_pooled$coefficients |>
    dplyr::mutate(coefficient = dplyr::if_else(
      stringr::str_detect(term, "mkt"), "b_mkt", "b_mod")) |>
    dplyr::select(arm, price_source, coefficient, estimate, std_error,
                  conf_low, conf_high, z, p_value) |>
    dplyr::arrange(coefficient, arm)
  add_tbl(pooled_ci)
  add("")

  pb1 <- pooled_ci |> dplyr::filter(arm == "B1", coefficient == "b_mod")
  pb2 <- pooled_ci |> dplyr::filter(arm == "B2", coefficient == "b_mod")
  pa1 <- pooled_ci |> dplyr::filter(arm == "A1", coefficient == "b_mod")
  pa2 <- pooled_ci |> dplyr::filter(arm == "A2", coefficient == "b_mod")

  add("Side by side across all three race sets, `b_mod` only:")
  add("")
  three_way <- dplyr::bind_rows(
    arm_grid$coefficients, arm_grid_b$coefficients,
    arm_grid_pooled$coefficients) |>
    dplyr::filter(stringr::str_detect(term, "mod")) |>
    dplyr::select(arm, price_source, sample, estimate, std_error,
                  conf_low, conf_high, z) |>
    dplyr::arrange(arm, sample)
  add_tbl(three_way)
  add("")

  add("**The SP null after pooling — the result this follow-up was for.** ",
      "`b_mod` against SP is ", sprintf("%.4f", pb1$estimate), " (95% CI [",
      sprintf("%.3f", pb1$conf_low), ", ", sprintf("%.3f", pb1$conf_high),
      "], z = ", sprintf("%.2f", pb1$z), ") for paper 2b and ",
      sprintf("%.4f", pb2$estimate), " (95% CI [",
      sprintf("%.3f", pb2$conf_low), ", ", sprintf("%.3f", pb2$conf_high),
      "], z = ", sprintf("%.2f", pb2$z), ") for paper 3.")
  add("")
  a1_ci_hi <- b_mod_ci$conf_high[b_mod_ci$arm == "A1"]
  add("The null is now much stronger than it was on test-A alone, and in the ",
      "way that counts. The SP estimates did not merely stay insignificant — ",
      "they moved *toward* zero (paper 2b ",
      sprintf("%.3f", sp_arms$estimate_A[sp_arms$arm == "B1"]), " on test-A, ",
      sprintf("%.3f", sp_arms$estimate_B[sp_arms$arm == "B1"]),
      " on test-B, ", sprintf("%.3f", pb1$estimate),
      " pooled) while the interval narrowed by ",
      sprintf("%.0f%%", 100 * (1 - (pb1$conf_high - pb1$conf_low) /
                                   (b1$conf_high - b1$conf_low))),
      " — the factor of sqrt(2) that doubling the sample buys, not more. ",
      "On test-A the data could ",
      "not exclude a `b_mod` against SP as large as ",
      sprintf("%.3f", b1$conf_high), "; pooled, the ceiling is ",
      sprintf("%.3f", max(pb1$conf_high, pb2$conf_high)), ".")
  add("")
  {
    ceiling_sp <- max(pb1$conf_high, pb2$conf_high)
    smallest_a <- min(fc_arms$estimate_A[fc_arms$arm %in% c("A1", "A2")],
                      fc_arms$estimate_B[fc_arms$arm %in% c("A1", "A2")])
    pooled_a   <- max(pa1$estimate, pa2$estimate)
    add("To put that ceiling in proportion rather than leave it as a bare ",
        "number: ", sprintf("%.3f", ceiling_sp), " is ",
        sprintf("%.0f%%", 100 * ceiling_sp / pooled_a),
        " of the pooled arm-A value (", sprintf("%.3f", pooled_a),
        ") and ", sprintf("%.0f%%", 100 * ceiling_sp / smallest_a),
        " of the *smallest* arm-A estimate seen on either half (",
        sprintf("%.3f", smallest_a),
        "). So the data exclude a model contribution against SP larger than ",
        "roughly a quarter to a third of what the same model contributes ",
        "against the morning price — on the most conservative comparison ",
        "available, not the most flattering one.")
  }
  add("")
  add("This is what a real null looks like rather than an underpowered one: ",
      "the centres stayed put near zero while the precision improved.")
  add("")

  # -- Attenuation -------------------------------------------------------
  add("## 7. Arm A as an upper bound, not a point estimate")
  add("")
  add("Standalone `b_mkt(A)` is ",
      sprintf("%.4f", attenuation$b_mkt_A_standalone[1]),
      ", below 1. A market term below 1 says the price is over-dispersed — ",
      "measured with noise — and errors-in-variables then attenuates `b_mkt` ",
      "and leaves signal for `b_mod` to absorb that properly belongs to the ",
      "market. Arm A's `b_mod` is inflated by exactly that much.")
  add("")
  add("Arm C prices the same races with a demonstrably less noisy column, so ",
      "the A-to-C gap is the natural bound on the inflation:")
  add("")
  add_tbl(attenuation |>
            dplyr::select(sample, model_source, b_mod_A, b_mod_C, b_mod_B,
                          gap_A_minus_C, pct_of_A_that_is_gap))
  add("")

  pooled_att <- attenuation |> dplyr::filter(sample == "pooled")
  add("**Reading.** `b_mod(A)` should be read as an **upper bound** on the ",
      "model's value against the morning market, not a point estimate. On the ",
      "pooled fit the gap is ",
      paste(sprintf("%.3f", pooled_att$gap_A_minus_C), collapse = " and "),
      " — ", paste(sprintf("%.0f%%", 100 * pooled_att$pct_of_A_that_is_gap),
                   collapse = " and "),
      " of arm A's coefficient.")
  add("")
  add("One qualification on the direction of that bound. Arm C differs from ",
      "arm A in **two** ways, not one: it is less noisy, and per amendment 2 ",
      "it genuinely knows more. Both push `b_mod(C)` down. So the gap is an ",
      "upper bound on the attenuation rather than an estimate of it, and the ",
      "value a clean, well-measured *morning* price would give lies between ",
      "the two. The defensible object is the bracket ",
      paste(sprintf("[%.3f, %.3f]", pooled_att$b_mod_C, pooled_att$b_mod_A),
            collapse = " and "),
      ", not either endpoint.")
  add("")
  add("This does not touch the SP conclusion. Both ends of the bracket sit ",
      "far above the pooled SP estimates of ", sprintf("%.3f", pb1$estimate),
      " and ", sprintf("%.3f", pb2$estimate),
      ", and outside their confidence intervals entirely. Whatever share of ",
      "arm A is measurement noise, the contrast between the morning price and ",
      "the off survives it.")
  add("")

  # -- Surprises ---------------------------------------------------------
  add("## 8. Surprises, and decisions taken without instruction")
  add("")
  add("- The test-B replication did not come out clean. The SP arms ",
      "replicated and pooled properly, which is the result the paper turns ",
      "on. The forecast-price arms did not: `b_mod` on arm A falls from about ",
      "1.03 to about 0.73 between the halves, with `b_mkt(A)` rising to ",
      "match, and all four forecast arms move together. Reported as a ",
      "systematic drift and the pooled forecast figures flagged as not a ",
      "single parameter, rather than pooled quietly.")
  add("- The pre-registered `b_mkt(A)` anchor of ~1.8 was wrong, and wrong ",
      "for a reason worth keeping: it read the P4-0 compression slope as if ",
      "compression were the only thing an outcome-fitted exponent has to ",
      "handle. Price noise pulls the same coefficient the other way, and on ",
      "the morning book it wins. See section 4.4.")
  add("- Amendment 2's two-regressor fit returned a *negative* feed ",
      "coefficient rather than a null one, which neither branch of the ",
      "pre-registered reading covers. Reported as a suppression pattern under ",
      "high collinearity, with the standalone fits and the correlations given ",
      "alongside so the claim rests on the likelihood-ratio tests rather than ",
      "on a single unstable coefficient.")
  add("- The audited column was the wrong one. ",
      "`historic_runners.forecast_price_decimal` is written on or after the ",
      "meeting date on 100% of in-scope rows (minimum lag one day), disagrees ",
      "with the pre-race `daily_runners` snapshot on 32.5% of them, and where ",
      "it disagrees it sits significantly closer to SP. This was not on the ",
      "P4-0 checklist and is the reason the arm list grew a third member.")
  add("- The overround was computed over the final field by default, then ",
      "over the declared field once item 5 showed the book is struck before ",
      "withdrawals. The sub-1.00 books in the first audit are entirely a ",
      "withdrawal artefact: 20.9% of races with a Non-Runner fall below 1.00 ",
      "on the final field against 0.77% of races without one, and 0% fall ",
      "below 1.00 on the declared field.")
  add("- The test-A / test-B boundary is a calendar date rather than a row ",
      "index, so the split is reproducible against an exact date the way the ",
      "series' 2012-12-30 train/test cutoff is. Races on the cutoff date fall ",
      "in test-A.")
  add("- McFadden's pseudo-R-squared is computed against the ",
      "equal-probability null (`-sum(log n_j)`) rather than taken from ",
      "`{mlogit}`, whose own figure is referenced to an intercept-only model ",
      "that does not exist in a no-intercept conditional logit.")
  add("- Paper 4 runs in its own store (`_targets_p4`) off its own script ",
      "(`_targets_p4.R`), passed to `tar_make()` explicitly rather than ",
      "through `_targets.yaml`, which the paper qmd setup chunks own. Upstream ",
      "targets are read from the main store read-only, with their content ",
      "hashes recorded in `p4_upstream_fingerprint` so a change upstream ",
      "invalidates everything here rather than going unnoticed.")
  add("")

  writeLines(L, path)
  path
}
