# p5_embed.R
# Paper 5, rung 2 — entity embeddings.
#
# ONE CHANGE FROM RUNG 1. `trainerSR`, `jockeySR` and `sireSR` come out of
# the feature set and are replaced by learned embeddings on `trainer_id`,
# `jockey_id` and `sire_id`. Everything else is rung 1's arm unchanged: the
# same 23 remaining terms, the same MLP scorer, the same Plackett-Luce
# objective at k = 3, the same validation slice, the same seed, and the same
# nine-configuration grid.
#
# The arms must differ in exactly one respect. Rung 1 took four attempts
# because three of them compared arms differing in two ways at once — a
# feature encoding AND a function class, then a function class AND eight
# extra features, then a function class AND a selection budget. The
# term-by-term difference here is stated in `p5_rung2_term_list()` below
# and asserted in the pipeline.
#
# SPARSITY, FIXED BEFORE FITTING. A minimum-runner threshold per entity,
# everything below it mapped to a single shared bucket. The vocabulary is
# frozen on the FITTING partition, never the training split: deriving it
# from rows the model is scored on would let the validation slice decide
# model structure.

#' The three terms the embeddings replace
#'
#' @format Character vector of length 3.
P5_RUNG2_DROPPED <- c("trainerSR", "jockeySR", "sireSR")

#' Rung 2's dense feature set
#'
#' Rung 1's 26 terms less the three strike rates the embeddings replace.
#' Derived from the control terms rather than retyped, so the two lists
#' cannot drift apart.
#'
#' A FUNCTION, NOT A CONSTANT, and deliberately. Files under `R/` are
#' `source()`d in alphabetical order, so a top-level `setdiff(P5_CONTROL_TERMS,
#' ...)` here would evaluate before `p5_mlp.R` had defined its right-hand
#' side and break the bare `tar_source()` in `_targets.R`. Nothing in this
#' file may depend on another file's load order.
#'
#' @param control_terms Rung 1's term vector.
#' @return Character vector of length 23.
p5_rung2_term_list <- function(control_terms = P5_CONTROL_TERMS) {
  setdiff(control_terms, P5_RUNG2_DROPPED)
}

#' The entities that get embeddings
#'
#' @format Character vector of length 3.
P5_ENTITY_COLS <- c("trainer_id", "jockey_id", "sire_id")

#' Minimum runners for an entity to get its own embedding
#'
#' Twenty, one value for all three entities. Chosen from the training-split
#' distribution of runners per entity and fixed before any fit:
#'
#' \itemize{
#'   \item Twenty runs is about two full fields, and at the roughly 9% base
#'     win rate about 1.8 wins — the point at which an entity has five times
#'     as many observations as its embedding has parameters.
#'   \item It sits above the median run count for all three entities
#'     (trainer 14, jockey 5, sire 7 on the fitting partition), so the
#'     vocabulary is a minority of entities but a large majority of rows,
#'     which is what a frequency threshold should do to a tail this long.
#'   \item It leaves the shared bucket at 6.3% of fitting rows for trainer,
#'     4.4% for jockey and 14.6% for sire.
#' }
#'
#' One threshold rather than three: tuning three on validation loss would be
#' selection dressed as a design choice.
P5_EMBED_MIN_RUNS <- 20L

#' Embedding dimension
#'
#' Four, the same for all three entities. `295^0.25 = 4.1`, so the standard
#' fourth-root-of-cardinality heuristic lands here. It costs 3,540 embedding
#' parameters against 32,296 fitting rows — already about one parameter per
#' nine rows — and eight would double that on 3,517 fitting races.
P5_EMBED_DIM <- 4L

#' Bucket index for a rare or unseen entity
#'
#' Index 1 in every entity's vocabulary. Torch's `nn_embedding()` in R takes
#' 1-based indices, so the vocabulary runs 1..(n_kept + 1) with 1 reserved.
P5_EMBED_BUCKET <- 1L

#' Freeze an entity vocabulary on the fitting partition
#'
#' Entities with at least `min_runs` fitting rows get their own index;
#' everything else — rare in fitting, or absent from it entirely — maps to
#' the shared bucket at index 1.
#'
#' @param fit_ids Entity ids of the fitting rows.
#' @param min_runs Minimum fitting rows for an entity's own index.
#' @return A list: `lookup` (named integer vector, id -> index), `size`
#'   (vocabulary size including the bucket), `n_kept`, `min_runs`.
p5_entity_vocab <- function(fit_ids, min_runs = P5_EMBED_MIN_RUNS) {
  counts <- table(fit_ids[!is.na(fit_ids)])
  kept <- names(counts)[counts >= min_runs]
  lookup <- stats::setNames(seq_along(kept) + 1L, kept)
  list(lookup = lookup, size = length(kept) + 1L, n_kept = length(kept),
       min_runs = min_runs)
}

#' Map entity ids to vocabulary indices
#'
#' @param ids Entity ids.
#' @param vocab Output of `p5_entity_vocab()`.
#' @return Integer vector, `P5_EMBED_BUCKET` where the id is rare, unseen or
#'   NA.
p5_entity_index <- function(ids, vocab) {
  idx <- unname(vocab$lookup[as.character(ids)])
  idx[is.na(idx)] <- P5_EMBED_BUCKET
  as.integer(idx)
}

