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
- **Paper 2 — SPLIT into 2a + 2b.**
  - **Paper 2a — first full draft complete, corrections applied;
    pending publish to GitHub Pages.** *Extended feature set and the
    conditional-logit win model (including mixed-logit / race-level
    interactions).* Source: `papers/02a_extended_win_model/`. See
    "Paper 2a plan" below.
  - **Paper 2b — scaffolded.** *Exploded conditional logit as a
    ranking model, evaluated on ranking metrics.* Source:
    `papers/02b_ranking_model/`. See "Paper 2b plan" below.
  - **Pre-split draft archived.** `papers/02_extended_features_ARCHIVE/`
    is the combined pre-split paper-2 draft, kept for reference (not
    rendered).
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
  - `papers/02a_extended_win_model/` — **paper 2a, first full draft complete, corrections applied; pending publish to GitHub Pages.** Extended
    feature set, extended win model, mixed logit race-level interactions. Master
    `index.qmd` includes section partials via `{{< include >}}`. Rendered by
    `tar_quarto(paper_2a_extended_win_model)`.
  - `papers/02b_ranking_model/` — **paper 2b, scaffolded.** Exploded conditional
    logit as a ranking model. Master `index.qmd` includes section partials via
    `{{< include >}}`. Rendered by `tar_quarto(paper_2b_ranking_model)`.
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

### Paper 2 re-render nuisance
tar_make() re-renders paper 1 when paper 2 targets run, despite no
paper-1 source changes. Traced to both papers' qmd setup chunks
writing the same root _targets.yaml. Harmless — paper 1 re-renders
identically. To be investigated and fixed later; do not address in
current prompts.

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

### Paper 2 extended features (implemented)
The paper-2 candidate features are built in
`R/build_extended_features.R` (three pure builders) and assembled
into the single `runners_augmented` target — paper 1's `features`
plus every new column. The cumulative-strike-rate SQL
(`sql/trainer_sire_cumulative.sql`) was extended to emit jockey rows
(`kind = 'jockey'`) and AW-restricted cumulative columns
(`aw_wins_thru_date`, `aw_races_thru_date`); the trainer/sire overall
columns are byte-identical to before, so paper 1's `strike_rates` /
fit are untouched. Four resolved decisions (do not relitigate):

- **jockeySR is uncapped**, consistent with `trainerSR` / `sireSR`.
  Those two are themselves raw / uncapped in this pipeline
  (`build_strike_rates()` defers any winsorisation downstream), so
  jockeySR follows the same convention — all three strike rates stay
  on one comparable scale. If a cap is ever wanted it must be applied
  uniformly to all three at the modelling stage, not to jockeySR
  alone.
- **`class_delta` / `weight_delta_lbs` LTO lookup is floored at
  `date_from` (2006-01-01)**, the comparable-class era. Pre-2006
  Smartform class codes are multi-digit (11, 42, 53, 64, …) and not
  comparable with the 2006+ 1–7 scheme; an un-floored class_LTO
  produced nonsense deltas (e.g. 5 − 64 = −59). Consistent with the
  2006+ data-scope decision above. The `first_time_aw` / `has_wins`
  flags deliberately use *full* pre-2006 history — "ever ran AW" /
  "ever won" is valid across the boundary.
- **`or_relative` NA rate: ~10.5% overall, 14.4% on the training
  split** (the missingness is concentrated pre-2013, so it falls
  disproportionately in the earlier training window). Runners with a
  NULL official rating; not imputed to the race mean — that would
  spuriously read as 0 = "exactly average". Because `prepare_mlogit_data()` drops
  *whole races* on any NA in a modelling column, including it costs
  ~7,000 runner-rows. Decision: screen it in the univariate PL-R²
  screen; drop without guilt if it scores poorly, only pay the
  coverage cost if it scores well.
