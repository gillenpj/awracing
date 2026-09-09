# P5-DIAG — ROI intervals, and encoder diagnostics

Run 2026-09-07 on branch `paper5-encoder`. Two pieces: bootstrap intervals
on the closed test backtest, and descriptive diagnostics of the encoder on
the validation slice.

**No model was refitted or rescored on the test split.** The ROI work reads
stored predictions and paper 3's stored bet inputs. The encoder diagnostics
run entirely on the validation slice.

---

# TASK 1 — ROI intervals

## 1.1 What was stored, and what had to be re-derived

`p5_test_backtests` stored only the one-row summaries — `n_bets`, `roi`,
`profit` and so on. **The per-race stake and return were not stored**, and a
paired race-level bootstrap needs them.

They were re-derived, not refitted:

- **rung 1 and rung 3b** — from `p5_test_predictions`, the stored test
  predictions, through the same chain the backtest used:
  `compute_model_market_ratio_p2()` → `build_value_bet_runners()` →
  `single_bet_units()`. Every step is a deterministic function of scores
  that already exist. No model was refitted and no test row rescored.
- **paper 3** — read directly from its own stored main-store targets
  (`model_market_ratio_3_win`, `value_bets_place_3`,
  `value_bets_eachway_3`). Nothing recomputed at all.

`p5_roi_units_check` asserts the re-derived units reproduce the published
point ROIs and bet counts **exactly**, so the intervals attach to the same
bets P5_TEST_REPORT.md published:

| arm | bet | stored ROI | re-derived ROI | difference | bet-count difference |
|---|---|---|---|---|---|
| all nine rows | | | | **0** | **0** |

## 1.2 Method

The structure of the series' `bootstrap_roi_difference()` — resample the
common race universe, each arm contributing its own stake and return on each
drawn race, a race the arm did not bet contributing zero — applied to the
**single-bet** rule. B = 2000, seed 42, 90% intervals, 2,183 common races.

`bootstrap_roi_difference()` could not be reused directly: it recomputes
bets internally under the naive **multi-bet** rule (`n_bets = n()` per
race), which is a different backtest from the one the paper reports.
Resampling races rather than bets is what preserves the pairing — the arms
bet on overlapping but different sets of races.

## 1.3 Results

| contrast | bet | ROI a | ROI b | difference | 90% interval | excludes zero |
|---|---|---|---|---|---|---|
| rung 3b − rung 1 | win | −12.19% | −19.36% | +7.16 pts | [−4.77, +18.23] | no |
| rung 3b − rung 1 | place | −10.20% | −7.52% | −2.68 pts | [−8.61, +3.05] | no |
| rung 3b − rung 1 | each-way | −5.96% | −8.38% | +2.42 pts | [−5.41, +9.76] | no |
| rung 3b − paper 3 | win | −12.19% | −22.31% | +10.11 pts | [−3.96, +23.34] | no |
| rung 3b − paper 3 | place | −10.20% | −14.02% | +3.83 pts | [−2.01, +10.11] | no |
| rung 3b − paper 3 | each-way | −5.96% | −13.47% | +7.51 pts | [−1.27, +16.33] | no |
| rung 1 − paper 3 | win | −19.36% | −22.31% | +2.95 pts | [−7.01, +12.82] | no |
| **rung 1 − paper 3** | **place** | **−7.52%** | **−14.02%** | **+6.51 pts** | **[+1.65, +11.38]** | **YES** |
| rung 1 − paper 3 | each-way | −8.38% | −13.47% | +5.09 pts | [−1.19, +11.63] | no |

## 1.4 Your expectation was right where it matters, and one interval breaks it

**Eight of the nine intervals contain zero**, and they are as wide as you
expected — roughly ±5 to ±14 points. In particular:

> **The headline ROI improvements are not distinguishable from zero.** Rung
> 3b's +10.11 points over paper 3 on win ROI carries an interval of
> [−3.96, +23.34]. Its +7.16 points over rung 1 carries [−4.77, +18.23].
> Neither can be told from no improvement at all.

That is the number the paper must report alongside the point estimate.
A 10-point ROI difference on ~1,100 single bets, where the payoff is a ~7×
return landing on about 12% of them, simply does not resolve at this sample
size.

**One interval excludes zero, and it is flagged here rather than left in the
table:**

> **rung 1 (MLP) − paper 3 (GBT), place ROI: +6.51 points, 90% interval
> [+1.65, +11.38].**

Three things about it, and I would not build a headline on it:

1. **It is not the paper's model.** Rung 3b is. The contrast that excludes
   zero involves rung 1, the MLP control, against paper 3. Rung 3b's own
   ROI contrasts all contain zero — including its place contrast against
   paper 3 (+3.83, [−2.01, +10.11]), which is a *smaller* point estimate
   than rung 1's on the same comparison.
2. **It is one of nine intervals, with no multiplicity control**, and none
   was pre-registered. Nine 90% intervals under a global null would produce
   at least one exclusion more often than not. This is the kind of finding
   that needs to be stated as what it is: a single interval out of nine, not
   a tested claim.
3. **It is a smaller loss, not a profit.** −7.52% against −14.02%. Both arms
   lose money. Nothing here is a betting result.

So: the first ROI interval in the series to exclude zero, yes — and worth
recording. But it belongs in the results as a noted exception with its
multiplicity caveat attached, not as the paper's headline. If it were to be
promoted, the honest route is a pre-registered test on a fresh sample, and
the test split is now closed.

---

# TASK 2 — Encoder diagnostics, validation slice only

**Descriptive. No intervals are attached and none of this is a tested
claim.** These describe the question — new information, or a better
representation of the same information — rather than settling it.

## 2.0 Recovering the encoder, and checking it is the right one

