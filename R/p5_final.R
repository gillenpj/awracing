# p5_final.R
# Paper 5 — the final refits, and the one scoring of the test split.
#
# Each arm is refitted on the FULL training split at the configuration
# selected on the validation slice, then scores the test split once.
#
# NO VALIDATION LOOP HERE, AND THAT IS THE POINT. `p5_fit_mlp()` and
# `p5_fit_gru()` evaluate a held-out set after every epoch and keep the best.
# There is no held-out set left at this stage: the validation slice has been
# folded back into training, and evaluating the test split per epoch — even
# only to record it — would put the test split inside the selection loop.
# These functions therefore train for a FIXED number of epochs, chosen on
# validation and carried over unchanged, and touch the test split exactly
# once, at the end.
#
# THE EPOCH COUNT. Both arms selected epoch 3 on the validation slice, so
# both are trained for 3 epochs here. The full training split is about 43%
# larger than the fitting partition, so an epoch is 43% more gradient steps
# than it was during selection. Both arms take that change identically, so
# the contrast between them is unaffected; it is recorded because it is a
# real difference between the selection fits and these.

#' Train an MLP for a fixed number of epochs and score one matrix
#'
#' Rung 1's arm. The training loop is `p5_fit_mlp()`'s with the per-epoch
#' validation scoring removed.
#'
#' @param x_train Standardised training matrix.
#' @param gs_train Field sizes, race order, matching the training rows.
#' @param x_score Standardised matrix to score once at the end.
#' @param config One row of `p5_mlp_configs_equal_budget()`.
#' @param epochs Epochs to train, fixed in advance.
#' @param seed Integer seed, set for both R and torch.
#' @param k Objective depth.
#' @return A list: the scores, the configuration, and the backend.
p5_fit_final_mlp <- function(x_train, gs_train, x_score, config, epochs,
                             seed = 42L, k = 3L) {
  stopifnot(epochs >= 1L)
  set.seed(seed)
  torch::torch_manual_seed(seed)

  module <- p5_mlp_module(ncol(x_train), config$widths[[1]], config$dropout)
  module$to(dtype = torch::torch_float64())
  optim <- torch::optim_adam(module$parameters, lr = config$lr,
                             weight_decay = config$weight_decay)

  x_t <- torch::torch_tensor(x_train, dtype = torch::torch_float64())
  batches <- p5_race_batches(gs_train, config$batch_races, shuffle = FALSE)
  masks <- purrr::map(batches, function(b) p5_batch_masks(gs_train[b$races], k))

  for (epoch in seq_len(epochs)) {
    module$train()
    ord <- sample.int(length(batches))
    for (bi in ord) {
      b <- batches[[bi]]
      optim$zero_grad()
      z <- module(x_t[b$rows, ])$view(-1)
      padded <- p5_scatter_scores(z, masks[[bi]])
      loss <- p5_pl_nll_tensor(padded, masks[[bi]]$valid, masks[[bi]]$stage)
      loss$backward()
      optim$step()
    }
  }

  list(
    arm = "rung 1 MLP",
    scores = p5_predict_scores(module, x_score),
    config = config$config,
    label = config$width_label,
    lr = config$lr,
    dropout = config$dropout,
    epochs = epochs,
    n_train_rows = nrow(x_train),
    n_train_races = length(gs_train),
    n_terms = ncol(x_train),
    backend = p5_capture_backend()
  )
}

#' Train the encoder for a fixed number of epochs and score one matrix
#'
#' Rung 3's arm. The training loop is `p5_fit_gru()`'s with the per-epoch
#' validation scoring removed.
#'
#' @param x_train,x_score Standardised dense matrices.
#' @param s_train,s_score Standardised sequence arrays.
#' @param l_train,l_score Sequence lengths.
#' @param gs_train Field sizes, race order, matching the training rows.
#' @param config One row of `p5_gru_configs()`.
#' @param epochs Epochs to train, fixed in advance.
#' @param seed Integer seed, set for both R and torch.
#' @param k Objective depth.
#' @return A list: the scores, the configuration, and the backend.
p5_fit_final_gru <- function(x_train, s_train, l_train, gs_train,
                             x_score, s_score, l_score, config, epochs,
                             seed = 42L, k = 3L) {
  stopifnot(epochs >= 1L)
  set.seed(seed)
  torch::torch_manual_seed(seed)

  module <- p5_gru_module(
    n_dense = ncol(x_train), n_channels = dim(s_train)[3],
    hidden = config$hidden, layers = config$layers,
    widths = config$widths[[1]], dropout = config$dropout
  )
  module$to(dtype = torch::torch_float64())
  optim <- torch::optim_adam(module$parameters, lr = config$lr,
                             weight_decay = config$weight_decay)

  x_t <- torch::torch_tensor(x_train, dtype = torch::torch_float64())
  s_t <- torch::torch_tensor(s_train, dtype = torch::torch_float64())
  l_t <- torch::torch_tensor(l_train, dtype = torch::torch_long())
  batches <- p5_race_batches(gs_train, config$batch_races, shuffle = FALSE)
  masks <- purrr::map(batches, function(b) p5_batch_masks(gs_train[b$races], k))

  for (epoch in seq_len(epochs)) {
    module$train()
    ord <- sample.int(length(batches))
    for (bi in ord) {
      b <- batches[[bi]]
      optim$zero_grad()
      z <- module(x_t[b$rows, ], s_t[b$rows, , ], l_t[b$rows])$view(-1)
      padded <- p5_scatter_scores(z, masks[[bi]])
      loss <- p5_pl_nll_tensor(padded, masks[[bi]]$valid, masks[[bi]]$stage)
      loss$backward()
      optim$step()
    }
  }

  list(
    arm = "rung 3 encoder",
    scores = p5_predict_gru_scores(module, x_score, s_score, l_score),
    config = config$config,
    label = config$label,
    lr = config$lr,
    dropout = config$dropout,
    epochs = epochs,
    n_train_rows = nrow(x_train),
    n_train_races = length(gs_train),
    n_terms = ncol(x_train),
    backend = p5_capture_backend()
  )
}

#' Put paper 3's stored key order beside a paper-5 feature frame
#'
#' The test scoring reuses paper 3's own `gbt_train_data` / `gbt_test_data`
#' key order rather than re-deriving one, so a paper-5 score vector lines up
#' with `gbt_test_data$group_sizes` by construction and can be handed
#' straight to `build_test_predictions_3()`.
#'
#' @param key A `race_id`/`runner_id` tibble in paper 3's stored order.
#' @param runners The paper-5 copy of `runners_interactions`.
#' @param group_sizes Paper 3's stored group sizes for that key.
#' @return `runners` reordered to `key`, one row per key row.
p5_rows_in_key_order <- function(key, runners, group_sizes) {
  idx <- match(paste(key$race_id, key$runner_id),
               paste(runners$race_id, runners$runner_id))
  stopifnot(!anyNA(idx), !anyDuplicated(idx))
  out <- runners[idx, ]
  stopifnot(
    nrow(out) == nrow(key),
    identical(as.integer(rle(as.character(key$race_id))$lengths),
              as.integer(group_sizes))
  )
  out
}
