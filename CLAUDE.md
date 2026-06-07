# awracing — Claude Code memory

Statistical models of UK All-Weather racing outcomes, built on the
Smartform MySQL database in R. Multi-paper series; current state and
forward plan below.

## Series status (read this first)

- **Paper 1 — DONE.** *Replicating Owen (2019) on UK All-Weather
  Flat handicaps, 2006–2015.*
  - Source: `papers/01_replication/`
  - Rendered output (committed): `docs/paper1/index.html` and
    `docs/paper1/index.pdf`
  - GitHub repo: <https://github.com/gillenpj/awracing>
  - GitHub Pages: <https://gillenpj.github.io/awracing/paper1/>
  - One-line summary of the result: coefficient picture broadly
    consistent with Owen; reduced model fails the §3.4 betting
    backtest (−28% ROI on 1,713 bets vs Owen's reported +20.5% on
    264 bets), which the paper's discussion ascribes primarily to
    the starting price aggregating richer information than the
    13-feature predictor set.
- **Paper 2 — planning / starting.** *Extended feature set with
  automated feature selection, refit with the exploded conditional
  logit.* See "Paper 2 plan" below.
- **Paper 3 — planned, model class change.** *Non-linear /
  interaction-friendly model class, applied to AW racing.* See
  "Paper 3 plan" below.
- **Beyond the papers — possible direction.** Live Smartform feed
  + paper-trading on Betfair, exploiting early-market non-
  convergence. See "Longer-term direction" below.

## Tech stack
- R 4.6 — use the full path
  `"C:/Program Files/R/R-4.6.0/bin/Rscript.exe"` on this machine.
  See the user-memory entry `rscript_path.md` for why the default
  `Rscript` on PATH (4.2.2) fails on this project.
- `{renv}` for packages (`use.cache = FALSE` in init).
- `{targets}` + `{tarchetypes}` pipeline; entry point `_targets.R`.
- `{DBI}` + `{RMariaDB}` for the Smartform MySQL database.
- `{tidyverse}`, `{tidymodels}`, `{mlogit}` for modelling.
- `{quarto}` for the papers under `papers/`. Quarto CLI is bundled
  with RStudio at
  `C:/Program Files/RStudio/resources/app/bin/quarto/bin/quarto.exe`.

## Tidyverse-first style — main convention
- `dplyr` verbs over base subsetting: `filter()`, `mutate()`,
  `select()`, `summarise()`, `group_by()`, `arrange()`.
- Native pipe `|>`, never `%>%`. r4ds (2nd ed) style throughout.
- Return tibbles, not data.frames. No `stringsAsFactors`.
- Strings → `{stringr}`. Dates → `{lubridate}`. Factors →
  `{forcats}`. I/O → `{readr}`.
- Plots → `{ggplot2}` only. No base R plotting.
- Iteration → `purrr::map_*()` over `for`. `across()` for
  column-wise ops.
- Prefer `mutate(across(c(a, b), as.integer))` over multi-line
  boilerplate.
- Function signatures: snake_case; accept and return tibbles where
  natural.
- Roxygen2 comments on every function in `R/`.
- Inside `R/*.R`, qualify package functions with `::` (e.g.
  `dplyr::mutate()`) rather than `library()` at the top. Keeps
  dependencies explicit and avoids namespace surprises in
  `{targets}`. `_targets.R` may use `library()` for `{targets}` and
  `{tarchetypes}` themselves.

## Project structure
- `R/` — functions, sourced by `_targets.R` via `tar_source()`.
- `sql/` — SQL queries, read by `R/db.R::read_sql_file()`.
- `papers/` — one Quarto sub-project per paper.
  - `papers/01_replication/` — **paper 1, complete.** Master
    document `index.qmd` includes `_01_data.qmd`,
    `_02_exploratory.qmd`, `_03_results.qmd`,
    `_04_future_predictive.qmd`, `_appx_derivation.qmd`,
    `_appx_software.qmd` via `{{< include >}}`. `_helpers.R` holds
    plotting helpers used in the section files. Bibliography in
    `references.bib`.
  - `papers/02_extended_factors/` — paper 2, not yet created. When
    starting, mirror the paper-1 layout (master `index.qmd` +
    underscore-prefixed section partials + per-paper
    `references.bib` + `_quarto.yml` with
    `project.render: [index.qmd]` and `output-dir: _output`).
  - `papers/03_<slug>/` — paper 3, model-class change. Slug TBD
    once the model is picked.
