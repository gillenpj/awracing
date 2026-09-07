# P5-1 — sequence pipeline and rung 1

Run 2026-09-04 on branch `paper5-encoder`. The pipeline, the prior-run
sequences, the torch Plackett-Luce objective and its gate, and rung 1: the
MLP control.

**The test split is not scored anywhere in this task.** The encoder and the
entity embeddings are not built; those are rungs 2 and 3.

---

## 1. Rung 1 — the comparison, and which reading obtained

1,505 validation races (2010-12-16 to 2012-12-30). Paired race-level
bootstrap, B = 2000, seed 42, 90% intervals.

| metric | MLP | paper 2b (refit) | difference | 90% interval | favours |
|---|---|---|---|---|---|
| P1_rank (higher better) | 0.00292297 | 0.00298455 | −6.157e-05 | [−1.211e-04, −5.675e-06] | **paper 2b** |
| Brier_place (lower better) | 0.19884162 | 0.19762087 | +1.221e-03 | [+2.420e-04, +2.228e-03] | **paper 2b** |

Both intervals exclude zero, both against the MLP. Of the three readings
fixed before the fit:

> **Either favours paper 2b → implementation fault. One remediation pass
> over learning rate, epochs, batching and layer widths — never the loss,
> features, split, metric or seed — then stop and report either way.**

That is the reading that obtained. The remediation pass was run. **It did not
fix the gap, and this report is the stop.**

## 2. The nine declared configurations

Declared in full before any was scored. A 3×3 grid over layer widths and
learning rate; dropout 0.1, 64 races per batch, 60 epochs, weight decay
1e-5, seed 42 held fixed across all nine. Selection on validation
Plackett-Luce loss and nothing else.

| config | widths | learning rate |
|---|---|---|
| 1 | 128-64 | 3e-03 |
| 2 | 128-64 | 1e-03 |
| 3 | 128-64 | 3e-04 |
| 4 | 256-128 | 3e-03 |
| 5 | 256-128 | 1e-03 |
| 6 | 256-128 | 3e-04 |
| 7 | 64-32 | 3e-03 |
| 8 | 64-32 | 1e-03 |
| 9 | 64-32 | 3e-04 |

Their scores, per-race validation PL loss:

| config | widths | lr | best val PL loss | best epoch | loss at epoch 60 |
|---|---|---|---|---|---|
| 4 | 256-128 | 3e-03 | **5.835154** | 6 | 6.722565 |
| 1 | 128-64 | 3e-03 | 5.837268 | 6 | 6.124677 |
| 7 | 64-32 | 3e-03 | 5.839138 | 6 | 5.974801 |
| 6 | 256-128 | 3e-04 | 5.842799 | 9 | 5.929561 |
| 5 | 256-128 | 1e-03 | 5.844095 | 3 | 6.266279 |
| 8 | 64-32 | 1e-03 | 5.845048 | 8 | 5.911019 |
| 9 | 64-32 | 3e-04 | 5.849470 | 21 | 5.876237 |
| 2 | 128-64 | 1e-03 | 5.850287 | 3 | 5.992243 |
| 3 | 128-64 | 3e-04 | 5.850716 | 13 | 5.886665 |

**Paper 2b, refitted on the same fitting partition: 5.814307.** Every one of
the nine is worse, and all nine peak within about six epochs and then
degrade — the signature of overfitting, not of a model still learning.

## 3. The remediation pass

One pass, varying only learning rate, epochs, batching and layer widths.
The loss, features, split, metric and seed are untouched.

*Interpretive note.* "Within the declared grid" is read as "over those four
knobs only". Confining the pass to the original nine points would make it a
no-op, since those nine are exactly what failed.

Two configurations have **no hidden layer**. That is layer width taken to
its degenerate case, and it is the diagnostic that matters: a linear scorer
trained through this loss and this loop is the same function class as the
conditional logit it is being compared against.

