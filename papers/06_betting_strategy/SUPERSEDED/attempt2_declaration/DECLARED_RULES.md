# Paper 6 — declared betting rules

**Frozen before any test target was built.** Nothing in this file may be
altered after the commit that introduced it. Every number below is from
the validation slice alone.

## 0. The search set

Paper 5's validation slice: 13,674 runner-rows over 1,505 races, carved
out of the training period at 2010-12-15. The 3,517 fitting races are
not used: the model was fitted on them and memorised them.

Overlap with the test split: 0 races. Overlap with the fitting
partition: 0 races. Rows dropped for want of a usable price: 0.

The search set is scored by the **fitting-partition** fit, which never saw
these races. The test split is scored by the **full-training-split**
refit, the model paper 5 published. Two fits of one architecture:

| fit | scores | training races | config | epochs | validation PL loss | source |
|---|---|---|---|---|---|---|
| fitting partition | validation slice (the search set) | 3517 | 5 | 3 | 5.718496 | p5_scored_v7 / p5_rung3b_selected |
| full training split | test split | 5022 | 5 | 3 | — | p5_test_predictions |

Their score distributions differ in scale, so every candidate threshold
below is a within-split quantile rather than an absolute number:

| split | races | median P_mod | median ratio | median SP | share with positive Kelly edge |
|---|---|---|---|---|---|
| validation | 1505 | 0.2083 | 1.0281 | 4.00 | 37.1% |
| test | 2183 | 0.2192 | 0.9509 | 3.75 | 31.0% |

| split | quantity | S1 threshold | quantile it sits at | share of top-rated passing |
|---|---|---|---|---|
| validation | P_mod | 0.1500 | 12.4% | 87.6% |
| validation | P_mod / P_mkt | 1.3000 | 72.8% | 27.2% |
| test | P_mod | 0.1500 | 8.5% | 91.5% |
| test | P_mod / P_mkt | 1.3000 | 77.7% | 22.3% |

## 1. The declaration

Two stages, because selection and staking are two questions and a single
grid confounds them.

**Stage A — selection, at a flat stake.** All nine selection rules at K0.
Comparator S1/K0.

**Stage B — staking, on the declared selection only.** K0, K1 and K2 on
whatever stage A declared. Comparator: that selection at K0.

Each stage varies exactly one term against its comparator, asserted in
code by `p6_assert_one_difference()`.

Within a stage, and with no judgement at any step: among **eligible**
candidates take the highest validation ROI at the real starting price;
paired race-level bootstrap (B = 2000, seed 42) of its ROI difference
against the stage comparator on their common races; declare it only if
the point difference exceeds one bootstrap standard error of the
difference, otherwise declare the comparator. Ties on ROI to four
decimals prefer the lower-numbered selection arm, then K0 over K1 over
K2.

| stage | bet type | declared | top eligible candidate | candidate ROI | comparator ROI | paired difference | bootstrap SE | exceeds one SE | eligible candidates |
|---|---|---|---|---|---|---|---|---|---|
| A | win | S1/K0 | S1/K0 | 8.00% | 8.00% | 0.00% | — | no | 9 |
| A | place | S1/K0 | S1/K0 | -3.84% | -3.84% | 0.00% | — | no | 9 |
| A | each-way (corrected terms) | S1/K0 | S1/K0 | -3.08% | -3.08% | 0.00% | — | no | 9 |
| B | win | S1/K0 | S1/K0 | 8.00% | 8.00% | 0.00% | — | no | 3 |
| B | place | S1/K0 | S1/K0 | -3.84% | -3.84% | 0.00% | — | no | 3 |
| B | each-way (corrected terms) | S1/K0 | S1/K0 | -3.08% | -3.08% | 0.00% | — | no | 3 |

The each-way declaration runs on the **corrected** place terms, and its
comparator is recomputed on those same terms. Paper 5's flat
one-fifth-top-three terms are reported alongside throughout but declare
nothing.

## 2. Eligibility

Two conditions, both applied **before** the argmax rather than after it:

1. projected test bets >= 300, where projected = validation bets
   placed x (test races / validation races). Would the arm bet often
   enough on test for the result to mean anything?
2. the arm places a positive stake in at least 60% of the races its
   selection rule selects. K1 and K2 stake zero where the model
   probability does not exceed the price, which makes them selection
   rules as well as staking rules; this is the direct guard.

No candidate was struck from either stage's pool.

Stage A runs at K0, where every selected race is staked by construction,
and stage B runs on whatever stage A declared, so the gate can strike
nothing in either pool without being inert. The diagnostic below applies
the same gate to the full nine-by-three cross-product on the validation
slice, to show what it would strike. **Nothing in the declaration reads
it**: the declaration is passed the stage grids, never this one.

| arm | races selected | bets placed | staked share | projected test bets | ROI (SP) | eligible | struck because |
|---|---|---|---|---|---|---|---|
| S0/K0 | 1505 | 1505 | 100.0% | 2183 | -6.89% | yes | — |
| S0/K1 | 1505 | 802 | 53.3% | 1163 | -1.68% | no | stakes too few of its selected races |
| S0/K2 | 1505 | 559 | 37.1% | 811 | 0.27% | no | stakes too few of its selected races |
| S1/K0 | 704 | 704 | 100.0% | 1021 | 8.00% | yes | — |
| S1/K1 | 704 | 704 | 100.0% | 1021 | 3.86% | yes | — |
| S1/K2 | 704 | 704 | 100.0% | 1021 | 2.66% | yes | — |
| S2a/K0 | 753 | 753 | 100.0% | 1092 | -9.07% | yes | — |
| S2a/K1 | 753 | 426 | 56.6% | 618 | -3.90% | no | stakes too few of its selected races |
| S2a/K2 | 753 | 183 | 24.3% | 265 | -0.63% | no | too few projected test bets; stakes too few of its selected races |
| S2b/K0 | 451 | 451 | 100.0% | 654 | -15.28% | yes | — |
| S2b/K1 | 451 | 200 | 44.3% | 290 | 5.65% | no | too few projected test bets; stakes too few of its selected races |
| S2b/K2 | 451 | 14 | 3.1% | 20 | -9.95% | no | too few projected test bets; stakes too few of its selected races |
| S2c/K0 | 451 | 451 | 100.0% | 654 | -18.39% | yes | — |
| S2c/K1 | 451 | 350 | 77.6% | 508 | -20.81% | yes | — |
| S2c/K2 | 451 | 107 | 23.7% | 155 | -50.43% | no | too few projected test bets; stakes too few of its selected races |
| S3a/K0 | 408 | 408 | 100.0% | 592 | -8.09% | yes | — |
| S3a/K1 | 408 | 63 | 15.4% | 91 | 14.61% | no | too few projected test bets; stakes too few of its selected races |
| S3a/K2 | 408 | 30 | 7.4% | 44 | 21.23% | no | too few projected test bets; stakes too few of its selected races |
| S3b/K0 | 771 | 771 | 100.0% | 1118 | -13.23% | yes | — |
| S3b/K1 | 771 | 205 | 26.6% | 297 | -14.96% | no | too few projected test bets; stakes too few of its selected races |
| S3b/K2 | 771 | 102 | 13.2% | 148 | -14.85% | no | too few projected test bets; stakes too few of its selected races |
| S3c/K0 | 1130 | 1130 | 100.0% | 1639 | -9.35% | yes | — |
| S3c/K1 | 1130 | 441 | 39.0% | 640 | -11.45% | no | stakes too few of its selected races |
| S3c/K2 | 1130 | 237 | 21.0% | 344 | -11.30% | no | stakes too few of its selected races |
| S4/K0 | 1505 | 1505 | 100.0% | 2183 | -13.10% | yes | — |
| S4/K1 | 1505 | 166 | 11.0% | 241 | -9.01% | no | too few projected test bets; stakes too few of its selected races |
| S4/K2 | 1505 | 59 | 3.9% | 86 | 4.04% | no | too few projected test bets; stakes too few of its selected races |

(Win market shown; the other three settlement columns select the same
races and differ only in what a bet returns.)