- `docs/` — GitHub Pages publishing root. **Committed.**
  - `docs/index.html` — landing page, one entry per paper.
  - `docs/paper1/index.html` + `.pdf` — paper 1 rendered output,
    copied from `papers/01_replication/_output/` after each render.
  - Pages source is set to `main` branch, `/docs` folder.
  - Republishing convention: re-render via `tar_make()`, copy the
    new HTML + PDF into the matching `docs/paperN/` folder, commit
    + push.
- `notes/` — kept as a reference shelf only; not consumed by the
  pipeline.
  - `Statistical Models of Horse Racing Outcomes Using R (Owen).pdf`
    — the paper being replicated.
  - `paper2_seed_plackett_luce.md` — Plackett–Luce + exploded-logit
    derivation, cut from paper 1's appendix. Ready to lift into
    paper 2.
  - `paper2_seed_mixed_choice.md` — mixed discrete choice +
    race-level features mechanism, cut from paper 1's appendix.
    Ready to lift into paper 2 alongside the exploded-logit seed.
- `scripts/`
  - `verify_rebuild.R` — standing read-only integrity check on
    `qualifying_races` / `qualifying_runners` / `candidate_races`.
    Run after any change to SQL or the R-level filters in
    `R/extract_*.R`. Eight `stopifnot()` assertions; see file
    header.
- `_targets/` — pipeline cache (gitignored).
- `renv/`, `renv.lock` — package state.
- `.env` — DB credentials (gitignored). Read at runtime by
  `R/db.R::connect_smartform()` via `dotenv::load_dot_env()`.
- `_targets.yaml` — written by `tar_config_set()` in the qmd setup
  chunks; absolute path to the store; gitignored.

## Paper / Quarto convention
- One Quarto project per paper under `papers/<NN>_<slug>/`. Each
  has its own `_quarto.yml` with `output-dir: _output` (required by
  `tarchetypes::tar_quarto()`).
- Single-document Quarto manuscript. Master `index.qmd` carries
  YAML, abstract, intro, and `{{< include >}}` directives for the
  section partials. Partials are prefixed with `_` so Quarto does
  not try to render them standalone.
- `_quarto.yml` lists only `index.qmd` under `project.render`; all
  partials are pulled in via includes.
- Bibliography is a per-paper `references.bib`; the format spec in
  `_quarto.yml` carries `bibliography: references.bib`.
- One `tar_quarto()` target per paper in `_targets.R`. `extra_files`
  lists every partial qmd, the helpers `.R`, the bibliography, and
  `_quarto.yml`, so an edit to any of them triggers a re-render.
- `quiet = FALSE` on `tar_quarto()` — surface quarto's error
  output instead of "System command 'quarto.exe' failed".

## Render environment bootstrap (load-bearing)
`tar_quarto()` launches `quarto.exe` as a child process, which in
turn launches a fresh R session to execute the qmd's code chunks.
That child session only inherits **environment variables** — not
the parent's `.libPaths()` — so without help it picks system
`Rscript` (R 4.2.2, no renv packages installed) and the render
fails with cryptic errors. The top of `_targets.R` sets three env
vars to fix this:
- `R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep)`
  exposes the renv library to the child.
- `QUARTO_R = file.path(R.home("bin"), "Rscript.exe")` pins the
  child R to the same R the parent is running.
