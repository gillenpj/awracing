# scripts/verify_pl_objective.R
# Read-only verification gate for R/pl_objective.R (paper 3's custom
# Plackett-Luce objective for {xgboost}). stopifnot() throughout; the
# script halts on the first failing assertion and should be reported back
# rather than worked around.
#
# Run with:
#   "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" scripts/verify_pl_objective.R
# from the project root (relative paths below assume that cwd).

source("renv/activate.R")

suppressPackageStartupMessages({
  library(targets)
  library(dplyr)
})
loadNamespace("mlogit")
source("R/pl_objective.R")

set.seed(20260819)

# ---------------------------------------------------------------------------
# Synthetic race generator shared by assertions (1)-(4): 20 races, including
# an explicit 4-runner race, a 16-runner race, and a single-runner race
# (J = 1 satisfies J <= k for both k = 1 and k = 3 tested below), plus 17
# further races with random field sizes 2-4 (kept small so numDeriv::hessian()
# in (4), which is O(n^2) in total row count, finishes in reasonable time).
# ---------------------------------------------------------------------------
sizes <- c(4L, 16L, 1L, sample(2:4, 17L, replace = TRUE))
stopifnot(length(sizes) == 20L)
n_rows <- sum(sizes)
z0 <- rnorm(n_rows, sd = 1.5)

cat("Synthetic dataset: ", length(sizes), " races, ", n_rows, " rows, field sizes ",
    paste(sizes, collapse = ","), "\n\n", sep = "")

# ---------------------------------------------------------------------------
# (1) Translation invariance: adding a constant to every z WITHIN A RACE
#     leaves the loss and gradient unchanged. k = 1 and k = 3.
# ---------------------------------------------------------------------------
cat("---- (1) Translation invariance ----\n")
race_idx <- rep.int(seq_along(sizes), sizes)
shift    <- rnorm(length(sizes), sd = 5)   # one constant per race
z_shift  <- z0 + shift[race_idx]           # same shift applied within each race

for (k in c(1L, 3L)) {
  loss0 <- pl_neg_loglik(z0,      sizes, k)
  loss1 <- pl_neg_loglik(z_shift, sizes, k)
  gh0   <- pl_grad_hess(z0,      sizes, k)
  gh1   <- pl_grad_hess(z_shift, sizes, k)

  cat("k =", k, ": loss0 =", loss0, " loss(shifted) =", loss1,
      " |diff| =", abs(loss0 - loss1), "\n")
  stopifnot(abs(loss0 - loss1) < 1e-8)
  stopifnot(max(abs(gh0$grad - gh1$grad)) < 1e-8)
}
cat("OK: loss and gradient invariant to within-race constant shifts\n\n")

# ---------------------------------------------------------------------------
# (2) Gradient sums to zero within each race, every k.
# ---------------------------------------------------------------------------
cat("---- (2) Gradient sums to zero within each race ----\n")
for (k in c(1L, 3L)) {
  core      <- pl_core(z0, sizes, k)
  race_sums <- tapply(core$grad, core$race, sum)
  cat("k =", k, ": max |race gradient sum| =", max(abs(race_sums)), "\n")
  stopifnot(max(abs(race_sums)) < 1e-8)
}
cat("OK: gradient sums to zero within every race\n\n")

# ---------------------------------------------------------------------------
# (3) Analytic gradient vs numDeriv::grad(), same 20 synthetic races,
#     k = 1 and k = 3, tolerance 1e-6.
# (4) Analytic Hessian DIAGONAL vs diag(numDeriv::hessian()), same setup.
# ---------------------------------------------------------------------------
cat("---- (3) Analytic gradient vs numDeriv::grad() ----\n")
cat("---- (4) Analytic Hessian diagonal vs numDeriv::hessian() ----\n")
for (k in c(1L, 3L)) {
  gh <- pl_grad_hess(z0, sizes, k)

  num_grad  <- numDeriv::grad(function(zz) pl_neg_loglik(zz, sizes, k), z0)
  grad_diff <- max(abs(gh$grad - num_grad))
  cat("k =", k, ": max |analytic grad - numDeriv grad|           =", grad_diff, "\n")
  stopifnot(grad_diff < 1e-6)

  num_hess_diag <- diag(numDeriv::hessian(function(zz) pl_neg_loglik(zz, sizes, k), z0))
  hess_diff     <- max(abs(gh$hess - num_hess_diag))
  cat("k =", k, ": max |analytic hess diag - numDeriv hess diag| =", hess_diff, "\n")
  stopifnot(hess_diff < 1e-6)
}
cat("OK: analytic gradient and Hessian diagonal match numDeriv\n\n")

