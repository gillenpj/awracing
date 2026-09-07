# p5_gru.R
# Paper 5, rung 3 — the sequence encoder.
#
# ONE CHANGE FROM RUNG 1. Nine hand-summarised history terms come out of the
# feature set and a GRU over the horse's prior-run sequences goes in, its
# output vector concatenated with the remaining terms before rung 1's MLP
# scorer. Everything downstream is rung 1's arm unchanged: the same MLP
# stack, the same Plackett-Luce objective at k = 3, the same validation
# slice, the same seed, the same race universe.
#
# The strike rates stay. Rung 2 closed as a loss and the embeddings that
# would have replaced them are not carried forward.
#
# MASKING IS THE LOAD-BEARING PART. Sequences are right-padded — the real
# runs occupy the leading slots and padding follows — and the encoder output
# is the hidden state at slot `seq_len`, so the recurrence never consumes a
# padded slot. Left-padding would not do: a GRU fed k zero vectors from a
# zero initial state does not stay at zero, because the update and reset
# gates carry biases, so the state entering the first real run would depend
# on how much padding preceded it. `p5_check_gru_masking()` asserts the
# property directly rather than trusting the argument.
#
# ORDER WITHIN THE SEQUENCE. `build_p5_sequences()` stores runs most recent
# first. They are reversed here, so the encoder reads oldest to newest and
# the last thing it sees before emitting its summary is the most recent run.
# The reversal is applied to the real slots only; padding stays at the tail.

#' The nine hand-summarised history terms the encoder replaces
#'
#' Each is a scalar summary of the same prior runs the sequences carry:
#' the two position lags and their companion indicators, the layoff, the
#' going-affinity block, and the ever-won flag.
#'
#' @format Character vector of length 9.
P5_RUNG3_DROPPED <- c(
  "pos_lag1_zero", "pos_lag1_nonzero", "pos_lag2_zero", "pos_lag2_nonzero",
  "days_LTO_log", "going_runs_prior", "going_sr_shrunk", "going_sr_delta",
  "has_wins"
)

#' The scalar the encoder block carries alongside the sequence
#'
#' The sequence is capped at the 20 most recent runs, so a horse with a
#' longer career has its oldest runs truncated. `career_runs_prior` is the
#' untruncated count and is part of the encoder block, not a new feature
#' added on top of it: without it the block would carry strictly less than
#' the sequences do.
#'
#' @format Character scalar.
P5_RUNG3_SEQ_SCALAR <- "career_runs_prior"

#' Rung 3's dense feature set
#'
#' Rung 1's 26 terms less the nine the encoder replaces, plus the encoder
#' block's own scalar. A function rather than a constant: nothing under
#' `R/` may depend on the alphabetical order `tar_source()` reads it in.
#'
#' @param control_terms Rung 1's term vector.
#' @return Character vector of length 18.
p5_rung3_term_list <- function(control_terms = P5_CONTROL_TERMS) {
  c(setdiff(control_terms, P5_RUNG3_DROPPED), P5_RUNG3_SEQ_SCALAR)
}

#' Align the built sequences to an arm's scoring row order
#'
#' `build_p5_sequences()` returns rows sorted by `(race_id, runner_id)`;
#' the fitting arms are ordered by `arrange_for_xgb()`. This matches one to
#' the other and reverses each row's real slots into chronological order.
#'
#' @param sequences The `p5_sequences` target.
#' @param key A tibble of `race_id`/`runner_id` in the arm's row order.
#' @return A list: `x` (`[n, max_len, n_channels]`, oldest real run first),
#'   `seq_len`, `career_runs_prior`.
p5_align_sequences <- function(sequences, key) {
  row_of <- match(
    paste(key$race_id, key$runner_id),
    paste(sequences$key$race_id, sequences$key$runner_id)
  )
  stopifnot(!anyNA(row_of), !anyDuplicated(row_of))

  x <- sequences$x[row_of, , , drop = FALSE]
  lens <- sequences$seq_len[row_of]

  # Reverse the real slots only. Padding is at the tail and stays there.
  for (i in which(lens > 1L)) {
    x[i, seq_len(lens[i]), ] <- x[i, rev(seq_len(lens[i])), , drop = FALSE]
  }

  list(x = x, seq_len = as.integer(lens),
       career_runs_prior = as.integer(sequences$career_runs_prior[row_of]))
}

