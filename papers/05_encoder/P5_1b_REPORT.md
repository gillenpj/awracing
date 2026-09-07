# P5-1b — rung 1 respecified

Run 2026-09-04 on branch `paper5-encoder`. The rung-1 control respecified
for a model that is not a tree, the four flagged sequence channels cleaned,
and the torch stack pinned.

**The test split is not scored anywhere in this task. Rung 2 is not
started.**

---

## 1. Rung 1 — the comparison, and which reading obtained

1,505 validation races. Paired race-level bootstrap, B = 2000, seed 42, 90%
intervals.

| metric | MLP | paper 2b (refit) | difference | 90% interval | favours |
|---|---|---|---|---|---|
| P1_rank (higher better) | 0.00302479 | 0.00298455 | +4.024e-05 | [+1.026e-05, +6.832e-05] | **MLP** |
| Brier_place (lower better) | 0.19707135 | 0.19762087 | −5.495e-04 | [−1.026e-03, −5.470e-05] | **MLP** |

Both intervals exclude zero, both favouring the MLP. Of the three readings
fixed before the fit:

> **Either favours the MLP → proceed, and record that the control claim is
> weakened.**

That is the reading that obtained. **Recorded: the control claim is
weakened.**

The respecification worked in the narrow sense — the encoding deficit is
gone. Every one of the nine configurations now beats mlogit's 5.814307,
where before none of fifteen did.

## 2. Why "the control claim is weakened" needs stating carefully

The rung exists to establish that an MLP under this objective **ties** a
linear scorer, so that any later gain from the encoder is attributable to
the sequence representation rather than to nonlinearity. The MLP did not
tie. It won, on both metrics.

**But this comparison is still feature-confounded, now in the opposite
direction from before.** The MLP has 25 terms; paper 2b has 17. The eight
extra are exactly the going-affinity block and the course indicators, which
2b does not carry:

| | terms |
|---|---|
| MLP control | 25 |
| paper 2b (refit) | 17 |
| in the MLP, not in 2b | `going_runs_prior`, `going_sr_shrunk`, `going_sr_delta`, `going_ordinal`, `course_Kempton`, `course_Lingfield`, `course_Southwell`, `course_Wolverhampton` |

So "MLP favoured" has two candidate explanations and this run cannot
separate them: the nonlinearity is buying something, or the eight extra
features are. Before P5-1b the confound ran against the MLP (it lacked the
`pos_lag*_zero` indicators); now it runs in its favour.

**The fit that would settle it is a linear scorer on these same 25 terms.**
If linear-on-25 matches the MLP, the gain is the features and the control
claim survives. If the MLP still wins, the gain is the function class and
the claim is genuinely weakened. I have not run it — the instruction was to
report and stop — and it is one fit whenever you want it.

Recorded either way, per the reading: **do not treat a later encoder gain as
evidence about sequence representation until this is resolved**, because on
current evidence the MLP's nonlinearity may already be contributing.

## 3. The nine declared configurations

Declared before any was scored. The same grid as the first attempt; only the
feature set changed. Dropout 0.1, 64 races per batch, 60 epochs with the
best chosen on validation PL loss, weight decay 1e-5, seed 42 held fixed
across all nine. Selection on validation PL loss and nothing else.

| config | widths | lr | best val PL loss | best epoch | loss at epoch 60 |
|---|---|---|---|---|---|
| 6 | 256-128 | 3e-04 | **5.800915** | 3 | 5.927915 |
| 3 | 128-64 | 3e-04 | 5.803649 | 9 | 5.863212 |
| 2 | 128-64 | 1e-03 | 5.803680 | 3 | 5.963032 |
| 5 | 256-128 | 1e-03 | 5.804276 | 3 | 6.242003 |
| 7 | 64-32 | 3e-03 | 5.804841 | 3 | 5.951903 |
| 9 | 64-32 | 3e-04 | 5.805346 | 17 | 5.843245 |
| 8 | 64-32 | 1e-03 | 5.805440 | 6 | 5.869009 |
| 1 | 128-64 | 3e-03 | 5.811672 | 1 | 6.149137 |
| 4 | 256-128 | 3e-03 | 5.813366 | 1 | 6.555934 |

