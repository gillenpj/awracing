# Provenance: `gbt_tuning_final.rds`

This file records exactly how `gbt_tuning_final.rds` (committed at the
project root, alongside this document) was produced, so it can be
regenerated and checked rather than taken on trust. See CLAUDE.md
("Paper 3 plan" — tuning grid budget, divergence guard, and the
"`papers/03_gradient_boosted_trees/` scaffolded and wired" entry) for the
full narrative this summarises.

## What produced it

- **Script:** `scripts/run_gbt_tuning.R`, run as:
  ```
  "C:/Program Files/R/R-4.6.0/bin/Rscript.exe" scripts/run_gbt_tuning.R
  ```
  (run via PowerShell/`Start-Process`, detached — native xgboost calls
  crash under a POSIX/Git-Bash shell environment on this machine, so
  PowerShell is the required launch path.)
- **Code state (git SHA):** `7be1cf5bb74f913b331337e69a07778439768eae`
  ("Sweep for the log() shadowing bug elsewhere; close the gate's blind
  spot", committed 2026-08-21 19:01:58 +0100) — the commit immediately
  preceding the run's launch. Confirmed this is the exact code state the
  run used: `git diff --name-only 7be1cf5 73298f8` (the next commit that
  *recorded* results, after the run had finished) touches only
  `CLAUDE.md` and `scripts/diagnose_nrounds_cap.R` — neither read by
  `run_gbt_tuning.R` — so no code the script depends on changed between
  launch and completion.
- **Files that code state comprises:** `R/pl_objective.R` (custom
  Plackett–Luce objective/eval, `{data.table}`-vectorised,
  `base::log()`-qualified — this is the commit that closed the `log()`
  name-shadowing bug that caused the earlier 100%-divergence incident),
  `R/gbt_data.R` (feature matrix / `FEATURE_COLS`), `R/gbt_folds.R`
  (race-grouped CV folds), `R/gbt_tuning.R` (grid, one-fold fit,
  selection, final fit, permutation importance), plus
  `R/build_going_features.R`, `R/build_extended_features.R`,
  `R/model_fitting_p2.R` for feature construction upstream of the matrix.
- **Date/time:** started 2026-08-21 19:02 (BST, +0100); `gbt_tuning_final.rds`
  written 2026-08-22 06:01 (BST, +0100). Wall-clock **~10h59m**
  (~11h) for the full grid + Stage E.
- **Seed:** `42L`, set in **two** places, both load-bearing (R's
  `set.seed()` alone does not control xgboost's own RNG for
  `subsample`/`colsample_bytree` draws — see CLAUDE.md's divergence-guard
  note): `set.seed(42L)` in R, and `seed = 42L` inside xgboost's own
  `params` list, in `R/gbt_tuning.R::fit_one_fold()` and
  `fit_final_model()`.

## The grid

`R/gbt_tuning.R::build_tuning_grid()` — full factorial, 72 points:

| Hyperparameter       | Values tested        |
|-----------------------|-----------------------|
| `max_depth`           | 2, 3, 4, 6            |
| `eta`                 | 0.01, 0.03, 0.1        |
| `min_child_weight`    | 1, 5, 20               |
| `subsample`           | 0.7, 1.0               |
| `colsample_bytree`    | 0.7 (fixed — see fallback ladder) |

4 × 3 × 3 × 2 × 1 = **72 points**, each fit under **race-grouped 5-fold
CV** (`R/gbt_folds.R::make_race_folds(v = 5, seed = 42)`, on the 5,022
complete-case training races), `nrounds` capped at 2000 with early
stopping at 50 rounds on fold-mean `pl_r2` — **72 × 5 = 360 fits**.

### Fallback ladder (fixed before any test-set number)

The full, un-reduced grid also varies `colsample_bytree` over
`{0.7, 1.0}`: 144 points × 5 folds = 720 fits, projected ~12.9 hours —
not comfortably under the project's ~12-hour single-run budget. The
fixed rule was: stop cutting as soon as the projection drops under 12
hours.

1. **Applied:** `colsample_bytree → {0.7}` only. 144 → 72 points, 360
   fits, projected ~6.5 hours. **Stopped here** — comfortably under 12
   hours, so the remaining rungs were not needed:
2. (not applied) `subsample → {0.7}` only.
3. (not applied) drop `eta = 0.01`.
4. (not applied) narrow `min_child_weight` to `{1, 20}`.

`max_depth`, the 5-fold count, the `nrounds` cap (2000), and the
early-stopping patience (50 rounds) were left untouched at every rung.

**Measured wall-clock (~11h for 72 points) came in above the ~6.5h
projection** — at that measured rate the un-reduced 144-point grid would
have taken **~22 hours**, confirming the ladder cut was necessary, not
cosmetic.

## Selection rule and tie-break

`R/gbt_tuning.R::select_best_config()`: highest `fold_mean_pl_r2`; among
points within **0.001** of the maximum, prefer lowest `max_depth`, then
lowest `mean_best_iteration`. Fixed in advance of seeing results.

- Grid maximum `fold_mean_pl_r2`: **0.068666** (depth=4, eta=0.01,
  min_child_weight=20, subsample=0.7).
- **11 of 72 points** fell within the 0.001 tie window.
- Selected point (shallowest, fewest rounds among the 11): `tie_break =
  TRUE` in the saved object.
- A later paired-fold check (same 5 folds throughout the grid, so paired
  SE is the correct yardstick — see CLAUDE.md) found only 3 of 72 points
  statistically indistinguishable from the max at 1 paired SE, and the
  selected point is *not* one of them (~1.26 paired SE from the max).
  The fixed rule stands regardless — pre-declaration is the point — but
  a reader should not read "selected" as "tied" under a stricter test.
  A follow-up refit of the untied grid maximum found the top-10
  gain-importance ranking nearly identical to the selected point's, so
  the tie-break's practical stakes are low.

## Selected configuration

| Field | Value |
|---|---|
| `max_depth` | 3 |
| `eta` | 0.03 |
| `min_child_weight` | 1 |
| `subsample` | 0.7 |
| `colsample_bytree` | 0.7 |
| `fold_mean_pl_r2` | 0.06776123 |
| `fold_sd_pl_r2` | 0.00505687 |
| `mean_best_iteration` | 698.4 |
| per-fold `pl_r2` | 0.0677844, 0.06596676, 0.07611499, 0.06642158, 0.06251842 |
| this point's own 5-fold CV elapsed time | 504.5s (~8.4 min) |

**Not a boundary optimum** (`max_depth ≠ 6`, `eta ≠ 0.1`) — the
`selected_boundary` flag in the saved object is `FALSE`.

**Stage E refit:** all training data, no early stopping (none possible —
no held-out data remains), `nrounds = round(mean_best_iteration) = 698`
(fold-mean, not fold-median or fold-max — a deliberate choice, see
CLAUDE.md). In-sample `train_pl_r2` from that refit: **0.09200074**
(compare: paper 2b's own training `pl_r2`, computed the identical way,
is 0.05415977 — an in-sample number only, not evidence of anything out
of sample).

## Divergence

**Zero divergence events across all 72 grid points** (`nrow(all_divergence)
== 0`, `n_grid_points_with_divergence == 0` in the saved object) — the
decisive confirmation that the earlier multi-day, 100%-divergence
incident (three sequential diagnoses; the real cause was a `log()`
name-shadowing bug in the driver script, not numerical instability or
RNG seeding — see CLAUDE.md) was fully closed by the `7be1cf5` fix this
run's code state reflects. Divergence, if it recurs on a future
re-generation, is logged (not silently floored) to
`gbt_tuning_divergence.csv` by the same run — see `R/gbt_tuning.R`'s
`diag_env` mechanism.

## How to check this file

1. Confirm the code state: `git show 7be1cf5:R/pl_objective.R` (etc.) and
   diff against a fresh checkout, or just check out that commit's tree
   for the six files listed above.
2. Re-run `scripts/run_gbt_tuning.R` from a clean checkout (~11 hours;
   see CLAUDE.md for why this is a deliberate standalone run, not a
   `{targets}` target).
3. Compare the resulting `gbt_tuning_final.rds` against this document:
   same grid, same seed ⇒ byte-identical `all_results` (xgboost + R seeded
   deterministically per the divergence-guard fix), same selected
   configuration, same zero-divergence count.
