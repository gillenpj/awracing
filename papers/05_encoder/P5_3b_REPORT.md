# P5-3b — rung 3 with the layoff restored

Run 2026-09-07 on branch `paper5-encoder`. `days_LTO_log` comes back as a
scalar term alongside `career_runs_prior`; 18 dense terms become 19.
Nothing else moves.

**The test split is not scored anywhere in this task.**

---

## 1. Why this rung exists

Rung 3 dropped nine hand-summarised history terms and replaced them with a
GRU over the prior-run sequences. Eight of the nine are things the
sequences do express. `days_LTO_log` is not.

The sequence carries `days_since_prev` — the gap between a historical run
and the one before it. It does not carry the gap from the **most recent**
prior run to **today's race**. The layoff a horse is coming off was
therefore invisible to rung 3's encoder, and nothing replaced it.

So rung 3 changed two things at once: it substituted eight summaries the
sequences subsume, and it deleted one they do not. That is the same fault
that cost rung 1 three attempts, in a form that survived the arm-difference
assertion because the assertion checked the term list against rung 1 and
not against what the sequences actually contain.

Rung 3b is the arm rung 3 should have been.

## 2. The two arms, term by term

Asserted in the pipeline (`p5_rung3b_arm_difference`) against **rung 3**,
not rung 1.

| respect | rung 3 | rung 3b | differs |
|---|---|---|---|
| dense terms added | — | `days_LTO_log` | **yes** |
| dense terms dropped | — | — | no |
| sequence encoder | GRU, 20 prior runs × 8 channels | identical | no |
| downstream scorer | `p5_mlp_module` 256-128 | identical | no |
| objective | PL, k = 3 | PL, k = 3 | no |
| validation slice | 2010-12-16 to 2012-12-30 | identical | no |
| seed | 42 | 42 | no |
| configuration grid | 9, one-factor-at-a-time | identical object | no |
| epochs per configuration | 60, winner refit at 200 | identical | no |

Exactly one respect, and the target fails if the grid is not the identical
object. The 200-epoch refit of the winner is included because rung 3's
comparator number is itself post-refit; comparing a 60-epoch figure against
it would reintroduce the budget asymmetry P5-1c was spent on.

## 3. Headline — the layoff was a real omission

1,505 validation races, paired race-level bootstrap, B = 2000, seed 42, 90%
intervals.

| metric | rung 3b (layoff restored) | rung 3 (layoff missing) | difference | 90% interval | favours |
|---|---|---|---|---|---|
| P1_rank (higher better) | 0.00328465 | 0.00320924 | +7.540e-05 | [+4.235e-05, +1.082e-04] | **rung 3b** |
| Brier_place (lower better) | 0.19326270 | 0.19434864 | −1.086e-03 | [−1.589e-03, −5.488e-04] | **rung 3b** |

Both intervals exclude zero, both favouring rung 3b.

The pre-registered reading that fired:

> the layoff was a real omission — rung 3b is the encoder arm

**Validation PL loss 5.718496 against rung 3's 5.741720** — the single
restored term is worth **0.023224 per race**. For scale, that is 1.8 times
what the whole nonlinearity bought in rung 1 (0.012710), and 41% of the
entire encoder gain rung 3 reported. One scalar.

Eight of the nine rung-3b configurations beat rung 3's selected arm. Only
config 1 (hidden 16) does not, at 5.743021 against 5.741720.

## 4. The ladder on validation

| arm | terms | val PL loss | vs rung 1 |
|---|---|---|---|
| paper 2b, mlogit | 17 | 5.814307 | −0.015709 |
| linear in torch | 26 | 5.811308 | −0.012710 |
| rung 1 MLP | 26 | 5.798597 | — |
| rung 2 MLP + embeddings | 23 + 3 | 5.841117 | −0.042520 |
| rung 3 GRU + encoder | 18 + seq | 5.741720 | +0.056878 |
| **rung 3b GRU + encoder** | **19 + seq** | **5.718496** | **+0.080102** |

Rung 3b sits 0.080102 better than rung 1 on **seven fewer hand-built
terms**.

## 5. Every configuration — 9 × 60 epochs

| config | hidden | layers | dropout | lr | best val PL loss | best epoch | loss at epoch 60 | degradation |
|---|---|---|---|---|---|---|---|---|
| 5 | 32 | 1 | **0.3** | 1e-03 | **5.718496** | 3 | 6.011697 | +0.2932 |
| 2 | 32 | 1 | 0.1 | 1e-03 | 5.729136 | 3 | 6.517491 | +0.7884 |
| 3 | 64 | 1 | 0.1 | 1e-03 | 5.730836 | 1 | 7.826136 | +2.0953 |
| 9 | 32 | 1 | 0.1 | 3e-04 | 5.731301 | 3 | 5.855294 | +0.1240 |
| 8 | 32 | 1 | 0.1 | 3e-03 | 5.734502 | 6 | 8.824645 | +3.0901 |
| 4 | 32 | 1 | **0.0** | 1e-03 | 5.735286 | 1 | 8.649143 | +2.9139 |
| 6 | 32 | 2 | 0.1 | 1e-03 | 5.735824 | 3 | 6.551225 | +0.8154 |
| 7 | 64 | 2 | 0.1 | 1e-03 | 5.737442 | 6 | 8.559757 | +2.8223 |
| 1 | **16** | 1 | 0.1 | 1e-03 | 5.743021 | 3 | 6.280685 | +0.5377 |

