# awracing — Claude Code memory

Statistical models of UK All-Weather racing outcomes, built on the
Smartform MySQL database in R. Multi-paper series; current state below.

## Default to proceeding

Do not stop for approval on implementation choices, performance work,
refactors, debugging, or anything reversible under version control. Make
the call, do the work, and report what you did and why afterwards. A stop
costs a full turn; a reversible mistake costs a `git checkout`.

Stop and ask only when one of these is true:
- The action would change or republish a **published figure** — anything
  under `docs/`, or any headline number in papers 1, 2a, 2b or 3.
- The action would **modify a model specification** that affects reported
  results. The existing model-spec gate stands.
- The action would **destroy or overwrite state not recoverable from
  git**: `renv.lock`, the `_targets` store, the database, `.env`.
- The action would **commit a large irreversible spend of wall-clock** —
  a run projected beyond about 12 hours.
- A prompt explicitly says to stop.

Verification gates are not a reason to stop; they are the reason not to.
Where a gate exists — `scripts/verify_pl_objective.R`,
`scripts/verify_going_features.R`, `scripts/verify_rebuild.R`,
`scripts/verify_p4_market_probs.R`, `scripts/verify_p4_data_targets.R`,
`scripts/verify_p5_pl_torch.R`, `scripts/verify_p5_gru_mask.R`,
`scripts/verify_p6_ledger.R` — proceed and let the gate catch you. If a
gate fails, fix it and report. Do not ask permission to fix it.

Two calibration examples (2026-08-20):
- **The tuning-grid stop was CORRECT.** A 37-hour projection (before the
  `pl_objective.R` speedup) is an irreversible spend.
- **The performance-rewrite stop was UNNECESSARY.** The rewrite was
  reversible and covered by a gate (`scripts/verify_pl_objective.R`).
  The right behaviour was the rewrite-debug-fix-reverify cycle actually
  run unprompted, reported after the fact — not pausing to ask first.

## Papers

Statistical models of UK All-Weather Flat handicap outcomes on the
Smartform database. Each paper changes one thing and reports the result
against the previous paper and against the betting market. Papers 1 to 4
are complete and published; paper 2 is split into 2a and 2b, so the list
below has five entries for four numbered papers.

- **Paper 1 — Replicating Owen (2019) on UK AW Flat handicaps,
  2006–2015.** Coefficient picture broadly consistent with Owen; the
  reduced model loses money on the naive betting backtest (−28.2% ROI,
  1,713 bets), which the paper attributes mainly to the starting price
  aggregating richer information than the 13-feature predictor set.
  Live: <https://gillenpj.github.io/awracing/paper1/>.
- **Paper 2a — Extended feature set and the conditional-logit win
  model.** An extended feature set plus a course×draw interaction
  narrows the backtest loss to −25.4% ROI — directionally consistent
  with an improvement over paper 1, but a paired race-level bootstrap
  can't distinguish the gain from zero.
  Live: <https://gillenpj.github.io/awracing/paper2a/>.
- **Paper 2b — Exploded conditional logit as a ranking model.** Same
  features, a depth-3 (top-3) ranking objective instead of win-only.
  Beats chance at predicting the finishing order but not the market
  (P1_rank 0.00402 vs 0.00543; Brier_place 0.2013 vs 0.1875). Ranking
  supervision makes a statistically distinguishable better win-picker
  than 2a (−17.4% vs −25.4% ROI). Single-bet-per-race place/each-way
  returns −9.8%/−7.7%, roughly half the loss of backing every qualifier.
  Live: <https://gillenpj.github.io/awracing/paper2b/>.
- **Paper 3 — Gradient boosted trees for UK AW Flat handicaps.** Same
  features and ranking objective as 2b; only the function class changes
  (linear score → gradient-boosted tree ensemble, custom Plackett–Luce
  objective). Ties 2b on every ranking, win-picking and betting-value
  measure tested — every paired-bootstrap CI against 2b contains zero —
  while the market still beats both decisively on ranking (P1_rank and
  Brier_place CIs exclude zero: the one distinguishable contrast in the
  whole series). Reading: the linear predictor was not the binding
  constraint, so the feature set — not the function class — is the next
  lever. Tuning-grid provenance:
  `papers/03_gradient_boosted_trees/TUNING_PROVENANCE.md`.
  Live: <https://gillenpj.github.io/awracing/paper3/>.
- **Paper 4 — The marginal value of a model over the market.** Changes
  no model. Releases the constraint that market data stays out, and asks
  whether the model adds anything *given* the price rather than whether
  it beats it, via a two-stage conditional logit (Benter) with both
  coefficients free. Reuses papers 2b and 3's stored test predictions;
  neither refitted. Against the settled starting price the model adds
  nothing distinguishable — pooled `b_mod` 0.068 (2b) and 0.039 (GBT)
  over 2,182 races, 95% intervals reaching no higher than 0.204. Against
  the pre-race racecard forecast price it adds substantially (1.037 and
  1.026 on the earlier test half, 0.746 and 0.723 on the later). Reading:
  of the two explanations papers 1–3 could not separate — the market
  knows strictly more, or the two know overlapping but different things —
  the settled market knows strictly more, and the model's value sits in
  the interval between an early price and the off. Own pipeline and
  store (`_targets_p4.R` / `_targets_p4`). Pre-registration:
  `papers/04_market_blend/PRE_REGISTRATION.md`.
  Live: <https://gillenpj.github.io/awracing/paper4/>.
