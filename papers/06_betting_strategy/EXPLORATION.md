# Paper 6 — exploratory ROI sweep, validation to test

**What this is.** An exploratory sweep of betting rules whose selections were made on a 1,505-race validation window and then scored once on 2,183 test races, with several rules read against that same test split — so whatever tops the test table is partly noise. There is no declaration rule, no bar to clear and no interval gating what reaches test; the intervals below are context and nothing is excluded on their basis. The purpose is to generate ideas to return to when betting goes live, not to test a hypothesis.

**Not published.** `docs/` is untouched and no Quarto paper is rendered.
The two previous drafts, both hypothesis-testing papers, are in
`SUPERSEDED/` with a README explaining why each was set aside.

The model is fixed throughout and nothing here refits anything: paper
5's rung-3b encoder, scored by its fitting-partition fit on the
validation slice and by its published full-training-split refit on the
test split.

---

## Setup

**Splits.** Validation 1,505 races / 13,674 runners; test 2,183 races / 18,419 runners. Race-id overlap between them: 0 (asserted zero). Overlap with the 3,517 races paper 5's fitting partition saw: 0 (asserted zero).

**Ledger gate.** `scripts/verify_p6_ledger.R` now carries seven
assertions, not six. Assertion 7 is new: the validation S1/K0 and
S0/K0 win ledgers rebuilt from `historic_runners` in code calling no
`p6_*` function, required to match the pipeline exactly on the bet set
as well as the arithmetic. Both previous drafts searched the validation
slice with that path unchecked. It passes.

**Sweep gate.** The sweep is a second implementation of the selection
and settlement arithmetic — index arithmetic rather than `dplyr` verbs,
because it scores 25,220 rule-by-bet combinations — so it is asserted
against `p6_ledger()` on three rules that exist in both:

| rule | ledger arm | bet | bets | sweep ROI | ledger ROI | abs ROI diff | same bet set |
|---|---|---|---|---|---|---|---|
| P5 / P>0.15, ratio>1.30 | S1/K0 | win | 704 | 0.080028409 | 0.080028409 | 0.0e+00 | TRUE |
| P1 / no filter | S0/K0 | win | 1505 | -0.068890363 | -0.068890363 | 0.0e+00 | TRUE |
| P2 / no filter | S4/K0 | win | 1505 | -0.130970096 | -0.130970096 | 0.0e+00 | TRUE |
| P5 / P>0.15, ratio>1.30 | S1/K0 | each-way (corrected terms) | 704 | -0.030752532 | -0.030752532 | 0.0e+00 | TRUE |
| P1 / no filter | S0/K0 | each-way (corrected terms) | 1505 | -0.092360369 | -0.092360369 | 0.0e+00 | TRUE |

**Pickers** — which horse, given a race worth betting. P1-P4 read the
whole field; only P5 reads the filter's cuts, because Owen's rule is
defined that way. Ties go to the lower `runner_id` throughout.

| picker | definition | reads the cuts |
|---|---|---|
| P1 | P1 highest model probability | no |
| P2 | P2 market favourite (shortest SP) | no |
| P3 | P3 highest model probability x SP (expected return) | no |
| P4 | P4 largest model minus market probability | no |
| P5 | P5 highest model probability among qualifiers (Owen) | yes |

**Filters** — which races to bet. A runner passes when `P_mod > p` and `P_mod/P_mkt > r`; a race is bet when at least one of its runners passes. The grid is p from 0.00 to 0.35 step 0.01 crossed with r from 0.80 to 2.50 step 0.05, plus a no-filter row that bets every race: **1,261 filters**, times 5 pickers, times 4 settlement tables = **25,220 scored combinations**, all at a flat stake.

**Staking is flat at stages 1 and 2 and gets its own stage 3.** In the
first draft the Kelly and edge-proportional rules staked zero wherever
the model probability did not exceed the price, which changed the bet
set as well as the stake and wrecked the comparison. Stage 3 reports the
share of selected races staked zero so that thinness is visible rather
than buried in an ROI.

**Mean backed price is on every table, and it is the column to read
first.** Across the previous sweep's populated cells, ROI correlated
−0.785 with the mean price the rule backs and a quadratic in log mean
price explained 65% of the between-rule variance (`DIAGNOSTICS.md`). A
rule's return is mostly a statement about the price band it bets in
unless the price column says otherwise. Nothing here controls for it.

---

## Stage 1 — sweep on validation

### Do the pickers actually differ?

Of the races where two pickers both bet, the fraction backing the same
horse. **A pair above 0.95 is one arm, not two.**

At no filter — all pickers bet all races:

|   | P1 | P2 | P3 | P4 | P5 |
|---|---|---|---|---|---|
| P1 | 1.000 | 0.487 | 0.090 | 0.247 | 1.000 |
| P2 | 0.487 | 1.000 | 0.007 | 0.028 | 0.487 |
| P3 | 0.090 | 0.007 | 1.000 | 0.544 | 0.090 |
| P4 | 0.247 | 0.028 | 0.544 | 1.000 | 0.247 |
| P5 | 1.000 | 0.487 | 0.090 | 0.247 | 1.000 |

At Owen's filter, `P > 0.15` and ratio `> 1.30`:

|   | P1 | P2 | P3 | P4 | P5 |
|---|---|---|---|---|---|
| P1 | 1.000 | 0.381 | 0.165 | 0.423 | 0.513 |
| P2 | 0.381 | 1.000 | 0.009 | 0.028 | 0.027 |
| P3 | 0.165 | 0.009 | 1.000 | 0.507 | 0.372 |
| P4 | 0.423 | 0.028 | 0.507 | 1.000 | 0.807 |
| P5 | 0.513 | 0.027 | 0.372 | 0.807 | 1.000 |

Common races behind those shares, at Owen's filter:

|   | P1 | P2 | P3 | P4 | P5 |
|---|---|---|---|---|---|
| P1 | 704 | 704 | 704 | 704 | 704 |
| P2 | 704 | 704 | 704 | 704 | 704 |
| P3 | 704 | 704 | 704 | 704 | 704 |
| P4 | 704 | 704 | 704 | 704 | 704 |
| P5 | 704 | 704 | 704 | 704 | 704 |

Worst case across the whole filter grid — the maximum agreement each
pair reaches at any filter with at least 300 common races, which is the
number that decides whether two pickers are really two:

| pair | filters compared | max agreement | at | min agreement | one arm, not two |
|---|---|---|---|---|---|
| P1 vs P2 | 598 | 0.575 | P>0.26, r>0.80 | 0.283 | no |
| P1 vs P3 | 598 | 0.272 | P>0.18, r>1.45 | 0.055 | no |
| P1 vs P4 | 598 | 0.635 | P>0.20, r>1.30 | 0.160 | no |
| P1 vs P5 | 598 | 1.000 | no filter | 0.060 | **YES** |
| P2 vs P3 | 598 | 0.033 | P>0.25, r>0.95 | 0.000 | no |
| P2 vs P4 | 598 | 0.111 | P>0.25, r>0.95 | 0.000 | no |
| P2 vs P5 | 598 | 0.541 | P>0.26, r>0.80 | 0.000 | no |
| P3 vs P4 | 598 | 0.759 | P>0.12, r>2.05 | 0.502 | no |
| P3 vs P5 | 598 | 0.920 | P>0.00, r>2.50 | 0.090 | no |
| P4 vs P5 | 598 | 0.947 | P>0.14, r>1.80 | 0.247 | no |

**No pair exceeds 0.95 at any filter with a cut in it.** The closest are P4 vs P5 at 0.947 and P3 vs P5 at 0.920. That is the thing the previous nine-arm set failed: seven of its nine arms agreed at 1.000 in every shared race, because they were one horse-picker behind seven race filters.

The 1.000 on P1 vs P5 is at the no-filter row only, and it is definitional: P5 picks the highest model probability among the runners passing the cuts, and with no cuts every runner passes, so P5 *is* P1 there. Away from that row the pair falls to a minimum of 0.060. It is listed rather than suppressed, but it is not a hidden duplicate.

The `n_both` matrix at Owen's filter is 704 in every cell, and that is the point of separating the two decisions: the filter fixes WHICH RACES are bet, so all five pickers bet the same 704 races and differ only in which horse they back in them.

### win — validation leaderboard

Top 15 rules by validation ROI at the real starting price, among
those placing at least 300 validation bets.

| rule | bets | wins | ROI | ROI fair | mean price | med price | fav share |
|---|---|---|---|---|---|---|---|
| P4 / P>0.15, ratio>1.50 | 483 | 63 | 10.68% | 26.33% | 9.32 | 9.00 | 0.8% |
| P1 / P>0.16, ratio>1.40 | 498 | 137 | 10.20% | 25.23% | 5.11 | 4.50 | 36.1% |
| P3 / P>0.15, ratio>1.70 | 328 | 25 | 10.01% | 26.20% | 17.63 | 12.00 | 0.3% |
| P4 / P>0.17, ratio>1.45 | 370 | 54 | 9.89% | 24.85% | 8.29 | 7.50 | 1.1% |
| P4 / P>0.17, ratio>1.50 | 334 | 49 | 9.60% | 24.78% | 8.30 | 8.00 | 1.2% |
| P4 / P>0.15, ratio>1.45 | 532 | 69 | 9.60% | 24.84% | 9.41 | 8.50 | 0.8% |
| P1 / P>0.17, ratio>1.40 | 412 | 112 | 8.72% | 23.02% | 5.17 | 5.00 | 33.5% |
| P4 / P>0.15, ratio>1.40 | 591 | 79 | 8.52% | 23.65% | 9.36 | 8.50 | 1.4% |
| P2 / P>0.10, ratio>2.25 | 311 | 118 | 8.29% | 24.18% | 3.10 | 3.00 | 98.4% |
| P1 / P>0.18, ratio>1.45 | 313 | 83 | 8.13% | 21.98% | 5.22 | 5.00 | 32.6% |
| P5 / P>0.15, ratio>1.25 | 758 | 121 | 8.11% | 23.49% | 7.46 | 7.00 | 3.4% |
| P1 / P>0.17, ratio>1.45 | 370 | 100 | 8.06% | 22.30% | 5.22 | 5.00 | 33.8% |
| P5 / P>0.15, ratio>1.30 | 704 | 109 | 8.00% | 23.44% | 7.71 | 7.50 | 2.8% |
| P1 / P>0.16, ratio>1.30 | 598 | 162 | 7.90% | 22.70% | 4.99 | 4.50 | 37.0% |
| P1 / P>0.16, ratio>1.35 | 544 | 146 | 7.89% | 22.72% | 5.08 | 4.50 | 35.5% |

Per picker: its best rule, and the median over all its rules placing
at least 300 bets — the median is what the picker is worth on average,
the best is what it is worth after the grid has been searched.

| picker | rows | best rule | best ROI | best bets | best mean price | median ROI | median mean price |
|---|---|---|---|---|---|---|---|
| P1 | 598 | P1 / P>0.16, ratio>1.40 | 10.20% | 498 | 5.11 | -5.69% | 4.91 |
| P2 | 598 | P2 / P>0.10, ratio>2.25 | 8.29% | 311 | 3.10 | -10.52% | 3.38 |
| P3 | 598 | P3 / P>0.15, ratio>1.70 | 10.01% | 328 | 17.63 | -39.24% | 24.09 |
| P4 | 598 | P4 / P>0.15, ratio>1.50 | 10.68% | 483 | 9.32 | -12.15% | 13.60 |
| P5 | 598 | P5 / P>0.15, ratio>1.25 | 8.11% | 758 | 7.46 | -10.33% | 10.61 |

### place — validation leaderboard

Top 15 rules by validation ROI at the real starting price, among
those placing at least 300 validation bets.

| rule | bets | wins | ROI | ROI fair | mean price | med price | fav share |
|---|---|---|---|---|---|---|---|
| P4 / P>0.17, ratio>1.45 | 370 | 173 | -0.09% | 13.99% | 8.29 | 7.50 | 1.1% |
| P3 / P>0.15, ratio>1.70 | 328 | 96 | -0.13% | 14.35% | 17.63 | 12.00 | 0.3% |
| P5 / P>0.12, ratio>1.50 | 769 | 285 | -0.42% | 14.80% | 10.48 | 10.00 | 0.5% |
| P5 / P>0.06, ratio>1.40 | 1391 | 460 | -0.69% | 15.50% | 12.57 | 11.00 | 0.5% |
| P5 / P>0.09, ratio>1.20 | 1418 | 572 | -0.77% | 15.17% | 9.38 | 8.50 | 2.5% |
| P5 / P>0.08, ratio>1.20 | 1456 | 581 | -0.88% | 15.09% | 9.60 | 8.50 | 2.5% |
| P5 / P>0.05, ratio>1.40 | 1412 | 462 | -0.99% | 15.23% | 12.84 | 11.00 | 0.5% |
| P5 / P>0.07, ratio>1.20 | 1475 | 584 | -1.00% | 14.96% | 9.74 | 9.00 | 2.4% |
| P5 / P>0.07, ratio>1.40 | 1359 | 455 | -1.02% | 15.01% | 12.22 | 11.00 | 0.5% |
| P5 / P>0.12, ratio>2.05 | 307 | 92 | -1.05% | 13.69% | 13.90 | 13.00 | 0.3% |
| P4 / P>0.12, ratio>1.80 | 479 | 160 | -1.23% | 13.77% | 12.23 | 12.00 | 0.4% |
| P5 / P>0.15, ratio>1.60 | 408 | 170 | -1.26% | 13.32% | 9.18 | 9.00 | 0.7% |
| P5 / P>0.12, ratio>1.60 | 666 | 235 | -1.26% | 13.84% | 11.12 | 11.00 | 0.5% |
| P4 / P>0.12, ratio>1.60 | 666 | 236 | -1.45% | 13.76% | 11.42 | 11.00 | 0.8% |
| P4 / P>0.15, ratio>1.55 | 434 | 177 | -1.46% | 13.11% | 9.53 | 9.00 | 0.7% |