## 3. The reproduction gate

Paper 5's test ledger, rebuilt through paper 6's ledger function under
S1/K0 and paper 5's each-way terms, against the encoder rows of paper 5's
`p5_test_backtests`:

| bet | p6 bets | p5 bets | p6 wins | p5 wins | p6 profit | p5 profit | ROI difference |
|---|---|---|---|---|---|---|---|
| win | 1064 | 1064 | 131 | 131 | -129.75 | -129.75 | 0.0e+00 |
| place | 1064 | 1064 | 475 | 475 | -108.51 | -108.51 | 0.0e+00 |
| eachway | 1064 | 1064 | 475 | 475 | -126.83 | -126.83 | 0.0e+00 |

## 4. Each-way terms

Races with four to seven runners: 29.4% of the validation slice, 39.0% of
the test split. The threshold is 10%, so the terms are corrected.
Correcting only the four-to-seven band would leave the twelve-and-up band
wrong as well, so the full industry handicap ladder is used: win-only at
four runners; a quarter the odds on the first two from five to seven; a
fifth on the first three from eight to eleven; a quarter on the first
three from twelve to fifteen; a quarter on the first four from sixteen.
Paper 5's terms differ from these on 50.5% of validation races.

## 5. The candidates

| rule | definition |
|---|---|
| S0 | S0 — model's top-rated horse, every race |
| S1 | S1 — Owen: P_mod > 0.15 and P_mod/P_mkt > 1.3, highest P_mod |
| S2a | S2a — top-rated, ratio in [q25, q75] = [0.812, 1.335] |
| S2b | S2b — top-rated, ratio in [q30, q60] = [0.856, 1.121] |
| S2c | S2c — top-rated, ratio in [q40, q70] = [0.941, 1.247] |
| S3a | S3a — top-rated, SP <= q25 = 3.00 |
| S3b | S3b — top-rated, SP <= q50 = 4.00 |
| S3c | S3c — top-rated, SP <= q75 = 5.50 |
| S4 | S4 — market favourite, every race, no model input |
| K0 | K0 — flat, 1 unit |
| K1 | K1 — (P_mod - P_mkt) / 0.05, capped at 3 units |
| K2 | K2 — quarter-Kelly at P_mod against SP / 0.05, capped at 3 units |

Quantile cuts, taken over the model's top-rated horse in each of the
1,505 validation races: ratio q25 0.812, q30 0.856, q40 0.941, q60 1.121,
q70 1.247, q75 1.335; starting price q25 3.00, q50 4.00, q75 5.50.
The same quantiles are recomputed on the test split from its own
distribution, so a declared rule selects the same fraction of races there.

## 6. Stage A — every selection rule at a flat stake, validation slice

