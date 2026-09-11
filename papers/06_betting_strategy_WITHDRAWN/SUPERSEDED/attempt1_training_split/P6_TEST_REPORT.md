# Paper 6 — the test split, scored once

Five rules reached the test split and no others: the three declared in
`DECLARED_RULES.md`, S1/K0 (paper 5's incumbent) and S4/K0 (the
market-only control). The declaration was committed before any target in
this report existed, and `p6_declaration_frozen` re-reads the file from
disk and matches it against the declaration target on every build.

The comparator for every headline number is paper 5's encoder under
Owen's rule on the same 2,183 test races: win -12.19%, place -10.20%,
each-way -5.96% (paper 5's terms).

## 1. The declared rules

| bet type | selection | staking |
|---|---|---|
| win | S3b | K2 |
| place | S1 | K1 |
| each-way (corrected terms) | S4 | K2 |

## 2. Results

| bet | arm | bets | wins | total stake | profit | ROI (SP) | ROI (fair book) | ROI less top winner | 90% interval |
|---|---|---|---|---|---|---|---|---|---|
| win | S1/K0 (paper 5 incumbent) | 1064 | 131 | 1064 | -129.75 | -12.19% | 0.84% | -13.52% | [-24.83%, 0.65%] |
| win | S4/K0 (market-only control) | 2183 | 719 | 2183 | -138.79 | -6.36% | 8.42% | -6.59% | [-11.30%, -1.50%] |
| win | declared (S3b/K2) | 122 | 33 | 33 | -7.17 | -21.73% | -12.79% | -29.77% | [-47.40%, 6.80%] |
| place | S1/K0 (paper 5 incumbent) | 1064 | 475 | 1064 | -108.51 | -10.20% | 2.74% | -10.70% | [-15.69%, -4.63%] |
| place | S4/K0 (market-only control) | 2183 | 1453 | 2183 | -412.36 | -18.89% | -6.04% | -18.96% | [-21.05%, -16.67%] |
| place | declared (S1/K1) | 1064 | 475 | 1760 | -187.78 | -10.67% | 1.89% | -11.34% | [-16.47%, -4.80%] |
| each-way (paper 5 terms) | S1/K0 (paper 5 incumbent) | 1064 | 475 | 2128 | -126.83 | -5.96% | 5.10% | -6.76% | [-13.96%, 1.95%] |
| each-way (paper 5 terms) | S4/K0 (market-only control) | 2183 | 1453 | 4366 | -294.39 | -6.74% | 3.82% | -6.88% | [-10.08%, -3.46%] |
| each-way (paper 5 terms) | declared (S4/K2) | 35 | 20 | 13 | -3.20 | -25.40% | -20.10% | -36.80% | [-52.89%, 9.52%] |
| each-way (corrected terms) | S1/K0 (paper 5 incumbent) | 1064 | 325 | 2063 | -359.66 | -17.43% | -6.89% | -18.27% | [-25.71%, -8.83%] |
| each-way (corrected terms) | S4/K0 (market-only control) | 2183 | 1325 | 4283 | -377.23 | -8.81% | 2.06% | -8.96% | [-12.26%, -5.42%] |
| each-way (corrected terms) | declared (S4/K2) | 35 | 15 | 12 | -3.94 | -33.38% | -25.95% | -46.60% | [-65.67%, 5.05%] |

## 3. Paired contrasts on common races

B = 2000, seed 42, resampling races rather than bets so an arm that did
not bet a drawn race contributes zero to that draw.

| bet | declared | against | difference | bootstrap SE | 90% interval | excludes zero | common races |
|---|---|---|---|---|---|---|---|
| win | declared (S3b/K2) | S1/K0 (paper 5 incumbent) | -9.08% | 20.74% | [-41.44%, 26.53%] | no | 618 |
| win | declared (S3b/K2) | S4/K0 (market-only control) | -17.45% | 17.22% | [-44.19%, 12.12%] | no | 1353 |
| place | declared (S1/K1) | S1/K0 (paper 5 incumbent) | -0.47% | 1.11% | [-2.29%, 1.42%] | no | 1064 |
| place | declared (S1/K1) | S4/K0 (market-only control) | 9.88% | 4.08% | [3.10%, 16.24%] | yes | 1064 |
| each-way (paper 5 terms) | declared (S4/K2) | S1/K0 (paper 5 incumbent) | -13.29% | 27.27% | [-49.61%, 38.57%] | no | 1064 |
| each-way (paper 5 terms) | declared (S4/K2) | S4/K0 (market-only control) | -18.66% | 18.85% | [-46.08%, 15.19%] | no | 2183 |
| each-way (corrected terms) | declared (S4/K2) | S1/K0 (paper 5 incumbent) | -5.55% | 30.16% | [-46.34%, 52.51%] | no | 1064 |
| each-way (corrected terms) | declared (S4/K2) | S4/K0 (market-only control) | -24.57% | 21.19% | [-54.74%, 13.50%] | no | 2183 |

## 4. Margin decomposition

`margin paid` is the fair-book ROI less the real-SP ROI: the share of
stake the over-round takes on the horses that arm actually backs. A rule
that improves ROI by backing shorter prices has reduced the margin it
pays, which is not the same thing as picking better.

| bet | arm | bets | ROI (SP) | ROI (fair book) | margin paid | mean stake | sd unit return | max drawdown |
|---|---|---|---|---|---|---|---|---|
| win | S1/K0 (paper 5 incumbent) | 1064 | -12.19% | 0.84% | 13.03% | 1.000 | 2.466 | 157.5 |
| win | S4/K0 (market-only control) | 2183 | -6.36% | 8.42% | 14.78% | 1.000 | 1.428 | 144.2 |
| win | declared (S3b/K2) | 122 | -21.73% | -12.79% | 8.94% | 0.271 | 1.625 | 11.8 |
| place | S1/K0 (paper 5 incumbent) | 1064 | -10.20% | 2.74% | 12.94% | 1.000 | 1.086 | 117.3 |
| place | S4/K0 (market-only control) | 2183 | -18.89% | -6.04% | 12.85% | 1.000 | 0.606 | 412.9 |
| place | declared (S1/K1) | 1064 | -10.67% | 1.89% | 12.56% | 1.654 | 1.086 | 203.6 |
| each-way (paper 5 terms) | S1/K0 (paper 5 incumbent) | 1064 | -5.96% | 5.10% | 11.06% | 2.000 | 1.567 | 186.3 |
| each-way (paper 5 terms) | S4/K0 (market-only control) | 2183 | -6.74% | 3.82% | 10.56% | 2.000 | 0.925 | 302.8 |
| each-way (paper 5 terms) | declared (S4/K2) | 35 | -25.40% | -20.10% | 5.30% | 0.360 | 0.910 | 4.2 |
| each-way (corrected terms) | S1/K0 (paper 5 incumbent) | 1064 | -17.43% | -6.89% | 10.55% | 1.939 | 1.672 | 374.1 |
| each-way (corrected terms) | S4/K0 (market-only control) | 2183 | -8.81% | 2.06% | 10.86% | 1.962 | 0.966 | 385.6 |
| each-way (corrected terms) | declared (S4/K2) | 35 | -33.38% | -25.95% | 7.42% | 0.337 | 0.996 | 5.1 |

