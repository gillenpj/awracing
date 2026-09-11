# p6_explore.R
# Paper 6 — the exploratory ROI sweep.
#
# WHAT THIS IS. An exploratory stress test of whether test-split ROI can be
# moved by a different betting rule, to generate ideas to return to when
# betting goes live. It is NOT a hypothesis test: there is no declaration
# rule, no bar to clear, and no interval gating what reaches the test split.
# Several rules are read against the same 2,183 test races, so whatever tops
# the test table is partly noise, and the report says so at the top.
#
# WHY THE CANDIDATE SET IS SHAPED THIS WAY. The previous draft's nine
# selection arms collapsed to three horse-picking functions behind seven
# race-level filters: seven of nine backed the identical horse in 100.0% of
# races where any two of them bet (see `../papers/06_betting_strategy/
# DIAGNOSTICS.md`). The sweep here separates the two decisions explicitly:
#
#   a PICKER decides WHICH HORSE, given a race worth betting;
#   a FILTER decides WHICH RACES are worth betting.
#
# and takes their full cross-product. A picker reads the whole field; only P5
# reads the filter's cuts, because Owen's rule is defined that way — pick the
# highest model probability AMONG THE QUALIFIERS, which is what made S1 the
# one arm in the old set that ever backed a non-top-rated horse.
#
# MEAN BACKED PRICE IS REPORTED ON EVERY ROW, and that is load-bearing.
# Across the previous sweep's populated cells, ROI correlated -0.785 with the
# mean price the cell backs and a quadratic in log mean price explained 65% of
# the between-cell variance. A rule's return is mostly a statement about the
# price band it bets in unless the price column says otherwise. Nothing here
# controls for it; it is simply always visible.
#
# A NEW FILE, DELIBERATELY: nothing under `R/p6_ledger.R` or `R/p6_rules.R` is
# edited, so `scripts/verify_p6_ledger.R` keeps testing exactly what it did.

# ---------------------------------------------------------------------------
# Pickers
# ---------------------------------------------------------------------------

#' The five horse-pickers
#'
#' Each takes the per-runner frame restricted to the races the filter selected,
#' plus the filter's own cuts, and returns exactly one row per race.
#'
#' P1  highest model win probability                         (the field)
#' P2  the market favourite, shortest starting price         (the field)
#' P3  highest model probability x starting price            (expected return)
#' P4  largest model probability minus market probability    (largest edge)
#' P5  highest model probability among runners passing the filter's cuts —
#'     Owen's picker. Degenerates to P1 on the no-filter row, where every
#'     runner passes.
#'
#' Ties are broken by the lower `runner_id` throughout, which is the tie-break
#' `select_single_win_bet()` and `p6_top_rated()` already use.
#'
#' @return A named list of five pickers, each `list(label, key, uses_cuts)`
#'   where `key` maps the frame to the quantity maximised.
p6_pickers <- function() {
  list(
    P1 = list(label = "P1 highest model probability",
              key = function(f) f$win_model, uses_cuts = FALSE),
    P2 = list(label = "P2 market favourite (shortest SP)",
              key = function(f) -f$starting_price_decimal, uses_cuts = FALSE),
    P3 = list(label = "P3 highest model probability x SP (expected return)",
              key = function(f) f$win_model * f$starting_price_decimal,
              uses_cuts = FALSE),
    P4 = list(label = "P4 largest model minus market probability",
              key = function(f) f$win_model - f$win_market, uses_cuts = FALSE),
    P5 = list(label = "P5 highest model probability among qualifiers (Owen)",
              key = function(f) f$win_model, uses_cuts = TRUE)
  )
}

