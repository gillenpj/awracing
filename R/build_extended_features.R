# build_extended_features.R
# Paper-2 candidate features. Three pure builders, each keyed by
# (race_id, runner_id), that are joined onto paper 1's `features`
# tibble to form the single `runners_augmented` target. None of them
# touch paper 1's feature path, so the replication fit is unaffected.
#
# Every feature here is computed on a strictly pre-race basis: any
# history-derived quantity uses runs strictly before the qualifying
# race's meeting_date (`hist_date < qualifying_date`), never the race
# itself and never future runs. This mirrors the leakage rule already
# enforced in build_strike_rates() and build_position_lags().

#' Build jockey strike rate and the trainer/sire/jockey AW premiums
#'
#' Adds the jockey analogue of Owen's trainerSR / sireSR, plus three
#' "AW premium" features measuring how much better (or worse) an
#' entity performs on All-Weather than across all surfaces.
#'
#' \describe{
#'   \item{`jockeySR`}{Cumulative pre-race win rate of the horse's
#'     jockey, computed exactly as `trainerSR` / `sireSR` in
#'     build_strike_rates(): the jockey's cumulative wins / races at
#'     the latest entity-day strictly before the race date. NA when
#'     the jockey has no prior runs (debut), never 0 — the same
#'     strict-no-leakage convention as the trainer/sire rates.
#'
#'     **No cap is applied.** The brief asked to cap jockeySR "at the
#'     same percentile used for trainerSR/sireSR", but those two
#'     features are themselves raw / uncapped in this pipeline
#'     (build_strike_rates() returns them unwinsorised; any capping is
#'     deferred downstream). jockeySR follows the same raw convention
#'     so all three strike rates remain directly comparable. If a cap
#'     is wanted later it should be applied uniformly to all three at
#'     the modelling stage.}
#'   \item{`trainer_aw_premium`, `sire_aw_premium`,
#'     `jockey_aw_premium`}{Entity's cumulative AW win rate minus its
#'     cumulative overall win rate, both measured strictly pre-race.
#'     Set to 0 when the entity has no prior AW runs.
#'
#'     **Limitation — zero/missing conflation.** A 0 premium means
#'     either "no AW history yet" or "AW rate exactly equals overall
#'     rate". These are not distinguished, the same zero/missing
#'     conflation already noted for the SR features in CLAUDE.md. We
#'     use 0 (not NA) here because the brief specifies it and because
#'     a premium of 0 — "no evidence of an AW-specific edge" — is the
#'     natural neutral value for a difference feature. AW runs are a
#'     subset of all runs, so whenever AW history exists the overall
#'     rate exists too; both rate terms are therefore non-NA whenever
#'     the premium is non-zero.}
#' }
#'
#' @param qualifying_runners Tibble from the qualifying_runners target.
#'   Supplies (race_id, runner_id, trainer_id, sire_id, jockey_id).
#' @param qualifying_races Tibble from the qualifying_races target.
#'   Joined on race_id for `meeting_date` (the race date).
#' @param trainer_sire_cumulative Tibble from the
#'   trainer_sire_cumulative target. Columns: kind, entity_id,
#'   meeting_date, wins_thru_date, races_thru_date, aw_wins_thru_date,
#'   aw_races_thru_date.
#' @return Tibble keyed by (race_id, runner_id) with numeric columns
#'   jockeySR, trainer_aw_premium, sire_aw_premium, jockey_aw_premium.
build_jockey_sr_and_premiums <- function(qualifying_runners,
                                         qualifying_races,
                                         trainer_sire_cumulative) {
  spine <- qualifying_runners |>
    dplyr::select(race_id, runner_id, trainer_id, sire_id, jockey_id) |>
    dplyr::inner_join(
      dplyr::select(qualifying_races, race_id, qualifying_date = meeting_date),
      by = "race_id"
    )

  # Cast the cumulative counts to double: RMariaDB returns SQL BIGINT
  # (COUNT/SUM) as integer64, and {bit64} overloads `/` to integer
  # division (10/100 -> 0), which would silently corrupt the rates.
  prep_kind <- function(k) {
    trainer_sire_cumulative |>
      dplyr::filter(kind == k) |>
      dplyr::transmute(
        entity_id,
        result_date = meeting_date,
        wins     = as.numeric(wins_thru_date),
        races    = as.numeric(races_thru_date),
        aw_wins  = as.numeric(aw_wins_thru_date),
        aw_races = as.numeric(aw_races_thru_date)
      )
  }

  # For one entity kind: closest cumulative row strictly before the
  # race date, then the strike rate (wins/races; NA if no prior runs)
  # and the AW premium (AW rate minus overall rate; 0 if no prior AW
  # runs). `id_col` is the spine column holding this kind's id.
  sr_and_premium <- function(id_col, cum) {
    spine |>
      dplyr::transmute(
        race_id, runner_id,
        entity_id = .data[[id_col]],
        qualifying_date
      ) |>
      dplyr::left_join(
        cum,
        by = dplyr::join_by(entity_id, closest(qualifying_date > result_date))
      ) |>
      dplyr::transmute(
        race_id,
        runner_id,
        sr = wins / races,
        premium = dplyr::if_else(
          !is.na(aw_races) & aw_races > 0,
          (aw_wins / aw_races) - (wins / races),
          0
        )
      )
  }

  jockey  <- sr_and_premium("jockey_id",  prep_kind("jockey"))
  trainer <- sr_and_premium("trainer_id", prep_kind("trainer"))
  sire    <- sr_and_premium("sire_id",    prep_kind("sire"))

  jockey |>
    dplyr::transmute(
      race_id, runner_id,
      jockeySR          = sr,
      jockey_aw_premium = premium
    ) |>
    dplyr::left_join(
      dplyr::transmute(trainer, race_id, runner_id, trainer_aw_premium = premium),
      by = c("race_id", "runner_id")
    ) |>
    dplyr::left_join(
      dplyr::transmute(sire, race_id, runner_id, sire_aw_premium = premium),
      by = c("race_id", "runner_id")
    )
}