- **`stall_normalised` can exceed 1** (max ~1.8). Stall numbers
  reflect the original draw, so after scratchings a horse can be
  drawn higher than the actual (post-Non-Runner) field size. Kept as
  the literal `stall_number / field_size` for now; if the feature
  survives the screen, revisit within-race rank as a paper-3
  refinement.

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
- **Exploratory analysis is training-only (Paper 2 onwards).** All
  win-rate summaries, tables, and plots in the exploratory section
  must be computed after filtering to the training split
  (`split == 'train'`). Paper 1 computed these on the full joined
  tibble — that paper is complete and is not being corrected.
  Paper 2 onwards: filter before any feature summarisation.

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

## Paper 2a plan
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
  (The exploded conditional logit / Plackett–Luce ranking refit is
  **paper 2b**, not 2a — see "Paper 2b plan" below.)
- **Comparison plan**: report paper-1 model, Owen's published
  model (where comparable), and the extended win + interaction fit
  side-by-side. Carry through Table 3 / Figure 7 / Figure 8 / §3.4
  backtest diagnostics.
- **Mirror paper-1 paper structure** under
  `papers/02a_extended_win_model/`. Reuse the layout, helpers, and
  rendering bootstrap. (Done — scaffolded; section bodies are stubs.)

## Paper 2b plan
Exploded conditional logit as a ranking model. See
`papers/02b_ranking_model/`.
- **Objective:** ranking (top-3 finishing order), not the win.
- **Model:** exploded conditional logit (Plackett–Luce, depth k = 3);
  feature set inherited from paper 2a.
- **Market baseline:** discounted Harville place probabilities via
  Lo & Bacon-Shone (α = 0.80 for the 2nd-place conditional, 0.65 for the
  3rd), built from over-round-adjusted SP win probabilities.
  `compute_harville_place_probs()` in `R/scoring.R` (scaffolded; not yet a
  target).
- **Metrics:** P1_rank (geometric mean depth-3 PL probability of the
  observed top-3 order) and Brier_place (top-3 Brier score). Stubs
  `score_p1_rank()` / `score_brier_place()` in `R/scoring.R`.
- **New references:** Harville (1973), Lo & Bacon-Shone (1994, 2008).
- **Status:** scaffolded; content to be filled after paper 2a is complete.

## Paper 2 feature decisions

### Settled drop decisions (do not relitigate)
- `weight_delta_lbs` — dropped. NA mechanism is not missing-at-random
  (no prior run, not a neutral value). Weak univariate signal (PL-R²
  0.008). `rel_weight` already captures the within-race weight level.
- `class_delta` — dropped. Near-zero univariate signal (PL-R² 0.00004).
  Handicapper already prices class moves into the weight.
- `sire_aw_premium`, `jockey_aw_premium` — dropped. Near-zero signal
  (0.0008, 0.0007).
- `stall_normalised` — dropped. Weak signal (0.0003). Candidate for
  course-interaction in paper 3.
- `first_time_aw` — dropped. Near-zero signal (0.0001).

### Settled keep decisions
- `or_relative` — strongest new feature (PL-R² 0.035). Impute 0 for
  NULL official rating; add `or_missing` binary companion (1 if OR was
  NULL). Missing-not-at-random: unrated horses are a distinct population
  (unexposed or returning); imputing 0 with companion indicator lets the
  model estimate the missing-OR effect separately.
- `jockeySR` — carry forward (PL-R² 0.011, comparable to trainerSR).
  Uncapped, consistent with trainerSR/sireSR.
- `rel_weight` — carry forward (PL-R² 0.009, zero coverage cost).
- `trainer_aw_premium` — carry forward into full model fit; drop
  decision deferred to reduced model (coefficient test).
- `has_wins`, `cheekpieces`, `gelding` — carry forward into full model;
  drop decision deferred to reduced model.

