# awracing — Claude Code memory

Horse racing prediction model on UK All-Weather Flat racing, 2006–2015.
Goal: replicate Owen (2019), *Statistical Models of Horse Racing Outcomes
Using R*, on AW data (paper 1), then extend in two further papers — one
adding features to the same conditional-logit backbone, and one moving
to a ranking-level Plackett–Luce / exploded-logit model with a
PL R²-style tree fit.

## Tech stack
- R 4.6 (use the full path `"C:/Program Files/R/R-4.6.0/bin/Rscript.exe"`
  on this machine — see `~/.claude/.../memory/rscript_path.md`)
- {renv} for packages (`use.cache = FALSE`)
- {targets} + {tarchetypes} pipeline; entry point `_targets.R`
- {DBI} + {RMariaDB} for the Smartform MySQL database
- {tidyverse}, {tidymodels}, {mlogit} for modelling
- {quarto} for the papers under `papers/`. Quarto CLI is bundled with
  RStudio at `C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe`;
  set `QUARTO_PATH` to that location for ad-hoc `tar_make()` invocations.

## Tidyverse-first style — this is the main convention
- Use `dplyr` verbs over base subsetting: `filter()`, `mutate()`, `select()`,
  `summarise()`, `group_by()`, `arrange()`.
- Native pipe `|>`, never `%>%`. Match r4ds (2nd ed) style throughout.
- Return tibbles, not data.frames. No `stringsAsFactors`.
- Strings → {stringr}. Dates → {lubridate}. Factors → {forcats}. I/O → {readr}.
- Plots → {ggplot2} only. No base R plotting.
- Iteration → `purrr::map_*()` over `for`. Use `across()` for column-wise ops.
- Prefer `mutate(across(c(a, b), as.integer))` over multi-line boilerplate.
- Function signatures: snake_case; accept and return tibbles where natural.
- Roxygen2 comments on every function in `R/`.
- Inside `R/*.R`, qualify package functions with `::` (e.g. `dplyr::mutate()`)
  rather than `library()` at the top. Keeps dependencies explicit and avoids
  namespace surprises in {targets}. `_targets.R` may use `library()` for
  {targets} and {tarchetypes} themselves.

## Project structure
- `R/` — functions, sourced by `_targets.R` via `targets::tar_source()`.
- `sql/` — SQL queries, read by `R/db.R::read_sql_file()`.
- `papers/` — one Quarto sub-project per paper. Current set:
  - `papers/01_replication/` — paper 1 (Owen replication on AW).
    Master document is `index.qmd`, which `{{< include >}}`s
    `_01_data.qmd`, `_02_exploratory.qmd`, `_03_results.qmd`,
    `_appx_derivation.qmd`. `_helpers.R` holds plotting helpers used
    inside the section files. Bibliography is `references.bib`.
    Renders to `_output/index.html` via `tar_quarto(paper_1_replication)`.
  - Future: `papers/02_extended_factors/`, `papers/03_pl_r2_trees/`.
- `notes/` — reference material kept for citation but no longer
  maintained as a working journal:
  - `Statistical Models of Horse Racing Outcomes Using R (Owen).pdf` —
    the paper being replicated.
  - `awracing - Journal.docx` — derivation of conditional logit and
    related notes. The derivation has been ported into
    `papers/01_replication/_appx_derivation.qmd`.
  - `British_Racing_Classification_System.md.docx` — classification-
    system reference, source for `papers/01_replication/_01_data.qmd`.
  - `Guide to all weather tracks in the UK 1022.docx` — AW course
    reference, also feeds `_01_data.qmd`.
  - `session_1.md` — historical session journal; not maintained going
    forward.
- `scripts/` — diagnostic R scripts. Temporary by default. Currently:
  - `verify_rebuild.R` — standing integrity check; keep.
  - `check_calib_data.R`, `find_cutoff_date.R` — one-shot diagnostics
    flagged for removal once the paper-1 rewrite lands.
- `_targets/` — cached pipeline objects (gitignored).
- `renv/`, `renv.lock` — package state.

## Paper / Quarto convention

- **One Quarto project per paper** under `papers/<NN>_<slug>/`. Each
  project has its own `_quarto.yml` with `output-dir: _output` (required
  by `tarchetypes::tar_quarto()`).
- Each paper is a single-document Quarto article. The master
  `index.qmd` carries the YAML, abstract, intro, and `{{< include >}}`
  directives for each section. Section files are prefixed with `_` so
  Quarto does not try to render them standalone.
- `_quarto.yml` lists only `index.qmd` under `project.render`; all the
  partial files are pulled in via includes.
- Bibliography is a per-paper `references.bib`; the format spec in
  `_quarto.yml` carries `bibliography: references.bib`.
- One `tar_quarto()` target per paper in `_targets.R`. `extra_files`
  lists all the partial qmds, the helpers `.R`, the bibliography, and
  the YAML so any edit triggers a re-render.

