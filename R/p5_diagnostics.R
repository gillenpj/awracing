# p5_diagnostics.R
# Paper 5 — ROI intervals on the closed test backtest, and validation-only
# encoder diagnostics.
#
# NOTHING HERE REFITS OR RESCORES THE TEST SPLIT. The ROI work reads stored
# predictions and stored paper-3 targets and re-derives per-race bet units
# from them, which is a deterministic function of scores that already exist.
# The encoder diagnostics run entirely on the validation slice.
#
# A SEPARATE FILE, DELIBERATELY. `R/p5_gru.R` cannot be edited without
# invalidating rungs 3 and 3b (`torch::nn_module()` builds `p5_gru_module` at
# source time and the generator captures the enclosing environment — see the
# standing convention in CLAUDE.md). Everything new lives here and only
# calls into that file.

# ---------------------------------------------------------------------------
# ROI intervals
# ---------------------------------------------------------------------------

#' Per-race single-bet units for one arm, all three bet types
#'
#' Re-derived from a stored `test_predictions`-shaped tibble. No model is
#' refitted and no score recomputed: `compute_model_market_ratio_p2()` and
#' the value-bet builders are deterministic functions of the stored
#' predictions.
#'
#' @param pred A stored test-predictions tibble (`win_model`, `win_market`,
#'   `won`, `starting_price_decimal`, `race_id`, `runner_id`, `horse_ref`).
#' @param qualifying_runners The series' runner table.
#' @return A named list of `single_bet_units()` tibbles: `win`, `place`,
#'   `eachway`.
p5_bet_units_for <- function(pred, qualifying_runners) {
  ratio <- compute_model_market_ratio_p2(
    pred |> dplyr::rename(predicted_prob = win_model,
                          market_prob = win_market)
  )
  vbr <- build_value_bet_runners(pred, qualifying_runners)
  list(
    win = single_bet_units(ratio, NULL),
    place = single_bet_units(ratio, build_place_value_bets(vbr)),
    eachway = single_bet_units(ratio, build_eachway_value_bets(vbr))
  )
}

#' Per-race single-bet units for paper 3, from its own stored targets
#'
#' @param ratio_df Paper 3's stored `model_market_ratio_3_win`.
#' @param place,eachway Paper 3's stored value-bet payout tibbles.
#' @return The same shape `p5_bet_units_for()` returns.
p5_bet_units_from_stored <- function(ratio_df, place, eachway) {
  list(
    win = single_bet_units(ratio_df, NULL),
    place = single_bet_units(ratio_df, place),
    eachway = single_bet_units(ratio_df, eachway)
  )
}