# ---------------------------------------------------------------------------
# Shared helper for (5)/(6): reconstruct the full-field z vector + group
# sizes for a fitted mlogit model from its {mlogit} long-form training data,
# via arrange_for_xgb() -- the same production sort every real caller uses.
# ---------------------------------------------------------------------------
prep_full_field <- function(mlogit_data, coefs, extra_filter = NULL) {
  df <- as.data.frame(mlogit_data)
  class(df) <- "data.frame"
  attr(df, "index")    <- NULL
  attr(df, "clseries") <- NULL
  if (!is.null(extra_filter)) df <- extra_filter(df)

  terms <- names(coefs)
  stopifnot(all(terms %in% names(df)))
  stopifnot(all(c("race_id", "won") %in% names(df)))

  X       <- as.matrix(df[, terms, drop = FALSE])
  df$z    <- as.vector(X %*% coefs)
  # runner_id is the project's population-wide horse identifier and should
  # pass through as an ordinary column; fall back to horse_ref (the per-race
  # alt.var, guaranteed present) if it doesn't -- tie-breaking among rows
  # that are neither the k=1..S finishers doesn't affect the loss either way.
  df$runner_id <- if ("runner_id" %in% names(df)) df$runner_id else df$horse_ref
  if (!"finish_pos" %in% names(df)) {
    df$finish_pos <- ifelse(df$won == 1L, 1L, NA_integer_)
  }

  ordered      <- arrange_for_xgb(df)
  group_sizes  <- rle(as.character(ordered$race_id))$lengths
  stopifnot(length(ordered$z) == sum(group_sizes))
  list(z = ordered$z, group_sizes = group_sizes)
}

# ---------------------------------------------------------------------------
# (5) LOAD-BEARING: paper 2a final win model (model_w_final), k = 1, must
#     match its own mlogit logLik to 1e-6. If this fails the objective is
#     wrong -- stop here, do not proceed to (6)/(7).
# ---------------------------------------------------------------------------
cat("---- (5) LOAD-BEARING: paper 2a model_w_final vs pl_neg_loglik(k=1) ----\n")

model_w_final <- targets::tar_read(model_w_final)
mlogit_train_data_interactions <- targets::tar_read(mlogit_train_data_interactions)

prep5 <- prep_full_field(mlogit_train_data_interactions, stats::coef(model_w_final))

ll_pl5     <- -pl_neg_loglik(prep5$z, prep5$group_sizes, k = 1L)
ll_mlogit5 <- as.numeric(stats::logLik(model_w_final))
diff5      <- abs(ll_pl5 - ll_mlogit5)

cat("pl_neg_loglik-implied logLik (k=1): ", ll_pl5, "\n", sep = "")
cat("logLik(model_w_final):              ", ll_mlogit5, "\n", sep = "")
cat("|difference|:                       ", diff5, "\n\n", sep = "")
stopifnot(diff5 < 1e-6)
cat("OK: matches to 1e-6\n\n")

# ---------------------------------------------------------------------------
# (6) Paper 2b exploded model (model_2b_exploded_draw_final), k = 3, vs its
#     own mlogit logLik. Reconstructed from the depth == 1 subset of
#     exploded_interactions_data: depth 1's candidate pool is the full
#     original race field for every surviving race (finish_pos >= 1 is true
#     for every placed horse, and unplaced horses have NA finish_pos, so
#     `finish_pos >= s | is.na(finish_pos)` at s = 1 keeps everyone).
# ---------------------------------------------------------------------------
cat("---- (6) paper 2b model_2b_exploded_draw_final vs pl_neg_loglik(k=3) ----\n")

model_2b_exploded_draw_final <- targets::tar_read(model_2b_exploded_draw_final)
exploded_interactions_data   <- targets::tar_read(exploded_interactions_data)

prep6 <- prep_full_field(
  exploded_interactions_data,
  stats::coef(model_2b_exploded_draw_final),
  extra_filter = function(df) {
    stopifnot("depth" %in% names(df))
    dplyr::filter(df, depth == 1)
  }
)