Per picker: its best rule, and the median over all its rules placing
at least 300 bets — the median is what the picker is worth on average,
the best is what it is worth after the grid has been searched.

| picker | rows | best rule | best ROI | best bets | best mean price | median ROI | median mean price |
|---|---|---|---|---|---|---|---|
| P1 | 598 | P1 / P>0.16, ratio>1.55 | -5.18% | 358 | 5.37 | -14.13% | 4.91 |
| P2 | 598 | P2 / P>0.12, ratio>2.00 | -9.11% | 339 | 3.08 | -16.88% | 3.38 |
| P3 | 598 | P3 / P>0.15, ratio>1.70 | -0.13% | 328 | 17.63 | -22.63% | 24.09 |
| P4 | 598 | P4 / P>0.17, ratio>1.45 | -0.09% | 370 | 8.29 | -8.46% | 13.60 |
| P5 | 598 | P5 / P>0.12, ratio>1.50 | -0.42% | 769 | 10.48 | -9.30% | 10.61 |

### each-way (paper 5 terms) — validation leaderboard

Top 15 rules by validation ROI at the real starting price, among
those placing at least 300 validation bets.

| rule | bets | wins | ROI | ROI fair | mean price | med price | fav share |
|---|---|---|---|---|---|---|---|
| P4 / P>0.17, ratio>1.45 | 370 | 173 | 9.11% | 21.50% | 8.29 | 7.50 | 1.1% |
| P4 / P>0.17, ratio>1.50 | 334 | 150 | 6.80% | 19.10% | 8.30 | 8.00 | 1.2% |
| P5 / P>0.17, ratio>1.45 | 370 | 176 | 6.79% | 18.86% | 7.65 | 7.50 | 1.1% |
| P4 / P>0.17, ratio>1.40 | 412 | 191 | 6.57% | 18.59% | 8.27 | 7.50 | 1.7% |
| P4 / P>0.15, ratio>1.45 | 532 | 222 | 6.01% | 18.55% | 9.41 | 8.50 | 0.8% |
| P4 / P>0.15, ratio>1.50 | 483 | 197 | 5.77% | 18.50% | 9.32 | 9.00 | 0.8% |
| P1 / P>0.16, ratio>1.40 | 498 | 299 | 5.70% | 16.97% | 5.11 | 4.50 | 36.1% |
| P5 / P>0.16, ratio>1.30 | 598 | 287 | 5.50% | 17.60% | 7.36 | 7.00 | 3.3% |
| P5 / P>0.15, ratio>1.30 | 704 | 326 | 5.47% | 17.89% | 7.71 | 7.50 | 2.8% |
| P5 / P>0.17, ratio>1.40 | 412 | 200 | 5.44% | 17.25% | 7.44 | 7.00 | 1.7% |
| P5 / P>0.17, ratio>1.50 | 334 | 153 | 5.31% | 17.23% | 7.83 | 7.50 | 1.2% |
| P4 / P>0.15, ratio>1.55 | 434 | 177 | 5.25% | 17.98% | 9.53 | 9.00 | 0.7% |
| P1 / P>0.17, ratio>1.40 | 412 | 246 | 5.13% | 16.02% | 5.17 | 5.00 | 33.5% |
| P5 / P>0.17, ratio>1.30 | 505 | 250 | 5.09% | 16.78% | 6.97 | 6.50 | 3.8% |
| P5 / P>0.15, ratio>1.25 | 758 | 355 | 5.03% | 17.31% | 7.46 | 7.00 | 3.4% |

Per picker: its best rule, and the median over all its rules placing
at least 300 bets — the median is what the picker is worth on average,
the best is what it is worth after the grid has been searched.

| picker | rows | best rule | best ROI | best bets | best mean price | median ROI | median mean price |
|---|---|---|---|---|---|---|---|
| P1 | 598 | P1 / P>0.16, ratio>1.40 | 5.70% | 498 | 5.11 | -6.53% | 4.91 |
| P2 | 598 | P2 / P>0.10, ratio>2.25 | 4.96% | 311 | 3.10 | -8.94% | 3.38 |
| P3 | 598 | P3 / P>0.15, ratio>1.70 | 4.85% | 328 | 17.63 | -33.31% | 24.09 |
| P4 | 598 | P4 / P>0.17, ratio>1.45 | 9.11% | 370 | 8.29 | -11.57% | 13.60 |
| P5 | 598 | P5 / P>0.17, ratio>1.45 | 6.79% | 370 | 7.65 | -7.41% | 10.61 |

### each-way (corrected terms) — validation leaderboard

Top 15 rules by validation ROI at the real starting price, among
those placing at least 300 validation bets.

| rule | bets | wins | ROI | ROI fair | mean price | med price | fav share |
|---|---|---|---|---|---|---|---|
| P2 / P>0.10, ratio>2.25 | 311 | 209 | 3.35% | 14.90% | 3.10 | 3.00 | 98.4% |
| P2 / P>0.08, ratio>2.40 | 319 | 211 | 1.87% | 13.29% | 3.14 | 3.00 | 98.1% |
| P1 / P>0.16, ratio>1.40 | 498 | 255 | 1.36% | 12.74% | 5.11 | 4.50 | 36.1% |
| P1 / P>0.02, ratio>2.45 | 476 | 265 | 0.52% | 13.50% | 5.04 | 4.00 | 49.6% |
| P1 / P>0.00, ratio>2.45 | 477 | 265 | 0.31% | 13.26% | 5.04 | 4.00 | 49.7% |
| P1 / P>0.01, ratio>2.45 | 477 | 265 | 0.31% | 13.26% | 5.04 | 4.00 | 49.7% |
| P1 / P>0.06, ratio>2.45 | 383 | 211 | 0.20% | 12.89% | 5.15 | 4.33 | 48.0% |
| P1 / P>0.17, ratio>1.40 | 412 | 207 | 0.12% | 11.05% | 5.17 | 5.00 | 33.5% |
| P2 / P>0.07, ratio>2.40 | 360 | 235 | -0.19% | 11.24% | 3.23 | 3.13 | 97.8% |
| P1 / P>0.17, ratio>1.45 | 370 | 185 | -0.57% | 10.31% | 5.22 | 5.00 | 33.8% |
| P2 / P>0.10, ratio>2.20 | 341 | 225 | -0.59% | 10.43% | 3.12 | 3.00 | 98.2% |
| P2 / P>0.08, ratio>2.30 | 379 | 246 | -0.65% | 10.52% | 3.17 | 3.00 | 97.9% |
| P1 / P>0.17, ratio>1.50 | 334 | 165 | -0.68% | 10.30% | 5.31 | 5.00 | 33.5% |
| P2 / P>0.07, ratio>2.45 | 329 | 217 | -0.68% | 10.61% | 3.24 | 3.13 | 97.6% |
| P1 / P>0.16, ratio>1.35 | 544 | 274 | -0.75% | 10.43% | 5.08 | 4.50 | 35.5% |

