# build_going_features.R
# Paper-3 going-affinity feature: how a horse has performed on today's kind
# of going (fast/standard/slow, defined WITHIN surface), shrunk toward its
# own overall career win rate. Deferred from paper 2 by design (CLAUDE.md
# "Going interaction — deferred to paper 3"): going is a race-level feature
# that cancels in the conditional-logit softmax unless interacted with a
# horse-level affinity measure, and building that interaction required the
# cumulative-history sub-query this file provides. A gradient-boosted tree
# takes it as an ordinary raw feature, no interaction term required.
#
# Vocabulary audit (2026-08-19, this session): every distinct `going`
# string over the full cross-surface career-history universe (486,055 rows,
# 17,376 horses) and over `qualifying_races` (7,441 races) was enumerated.
# 16 raw strings survive after collapsing pure formatting variants (" - "
# vs " to "), all 16 map cleanly onto `going_ordinal` below — zero unmapped
# strings (0% of career rows with a non-NULL going).

#' Normalise a raw `going` string to a lookup key
#'
#' Collapses formatting variants observed in the Smartform `going` column
#' (e.g. "Good to Firm" and "Good - Firm" both denote the same going, and
#' both are present in this database) to one canonical lowercase
#' "<term> to <term>" string: trims, lowercases, and rewrites hyphen
#' separators (with or without surrounding spaces) to " to ".
#'
#' No watered / dead / other qualifier suffixes (e.g. "Good (watered)")
#' were found anywhere in the audited vocabulary — every one of the 16
#' distinct raw strings is a bare going term or a two-term range. This
#' function therefore does not strip such qualifiers; if a future data
#' pull introduces one, it will surface as an unmapped string (via the
#' `going_ordinal` lookup returning NA) rather than being silently folded
#' into a base going, consistent with "unmapped strings map to NA, never
#' silently to a default".
#'
#' @param x Character vector of raw going strings (`NA` passes through).
#' @return Character vector, normalised.
normalize_going <- function(x) {
  x |>
    stringr::str_trim() |>
    stringr::str_to_lower() |>
    stringr::str_replace_all("\\s*-\\s*", " to ") |>
    stringr::str_squish()
}

#' Canonical going-string to numeric-ordinal lookup (fast to slow)
#'
#' One common numeric axis across every going term observed in the
#' project's full career-history universe (AW, turf flat, hurdle, chase,
#' NH flat), keyed by the normalised string from `normalize_going()`, so a
#' tree has a single splitting variable rather than one per going category.
#'
#' Adjusted from the originally suggested anchor scale to the vocabulary
#' actually present in this database:
#' \itemize{
#'   \item{Dropped: "Fast" (2), "Sloppy" (7), "Muddy" (7) — never appear.
#'     These are US dirt-track terms; this database is UK racing only.}
#'   \item{Added: "yielding to soft" at 5.5 — a real, non-trivial category
#'     (212 career-history rows) the original anchor list omitted. Placed
#'     the same way "soft to heavy" already sits at 6.5, interpolated
#'     between its two flanking terms (yielding = 5, soft = 6).}
#' }
#' Every other anchor is unchanged from the brief.
#'
#' @format Named numeric vector, name = `normalize_going()`-normalised
#'   going string, value = ordinal (1 = fastest/firmest, 7 = slowest).
going_ordinal <- c(
  "hard"             = 1,
  "firm"             = 2,
  "good to firm"     = 3,
  "standard to fast" = 3,
  "good"             = 4,
  "standard"         = 4,
  "good to yielding" = 4.5,
  "yielding"         = 5,
  "good to soft"     = 5,
  "standard to slow" = 5,
  "yielding to soft" = 5.5,
  "soft"             = 6,
  "slow"             = 6,
  "soft to heavy"    = 6.5,
  "heavy"            = 7
)

