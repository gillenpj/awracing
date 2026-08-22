# awracing — Claude Code memory

Statistical models of UK All-Weather racing outcomes, built on the
Smartform MySQL database in R. Multi-paper series; current state and
forward plan below.

## Default to proceeding

Do not stop for approval on implementation choices, performance work,
refactors, debugging, or anything reversible under version control. Make
the call, do the work, and report what you did and why afterwards. A stop
costs a full turn; a reversible mistake costs a `git checkout`.

Stop and ask only when one of these is true:
- The action would change or republish a **published figure** — anything
  under `docs/`, or any headline number in papers 1, 2a or 2b.
- The action would **modify a model specification** that affects reported
  results. The existing model-spec gate stands.
- The action would **destroy or overwrite state not recoverable from
  git**: `renv.lock`, the `_targets` store, the database, `.env`.
- The action would **commit a large irreversible spend of wall-clock** —
  a run projected beyond about 12 hours.
- A prompt explicitly says to stop.

Verification gates are not a reason to stop; they are the reason not to.
Where a gate exists — `scripts/verify_pl_objective.R`,
`scripts/verify_going_features.R`, `scripts/verify_rebuild.R` — proceed
and let the gate catch you. If a gate fails, fix it and report. Do not
ask permission to fix it.

Two calibration examples (2026-08-20):
- **The tuning-grid stop was CORRECT.** A 37-hour projection (before the
  `pl_objective.R` speedup) is an irreversible spend.
- **The performance-rewrite stop was UNNECESSARY.** The rewrite was
  reversible and covered by a gate (`scripts/verify_pl_objective.R`).
  The right behaviour was the rewrite-debug-fix-reverify cycle actually
  run unprompted, reported after the fact — not pausing to ask first.

## Series status (read this first)