#' Paired race-level bootstrap on single-bet ROI
#'
#' The structure of `bootstrap_roi_difference()` — resample the COMMON race
#' universe, each arm contributing its own stake and return on each drawn
#' race, with a race the arm did not bet contributing zero — applied to the
#' SINGLE-BET rule rather than the naive multi-bet rule. Pairing is what the
#' shared race draw buys: the two arms bet on overlapping but different sets
#' of races, and resampling races rather than bets keeps their correlation.
#'
#' `bootstrap_roi_difference()` itself cannot be reused: it recomputes bets
#' internally under the multi-bet rule (`n_bets = n()` per race), which is a
#' different backtest from the one the paper reports.
#'
#' @param units_a,units_b Per-race unit tibbles (`race_id`, `stake`, `ret`).
#' @param races The common race universe both arms were scored on.
#' @param label Contrast label.
#' @param bet Bet-type label.
#' @param n_boot,seed Bootstrap replicates and seed.
#' @return A one-row tibble with point difference, 90% interval, and each
#'   arm's own ROI and bet count.
p5_bootstrap_single_bet_roi <- function(units_a, units_b, races, label, bet,
                                        n_boot = 2000L, seed = 42L) {
  fill <- function(u) {
    agg <- u |>
      dplyr::filter(race_id %in% races) |>
      dplyr::group_by(race_id) |>
      dplyr::summarise(stake = sum(stake), ret = sum(ret), .groups = "drop")
    tibble::tibble(race_id = races) |>
      dplyr::left_join(agg, by = "race_id") |>
      dplyr::mutate(stake = dplyr::coalesce(stake, 0),
                    ret = dplyr::coalesce(ret, 0))
  }
  a <- fill(units_a)
  b <- fill(units_b)
  n <- length(races)

  roi <- function(st, rt) if (sum(st) == 0) NA_real_ else
    (sum(rt) - sum(st)) / sum(st)
  roi_a <- roi(a$stake, a$ret)
  roi_b <- roi(b$stake, b$ret)

  set.seed(seed)
  diffs <- vapply(seq_len(n_boot), function(i) {
    idx <- sample.int(n, n, replace = TRUE)
    roi(a$stake[idx], a$ret[idx]) - roi(b$stake[idx], b$ret[idx])
  }, numeric(1))

  tibble::tibble(
    contrast = label,
    bet = bet,
    roi_a = roi_a,
    roi_b = roi_b,
    diff_point = roi_a - roi_b,
    ci_lo = stats::quantile(diffs, 0.05, na.rm = TRUE, names = FALSE),
    ci_hi = stats::quantile(diffs, 0.95, na.rm = TRUE, names = FALSE),
    n_bets_a = sum(a$stake > 0),
    n_bets_b = sum(b$stake > 0),
    n_races = n,
    n_boot = n_boot
  )
}

# ---------------------------------------------------------------------------
# Encoder diagnostics, validation slice only
# ---------------------------------------------------------------------------

#' Refit the selected encoder and return the fitted module
#'
#' `p5_fit_gru()` returns scores, not the module, so the encoder's hidden
#' states cannot be recovered from anything stored. This trains the same
#' configuration, on the same fitting partition, with the same seed, for
#' exactly the number of epochs the validation slice selected — which
#' reproduces the module that produced the stored arm. The caller verifies
#' that by comparing scores.
#'
#' The loop is `p5_fit_gru()`'s, minus the per-epoch validation scoring and
#' plus the module in the return value. It is duplicated rather than
#' refactored because refactoring means editing `R/p5_gru.R`.
#'
#' @param x_fit Standardised dense matrix, fitting partition.
#' @param s_fit Standardised sequence array, fitting partition.
#' @param l_fit Sequence lengths, fitting partition.
#' @param gs_fit Field sizes, race order.
#' @param config One row of `p5_gru_configs()`.
#' @param epochs Epochs to train.
#' @param seed Integer seed.
#' @param k Objective depth.
#' @return The fitted `nn_module`.
p5_refit_encoder_module <- function(x_fit, s_fit, l_fit, gs_fit, config,
                                    epochs, seed = 42L, k = 3L) {
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

  x_t <- torch::torch_tensor(x_fit, dtype = torch::torch_float64())
  s_t <- torch::torch_tensor(s_fit, dtype = torch::torch_float64())
  l_t <- torch::torch_tensor(l_fit, dtype = torch::torch_long())
  batches <- p5_race_batches(gs_fit, config$batch_races, shuffle = FALSE)
  masks <- purrr::map(batches, function(b) p5_batch_masks(gs_fit[b$races], k))

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
  module
}

