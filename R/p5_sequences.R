# p5_sequences.R
# Paper 5 — per-horse prior-run sequences for the encoder arm.
#
# One vector per prior run, ordered most-recent-first, capped at the 20 most
# recent, padded to a fixed length with an explicit length carried alongside
# so the encoder can mask. Cross-surface and across every race code,
# consistent with the series' full-career-history convention.
#
# THE TEMPORAL BOUNDARY: strictly `meeting_date <` the race being predicted.
# Same rule as every other prior-run feature in the series.
#
# Built for the whole paper-3 frame, but rung 1 does not consume it — the
# MLP control scores paper 3's 24 tabular features. The sequences exist here
# so that rungs 2 and 3 have a verified input to build on.

#' Maximum prior runs carried in a sequence
#'
#' Twenty. Horses with longer careers lose their oldest runs from the
#' sequence, so `career_runs_prior` is carried as a separate scalar and
#' nothing about career length is lost.
P5_SEQ_MAX_LEN <- 20L

#' Sequence feature names, in channel order
#'
#' @format Character vector of length 8.
P5_SEQ_FEATURES <- c(
  "finish_pos", "beaten_dist", "beaten_missing", "going_ordinal",
  "class", "field_size", "distance_furlongs", "days_since_prev"
)

#' Fill value for an unavailable channel reading
#'
#' Outside the natural range of every channel that uses it, so a missing
#' entry is never confusable with a real one. Padding stays at 0 and is
#' masked by `seq_len`, so the two never collide.
#'
#' Winners are NOT filled on beaten distance: a winner is zero lengths
#' behind the winner, which is definitional rather than imputed.
P5_BEATEN_FILL <- -1

#' Channel cleaning bounds
#'
#' Established by inspecting the career-run universe (444,580 rows) rather
#' than assumed. See `P5_1a_REPORT.md` for what was found at each.
#' \itemize{
#'   \item{`class`: the 2006+ scheme runs 1-7. Values outside it are the
#'     pre-2006 multi-digit codes CLAUDE.md records as not comparable, and
#'     they are ENTIRELY pre-2006 — 6,022 rows, every one before
#'     2006-01-01. They are read as unavailable, not clipped, because a
#'     code of 42 is not "class 42".}
#'   \item{`finish_pos`: 98 and 99 are sentinels, not placings. Anything
#'     beyond `P5_MAX_FINISH` is read as unavailable.}
#'   \item{`field_size`: the largest legitimate British field is 40 (the
#'     Grand National). Larger values are winsorised rather than dropped —
#'     the ordering still means "very large field".}
#'   \item{`days_since_prev`: winsorised at `P5_MAX_DAYS`. Past about three
#'     years the exact gap carries nothing the encoder can use, and the
#'     maximum observed is 37,918 days, which is not a real layoff.}
#'   \item{`beaten_dist`: winsorised at `P5_MAX_BEATEN`, per P5-1d. The
#'     column is CUMULATIVE lengths behind the winner, so a large value is
#'     a real reading rather than a sentinel — the tail above 100 lengths
#'     is 62% Hurdle and Chase, where a tailed-off horse in a jumps race
#'     genuinely finishes hundreds of lengths adrift. It is therefore
#'     winsorised, not read as unavailable: unlike a pre-2006 class code or
#'     a finishing position of 99, the number is on the channel's own
#'     scale and its ORDER is informative. Beyond 100 lengths the exact
#'     figure is not: the horse was comprehensively beaten either way.}
#' }
P5_MAX_FINISH <- 40
P5_MAX_FIELD <- 40
P5_MAX_DAYS <- 1000
P5_MAX_BEATEN <- 100

#' Fetch field sizes for a set of historic races
#'
#' `sql/horse_full_history.sql` carries race date, course, type, class,
#' going and distance but not the runner count, and that file is
#' deliberately left alone — editing it would change the `full_history`
#' target's hash and invalidate every downstream target in papers 1-3.
#'
#' This is NOT a second career-history query. It reads one column from
#' `historic_races`, keyed on race id, with no join to runners and no
#' filters. The career history itself still comes from the cached
#' `full_history` target, which is `extract_career_history()`'s own output.
#'
#' @param con A connection from `connect_smartform()`.
#' @param race_ids Integer vector of historic race ids.
#' @param chunk Ids per query.
#' @return A tibble of `race_id`, `num_runners`.
p5_fetch_field_sizes <- function(con, race_ids, chunk = 2000L) {
  ids <- sort(unique(race_ids))
  splits <- split(ids, ceiling(seq_along(ids) / chunk))
  purrr::map(splits, function(chunk_ids) {
    sql <- paste0(
      "SELECT race_id, num_runners FROM historic_races WHERE race_id IN (",
      paste(chunk_ids, collapse = ", "), ")"
    )
    tibble::as_tibble(DBI::dbGetQuery(con, sql))
  }) |>
    purrr::list_rbind()
}