#' Standardise sequence channels on the fitting partition's real slots
#'
#' Channel-wise centring and scaling, with statistics taken over the real
#' slots of the fitting partition only — padding contributes nothing to the
#' mean, and no validation slot influences the scale. Padded slots are set
#' back to exactly zero afterwards; they are masked in any case, and leaving
#' them at a standardised zero would make the padding channel-dependent for
#' no reason.
#'
#' The `-1` unavailable sentinel is standardised along with the real
#' readings rather than treated separately. It is outside every channel's
#' natural range by construction, so it stays separable after an affine
#' transform — the same treatment rung 1 gives its own missing values.
#'
#' @param x_fit,x_val Arrays `[n, max_len, n_channels]`.
#' @param len_fit,len_val Sequence lengths.
#' @return A list: `fit`, `val`, `centre`, `scale`.
p5_standardise_sequences <- function(x_fit, len_fit, x_val, len_val) {
  max_len <- dim(x_fit)[2]
  n_ch <- dim(x_fit)[3]
  mask_fit <- outer(len_fit, seq_len(max_len), ">=")
  mask_val <- outer(len_val, seq_len(max_len), ">=")

  centre <- numeric(n_ch)
  scale <- numeric(n_ch)
  for (f in seq_len(n_ch)) {
    real <- x_fit[, , f][mask_fit]
    centre[f] <- mean(real)
    s <- stats::sd(real)
    scale[f] <- if (!is.finite(s) || s < 1e-12) 1 else s
    x_fit[, , f] <- (x_fit[, , f] - centre[f]) / scale[f]
    x_val[, , f] <- (x_val[, , f] - centre[f]) / scale[f]
    x_fit[, , f][!mask_fit] <- 0
    x_val[, , f][!mask_val] <- 0
  }
  list(fit = x_fit, val = x_val, centre = centre, scale = scale)
}

#' The rung-3 scorer: a GRU encoder feeding rung 1's MLP
#'
#' The MLP stack is `p5_mlp_module()` — rung 1's scorer, unchanged — sitting
#' on a wider input. Nothing about its hidden layers, activation or dropout
#' differs.
#'
#' @param n_dense Number of dense columns.
#' @param n_channels Sequence channels.
#' @param hidden GRU hidden size.
#' @param layers GRU layers.
#' @param widths Hidden layer widths of the downstream MLP.
#' @param dropout Dropout probability, applied between GRU layers and
#'   between MLP layers.
#' @return A `torch::nn_module` mapping (dense, sequence, length) to one
#'   score a row.
p5_gru_module <- torch::nn_module(
  "p5_gru_scorer",
  initialize = function(n_dense, n_channels, hidden, layers, widths,
                        dropout) {
    self$hidden <- hidden
    self$gru <- torch::nn_gru(
      input_size = n_channels, hidden_size = hidden, num_layers = layers,
      batch_first = TRUE, dropout = if (layers > 1L) dropout else 0
    )
    self$mlp <- p5_mlp_module(n_dense + hidden, widths, dropout)
  },
  forward = function(x_dense, x_seq, lens) {
    out <- self$gru(x_seq)[[1]]

    # The hidden state at the last REAL slot. Rows with no prior run have
    # no such slot; they are gathered at slot 1 to keep the index valid and
    # then zeroed, which is the same vector a zero-length sequence would
    # give.
    idx <- torch::torch_clamp(lens, min = 1L)$
      to(dtype = torch::torch_long())$
      view(c(-1L, 1L, 1L))$
      expand(c(-1L, 1L, self$hidden))
    h <- out$gather(dim = 2, index = idx)$squeeze(2)
    keep <- (lens > 0)$to(dtype = torch::torch_float64())$view(c(-1L, 1L))
    h <- h * keep

    self$mlp(torch::torch_cat(list(x_dense, h), dim = 2))
  }
)