#' Build within-race relative features (stall, weight, official rating)
#'
#' Three features that position a runner relative to its own field.
#' All are computed within the race from the qualifying runners, so no
#' history and no leakage are involved.
#'
#' \describe{
#'   \item{`stall_normalised`}{`stall_number / field_size`, where
#'     field_size is the number of (post-Non-Runner) starters in the
#'     race. NA when `stall_number` is NULL — some races have no draw
#'     recorded (e.g. certain Wolverhampton configurations); these are
#'     left NA and not imputed.}
#'   \item{`rel_weight`}{`weight_pounds` minus the race-mean
#'     `weight_pounds` over the field. A direct readout of the
#'     handicapper's within-race weight assessment.}
#'   \item{`or_relative`}{`official_rating` minus the race-mean
#'     `official_rating` over the field. NA when the runner's own
#'     official rating is NULL — left NA, not imputed with the race
#'     mean (which would spuriously read as 0, i.e. "exactly average").}
#' }
#'
#' Race means are taken with `na.rm = TRUE` so a single missing weight
#' or rating does not blank the whole field's relative values.
#'
#' @param qualifying_runners Tibble from the qualifying_runners target.
#'   Supplies (race_id, runner_id, stall_number, weight_pounds,
#'   official_rating).
#' @return Tibble keyed by (race_id, runner_id) with numeric columns
#'   stall_normalised, rel_weight, or_relative.
build_within_race_features <- function(qualifying_runners) {
  qualifying_runners |>
    dplyr::group_by(race_id) |>
    dplyr::mutate(
      field_size       = dplyr::n(),
      race_mean_weight = mean(weight_pounds, na.rm = TRUE),
      race_mean_or     = mean(official_rating, na.rm = TRUE)
    ) |>
    dplyr::ungroup() |>
    dplyr::transmute(
      race_id,
      runner_id,
      stall_normalised = dplyr::if_else(
        is.na(stall_number),
        NA_real_,
        stall_number / field_size
      ),
      rel_weight  = weight_pounds - race_mean_weight,
      or_relative = official_rating - race_mean_or
    )
}