- **Paper 5 — Sequence encoding of run histories.** Changes how a horse's
  own run history reaches the model. Eight of the 26 features — the two
  position lags and their indicators, `has_wins` and the three
  going-affinity terms — are replaced by a GRU encoder reading the 20 most
  recent prior runs directly, eight values a run, with the raw finishing
  position instead of a top-four code. The other 18 features, the races,
  the depth-3 Plackett-Luce objective and the downstream MLP scorer are
  unchanged. On the test split the encoder beats the hand-built summaries
  on all three ranking measures — P1_rank +2.586e-04, Brier_place
  −3.204e-03, pseudo-R² +1.059e-02, every 90% interval excluding zero —
  and beats paper 3 by more, so three models order strictly: **paper 3 <
  MLP on hand-built summaries < encoder**, nine contrasts and nine
  exclusions of zero, on a split where papers 1-3 could not be told apart.
  The market still ranks ahead of all of them, and **no ROI improvement is
  distinguishable from zero** (win ROI −12.2%, the best in the series, but
  the difference from paper 3 is +10.1 points with a 90% interval of
  [−4.0, +23.3]; eight of nine ROI intervals contain zero).
  Two findings from the ladder that got there: an MLP beat a linear scorer
  on identical 26 features, which paper 3's conclusion about function class
  did not anticipate; and embeddings for trainer, jockey and sire lost to
  the strike rates they replaced, both intervals excluding zero, because a
  hand-built feature computed from a wider information set than the model
  can be fitted on is hard for an embedding to beat.
  Own pipeline and store (`_targets_p5.R` / `_targets_p5`), following
  paper 4's arrangement, so nothing it does can touch papers 1-4; its qmd
  setup chunk passes `store =` to each `tar_load()` rather than calling
  `tar_config_set()`, so the root `_targets.yaml` papers 1-3 share is never
  written. Fitting is `{torch}` directly, not `{tidymodels}`. Standing
  gates: `scripts/verify_p5_pl_torch.R` and `scripts/verify_p5_gru_mask.R`.
  Model selection ran on a validation slice carved out of the training
  split at 2010-12-15 (3,517 fitting / 1,505 validation races); the test
  split was scored once. Per-rung stage reports are in
  `papers/05_encoder/`, and the supplementary theory note is in
  `papers/05_encoder/supplement/`.
  Live: <https://gillenpj.github.io/awracing/paper5/>.
- **Paper 6 — Bet selection and staking. DRAFTED, NOT PUBLISHED.**
  Changes the betting rule and nothing else; the model is held fixed at
  paper 5's rung-3b encoder. Nine selection rules and three staking rules
  searched on the 5,022 training races, one rule per bet type declared by a
  mechanical rule and frozen in `papers/06_betting_strategy/DECLARED_RULES.md`
  before any test contact, test split scored once. **Nothing wins.** All three
  declared rules lose more than the incumbent and every paired interval
  against it contains zero. The result that matters is the control: on the
  win market S4/K0 — back the market favourite flat, no model input at all —
  returns −6.36% against the incumbent's −12.19%, its 90% interval excluding
  zero, so the model's contribution to bet selection is not visible on this
  data (consistent with paper 4). The place market is the one exception and
  goes the other way, which is a fact about a synthetic top-3 place market
  that prices favourites hardest, not about the model. Priced at a zero-margin
  book the incumbent returns +0.84% on win, so the whole of its loss is the
  over-round. Own pipeline and store (`_targets_p6.R` / `_targets_p6`).
  Standing gate: `scripts/verify_p6_ledger.R`. **`docs/` is untouched and the
  site index is not updated** — publishing is a separate, unstarted task.

## Standing conventions

- **Verification gates are the reason not to stop, not a reason to.**
  Where a gate exists (`scripts/verify_pl_objective.R`,
  `scripts/verify_going_features.R`, `scripts/verify_rebuild.R`,
  `scripts/verify_p4_market_probs.R`, `scripts/verify_p4_data_targets.R`,
  `scripts/verify_p5_pl_torch.R`, `scripts/verify_p5_gru_mask.R`,
  `scripts/verify_p6_ledger.R`), proceed and let it catch mistakes; fix
  and report, don't ask first (see "Default to proceeding" above).
- **Reproducibility checks need two fresh processes, not two calls in
  one session.** Process-constant state — a library's own un-seeded
  internal RNG, or anything else cached at the process level — can make
  a broken setting look verified when re-checked within the same R
  session. Always verify across two separate `Rscript` invocations.
