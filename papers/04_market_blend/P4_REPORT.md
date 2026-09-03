# Paper 4 — the marginal value of the model over the market

Stage P4-3 report. Generated 2026-09-03 10:26:45 BST from the `_targets_p4` store. Every number below is computed from a target; none is transcribed.

The construction is Benter's two-stage conditional logit,

    V_ij = b_mkt * log(P_mkt_ij) + b_mod * log(P_mod_ij)

fitted with both coefficients free, race as chooser, no intercept. `b_mod` is the output: it asks whether the model carries information the market price does not, which papers 1-3 could not distinguish from the market simply knowing strictly more.

Pre-registered expectations were recorded before fitting in `papers/04_market_blend/PRE_REGISTRATION.md`.

## 1. P4-0 — the audit of the forecast price

Full findings: `scripts/p4_audit_forecast_price_output.md` and the three follow-up reports. Summarised here.

### 1.1 Abort conditions

As originally stated:

| condition | observed | verdict |
|---|---|---|
| < 70% of the 2,183 test-universe races have every runner priced | 100.00% of races complete | pass |
| median race overround outside 1.05 to 1.60 | median = 1.1564 | pass |
| pre-2013 coverage differs from 2013-onward by > 20 percentage points | 2.05 pp | pass |
| runner-set mismatch (item 5) above 5% of races | 38.89% | **ABORT** |

Condition 4 fired. It was then restated: it had tested set equality between the priced field and the pipeline's field, when the only risk is a pipeline runner *without* a price. The set difference is entirely declared runners who were later withdrawn — the forecast book is struck against the declared field, which item 5 established directly (81.75% of Non-Runner rows carry a forecast price; 0.39% carry an SP).

Restated as "every runner the pipeline uses has a usable price", measured live on the test universe: **** of races complete on the archived forecast column. The gate passes and the other three conditions were never close — condition 1 at 100% against a 70% floor, condition 2 at a median overround of 1.1564 inside a 1.05-1.60 band, condition 3 at 2.05 percentage points against a 20-point limit.

One thing worth recording that no condition tested: the pre-race feed column would have failed condition 1 badly on the **training** split, where only 53.5% of races are fully priced (`daily_races` begins 2008-03-01). It does not need to pass there — P4-2 fits on test races only — but the column is not a drop-in replacement for the archive column anywhere else in the series.

### 1.2 Shape of the forecast book against SP

| spec | slope |
|---|---|
| pooled | 0.6038 |
| within_race | 0.5544 |

The within-race slope of 0.5544 is the compression that motivates the pre-registered `b_mkt(A)` expectation of roughly its reciprocal.

## 2. P4-1 — market probability construction, and what each column cost

Probabilities are built by the same proportional overround adjustment the series already applies to SP, stated once as `normalise_overround()` in `R/market_blend_p4.R`. `scripts/verify_p4_market_probs.R` is the standing gate proving it is that adjustment and not a second one: it rebuilds the stored `win_market` column of `test_predictions_3` from raw starting prices and asserts agreement to 1e-12 (observed: exactly 0).

Races are dropped whole where any runner lacks a price. Individual runners are never dropped — removing one would change the normalisation for every other runner in that race.

### 2.1 The intersection race set

| price_set | races_complete | races_offered | pct_complete | races_lost |
|---|---|---|---|---|
| A — pre-race racecard forecast | 2182 | 2183 | 0.9995 | 1 |
| B — industry starting price | 2183 | 2183 | 1 | 0 |
| C — archived racecard forecast | 2183 | 2183 | 1 | 0 |
| intersection (all three) | 2182 | 2183 | 0.9995 | 1 |

**All arms fit the same 2182 races.** A paired comparison of `b_mod` across arms is void if the race sets differ, so the intersection is used even where a column individually covers more.

### 2.2 The probability floor

Both `P_mkt` and `P_mod` are floored at 1e-6 before `log()`.

| column | n_rows_floored | min_value |
|---|---|---|
| p_mkt_A | 0 | 0.011931 |
| p_mkt_B | 0 | 0.0056489 |
| p_mkt_C | 0 | 0.0088506 |
| p_mod_2b | 0 | 0.0087401 |
| p_mod_3 | 0 | 0.0041882 |


## 3. Amendment 2 — is the archive a revision, or is the feed noisy?

A conditional logit on the whole common race set carrying **both** `log(p_archive)` and `log(p_feed)`, each overround-normalised over its own final field, tested against the feed-only model.

