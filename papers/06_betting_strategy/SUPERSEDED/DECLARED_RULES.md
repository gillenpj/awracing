# Paper 6 — declared betting rules

**Frozen before any test target was built.** Nothing in this file may be
altered after the commit that introduced it. Every number below is from
the training split alone.

Search set: 45,958 runner-rows over 5,022 races, the paper-5 training
split. 12 rows of paper 5's training frame carry no usable price and
are dropped; 0 test races appear in it.

Model: paper 5's rung-3b encoder, refit from paper 5's stored
configuration with paper 5's own function and asserted bit-identical to
paper 5's stored test scores before any training score was read.

**The training-split probabilities are IN-SAMPLE.** The encoder was
fitted on these races, so its win probabilities here are sharper than
anything it will produce out of sample, and every ROI below that uses a
model probability is inflated by that. The scale of it is visible in the
grid: S4/K0 — the market favourite, flat stake, no model input at all and
therefore not inflated — returns -12.7% on the training split, while
S1/K0 returns 39.8% on the same races against paper 5's -12.19% on test.
No training-split ROI here is an estimate of what a rule will return.
They are a ranking device and nothing more, which is all the declaration
rule uses them for. The test split settles the levels.

## 1. The declaration

For each bet type independently: take the highest training-split ROI at
the real starting price; paired race-level bootstrap (B = 2000, seed 42)
of its ROI difference against S1/K0 on their common races; declare the
candidate only if the point difference exceeds one bootstrap standard
error of the difference, otherwise declare S1/K0. Ties on ROI to four
decimals prefer the lower-numbered selection arm, then K0 over K1 over
K2. No judgement enters at any step.

| bet type | declared selection | declared staking | top candidate | candidate ROI | S1/K0 ROI | paired difference | bootstrap SE | exceeds one SE | bets on training |
|---|---|---|---|---|---|---|---|---|---|
| win | S3b | K2 | S3b/K2 | 62.66% | 39.80% | 40.19% | 14.19% | yes | 417 |
| place | S1 | K1 | S1/K1 | 14.28% | 12.91% | 1.37% | 0.80% | yes | 2552 |
| each-way (corrected terms) | S4 | K2 | S4/K2 | 40.10% | 22.80% | 19.64% | 12.10% | yes | 255 |

The each-way declaration runs on the **corrected** place terms, and its
comparator is S1/K0 recomputed on those same terms. Paper 5's flat
one-fifth-top-three terms are reported alongside throughout but declare
nothing.

## 2. Each-way terms

Races with four to seven runners: 29.1% of the training split, 39.0% of
the test split. The threshold in the brief is 10%, so the terms are
corrected. Correcting only the four-to-seven band would leave the
twelve-and-up band wrong as well, so the full industry handicap ladder is
used: win-only at four runners; a quarter the odds on the first two from
five to seven; a fifth on the first three from eight to eleven; a quarter
on the first three from twelve to fifteen; a quarter on the first four
from sixteen. Paper 5's terms differ from these on
51.0% of training races.

## 3. The reproduction gate

Paper 5's test ledger, rebuilt through paper 6's ledger function under
S1/K0 and paper 5's each-way terms, against the encoder rows of paper 5's
`p5_test_backtests`:

| bet | p6 bets | p5 bets | p6 wins | p5 wins | p6 profit | p5 profit | ROI difference |
|---|---|---|---|---|---|---|---|
| win | 1064 | 1064 | 131 | 131 | -129.75 | -129.75 | 0.0e+00 |
| place | 1064 | 1064 | 475 | 475 | -108.51 | -108.51 | 0.0e+00 |
| eachway | 1064 | 1064 | 475 | 475 | -126.83 | -126.83 | 0.0e+00 |

## 4. The candidates