Per picker: its best rule, and the median over all its rules placing
at least 300 bets — the median is what the picker is worth on average,
the best is what it is worth after the grid has been searched.

| picker | rows | best rule | best ROI | best bets | best mean price | median ROI | median mean price |
|---|---|---|---|---|---|---|---|
| P1 | 598 | P1 / P>0.16, ratio>1.40 | 1.36% | 498 | 5.11 | -8.76% | 4.91 |
| P2 | 598 | P2 / P>0.10, ratio>2.25 | 3.35% | 311 | 3.10 | -10.51% | 3.38 |
| P3 | 598 | P3 / P>0.15, ratio>1.70 | -6.20% | 328 | 17.63 | -39.43% | 24.09 |
| P4 | 598 | P4 / P>0.17, ratio>1.45 | -2.70% | 370 | 8.29 | -16.64% | 13.60 |
| P5 | 598 | P5 / P>0.15, ratio>1.30 | -3.08% | 704 | 7.71 | -14.62% | 10.61 |

Owen's own cell, and where it sits on each surface:

| bet | Owen ROI | Owen bets | Owen mean price | rank of | rank | percentile | rows beating it | best margin (pts) |
|---|---|---|---|---|---|---|---|---|
| win | 8.00% | 704 | 7.71 | 2990 | 13 | 99.6 | 12 | +2.68 |
| place | -3.84% | 704 | 7.71 | 2990 | 131 | 95.7 | 130 | +3.76 |
| each-way (paper 5 terms) | 5.47% | 704 | 7.71 | 2990 | 9 | 99.7 | 8 | +3.65 |
| each-way (corrected terms) | -3.08% | 704 | 7.71 | 2990 | 59 | 98.1 | 58 | +6.43 |

---

## Stage 2 — carry forward to test

Per bet type: the top 5 validation rows placing at least 300
validation bets, plus Owen's S1/K0, plus the market favourite in every
race, plus the best row from a picker other than the top row's — so at
least two pickers reach test. Coincident entries collapse to one rule
carrying every role it plays. Scored once on the test split.

### win

| rule | val ROI | test ROI | test 90% CI | val bets | test bets | test wins | val price | test price | test ROI fair | test ROI less top win | role |
|---|---|---|---|---|---|---|---|---|---|---|---|
| P4 / P>0.15, ratio>1.50 | 10.68% | -18.77% | [-34.0%, -3.2%] | 483 | 782 | 76 | 9.32 | 10.26 | -6.57% | -20.84% | validation top 1 |
| P1 / P>0.16, ratio>1.40 | 10.20% | -18.82% | [-28.8%, -9.4%] | 498 | 766 | 200 | 5.11 | 4.57 | -7.97% | -19.89% | validation top 2; best row from a picker other than P4 |
| P3 / P>0.15, ratio>1.70 | 10.01% | -5.99% | [-33.0%, 24.5%] | 328 | 534 | 37 | 17.63 | 20.66 | 7.45% | -15.38% | validation top 3 |
| P4 / P>0.17, ratio>1.45 | 9.89% | -19.48% | [-35.8%, -2.6%] | 370 | 589 | 65 | 8.29 | 8.90 | -8.14% | -21.56% | validation top 4 |
| P4 / P>0.17, ratio>1.50 | 9.60% | -21.63% | [-38.4%, -4.1%] | 334 | 549 | 57 | 8.30 | 9.00 | -10.55% | -23.86% | validation top 5 |
| P5 / P>0.15, ratio>1.30 | 8.00% | -12.19% | [-24.8%, 0.6%] | 704 | 1064 | 131 | 7.71 | 8.02 | 0.84% | -13.52% | S1/K0, Owen's rule (series comparator) |
| P2 / no filter | -13.10% | -6.36% | [-11.3%, -1.5%] | 1505 | 2183 | 719 | 3.48 | 3.15 | 8.42% | -6.59% | market favourite, every race (no model) |

### place

| rule | val ROI | test ROI | test 90% CI | val bets | test bets | test wins | val price | test price | test ROI fair | test ROI less top win | role |
|---|---|---|---|---|---|---|---|---|---|---|---|
| P4 / P>0.17, ratio>1.45 | -0.09% | -8.10% | [-15.4%, -0.6%] | 370 | 589 | 261 | 8.29 | 8.90 | 4.13% | -8.80% | validation top 1 |
| P3 / P>0.15, ratio>1.70 | -0.13% | 0.65% | [-14.9%, 17.1%] | 328 | 534 | 148 | 17.63 | 20.66 | 14.91% | -3.35% | validation top 2; best row from a picker other than P4 |
| P5 / P>0.12, ratio>1.50 | -0.42% | -8.04% | [-14.1%, -1.9%] | 769 | 1234 | 441 | 10.48 | 10.76 | 5.92% | -8.64% | validation top 3 |
| P5 / P>0.06, ratio>1.40 | -0.69% | -8.78% | [-14.1%, -3.4%] | 1391 | 2085 | 664 | 12.57 | 12.82 | 5.73% | -9.15% | validation top 4 |
| P5 / P>0.09, ratio>1.20 | -0.77% | -13.39% | [-17.6%, -9.1%] | 1418 | 2085 | 798 | 9.38 | 9.61 | 0.32% | -13.66% | validation top 5 |
| P5 / P>0.15, ratio>1.30 | -3.84% | -10.20% | [-15.7%, -4.6%] | 704 | 1064 | 475 | 7.71 | 8.02 | 2.74% | -10.70% | S1/K0, Owen's rule (series comparator) |
| P2 / no filter | -17.24% | -18.89% | [-21.1%, -16.7%] | 1505 | 2183 | 1453 | 3.48 | 3.15 | -6.04% | -18.96% | market favourite, every race (no model) |

### each-way (paper 5 terms)