| term | estimate | std_error | z | p_value | logLik | mcfadden_r2 | n_races |
|---|---|---|---|---|---|---|---|
| log_p_mkt_C | 1.431 | 0.1437 | 9.961 | <2e-16 | -4235 | 0.07061 | 2182 |
| log_p_mkt_A | -0.3748 | 0.1391 | -2.694 | 0.00706 | -4235 | 0.07061 | 2182 |

Each column on its own, on the same races:

| price_source | term | estimate | std_error | z | logLik | mcfadden_r2 |
|---|---|---|---|---|---|---|
| pre-race feed only | log_p_mkt_A | 0.9623 | 0.04271 | 22.53 | -4283 | 0.06011 |
| archive only | log_p_mkt_C | 1.064 | 0.04408 | 24.13 | -4239 | 0.06982 |

Likelihood-ratio tests:

| contrast | logLik_full | logLik_reduced | lr_stat | df | p_value |
|---|---|---|---|---|---|
| archive + feed vs feed only (does the archive add?) | -4235 | -4283 | 95.64 | 1 | <2e-16 |
| archive + feed vs archive only (does the feed add?) | -4235 | -4239 | 7.157 | 1 | 0.00747 |

Collinearity between the columns, since the fit above puts two market measures of the same race in one likelihood. The within-race figure is the one that matters: a conditional logit is invariant to race-constant shifts, so only within-race variation identifies a coefficient.

| x | y | corr_raw | corr_within_race |
|---|---|---|---|
| log_p_mkt_A | log_p_mkt_C | 0.9668 | 0.9588 |
| log_p_mkt_A | log_p_mkt_B | 0.7314 | 0.6875 |
| log_p_mkt_C | log_p_mkt_B | 0.7649 | 0.7276 |
| log_p_mkt_A | log_p_mod_2b | 0.7775 | 0.7143 |
| log_p_mkt_B | log_p_mod_2b | 0.7358 | 0.6936 |
| log_p_mkt_A | log_p_mod_3 | 0.7449 | 0.6734 |
| log_p_mkt_B | log_p_mod_3 | 0.74 | 0.6989 |

### Verdict

The archive coefficient is 1.4313 (SE 0.1437, z = 9.96, p = <2e-16); the feed coefficient alongside it is -0.3748 (SE 0.1391, z = -2.69). Adding the archive to the feed-only model gives LR = 95.64 on 1 df, p = <2e-16.

**The archive coefficient is distinguishable from zero.** By the pre-registered reading, the divergence is a genuine revision: the archived column holds information the pre-race feed does not, it is therefore contaminated by whatever was known later, and **arm C is a contamination estimate** rather than a second measurement of the morning price. Arm A is the price that was actually available at bet time; arm C bounds how much the archive's post-race transcription moves the answer.

The archive also beats the feed decisively on its own — McFadden 0.0698 against 0.0601 — which is the same conclusion without the two-regressor fit.

**One thing the pre-registered reading did not anticipate: the feed coefficient is negative** (-0.3748, z = -2.69), not merely indistinguishable from zero. With a within-race correlation of 0.959 between the two columns, this is a suppression pattern: given the archive, the feed's residual variation is weighted *against* the outcome. That is what a noisier measurement of a shared quantity looks like once the cleaner one is in the model, but it is not something the binary reading fixed in advance can adjudicate. The safe statement is the one the likelihood-ratio tests support: the archive carries information the feed does not (LR 95.6), and the two are not interchangeable. Read arm A as the price actually available and arm C as the contaminated comparison, and do not read the negative coefficient as a property of the feed column on its own — on its own it is strongly positive (0.9623).

## 4. P4-2 — the blend

Section 4 is the original P4-2: every blend fitted on test-A only, with test-B (1087 races) held back. Section 6 then spends that reservation on an independent replication — see there for what it cost.

Nothing in the test-A results was selected using a test-B race. The one thing that touched test-B before section 6 is amendment 2, which the brief specifies on "the test universe" and which therefore runs on all common races; that fit contains only the two market price columns, with no `P_mod` term of either model in it, so it cannot leak model performance, and its result changed no arm.

`b_mod` is only meaningful on out-of-sample model predictions. Papers 2b and 3 were fitted on the training split, so their training-split probabilities are optimistic and would bias `b_mod` upward; the blend has two parameters, so fitting it on this many races carries negligible overfitting risk. This is the deliberate exception to the series' training-split-only rule for exploratory work.

