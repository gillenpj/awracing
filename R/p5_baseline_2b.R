# p5_baseline_2b.R
# Paper 5, rung 1 — the paper-2b baseline, refitted.
#
# WHY REFIT RATHER THAN USE PAPER 2B'S PUBLISHED FIT. Paper 2b was fitted on
# the whole training split, and this paper's validation slice is carved out
# of that same training split. Scoring 2b's published model on the
# validation slice would therefore be IN-SAMPLE for 2b and OUT-OF-SAMPLE for
# the MLP, which biases the comparison toward 2b and would make a "the MLP
# loses" reading meaningless.
#
# So paper 2b's exploded conditional logit is refitted on the fitting
# partition alone and scored on the validation slice, exactly as the MLP is.
# Same rows, same races, same objective, same scoring path. What differs is
# the function class, which is the point of the rung.
#
# This is 2b's BASE exploded specification — `fit_exploded_model()`, the
# term set from `model_p2_reduced` — not 2b's published draw-interaction
# model. The draw-interaction fit carries its own per-term Wald reduction,
# and re-running a selection procedure inside a refit would add a moving
# part that has nothing to do with the question being asked here.

#' Refit paper 2b's exploded conditional logit on a set of races
#'
#' @param runners The paper-3 modelling frame's runner rows
#'   (`runners_interactions`), carrying every term the model needs.
#' @param qualifying_runners Supplies the finishing positions the explosion
#'   needs.
#' @param fit_race_ids Races to fit on.
#' @param model_p2_reduced Paper 2's reduced fit, supplying the term set.
#' @param k Explosion depth; 3, as in papers 2b and 3.
#' @return A list: the fitted model, its coefficients, and the term names.
p5_fit_2b_baseline <- function(runners, qualifying_runners, fit_race_ids,
                               model_p2_reduced, k = 3L) {
  loadNamespace("mlogit")

  fit_rows <- runners |>
    dplyr::filter(race_id %in% fit_race_ids) |>
    dplyr::left_join(
      dplyr::select(qualifying_runners, race_id, runner_id,
                    finish_position, amended_position),
      by = c("race_id", "runner_id")
    )

  exploded <- prepare_exploded_data(fit_rows, k = k)
  fitted <- fit_exploded_model(exploded, model_p2_reduced)

  list(
    model = fitted,
    coefs = stats::coef(fitted),
    terms = names(stats::coef(fitted)),
    n_fit_races = dplyr::n_distinct(fit_rows$race_id)
  )
}

#' Score rows with the refitted conditional logit's linear predictor
#'
#' The exploded conditional logit's latent score is exactly the linear
#' predictor, and its win probabilities are the per-race softmax of that
#' score — the same transformation the MLP's scores go through. Computing it
#' directly, rather than through `mlogit::predict()`, keeps both arms on one
#' scoring path and avoids rebuilding an `mlogit` design matrix for the
#' validation races.
#'
#' @param baseline Output of `p5_fit_2b_baseline()`.
#' @param rows A tibble carrying every term in `baseline$terms`, in the row
#'   order the scores are wanted in.
#' @return Numeric vector of latent scores.
p5_score_2b_baseline <- function(baseline, rows) {
  missing <- setdiff(baseline$terms, names(rows))
  if (length(missing)) {
    stop("rows lack terms the refitted 2b model needs: ",
         paste(missing, collapse = ", "))
  }
  x <- as.matrix(rows[, baseline$terms, drop = FALSE])
  # An NA term would propagate to the whole race's softmax. The conditional
  # logit was fitted on complete cases by construction (prepare_exploded_data
  # drops them), so this asserts rather than imputes.
  stopifnot(!anyNA(x))
  as.numeric(x %*% baseline$coefs)
}
