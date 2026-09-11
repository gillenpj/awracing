# p6_racechar.R
# Paper 6 — race-characteristic filters, and the half-window stability guard.
#
# WHY THIS FAMILY EXISTS. Rounds 1 and 2 searched two families: which horse to
# back (the picker) and where to cut on the model-probability /
# model-to-market-ratio plane (the threshold filter). `DIAGNOSTICS.md` showed
# that plane is largely a price-band dial — ROI correlates -0.785 with mean
# backed price across the surface and a quadratic in log mean price explains
# 65% of the between-rule variance — so the search was dense in one dimension
# and absent everywhere else. "Nothing beat Owen's rule" was a claim about one
# family, not about betting rules.
#
# A race-characteristic filter conditions on what is known the night before
# the race and is independent of the model's own output: field size, class,
# course, distance, going. It selects RACES rather than reacting to a settled
# price, which is also why it is the family that carries forward to the
# early-price work.
#
# TWO THINGS ABOUT THE INPUTS, both load-bearing.
#
#   FIELD SIZE comes from the betting frame, not from `qualifying_races`. The
#   SQL's `num_runners` counts DECLARED runners; Smartform's "Non-Runner"
#   entries are dropped in R, so the frame's `field_size` is the number of
#   actual starters and is the only correct field size for a betting rule. It
#   also arrives as `integer64` from the database, which compares wrongly
#   against a plain integer without an explicit cast.
#
#   TERCILE BOUNDARIES for distance are computed on the VALIDATION slice and
#   then applied to the test split unchanged. They are part of the filter's
#   definition, declared on the search set, not recomputed per split — a
#   re-derived boundary would make the two splits' rules different rules.
#
# A NEW FILE: nothing in `R/p6_ledger.R`, `R/p6_rules.R` or `R/p6_explore.R`
# is edited, so all seven ledger assertions and `p6_sweep_gate` keep testing
# exactly what they did.

# ---------------------------------------------------------------------------
# Race attributes
# ---------------------------------------------------------------------------

#' One row per race, carrying every filterable characteristic
#'
#' @param frame Output of `p6_build_bet_frame()`.
#' @param qualifying_races The series' race table.
#' @return A tibble keyed by `race_id`, in ascending `race_id` order to match
#'   `p6_compile_frame()`'s `races` vector.
p6_race_attributes <- function(frame, qualifying_races) {
  fs <- frame |>
    dplyr::distinct(race_id, race_date, field_size)

  ra <- qualifying_races |>
    dplyr::transmute(
      race_id,
      class = as.integer(class),
      course = as.character(course),
      distance_yards = as.numeric(distance_yards),
      going_ordinal = unname(going_ordinal[normalize_going(going)])
    )

  out <- fs |>
    dplyr::inner_join(ra, by = "race_id") |>
    dplyr::arrange(race_id)

  # Every race in the frame must have attributes: a silent inner-join loss
  # would shrink the universe a filter is scored against.
  stopifnot(nrow(out) == dplyr::n_distinct(frame$race_id))
  out
}

#' The distance terciles, computed once on the search set
#'
#' @param attrs Output of `p6_race_attributes()` on the validation slice.
#' @return A length-two numeric vector of the two interior boundaries.
p6_distance_terciles <- function(attrs) {
  unname(stats::quantile(attrs$distance_yards, c(1 / 3, 2 / 3),
                         names = FALSE))
}

# ---------------------------------------------------------------------------
# Filter specifications
# ---------------------------------------------------------------------------