- `QUARTO_PATH` fallback to common Quarto install locations on
  this machine (RStudio's bundled copy first).

Inside each qmd's setup chunk, the targets store is located via
`rprojroot::find_root(rprojroot::has_file("awracing.Rproj"))` + the
literal `"_targets"`, **not** `here::here("_targets")`. `here`
caches its root marker and was being fooled by something in the
paper folder; `rprojroot` recomputes deterministically. The same
pattern is used in `_02_exploratory.qmd` to `source()` `_helpers.R`
robustly across the cwd that `tar_quarto` sets (project root) vs
direct `quarto render` (paper folder).

With those two fixes in place, the single command `tar_make()` from
the project root is the only render path needed.

## `{targets}` conventions
- One function per `tar_target()`. Pure functions: inputs →
  outputs, no side effects (no writing to disk, no global state).
- DB connections: open and close inside the function. Use the
  `connect_smartform()` / `disconnect_smartform()` helpers in
  `R/db.R`.
- Plot targets return ggplot objects. Save to disk only inside
  Quarto docs.
- Run: `targets::tar_make()`. Load into session:
  `targets::tar_load(name)`. Inspect graph:
  `targets::tar_visnetwork()`.

## Data-scope decisions (do not relitigate)

### Full cross-surface career history (not AW-only)
We extract **full cross-surface career history** for every AW
horse, not AW-only history. The median AW horse runs only 33% of
its career on AW courses; 8.2% of AW runner-race observations have
no prior AW history. Restricting to AW history alone biases
daysLTO and underestimates form. This drives
`extract_career_history()` in `R/extract_runners.R`.

### Filter on `race_type = 'All Weather Flat'`, not `all_weather = 1`
The `all_weather` flag is unreliable: ~2,547 races at our four
courses are coded `race_type = 'All Weather Flat'` but have
`all_weather != 1`, and Southwell loses 30% of its history under
the flag-based filter. `race_type` is consistent across the table.
Set in `sql/qualifying_races.sql`.

### Date range 2006-01-01 to 2015-10-14
The British class system was restructured 1 Jan 2006. Pre-2006
data includes multi-digit class codes (11, 42, 53, 64, …) whose
meaning is not comparable with the 2006+ 1–7 scheme; pooling the
two encodings biases any class-based feature. Restrict to 2006+
rather than recode. Set as `date_from` in `_targets.R`.

### AW course scope: Kempton, Lingfield, Southwell, Wolverhampton
Deliberately excluded: Chelmsford City (opened Jan 2015 — only
9 months inside the window), Dundalk (Irish, not UK), Newcastle
(AW track opened May 2016, after the window). Scope is "UK AW,
full window". Held in the `aw_courses` target.

### Race selection: Class 2–5 handicaps only
`class IN (2, 3, 4, 5)` AND `handicap = 1`. Class 1 is
Group/Listed (conditions racing, mechanically different);
non-handicap races within Classes 2–5 are conditions races with a
different weight structure. Data scope after this filter: 7,507
Class 2–5 handicap races at SQL level, 7,441 `qualifying_races`
after the R-level cuts. Window 2006-01-01 to 2015-10-14, four AW
courses, non-maiden, declared field 4–16. Prize money and distance
are *not* filtered.

### Winner is `coalesce(amended_position, finish_position) == 1`
Handles the 7 disqualified-winner races where Smartform records
the promoted winner via `amended_position = 1`. Plain coalesce is
safe: across the full `historic_runners` table (1.72M rows),
`amended_position` is NULL (1.71M) or a real position 1–30
(3,399); zero literal-0 rows. Implemented in
`extract_runners_for_races()` in `R/extract_runners.R`.

### Dead-heat races dropped
The 35 races with two `won == 1` rows are removed. `{mlogit}`
cannot fit a choice set with !=1 chosen alternative. Enforced via
`sum(won) == 1L` in the race-level filter in
`extract_runners_for_races()`.

### Field size >= 4 applied *after* Non-Runner removal
The SQL HAVING clause counts declared runners, but Smartform's
"Non-Runner" entries are dropped in R, leaving some races below 4
actual starters. Re-applied as `n() >= 4L` in
`extract_runners_for_races()`.

### `amended_position` semantics (empirical)
NULL when the race result was not amended; when populated, it is
the horse's post-amendment official placing. For the post-DQ horse
it is the demoted position; for the promoted horse the new winning
position. Verified empirically across the full 1.72M-row table.

### Train/test split: chronological 70/30 with cutoff 2012-12-30
70/30 split by race date. Cutoff frozen at 2012-12-30 so the split
is reproducible against an exact calendar boundary irrespective of
upstream changes. Race-level split; no within-race information
crosses the boundary.

## Pipeline / feature engineering notes

### `tarchetypes` auto-wiring of Quarto includes
`tar_quarto()` parses the master `.qmd` for `tar_read()` /
`tar_load()` calls and turns the referenced targets into
dependencies. Files brought in via `{{< include >}}` are NOT
auto-scanned, so list them under `extra_files` and put their
`tar_load(...)` calls in the master `index.qmd` setup chunk so
dependency detection picks them up centrally.

### `{mlogit}` `alt.var` must be a per-race index
`{mlogit}` dimensions internal design / Hessian matrices by
`nlevels(alt.var)`. Passing the population-wide `runner_id`
(~10k+ horses) blows those matrices up by ~600× and causes a
~16 GB hang. `prepare_mlogit_data()` builds
`horse_ref = 1..n_runners` per race for use as `alt.var`. The
three-part formula `won ~ ... | 0 | 0` is also load-bearing — a
two-part `| 0` interacted badly with high-cardinality `alt.var`
in earlier versions.

### `summary.mlogit` namespace dispatch
`extract_model_diagnostics()` calls `loadNamespace("mlogit")` at
the top so `summary(fitted_model)` dispatches to `summary.mlogit`
instead of falling back to `summary.default` (which returns an
atomic vector and breaks the rest of the function). The pipeline
otherwise qualifies all `mlogit::` calls; the namespace would only
be loaded by side effect of the first `mlogit::mlogit()` call,
which `extract_model_diagnostics` doesn't make itself.

### Padded slots in `fitted$probabilities`
`{mlogit}` pads each race to `max_field_size` with **zero**
probabilities for non-existent alternatives (not NA). Counts and
the null log-likelihood in `extract_model_diagnostics()` and in
`_03_results.qmd::summarise_fit()` use `probs_mat > 0` to
discriminate real alternatives from padded ones. The earlier route
via `nrow(fitted_model$model)` over-counted by ~70%
(5,150 races × 16 max alts = 82,400 rather than 47,299 actual
runner-rows).

## Modelling notes
- Owen's model is a conditional logit (McFadden) fitted with
  `{mlogit}`. Race is the choice set, no intercept, no
  race-specific covariates.
- `{tidymodels}` has no conditional logit engine. Use `{mlogit}`
  directly for fitting; `{rsample}` for race-level splits and
  `{yardstick}` for metrics where they fit naturally.
- Splits are **race-level**, never row-level. Grouping variable:
  `race_id`.
- Paper 1 headline is the *reduced* fit (terms with all levels at
  p > 0.05 dropped), to parallel Owen's Table 3 — itself a reduced
  model. Calibration and the P1 / P2 scoring rules are evaluated
  on the held-out test set.

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
- Dropped as non-significant: `position3` (all levels), `blinkers`,
  `visor`, `tonguetie`.

Carried in the `owen_table3` chunk inside
`papers/01_replication/_03_results.qmd`. Owen uses raw `daysLTO`
while the AW fit uses `log(1 + daysLTO)`, so those rows aren't
directly comparable on absolute magnitude. The `sireSR` /
`trainerSR` rows also aren't: Owen's coefficients behave as though
his rates were reported on the percent scale (0–100), ours are on
the proportion scale (0–1). Dividing AW by 100 puts them on the
same footing: AW trainerSR matches Owen near-exactly (0.0509 vs
0.0510); AW sireSR is roughly half (0.0235 vs 0.0480). Both
observations are documented in §4.3 of paper 1.

## §3.4 backtest (paper 1)
- Owen's bet-selection rule, replicated verbatim:
  $\hat{P}_{jk} > 0.15$ AND ratio $=\hat{P}_{jk}/P^{\text{mkt}}_{jk} > 1.3$.
  Market probability is over-round-adjusted starting price,
  renormalised per race.
- Threshold sweep for sensitivity: ratio threshold
  $\tau \in \{0.9, 0.95, \ldots, 2.0\}$ (step 0.05),
  model-probability filter held at 0.13. 90% CI via race-level
  bootstrap, B = 2000, seed 42.
- Owen's training-set scoring reference values (his §3.3,
  in-sample): P1_model = 0.120, P1_market = 0.136;
  P2_model = 0.860, P2_market = 0.831. NOT directly comparable to
  our P1 / P2, which are out-of-sample on the test set.