**paper 2b, refitted on the same fitting partition: 5.814307.** All nine
beat it. Selected: config 6, 256-128 at lr 3e-04, epoch 3.

The remediation allowance was reset and **was not used** — it was not
needed.

The best epochs remain very early (1 to 17 of 60), so these models still
overfit quickly. That is not a fault under the rung's rules, since epoch
selection is on validation loss, but it is worth knowing before rung 2:
these configurations are being chosen at the point where a short run
happens to peak.

## 4. The control's exact 25 terms

Stated before the fit, and asserted in the pipeline (`length(...) == 25L`).

**Paper 2b's 17:** `pos_lag1_zero`, `pos_lag1_nonzero`, `pos_lag2_zero`,
`pos_lag2_nonzero`, `age_diff`, `days_LTO_log`, `trainerSR`, `sireSR`,
`jockeySR`, `entire`, `gelding`, `cheekpieces`, `rel_weight`,
`or_relative`, `or_missing`, `trainer_aw_premium`, `has_wins`.

**Paper 3's going-affinity block:** `going_runs_prior`, `going_sr_shrunk`,
`going_sr_delta`, `going_ordinal`.

**The four course indicators:** `course_Kempton`, `course_Lingfield`,
`course_Southwell`, `course_Wolverhampton`.

**One discrepancy against the stated intent.** `stall_normalised` is in
paper 3's 24 and is not on this list, because it was not in the
specification given. Paper 3 carries draw position through it; the four
course dummies alone carry none. So "same information as paper 3's 24" is
not quite met — this control is short of paper 3 by exactly the draw. I
implemented the list as given rather than adding a feature to a stated
control specification. It is a one-line change if you want it.

Only three of the 25 have any NA — `going_runs_prior` 0.198%,
`going_sr_shrunk` and `going_sr_delta` 0.903% — imputed to the
fitting-partition mean after standardising, since an MLP has no native
missing routing. Unchanged from before and too small to explain anything.

## 5. Sequence channel cleaning

**A correction to what I told you last time.** I said out-of-range `class`
values were "not confined to pre-2006". That was wrong, and it was driven by
NA rather than by the multi-digit codes. Separating the two:

| | rows | share |
|---|---|---|
| `class` NA | 17,674 | 3.975% |
| `class` outside 1-7 | 6,022 | 1.355% |

**Every one of the 6,022 out-of-range values is pre-2006** — 3,552 All
Weather Flat, 2,408 Flat, 62 National Hunt Flat, none after 2005-12-31.
CLAUDE.md's account of the class restructuring is exactly right and my
earlier reading was not.

