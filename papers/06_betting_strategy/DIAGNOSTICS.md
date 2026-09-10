# Paper 6 — three diagnostic checks on the "Owen survived" result

**Standalone. Declares nothing, changes nothing.** The drafted paper, its
targets, `DECLARED_RULES.md` and the `_targets_p6` store are untouched; no
target was added or rebuilt. Everything below runs on the **validation slice
only** — the 1,505 races of `p5_scored_v7`, scored by paper 5's
fitting-partition rung-3b fit. No test row was scored. Where a figure quotes
the test split it is a number the pipeline already holds, read back, not
recomputed.

Three figures are written alongside this file
(`diagnostics_win_roi_surface.png`, `diagnostics_win_bets_surface.png`,
`diagnostics_roi_vs_price_band.png`). No `.qmd` references them, so they do
not enter the render.

Date: 2026-09-10. Branch `paper-6-redo`, at `dec9d1c`.

---

## Headline

The ledger is correct — an independent rebuild from the database reproduces
the validation figures to every printed digit, so the result is not an
arithmetic artefact. But **Owen's cell is not mid-slope. On the win market it
ranks 2nd of the 597 sweep cells that place at least 300 bets — the 99.8th
percentile — and 1st of 597 on each-way corrected terms.** The populated
surface has a median of −10.5%; Owen's cell returns +8.0%.

What dissolves the suspicion is not the ranking but the structure behind it:

1. Two thirds of the variance across populated cells is a declining function
   of the mean starting price the cell lands on (R² = 0.648 in a quadratic in
   log mean SP). The ratio threshold is a price-band dial, not a skill dial.
2. Owen's cell is a **+15.0 point positive residual** on that trend, and the
   residual is a **first-half-of-validation phenomenon**. Split the 1,505
   races at 2012-01-15: Owen ranks **1st of 617** populated cells in the first
   755 races (+22.6%) and **157th of 579** in the last 750 (−10.2%).
3. Relative to its own neighbourhood the peak is a plateau, not a spike: 21
   populated cells spanning P ∈ [0.12, 0.18] and ratio ∈ [1.20, 1.50] all sit
   within 5 points of Owen, and the true argmax (0.15 / 1.25) beats Owen by
   **0.11 points**.

And a separate finding, from check 2: **seven of the nine selection arms back
the identical horse in every race where they both bet.** The nine-arm search
contained three distinct horse-picking functions, not nine.

---

## Check 3 — is the validation ledger correct?

### 3a. The standing gate never touches the validation path

**`scripts/verify_p6_ledger.R` exercises the test path only. All six
assertions run against paper 5's test numbers. The validation path — the path
every declaration in paper 6 was made on — is ungated.**

Its three inputs are `p5_test_predictions`, `p5_qualifying_runners` and
`p5_test_backtests`; it builds one frame (`p6_build_bet_frame(pred, …)` on the
test predictions) and one settlement set, and every `stopifnot()` compares
against `p5_test_backtests` or paper 5's printed test figures. The
`p6_ledger_gate` target inside `_targets_p6.R` is the same check on the same
frame.

Two validation-side assertions do exist, and neither is an arithmetic check:
`p6_validation_predictions()` asserts the stored rung-3b validation PL loss
equals the published 5.718496 and that the rows are row-identical to
`p5_arm_data$val$key`; `p6_assert_search_set()` asserts zero overlap with the
test split and with the 3,517 fitting races. Both check *provenance*. Nothing
checked that the validation ledger's stakes, returns and ROI were right.

Check 3b below is that missing check, run once. It passes.

### 3b. Independent recompute from the source tables — no difference

Method: pull `finish_position`, `amended_position` and
`starting_price_decimal` straight from `historic_runners` for the 1,505
validation `race_id`s; derive the finishing position as
`coalesce(amended_position, finish_position)`, the winner as that equalling 1,
the implied probability as `1/SP` where `SP > 1`, and the market probability by
renormalising within race; join `win_model` from `p5_scored_v7` (the model's
own output — the one quantity that cannot be recomputed from raw data) and
apply the selection and settlement arithmetic in fresh code that calls no
`p6_*` function.

| arm | source | bets | wins | gross | ROI |
|---|---|---:|---:|---:|---:|
| S1/K0 win | paper 6 pipeline | 704 | 109 | 760.34 | +0.080028409 |
| S1/K0 win | independent | 704 | 109 | 760.34 | +0.080028409 |
| S0/K0 win | paper 6 pipeline | 1505 | 363 | 1401.32 | −0.068890363 |
| S0/K0 win | independent | 1505 | 363 | 1401.32 | −0.068890363 |