#' Build the race-characteristic filter specifications
#'
#' A specification is data, not a closure, so the identical filter can be
#' evaluated against either split. `kind` is `"range"` (inclusive numeric
#' bounds on `var`) or `"set"` (membership of `levels`).
#'
#' Families, and what is enumerated:
#'
#'   field size  every contiguous band over 4-16. `<= N` and `>= N` are the
#'               bands `[4, N]` and `[N, 16]` and are labelled that way
#'               rather than duplicated.
#'   class       each of classes 2-5 singly, and each contiguous pair.
#'   course      each of the four singly, and each pair.
#'   distance    the three terciles, and the single cuts at each boundary.
#'   going       the series' ordinal scale, split at each interior cut point.
#'
#' Nothing is pruned here. `min_races` pruning happens against the search
#' set in `p6_rc_prune()`, so the count that struck a filter is reportable.
#'
#' @param attrs Output of `p6_race_attributes()` on the validation slice.
#' @param terciles Output of `p6_distance_terciles()`.
#' @return A tibble of specifications.
p6_rc_specs <- function(attrs, terciles = p6_distance_terciles(attrs)) {
  rng <- function(family, var, lo, hi, label) {
    tibble::tibble(family = family, kind = "range", var = var,
                   lo = as.numeric(lo), hi = as.numeric(hi),
                   levels = NA_character_, label = label)
  }
  st <- function(family, var, levels, label) {
    tibble::tibble(family = family, kind = "set", var = var,
                   lo = NA_real_, hi = NA_real_,
                   levels = paste(levels, collapse = "|"), label = label)
  }

  # -- field size ---------------------------------------------------------
  fmin <- 4L; fmax <- 16L
  fs <- purrr::map(fmin:fmax, function(lo)
    purrr::map(lo:fmax, function(hi) {
      lab <- if (lo == fmin && hi == fmax) "field size any"
             else if (lo == fmin) sprintf("field size <= %d", hi)
             else if (hi == fmax) sprintf("field size >= %d", lo)
             else sprintf("field size %d-%d", lo, hi)
      rng("field size", "field_size", lo, hi, lab)
    }) |> purrr::list_rbind()) |> purrr::list_rbind()

  # -- class --------------------------------------------------------------
  cl_single <- purrr::map(2:5, function(c)
    rng("class", "class", c, c, sprintf("class %d only", c))) |>
    purrr::list_rbind()
  cl_pair <- purrr::map(2:4, function(c)
    rng("class", "class", c, c + 1, sprintf("class %d-%d", c, c + 1))) |>
    purrr::list_rbind()

  # -- course -------------------------------------------------------------
  courses <- sort(unique(attrs$course))
  co_single <- purrr::map(courses, function(x)
    st("course", "course", x, sprintf("course %s only", x))) |>
    purrr::list_rbind()
  co_pair <- purrr::map(seq_along(courses), function(i)
    purrr::map(seq_along(courses), function(j) {
      if (j <= i) return(NULL)
      st("course", "course", c(courses[i], courses[j]),
         sprintf("course %s or %s", courses[i], courses[j]))
    }) |> purrr::list_rbind()) |> purrr::list_rbind()

  # -- distance -----------------------------------------------------------
  t1 <- terciles[1]; t2 <- terciles[2]
  dmin <- min(attrs$distance_yards); dmax <- max(attrs$distance_yards)
  di <- dplyr::bind_rows(
    rng("distance", "distance_yards", dmin, t1,
        sprintf("distance <= %.0fy (tercile 1)", t1)),
    rng("distance", "distance_yards", t1 + 1e-9, t2,
        sprintf("distance %.0f-%.0fy (tercile 2)", t1, t2)),
    rng("distance", "distance_yards", t2 + 1e-9, dmax,
        sprintf("distance > %.0fy (tercile 3)", t2)),
    rng("distance", "distance_yards", t1 + 1e-9, dmax,
        sprintf("distance > %.0fy", t1)),
    rng("distance", "distance_yards", dmin, t2,
        sprintf("distance <= %.0fy", t2))
  )

  # -- going --------------------------------------------------------------
  go_vals <- sort(unique(attrs$going_ordinal[!is.na(attrs$going_ordinal)]))
  go <- if (length(go_vals) < 2L) tibble::tibble() else {
    purrr::map(go_vals[-length(go_vals)], function(c)
      dplyr::bind_rows(
        rng("going", "going_ordinal", min(go_vals), c,
            sprintf("going ordinal <= %g (firmer)", c)),
        rng("going", "going_ordinal", c + 1e-9, max(go_vals),
            sprintf("going ordinal > %g (softer)", c))
      )) |> purrr::list_rbind()
  }

  dplyr::bind_rows(fs, cl_single, cl_pair, co_single, co_pair, di, go) |>
    dplyr::mutate(rc_id = dplyr::row_number(), .before = 1)
}