### Features deferred for later prompts
- B: Position encoding parsimony — SETTLED. Model S (semi-parsimonious,
  6 coefficients) adopted. *(Display-name note: an editorial pass renamed
  the paper's model labels to plain descriptive terms — Model S →
  "zero-plus-slope encoding", Model P → "single-slope encoding", Model F →
  "factor encoding"; the "(Model W)" parenthetical for the extended win
  model was dropped from prose. Variable names `pos_lagN_zero` /
  `pos_lagN_nonzero` are unchanged. The P/S/F shorthand is retained here as
  internal memory only.)* For each lag N, two terms:
  pos_lagN_zero (binary: 1 if position = 0) and pos_lagN_nonzero
  (numeric: raw position 1–4, else 0). LR test vs full factor Model F:
  LR = 4.88, df = 6, p = 0.560 — not rejected. AIC favours S over F
  by 7 points. Positions 1–4 are effectively linear once the zero
  category is separated out. Model P (scalar + decay, 2 coefficients)
  was decisively rejected (LR = 600, df = 10, p ≈ 1.4 × 10⁻¹²²) —
  failure traced to mis-ordering the zero level on the numeric scale.
  Paper 1's factor encoding is NOT carried forward into paper 2.
- C: Going interaction — DEFERRED TO PAPER 3. See "Going interaction —
  deferred to paper 3" subsection below for rationale.

### Going interaction — deferred to paper 3
Going is a race-level feature; it cancels in the softmax unless
interacted with a horse-level affinity measure. The meaningful
version — going_ordinal × horse_going_sr — requires a cumulative
pre-race win rate filtered by going category (career-history
sub-query). Deferred to paper 3: tree-based models handle going
as a raw feature without the interaction constraint, which is the
right home for it. Do not implement in paper 2.

### Exploratory analysis convention (paper 2)
- Filter to `split == "train"` before any summarisation.
- Headline counts reflect training data only.
- Note the 70/30 chronological split in the section header.
- Paper 1 used full joined tibble — known issue, not being revisited.

## Paper 2a corrections (final model + honest reporting)
Applied after the first full draft; these supersede earlier
choices where they conflict.

- **Reduction rule, stated honestly (§4.1).** The reduced extended
  win model drops the two lag-3 terms on per-term Wald p — the same
  rule paper 1 and Owen use. The *joint* LR test of reduced vs full
  (both on the identical 5,065 training races) **rejects** the
  reduction (LR ≈ 9.3, df 2, p ≈ 0.009; AIC prefers the full model
  by ~5). We nonetheless keep the *reduced* model as the paper-2a
  headline, for (a) like-for-like comparability with paper 1 / Owen
  and (b) negligible practical difference (McFadden R² 0.0802 full
  vs 0.0798 reduced). The joint test is reported in §4.1 rather than
  hidden. Computed live from the fitted objects — not hard-coded.
- **Draw block selected, then reduced per-term; final model = 2-course
  (Kempton + Southwell), 19 coefficients.** *(SUPERSEDES the earlier
  "final = 4-course block" decision — see history note below.)* The
  draw×course block is admitted via the W+draw vs W likelihood-ratio
  test (block in/out), establishing course-specific draw bias carries
  signal. Within the admitted block the **inclusion threshold for each
  course slope is p < 0.05 on its individual Wald test** — the same
  per-term rule paper 1 / Owen use and that already drops the lag-3
  terms in §3.2/§4.1, applied uniformly. In the full block
  (`model_w_ed`): Kempton (p ≈ 0.009) and Southwell (p ≈ 0.025) are
  significant and retained; Lingfield (p ≈ 0.35) and Wolverhampton
  (p ≈ 0.066, marginal) are not, and are dropped. The final model is
  **`model_w_final`** = extended win + `stall_x_kempton` +
  `stall_x_southwell`. Confirmed by `final_reduction_lr_w`: two
  sequential 1-df LR tests (drop Lingfield LR ≈ 0.89, p ≈ 0.35; drop
  Wolverhampton LR ≈ 3.40, p ≈ 0.065), **neither rejected**, so the
  reduction is clean. `model_w_final_diagnostics` and
  `test_predictions_w_final` read off `model_w_final`. `model_w_ed`
  (4-course block) is kept only as the selection-stage fit shown in the
  draw-course table and reduction prose. *History:* an intermediate
  draft made the 4-course block the headline (treating Lingfield's
  near-zero slope as a "no-draw-bias finding" not to be pruned); that
  was deliberately reversed back to per-term reduction for internal
  consistency with the rest of the reduced model (which prunes
  non-significant terms, e.g. lag-3).