#' Build career-form lag features (class / weight deltas, AW + win flags)
#'
#' Four features derived from each horse's full cross-surface career
#' history, using the same most-recent-prior-run lag logic as
#' build_position_lags(): group by runner_id, keep runs strictly
#' before the qualifying race date, order by date.
#'
#' \describe{
#'   \item{`class_delta`}{`class_today - class_LTO`, where class_LTO is
#'     the race class of the horse's immediately preceding run on any
#'     surface. Smartform class runs 1 (highest) to 7, so a positive
#'     delta = dropping in class, negative = stepping up. NA when the
#'     horse has no prior run in the comparable-class era.
#'
#'     **Class-era floor.** The LTO lookup is restricted to runs on or
#'     after `class_era_floor` (default 2006-01-01). Pre-2006 Smartform
#'     class codes are multi-digit (11, 42, 53, 64, ...) and not
#'     comparable with the 2006+ 1-7 scheme (CLAUDE.md data-scope
#'     decision); an un-floored pre-2006 class_LTO produces nonsense
#'     deltas (e.g. 5 - 64 = -59). Both LTO values below are taken from
#'     the same physical race, so the two deltas refer to one "last
#'     time out".}
#'   \item{`weight_delta_lbs`}{`weight_today - weight_LTO` in pounds,
#'     from the same immediately-preceding (era-floored) run as
#'     class_LTO. NA when no prior run in the comparable era. Weight in
#'     pounds is itself comparable across the 2006 boundary; it shares
#'     the floor only so both deltas describe the same race.}
#'   \item{`first_time_aw`}{Integer 0/1; 1 if the horse has no prior
#'     All-Weather start before this race (i.e. today is its AW debut),
#'     0 otherwise. Based on full cross-surface history, consistent
#'     with extract_career_history().}
#'   \item{`has_wins`}{Integer 0/1; 1 if the horse has at least one
#'     win in any prior run before this race, 0 otherwise.}
#' }
#'
#' Note on the deltas' NA semantics: a horse with no prior run gets NA
#' (not 0) for class_delta and weight_delta_lbs — 0 would falsely read
#' as "same class / same weight as last time" for a horse that has no
#' last time. The binary flags instead resolve a no-history horse to
#' the informative value (first_time_aw = 1, has_wins = 0).
#'
#' @param qualifying_runners Tibble from the qualifying_runners target.
#'   Supplies (race_id, runner_id, weight_pounds) for "today".
#' @param full_history Tibble from the full_history target. Source of
#'   prior runs: `meeting_date` for ordering, `unfinished` to drop
#'   Non-Runners, `class` / `weight_pounds` for the lagged values,
#'   `race_type` for the AW flag, and
#'   `coalesce(amended_position, finish_position)` for prior wins.
#' @param qualifying_races Tibble from the qualifying_races target.
#'   Joined on race_id to supply the qualifying date and today's class.
#' @param class_era_floor Date (or "YYYY-MM-DD") from which class codes
#'   are comparable; the class/weight LTO lookup ignores runs before
#'   it. Defaults to "2006-01-01", the British class-system
#'   restructure and the project's `date_from`.
#' @return Tibble keyed by (race_id, runner_id) with columns
#'   class_delta (integer, NA-bearing), weight_delta_lbs (integer,
#'   NA-bearing), first_time_aw (integer 0/1), has_wins (integer 0/1).
build_career_form_features <- function(qualifying_runners,
                                       full_history,
                                       qualifying_races,
                                       class_era_floor = "2006-01-01") {
  class_era_floor <- as.Date(class_era_floor)

  spine <- qualifying_runners |>
    dplyr::select(race_id, runner_id, weight_today = weight_pounds) |>
    dplyr::inner_join(
      dplyr::select(
        qualifying_races,
        race_id,
        qualifying_date = meeting_date,
        class_today     = class
      ),
      by = "race_id"
    )

  history <- full_history |>
    dplyr::filter(is.na(unfinished) | unfinished != "Non-Runner") |>
    dplyr::transmute(
      runner_id,
      hist_date   = meeting_date,
      hist_class  = class,
      hist_weight = weight_pounds,
      hist_is_aw  = race_type == "All Weather Flat",
      hist_won    = dplyr::coalesce(amended_position, finish_position) == 1L
    )

  # All of a runner's runs strictly before its qualifying race.
  joined <- spine |>
    dplyr::select(race_id, runner_id, qualifying_date) |>
    dplyr::inner_join(history, by = "runner_id", relationship = "many-to-many") |>
    dplyr::filter(hist_date < qualifying_date)

  # LTO class / weight from the most recent prior run *in the
  # comparable-class era* (>= class_era_floor). The floor keeps a
  # pre-2006 multi-digit class code from leaking into class_delta; both
  # values come from the same race so the deltas share one "last time
  # out".
  prior_lto <- joined |>
    dplyr::filter(hist_date >= class_era_floor) |>
    dplyr::group_by(race_id, runner_id) |>
    dplyr::arrange(dplyr::desc(hist_date), .by_group = TRUE) |>
    dplyr::summarise(
      class_LTO  = dplyr::first(hist_class),
      weight_LTO = dplyr::first(hist_weight),
      .groups = "drop"
    )

  # Career flags use the *full* cross-surface history (no date floor):
  # whether a horse ever ran AW or ever won is valid pre-2006 too.
  prior_flags <- joined |>
    dplyr::group_by(race_id, runner_id) |>
    dplyr::summarise(
      any_aw_prior  = any(hist_is_aw, na.rm = TRUE),
      any_win_prior = any(hist_won,  na.rm = TRUE),
      .groups = "drop"
    )

  spine |>
    dplyr::left_join(prior_lto,   by = c("race_id", "runner_id")) |>
    dplyr::left_join(prior_flags, by = c("race_id", "runner_id")) |>
    dplyr::transmute(
      race_id,
      runner_id,
      class_delta      = class_today  - class_LTO,   # NA if no prior era run
      weight_delta_lbs = weight_today - weight_LTO,  # NA if no prior era run
      first_time_aw    = dplyr::if_else(dplyr::coalesce(any_aw_prior,  FALSE), 0L, 1L),
      has_wins         = dplyr::if_else(dplyr::coalesce(any_win_prior, FALSE), 1L, 0L)
    )
}