- **Editing `R/p5_gru.R` costs about 3h20m of recompute, even for an
  unrelated constant.** `p5_gru_module` is built at **source time** by
  `torch::nn_module()`, and the R6 generator it returns captures the
  enclosing environment. Adding anything to that environment changes the
  generator's hash, so every target depending on it — `p5_rung3_runs`,
  `p5_rung3_refit_200`, `p5_rung3b_runs`, `p5_rung3b_refit_200`,
  `p5_gru_mask_check` — is invalidated and rungs 3 and 3b refit from
  scratch. Confirmed empirically at P5-3b: adding two term-list helpers
  to that file re-ran rung 3's whole grid (1h40m wasted), while
  `p5_rung2_runs` — the same pattern via `p5_embed_module`, in a file
  that was not touched — skipped, along with all of rungs 1 and 2. The
  recompute is deterministic, so it costs time and nothing else; rung 3
  reproduced to every printed digit. **Not being fixed**, because the fix
  — putting the generator behind a lazily-called function — is itself an
  edit to that file and would trigger the same recompute. Practical rule:
  put new paper-5 helpers in a NEW file, never in `R/p5_gru.R`, and
  before any long run check `tar_outdated()` to see whether the GRU
  targets have been invalidated. The same trap applies in principle to
  `p5_embed_module` in `R/p5_embed.R` (rung 2, about 49m).
- **Never give a driver script's own helper the same name as a base R
  function.** Files under `R/` are `source()`d into the caller's global
  environment, not loaded as a namespaced package, so a same-named
  helper (a script-local `log()` for timestamped progress messages,
  say) silently shadows the base function for everything sourced
  afterward, with no warning. Name such helpers `log_msg`, `note`, etc.
  — never a base R name.
- **A specific "report and stop" instruction overrides the standing
  proceed-by-default rule.** Where a prompt gates a stage on reporting
  back, computing the gated result, judging it yourself and launching
  the next stage in the same turn is a failure of that instruction —
  even when the judgement turns out to be correct. The point of the gate
  is the chance to intervene, and that is lost whether or not the call
  was right. Report, then wait.
- **Making all features NA-tolerant rather than complete-case is a
  database-refresh candidate, not a mid-series change.** It alters which
  races qualify, so papers 1-3 would no longer share a race universe
  with anything that followed, and every paired race-level bootstrap
  against them would be computed on a different set of races. Comment-
  and going-style features are exempt from the complete-case rule
  individually; changing the rule itself is a different act.
- **Every reported number is a live target, not a transcription.**
  Papers reference results via `tar_read()`/`tar_load()` inline in the
  `.qmd`, never as a hard-coded figure — a number with nothing behind it
  is a number that can silently go stale.
- **The test split stays untouched until the results pass.** Every
  modelling decision — features, objective, hyperparameters, the fitted
  model itself — is fixed before the test split is scored even once.
  Scoring it more than once (e.g. to compare a diagnostic model against
  the candidate) is selection on the test set.
- **Features are fixed before fitting**, not adjusted in response to a
  fit's performance — see "Data-scope decisions" below for the settled
  feature/scope choices.
- **`renv::record()`, not `renv::snapshot()`,** to pin a package version
  without forcing a full library re-scan.
- **PowerShell, not the Bash tool, for anything that touches
  `{xgboost}`, the Smartform `{RMariaDB}` connection, or
  `targets::tar_exist_objects()`.** All three crash under the Bash
  tool's Git Bash environment on this machine.
- **`git commit -m` with a PowerShell here-string (`@'...'@`) does not
  bind reliably when chained after another command with `;`** — git
  treats the message as pathspecs and the commit fails. Use
  `git commit -F` with a message file instead.

## Tech stack
- R 4.6 — use the full path
  `"C:/Program Files/R/R-4.6.0/bin/Rscript.exe"` on this machine.
  See the user-memory entry `rscript_path.md` for why the default
  `Rscript` on PATH (4.2.2) fails on this project.