#' The filter grid
#'
#' A runner passes when `win_model > p_cut` and `ratio > r_cut`; a race is bet
#' when at least one of its runners passes. The no-filter row bets every race
#' and is encoded as both cuts at `-Inf` so it runs through the same code path
#' rather than a special case.
#'
#' @param p_cuts,r_cuts The probability and ratio cut sequences.
#' @return A tibble of `filter_id`, `p_cut`, `r_cut`, `no_filter`.
p6_filter_grid <- function(p_cuts = seq(0.00, 0.35, by = 0.01),
                           r_cuts = seq(0.80, 2.50, by = 0.05)) {
  dplyr::bind_rows(
    tibble::tibble(p_cut = -Inf, r_cut = -Inf, no_filter = TRUE),
    tidyr::expand_grid(p_cut = p_cuts, r_cut = r_cuts) |>
      dplyr::mutate(no_filter = FALSE)
  ) |>
    dplyr::mutate(filter_id = dplyr::row_number(), .before = 1)
}

# ---------------------------------------------------------------------------
# The compiled frame
# ---------------------------------------------------------------------------

#' Compile one split's frame into the vectors the sweep needs
#'
#' The sweep scores 6,305 rules on four settlement tables, so the per-cell
#' work has to be indices and sums rather than `dplyr` verbs. This does every
#' join and every within-race argmax that does NOT depend on the filter, once.
#'
#' The P1-P4 pickers read the whole field, so their chosen runner in a race is
#' the same whatever the filter is — only the SET of races changes. Their
#' argmax row index per race is therefore precomputed here and merely subset
#' per cell. P5 depends on the cuts and is resolved per cell against
#' `order_by_prob`, a single ordering of the frame by race then descending
#' model probability then runner id.
#'
#' @param frame Output of `p6_build_bet_frame()`.
#' @param settle Output of `p6_settlement_tables()`.
#' @return A list of vectors and index tables. `stake`, `ret` and `fair` are
#'   matrices, one column per bet type, `NA` where that bet does not exist —
#'   the settlement universes drop races without a complete price vector or a
#'   clean three-horse place set, and a bet in a dropped race is dropped, the
#'   same inner join `p6_ledger()` performs.
p6_compile_frame <- function(frame, settle) {
  bets <- names(settle)

  wide <- frame
  for (b in bets) {
    s <- settle[[b]] |>
      dplyr::transmute(race_id, horse_ref,
                       !!paste0(b, "__stake") := stake_mult,
                       !!paste0(b, "__ret")   := ret_unit,
                       !!paste0(b, "__fair")  := ret_unit_fair)
    stopifnot(!anyDuplicated(paste(s$race_id, s$horse_ref)))
    wide <- dplyr::left_join(wide, s, by = c("race_id", "horse_ref"))
  }
  # A settlement join must never change the row count: every bet is priced at
  # most once.
  stopifnot(nrow(wide) == nrow(frame))

  mat <- function(suffix) {
    m <- vapply(bets, function(b) as.numeric(wide[[paste0(b, "__", suffix)]]),
                numeric(nrow(wide)))
    dim(m) <- c(nrow(wide), length(bets))
    dimnames(m) <- list(NULL, bets)
    m
  }

  races <- sort(unique(frame$race_id))
  race_ix <- match(frame$race_id, races)

  # Per-race argmax row for each field-reading picker, ties to lower runner_id.
  # These do not depend on the filter — only the SET of races does — so the
  # sweep subsets these vectors instead of recomputing 1,261 argmaxes each.
  pickers <- p6_pickers()
  field_pickers <- names(pickers)[!vapply(pickers, function(p) p$uses_cuts,
                                          logical(1))]
  argmax_by_race <- function(key) {
    o <- order(race_ix, -key, frame$runner_id)
    first <- o[!duplicated(race_ix[o])]
    # `race_ix[o]` is sorted ascending and the races are 1..n contiguous, so
    # the survivors already come out in race order. Asserted, not assumed.
    stopifnot(identical(race_ix[first], seq_along(races)))
    first
  }
  idx <- lapply(stats::setNames(field_pickers, field_pickers),
                function(nm) argmax_by_race(pickers[[nm]]$key(frame)))

  list(
    n_rows = nrow(frame), races = races, race_ix = race_ix,
    n_races = length(races), bets = bets,
    win_model = frame$win_model, win_market = frame$win_market,
    ratio = frame$ratio, sp = frame$starting_price_decimal,
    sp_rank = frame$sp_rank, runner_id = frame$runner_id,
    stake = mat("stake"), ret = mat("ret"), fair = mat("fair"),
    picker_idx = idx,
    order_by_prob = order(race_ix, -frame$win_model, frame$runner_id)
  )
}