**Difference: exactly zero on both arms**, on bets, wins, gross return and
ROI. The two selected bet sets are identical as `(race_id, runner_id)` key
sets, not merely equal in count.

Row level, on all 13,674 frame rows:

| quantity | max absolute difference |
|---|---|
| `starting_price_decimal` | 0 |
| `win_market` | 0 |
| finishing position (mismatches) | 0 of 13,674 |
| `won` (mismatches) | 0 of 13,674 |

No blocker. The rest of the report is meaningful.

### 3c. Sanity checks on the validation ledger

**Probabilities sum to 1 within race.** Over 1,505 races the maximum absolute
deviation of `sum(win_model)` from 1 is 2.22e-16, both on `p5_scored_v7` and
on `p6_val_frame`. Same for `win_market`.

**Top-rated win rate is plausible, and lower than on test.**

| split | races | top-rated win rate | favourite win rate | mean top-rated `win_model` | mean top-rated SP | top-rated is favourite |
|---|---:|---:|---:|---:|---:|---:|
| validation | 1,505 | 0.2412 | 0.2817 | 0.2264 | 4.758 | 49.5% |
| test | 2,183 | 0.2744 | 0.3294 | 0.2294 | 4.333 | 50.3% |

The model is calibrated on both (mean top probability 0.226 / 0.229 against a
0.241 / 0.274 hit rate). The gap between splits is not the model: **the
market favourite also wins 4.8 points less often on validation than on test**
(28.2% vs 32.9%), and the mean top-rated price is 0.42 longer. The validation
window is a period in which shorter-priced horses won less. That fact returns
in check 1.

**No degeneracy, and none asymmetric between splits.**

| | validation | test |
|---|---:|---:|
| rows / races | 13,674 / 1,505 | 18,419 / 2,183 |
| missing SP | 0 | 0 |
| SP ≤ 1 | 0 | 0 |
| SP range | 1.17 – 151 | 1.25 – 151 |
| missing finishing position | 33 (0.24%) | 54 (0.29%) |
| zero finishing position | 0 | 0 |
| field size range | 4 – 16 | 4 – 16 |
| races with exactly one winner | 1,505 / 1,505 | 2,183 / 2,183 |
| missing race date | 0 | 0 |

The missing finishing positions are non-finishers; they settle as losers on
both splits, at the same rate.

**Price filtering is symmetric.** `p6_build_bet_frame()` drops rows with a
missing or non-positive `win_model` or `win_market`. On both splits it drops
**zero rows and zero races**, and no race is partially priced (some runners
kept, others lost):

| split | prediction rows / races | frame rows / races | rows dropped | races dropped | partially-priced races |
|---|---:|---:|---:|---:|---:|
| validation | 13,674 / 1,505 | 13,674 / 1,505 | 0 | 0 | 0 |
| test | 18,419 / 2,183 | 18,419 / 2,183 | 0 | 0 | 0 |

No asymmetry to report.

### 3d. The two headline ROIs, confirmed

| split | arm | bets | wins | ROI | 90% race-level bootstrap CI (B=2000, seed 42) |
|---|---|---:|---:|---:|---|
| validation | S1/K0 win | 704 | 109 | **+8.00%** | [−8.84%, +25.24%] |
| test | S1/K0 win | 1,064 | 131 | **−12.19%** | [−24.83%, +0.65%] |

Both are what the pipeline holds (`p6_val_incumbent`, `p6_test_results`). The
paper's +8.0% / −12.2% are correct.

The validation interval is 34 points wide. **The −20.2 point drop from
validation to test is comfortably inside a single arm's own sampling noise**
on 1,505 races.

---

## Check 2 — do the nine selection arms actually differ?

### 2a. Races selected and bets placed

At a flat stake every selected race is staked, and on the validation slice
neither the place nor the each-way settlement universe drops a row, so all
four bet columns place identically many bets.