| selection | staking | bet | races selected | bets placed | staked share | projected test bets | wins | ROI (SP) | ROI (fair book) | mean stake | sd unit return | max drawdown | eligible | struck because |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| S0 | K0 | win | 1505 | 1505 | 100.0% | 2183 | 363 | -6.89% | 7.34% | 1.000 | 1.915 | 150.8 | yes | — |
| S0 | K0 | place | 1505 | 1505 | 100.0% | 2183 | 846 | -14.73% | -1.48% | 1.000 | 0.860 | 222.2 | yes | — |
| S0 | K0 | each-way (paper 5 terms) | 1505 | 1505 | 100.0% | 2183 | 846 | -7.51% | 3.27% | 2.000 | 1.226 | 258.6 | yes | — |
| S0 | K0 | each-way (corrected terms) | 1505 | 1505 | 100.0% | 2183 | 765 | -9.24% | 1.85% | 1.970 | 1.273 | 301.7 | yes | — |
| S1 | K0 | win | 704 | 704 | 100.0% | 1021 | 109 | 8.00% | 23.44% | 1.000 | 2.679 | 48.6 | yes | — |
| S1 | K0 | place | 704 | 704 | 100.0% | 1021 | 326 | -3.84% | 10.09% | 1.000 | 1.117 | 54.9 | yes | — |
| S1 | K0 | each-way (paper 5 terms) | 704 | 704 | 100.0% | 1021 | 326 | 5.47% | 17.89% | 2.000 | 1.684 | 67.9 | yes | — |
| S1 | K0 | each-way (corrected terms) | 704 | 704 | 100.0% | 1021 | 250 | -3.08% | 9.05% | 1.963 | 1.768 | 121.7 | yes | — |
| S2a | K0 | win | 753 | 753 | 100.0% | 1092 | 179 | -9.07% | 4.96% | 1.000 | 1.756 | 98.9 | yes | — |
| S2a | K0 | place | 753 | 753 | 100.0% | 1092 | 427 | -18.00% | -5.46% | 1.000 | 0.768 | 136.0 | yes | — |
| S2a | K0 | each-way (paper 5 terms) | 753 | 753 | 100.0% | 1092 | 427 | -9.73% | 0.69% | 2.000 | 1.132 | 164.6 | yes | — |
| S2a | K0 | each-way (corrected terms) | 753 | 753 | 100.0% | 1092 | 379 | -11.66% | -0.90% | 1.961 | 1.178 | 193.7 | yes | — |
| S2b | K0 | win | 451 | 451 | 100.0% | 654 | 107 | -15.28% | -2.20% | 1.000 | 1.623 | 69.7 | yes | — |
| S2b | K0 | place | 451 | 451 | 100.0% | 654 | 262 | -20.01% | -7.68% | 1.000 | 0.719 | 90.7 | yes | — |
| S2b | K0 | each-way (paper 5 terms) | 451 | 451 | 100.0% | 654 | 262 | -13.31% | -3.48% | 2.000 | 1.052 | 121.0 | yes | — |
| S2b | K0 | each-way (corrected terms) | 451 | 451 | 100.0% | 654 | 226 | -16.06% | -5.91% | 1.951 | 1.097 | 142.3 | yes | — |
| S2c | K0 | win | 451 | 451 | 100.0% | 654 | 91 | -18.39% | -5.34% | 1.000 | 1.725 | 102.4 | yes | — |
| S2c | K0 | place | 451 | 451 | 100.0% | 654 | 233 | -23.38% | -11.53% | 1.000 | 0.788 | 105.9 | yes | — |
| S2c | K0 | each-way (paper 5 terms) | 451 | 451 | 100.0% | 654 | 233 | -17.60% | -7.81% | 2.000 | 1.125 | 170.3 | yes | — |
| S2c | K0 | each-way (corrected terms) | 451 | 451 | 100.0% | 654 | 198 | -20.40% | -10.34% | 1.962 | 1.163 | 195.4 | yes | — |
| S3a | K0 | win | 408 | 408 | 100.0% | 592 | 161 | -8.09% | 4.48% | 1.000 | 1.183 | 41.8 | yes | — |
| S3a | K0 | place | 408 | 408 | 100.0% | 592 | 306 | -19.22% | -7.94% | 1.000 | 0.475 | 78.6 | yes | — |
| S3a | K0 | each-way (paper 5 terms) | 408 | 408 | 100.0% | 592 | 306 | -6.05% | 2.76% | 2.000 | 0.761 | 61.0 | yes | — |
| S3a | K0 | each-way (corrected terms) | 408 | 408 | 100.0% | 592 | 275 | -8.40% | 0.80% | 1.922 | 0.827 | 74.0 | yes | — |
| S3b | K0 | win | 771 | 771 | 100.0% | 1118 | 242 | -13.23% | -0.73% | 1.000 | 1.352 | 109.2 | yes | — |
| S3b | K0 | place | 771 | 771 | 100.0% | 1118 | 527 | -18.45% | -6.62% | 1.000 | 0.573 | 143.4 | yes | — |
| S3b | K0 | each-way (paper 5 terms) | 771 | 771 | 100.0% | 1118 | 527 | -9.32% | -0.16% | 2.000 | 0.871 | 151.2 | yes | — |
| S3b | K0 | each-way (corrected terms) | 771 | 771 | 100.0% | 1118 | 466 | -12.60% | -3.23% | 1.948 | 0.929 | 191.1 | yes | — |
| S3c | K0 | win | 1130 | 1130 | 100.0% | 1639 | 314 | -9.35% | 4.19% | 1.000 | 1.582 | 130.6 | yes | — |
| S3c | K0 | place | 1130 | 1130 | 100.0% | 1639 | 702 | -18.13% | -5.84% | 1.000 | 0.675 | 205.4 | yes | — |
| S3c | K0 | each-way (paper 5 terms) | 1130 | 1130 | 100.0% | 1639 | 702 | -8.59% | 1.38% | 2.000 | 1.020 | 212.8 | yes | — |
| S3c | K0 | each-way (corrected terms) | 1130 | 1130 | 100.0% | 1639 | 631 | -10.91% | -0.68% | 1.964 | 1.064 | 250.9 | yes | — |
| S4 | K0 | win | 1505 | 1505 | 100.0% | 2183 | 424 | -13.10% | -0.21% | 1.000 | 1.490 | 228.5 | yes | — |
| S4 | K0 | place | 1505 | 1505 | 100.0% | 2183 | 950 | -17.24% | -4.48% | 1.000 | 0.671 | 260.9 | yes | — |
| S4 | K0 | each-way (paper 5 terms) | 1505 | 1505 | 100.0% | 2183 | 950 | -10.58% | -0.91% | 2.000 | 0.965 | 354.9 | yes | — |
| S4 | K0 | each-way (corrected terms) | 1505 | 1505 | 100.0% | 2183 | 880 | -11.73% | -1.72% | 1.970 | 1.000 | 381.7 | yes | — |