### 4.1 The split

| half | cutoff_date | races | runners | first_race | last_race |
|---|---|---|---|---|---|
| A | 2014-03-19 | 1095 | 9100 | 2012-12-31 | 2014-03-19 |
| B | 2014-03-19 | 1087 | 9311 | 2014-03-20 | 2015-10-14 |


### 4.2 The six arms

`mkt_*` is `b_mkt`, `mod_*` is `b_mod`. The LR test is against the market-only model on the same races and the same price column.

| arm | model_source | price_source | b_mkt | se_mkt | z_mkt | b_mod | se_mod | z_mod | p_mod | logLik | mcfadden_r2 | lr_stat | lr_p |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A1 | paper 2b (exploded conditional logit) | pre-race feed forecast | 0.2784 | 0.08275 | 3.365 | 1.037 | 0.1027 | 10.09 | <2e-16 | -2098 | 0.07562 | 104.6 | <2e-16 |
| A2 | paper 3 (gradient boosted trees) | pre-race feed forecast | 0.3285 | 0.07819 | 4.202 | 1.026 | 0.09845 | 10.42 | <2e-16 | -2093 | 0.07745 | 112.9 | <2e-16 |
| B1 | paper 2b (exploded conditional logit) | starting price | 1.09 | 0.06592 | 16.54 | 0.1516 | 0.09783 | 1.549 | 0.121 | -1955 | 0.1383 | 2.406 | 0.121 |
| B2 | paper 3 (gradient boosted trees) | starting price | 1.102 | 0.0668 | 16.49 | 0.1242 | 0.0998 | 1.245 | 0.213 | -1956 | 0.1381 | 1.556 | 0.212 |
| C1 | paper 2b (exploded conditional logit) | archived forecast | 0.4564 | 0.08511 | 5.362 | 0.8842 | 0.1033 | 8.556 | <2e-16 | -2089 | 0.07953 | 74.41 | <2e-16 |
| C2 | paper 3 (gradient boosted trees) | archived forecast | 0.4815 | 0.08123 | 5.928 | 0.8963 | 0.1001 | 8.959 | <2e-16 | -2084 | 0.08139 | 82.83 | <2e-16 |


Market-only reference fits on the same races:

| arm | price_source | term | estimate | std_error | z | logLik | mcfadden_r2 |
|---|---|---|---|---|---|---|---|
| A-mktonly | pre-race feed forecast | log_p_mkt_A | 0.8846 | 0.05906 | 14.98 | -2150 | 0.05256 |
| B-mktonly | starting price | log_p_mkt_B | 1.156 | 0.05078 | 22.76 | -1957 | 0.1378 |
| C-mktonly | archived forecast | log_p_mkt_C | 0.9853 | 0.06049 | 16.29 | -2126 | 0.06314 |


#### 95% confidence intervals (Wald)

| arm | price_source | coefficient | estimate | std_error | conf_low | conf_high | z |
|---|---|---|---|---|---|---|---|
| A1 | pre-race feed forecast | b_mkt | 0.2784 | 0.08275 | 0.1162 | 0.4406 | 3.365 |
| A2 | pre-race feed forecast | b_mkt | 0.3285 | 0.07819 | 0.1753 | 0.4818 | 4.202 |
| B1 | starting price | b_mkt | 1.09 | 0.06592 | 0.9612 | 1.22 | 16.54 |
| B2 | starting price | b_mkt | 1.102 | 0.0668 | 0.9707 | 1.233 | 16.49 |
| C1 | archived forecast | b_mkt | 0.4564 | 0.08511 | 0.2896 | 0.6232 | 5.362 |
| C2 | archived forecast | b_mkt | 0.4815 | 0.08123 | 0.3223 | 0.6407 | 5.928 |
| A1 | pre-race feed forecast | b_mod | 1.037 | 0.1027 | 0.8353 | 1.238 | 10.09 |
| A2 | pre-race feed forecast | b_mod | 1.026 | 0.09845 | 0.8329 | 1.219 | 10.42 |
| B1 | starting price | b_mod | 0.1516 | 0.09783 | -0.04017 | 0.3433 | 1.549 |
| B2 | starting price | b_mod | 0.1242 | 0.0998 | -0.07136 | 0.3199 | 1.245 |
| C1 | archived forecast | b_mod | 0.8842 | 0.1033 | 0.6817 | 1.087 | 8.556 |
| C2 | archived forecast | b_mod | 0.8963 | 0.1001 | 0.7002 | 1.092 | 8.959 |