- `{renv}` for packages (`use.cache = FALSE` in init).
- `{targets}` + `{tarchetypes}` pipeline; entry point `_targets.R`.
- `{DBI}` + `{RMariaDB}` for the Smartform MySQL database.
- `{tidyverse}`, `{tidymodels}`, `{mlogit}` for modelling.
- **`{torch}` 0.17.0 (libtorch 2.8.0) + `{luz}` 0.5.2 (and `coro` 1.1.0)
  for paper 5.** Pinned with `renv::record()`. The backend is the **CPU**
  libtorch build, and **`renv.lock` cannot capture that** — it pins R
  packages, not the C++ runtime. Reproducing this environment therefore
  needs `Sys.setenv(CUDA = "cpu")` before `torch::install_torch()`.
  **The CPU backend is a frozen parameter of paper 5. Decided
  2026-09-07; do not revisit mid-ladder.** Every rung is fitted on it,
  and results do not reproduce across backends, so switching would
  invalidate the frozen comparator and force refitting every closed
  rung. The pipeline records the backend at fit time in `p5_backend`
  and inside each fitted run, so no report can claim a backend it was
  not fitted on.
  - **Why CPU, correctly stated.** It is *not* the driver: driver
    560.94 supports a CUDA 12.6 runtime, as `nvidia-smi` reports. What
    failed at P5-1b was the installer's **toolkit** probe —
    `torch:::cuda_version_from_system_windows()` reads `CUDA_PATH`,
    then `version.txt`, then `nvcc`, and this machine's toolkit is
    v12.0. torch 0.17.0 ships **no CUDA build below 12.6** on Windows or
    Linux (`supported_cuda_versions_windows` is `12.6, 12.8, 12.9`), so
    `check_supported_version()` aborts. The probe is bypassable without
    installing a toolkit — `torch:::cuda_version()` honours
    `Sys.setenv(CUDA = "12.6")` first, and libtorch ships its own CUDA
    runtime — so a GPU build was available and was declined on the
    merits, not blocked.
  - **The merits.** The GPU is a GeForce GT 1030 (Pascal GP108, compute
    6.1, 2 GB, ~1.1 GB free with the desktop on it). Consumer Pascal
    runs FP64 at 1/32 rate — about 35 GFLOPS — against roughly 50-70
    GFLOPS achievable on this i5-3470. **The paper-5 fitting path is
    `float64` throughout**, so the GPU would likely be slower, and
    float32 is a larger change than the backend: it would break
    `verify_p5_pl_torch.R`'s 1e-4 gradient assertions and force a
    refit of every rung anyway.
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
- **Documented exception (paper 5, in force): `{torch}` used directly,
  not via `{tidymodels}`/`{parsnip}`.** `{tidymodels}` has no interface
  for a custom Plackett–Luce objective over variable-length, padded
  sequences — the same class of gap the `{mlogit}` and `{xgboost}`
  exceptions above cover. The project stays tidyverse-first throughout;
  this is a scorer-fitting exception, not a departure from it.
  `{luz}` is installed and pinned but the training loop is written
  against `{torch}` directly: the loss is race-grouped — a batch is a
  set of whole races, padded to that batch's widest field, reducing over
  races rather than rows — and an explicit loop is easier to audit than
  the same thing routed through luz's callback API.

## Project structure
- `R/` — functions, sourced by `_targets.R` via `tar_source()`.
- `sql/` — SQL queries, read by `R/db.R::read_sql_file()`.
- `papers/` — one Quarto sub-project per paper.
  - `papers/01_replication/` — **paper 1, complete and published.**
    Master document `index.qmd` includes `_01_data.qmd`,
    `_02_exploratory.qmd`, `_03_results.qmd`,
    `_04_future_predictive.qmd`, `_appx_derivation.qmd`,
    `_appx_software.qmd` via `{{< include >}}`. `_helpers.R` holds
    plotting helpers used in the section files. Bibliography in
    `references.bib`.
  - `papers/02a_extended_win_model/` — **paper 2a, complete and
    published.** Extended feature set, extended win model, mixed logit
    race-level interactions. Rendered by
    `tar_quarto(paper_2a_extended_win_model)`.
  - `papers/02b_ranking_model/` — **paper 2b, complete and published.**
    Exploded conditional logit as a ranking model. Rendered by
    `tar_quarto(paper_2b_ranking_model)`.
  - `papers/03_gradient_boosted_trees/` — **paper 3, complete and
    published.** Gradient boosted trees, same feature set and ranking
    objective as 2b. Rendered by
    `tar_quarto(paper_3_gradient_boosted_trees)`. Tuning-grid
    provenance in `TUNING_PROVENANCE.md`.
  - `papers/04_market_blend/` — **paper 4, complete and published.**
    Two-stage conditional-logit blend of a market price and a model
    probability. Built by its own pipeline, `_targets_p4.R`, into its own
    store, `_targets_p4` — NOT by `_targets.R`. Rendered by
    `tar_quarto(paper_4_market_blend)` inside that pipeline. Run it with
    `targets::tar_make(script = "_targets_p4.R", store = "_targets_p4")`.
    Its qmd setup chunk passes `store =` to each `tar_load()` rather than
    calling `tar_config_set()`, so it never writes the root
    `_targets.yaml` that papers 1–3 share. Pre-registration in
    `PRE_REGISTRATION.md`, stage report in `P4_REPORT.md`. The P4-0 audit
    working files — the evidence base for Appendix A — are in
    `papers/04_market_blend/audit/` with their own README; they are one-off
    analysis, not on the `{targets}` graph. The P4-0 gate itself stays at
    `scripts/p4_audit_forecast_price.R`, because
    `scripts/verify_p4_data_targets.R` and the paper-4 report target both
    read the `.rds` it writes.
  - `papers/05_encoder/` — **paper 5, complete and published.** Sequence
    encoding of run histories. Built by its own pipeline, `_targets_p5.R`,
    into its own store, `_targets_p5` — NOT by `_targets.R`. Run it with
    `Rscript scripts/run_p5_pipeline.R`, or
    `targets::tar_make(script = "_targets_p5.R", store = "_targets_p5")`.
    Rendered by `tar_quarto(paper_5_encoder)` inside that pipeline.
    Upstream targets are read from the main store **read-only**, with
    their content hashes recorded in `p5_upstream_fingerprint` so an
    upstream change invalidates downstream work rather than going stale.
    `tar_config_set()` is never called anywhere in paper 5 — the qmd setup
    chunk passes `store =` to each `tar_load()` — so the root
    `_targets.yaml` papers 1-3 share is never written. Alongside the paper
    the folder keeps the per-rung stage reports (`P5_1_REPORT.md` through
    `P5_3b_REPORT.md`, `P5_TEST_REPORT.md`, `P5_DIAGNOSTICS_REPORT.md`)
    and their `tar_make()` run logs.
  - `papers/05_encoder/supplement/` — paper 5's supplementary theory note,
    *Notes on Neural Scorers and Sequence Encoders*, a tutorial following
    the precedent of paper 3's tree notes. Its own tiny Quarto project,
    PDF only, and **not** on the `{targets}` graph: it has no executable
    chunks, so `quarto render notes_on_neural_scorers.qmd --to pdf` from
    that folder needs neither renv nor the targets store. `publish_docs.R`
    copies the result to `docs/paper5/notes-on-neural-scorers.pdf`.
  - `papers/06_betting_strategy/` — **paper 6, drafted, NOT published.** Bet
    selection and staking. Built by its own pipeline, `_targets_p6.R`, into
    its own store, `_targets_p6` — NOT by `_targets.R`. Run it with
    `Rscript scripts/run_p6_pipeline.R`, optionally naming a target to build
    up to. Rendered by `tar_quarto(paper_6_betting_strategy)` inside that
    pipeline. `tar_config_set()` is never called; the qmd setup chunk passes
    `store =` to each `tar_load()`. Upstream targets are read from the MAIN
    and PAPER-5 stores read-only, hashes in `p6_upstream_fingerprint`.
    Alongside the paper: the frozen `DECLARED_RULES.md` (committed before any
    test target existed — do not alter it), `P6_TEST_REPORT.md`, and the
    `tar_make()` run logs.
  - `papers/02_extended_features_ARCHIVE/` — the combined pre-split
    paper-2 draft, kept for reference only, not rendered.
  - Every paper follows the same shape: master `index.qmd` (YAML,
    abstract, intro, `{{< include >}}` directives) plus numbered
    section partials, a `_helpers.R`, and a `references.bib`.