ll_pl6     <- -pl_neg_loglik(prep6$z, prep6$group_sizes, k = 3L)
ll_mlogit6 <- as.numeric(stats::logLik(model_2b_exploded_draw_final))
diff6      <- abs(ll_pl6 - ll_mlogit6)

cat("pl_neg_loglik-implied logLik (k=3):        ", ll_pl6, "\n", sep = "")
cat("logLik(model_2b_exploded_draw_final):      ", ll_mlogit6, "\n", sep = "")
cat("|difference|:                              ", diff6, "\n\n", sep = "")

if (diff6 >= 1e-6) {
  cat(
    "DISCREPANCY at k = 3: the reconstructed full-field data does not ",
    "reproduce model_2b_exploded_draw_final's own pooled-exploded logLik to ",
    "1e-6. Reporting this explicitly per the verification-gate instructions ",
    "rather than loosening the tolerance -- |difference| = ", diff6, "\n",
    sep = ""
  )
}
stopifnot(diff6 < 1e-6)
cat("OK: matches to 1e-6\n\n")

# ---------------------------------------------------------------------------
# (7) pl_r2 returns exactly 0 when all scores within every race are equal.
# ---------------------------------------------------------------------------
cat("---- (7) pl_r2 == 0 when all within-race scores are equal ----\n")
z_flat <- rep(rnorm(length(sizes)), sizes)   # one constant score per race
for (k in c(1L, 3L)) {
  eval_fn <- make_pl_eval(sizes, k)
  result  <- eval_fn(z_flat, dtrain = NULL)
  cat("k =", k, ": metric =", result$metric, " value =", result$value, "\n")
  stopifnot(identical(result$metric, "pl_r2"))
  stopifnot(abs(result$value) < 1e-9)
}
cat("OK: pl_r2 is 0 for flat scores\n\n")

# ---------------------------------------------------------------------------
# (8) NEW: equivalence between the vectorised pl_core() and the retained
#     dplyr-based pl_core_reference() -- 200 random synthetic races of
#     varying field size, including a 4-runner, a 16-runner, and one with
#     J <= k, at k = 1 and k = 3, tolerance 1e-10.
# ---------------------------------------------------------------------------
cat("---- (8) NEW: pl_core() vs pl_core_reference() equivalence, 200 races ----\n")
sizes8 <- c(4L, 16L, 1L, sample(2:12, 197L, replace = TRUE))
stopifnot(length(sizes8) == 200L)
z8 <- rnorm(sum(sizes8), sd = 1.5)
cat("200-race dataset: ", sum(sizes8), " rows, field sizes range ",
    min(sizes8), "-", max(sizes8), "\n", sep = "")

for (k in c(1L, 3L)) {
  old8 <- pl_core_reference(z8, sizes8, k)
  new8 <- pl_core(z8, sizes8, k)
  d_grad  <- max(abs(old8$grad - new8$grad))
  d_hess  <- max(abs(old8$hess - new8$hess))
  d_stage <- max(abs(old8$stage_term - new8$stage_term))
  cat("k =", k, ": max |grad diff| =", d_grad, " max |hess diff| =", d_hess,
      " max |stage_term diff| =", d_stage, "\n")
  stopifnot(d_grad < 1e-10, d_hess < 1e-10, d_stage < 1e-10)
}
cat("OK: vectorised pl_core() matches the dplyr reference to 1e-10\n\n")

# ---------------------------------------------------------------------------
# (9) NEW (2026-08-21): the gate's blind spot, closed. Incident: because
#     R/pl_objective.R is source()d rather than loaded as a package, an
#     unqualified log() call inside it resolves lexically to whatever
#     environment sourced it. scripts/run_gbt_tuning.R defined its own
#     top-level `log <- function(...) {...}` console-logging helper, which
#     silently shadowed base::log() for the rest of that R session --
#     pl_neg_loglik(), pl_core(), and make_pl_eval()'s logl_null
#     computation all called unqualified log(), so every one of those
#     calls invoked the LOGGING helper instead of the logarithm: it
#     printed its numeric argument (explaining a since-diagnosed stray
#     stdout blob) and returned NULL. `zc - log(denom)` became
#     `zc - NULL` -> `numeric(0)`, and `ifelse(cond, numeric(0), 0)`
#     recycled the empty vector into NA for every scored row -- silently
#     sentinelling every single grid point in a real tuning run to
#     -1e10, config-independent, for hours, with this gate passing
#     throughout. It passed throughout because THIS SCRIPT never defines
#     its own log(), so it was structurally incapable of catching this
#     bug class. The fix (base::log() qualification in R/pl_objective.R)
#     is necessary but not sufficient on its own -- nothing previously
#     stopped a FUTURE driver script from reintroducing the same shadow
#     and this gate staying silent again. This assertion reproduces the
#     exact shadow and asserts the fix survives it, so that scenario is
#     now covered. See CLAUDE.md's paper-3 divergence-guard note for the
#     full incident writeup.
# ---------------------------------------------------------------------------
cat("---- (9) NEW: base::log() qualification survives a shadowing log() ----\n")