**What the SP intervals exclude.** `b_mod` on the SP arms is a weak null on the z-test alone (z = 1.55 and 1.24), so the useful statement is not that the interval contains zero but what magnitude it rules out. Arm B1's interval is [-0.040, 0.343] and B2's is [-0.071, 0.320].

So on test-A the data exclude a `b_mod` against SP above 0.343 (paper 2b) and 0.320 (paper 3). Arm A's estimate of 1.037 sits far outside both — the SP arms rule out a model contribution anywhere near the size the morning-price arms show, which is a much stronger claim than "the interval contains zero". They do not rule out a small positive contribution: values up to roughly a third of arm A's remain inside the interval on this half alone. Section 6 narrows that.

### 4.3 `b_mod` under the forecast price versus SP

| model | b_mod_A_feed_forecast | b_mod_B_starting_price | b_mod_C_archive_forecast | ratio_B_over_A |
|---|---|---|---|---|
| paper 2b | 1.037 | 0.1516 | 0.8842 | 0.1462 |
| paper 3 | 1.026 | 0.1242 | 0.8963 | 0.1211 |

Comparable magnitudes mean the model's contribution survives market convergence. A collapse from A to B means the edge lives only in the timing gap between the morning price and the off.

**The numbers show a collapse.** `b_mod` under SP retains 15% (paper 2b) and 12% (paper 3) of its value under the pre-race forecast price.

#### The context that makes `b_mod` readable

`b_mod` measures what the model adds *to the price it is blended with*. It is not a measure of how good the blend is. Ranking every fit on the same races by log-likelihood puts the size of `b_mod(A)` in proportion:

| fit | logLik | mcfadden_r2 |
|---|---|---|
| blend B1 — starting price + paper 2b (exploded conditional logit) | -1955 | 0.1383 |
| blend B2 — starting price + paper 3 (gradient boosted trees) | -1956 | 0.1381 |
| market only — starting price | -1957 | 0.1378 |
| blend C2 — archived forecast + paper 3 (gradient boosted trees) | -2084 | 0.08139 |
| blend C1 — archived forecast + paper 2b (exploded conditional logit) | -2089 | 0.07953 |
| blend A2 — pre-race feed forecast + paper 3 (gradient boosted trees) | -2093 | 0.07745 |
| blend A1 — pre-race feed forecast + paper 2b (exploded conditional logit) | -2098 | 0.07562 |
| market only — archived forecast | -2126 | 0.06314 |
| market only — pre-race feed forecast | -2150 | 0.05256 |

The starting price on its own (McFadden 0.1378) beats every blend built on the morning forecast price (best 0.0774). So a large `b_mod` on arm A does not say the model is close to the market — it says the model adds a great deal to a *weak* price. The morning price is the weak thing here.

### 4.4 Amendment 3 — observed against pre-registered expectations

| quantity | expected | observed |
|---|---|---|
| b_mkt on arm A (pre-race feed forecast), paper 2b | ~1.8 | 0.2784 |
| b_mkt on arm A (pre-race feed forecast), paper 3 | ~1.8 | 0.3285 |
| b_mkt on arm B (starting price), paper 2b | ~1.0-1.1 | 1.09 |
| b_mkt on arm B (starting price), paper 3 | ~1.0-1.1 | 1.102 |

Anchors for interpretation, not thresholds. Nothing was adjusted to move an observed value toward an expected one.

`b_mkt(B)` lands inside its pre-registered range. **`b_mkt(A)` misses its anchor badly, and in the opposite direction**: expected ~1.8, observed 0.28 and 0.33.

This is not the model term stealing the coefficient. Fitted market-only, with no model term competing for the likelihood, `b_mkt(A)` is 0.8846 — still below 1, still nowhere near 1.8.

The anchor assumed one force and there are two. A book that is *compressed* relative to the truth wants an exponent above 1 to sharpen it back up; a book measured with *noise* wants an exponent below 1 to shrink it. The 0.554 within-race slope measured the compression only, because it regressed the forecast book on SP rather than on outcomes. Fitted against outcomes, the two forces oppose, and the observed exponent below 1 says the noise dominates the compression. That is consistent with everything else here: the morning book is not merely a flattened SP, it is a substantially noisier price.

