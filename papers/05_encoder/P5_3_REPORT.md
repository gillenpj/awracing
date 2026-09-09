# P5-3 — rung 3, the sequence encoder

Run 2026-09-07 on branch `paper5-encoder`. Nine hand-summarised history
terms leave the feature set; a GRU over the horse's prior-run sequences
replaces them, its output concatenated with the remaining terms before rung
1's MLP scorer. The strike rates stay — rung 2 closed as a loss.

**The test split is not scored anywhere in this task. Rung 4 is not
started.**

---

## 1. The two arms, term by term

Stated before any score and asserted in the pipeline
(`p5_rung3_arm_difference`), not left to prose.

| respect | rung 1 | rung 3 | differs |
|---|---|---|---|
| dense terms dropped | — | `pos_lag1_zero`, `pos_lag1_nonzero`, `pos_lag2_zero`, `pos_lag2_nonzero`, `days_LTO_log`, `going_runs_prior`, `going_sr_shrunk`, `going_sr_delta`, `has_wins` | **yes** |
| dense terms added | — | `career_runs_prior` (encoder block scalar) | **yes** |
| sequence encoder added | none | GRU over 20 prior runs × 8 channels | **yes** |
| downstream scorer | `p5_mlp_module` 256-128 | `p5_mlp_module` 256-128 | no |
| objective | PL, k = 3 | PL, k = 3 | no |
| validation slice | 2010-12-16 to 2012-12-30 | same | no |
| race universe | 32,296 fit / 13,674 val rows | identical | no |
| seed | 42 | 42 | no |
| configurations | 9 | 9 | no |
| epochs per configuration | 200 | 60, then the selected one refitted at 200 | **yes** |

The first three rows are the two halves of **one substitution**: nine scalar
summaries of a horse's prior runs out, the raw prior runs in.
`career_runs_prior` is part of the encoder block rather than a new feature —
the sequence is capped at 20 runs, and without the untruncated count the
block would carry strictly less than the sequences do. 26 terms become 18.
The strike rates survive, asserted.

**The one declared difference beyond that is the selection budget**, and §4
shows it is not load-bearing: the selected configuration refitted at 200
epochs reproduces its 60-epoch run exactly and does not improve on it. At
the level of the two models actually compared, the epoch allowance is
identical.

Rung 3's 18 dense terms:

```
age_diff  trainerSR  sireSR  jockeySR  entire  gelding  cheekpieces
rel_weight  or_relative  or_missing  trainer_aw_premium  going_ordinal
stall_normalised  course_Kempton  course_Lingfield  course_Southwell
course_Wolverhampton  career_runs_prior
```

## 2. Headline — the encoder wins on both metrics

Selection on validation Plackett-Luce loss and nothing else. 1,505
validation races, paired race-level bootstrap, B = 2000, seed 42, 90%
intervals.

| metric | rung 3 (encoder) | rung 1 (summaries) | difference | 90% interval | favours |
|---|---|---|---|---|---|
| P1_rank (higher better) | 0.00320924 | 0.00303180 | +1.774e-04 | [+1.160e-04, +2.399e-04] | **rung 3** |
| Brier_place (lower better) | 0.19434864 | 0.19700495 | −2.656e-03 | [−3.662e-03, −1.706e-03] | **rung 3** |

Both intervals exclude zero, both favouring the encoder.

> **The encoder finds something the summaries miss.**

The pre-registered reading that fired, verbatim:

> the encoder finds something the summaries miss — report and proceed to the
> test split

**It is not proceeded with here.** The instruction for this task was to
report and stop, and a specific stop instruction overrides the standing
proceed-by-default rule. The test split has not been scored. Whether to
score it is the next decision, not this task's.

## 3. Scale — the largest effect in the ladder so far

Validation PL loss per race, the one scale on which every arm is directly
comparable:

| arm | terms | budget | val PL loss | vs rung 1 |
|---|---|---|---|---|
| paper 2b, mlogit | 17 | closed form | 5.814307 | −0.015709 |
| linear in torch | 26 | 9 × 200 | 5.811308 | −0.012710 |
| rung 1 MLP | 26 | 9 × 200 | 5.798597 | — |
| rung 2 MLP | 23 + 3 embeddings | 9 × 200 | 5.841117 | −0.042520 |
| **rung 3 GRU** | **18 + sequence encoder** | **9 × 60, refit at 200** | **5.741720** | **+0.056878** |

**The encoder is worth 0.056878 per race** — 4.5 times what the
nonlinearity bought in rung 1 (0.012710) and 19 times what the nine extra
features bought (0.002999). It is also the only change in the paper so far
that moves the loss by more than the gap between paper 2b and rung 1.