## targets conventions
- One function per `tar_target()`. Pure functions: inputs → outputs, no
  side effects (no writing to disk, no global state).
- DB connections: open and close inside the function. Use the
  `connect_smartform()` / `disconnect_smartform()` helpers in `R/db.R`.
- Plot targets return ggplot objects. Save to disk only inside Quarto docs.
- Run: `targets::tar_make()`. Load into session: `targets::tar_load(name)`.
  Inspect graph: `targets::tar_visnetwork()`.

## Data-scope decisions (do not relitigate)

### Full cross-surface career history (not AW-only)
We extract **full cross-surface career history** for every AW horse, not
AW-only history. The median AW horse runs only 33% of its career on AW
courses; 8.2% of AW runner-race observations have no prior AW history.
Restricting to AW history alone biases daysLTO and underestimates form.
This drives `extract_career_history()` in `R/extract_runners.R`.

### Filter on `race_type = 'All Weather Flat'`, not `all_weather = 1`
The `all_weather` flag is unreliable: ~2,547 races at our four courses
are coded `race_type = 'All Weather Flat'` but have `all_weather != 1`,
and Southwell loses 30% of its history under the flag-based filter.
`race_type` is consistent across the table. Set in
`sql/qualifying_races.sql`.

### Date range 2006-01-01 to 2015-10-14
The British class system was restructured 1 Jan 2006. Pre-2006 data
includes multi-digit class codes (11, 42, 53, 64, …) whose meaning is
not comparable with the 2006+ 1–7 scheme; pooling the two encodings
biases any class-based feature. We restrict to 2006+ rather than recode.
Set as the `date_from` arg in `_targets.R`.

### AW course scope: Kempton, Lingfield, Southwell, Wolverhampton
Deliberately excluded: Chelmsford City (opened Jan 2015 — only 9 months
inside the window), Dundalk (Irish, not UK), Newcastle (AW track opened
May 2016, after the window). Scope is "UK AW, full window". Held in the
`aw_courses` target as the single source of truth.

### Race selection: Class 2–5 handicaps only
Filter: `class IN (2, 3, 4, 5)` (exclude Class 1) and `handicap = 1`
(handicap races only). Class 1 is Group/Listed (conditions racing,
mechanically different); non-handicap races within Classes 2–5 are
conditions races, which carry a different weight structure. Handicap
structure is the foundation of Owen's model and must be the only
race-type in scope. Data scope after this filter: 7,507 Class 2–5
handicap races at SQL level, reducing to 7,441 `qualifying_races`
after the R-level cuts (post-Non-Runner field size and dead-heat
removal). Window: 2006-01-01 to 2015-10-14, four AW courses,
non-maiden, declared field 4–16. Prize money and distance are *not*
filtered — these are within-class variation rather than class
differences, and will be tested as features in paper 2 if needed.

### Winner is `coalesce(amended_position, finish_position) == 1`
Handles the 7 disqualified-winner races where Smartform records the
promoted winner via `amended_position = 1` while the DQ'd horse has
`finish_position` NA'd. Plain coalesce is safe: across the full
`historic_runners` table (1.72M rows), `amended_position` is either
NULL (1.71M) or a real position 1–30 (3,399); zero literal-0 rows.
Implemented in `extract_runners_for_races()` in `R/extract_runners.R`.

### Dead-heat races are dropped
The 35 races with two `won == 1` rows under the new winner rule are
removed. `mlogit` cannot fit a choice set with !=1 chosen alternative.
Enforced via `sum(won) == 1L` in the race-level filter in
`extract_runners_for_races()`.

### Field size >= 4 is applied *after* Non-Runner removal
The SQL HAVING clause counts declared runners, but Smartform's
"Non-Runner" entries are dropped in R, leaving some races below 4
actual starters. Re-applied as `n() >= 4L` in the race-level filter
in `extract_runners_for_races()`.

### `amended_position` semantics (empirical)
`historic_runners.amended_position` is NULL when the race result was
not amended; when populated, it is the horse's *post-amendment
official* placing (1, 2, …). For the post-DQ horse it is the demoted
position; for the promoted horse it is the new winning position.
The Smartform manual was unavailable to confirm; the encoding above is
verified empirically across the full 1.72M-row table.

### Train/test split: chronological 70/30 with cutoff 2012-12-30
70/30 split by race date. Cutoff frozen at 2012-12-30 so the split
boundary is reproducible against an exact calendar date irrespective
of upstream changes. Every runner in a race stays together in one
set — no within-race information crosses the boundary.

## Pipeline / feature engineering notes

### tarchetypes auto-wiring of Quarto includes
`tarchetypes::tar_quarto()` parses the master `.qmd` for
`tar_read()` / `tar_load()` calls and turns the referenced targets
into dependencies. Files brought in via `{{< include >}}` are NOT
auto-scanned, so list them under `extra_files` so edits invalidate
the render, and put their `tar_load(...)` calls in the master setup
chunk so dependency detection picks them up centrally.

