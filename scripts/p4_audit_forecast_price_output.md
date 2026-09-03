# Paper 4 / stage P4-0 — audit of `forecast_price_decimal`

Generated: 2026-08-28 11:01:55 BST

Read-only. Source: Smartform `historic_runners` / `daily_runners`, plus the main `_targets` store (read, never written).

Universe anchors: `qualifying_races` = 7441 races, `qualifying_runners` = 66770 runner-rows; ranking test universe (races in `test_predictions_3`) = 2183 races.

Raw `historic_runners` rows pulled for those races (Non-Runners still in): 71170.

## Item 1 — where the column lives, its type, and its timing semantics

### Schema location of the price columns

| TABLE_NAME | COLUMN_NAME | COLUMN_TYPE | IS_NULLABLE |
|---|---|---|---|
| daily_races | loaded_at | timestamp | NO |
| daily_runners | forecast_price | char(10) | YES |
| daily_runners | forecast_price_decimal | float(8,2) | YES |
| daily_runners | loaded_at | timestamp | NO |
| historic_races | loaded_at | timestamp | NO |
| historic_runners | forecast_price | char(10) | YES |
| historic_runners | forecast_price_decimal | float(8,2) | YES |
| historic_runners | loaded_at | timestamp | NO |
| historic_runners | position_in_betting | tinyint | YES |
| historic_runners | starting_price | char(10) | YES |
| historic_runners | starting_price_decimal | float(8,2) | YES |