| rule | val ROI | test ROI | test 90% CI | val bets | test bets | test wins | val price | test price | test ROI fair | test ROI less top win | role |
|---|---|---|---|---|---|---|---|---|---|---|---|
| P4 / P>0.17, ratio>1.45 | 9.11% | -6.70% | [-17.2%, 4.1%] | 370 | 589 | 261 | 8.29 | 8.90 | 3.50% | -7.94% | validation top 1 |
| P4 / P>0.17, ratio>1.50 | 6.80% | -7.39% | [-18.4%, 3.9%] | 334 | 549 | 240 | 8.30 | 9.00 | 2.75% | -8.72% | validation top 2 |
| P5 / P>0.17, ratio>1.45 | 6.79% | -0.28% | [-10.8%, 10.9%] | 370 | 589 | 274 | 7.65 | 8.06 | 10.95% | -1.51% | validation top 3; best row from a picker other than P4 |
| P4 / P>0.17, ratio>1.40 | 6.57% | -6.46% | [-16.4%, 3.8%] | 412 | 641 | 287 | 8.27 | 8.87 | 3.72% | -7.60% | validation top 4 |
| P4 / P>0.15, ratio>1.45 | 6.01% | -5.83% | [-15.4%, 3.7%] | 532 | 843 | 345 | 9.41 | 10.22 | 5.48% | -6.98% | validation top 5 |
| P5 / P>0.15, ratio>1.30 | 5.47% | -5.96% | [-14.0%, 2.0%] | 704 | 1064 | 475 | 7.71 | 8.02 | 5.10% | -6.76% | S1/K0, Owen's rule (series comparator) |
| P2 / no filter | -10.58% | -6.74% | [-10.1%, -3.5%] | 1505 | 2183 | 1453 | 3.48 | 3.15 | 3.82% | -6.88% | market favourite, every race (no model) |

### each-way (corrected terms)

| rule | val ROI | test ROI | test 90% CI | val bets | test bets | test wins | val price | test price | test ROI fair | test ROI less top win | role |
|---|---|---|---|---|---|---|---|---|---|---|---|
| P2 / P>0.10, ratio>2.25 | 3.35% | -6.31% | [-12.5%, -0.1%] | 311 | 554 | 365 | 3.10 | 2.77 | 4.16% | -6.90% | validation top 1 |
| P2 / P>0.08, ratio>2.40 | 1.87% | -8.16% | [-13.6%, -2.1%] | 319 | 675 | 433 | 3.14 | 2.87 | 2.23% | -8.64% | validation top 2 |
| P1 / P>0.16, ratio>1.40 | 1.36% | -19.96% | [-26.6%, -13.2%] | 498 | 766 | 365 | 5.11 | 4.57 | -11.35% | -20.67% | validation top 3; best row from a picker other than P2 |
| P1 / P>0.02, ratio>2.45 | 0.52% | -8.51% | [-14.3%, -2.3%] | 476 | 928 | 531 | 5.04 | 4.42 | 3.28% | -9.43% | validation top 4 |
| P1 / P>0.00, ratio>2.45 | 0.31% | -8.61% | [-14.4%, -2.4%] | 477 | 929 | 531 | 5.04 | 4.42 | 3.17% | -9.53% | validation top 5 |
| P5 / P>0.15, ratio>1.30 | -3.08% | -17.43% | [-25.7%, -8.8%] | 704 | 1064 | 325 | 7.71 | 8.02 | -6.89% | -18.27% | S1/K0, Owen's rule (series comparator) |
| P2 / no filter | -11.73% | -8.81% | [-12.3%, -5.4%] | 1505 | 2183 | 1325 | 3.48 | 3.15 | 2.06% | -8.96% | market favourite, every race (no model) |

### Validation rank against test rank

The number that matters for live use: whether picking on validation ROI
picks anything useful. Rank 1 is the best ROI within that bet type's
shortlist.

| bet | rule | val ROI | val rank | test ROI | test rank | rank move | val price | test price |
|---|---|---|---|---|---|---|---|---|
| each-way (paper 5 terms) | P4 / P>0.17, ratio>1.45 | 9.11% | 1 | -6.70% | 5 | +4 | 8.29 | 8.90 |
| each-way (paper 5 terms) | P4 / P>0.17, ratio>1.50 | 6.80% | 2 | -7.39% | 7 | +5 | 8.30 | 9.00 |
| each-way (paper 5 terms) | P5 / P>0.17, ratio>1.45 | 6.79% | 3 | -0.28% | 1 | -2 | 7.65 | 8.06 |
| each-way (paper 5 terms) | P4 / P>0.17, ratio>1.40 | 6.57% | 4 | -6.46% | 4 | +0 | 8.27 | 8.87 |
| each-way (paper 5 terms) | P4 / P>0.15, ratio>1.45 | 6.01% | 5 | -5.83% | 2 | -3 | 9.41 | 10.22 |
| each-way (paper 5 terms) | P5 / P>0.15, ratio>1.30 | 5.47% | 6 | -5.96% | 3 | -3 | 7.71 | 8.02 |
| each-way (paper 5 terms) | P2 / no filter | -10.58% | 7 | -6.74% | 6 | -1 | 3.48 | 3.15 |
| each-way (corrected terms) | P2 / P>0.10, ratio>2.25 | 3.35% | 1 | -6.31% | 1 | +0 | 3.10 | 2.77 |
| each-way (corrected terms) | P2 / P>0.08, ratio>2.40 | 1.87% | 2 | -8.16% | 2 | +0 | 3.14 | 2.87 |
| each-way (corrected terms) | P1 / P>0.16, ratio>1.40 | 1.36% | 3 | -19.96% | 7 | +4 | 5.11 | 4.57 |
| each-way (corrected terms) | P1 / P>0.02, ratio>2.45 | 0.52% | 4 | -8.51% | 3 | -1 | 5.04 | 4.42 |
| each-way (corrected terms) | P1 / P>0.00, ratio>2.45 | 0.31% | 5 | -8.61% | 4 | -1 | 5.04 | 4.42 |
| each-way (corrected terms) | P5 / P>0.15, ratio>1.30 | -3.08% | 6 | -17.43% | 6 | +0 | 7.71 | 8.02 |
| each-way (corrected terms) | P2 / no filter | -11.73% | 7 | -8.81% | 5 | -2 | 3.48 | 3.15 |
| place | P4 / P>0.17, ratio>1.45 | -0.09% | 1 | -8.10% | 3 | +2 | 8.29 | 8.90 |
| place | P3 / P>0.15, ratio>1.70 | -0.13% | 2 | 0.65% | 1 | -1 | 17.63 | 20.66 |
| place | P5 / P>0.12, ratio>1.50 | -0.42% | 3 | -8.04% | 2 | -1 | 10.48 | 10.76 |
| place | P5 / P>0.06, ratio>1.40 | -0.69% | 4 | -8.78% | 4 | +0 | 12.57 | 12.82 |
| place | P5 / P>0.09, ratio>1.20 | -0.77% | 5 | -13.39% | 6 | +1 | 9.38 | 9.61 |
| place | P5 / P>0.15, ratio>1.30 | -3.84% | 6 | -10.20% | 5 | -1 | 7.71 | 8.02 |
| place | P2 / no filter | -17.24% | 7 | -18.89% | 7 | +0 | 3.48 | 3.15 |
| win | P4 / P>0.15, ratio>1.50 | 10.68% | 1 | -18.77% | 4 | +3 | 9.32 | 10.26 |
| win | P1 / P>0.16, ratio>1.40 | 10.20% | 2 | -18.82% | 5 | +3 | 5.11 | 4.57 |
| win | P3 / P>0.15, ratio>1.70 | 10.01% | 3 | -5.99% | 1 | -2 | 17.63 | 20.66 |
| win | P4 / P>0.17, ratio>1.45 | 9.89% | 4 | -19.48% | 6 | +2 | 8.29 | 8.90 |
| win | P4 / P>0.17, ratio>1.50 | 9.60% | 5 | -21.63% | 7 | +2 | 8.30 | 9.00 |
| win | P5 / P>0.15, ratio>1.30 | 8.00% | 6 | -12.19% | 3 | -3 | 7.71 | 8.02 |
| win | P2 / no filter | -13.10% | 7 | -6.36% | 2 | -5 | 3.48 | 3.15 |