#' Assemble the per-run vectors for every career run
#'
#' One row per career run, carrying the eight sequence channels. Non-Runner
#' rows are dropped, the same treatment `build_going_features()` gives them:
#' a declared non-runner did not run, so it is not a prior run.
#'
#' `finish_pos` is the RAW finishing position, not capped at 4. That is the
#' point of the encoder arm — paper 3's `pos_lag*_nonzero` encoding is
#' top-4-only and loses the difference between seventh and fifteenth.
#'
#' @param full_history The cached `full_history` target.
#' @param field_sizes Output of `p5_fetch_field_sizes()`.
#' @return A tibble, one row per career run, with the channels above.
build_p5_run_vectors <- function(full_history, field_sizes) {
  n_before <- full_history |>
    dplyr::filter(is.na(unfinished) | unfinished != "Non-Runner") |>
    nrow()

  out <- full_history |>
    dplyr::filter(is.na(unfinished) | unfinished != "Non-Runner") |>
    dplyr::left_join(field_sizes, by = "race_id") |>
    dplyr::transmute(
      runner_id,
      hist_race_id = race_id,
      hist_date = meeting_date,
      finish_pos = as.numeric(dplyr::coalesce(amended_position, finish_position)),
      beaten_raw = distance_behind_winner,
      going_ordinal = unname(going_ordinal[normalize_going(going)]),
      class = as.numeric(class),
      field_size = as.numeric(num_runners),
      distance_furlongs = distance_yards / 220,
      days_since_prev = as.numeric(days_since_ran)
    ) |>
    dplyr::mutate(
      # A winner is zero lengths behind the winner. That is definitional,
      # not imputation, so it is not marked missing. What remains missing is
      # a non-finisher, or a row the feed simply lacks.
      beaten_dist = dplyr::case_when(
        !is.na(finish_pos) & finish_pos == 1 ~ 0,
        TRUE ~ beaten_raw
      ),
      beaten_missing = as.numeric(is.na(beaten_dist)),
      beaten_dist = dplyr::coalesce(beaten_dist, P5_BEATEN_FILL),

      # -- Channel cleaning, per P5-1b --------------------------------------
      # Unavailable readings take P5_BEATEN_FILL rather than 0, because 0 is
      # a legitimate value for several of these channels (a same-day
      # re-run, a winner's beaten distance) and is also the padding value.
      # Padding stays inert because `seq_len` masks it.
      class = dplyr::if_else(
        is.na(class) | class < 1 | class > 7, P5_BEATEN_FILL, class
      ),
      finish_pos = dplyr::if_else(
        is.na(finish_pos) | finish_pos > P5_MAX_FINISH,
        P5_BEATEN_FILL, finish_pos
      ),
      field_size = pmin(field_size, P5_MAX_FIELD),
      days_since_prev = dplyr::if_else(
        is.na(days_since_prev), P5_BEATEN_FILL,
        pmin(days_since_prev, P5_MAX_DAYS)
      ),
      # Winsorised last, so the P5_BEATEN_FILL sentinel set above is left
      # alone by `pmin()` and only real readings are capped.
      beaten_dist = pmin(beaten_dist, P5_MAX_BEATEN)
    ) |>
    dplyr::select(-beaten_raw)

  stopifnot(nrow(out) == n_before)
  out
}