#' Evaluate one specification against a race-attribute table
#'
#' @param attrs Output of `p6_race_attributes()`.
#' @param spec A one-row slice of `p6_rc_specs()`.
#' @return A logical vector, one element per row of `attrs`.
p6_rc_mask <- function(attrs, spec) {
  v <- attrs[[spec$var]]
  if (spec$kind == "range") {
    !is.na(v) & v >= spec$lo & v <= spec$hi
  } else {
    !is.na(v) & v %in% strsplit(spec$levels, "|", fixed = TRUE)[[1]]
  }
}

#' Every specification's mask, as a races-by-filters logical matrix
#'
#' @param cf Output of `p6_compile_frame()`.
#' @param attrs Output of `p6_race_attributes()` for the same split.
#' @param specs Output of `p6_rc_specs()`.
#' @return A logical matrix, `cf$n_races` rows, one column per specification.
p6_rc_masks <- function(cf, attrs, specs) {
  stopifnot(identical(attrs$race_id, cf$races))
  m <- vapply(seq_len(nrow(specs)),
              function(i) p6_rc_mask(attrs, specs[i, ]),
              logical(nrow(attrs)))
  dim(m) <- c(nrow(attrs), nrow(specs))
  colnames(m) <- as.character(specs$rc_id)
  m
}

#' Prune the specifications that cannot place enough bets on the search set
#'
#' @param specs Output of `p6_rc_specs()`.
#' @param masks Output of `p6_rc_masks()` on the validation slice.
#' @param half A half index over the same races (1 or 2), for the guard's
#'   per-half counts.
#' @param min_races Minimum search-set races.
#' @param min_half Minimum races in each half.
#' @return `specs` with `n_races`, `n_h1`, `n_h2` and `kept` columns.
p6_rc_prune <- function(specs, masks, half, min_races = 300L,
                        min_half = 150L) {
  specs |>
    dplyr::mutate(
      n_races = colSums(masks),
      n_h1 = colSums(masks & half == 1L),
      n_h2 = colSums(masks & half == 2L),
      kept = n_races >= min_races & n_h1 >= min_half & n_h2 >= min_half,
      struck_because = dplyr::case_when(
        kept ~ NA_character_,
        n_races < min_races ~ sprintf("only %d search-set races", n_races),
        TRUE ~ sprintf("only %d / %d races in the two halves", n_h1, n_h2)
      )
    )
}

# ---------------------------------------------------------------------------
# Scoring, with a race mask
# ---------------------------------------------------------------------------

#' Restrict a rule's backed rows to a set of races
#'
#' @param cf Output of `p6_compile_frame()`.
#' @param rows Output of `p6_rule_rows()`.
#' @param race_mask Logical over `cf$races`, or `NULL` for no restriction.
#' @return The subset of `rows` whose race is in the mask.
p6_restrict <- function(cf, rows, race_mask = NULL) {
  if (is.null(race_mask) || !length(rows)) return(rows)
  rows[race_mask[cf$race_ix[rows]]]
}

#' Score one rule on one settlement table, restricted to a race set
#'
#' Adds the two columns the race-characteristic family needs on every row:
#' mean field size, and the count of races the filter itself admits.
#'
#' @param cf Output of `p6_compile_frame()`.
#' @param rows Backed rows, already restricted.
#' @param bet Settlement table name.
#' @param n_filter_races How many races the filter admits, for the report.
#' @param field_size Field size per frame row.
#' @return A flat named list.
p6_score_rc <- function(cf, rows, bet, n_filter_races, field_size) {
  s <- p6_score_rule(cf, rows, bet)
  st <- if (length(rows)) cf$stake[rows, bet] else numeric(0)
  ok <- if (length(rows)) !is.na(st) & st > 0 else logical(0)
  c(s, list(
    n_filter_races = n_filter_races,
    mean_field_size = if (any(ok)) mean(field_size[rows[ok]]) else NA_real_
  ))
}

