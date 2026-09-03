# P4-0 follow-ups

Generated: 2026-08-28 10:54:23 BST

## A. Is the forecast price revised between the daily feed and the archive?

`daily_runners`: 1064594 rows over 1064594 distinct (runner_id, race_id) keys — one row per runner-race, so the feed table is a snapshot, not a version log.

### Daily-feed value vs archive value, all matched runner-rows

| case | rows | pct |
|---|---|---|
| both_null | 13823 | 0.01359 |
| daily_null_only | 1894 | 0.001862 |
| hist_null_only | 5860 | 0.0057611 |
| both_equal | 833286 | 0.81923 |
| both_differ | 162298 | 0.15956 |
| n_matched | 1017161 | 1 |

Read: `both_equal` is the archive reproducing the pre-race feed value unchanged. `daily_null_only` / `hist_null_only` are coverage gaps on one side, not revisions. `both_differ` is the only cell that could be a revision.

### Twenty most common (daily, archive) disagreeing pairs

| daily_fp | hist_fp | n |
|---|---|---|
| 11 | 13 | 4296 |
| 13 | 11 | 4169 |
| 11 | 9 | 4086 |
| 17 | 15 | 3846 |
| 15 | 13 | 3776 |
| 9 | 11 | 3768 |
| 13 | 15 | 3763 |
| 15 | 17 | 3735 |
| 21 | 26 | 3374 |
| 17 | 21 | 3196 |
| 9 | 8 | 3146 |
| 21 | 17 | 3103 |
| 26 | 21 | 2887 |
| 8 | 9 | 2684 |
| 26 | 34 | 2281 |
| 7 | 8 | 2028 |
| 34 | 26 | 1957 |
| 8 | 7 | 1858 |
| 17 | 13 | 1706 |
| 15 | 11 | 1640 |

### Restricted to the 7441 in-scope AW races

| both_equal | both_differ | n_matched |
|---|---|---|
| 36297 | 18489 | 55471 |

## B. The `forecast_price = '-214748364'` rows

| runner_id | race_id | unfinished | forecast_price | forecast_price_decimal | starting_price | starting_price_decimal |
|---|---|---|---|---|---|---|
| 559373 | 150902 | Non-Runner | -214748364 | NA | 0/0 | NA |
| 283111 | 165192 | Non-Runner | -214748364 | NA | 0/0 | NA |

`-214748364` is a truncated INT_MIN sentinel written into the char column. What matters for P4-1 is only whether the *decimal* column on those rows is usable.

Of those rows, 0 are in the pipeline's runner set; 0 are in the ranking test universe.

Whole-table `historic_runners` rows with a non-NULL `forecast_price_decimal` outside (1, 1001]: 0.

## C. Degenerate books

Complete-book races with an implausible overround, by band:

| band | test | train |
|---|---|---|
| 0.90 to 1.00 | 141 | 281 |
| 1.00 to 1.60 (plausible) | 2011 | 4586 |
| above 1.60 | 0 | 20 |
| below 0.90 (an underround the market would never strike) | 80 | 206 |

Ranking-test-universe races outside 1.00 to 1.60: 218 of 2183.

Ten most extreme complete-book overrounds (any split):

| race_id | split | in_rank | n_runners | or_fp |
|---|---|---|---|---|
| 121375 | train | FALSE | 12 | 2.4242 |
| 123629 | train | FALSE | 13 | 2.3392 |
| 127858 | train | FALSE | 14 | 2.3183 |
| 126707 | train | FALSE | 12 | 2.1574 |
| 127008 | train | FALSE | 13 | 2.0446 |
| 127532 | train | FALSE | 12 | 2.0421 |
| 126837 | train | FALSE | 9 | 2.0333 |
| 219397 | train | FALSE | 5 | 0.33178 |
| 125057 | train | FALSE | 10 | 1.9644 |
| 124271 | train | FALSE | 12 | 1.9552 |