baseline_loglik1 <- pl_neg_loglik(z0, sizes, k = 1L)
baseline_loglik3 <- pl_neg_loglik(z0, sizes, k = 3L)
baseline_eval    <- make_pl_eval(sizes, k = 3L)(z0, dtrain = NULL)$value

log <- function(...) invisible(NULL)  # the exact shadow that broke the tuning grid

shadowed_loglik1 <- pl_neg_loglik(z0, sizes, k = 1L)
shadowed_loglik3 <- pl_neg_loglik(z0, sizes, k = 3L)
shadowed_eval    <- make_pl_eval(sizes, k = 3L)(z0, dtrain = NULL)$value

rm(log)  # restore base::log() for the rest of this script

cat("k = 1 : pl_neg_loglik unshadowed =", baseline_loglik1, " shadowed =", shadowed_loglik1, "\n")
cat("k = 3 : pl_neg_loglik unshadowed =", baseline_loglik3, " shadowed =", shadowed_loglik3, "\n")
cat("make_pl_eval() unshadowed =", baseline_eval, " shadowed =", shadowed_eval, "\n")

stopifnot(
  is.finite(shadowed_loglik1), is.finite(shadowed_loglik3), is.finite(shadowed_eval),
  identical(baseline_loglik1, shadowed_loglik1),
  identical(baseline_loglik3, shadowed_loglik3),
  identical(baseline_eval, shadowed_eval)
)
cat("OK: base::log() qualification is immune to a caller-defined log() shadow\n\n")

cat("All checks passed.\n\n")

# ---------------------------------------------------------------------------
# Timing: pl_core_reference() (dplyr) vs pl_core() (vectorised) at a
# realistic training-fold scale (~4,000 races / ~40,000 rows), plus the
# full-144x5-grid extrapolation this rewrite was for. This complements the
# `xgb.train()` end-to-end benchmark reported separately (which additionally
# includes the split loss-only/grad-only hot paths pl_neg_loglik()/
# pl_grad_hess() use internally, not exercised by pl_core() alone).
# ---------------------------------------------------------------------------
cat("==== Timing: pl_core_reference() (dplyr) vs pl_core() (vectorised) ====\n")
set.seed(1)
sizes_t <- sample(4:16, 4017L, replace = TRUE)
z_t     <- rnorm(sum(sizes_t), sd = 1.5)
cat("Timing dataset: ", length(sizes_t), " races, ", sum(sizes_t), " rows\n", sep = "")

t0 <- Sys.time()
invisible(pl_core_reference(z_t, sizes_t, k = 3L))
t_old <- as.numeric(difftime(Sys.time(), t0, units = "secs")) * 1000

t0 <- Sys.time()
invisible(pl_core(z_t, sizes_t, k = 3L))
t_new <- as.numeric(difftime(Sys.time(), t0, units = "secs")) * 1000

cat("pl_core_reference(): ", round(t_old, 1), " ms\n", sep = "")
cat("pl_core():           ", round(t_new, 1), " ms\n", sep = "")
cat("speedup: ", round(t_old / t_new, 1), "x\n\n", sep = "")

cat("==== Numbers for assertions (5) and (6) ====\n")
cat("(5) paper 2a model_w_final, k=1: pl_neg_loglik-implied logLik = ",
    ll_pl5, ", logLik(model_w_final) = ", ll_mlogit5,
    ", |diff| = ", diff5, "\n", sep = "")
cat("(6) paper 2b model_2b_exploded_draw_final, k=3: pl_neg_loglik-implied logLik = ",
    ll_pl6, ", logLik(model_2b_exploded_draw_final) = ", ll_mlogit6,
    ", |diff| = ", diff6, "\n", sep = "")