#' Surface -> going-ordinal -> FAST/STANDARD/SLOW bucket lookup
#'
#' `going_bucket` is defined WITHIN surface because AW "Standard" and turf
#' "Good" sit in the middle of different distributions of going. "Surface"
#' is two-valued: `"AW"` (`race_type == "All Weather Flat"`) vs `"Turf"`
#' (Flat, Hurdle, Chase, National Hunt Flat pooled) — going is a
#' course/date-level ground condition, not race-type-specific, so every
#' turf race type at a meeting shares one going report and belongs in one
#' pooled turf population for this cut.
#'
#' Cut points are the empirical terciles (1/3, 2/3 quantiles, R's default
#' type-7 interpolation) of `going_ordinal` over every career-history row
#' with a non-NULL going, computed separately per surface (audited
#' 2026-08-19 against 486,055 career-history rows):
#' \itemize{
#'   \item{AW (n = 171,520): q(1/3) = q(2/3) = 4 ("Standard"). AW going is
#'     98.4% "Standard" — the surface is engineered for day-to-day
#'     consistency — so the volume terciles collapse onto a single
#'     ordinal value. The resulting split (FAST 0.7% / STANDARD 98.8% /
#'     SLOW 0.5%) is the honest answer for this surface, not a defect of
#'     the cut rule.}
#'   \item{Turf (n = 313,101): q(1/3) = 3 ("Good to Firm"), q(2/3) = 4
#'     ("Good" / "Standard"). Split: FAST 2.9% / STANDARD 65.5% /
#'     SLOW 31.6%.}
#' }
#' Bucket assignment: FAST if `going_ordinal < q(1/3)`; STANDARD if
#' `q(1/3) <= going_ordinal <= q(2/3)`; SLOW if `going_ordinal > q(2/3)`.
#'
#' The cut points are frozen as literals here (like the project's AW
#' course list or date-window constants) rather than recomputed from
#' `full_history` inside `build_going_features()` on every pipeline run,
#' so the feature definition does not silently drift if the underlying
#' career-history universe changes on a future data refresh.
#'
#' @format Tibble: `surface` ("AW"/"Turf"), `going_ordinal` (numeric, every
#'   value appearing in `going_ordinal` above), `going_bucket` (character,
#'   "FAST"/"STANDARD"/"SLOW").
going_bucket <- {
  cut_points <- tibble::tribble(
    ~surface, ~q1, ~q2,
    "AW",     4,   4,
    "Turf",   3,   4
  )
  tidyr::expand_grid(
    surface       = c("AW", "Turf"),
    going_ordinal = sort(unique(unname(going_ordinal)))
  ) |>
    dplyr::left_join(cut_points, by = "surface") |>
    dplyr::mutate(
      going_bucket = dplyr::case_when(
        going_ordinal < q1  ~ "FAST",
        going_ordinal <= q2 ~ "STANDARD",
        TRUE                ~ "SLOW"
      )
    ) |>
    dplyr::select(surface, going_ordinal, going_bucket)
}

#' Shrinkage prior weight for `going_sr_shrunk`
#'
#' A judgement call, not derived from the data — flagged here to be
#' sensitivity-checked later (e.g. re-running the win-rate-by-
#' `going_sr_delta`-decile diagnostic in `scripts/verify_going_features.R`
#' at m = 3 and m = 10 and confirming the ranking is stable).
GOING_SHRINKAGE_M <- 5