# ---------------------------------------------------------------------------
# Scoring one rule
# ---------------------------------------------------------------------------

#' Resolve one filter, once, for every picker
#'
#' The filter work — which runners pass, which races therefore get a bet, and
#' P5's per-race argmax among the passers — is identical across the five
#' pickers, so the sweep computes it once per filter and hands it to all five.
#'
#' @param cf Output of `p6_compile_frame()`.
#' @param p_cut,r_cut The filter's cuts; `-Inf` for the no-filter row.
#' @return A list of `bet_races` (race indices) and `p5_rows` (frame rows).
p6_filter_state <- function(cf, p_cut, r_cut) {
  pass <- cf$win_model > p_cut & cf$ratio > r_cut
  if (!any(pass)) {
    return(list(bet_races = integer(0), p5_rows = integer(0)))
  }
  o <- cf$order_by_prob
  op <- o[pass[o]]
  p5 <- op[!duplicated(cf$race_ix[op])]
  list(bet_races = sort(unique(cf$race_ix[pass])), p5_rows = p5)
}

#' The rows one (picker, filter) rule backs
#'
#' @param cf Output of `p6_compile_frame()`.
#' @param picker Picker name.
#' @param p_cut,r_cut The filter's cuts; `-Inf` for the no-filter row.
#' @param state Optional precomputed `p6_filter_state()`, to avoid redoing the
#'   filter once per picker.
#' @return An integer vector of frame row indices, one per race bet.
p6_rule_rows <- function(cf, picker, p_cut, r_cut, state = NULL) {
  if (is.null(state)) state <- p6_filter_state(cf, p_cut, r_cut)
  if (length(state$bet_races) == 0L) return(integer(0))
  if (picker == "P5") return(state$p5_rows)
  cf$picker_idx[[picker]][state$bet_races]
}

#' Score one rule on one settlement table
#'
#' Flat stake. A row whose settlement entry is absent (`NA` stake) is dropped,
#' matching `p6_ledger()`'s inner join, and is counted in `n_races_selected`
#' but not in `n_bets`.
#'
#' @param cf Output of `p6_compile_frame()`.
#' @param rows Output of `p6_rule_rows()`.
#' @param bet Settlement table name.
#' @return A flat named list of the row's columns. A list rather than a tibble
#'   because the sweep builds 25,220 of these and one `bind_rows()` at the end
#'   is an order of magnitude cheaper than 25,220 tibble constructions.
p6_score_rule <- function(cf, rows, bet) {
  empty <- function(n_sel) list(
    n_races_selected = n_sel, n_bets = 0L, n_wins = 0L, total_stake = 0,
    gross_return = 0, profit = 0, roi = NA_real_, roi_fair = NA_real_,
    roi_drop_top1 = NA_real_, mean_sp = NA_real_, median_sp = NA_real_,
    share_favourite = NA_real_, mean_model_prob = NA_real_,
    mean_ratio = NA_real_
  )
  n_sel <- length(rows)
  if (n_sel == 0L) return(empty(0L))

  st <- cf$stake[rows, bet]
  ok <- !is.na(st) & st > 0
  r  <- rows[ok]
  if (length(r) == 0L) return(empty(n_sel))
  st <- st[ok]

  rt <- cf$ret[r, bet]
  fr <- cf$fair[r, bet]
  ts <- sum(st)
  gross <- sum(rt)
  drop1 <- if (length(r) <= 1L) NA_real_ else {
    k <- which.max(rt)
    (gross - rt[k] - (ts - st[k])) / (ts - st[k])
  }
  list(
    n_races_selected = n_sel,
    n_bets = length(r), n_wins = sum(rt > 0),
    total_stake = ts, gross_return = gross, profit = gross - ts,
    roi = (gross - ts) / ts,
    roi_fair = (sum(fr) - ts) / ts,
    roi_drop_top1 = drop1,
    mean_sp = mean(cf$sp[r]), median_sp = stats::median(cf$sp[r]),
    share_favourite = mean(cf$sp_rank[r] == 1),
    mean_model_prob = mean(cf$win_model[r]),
    mean_ratio = mean(cf$ratio[r])
  )
}