#' Sweep the race-characteristic family
#'
#' Every kept specification crossed with every picker, at a flat stake and
#' unfiltered on the probability / ratio plane. Optionally restricted to a
#' window (a half of the validation slice).
#'
#' @param cf Output of `p6_compile_frame()`.
#' @param masks Output of `p6_rc_masks()`.
#' @param specs The kept rows of `p6_rc_prune()`.
#' @param field_size Field size per frame row.
#' @param window Logical over `cf$races`, or `NULL` for the whole split.
#' @param pickers Output of `p6_pickers()`.
#' @return A long tibble, one row per (picker, specification, bet).
p6_rc_sweep <- function(cf, masks, specs, field_size, window = NULL,
                        pickers = p6_pickers()) {
  pn <- names(pickers)
  state <- p6_filter_state(cf, -Inf, -Inf)
  base <- lapply(stats::setNames(pn, pn),
                 function(nm) p6_rule_rows(cf, nm, -Inf, -Inf, state = state))

  out <- vector("list", nrow(specs) * length(pn) * length(cf$bets))
  z <- 0L
  for (i in seq_len(nrow(specs))) {
    key <- as.character(specs$rc_id[i])
    mask <- masks[, key]
    if (!is.null(window)) mask <- mask & window
    nfr <- sum(mask)
    for (nm in pn) {
      rows <- p6_restrict(cf, base[[nm]], mask)
      for (b in cf$bets) {
        z <- z + 1L
        out[[z]] <- c(
          list(picker = nm, rc_id = specs$rc_id[i],
               family = "race characteristic",
               subfamily = specs$family[i],
               filter = specs$label[i], bet = b),
          p6_score_rc(cf, rows, b, nfr, field_size)
        )
      }
    }
  }
  dplyr::bind_rows(out) |>
    dplyr::mutate(rule = paste0(picker, " / ", filter), .before = 1)
}

#' Sweep the threshold family, restricted to a window
#'
#' Round 2's family, re-scored on a half of the validation slice so the
#' stability guard can be applied to it — and so Owen's cell can be put
#' through the same guard as everything else.
#'
#' @param cf Output of `p6_compile_frame()`.
#' @param grid Output of `p6_filter_grid()`.
#' @param field_size Field size per frame row.
#' @param window Logical over `cf$races`, or `NULL`.
#' @param pickers Output of `p6_pickers()`.
#' @return A long tibble.
p6_threshold_sweep_window <- function(cf, grid, field_size, window = NULL,
                                      pickers = p6_pickers()) {
  pn <- names(pickers)
  nfr <- if (is.null(window)) cf$n_races else sum(window)
  out <- vector("list", nrow(grid) * length(pn) * length(cf$bets))
  z <- 0L
  for (g in seq_len(nrow(grid))) {
    p_cut <- grid$p_cut[g]; r_cut <- grid$r_cut[g]
    state <- p6_filter_state(cf, p_cut, r_cut)
    for (nm in pn) {
      rows <- p6_restrict(cf, p6_rule_rows(cf, nm, p_cut, r_cut, state = state),
                         window)
      for (b in cf$bets) {
        z <- z + 1L
        out[[z]] <- c(
          list(picker = nm, filter_id = grid$filter_id[g], p_cut = p_cut,
               r_cut = r_cut, no_filter = grid$no_filter[g], bet = b),
          p6_score_rc(cf, rows, b, nfr, field_size)
        )
      }
    }
  }
  dplyr::bind_rows(out) |>
    dplyr::mutate(family = "threshold", subfamily = "threshold",
                  filter = p6_rule_label(picker, p_cut, r_cut, no_filter),
                  rule = filter, .before = 1)
}