### Stage A, paired against S1/K0 on common races

| selection | bet | difference vs S1/K0 | bootstrap SE | 90% interval | common races |
|---|---|---|---|---|---|
| S0 | win | -3.03% | 9.08% | [-18.02%, 11.63%] | 704 |
| S0 | place | -7.27% | 3.57% | [-13.32%, -1.43%] | 704 |
| S0 | each-way (paper 5 terms) | -4.60% | 5.68% | [-13.73%, 4.61%] | 704 |
| S0 | each-way (corrected terms) | 0.33% | 5.99% | [-9.08%, 10.05%] | 704 |
| S1 | win | 0.00% | 0.00% | [0.00%, 0.00%] | 704 |
| S1 | place | 0.00% | 0.00% | [0.00%, 0.00%] | 704 |
| S1 | each-way (paper 5 terms) | 0.00% | 0.00% | [0.00%, 0.00%] | 704 |
| S1 | each-way (corrected terms) | 0.00% | 0.00% | [0.00%, 0.00%] | 704 |
| S2a | win | -12.79% | 22.91% | [-49.92%, 24.50%] | 229 |
| S2a | place | -16.40% | 8.98% | [-30.85%, -1.02%] | 229 |
| S2a | each-way (paper 5 terms) | -12.91% | 14.24% | [-35.59%, 10.18%] | 229 |
| S2a | each-way (corrected terms) | -3.36% | 15.22% | [-28.29%, 21.10%] | 229 |
| S2b | win | -35.55% | 35.80% | [-94.55%, 22.83%] | 120 |
| S2b | place | -26.88% | 12.88% | [-47.94%, -6.00%] | 120 |
| S2b | each-way (paper 5 terms) | -30.00% | 21.82% | [-66.71%, 5.56%] | 120 |
| S2b | each-way (corrected terms) | -15.97% | 23.81% | [-55.16%, 22.62%] | 120 |
| S2c | win | -20.93% | 32.94% | [-78.74%, 30.94%] | 118 |
| S2c | place | -16.23% | 13.00% | [-38.55%, 4.32%] | 118 |
| S2c | each-way (paper 5 terms) | -16.94% | 20.66% | [-51.69%, 15.23%] | 118 |
| S2c | each-way (corrected terms) | -6.18% | 22.19% | [-43.28%, 28.61%] | 118 |
| S3a | win | 19.66% | 21.46% | [-16.76%, 53.78%] | 200 |
| S3a | place | -19.65% | 8.76% | [-34.18%, -5.21%] | 200 |
| S3a | each-way (paper 5 terms) | -1.54% | 13.40% | [-24.35%, 20.16%] | 200 |
| S3a | each-way (corrected terms) | 14.96% | 14.29% | [-9.44%, 37.52%] | 200 |
| S3b | win | -7.35% | 18.51% | [-37.75%, 23.31%] | 324 |
| S3b | place | -11.69% | 6.83% | [-23.13%, -0.65%] | 324 |
| S3b | each-way (paper 5 terms) | -8.85% | 11.31% | [-27.06%, 9.84%] | 324 |
| S3b | each-way (corrected terms) | 1.17% | 12.26% | [-18.67%, 21.32%] | 324 |
| S3c | win | -4.16% | 13.74% | [-28.23%, 16.60%] | 464 |
| S3c | place | -11.59% | 5.30% | [-20.33%, -3.03%] | 464 |
| S3c | each-way (paper 5 terms) | -7.09% | 8.52% | [-21.79%, 5.84%] | 464 |
| S3c | each-way (corrected terms) | 0.39% | 9.04% | [-15.12%, 14.47%] | 464 |
| S4 | win | -13.15% | 12.39% | [-33.20%, 7.31%] | 704 |
| S4 | place | -13.57% | 5.27% | [-22.38%, -4.57%] | 704 |
| S4 | each-way (paper 5 terms) | -11.17% | 7.91% | [-24.32%, 2.13%] | 704 |
| S4 | each-way (corrected terms) | -5.88% | 8.30% | [-19.71%, 7.94%] | 704 |

