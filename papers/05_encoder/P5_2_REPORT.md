# P5-2 — rung 2, entity embeddings

Run 2026-09-07 on branch `paper5-encoder`. The three strike rates leave the
feature set; learned embeddings on `trainer_id`, `jockey_id` and `sire_id`
replace them. Everything else is rung 1's closed arm, unchanged.

**The test split is not scored anywhere in this task. Rung 3 is not
started. No remediation was attempted.**

---

## 1. The two arms, term by term

Stated before any score, and asserted in the pipeline (`p5_arm_difference`)
rather than left to prose. Rung 1 took four attempts because three of them
compared arms differing in two ways at once.

| respect | rung 1 | rung 2 | differs |
|---|---|---|---|
| dense terms dropped | — | `trainerSR`, `jockeySR`, `sireSR` | **yes** |
| dense terms added | — | — | no |
| entity embeddings added | none | `trainer_id`, `jockey_id`, `sire_id` | **yes** |
| scorer | `p5_mlp_module` | `p5_mlp_module` | no |
| objective | PL, k = 3 | PL, k = 3 | no |
| validation slice | 2010-12-16 to 2012-12-30 | same | no |
| seed | 42 | 42 | no |
| configuration grid | 3 widths × 3 lr, batch 64 | identical object | no |
| epochs per configuration | 200 | 200 | no |

The two flagged rows are the two halves of one substitution: three columns
out, three embeddings in. Nothing else moves. 26 terms become 23, no term is
added, and `identical(p5_configs_v5, p5_configs_v4_mlp)` is asserted `TRUE`.

Rung 2's 23 dense terms:

```
pos_lag1_zero  pos_lag1_nonzero  pos_lag2_zero  pos_lag2_nonzero
age_diff  days_LTO_log  entire  gelding  cheekpieces  rel_weight
or_relative  or_missing  trainer_aw_premium  has_wins
going_runs_prior  going_sr_shrunk  going_sr_delta  going_ordinal
stall_normalised  course_Kempton  course_Lingfield  course_Southwell
course_Wolverhampton
```

Embedding side, all fixed before fitting: dimension 4 for all three
entities, minimum 20 fitting runs for an entity's own index, everything
below it to a shared bucket at index 1, vocabularies frozen on the fitting
partition. 885 indices × 4 = **3,540 embedding parameters**, and the
scorer's input width goes from 26 to 35.

## 2. Headline — the embeddings lose, and not narrowly

9 configurations × 200 epochs, selected on best validation Plackett-Luce
loss at any epoch and nothing else. 1,505 validation races, paired
race-level bootstrap, B = 2000, seed 42, 90% intervals.

| metric | rung 2 (embeddings) | rung 1 (strike rates) | difference | 90% interval | favours |
|---|---|---|---|---|---|
| P1_rank (higher better) | 0.00290560 | 0.00303180 | −1.262e-04 | [−1.728e-04, −7.981e-05] | **rung 1** |
| Brier_place (lower better) | 0.19894076 | 0.19700495 | +1.936e-03 | [+1.143e-03, +2.722e-03] | **rung 1** |

Both intervals exclude zero, both favouring rung 1.

> **The embeddings are worse than the strike rates they replaced.**

For scale: rung 1's MLP beat the linear scorer by +3.829e-05 on P1_rank.
Rung 2 loses to rung 1 by 1.262e-04 on the same metric — about 3.3 times the
size of the effect rung 1 closed on, in the opposite direction.

## 3. Validation PL loss — the swap gives back more than rung 1 won

Per race, the one scale on which every arm in this paper is directly
comparable:

| arm | terms | budget | val PL loss | change on previous row |
|---|---|---|---|---|
| paper 2b, mlogit | 17 | closed form | 5.814307 | — |
| linear in torch | 26 | 9 × 200 | 5.811308 | +0.002999 — the nine extra features |
| rung 1 MLP | 26 | 9 × 200 | 5.798597 | +0.012710 — the nonlinearity |
| **rung 2 MLP** | **23 + 3 embeddings** | **9 × 200** | **5.841117** | **−0.042520 — the swap** |

The swap costs 0.042520 per race: **3.3 times what the nonlinearity bought
and 14 times what the nine extra features bought.** Rung 2 sits 0.026810
worse than paper 2b's mlogit, which had 17 terms, a linear score and a
closed-form fit.

**The separation is complete across the grid.** The best of rung 2's nine
configurations (5.841117) is worse than the worst of rung 1's nine
(5.818877), by 0.022240. There is no configuration-selection story here:
every embedding fit loses to every strike-rate fit.

## 4. Every configuration

### Rung 2 — 9 × 200 epochs, batch 64 throughout

| config | widths | lr | best val PL loss | best epoch | loss at epoch 200 | degradation |
|---|---|---|---|---|---|---|
| 2 | 128-64 | 1e-03 | **5.841117** | 3 | 7.242583 | +1.4015 |
| 5 | 256-128 | 1e-03 | 5.842595 | 3 | 9.356203 | +3.5136 |
| 8 | 64-32 | 1e-03 | 5.842750 | 6 | 6.593595 | +0.7508 |
| 3 | 128-64 | 3e-04 | 5.843719 | 6 | 6.335585 | +0.4919 |
| 7 | 64-32 | 3e-03 | 5.843844 | 3 | 7.012761 | +1.1689 |
| 6 | 256-128 | 3e-04 | 5.844630 | 3 | 7.065270 | +1.2206 |
| 9 | 64-32 | 3e-04 | 5.847633 | 15 | 6.099359 | +0.2517 |
| 1 | 128-64 | 3e-03 | 5.862054 | 1 | 8.374052 | +2.5120 |
| 4 | 256-128 | 3e-03 | 5.864305 | 1 | 11.307956 | +5.4437 |