It does this on **nine fewer hand-built features**. The dense block shrinks
from 26 terms to 18, and the model still improves — the sequences carry more
than the summaries extracted from them.

**The separation is complete across the grid.** Every one of the nine
encoder configurations at 60 epochs beats rung 1's best of nine at 200:
worst encoder 5.770048, best rung-1 MLP 5.798597. As in rung 2, there is no
configuration-selection story — only here it runs the other way.

## 4. The budget — 60 epochs was not the constraint

The selected configuration refitted alone at 200 epochs:

| | value |
|---|---|
| max abs difference, first 60 epochs of the 200-epoch trace vs the 60-epoch trace | **0** |
| best at 60 epochs | 5.741720, epoch 3 |
| best at 200 epochs | 5.741720, epoch 3 |
| improvement from the extra 140 epochs | **none** |

The refit is the same seeded run continued, and it reproduces the 60-epoch
trace **exactly** — max absolute difference 0, not merely within tolerance.
That is the two-fresh-processes reproducibility check satisfied by
construction, and it makes "did the extra epochs help?" well posed. They did
not: the optimum is at epoch 3 either way.

The trace afterwards is monotone divergence, more pronounced than anything
in rung 1: 5.9985 at epoch 60, 6.3002 at 100, 6.6125 at 150, 6.9166 at 200.
The encoder overfits this training partition quickly and comprehensively;
early stopping on the validation slice is doing the work, exactly as it did
for rung 1's MLP.

## 5. Every configuration — 9 × 60 epochs

Downstream MLP held at rung 1's selected 256-128, batch 64, weight decay
1e-5 throughout, so the only architecture searched is the encoder's own. A
one-factor-at-a-time design around a centre of hidden 32, one layer, dropout
0.1, lr 1e-3.

| config | hidden | layers | dropout | lr | best val PL loss | best epoch | loss at epoch 60 | degradation |
|---|---|---|---|---|---|---|---|---|
| 5 | 32 | 1 | **0.3** | 1e-03 | **5.741720** | 3 | 5.998542 | +0.2568 |
| 9 | 32 | 1 | 0.1 | 3e-04 | 5.752677 | 6 | 5.882625 | +0.1299 |
| 3 | 64 | 1 | 0.1 | 1e-03 | 5.753808 | 6 | 7.344000 | +1.5902 |
| 2 | 32 | 1 | 0.1 | 1e-03 | 5.754818 | 3 | 6.550726 | +0.7959 |
| 6 | 32 | 2 | 0.1 | 1e-03 | 5.755974 | 3 | 6.624005 | +0.8680 |
| 8 | 32 | 1 | 0.1 | 3e-03 | 5.757974 | 1 | 8.599707 | +2.8417 |
| 7 | 64 | 2 | 0.1 | 1e-03 | 5.758384 | 6 | 8.360324 | +2.6019 |
| 4 | 32 | 1 | **0.0** | 1e-03 | 5.758800 | 1 | 8.630301 | +2.8715 |
| 1 | **16** | 1 | 0.1 | 1e-03 | 5.770048 | 2 | 6.318262 | +0.5482 |

Three readings from the grid, none of them load-bearing for §2:

- **Dropout is the axis that matters.** 0.3 is best, 0.0 is second worst, and
  the ordering is monotone. Consistent with everything else here: the
  binding problem is overfitting, not capacity.
- **Capacity past 32 buys nothing.** Hidden 16 is the worst configuration,
  hidden 64 and two layers are no better than 32 and one. The spread from
  best to worst is 0.028, small against the 0.057 gain over rung 1.
- **Best epochs run 1 to 6**, tighter even than rung 1's 1 to 10.

## 6. The sequences as consumed

| | |
|---|---|
| channels | 8, per P5-1d, all bounded |
| cap | 20 most recent strictly-prior runs, cross-surface |
| mean sequence length | 13.77 fitting, 13.91 validation |
| rows at the 20-run cap | 13,492 of 32,296 fitting rows (**41.8%**) |
| rows with no prior run | 65 fitting, 26 validation |
| career length, fitting | median 16, max 167 |

41.8% of fitting rows sit at the cap, so `career_runs_prior` is carrying
real information for a large minority of the data rather than being a
formality.

Channel standardisation, computed over the fitting partition's **real slots
only** — padding contributes nothing to any mean and no validation slot
influences any scale:

| channel | centre | scale |
|---|---|---|
| `finish_pos` | 5.4318 | 3.8472 |
| `beaten_dist` | 7.5796 | 12.2939 |
| `beaten_missing` | 0.0005 | 0.0218 |
| `going_ordinal` | 3.9641 | 0.9034 |
| `class` | 4.1433 | 1.6594 |
| `field_size` | 11.8349 | 3.9553 |
| `distance_furlongs` | 8.1151 | 3.0043 |
| `days_since_prev` | 34.3838 | 58.3650 |

**One thing the encoder does not get back.** `days_LTO_log` — days from the
most recent prior run to today's race — leaves with the other summaries, and
the sequences do **not** restore it. The `days_since_prev` channel is the gap
between a historical run and the one before it, so the sequence carries the
rhythm of a career but not its distance from today. Rung 3 wins having lost
that, which makes the result stronger rather than weaker; it also names the
obvious first thing to try if the encoder is developed further.

## 7. Masking — asserted, not argued

Sequences are **right-padded**: real runs occupy the leading slots, padding
follows, and the encoder output is the hidden state at slot `seq_len`. Left
padding would not do — a GRU fed k zero vectors from a zero initial state
does not stay at zero, because the update and reset gates carry biases, so
the state entering the first real run would depend on how much padding
preceded it.

`p5_check_gru_masking()` asserts the property directly, both as a pipeline
target (`p5_gru_mask_check`) and as a standing gate
(`scripts/verify_p5_gru_mask.R`, three seeds):

| check | max abs diff | tolerance | passed |
|---|---|---|---|
| padding width is inert (20 vs 32) | 0 | 1e-12 | ✔ |
| padding content is inert (1e3 × noise in padded slots) | 0 | 1e-12 | ✔ |
| matches the unpadded sequence | 5.55e-17 | 1e-12 | ✔ |
| zero-length row gives the zero vector | 0 | 1e-12 | ✔ |

The third check is the one that earns its place. The two invariance checks
above it pass just as cleanly if the gather index is off by one — the
encoder would then summarise the wrong run and be perfectly consistent about
it. Feeding each row's real runs alone, with no padding at all, is what
pins the index.

Runs are reversed into chronological order before the encoder sees them, so
the last thing it reads is the most recent run.

## 8. Backend — recorded at fit time

The CPU decision is frozen for the paper (see CLAUDE.md), and `renv.lock`
cannot capture a C++ runtime. `p5_capture_backend()` is therefore called
both as its own target and **inside every fitting function**, so a fitted
run carries the backend it was actually produced on. `p5_backend_check`
asserts the two agree across all ten runs:

| device | CUDA available | torch | libtorch | threads | R | runs checked |
|---|---|---|---|---|---|---|
| cpu | FALSE | 0.17.0 | 2.8.0 | 4 | 4.6.0 | 10 |

No report can now claim a backend a fit did not use.

## 9. Runtime

| | wall clock |
|---|---|
| 9 configurations × 60 epochs | 1h 22m 13s |
| selected configuration refitted at 200 epochs | 22m 49s |
| everything else | ~3s |
| **total** | **1h 45m 15s** |

12 targets built, 80 skipped. CPU libtorch, 4 threads. The heaviest
configuration measured 19.1 s/epoch before the run; rung 1's MLP was about
1.15 s/epoch, so the encoder costs roughly an order of magnitude more per
epoch and the 60-epoch budget is what kept the grid inside two hours.

## 10. Gates

- `scripts/verify_p5_gru_mask.R` — **passes**, three seeds, all four checks.
- `scripts/verify_p5_pl_torch.R` — passes; unchanged by this rung, run as a
  standing check.
- `p5_rung3_arm_difference` — asserts the term-by-term difference, the
  surviving strike rates, and that the downstream scorer, batch size and
  weight decay match rung 1's selected configuration.
- `p5_backend_check` — asserts all ten fitted runs carry the recorded
  backend.
- `tar_outdated()` on the main store — `character(0)`; papers 1-4 untouched.

## 11. Where the ladder stands

| rung | change | verdict |
|---|---|---|
| 1 | linear scorer → MLP, same 26 terms | MLP wins, both intervals exclude zero. Control claim does not hold. |
| 2 | 3 strike rates → 3 entity embeddings | Embeddings lose, both intervals exclude zero. |
| 3 | 9 history summaries → GRU over prior runs | **Encoder wins, both intervals exclude zero. Largest effect in the paper: +0.0569 val PL loss.** |

Rung 3 is closed on validation. The pre-registered next step is the test
split; it is not taken here. Rung 4 is not started.
