# p5_mlp.R
# Paper 5, rung 1 — the MLP control.
#
# Paper 3's 24 features, unchanged, scored by a multi-layer perceptron under
# the Plackett-Luce objective at k = 3. The point of the rung is that it
# should TIE with a linear scorer on the same information: paper 3 already
# showed the function class was not the binding constraint, so an MLP that
# beats or loses to a linear score on the same features is evidence about
# the implementation, not about horses.
#
# Weights are shared across horses. The scorer maps one runner's feature
# vector to one scalar; runners are coupled only through the per-race
# softmax denominator in the loss, so variable field sizes need nothing
# beyond masking.
#
# `{luz}` is installed and pinned per the paper-5 plan, but the training
# loop here is written directly against `{torch}`. The loss is race-grouped:
# a batch is a set of whole races, padded to that batch's widest field, and
# the loss reduces over races rather than rows. Writing that loop explicitly
# is easier to audit than fitting it into luz's callback API, and it is the
# same code path the encoder rungs will reuse.

#' The respecified rung-1 control feature set
#'
#' Paper 3's 24 features carry a TREE-SHAPED encoding: `pos_lag1_zero` and
#' `pos_lag2_zero` were dropped because a tree splits on the sentinel
#' directly. An MLP has no such property, and the P5-1a diagnostic put the
#' cost of that omission at 0.049 per race — a linear scorer on paper 2b's
#' 17 terms reproduced mlogit's optimum, while the same scorer on paper 3's
#' 24 did not.
#'
#' So the control is respecified as the same information, encoded for a
#' model that is not a tree: paper 2b's 17 terms, plus paper 3's four
#' going-affinity features and four course indicators. 25 columns.
#'
#' `stall_normalised` is included as of P5-1c. It is in paper 3's 24 and was
#' omitted from the P5-1b term list in error; the four course dummies alone
#' carry no draw information, so without it the control was short of paper 3
#' by exactly the draw.
#'
#' @format Character vector of length 26.
P5_CONTROL_TERMS <- c(
  # paper 2b's 17 terms, including the zero/nonzero companion indicators
  "pos_lag1_zero", "pos_lag1_nonzero", "pos_lag2_zero", "pos_lag2_nonzero",
  "age_diff", "days_LTO_log", "trainerSR", "sireSR", "jockeySR",
  "entire", "gelding", "cheekpieces", "rel_weight",
  "or_relative", "or_missing", "trainer_aw_premium", "has_wins",
  # paper 3's going-affinity block
  "going_runs_prior", "going_sr_shrunk", "going_sr_delta", "going_ordinal",
  # draw position, and the four course indicators
  "stall_normalised",
  "course_Kempton", "course_Lingfield", "course_Southwell",
  "course_Wolverhampton"
)

#' History-derived terms, for part B
#'
#' Recorded now so the decision is not relitigated later.
#' `pos_lag1_zero` and `pos_lag2_zero` are history summaries in exactly the
#' way `pos_lag1_nonzero` and `pos_lag2_nonzero` are: they summarise whether
#' a prior run exists. They therefore LEAVE in part B with the rest of the
#' hand-summarised history, and the encoder receives the raw sequence and
#' its length instead — which carries the same fact, since a sequence of
#' length zero is exactly "no prior run".
#'
#' @format Character vector.
P5_HISTORY_TERMS <- c(
  "pos_lag1_zero", "pos_lag1_nonzero", "pos_lag2_zero", "pos_lag2_nonzero",
  "days_LTO_log", "going_runs_prior", "going_sr_shrunk", "going_sr_delta",
  "has_wins", "trainerSR", "jockeySR", "sireSR"
)