| arm | rule | races selected | bets (win / place / e-w corrected) | share of 1,505 |
|---|---|---:|---:|---:|
| S0 | top-rated, every race | 1,505 | 1,505 | 100.0% |
| S1 | Owen: P>0.15, ratio>1.3 | 704 | 704 | 46.8% |
| S2a | top-rated, ratio ∈ [0.812, 1.335] | 753 | 753 | 50.0% |
| S2b | top-rated, ratio ∈ [0.856, 1.121] | 451 | 451 | 30.0% |
| S2c | top-rated, ratio ∈ [0.941, 1.247] | 451 | 451 | 30.0% |
| S3a | top-rated, SP ≤ 3.00 | 408 | 408 | 27.1% |
| S3b | top-rated, SP ≤ 4.00 | 771 | 771 | 51.2% |
| S3c | top-rated, SP ≤ 5.50 | 1,130 | 1,130 | 75.1% |
| S4 | market favourite, every race | 1,505 | 1,505 | 100.0% |

### 2b. Pairwise overlap — fraction backing the SAME horse

Of the races where both arms bet:

|      |    S0 |    S1 |   S2a |   S2b |   S2c |   S3a |   S3b |   S3c |    S4 |
|------|------:|------:|------:|------:|------:|------:|------:|------:|------:|
| S0   | 1.000 | 0.513 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 0.487 |
| S1   | 0.513 | 1.000 | 0.140 | 0.000 | 0.000 | 0.030 | 0.117 | 0.276 | 0.027 |
| S2a  | 1.000 | 0.140 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 0.490 |
| S2b  | 1.000 | 0.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 0.579 |
| S2c  | 1.000 | 0.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 0.435 |
| S3a  | 1.000 | 0.030 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 0.953 |
| S3b  | 1.000 | 0.117 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 0.805 |
| S3c  | 1.000 | 0.276 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 | 0.645 |
| S4   | 0.487 | 0.027 | 0.490 | 0.579 | 0.435 | 0.953 | 0.805 | 0.645 | 1.000 |

Races where both bet (the denominator):

|      |   S0 |  S1 | S2a | S2b | S2c | S3a | S3b |  S3c |   S4 |
|------|-----:|----:|----:|----:|----:|----:|----:|-----:|-----:|
| S0   | 1505 | 704 | 753 | 451 | 451 | 408 | 771 | 1130 | 1505 |
| S1   |  704 | 704 | 229 | 120 | 118 | 200 | 324 |  464 |  704 |
| S2a  |  753 | 229 | 753 | 451 | 451 | 165 | 403 |  646 |  753 |
| S2b  |  451 | 120 | 451 | 451 | 301 | 115 | 278 |  418 |  451 |
| S2c  |  451 | 118 | 451 | 301 | 451 |  77 | 212 |  378 |  451 |
| S3a  |  408 | 200 | 165 | 115 |  77 | 408 | 408 |  408 |  408 |
| S3b  |  771 | 324 | 403 | 278 | 212 | 408 | 771 |  771 |  771 |
| S3c  | 1130 | 464 | 646 | 418 | 378 | 408 | 771 | 1130 | 1130 |
| S4   | 1505 | 704 | 753 | 451 | 451 | 408 | 771 | 1130 | 1505 |

**The seven arms S0, S2a, S2b, S2c, S3a, S3b, S3c back the identical horse in
every race where any two of them bet — 1.000, exactly, across a 7×7 block.**
This is not a near-coincidence; it is structural. All seven are
`p6_top_rated()` followed by a race-level filter on `ratio` or on
`starting_price_decimal`. The filter decides *whether* to bet, never *which
horse*.

So the nine-arm search space contained **three distinct horse-picking
functions**: the model's top-rated horse (seven arms), Owen's
highest-`win_model`-among-qualifiers (S1, which agrees with the top-rated pick
in 51.3% of its races), and the market favourite (S4).

### 2c. S1 vs S0 — does the filter change the horse or the race?

| | |
|---|---:|
| races S0 bets | 1,505 |
| races S1 bets | 704 |
| races both bet | 704 |
| races S1 bets that S0 does not | 0 |
| races S0 bets that S1 does not | 801 |
| **fraction of the 704 common races backing the same horse** | **0.513** |
| races where the filter changes the horse | 343 |

**The filter does both, in roughly equal measure.** It changes which races are
bet in 801 of 1,505 (53%) and which horse is backed in 343 of the 704 it does
bet (49%). So the earlier reading — "most of the difference is which races,
not which horse" — is **not** what the data says for this pair. The mechanism:

| | races |
|---|---:|
| top-rated horse passes both filters | 361 |
| top-rated fails the ratio filter only | 958 |
| top-rated fails the probability filter only | 48 |
| top-rated fails both | 138 |
| races with at least one qualifier (S1 bets) | 704 |