#' Score every row with a fitted encoder
#'
#' @param module A fitted `p5_gru_module`.
#' @param x Standardised dense matrix.
#' @param x_seq Standardised sequence array.
#' @param lens Sequence lengths.
#' @param chunk Rows per forward pass.
#' @return Numeric vector of scores, one per row.
p5_predict_gru_scores <- function(module, x, x_seq, lens, chunk = 4096L) {
  module$eval()
  parts <- split(seq_len(nrow(x)), ceiling(seq_len(nrow(x)) / chunk))
  out <- purrr::map(parts, function(rows) {
    torch::with_no_grad({
      as.numeric(
        module(
          torch::torch_tensor(x[rows, , drop = FALSE],
                              dtype = torch::torch_float64()),
          torch::torch_tensor(x_seq[rows, , , drop = FALSE],
                              dtype = torch::torch_float64()),
          torch::torch_tensor(lens[rows], dtype = torch::torch_long())
        )$view(-1)
      )
    })
  })
  unlist(out, use.names = FALSE)
}

#' The nine declared configurations for rung 3
#'
#' Declared in full before any of them is scored, and selection is on
#' validation Plackett-Luce loss and nothing else.
#'
#' A one-factor-at-a-time design around a centre of hidden 32, one layer,
#' dropout 0.1, lr 1e-3, rather than a factorial: four axes at three levels
#' is 81 fits, and rung 1 showed the response surface over this kind of grid
#' is flat enough that nine well-spread points locate the plateau.
#'
#' The downstream MLP is held at rung 1's SELECTED architecture — 256-128,
#' batch 64, weight decay 1e-5 — so the only architecture being searched is
#' the encoder's own. Sixty epochs, not 200: rung 1 established that the
#' optimum arrives inside ten epochs and the rest proves divergence. The
#' selected configuration is then refitted alone at 200 epochs, which is
#' what makes the budget comparable with rung 1's.
#'
#' @format A tibble of nine rows.
p5_gru_configs <- function() {
  spec <- tibble::tribble(
    ~hidden, ~layers, ~dropout,   ~lr,
        16L,      1L,      0.1, 1e-03,
        32L,      1L,      0.1, 1e-03,
        64L,      1L,      0.1, 1e-03,
        32L,      1L,      0.0, 1e-03,
        32L,      1L,      0.3, 1e-03,
        32L,      2L,      0.1, 1e-03,
        64L,      2L,      0.1, 1e-03,
        32L,      1L,      0.1, 3e-03,
        32L,      1L,      0.1, 3e-04
  )
  spec |>
    dplyr::mutate(
      config = dplyr::row_number(),
      widths = list(c(256L, 128L)),
      width_label = "256-128",
      label = paste0("h", hidden, "/L", layers, "/d", dropout),
      batch_races = 64L,
      max_epochs = 60L,
      weight_decay = 1e-5
    ) |>
    dplyr::select(config, hidden, layers, dropout, lr, widths, width_label,
                  label, batch_races, max_epochs, weight_decay)
}