### 4.5 `b_mkt` on the SP arms as a favourite-longshot exponent

Reading `b_mkt` from the SP fits directly: paper 2b gives 1.0904 (SE 0.0659), paper 3 gives 1.1016 (SE 0.0668). The market-only SP fit, with no model term competing for the likelihood, gives 1.1560.

Levey reports approximately 1.10 for US pari-mutuel odds. US odds come from a pari-mutuel pool and UK SP from bookmaker markets, so a difference between the two is expected and is not evidence of an error.

## 5. Amendment 4 — does `b_mod` survive a flexible market term on arm A?

A single `b_mkt` absorbs a power-law miscalibration but not one that varies with field size, and P4-0 found the forecast book's overround running from 1.071 at four runners to 1.323 at sixteen. Two flexible market specifications, each tested against its own market-only model so the LR isolates the model term: a natural spline in `log(P_mkt)` (df = 4), and `log(P_mkt)` interacted with mean-centred field size.

Model-term coefficients under the flexible market specifications:

| arm | term | b_mod | std_error | z | p_value | logLik | mcfadden_r2 |
|---|---|---|---|---|---|---|---|
| A1-spline | log_p_mod_2b | 1.047 | 0.1031 | 10.15 | <2e-16 | -2095 | 0.07695 |
| A1-fieldint | log_p_mod_2b | 1.038 | 0.103 | 10.08 | <2e-16 | -2098 | 0.07563 |
| A2-spline | log_p_mod_3 | 1.034 | 0.09886 | 10.46 | <2e-16 | -2091 | 0.07866 |
| A2-fieldint | log_p_mod_3 | 1.028 | 0.09877 | 10.4 | <2e-16 | -2093 | 0.07746 |


Likelihood-ratio tests, blend against market-only under the same flexible market term:

| contrast | logLik_full | logLik_reduced | lr_stat | df | p_value |
|---|---|---|---|---|---|
| A1 spline: blend vs market-only | -2095 | -2148 | 106.1 | 1 | <2e-16 |
| A1 field interaction: blend vs market-only | -2098 | -2150 | 104.5 | 1 | <2e-16 |
| A2 spline: blend vs market-only | -2091 | -2148 | 113.9 | 1 | <2e-16 |
| A2 field interaction: blend vs market-only | -2093 | -2150 | 112.9 | 1 | <2e-16 |


`b_mod` under the flexible market term, against `b_mod` from the linear-market arm on the same races:

| arm | b_mod_flexible | b_mod_linear_market | retained |
|---|---|---|---|
| A1-spline | 1.047 | 1.037 | 1.01 |
| A1-fieldint | 1.038 | 1.037 | 1.002 |
| A2-spline | 1.034 | 1.026 | 1.008 |
| A2-fieldint | 1.028 | 1.026 | 1.002 |


**`b_mod` survives.** It retains at least 100% of its linear-market value under both flexible specifications, so it is not an artefact of the market term being too rigid to absorb a field-size-dependent margin.

## 6. Test-B replication, and the pooled estimate

Test-B was reserved to evaluate blend performance. The null against SP made that question moot, so it is spent here on the higher-value use: an independent replication of `b_mod` on 1087 races, same specification, no refits of either underlying model and no selection of any kind.

**This consumes the reservation.** After this section there is no held-out race set left in the paper-4 universe, and any further specification choice made in light of these numbers would be selection on data already seen.

### 6.1 `b_mod`, test-A against test-B

| arm | price_source | b_mod_A | se_A | b_mod_B | se_B | difference | se_diff | z_diff | p_diff |
|---|---|---|---|---|---|---|---|---|---|
| A1 | pre-race feed forecast | 1.037 | 0.1027 | 0.746 | 0.1018 | 0.2906 | 0.1446 | 2.009 | 0.04449 |
| A2 | pre-race feed forecast | 1.026 | 0.09845 | 0.7233 | 0.09419 | 0.3025 | 0.1362 | 2.22 | 0.02639 |
| B1 | starting price | 0.1516 | 0.09783 | -0.01481 | 0.09801 | 0.1664 | 0.1385 | 1.201 | 0.2296 |
| B2 | starting price | 0.1242 | 0.0998 | -0.04006 | 0.09638 | 0.1643 | 0.1387 | 1.184 | 0.2363 |
| C1 | archived forecast | 0.8842 | 0.1033 | 0.6197 | 0.104 | 0.2645 | 0.1466 | 1.804 | 0.07118 |
| C2 | archived forecast | 0.8963 | 0.1001 | 0.6169 | 0.09619 | 0.2794 | 0.1388 | 2.013 | 0.04407 |