#' Standardise a feature matrix on the fitting partition only
#'
#' Centring and scaling statistics come from the fitting rows and are then
#' applied unchanged to every partition, so no validation information
#' reaches the fitted model.
#'
#' NA HANDLING, AND IT IS A DEPARTURE FROM PAPER 3. Paper 3's going-affinity
#' columns are NA for a horse with no prior run on today's going, and
#' XGBoost routes missing values natively. An MLP has no such mechanism, so
#' after standardising, NA is set to zero — the fitting-partition mean. That
#' is imputation where paper 3 does something strictly better informed, and
#' it is a candidate explanation for any gap this rung finds. Recorded here
#' rather than buried in the report.
#'
#' A column that is constant on the fitting partition gets scale 1, leaving
#' it at zero rather than dividing by zero.
#'
#' @param x Numeric matrix, all rows.
#' @param fit_rows Integer indices of the fitting partition.
#' @return A list: `x` (standardised), `centre`, `scale`, `na_share`.
p5_standardise <- function(x, fit_rows) {
  centre <- apply(x[fit_rows, , drop = FALSE], 2, mean, na.rm = TRUE)
  scale <- apply(x[fit_rows, , drop = FALSE], 2, stats::sd, na.rm = TRUE)
  scale[!is.finite(scale) | scale < 1e-12] <- 1
  centre[!is.finite(centre)] <- 0

  na_share <- apply(x, 2, function(col) mean(is.na(col)))
  out <- sweep(sweep(x, 2, centre, "-"), 2, scale, "/")
  out[is.na(out)] <- 0

  list(x = out, centre = centre, scale = scale, na_share = na_share)
}

#' The nine declared configurations for rung 1
#'
#' Declared in full before any of them is scored, and selection is on
#' validation Plackett-Luce loss and nothing else. A 3x3 grid over layer
#' widths and learning rate; everything else is held fixed.
#'
#' @format A tibble of nine rows.
p5_mlp_configs <- function() {
  widths <- list(c(64L, 32L), c(128L, 64L), c(256L, 128L))
  lrs <- c(0.003, 0.001, 0.0003)
  grid <- expand.grid(width_i = seq_along(widths), lr_i = seq_along(lrs))
  tibble::tibble(
    config = seq_len(nrow(grid)),
    widths = widths[grid$width_i],
    width_label = vapply(widths[grid$width_i],
                         function(w) paste(w, collapse = "-"), character(1)),
    lr = lrs[grid$lr_i],
    dropout = 0.1,
    batch_races = 64L,
    max_epochs = 60L,
    weight_decay = 1e-5
  ) |>
    dplyr::arrange(width_label, dplyr::desc(lr)) |>
    dplyr::mutate(config = dplyr::row_number())
}

#' The remediation grid, run once after the declared nine
#'
#' The declared nine all overfit within about six epochs at their learning
#' rates, and none reached the refitted paper-2b baseline. The permitted
#' remediation varies learning rate, epochs, batching and layer widths, and
#' nothing else — not the loss, the features, the split, the metric or the
#' seed.
#'
#' Two of the six have NO hidden layer. That is layer width taken to its
#' degenerate case, and it is the diagnostic that matters: a linear scorer
#' trained through this loss and this loop is the same function class as the
#' conditional logit it is being compared against, so if it also loses, the
#' fault is in the data path or the loss rather than in MLP capacity.
#'
#' @format A tibble of six rows.
p5_mlp_configs_remediation <- function() {
  tibble::tibble(
    config = 1:6,
    widths = list(integer(0), integer(0), c(32L, 16L),
                  c(64L, 32L), c(64L, 32L), c(128L, 64L)),
    width_label = c("linear", "linear", "32-16", "64-32", "64-32", "128-64"),
    lr = c(1e-3, 3e-4, 3e-4, 1e-4, 3e-5, 1e-4),
    dropout = 0.1,
    batch_races = c(64L, 64L, 64L, 64L, 128L, 128L),
    max_epochs = 200L,
    weight_decay = 1e-5
  )
}

#' The rung-1 MLP grid at the equal selection budget (P5-1d)
#'
#' The same nine configurations as `p5_mlp_configs()` — the grid is not
#' re-declared, only its epoch allowance changes — run to 200 epochs rather
#' than 60. P5-1c compared an MLP selected over 9 x 60 = 540 evaluations
#' against a linear scorer selected over 1 x 200 = 200, and the minimum of
#' more noisy evaluations is lower for that reason alone. Both arms now get
#' 9 x 200.
#'
#' @format A tibble of nine rows.
p5_mlp_configs_equal_budget <- function() {
  p5_mlp_configs() |>
    dplyr::mutate(max_epochs = 200L)
}

