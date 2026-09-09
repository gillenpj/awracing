# scripts/verify_p5_pl_torch.R
# Standing gate on paper 5's torch Plackett-Luce objective.
#
# The claim: `R/p5_torch.R::p5_pl_nll_torch()` computes the same number as
# `R/pl_objective.R::pl_neg_loglik()` — the loss papers 2b and 3 already fit
# — on the same input. If it does not, every fitted result in paper 5 is
# optimising a different objective from the papers it is compared against,
# and nothing downstream means what it claims.
#
# Run with:
#   "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" scripts/verify_p5_pl_torch.R
# from the project root, via PowerShell (torch crashes under the Bash tool's
# Git Bash environment on this machine).
#
# Read-only: opens no database connection, writes to no store, and never
# calls tar_config_set().
#
# What it asserts:
#   (1) Agreement on random inputs across many field-size mixes, including
#       the edge cases: two-runner races (S = 1), races at exactly k + 1
#       runners, and single-race inputs.
#   (2) Agreement at k = 1, 2, 3 and 4, not only the k = 3 the paper fits.
#   (3) Shift invariance, which the loss has analytically: adding a constant
#       to every score in a race must not move the loss.
#   (4) Agreement on degenerate score vectors — all-equal, large-magnitude,
#       and widely-spread scores that would overflow a naive exp().
#   (5) The gradient is finite everywhere and matches a finite-difference
#       check on the R implementation.
#   (6) Padding is inert: a batch padded to a longer width gives the same
#       loss as one padded to its own width.

source("renv/activate.R")

suppressPackageStartupMessages({
  library(torch)
})
source("R/pl_objective.R")
source("R/p5_torch.R")

set.seed(20260905)
TOL <- 1e-5

cat("torch:", as.character(utils::packageVersion("torch")), "\n")
cat("tolerance:", TOL, "\n\n")

agree <- function(z, group_sizes, k, label) {
  r_val <- pl_neg_loglik(z, group_sizes, k)
  t_val <- as.numeric(p5_pl_nll_torch(z, group_sizes, k)$item())
  rel <- abs(t_val - r_val) / max(abs(r_val), 1)
  cat(sprintf("  %-46s R %14.8f | torch %14.8f | rel diff %.3e\n",
              label, r_val, t_val, rel))
  stopifnot(is.finite(r_val), is.finite(t_val), rel < TOL)
  invisible(rel)
}

# ---------------------------------------------------------------------------
cat("---- (1) Random inputs, mixed field sizes ----\n")
for (trial in 1:8) {
  n_races <- sample(3:40, 1)
  gs <- sample(2:16, n_races, replace = TRUE)
  z <- stats::rnorm(sum(gs))
  agree(z, gs, 3L, sprintf("trial %d: %d races, fields %d-%d",
                           trial, n_races, min(gs), max(gs)))
}

cat("\n---- (1b) Edge cases in field size ----\n")
agree(stats::rnorm(2), 2L, 3L, "one race of 2 (S = 1)")
agree(stats::rnorm(4), 4L, 3L, "one race of 4 (S = 3 = k)")
agree(stats::rnorm(3), 3L, 3L, "one race of 3 (S = 2, J - 1 binds)")
agree(stats::rnorm(24), rep(2L, 12), 3L, "twelve races of 2")
agree(stats::rnorm(16), c(2L, 3L, 4L, 7L), 3L, "ragged: 2, 3, 4, 7")
agree(stats::rnorm(40), c(16L, 2L, 16L, 2L, 4L), 3L, "wide then narrow")

cat("\n---- (2) Objective depth k ----\n")
gs <- c(5L, 8L, 3L, 12L, 2L)
z <- stats::rnorm(sum(gs))
for (k in 1:4) agree(z, gs, as.integer(k), sprintf("k = %d", k))