#' Sweep the combined layer: one race-characteristic filter plus the plane
#'
#' The second layer the brief asks for: the best race-characteristic filter
#' per picker per bet type, crossed with the existing probability and ratio
#' cuts, so it is visible whether the two families are additive or redundant.
#'
#' @param cf Output of `p6_compile_frame()`.
#' @param masks Output of `p6_rc_masks()`.
#' @param pairs A tibble of `picker` and `rc_id` to cross, plus `filter`.
#' @param grid Output of `p6_filter_grid()`.
#' @param field_size Field size per frame row.
#' @param window Logical over `cf$races`, or `NULL`.
#' @return A long tibble.
p6_combined_sweep <- function(cf, masks, pairs, grid, field_size,
                              window = NULL) {
  pairs <- dplyr::distinct(pairs, picker, rc_id, filter)
  mk <- lapply(seq_len(nrow(pairs)), function(i) {
    m <- masks[, as.character(pairs$rc_id[i])]
    if (!is.null(window)) m <- m & window
    m
  })
  nfr <- vapply(mk, sum, integer(1))

  out <- vector("list", nrow(grid) * nrow(pairs) * length(cf$bets))
  z <- 0L
  for (g in seq_len(nrow(grid))) {
    p_cut <- grid$p_cut[g]; r_cut <- grid$r_cut[g]
    state <- p6_filter_state(cf, p_cut, r_cut)
    for (i in seq_len(nrow(pairs))) {
      rows <- p6_restrict(
        cf, p6_rule_rows(cf, pairs$picker[i], p_cut, r_cut, state = state),
        mk[[i]])
      for (b in cf$bets) {
        z <- z + 1L
        out[[z]] <- c(
          list(picker = pairs$picker[i], rc_id = pairs$rc_id[i],
               rc_filter = pairs$filter[i], filter_id = grid$filter_id[g],
               p_cut = p_cut, r_cut = r_cut, no_filter = grid$no_filter[g],
               bet = b),
          p6_score_rc(cf, rows, b, nfr[i], field_size)
        )
      }
    }
  }
  dplyr::bind_rows(out) |>
    dplyr::mutate(
      family = "combined", subfamily = "combined",
      filter = paste0(rc_filter, " + ",
                      p6_thr_label(p_cut, r_cut, no_filter)),
      rule = paste0(picker, " / ", filter), .before = 1
    )
}

#' A threshold cut's label on its own, without a picker prefix
#'
#' @param p_cut,r_cut,no_filter Cut components.
#' @return A character vector.
p6_thr_label <- function(p_cut, r_cut, no_filter) {
  dplyr::if_else(no_filter, "no filter",
                 sprintf("P>%.2f, ratio>%.2f", p_cut, r_cut))
}

# ---------------------------------------------------------------------------
# The stability guard
# ---------------------------------------------------------------------------

#' The half index over a split's races
#'
#' @param attrs Output of `p6_race_attributes()`, in `cf$races` order.
#' @param cut The boundary date; races on or before it are half 1.
#' @return An integer vector of 1s and 2s.
p6_half_index <- function(attrs, cut = as.Date("2012-01-15")) {
  as.integer(ifelse(attrs$race_date <= cut, 1L, 2L))
}

#' Apply the half-window stability guard to one family
#'
#' A candidate survives only if it ranks in the top decile of its family on
#' BOTH halves and places at least `min_bets` bets in each. Ranking is by ROI
#' at the real starting price within the family and bet type. Eligibility for
#' the decile calculation is the bet-count condition, so the decile is taken
#' among candidates that could be ranked at all.
#'
#' The guard exists because a single-window argmax cannot see a collapse:
#' Owen's cell ranked 1st of 617 on the first half of the validation slice
#' and 157th of 579 on the second (`DIAGNOSTICS.md`).
#'
#' @param full,h1,h2 The same family swept on the whole split and each half.
#' @param keys The columns identifying a candidate.
#' @param decile Top fraction required on both halves.
#' @param min_bets Minimum bets in each half.
#' @return A tibble of every candidate with its two half ranks and `survives`.
p6_stability_guard <- function(full, h1, h2,
                               keys = c("picker", "family", "filter", "bet"),
                               decile = 0.10, min_bets = 150L) {
  pick <- function(d, sfx) d |>
    dplyr::select(dplyr::all_of(keys), dplyr::all_of(c("roi", "n_bets"))) |>
    dplyr::rename_with(~ paste0(., sfx), c("roi", "n_bets"))

  full |>
    dplyr::select(dplyr::all_of(keys), rule, subfamily, roi, roi_fair,
                  n_bets, n_wins, mean_sp, median_sp, share_favourite,
                  mean_field_size, n_filter_races) |>
    dplyr::left_join(pick(h1, "_h1"), by = keys) |>
    dplyr::left_join(pick(h2, "_h2"), by = keys) |>
    dplyr::group_by(bet, family) |>
    dplyr::mutate(
      eligible = !is.na(n_bets_h1) & n_bets_h1 >= min_bets &
        !is.na(n_bets_h2) & n_bets_h2 >= min_bets &
        !is.na(roi_h1) & !is.na(roi_h2),
      n_eligible = sum(eligible),
      cutoff = ceiling(decile * n_eligible),
      rank_h1 = dplyr::if_else(
        eligible,
        as.integer(rank(dplyr::if_else(eligible, -roi_h1, Inf),
                        ties.method = "min")), NA_integer_),
      rank_h2 = dplyr::if_else(
        eligible,
        as.integer(rank(dplyr::if_else(eligible, -roi_h2, Inf),
                        ties.method = "min")), NA_integer_),
      rank_full = dplyr::if_else(
        eligible,
        as.integer(rank(dplyr::if_else(eligible, -roi, Inf),
                        ties.method = "min")), NA_integer_),
      cutoff = as.integer(cutoff),
      survives = eligible & rank_h1 <= cutoff & rank_h2 <= cutoff,
      struck_because = dplyr::case_when(
        survives ~ NA_character_,
        !eligible ~ "too few bets in a half",
        rank_h1 > cutoff & rank_h2 > cutoff ~
          sprintf("outside the top decile on both halves (%d, %d of %d)",
                  rank_h1, rank_h2, n_eligible),
        rank_h1 > cutoff ~ sprintf("first half only %d of %d", rank_h1,
                                   n_eligible),
        TRUE ~ sprintf("second half only %d of %d", rank_h2, n_eligible)
      )
    ) |>
    dplyr::ungroup()
}