The halves are disjoint race sets, so the two estimates are independent and the difference has variance `se_A^2 + se_B^2`. `z_diff` tests the difference directly, which is the right check — two intervals can overlap while the difference is still distinguishable, and vice versa.

**The answer differs by price column, so it has to be given twice.**

- **The SP arms agree.** Neither B1 nor B2 shows a difference between halves distinguishable from zero (p = 0.23 and 0.24), and both estimates sit near zero in each half (0.152 / 0.124 on test-A against -0.015 / -0.040 on test-B). **Pooling is justified for the SP arms**, and it is the pooling that matters, since the SP null is the paper's result.
- **The forecast-price arms do not.** 3 of 4 (A1, A2, C2) differ between halves at the 5% level, and the one that does not (C1) is marginal at p = 0.071. `b_mod` falls from about 1.03 to about 0.73 on the arm-A pair between the earlier and later half. This is not six independent coin flips coming up odd: all four forecast arms move the same way on `b_mod`, and all four move the same way on `b_mkt` (section 6.2, every p below 0.02). That is a systematic shift over time, not multiple-comparison noise.
- **So the pooled forecast-price figures are not a single population parameter** and should not be read as one. They are reported below for completeness and used in section 7 only as a ratio between two columns measured on identical races, where the drift affects numerator and denominator alike.

Direction of the drift, stated but not explained: between the earlier and later half the morning price gets *better* (`b_mkt(A)` rises from about 0.30 to about 0.61) and the model adds correspondingly less. The SP arms show no such movement. Diagnosing it would need work outside this follow-up's scope, and would be selection on a set that no longer has a held-out counterpart.

### 6.2 `b_mkt`, test-A against test-B

| arm | price_source | b_mkt_A | b_mkt_B | difference | se_diff | z_diff | p_diff |
|---|---|---|---|---|---|---|---|
| A1 | pre-race feed forecast | 0.2784 | 0.5934 | -0.315 | 0.1195 | -2.637 | 0.008361 |
| A2 | pre-race feed forecast | 0.3285 | 0.6307 | -0.3021 | 0.1127 | -2.681 | 0.007334 |
| B1 | starting price | 1.09 | 1.186 | -0.0958 | 0.09249 | -1.036 | 0.3003 |
| B2 | starting price | 1.102 | 1.197 | -0.09547 | 0.09307 | -1.026 | 0.305 |
| C1 | archived forecast | 0.4564 | 0.7547 | -0.2983 | 0.1249 | -2.389 | 0.01688 |
| C2 | archived forecast | 0.4815 | 0.7759 | -0.2943 | 0.1183 | -2.488 | 0.01283 |


### 6.3 The pooled fit on all 2182 races

| arm | price_source | coefficient | estimate | std_error | conf_low | conf_high | z | p_value |
|---|---|---|---|---|---|---|---|---|
| A1 | pre-race feed forecast | b_mkt | 0.4311 | 0.05962 | 0.3143 | 0.548 | 7.231 | 4.78e-13 |
| A2 | pre-race feed forecast | b_mkt | 0.4762 | 0.05626 | 0.366 | 0.5865 | 8.465 | <2e-16 |
| B1 | starting price | b_mkt | 1.139 | 0.04621 | 1.048 | 1.23 | 24.65 | <2e-16 |
| B2 | starting price | b_mkt | 1.151 | 0.04648 | 1.06 | 1.242 | 24.77 | <2e-16 |
| C1 | archived forecast | b_mkt | 0.5965 | 0.06228 | 0.4745 | 0.7186 | 9.579 | <2e-16 |
| C2 | archived forecast | b_mkt | 0.6226 | 0.05902 | 0.507 | 0.7383 | 10.55 | <2e-16 |
| A1 | pre-race feed forecast | b_mod | 0.8928 | 0.07227 | 0.7511 | 1.034 | 12.35 | <2e-16 |
| A2 | pre-race feed forecast | b_mod | 0.8717 | 0.06803 | 0.7384 | 1.005 | 12.81 | <2e-16 |
| B1 | starting price | b_mod | 0.06834 | 0.06919 | -0.06728 | 0.204 | 0.9877 | 0.323 |
| B2 | starting price | b_mod | 0.0391 | 0.06924 | -0.0966 | 0.1748 | 0.5648 | 0.572 |
| C1 | archived forecast | b_mod | 0.7568 | 0.07327 | 0.6132 | 0.9004 | 10.33 | <2e-16 |
| C2 | archived forecast | b_mod | 0.7556 | 0.06928 | 0.6198 | 0.8913 | 10.91 | <2e-16 |