- **Headline ROI is −25.4%** (the 2-course final model), up from paper
  1's −28.2% and the extended-win model's −26.0% — monotone
  improvement, but smaller than the dropped Wolverhampton slope (which
  favoured low draws) had bought the 4-course block (−22.8%). Propagated
  via inline `tar_read(backtest_naive_w_final)$roi` throughout (abstract,
  intro, §5.5, progression table) — no hard-coded ROI strings for the
  final model. **Consequence of the 2-course reduction:** the draw step
  now adds only ≈ +0.6 pp of ROI over the extended-win model vs the
  extended features' ≈ +2.2 pp, so prose crediting draw as the *largest*
  backtest contributor was corrected — `or_relative` / the extended
  feature set is the larger contributor, draw a smaller further
  increment (intro, §5.5, §6.1).
- **Paired ROI-difference bootstrap.**
  `R/scoring.R::bootstrap_roi_difference()` + target
  `roi_difference_bootstrap`: restricts each model pair to its COMMON
  test races (paper 1 and 2a drop different races to NA), resamples
  races paired (B = 2000, seed 42), applies Owen's naive rule per
  model, returns the ROI-difference point + 90% percentile CI. Three
  contrasts (2-course final): final − paper 1 (+2.8%, [−6.4, +12.2]);
  final − extended win (+0.6%, [−2.8, +4.2]); extended win − paper 1
  (+2.2%, [−6.9, +11.5]). **All three CIs straddle zero** → the ROI
  gains are directionally consistent but **not statistically
  distinguishable**. Prose (abstract, intro, §5.5, §6.1) framed as that,
  not "modest but real"; ROI-difference table in §6.1. See
  [[feedback_temporal_integrity]] for the related honesty principle.
- **Race-loss accounting (§4.1).** The fits are complete-case at the
  race level and use 5,065 of 5,209 training races (144 dropped,
  2.8%). Drops are driven by undefined pre-race strike rates under
  the strict-before rule: missing `jockeySR` touches 88 races,
  `sireSR` 35, `trainerSR` 23, `days_LTO_log` 2 (overlapping). The
  test set is filtered the same way, so paper 1 (2,232 test races)
  and paper 2a evaluate on slightly different universes — flagged in
  the Table 18 caption; the paired bootstrap handles it by
  intersecting. Complete-case behaviour itself is unchanged.
- **No paper-2b RESULT claims in paper 2a.** Until 2b is actually
  fitted, every 2b reference in the 2a qmds is design/prospective
  only ("changes the objective to ranking", "a question we leave to
  that paper") — no assertion that the exploded fit estimates any
  interaction "more sharply". Re-audit on any 2a edit: grep `2b`.

## Paper 2 status
Pre-split draft archived at `papers/02_extended_features_ARCHIVE/`.
Paper 2a and 2b are now the active branches.

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
- Harville, D. A. (1973), *Assigning Probabilities to the Outcomes of
  Multi-Entry Competitions*, JASA 68(342) — the win→place probability
  formula; paper 2b's market baseline.
- Lo, V. S. Y. & Bacon-Shone, J. (1994; 2008) — discounted-Harville
  corrections for the favourite–longshot bias in the place market
  (paper 2b's market baseline; α = 0.80, 0.65).
- r4ds.hadley.nz — tidyverse style guide.
- tmwr.org — tidymodels patterns.
- books.ropensci.org/targets — pipeline patterns.

## Out of scope
- Pre-2003 data (Smartform's earliest record).
- Other surfaces (turf, jumps) beyond using their data for
  cross-surface feature history.
- Live betting infrastructure remains out of scope until at least
  after paper 3, and even then begins as paper trading.