#' Cross-half rank correlation, per family and bet type
#'
#' The number that says whether a family is findable at all on this data
#' size. Worth as much as any ROI in the paper: a family whose halves do not
#' agree cannot be searched on 1,505 races however good its best row looks.
#'
#' @param guarded Output of `p6_stability_guard()`.
#' @return A tibble, one row per (family, bet).
p6_half_correlations <- function(guarded, by = c("family", "subfamily")) {
  by <- match.arg(by)
  grp <- if (by == "family") c("family", "bet") else
    c("family", "subfamily", "bet")
  guarded |>
    dplyr::filter(eligible) |>
    dplyr::group_by(dplyr::across(dplyr::all_of(grp))) |>
    dplyr::summarise(
      n_eligible = dplyr::n(),
      spearman = suppressWarnings(stats::cor(roi_h1, roi_h2,
                                             method = "spearman")),
      pearson = suppressWarnings(stats::cor(roi_h1, roi_h2)),
      n_survivors = sum(survives),
      best_h1_roi = max(roi_h1), best_h2_roi = max(roi_h2),
      .groups = "drop"
    )
}

# ---------------------------------------------------------------------------
# Test contact
# ---------------------------------------------------------------------------

#' Build the round-3 test shortlist
#'
#' Per bet type: the top 3 surviving race-characteristic candidates, the top
#' 2 surviving combined-layer candidates, Owen's S1/K0 as the series
#' comparator, and P2 unfiltered as the no-model control. Survivors are
#' ranked by full-validation ROI. Owen and the control are carried forward
#' unconditionally, whether or not they survive the guard — that is the point
#' of a comparator.
#'
#' @param rc_guard,comb_guard,thr_guard Guard outputs for the three families.
#' @param bet The settlement table to shortlist for.
#' @param n_rc,n_comb How many survivors to take from each family.
#' @return A tibble of shortlisted rules with a `roles` column.
p6_round3_shortlist <- function(rc_guard, comb_guard, thr_guard, bet,
                                n_rc = 3L, n_comb = 2L) {
  take <- function(g, n, lab) g |>
    dplyr::filter(bet == !!bet, survives) |>
    dplyr::arrange(dplyr::desc(roi)) |>
    dplyr::slice_head(n = n) |>
    dplyr::mutate(role = sprintf(lab, dplyr::row_number()))

  rc <- take(rc_guard, n_rc, "race-characteristic survivor %d")
  cb <- take(comb_guard, n_comb, "combined-layer survivor %d")

  owen <- thr_guard |>
    dplyr::filter(bet == !!bet, picker == "P5",
                  filter == "P5 / P>0.15, ratio>1.30") |>
    dplyr::mutate(role = "S1/K0, Owen's rule (series comparator)")
  stopifnot(nrow(owen) == 1L)

  fav <- thr_guard |>
    dplyr::filter(bet == !!bet, picker == "P2", filter == "P2 / no filter") |>
    dplyr::mutate(role = "market favourite, every race (no model)")
  stopifnot(nrow(fav) == 1L)

  dplyr::bind_rows(rc, cb, owen, fav) |>
    dplyr::group_by(rule, picker, family, subfamily, filter) |>
    dplyr::summarise(roles = paste(sort(unique(role)), collapse = "; "),
                     val_roi = dplyr::first(roi),
                     val_roi_h1 = dplyr::first(roi_h1),
                     val_roi_h2 = dplyr::first(roi_h2),
                     val_bets = dplyr::first(n_bets),
                     val_mean_sp = dplyr::first(mean_sp),
                     val_rank = dplyr::first(rank_full),
                     val_n_eligible = dplyr::first(n_eligible),
                     survives = dplyr::first(survives),
                     .groups = "drop") |>
    dplyr::mutate(bet = bet, .before = 1)
}