| rule | definition |
|---|---|
| S0 | S0 — model's top-rated horse, every race |
| S1 | S1 — Owen: P_mod > 0.15 and P_mod/P_mkt > 1.3, highest P_mod |
| S2a | S2a — top-rated, ratio in [q25, q75] = [0.840, 1.403] |
| S2b | S2b — top-rated, ratio in [q30, q60] = [0.884, 1.185] |
| S2c | S2c — top-rated, ratio in [q40, q70] = [0.977, 1.319] |
| S3a | S3a — top-rated, SP <= q25 = 3.00 |
| S3b | S3b — top-rated, SP <= q50 = 4.33 |
| S3c | S3c — top-rated, SP <= q75 = 6.00 |
| S4 | S4 — market favourite, every race, no model input |
| K0 | K0 — flat, 1 unit |
| K1 | K1 — (P_mod - P_mkt) / 0.05, capped at 3 units |
| K2 | K2 — quarter-Kelly at P_mod against SP / 0.05, capped at 3 units |

Quantile cuts, taken over the model's top-rated horse in each of the
5,022 training races: ratio q25 0.840, q30 0.884, q40 0.977, q60 1.185,
q70 1.319, q75 1.403; starting price q25 3.00, q50 4.33, q75 6.00.

## 5. The full search grid, training split

