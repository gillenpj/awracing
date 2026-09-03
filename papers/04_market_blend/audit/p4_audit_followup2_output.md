# P4-0 follow-ups, part 2

Generated: 2026-08-28 10:58:45 BST

## D0. When was each row written, relative to the race?

`loaded_at` stamps the row, not the price. But if the daily-feed row is written before the meeting and the archive row after it, then the archive's forecast price was *transcribed* post-race — which is the circumstance under which a difference between the two could carry hindsight, and is therefore worth establishing before reading the revision direction in D.

| case | rows |
|---|---|
| daily_before_meeting | 51485 |
| daily_on_or_after | 3986 |
| hist_before_meeting | 0 |
| hist_on_or_after | 55471 |
| n | 55471 |

Row-write lag relative to `meeting_date`, in days (negative = written before the meeting):

| mean_daily_lag_days | min_daily_lag_days | max_daily_lag_days | mean_hist_lag_days | min_hist_lag_days | max_hist_lag_days |
|---|---|---|---|---|---|
| 5.829 | -3 | 234 | 10.048 | 1 | 863 |


## D. Which way does the feed-to-archive revision run?

If the archived `forecast_price_decimal` were a late or post-race revision, it would sit systematically closer to the starting price than the daily-feed value does. Test on TRAINING-split runner-rows where the feed value, the archive value and the SP are all present and the feed and archive disagree.

Training-split runner-rows with feed + archive + SP all present: 32898, of which 10691 (32.50%) have feed and archive disagreeing.

### Distance to SP on |log price| scale, rows where feed and archive disagree

| quantity | value |
|---|---|
| mean |log fp_feed - log sp| | 0.44779 |
| mean |log fp_arch - log sp| | 0.395 |
| mean difference (archive - feed) | -0.052794 |
| share of rows where archive is CLOSER to SP than feed | 0.58984 |

Paired t-test on the per-row difference (archive - feed) in distance to SP: mean -0.05279, 95% CI [-0.05766, -0.04793], t = -21.27, p = <2e-16.

A mean near zero and a ~50% share means the revision is noise around the same target, not convergence toward SP. A clearly negative mean and a share well above 50% would mean the archive value has drifted toward the result-side price and could not be treated as the morning price.

### Size of the revision, in ladder steps

| n | p05 | p25 | median | p75 | p95 | mean | sd |
|---|---|---|---|---|---|---|---|
| 10691 | -0.48551 | -0.20067 | -0.068993 | 0.16705 | 0.38299 | -0.03441 | 0.29266 |

Symmetric around zero would say the archive is a re-forecast, not a correction in a known direction.

### Which value correlates better with the outcome?

| price_source | mean_log_price_winners | mean_log_price_losers | separation |
|---|---|---|---|
| daily feed forecast | 1.915 | 2.2347 | 0.31969 |
| archive forecast | 1.8579 | 2.2034 | 0.34552 |
| starting price | 1.7163 | 2.3144 | 0.59814 |

Larger `separation` = the price discriminates winners from losers more sharply on these rows. Reported as a descriptive check on the training split only; it is not a model fit and nothing downstream is selected on it.

## E. Overround over the declared field vs the final field

### Training split, forecast book

| basis | races | p25 | median | p75 | min | max |
|---|---|---|---|---|---|---|
| declared field (as struck) | 4624 | 1.148 | 1.1895 | 1.2412 | 0.54545 | 2.4242 |
| final field (pipeline runner set) | 5093 | 1.1006 | 1.1564 | 1.2069 | 0.33178 | 2.4242 |

### Split by whether the race had a withdrawal (training split, final-field basis)

| had_non_runner | races | median_or_final | median_or_declared | pct_under_1 |
|---|---|---|---|---|
| FALSE | 2867 | 1.1831 | 1.1831 | 0.0076735 |
| TRUE | 2226 | 1.0986 | 1.2092 | 0.20889 |

This is the whole story behind the sub-1.00 books in the main audit: removing a withdrawn runner removes its share of the book, so a race struck at ~1.16 over the declared field falls below 1.00 over the final field once enough runners come out. It is an artefact of the field change, not a malformed price. Proportional renormalisation over the final field is unaffected — it rescales to sum 1 either way.

### Ranking test universe, final-field basis

| races | median | p25 | p75 | pct_under_1 | pct_over_1.6 |
|---|---|---|---|---|---|
| 2183 | 1.1487 | 1.1024 | 1.1917 | 0.099863 | 0 |

### Ranking test universe, declared-field basis

| races | median | p25 | p75 | pct_under_1 | pct_over_1.6 |
|---|---|---|---|---|---|
| 1941 | 1.1826 | 1.1465 | 1.2242 | 0 | 0 |