#' Score one rule on one settlement table, as a tibble
#'
#' The one-row-tibble wrapper the shortlist and staking paths want.
#'
#' @inheritParams p6_score_rule
#' @return A one-row tibble.
p6_score_rule_tbl <- function(cf, rows, bet) {
  tibble::as_tibble(p6_score_rule(cf, rows, bet))
}

#' Sweep every (picker, filter) rule on one split
#'
#' @param cf Output of `p6_compile_frame()`.
#' @param grid Output of `p6_filter_grid()`.
#' @param pickers Output of `p6_pickers()`.
#' @return A long tibble, one row per (picker, filter, bet).
p6_sweep <- function(cf, grid, pickers = p6_pickers()) {
  pn <- names(pickers)
  nb <- length(cf$bets)
  out <- vector("list", nrow(grid) * length(pn) * nb)
  z <- 0L
  for (g in seq_len(nrow(grid))) {
    p_cut <- grid$p_cut[g]
    r_cut <- grid$r_cut[g]
    state <- p6_filter_state(cf, p_cut, r_cut)
    for (nm in pn) {
      rows <- p6_rule_rows(cf, nm, p_cut, r_cut, state = state)
      for (b in cf$bets) {
        z <- z + 1L
        out[[z]] <- c(
          list(picker = nm, filter_id = grid$filter_id[g], p_cut = p_cut,
               r_cut = r_cut, no_filter = grid$no_filter[g], bet = b),
          p6_score_rule(cf, rows, b)
        )
      }
    }
  }
  dplyr::bind_rows(out) |>
    dplyr::mutate(rule = p6_rule_label(picker, p_cut, r_cut, no_filter),
                  .before = 1)
}

#' A rule's human-readable label
#'
#' @param picker,p_cut,r_cut,no_filter Rule components.
#' @return A character vector.
p6_rule_label <- function(picker, p_cut, r_cut, no_filter) {
  dplyr::if_else(
    no_filter,
    paste0(picker, " / no filter"),
    sprintf("%s / P>%.2f, ratio>%.2f", picker, p_cut, r_cut)
  )
}

# ---------------------------------------------------------------------------
# Picker agreement
# ---------------------------------------------------------------------------

#' Pairwise selection agreement between pickers at one filter
#'
#' Of the races where two pickers both bet, the fraction backing the same
#' horse. Any pair above `flag_at` is one arm, not two.
#'
#' @param cf Output of `p6_compile_frame()`.
#' @param p_cut,r_cut The filter's cuts.
#' @param label A label recorded on every row.
#' @param flag_at Agreement above which the pair is flagged as duplicate.
#' @return A long tibble of `a`, `b`, `n_both`, `share_same`, `duplicate`.
p6_picker_agreement <- function(cf, p_cut, r_cut, label, flag_at = 0.95) {
  pn <- names(p6_pickers())
  state <- p6_filter_state(cf, p_cut, r_cut)
  rows <- lapply(stats::setNames(pn, pn), function(nm)
    p6_rule_rows(cf, nm, p_cut, r_cut, state = state))

  tidyr::expand_grid(a = pn, b = pn) |>
    purrr::pmap(function(a, b) {
      ra <- rows[[a]]; rb <- rows[[b]]
      da <- cf$race_ix[ra]; db <- cf$race_ix[rb]
      common <- intersect(da, db)
      if (length(common) == 0L) {
        return(tibble::tibble(a = a, b = b, n_both = 0L,
                              share_same = NA_real_, duplicate = NA))
      }
      ia <- ra[match(common, da)]
      ib <- rb[match(common, db)]
      sh <- mean(cf$runner_id[ia] == cf$runner_id[ib])
      tibble::tibble(a = a, b = b, n_both = length(common), share_same = sh,
                     duplicate = a != b & sh > flag_at)
    }) |>
    purrr::list_rbind() |>
    dplyr::mutate(filter = label, p_cut = p_cut, r_cut = r_cut, .before = 1)
}