#' The linear grid at the equal selection budget (P5-1d)
#'
#' Nine configurations, matching the MLP arm's count and its 200 epochs.
#' A linear scorer has no layer widths, so the MLP grid's second axis is
#' replaced by batch size — the other knob that changes the optimisation
#' path without changing the function class or the information available.
#'
#' Learning rates are the three specified: 1e-3, 3e-4, 1e-4. Batch sizes
#' span the range the MLP work has used — the declared grid holds 64 races
#' per batch and the P5-1a remediation pass used 64 and 128 — extended
#' downward to 32 so the three levels span the same fourfold range as the
#' MLP grid's widths (64-32 to 256-128), centred on the 64 the MLP grid
#' holds fixed.
#'
#' Dropout is carried for signature compatibility and does nothing: with no
#' hidden layer there is nothing between the input and the output to drop.
#'
#' @format A tibble of nine rows.
p5_linear_configs_equal_budget <- function() {
  lrs <- c(1e-3, 3e-4, 1e-4)
  batches <- c(32L, 64L, 128L)
  grid <- expand.grid(batch_i = seq_along(batches), lr_i = seq_along(lrs))
  tibble::tibble(
    config = seq_len(nrow(grid)),
    widths = list(integer(0)),
    width_label = "linear",
    lr = lrs[grid$lr_i],
    dropout = 0.1,
    batch_races = batches[grid$batch_i],
    max_epochs = 200L,
    weight_decay = 1e-5
  ) |>
    dplyr::arrange(batch_races, dplyr::desc(lr)) |>
    dplyr::mutate(config = dplyr::row_number())
}

#' Summarise a set of fitted runs as one selection table
#'
#' Best epoch, the loss at it, and the loss at the final epoch — the three
#' numbers that show whether a configuration peaked and then degraded or
#' converged and held.
#'
#' @param runs A list of `p5_fit_mlp()` results.
#' @param batch_races Optional batch size per run, for the linear grid where
#'   it is the varying axis.
#' @return A tibble ordered by best validation PL loss.
p5_run_table <- function(runs, batch_races = NULL) {
  purrr::imap(runs, function(r, i) {
    tibble::tibble(
      config = r$config,
      widths = r$width_label,
      lr = r$lr,
      batch_races = if (is.null(batch_races)) NA_integer_ else batch_races[[i]],
      best_val_pl_loss = r$best_val_loss,
      best_epoch = r$best_epoch,
      final_epoch_val_pl_loss = r$final_val_loss,
      degradation = r$final_val_loss - r$best_val_loss
    )
  }) |>
    purrr::list_rbind() |>
    dplyr::arrange(best_val_pl_loss)
}

#' The validation-slice scoring frame, shared by every arm
#'
#' Everything about a scored validation row that does not depend on which
#' arm produced the score: the finishing position, the over-round-adjusted
#' market probability, and the per-race `horse_ref`. Factored out of the
#' per-arm scoring targets, which previously carried three copies of it.
#'
#' @param key Validation `race_id`/`runner_id` in scoring row order.
#' @param qualifying_runners The series' runner table.
#' @return A tibble, one row per validation runner.
p5_val_base <- function(key, qualifying_runners) {
  sp <- qualifying_runners |>
    dplyr::select(race_id, runner_id, starting_price_decimal,
                  finish_position, amended_position, won)
  key |>
    dplyr::left_join(sp, by = c("race_id", "runner_id")) |>
    dplyr::mutate(
      finish_pos = dplyr::coalesce(amended_position, finish_position)
    ) |>
    dplyr::group_by(race_id) |>
    dplyr::mutate(
      horse_ref = dplyr::row_number(),
      implied = dplyr::if_else(
        !is.na(starting_price_decimal) & starting_price_decimal > 1,
        1 / starting_price_decimal, NA_real_
      ),
      win_market = implied / sum(implied, na.rm = TRUE)
    ) |>
    dplyr::ungroup()
}

#' Attach one arm's per-race softmax win probabilities to the base frame
#'
#' @param base Output of `p5_val_base()`.
#' @param z Latent scores in the same row order.
#' @param key The same key `base` was built from.
#' @return `base` with a `win_model` column.
p5_attach_scores <- function(base, z, key) {
  sm <- pl_softmax_by_race(z, key$race_id, key$runner_id)
  dplyr::bind_cols(base, dplyr::select(
    dplyr::rename(sm, win_model = p_win), win_model))
}

