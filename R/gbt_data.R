# gbt_data.R
# Paper-3 GBT feature matrix + race grouping for the custom Plackett-Luce
# objective (R/pl_objective.R). Feature list is paper 2b's final term set
# (model_2b_exploded_draw_final, 20 terms) with two encoding artefacts a
# tree does not need substituted for their underlying raw variables, plus
# the four going-affinity columns.

#' Paper-3 GBT design-matrix columns (post-substitution)
#'
#' Starting point: `model_2b_exploded_draw_final`'s 20 terms (verified via
#' `names(coef(model_2b_exploded_draw_final))`: `pos_lag1_zero`,
#' `pos_lag1_nonzero`, `pos_lag2_zero`, `pos_lag2_nonzero` — lag 3 did not
#' survive paper 2's reduction — `age_diff`, `days_LTO_log`, `trainerSR`,
#' `sireSR`, `jockeySR`, `entire`, `gelding`, `cheekpieces`, `rel_weight`,
#' `or_relative`, `or_missing`, `trainer_aw_premium`, `has_wins`,
#' `stall_x_kempton`, `stall_x_southwell`, `stall_x_wolverhampton`).
#'
#' Two substitutions applied (both are pure conditional-logit encoding
#' workarounds a tree does not need):
#' \itemize{
#'   \item `pos_lag{1,2}_zero` / `pos_lag{1,2}_nonzero` (4 columns) ->
#'     `pos_lag{1,2}_nonzero` alone (2 columns). The zero/nonzero split
#'     exists only so a LINEAR predictor can avoid conflating "no prior
#'     run" (coded 0) with a real graded finish position on the same
#'     numeric scale; a tree splits on `pos_lagN_nonzero == 0` directly,
#'     no separate indicator required.
#'   \item `stall_x_kempton` / `stall_x_southwell` / `stall_x_wolverhampton`
#'     (the per-course draw-interaction block, 3 columns; Lingfield was
#'     already dropped by 2b's own per-term Wald reduction) ->
#'     `stall_normalised` plus one-hot `course_<Course>` for all FOUR AW
#'     courses (5 columns). The interaction block exists only because a
#'     conditional logit cannot use a race-level covariate (course)
#'     without crossing it with a horse-level one to survive the softmax;
#'     a tree finds a course-specific draw effect on its own (paper 3's
#'     §3 thesis: interactions found rather than specified), and is not
#'     restricted to the 3 courses 2b's linear reduction happened to keep.
#' }
#'
#' Two further cases were considered and deliberately left unsubstituted
#' (kept as 2b's own form) — see CLAUDE.md "Paper 3 plan" for the reasoning
#' behind each:
#' \itemize{
#'   \item `or_relative` (0-imputed) / `or_missing` (companion flag). Unlike
#'     the position-lag pair, this is not PURELY an encoding artefact of
#'     `{mlogit}`'s inability to handle NA — CLAUDE.md's "Settled keep
#'     decisions" frames the companion flag as a deliberate
#'     missing-not-at-random handling strategy in its own right, not just a
#'     workaround. Genuinely ambiguous whether a tree should get the same
#'     treatment as the going-affinity columns (native missing routing, no
#'     impute/flag) or keep 2b's form; kept as 2b's form rather than
#'     deciding unilaterally.
#'   \item `days_LTO_log`. A tree is invariant to a monotonic transform of
#'     a single feature (a split on `log(x) < c` is identical to a split on
#'     `x < exp(c)`), so the log transform is inert for the fitted model's
#'     predictions either way. Left as the log form for direct scale
#'     comparability with 2b's training McFadden pseudo-R^2 in the
#'     progression table, and because this is a mild feature-engineering
#'     choice, not the kind of categorical-encoding artefact the brief
#'     asked about.
#' }
#'
#' Plus the four paper-3 going-affinity columns (`R/build_going_features.R`).
#'
#' @format Character vector, 24 columns.
FEATURE_COLS <- c(
  "pos_lag1_nonzero", "pos_lag2_nonzero",
  "age_diff", "days_LTO_log", "trainerSR", "sireSR", "jockeySR",
  "entire", "gelding", "cheekpieces",
  "rel_weight", "or_relative", "or_missing",
  "trainer_aw_premium", "has_wins",
  "stall_normalised",
  "course_Kempton", "course_Lingfield", "course_Southwell", "course_Wolverhampton",
  "going_runs_prior", "going_sr_shrunk", "going_sr_delta", "going_ordinal"
)