- `docs/` — GitHub Pages publishing root. **Committed.**
  - `docs/index.html` — landing page, one entry per paper; each entry
    links the HTML and a "— PDF" link to `paperN/index.pdf`.
  - `docs/paper1/`, `docs/paper2a/`, `docs/paper2b/`, `docs/paper3/`,
    `docs/paper4/`, `docs/paper5/` —
    rendered `index.html` + `index.pdf`, copied from the matching
    `papers/*/_output/` after each render. `docs/paper3/` and
    `docs/paper5/` also carry a supplementary PDF each.
  - Pages source is set to `main` branch, `/docs` folder. There is
    **no GitHub Actions workflow** — Pages serves the committed
    `/docs` files directly and runs its own build on push, so
    publishing = copy `_output/` into `docs/`, commit, push. The
    `papers/*/_output/` working copies are gitignored. (A render-in-CI
    Action is not possible: the `{targets}` pipeline needs the local
    Smartform MySQL DB, which CI cannot reach.)
  - Republishing convention: (1) re-render via `tar_make()` (produces
    **both `index.html` and `index.pdf`** per paper — see "Paper /
    Quarto convention"); (2) run `Rscript scripts/publish_docs.R` to
    copy each paper's `_output/` HTML+PDF into the matching
    `docs/paperN/`; (3) `git add docs/`, commit, push. The landing page
    `docs/index.html` is hand-edited (one entry per paper); the script
    does not touch it.
  - Each `index.qmd` carries a **pinned** `date:` (e.g. paper 1
    `"2026-06-06"`, paper 3 `"2026-08-23"`), not `date: today`, so a
    paper's published date is stable across re-renders. Set the date
    once when the paper is first published.
- `notes/` — kept as a reference shelf only; not consumed by the
  pipeline. Includes the Owen (2019) paper paper 1 replicates and
  `Notes_on_Tree-based_Methods.pdf` (paper 3's theory source — regression
  trees through gradient boosting and its application to horse racing),
  published as supplementary material at
  `docs/paper3/notes-on-tree-based-methods.pdf` (`publish_docs.R` copies
  it on every publish run and fails loudly, rather than skipping it, if
  the source is absent — it is gitignored, so a fresh clone won't have
  it). **Provenance, load-bearing:** the file in `notes/` today is
  already a cleaned export — the original Word document carried an
  author email address (tied to a former employer) in its custom
  document properties and a corporate sensitivity-label footer
  ("Information Classification: General") baked into every page. Do
  **not** restore or re-export from any pre-cleaning copy of that Word
  document. Any future revision starts from the cleaned file; before
  publishing a re-export, check both the text layer (`pdftotext`) and
  the metadata (Info dict *and* the full XMP packet — the footer and an
  email are exactly the kind of thing that hides in one but not the
  other) for anything identifying.
- `scripts/`
  - `verify_rebuild.R` — standing read-only integrity check on
    `qualifying_races` / `qualifying_runners` / `candidate_races`. Run
    after any change to SQL or the R-level filters in
    `R/extract_*.R`. Eight `stopifnot()` assertions; see file header.
  - `verify_pl_objective.R` — standing gate on the paper-3 custom
    Plackett–Luce objective (gradient/Hessian correctness, including a
    deliberate `log()`-shadowing regression check — see "Standing
    conventions" above). Run after any change to `R/pl_objective.R`.
  - `verify_going_features.R` — standing gate on the going-affinity
    feature builder. Run after any change to `R/build_going_features.R`.
  - `verify_p4_market_probs.R` — standing gate on paper 4's
    market-probability helper: asserts `normalise_overround()` reproduces
    the stored `win_market` of `test_predictions_3` exactly, so paper 4
    uses the series' existing overround adjustment rather than a second
    implementation of it. Run after any change to it or to
    `R/scoring.R::build_test_predictions()`.
  - `verify_p4_data_targets.R` — standing gate tying paper 4's
    data-section targets to the frozen P4-0 audit, and asserting the
    distributional summaries touch no test race. Run after any change to
    `R/p4_data_summaries.R`.
  - `verify_p5_pl_torch.R` — standing gate on paper 5's `{torch}`
    Plackett–Luce objective (`R/p5_torch.R`): asserts it agrees with
    `R/pl_objective.R::pl_neg_loglik()` on identical input (~1e-9
    relative) across mixed field sizes, the edge cases, depths k = 1 to
    4, shift invariance and padding width, and that its autograd
    gradient matches paper 3's analytic `pl_grad_hess()` (~2.9e-08). Run
    after any change to `R/p5_torch.R`. It caught a real bug and a
    loss-value-only check would not have: `torch_where()` selects one
    branch but differentiates both, so padded slots carrying `log(0)`
    gave an exactly correct forward loss and a NaN gradient.
  - `verify_p5_gru_mask.R` — standing gate on paper 5's sequence encoder
    (`R/p5_gru.R`): asserts the GRU never reads padding and reads the
    correct slot. Sequences are right-padded and the encoder output is the
    hidden state at `seq_len`. Three seeds, four checks — padding width
    inert, padding content inert, a zero-length row giving the zero
    vector, and the output matching the same encoder run on the unpadded
    sequence. That last one is the check that earns its place: an
    off-by-one in the gather index passes both invariance checks while
    summarising the wrong run. Also on the graph as `p5_gru_mask_check`.
    Run after any change to `R/p5_gru.R` — but see the recompute trap in
    "Standing conventions" first.
  - `verify_p6_ledger.R` — standing gate on paper 6's betting ledger
    (`R/p6_ledger.R`, `R/p6_rules.R`). Six assertions: three that the ledger
    rebuilds paper 5's published test backtest exactly under S1/K0 (against
    the stored targets AND against the printed figures), one that
    `p6_eachway_returns()` reproduces `build_eachway_value_bets()` when given
    paper 5's terms, one that the corrected each-way terms move exactly the
    rows the field-size ladder marks, one that a staking rule changes stakes
    and not the bet set. Read-only; also on the graph as `p6_ledger_gate`.
  - `run_p6_pipeline.R` — the paper-6 driver, same reasons as paper 5's. An
    optional argument names a target to build up to; that is how the
    declaration was frozen before the test targets were written.
  - `run_p5_pipeline.R` — the paper-5 driver. Exists because `Rscript -e`
    does not activate renv on this machine and because the script/store
    pair must be passed explicitly on every call.
  - `publish_docs.R` — the publish step. After `tar_make()`, copies
    each paper's `_output/index.{html,pdf}` into `docs/paperN/`
    (mapping table at the top of the file; add a row per new paper).
    Self-contained base R — run as `Rscript scripts/publish_docs.R`, no
    renv needed. Does not touch the hand-edited landing page.
  - `run_gbt_tuning.R` — the standalone driver that produces
    `gbt_tuning_final.rds` (paper 3's frozen tuning-grid result, ~11h
    wall-clock — not a `{targets}` target; see
    `papers/03_gradient_boosted_trees/TUNING_PROVENANCE.md` for exactly
    how to reproduce and check it).
- `_targets/` — pipeline cache (gitignored).
- `_targets_p5/` — paper 5's own pipeline store (gitignored, alongside
  paper 4's `_targets_p4/` and paper 6's `_targets_p6/`).