| selection | staking | bet | n_bets | n_wins | ROI (SP) | ROI (fair book) | mean stake | sd unit return | max drawdown |
|---|---|---|---|---|---|---|---|---|---|
| S0 | K0 | win | 5022 | 1430 | 16.42% | 35.91% | 1.000 | 2.184 | 125.9 |
| S0 | K0 | place | 5011 | 3033 | -6.05% | 9.48% | 1.000 | 0.896 | 395.1 |
| S0 | K0 | each-way (paper 5's terms) | 5011 | 3033 | 8.61% | 22.73% | 2.000 | 1.371 | 271.9 |
| S0 | K0 | each-way (corrected terms) | 5011 | 2765 | 7.23% | 21.76% | 1.973 | 1.423 | 353.4 |
| S0 | K1 | win | 2885 | 728 | 53.68% | 79.42% | 1.227 | 2.576 | 91.8 |
| S0 | K1 | place | 2881 | 1621 | 11.20% | 29.40% | 1.228 | 1.046 | 86.2 |
| S0 | K1 | each-way (paper 5's terms) | 2881 | 1621 | 34.34% | 52.81% | 2.455 | 1.605 | 145.9 |
| S0 | K1 | each-way (corrected terms) | 2881 | 1460 | 32.27% | 51.23% | 2.410 | 1.667 | 157.3 |
| S0 | K2 | win | 2104 | 522 | 57.44% | 82.22% | 0.365 | 2.776 | 23.3 |
| S0 | K2 | place | 2096 | 1162 | 12.83% | 30.34% | 0.365 | 1.121 | 24.8 |
| S0 | K2 | each-way (paper 5's terms) | 2096 | 1162 | 37.61% | 55.56% | 0.731 | 1.722 | 41.3 |
| S0 | K2 | each-way (corrected terms) | 2096 | 1042 | 34.31% | 52.68% | 0.713 | 1.791 | 46.0 |
| S1 | K0 | win | 2557 | 535 | 39.80% | 62.29% | 1.000 | 2.971 | 74.1 |
| S1 | K0 | place | 2552 | 1362 | 12.91% | 30.60% | 1.000 | 1.162 | 42.5 |
| S1 | K0 | each-way (paper 5's terms) | 2552 | 1362 | 29.16% | 46.24% | 2.000 | 1.832 | 111.8 |
| S1 | K0 | each-way (corrected terms) | 2552 | 1127 | 22.80% | 39.86% | 1.965 | 1.936 | 126.9 |
| S1 | K1 | win | 2557 | 535 | 49.61% | 73.47% | 1.735 | 2.971 | 112.9 |
| S1 | K1 | place | 2552 | 1362 | 14.28% | 32.05% | 1.736 | 1.162 | 78.2 |
| S1 | K1 | each-way (paper 5's terms) | 2552 | 1362 | 35.19% | 53.03% | 3.472 | 1.832 | 171.5 |
| S1 | K1 | each-way (corrected terms) | 2552 | 1127 | 28.70% | 46.56% | 3.394 | 1.936 | 209.8 |
| S1 | K2 | win | 2557 | 535 | 49.20% | 72.00% | 0.424 | 2.971 | 28.6 |
| S1 | K2 | place | 2552 | 1362 | 13.27% | 30.21% | 0.424 | 1.162 | 22.0 |
| S1 | K2 | each-way (paper 5's terms) | 2552 | 1362 | 35.10% | 52.18% | 0.847 | 1.832 | 46.6 |
| S1 | K2 | each-way (corrected terms) | 2552 | 1127 | 28.01% | 45.10% | 0.824 | 1.936 | 56.7 |
| S2a | K0 | win | 2510 | 699 | 9.50% | 27.47% | 1.000 | 1.891 | 114.4 |
| S2a | K0 | place | 2508 | 1534 | -9.39% | 5.15% | 1.000 | 0.779 | 246.1 |
| S2a | K0 | each-way (paper 5's terms) | 2508 | 1534 | 4.10% | 17.10% | 2.000 | 1.198 | 202.1 |
| S2a | K0 | each-way (corrected terms) | 2508 | 1384 | 2.54% | 15.95% | 1.968 | 1.246 | 266.0 |
| S2a | K1 | win | 1629 | 435 | 25.13% | 44.59% | 0.668 | 2.017 | 44.3 |
| S2a | K1 | place | 1628 | 965 | -3.14% | 11.78% | 0.668 | 0.828 | 65.6 |
| S2a | K1 | each-way (paper 5's terms) | 1628 | 965 | 15.41% | 29.38% | 1.337 | 1.275 | 70.3 |
| S2a | K1 | each-way (corrected terms) | 1628 | 871 | 13.68% | 28.09% | 1.310 | 1.325 | 92.9 |
| S2a | K2 | win | 844 | 228 | 28.62% | 44.93% | 0.151 | 2.105 | 5.9 |
| S2a | K2 | place | 843 | 506 | -0.55% | 12.18% | 0.150 | 0.858 | 7.0 |
| S2a | K2 | each-way (paper 5's terms) | 843 | 506 | 19.84% | 31.67% | 0.301 | 1.321 | 7.5 |
| S2a | K2 | each-way (corrected terms) | 843 | 453 | 16.63% | 28.88% | 0.292 | 1.381 | 9.9 |
| S2b | K0 | win | 1506 | 418 | 2.53% | 19.44% | 1.000 | 1.764 | 91.7 |
| S2b | K0 | place | 1504 | 927 | -12.62% | 1.33% | 1.000 | 0.734 | 194.4 |
| S2b | K0 | each-way (paper 5's terms) | 1504 | 927 | -0.57% | 11.66% | 2.000 | 1.125 | 157.3 |
| S2b | K0 | each-way (corrected terms) | 1504 | 823 | -2.84% | 9.73% | 1.963 | 1.174 | 206.7 |
| S2b | K1 | win | 876 | 238 | 19.22% | 38.04% | 0.368 | 1.860 | 20.3 |
| S2b | K1 | place | 875 | 534 | -5.01% | 9.60% | 0.368 | 0.766 | 20.2 |
| S2b | K1 | each-way (paper 5's terms) | 875 | 534 | 12.37% | 25.76% | 0.736 | 1.180 | 24.5 |
| S2b | K1 | each-way (corrected terms) | 875 | 476 | 10.16% | 24.09% | 0.711 | 1.232 | 33.6 |
| S2b | K2 | win | 143 | 46 | 38.60% | 48.10% | 0.072 | 1.804 | 1.9 |
| S2b | K2 | place | 142 | 101 | 1.39% | 9.24% | 0.069 | 0.688 | 1.0 |
| S2b | K2 | each-way (paper 5's terms) | 142 | 101 | 31.34% | 38.43% | 0.139 | 1.110 | 2.3 |
| S2b | K2 | each-way (corrected terms) | 142 | 84 | 27.20% | 35.18% | 0.120 | 1.225 | 2.7 |
| S2c | K0 | win | 1506 | 397 | 8.96% | 27.05% | 1.000 | 1.938 | 129.5 |
| S2c | K0 | place | 1505 | 893 | -9.88% | 4.55% | 1.000 | 0.799 | 156.4 |
| S2c | K0 | each-way (paper 5's terms) | 1505 | 893 | 3.28% | 16.36% | 2.000 | 1.229 | 212.0 |
| S2c | K0 | each-way (corrected terms) | 1505 | 797 | 1.53% | 15.04% | 1.965 | 1.281 | 255.3 |
| S2c | K1 | win | 1378 | 366 | 18.77% | 37.85% | 0.565 | 1.961 | 75.1 |
| S2c | K1 | place | 1377 | 812 | -6.81% | 7.52% | 0.566 | 0.806 | 61.5 |
| S2c | K1 | each-way (paper 5's terms) | 1377 | 812 | 10.60% | 24.15% | 1.132 | 1.244 | 104.9 |
| S2c | K1 | each-way (corrected terms) | 1377 | 731 | 8.88% | 22.94% | 1.103 | 1.295 | 124.9 |
| S2c | K2 | win | 591 | 159 | 13.54% | 27.43% | 0.118 | 2.021 | 12.3 |
| S2c | K2 | place | 591 | 352 | -5.61% | 5.37% | 0.118 | 0.822 | 5.6 |
| S2c | K2 | each-way (paper 5's terms) | 591 | 352 | 10.09% | 20.12% | 0.235 | 1.275 | 14.9 |
| S2c | K2 | each-way (corrected terms) | 591 | 312 | 5.77% | 16.36% | 0.224 | 1.340 | 17.5 |
| S3a | K0 | win | 1307 | 543 | -2.39% | 12.14% | 1.000 | 1.204 | 100.7 |
| S3a | K0 | place | 1306 | 1014 | -16.82% | -4.37% | 1.000 | 0.455 | 219.6 |
| S3a | K0 | each-way (paper 5's terms) | 1306 | 1014 | -1.55% | 8.56% | 2.000 | 0.762 | 122.5 |
| S3a | K0 | each-way (corrected terms) | 1306 | 900 | -4.36% | 6.15% | 1.927 | 0.834 | 173.9 |
| S3a | K1 | win | 221 | 103 | 43.13% | 61.97% | 0.926 | 1.339 | 16.4 |
| S3a | K1 | place | 221 | 187 | -5.03% | 7.60% | 0.926 | 0.403 | 10.5 |
| S3a | K1 | each-way (paper 5's terms) | 221 | 187 | 29.77% | 42.29% | 1.853 | 0.798 | 12.7 |
| S3a | K1 | each-way (corrected terms) | 221 | 157 | 30.80% | 44.74% | 1.642 | 0.961 | 14.5 |
| S3a | K2 | win | 95 | 49 | 44.54% | 61.18% | 0.420 | 1.391 | 5.4 |
| S3a | K2 | place | 95 | 82 | -3.80% | 7.99% | 0.420 | 0.386 | 2.7 |
| S3a | K2 | each-way (paper 5's terms) | 95 | 82 | 31.63% | 42.90% | 0.840 | 0.820 | 4.5 |
| S3a | K2 | each-way (corrected terms) | 95 | 72 | 34.74% | 47.63% | 0.720 | 1.009 | 4.3 |
| S3b | K0 | win | 2596 | 933 | 4.96% | 21.06% | 1.000 | 1.483 | 143.6 |
| S3b | K0 | place | 2593 | 1854 | -13.75% | -0.49% | 1.000 | 0.566 | 357.0 |
| S3b | K0 | each-way (paper 5's terms) | 2593 | 1854 | 2.43% | 13.82% | 2.000 | 0.937 | 197.1 |
| S3b | K0 | each-way (corrected terms) | 2593 | 1652 | -0.40% | 11.32% | 1.952 | 1.001 | 300.1 |
| S3b | K1 | win | 781 | 291 | 50.80% | 71.61% | 1.003 | 1.674 | 43.8 |
| S3b | K1 | place | 781 | 589 | -0.23% | 13.19% | 1.003 | 0.564 | 37.3 |
| S3b | K1 | each-way (paper 5's terms) | 781 | 589 | 34.54% | 48.62% | 2.006 | 1.022 | 41.6 |
| S3b | K1 | each-way (corrected terms) | 781 | 494 | 31.19% | 46.00% | 1.874 | 1.142 | 57.8 |
| S3b | K2 | win | 417 | 173 | 62.66% | 81.59% | 0.363 | 1.763 | 9.3 |
| S3b | K2 | place | 416 | 323 | 2.01% | 14.15% | 0.363 | 0.548 | 5.0 |
| S3b | K2 | each-way (paper 5's terms) | 416 | 323 | 42.45% | 55.43% | 0.726 | 1.063 | 8.3 |
| S3b | K2 | each-way (corrected terms) | 416 | 266 | 39.90% | 53.78% | 0.661 | 1.221 | 11.5 |
| S3c | K0 | win | 3967 | 1259 | 10.72% | 28.54% | 1.000 | 1.763 | 101.4 |
| S3c | K0 | place | 3961 | 2588 | -11.22% | 2.88% | 1.000 | 0.692 | 451.4 |
| S3c | K0 | each-way (paper 5's terms) | 3961 | 2588 | 5.01% | 17.71% | 2.000 | 1.115 | 224.5 |
| S3c | K0 | each-way (corrected terms) | 3961 | 2340 | 2.90% | 15.92% | 1.967 | 1.167 | 327.1 |
| S3c | K1 | win | 1841 | 558 | 50.08% | 73.24% | 1.042 | 2.033 | 66.3 |
| S3c | K1 | place | 1840 | 1180 | 4.04% | 19.48% | 1.042 | 0.761 | 84.7 |
| S3c | K1 | each-way (paper 5's terms) | 1840 | 1180 | 33.29% | 49.38% | 2.084 | 1.268 | 85.5 |
| S3c | K1 | each-way (corrected terms) | 1840 | 1039 | 29.68% | 46.20% | 2.018 | 1.339 | 126.9 |
| S3c | K2 | win | 1129 | 363 | 58.68% | 80.59% | 0.329 | 2.132 | 14.0 |
| S3c | K2 | place | 1126 | 750 | 8.79% | 23.57% | 0.329 | 0.763 | 12.4 |
| S3c | K2 | each-way (paper 5's terms) | 1126 | 750 | 41.12% | 56.55% | 0.658 | 1.313 | 16.3 |
| S3c | K2 | each-way (corrected terms) | 1126 | 650 | 36.58% | 52.48% | 0.628 | 1.402 | 26.2 |
| S4 | K0 | win | 5022 | 1394 | -12.73% | 1.21% | 1.000 | 1.505 | 668.7 |
| S4 | K0 | place | 5011 | 3093 | -19.34% | -6.19% | 1.000 | 0.672 | 972.5 |
| S4 | K0 | each-way (paper 5's terms) | 5011 | 3093 | -11.43% | -1.07% | 2.000 | 0.978 | 1180.4 |
| S4 | K0 | each-way (corrected terms) | 5011 | 2830 | -12.96% | -2.29% | 1.973 | 1.015 | 1319.1 |
| S4 | K1 | win | 623 | 224 | 49.40% | 71.76% | 0.775 | 1.794 | 36.8 |
| S4 | K1 | place | 622 | 431 | -0.27% | 14.62% | 0.777 | 0.680 | 36.7 |
| S4 | K1 | each-way (paper 5's terms) | 622 | 431 | 30.31% | 45.39% | 1.553 | 1.121 | 54.3 |
| S4 | K1 | each-way (corrected terms) | 622 | 391 | 30.08% | 45.79% | 1.505 | 1.181 | 63.0 |
| S4 | K2 | win | 258 | 103 | 60.10% | 76.63% | 0.301 | 1.910 | 5.2 |
| S4 | K2 | place | 255 | 181 | 5.46% | 18.37% | 0.303 | 0.687 | 5.3 |
| S4 | K2 | each-way (paper 5's terms) | 255 | 181 | 38.93% | 50.95% | 0.606 | 1.172 | 10.0 |
| S4 | K2 | each-way (corrected terms) | 255 | 167 | 40.10% | 52.83% | 0.575 | 1.236 | 10.3 |

## 6. Every candidate against S1/K0, paired on common races

| selection | staking | bet | difference vs S1/K0 | bootstrap SE | 90% interval | common races |
|---|---|---|---|---|---|---|
| S0 | K0 | win | -14.32% | 4.95% | [-22.25%, -6.14%] | 2557 |
| S0 | K0 | place | -13.02% | 1.94% | [-16.27%, -9.82%] | 2552 |
| S0 | K0 | each-way (paper 5's terms) | -12.73% | 3.09% | [-18.10%, -7.66%] | 2552 |
| S0 | K0 | each-way (corrected terms) | -9.35% | 3.21% | [-14.71%, -4.10%] | 2552 |
| S0 | K1 | win | 18.18% | 5.98% | [8.48%, 28.01%] | 2557 |
| S0 | K1 | place | 0.78% | 2.22% | [-2.82%, 4.51%] | 2552 |
| S0 | K1 | each-way (paper 5's terms) | 8.95% | 3.62% | [3.20%, 15.14%] | 2552 |
| S0 | K1 | each-way (corrected terms) | 12.44% | 3.79% | [6.57%, 19.01%] | 2552 |
| S0 | K2 | win | 18.41% | 7.28% | [6.45%, 30.45%] | 2557 |
| S0 | K2 | place | 0.28% | 2.82% | [-4.14%, 5.08%] | 2552 |
| S0 | K2 | each-way (paper 5's terms) | 9.47% | 4.50% | [2.32%, 17.03%] | 2552 |
| S0 | K2 | each-way (corrected terms) | 11.98% | 4.72% | [4.68%, 19.91%] | 2552 |
| S1 | K0 | win | 0.00% | 0.00% | [0.00%, 0.00%] | 2557 |
| S1 | K0 | place | 0.00% | 0.00% | [0.00%, 0.00%] | 2552 |
| S1 | K0 | each-way (paper 5's terms) | 0.00% | 0.00% | [0.00%, 0.00%] | 2552 |
| S1 | K0 | each-way (corrected terms) | 0.00% | 0.00% | [0.00%, 0.00%] | 2552 |
| S1 | K1 | win | 9.80% | 2.16% | [6.44%, 13.64%] | 2557 |
| S1 | K1 | place | 1.37% | 0.80% | [0.06%, 2.72%] | 2552 |
| S1 | K1 | each-way (paper 5's terms) | 6.03% | 1.35% | [3.90%, 8.28%] | 2552 |
| S1 | K1 | each-way (corrected terms) | 5.90% | 1.41% | [3.70%, 8.25%] | 2552 |
| S1 | K2 | win | 9.40% | 3.62% | [3.51%, 15.39%] | 2557 |
| S1 | K2 | place | 0.36% | 1.45% | [-1.99%, 2.76%] | 2552 |
| S1 | K2 | each-way (paper 5's terms) | 5.94% | 2.28% | [2.40%, 9.67%] | 2552 |
| S1 | K2 | each-way (corrected terms) | 5.21% | 2.37% | [1.43%, 9.22%] | 2552 |
| S2a | K0 | win | -25.11% | 10.97% | [-42.78%, -7.47%] | 932 |
| S2a | K0 | place | -20.33% | 4.16% | [-27.00%, -13.54%] | 932 |
| S2a | K0 | each-way (paper 5's terms) | -20.04% | 6.80% | [-31.19%, -9.05%] | 932 |
| S2a | K0 | each-way (corrected terms) | -16.18% | 7.14% | [-27.94%, -4.89%] | 932 |
| S2a | K1 | win | -10.16% | 11.28% | [-28.83%, 8.35%] | 932 |
| S2a | K1 | place | -13.89% | 4.24% | [-20.87%, -6.83%] | 932 |
| S2a | K1 | each-way (paper 5's terms) | -9.53% | 6.97% | [-21.19%, 1.65%] | 932 |
| S2a | K1 | each-way (corrected terms) | -4.85% | 7.26% | [-17.06%, 6.96%] | 932 |
| S2a | K2 | win | -2.72% | 12.29% | [-22.30%, 17.54%] | 932 |
| S2a | K2 | place | -11.28% | 4.51% | [-18.65%, -3.93%] | 932 |
| S2a | K2 | each-way (paper 5's terms) | -3.84% | 7.55% | [-16.21%, 8.65%] | 932 |
| S2a | K2 | each-way (corrected terms) | 0.30% | 7.95% | [-12.70%, 13.48%] | 932 |
| S2b | K0 | win | -34.81% | 18.79% | [-66.05%, -3.73%] | 444 |
| S2b | K0 | place | -26.79% | 7.15% | [-39.06%, -15.27%] | 444 |
| S2b | K0 | each-way (paper 5's terms) | -27.13% | 11.68% | [-46.65%, -8.05%] | 444 |
| S2b | K0 | each-way (corrected terms) | -23.61% | 12.33% | [-44.22%, -3.11%] | 444 |
| S2b | K1 | win | -19.50% | 21.92% | [-55.98%, 16.65%] | 444 |
| S2b | K1 | place | -21.95% | 8.19% | [-35.41%, -8.94%] | 444 |
| S2b | K1 | each-way (paper 5's terms) | -16.59% | 13.70% | [-39.58%, 5.48%] | 444 |
| S2b | K1 | each-way (corrected terms) | -11.22% | 14.57% | [-35.25%, 12.73%] | 444 |
| S2b | K2 | win | -16.54% | 43.29% | [-85.00%, 54.59%] | 444 |
| S2b | K2 | place | -23.79% | 16.16% | [-50.28%, 2.38%] | 444 |
| S2b | K2 | each-way (paper 5's terms) | -15.21% | 28.17% | [-60.74%, 31.66%] | 444 |
| S2b | K2 | each-way (corrected terms) | -11.35% | 31.14% | [-59.12%, 42.47%] | 444 |
| S2c | K0 | win | -23.22% | 17.45% | [-52.40%, 4.90%] | 443 |
| S2c | K0 | place | -22.06% | 6.81% | [-33.52%, -10.68%] | 443 |
| S2c | K0 | each-way (paper 5's terms) | -19.11% | 10.86% | [-37.11%, -1.78%] | 443 |
| S2c | K0 | each-way (corrected terms) | -16.07% | 11.29% | [-34.67%, 2.20%] | 443 |
| S2c | K1 | win | -20.62% | 17.67% | [-49.46%, 8.23%] | 443 |
| S2c | K1 | place | -19.62% | 7.14% | [-30.93%, -7.69%] | 443 |
| S2c | K1 | each-way (paper 5's terms) | -16.23% | 11.06% | [-34.18%, 1.70%] | 443 |
| S2c | K1 | each-way (corrected terms) | -12.64% | 11.52% | [-31.40%, 6.19%] | 443 |
| S2c | K2 | win | -22.32% | 19.50% | [-54.65%, 8.85%] | 443 |
| S2c | K2 | place | -16.89% | 7.97% | [-30.07%, -4.10%] | 443 |
| S2c | K2 | each-way (paper 5's terms) | -14.91% | 12.17% | [-34.93%, 4.71%] | 443 |
| S2c | K2 | each-way (corrected terms) | -13.30% | 12.89% | [-34.20%, 7.48%] | 443 |
| S3a | K0 | win | -21.48% | 13.76% | [-45.09%, 0.84%] | 640 |
| S3a | K0 | place | -25.46% | 5.10% | [-33.59%, -16.94%] | 639 |
| S3a | K0 | each-way (paper 5's terms) | -24.56% | 8.55% | [-38.63%, -10.96%] | 639 |
| S3a | K0 | each-way (corrected terms) | -12.31% | 9.24% | [-27.31%, 2.82%] | 639 |
| S3a | K1 | win | 36.17% | 21.73% | [-0.05%, 70.00%] | 640 |
| S3a | K1 | place | -13.24% | 6.49% | [-24.09%, -3.10%] | 639 |
| S3a | K1 | each-way (paper 5's terms) | 13.18% | 12.78% | [-8.75%, 33.76%] | 639 |
| S3a | K1 | each-way (corrected terms) | 32.04% | 14.29% | [7.86%, 55.64%] | 639 |
| S3a | K2 | win | 27.11% | 29.53% | [-21.73%, 76.46%] | 640 |
| S3a | K2 | place | -12.62% | 8.34% | [-27.05%, 0.26%] | 639 |
| S3a | K2 | each-way (paper 5's terms) | 9.11% | 16.76% | [-18.47%, 37.53%] | 639 |
| S3a | K2 | each-way (corrected terms) | 27.98% | 19.56% | [-3.06%, 62.72%] | 639 |
| S3b | K0 | win | -20.22% | 9.67% | [-36.61%, -4.47%] | 1175 |
| S3b | K0 | place | -21.36% | 3.77% | [-27.75%, -15.18%] | 1174 |
| S3b | K0 | each-way (paper 5's terms) | -19.60% | 6.21% | [-30.02%, -9.79%] | 1174 |
| S3b | K0 | each-way (corrected terms) | -12.46% | 6.62% | [-23.75%, -1.65%] | 1174 |
| S3b | K1 | win | 33.88% | 12.36% | [12.27%, 53.08%] | 1175 |
| S3b | K1 | place | -6.25% | 4.07% | [-13.09%, 0.41%] | 1174 |
| S3b | K1 | each-way (paper 5's terms) | 17.06% | 7.50% | [4.69%, 29.35%] | 1174 |
| S3b | K1 | each-way (corrected terms) | 25.28% | 8.30% | [11.54%, 38.79%] | 1174 |
| S3b | K2 | win | 40.19% | 14.19% | [16.01%, 63.00%] | 1175 |
| S3b | K2 | place | -5.27% | 4.32% | [-12.56%, 1.82%] | 1174 |
| S3b | K2 | each-way (paper 5's terms) | 21.41% | 8.47% | [7.28%, 35.14%] | 1174 |
| S3b | K2 | each-way (corrected terms) | 30.53% | 9.55% | [14.50%, 46.03%] | 1174 |
| S3c | K0 | win | -20.03% | 7.08% | [-32.20%, -8.59%] | 1828 |
| S3c | K0 | place | -18.01% | 2.64% | [-22.40%, -13.75%] | 1826 |
| S3c | K0 | each-way (paper 5's terms) | -17.70% | 4.30% | [-24.74%, -10.63%] | 1826 |
| S3c | K0 | each-way (corrected terms) | -13.06% | 4.55% | [-20.65%, -5.49%] | 1826 |
| S3c | K1 | win | 19.45% | 7.95% | [6.42%, 32.53%] | 1828 |
| S3c | K1 | place | -3.60% | 2.77% | [-8.03%, 1.05%] | 1826 |
| S3c | K1 | each-way (paper 5's terms) | 9.55% | 4.80% | [1.61%, 17.41%] | 1826 |
| S3c | K1 | each-way (corrected terms) | 14.02% | 5.16% | [5.46%, 22.52%] | 1826 |
| S3c | K2 | win | 24.41% | 9.32% | [9.09%, 39.85%] | 1828 |
| S3c | K2 | place | -0.44% | 2.99% | [-5.33%, 4.59%] | 1826 |
| S3c | K2 | each-way (paper 5's terms) | 14.51% | 5.45% | [5.34%, 23.67%] | 1826 |
| S3c | K2 | each-way (corrected terms) | 18.52% | 5.93% | [8.57%, 28.32%] | 1826 |
| S4 | K0 | win | -54.20% | 7.10% | [-65.78%, -42.57%] | 2557 |
| S4 | K0 | place | -33.89% | 2.72% | [-38.34%, -29.49%] | 2552 |
| S4 | K0 | each-way (paper 5's terms) | -41.72% | 4.28% | [-49.14%, -35.14%] | 2552 |
| S4 | K0 | each-way (corrected terms) | -38.38% | 4.47% | [-46.30%, -31.46%] | 2552 |
| S4 | K1 | win | 26.25% | 14.79% | [2.32%, 50.62%] | 2557 |
| S4 | K1 | place | -8.66% | 4.90% | [-16.73%, -0.63%] | 2552 |
| S4 | K1 | each-way (paper 5's terms) | 11.92% | 9.06% | [-2.88%, 26.56%] | 2552 |
| S4 | K1 | each-way (corrected terms) | 18.42% | 9.54% | [2.67%, 33.80%] | 2552 |
| S4 | K2 | win | 22.63% | 19.85% | [-9.34%, 56.20%] | 2557 |
| S4 | K2 | place | -5.81% | 6.09% | [-15.93%, 4.15%] | 2552 |
| S4 | K2 | each-way (paper 5's terms) | 12.05% | 11.32% | [-5.98%, 30.82%] | 2552 |
| S4 | K2 | each-way (corrected terms) | 19.64% | 12.10% | [0.31%, 39.92%] | 2552 |