## 7. Stage B — staking on the declared selection, validation slice

| selection | staking | bet | races selected | bets placed | staked share | projected test bets | wins | ROI (SP) | ROI (fair book) | mean stake | sd unit return | max drawdown | eligible | struck because |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| S1 | K0 | win | 704 | 704 | 100.0% | 1021 | 109 | 8.00% | 23.44% | 1.000 | 2.679 | 48.6 | yes | — |
| S1 | K0 | place | 704 | 704 | 100.0% | 1021 | 326 | -3.84% | 10.09% | 1.000 | 1.117 | 54.9 | yes | — |
| S1 | K0 | each-way (paper 5 terms) | 704 | 704 | 100.0% | 1021 | 326 | 5.47% | 17.89% | 2.000 | 1.684 | 67.9 | yes | — |
| S1 | K0 | each-way (corrected terms) | 704 | 704 | 100.0% | 1021 | 250 | -3.08% | 9.05% | 1.963 | 1.768 | 121.7 | yes | — |
| S1 | K1 | win | 704 | 704 | 100.0% | 1021 | 109 | 3.86% | 18.33% | 1.653 | 2.679 | 98.6 | yes | — |
| S1 | K1 | place | 704 | 704 | 100.0% | 1021 | 326 | -6.06% | 7.25% | 1.653 | 1.117 | 105.4 | yes | — |
| S1 | K1 | each-way (paper 5 terms) | 704 | 704 | 100.0% | 1021 | 326 | 2.89% | 14.67% | 3.305 | 1.684 | 123.1 | yes | — |
| S1 | K1 | each-way (corrected terms) | 704 | 704 | 100.0% | 1021 | 250 | -6.58% | 4.86% | 3.227 | 1.768 | 219.9 | yes | — |
| S1 | K2 | win | 704 | 704 | 100.0% | 1021 | 109 | 2.66% | 16.43% | 0.391 | 2.679 | 23.8 | yes | — |
| S1 | K2 | place | 704 | 704 | 100.0% | 1021 | 326 | -8.21% | 4.34% | 0.391 | 1.117 | 28.3 | yes | — |
| S1 | K2 | each-way (paper 5 terms) | 704 | 704 | 100.0% | 1021 | 326 | 1.66% | 12.86% | 0.782 | 1.684 | 33.0 | yes | — |
| S1 | K2 | each-way (corrected terms) | 704 | 704 | 100.0% | 1021 | 250 | -8.36% | 2.49% | 0.760 | 1.768 | 58.0 | yes | — |