- **Paper 1 — complete and PUBLISHED.** *Replicating Owen (2019) on
  UK All-Weather Flat handicaps, 2006–2015* (pinned date 2026-06-06,
  revised 2026-07-03 — added a one-line clarification that Owen's naive
  rule can qualify several horses per race and this paper backs all, the
  multi-bet rule).
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
  - **Paper 2a — complete and PUBLISHED.** *Extended feature set and
    the conditional-logit win model (including mixed-logit /
    race-level interactions).* Source:
    `papers/02a_extended_win_model/`. Live at
    <https://gillenpj.github.io/awracing/paper2a/> (HTML + PDF), pinned
    date 2026-06-21, revised 2026-07-03. One
    headline change from the first draft: the draw×course block is
    reduced per-term to the two significant courses (Kempton,
    Southwell) — Wolverhampton and Lingfield dropped — giving a
    −25.4% backtest ROI (multi-bet). The 2026-07-03 revision adds the
    Owen betting-rule clarification and the **single-bet win** figure
    (−25.9% on 1,305 bets, marginally worse than multi-bet), adopting
    single-bet — one bet per race, the highest-model-win-prob qualifier —
    as the **primary rule from this paper onwards** (for realism; no
    win-market advantage). See "Paper 2a plan" and "Paper 2a
    corrections" below.
  - **Paper 2b — complete and PUBLISHED.** *Exploded conditional logit
    as a ranking model, evaluated on ranking metrics; plus a betting
    application.* Source: `papers/02b_ranking_model/`. Live at
    <https://gillenpj.github.io/awracing/paper2b/> (HTML + PDF), pinned
    date 2026-07-03 (re-published, single-bet overhaul; was 2026-06-29).
    The paper is built around **three questions in
    order**: (Q1) under a ranking objective, how well does the model
    predict the top-3 finishing order? — it beats chance but the
    discounted-Harville place market scores higher on both metrics
    (P1_rank 0.00402 model vs 0.00543 market; Brier_place 0.2013 vs
    0.1875); (Q2) does depth-3 ranking supervision make a better
    *win*-picker than 2a's depth-1 fit? — yes, −17.4% vs −25.4% ROI,
    a paired bootstrap difference of +8.0 pp [+1.0, +14.8] (90% CI
    excludes zero), the first statistically distinguishable improvement
    in the series, though still a loss to the market; and (Q3) does that
    place accuracy translate into betting value? — under the **single-bet**
    primary rule (one bet per race, priced at real SP), place returns
    −9.8% and each-way −7.7% — materially better than the multi-bet rule
    (−17.3% / −26.3%), a place/each-way effect only (no win advantage),
    but still a loss; consistent with Q1. See "Paper 2b plan" below.
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
- **TeX (TinyTeX) — required for the PDF output.** Each paper renders
  both HTML and PDF (see "Paper / Quarto convention"), and the PDF
  branch needs a LaTeX install. TinyTeX is installed under
  `C:/Users/gille/AppData/Roaming/TinyTeX` (via `quarto install
  tinytex`); its `tlmgr` is at
  `…/TinyTeX/bin/windows/tlmgr.bat`. The PDF uses the default
  `lualatex` engine. Two gotchas, both already resolved on this
  machine: (1) paper 1 needs the `luatexbase` package — install with
  `tlmgr install luatexbase` if a PDF render reports it missing; (2)
  the default CTAN mirror (`gb.mirrors.cicku.me`, also where
  `mirror.ctan.org` redirects from GB) served corrupt checksums right
  after the TeX Live 2026 release — the repo is pinned to
  `https://ftp.fau.de/ctan/systems/texlive/tlnet` via
  `tlmgr option repository …`, which fixed it. If a fresh package
  auto-install fails mid-render with a checksum error, re-pin a
  different mirror.
  - **Debugging a PDF failure:** under `tar_make()` a PDF render error
    surfaces *masked* as a cryptic targets/cli message
    (`Could not evaluate cli {} expression: 'captions' … object
    'captions' not found`) — that is the KOMA `\KOMAoption{captions}`
    header getting mangled by cli interpolation, **not** the real
    cause. To see the actual LaTeX/quarto error, render the offending
    paper directly from the project root:
    `quarto render papers/<NN>_<slug>/index.qmd --to pdf` (run from the
    root so the child R session's cwd is correct).

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
- **Documented exception: `{xgboost}` used directly (`xgboost::xgb.train()`),
  not via `{tidymodels}`/`{parsnip}`, for paper 3's custom
  Plackett–Luce objective.** `{parsnip}` has no interface for a custom
  objective plus a custom eval metric plus group info together. Same
  kind of exception as the `{mlogit}` route in papers 1/2 (see
  "Modelling notes" below).

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
  - `papers/02a_extended_win_model/` — **paper 2a, complete and published.** Extended
    feature set, extended win model, mixed logit race-level interactions. Master
    `index.qmd` includes section partials via `{{< include >}}`. Rendered by
    `tar_quarto(paper_2a_extended_win_model)` (HTML + PDF).
  - `papers/02b_ranking_model/` — **paper 2b, scaffolded.** Exploded conditional
    logit as a ranking model. Master `index.qmd` includes section partials via
    `{{< include >}}`. Rendered by `tar_quarto(paper_2b_ranking_model)`.
  - `papers/03_<slug>/` — paper 3, model-class change. Slug TBD
    once the model is picked.
- `docs/` — GitHub Pages publishing root. **Committed.**
  - `docs/index.html` — landing page, one entry per paper; each
    entry links the HTML and a "— PDF" link to `paperN/index.pdf`.
  - `docs/paper1/index.html` + `.pdf`, `docs/paper2a/index.html` +
    `.pdf` — rendered output, copied from the matching
    `papers/*/_output/` after each render.
  - Pages source is set to `main` branch, `/docs` folder. There is
    **no GitHub Actions workflow** — Pages serves the committed
    `/docs` files directly and runs its own build on push, so
    publishing = copy `_output/` into `docs/`, commit, push. The
    `papers/*/_output/` working copies are gitignored. (A render-in-CI
    Action is not possible: the `{targets}` pipeline needs the local
    Smartform MySQL DB, which CI cannot reach.)
  - Republishing convention: (1) re-render via `tar_make()` (which
    produces **both `index.html` and `index.pdf`** per paper — see
    "Paper / Quarto convention"); (2) run
    `Rscript scripts/publish_docs.R` to copy each paper's `_output/`
    HTML+PDF into the matching `docs/paperN/`; (3) `git add docs/`,
    commit, push. The landing page `docs/index.html` is hand-edited
    (one entry per paper); the script does not touch it.
  - Each `index.qmd` carries a **pinned** `date:` (e.g. paper 1
    `"2026-06-06"`, paper 2a `"2026-06-21"`), not `date: today`, so a
    paper's published date is stable across re-renders. Set the date
    once when the paper is first published.
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
  - `Notes on Trees-based Methods.pdf` — background theory for
    paper 3: regression trees, pruning, bagging, random forests,
    boosting, gradient boosting, XGBoost, and the application to
    horse racing. See "Paper 3 theory note" below.
- `scripts/`
  - `verify_rebuild.R` — standing read-only integrity check on
    `qualifying_races` / `qualifying_runners` / `candidate_races`.
    Run after any change to SQL or the R-level filters in
    `R/extract_*.R`. Eight `stopifnot()` assertions; see file
    header.
  - `publish_docs.R` — the publish step. After `tar_make()`, copies
    each paper's `_output/index.{html,pdf}` into `docs/paperN/`
    (mapping table at the top of the file; add a row per new paper).
    Self-contained base R — run as
    `Rscript scripts/publish_docs.R`, no renv needed. Does not touch
    the hand-edited landing page.
- `_targets/` — pipeline cache (gitignored).
- `renv/`, `renv.lock` — package state.
- `.env` — DB credentials (gitignored). Read at runtime by
  `R/db.R::connect_smartform()` via `dotenv::load_dot_env()`.
- `_targets.yaml` — written by `tar_config_set()` in the qmd setup
  chunks; absolute path to the store; gitignored.
- **`_targets/meta/process`** — the `{targets}` pipeline lock, recording
  the PID of whichever R session last ran `tar_make()`. If that session
  didn't exit cleanly, the lock can outlive it: the next `tar_make()`
  then refuses to run, citing a PID that may by now belong to something
  else entirely on this machine (found 2026-08-21: a lock from
  2026-08-19 named a PID that Windows had since reassigned to an
  unrelated `AdobeCollabSync` process). Fix: confirm no live R process
  actually owns that PID (`Get-Process -Id <pid>` — if it's not
  `R`/`Rscript`, or nothing's there, the lock is stale), then delete
  `_targets/meta/process` directly. Harmless to remove once confirmed
  stale — it's regenerated on the next `tar_make()`. Note this lock is
  unrelated to, and not touched by, any script that only calls
  `targets::tar_read()` (read-only) — `scripts/run_gbt_tuning.R` and the
  other `scripts/*.R` drivers never acquire it.
- `.claude/settings.json` — **committed**, project-level Claude Code
  permissions. Allow-lists read-only Bash (`head`, `cat`, `wc`, `awk`,
  `ls`, `grep`, `tail`, `find`) and bare/prefixed `git status` /
  `git log` / `git diff`, plus the `Read` tool (file reads anywhere in
  the project) — so routine inspection doesn't prompt for approval.
  Deliberately excludes anything that writes, deletes, kills processes,
  or touches `renv.lock`, the `_targets` store, `docs/`, or `.env` —
  those still prompt, unchanged. Note: the allow rules match on command
  *text prefix*, not semantics — `Bash(find *)` and `Bash(awk *)` permit
  any arguments, including `find -delete` or `awk`'s `system()` call,
  which are not actually read-only; accepted as a residual risk of the
  prefix-match permission model rather than narrowed further. Personal,
  uncommitted overrides live in `.claude/settings.local.json`
  (gitignored) and don't survive a fresh clone.

## Paper / Quarto convention
- One Quarto project per paper under `papers/<NN>_<slug>/`. Each
  has its own `_quarto.yml` with `output-dir: _output` (required by
  `tarchetypes::tar_quarto()`).
- Single-document Quarto manuscript. Master `index.qmd` carries
  YAML, abstract, intro, and `{{< include >}}` directives for the
  section partials. Partials are prefixed with `_` so Quarto does
  not try to render them standalone.
- **Each paper renders two formats — HTML and PDF.** The master
  `index.qmd` YAML carries `format: {html: default, pdf: {toc: true,
  number-sections: true}}`, so a single `tar_make()` produces both
  `_output/index.html` and `_output/index.pdf` via one
  `tar_quarto()` target. The PDF needs TinyTeX (see "Tech stack").
  Do not render the PDF standalone with `quarto render --to pdf` from
  the paper folder — the child R session's cwd breaks the home
  `~/.Rprofile`'s relative `source("renv/activate.R")`, and the qmd
  setup chunk fails to find the `_targets` store; `tar_make()` (run
  from the project root) is the supported render path for both
  formats.
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
  rendering bootstrap. (Done — complete and published.)

## Paper 2b plan
Exploded conditional logit as a **ranking** model, then its win
performance as a byproduct, then a betting application. See
`papers/02b_ranking_model/`. **Three questions, in order.** *(Supersedes the earlier "wrong objective, better
ROI" framing, which was written against pre-rebuild numbers on a stale
draw spec; the exploded fits were rebuilt after the 2a draw-block
correction.)*

- **Q1 — Ranking performance.** Refit the full 2a extended feature set on
  the ranking (depth-3 Plackett–Luce) objective, with an **independent**
  course×draw search (not inherited from 2a). Fresh per-term Wald
  reduction on the exploded fit retains **Kempton, Southwell,
  Wolverhampton** (3 courses) vs 2a's Kempton + Southwell — only Lingfield
  drops (p=0.91). Does it beat the market on ranking metrics? **No** —
  market wins both on the test split: **P1_rank 0.00402 (model) vs 0.00543
  (market); Brier_place 0.2013 vs 0.1875**. Consistent with papers 1/2a's
  market-trails-throughout pattern — reported, not chased. Targets:
  `model_2b_exploded_draw_full`/`_final`, `model_2b_draw_reduction`
  (+`_steps`), `ranking_eval_runners_2b`, `ranking_metrics_2b`.
- **Q2 — Win performance as a byproduct.** Does depth-3 ranking
  supervision make a better **win**-picker than 2a's depth-1 win-fitted
  model? The same 3-course exploded model on the depth-1 win backtest:
  **−17.4% ROI vs 2a's −25.4%**, both on the identical 2,193-race test set
  (`mlogit_test_data_interactions`; 0 dropped either side). Paired
  ROI-difference bootstrap (`roi_difference_2b_vs_2a`, B=2000, seed 42):
  **+8.0 pp [+1.0, +14.8]**, 90% CI **excludes zero** — the first
  statistically distinguishable improvement in the series, though still a
  clear loss to the market. Targets: `model_market_ratio_2b_win`,
  `backtest_naive_2b_win`, `backtest_sweep_2b_win`,
  `roi_difference_2b_vs_2a`.
- **Market baseline:** discounted Harville (Lo & Bacon-Shone, α=0.80/0.65)
  throughout — place probs for Brier_place, depth-3 order probability for the
  P1_rank market baseline. One consistent market baseline for both metrics;
  the model side of each uses its own α=1 (no discounting) PL implication. `compute_harville_place_probs()` +
  `compute_pl_order_probs()` in `R/scoring.R`; `score_p1_rank()` /
  `score_brier_place()` implemented; eval module `R/ranking_eval_p2b.R`.
- **Wolverhampton (sign sanity-checked).** Draw slope −0.182 (p=0.0003)
  on the exploded fit vs −0.160 (p=0.066) in 2a's win model — **same sign,
  sharper estimate**. Low-draw advantage, directionally consistent with a
  tight left-handed AW track, but a **distance-pooled** slope: frame as
  "the ranking objective estimates the same draw effect 2a saw, sharply
  enough to retain it", not "a new physical bias resolved".
- **Going: OUT OF SCOPE — deferred to paper 3.** No going feature, no
  going code in 2b; paper 3's tree-model rationale depends on it being
  untouched.
- **New references:** Harville (1973), Lo & Bacon-Shone (1994, 2008).
- **Q3 betting application: place + each-way, SINGLE-BET primary**
  (exacta/trifecta dropped — CSF / Tote-pool dividend, no dividend data).
  Selection = discounted-Harville (α=0.80/0.65) value ratio; **prob floor
  standardised to 0.15 across all 2b betting targets** (was 0.10 place/each-way
  naive+sweep, 0.13 win sweep). Payout = **real industry-SP book** (observed
  ~16% over-round), same basis as Q2. **Single-bet** (one bet/race, the
  highest-model-win-prob qualifier) is the primary, more realistic rule;
  **multi-bet** (back all qualifiers) reported for continuity with papers 1/2a
  (Owen does not specify his own rule). Single-bet **place −9.8%, each-way
  −7.7%** — far smaller losses than multi-bet **place −17.3%, each-way −26.3%**
  (multi-bet each-way compounded by the 1/5 terms: bet-all each-way floor −18.5%
  `backtest_betall_eachway`, weaker qualifiers push below it). **Win: no
  single-bet advantage** — −15.1% (2b) / −25.9% (2a) vs multi-bet, within CIs;
  the single-bet effect is place/each-way only. Robustness: single-bet place
  drop-largest-winner −10.4%; each-way τ=1.3 90% CI upper bound −0.1% (grazes
  zero — framed cautiously, "not comfortably below zero"). The
  `fig-single-vs-multi-sweep` overlay (place + each-way, single vs multi, CI
  ribbons) shows single-bet above multi-bet across τ, gap widening; win omitted
  (indistinguishable). `_04` contextualises with **bet-all win −22.8%** and
  **back-the-favourite −6.6%** (ties 9.1%, lower runner_id), and the **Betfair
  convergence motivation** (single place −9.8% ≈ half the ~16% margin; ~5%
  exchange commission → smaller headwind; left to a future paper). Single-bet
  machinery in `R/scoring.R` (`select_single_win_bet`, `single_bet_units`,
  `summarise_single_bets` (now returns `roi_drop_top1`), `run_single_win_backtest`,
  `run_single_settled_backtest`, `run_single_sweep`). Targets:
  `backtest_single_{win,place,eachway}_2b` (+`_sweep_2b`), `backtest_single_win_2a`,
  `value_bet_baselines_2b`, `backtest_betall_{win,eachway}`,
  `backtest_favourite_win`.
- **qmd structure:** `_01` data pointer + discounted-Harville market
  baseline; `_02` model build + independent draw search + Wolverhampton;
  `_03` Q1 (ranking vs market), Q2 (win/ROI vs 2a), Q3 (place/each-way
  betting value, real-SP basis) as **separate** subsections; `_04`
  discussion (three paragraphs, three-question framing);
  `_appx_derivations` Plackett–Luce / exploded-logit + Harville derivation.
- **Status: COMPLETE and PUBLISHED** (2026-07-03, HTML + PDF). Live at
  <https://gillenpj.github.io/awracing/paper2b/>; landing-page entry and
  `docs/paper2b/` committed. Both market baselines use discounted Harville
  (α=0.80/0.65); model P1_rank market figure is 0.00543.

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

## Paper 3 theory note
Read `notes/Notes on Trees-based Methods.pdf` before touching paper-3
code or prose — it is the canonical source for this paper's notation
and framing (race $i$ the chooser, horse $j$ the alternative, latent
score $z_{ij}$, $\mathcal{C}_{is}$ the set of horses not yet ranked at
stage $s$, win probabilities a softmax over the field — matches papers
1, 2a, 2b). Two things from the note are load-bearing:
- **The structural change for racing is that the loss stops
  factorising per observation: one term of the loss spans every runner
  in the field.** Every other complication in the method section — the
  grouped likelihood, the gradient/Hessian bookkeeping, the group-size
  vs group-pointer trap in `{xgboost}` — follows from this single fact.
- **Going affinity is a body-section modelling choice, not appendix
  material.** It is the feature paper 2 deferred specifically because
  conditional logit can't take it without an explicit interaction term;
  paper 3's method section is built around removing that constraint, so
  the feature belongs where that argument is made, not tucked into an
  appendix as an afterthought.

## Paper 3 plan
- **Trees only.** The neural-ranking-network extension floated at
  paper 2b completion is dropped from scope — no paper number, no plan
  for it. *(Supersedes the earlier "two model classes in one paper"
  framing.)*
- **One model fitted:** gradient boosted trees under a custom
  Plackett–Luce objective, $k = 3$, via `{xgboost}`. Papers 1, 2a and
  2b enter as stored comparators through their existing `{targets}`
  objects — no refits of the linear models.
- **Objective = ListMLE.** The grouped PL log-likelihood in
  `R/pl_objective.R` is term-for-term the ListMLE objective from the
  learning-to-rank literature. Paper 3 keeps the objective from paper
  2b and swaps the function class from conditional logit to GBT.
  Off-the-shelf `rank:ndcg`, `rank:pairwise`, and LambdaMART objectives
  are **not** this objective and must not be substituted — custom
  objective only (`make_pl_objective()` / `make_pl_eval()`).
- **`R/pl_objective.R`'s hot path is `{data.table}`-vectorised, not
  `dplyr`** (2026-08-20) — a pure performance rewrite, not a behaviour
  change; `scripts/verify_pl_objective.R` (the reason this was safe to
  do) still passes all assertions, including an added equivalence check
  (200 synthetic races, tolerance 1e-10) against the original
  implementation, retained as `pl_core_reference()` for exactly this
  purpose. The original `dplyr::group_by() |> mutate()` implementation
  cost ~900ms/call on a ~40,000-row / ~4,000-race training fold — called
  twice per boosting round (objective + eval) — making the tuning grid
  below an estimated 9-180+ hours depending on rounds/fit. Two rewrite
  attempts: a hand-rolled vectorisation (global `cumsum()` with a
  per-group offset subtraction) was tried first and **rejected** — for a
  race late in the arbitrary processing order it cancels two large,
  nearly-equal numbers to recover a small suffix sum, which degraded the
  Hessian-vs-`numDeriv` verification assertion from ~7e-8 to ~1.6e-6
  (over its 1e-6 tolerance) despite matching the reference to ~1e-14 at
  the tested point — the finite-difference check is far more sensitive
  to which floating-point path produced a near-identical value than a
  point-estimate comparison is. `{data.table}`'s grouped operations
  (`by = race`) fit each group's `rev(cumsum(rev(x)))` on a genuinely
  isolated per-group vector — the same property that makes `dplyr`
  numerically safe — while running in C; this restored EXACT agreement
  with the original implementation (0 difference on the 200-race
  equivalence check) at ~105ms/round end-to-end via `xgb.train()` — an
  ~8.7x speedup, not the ~35-45x a purely index-arithmetic vectorisation
  briefly appeared to give before its precision problem was caught.
  `{data.table}` is a new direct dependency (previously present only
  transitively via `{xgboost}`); no tidyverse-first exception note
  needed beyond this one, since it is confined to `pl_objective.R`'s
  internal hot path and never appears in the tidyverse-first pipeline
  code the rest of the project is written in.
  - **Consequences of the incident, for anyone touching this file
    again:** `pl_core_reference()` and the current verification
    tolerances in `scripts/verify_pl_objective.R` are **permanent, not
    scaffolding** — they are what caught a bug that agreed with the
    reference to ~1e-14 at a point comparison yet was still wrong. Any
    future performance work on the objective must re-run the **full**
    gate, not a point check; a point comparison alone would have let
    this exact bug through.
- **Divergence guard, added 2026-08-20 during the tuning grid's first
  real (unbounded, up-to-2000-round) run.** A grid point can genuinely
  diverge — scores grow until `exp(zc)` overflows or `denom` underflows
  to exactly `0.0`, making that row's `1/denom` (hence `cuminv`/
  `grad`/`hess`) non-finite, and `pl_r2` non-finite in turn. XGBoost's
  early-stopping callback does a raw `score > best_score` comparison with
  no `NA`-handling of its own, so a single non-finite `pl_r2` crashed the
  entire `xgb.train()` call ("missing value where TRUE/FALSE needed"),
  not just that round. Two guards, both in `R/pl_objective.R`:
  - `pl_grad_hess()`: non-finite `grad` -> `0` (no push, either
    direction, for that row); non-finite `hess` -> `1e-16` (the same
    floor already used for a legitimately tiny Hessian). Keeps a
    diverging row from corrupting that round's tree-building silently —
    worse than a crash — rather than fixing the ranking, since these
    values never reach the eval metric that scores a grid point.
  - `make_pl_eval()`: non-finite `pl_r2` -> `-1e10`, a large negative
    **finite** sentinel (not `-Inf`, specifically so no comparison is
    ever `-Inf` vs `-Inf`, which is what caused the crash in the first
    place). This is the value that determines grid ranking, and the
    choice is deliberately conservative: `fold_mean_pl_r2` is the mean
    of 5 folds, so even a SINGLE diverged fold drags a grid point's mean
    to roughly `-2e9` — three orders of magnitude below any real `pl_r2`
    (bounded above by 1; observed in this data around 0.06-0.07) — so a
    diverged config cannot be masked by its other folds' good scores and
    cannot win `select_best_config()`'s ranking. Confirmed by
    construction, not just asserted.
  - Both guards checked against `scripts/verify_pl_objective.R`'s full
    gate (still passes unchanged) before being trusted.
  - **Divergence event logging**, added alongside (not just flooring):
    `make_pl_objective()`/`make_pl_eval()` take an optional `diag_env`;
    `R/gbt_tuning.R::fit_one_fold()` supplies one per fold-fit and
    returns every floored event (`round`, `source`, and either
    `n_grad_floored`/`n_hess_floored` or the pre-floor `raw_value`).
    `scripts/run_gbt_tuning.R` checkpoints these to
    `gbt_tuning_divergence.csv` as they occur, tagged with the grid
    point and fold. Purpose: divergence confined to the expected
    high-`eta`/high-`max_depth` corner is unremarkable; divergence
    appearing at low `eta` would mean the objective has a numerical
    problem at scale, not just at parameter extremes, and would make the
    whole run's results suspect — worth knowing, not just surviving.
  - **§6 drafting note:** state plainly that divergent configurations
    during tuning were floored to a sentinel rather than dropped from
    the grid, with the count and the grid corner(s) affected (from
    `gbt_tuning_divergence.csv`) — this belongs in the same paragraph as
    the capacity-and-selection asymmetry disclosure, not left implicit.
  - **Root cause, found 2026-08-20, two rounds of correction on
    2026-08-21 — the ACTUAL bug had nothing to do with numerical
    divergence at all.** Full incident history, because both earlier
    "fixes" below were real bugs worth having fixed but neither was the
    cause of the 100% divergence rate, and the reasoning that got to the
    true cause is itself the reusable lesson.
    - **Attempt 1 (2026-08-20):** the first real run hit 255 divergence
      events on grid point 1 (`max_depth=2, eta=0.01, min_child_weight=1,
      subsample=0.7`), every fold, from round 1. Diagnosed as
      `fit_one_fold()` never calling `set.seed()`; fixed by adding
      `set.seed(42L)` before `xgb.train()`; "verified" by two same-session
      reruns agreeing. **Wrong** — a same-process rerun proves nothing
      about a library's own internal state (see the standing rule below).
    - **Attempt 2 (2026-08-21, morning):** re-investigation after a
      mid-run reboot found the root problem was real but different: R's
      `set.seed()` never reaches xgboost's OWN internal RNG (governing
      `subsample`/`colsample_bytree` draws) unless `seed` is also passed
      inside xgboost's `params` list, which `full_params` never did.
      Fixed by adding `seed = 42L` to `full_params` in `fit_one_fold()`
      (`R/gbt_tuning.R`) — genuinely verified this time, via two SEPARATE
      fresh `Rscript` processes producing byte-identical tree structure
      and `pl_r2` trajectories. **This fix is real, correctly diagnosed,
      and stays in the code** — R's `set.seed()` truly does not control
      xgboost's internal RNG, and cross-process reproducibility truly
      did require this. But relaunching the full grid with it still
      produced 100% divergence, config-independent, across 41 checked
      grid points spanning multiple `eta`/`max_depth`/`min_child_weight`
      combinations — ruling out "hyperparameter corner" as the
      explanation and ruling out the seed fix as sufficient.
    - **Actual root cause (2026-08-21, found by direct instrumentation of
      the live `make_pl_eval()` closure, not by diffing isolated
      replicas against the deployed script — replica-diffing had already
      failed four times and was the wrong tool for a `NA`-not-`NaN`
      signature):** `scripts/run_gbt_tuning.R` (and the earlier
      `scripts/diagnose_*.R` one-off scripts) define, at their own top
      level, a console-logging convenience helper:
      ```r
      log <- function(...) {
        cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " ", ..., "\n", sep = "")
        flush(stdout())
      }
      ```
      Because `R/pl_objective.R` is `source()`d rather than loaded as a
      package, its functions resolve an unqualified `log()` call
      lexically back to whatever environment sourced them — the driver
      script's global environment, where this helper now shadows
      `base::log()` for the rest of that R session. `pl_neg_loglik()`
      (called by `make_pl_eval()`), `pl_core()`, and `make_pl_eval()`'s
      own `logl_null` computation all called unqualified `log()`. Each
      such call therefore invoked the LOGGING helper instead of the
      logarithm: it printed its numeric argument (explaining the
      "stray stdout blob" of concatenated digits present since the very
      first diagnostic log in this incident) and returned `NULL`
      (invisibly, from `flush()`). `zc - log(denom)` became `zc - NULL`,
      which R evaluates as `numeric(0)`; `ifelse(cond, numeric(0), 0)`
      then recycles the empty "yes" vector into `NA` for every position
      where `cond` is `TRUE` — a genuine, well-known R gotcha
      (`rep(numeric(0), length.out = n)` is `NA`-filled). This is the
      exact observed signature: every divergence event was
      `source = "eval"` (never `"objective"` — `pl_grad_hess()` never
      calls `log()`), `raw_value` was literally `NA` (not `NaN`/`Inf`,
      because it never was a numerical overflow), and `logl_null` came
      back exactly `0` (`sum(log(...))` over the null-model formula
      became `sum(NULL)`) — mechanically identical at 41 different
      hyperparameter configurations because the bug never depended on
      the hyperparameters at all. This also explains why none of five
      independent fresh-process isolation attempts (including one that
      called `run_grid_point()` with byte-identical arguments to the
      deployed script) ever reproduced it: none of those throwaway test
      scripts happened to define their own `log()`, so `base::log()`
      resolved correctly every time — the deployed script was the only
      one shadowing it. **Fix:** qualify every mathematical `log()` call
      in `R/pl_objective.R` as `base::log()` (`pl_neg_loglik()`,
      `pl_core()`, `pl_core_reference()`, `make_pl_eval()`'s `logl_null`).
      Confirmed by instrumenting the live closure inside the actual
      deployed script (not a replica): pre-fix, `logl_model` was `NA`;
      post-fix, identical call site, `logl_model = -6196.96` (finite,
      correct) and a full grid-point run completed cleanly
      (`fold_mean_pl_r2 = 0.0641`, zero divergence events).
      `scripts/verify_pl_objective.R`'s full 8-assertion gate passed
      throughout this entire incident, before and after every fix — it
      never defines its own `log()`, so it was structurally incapable of
      catching this class of bug. That is a real gap in the gate's
      coverage, not a false reassurance to rely on again: a
      namespace-collision bug can be invisible to a test suite that
      never shares a global environment with the code under test.
    - **Standing project rule #1 (still true, still worth keeping):
      reproducibility checks run twice in the SAME R process can pass
      while the underlying setting does nothing, because process-constant
      state (a library's own un-seeded internal RNG, or anything else
      cached at the process level) is shared across calls within that
      process. Any reproducibility verification in this project must use
      two FRESH `Rscript` processes, not two calls in one session.**
    - **Standing project rule #2 (new): never give a driver script's own
      helper function the same name as a base R function.** `log` is
      the specific name that bit this project — every `scripts/*.R`
      driver here that prints timestamped progress messages should name
      that helper something that cannot collide (`log_msg`, `note`,
      `progress` — not `log`). This matters specifically because
      `R/*.R` files in this project are `source()`d into the caller's
      global environment rather than loaded as a namespaced package, so
      a same-named helper silently shadows the base function for
      EVERYTHING sourced afterward, with no warning. The general
      `::`-qualification convention (see "Tidyverse-first style" above)
      already covers third-party packages; this extends it to base R
      functions specifically inside `R/pl_objective.R` and any future
      numerically-sensitive hot-path file, where an unqualified call
      silently resolving to the wrong thing is far more dangerous than
      in ordinary glue code.
    - **The "`min_child_weight = 1` is the real risk axis" claim from
      Attempt 1 is WITHDRAWN, not just reopened.** There never was a
      hyperparameter-dependent numerical instability to explain — every
      divergence event in this entire incident, across three separate
      "diagnosed" causes and dozens of grid points, was this one
      namespace collision. Whether genuine numerical divergence ever
      occurs anywhere in this grid is now, again, an open empirical
      question to be read off the real `gbt_tuning_divergence.csv` from
      a clean run — not assumed present, and not assumed confined to any
      particular corner.
    - **Process-hygiene note for future debugging sessions on this
      machine:** repeated `Start-Process` / `Stop-Process -Force` cycles
      against the same log/checkpoint file paths (as this incident's
      investigation did many times) can leave orphaned `Rscript.exe`
      processes running well after `Stop-Process` returns — eight were
      found still running, spanning over half an hour, during this
      incident's cleanup. Orphaned processes writing to a shared
      checkpoint/log path concurrently with a "fresh" run produces
      corrupted-looking artifacts (stale rows interleaved with new ones,
      NUL-byte gaps in redirected output) that look like new bugs but
      aren't. Verify with `Get-Process` (not just the `Stop-Process` exit
      status) before trusting a "clean" checkpoint file's contents.