- Targets: `fitted_final`, `test_predictions`,
  `model_market_ratio`, `backtest_naive`, `backtest_sweep`.
  Helpers in `R/scoring.R`.
- AW headline: −28.2% ROI on 1,713 bets vs Owen's reported +20.5%
  on 264 bets. The discussion section frames Owen's small-sample
  positive as plausibly indistinguishable from zero, and ours as a
  confident null on the larger sample.

## Paper 2 plan
- **Extend the feature set**, both horse-level and race-level.
  Candidates explicitly named in paper 1's §4.6:
  - **Draw / stall number** (`stall_number` in Smartform). Known
    to matter on AW; varies with course and distance.
  - **Weight carried** (or each horse's deviation from the race's
    weight range). Direct readout of the handicapper's assessment
    of relative ability within the race — structurally natural for
    a handicap and absent from Owen's specification.
  - **Going**, **distance**, **race class**, **prize money**,
    **course** as race-level features entered via interactions
    with horse-level features (a *mixed* discrete-choice
    formulation; the derivation is in
    `notes/paper2_seed_mixed_choice.md`).
- **Automated feature selection** — choose a framework that
  respects the conditional-logit / `{mlogit}` interface (so no
  off-the-shelf `tidymodels` workflow); stability selection over
  race-level bootstrap is one candidate, AIC-driven stepwise on
  the full + interaction grid is another. Pick during scoping.
