# Smartform DB audit 2: weight identity & full-history sequence length

Generated: 2026-08-23 18:55:52 BST

Universe: rebuilt via `R/extract_qualifying_races.R::extract_qualifying_races()` and 
`R/extract_runners.R::extract_runners_for_races()` with the `_targets.R` parameters (date_from = "2006-01-01", date_to = "2015-10-14", aw_courses = c("Kempton", "Lingfield", "Southwell", "Wolverhampton")), replicating candidate_races -> qualifying_runners -> qualifying_races.
qualifying_races: 7441 races. qualifying_runners: 66770 runner-rows.

## Audit C: weight identity

Identity tested: `adj_weight = weight_pounds - penalty_weight - over_weight + jockey_claim - long_handicap` (NULL treated as 0 on the four adjustment terms), compared to `official_rating`, both centred on their race minimum among eligible runners (non-null official_rating and weight_pounds).

Rows after Non-Runner removal and joining to qualifying_runners' `won` flag: 66770 (vs qualifying_runners: 66770).
Rows with non-null official_rating AND weight_pounds: 59789 of 66770 (89.54%).

### (a) Row-level exact match

24603 of 59789 rows match exactly (41.150%).

### (b) Discrepancy in pounds

| quantile | discrepancy |
|---|---|
| min | -156 |
| p10 | -6 |
| p25 | -2 |
| median | 0 |
| p75 | 1 |
| p90 | 5 |
| p99 | 11 |
| max | 28 |

| bucket | n | pct |
|---|---|---|
| < -5 | 5,984 | 10.009 |
| -5 | 1,667 | 2.788 |
| -4 | 1,766 | 2.954 |
| -3 | 2,960 | 4.951 |
| -2 | 2,862 | 4.787 |
| -1 | 3,282 | 5.489 |
| 0 | 24,603 | 41.150 |
| 1 | 2,903 | 4.855 |
| 2 | 2,338 | 3.910 |
| 3 | 3,168 | 5.299 |
| 4 | 1,439 | 2.407 |
| 5 | 2,520 | 4.215 |
| > 5 | 4,297 | 7.187 |

### (c) Races where every eligible runner matches exactly

680 of 7106 races (9.569%).
85 of those races have only one eligible runner, which trivially matches (min of one value equals itself); restricting to races with >=2 eligible runners: 595 of 7021 match exactly (8.475%).

### (d) Effect of omitting each adjustment term

| variant | row_exact_pct | median_abs_discrepancy | race_all_exact_pct |
|---|---|---|---|
| full | 41.150 | 1 | 9.569 |
| no_penalty | 40.365 | 1 | 8.809 |
| no_over_weight | 42.190 | 1 | 10.090 |
| no_jockey_claim | 57.932 | 0 | 36.223 |
| no_long_handicap | 37.085 | 2 | 8.753 |

### (a)-(c) split by winner status (full identity)

**Winners (won == 1)** — 6770 rows

(a) Row-level exact match: 40.118%

| quantile | discrepancy |
|---|---|
| min | -156 |
| p10 | -9 |
| p25 | -3 |
| median | 0 |
| p75 | 0 |
| p90 | 4 |
| p99 | 9 |
| max | 22 |

| bucket | n | pct |
|---|---|---|
| < -5 | 1,139 | 16.824 |
| -5 | 245 | 3.619 |
| -4 | 235 | 3.471 |
| -3 | 359 | 5.303 |
| -2 | 296 | 4.372 |
| -1 | 350 | 5.170 |
| 0 | 2,716 | 40.118 |
| 1 | 252 | 3.722 |
| 2 | 186 | 2.747 |
| 3 | 281 | 4.151 |
| 4 | 115 | 1.699 |
| 5 | 240 | 3.545 |
| > 5 | 356 | 5.258 |

**Non-winners (won == 0)** — 53019 rows

(a) Row-level exact match: 41.281%

| quantile | discrepancy |
|---|---|
| min | -156 |
| p10 | -5 |
| p25 | -1 |
| median | 0 |
| p75 | 1 |
| p90 | 5 |
| p99 | 11 |
| max | 28 |

| bucket | n | pct |
|---|---|---|
| < -5 | 4,845 | 9.138 |
| -5 | 1,422 | 2.682 |
| -4 | 1,531 | 2.888 |
| -3 | 2,601 | 4.906 |
| -2 | 2,566 | 4.840 |
| -1 | 2,932 | 5.530 |
| 0 | 21,887 | 41.281 |
| 1 | 2,651 | 5.000 |
| 2 | 2,152 | 4.059 |
| 3 | 2,887 | 5.445 |
| 4 | 1,324 | 2.497 |
| 5 | 2,280 | 4.300 |
| > 5 | 3,941 | 7.433 |

(c) split by winner status: since (c) is a race-level statistic, split here as "does the winner's own row match exactly" vs "does every non-winning runner's row match exactly", each restricted to races where that group has at least one eligible row.