#' Resolve a shortlisted rule's backed rows on either split
#'
#' A shortlist row names its rule by family and label, and the three families
#' resolve differently. This is the single place that mapping lives, so the
#' validation and test sides cannot drift apart.
#'
#' @param cf Output of `p6_compile_frame()` for the split being scored.
#' @param masks Output of `p6_rc_masks()` for the SAME split.
#' @param specs The full specification table.
#' @param row A one-row shortlist slice.
#' @return An integer vector of frame rows.
p6_resolve_rule <- function(cf, masks, specs, row) {
  parse_thr <- function(lbl) {
    if (grepl("no filter", lbl, fixed = TRUE)) return(c(-Inf, -Inf))
    m <- regmatches(lbl, regexec(
      "P>(-?[0-9.]+|-Inf), ratio>(-?[0-9.]+|-Inf)", lbl))[[1]]
    stopifnot(length(m) == 3L)
    as.numeric(m[2:3])
  }
  rc_mask_of <- function(lbl) {
    i <- which(specs$label == lbl)
    stopifnot(length(i) == 1L)
    masks[, as.character(specs$rc_id[i])]
  }

  if (row$family == "threshold") {
    cuts <- parse_thr(row$filter)
    return(p6_rule_rows(cf, row$picker, cuts[1], cuts[2]))
  }
  if (row$family == "race characteristic") {
    return(p6_restrict(cf, p6_rule_rows(cf, row$picker, -Inf, -Inf),
                       rc_mask_of(row$filter)))
  }
  stopifnot(row$family == "combined")
  # "<rc label> + <threshold label>"
  parts <- strsplit(row$filter, " + ", fixed = TRUE)[[1]]
  stopifnot(length(parts) == 2L)
  cuts <- parse_thr(parts[2])
  p6_restrict(cf, p6_rule_rows(cf, row$picker, cuts[1], cuts[2]),
              rc_mask_of(parts[1]))
}

#' Score a round-3 shortlist on one split
#'
#' @param cf,masks,specs The split's compiled frame, masks and specifications.
#' @param shortlist Output of `p6_round3_shortlist()`.
#' @param field_size Field size per frame row.
#' @param n_boot,seed Bootstrap replicates and RNG seed.
#' @return `shortlist`'s keys with the split's scores and interval.
p6_score_round3 <- function(cf, masks, specs, shortlist, field_size,
                            n_boot = 2000L, seed = 42L) {
  purrr::map(seq_len(nrow(shortlist)), function(i) {
    row <- shortlist[i, ]
    rows <- p6_resolve_rule(cf, masks, specs, row)
    s <- tibble::as_tibble(p6_score_rc(cf, rows, row$bet,
                                       length(unique(cf$race_ix[rows])),
                                       field_size))
    bs <- p6_explore_bootstrap(cf, rows, row$bet, n_boot = n_boot, seed = seed)
    dplyr::mutate(s, bet = row$bet, rule = row$rule, picker = row$picker,
                  family = row$family, filter = row$filter,
                  roles = row$roles, ci_lo = bs$ci_lo, ci_hi = bs$ci_hi,
                  .before = 1)
  }) |> purrr::list_rbind()
}