In 343 of the 704 races S1 bets, the top-rated horse is disqualified (almost
always by `ratio ≤ 1.3`) and S1 drops to a lower-rated horse that clears it.
That is the one genuinely different horse-picker among the model arms — and
the consequence is a completely different price band.

### 2d. Starting price of the backed horse

| arm | n | min | q25 | median | q75 | max | mean SP | win rate | mean ratio | backed is top-rated | backed is favourite |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| S0 | 1505 | 1.17 | 3.00 | 4.00 | 5.50 | 34.0 | 4.76 | 0.241 | 1.136 | 100.0% | 49.5% |
| **S1** | **704** | **2.63** | **6.00** | **7.50** | **9.00** | **26.0** | **7.71** | **0.155** | **1.761** | **51.3%** | **2.8%** |
| S2a | 753 | 1.17 | 3.25 | 4.00 | 5.00 | 9.0 | 4.26 | 0.238 | 1.040 | 100.0% | 50.5% |
| S2b | 451 | 1.17 | 3.00 | 3.75 | 4.75 | 9.0 | 3.96 | 0.237 | 0.987 | 100.0% | 59.4% |
| S2c | 451 | 1.17 | 3.50 | 4.50 | 5.50 | 9.0 | 4.43 | 0.202 | 1.080 | 100.0% | 44.1% |
| S3a | 408 | 1.17 | 2.20 | 2.50 | 2.88 | 3.0 | 2.44 | 0.395 | 0.784 | 100.0% | 95.3% |
| S3b | 771 | 1.17 | 2.50 | 3.00 | 3.75 | 4.0 | 3.01 | 0.314 | 0.867 | 100.0% | 81.8% |
| S3c | 1130 | 1.17 | 2.75 | 3.50 | 4.50 | 5.5 | 3.63 | 0.278 | 0.953 | 100.0% | 65.6% |
| S4 | 1505 | 1.17 | 2.75 | 3.50 | 4.33 | 7.0 | 3.48 | 0.282 | 0.723 | 48.7% | 95.0% |

**S1's interquartile range [6.00, 9.00] does not overlap any other arm's.**
Eight arms bet a median price between 2.50 and 4.50; S1 bets 7.50. Its lower
quartile (6.00) is above the *upper* quartile of every other arm. **S1 is not
one of nine comparable rules — it is the only arm in its price band, and eight
of the other arms are crowded into the 2.5–4.5 band.**

Read as a search space: nine arms, three horse-pickers, and one arm alone in
the price band that this two-year window happened to reward.

---

## Check 1 — sweep Owen's own thresholds

36 probability thresholds (0.00 to 0.35 step 0.01) × 35 ratio thresholds (0.80
to 2.50 step 0.05) = **1,260 cells**, each scored on the validation slice at a
flat stake for win, place and each-way (corrected terms), at the real starting
price and at a zero-margin fair book. **597 cells place at least 300 bets**;
the rest are thin corner cells at high thresholds.

Owen's cell:

| bet | bets | wins | ROI at real SP | ROI at fair book |
|---|---:|---:|---:|---:|
| win | 704 | 109 | +8.00% | +23.44% |
| place | 704 | 326 | −3.84% | +10.09% |
| each-way (corrected) | 704 (1,382 units) | 250 | −3.08% | +9.05% |

### 1a. Best cell per bet type

Unconstrained, the argmax is a 3-bet corner cell in every case and means
nothing:

| bet | best cell (P / ratio) | ROI | bets | points above Owen |
|---|---|---:|---:|---:|
| win | 0.32 / 2.50 | +133.33% | 3 | +125.33 |
| place | 0.17 / 1.75 | +2.69% | 206 | +6.53 |
| each-way corrected | 0.32 / 2.50 | +75.00% | 3 | +78.08 |

Restricted to cells placing at least 300 validation bets, which is the only
version of the question that means anything:

| bet | best populated cell | ROI | bets | points above Owen |
|---|---|---:|---:|---:|
| win | 0.15 / **1.25** | +8.11% | 758 | **+0.11** |
| place | 0.12 / 1.50 | −0.42% | 769 | +3.42 |
| each-way corrected | **0.15 / 1.30 (Owen)** | −3.08% | 704 | **0.00** |

On win the best populated cell is Owen's, one ratio step lower, better by
one-tenth of a point. On each-way corrected terms Owen's cell *is* the argmax
of all 597.

