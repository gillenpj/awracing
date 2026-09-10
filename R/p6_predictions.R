# p6_predictions.R
# Paper 6 — the two prediction sets, and the assertions that pin them.
#
# TWO FITS OF ONE ARCHITECTURE, AND THEY ARE NOT THE SAME MODEL.
#
#   The SEARCH SET is paper 5's validation slice: 1,505 races carved out of
#   the training period at 2010-12-15, scored by the fit trained on the 3,517
#   fitting races only. That fit never saw the validation races, so its
#   probabilities there are out of sample — which is the whole point, and the
#   reason this paper's search set is not the training split.
#
#   The TEST SPLIT is scored by paper 5's full-training-split refit, the fit
#   paper 5 published. That is the model whose betting behaviour anyone would
#   actually deploy.
#
# Both are paper 5's own stored targets, read read-only. Paper 6 refits
# nothing. The consequence of using two fits is that their score
# distributions differ in scale, which is why every candidate threshold in
# this paper is a within-split quantile rather than an absolute number.
#
# The 3,517 fitting races are not used anywhere. The model memorised them.

#' The validation-slice search set, with its provenance asserted
#'
#' `p5_scored_v7` is paper 5's rung-3b arm scored on the validation slice by
#' the fitting-partition fit, with the series' own market-probability
#' construction already attached. It is taken as it stands; the assertions
#' below check it is what it is claimed to be before anything is searched on
#' it.
#'
#' @param scored The `p5_scored_v7` target.
#' @param selected The `p5_rung3b_selected` target, for the validation loss.
#' @param val_key The `p5_arm_data$val$key` tibble.
#' @param published_val_loss Paper 5's published rung-3b validation PL loss.
#' @param tol Absolute tolerance on that loss.
#' @return `scored`, renamed into the shape `p6_build_bet_frame()` expects.
p6_validation_predictions <- function(scored, selected, val_key,
                                      published_val_loss = 5.718496,
                                      tol = 5e-7) {
  d <- abs(selected$best_val_loss - published_val_loss)
  if (d > tol) {
    stop(sprintf(
      paste("Paper 5's stored rung-3b validation loss is %.6f, not the",
            "published %.6f (|diff| = %.3e). The search set cannot be",
            "attributed to the fit paper 5 selected; stop."),
      selected$best_val_loss, published_val_loss, d
    ))
  }

  stopifnot(
    nrow(scored) == nrow(val_key),
    identical(scored$race_id, val_key$race_id),
    identical(scored$runner_id, val_key$runner_id),
    length(selected$val_scores) == nrow(val_key)
  )

  scored |>
    dplyr::select(race_id, runner_id, horse_ref, won, win_model, win_market,
                  starting_price_decimal)
}

#' Assert the search set is the validation slice and nothing else
#'
#' Three blockers from the brief, as assertions rather than reports: row
#' identity against paper 5's validation key, zero overlap with the test
#' split, zero overlap with the 3,517 fitting races the model memorised.
#'
#' @param frame The validation-slice `p6_build_bet_frame()` output.
#' @param val_key Paper 5's validation key.
#' @param fit_race_ids The 3,517 fitting race ids (`p5_slice$fit_race_ids`).
#' @param test_key Paper 3's test key.
#' @return A one-row tibble of the counts checked.
p6_assert_search_set <- function(frame, val_key, fit_race_ids, test_key) {
  fk <- sort(paste(frame$race_id, frame$runner_id))
  vk <- sort(paste(val_key$race_id, val_key$runner_id))
  dropped <- setdiff(vk, fk)
  overlap_test <- intersect(unique(frame$race_id), unique(test_key$race_id))
  overlap_fit <- intersect(unique(frame$race_id), fit_race_ids)

  stopifnot(
    length(setdiff(fk, vk)) == 0L,   # nothing outside paper 5's val frame
    length(overlap_test) == 0L,      # nothing from the test split
    length(overlap_fit) == 0L        # nothing the model was fitted on
  )

  tibble::tibble(
    n_rows_p5_val    = nrow(val_key),
    n_races_p5_val   = dplyr::n_distinct(val_key$race_id),
    n_rows_frame     = nrow(frame),
    n_races_frame    = dplyr::n_distinct(frame$race_id),
    n_rows_dropped   = length(dropped),
    n_races_fit      = length(fit_race_ids),
    n_test_overlap   = length(overlap_test),
    n_fit_overlap    = length(overlap_fit)
  )
}

#' The two fits, side by side, for the paper's method section
#'
#' Descriptive. Records that the search set and the test split are scored by
#' different fits of the same architecture, and how much data each saw.
#'
#' @param selected The `p5_rung3b_selected` target (fitting-partition fit).
#' @param test_fit The `p5_test_fit_rung3b` target (full-training refit).
#' @param slice The `p5_slice` target.
#' @return A two-row tibble.
p6_fit_provenance <- function(selected, test_fit, slice) {
  tibble::tibble(
    fit = c("fitting partition", "full training split"),
    scores = c("validation slice (the search set)", "test split"),
    n_train_races = c(slice$n_races_fit, test_fit$n_train_races),
    n_train_rows = c(NA_integer_, test_fit$n_train_rows),
    config = c(selected$config, test_fit$config),
    epochs = c(selected$best_epoch, test_fit$epochs),
    val_pl_loss = c(selected$best_val_loss, NA_real_),
    source = c("p5_scored_v7 / p5_rung3b_selected", "p5_test_predictions")
  )
}