#' The worst-case agreement between each picker pair across the whole grid
#'
#' A pair can look distinct at one filter and duplicate at another. This takes
#' the maximum agreement over every filter placing at least `min_bets` bets,
#' which is the number that decides whether two pickers are really two.
#'
#' @param cf Output of `p6_compile_frame()`.
#' @param grid Output of `p6_filter_grid()`.
#' @param min_bets Minimum common races for a filter to count.
#' @return A tibble, one row per unordered pair.
p6_picker_agreement_max <- function(cf, grid, min_bets = 300L) {
  pn <- names(p6_pickers())
  pairs <- tidyr::expand_grid(ai = seq_along(pn), bi = seq_along(pn)) |>
    dplyr::filter(ai < bi) |>
    dplyr::transmute(a = pn[ai], b = pn[bi])

  acc <- purrr::map(seq_len(nrow(pairs)), function(i)
    list(a = pairs$a[i], b = pairs$b[i], max_share = -Inf, min_share = Inf,
         at_p = NA_real_, at_r = NA_real_, n_filters = 0L))

  for (g in seq_len(nrow(grid))) {
    p_cut <- grid$p_cut[g]; r_cut <- grid$r_cut[g]
    state <- p6_filter_state(cf, p_cut, r_cut)
    rows <- lapply(stats::setNames(pn, pn), function(nm)
      p6_rule_rows(cf, nm, p_cut, r_cut, state = state))
    for (i in seq_len(nrow(pairs))) {
      ra <- rows[[pairs$a[i]]]; rb <- rows[[pairs$b[i]]]
      da <- cf$race_ix[ra]; db <- cf$race_ix[rb]
      common <- intersect(da, db)
      if (length(common) < min_bets) next
      sh <- mean(cf$runner_id[ra[match(common, da)]] ==
                   cf$runner_id[rb[match(common, db)]])
      acc[[i]]$n_filters <- acc[[i]]$n_filters + 1L
      acc[[i]]$min_share <- min(acc[[i]]$min_share, sh)
      if (sh > acc[[i]]$max_share) {
        acc[[i]]$max_share <- sh
        acc[[i]]$at_p <- p_cut
        acc[[i]]$at_r <- r_cut
      }
    }
  }

  purrr::map(acc, function(x) tibble::tibble(
    a = x$a, b = x$b, n_filters = x$n_filters,
    max_share = dplyr::if_else(is.finite(x$max_share), x$max_share, NA_real_),
    min_share = dplyr::if_else(is.finite(x$min_share), x$min_share, NA_real_),
    at_p_cut = x$at_p, at_r_cut = x$at_r
  )) |>
    purrr::list_rbind() |>
    dplyr::mutate(duplicate_anywhere = !is.na(max_share) & max_share > 0.95)
}

# ---------------------------------------------------------------------------
# Selecting what carries forward to the test split
# ---------------------------------------------------------------------------

