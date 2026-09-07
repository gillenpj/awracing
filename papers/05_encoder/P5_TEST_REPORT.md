# P5-TEST — the test split, scored once

Run 2026-09-07 on branch `paper5-encoder`. Two arms refitted on the full
training split at their validation-selected configurations, then scored on
the held-out test split. Three contrasts, all pre-registered.

**The test split was scored once. No re-runs, no variants, no sanity
refits.**

---

## 1. Backend

Captured inside each fitted run and asserted against the pipeline's own
record (`p5_test_backend_check`), so neither arm can be reported on a
backend it was not fitted on.

| device | CUDA available | torch | libtorch | threads | R | runs checked |
|---|---|---|---|---|---|---|
| cpu | FALSE | 0.17.0 | 2.8.0 | 4 | 4.6.0 | 2 |

The CPU backend is frozen for the paper. Both arms, and every rung behind
them, were fitted on it.

## 2. The arm difference

Asserted in `p5_test_arm_difference` before any score.

| respect | rung 1 | rung 3b | differs |
|---|---|---|---|
| dense terms | 26 hand-built | 19 (8 summaries out, + block scalar) | **yes** |
| sequence encoder | none | GRU over 20 prior runs × 8 channels | **yes** |
| downstream scorer | `p5_mlp_module` 256-128 | `p5_mlp_module` 256-128 | no |
| objective | PL, k = 3 | PL, k = 3 | no |
| fitted on | 45,970 rows / 5,022 races | identical | no |
| scored on | 18,419 rows / 2,183 races | identical | no |
| epochs (validation-selected) | 3 | 3 | no |
| seed | 42 | 42 | no |
| selection | validation slice only | validation slice only | no |

The two flagged rows are the one substitution: eight scalar summaries of a
horse's prior runs out, the raw prior runs in. The strike rates are in both
arms — rung 2 lost and its embeddings are not carried forward.

**Both arms were trained for exactly 3 epochs**, the epoch each selected on
the validation slice, carried over unchanged. There is no held-out set at
this stage and no per-epoch evaluation: scoring the test split each epoch,
even only to record it, would put it inside the selection loop. The full
training split is 43% larger than the fitting partition used for selection,
so an epoch is 43% more gradient steps than it was; both arms take that
change identically.

**Race universe.** All three arms are scored on the identical set of 2,183
test races — rung 1, rung 3b and paper 3's stored per-race table each
contain exactly those races, so the intersection is the whole of each.

Paper 5's arms go through paper 3's own evaluation path —
`build_test_predictions_3()`, `build_ranking_eval_runners()`,
`build_ranking_per_race()`, and the series' single-bet backtest — with
nothing differing but the z vector.

## 3. Headline — rung 3b vs rung 1

2,183 test races, paired race-level bootstrap, B = 2000, seed 42, 90%
intervals.

| metric | rung 3b (encoder) | rung 1 (summaries) | difference | 90% interval | favours |
|---|---|---|---|---|---|
| P1_rank (higher better) | 0.00432735 | 0.00406876 | +2.586e-04 | [+1.994e-04, +3.201e-04] | **rung 3b** |
| Brier_place (lower better) | 0.19741153 | 0.20061520 | −3.204e-03 | [−4.019e-03, −2.452e-03] | **rung 3b** |
| test pl_r2 (higher better) | 0.06438041 | 0.05378811 | +1.059e-02 | [+8.220e-03, +1.300e-02] | **rung 3b** |

All three intervals exclude zero.

> **The sequence encoder beats the hand-built history summaries on the test
> split, on every measure, and the validation result holds out of sample.**

The effect is larger on test than on validation: +2.586e-04 on P1_rank
against +1.774e-04 for rung 3 on the validation slice. Nothing was tuned
between the two, so this is the same model measured on a different, larger
sample rather than an improvement.

## 4. The series comparison — rung 3b vs paper 3

| metric | rung 3b (encoder) | paper 3 (GBT) | difference | 90% interval | favours |
|---|---|---|---|---|---|
| P1_rank | 0.00432735 | 0.00401388 | +3.135e-04 | [+2.455e-04, +3.801e-04] | **rung 3b** |
| Brier_place | 0.19741153 | 0.20143009 | −4.019e-03 | [−4.915e-03, −3.134e-03] | **rung 3b** |
| test pl_r2 | 0.06438041 | 0.05145382 | +1.293e-02 | [+1.016e-02, +1.562e-02] | **rung 3b** |

All three intervals exclude zero.

Paper 3's figures are its published ones, read from the main store and not
recomputed: P1_rank 0.004014, Brier_place 0.201430 — the numbers CLAUDE.md
records for that paper.

## 5. The ladder end to end — rung 1 vs paper 3

| metric | rung 1 (MLP) | paper 3 (GBT) | difference | 90% interval | favours |
|---|---|---|---|---|---|
| P1_rank | 0.00406876 | 0.00401388 | +5.488e-05 | [+1.735e-05, +9.178e-05] | **rung 1** |
| Brier_place | 0.20061520 | 0.20143009 | −8.149e-04 | [−1.343e-03, −2.913e-04] | **rung 1** |
| test pl_r2 | 0.05378811 | 0.05145382 | +2.334e-03 | [+7.285e-04, +3.898e-03] | **rung 1** |