Side by side across all three race sets, `b_mod` only:

| arm | price_source | sample | estimate | std_error | conf_low | conf_high | z |
|---|---|---|---|---|---|---|---|
| A1 | pre-race feed forecast | pooled | 0.8928 | 0.07227 | 0.7511 | 1.034 | 12.35 |
| A1 | pre-race feed forecast | test-A | 1.037 | 0.1027 | 0.8353 | 1.238 | 10.09 |
| A1 | pre-race feed forecast | test-B | 0.746 | 0.1018 | 0.5466 | 0.9455 | 7.331 |
| A2 | pre-race feed forecast | pooled | 0.8717 | 0.06803 | 0.7384 | 1.005 | 12.81 |
| A2 | pre-race feed forecast | test-A | 1.026 | 0.09845 | 0.8329 | 1.219 | 10.42 |
| A2 | pre-race feed forecast | test-B | 0.7233 | 0.09419 | 0.5387 | 0.9079 | 7.679 |
| B1 | starting price | pooled | 0.06834 | 0.06919 | -0.06728 | 0.204 | 0.9877 |
| B1 | starting price | test-A | 0.1516 | 0.09783 | -0.04017 | 0.3433 | 1.549 |
| B1 | starting price | test-B | -0.01481 | 0.09801 | -0.2069 | 0.1773 | -0.1511 |
| B2 | starting price | pooled | 0.0391 | 0.06924 | -0.0966 | 0.1748 | 0.5648 |
| B2 | starting price | test-A | 0.1242 | 0.0998 | -0.07136 | 0.3199 | 1.245 |
| B2 | starting price | test-B | -0.04006 | 0.09638 | -0.229 | 0.1488 | -0.4157 |
| C1 | archived forecast | pooled | 0.7568 | 0.07327 | 0.6132 | 0.9004 | 10.33 |
| C1 | archived forecast | test-A | 0.8842 | 0.1033 | 0.6817 | 1.087 | 8.556 |
| C1 | archived forecast | test-B | 0.6197 | 0.104 | 0.416 | 0.8235 | 5.961 |
| C2 | archived forecast | pooled | 0.7556 | 0.06928 | 0.6198 | 0.8913 | 10.91 |
| C2 | archived forecast | test-A | 0.8963 | 0.1001 | 0.7002 | 1.092 | 8.959 |
| C2 | archived forecast | test-B | 0.6169 | 0.09619 | 0.4284 | 0.8054 | 6.413 |


**The SP null after pooling — the result this follow-up was for.** `b_mod` against SP is 0.0683 (95% CI [-0.067, 0.204], z = 0.99) for paper 2b and 0.0391 (95% CI [-0.097, 0.175], z = 0.56) for paper 3.

The null is now much stronger than it was on test-A alone, and in the way that counts. The SP estimates did not merely stay insignificant — they moved *toward* zero (paper 2b 0.152 on test-A, -0.015 on test-B, 0.068 pooled) while the interval narrowed by 29% — the factor of sqrt(2) that doubling the sample buys, not more. On test-A the data could not exclude a `b_mod` against SP as large as 0.343; pooled, the ceiling is 0.204.

To put that ceiling in proportion rather than leave it as a bare number: 0.204 is 23% of the pooled arm-A value (0.893) and 28% of the *smallest* arm-A estimate seen on either half (0.723). So the data exclude a model contribution against SP larger than roughly a quarter to a third of what the same model contributes against the morning price — on the most conservative comparison available, not the most flattering one.

This is what a real null looks like rather than an underpowered one: the centres stayed put near zero while the precision improved.

## 7. Arm A as an upper bound, not a point estimate

Standalone `b_mkt(A)` is 0.8846, below 1. A market term below 1 says the price is over-dispersed — measured with noise — and errors-in-variables then attenuates `b_mkt` and leaves signal for `b_mod` to absorb that properly belongs to the market. Arm A's `b_mod` is inflated by exactly that much.

Arm C prices the same races with a demonstrably less noisy column, so the A-to-C gap is the natural bound on the inflation:

| sample | model_source | b_mod_A | b_mod_C | b_mod_B | gap_A_minus_C | pct_of_A_that_is_gap |
|---|---|---|---|---|---|---|
| test-A | paper 2b (exploded conditional logit) | 1.037 | 0.8842 | 0.1516 | 0.1524 | 0.147 |
| test-A | paper 3 (gradient boosted trees) | 1.026 | 0.8963 | 0.1242 | 0.1295 | 0.1262 |
| test-B | paper 2b (exploded conditional logit) | 0.746 | 0.6197 | -0.01481 | 0.1263 | 0.1693 |
| test-B | paper 3 (gradient boosted trees) | 0.7233 | 0.6169 | -0.04006 | 0.1064 | 0.1471 |
| pooled | paper 2b (exploded conditional logit) | 0.8928 | 0.7568 | 0.06834 | 0.136 | 0.1523 |
| pooled | paper 3 (gradient boosted trees) | 0.8717 | 0.7556 | 0.0391 | 0.1162 | 0.1333 |


**Reading.** `b_mod(A)` should be read as an **upper bound** on the model's value against the morning market, not a point estimate. On the pooled fit the gap is 0.136 and 0.116 — 15% and 13% of arm A's coefficient.

One qualification on the direction of that bound. Arm C differs from arm A in **two** ways, not one: it is less noisy, and per amendment 2 it genuinely knows more. Both push `b_mod(C)` down. So the gap is an upper bound on the attenuation rather than an estimate of it, and the value a clean, well-measured *morning* price would give lies between the two. The defensible object is the bracket [0.757, 0.893] and [0.756, 0.872], not either endpoint.

This does not touch the SP conclusion. Both ends of the bracket sit far above the pooled SP estimates of 0.068 and 0.039, and outside their confidence intervals entirely. Whatever share of arm A is measurement noise, the contrast between the morning price and the off survives it.

## 8. Surprises, and decisions taken without instruction

- The test-B replication did not come out clean. The SP arms replicated and pooled properly, which is the result the paper turns on. The forecast-price arms did not: `b_mod` on arm A falls from about 1.03 to about 0.73 between the halves, with `b_mkt(A)` rising to match, and all four forecast arms move together. Reported as a systematic drift and the pooled forecast figures flagged as not a single parameter, rather than pooled quietly.
- The pre-registered `b_mkt(A)` anchor of ~1.8 was wrong, and wrong for a reason worth keeping: it read the P4-0 compression slope as if compression were the only thing an outcome-fitted exponent has to handle. Price noise pulls the same coefficient the other way, and on the morning book it wins. See section 4.4.
- Amendment 2's two-regressor fit returned a *negative* feed coefficient rather than a null one, which neither branch of the pre-registered reading covers. Reported as a suppression pattern under high collinearity, with the standalone fits and the correlations given alongside so the claim rests on the likelihood-ratio tests rather than on a single unstable coefficient.
- The audited column was the wrong one. `historic_runners.forecast_price_decimal` is written on or after the meeting date on 100% of in-scope rows (minimum lag one day), disagrees with the pre-race `daily_runners` snapshot on 32.5% of them, and where it disagrees it sits significantly closer to SP. This was not on the P4-0 checklist and is the reason the arm list grew a third member.
- The overround was computed over the final field by default, then over the declared field once item 5 showed the book is struck before withdrawals. The sub-1.00 books in the first audit are entirely a withdrawal artefact: 20.9% of races with a Non-Runner fall below 1.00 on the final field against 0.77% of races without one, and 0% fall below 1.00 on the declared field.
- The test-A / test-B boundary is a calendar date rather than a row index, so the split is reproducible against an exact date the way the series' 2012-12-30 train/test cutoff is. Races on the cutoff date fall in test-A.
- McFadden's pseudo-R-squared is computed against the equal-probability null (`-sum(log n_j)`) rather than taken from `{mlogit}`, whose own figure is referenced to an intercept-only model that does not exist in a no-intercept conditional logit.
- Paper 4 runs in its own store (`_targets_p4`) off its own script (`_targets_p4.R`), passed to `tar_make()` explicitly rather than through `_targets.yaml`, which the paper qmd setup chunks own. Upstream targets are read from the main store read-only, with their content hashes recorded in `p4_upstream_fingerprint` so a change upstream invalidates everything here rather than going unnoticed.