| channel | what was found | how it is handled |
|---|---|---|
| `class` | 6,022 pre-2006 multi-digit codes (85, 74, 64, 63, 54, 53, 52, 44, 43, 42, 41, 32); 17,674 NA | read as **unavailable**, not clipped — a code of 42 is not "class 42" |
| `finish_pos` | 99 appears 12 times, 98 nine times, 80 three times; 59 rows above 30, 24 above 40 | above 40 read as **unavailable**; these are sentinels, not placings |
| `field_size` | 154 rows above 40 (118, 114, 93, 88, 85, 78, 77, 73…) | **winsorised to 40**, the largest legitimate British field; the ordering still means "very large field" |
| `days_since_prev` | 99.9th percentile 707 days, maximum 37,918 (about 104 years); 104 rows above 1,000; 16,116 NA (3.6%, a horse's first run) | **winsorised at 1,000**; NA read as unavailable |

Unavailable readings take **−1**, not 0, because 0 is legitimate for several
of these channels — a same-day re-run, a winner's beaten distance — and is
also the padding value. Padding stays 0 and is masked by `seq_len`, so the
two never collide.

Channels after cleaning, over the 634,803 real slots on the training split:

| channel | min | median | mean | max | % zero |
|---|---|---|---|---|---|
| `finish_pos` | −1 | 5.00 | 5.391 | **35** | 0.00 |
| `beaten_dist` | −1 | 4.25 | 7.838 | 430 | 13.59 |
| `beaten_missing` | 0 | 0.00 | 0.000 | 1 | **99.96** |
| `going_ordinal` | 0 | 4.00 | 3.982 | 7 | 0.46 |
| `class` | −1 | 5.00 | 4.216 | **7** | 0.00 |
| `field_size` | 1 | 11.00 | 11.495 | **40** | 0.00 |
| `distance_furlongs` | 5 | 7.00 | 8.103 | 32 | 0.00 |
| `days_since_prev` | −1 | 17.00 | 34.574 | **1000** | 0.00 |

**`beaten_missing` is kept as instructed and is nearly constant** — 99.96%
zero. It will carry almost nothing for the encoder, and is retained only
because a genuinely missing beaten distance is otherwise indistinguishable
from the −1 fill.

**One anomaly remains and I have not touched it**, because it was not among
the four flagged: `beaten_dist` still reaches 430 lengths. That is not a
plausible winning distance in a British race. It affects a small number of
rows and should be decided before rung 3.

## 6. Recorded for part B

`pos_lag1_zero` and `pos_lag2_zero` are history summaries in exactly the way
`pos_lag1_nonzero` and `pos_lag2_nonzero` are — they summarise whether a
prior run exists. They therefore **leave in part B** with the rest of the
hand-summarised history, and the encoder receives the raw sequence and its
length instead. A sequence of length zero carries the same fact the
indicator did.

Written into `P5_HISTORY_TERMS` in `R/p5_mlp.R` so the decision is not
relitigated when part B is built.

## 7. Environment pinned

`renv::record()` run on the torch stack. `renv.lock` gains three records and
no existing record is touched:

| package | version |
|---|---|
| `torch` | 0.17.0 |
| `luz` | 0.5.2 |
| `coro` | 1.1.0 |

The libtorch backend itself is the **CPU** build, installed by forcing
`CUDA=cpu` — this machine has CUDA 12.0 and torch 0.17.0 supports only
12.6, 12.8 and 12.9. That is not captured by `renv.lock`, which pins R
packages rather than the C++ runtime, so it is recorded here: reproducing
this environment needs `Sys.setenv(CUDA = "cpu")` before
`torch::install_torch()`.

## 8. Rollback verification

`git diff main --stat`:

```
 .gitignore |  4 ++++
 renv.lock  | 18 ++++++++++++++++++
 2 files changed, 22 insertions(+)
```

Both are additions only: `_targets_p5/` added to `.gitignore` alongside
paper 4's equivalent entry, and the three torch records added to
`renv.lock`. Nothing else on this branch is committed; everything else is
untracked working-tree state —

```
R/p5_sequences.R   R/p5_torch.R   R/p5_mlp.R   R/p5_baseline_2b.R
_targets_p5.R      scripts/run_p5_pipeline.R
scripts/verify_p5_pl_torch.R      papers/05_encoder/
```

No file used by papers 1-4 was modified. `docs/`, the landing page and
CLAUDE.md are untouched.

**Main store untouched:**

```
targets::tar_outdated(store = "_targets", script = "_targets.R")
→ character(0)
```

## 9. Where this stops

Reported, and stopping. Rung 2 is not started.

Two things are outstanding and both are yours:

1. **Whether to add `stall_normalised`** to the control, so it genuinely
   carries the same information as paper 3's 24 (§4).
2. **Whether to run the linear-on-25-terms fit** that separates "the
   nonlinearity is buying something" from "the eight extra features are"
   (§2). Until that is settled, a gain at rung 3 cannot be attributed to
   sequence representation, because the MLP's nonlinearity is already
   ahead of the linear baseline on this slice.