| config | widths | lr | batch | best val PL loss | best epoch | loss at epoch 200 |
|---|---|---|---|---|---|---|
| 4 | 64-32 | 1e-04 | 64 | **5.849523** | 73 | 5.879122 |
| 6 | 128-64 | 1e-04 | 128 | 5.852295 | 39 | 5.883985 |
| 5 | 64-32 | 3e-05 | 128 | 5.853295 | 197 | 5.853476 |
| 3 | 32-16 | 3e-04 | 64 | 5.856516 | 61 | 5.879505 |
| 1 | **linear** | 1e-03 | 64 | 5.863199 | 13 | 5.865969 |
| 2 | **linear** | 3e-04 | 64 | 5.863256 | 39 | 5.865808 |

The remediation made things **worse**, not better: its best (5.849523) is
below the declared nine's best (5.835154). The selected model is therefore
still config 4 of the declared nine, and the comparison in §1 is unchanged.

## 4. What the linear anchor shows

| | validation PL loss |
|---|---|
| paper 2b (refit, mlogit) | **5.814307** |
| best of the declared nine | 5.835154 |
| best of the remediation | 5.849523 |
| linear scorer in torch | 5.863199 |

**The fault is not MLP capacity.** A linear scorer is the same function class
as the conditional logit, and it loses to it by 0.049 per race — a wider gap
than any MLP's.

**Nor is it optimisation.** The linear configuration's epoch trace converges
smoothly and then sits flat:

```
6.0402 5.9666 5.9222 5.8976 5.8827 5.8740 5.8692 5.8669 5.8643 5.8634
5.8635 5.8632 5.8632 5.8638 5.8633 5.8644 5.8641 5.8648 5.8652 5.8647
```

That is a converged optimum, not a run stopped early or diverging.

**The torch objective itself is verified** (§6): it agrees with
`pl_neg_loglik()` to about 1e-9 relative, and its autograd gradient matches
paper 3's analytic `pl_grad_hess()` to 3e-8.

## 5. The likely cause, which I have not fixed

**The two arms do not use the same features, and one of the differences is
exactly the kind an MLP cannot absorb.**

| | |
|---|---|
| MLP arm | paper 3's 24 `FEATURE_COLS` |
| paper 2b arm | `model_p2_reduced`'s 17 terms |
| in 2b but not paper 3 | `pos_lag1_zero`, `pos_lag2_zero` |
| in paper 3 but not 2b | `stall_normalised`, four course indicators, `going_runs_prior`, `going_sr_shrunk`, `going_sr_delta`, `going_ordinal` |

The two missing columns are the point. Paper 2b encodes each prior finish as
a **pair**: a zero/nonzero indicator plus the position. CLAUDE.md records why
the pair exists — "the zero/nonzero split exists only so a LINEAR predictor
can avoid conflating 'no prior run' (coded 0) with a real graded finish
position on the same numeric scale". Paper 3 dropped the indicators because
"a tree splits on `pos_lagN_nonzero == 0` directly, no separate indicator
required".

**An MLP is not a tree.** Feeding it `pos_lag1_nonzero` alone reintroduces
precisely the conflation the pair was designed to remove: zero means "no
prior run" on the same axis as a real finishing position. Paper 3's 24
features are a tree-shaped encoding, and handing them unchanged to a
gradient-descent scorer is not the neutral act the rung assumed.

The same class of problem affects the going columns, which are NA for 0.2%
to 0.9% of rows: XGBoost routes missing values natively, an MLP cannot, so
those NAs are imputed to the fitting-partition mean. That is a smaller
effect — the NA share is tiny — but it is the same failure mode.

**I have not tested this explanation**, because doing so means changing the
arm's feature set, which the remediation rule forbids. The decisive test is
one fit: the linear torch scorer on paper 2b's own 17 terms. If it reaches
5.814, the torch path is sound and the rung's feature specification is the
fault. If it does not, the fault is somewhere I have not looked.

**What this means for the rung's conclusion.** The reading that obtained is
"implementation fault", and there is an implementation fault — but on the
evidence it is in how rung 1 was specified, not in the torch machinery. The
comparison as written pits 24 tree-shaped features against 17
linear-shaped ones and calls the difference a function-class result. That is
confounded, and it would have been confounded whatever the numbers came out
as.

## 6. The torch Plackett-Luce objective and its gate

`scripts/verify_p5_pl_torch.R`, a standing gate. **Passes.** It asserts the
torch loss agrees with `R/pl_objective.R::pl_neg_loglik()` on identical
input across: random inputs at mixed field sizes; the edge cases (two-runner
races where S = 1, races at exactly k + 1, ragged and single-race batches);
objective depths k = 1 to 4; shift invariance; degenerate score vectors
including scores spread over 200, where a naive `exp()` overflows; and
padding width.

