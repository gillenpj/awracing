# P5-1d — equal selection budget, and the close of rung 1

Run 2026-09-07 on branch `paper5-encoder`. Both arms refitted at the same
budget, the last flagged sequence channel cleaned, and rung 1 closed.

**The test split is not scored anywhere in this task. Rung 2 is not
started.**

---

## 1. Headline — the MLP's advantage survives an equal budget

9 configurations × 200 epochs per arm, 1,800 evaluations each, selected on
best validation Plackett-Luce loss at any epoch. Identical 26 terms,
identical loss, loop, slice and seed. 1,505 validation races, paired
race-level bootstrap, B = 2000, seed 42, 90% intervals.

| metric | MLP | linear | difference | 90% interval | favours |
|---|---|---|---|---|---|
| P1_rank (higher better) | 0.00303180 | 0.00299351 | +3.829e-05 | [+1.042e-05, +6.579e-05] | **MLP** |
| Brier_place (lower better) | 0.19700495 | 0.19754793 | −5.430e-04 | [−1.001e-03, −6.284e-05] | **MLP** |

Both intervals exclude zero, both favouring the MLP.

> **Control claim does NOT hold at an equal budget. The nonlinearity is
> buying something.**

Against P5-1c's unequal-budget figures (+3.909e-05, −5.502e-04) the change
is in the fourth significant figure. The selection-budget asymmetry was not
what produced the result.

## 2. What the nonlinearity buys — the revised figure

Validation PL loss per race, the one scale on which the three arms are
directly comparable:

| arm | terms | budget | val PL loss | gain over previous row |
|---|---|---|---|---|
| paper 2b, mlogit | 17 | closed form | 5.814307 | — |
| linear in torch | 26 | 9 × 200 | 5.811308 | **+0.002999** — the nine extra features |
| MLP | 26 | 9 × 200 | 5.798597 | **+0.012710** — the nonlinearity |

**The nonlinearity is worth 0.01271 per race, about 4.2 times the 0.00300
the nine extra features are worth.** P5-1c put the same two quantities at
0.01298 and 0.00273, a ratio of 4.8. The revision is small and in the
direction of the features, because the extra eight linear configurations
improved the linear arm and no extra MLP epoch improved the MLP.

## 3. Why the equal budget changed so little

**The MLP arm's numbers did not move at all.** Every one of the nine
configurations already had its minimum inside the first ten epochs at 60,
so the extra 140 epochs were 140 more chances to be worse, and each one
was. The 200-epoch grid reproduces the 60-epoch grid to every printed
digit — same best loss, same best epoch, all nine.

That reproduction is worth recording on its own account: it is the
convention's two-fresh-processes check, satisfied by construction. The
P5-1c grid and this one ran in separate `Rscript` invocations days apart,
and the fitting path is deterministic under the seed.

**The correction had to come from the linear side, and it was small.**
Nine linear configurations instead of one improved the best linear loss
from 5.811575 to 5.811308 — 0.000267, about 2% of the 0.01271 gap. The
grid's own spread is 0.00145 from best to worst excluding the outlier at
lr 1e-04 / batch 128, so there was very little there to find.

## 4. Every configuration, both arms

### MLP arm — 9 × 200 epochs, batch 64 throughout

| config | widths | lr | best val PL loss | best epoch | loss at epoch 200 | degradation |
|---|---|---|---|---|---|---|
| 6 | 256-128 | 3e-04 | **5.798597** | 3 | 6.310393 | +0.5118 |
| 2 | 128-64 | 1e-03 | 5.805054 | 3 | 6.324014 | +0.5190 |
| 8 | 64-32 | 1e-03 | 5.805308 | 3 | 6.039470 | +0.2342 |
| 3 | 128-64 | 3e-04 | 5.806882 | 6 | 6.003979 | +0.1971 |
| 7 | 64-32 | 3e-03 | 5.807255 | 2 | 6.136743 | +0.3295 |
| 9 | 64-32 | 3e-04 | 5.807342 | 10 | 5.905335 | +0.0980 |
| 5 | 256-128 | 1e-03 | 5.810039 | 3 | 7.367612 | +1.5576 |
| 4 | 256-128 | 3e-03 | 5.815154 | 1 | 8.561473 | +2.7463 |
| 1 | 128-64 | 3e-03 | 5.818877 | 1 | 6.747924 | +0.9290 |

### Linear arm — 9 × 200 epochs, lr × batch size