#' The rules that reach the test split, per bet type
#'
#' Exploratory, so this is a shortlist and not a declaration. Per bet type:
#'
#'   * the top 5 rows by validation ROI at the real starting price, among rows
#'     placing at least `min_bets` validation bets;
#'   * S1/K0, Owen's rule, as the series comparator — P5 at 0.15 / 1.30;
#'   * P2 with no filter, the market favourite in every race;
#'   * the best row from a DIFFERENT picker than the top row, so at least two
#'     pickers reach the test split.
#'
#' Coincident entries collapse to one rule carrying every role it plays,
#' rather than being scored twice.
#'
#' @param sweep Output of `p6_sweep()` on the validation slice.
#' @param bet The settlement table to shortlist for.
#' @param min_bets Minimum validation bets for a row to be eligible.
#' @param n_top How many top rows to take.
#' @return A tibble of shortlisted rules with a `roles` column.
p6_shortlist <- function(sweep, bet, min_bets = 300L, n_top = 5L) {
  pool <- sweep |>
    dplyr::filter(bet == !!bet, !is.na(roi), n_bets >= min_bets) |>
    dplyr::arrange(dplyr::desc(roi), picker, p_cut, r_cut)

  stopifnot(nrow(pool) > 0L)

  top <- pool |>
    dplyr::slice_head(n = n_top) |>
    dplyr::mutate(role = sprintf("validation top %d", dplyr::row_number()))

  owen <- sweep |>
    dplyr::filter(bet == !!bet, picker == "P5", !no_filter,
                  abs(p_cut - 0.15) < 1e-9, abs(r_cut - 1.30) < 1e-9) |>
    dplyr::mutate(role = "S1/K0, Owen's rule (series comparator)")
  stopifnot(nrow(owen) == 1L)

  fav <- sweep |>
    dplyr::filter(bet == !!bet, picker == "P2", no_filter) |>
    dplyr::mutate(role = "market favourite, every race (no model)")
  stopifnot(nrow(fav) == 1L)

  other <- pool |>
    dplyr::filter(picker != top$picker[1]) |>
    dplyr::slice_head(n = 1L) |>
    dplyr::mutate(role = sprintf("best row from a picker other than %s",
                                 top$picker[1]))

  dplyr::bind_rows(top, owen, fav, other) |>
    dplyr::group_by(rule, picker, filter_id, p_cut, r_cut, no_filter) |>
    dplyr::summarise(roles = paste(role, collapse = "; "), .groups = "drop") |>
    dplyr::mutate(bet = bet, .before = 1) |>
    dplyr::arrange(picker, p_cut, r_cut)
}

#' Score a shortlist on a split, with bootstrap intervals
#'
#' Intervals are CONTEXT, not a filter: nothing is excluded on their basis.
#'
#' @param cf Compiled frame for the split being scored.
#' @param shortlist Output of `p6_shortlist()` (one bet type, or several).
#' @param n_boot,seed Bootstrap replicates and RNG seed.
#' @return `shortlist` with the split's scores and interval attached.
p6_score_shortlist <- function(cf, shortlist, n_boot = 2000L, seed = 42L) {
  purrr::pmap(shortlist, function(bet, rule, picker, p_cut, r_cut,
                                  no_filter, roles, ...) {
    rows <- p6_rule_rows(cf, picker, p_cut, r_cut)
    s <- p6_score_rule_tbl(cf, rows, bet)
    bs <- p6_explore_bootstrap(cf, rows, bet, n_boot = n_boot, seed = seed)
    dplyr::mutate(s, bet = bet, rule = rule, picker = picker, p_cut = p_cut,
                  r_cut = r_cut, no_filter = no_filter, roles = roles,
                  ci_lo = bs$ci_lo, ci_hi = bs$ci_hi, .before = 1)
  }) |> purrr::list_rbind()
}