#' Build the going-affinity features
#'
#' Four columns on the runner grain, all derived from each horse's full
#' cross-surface career history (per the project's standing data-scope
#' decision), using runs strictly before today's race date (STRICT BEFORE
#' — same-date runs excluded entirely, matching the `trainerSR` /
#' `jockeySR` / `sireSR` convention: `hist_date < qualifying_date`, never
#' `<=`):
#'
#' \describe{
#'   \item{`going_runs_prior`}{Count of the horse's prior career runs whose
#'     OWN going bucket (computed within THAT run's surface) matches
#'     today's going bucket (computed within AW, since every qualifying
#'     race is All-Weather). A turf "Good" run counts toward the STANDARD
#'     bucket and an AW "Standard" run does too, because both are labelled
#'     STANDARD by their own surface's cut points — this is what lets
#'     turf history count as relevant exposure for an AW race today.}
#'   \item{`going_sr_shrunk`}{The horse's win rate in that bucket, shrunk
#'     toward its own overall (any-bucket, any-surface) prior win rate
#'     `career_sr` with prior weight `m` (`GOING_SHRINKAGE_M`):
#'     `(wins_bucket + m * career_sr) / (runs_bucket + m)`.}
#'   \item{`going_sr_delta`}{`going_sr_shrunk` minus `career_sr`. This is
#'     the column that isolates going affinity from general ability — the
#'     raw bucket rate would partly proxy what `or_relative` already
#'     carries, since a generally better horse wins more in every bucket.}
#'   \item{`going_ordinal`}{Today's race going on the common
#'     `going_ordinal` axis. Race-level, constant within race. Unlike in
#'     the conditional logit it does not cancel here, and it is what a
#'     first split conditions on. The 11 `qualifying_races` rows (0.15%)
#'     with a NULL going are imputed to 4 ("Standard"), AW's modal going
#'     by a wide margin (98.4% of AW race-days) — a race-level default,
#'     distinct from the never-impute rule below, which concerns the
#'     ABSENCE OF PRIOR RUNS, not the absence of a recorded going on
#'     today's own race. `going_ordinal` is therefore always defined.}
#' }
#'
#' NA semantics for the three horse-level columns (no zero-imputation, no
#' missing-indicator companion column):
#' \itemize{
#'   \item{Horse has SOME career history but none of it falls in today's
#'     bucket: `going_runs_prior = 0`, `going_sr_shrunk = NA`,
#'     `going_sr_delta = NA`. A genuine, informative zero — the horse has
#'     raced before, just never (yet) on this kind of going.}
#'   \item{Horse has NO career history at all (true debut): all three are
#'     `NA`, including `going_runs_prior` — distinguishing "never run in
#'     this going" from "never run at all" is itself information XGBoost
#'     can use its default-direction split routing on.}
#' }
#' No zero-imputation and no missing-indicator column are added for either
#' case. XGBoost learns a default routing direction per split from the
#' training data and sends every absent value that way together, so the
#' fact of absence is already available to the model as information in its
#' own right — a missing-indicator companion (the pattern used for
#' `or_relative` / `or_missing` in paper 2, where the modelling family
#' offers no native missing-value handling) would be redundant here.
#'
#' A historical run whose OWN going could not be mapped to an ordinal (a
#' NULL going on that specific past run) still counts toward `career_sr`'s
#' denominator (it is a real prior run, going-agnostic) but never
#' contributes to any bucket count (it cannot be known whether it matches
#' today's bucket).
#'
#' @param qualifying_runners Tibble from the `qualifying_runners` target.
#'   Supplies the (race_id, runner_id) spine.
#' @param qualifying_races Tibble from the `qualifying_races` target.
#'   Supplies `meeting_date` (today's date) and `going` (today's going) per
#'   race.
#' @param full_history Tibble from the `full_history` target. Must carry
#'   `going` (career-history race-level context; see
#'   `sql/horse_full_history.sql`) alongside `runner_id`, `meeting_date`,
#'   `race_type`, `finish_position`, `amended_position`, `unfinished`.
#' @return Tibble keyed by (race_id, runner_id) with columns
#'   `going_runs_prior` (integer, NA-bearing), `going_sr_shrunk` (double,
#'   NA-bearing), `going_sr_delta` (double, NA-bearing), `going_ordinal`
#'   (double, never NA).
build_going_features <- function(qualifying_runners, qualifying_races, full_history) {
  history_bucketed <- full_history |>
    dplyr::filter(is.na(unfinished) | unfinished != "Non-Runner") |>
    dplyr::transmute(
      runner_id,
      hist_date    = meeting_date,
      hist_won     = dplyr::coalesce(amended_position, finish_position) == 1L,
      hist_surface = dplyr::if_else(race_type == "All Weather Flat", "AW", "Turf"),
      hist_ordinal = unname(going_ordinal[normalize_going(going)])
    ) |>
    dplyr::left_join(
      going_bucket,
      by = c("hist_surface" = "surface", "hist_ordinal" = "going_ordinal")
    ) |>
    dplyr::rename(hist_bucket = going_bucket)

  race_today <- qualifying_races |>
    dplyr::transmute(
      race_id,
      qualifying_date   = meeting_date,
      today_ordinal_raw = unname(going_ordinal[normalize_going(going)])
    ) |>
    dplyr::mutate(
      # Race-level going.ordinal must always be defined; the rare NULL
      # (11 of 7,441 races) is imputed to AW's modal going. See roxygen.
      today_ordinal = dplyr::coalesce(today_ordinal_raw, 4)
    ) |>
    dplyr::left_join(
      going_bucket |> dplyr::filter(surface == "AW") |> dplyr::select(-surface),
      by = c("today_ordinal" = "going_ordinal")
    ) |>
    dplyr::rename(today_bucket = going_bucket) |>
    dplyr::select(race_id, qualifying_date, today_ordinal, today_bucket)

  spine <- qualifying_runners |>
    dplyr::select(race_id, runner_id) |>
    dplyr::left_join(race_today, by = "race_id")

  agg <- spine |>
    dplyr::select(race_id, runner_id, qualifying_date, today_bucket) |>
    dplyr::inner_join(history_bucketed, by = "runner_id", relationship = "many-to-many") |>
    dplyr::filter(hist_date < qualifying_date) |>
    dplyr::group_by(race_id, runner_id) |>
    dplyr::summarise(
      runs_prior_all = dplyr::n(),
      # na.rm = TRUE: hist_won is NA for a prior run with unresolved finish
      # position (e.g. "Fell" / "Pulled Up" / "Unseated Rider" -- excluded
      # from unfinished == "Non-Runner" above but has NULL finish_position
      # AND NULL amended_position), matching build_career_form_features()'s
      # any(hist_won, na.rm = TRUE) treatment of the same coalesce(). Such a
      # run counts toward runs_prior_all (it happened) but is treated as not
      # a win (the honest reading of "did not finish") rather than
      # propagating NA into every subsequent runner-race's career_sr.
      wins_prior_all = sum(hist_won, na.rm = TRUE),
      runs_bucket    = sum(hist_bucket == today_bucket, na.rm = TRUE),
      wins_bucket    = sum(hist_won & hist_bucket == today_bucket, na.rm = TRUE),
      .groups = "drop"
    )

  m <- GOING_SHRINKAGE_M

  spine |>
    dplyr::left_join(agg, by = c("race_id", "runner_id")) |>
    dplyr::mutate(
      career_sr        = wins_prior_all / runs_prior_all,
      going_runs_prior  = dplyr::if_else(
        is.na(runs_prior_all), NA_integer_, as.integer(runs_bucket)
      ),
      going_sr_shrunk   = dplyr::if_else(
        is.na(runs_prior_all) | runs_bucket == 0,
        NA_real_,
        (wins_bucket + m * career_sr) / (runs_bucket + m)
      ),
      going_sr_delta    = going_sr_shrunk - career_sr,
      going_ordinal     = today_ordinal
    ) |>
    dplyr::select(
      race_id, runner_id,
      going_runs_prior, going_sr_shrunk, going_sr_delta, going_ordinal
    )
}