#' Build the paper-3 GBT feature matrix and race grouping for one split
#'
#' Race universe is paper 2b's own complete-case set: this function
#' rebuilds it internally via `prepare_exploded_data()` with the SAME
#' draw-interaction `extra_na_vars` `exploded_interactions_data` uses, so
#' paper 3 scores exactly the races `model_2b_exploded_draw_final` was
#' fitted/evaluated on (verified: 5,022 training races) — required for the
#' paired race-level ROI bootstrap against 2b (CLAUDE.md "frozen for
#' comparability"). Going-affinity NA does not affect this set (the
#' going_* columns are never in the NA-drop variable list); a going-NA
#' runner still contributes a row, with NA in the four going columns,
#' routed by XGBoost's native missing-value handling.
#'
#' Rows are ordered via `arrange_for_xgb()` (R/pl_objective.R) — every
#' caller of the PL objective must go through it; this is the one place in
#' the pipeline that does.
#'
#' Construction assertions (all `stopifnot()`): row count equals the sum of
#' `group_sizes`; group count equals the number of distinct races (no race
#' split across two blocks); within each race block, the first
#' `S = min(3, J - 1)` rows carry `finish_pos` `1, 2, ..., S` in that
#' order — i.e. `arrange_for_xgb()`'s ordering contract actually holds on
#' this data, not just in principle.
#'
#' @param runners_interactions Tibble from the `runners_interactions`
#'   target (`runners_model_ready` + `build_interaction_features()`, which
#'   itself sits on `runners_augmented` + `going_features`). Carries every
#'   raw column `FEATURE_COLS` needs: `pos_lag{1,2}_nonzero`, `or_missing`,
#'   `split`, `course`, `stall_normalised`, and the going-affinity columns.
#'   *(The brief's signature was `prepare_gbt_data(runners_augmented,
#'   split)`. Renamed/expanded here because `runners_augmented` alone
#'   lacks `course`, `pos_lag*`, `or_missing` and `split` — those are added
#'   downstream by `build_model_ready()` / `build_interaction_features()`;
#'   re-deriving them inside this file would duplicate existing pipeline
#'   logic rather than reuse it.)*
#' @param qualifying_runners Tibble from the `qualifying_runners` target.
#'   Supplies `finish_position` / `amended_position`, needed both by
#'   `prepare_exploded_data()` (to derive the complete-case race universe)
#'   and by `arrange_for_xgb()` (the finishing-position sort). *(Not in the
#'   brief's two-argument signature; added because the complete-case
#'   universe can't be derived without it — see roxygen above.)*
#' @param split Character, `"train"` or `"test"`. This build only calls it
#'   with `"train"` (per "nothing in this prompt may touch the test
#'   split") — the `"test"` path is implemented for the later results
#'   prompt but not exercised or verified here.
#' @return A list: `X` (plain numeric matrix, `FEATURE_COLS` columns, in
#'   `arrange_for_xgb()` order — deliberately NOT wrapped in an
#'   `xgb.DMatrix` here, so callers doing cross-validation can slice fold
#'   subsets with ordinary matrix indexing; `{xgboost}` does not support
#'   slicing a DMatrix that already has group info attached, see
#'   `prepare_gbt_data()`), `y` (numeric vector, `won`, matching row
#'   order), `group_sizes` (integer vector, per-race field sizes in `X`
#'   row order), `feature_names` (`FEATURE_COLS`), `key` (tibble,
#'   `race_id`, `runner_id`, one row per `X` row, matching row order).
build_gbt_matrix <- function(runners_interactions, qualifying_runners, split) {
  split_rows <- runners_interactions |> dplyr::filter(.data$split == .env$split)

  exploded_check <- prepare_exploded_data(
    split_rows |>
      dplyr::left_join(
        dplyr::select(qualifying_runners, race_id, runner_id, finish_position, amended_position),
        by = c("race_id", "runner_id")
      ),
    extra_na_vars = c("rel_weight_x_dist", "stall_x_kempton", "stall_x_lingfield",
                       "stall_x_southwell", "stall_x_wolverhampton")
  )
  df_check <- as.data.frame(exploded_check)
  class(df_check) <- "data.frame"
  attr(df_check, "index")    <- NULL
  attr(df_check, "clseries") <- NULL
  complete_case_race_ids <- unique(df_check$race_id)

  if (identical(split, "train")) {
    stopifnot(length(complete_case_race_ids) == 5022L)
  }

  ordered <- split_rows |>
    dplyr::filter(race_id %in% complete_case_race_ids) |>
    dplyr::left_join(
      dplyr::select(qualifying_runners, race_id, runner_id, finish_position, amended_position),
      by = c("race_id", "runner_id")
    ) |>
    dplyr::mutate(finish_pos = dplyr::coalesce(amended_position, finish_position)) |>
    arrange_for_xgb()

  group_sizes <- rle(as.character(ordered$race_id))$lengths
  stopifnot(sum(group_sizes) == nrow(ordered))
  stopifnot(length(group_sizes) == dplyr::n_distinct(ordered$race_id))

  check <- ordered |>
    dplyr::mutate(J = rep.int(group_sizes, group_sizes)) |>
    dplyr::group_by(race_id) |>
    dplyr::mutate(pos_in_block = dplyr::row_number(), S = pmin(3L, J - 1L)) |>
    dplyr::ungroup() |>
    dplyr::filter(pos_in_block <= S)
  stopifnot(all(check$finish_pos == check$pos_in_block))

  X <- ordered |>
    dplyr::mutate(
      course_Kempton       = as.numeric(course == "Kempton"),
      course_Lingfield     = as.numeric(course == "Lingfield"),
      course_Southwell     = as.numeric(course == "Southwell"),
      course_Wolverhampton = as.numeric(course == "Wolverhampton")
    ) |>
    dplyr::select(dplyr::all_of(FEATURE_COLS)) |>
    as.matrix()

  list(
    X             = X,
    y             = ordered$won,
    group_sizes   = group_sizes,
    feature_names = FEATURE_COLS,
    key           = dplyr::select(ordered, race_id, runner_id)
  )
}