Rank agreement within each bet type's shortlist:

| bet | rules | Spearman | Pearson | mean abs rank move |
|---|---|---|---|---|
| each-way (paper 5 terms) | 7 | -0.143 | +0.183 | 2.57 |
| each-way (corrected terms) | 7 | +0.607 | +0.026 | 1.14 |
| place | 7 | +0.857 | +0.734 | 0.86 |
| win | 7 | -0.143 | -0.586 | 2.86 |

---

## Stage 3 — staking, separately

Held fixed: the selection. Varied: the stake. Per bet type, the single
best rule on the test split from stage 2, and Owen's, under all three
staking rules. `zero-stake share` is the fraction of the races the
selection picked where the staking rule puts nothing on — the column
that was missing when the first draft declared a Kelly arm that staked
in 122 of 1,353 selected test races.

| bet | rule | role |
|---|---|---|
| win | P3 / P>0.15, ratio>1.70 | best test rule from stage 2 |
| win | P5 / P>0.15, ratio>1.30 | S1/K0, Owen's rule |
| place | P3 / P>0.15, ratio>1.70 | best test rule from stage 2 |
| place | P5 / P>0.15, ratio>1.30 | S1/K0, Owen's rule |
| each-way (paper 5 terms) | P5 / P>0.15, ratio>1.30 | S1/K0, Owen's rule |
| each-way (paper 5 terms) | P5 / P>0.17, ratio>1.45 | best test rule from stage 2 |
| each-way (corrected terms) | P2 / P>0.10, ratio>2.25 | best test rule from stage 2 |
| each-way (corrected terms) | P5 / P>0.15, ratio>1.30 | S1/K0, Owen's rule |

On the **test** split:

| bet | rule | staking | races selected | bets | wins | total staked | mean stake | max stake | ROI | ROI fair | zero-stake share |
|---|---|---|---|---|---|---|---|---|---|---|---|
| win | P3 / P>0.15, ratio>1.70 | K0 | 534 | 534 | 37 | 534.0 | 1.000 | 1.00 | -5.99% | 7.45% | 0.0% |
| win | P3 / P>0.15, ratio>1.70 | K1 | 534 | 534 | 37 | 927.9 | 1.738 | 3.00 | -16.24% | -4.43% | 0.0% |
| win | P3 / P>0.15, ratio>1.70 | K2 | 534 | 534 | 37 | 231.8 | 0.434 | 1.37 | -18.72% | -7.39% | 0.0% |
| win | P5 / P>0.15, ratio>1.30 | K0 | 1064 | 1064 | 131 | 1064.0 | 1.000 | 1.00 | -12.19% | 0.84% | 0.0% |
| win | P5 / P>0.15, ratio>1.30 | K1 | 1064 | 1064 | 131 | 1759.8 | 1.654 | 3.00 | -15.81% | -3.50% | 0.0% |
| win | P5 / P>0.15, ratio>1.30 | K2 | 1064 | 1064 | 131 | 407.6 | 0.383 | 1.43 | -18.21% | -6.60% | 0.0% |
| place | P3 / P>0.15, ratio>1.70 | K0 | 534 | 534 | 148 | 534.0 | 1.000 | 1.00 | 0.65% | 14.91% | 0.0% |
| place | P3 / P>0.15, ratio>1.70 | K1 | 534 | 534 | 148 | 927.9 | 1.738 | 3.00 | -3.88% | 9.21% | 0.0% |
| place | P3 / P>0.15, ratio>1.70 | K2 | 534 | 534 | 148 | 231.8 | 0.434 | 1.37 | -3.70% | 9.17% | 0.0% |
| place | P5 / P>0.15, ratio>1.30 | K0 | 1064 | 1064 | 475 | 1064.0 | 1.000 | 1.00 | -10.20% | 2.74% | 0.0% |
| place | P5 / P>0.15, ratio>1.30 | K1 | 1064 | 1064 | 475 | 1759.8 | 1.654 | 3.00 | -10.67% | 1.89% | 0.0% |
| place | P5 / P>0.15, ratio>1.30 | K2 | 1064 | 1064 | 475 | 407.6 | 0.383 | 1.43 | -9.84% | 2.19% | 0.0% |
| each-way (paper 5 terms) | P5 / P>0.15, ratio>1.30 | K0 | 1064 | 1064 | 475 | 2128.0 | 2.000 | 2.00 | -5.96% | 5.10% | 0.0% |
| each-way (paper 5 terms) | P5 / P>0.15, ratio>1.30 | K1 | 1064 | 1064 | 475 | 3519.6 | 3.308 | 6.00 | -7.22% | 3.43% | 0.0% |
| each-way (paper 5 terms) | P5 / P>0.15, ratio>1.30 | K2 | 1064 | 1064 | 475 | 815.1 | 0.766 | 2.85 | -7.29% | 2.89% | 0.0% |
| each-way (paper 5 terms) | P5 / P>0.17, ratio>1.45 | K0 | 589 | 589 | 274 | 1178.0 | 2.000 | 2.00 | -0.28% | 10.95% | 0.0% |
| each-way (paper 5 terms) | P5 / P>0.17, ratio>1.45 | K1 | 589 | 589 | 274 | 2331.7 | 3.959 | 6.00 | -3.84% | 6.75% | 0.0% |
| each-way (paper 5 terms) | P5 / P>0.17, ratio>1.45 | K2 | 589 | 589 | 274 | 574.7 | 0.976 | 2.85 | -4.52% | 5.64% | 0.0% |
| each-way (corrected terms) | P2 / P>0.10, ratio>2.25 | K0 | 554 | 554 | 365 | 1084.0 | 1.957 | 2.00 | -6.31% | 4.16% | 0.0% |
| each-way (corrected terms) | P2 / P>0.10, ratio>2.25 | K1 | 554 | 13 | 6 | 13.0 | 1.000 | 2.92 | -37.87% | -31.87% | 97.7% |
| each-way (corrected terms) | P2 / P>0.10, ratio>2.25 | K2 | 554 | 6 | 2 | 0.4 | 0.068 | 0.15 | -57.10% | -53.66% | 98.9% |
| each-way (corrected terms) | P5 / P>0.15, ratio>1.30 | K0 | 1064 | 1064 | 325 | 2063.0 | 1.939 | 2.00 | -17.43% | -6.89% | 0.0% |
| each-way (corrected terms) | P5 / P>0.15, ratio>1.30 | K1 | 1064 | 1064 | 325 | 3379.7 | 3.176 | 6.00 | -20.08% | -10.00% | 0.0% |
| each-way (corrected terms) | P5 / P>0.15, ratio>1.30 | K2 | 1064 | 1064 | 325 | 775.8 | 0.729 | 2.85 | -21.61% | -11.99% | 0.0% |

