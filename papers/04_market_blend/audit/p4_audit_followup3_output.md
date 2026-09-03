# P4-0 follow-ups, part 3 — the pre-race `daily_runners` price as a substitute

Generated: 2026-08-28 11:00:10 BST

## Coverage of the daily-feed price on the pipeline's runner set

`fp_feed` = `daily_runners.forecast_price_decimal`. `fp_feed_prerace` additionally requires the feed row to have been written strictly before the meeting date.

| split | runner_rows | fp_arch_pct | fp_feed_pct | fp_feed_prerace_pct |
|---|---|---|---|---|
| test | 18877 | 1 | 0.99984 | 0.99984 |
| train | 47893 | 0.97945 | 0.68691 | 0.609 |
| ALL | 66770 | 0.98526 | 0.77538 | 0.7195 |

### By year

| year | runner_rows | fp_arch_pct | fp_feed_pct | fp_feed_prerace_pct |
|---|---|---|---|---|
| 2006 | 6404 | 0.87071 | 0 | 0 |
| 2007 | 6472 | 0.9759 | 0 | 0 |
| 2008 | 6427 | 1 | 0.75914 | 0.25642 |
| 2009 | 7543 | 1 | 0.96686 | 0.9418 |
| 2010 | 7322 | 1 | 0.97023 | 0.94892 |
| 2011 | 6201 | 1 | 0.98339 | 0.97742 |
| 2012 | 7548 | 1 | 1 | 0.98437 |
| 2013 | 7074 | 1 | 1 | 1 |
| 2014 | 7347 | 1 | 1 | 1 |
| 2015 | 4432 | 1 | 0.99932 | 0.99932 |

`daily_races` only starts 2008-03-01, so the feed price is structurally absent before then. The test split starts 2012-12-30, well inside the feed's span, which is what matters for P4-2.

### Race-level completeness — every runner in the race priced

| split | races | arch_pct | feed_pct | feed_prerace_pct |
|---|---|---|---|---|
| test | 2232 | 1 | 0.99955 | 0.99955 |
| train | 5209 | 0.97773 | 0.61144 | 0.53523 |
| ALL | 7441 | 0.98441 | 0.72786 | 0.67451 |

### The 2,183-race ranking test universe — the number that decides it

| price_source | races_complete | of_races | pct_complete |
|---|---|---|---|
| archive forecast (historic_runners) | 2183 | 2183 | 1 |
| feed forecast (daily_runners, any load time) | 2182 | 2183 | 0.99954 |
| feed forecast, feed row written pre-race | 2182 | 2183 | 0.99954 |

The P4-0 abort threshold on this quantity is 70%.

## Overround and shape of the feed book (training split)

| source | races | p25 | median | p75 |
|---|---|---|---|---|
| feed forecast | 3185 | 1.0869 | 1.1483 | 1.2007 |
| archive forecast | 5093 | 1.1006 | 1.1564 | 1.2069 |
| starting price | 5197 | 1.1288 | 1.1628 | 1.2006 |

The P4-0 abort band on the median is 1.05 to 1.60.

### Within-race regression of log p_forecast on log p_SP, both sources

Rows: 28744 runners across 3185 training races complete in all three books.

| forecast_source | within_race_slope | std_error | r_squared |
|---|---|---|---|
| feed (pre-race) | 0.54815 | 0.0034172 | 0.47235 |
| archive (post-race transcription) | 0.56657 | 0.0032789 | 0.50951 |

A slope closer to 1, and a higher R-squared, means that source is more SP-like. The archive column being the more SP-like of the two is the same finding as follow-up 2 section D, measured a second way.

### Winner/loser separation, training split, races complete in all three books

| price_source | separation_log_price |
|---|---|
| feed forecast (pre-race) | 0.36065 |
| archive forecast | 0.36926 |
| starting price | 0.61872 |

Descriptive only, training split, nothing downstream selected on it.