- `renv/`, `renv.lock` — package state.
- `.env` — DB credentials (gitignored). Read at runtime by
  `R/db.R::connect_smartform()` via `dotenv::load_dot_env()`.
- `_targets.yaml` — written by `tar_config_set()` in the qmd setup
  chunks; absolute path to the store; gitignored.
- **`_targets/meta/process`** — the `{targets}` pipeline lock, recording
  the PID of whichever R session last ran `tar_make()`. If that session
  didn't exit cleanly, the lock can outlive it: the next `tar_make()`
  then refuses to run, citing a PID that may by now belong to something
  else entirely on this machine. Fix: confirm no live R process
  actually owns that PID (`Get-Process -Id <pid>` — if it's not
  `R`/`Rscript`, or nothing's there, the lock is stale), then delete
  `_targets/meta/process` directly. Harmless to remove once confirmed
  stale — it's regenerated on the next `tar_make()`. This lock is
  unrelated to, and not touched by, any script that only calls
  `targets::tar_read()` (read-only) — none of the `scripts/*.R` drivers
  acquire it.
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

## Writing style

Observed whenever any paper in this series is drafted or revised.

Terse. Lead with the result. Plain English over jargon. No filler, no
rhetorical questions, no sentences set up to knock down an objection
nobody raised. Neutral framing of results. Limitations stated honestly
without pessimism. Cut rather than patch when material is not working.

No mannered prose. Do not substitute metaphor or flourish for direct
statement. Write "a parameter worth varying", not "a dial worth tuning".
Write "this matters", not "this earns its keep". Phrases that display
the writer rather than convey the idea are to be cut. If a sentence has
a figurative construction where a plain one would do, use the plain one.

Give material space in proportion to what it found, not in proportion to
the effort it took.

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
pattern is used to `source()` each paper's `_helpers.R` robustly
across the cwd that `tar_quarto` sets (project root) vs direct
`quarto render` (paper folder).

With those two fixes in place, the single command `tar_make()` from
the project root is the only render path needed.

### Paper 2 re-render nuisance
tar_make() re-renders paper 1 when paper 2 targets run, despite no
paper-1 source changes. Traced to both papers' qmd setup chunks
writing the same root _targets.yaml. Harmless — paper 1 re-renders
identically. Not yet fixed; low priority.

## `{targets}` conventions
- One function per `tar_target()`. Pure functions: inputs →
  outputs, no side effects (no writing to disk, no global state).
  Documented exception: a target whose product needs its own
  serialisation (an `xgb.Booster`, saved via `xgboost::xgb.save()`)
  uses `format = "file"` and returns the file path — the standard
  `{targets}` idiom for a bespoke-serialised object, the same
  accepted side effect `tar_quarto()` targets already have.
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
Set in `sql/qualifying_races.sql`. (A related, smaller
cross-vocabulary issue — `going` values inconsistent with
`race_type` at the two dual-surface AW courses, Lingfield and
Kempton — affects ~0.22% of career-history rows and is quantified
but not fixed; see `R/build_going_features.R`.)

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
crosses the boundary. Used unchanged by every paper in the series.

### Feature-engineering settled decisions
Dropped (near-zero or redundant signal): `weight_delta_lbs`,
`class_delta`, `sire_aw_premium`, `jockey_aw_premium`,
`first_time_aw`. Kept: `or_relative` (strongest new predictor;
NULL-official-rating imputed to 0 with an `or_missing` companion
flag, since unrated horses are a distinct population, not an
average one), `jockeySR` (uncapped, consistent with
`trainerSR`/`sireSR`), `rel_weight`, `trainer_aw_premium`,
`has_wins`, `cheekpieces`, `gelding`. Position lags use a
zero-plus-slope encoding (a "no prior run" indicator plus the raw
position, two terms per lag) rather than paper 1's twelve-level
factor encoding — not statistically distinguishable from the
richer encoding, and more parsimonious. Going affinity (going ×
horse-level going strike rate) was deferred from papers 1/2 to
paper 3, since a conditional logit can't use a race-level feature
without an explicit interaction term and a tree needs no such
interaction; see paper 3's own data section for how it was built
and what was found. Built in `R/build_extended_features.R` and
`R/build_going_features.R`.

### Market data — scoped, not excluded
Post-race columns remain excluded everywhere, without exception.

Settled, and paper 4 depends on it. Market columns
(`forecast_price_decimal`, starting price) are excluded from the
**model feature set** in every paper of the series, so the papers stay
internally comparable. Paper 4 uses them as a second-stage input to the
*evaluation* — the blend's market term — and not as model features;
releasing that constraint is the point of the paper, and the model it
blends is still market-blind.

Neither column is leakage. Both are pre-race.
`forecast_price_decimal` is published the evening before and is
the price available at bet time in live deployment. Starting
price is already used throughout the series to build the
discounted-Harville market baseline and to price the backtests.

### Which forecast-price column to use
Smartform holds a forecast price in two places and they are **not**
interchangeable: they disagree on about a third of in-scope runner rows.
`daily_runners` carries the forthcoming day's racecards and is written
the night before racing; `historic_runners` is the results archive,
written the following day. Where a verifiably pre-race price is needed,
take it from `daily_runners` and require the row to have been written
before the meeting date — expect it to be absent before March 2008 and
patchy for a year after. `historic_runners.forecast_price_decimal` is
written after the race and does not reproduce the pre-race value; the
documentation gives no reason for the difference. Evidence and the two
competing explanations are in paper 4's Appendix A
(`papers/04_market_blend/_appx_provenance.qmd`) — do not restate them,
point at it.

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
the null log-likelihood in `extract_model_diagnostics()` use
`probs_mat > 0` to discriminate real alternatives from padded ones.

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
- Paper 3's Plackett–Luce objective (`R/pl_objective.R`) is the k=3
  case of the same likelihood paper 2b's exploded conditional logit
  fits, with the score coming from a tree ensemble instead of a
  linear predictor. See paper 3's own Method section and Appendix A
  for the derivation.

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

## Paper 5 — sequence encoding of run histories (COMPLETE)

Published. See the Papers list above for the result and the pipeline
details, and `papers/05_encoder/` for the per-rung stage reports. What
follows is what the work left behind for later — the lessons and the
built inputs — not a restatement of the results.

**Rung 1 (the MLP control) is closed, at 3bf41be.** It took four
attempts, and three of them were wasted on the same mistake: an arm that
differed from its comparator in two respects at once, so the contrast
could not test what the rung existed to test. P5-1 pitted paper 3's 24
tree-shaped features against paper 2b's 17; P5-1b fixed the encoding but
gave the MLP eight features 2b did not have; P5-1c matched the features
and left the selection budget asymmetric (9 x 60 evaluations against
1 x 200); P5-1d equalised the budget and settled it. **Standing lesson,
and it applies to every rung that follows: state the term-by-term
difference between the two arms before fitting anything, and confirm it
is exactly one difference.**

The result: on identical 26 terms and an equal budget the MLP beats a
linear scorer on both P1_rank and Brier_place, both 90% intervals
excluding zero. The control claim does not hold — the nonlinearity is
worth about 0.0127 per race on validation PL loss, roughly 4.2 times the
0.0030 the nine features paper 2b lacks are worth — so **later rungs are
judged against the rung-1 MLP, not against paper 2b or paper 3.**

Sequence channels are built and bounded (`R/p5_sequences.R`): eight
channels over the 20 most recent strictly-prior runs, cross-surface,
row-identical to paper 3's frame. Unavailable readings take **−1**, not
0, because 0 is legitimate for several channels and is also the padding
value; padding stays 0 and is masked by `seq_len`. `class` and
`finish_pos` sentinels read as unavailable; `field_size` (40),
`days_since_prev` (1000) and `beaten_dist` (100) are winsorised, which
keeps the ordering where the magnitude stops being informative.

**What rung 3 consumes them with, and the one thing it does not get
back.** Sequences are right-padded — real runs in the leading slots,
padding after — and the encoder output is the GRU hidden state at slot
`seq_len`, so the recurrence never consumes padding. Left-padding would
not do: a GRU fed zero vectors from a zero state does not stay at zero,
because the gates carry biases. Runs are reversed into chronological
order first, so the last thing the encoder reads is the most recent run.
Gate: `scripts/verify_p5_gru_mask.R`, also on the graph as
`p5_gru_mask_check`. Its third check — output must match feeding a row's
real runs with no padding at all — is the one that matters: an
off-by-one in the gather index passes both padding-invariance checks
while summarising the wrong run. **`days_LTO_log` leaves in rung 3 and
the sequences do not restore it**: `days_since_prev` is the gap between
a historical run and the one before it, not the gap to today's race. The
encoder wins having lost that, which is the obvious first thing to try
if it is developed further.

**The CPU backend is frozen and recorded.** `p5_capture_backend()` runs
both as the `p5_backend` target and inside every fitting function, and
`p5_backend_check` asserts all fitted runs agree with it, so no report
can claim a backend it was not fitted on. See the `{torch}` entry under
"Tech stack" for why CPU, and do not revisit it mid-ladder.

**Abandoned unpublished: comment tags.** Features parsed from
`in_race_comment` on a horse's prior runs were tried against paper 3's
GBT and abandoned without publication. The block improved ranking
slightly on both the validation slice and the test split, with a
shuffled control at zero; it gave no ROI improvement; and attribution
within the block failed to replicate twice — a career-length
decomposition and a tag-family group-drop each produced a clear story on
validation and neither held on test. **Not a baseline and not citable.**
Recorded so the idea is not picked up again as new.

## Longer-term direction (post-paper-4, speculative)
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
  "well-calibrated" means across the series — the relevant
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
- Chen, T. & Guestrin, C. (2016), *XGBoost: A Scalable Tree Boosting
  System*, KDD '16 — paper 3's model, and its Appendix A's
  closed-form leaf-value derivation.
- r4ds.hadley.nz — tidyverse style guide.
- tmwr.org — tidymodels patterns.
- books.ropensci.org/targets — pipeline patterns.

## Out of scope
- Pre-2003 data (Smartform's earliest record).
- Other surfaces (turf, jumps) beyond using their data for
  cross-surface feature history.
- Live betting infrastructure remains out of scope, and even then
  begins as paper trading.
