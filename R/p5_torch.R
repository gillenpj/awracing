# p5_torch.R
# Paper 5 — the Plackett-Luce objective in torch, and the race-batching it
# needs.
#
# The likelihood is the one papers 2b and 3 already fit, at k = 3. Race i is
# the grouping unit; given the top-k finishers in order and S = min(k, J-1),
#
#   L_i = - sum_{s=1}^{S} ( z_{i,j_s} - log sum_{r in C_is} exp(z_ir) )
#
# where C_is is the set of horses not yet ranked at stage s. Rows arrive
# arranged by `arrange_for_xgb()`, so the s-th finisher is the s-th row of
# its race block and C_is is "positions s and later" — the same positional
# indexing `R/pl_objective.R` relies on.
#
# Weights are shared across horses: the scorer maps one runner's feature
# vector to one scalar, and the loss couples runners only through the
# per-race softmax denominator. Variable field sizes therefore need no
# special handling beyond masking the padding.
#
# `scripts/verify_p5_pl_torch.R` is the standing gate: this loss must agree
# with `pl_neg_loglik()` to numerical tolerance on the same input.

#' Pad a flat, race-grouped score vector into a race-by-runner matrix
#'
#' @param group_sizes Integer vector of field sizes, race order.
#' @return A list: `row` and `col` index vectors mapping each flat position
#'   into the padded matrix, plus `n_races` and `max_j`.
p5_pad_index <- function(group_sizes) {
  n_races <- length(group_sizes)
  max_j <- max(group_sizes)
  list(
    row = rep.int(seq_len(n_races), group_sizes),
    col = sequence(group_sizes),
    n_races = n_races,
    max_j = max_j
  )
}

#' Plackett-Luce negative log-likelihood, torch
#'
#' Operates on a padded score matrix so it is differentiable and batched.
#' Padded entries contribute nothing: their exponentials are zeroed before
#' the denominator is accumulated, and their stage terms are excluded by a
#' mask applied to an already-finite quantity. Computed in float64, so the
#' agreement with `pl_neg_loglik()` is limited by the algebra rather than by
#' single-precision rounding.
#'
#' @param scores Tensor `[n_races, max_j]` of latent scores.
#' @param valid Tensor `[n_races, max_j]`, 1 where the slot is a real runner.
#' @param stage Tensor `[n_races, max_j]`, 1 where the slot contributes a
#'   stage term, i.e. position <= S = min(k, J - 1).
#' @param reduction `"sum"` or `"mean"` (per race).
#' @return A scalar tensor.
p5_pl_nll_tensor <- function(scores, valid, stage, reduction = "sum") {
  neg_inf <- torch::torch_tensor(-1e30, dtype = scores$dtype)
  masked <- torch::torch_where(valid > 0, scores, neg_inf)
  zmax <- masked$max(dim = 2, keepdim = TRUE)[[1]]
  zc <- scores - zmax
  e <- torch::torch_exp(zc) * valid

  # Denominator at position i is the sum over positions i..J, which is the
  # reverse cumulative sum along the runner axis.
  denom <- torch::torch_flip(
    torch::torch_cumsum(torch::torch_flip(e, dims = 2), dim = 2),
    dims = 2
  )

  # The denominator must be finite and positive BEFORE the stage mask is
  # applied, not merely masked afterwards. `torch_where()` selects the
  # value of one branch but still differentiates both, so a padded slot
  # carrying log(0) = -Inf sends NaN into the gradient even though its
  # forward contribution is discarded. Padded slots are set to 1 (log 1 = 0)
  # and the clamp guards the underflow case where every surviving score in a
  # race sits far below that race's maximum.
  denom_safe <- torch::torch_clamp(denom * valid + (1 - valid), min = 1e-300)

  term <- zc - torch::torch_log(denom_safe)
  zero <- torch::torch_zeros_like(term)
  contrib <- torch::torch_where(stage > 0, term, zero)

  total <- -contrib$sum()
  if (identical(reduction, "mean")) total / scores$size(1) else total
}

