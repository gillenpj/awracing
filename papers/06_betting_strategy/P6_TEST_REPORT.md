# Paper 6 — the test split, scored once

The arms below are the entire test contact. The declaration was
committed before any target in this report existed, and
`p6_declaration_frozen` re-reads the file from disk and matches it
against the declaration target on every build.

The comparator for every headline number is paper 5's encoder under
Owen's rule on the same 2,183 test races: win -12.19%, place -10.20%,
each-way -5.96% (paper 5's terms).

## 1. What was declared

| stage | bet type | declared |
|---|---|---|
| A | win | S1/K0 |
| A | place | S1/K0 |
| A | each-way (corrected terms) | S1/K0 |
| B | win | S1/K0 |
| B | place | S1/K0 |
| B | each-way (corrected terms) | S1/K0 |

Both stages declared the incumbent for every bet type. The declared
selection at a flat stake is therefore the same rule as S1/K0, and the
declared stake is the same rule again, so the arms coincide and two of
the four contrasts below are identically zero by construction. That is
reported rather than hidden.

## 2. The arms

| arm | races selected on test | roles |
|---|---|---|
| S1/K0 | 1064 | declared selection, flat stake; S1/K0, paper 5 incumbent |
| S4/K0 | 2183 | S4/K0, market-only control |

## 3. Results

| bet | arm | bets | wins | staked | profit | ROI (SP) | ROI (fair book) | ROI less top winner | 90% interval |
|---|---|---|---|---|---|---|---|---|---|
| win | S1/K0 | 1064 | 131 | 1064 | -129.75 | -12.19% | 0.84% | -13.52% | [-24.83%, 0.65%] |
| win | S4/K0 | 2183 | 719 | 2183 | -138.79 | -6.36% | 8.42% | -6.59% | [-11.30%, -1.50%] |
| place | S1/K0 | 1064 | 475 | 1064 | -108.51 | -10.20% | 2.74% | -10.70% | [-15.69%, -4.63%] |
| place | S4/K0 | 2183 | 1453 | 2183 | -412.36 | -18.89% | -6.04% | -18.96% | [-21.05%, -16.67%] |
| each-way (paper 5 terms) | S1/K0 | 1064 | 475 | 2128 | -126.83 | -5.96% | 5.10% | -6.76% | [-13.96%, 1.95%] |
| each-way (paper 5 terms) | S4/K0 | 2183 | 1453 | 4366 | -294.39 | -6.74% | 3.82% | -6.88% | [-10.08%, -3.46%] |
| each-way (corrected terms) | S1/K0 | 1064 | 325 | 2063 | -359.66 | -17.43% | -6.89% | -18.27% | [-25.71%, -8.83%] |
| each-way (corrected terms) | S4/K0 | 2183 | 1325 | 4283 | -377.23 | -8.81% | 2.06% | -8.96% | [-12.26%, -5.42%] |

## 4. Contrasts on common races

B = 2000, seed 42, resampling races rather than bets so an arm that did
not bet a drawn race contributes zero to that draw.

| bet | question | contrast | ROI a (common) | ROI b (common) | difference | bootstrap SE | 90% interval | excludes zero | common races |
|---|---|---|---|---|---|---|---|---|---|
| win | did selection help? | S1/K0 - S1/K0 | — | — | 0 (same arm) | — | — | — | 1064 |
| win | did staking help? | S1/K0 - S1/K0 | — | — | 0 (same arm) | — | — | — | 1064 |
| win | does the declared rule beat a rule with no model? | S1/K0 - S4/K0 | -12.19% | -6.03% | -6.16% | 9.31% | [-21.05%, 9.44%] | no | 1064 |
| win | does the incumbent beat a rule with no model? | S1/K0 - S4/K0 | -12.19% | -6.03% | -6.16% | 9.31% | [-21.05%, 9.44%] | no | 1064 |
| place | did selection help? | S1/K0 - S1/K0 | — | — | 0 (same arm) | — | — | — | 1064 |
| place | did staking help? | S1/K0 - S1/K0 | — | — | 0 (same arm) | — | — | — | 1064 |
| place | does the declared rule beat a rule with no model? | S1/K0 - S4/K0 | -10.20% | -20.55% | 10.35% | 3.93% | [3.63%, 16.57%] | yes | 1064 |
| place | does the incumbent beat a rule with no model? | S1/K0 - S4/K0 | -10.20% | -20.55% | 10.35% | 3.93% | [3.63%, 16.57%] | yes | 1064 |
| each-way (paper 5 terms) | did selection help? | S1/K0 - S1/K0 | — | — | 0 (same arm) | — | — | — | 1064 |
| each-way (paper 5 terms) | did staking help? | S1/K0 - S1/K0 | — | — | 0 (same arm) | — | — | — | 1064 |
| each-way (paper 5 terms) | does the declared rule beat a rule with no model? | S1/K0 - S4/K0 | -5.96% | -6.70% | 0.74% | 5.95% | [-9.08%, 10.77%] | no | 1064 |
| each-way (paper 5 terms) | does the incumbent beat a rule with no model? | S1/K0 - S4/K0 | -5.96% | -6.70% | 0.74% | 5.95% | [-9.08%, 10.77%] | no | 1064 |
| each-way (corrected terms) | did selection help? | S1/K0 - S1/K0 | — | — | 0 (same arm) | — | — | — | 1064 |
| each-way (corrected terms) | did staking help? | S1/K0 - S1/K0 | — | — | 0 (same arm) | — | — | — | 1064 |
| each-way (corrected terms) | does the declared rule beat a rule with no model? | S1/K0 - S4/K0 | -17.43% | -10.17% | -7.26% | 6.40% | [-17.84%, 3.57%] | no | 1064 |
| each-way (corrected terms) | does the incumbent beat a rule with no model? | S1/K0 - S4/K0 | -17.43% | -10.17% | -7.26% | 6.40% | [-17.84%, 3.57%] | no | 1064 |

## 5. Margin decomposition

`margin paid` is the fair-book ROI less the real-SP ROI: the share of
stake the over-round takes on the horses that arm actually backs. A rule
that improves ROI by backing shorter prices has reduced the margin it
pays, which is not the same thing as picking better.

| bet | arm | bets | ROI (SP) | ROI (fair book) | margin paid | mean stake | sd unit return | max drawdown |
|---|---|---|---|---|---|---|---|---|
| win | S1/K0 | 1064 | -12.19% | 0.84% | 13.03% | 1.000 | 2.466 | 157.5 |
| win | S4/K0 | 2183 | -6.36% | 8.42% | 14.78% | 1.000 | 1.428 | 144.2 |
| place | S1/K0 | 1064 | -10.20% | 2.74% | 12.94% | 1.000 | 1.086 | 117.3 |
| place | S4/K0 | 2183 | -18.89% | -6.04% | 12.85% | 1.000 | 0.606 | 412.9 |
| each-way (paper 5 terms) | S1/K0 | 1064 | -5.96% | 5.10% | 11.06% | 2.000 | 1.567 | 186.3 |
| each-way (paper 5 terms) | S4/K0 | 2183 | -6.74% | 3.82% | 10.56% | 2.000 | 0.925 | 302.8 |
| each-way (corrected terms) | S1/K0 | 1064 | -17.43% | -6.89% | 10.55% | 1.939 | 1.672 | 374.1 |
| each-way (corrected terms) | S4/K0 | 2183 | -8.81% | 2.06% | 10.86% | 1.962 | 0.966 | 385.6 |