- **Tuning grid budget — fixed 2026-08-20, before any test-set number,
  supporting the §6 capacity-and-selection disclosure.** Full factorial:
  `max_depth` {2,3,4,6} x `eta` {0.01,0.03,0.1} x `min_child_weight`
  {1,5,20} x `subsample` {0.7,1.0} x `colsample_bytree` {0.7,1.0} = 144
  points x 5 folds = 720 fits; `nrounds` up to 2000, early stopping at 50
  rounds on fold-mean `pl_r2`. At ~105ms/round (post-rewrite), an
  early-stopping diagnostic on 3 representative grid points (depth
  3/eta 0.1/mcw 5; depth 2/eta 0.03/mcw 5; depth 6/eta 0.01/mcw 1/
  subsample 0.7) needed roughly 156, 369, and 1,246 rounds respectively
  to converge — low-eta points cost substantially more rounds by design,
  and the 144-point grid's eta=0.01 third (48 points) weights the
  grid-wide average toward the expensive end. Estimated full-grid
  wall-clock from this: **~12.9 hours — not comfortably under the ~12
  hour bar**, so the fallback ladder below was applied, per the fixed
  rule ("stop as soon as the projection is under 12 hours, do not cut
  further"):
  1. `colsample_bytree` -> {0.7} only. 144 -> 72 points, 360 fits.
     Estimated ~6.5 hours. **Stopped here** — comfortably under 12
     hours, so steps 2-4 (dropping `subsample` to {0.7}, dropping `eta`
     0.01, or narrowing `min_child_weight` to {1, 20}) were not applied.
     `max_depth`, the fold count, the `nrounds` cap, and the
     early-stopping patience are all untouched, per the fallback rule.
  The tuning run itself (Stage C proper: the 72-point x 5-fold CV loop,
  selection, and the Stage D final fit) had not yet been executed as of
  this note — see the paper-3 status line below for what actually ran.
- **Stage E (final fit) `nrounds` — a decision, not a default, fixed
  2026-08-21.** After Stage D selects the winning grid point,
  `fit_final_model()` (`R/gbt_tuning.R`) refits on ALL training data (no
  held-out set survives, and the test split must not be touched at this
  stage) for `round(mean_best_iteration)` rounds — the winning point's
  MEAN best-iteration across its 5 CV folds, rounded, no early stopping.
  Two alternatives were considered and not taken: fold-**median** (less
  sensitive to one fold's outlier stopping point, but discards
  information the mean uses) and fold-**maximum** (avoids ever
  under-fitting the full-data refit, on the theory that more training
  rows typically support a few more rounds than any individual 4/5-sized
  fold needed, but risks overfitting to whichever fold happened to run
  longest). Fold-mean was chosen for consistency with `fold_mean_pl_r2`
  already being the grid's own Stage D selection criterion — the same
  aggregate stands for both selecting and sizing the final model, rather
  than mixing statistics. `seed = 42L` is set inside `full_params` for
  this fit too (xgboost's own RNG, not just R's `set.seed()`) — see the
  divergence-guard note above for why that specific placement is the one
  that matters.
- **Stage E permutation importance — training split, within-race, 30
  repeats, seed 42.** `permutation_importance_within_race()`
  (`R/gbt_tuning.R`) shuffles each feature's values WITHIN each race
  (which horse holds which value; every race's set of values and every
  other feature untouched) rather than globally across the training set —
  a global permutation would destroy field composition and confound "does
  this feature matter" with "does having a coherent field matter."
  Deliberately scored against the training split's `pl_r2`, not the test
  split's — the test split is not touched anywhere in Stage E. The
  out-of-sample permutation run belongs in the results/analysis pass
  alongside the Q1–Q3 comparisons, on a common race set with everything
  else that touches the test split, not brought forward into tuning.
- **Going affinity** is added as a feature and is, by design,
  confounded with the model-class change (linear models never saw it).
  Addressed via predictor importance (does the model use it), not an
  ablation fit (does it help out of sample) — see the honesty
  requirement below. Built by `R/build_going_features.R`
  (`build_going_features()`), wired into `runners_augmented` via the
  `going_features` target. Four columns: `going_runs_prior`,
  `going_sr_shrunk` (shrunk toward the horse's own career win rate,
  prior weight `m = 5`, `GOING_SHRINKAGE_M`), `going_sr_delta`
  (`going_sr_shrunk` minus career rate — the affinity-vs-ability
  separation), `going_ordinal` (today's going, never NA). Strict-before,
  cross-surface, per the standing decisions above; going_bucket
  (FAST/STANDARD/SLOW) is defined **within surface** (AW vs Turf =
  Flat+Hurdle+Chase+NH Flat pooled) at that surface's own terciles of
  raced volume — AW's terciles collapse to a single point (q1=q2=4,
  "Standard", since AW going is 98.4% Standard by construction), Turf's
  don't (q1=3, q2=4). No zero-imputation and no missing-indicator
  companion column for the three horse-level columns (unlike
  `or_relative`/`or_missing`) — see the missing-handling note below.
  Verified in `scripts/verify_going_features.R` (8 assertions, all
  passing, incl. an exact match of `going_runs_prior` for a 200-sample
  brute-force recomputation and byte-identical pre-existing
  `runners_augmented` columns).
- **Going-affinity NA is exempt from the paper 2/2a/2b complete-case
  rule.** `model_fitting_p2_vars()` never lists the `going_*` columns,
  so no paper 1/2a/2b conditional-logit fit's race universe is affected
  by their NA-bearing values (confirmed: the paper 2b exploded-
  interactions training race count behind `model_2b_exploded_draw_final`
  — `build_interaction_features()` + the draw extra_na_vars — is
  unchanged, **5,022** races, before vs after the join). *(An earlier
  version of this note said 5,023, from checking a different,
  non-interaction complete-case set by mistake — corrected 2026-08-20;
  see `scripts/verify_going_features.R` assertion 7.)* Reason it must
  stay this way for paper 3 too, rather than joining the GBT's
  complete-case rule to going-affinity NA: (1) XGBoost has native
  missing-value handling (a learned default split direction per node),
  so an NA feature value is not a fitting obstacle the way it is for
  `{mlogit}`; and (2) the paired race-level ROI bootstrap against 2b
  (frozen-for-comparability list above) needs paper 3 to score the
  *same* test races 2b does — dropping races for going-affinity NA
  would break that comparison for no modelling benefit.
- **Going is near-constant in the modelling universe — found
  2026-08-20, read this before drafting §2/§6.** AW going is 98.4%
  "Standard" across the full career-history universe and 98.7%
  "Standard" across `qualifying_races` (88 of 7,441 races non-Standard
  and non-NA); on the paper 2b complete-case training set specifically
  (5,022 races) it is 98.9% Standard (`going_ordinal` = 4), with only
  57 races at ordinal 2/3/5/6 and 8 with NA going.
  `sd(going_ordinal)` on that fit set is **0.147** on a 1–7 axis —
  `going_ordinal` is very close to a constant there. Four consequences
  for the paper, all to be stated by us, not left for a reader to
  notice:
  - The tree will almost never split on `going_ordinal` itself — there
    is essentially no within-AW variation to split on. This does not
    argue against including it (it is still the right race-level
    control, and it is cheap), but the paper must not imply the model
    is meaningfully weighing "how fast today's ground is" — there is
    barely any "today's ground" variation in this dataset to weigh.
  - **`going_sr_shrunk` / `going_sr_delta` measure ground-type form,
    not going preference, for ~99% of runners.** Because today's
    bucket is STANDARD for nearly every runner, and STANDARD pools AW
    Standard with turf Good (going_bucket is defined within surface,
    see above), the feature is really "the horse's win rate on
    Standard-or-Good ground relative to its own career rate" for
    almost the whole fit set — a ground-type form measure, not a
    preference for *today's specific going* in the sense the note's
    framing and paper 2b's discussion promised. §2 must state this
    plainly when the feature is introduced; §6 must not claim the
    paper tested going affinity in the fuller sense (fast vs standard
    vs slow discrimination) that data this skewed cannot support.
  - The note's illustration of a tree splitting on going and then a
    distance record, letting the effect of distance record differ by
    going, is expositional — a general property of how depth-≥2 trees
    can express interactions, not a claim about what this fit
    actually finds. With going this close to constant, that specific
    interaction has almost no room to appear in the data; the paper
    must not assert it was found.
  - `going_sr_delta` is **exactly 0 for 23.9% of train-split runners**
    with a defined value (11,332 of 47,454) — of those, 59.1% (6,697)
    are single-bucket careers, where the shrinkage formula forces
    `going_sr_shrunk == career_sr` exactly by construction (see
    `build_going_features()` roxygen); the remaining 40.9% are
    coincidental exact matches. A further 7.9% (3,765) are near-zero
    (0 < |delta| ≤ 0.005) without being exactly 0. Report the 23.9%
    share in §2 alongside the near-constant-going point — it is a
    second reason a large share of the feature's mass sits at or near
    zero, distinct from the "no career history" NA case.
  - **Follow-up check result, reported for the record (not yet in any
    model):** on the train split, mean field size is flat across
    `going_sr_delta` deciles (9.4–10.1, no gradient), which rules out
    a field-size-mechanical explanation for the decile pattern; a
    race-level bootstrap (B = 2000, seed 42) on the win-rate difference
    between decile 10 and decile 1 gives a point estimate of +0.030
    with a 90% CI of **[0.019, 0.040] — excludes zero**. This is
    evidence the feature (as it actually operates in this near-
    constant-going universe, i.e. mostly a ground-type-form signal)
    correlates with the outcome on the training data; it is not
    evidence for "going affinity" in the fuller sense the feature was
    originally framed as, per the point above. Permutation importance
    on the test split, once the GBT is fitted, is the metric that
    actually answers whether it earns its place in the model.
- **Cross-vocabulary integrity — a real, quantified, small data-quality
  issue, not yet fixed.** Some `race_type` values in the underlying DB
  are unreliable at the two dual-surface AW courses (Lingfield,
  Kempton) — extending the project's existing "`all_weather` flag is
  unreliable" finding to `race_type` itself, at small scale. Evidence:
  3,777 career-history rows tagged `race_type` = Flat/Hurdle/Chase/NH
  Flat report going = "Standard" (an AW-only term, never used for
  genuine turf going) — 70.7% of them at Lingfield, and 645 at courses
  with **no turf track at all** (Southwell, Wolverhampton, Dundalk,
  Great Leighs), which is unambiguous: those rows are genuine AW races
  mis-tagged as Flat/jumps. Symmetrically, 2,233 rows tagged
  `race_type` = "All Weather Flat" report turf-vocabulary going
  (Good/Good to Firm/Good to Soft/Soft/Firm/Heavy) — 94.2% at
  Lingfield again, plus 87 rows at courses with **no AW track at all**
  (Windsor, Doncaster, Leicester, Folkestone, Bath, Haydock, Warwick,
  Newbury, Nottingham, Tipperary, Roscommon), equally unambiguous the
  other way. Three smaller, distinct anomalies found alongside this:
  Laytown (36 rows, going = "Standard") is a turf-only course that
  races once a year on a tidal beach — likely a placeholder going
  value for a course with no established going vocabulary, not a
  surface mis-tag. Wolverhampton/Southwell (43 rows, 2003–2008) report
  turf-vocabulary going with a *correctly* AW-tagged `race_type` —
  concentrated in AW racing's early years, consistent with a
  pre-standardisation going-terminology convention rather than any
  mis-coding. "TurfTV_Extras" (11 rows, one meeting, 2014-11-24) is not
  a real course name — a data artifact, unrelated to the going/surface
  question. **Quantified impact on `going_bucket` specifically:**
  because the AW cut points are so skewed (q1 = q2 = 4), a
  surface-tag error only changes the resulting bucket for going =
  "Good to Firm" (ordinal 3: AW → FAST, Turf → STANDARD) — every other
  going value in the confused set happens to land in the same bucket
  either way. That is 1,090 career-history rows (0.22% of 486,055),
  concentrated at Lingfield. **Not fixed.** A future pass could
  cross-check `race_type` against `going` (AW-only terms imply AW;
  turf-only terms at a dual-surface course imply Turf) to correct it;
  left as a follow-up, out of scope for the going-affinity feature
  itself since the quantified impact is small.
- **Frozen for comparability with papers 1/2a/2b** (do not vary any of
  these in paper 3): data scope; the 2012-12-30 race-level
  chronological split; the diagnostic suite (Owen Table 3, Figures 7
  and 8, the §3.4 backtest); `P1_rank`; `Brier_place`; McFadden
  pseudo-$R^2$; the discounted-Harville market baseline (α = 0.80 /
  0.65); single-bet-per-race as the primary betting rule; the paired
  race-level ROI bootstrap at B = 2000, seed 42.
- **Paper outline (fixed shape to build to):**
  - §1 Intro — the lever this paper pulls is the model class.
  - §2 Data and features — same scope and split as 1/2a/2b; one new
    feature, going affinity, from a career-history sub-query.
    Exploratory work on `split == "train"` only.
  - §3 Method — why the loss stops factorising per observation; latent
    scores; softmax over the field; interactions found rather than
    specified. Prose only, maths to the appendix.
  - §4 Model fitted — the GBT: feature matrix, race grouping, tuning
    grid and budget, selected hyperparameters, training McFadden
    pseudo-$R^2$. **Must include a subsection documenting the numerical
    tuning procedure** (decided 2026-08-21) — this is what makes the §6
    tuning-asymmetry disclosure (linear models got a hand-run Wald
    reduction, this got a cross-validated grid) legible rather than an
    unexplained caveat:
    - The grid fixed in advance (72 points, the fallback ladder, and
      which rung was reached — see "Tuning grid budget" above).
    - The race-grouped 5-fold CV.
    - Early stopping determining `nrounds` PER FOLD DURING SELECTION —
      not the grid — versus the separate fold-mean-rounds decision for
      the refit (see "Stage E (final fit) `nrounds`" above).
    - The selection rule and tie-break (`select_best_config()`: highest
      `fold_mean_pl_r2`; among points within 0.001 of the max, lowest
      `max_depth` then lowest `mean_best_iteration`).
    - The refit at fold-mean rounds on all training data.
    - A short paragraph (not a table) on where the compute goes: the PL
      objective is evaluated twice per boosting round (`make_pl_objective()`
      + `make_pl_eval()`), which dominates the ~105ms/round cost from the
      `{data.table}` rewrite — tree-building itself is comparatively
      cheap.
    - The divergence guard: that it exists (floors a diverging
      configuration to a sentinel rather than dropping it), and the
      **count from the clean, seeded run** — not the incident. The
      seeding bug and the first attempt's now-void divergence table are
      project history (this file), not paper content; §4 states only
      that the guard exists and what the clean run's count was.
  - §5 Results — three questions in order, predictor importance sits
    with Q1:
    - Q1: does the tree class beat the linear predictor on the
      ranking objective (vs `ranking_metrics_2b`, with the market
      baseline)?
    - Q2: does it make a better win-picker (vs `backtest_naive_2b_win`
      and 2a's `backtest_naive_w_final`, paired bootstrap on common
      test races)?
    - Q3: does it translate into betting value (single-bet rule at
      real SP, place and each-way, ratio sweep with CIs)?
  - §6 Discussion, including limitations.
  - Appendix A — follows the derivation in
    `notes/Notes on Trees-based Methods.pdf`, compressed. Assume the
    reader knows regression trees, pruning, bagging and random
    forests; do not reproduce that preliminary material. Chain to
    keep: squared error → pseudo-residuals under a general loss;
    likelihood substitution; the quadratic approximation giving the
    leaf value in closed form; the grouped Plackett–Luce likelihood
    and what breaks when the loss stops factorising; the gradient and
    diagonal Hessian in the note's notation, noting in passing that
    XGBoost consumes the diagonal only. Carries over the note's four
    references into `papers/03_*/references.bib` when that paper is
    scaffolded (verified bibliographic details, not the note's own
    citation keys):
    - James, G., Witten, D., Hastie, T., & Tibshirani, R. (2021). *An
      Introduction to Statistical Learning with Applications in R*,
      2nd ed. Springer. (Chapter 8.)
    - Johansson, R. *An intuitive explanation of gradient boosting.*
      Lecture notes, DIT866, Chalmers University of Technology /
      University of Gothenburg. No publication year stated in the
      document itself — do not invent one.
    - Li, C. *A Gentle Introduction to Gradient Boosting.* Slides,
      College of Computer and Information Science, Northeastern
      University. No publication year stated in the document itself —
      do not invent one.
    - Chen, T., & Guestrin, C. (2016). XGBoost: A Scalable Tree
      Boosting System. *Proceedings of the 22nd ACM SIGKDD
      International Conference on Knowledge Discovery and Data
      Mining* (KDD '16), San Francisco, 13–17 August 2016, 785–794.
  - Appendix B — software, following the papers 1/2a/2b pattern.
- **Two honesty requirements (carry into the drafting pass):**
  - Gain-based importance is an in-sample decomposition of the fitted
    loss. State once, plainly (same register as paper 2a's "reduction
    rule, stated honestly" paragraph): it answers whether the model
    *used* going affinity, not whether going affinity *helped out of
    sample*.
  - The linear models were reduced by a hand-run Wald rule; the GBT
    gets a cross-validated grid. That is a capacity-and-selection
    asymmetry and a live alternative explanation for any GBT gain —
    state it ourselves in §6, with the tuning budget fixed and
    reported, rather than leaving it for a reader to notice.
- **Missing-going-affinity handling must be stated in the paper, twice.**
  Paper 3 relies on XGBoost's default-direction missing-value handling
  for the three horse-level going columns rather than imputing (no
  zero-fill, no missing-indicator companion — see "Going affinity"
  above) — say this explicitly in **§2** where the feature is
  introduced (why no imputation: absence — no prior runs at all, or none
  in this bucket — is itself informative, and imputing would discard
  that) and again in **§4** where the fit is described (the mechanism:
  XGBoost learns a default split direction per node from the training
  data and routes every missing value that way).
- **Status: tuning grid run to completion 2026-08-22; results below.**
  `R/pl_objective.R` (the custom PL objective for `{xgboost}`,
  `{data.table}`-vectorised as of 2026-08-20, `log()`-shadowing fixed
  2026-08-21) and its verification gate (`scripts/verify_pl_objective.R`,
  9 assertions, see the divergence-guard note above for what #9 covers),
  `R/build_going_features.R` and its verification gate
  (`scripts/verify_going_features.R`), `R/gbt_data.R` / `R/gbt_folds.R`
  (feature-matrix builder + race-grouped CV folds), and Stage E
  (`fit_final_model()`, `permutation_importance_within_race()`,
  `paper2b_training_pl_r2()`, all in `R/gbt_tuning.R`) all exist and are
  tested. The 72-point grid, Stage D selection, and Stage E have now run
  to completion once, cleanly (**zero divergence events across all 72
  points** — the decisive confirmation that the entire multi-day
  divergence incident above was the `log()` shadowing bug and nothing
  else). Still **not yet wired into `_targets.R`** — no `model_3_gbt`
  target, no tuning-results target. `papers/03_*/` is not yet
  scaffolded. Numbers below are training-side only; the test split has
  not been touched by anything in this run.
  - **Wall-clock: ~11h (10h59m) for 72 points** — validates the fallback
    ladder's decision to cut `colsample_bytree` to {0.7} rather than
    running the full 144-point grid: at this measured rate the full grid
    would have taken **~22 hours**, not the ~12.9h estimated when the
    ladder was applied. The reduction was necessary, not cosmetic.
  - **Selected: `max_depth=3, eta=0.03, min_child_weight=1,
    subsample=0.7, colsample_bytree=0.7`, refit at `nrounds=698`**
    (fold-mean best iteration 698.4, rounded). Not a boundary optimum
    (`max_depth≠6`, `eta≠0.1`). Tie-break invoked: 11 of 72 points
    scored within the pre-declared 0.001 window of the grid max
    (0.06867); this point was the shallowest among them with the fewest
    rounds, per the fixed rule.
  - **Every one of the top 10 points has `subsample=0.7`** —
    `subsample=1.0` appears nowhere in the top 10 of 72. Row
    subsampling reliably helps in this grid; worth one line in §4.
  - **The grid is flatter than the 0.001 tie window alone suggests, but
    not as flat as the marginal fold sd (~0.006, six times the tie
    threshold) makes it look at first glance — properly measured, it's
    narrower than either naive read.** A paired fold-level comparison
    (same 5 folds throughout the grid, so paired SE — not the marginal
    per-point fold sd — is the right yardstick) between the grid max
    (depth=4, eta=0.01, mcw=20, subsample=0.7, mean=0.06867) and every
    other point finds only **3 of 72 points fall within 1 paired SE of
    the max** — the max itself plus the two other depth=4/eta=0.01
    points differing only in `min_child_weight` (paired mean diff
    0.0000558 and 0.000182 against paired SEs of 0.000279 and 0.000268).
    The selected point (depth=3, eta=0.03) is NOT among these three: its
    paired mean diff from the max is 0.000905 against a paired SE of
    0.000717 (~1.26 SE away) — close in absolute terms (0.0009 in
    `pl_r2`) but outside the strict 1-SE band. **§4 should report this
    paired result, not the marginal-sd comparison**: "3 of 72
    configurations are statistically indistinguishable from the grid
    maximum" is the properly-measured version of the flatness finding,
    and it still supports (if somewhat more narrowly than the naive
    read) the same conclusion for §6: tuning bought little, which
    weakens tuning as an alternative explanation for any GBT-vs-linear
    performance gap found later.
  - **Tie-break disclosure (state plainly in §4): the selected point is
    not, on a paired test, tied with the grid maximum.** The pre-declared
    0.001 tie window is roughly 1.3–3.6x the paired SEs actually observed
    near the top of this grid (0.0003–0.0007) — a fixed absolute
    constant chosen before seeing the paired structure of the data
    turned out to be wider than the paired uncertainty it was meant to
    approximate. The selected point sits ~1.26 paired SE from the max,
    i.e. outside the 1-SE band that only 3 of 72 points satisfy. **The
    rule was fixed in advance and stands — that is what pre-declaration
    is for** — but §4 must say plainly that the tie-break, as specified,
    selected among points that a paired test would not call tied.
    **Standing methodological note for the series: a fixed tie
    threshold should be set relative to the paired SE of the metric
    being compared, not as an absolute constant chosen before the
    paired structure of the data is known.** A future paper's grid
    search should either compute the paired SE first and set the window
    as a multiple of it, or report the paired comparison alongside
    whatever fixed window was used, as done here. (The tie-break's
    practical stakes turned out to be low regardless — see the refit
    comparison below — but that was found out, not known in advance.)
  - **In-sample training `pl_r2`: GBT 0.09200 vs. paper 2b's own
    training `pl_r2` (k=3, identical metric) 0.05416 — label this
    IN-SAMPLE everywhere it appears and do not let it into §5 as a
    result.** A 698-tree depth-3 ensemble out-fitting a linear model
    in-sample is expected by construction (more capacity, no
    out-of-sample penalty here) and is not evidence the GBT ranks
    better out of sample — that question is Q1/Q2 of the results pass,
    against the test split.
  - **Permutation importance: no feature's `mean_drop` is smaller than
    its own `sd_drop`** (checked across all 24 features, 30 repeats
    each) — every nonzero importance value is statistically
    distinguishable from noise at this repeat count. The 5 features
    with an exact `mean_drop = sd_drop = 0` (`going_ordinal` and all
    four course dummies) were never used by the fitted model in a way
    permutation detects — a clean zero, not noise.
  - **Correlation caveat for the going features (record here AND
    surface in §5 alongside the importance table):**
    `going_sr_delta` and `going_sr_shrunk` correlate at **r=0.319** on
    the training split (unsurprising — `going_sr_delta` is
    `going_sr_shrunk` minus the horse's career win rate, so the two
    share a term by construction). `going_runs_prior` and
    `going_ordinal` are both close to uncorrelated with everything
    (|r|≤0.10). **Permutation importance systematically UNDERSTATES
    correlated predictors** — permuting one of a correlated pair still
    leaves its partner intact to partially compensate for the lost
    signal, so a correlated feature's measured importance is a lower
    bound, not a point estimate. `going_sr_shrunk` (rank 12) and
    `going_sr_delta` (rank 13) should be read with this in mind; their
    true joint contribution is understated by looking at either one's
    permutation rank alone.
  - **STRUCTURAL LIMITATION, found 2026-08-22, corrects an initial
    misreading below: within-race permutation importance cannot measure
    ANY race-level feature, regardless of that feature's true
    importance.** `going_ordinal` (today's going) and all four
    `course_*` dummies are constant for every runner in a given race by
    construction — they describe the race, not the horse. Permuting
    "which horse holds this value" within a race that already has one
    value for every horse is a no-op: the permuted column is identical
    to the original, so the measured `pl_r2` drop is exactly `0` with
    exactly `0` variance across all 30 repeats, independent of whether
    the feature matters. This was checked, not assumed: dumping the
    SELECTED model's fitted trees (`xgb.model.dt.tree()`) shows all four
    course dummies genuinely ARE split on (`course_Kempton` 20 times,
    `course_Lingfield` 19, `course_Southwell` 23,
    `course_Wolverhampton` 22, out of 4,868 total splits) — ruling out
    "silently never reached the model" as the explanation before this
    got written up. The training matrix itself is clean too: all four
    columns present, correctly named, non-degenerate (variance
    0.12–0.21), no NA, and exactly one course dummy is `1` per row
    across all 45,970 training rows. **This must be stated in §5,
    not left implicit: the within-race permutation column is silent on
    any race-level feature — a reader must not take that zero as a
    finding of unimportance.** Name the course dummies as the proof
    (19–23 splits each, so the model demonstrably uses them, and
    permutation still reports exactly nothing) — that is the concrete,
    checkable evidence that the zero is a method artefact, not a
    substantive result.
  - **`permutation_importance_across_races()` (`R/gbt_tuning.R`,
    2026-08-22): the correct null for a race-level feature.** Permutes
    the feature's value ACROSS races (which race gets which value) while
    holding it constant WITHIN each race, preserving the feature's
    race-level structure and breaking only its association with the
    outcome — the within-race function's null (shuffle who holds a
    value within a race) is meaningless when nobody in the race holds a
    different value to begin with. Verified before trusting it: a
    pre-check confirms all five race-level features have exactly `0`
    races with more than one distinct value (i.e. they really are
    constant within every race, not merely assumed to be). Same
    convention as the within-race function: 30 repeats, seed 42,
    training split only. **Uses a DIFFERENT null than the within-race
    function and is NOT directly comparable to it — report as a
    separate table in §5, not merged into the horse-level one.**
    Results, sorted by `mean_drop` (all 5 comfortably exceed their own
    `sd_drop` — none is noise):
    | feature | mean_drop | sd_drop | rank (of 5) |
    |---|---|---|---|
    | course_Southwell | 0.000201 | 0.0000202 | 1 |
    | course_Wolverhampton | 0.000190 | 0.0000259 | 2 |
    | course_Kempton | 0.000166 | 0.0000169 | 3 |
    | going_ordinal | 0.000129 | 0.0000141 | 4 |
    | course_Lingfield | 0.000102 | 0.0000133 | 5 |
    All five race-level features have a small but genuine, statistically
    real effect under the correct null — roughly two to three orders of
    magnitude smaller than the top horse-level features (`or_relative`
    mean_drop 0.078), consistent with them being minor, not negligible,
    contributors. `going_ordinal` ranks 4th of 5 among race-level
    features specifically — it contributes less than three of the four
    course dummies, but more than `course_Lingfield`.
  - **Going features' positions, both rankings (of 24 features):**
    | feature | gain rank | gain | permutation rank | mean_drop |
    |---|---|---|---|---|
    | going_sr_shrunk | 9 | 0.0338 | 12 | 0.00283 |
    | going_sr_delta | 11 | 0.0240 | 13 | 0.00272 |
    | going_runs_prior | 12 | 0.0223 | 16 | 0.00195 |
    | going_ordinal | 23 | 0.0014 | 24 (within-race; not comparable — see across-race table above) | — |
    **`going_ordinal`'s within-race permutation rank of 24 is NOT
    confirmation of the near-constant-going finding — it is a method
    artefact, guaranteed for any race-level feature regardless of true
    importance.** Its across-race permutation result (rank 4 of 5 race-
    level features, mean_drop 0.000129, real and nonzero) is the
    honest permutation-based number. Its gain rank of 23/24
    (`Gain=0.0014`, 19 splits — the same order of magnitude as the
    course dummies' 19–23) is separately informative and IS consistent
    with the near-constant-going finding (98.9% Standard leaves little
    cross-race variation for a tree to exploit) — but it supports that
    conclusion only weakly, and only in-sample.
  - **Tie-break robustness check (2026-08-22, one refit, training-side
    only):** the pre-declared 0.001 tie window is an absolute constant,
    not scaled to the paired SE (~0.0007–0.0003 near the top of this
    grid) — see the tie-break disclosure note above; this is the
    empirical check of whether that gap actually matters. Refit the
    GRID MAXIMUM (`max_depth=4, eta=0.01, min_child_weight=20,
    subsample=0.7`, at its own fold-mean 1507 rounds) the same way as
    the selected point. In-sample `train_pl_r2`: grid max 0.10219 vs.
    selected 0.09200 (grid max higher, expected — more depth and
    ~2.16x the rounds, not a meaningful comparison on its own). **The
    top-10 gain-importance ranking is nearly identical between the two
    models** — the same 10 features, in the same order, except
    `pos_lag2_nonzero`/`trainer_aw_premium` swap ranks 7/8. **This closes
    the question for §4: the tie-break's practical stakes are low —
    whichever of the near-tied configurations the fixed rule had
    selected, the substantive feature-importance story is the same.**
  - **Nrounds-cap check (2026-08-22, `scripts/diagnose_nrounds_cap.R`,
    training-side): none of the near-cap points were truncated.** Four
    grid points had `mean_best_iteration >= 1900` (close to the 2000
    cap): the three `max_depth=2, eta=0.01` points (mcw 1/5/20, all
    ~1998) and `max_depth=3, eta=0.01, mcw=1` (1943, the tie-break's
    second-highest scorer). Per-fold `best_iteration` isn't stored in
    the checkpoint (only the fold mean), so this re-ran all 4 points'
    5 folds each (deterministic given the seed fix, reproducing the
    original run's `fold_mean_pl_r2` exactly) and recorded each fold's
    own `best_iteration`. **Result: 0 of 20 folds hit the exact 2000
    cap** — every fold's early stopping genuinely triggered on its own
    (individual fold iterations ranged 1724-1999). None of these four
    points' scores are understated by truncation; all are converged
    values. Flagged as low-value before running (all four points score
    below the selected/tie-break set, so truncation could only have
    raised already-losing scores) and the result confirms there was
    nothing to find — recorded for completeness.
- **Paper 3 results pass (test split) — 2026-08-22,
  `scripts/run_results_pass.R`. THE ONLY TEST-SET CONTACT for paper 3.**
  Every modelling decision (feature set, hyperparameters, `nrounds`, the
  fitted `gbt_final_model.xgb`) was fixed by the training-side pass above
  before this ran; nothing here fed back into model selection. Figures
  below are marked test-split throughout — this is the single source for
  the drafting pass.
  - **Two test universes exist for paper 2b, and paper 3 sits on the
    smaller one throughout — state this in §2 where the universe is
    defined, and use the RESTRICTED comparison in every §5 table.**
    `prepare_exploded_data()` (the same function `build_gbt_matrix()`
    reuses for paper 3, matching the training-side convention) requires
    a **clean top-3**: positions 1, 2 and 3 each recorded exactly once,
    because a depth-3 model needs a well-defined top-3 to explode into
    choice sets. A plain win-only backtest doesn't need this — it only
    needs to know who won. Consequence: paper 2b's own **ranking**
    evaluation (`ranking_eval_runners_2b`) runs on **2,183** test races,
    while its **win-backtest** evaluation (`test_predictions_2b`,
    feeding `backtest_naive_2b_win` etc.) runs on **2,193** — ten more,
    the messy-top-3 races that are unscorable for ranking but perfectly
    fine for "did the favourite-ish pick win." Paper 3's feature matrix
    comes through the exploded/ranking-compatible path only (there is no
    separate, looser construction), so it uses 2,183 throughout, for
    Q1/Q2/Q3 alike — ten races short of 2a's and 2b's own published
    win-backtest and single-bet figures. The ten excluded races are
    **not random** (they are specifically the dead-heat / amended-
    position-gap races), so this is a real asymmetry, not a rounding
    footnote. **Fix applied throughout Stages C and D:** every 2a/2b
    comparison figure is reported in three columns — PUBLISHED (the
    model's own, larger universe, as originally reported), RESTRICTED
    (the identical stored predictions and backtest functions, recomputed
    on paper 3's 2,183-race subset, no refit), and PAPER 3 (2,183). The
    restricted column is the only like-for-like comparison and is what
    every §5 table must use; the published column stays alongside it so
    a reader can see whether restricting the universe changed anything
    materially. The paired race-level ROI bootstrap
    (`bootstrap_roi_difference()`) intersects race sets automatically
    regardless, so the contrast and its CI were never affected by this —
    but report which universe and how many races it actually used
    (`n_common` in its own output) alongside the point estimate, rather
    than leaving it implicit.
  - **Stage A gate (race-universe check): compares against
    `ranking_eval_runners_2b` (2,183), not the raw `test_predictions_2b`
    win-backtest universe (2,193)** — the first version of this check
    compared against the wrong reference and stopped on an apparent
    10-race mismatch; investigating (rather than loosening the check)
    found the real two-universe structure above, and confirmed all 10
    "missing" races are absent from `ranking_eval_runners_2b` too, for
    the identical clean-top-3 reason. Corrected reference: exact match
    (0 races either side), as required before Stage B proceeds.
- **Rebuild gate — to-do, not yet run.** `runners_augmented` now has new
  (`going_*`) columns, so its content hash changed; the next full
  `tar_make()` will invalidate and re-fit/re-render every downstream
  target, including papers 1, 2a and 2b, even though every pre-existing
  `runners_augmented` column is verified byte-identical (see
  `scripts/verify_going_features.R` assertion 6). This session only ran
  a scoped `tar_make(names = "full_history")` — no downstream target has
  actually been rebuilt yet. **Before republishing anything** off the
  next full `tar_make()`, diff the headline published figures against
  the current `docs/paperN/index.pdf` and confirm they are unchanged:
  paper 1 §3.4 backtest ROI (−28.2%), paper 2a's `model_w_final` backtest
  ROI (−25.4%), paper 2b's win/place single-bet ROI (−17.4% / −9.8%) and
  its ranking metrics (P1_rank 0.00402 model vs 0.00543 market;
  Brier_place 0.2013 vs 0.1875). Report any difference rather than
  overwriting `docs/` — a byte-identical-columns fit that nonetheless
  produces different numbers would mean something in the pipeline is
  non-deterministic (e.g. an unset seed) and needs investigating before
  anything is republished.
- **`{xgboost}` used directly, not via `{tidymodels}`/`{parsnip}`** —
  parsnip has no interface for a custom objective plus a custom eval
  metric plus group info. Same kind of documented exception as the
  `{mlogit}` route in papers 1/2 (see "Tidyverse-first style" above).

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