#' Build padded prior-run sequences for a modelling frame
#'
#' For each runner-race, the `max_len` most recent strictly-prior runs,
#' ordered MOST RECENT FIRST, padded at the tail with zeros. `seq_len`
#' carries the true count so the encoder masks the padding;
#' `career_runs_prior` carries the untruncated career length so nothing is
#' lost for horses with more than `max_len` prior runs.
#'
#' One row in, one row out: the frame is never filtered, so a caller can
#' assert row identity across this function.
#'
#' @param frame The paper-5 frame (`race_id`, `runner_id`, `race_date`).
#' @param run_vectors Output of `build_p5_run_vectors()`.
#' @param max_len Sequence cap.
#' @param features Channel names, in order.
#' @return A list: `key` (tibble of race_id/runner_id in array row order),
#'   `x` (numeric array `[n, max_len, n_features]`), `seq_len` (integer),
#'   `career_runs_prior` (integer), `features`, `max_len`.
build_p5_sequences <- function(frame, run_vectors, max_len = P5_SEQ_MAX_LEN,
                               features = P5_SEQ_FEATURES) {
  stopifnot(!anyDuplicated(frame[c("race_id", "runner_id")]))

  key <- frame |>
    dplyr::select(race_id, runner_id, race_date) |>
    dplyr::arrange(race_id, runner_id)
  n <- nrow(key)

  prior <- key |>
    dplyr::inner_join(run_vectors, by = "runner_id",
                      relationship = "many-to-many") |>
    dplyr::filter(hist_date < race_date) |>
    dplyr::arrange(race_id, runner_id, dplyr::desc(hist_date), hist_race_id) |>
    dplyr::group_by(race_id, runner_id) |>
    dplyr::mutate(slot = dplyr::row_number(), career_runs_prior = dplyr::n()) |>
    dplyr::ungroup()

  # Career length is counted BEFORE the cap, so truncation loses nothing.
  totals <- prior |>
    dplyr::distinct(race_id, runner_id, career_runs_prior)

  kept <- prior |> dplyr::filter(slot <= max_len)

  x <- array(0, dim = c(n, max_len, length(features)))
  row_of <- match(
    paste(kept$race_id, kept$runner_id),
    paste(key$race_id, key$runner_id)
  )
  stopifnot(!anyNA(row_of))
  for (f in seq_along(features)) {
    x[cbind(row_of, kept$slot, f)] <- kept[[features[f]]]
  }
  # Padding and any residual NA channel value are zero: the mask makes the
  # padded slots inert, and a channel that is NA within a real slot (a
  # going string outside the lookup, say) is centred rather than propagated.
  x[is.na(x)] <- 0

  lens <- tibble::tibble(race_id = key$race_id, runner_id = key$runner_id) |>
    dplyr::left_join(totals, by = c("race_id", "runner_id")) |>
    dplyr::mutate(career_runs_prior = dplyr::coalesce(career_runs_prior, 0L))

  list(
    key = dplyr::select(key, race_id, runner_id),
    x = x,
    seq_len = as.integer(pmin(lens$career_runs_prior, max_len)),
    career_runs_prior = as.integer(lens$career_runs_prior),
    features = features,
    max_len = max_len
  )
}

#' Summarise the sequences for the report
#'
#' Training-portion rows only where a split is supplied, per the series'
#' convention that exploratory tables use the training split.
#'
#' @param sequences Output of `build_p5_sequences()`.
#' @param frame The paper-5 frame, for the split labels.
#' @param which_split Split to summarise.
#' @return A list of summary tibbles.
summarise_p5_sequences <- function(sequences, frame, which_split = "train") {
  idx <- sequences$key |>
    dplyr::left_join(dplyr::select(frame, race_id, runner_id, split),
                     by = c("race_id", "runner_id")) |>
    dplyr::mutate(row = dplyr::row_number()) |>
    dplyr::filter(split == which_split) |>
    dplyr::pull(row)

  sl <- sequences$seq_len[idx]
  cr <- sequences$career_runs_prior[idx]

  q <- function(v) {
    qq <- stats::quantile(v, c(0, .25, .5, .75, .9, 1))
    tibble::tibble(min = qq[[1]], q1 = qq[[2]], median = qq[[3]],
                   q3 = qq[[4]], p90 = qq[[5]], max = qq[[6]],
                   mean = round(mean(v), 2))
  }

  channels <- purrr::map(seq_along(sequences$features), function(f) {
    vals <- sequences$x[idx, , f]
    mask <- outer(sl, seq_len(sequences$max_len), ">=")
    real <- vals[mask]
    tibble::tibble(
      channel = sequences$features[f],
      n_real_slots = length(real),
      min = min(real), median = stats::median(real),
      mean = round(mean(real), 3), max = max(real),
      pct_zero = round(100 * mean(real == 0), 2)
    )
  }) |> purrr::list_rbind()

  list(
    n_obs = length(idx),
    seq_len = q(sl) |> dplyr::mutate(measure = "sequence length (capped)",
                                     .before = 1),
    career = q(cr) |> dplyr::mutate(measure = "career runs prior (uncapped)",
                                    .before = 1),
    truncated = tibble::tibble(
      measure = "observations whose career exceeds the cap",
      n = sum(cr > sequences$max_len),
      share_pct = round(100 * mean(cr > sequences$max_len), 2)
    ),
    empty = tibble::tibble(
      measure = "observations with no prior run at all",
      n = sum(cr == 0), share_pct = round(100 * mean(cr == 0), 2)
    ),
    channels = channels
  )
}