Rung 1's comparator grid, for reference: best 5.798597 (config 6, 256-128 at
3e-04), worst 5.818877, best epochs 1 to 10, degradation +0.098 to +2.746.

**Rung 2 overfits harder.** Degradation from best epoch to epoch 200 runs
+0.25 to +5.44, against rung 1's +0.10 to +2.75, and the worst case doubles.
That is what 3,540 extra free parameters on 3,517 fitting races look like.
The winning configuration's first ten epochs never get below 5.841117:

```
5.860574  5.851140  5.841117  5.854282  5.862505
5.855782  5.870103  5.881549  5.884348  5.901743
```

Rung 1's winner passes under that number at epoch 2 and stays under it
through epoch 7.

## 5. Why — two structural reasons, both visible without another fit

### The strike rates are time-varying and externally computed; an embedding is neither

`trainerSR`, `jockeySR` and `sireSR` are the entity's cumulative wins over
races at the latest meeting date **strictly before** this race, read from a
cumulative table built over the whole 1.72M-row archive. The same trainer
therefore carries a different value in every race, the value updates as the
career runs, and it is defined from history the fitting partition never
sees.

An embedding is one static vector per entity, learned only from the 32,296
fitting rows. It cannot vary within an entity over time, and it knows
nothing about the entity's record outside the fitting partition. The swap
was one change to the feature set, but it removed a moving, archive-wide
statistic and put back a fixed, partition-local parameter.

### Under a chronological split, half the validation rows get the generic vector

Vocabularies are frozen on the fitting partition, which is the earlier
period. The validation slice is later, so it contains entities that were
rare or absent then:

| entity | distinct in fitting | vocabulary | own index | % fitting rows bucketed | % validation rows bucketed | % validation rows unseen in fitting |
|---|---|---|---|---|---|---|
| `trainer_id` | 657 | 296 | 295 | 6.34 | 15.54 | 6.35 |
| `jockey_id` | 541 | 185 | 184 | 4.38 | 19.77 | 9.19 |
| `sire_id` | 1,279 | 404 | 403 | 14.58 | 26.36 | 6.65 |

**49.5% of validation rows have at least one of the three entities mapped to
the shared bucket**, against 22.8% of fitting rows. For those rows the model
sees a generic vector where rung 1 saw a real number: `trainerSR`,
`jockeySR` and `sireSR` are NA on **zero** rows of either partition.

Both reasons are properties of the design as pre-registered, not of the
tuning. Neither is a defect to fix inside rung 2 — the rung asked whether
learned embeddings beat the strike rates on equal terms, and the answer is
no.

## 6. The reading, as pre-registered

The three readings were fixed in `p5_rung2_reading` before the fit. The one
that fired:

> **embeddings are WORSE than the strike rates they replaced — report and
> stop, do not remediate**

Followed exactly. No threshold was re-tuned, no dimension re-tried, no
fourth attempt started.

**Rung 3's comparator stays the rung-1 MLP at 5.798597 on this slice.**
Rung 2 does not become it.

What rung 2 does not say: it does not say entity identity is uninformative.
It says that a static, fitting-partition-local embedding at these settings
is a worse carrier of it than a time-varying career strike rate, on a
chronological split where half the later rows fall outside the vocabulary.
Anything stronger would need a rung that was not run.

## 7. Runtime

| | wall clock |
|---|---|
| rung 2 grid, 9 × 200 epochs | 48m 50s |
| everything else in the pipeline run | 4s |
| **total** | **49m 4s** |

Rung 1's MLP grid was 34m 36s; the embeddings add about 41%. CPU libtorch
build, as before. 10 targets built, 63 skipped.

## 8. Housekeeping done in this task

**A `tar_source()` load-order collision, fixed.** `R/p5_embed.R` defined
`P5_RUNG2_TERMS <- setdiff(P5_CONTROL_TERMS, ...)` at source time, but
`P5_CONTROL_TERMS` lives in `R/p5_mlp.R`, which sorts after it. Paper 5's
own pipeline sources explicitly and was unaffected; the main pipeline's bare
`tar_source()` failed to load, so `tar_outdated()` on the main store errored
with `object 'P5_CONTROL_TERMS' not found` and `tar_make()` on papers 1-3
would have failed the same way. Replaced with a literal `P5_RUNG2_DROPPED`
and a call-time `p5_rung2_term_list()`; the target now derives from the
pipeline's own `p5_control_terms`. `tar_outdated()` on the main store
returns `character(0)`. **No paper-5 file evaluates anything at source time
that depends on another file's load order.**

**A stale pipeline lock, cleared.** A reboot killed the first rung-2 run
inside `p5_rung2_runs` and left `_targets_p5/meta/process` holding PID
16056. `Get-Process` confirmed nothing owned it before it was deleted. The
six targets built before the reboot were skipped on the resumed run; the fit
restarted from scratch, as intended.

**Standing gate.** `scripts/verify_p5_pl_torch.R` — **passes**, all
assertions. Autograd matches finite differences to 2.861e-08 and paper 3's
analytic gradient to 2.866e-08. Rung 2 changed nothing it covers; run as
confirmation, not because anything moved.

## 9. Where the ladder stands

| rung | change | verdict |
|---|---|---|
| 1 | linear scorer → MLP, same 26 terms | MLP wins, both intervals exclude zero. Control claim does not hold. |
| 2 | 3 strike rates → 3 entity embeddings | **Embeddings lose, both intervals exclude zero.** |
| 3 | hand-summarised history → sequence encoder | not started |

Rung 3 is unchanged by this: its comparator was already the rung-1 MLP, its
sequence channels are built and bounded, and it does not read the entity
embeddings. Rung 2 is closed.