`p5_fit_gru()` returns scores, not the module, so the hidden states could not
be read out of anything stored. The selected configuration (h32/L1/dropout
0.3, lr 1e-3) was retrained on the fitting partition with the same seed for
the 3 epochs validation selected, and then checked before anything was read
off it:

| check | max abs difference | n |
|---|---|---|
| refit scores match the stored arm's validation scores | **0** | 13,674 |

Exactly zero, not merely within tolerance. Feeding the extracted 32-dimension
states back through the arm's own MLP reproduces the stored validation scores
bit for bit, which confirms two things at once: the refit is the same model,
and the states extracted here are the ones the arm's forward pass used.

## 2a. Feature recovery — can the encoder's output reconstruct what it replaced?

Ordinary least squares of each removed feature on the 32 encoder dimensions,
validation rows, complete cases.

| removed feature | R² | n | missing |
|---|---|---|---|
| `pos_lag1_zero` | **0.668** | 13,674 | 0 |
| `pos_lag2_zero` | **0.428** | 13,674 | 0 |
| `pos_lag1_nonzero` | 0.285 | 13,674 | 0 |
| `going_sr_shrunk` | 0.213 | 13,611 | 63 |
| `pos_lag2_nonzero` | 0.194 | 13,674 | 0 |
| `going_runs_prior` | 0.183 | 13,648 | 26 |
| `has_wins` | 0.140 | 13,674 | 0 |
| `going_sr_delta` | 0.029 | 13,611 | 63 |

**Reference scale.** Three terms rung 3b *kept*, which the encoder was never
required to encode, regressed the same way:

| kept feature | R² |
|---|---|
| `or_relative` | 0.123 |
| `days_LTO_log` | 0.099 |
| `trainerSR` | 0.087 |

These sit at 0.09–0.12 simply because a 32-dimension summary of a horse's
history correlates with most things about that horse. That is the floor
against which the table above should be read.

**What this describes.** Only one removed feature is substantially
recovered: `pos_lag1_zero`, whether the horse ran at all last time, at 0.668.
Its two-runs-back counterpart follows at 0.428. Everything else is between
0.03 and 0.29, and three of the eight — `has_wins`, `going_runs_prior`,
`going_sr_delta` — sit at or near the 0.09–0.12 floor set by terms the
encoder never had to represent. `going_sr_delta`, the going-affinity term
paper 3 built specifically for this, is at 0.029, *below* the floor.

The most striking row is `pos_lag1_nonzero` at 0.285: the horse's actual
finishing position last time out is literally channel 1 of the sequence's
most recent slot, and a linear read of the encoder's output recovers less
than a third of its variance.

**The caveat that governs all of it: these are linear R².** A low value
means the feature is not *linearly* recoverable from the 32 dimensions, not
that the information is absent — a GRU state is free to hold it in a form no
regression will find. The table is therefore evidence that the encoder is
**not** a linear re-encoding of the summaries it replaced; it is not evidence
about what else it is doing.

Read narrowly, that leans toward "carrying something else" rather than
"better representation of the same thing". Read honestly, it does not settle
it, and the report should not claim it does.

## 2b. Sequence length — how much history does the gain need?

Same configuration, same grid position, same seed, same slice, 60 epochs.
Only the number of prior runs the encoder can see changes.
`career_runs_prior` stays untruncated at every length, as it is at 20.

| prior runs | mean length (fit) | % at the cap | best val PL loss | best epoch | gain over rung 1 | share of the full gain |
|---|---|---|---|---|---|---|
| 5 | 4.78 | 88.1% | 5.721239 | 3 | +0.077358 | **96.6%** |
| 10 | 8.54 | 67.7% | 5.720594 | 3 | +0.078004 | 97.4% |
| 15 | 11.46 | 53.0% | 5.719584 | 3 | +0.079013 | 98.6% |
| 20 | 13.77 | 41.8% | 5.718496 | 3 | +0.080102 | 100.0% |

> **96.6% of the encoder's advantage over rung 1 survives with only the five
> most recent prior runs.**

The improvement from 5 to 20 runs is monotone but tiny: 0.002743 in total,
against the 0.080102 the encoder gains over rung 1. Going from 5 to 20 runs
— quadrupling the history the encoder can read — buys 3.4% of the effect.

Paper 3 sees two prior runs. On this evidence the encoder's gain is
overwhelmingly about the **first few runs in raw form**, not about how runs
relate across a long span. The long tail of a career is nearly free to
discard: the plateau starts by five.

Two things this does not say. It does not say the sequence is worth nothing
past five — the direction is consistent and monotone, just small. And it
does not identify *what* about those five runs matters, only that depth
beyond them is not where the gain lives.

## 3. Backend

| device | CUDA | torch | libtorch | threads |
|---|---|---|---|---|
| cpu | FALSE | 0.17.0 | 2.8.0 | 4 |

Unchanged and asserted, as for every rung.

## 4. Runtime and provenance

| | wall clock |
|---|---|
| sequence-length refits (3 × 60 epochs) | 12m 36s |
| encoder refit and hidden-state extraction | 19s |
| ROI unit derivation | 23s |
| ROI bootstraps (9 × 2000) | 6s |
| **total** | **13m 33s** |

9 targets built, 125 skipped. `tar_outdated()` was checked before the run:
only the nine new diagnostic targets were outstanding, no rung-3 or rung-3b
target was invalidated, and the test-split fits were untouched. New code
lives in `R/p5_diagnostics.R`; `R/p5_gru.R` was not edited, per the standing
convention.

## 5. Where this stops

Nothing here is a tested claim about the encoder, and nothing here reopens
the test split. Rung 4 is not started; the write-up is a separate task.