#' Fit one rung-3 configuration
#'
#' `p5_fit_mlp()` with two extra inputs. The training loop, the batching,
#' the seeding, the optimiser, the per-epoch validation scoring and the
#' best-epoch selection are identical — selection is on validation
#' Plackett-Luce loss and nothing else.
#'
#' @param x_fit,x_val Standardised dense matrices.
#' @param s_fit,s_val Standardised sequence arrays.
#' @param l_fit,l_val Sequence lengths.
#' @param gs_fit,gs_val Field sizes, race order, matching the row order.
#' @param config One row of `p5_gru_configs()`.
#' @param seed Integer seed, set for both R and torch.
#' @param k Objective depth.
#' @return The same shape `p5_fit_mlp()` returns, plus the encoder
#'   hyperparameters and the backend the fit ran on.
p5_fit_gru <- function(x_fit, x_val, s_fit, s_val, l_fit, l_val,
                       gs_fit, gs_val, config, seed = 42L, k = 3L) {
  set.seed(seed)
  torch::torch_manual_seed(seed)

  module <- p5_gru_module(
    n_dense = ncol(x_fit), n_channels = dim(s_fit)[3],
    hidden = config$hidden, layers = config$layers,
    widths = config$widths[[1]], dropout = config$dropout
  )
  module$to(dtype = torch::torch_float64())
  optim <- torch::optim_adam(module$parameters, lr = config$lr,
                             weight_decay = config$weight_decay)

  x_fit_t <- torch::torch_tensor(x_fit, dtype = torch::torch_float64())
  s_fit_t <- torch::torch_tensor(s_fit, dtype = torch::torch_float64())
  l_fit_t <- torch::torch_tensor(l_fit, dtype = torch::torch_long())
  batches <- p5_race_batches(gs_fit, config$batch_races, shuffle = FALSE)
  masks <- purrr::map(batches, function(b) p5_batch_masks(gs_fit[b$races], k))

  best <- list(loss = Inf, epoch = NA_integer_, scores = NULL)
  trace <- numeric(config$max_epochs)

  for (epoch in seq_len(config$max_epochs)) {
    module$train()
    ord <- sample.int(length(batches))
    for (bi in ord) {
      b <- batches[[bi]]
      optim$zero_grad()
      z <- module(x_fit_t[b$rows, ], s_fit_t[b$rows, , ],
                  l_fit_t[b$rows])$view(-1)
      padded <- p5_scatter_scores(z, masks[[bi]])
      loss <- p5_pl_nll_tensor(padded, masks[[bi]]$valid, masks[[bi]]$stage)
      loss$backward()
      optim$step()
    }

    val_scores <- p5_predict_gru_scores(module, x_val, s_val, l_val)
    val_loss <- p5_pl_loss_value(val_scores, gs_val, k)
    trace[epoch] <- val_loss
    if (is.finite(val_loss) && val_loss < best$loss) {
      best <- list(loss = val_loss, epoch = epoch, scores = val_scores)
    }
  }

  list(
    config = config$config,
    label = config$label,
    hidden = config$hidden,
    layers = config$layers,
    dropout = config$dropout,
    width_label = config$width_label,
    lr = config$lr,
    max_epochs = config$max_epochs,
    best_val_loss = best$loss,
    best_epoch = best$epoch,
    final_val_loss = trace[config$max_epochs],
    trace = trace,
    val_scores = best$scores,
    backend = p5_capture_backend()
  )
}

#' Summarise a set of rung-3 runs as one selection table
#'
#' @param runs A list of `p5_fit_gru()` results.
#' @return A tibble ordered by best validation PL loss.
p5_gru_run_table <- function(runs) {
  purrr::map(runs, function(r) {
    tibble::tibble(
      config = r$config, hidden = r$hidden, layers = r$layers,
      dropout = r$dropout, lr = r$lr, epochs = r$max_epochs,
      best_val_pl_loss = r$best_val_loss,
      best_epoch = r$best_epoch,
      final_epoch_val_pl_loss = r$final_val_loss,
      degradation = r$final_val_loss - r$best_val_loss
    )
  }) |>
    purrr::list_rbind() |>
    dplyr::arrange(best_val_pl_loss)
}