All three intervals exclude zero, all favouring rung 1 — but the margins
are roughly a fifth of rung 3b's over the same baseline.

**Nine contrasts, nine intervals excluding zero, every one favouring the
newer arm.** The ordering is strict and consistent across all three
metrics:

```
paper 3 (GBT)  <  rung 1 (MLP)  <  rung 3b (encoder)
```

This is a marked change in the series. Papers 1 to 3 could not distinguish
their models from one another on this test split — every paired interval in
paper 3 against 2b contained zero, and the one contrast that excluded zero
was the market beating both. Here three arms separate cleanly.

## 6. Where the market still stands

Not recomputed in this task, and no market contrast was run. For context
only, the series' published market baseline on the test split is P1_rank
0.00543 and Brier_place 0.1875 (papers 2b and 3). Rung 3b at 0.00433 and
0.19741 narrows the gap on both but does not close it: the settled starting
price remains ahead on ranking, consistent with paper 4's finding that
against the settled price the model adds nothing distinguishable.

Any statement stronger than that needs a market contrast on this universe,
which was not part of this task.

## 7. The backtest — an outcome, selecting nothing

Single bet per race, the series' rule: among horses clearing Owen's naive
filter (model win probability > 0.15 and model/market ratio > 1.3), back the
one with the highest model win probability. Win settled at SP; place and
each-way settled from the real-SP payout tables.

| arm | bet | bets | wins | profit | **ROI** | ROI less top winner |
|---|---|---|---|---|---|---|
| rung 3b | win | 1,064 | 131 | −129.75 | **−12.19%** | −13.52% |
| rung 1 | win | 1,096 | 124 | −212.17 | −19.36% | −20.84% |
| paper 3 | win | 1,133 | 124 | −252.76 | −22.31% | −23.74% |
| rung 3b | place | 1,064 | 475 | −108.51 | **−10.20%** | −10.70% |
| rung 1 | place | 1,096 | 477 | −82.39 | −7.52% | −8.07% |
| paper 3 | place | 1,133 | 471 | −158.90 | −14.02% | −14.56% |
| rung 3b | each-way | 1,064 | 475 | −126.83 | **−5.96%** | −6.76% |
| rung 1 | each-way | 1,096 | 477 | −183.65 | −8.38% | −9.26% |
| paper 3 | each-way | 1,133 | 471 | −305.20 | −13.47% | −14.33% |

**No arm makes money.** Every ROI is negative, consistent with the whole
series.

Rung 3b is the best of the three on win (−12.2% against −19.4% and −22.3%)
and on each-way (−6.0% against −8.4% and −13.5%). **It is the worst of the
paper-5 arms on place**: −10.20% against rung 1's −7.52%, despite having the
better Brier_place. That is not a contradiction — Brier_place scores
calibration across the whole field, while the bet rule selects the single
highest model win probability that clears a market-ratio filter, so the two
measure different things on different subsets. It is recorded rather than
explained away.

No intervals are attached to any ROI figure. None were requested, ROI
selects nothing here, and the `ROI less top winner` column shows what the
single largest winner is worth in each row — between 1.3 and 1.5 points
throughout, so no row rests on one result.

## 8. What went wrong, and what it did not touch

The first pipeline run **completed both fits and both sets of test
predictions**, then errored on `p5_test_backtests` with
`could not find function "build_value_bet_runners"` — `R/value_bets_p2b.R`
was not in the paper-5 pipeline's `tar_source()` list. My omission.

Adding the missing `tar_source()` line and re-running did **not** rescore
anything. Verified before re-running, not asserted afterwards:
`tar_outdated()` reported exactly five outstanding targets —
`p5_test_backtests`, `p5_test_per_race`, `p5_test_contrasts`,
`p5_test_race_universe`, `p5_test_reading` — and neither
`p5_test_fit_rung1`, `p5_test_fit_rung3b` nor `p5_test_predictions` was
among them. The scores in this report are from the first and only fit of
each arm.

The same check confirmed the GRU generator trap recorded in CLAUDE.md was
not triggered: sourcing a new file invalidates nothing, and no rung-3 or
rung-3b target refitted. The trap is specific to editing `R/p5_gru.R`
itself.

## 9. Where this stops

The test split is scored and closed. Rung 4 is not started, and the
write-up is a separate task.

Summary of the whole ladder, validation then test:

| arm | terms | val PL loss | test P1_rank | test Brier_place |
|---|---|---|---|---|
| paper 2b, mlogit | 17 | 5.814307 | — | — |
| linear in torch | 26 | 5.811308 | — | — |
| paper 3, GBT | 24 | — | 0.00401388 | 0.20143009 |
| rung 1 MLP | 26 | 5.798597 | 0.00406876 | 0.20061520 |
| rung 2 MLP + embeddings | 23 + 3 | 5.841117 | not scored (lost) | not scored |
| rung 3 GRU + encoder | 18 + seq | 5.741720 | not scored (superseded) | not scored |
| **rung 3b GRU + encoder** | **19 + seq** | **5.718496** | **0.00432735** | **0.19741153** |

Only the two arms named in the task were scored on test. Rungs 2 and 3 were
not, and must not be scored later: the split has been used.