On the **validation** slice, for reference:

| bet | rule | staking | races selected | bets | wins | total staked | mean stake | max stake | ROI | ROI fair | zero-stake share |
|---|---|---|---|---|---|---|---|---|---|---|---|
| win | P3 / P>0.15, ratio>1.70 | K0 | 328 | 328 | 25 | 328.0 | 1.000 | 1.00 | 10.01% | 26.20% | 0.0% |
| win | P3 / P>0.15, ratio>1.70 | K1 | 328 | 328 | 25 | 598.8 | 1.826 | 3.00 | -6.82% | 6.02% | 0.0% |
| win | P3 / P>0.15, ratio>1.70 | K2 | 328 | 328 | 25 | 154.8 | 0.472 | 2.48 | -6.16% | 6.31% | 0.0% |
| win | P5 / P>0.15, ratio>1.30 | K0 | 704 | 704 | 109 | 704.0 | 1.000 | 1.00 | 8.00% | 23.44% | 0.0% |
| win | P5 / P>0.15, ratio>1.30 | K1 | 704 | 704 | 109 | 1163.4 | 1.653 | 3.00 | 3.86% | 18.33% | 0.0% |
| win | P5 / P>0.15, ratio>1.30 | K2 | 704 | 704 | 109 | 275.3 | 0.391 | 2.48 | 2.66% | 16.43% | 0.0% |
| place | P3 / P>0.15, ratio>1.70 | K0 | 328 | 328 | 96 | 328.0 | 1.000 | 1.00 | -0.13% | 14.35% | 0.0% |
| place | P3 / P>0.15, ratio>1.70 | K1 | 328 | 328 | 96 | 598.8 | 1.826 | 3.00 | -8.85% | 3.70% | 0.0% |
| place | P3 / P>0.15, ratio>1.70 | K2 | 328 | 328 | 96 | 154.8 | 0.472 | 2.48 | -11.35% | 0.59% | 0.0% |
| place | P5 / P>0.15, ratio>1.30 | K0 | 704 | 704 | 326 | 704.0 | 1.000 | 1.00 | -3.84% | 10.09% | 0.0% |
| place | P5 / P>0.15, ratio>1.30 | K1 | 704 | 704 | 326 | 1163.4 | 1.653 | 3.00 | -6.06% | 7.25% | 0.0% |
| place | P5 / P>0.15, ratio>1.30 | K2 | 704 | 704 | 326 | 275.3 | 0.391 | 2.48 | -8.21% | 4.34% | 0.0% |
| each-way (paper 5 terms) | P5 / P>0.15, ratio>1.30 | K0 | 704 | 704 | 326 | 1408.0 | 2.000 | 2.00 | 5.47% | 17.89% | 0.0% |
| each-way (paper 5 terms) | P5 / P>0.15, ratio>1.30 | K1 | 704 | 704 | 326 | 2326.9 | 3.305 | 6.00 | 2.89% | 14.67% | 0.0% |
| each-way (paper 5 terms) | P5 / P>0.15, ratio>1.30 | K2 | 704 | 704 | 326 | 550.7 | 0.782 | 4.96 | 1.66% | 12.86% | 0.0% |
| each-way (paper 5 terms) | P5 / P>0.17, ratio>1.45 | K0 | 370 | 370 | 176 | 740.0 | 2.000 | 2.00 | 6.79% | 18.86% | 0.0% |
| each-way (paper 5 terms) | P5 / P>0.17, ratio>1.45 | K1 | 370 | 370 | 176 | 1481.7 | 4.004 | 6.00 | 3.48% | 14.90% | 0.0% |
| each-way (paper 5 terms) | P5 / P>0.17, ratio>1.45 | K2 | 370 | 370 | 176 | 375.1 | 1.014 | 4.96 | 1.96% | 12.82% | 0.0% |
| each-way (corrected terms) | P2 / P>0.10, ratio>2.25 | K0 | 311 | 311 | 209 | 612.0 | 1.968 | 2.00 | 3.35% | 14.90% | 0.0% |
| each-way (corrected terms) | P2 / P>0.10, ratio>2.25 | K1 | 311 | 14 | 8 | 9.5 | 0.679 | 2.35 | 40.21% | 56.75% | 95.5% |
| each-way (corrected terms) | P2 / P>0.10, ratio>2.25 | K2 | 311 | 2 | 1 | 0.6 | 0.319 | 0.47 | 88.36% | 103.94% | 99.4% |
| each-way (corrected terms) | P5 / P>0.15, ratio>1.30 | K0 | 704 | 704 | 250 | 1382.0 | 1.963 | 2.00 | -3.08% | 9.05% | 0.0% |
| each-way (corrected terms) | P5 / P>0.15, ratio>1.30 | K1 | 704 | 704 | 250 | 2271.9 | 3.227 | 6.00 | -6.58% | 4.86% | 0.0% |
| each-way (corrected terms) | P5 / P>0.15, ratio>1.30 | K2 | 704 | 704 | 250 | 534.7 | 0.760 | 4.96 | -8.36% | 2.49% | 0.0% |

---

## What looks worth trying live

**Nothing in this sweep is profitable at the settled starting price.** Of the 28 rule-by-bet-type combinations that reached the test split, 1 returned a positive ROI at real prices: P3 / P>0.15, ratio>1.70 on place, 0.65% (90% CI [-14.9%, 17.1%]). Everything below is therefore a candidate for a *different price*, not a candidate as it stands — which is the same conclusion papers 1 to 5 reached about the model and is why the fair-book column is the one that carries the information here.

### 1. Back the market favourite, every race, and get a better price

`P2 / no filter` — no model input at all. Test win ROI -6.36% on 2,183 bets, and **8.42% at a zero-margin book**, the highest fair-book win figure of any rule that reached test, ahead of the best model rule's 7.45% and Owen's 0.84%. Mean backed price 3.15.