#' Race-level bootstrap interval on one rule's ROI
#'
#' Resamples races rather than bets, so a race carrying no bet can be drawn
#' and contribute zero — the universe convention `p6_bootstrap_roi()` uses.
#'
#' @param cf Compiled frame.
#' @param rows Output of `p6_rule_rows()`.
#' @param bet Settlement table name.
#' @param n_boot,seed Replicates and RNG seed.
#' @return A one-row tibble: `roi`, `ci_lo`, `ci_hi`, `n_races`.
p6_explore_bootstrap <- function(cf, rows, bet, n_boot = 2000L, seed = 42L) {
  n <- length(cf$races)
  stake <- ret <- numeric(n)
  if (length(rows)) {
    st <- cf$stake[rows, bet]
    ok <- !is.na(st) & st > 0
    r <- rows[ok]
    if (length(r)) {
      ix <- cf$race_ix[r]
      stake[ix] <- stake[ix] + st[ok]
      ret[ix]   <- ret[ix] + cf$ret[r, bet]
    }
  }
  roi <- function(s, t) if (sum(s) == 0) NA_real_ else (sum(t) - sum(s)) / sum(s)
  set.seed(seed)
  reps <- vapply(seq_len(n_boot), function(i) {
    ix <- sample.int(n, n, replace = TRUE)
    roi(stake[ix], ret[ix])
  }, numeric(1))
  tibble::tibble(
    roi = roi(stake, ret),
    ci_lo = stats::quantile(reps, 0.05, na.rm = TRUE, names = FALSE),
    ci_hi = stats::quantile(reps, 0.95, na.rm = TRUE, names = FALSE),
    n_races = n
  )
}

#' Validation rank against test rank
#'
#' The number that matters for live use: whether picking on validation ROI
#' picks anything useful. Ranks are within bet type, 1 = best.
#'
#' @param val,test Outputs of `p6_score_shortlist()` on the two splits.
#' @return A tibble with both ranks, their difference, and the per-bet-type
#'   rank correlation.
p6_rank_comparison <- function(val, test) {
  j <- val |>
    dplyr::select(bet, rule, picker, roles, val_roi = roi,
                  val_bets = n_bets, val_mean_sp = mean_sp) |>
    dplyr::left_join(
      dplyr::select(test, bet, rule, test_roi = roi, test_bets = n_bets,
                    test_mean_sp = mean_sp),
      by = c("bet", "rule")
    ) |>
    dplyr::group_by(bet) |>
    dplyr::mutate(
      val_rank = rank(-val_roi, ties.method = "min"),
      test_rank = rank(-test_roi, ties.method = "min"),
      rank_move = test_rank - val_rank
    ) |>
    dplyr::ungroup()

  corrs <- j |>
    dplyr::group_by(bet) |>
    dplyr::summarise(
      n_rules = dplyr::n(),
      spearman = suppressWarnings(stats::cor(val_roi, test_roi,
                                             method = "spearman")),
      pearson = suppressWarnings(stats::cor(val_roi, test_roi)),
      mean_abs_rank_move = mean(abs(rank_move)),
      .groups = "drop"
    )

  list(table = dplyr::arrange(j, bet, val_rank), correlations = corrs)
}

# ---------------------------------------------------------------------------
# Stage 3 — staking, separately
# ---------------------------------------------------------------------------

#' The three staking rules, as functions of the backed rows
#'
#' K0 flat; K1 edge-proportional; K2 quarter-Kelly. The constants are
#' `R/p6_rules.R`'s, reused unchanged so stage 3 prices the same arms the
#' previous draft did. K1 and K2 both stake zero where the model probability
#' does not exceed the price, which makes them selection rules as well as
#' staking rules — the whole reason staking is a separate stage here, and the
#' reason `share_zero_stake` is reported rather than buried in an ROI.
#'
#' @return A named list of `list(label, fn)`, `fn` taking the compiled frame
#'   and row indices and returning the per-leg stake.
p6_explore_stakings <- function() {
  list(
    K0 = list(label = "K0 flat, 1 unit",
              fn = function(cf, r) rep(1, length(r))),
    K1 = list(
      label = sprintf("K1 edge-proportional, (P_mod - P_mkt) / %.2f, cap %d",
                      P6_EDGE_UNIT, P6_STAKE_CAP),
      fn = function(cf, r) pmin(
        P6_STAKE_CAP,
        pmax(0, (cf$win_model[r] - cf$win_market[r]) / P6_EDGE_UNIT))
    ),
    K2 = list(
      label = sprintf("K2 quarter-Kelly at P_mod against SP / %.2f, cap %d",
                      P6_KELLY_UNIT, P6_STAKE_CAP),
      fn = function(cf, r) {
        b <- cf$sp[r] - 1
        f <- (cf$win_model[r] * b - (1 - cf$win_model[r])) / b
        pmin(P6_STAKE_CAP, pmax(0, 0.25 * f / P6_KELLY_UNIT))
      }
    )
  )
}