#' The encoder's hidden state for every row
#'
#' The same gather `p5_gru_module`'s `forward()` performs: the GRU output at
#' the last REAL slot, zeroed for a row with no prior run. Recomputed here
#' rather than returned by the module, which emits only the final score.
#'
#' @param module A fitted `p5_gru_module`.
#' @param x_seq Standardised sequence array.
#' @param lens Sequence lengths.
#' @param chunk Rows per forward pass.
#' @return Numeric matrix `[n, hidden]`.
p5_encoder_hidden <- function(module, x_seq, lens, chunk = 4096L) {
  module$eval()
  n <- dim(x_seq)[1]
  parts <- split(seq_len(n), ceiling(seq_len(n) / chunk))
  out <- purrr::map(parts, function(rows) {
    torch::with_no_grad({
      s <- torch::torch_tensor(x_seq[rows, , , drop = FALSE],
                               dtype = torch::torch_float64())
      l <- torch::torch_tensor(lens[rows], dtype = torch::torch_long())
      o <- module$gru(s)[[1]]
      idx <- torch::torch_clamp(l, min = 1L)$
        to(dtype = torch::torch_long())$
        view(c(-1L, 1L, 1L))$
        expand(c(-1L, 1L, module$hidden))
      h <- o$gather(dim = 2, index = idx)$squeeze(2)
      keep <- (l > 0)$to(dtype = torch::torch_float64())$view(c(-1L, 1L))
      as.matrix(h * keep)
    })
  })
  do.call(rbind, out)
}

#' Score rows from the dense block and a hidden-state matrix
#'
#' Used only to verify that `p5_encoder_hidden()` reproduces the module's own
#' forward pass: feeding the extracted states back through the MLP must give
#' the scores the arm was evaluated on.
#'
#' @param module A fitted `p5_gru_module`.
#' @param x Standardised dense matrix.
#' @param h Hidden-state matrix from `p5_encoder_hidden()`.
#' @return Numeric vector of scores.
p5_scores_from_hidden <- function(module, x, h) {
  module$eval()
  torch::with_no_grad({
    as.numeric(
      module$mlp(torch::torch_cat(
        list(torch::torch_tensor(x, dtype = torch::torch_float64()),
             torch::torch_tensor(h, dtype = torch::torch_float64())),
        dim = 2
      ))$view(-1)
    )
  })
}

#' Linear recovery of a hand-built feature from the encoder's output
#'
#' Ordinary least squares of each named feature on the encoder's hidden
#' dimensions, on complete cases. Descriptive: an R-squared near 1 means the
#' encoder's summary contains the hand-built one, near 0 that it is carrying
#' something else. No interval is attached and none should be.
#'
#' @param h Hidden-state matrix `[n, hidden]`.
#' @param rows The validation rows, carrying the features.
#' @param features Feature names to regress.
#' @return A tibble: `feature`, `r_squared`, `n`, `n_missing`, `sd`.
p5_encoder_recovery <- function(h, rows, features) {
  hd <- as.data.frame(h)
  names(hd) <- paste0("h", seq_len(ncol(h)))
  purrr::map(features, function(f) {
    y <- rows[[f]]
    ok <- !is.na(y)
    fit <- stats::lm(y[ok] ~ ., data = hd[ok, , drop = FALSE])
    tibble::tibble(
      feature = f,
      r_squared = summary(fit)$r.squared,
      n = sum(ok),
      n_missing = sum(!ok),
      sd = stats::sd(y[ok])
    )
  }) |>
    purrr::list_rbind() |>
    dplyr::arrange(dplyr::desc(r_squared))
}

#' Truncate built sequences to the k most recent prior runs
#'
#' `build_p5_sequences()` stores runs MOST RECENT FIRST, so the k most recent
#' are simply the leading k slots. `career_runs_prior` is left untruncated —
#' it is the encoder block's scalar and reports the full career length at
#' every k, exactly as it does at 20.
#'
#' @param sequences The `p5_sequences` target.
#' @param k Slots to keep.
#' @return A sequences list of the same shape, capped at `k`.
p5_truncate_sequences <- function(sequences, k) {
  stopifnot(k >= 1L, k <= sequences$max_len)
  list(
    key = sequences$key,
    x = sequences$x[, seq_len(k), , drop = FALSE],
    seq_len = as.integer(pmin(sequences$seq_len, k)),
    career_runs_prior = sequences$career_runs_prior,
    features = sequences$features,
    max_len = k
  )
}
