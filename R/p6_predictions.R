# p6_predictions.R
# Paper 6 — the training-split predictions of paper 5's encoder.
#
# Paper 6 changes no model. It needs paper 5's rung-3b encoder scored on the
# TRAINING split, and paper 5 never stored that: `p5_fit_final_gru()` returns
# the scores of the one matrix it is handed, and paper 5 handed it the test
# matrix.
#
# The fit is therefore repeated — with paper 5's own function, its own stored
# configuration, its own epoch count and its own seed — twice: once scoring the
# test matrix, once scoring the training matrix. Training is fully determined
# by the seed and the data, and `x_score` is only read after the last gradient
# step, so both calls train the identical module. The first call's scores are
# asserted BIT-IDENTICAL to paper 5's stored `p5_test_fit_rung3b$scores`; that
# assertion is what licenses reading the second call's training scores as
# coming from the same model.
#
# Nothing here writes to the paper-5 store, and no paper-5 target is rebuilt.

#' Refit paper 5's rung-3b encoder and score both splits
#'
#' @param test_data The `p5_test_data` target: matrices, sequences, lengths and
#'   race-group sizes for both splits, on paper 3's key order.
#' @param configs The `p5_configs_v7` target.
#' @param selected The `p5_rung3b_selected` target (config index and epoch).
#' @param stored_test_scores `p5_test_fit_rung3b$scores`, the reproduction
#'   target.
#' @param seed,k Seed and objective depth, paper 5's values.
#' @return A list: `train_scores`, `test_scores`, `max_abs_test_diff`, the
#'   configuration echoed back, and the backend both fits ran on.
p6_refit_rung3b_both_splits <- function(test_data, configs, selected,
                                        stored_test_scores, seed = 42L,
                                        k = 3L) {
  cfg <- configs[selected$config, ]
  epochs <- selected$best_epoch

  fit_test <- p5_fit_final_gru(
    test_data$rung3b$train, test_data$seq_train, test_data$len_train,
    test_data$gs_train,
    test_data$rung3b$test, test_data$seq_test, test_data$len_test,
    cfg, epochs = epochs, seed = seed, k = k
  )

  d <- max(abs(fit_test$scores - stored_test_scores))
  if (!identical(fit_test$scores, stored_test_scores)) {
    stop(sprintf(
      paste("Paper 6's refit of rung 3b did not reproduce paper 5's stored",
            "test scores (max |diff| = %.3e). The training scores cannot be",
            "attributed to paper 5's model; stop."),
      d
    ))
  }

  fit_train <- p5_fit_final_gru(
    test_data$rung3b$train, test_data$seq_train, test_data$len_train,
    test_data$gs_train,
    test_data$rung3b$train, test_data$seq_train, test_data$len_train,
    cfg, epochs = epochs, seed = seed, k = k
  )

  list(
    train_scores = fit_train$scores,
    test_scores = fit_test$scores,
    max_abs_test_diff = d,
    config = selected$config,
    label = cfg$label,
    epochs = epochs,
    n_train_rows = nrow(test_data$rung3b$train),
    n_train_races = length(test_data$gs_train),
    backend = fit_train$backend
  )
}

#' The market side of the training split
#'
#' The same construction `build_test_predictions()` uses on the test split:
#' the raw starting-price-implied probability renormalised within race over the
#' runners the pipeline actually uses. A runner with no usable price gets NA
#' and is dropped downstream by `p6_build_bet_frame()`; the rest of its race
#' is renormalised over the prices that are there, exactly as on test.
#'
#' `horse_ref` is a within-race index over the frame's own key order. It is a
#' join key only — every consumer (the Harville place recursion included)
#' works on the rows of a race, not on the labels — so it need only be a
#' bijection within a race, which `row_number()` guarantees.
#'
#' @param key The `p5_gbt_train_data$key` tibble: `race_id`, `runner_id`.
#' @param qualifying_runners The series' runner table.
#' @return A `test_predictions_2b`-shaped tibble without the model column.
p6_train_market <- function(key, qualifying_runners) {
  # `won` is the series' own column, not a re-derivation: it already encodes
  # the promoted-winner coalesce and treats a non-finisher as a loser rather
  # than as missing.
  lookup <- qualifying_runners |>
    dplyr::transmute(race_id, runner_id, starting_price_decimal,
                     won = as.integer(won))

  out <- key |>
    dplyr::left_join(lookup, by = c("race_id", "runner_id")) |>
    dplyr::group_by(race_id) |>
    dplyr::mutate(
      horse_ref = dplyr::row_number(),
      implied_raw = dplyr::if_else(
        !is.na(starting_price_decimal) & starting_price_decimal > 1,
        1 / starting_price_decimal, NA_real_
      ),
      win_market = implied_raw / sum(implied_raw, na.rm = TRUE)
    ) |>
    dplyr::ungroup() |>
    dplyr::select(race_id, runner_id, horse_ref, won, win_market,
                  starting_price_decimal)

  stopifnot(nrow(out) == nrow(key), !anyNA(out$won))
  out
}

#' Assert the search set is the training split and nothing else
#'
#' Row identity as a sorted set on (race_id, runner_id) against paper 5's own
#' training frame, and zero overlap with the test race ids. A blocker in the
#' paper-6 brief, so it is an assertion rather than a report.
#'
#' @param frame The training-split `p6_build_bet_frame()` output.
#' @param train_key,test_key Paper 5's stored key tibbles.
#' @return A one-row tibble of the counts checked.
p6_assert_search_set <- function(frame, train_key, test_key) {
  fk <- sort(paste(frame$race_id, frame$runner_id))
  tk <- sort(paste(train_key$race_id, train_key$runner_id))
  dropped <- setdiff(tk, fk)
  overlap <- intersect(unique(frame$race_id), unique(test_key$race_id))

  stopifnot(
    length(setdiff(fk, tk)) == 0L,   # nothing outside paper 5's training frame
    length(overlap) == 0L            # nothing from the test split
  )

  tibble::tibble(
    n_rows_p5_train   = nrow(train_key),
    n_races_p5_train  = dplyr::n_distinct(train_key$race_id),
    n_rows_frame      = nrow(frame),
    n_races_frame     = dplyr::n_distinct(frame$race_id),
    n_rows_dropped    = length(dropped),
    n_test_overlap    = length(overlap)
  )
}