#' Assert that the encoder never reads padding
#'
#' Three properties, on a randomly initialised encoder in eval mode:
#'
#' \enumerate{
#'   \item **Padding width is inert.** The same real runs padded to width 20
#'     and to width 32 give the same output.
#'   \item **Padding content is inert.** Overwriting the padded slots with
#'     large arbitrary values changes nothing.
#'   \item **The gathered state is the right one.** The output equals what
#'     the same encoder gives when fed each row's real runs alone, with no
#'     padding at all — which an off-by-one in the gather index would fail
#'     even though both invariances above would still hold.
#' }
#'
#' A zero-length row is included: its encoder contribution must be exactly
#' the zero vector.
#'
#' @param seed Integer seed.
#' @param tol Absolute tolerance.
#' @return A tibble of the three checks and their observed maximum absolute
#'   differences.
p5_check_gru_masking <- function(seed = 42L, tol = 1e-12) {
  set.seed(seed)
  torch::torch_manual_seed(seed)

  n <- 12L
  max_len <- 20L
  n_ch <- length(P5_SEQ_FEATURES)
  n_dense <- 5L
  hidden <- 8L

  lens <- c(0L, 1L, 2L, 5L, 20L, sample.int(max_len, n - 5L, replace = TRUE))
  x_dense <- matrix(stats::rnorm(n * n_dense), nrow = n)

  x <- array(0, dim = c(n, max_len, n_ch))
  for (i in seq_len(n)) {
    if (lens[i] > 0L) {
      x[i, seq_len(lens[i]), ] <- stats::rnorm(lens[i] * n_ch)
    }
  }

  module <- p5_gru_module(n_dense, n_ch, hidden, 1L, c(8L, 4L), 0.1)
  module$to(dtype = torch::torch_float64())
  module$eval()

  run <- function(arr, l) {
    torch::with_no_grad({
      as.numeric(
        module(
          torch::torch_tensor(x_dense, dtype = torch::torch_float64()),
          torch::torch_tensor(arr, dtype = torch::torch_float64()),
          torch::torch_tensor(l, dtype = torch::torch_long())
        )$view(-1)
      )
    })
  }

  base <- run(x, lens)

  # (1) wider padding
  wide <- array(0, dim = c(n, 32L, n_ch))
  wide[, seq_len(max_len), ] <- x
  d_width <- max(abs(run(wide, lens) - base))

  # (2) garbage in the padded slots
  dirty <- x
  for (i in seq_len(n)) {
    if (lens[i] < max_len) {
      dirty[i, (lens[i] + 1L):max_len, ] <- 1e3 * stats::rnorm(
        (max_len - lens[i]) * n_ch
      )
    }
  }
  d_content <- max(abs(run(dirty, lens) - base))

  # (3) each row fed its real runs alone, no padding
  one_row <- function(i) {
    li <- lens[i]
    arr <- array(0, dim = c(1L, max(li, 1L), n_ch))
    if (li > 0L) arr[1, seq_len(li), ] <- x[i, seq_len(li), ]
    torch::with_no_grad({
      as.numeric(
        module(
          torch::torch_tensor(x_dense[i, , drop = FALSE],
                              dtype = torch::torch_float64()),
          torch::torch_tensor(arr, dtype = torch::torch_float64()),
          torch::torch_tensor(li, dtype = torch::torch_long())
        )$view(-1)
      )
    })
  }
  d_alone <- max(abs(vapply(seq_len(n), one_row, numeric(1)) - base))

  # A zero-length row contributes exactly the zero vector, so its score is
  # the MLP's on a zero-filled encoder slot.
  zero_row <- which(lens == 0L)[1]
  zero_arr <- array(0, dim = c(1L, max_len, n_ch))
  d_zero <- abs(
    torch::with_no_grad({
      as.numeric(module(
        torch::torch_tensor(x_dense[zero_row, , drop = FALSE],
                            dtype = torch::torch_float64()),
        torch::torch_tensor(zero_arr, dtype = torch::torch_float64()),
        torch::torch_tensor(0L, dtype = torch::torch_long())
      )$view(-1))
    }) - base[zero_row]
  )

  out <- tibble::tibble(
    check = c("padding width is inert",
              "padding content is inert",
              "matches the unpadded sequence",
              "zero-length row gives the zero vector"),
    max_abs_diff = c(d_width, d_content, d_alone, d_zero),
    tol = tol,
    passed = c(d_width, d_content, d_alone, d_zero) <= tol
  )
  stopifnot(all(out$passed))
  out
}