#' Score one rule under one staking rule
#'
#' @param cf Compiled frame.
#' @param rows Output of `p6_rule_rows()`.
#' @param bet Settlement table name.
#' @param staking One entry of `p6_explore_stakings()`.
#' @return A one-row tibble, including the share of SELECTED races staked zero.
p6_score_staked <- function(cf, rows, bet, staking) {
  n_sel <- length(rows)
  if (n_sel == 0L) {
    return(tibble::tibble(n_races_selected = 0L, n_bets = 0L, n_wins = 0L,
                          total_stake = 0, profit = 0, roi = NA_real_,
                          roi_fair = NA_real_, mean_stake = NA_real_,
                          max_stake = NA_real_, share_zero_stake = NA_real_,
                          mean_sp = NA_real_))
  }
  st_mult <- cf$stake[rows, bet]
  unit <- staking$fn(cf, rows)
  # A race is "staked zero" when the staking rule puts nothing on it. A race
  # whose settlement entry is absent is not a zero stake, it is not a bet at
  # all, so it leaves the denominator too.
  exists <- !is.na(st_mult) & st_mult > 0
  share_zero <- if (sum(exists) == 0L) NA_real_ else
    mean(unit[exists] <= 0)

  keep <- exists & unit > 0
  r <- rows[keep]
  if (length(r) == 0L) {
    return(tibble::tibble(n_races_selected = n_sel, n_bets = 0L, n_wins = 0L,
                          total_stake = 0, profit = 0, roi = NA_real_,
                          roi_fair = NA_real_, mean_stake = NA_real_,
                          max_stake = NA_real_, share_zero_stake = share_zero,
                          mean_sp = NA_real_))
  }
  u  <- unit[keep]
  ts <- sum(u * st_mult[keep])
  gr <- sum(u * cf$ret[r, bet])
  fr <- sum(u * cf$fair[r, bet])
  tibble::tibble(
    n_races_selected = n_sel, n_bets = length(r),
    n_wins = sum(cf$ret[r, bet] > 0),
    total_stake = ts, profit = gr - ts, roi = (gr - ts) / ts,
    roi_fair = (fr - ts) / ts,
    mean_stake = mean(u * st_mult[keep]), max_stake = max(u * st_mult[keep]),
    share_zero_stake = share_zero, mean_sp = mean(cf$sp[r])
  )
}

#' Stage 3: staking on a set of rules, on one split
#'
#' @param cf Compiled frame.
#' @param rules A tibble of `bet`, `rule`, `picker`, `p_cut`, `r_cut`, and a
#'   `role` column saying why the rule is here.
#' @param stakings Output of `p6_explore_stakings()`.
#' @return A long tibble, one row per (rule, staking).
p6_staking_sweep <- function(cf, rules, stakings = p6_explore_stakings()) {
  purrr::pmap(rules, function(bet, rule, picker, p_cut, r_cut, role, ...) {
    rows <- p6_rule_rows(cf, picker, p_cut, r_cut)
    purrr::imap(stakings, function(k, knm)
      dplyr::mutate(p6_score_staked(cf, rows, bet, k),
                    bet = bet, rule = rule, role = role, staking = knm,
                    staking_label = k$label, .before = 1)) |>
      purrr::list_rbind()
  }) |> purrr::list_rbind()
}