Races with an eligible winner row: 6770, of which the winner's row matches exactly: 40.118%.
Races with >=1 eligible non-winner row: 7094, of which every non-winner row matches exactly: 11.037%.

## Audit D: sequence length on full history

Horse identity: `runner_id`, not `name`. This is the field the pipeline already keys on -- `R/extract_runners.R::extract_career_history()` fetches full career history by `runner_id`, and `get_aw_runner_ids()` derives the horse population as `unique(qualifying_runners$runner_id)`. `historic_runners` has no separate horse_id column; `runner_id` is the persistent per-horse identifier reused across every race row for that horse (already evident in audit_smartform.R's Audit A, where individual runner_ids carry dozens of race rows spanning years).

Name collisions (full historic_runners table, not just this universe): 2028 of 133271 distinct names are shared by more than one runner_id (1.522%) -- name alone is not a safe join key. 40 distinct runner_ids are recorded under more than one name over their career (renames/retagging). `runner_id` avoids both problems.

Sample of colliding names, by number of runner_ids sharing the name (top 10):

| name | n_runner_ids |
|---|---|
| Tiernan's Terror | 5 |
| Amore Mio | 3 |
| Bivouac | 3 |
| Brynfa Boy | 3 |
| Cape Melody | 3 |
| Captain Henry | 3 |
| Dangerous Midge | 3 |
| Dark Moon | 3 |
| Dollar Express | 3 |
| Emerging Artist | 3 |

Full cross-surface history (>=2003-01-01, all race types/courses) pulled for 17376 horses: 486055 rows.

### Prior full-history runs (>=2003, strictly before meeting_date, all race types/courses)

| quantile | prior_full_runs |
|---|---|
| min | 0 |
| p10 | 5 |
| p25 | 8 |
| median | 17 |
| p75 | 34 |
| p90 | 55 |
| p99 | 101 |
| max | 243 |

| bucket | n | pct |
|---|---|---|
| 0 | 122 | 0.183 |
| 1-2 | 1,097 | 1.643 |
| 3-5 | 8,196 | 12.275 |
| 6-10 | 12,136 | 18.176 |
| 11-20 | 15,863 | 23.758 |
| 21+ | 29,356 | 43.966 |

### Same breakdown, split by whether the horse has any prior QUALIFYING run

**Zero prior qualifying runs** — 17376 rows (26.024% of universe)

| quantile | prior_full_runs |
|---|---|
| min | 0 |
| p10 | 3 |
| p25 | 4 |
| median | 7 |
| p75 | 12 |
| p90 | 23 |
| p99 | 52 |
| max | 105 |

| bucket | n | pct |
|---|---|---|
| 0 | 122 | 0.702 |
| 1-2 | 921 | 5.300 |
| 3-5 | 6,112 | 35.175 |
| 6-10 | 4,964 | 28.568 |
| 11-20 | 3,149 | 18.123 |
| 21+ | 2,108 | 12.132 |

**Has >=1 prior qualifying run** — 49394 rows (73.976% of universe)

| quantile | prior_full_runs |
|---|---|
| min | 1 |
| p10 | 8 |
| p25 | 13 |
| median | 23 |
| p75 | 41 |
| p90 | 62 |
| p99 | 108 |
| max | 243 |

| bucket | n | pct |
|---|---|---|
| 0 | 0 | 0.000 |
| 1-2 | 176 | 0.356 |
| 3-5 | 2,084 | 4.219 |
| 6-10 | 7,172 | 14.520 |
| 11-20 | 12,714 | 25.740 |
| 21+ | 27,248 | 55.165 |

### Distribution of days_since_ran (qualifying universe)

Non-null days_since_ran: 66768 of 66770 (100.00%).

| quantile | days_since_ran |
|---|---|
| min | 1 |
| p10 | 8 |
| p25 | 13 |
| median | 20 |
| p75 | 37 |
| p90 | 110 |
| p99 | 318 |
| max | 2,016 |

### Race-type composition of prior runs

Operational definition: for each horse, take its full-history rows (>=2003) with meeting_date strictly before that horse's LAST qualifying appearance in this universe -- i.e. every historical run that counts as "prior" to at least one of its qualifying rows, counted once each (not once per qualifying row it precedes).

Prior-run pool size: 334909 rows.

Distinct race_type values on historic_races: All Weather Flat, Chase, Flat, Hurdle, National Hunt Flat, Point to Point, Trotting

| race_type_bucket | n | pct |
|---|---|---|
| Flat | 196,795 | 58.761 |
| AW Flat | 121,147 | 36.173 |
| Hurdle | 14,912 | 4.453 |
| Chase | 1,316 | 0.393 |
| Other | 739 | 0.221 |

Breakdown of "Other":

| race_type | n |
|---|---|
| National Hunt Flat | 739 |