Agreement is about **1e-9 relative**. The autograd gradient matches finite
differences to 2.9e-8 **and matches paper 3's analytic `pl_grad_hess()` to
2.9e-8** — so paper 5 descends the same surface paper 3 did.

Reproducibility was checked across **two fresh `Rscript` processes**, not two
calls in one session: identical output, all 43 lines.

**One real bug the gate caught.** `torch_where()` selects the value of one
branch but differentiates both. Padded slots carried `log(0)` in the
unselected branch, so the forward loss was exactly right while the gradient
was NaN. The fix makes the denominator finite *before* the mask rather than
relying on the mask to discard it. A gate that only checked the loss value
would have passed this and left every fit silently broken.

## 7. The prior-run sequences

Built for the whole paper-3 frame. Rung 1 does not consume them; they exist
so rungs 2 and 3 have a verified input.

**Row identity with paper 3's frame**, asserted as a sorted set on
(`race_id`, `runner_id`) rather than by race count:

| check | value |
|---|---|
| rows | 64,389 |
| row-identical to paper 3's frame | TRUE |
| array dimensions | 64,389 × 20 × 8 |
| `seq_len` within the cap | 20 |
| no NA in the array | TRUE |

Eight channels per prior run: raw finishing position (not capped at 4),
beaten distance with a separate missing indicator, going ordinal, class,
field size, race distance in furlongs, and days since the previous run.
Cross-surface, every race code, ordered most-recent-first, padded with an
explicit length so the encoder masks correctly.

On the training split (45,970 observations):

| | min | Q1 | median | Q3 | p90 | max | mean |
|---|---|---|---|---|---|---|---|
| sequence length (capped) | 0 | 8 | 16 | 20 | 20 | 20 | 13.81 |
| career runs prior (uncapped) | 0 | 8 | 16 | 31 | 51 | 219 | 22.62 |

**40.29%** of observations have careers longer than the 20-run cap, which is
why `career_runs_prior` is carried as a separate scalar. Only 0.2% have no
prior run at all.

Channel summary over the 634,803 real (unpadded) slots:

| channel | min | median | mean | max | % zero |
|---|---|---|---|---|---|
| `finish_pos` | 0 | 5.00 | 5.406 | 99 | 0.58 |
| `beaten_dist` | −1 | 4.25 | 7.838 | 430 | 13.59 |
| `beaten_missing` | 0 | 0.00 | 0.000 | 1 | 99.96 |
| `going_ordinal` | 0 | 4.00 | 3.982 | 7 | 0.46 |
| `class` | 0 | 5.00 | 5.014 | 85 | 2.24 |
| `field_size` | 1 | 11.00 | 11.503 | 118 | 0.00 |
| `distance_furlongs` | 5 | 7.00 | 8.103 | 32 | 0.00 |
| `days_since_prev` | 0 | 17.00 | 34.930 | 37918 | 4.07 |

**Beaten distance is far better populated than expected.** P5-0's 89.75%
figure counted winners as missing; a winner is zero lengths behind the
winner, which is definitional rather than imputed, so only **0.04%** is
genuinely missing once winners are set to zero.

**Four channels carry values the encoder rungs will have to handle, and I
have not handled them.** They are reported rather than quietly cleaned:

- `class` reaches 85. CLAUDE.md records that pre-2006 class codes are
  multi-digit (11, 42, 53, 64…) and not comparable with the 2006+ 1–7
  scheme. The career history starts in 2003, so prior runs before 2006 carry
  the old encoding. The series' date-range decision keeps *qualifying races*
  at 2006+, but says nothing about prior runs reaching back further.
- `days_since_prev` reaches 37,918 — about 104 years, so a data fault or a
  sentinel.
- `field_size` reaches 118, implausible for a single race.
- `finish_pos` reaches 99, likely a sentinel rather than a placing.

None affects rung 1, which does not read the sequences. All four need a
decision before rung 3.

## 8. The paper-2b baseline was refitted, not reused