#' Plackett-Luce NLL from a flat score vector, matching pl_neg_loglik()
#'
#' Same call shape as `R/pl_objective.R::pl_neg_loglik()`, so the gate can
#' hand both functions identical input.
#'
#' @param z Numeric vector or 1-D tensor of scores, race-grouped and
#'   arranged by `arrange_for_xgb()`.
#' @param group_sizes Integer vector of field sizes.
#' @param k Depth of the objective.
#' @return A scalar tensor.
p5_pl_nll_torch <- function(z, group_sizes, k = 3L) {
  idx <- p5_pad_index(group_sizes)
  n <- sum(group_sizes)
  stopifnot(length(z) == n || (inherits(z, "torch_tensor") && z$numel() == n))

  flat_pos <- (idx$row - 1L) * idx$max_j + idx$col

  valid_m <- matrix(0, idx$n_races, idx$max_j)
  valid_m[cbind(idx$row, idx$col)] <- 1

  J <- rep.int(group_sizes, group_sizes)
  S <- pmin(k, J - 1L)
  stage_m <- matrix(0, idx$n_races, idx$max_j)
  stage_m[cbind(idx$row, idx$col)] <- as.numeric(idx$col <= S)

  scores_m <- torch::torch_zeros(idx$n_races, idx$max_j,
                                 dtype = torch::torch_float64())
  z_t <- if (inherits(z, "torch_tensor")) z else torch::torch_tensor(as.numeric(z))
  scores_m <- scores_m$view(-1)$index_put(
    list(torch::torch_tensor(as.integer(flat_pos), dtype = torch::torch_long())),
    z_t$to(dtype = torch::torch_float64())
  )$view(c(idx$n_races, idx$max_j))

  p5_pl_nll_tensor(
    scores_m,
    torch::torch_tensor(valid_m)$to(dtype = torch::torch_float64()),
    torch::torch_tensor(stage_m)$to(dtype = torch::torch_float64())
  )
}

#' Split races into fixed-size batches
#'
#' Races, never rows: the loss spans a whole field, so a race can never be
#' divided across batches. Each batch is padded to its own longest field.
#'
#' @param group_sizes Integer vector of field sizes, race order.
#' @param batch_races Races per batch.
#' @param shuffle Whether to permute race order.
#' @return A list of batches, each a list of `races` (indices into
#'   `group_sizes`) and `rows` (indices into the flat row order).
p5_race_batches <- function(group_sizes, batch_races, shuffle = FALSE) {
  n_races <- length(group_sizes)
  starts <- cumsum(c(0L, utils::head(group_sizes, -1L))) + 1L
  ends <- cumsum(group_sizes)
  order_of <- if (shuffle) sample.int(n_races) else seq_len(n_races)

  splits <- split(order_of, ceiling(seq_along(order_of) / batch_races))
  purrr::map(unname(splits), function(races) {
    list(
      races = races,
      rows = unlist(purrr::map(races, function(r) starts[r]:ends[r]),
                    use.names = FALSE)
    )
  })
}

#' Pre-compute the padded mask tensors for one batch
#'
#' @param group_sizes Field sizes of the batch's races.
#' @param k Objective depth.
#' @return A list of `valid`, `stage` tensors and the flat scatter index.
p5_batch_masks <- function(group_sizes, k = 3L) {
  idx <- p5_pad_index(group_sizes)
  J <- rep.int(group_sizes, group_sizes)
  S <- pmin(k, J - 1L)

  valid_m <- matrix(0, idx$n_races, idx$max_j)
  valid_m[cbind(idx$row, idx$col)] <- 1
  stage_m <- matrix(0, idx$n_races, idx$max_j)
  stage_m[cbind(idx$row, idx$col)] <- as.numeric(idx$col <= S)

  list(
    valid = torch::torch_tensor(valid_m)$to(dtype = torch::torch_float64()),
    stage = torch::torch_tensor(stage_m)$to(dtype = torch::torch_float64()),
    scatter = torch::torch_tensor(
      as.integer((idx$row - 1L) * idx$max_j + idx$col),
      dtype = torch::torch_long()
    ),
    n_races = idx$n_races,
    max_j = idx$max_j
  )
}

#' Scatter a flat score vector into this batch's padded matrix
#'
#' @param z 1-D tensor of scores in flat row order.
#' @param masks Output of `p5_batch_masks()`.
#' @return A `[n_races, max_j]` tensor.
p5_scatter_scores <- function(z, masks) {
  torch::torch_zeros(masks$n_races * masks$max_j,
                     dtype = torch::torch_float64())$index_put(
    list(masks$scatter), z$to(dtype = torch::torch_float64())
  )$view(c(masks$n_races, masks$max_j))
}