**Timing evidence 1 — which tables carry which price.** `starting_price` / `starting_price_decimal` exist ONLY on `historic_runners`. `forecast_price` / `forecast_price_decimal` exist on BOTH `historic_runners` and `daily_runners`. `daily_runners` is the forward-looking feed table (today's declared cards), so the forecast price is a field the feed publishes *before* the race and the starting price is not.

Columns in `historic_runners` but NOT in `daily_runners` (the post-race additions): `distance_travelled`, `num_fences_jumped`, `how_easy_won`, `in_race_comment`, `official_rating_type`, `speed_rating`, `speed_rating_type`, `private_handicap`, `private_handicap_type`, `owner_id`, `dam_id`, `sire_id`, `dam_sire_id`, `starting_price`, `starting_price_decimal`, `betting_text`, `position_in_betting`, `finish_position`, `amended_position`, `unfinished`, `distance_beaten`, `distance_won`, `distance_behind_winner`, `prize_money`, `tote_win`, `tote_place`, `last_race_type_id`, `last_race_type`, `last_race_beaten_fav`, `penalty_weight`, `over_weight`.

Columns in `daily_runners` but NOT in `historic_runners`: `form_type`, `adjusted_rating`, `jockey_colours`, `dam_year_born`, `sire_year_born`, `dam_sire_year_born`, `days_since_ran_type`, `weight_penalty`, `course_winner`, `distance_winner`, `candd_winner`, `beaten_favourite`.

### `daily_races` date span

| min_date | max_date | n_races |
|---|---|---|
| 2008-03-01 | 2015-10-17 | 99848 |

**Timing evidence 2 — daily feed vs archive, same runner-race.** Rows appearing in both `daily_runners` and `historic_runners` on (runner_id, race_id): 1017161. Of those, 847109 carry an identical `forecast_price_decimal` and 847109 an identical `forecast_price` string.

### `forecast_price` (char) value ladder, in-scope races

Distinct `forecast_price` strings: 67. Distinct `starting_price` strings on the same rows: 66.

Top 25 `forecast_price` strings:

| forecast_price | n |
|---|---|
| 10/1 | 7172 |
| 8/1 | 6410 |
| 12/1 | 6268 |
| 14/1 | 5401 |
| 16/1 | 5077 |
| 6/1 | 4462 |
| 7/1 | 4438 |
| 5/1 | 3833 |
| 20/1 | 3701 |
| 4/1 | 3037 |
| 25/1 | 2816 |
| 9/2 | 2295 |
| 7/2 | 2207 |
| 11/2 | 1778 |
| 3/1 | 1727 |
| 13/2 | 1253 |
| 33/1 | 1212 |
| 11/4 | 1157 |
| 5/2 | 898 |
| 9/4 | 794 |
| 2/1 | 594 |
| 15/2 | 550 |
| 7/4 | 325 |
| 10/3 | 312 |
| 50/1 | 281 |

Non-fractional / non-numeric `forecast_price` strings (e.g. 'NR', 'SP', 'EVS'): 1 distinct: `-214748364` (n=2)

`forecast_price_decimal` = fraction + 1 (stake included)? 69383 of 69383 rows agree to within 0.011 (100.00%). Confirms decimal-odds semantics, not net odds.

### Granularity: distinct values in scope

| column | n_distinct_values |
|---|---|
| forecast_price_decimal | 66 |
| starting_price_decimal | 65 |

### `loaded_at` on the archive rows

| min | max | n_distinct_days |
|---|---|---|
| 2008-10-22 14:13:46 | 2015-10-15 04:00:07 | 1628 |

`loaded_at` is an archive-load stamp, not a price stamp: it carries no information about when the forecast price itself was set, and is reported here only to rule it out as a timing source.

## Item 2 — coverage

"Usable" = non-NA and strictly greater than 1 (a decimal price of 1 or below implies a probability of 1 or more and cannot be normalised).

### Runner-row coverage

| split | runner_rows | fp_usable | fp_pct | sp_usable | sp_pct |
|---|---|---|---|---|---|
| test | 18877 | 18877 | 1 | 18877 | 1 |
| train | 47893 | 46909 | 0.9795 | 47880 | 0.9997 |
| ALL | 66770 | 65786 | 0.9853 | 66757 | 0.9998 |

### Race-level coverage — every runner priced

| split | races | fp_races | fp_pct | sp_races | sp_pct |
|---|---|---|---|---|---|
| test | 2232 | 2232 | 1 | 2232 | 1 |
| train | 5209 | 5093 | 0.9777 | 5197 | 0.9977 |
| ALL | 7441 | 7325 | 0.9844 | 7429 | 0.9984 |

### The 2,183-race ranking test universe (the abort-condition target)

| races | every_runner_forecast | pct_forecast_complete | every_runner_sp | pct_sp_complete |
|---|---|---|---|---|
| 2183 | 2183 | 1 | 2183 | 1 |

### Coverage by year (all in-scope races, both splits)

| year | races | runner_rows | fp_row_pct | sp_row_pct | fp_race_complete_pct | sp_race_complete_pct |
|---|---|---|---|---|---|---|
| 2006 | 635 | 6404 | 0.8707 | 0.9983 | 0.8457 | 0.9843 |
| 2007 | 685 | 6472 | 0.9759 | 0.9997 | 0.9737 | 0.9971 |
| 2008 | 728 | 6427 | 1 | 1 | 1 | 1 |
| 2009 | 839 | 7543 | 1 | 1 | 1 | 1 |
| 2010 | 819 | 7322 | 1 | 1 | 1 | 1 |
| 2011 | 690 | 6201 | 1 | 1 | 1 | 1 |
| 2012 | 816 | 7548 | 1 | 1 | 1 | 1 |
| 2013 | 830 | 7074 | 1 | 1 | 1 | 1 |
| 2014 | 872 | 7347 | 1 | 1 | 1 | 1 |
| 2015 | 527 | 4432 | 1 | 1 | 1 | 1 |

Pre-2013 runner-row coverage 97.95% vs 2013-onward 100.00% — difference 2.05 percentage points.

## Item 3 — overround

Race overround = sum over the field of 1 / price, computed on races where EVERY runner is priced so the sum is over a complete book. Distributional statistics are TRAINING split only.

### Overround distribution — TRAINING split, complete books

| source | races | min | p25 | median | p75 | iqr | max | mean |
|---|---|---|---|---|---|---|---|---|
| forecast price | 5093 | 0.3318 | 1.101 | 1.156 | 1.207 | 0.1063 | 2.424 | 1.141 |
| starting price | 5197 | 0.5934 | 1.129 | 1.163 | 1.201 | 0.07177 | 1.562 | 1.168 |

Races complete in both books (training split): 5081. Median paired difference (forecast - SP): -0.0036; mean -0.0266.

### Overround trend across the window (all races, complete books)

| year | races_fp | median_or_fp | iqr_or_fp | races_sp | median_or_sp | iqr_or_sp |
|---|---|---|---|---|---|---|
| 2006 | 537 | 1.183 | 0.09619 | 625 | 1.176 | 0.07534 |
| 2007 | 667 | 1.148 | 0.1051 | 683 | 1.176 | 0.07644 |
| 2008 | 728 | 1.143 | 0.1111 | 728 | 1.169 | 0.08679 |
| 2009 | 839 | 1.158 | 0.1055 | 839 | 1.163 | 0.0663 |
| 2010 | 819 | 1.149 | 0.1119 | 819 | 1.152 | 0.06847 |
| 2011 | 690 | 1.161 | 0.1001 | 690 | 1.15 | 0.05855 |
| 2012 | 816 | 1.165 | 0.1046 | 816 | 1.161 | 0.06481 |
| 2013 | 830 | 1.147 | 0.1016 | 830 | 1.163 | 0.0678 |
| 2014 | 872 | 1.151 | 0.08839 | 872 | 1.16 | 0.06956 |
| 2015 | 527 | 1.149 | 0.08188 | 527 | 1.147 | 0.06556 |

### Overround by field size (training split)

| n_runners | races | median_or_fp | median_or_sp |
|---|---|---|---|
| 4 | 139 | 1.071 | 1.089 |
| 5 | 280 | 1.094 | 1.1 |
| 6 | 487 | 1.116 | 1.116 |
| 7 | 564 | 1.135 | 1.132 |
| 8 | 679 | 1.149 | 1.149 |
| 9 | 641 | 1.169 | 1.16 |
| 10 | 588 | 1.186 | 1.175 |
| 11 | 580 | 1.201 | 1.19 |
| 12 | 567 | 1.232 | 1.202 |
| 13 | 359 | 1.242 | 1.215 |
| 14 | 187 | 1.284 | 1.24 |
| 15 | 10 | 1.274 | 1.232 |
| 16 | 12 | 1.323 | 1.25 |

## Item 4 — shape of the forecast book versus SP

Both books proportionally overround-normalised within race (the same adjustment `build_test_predictions()` applies to SP: p_i = (1/price_i) / sum_j (1/price_j)). Restricted to TRAINING-split races complete in both books. Regression of log p_forecast on log p_SP.

Rows: 46614 runners across 5081 training races.

| specification | slope | std_error | r_squared |
|---|---|---|---|
| pooled OLS (with intercept) | 0.6038 | 0.00248 | 0.5599 |
| within-race (race FE, demeaned) | 0.5544 | 0.002566 | 0.5004 |

The within-race specification is the one P4-0 asks for; the pooled fit is reported alongside as a sanity check.

### Within-race comparison by SP-probability decile (training split)

| sp_decile | n | median_p_sp | median_p_fp | mean_log_ratio |
|---|---|---|---|---|
| 1 | 4662 | 0.02296 | 0.03989 | 0.6829 |
| 2 | 4662 | 0.03739 | 0.05501 | 0.4338 |
| 3 | 4662 | 0.04982 | 0.06386 | 0.2829 |
| 4 | 4662 | 0.06299 | 0.0749 | 0.2002 |
| 5 | 4661 | 0.07771 | 0.08645 | 0.0888 |
| 6 | 4661 | 0.09556 | 0.09748 | -0.005492 |
| 7 | 4661 | 0.1143 | 0.1091 | -0.07001 |
| 8 | 4661 | 0.1445 | 0.1246 | -0.1629 |
| 9 | 4661 | 0.187 | 0.1477 | -0.2536 |
| 10 | 4661 | 0.2739 | 0.2169 | -0.3297 |

`mean_log_ratio` > 0 in a decile means the forecast book assigns MORE probability there than SP does.

## Item 5 — declared field or final field?

### Are Non-Runners priced?

| row_class | rows | fp_priced | fp_pct | sp_priced | sp_pct |
|---|---|---|---|---|---|
| starter | 66770 | 65786 | 0.9853 | 66757 | 0.9998 |
| Non-Runner | 4400 | 3597 | 0.8175 | 17 | 0.003864 |

A Non-Runner carrying a forecast price but no starting price is the signature of a price stated against the DECLARED field: the forecast is published before withdrawals are known; the SP is returned only for horses that actually started.

### Runner-set comparison: forecast-priced set vs the pipeline's field

| scope | races | exact_set_match_pct | every_used_runner_priced_pct | mismatch_pct |
|---|---|---|---|---|
| all in-scope races | 7441 | 0.6111 | 0.9844 | 0.3889 |
| training split | 5209 | 0.6047 | 0.9777 | 0.3953 |
| test split | 2232 | 0.6259 | 1 | 0.3741 |
| ranking test universe | 2183 | 0.6262 | 1 | 0.3738 |

Decomposition of the mismatch (all in-scope races):

| condition | races_affected | pct_of_races |
|---|---|---|
| priced runner NOT in the pipeline field (a withdrawal, or a row the pipeline dropped) | 2785 | 0.3743 |
| pipeline runner NOT priced (a genuine coverage hole) | 116 | 0.01559 |

The two conditions are materially different. The first is expected and harmless *given* proportional renormalisation over the runners actually used: it means the morning book was struck over a larger field. The second is what actually costs races in P4-1.

Priced runner-rows not used by the pipeline: 3597, of which 100.00% are flagged `unfinished = 'Non-Runner'` (the remainder are rows the pipeline's own race-level filters removed).

## Abort conditions

| condition | observed | verdict |
|---|---|---|
| < 70% of the 2,183 test-universe races have every runner priced | 100.00% of races complete | pass |
| median race overround outside 1.05 to 1.60 | median = 1.1564 | pass |
| pre-2013 coverage differs from 2013-onward by > 20 percentage points | 2.05 pp | pass |
| runner-set mismatch (item 5) above 5% of races | 38.89% | **ABORT** |


**AT LEAST ONE ABORT CONDITION FIRED. P4-1 must not proceed on the stated design.**