- **Refit with the exploded conditional logit.** Each race
  explodes into one "real" race plus several "fictitious" sub-
  races, one for each ranked position. A 5-horse race finishing
  H1, H3, H4, H2, H5 becomes three nested choice sets:
  `{H1, H3, H4, H2, H5}` → H1; `{H3, H4, H2, H5}` → H3;
  `{H4, H2, H5}` → H4. Pool the exploded set and fit a single
  conditional logit across the whole pool. Extracts more signal
  from the same races by using the full finishing order rather
  than just the win indicator. Derivation in
  `notes/paper2_seed_plackett_luce.md`.
- **Comparison plan**: report paper-1 model, Owen's published
  model (where comparable), and the new exploded fit side-by-side.
  Carry through Table 3 / Figure 7 / Figure 8 / §3.4 backtest
  diagnostics.
- **Mirror paper-1 paper structure** under
  `papers/02_extended_factors/` (slug TBD). Reuse the layout,
  helpers, and rendering bootstrap.

## Paper 3 plan
- **Switch model class entirely** to a class that handles
  non-linearities and interactions gracefully — conditional logit
  in its linear-predictor form does neither natively. The specific
  model is the user's call; theory worked through but not yet
  documented in this repo. The user believes it is novel as an
  application to horse racing.
- Comparison plan: keep the same data scope, train/test split, and
  diagnostic suite (Owen Table 3 / Figure 7 / Figure 8 / §3.4
  backtest) so paper 1, paper 2, and paper 3 are directly
  comparable.

## Longer-term direction (post-paper-3, speculative)
If the modelling holds up, subscribe to the live Smartform feed
and refresh the pipeline with current data. Goal: paper-trade on
Betfair initially; potentially live betting after that. The angle
the user finds interesting:
- Betfair prices converge toward fair value as race time
  approaches and liquidity builds.
- Early markets are noisy — dominated by bookmaker prices and
  uninformed money.
- If a well-calibrated model can approximate the *starting* price
  using only pre-race features, it can identify horses where early
  prices haven't yet converged.
- The edge is *front-running the convergence*, not beating the
  final market: back underpriced horses early, trade out as the
  market corrects.
- Direction, not commitment. Worth flagging because it shapes what
  "well-calibrated" means in papers 2 and 3 — the relevant
  comparison target is the starting price's information set, not
  the in-running market.

## Key references
- Owen, A. (2019), *Statistical Models of Horse Racing Outcomes
  Using R*, MathSport International 2019 Proceedings — the paper
  paper-1 replicates.
- r4ds.hadley.nz — tidyverse style guide.
- tmwr.org — tidymodels patterns.
- books.ropensci.org/targets — pipeline patterns.

## Out of scope
- Pre-2003 data (Smartform's earliest record).
- Other surfaces (turf, jumps) beyond using their data for
  cross-surface feature history.
- Live betting infrastructure remains out of scope until at least
  after paper 3, and even then begins as paper trading.