#' Assemble the paper-2 modelling-ready runner tibble
#'
#' Applies the settled paper-2 data decisions to `runners_augmented` so
#' that every downstream paper-2 modelling target consumes one canonical
#' tibble (rather than `runners_augmented` directly):
#'
#' \describe{
#'   \item{`or_missing`}{Integer 0/1 companion to `or_relative`: 1 where
#'     the official rating was NULL (i.e. `or_relative` was NA *before*
#'     imputation), else 0. Computed before the imputation below so it
#'     records the genuine missingness.}
#'   \item{`or_relative`}{NA imputed to 0, paired with `or_missing`.
#'     Official ratings are missing-not-at-random — unrated horses
#'     (unexposed, or returning from a long absence) are a distinct
#'     population, not a random sample. Imputing 0 with the companion
#'     indicator lets the model estimate the missing-OR group effect
#'     separately instead of forcing those horses onto the zero point of
#'     the `or_relative` scale, and recovers full coverage at no cost to
#'     race count.}
#'   \item{`race_date`, `split`}{The race's `meeting_date` and its 70/30
#'     chronological split label ("train"/"test"), so exploratory and
#'     modelling code can restrict to the training split (see CLAUDE.md
#'     "Exploratory analysis convention") without re-deriving the cut.
#'     `split` is taken from membership in `races_train`, so it is
#'     identical to the pipeline's race-level split by construction.}
#'   \item{`pos_lagN_zero` / `pos_lagN_nonzero` (N = 1,2,3)}{The paper-2
#'     Model-S position encoding, derived from paper 1's `position1/2/3`
#'     factors: per lag a zero indicator (1 if the lag position is 0) and
#'     the graded raw position (1--4, else 0). These six columns replace
#'     the three factor columns in all paper-2 model formulas; the factor
#'     columns remain in the tibble for paper-1 compatibility but are not
#'     used by paper 2. See CLAUDE.md "Paper 2 feature decisions" item B
#'     for the LR test that settled this encoding.}
#' }
#'
#' All other columns pass through unchanged. The settled feature *drops*
#' are applied at model-formula time (variable selection), not by
#' removing columns here.
#'
#' @param runners_augmented Tibble from the `runners_augmented` target.
#' @param qualifying_races Tibble from the `qualifying_races` target;
#'   supplies `meeting_date` (surfaced as `race_date`) per race.
#' @param races_train Tibble from the `races_train` target; its
#'   `race_id`s define the training split.
#' @return `runners_augmented` plus `or_missing`, an imputed
#'   `or_relative`, `race_date`, `split`, and the six Model-S position
#'   columns `pos_lag{1,2,3}_{zero,nonzero}`.
build_model_ready <- function(runners_augmented, qualifying_races, races_train) {
  runners_augmented |>
    dplyr::left_join(
      dplyr::select(qualifying_races, race_id, race_date = meeting_date),
      by = "race_id"
    ) |>
    dplyr::mutate(
      or_missing  = as.integer(is.na(or_relative)),       # before imputation
      or_relative = dplyr::coalesce(or_relative, 0),       # impute NULL OR -> 0
      split       = dplyr::if_else(
        race_id %in% races_train$race_id, "train", "test"
      ),
      # Paper-2 Model-S position encoding (CLAUDE.md feature decision B):
      # per lag, the graded raw position (1-4, else 0) and a zero
      # indicator, derived from paper 1's position1/2/3 factors. These
      # replace the factors in paper-2 formulas; the factors remain for
      # paper-1 compatibility.
      pos_lag1_nonzero = as.integer(as.character(position1)),
      pos_lag2_nonzero = as.integer(as.character(position2)),
      pos_lag3_nonzero = as.integer(as.character(position3)),
      pos_lag1_zero    = as.integer(pos_lag1_nonzero == 0L),
      pos_lag2_zero    = as.integer(pos_lag2_nonzero == 0L),
      pos_lag3_zero    = as.integer(pos_lag3_nonzero == 0L)
    )
}