| config | lr | batch | best val PL loss | best epoch | loss at epoch 200 | degradation |
|---|---|---|---|---|---|---|
| 1 | 1e-03 | 32 | **5.811308** | 69 | 5.813679 | +0.0024 |
| 7 | 1e-03 | 128 | 5.811389 | 47 | 5.812585 | +0.0012 |
| 4 | 1e-03 | 64 | 5.811575 | 85 | 5.812750 | +0.0012 |
| 8 | 3e-04 | 128 | 5.811631 | 160 | 5.812235 | +0.0006 |
| 2 | 3e-04 | 32 | 5.811864 | 60 | 5.812549 | +0.0007 |
| 5 | 3e-04 | 64 | 5.811962 | 97 | 5.812528 | +0.0006 |
| 3 | 1e-04 | 32 | 5.812067 | 194 | 5.812150 | +0.0001 |
| 6 | 1e-04 | 64 | 5.812761 | 199 | 5.812803 | +0.0000 |
| 9 | 1e-04 | 128 | 5.820033 | 200 | 5.820033 | 0.0000 |

Config 4 is the single configuration P5-1c ran, and it reproduces exactly:
5.811575 at epoch 85.

**Batch size as the linear arm's second axis.** A linear scorer has no layer
widths, so the MLP grid's second axis is replaced by the other knob that
changes the optimisation path without changing the function class or the
information available. The three levels span the range this work has used —
the declared MLP grid holds 64 races per batch and the P5-1a remediation
pass used 64 and 128 — extended down to 32 so the levels span the same
fourfold range as the MLP grid's widths, centred on the 64 the MLP grid
holds fixed. Learning rates are the three specified.

## 5. Does the early-peak pattern persist? Yes, and more starkly

| | MLP | linear |
|---|---|---|
| best epoch, range over the nine | **1 to 10** of 200 | **47 to 200** of 200 |
| degradation from best to epoch 200 | +0.098 to +2.746 | +0.000 to +0.002 |

At 60 epochs the MLP's best epochs ran 1 to 10 and the degradation by
epoch 60 ran +0.05 to +1.01. At 200 they are the same best epochs and the
degradation reaches +2.75. The MLP overfits this feature set within a
handful of passes and then diverges; the linear arm converges and holds
flat, exactly as it did at 200 epochs in P5-1c.

**But the MLP's optimum is not a single noisy dip, which is what P5-1c
could not rule out.** The winning configuration's first ten epochs:

```
5.833250  5.808491  5.798597  5.804707  5.805365
5.807029  5.810677  5.814510  5.814675  5.819223
```

Epochs 2 through 7 — six consecutive evaluations — all sit below 5.811308,
the best the linear arm reached across all 1,800 of its own evaluations.
And 7 of the 9 MLP configurations beat that number; only configs 4 and 1,
both at lr 3e-03, do not. The MLP's advantage is a plateau across
configurations and across epochs, not a minimum found by searching harder.

## 6. Rung 1's verdict

The equal-budget test was the last thing standing between P5-1c's result
and a conclusion. It changed nothing material.

**On identical features and an identical selection budget, the MLP beats
the linear scorer on both ranking metrics. The control claim does not
hold.** Rung 1 was built to establish that an MLP under this objective ties
a linear scorer, so that a later encoder gain could be attributed to the
sequence representation. It does not tie.

What follows from that, unchanged from P5-1c and now on firmer ground:

- **Rung 3's comparator is the 26-term MLP**, not paper 2b and not paper 3.
  The baseline an encoder has to beat is 5.798597 on this slice, not
  5.814307.
- **Paper 3's "the function class was not the binding constraint" is in
  tension with this** and the write-up should say so. Paper 3 found a tie
  between a linear score and a gradient-boosted tree; here a different
  nonlinear class, on the same objective and essentially the same
  information, wins. This does not overturn paper 3 — different function
  class, different comparison, and paper 3's contrast was scored on the
  test split rather than on a validation slice carved out of training — but
  a reader will notice, and the paper should get there first.

No further rung 1 diagnostics, per the instruction. Rung 1 is closed.

## 7. `beaten_dist` — winsorised at 100 lengths

### The distribution, before cleaning

444,580 career-run rows, of which 208 (0.047%) have no reading at all.
Over the 444,372 real values:

| quantile | 0% | 50% | 75% | 90% | 95% | 99% | 99.9% | max |
|---|---|---|---|---|---|---|---|---|
| lengths | 0.00 | 5.52 | 11.81 | 23.75 | 38.12 | 102.81 | 177.54 | **430.00** |

| above | 30 | 50 | 75 | 100 | 150 | 200 | 300 |
|---|---|---|---|---|---|---|---|
| rows | 31,807 | 14,433 | 7,299 | 4,664 | 1,028 | 293 | 20 |
| share | 7.16% | 3.25% | 1.64% | 1.05% | 0.23% | 0.066% | 0.005% |

### What the tail is

It is real data, not a sentinel. The column is **cumulative** lengths behind
the winner, and the tail is jumps racing:

| race type | rows | median | p99 | max | rows over 100 |
|---|---|---|---|---|---|
| All Weather Flat | 160,596 | 4.31 | 49.62 | 349.50 | 638 |
| Flat | 241,560 | 5.75 | 56.25 | 306.75 | 1,084 |
| Hurdle | 35,846 | 22.00 | 171.89 | 427.75 | 2,525 |
| Chase | 5,598 | 23.75 | 152.02 | 430.00 | 378 |
| National Hunt Flat | 772 | 12.91 | 186.76 | 394.31 | 39 |

Of the 4,664 rows above 100 lengths, 54% are Hurdle and 8% Chase, and 33%
carry an `unfinished` code — pulled up, fell, unseated. A tailed-off horse
in a jumps race genuinely finishes hundreds of lengths adrift of the winner.
430 is not a fault in the feed.

### The treatment, and why

**Winsorised at 100 lengths, not read as unavailable.** The two treatments
already in use divide on whether the out-of-range value is on the channel's
own scale:

- `class` 42 and `finish_pos` 99 are **not** on their channels' scales — a
  pre-2006 class code is a different encoding, and 99 is a sentinel. Both
  take −1, the unavailable fill.
- `field_size` 118 and `days_since_prev` 37,918 **are** on their scales but
  their exact magnitude carries nothing. Both are winsorised, which keeps
  the ordering.

`beaten_dist` is the second kind. A reading of 430 means the horse was
beaten a very long way, which is information, and −1 would throw it away
and misreport it as absent. Past about 100 lengths the exact figure adds
nothing an encoder can use: the horse was comprehensively beaten either way.

**One honest asymmetry.** The bound touches 1.05% of rows, where the
`field_size` and `days_since_prev` bounds touch 0.03% each. It is a more
aggressive cap in that sense, and it is deliberate: this channel's tail is
what distorts the standardised scale a neural encoder sees. Before the
bound the maximum sits 22.8 standard deviations above the channel mean;
after it, 5.8. That is the reason to cap it, and a bound at 250 would leave
the scale problem in place while cleaning almost nothing.

### The channel afterwards

Over the 634,803 real slots on the training split:

| channel | min | median | mean | max | % zero |
|---|---|---|---|---|---|
| `finish_pos` | −1 | 5.00 | 5.391 | 35 | 0.00 |
| `beaten_dist` | −1 | 4.25 | **7.619** | **100** | 13.59 |
| `beaten_missing` | 0 | 0.00 | 0.000 | 1 | 99.96 |
| `going_ordinal` | 0 | 4.00 | 3.982 | 7 | 0.46 |
| `class` | −1 | 5.00 | 4.216 | 7 | 0.00 |
| `field_size` | 1 | 11.00 | 11.495 | 40 | 0.00 |
| `distance_furlongs` | 5 | 7.00 | 8.103 | 32 | 0.00 |
| `days_since_prev` | −1 | 17.00 | 34.574 | 1000 | 0.00 |

Mean falls from 7.838 to 7.619; nothing else moves. Every sequence channel
is now bounded. Row identity with paper 3's frame re-asserted after the
rebuild: 64,389 rows, array 64,389 × 20 × 8, no NA.

**This changed no number in sections 1 to 6.** Rung 1 does not read the
sequences. The cleaning is for rung 3.

## 8. Runtime

| | wall clock |
|---|---|
| linear grid, 9 × 200 epochs | 13m 51s |
| MLP grid, 9 × 200 epochs | 34m 36s |
| sequence rebuild | 7s |
| everything else | under a minute |

CPU libtorch build, as before.

## 9. Gates and rollback

`scripts/verify_p5_pl_torch.R` — **passes**, all assertions. Autograd
matches finite differences to 2.86e-08 and paper 3's analytic
`pl_grad_hess()` to 2.87e-08. Nothing in the objective was touched; run as
a standing check.

`git diff main --stat`:

```
 .gitignore |  4 ++++
 renv.lock  | 18 ++++++++++++++++++
 2 files changed, 22 insertions(+)
```

Unchanged from P5-1b and P5-1c — both additions only. Everything else on
this branch is untracked working-tree state. No file used by papers 1-4 was
modified; `docs/`, the landing page and CLAUDE.md are untouched.

**Main store untouched:**

```
targets::tar_outdated(store = "_targets", script = "_targets.R")
→ character(0)
```

Only 19 targets in the paper-5 store were invalidated: the P5-1d block and
the four-target sequence chain the `beaten_dist` bound feeds. No rung-1
target from P5-1b or P5-1c re-ran, so the comparisons in §1 and §2 are
against exactly the numbers those reports carry.

## 10. Where this stops

Rung 1 is closed. Rung 2 is not started, and no further rung 1 diagnostic
is proposed.