### 1b. Owen's rank and percentile

| bet | ROI | rank of 1,260 | percentile | rank of 597 populated | percentile |
|---|---:|---:|---:|---:|---:|
| win | +8.00% | 164 | 87.1 | **2** | **99.8** |
| place | −3.84% | 126 | 90.1 | 114 | 81.1 |
| each-way corrected | −3.08% | 124 | 90.2 | **1** | **100.0** |

For context, the distribution over the 597 populated cells on the win market:
min −46.4%, q25 −25.8%, median −10.5%, q75 −4.6%, max +8.1%. **Owen's +8.0%
is above the 75th percentile by 12.6 points and above the median by 18.5.**

The all-cell percentiles (87–90) are misleading, because 122 of the 163 cells
that beat Owen on win place fewer than 300 bets. Reported both ways
deliberately.

### 1c. The surface

Figure: `diagnostics_win_roi_surface.png` (win ROI, fill clamped to
[−40, +20]% because the thin corner reaches +133%; the heavy black line is the
300-bet contour; the circle is Owen's cell). Companion:
`diagnostics_win_bets_surface.png` (bets per cell).

**Shape, in words: smooth, with a single interior peak inside the populated
region and a separate thin high-threshold corner that should be ignored.**
Lag-1 autocorrelation of cell ROI is 0.890 along the probability axis and
0.956 along the ratio axis, so it is not noise at the cell scale. Within the
populated region the dominant structure is a broad decline to the right and
downward: ROI falls as the ratio threshold rises past about 1.5 and as the
probability threshold falls below about 0.10. Owen's cell sits in a small
light-coloured island — the only positive-ROI region on the populated side of
the 300-bet line — roughly bounded by P ∈ [0.12, 0.18] and ratio ∈ [1.20,
1.50]. Everything outside it that still bets 300 times is negative.

Above the 300-bet line the surface breaks into a mottled patchwork with a
strongly positive top-right corner (P > 0.30, ratio > 2.2). That corner is 3
to 40 bets and is noise.

Plateau width around Owen, on the win market:

| tolerance | cells within it | of which ≥ 300 bets | P range | ratio range |
|---|---:|---:|---|---|
| 1 point | 169 | 4 | [0.15, 0.17] | [1.25, 1.45] |
| 2 points | 175 | 6 | [0.15, 0.17] | [1.25, 1.50] |
| 5 points | 199 | 21 | [0.12, 0.18] | [1.20, 1.50] |

So: **a sharp peak measured against the whole populated grid, a plateau
measured against its own neighbourhood.** Both statements are true and they
matter differently — see the conclusion.

The picture is the same at a zero-margin fair book, which rules out "Owen's
cell just pays less over-round": Owen's fair-book ROI of +23.44% also ranks
**2 of 597** populated cells, again behind only 0.15 / 1.25 (+23.49%).

### 1d. Owen's cell and its eight immediate neighbours (win)

| P | ratio | bets | wins | ROI | fair-book ROI |
|---:|---:|---:|---:|---:|---:|
| 0.14 | 1.25 | 885 | 128 | +0.51% | +15.10% |
| 0.14 | 1.30 | 827 | 116 | +0.40% | +15.07% |
| 0.14 | 1.35 | 755 | 97 | −3.18% | +10.98% |
| 0.15 | 1.25 | 758 | 121 | **+8.11%** | +23.49% |
| **0.15** | **1.30** | **704** | **109** | **+8.00%** | **+23.44%** |
| 0.15 | 1.35 | 642 | 90 | +2.95% | +17.65% |
| 0.16 | 1.25 | 645 | 106 | +6.43% | +21.39% |
| 0.16 | 1.30 | 598 | 96 | +7.33% | +22.49% |
| 0.16 | 1.35 | 544 | 80 | +3.58% | +18.19% |

**Owen's cell is a local peak in the ratio direction and on a slope in the
probability direction.** Seven of the eight neighbours are below it; the one
that beats it is 0.15 / 1.25, by 0.11 points. The step from P = 0.14 to
P = 0.15 is worth 7.6 points at fixed ratio: the 123 bets it removes won only
7 times (5.7%). That is a lumpy pocket of 123 bets, not a structural boundary
— which is a reminder that even the "smooth" part of this surface moves on
small groups of bets.

Slices through the cell:

| ratio held at 1.30, P varying | | | P held at 0.15, ratio varying | | |
|---|---:|---:|---|---:|---:|
| P | bets | ROI | ratio | bets | ROI |
| 0.00 | 1470 | −2.19% | 0.80 | 1213 | −5.02% |
| 0.05 | 1461 | −1.59% | 0.95 | 1101 | −2.19% |
| 0.10 | 1276 | +0.85% | 1.10 | 928 | −2.63% |
| 0.12 | 1054 | +3.64% | 1.20 | 812 | +5.17% |
| 0.14 | 827 | +0.40% | 1.25 | 758 | **+8.11%** |
| **0.15** | **704** | **+8.00%** | **1.30** | **704** | **+8.00%** |
| 0.17 | 505 | +5.91% | 1.40 | 591 | +3.78% |
| 0.20 | 307 | −3.96% | 1.50 | 483 | +3.74% |
| 0.25 | 143 | −19.34% | 1.60 | 408 | −5.56% |
| 0.30 | 70 | −8.80% | 1.90 | 220 | −16.82% |
| 0.35 | 28 | +37.82% | 2.50 | 60 | −1.67% |

Both dimensions have a genuine interior optimum, and Owen's values sit inside
it on both: probability rising through 0.10–0.18 helps and then hurts; ratio
rising through 1.20–1.50 helps and then hurts hard.

### 1e. How many cells beat Owen

| bet | cells beating Owen (of 1,260) | of those, ≥ 300 validation bets | of those, ≥ 300 *projected test* bets | best margin among ≥300-bet cells |
|---|---:|---:|---:|---:|
| win | 163 | **1** | 1 | +0.11 pts |
| place | 125 | 113 | 120 | +3.42 pts |
| each-way corrected | 123 | **0** | 0 | — |

On the win market and on each-way corrected terms, **widening the search from
nine arms to 1,260 cells of the same rule family would have changed the
declaration by at most 0.11 points, or not at all.** On place it would have
changed it — 113 populated cells beat Owen — but by no more than 3.4 points.

---

## Supporting analysis: what the surface is actually a function of

Two additional diagnostics, run because the ranking in 1b needed explaining.

### The ratio threshold is a price-band dial

At P = 0.15, raising the ratio threshold moves the backed horse monotonically
up the price ladder and monotonically away from the model's own top pick:

| ratio > | bets | mean SP | median SP | win rate | backed is favourite | backed is top-rated |
|---:|---:|---:|---:|---:|---:|---:|
| 0.80 | 1213 | 5.31 | 5.0 | 0.209 | 32.2% | 83.8% |
| 1.00 | 1059 | 6.11 | 5.5 | 0.179 | 15.4% | 67.6% |
| 1.20 | 812 | 7.21 | 7.0 | 0.159 | 4.4% | 54.6% |
| **1.30** | **704** | **7.71** | **7.5** | **0.155** | **2.8%** | **51.3%** |
| 1.50 | 483 | 8.69 | 8.5 | 0.130 | 0.8% | 46.4% |
| 1.80 | 268 | 10.12 | 10.0 | 0.090 | 0.4% | 42.9% |
| 2.20 | 120 | 12.24 | 12.0 | 0.083 | 0.0% | 30.8% |

Across the 597 populated cells, ROI correlates −0.785 with the mean SP the
cell backs, and a quadratic in log mean SP explains **R² = 0.648** of the
between-cell variance (figure `diagnostics_roi_vs_price_band.png`).

**So most of the surface is not about the model. It is about which price band
each threshold pair lands on.** Owen's cell lands on mean SP 7.71.

### The band that made the difference is 6–9, and only on validation

Observed win rate divided by mean implied probability, by SP band, all
runners:

| SP band | validation n | val. observed/implied | test n | test observed/implied |
|---|---:|---:|---:|---:|
| < 2 | 117 | 1.053 | 238 | 1.052 |
| 2–3 | 536 | 0.877 | 1,069 | 0.920 |
| 3–4 | 946 | 0.853 | 1,634 | 0.893 |
| 4–6 | 2,135 | 0.868 | 3,005 | 0.865 |
| **6–9** | **3,041** | **0.973** | **3,746** | **0.871** |
| 9–15 | 3,024 | 0.759 | 3,472 | 0.786 |
| 15+ | 3,875 | 0.671 | 5,255 | 0.632 |

**6–9 is the one band where validation is materially kinder than test** — 0.973
against 0.871, a 10-point gap, where every other band agrees within 4 points.
That is the band Owen's rule lives in (median SP 7.5).

S1's own validation ledger, by band:

| SP band | bets | win rate | ROI | fair-book ROI |
|---|---:|---:|---:|---:|
| < 4 | 39 | 0.282 | −2.54% | +8.92% |
| 4–6 | 169 | 0.178 | −6.61% | +5.62% |
| **6–9** | **363** | **0.154** | **+17.63%** | **+35.39%** |
| 9–15 | 124 | 0.097 | +10.89% | +26.29% |
| 15+ | 9 | 0.000 | −100.00% | −100.00% |

**All of S1's validation profit is in the 6–9 and 9–15 bands. It loses money
in every band below 6.** It is not one lucky price: dropping the single
largest return leaves +6.02%, and dropping the best three leaves +2.76%.

Splitting S1's bets by whether it backs the model's top-rated horse shows the
edge is not in the 343 races where the filter overrides the model either
(+6.41% on those, +9.51% on the 361 where it agrees) — the filter's
horse-switching is not the source.

### The peak does not survive halving the window

Split the 1,505 validation races at 2012-01-15 (755 / 750) and re-run the full
sweep on each half, ranking among cells that place at least 150 bets in that
half:

| half | races | Owen ROI | Owen bets | Owen rank | best cell | best ROI |
|---|---:|---:|---:|---:|---|---:|
| 2010-12-16 to 2012-01-15 | 755 | **+22.56%** | 391 | **1 of 617** | 0.15 / 1.30 (Owen) | +22.56% |
| 2012-01-16 to 2012-12-30 | 750 | **−10.18%** | 313 | **157 of 579** | 0.18 / 1.25 | +3.49% |

The surface's *shape* half-replicates — cell-ROI correlation across the two
halves is 0.641 (Spearman 0.630) over the 575 cells populated in both. Its
*peak* does not: Owen goes from first of 617 to 157th of 579, and the second
half has no positive cell above +3.5%.

Per-cell noise, for scale (race-level bootstrap, B = 2000, seed 42, on the
full 1,505):

| cell | bets | ROI | 90% CI |
|---|---:|---:|---|
| 0.15 / 1.30 (Owen) | 704 | +8.00% | [−8.84%, +25.24%] |
| 0.15 / 1.25 | 758 | +8.11% | [−8.08%, +24.10%] |
| 0.12 / 1.50 | 769 | −5.32% | [−22.82%, +12.39%] |
| 0.00 / 0.80 (bet every race) | 1505 | −6.04% | [−15.62%, +3.38%] |
| 0.15 / 1.70 | 328 | −17.89% | [−42.16%, +8.93%] |

A single populated cell's ROI carries a bootstrap standard error of about 10
points. Owen's excess over the fitted price-band trend is +15.0 points, about
**1.5 standard errors** — not distinguishable from zero. Its excess over the
populated median is 18.5 points, about 1.8 standard errors.

---

## What to conclude

**Not a ledger fault.** The independent rebuild from `historic_runners`
reproduces both validation ROIs to every digit, the bet sets match key for
key, probabilities normalise, prices and finishing positions are complete and
non-degenerate, and the price filtering is identical on the two splits. The
one real finding under check 3 is procedural: the standing gate covers only
the test path, so until this report the validation arithmetic — on which every
declaration in paper 6 rests — had never been checked against anything. It
checks out.

**Not the brief's "mid-slope" case either.** The brief anticipated Owen
sitting mid-slope with better cells a few points above. That is false on the
win market. Owen's cell ranks 2nd of 597 populated cells (99.8th percentile),
1st of 597 on each-way corrected terms, and the whole populated surface has a
median of −10.5% against Owen's +8.0%. The 1,260-cell sweep does not find a
better rule of this family: the argmax among cells that bet enough to matter
is one ratio step away and worth 0.11 points. **The nine-arm search was not
too narrow to find the peak on the win market. The peak is where the nine-arm
search said it was.** (On place it was too narrow — 113 populated cells beat
Owen, by up to 3.4 points. That single exception is the only place the
narrowness criticism lands.)

**But the peak has a mundane explanation, and the explanation is a warning
rather than a vindication.** Three findings, in the order they matter:

1. **The thresholds are a price-band dial, not a skill dial.** Two thirds of
   the between-cell variance in the populated region is a smooth declining
   function of the mean starting price the cell lands on. Raising the ratio
   threshold from 0.8 to 2.2 walks the backed horse from mean SP 5.31 to 12.24
   and drops the share that are the model's own top pick from 84% to 31%. The
   surface is mostly a map of the favourite–longshot bias, read at different
   prices.
2. **This particular two-year window paid the 6–9 band unusually well, and
   Owen's rule lives there.** Validation's 6–9 band returned 0.973 of implied
   against test's 0.871 — the only band where the two splits disagree by more
   than four points. S1's median price is 7.5, 363 of its 704 bets are in 6–9,
   and every one of its profitable bands is at 6 or above. The market
   favourite also won 4.8 points less often on validation than on test. This
   is a period effect, not a rule property, and it is sufficient on its own to
   explain a +8% that becomes −12% out of sample.
3. **The peak's location does not survive halving the window.** First half:
   Owen is 1st of 617 at +22.6%. Second half: 157th of 579 at −10.2%. The
   surface shape half-replicates (r = 0.64); the peak does not. Owen's excess
   over the price-band trend is 1.5 bootstrap standard errors — inside noise.

**So: is "Owen survived" an artefact?** No — the arithmetic is right, and the
argmax really is at Owen's cell. Is it evidence that Owen's thresholds are
right for 2006–2012 all-weather? Also no. The honest statement is narrower
than either: *on 1,505 races drawn from a two-year window whose 6–9 price band
paid ten points above its long-run rate, the threshold pair that concentrates
in that band won a search over 1,260 pairs, and the winner's margin over its
neighbours is a tenth of a point while its margin over the noise is 1.5
standard errors.* The declaration was correctly executed on a search set that
could not distinguish the candidates. The test result — −12.2%, with the same
rule's fair-book return at +0.84% — is what that looks like from the other
side.

Two further things worth stating plainly, neither of which the brief asked
about but both of which bear on the same question:

**The search had much less variety than nine arms implies.** Seven of the nine
selection rules are one horse-picking function (`p6_top_rated()`) behind seven
different race filters, and they agree on the backed horse in 100.0% of shared
races. The space contained three horse-pickers. Worse for the comparison, S1's
interquartile price range [6.00, 9.00] does not overlap any other arm's, and
eight of nine arms crowd into a median SP of 2.5–4.5. **S1 did not beat eight
comparable rivals; it was the only candidate standing in the band that this
window rewarded.** The 15-point win margin the paper reports is, structurally,
the return of the 6–9 band against the return of the 2.5–4.5 band on 1,505
races in 2011–2012.

**One thing this check cannot settle.** Whether the interior optimum in the
ratio dimension — real on both validation halves in *shape*, if not in height
— exists on the test split is unknowable without scoring test cells, which
would be exactly the selection-on-the-test-set failure the series has avoided
throughout. What can be said is that the mechanism behind an interior optimum
(some longshot tilt captures market bias; too much tilt lands on model error,
which is paper 4's finding) is not window-specific, so a plateau somewhere in
P ∈ [0.12, 0.18], ratio ∈ [1.20, 1.50] is a reasonable prior for any such
dataset. Owen chose round numbers inside that plateau on turf. Which cell
inside it wins a given 1,505-race sample is noise, and the margin says so.

---

## Reproducing this report

Read-only throughout; no target was built and no store written. The four
driver scripts are in the session scratchpad, not committed, because they are
one-off analysis in the manner of paper 4's `audit/` working files. Their
inputs are the built `_targets_p6` targets (`p6_val_frame`, `p6_val_settle`,
`p6_val_predictions`, `p6_selections_val`, `p6_stakings`, `p6_test_frame`,
`p6_val_incumbent`, `p6_test_results`, `p6_p5_scored_val`,
`p6_qualifying_runners`) plus one direct read of `historic_runners` for the
1,505 validation races. Everything in check 3b calls no `p6_*` function.

Two structural notes for anyone repeating this:

- **The validation ledger has no standing gate.** If any of this becomes
  load-bearing, `scripts/verify_p6_ledger.R` should gain the check 3b
  assertion — the validation S1/K0 win ROI against an independent recompute —
  so the validation path stops being ungated. Recorded here, not done, because
  editing the gate is a change to the paper's verification surface and this
  task was report-only.
- The DB read must run under PowerShell, not the Bash tool: `{RMariaDB}`
  crashes under Git Bash on this machine (CLAUDE.md, "Standing conventions").