#' Build the paper-3 GBT feature matrix and race grouping for one split
#'
#' Thin wrapper around `build_gbt_matrix()` that additionally constructs
#' the `xgb.DMatrix` and attaches group info — the form a single (non-CV)
#' fit needs. Cross-validation callers that need to slice fold subsets
#' should call `build_gbt_matrix()` directly instead: `{xgboost}` does not
#' support slicing a DMatrix that already has group info set
#' (`xgb.slice.DMatrix` errors: "slice does not support group structure"),
#' so per-fold DMatrices must be constructed fresh from sliced `X`/`y`
#' rather than sliced from an already-grouped parent DMatrix.
#'
#' @inheritParams build_gbt_matrix
#' @return A list: `dtrain` (an `xgboost::xgb.DMatrix`, group info
#'   already attached), `group_sizes`, `feature_names`, `key` — see
#'   `build_gbt_matrix()`.
prepare_gbt_data <- function(runners_interactions, qualifying_runners, split) {
  built <- build_gbt_matrix(runners_interactions, qualifying_runners, split)

  dtrain <- xgboost::xgb.DMatrix(data = built$X, label = built$y)
  xgboost::setinfo(dtrain, "group", built$group_sizes)

  list(
    dtrain        = dtrain,
    group_sizes   = built$group_sizes,
    feature_names = built$feature_names,
    key           = built$key
  )
}