#' Reduce a scored arm to the per-race ranking metrics
#'
#' @param scored Output of `p5_attach_scores()`.
#' @param scorable_ids Races both arms can be scored on.
#' @return The per-race metric tibble `bootstrap_ranking_metrics()` consumes.
p5_per_race_metrics <- function(scored, scorable_ids) {
  scored |>
    dplyr::filter(race_id %in% scorable_ids) |>
    dplyr::mutate(placed = as.integer(!is.na(finish_pos) &
                                        finish_pos %in% 1:3)) |>
    dplyr::select(race_id, horse_ref, won, win_model, win_market,
                  finish_pos, placed) |>
    build_ranking_per_race("win_model")
}

#' The MLP scorer
#'
#' @param n_features Input width.
#' @param widths Integer vector of hidden layer widths.
#' @param dropout Dropout probability between hidden layers.
#' @return A `torch::nn_module` mapping `[n, n_features]` to `[n]`.
p5_mlp_module <- function(n_features, widths, dropout) {
  layers <- list()
  prev <- n_features
  for (w in widths) {
    layers <- c(layers, list(torch::nn_linear(prev, w), torch::nn_relu(),
                             torch::nn_dropout(dropout)))
    prev <- w
  }
  layers <- c(layers, list(torch::nn_linear(prev, 1)))
  do.call(torch::nn_sequential, layers)
}

#' Score every row of a matrix with a fitted module
#'
#' @param module A fitted `nn_module`.
#' @param x Standardised numeric matrix.
#' @return Numeric vector of scores, one per row.
p5_predict_scores <- function(module, x) {
  module$eval()
  with_no_grad_scores <- torch::with_no_grad({
    module(torch::torch_tensor(x, dtype = torch::torch_float64()))$view(-1)
  })
  as.numeric(with_no_grad_scores)
}

#' Plackett-Luce loss of a score vector, as a plain number
#'
#' @param z Numeric scores in flat row order.
#' @param group_sizes Field sizes.
#' @param k Objective depth.
#' @return Mean negative log-likelihood per race.
p5_pl_loss_value <- function(z, group_sizes, k = 3L) {
  as.numeric(p5_pl_nll_torch(z, group_sizes, k)$item()) / length(group_sizes)
}

#' Fit one MLP configuration
#'
#' Trains on the fitting partition, evaluating the validation Plackett-Luce
#' loss after every epoch and keeping the parameters from the best epoch.
#' Epoch selection is on validation PL loss and nothing else.
#'
#' @param x_fit,x_val Standardised feature matrices.
#' @param gs_fit,gs_val Field sizes, race order, matching the row order.
#' @param config One row of `p5_mlp_configs()`.
#' @param seed Integer seed, set for both R and torch.
#' @param k Objective depth.
#' @return A list with the best validation loss, the epoch it came from, the
#'   per-epoch trace, and the validation scores at that epoch.
p5_fit_mlp <- function(x_fit, x_val, gs_fit, gs_val, config, seed = 42L,
                       k = 3L) {
  set.seed(seed)
  torch::torch_manual_seed(seed)

  module <- p5_mlp_module(ncol(x_fit), config$widths[[1]], config$dropout)
  module$to(dtype = torch::torch_float64())
  optim <- torch::optim_adam(module$parameters, lr = config$lr,
                             weight_decay = config$weight_decay)

  x_fit_t <- torch::torch_tensor(x_fit, dtype = torch::torch_float64())
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
      z <- module(x_fit_t[b$rows, ])$view(-1)
      padded <- p5_scatter_scores(z, masks[[bi]])
      loss <- p5_pl_nll_tensor(padded, masks[[bi]]$valid, masks[[bi]]$stage)
      loss$backward()
      optim$step()
    }

    val_scores <- p5_predict_scores(module, x_val)
    val_loss <- p5_pl_loss_value(val_scores, gs_val, k)
    trace[epoch] <- val_loss
    if (is.finite(val_loss) && val_loss < best$loss) {
      best <- list(loss = val_loss, epoch = epoch, scores = val_scores)
    }
  }

  list(
    config = config$config,
    width_label = config$width_label,
    lr = config$lr,
    best_val_loss = best$loss,
    best_epoch = best$epoch,
    final_val_loss = trace[config$max_epochs],
    trace = trace,
    val_scores = best$scores
  )
}