**What the price column says.** Mean price 3.15; 95.3% of bets sit on the shortest-priced runner as the frame ranks it, the shortfall from 100% being joint favourites broken a different way by the two tie-breaks. This is the favourite-longshot bias and nothing else: short-priced horses win more often than their over-round-adjusted implied probability, so the rule is profitable at fair odds and loses approximately the over-round at real ones. It looked good for a reason that has nothing to do with the model, and it was the WORST rule on the validation slice (-13.10%, rank 7 of 7) — it reached test only because the brief carried the market-favourite control forward unconditionally.

**Why it is still the strongest live candidate.** It needs no model edge — only a price better than the bookmaker's settled SP. That is exactly the Betfair convergence thesis in the project's longer-term direction: early prices are noisy and drift toward fair value as liquidity builds, so a rule whose entire loss is the over-round is the one that a better entry price can flip. It is also the cheapest thing to paper-trade, because it requires no model in the loop.

### 2. P3 / P>0.15, ratio>1.70, on the place market

`P3 / P>0.15, ratio>1.70` — the P3 picker. It is the **only positive test ROI in the sweep**: 0.65% on 534 place bets, 90% CI [-14.9%, 17.1%], and 14.91% at a fair book. The same rule is also the best win-market rule on test (-5.99% against Owen's -12.19%), with a fair-book win figure of 7.45%.

**What the price column says, and it is a warning.** Mean backed price 20.66 on test (17.63 on validation), median 15.00, 0.0% of bets on the favourite. This rule bets the extreme top of the price ladder — 37 wins in 534 win bets, a 6.9% strike rate. Maximising model probability times price maximises expected return, and on a market with a longshot bias that resolves to "back the longest price the model does not hate". The place market is where that actually paid, which is mechanically sensible: a 20-to-1 shot that runs third pays a place return without ever needing to win, so the rule collects on the part of its edge that does not require the tail event. The interval is the widest in the sweep and spans zero on both markets.

**What to do with it.** Worth paper-trading on the place market, at a small stake and with the strike rate watched rather than the ROI — a rule this concentrated in the tail needs a long run before its ROI means anything. Its win-market showing is a weaker version of the same thing and is not separately interesting.

### 3. A tighter Owen filter, on each-way — but check the terms

`P5 / P>0.17, ratio>1.45` is the best each-way rule on paper 5's terms: test ROI -0.28% on 589 bets, 10.95% at a fair book, mean price 8.06 — effectively breakeven at real prices, against Owen's -5.96% on the same terms. It is Owen's own picker with both cuts raised.

**The catch is the terms, not the price.** Paper 5's each-way settlement pays one fifth the odds on a top-three finish whatever the field size, which is not the market for a small-field handicap. Under the corrected industry ladder the same rule's advantage does not survive: the best corrected-terms rule is `P2 / P>0.10, ratio>2.25` at -6.31%, and Owen's own each-way falls from -5.96% on paper 5's terms to -17.43% on corrected ones. **Read the near-breakeven each-way figure as a property of the synthetic terms.** Any live each-way trial has to be priced on the corrected ladder from the start.

### 4. What is not worth trying

**Picking a rule by validation ROI, on the win market.** The five best validation win rules returned between 9.6% and 10.7% on validation and between -6.0% and -21.6% on test — a reversal of about 29 points on the top row. The best validation rule (`P4 / P>0.15, ratio>1.50`, 10.68%) came 4 of 7 on test. Rank agreement within the win shortlist is Spearman -0.143 and Pearson -0.586: validation ROI carries no usable information about test ROI on the win market, and mildly negative information on the linear scale. `DIAGNOSTICS.md` explains why — the validation window's 6-9 price band paid about ten points above its long-run rate, so the rules that window rewards are the ones betting that band, and every top-five validation win rule has a mean price between 5.1 and 17.6.

**But it is not uniformly useless.** On the place market rank agreement is Spearman +0.857 with a mean absolute rank move of 0.86, against 2.86 on win — validation ROI selects usefully there and not on win. The place market's returns depend on a top-three finish rather than a win, so they rest on far more events per race and are correspondingly less sample-driven. If one market is worth searching on a held-out window, it is the place market.

**Non-flat staking.** Of the 32 non-flat arms scored across the two splits, 29 return less than their own flat-stake counterpart. 1 of them beat flat staking on a bet set that was not collapsed, and the margin is trivial: P5 / P>0.15, ratio>1.30 under K2 on place, -9.8% (test split), +0.4 points on 407.6 units across 1064 staked races of 1064 selected. Read that as no difference. The remaining 2 show a positive-looking ROI only because the staking rule threw the bet set away: P2 / P>0.10, ratio>2.25 under K1 on each-way (corrected terms), 40.2% (validation split), +36.9 points on 9.5 units across 14 staked races of 311 selected; P2 / P>0.10, ratio>2.25 under K2 on each-way (corrected terms), 88.4% (validation split), +85.0 points on 0.6 units across 2 staked races of 311 selected. An ROI computed on that many units is not a staking result and should not be read as one. Two mechanisms, both visible in the stage-3 table. Where the selection already requires the model probability to exceed the price — any rule with a ratio cut above 1 — the zero-stake share is 0.0% and the staking rules simply lever up the identical bet set, so a negative ROI becomes more negative. Where the selection does not (the market-favourite rules, whose backed horse the model usually rates below the market), the stake collapses instead:

| bet | rule | staking | races selected | races staked | zero-stake share | total staked | ROI |
|---|---|---|---|---|---|---|---|
| each-way (corrected terms) | P2 / P>0.10, ratio>2.25 | K1 | 554 | 13 | 97.7% | 13.0 | -37.87% |
| each-way (corrected terms) | P2 / P>0.10, ratio>2.25 | K2 | 554 | 6 | 98.9% | 0.4 | -57.10% |

That is the first draft's failure reproduced exactly: K1 stakes 13 of 554 selected races and its ROI is computed on 13.0 units. It is not a staking result, it is a different and much smaller bet set, and an ROI on it means nothing.

### Summary

| idea | test evidence | mean price | why it looked good | verdict |
|---|---|---|---|---|
| Market favourite, every race, better entry price | win -6.4% real, 8.4% fair | 3.15 | favourite-longshot bias; loss is the over-round | **paper-trade first** |
| P3 / P>0.15, ratio>1.70, place market | place 0.6% real, 14.9% fair | 20.66 | bets the top of the price ladder; place leg collects without the win | **paper-trade, small** |
| P5 / P>0.17, ratio>1.45, each-way | -0.3% real, 10.9% fair on paper 5 terms | 8.06 | generous synthetic terms, not the real ladder | re-price on corrected terms before trying |
| Select a rule on validation ROI (win market) | Spearman -0.14, mean rank move 2.9 | 5.1 - 17.6 | the validation window's 6-9 band overpaid | no — search the place market instead |
| Kelly or edge-proportional staking | 29 of 32 non-flat arms worse than flat | — | leverage on a losing edge, or a collapsed bet set | no |