The same configuration wins as in rung 3 — hidden 32, one layer, dropout
0.3, lr 1e-3 — at the same best epoch, 3. The grid's shape is unchanged:
dropout is the axis that matters, capacity past 32 buys nothing, hidden 16
is worst.

## 6. The budget

| | value |
|---|---|
| max abs difference, first 60 epochs of the 200-epoch trace vs the 60-epoch trace | **0** |
| best at 60 epochs | 5.718496, epoch 3 |
| best at 200 epochs | 5.718496, epoch 3 |
| improvement from the extra 140 epochs | **none** |

Same finding as rung 3: the refit reproduces the shorter run exactly and the
optimum stays at epoch 3. The selection budget is not the constraint.

## 7. Rung 3 recomputed, and it reproduced exactly

Rung 3's grid and refit were rebuilt during this run — unintentionally; see
§8 — which turned into a full cross-process reproducibility check of the
previous report's headline.

| | P5_3_REPORT.md | recomputed here |
|---|---|---|
| best 60-epoch loss | 5.741720 | 5.741719947 |
| best epoch | 3 | 3 |
| all nine configurations | — | identical to every printed digit |
| arm (200-epoch refit) | 5.741720, epoch 3 | 5.741719947, epoch 3 |

`{targets}` confirms it independently: `p5_rung3_runs` and
`p5_rung3_refit_200` were recomputed, and **nothing downstream re-ran** —
`p5_scored_v6`, `p5_per_race_v6` and `p5_rung3_vs_rung1` all stayed skipped,
which only happens when the recomputed values hash identically to the
stored ones. Rung 3's numbers, and the comparison built on them, stand
unchanged.

## 8. The unintended recompute, and what caused it

Adding `P5_RUNG3B_RESTORED` and `p5_rung3b_term_list()` to `R/p5_gru.R`
invalidated every target depending on `p5_gru_module`, which is created at
source time by `torch::nn_module()` and captures the environment those new
objects were added to. The evidence is tight: exactly the
generator-dependent targets rebuilt (`p5_gru_mask_check`, `p5_rung3_runs`,
`p5_rung3_refit_200`), while `p5_rung2_runs` — the same pattern via
`p5_embed_module`, in a file that was not touched — skipped, along with all
of rungs 1 and 2. 93 targets skipped in total.

Cost: 1h 40m of recompute that produced nothing new. The helpers belonged in
their own file.

**Standing trap, worth recording:** any future edit to `R/p5_gru.R` — even
adding an unrelated constant — will re-run rungs 3 and 3b, about 3h 20m.
Moving the module generator behind a lazily-called function, or keeping new
helpers out of that file, would remove it. Not done here; this task's job
was rung 3b.

## 9. Which arm goes to the test split

Decided on validation PL loss and recorded as a target
(`p5_test_arm_choice`), not judged by hand:

| arm | terms | val PL loss | chosen |
|---|---|---|---|
| rung 3 | 18 | 5.741720 | |
| **rung 3b** | **19** | **5.718496** | **✔** |

Margin 0.023224. **Rung 3b is the encoder arm for the test split.**

## 10. Backend and gates

| device | CUDA | torch | libtorch | threads | runs checked |
|---|---|---|---|---|---|
| cpu | FALSE | 0.17.0 | 2.8.0 | 4 | 10 |

`p5_rung3b_backend_check` asserts every one of rung 3b's ten fitted runs
carries the recorded backend. `p5_gru_mask_check` passes — all four checks,
max abs difference 0, 0, 5.55e-17, 0.

## 11. Runtime

| | wall clock |
|---|---|
| rung 3b grid, 9 × 60 | 1h 15m 56s |
| rung 3 grid, recomputed unnecessarily | 1h 17m 27s |
| rung 3b refit at 200 | 24m 31s |
| rung 3 refit at 200, recomputed unnecessarily | 22m 17s |
| **total** | **3h 20m 25s** |

16 targets built, 93 skipped. About half the wall clock was the §8
recompute.

## 12. Where this stops

Rung 3b is closed on validation and is the encoder arm. **The test split has
not been scored** — the code for it (`R/p5_final.R`) exists but is not
sourced by any pipeline, and `_targets_p5.R` contains no test target. That
is the next task.