cat("\n---- (3) Shift invariance ----\n")
gs <- c(6L, 9L, 4L)
z <- stats::rnorm(sum(gs))
race <- rep.int(seq_along(gs), gs)
shift <- stats::rnorm(length(gs), sd = 5)[race]
base_val <- as.numeric(p5_pl_nll_torch(z, gs, 3L)$item())
shift_val <- as.numeric(p5_pl_nll_torch(z + shift, gs, 3L)$item())
cat(sprintf("  unshifted %14.8f | per-race shift %14.8f | diff %.3e\n",
            base_val, shift_val, abs(shift_val - base_val)))
stopifnot(abs(shift_val - base_val) < TOL * max(abs(base_val), 1))
agree(z + shift, gs, 3L, "shifted input still matches R")

cat("\n---- (4) Degenerate and extreme score vectors ----\n")
gs <- c(8L, 5L, 11L)
n <- sum(gs)
agree(rep(0, n), gs, 3L, "all scores equal (uniform softmax)")
agree(rep(50, n), gs, 3L, "all scores large and equal")
agree(stats::rnorm(n) * 40, gs, 3L, "scores spread over ~200 (exp overflow)")
agree(stats::rnorm(n) * 1e-8, gs, 3L, "scores near zero")
agree(seq(-30, 30, length.out = n), gs, 3L, "monotone spread")

cat("\n---- (5) Gradient: finite, and matching finite differences ----\n")
gs <- c(7L, 4L, 9L)
z0 <- stats::rnorm(sum(gs))
zt <- torch_tensor(z0, requires_grad = TRUE)
loss <- p5_pl_nll_torch(zt, gs, 3L)
loss$backward()
g_torch <- as.numeric(zt$grad)
stopifnot(all(is.finite(g_torch)))

eps <- 1e-5
g_fd <- vapply(seq_along(z0), function(i) {
  zp <- z0; zm <- z0
  zp[i] <- zp[i] + eps
  zm[i] <- zm[i] - eps
  (pl_neg_loglik(zp, gs, 3L) - pl_neg_loglik(zm, gs, 3L)) / (2 * eps)
}, numeric(1))
max_g <- max(abs(g_torch - g_fd))
cat(sprintf("  max |autograd - finite difference| over %d scores: %.3e\n",
            length(z0), max_g))
stopifnot(max_g < 1e-4)

# The analytic gradient in R/pl_objective.R must agree too, or paper 3 and
# paper 5 are descending different surfaces.
gh <- pl_grad_hess(z0, gs, 3L)
max_gr <- max(abs(g_torch - gh$grad))
cat(sprintf("  max |autograd - pl_grad_hess() grad|: %.3e\n", max_gr))
stopifnot(max_gr < 1e-4)

cat("\n---- (6) Padding is inert ----\n")
gs <- c(3L, 5L)
z <- stats::rnorm(sum(gs))
own_width <- as.numeric(p5_pl_nll_torch(z, gs, 3L)$item())

masks <- p5_batch_masks(gs, 3L)
wide_valid <- torch_cat(list(masks$valid, torch_zeros(2, 6)), dim = 2)
wide_stage <- torch_cat(list(masks$stage, torch_zeros(2, 6)), dim = 2)
wide_scores <- torch_cat(
  list(p5_scatter_scores(torch_tensor(z), masks), torch_zeros(2, 6)), dim = 2
)
wide <- as.numeric(p5_pl_nll_tensor(wide_scores, wide_valid, wide_stage)$item())
cat(sprintf("  padded to own width %14.8f | padded 6 wider %14.8f | diff %.3e\n",
            own_width, wide, abs(wide - own_width)))
stopifnot(abs(wide - own_width) < TOL * max(abs(own_width), 1))

cat("\n---- (7) No NaN from the masked stage terms ----\n")
gs <- c(2L, 2L, 16L)
z <- stats::rnorm(sum(gs))
val <- p5_pl_nll_torch(z, gs, 3L)
stopifnot(is.finite(as.numeric(val$item())))
zt <- torch_tensor(z, requires_grad = TRUE)
p5_pl_nll_torch(zt, gs, 3L)$backward()
stopifnot(all(is.finite(as.numeric(zt$grad))))
cat("  loss and gradient finite where padding and stage masks overlap\n")

cat("\nALL ASSERTIONS PASSED\n")