#' Build the rung-2 index matrix and its vocabularies
#'
#' @param fit_rows,val_rows Tibbles carrying the entity id columns, in the
#'   scoring row order.
#' @param entities Entity column names.
#' @param min_runs Threshold passed to `p5_entity_vocab()`.
#' @return A list: `fit`, `val` (integer matrices `[n, n_entities]`),
#'   `vocabs`, and a `summary` tibble for the report.
p5_build_entity_indices <- function(fit_rows, val_rows,
                                    entities = P5_ENTITY_COLS,
                                    min_runs = P5_EMBED_MIN_RUNS) {
  vocabs <- purrr::map(entities, function(e) {
    p5_entity_vocab(fit_rows[[e]], min_runs)
  })
  names(vocabs) <- entities

  idx_of <- function(rows) {
    m <- vapply(entities, function(e) p5_entity_index(rows[[e]], vocabs[[e]]),
                integer(nrow(rows)))
    matrix(as.integer(m), nrow = nrow(rows), ncol = length(entities),
           dimnames = list(NULL, entities))
  }
  fit_idx <- idx_of(fit_rows)
  val_idx <- idx_of(val_rows)

  summary <- tibble::tibble(
    entity = entities,
    n_distinct_fit = purrr::map_int(entities,
                                    ~ dplyr::n_distinct(fit_rows[[.x]])),
    vocab_size = purrr::map_int(vocabs, "size"),
    n_kept = purrr::map_int(vocabs, "n_kept"),
    pct_fit_bucket = purrr::map_dbl(
      entities, ~ round(100 * mean(fit_idx[, .x] == P5_EMBED_BUCKET), 2)),
    pct_val_bucket = purrr::map_dbl(
      entities, ~ round(100 * mean(val_idx[, .x] == P5_EMBED_BUCKET), 2)),
    pct_val_unseen = purrr::map_dbl(
      entities,
      ~ round(100 * mean(!(val_rows[[.x]] %in% unique(fit_rows[[.x]]))), 2))
  )

  list(fit = fit_idx, val = val_idx, vocabs = vocabs, summary = summary,
       entities = entities, min_runs = min_runs)
}

#' The rung-2 scorer: entity embeddings concatenated onto the dense terms
#'
#' The MLP stack is `p5_mlp_module()` — rung 1's scorer, unchanged — sitting
#' on a wider input. Nothing about the hidden layers, the activation or the
#' dropout differs.
#'
#' @param n_dense Number of dense columns.
#' @param vocab_sizes Integer vector of vocabulary sizes, one per entity.
#' @param embed_dim Embedding dimension.
#' @param widths Hidden layer widths.
#' @param dropout Dropout probability.
#' @return A `torch::nn_module` mapping (dense, indices) to one score a row.
p5_embed_module <- torch::nn_module(
  "p5_embed_scorer",
  initialize = function(n_dense, vocab_sizes, embed_dim, widths, dropout) {
    self$embeddings <- torch::nn_module_list(
      purrr::map(vocab_sizes, function(v) torch::nn_embedding(v, embed_dim))
    )
    self$mlp <- p5_mlp_module(
      n_dense + embed_dim * length(vocab_sizes), widths, dropout
    )
  },
  forward = function(x_dense, idx) {
    parts <- vector("list", length(self$embeddings) + 1L)
    parts[[1]] <- x_dense
    for (i in seq_along(self$embeddings)) {
      parts[[i + 1L]] <- self$embeddings[[i]](idx[, i])
    }
    self$mlp(torch::torch_cat(parts, dim = 2))
  }
)

#' Score every row with a fitted embedding scorer
#'
#' @param module A fitted `p5_embed_module`.
#' @param x Standardised dense matrix.
#' @param idx Integer index matrix.
#' @return Numeric vector of scores, one per row.
p5_predict_embed_scores <- function(module, x, idx) {
  module$eval()
  out <- torch::with_no_grad({
    module(
      torch::torch_tensor(x, dtype = torch::torch_float64()),
      torch::torch_tensor(idx, dtype = torch::torch_long())
    )$view(-1)
  })
  as.numeric(out)
}

#' Fit one rung-2 configuration
#'
#' `p5_fit_mlp()` with two inputs instead of one. The training loop, the
#' batching, the seeding, the optimiser, the per-epoch validation scoring and
#' the best-epoch selection are identical — selection is on validation
#' Plackett-Luce loss and nothing else.
#'
#' @param x_fit,x_val Standardised dense matrices.
#' @param idx_fit,idx_val Integer entity index matrices.
#' @param vocab_sizes Vocabulary sizes, one per entity.
#' @param gs_fit,gs_val Field sizes, race order, matching the row order.
#' @param config One row of `p5_mlp_configs_equal_budget()`.
#' @param embed_dim Embedding dimension.
#' @param seed Integer seed, set for both R and torch.
#' @param k Objective depth.
#' @return The same shape `p5_fit_mlp()` returns.
p5_fit_embed_mlp <- function(x_fit, x_val, idx_fit, idx_val, vocab_sizes,
                             gs_fit, gs_val, config,
                             embed_dim = P5_EMBED_DIM, seed = 42L, k = 3L) {
  set.seed(seed)
  torch::torch_manual_seed(seed)

  module <- p5_embed_module(ncol(x_fit), vocab_sizes, embed_dim,
                            config$widths[[1]], config$dropout)
  module$to(dtype = torch::torch_float64())
  optim <- torch::optim_adam(module$parameters, lr = config$lr,
                             weight_decay = config$weight_decay)

  x_fit_t <- torch::torch_tensor(x_fit, dtype = torch::torch_float64())
  idx_fit_t <- torch::torch_tensor(idx_fit, dtype = torch::torch_long())
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
      z <- module(x_fit_t[b$rows, ], idx_fit_t[b$rows, ])$view(-1)
      padded <- p5_scatter_scores(z, masks[[bi]])
      loss <- p5_pl_nll_tensor(padded, masks[[bi]]$valid, masks[[bi]]$stage)
      loss$backward()
      optim$step()
    }

    val_scores <- p5_predict_embed_scores(module, x_val, idx_val)
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