Paper 2b's published model was fitted on the whole training split, and this
paper's validation slice is carved out of that same split. Scoring the
published fit here would be in-sample for 2b and out-of-sample for the MLP,
which biases the comparison toward 2b and would make a "the MLP loses"
reading meaningless.

So 2b's exploded conditional logit was refitted on the fitting partition
alone and scored on the validation slice, exactly as the MLP is: same rows,
same races, same objective, same scoring path. This is 2b's base exploded
specification, not its published draw-interaction model, because the latter
carries a per-term Wald reduction and re-running a selection procedure
inside a refit would add a moving part irrelevant to the question.

Both arms are scored through one path: latent score → per-race softmax →
`build_ranking_per_race()`. The scorable race set is asserted identical
across arms — the same 1,505 races — so the bootstrap is genuinely paired.

## 9. The validation slice

**2010-12-15**, chosen by rule rather than by date: the series splits train
from test 70/30 by race count against a frozen calendar date, and this
applies the same rule one level down — the date at which 70% of the training
period's races have been run. A calendar date rather than a race index, so
it stays reproducible if the race universe changes.

| partition | races | dates |
|---|---|---|
| fitting | 3,517 (70.0%) | 2006-01-01 to 2010-12-15 |
| validation | 1,505 (30.0%) | 2010-12-16 to 2012-12-30 |

## 10. Environment

`{torch}` 0.17.0 and `{luz}` 0.5.2 installed. The first `install_torch()`
failed: it detected CUDA 12.0 on this machine, which that torch build does
not support (it wants 12.6, 12.8 or 12.9). The **CPU** build was installed
instead, which is the right target here — the nine fits took 10m 39s total,
about 71 seconds each, and the six remediation fits 12m 39s. There is
nothing in rungs 1 or 2 worth accelerating. Rung 3 is the first point at
which a GPU could matter, and that should be decided on a measured runtime.

`{luz}` is installed and pinned but the training loop is written directly
against `{torch}`. The loss is race-grouped — a batch is a set of whole
races, padded to that batch's widest field, reducing over races rather than
rows — and an explicit loop is easier to audit than the same thing routed
through luz's callback API. It is also the code path rungs 2 and 3 reuse.

**`renv::record()` has not been run.** The lockfile is unchanged, and
pinning is deliberately left until the environment is settled, since rung 3
may yet force a different torch build. Flagging it as outstanding rather
than doing it silently.

## 11. Rollback verification

`git diff main --stat` is **empty** — nothing on this branch is committed
yet. Everything is untracked working-tree state:

```
R/p5_sequences.R          R/p5_torch.R
R/p5_mlp.R                R/p5_baseline_2b.R
_targets_p5.R             scripts/run_p5_pipeline.R
scripts/verify_p5_pl_torch.R
papers/05_encoder/        (this report and two run logs)
```

`.gitignore` has one addition, `_targets_p5/`, matching paper 4's entry for
its own store.

No file used by papers 1-4 was modified. `docs/`, the landing page and
CLAUDE.md are untouched.

**Main store untouched:**

```
targets::tar_outdated(store = "_targets", script = "_targets.R")
→ character(0)
```

## 12. Where this stops, and what I recommend

The rung's rule says stop after the remediation pass and report either way.
This is that stop. Rung 2 is not started.

The decision in front of you is what rung 1's control should actually
compare. My reading is that the specification, not the machinery, is what
failed, and that the fix is one of:

1. **Give the MLP the zero/nonzero pairs** — `pos_lag1_zero` and
   `pos_lag2_zero` alongside the positions, so "no prior run" is separable
   from a finishing position. This changes the arm's feature set from paper
   3's 24, which is a real departure from "paper 3's features, unchanged",
   but it is the encoding paper 2b uses and the one a gradient-descent
   scorer needs.
2. **Compare against a linear scorer on identical features** rather than
   against paper 2b, so the contrast isolates function class with everything
   else held fixed. That control is already built — the linear configuration
   in the remediation pass — and it currently reads 5.863 against the MLP's
   5.835, which would make the MLP the *winner* of a like-for-like contrast.
3. **Run the one diagnostic fit** that separates the two explanations: the
   linear torch scorer on paper 2b's own 17 terms.

I have not chosen between these. Option 3 is cheap and settles the
attribution; options 1 and 2 change what the rung means and are yours to
decide.