#' Build the paper-2 mixed-logit interaction features
#'
#' Race-level features cannot enter a conditional logit directly — they
#' are constant within a race and cancel in the softmax. They enter only
#' as interactions with horse-level features, which vary across runners
#' within a race (the mixed discrete-choice mechanism in
#' notes/paper2_seed_mixed_choice.md). This augments `runners_model_ready`
#' with two such interactions:
#'
#' \describe{
#'   \item{`rel_weight_x_dist`}{`rel_weight` (horse-level) times
#'     `distance_furlongs` (race-level, `distance_yards / 220`). Motivated
#'     by @benter1994: the burden of extra weight compounds over longer
#'     trips. Never NA (`rel_weight` and distance are always present).}
#'   \item{`stall_x_kempton` / `_lingfield` / `_southwell` /
#'     `_wolverhampton`}{`stall_normalised` masked to one course each
#'     (`stall_normalised * 1{course == C}`), giving a per-course draw
#'     slope. Draw bias is known to vary by AW course. Where
#'     `stall_normalised` is NA (no draw recorded) the product is NA in
#'     **all four** columns, so the whole race is dropped downstream —
#'     the same rule as `stall_normalised` itself.}
#' }
#'
#' `distance_furlongs` and `course` are joined from the races target and
#' are race-level; a `stopifnot` asserts `distance_furlongs` is constant
#' within each race. All other columns pass through unchanged.
#'
#' @param runners_model_ready Tibble from the `runners_model_ready`
#'   target (carries `rel_weight`, `stall_normalised`, `race_id`).
#' @param races Tibble from the `qualifying_races` target; supplies
#'   `course` and `distance_yards` per race.
#' @return `runners_model_ready` plus `distance_furlongs`, `course`,
#'   `rel_weight_x_dist`, and the four `stall_x_<course>` columns.
build_interaction_features <- function(runners_model_ready, races) {
  race_info <- races |>
    dplyr::transmute(
      race_id,
      course,
      distance_furlongs = distance_yards / 220   # 1 furlong = 220 yards
    )

  out <- runners_model_ready |>
    dplyr::left_join(race_info, by = "race_id") |>
    dplyr::mutate(
      rel_weight_x_dist     = rel_weight * distance_furlongs,
      # Multiplicative masking: NA stall_normalised -> NA in all four,
      # so a draw-less runner drops its whole race (same as stall_normalised).
      stall_x_kempton       = stall_normalised * as.integer(course == "Kempton"),
      stall_x_lingfield     = stall_normalised * as.integer(course == "Lingfield"),
      stall_x_southwell     = stall_normalised * as.integer(course == "Southwell"),
      stall_x_wolverhampton = stall_normalised * as.integer(course == "Wolverhampton")
    )

  dist_check <- out |>
    dplyr::group_by(race_id) |>
    dplyr::summarise(nd = dplyr::n_distinct(distance_furlongs), .groups = "drop")
  stopifnot(all(dist_check$nd == 1L))

  out
}