### mlogit alt.var must be a per-race index, not the population runner_id
{mlogit} dimensions internal design / Hessian matrices by
`nlevels(alt.var)`. Passing the population-wide `runner_id` (~10k+
horses) blows those matrices up by a factor of ~600 and causes a
~16 GB hang. `prepare_mlogit_data()` builds `horse_ref = 1..n_runners`
per race for use as `alt.var` instead. The three-part formula
`won ~ ... | 0 | 0` is also load-bearing — a two-part `| 0` interacted
badly with high-cardinality `alt.var` in earlier versions.

## Modelling notes
- Owen's model is a conditional logit (McFadden) fitted with {mlogit}.
  Race is the choice set, no intercept, no race-specific covariates.
- {tidymodels} has no conditional logit engine. Use {mlogit} directly
  for fitting; use {rsample} for race-level splits and {yardstick} for
  metrics where they fit naturally.
- Splits are **race-level**, never row-level. Grouping variable:
  `race_id`.
- Paper 1 headline is the *reduced* fit (terms with all levels at
  p > 0.05 dropped), to parallel Owen's Table 3 — itself a reduced
  model. Calibration and the P1 / P2 scoring rules are evaluated on
  the held-out test set, not in-sample.

## Owen's Table 3 — the comparison baseline
Final (reduced) model on UK Flat Turf 2014–2016. Exact estimates
from the published Table 3:
- `age_diff`     −0.152 (SE 0.0313, p < 0.001)
- `sireSR`        0.048 (SE 0.0093, p < 0.001)
- `trainerSR`     0.051 (SE 0.0093, p < 0.001)
- `daysLTO`      −0.004 (SE 0.0018, p = 0.021) — raw, not log
- `position11`    0.607 (SE 0.0918, p < 0.001)
- `position12`    0.329 (SE 0.1003, p < 0.001)
- `position13`    0.313 (SE 0.1026, p < 0.001)
- `position14`    0.157 (SE 0.1081, p < 0.001)
- `position21`    0.377 (SE 0.0970, p < 0.001)
- `position22`    0.373 (SE 0.0975, p < 0.001)
- `position23`    0.075 (SE 0.1070, p < 0.001)
- `position24`    0.220 (SE 0.1048, p < 0.001)
- `entire`        0.489 (SE 0.1294, p < 0.001)
- `gelding`       0.548 (SE 0.0946, p < 0.001)
- `cheekpieces`  −0.503 (SE 0.1454, p = 0.001)
- Dropped as non-significant in the reduction: `position3` (all
  four levels), `blinkers`, `visor`, `tonguetie`.

These values are carried in the `owen_table3` chunk inside
`papers/01_replication/_03_results.qmd`. Note that Owen uses raw
`daysLTO` while the AW fit uses `log(1 + daysLTO)`, so the two
estimates are not directly comparable on that row.

## §3.4 backtest (Future Predictive Performance)
- Owen's bet-selection rule, replicated verbatim for the AW headline:
  stake one unit on horse $j$ in race $k$ when
  $\hat{P}_{jk} > 0.15$ AND ratio = $\hat{P}_{jk} / P^{\text{mkt}}_{jk} > 1.3$.
  Market probability is over-round-adjusted starting price, renormalised
  per race. Owen reports +20.5% ROI on 264 bets on his Turf test set.
- Threshold sweep for sensitivity analysis: ratio threshold
  $\tau \in \{0.9, 0.95, \ldots, 2.0\}$ (step 0.05), model-probability
  filter held at 0.13 (chosen on the AW scoring picture rather than
  Owen's 0.15). 90% CI via race-level bootstrap, B = 2000, seed 42.
- Owen's training-set scoring reference values (his §3.3, in-sample):
  P1_model = 0.120, P1_market = 0.136; P2_model = 0.860, P2_market = 0.831.
  These are NOT directly comparable to our P1 / P2 in
  `_03_results.qmd`, which are out-of-sample on the test set.
- Targets (in `_targets.R`): `fitted_final`, `test_predictions`,
  `model_market_ratio`, `backtest_naive`, `backtest_sweep`. Helpers
  live in `R/scoring.R`.

## Key references
- Owen, A. (2019), *Statistical Models of Horse Racing Outcomes Using R*,
  MathSport International 2019 Proceedings — the model paper 1 replicates.
- r4ds.hadley.nz — tidyverse style guide
- tmwr.org — tidymodels patterns
- books.ropensci.org/targets — pipeline patterns
- `notes/manual.pdf` (if present) — Smartform DB schema

## Out of scope (for paper 1)
- Live betting infrastructure (this is research, not deployment)
- Other surfaces (turf, jumps) beyond using their data for feature
  history (paper 2 may add interactions)
- Pre-2003 data (Smartform starts there)
- Anything beyond Owen's §3.4 — extended features and the exploded
  conditional logit are paper 2; PL R²-tree work is paper 3
