# Smartform DB audit: official_rating timing & column population

Generated: 2026-08-23 18:19:17 BST

## 0. Current sourcing of `official_rating` in the pipeline

Grep of `sql/` and `R/` for `official_rating`:

```
sql/horse_full_history.sql:30: rn.official_rating,
sql/runners_for_races.sql:22: official_rating,
R/build_extended_features.R:150: #'   \item{`or_relative`}{`official_rating` minus the race-mean
R/build_extended_features.R:151: #'     `official_rating` over the field. NA when the runner's own
R/build_extended_features.R:161: #'   official_rating).
R/build_extended_features.R:170: race_mean_or     = mean(official_rating, na.rm = TRUE)
R/build_extended_features.R:182: or_relative = official_rating - race_mean_or
```

`official_rating` is selected as-is from `historic_runners` in two places: `sql/runners_for_races.sql` (the runner's own rating for its qualifying race) and `sql/horse_full_history.sql` (career history rows, same column). `R/build_extended_features.R::build_within_race_features()` computes `or_relative` as this runner's `official_rating` for the current race minus the race-mean `official_rating` over the field — i.e. the pipeline treats the value on a runner's own qualifying-race row as the rating that horse carried INTO that race. No lag or as-of adjustment is applied anywhere in `R/` or `sql/`. Audit A below tests whether that assumption holds.

## Audit A: official_rating timing

Distinct `historic_races.race_type` values matching /flat/i: Flat, National Hunt Flat, All Weather Flat. Used for this audit: Flat, All Weather Flat (others containing "Flat", e.g. National Hunt Flat / bumpers, are a different racing code and excluded).
Date window: 2006-01-01 to 2015-12-31.

Candidate pool (>=6 runs, >=1 win, in window): 25328 horses. Selecting 20 spread evenly across the pool ordered by first run date.

### Horse runner_id=139213 (Dancing Mystery) — 44 runs, NA wins in pool

| meeting_date | course | class | finish_position | official_rating | weight_pounds | starting_price_decimal | note |
|---|---|---|---|---|---|---|---|
| 2006-01-01 | Southwell | 2 | 4 | 72 | 132 | 19 |  |
| 2006-01-26 | Southwell | 2 | 2 | 72 | 132 | 12 |  |
| 2006-02-04 | Lingfield | 2 | 6 | 72 | 124 | 13 |  |
| 2006-02-18 | Wolverhampton | 2 | 6 | 72 | 128 | 21 |  |
| 2006-03-18 | Lingfield | 2 | 8 | 72 | 129 | 41 |  |
| 2006-03-23 | Lingfield | 2 | 5 | 72 | 126 | 26 |  |
| 2006-04-10 | Windsor | 4 | 7 | 70 | 122 | 7 |  |
| 2006-04-25 | Folkestone | 5 | 5 | 69 | 125 | 9 |  |
| 2006-06-13 | Salisbury | 5 | 8 | 65 | 143 | 13 |  |
| 2006-06-24 | Lingfield | 5 | 8 | 62 | 130 | 9 |  |
| 2006-07-17 | Windsor | 5 | 8 | 59 | 126 | 13 |  |
| 2006-08-19 | Goodwood | 5 | 2 | 63 | 133 | 13 |  |
| 2006-09-20 | Goodwood | 5 | 1 | 67 | 126 | 9 | WIN |
| 2006-09-25 | Brighton | 5 | NA | 63 | 119 | NA | NA |
| 2006-09-30 | Redcar | 5 | NA | 67 | 128 | NA | NA |
| 2006-10-13 | Brighton | 5 | 1 | 83 | 127 | 7 | WIN |
| 2006-11-11 | Lingfield | 4 | 4 | 72 | 127 | 7 |  |
| 2006-11-15 | Southwell | 3 | 1 | 70 | 122 | 7 | WIN |
| 2006-12-05 | Southwell | 3 | 5 | 70 | 123 | 8 |  |
| 2007-01-09 | Southwell | 4 | 6 | 70 | 128 | 15 |  |
| 2007-02-24 | Lingfield | 4 | 9 | 82 | 125 | 26 |  |
| 2007-03-28 | Southwell | 4 | 10 | 80 | 126 | 41 |  |
| 2007-05-24 | Salisbury | 5 | 16 | 67 | 146 | 34 |  |
| 2007-06-09 | Windsor | 5 | 8 | 65 | 131 | 34 |  |
| 2007-08-06 | Windsor | 5 | 11 | 62 | 124 | 51 |  |
| 2007-08-21 | Brighton | 6 | 6 | 58 | 128 | 17 |  |
| 2007-09-06 | Salisbury | 5 | 3 | 56 | 117 | 34 |  |
| 2007-09-15 | Warwick | 5 | 1 | 56 | 117 | 8 | WIN |
| 2007-09-26 | Goodwood | 5 | NA | 62 | 124 | NA | NA |
| 2007-10-01 | Brighton | 6 | 3 | 62 | 127 | 5 |  |
| 2007-10-18 | Brighton | 5 | 2 | 62 | 124 | 9 |  |
| 2007-10-23 | Lingfield | 5 | 7 | 75 | 130 | 9 |  |
| 2007-10-31 | Nottingham | 5 | 7 | 62 | 124 | 15 |  |
| 2007-12-12 | Kempton | 5 | 4 | 72 | 128 | 21 |  |
| 2008-01-08 | Southwell | 4 | 6 | 70 | 117 | 13 |  |
| 2008-01-25 | Kempton | 4 | 5 | 62 | 120 | 15 |  |
| 2008-05-06 | Southwell | 5 | 7 | 60 | 124 | 34 |  |
| 2008-06-11 | Brighton | 6 | 5 | NA | 137 | 7 |  |
| 2008-06-26 | Leicester | 5 | 5 | 57 | 142 | 29 |  |
| 2008-07-01 | Brighton | 5 | 6 | 54 | 126 | 12 |  |
| 2008-07-17 | Doncaster | 6 | 10 | 51 | 128 | 17 |  |
| 2008-09-24 | Goodwood | 5 | 14 | NA | 118 | 26 |  |
| 2008-10-22 | Kempton | 6 | 11 | NA | 128 | 34 |  |
| 2008-12-12 | Southwell | 6 | 11 | NA | 122 | 34 |  |

Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):

| win_date | prior_or | win_or | next_or | verdict |
|---|---|---|---|---|
| 2006-09-20 | 63 | 67 | 63 | post-race (rose on win row) |
| 2006-10-13 | 67 | 83 | 72 | post-race (rose on win row) |
| 2006-11-15 | 72 | 70 | 70 | ambiguous (rating fell) |
| 2007-09-15 | 56 | 56 | 62 | pre-race (rose only on next run) |

**Horse verdict: mixed (both patterns observed)**

### Horse runner_id=267718 (Tackcoat) — 16 runs, NA wins in pool

| meeting_date | course | class | finish_position | official_rating | weight_pounds | starting_price_decimal | note |
|---|---|---|---|---|---|---|---|
| 2006-03-30 | Thurles | NA | 9 | 40 | 120 | 11.00 |  |
| 2006-04-12 | Limerick | NA | 11 | 40 | 120 | 13.00 |  |
| 2006-04-22 | Naas | NA | 14 | 38 | 120 | 17.00 |  |
| 2006-05-16 | Southwell | 7 | 6 | 40 | 123 | 17.00 |  |
| 2006-06-17 | Lingfield | 6 | NA | 38 | 121 | NA | NA |
| 2006-10-12 | Southwell | 7 | NA | NA | 125 | NA | NA |
| 2006-10-12 | Southwell | 7 | NA | NA | 126 | NA | NA |
| 2006-12-04 | Lingfield | 6 | NA | 40 | 127 | NA | NA |
| 2006-12-13 | Lingfield | 7 | NA | 40 | 124 | NA | NA |
| 2006-12-18 | Kempton | 7 | 3 | 40 | 125 | 17.00 |  |
| 2006-12-28 | Southwell | 7 | 7 | 40 | 124 | 8.00 |  |
| 2006-12-29 | Southwell | 7 | 1 | 40 | 125 | 4.33 | WIN |
| 2007-01-16 | Wolverhampton | 6 | 9 | 40 | 124 | 9.00 |  |
| 2007-01-28 | Kempton | 6 | 5 | 40 | 124 | 11.00 |  |
| 2007-02-08 | Southwell | 6 | 8 | NA | 124 | 6.00 |  |
| 2007-03-13 | Southwell | 6 | 5 | 49 | 126 | 9.00 |  |

Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):

| win_date | prior_or | win_or | next_or | verdict |
|---|---|---|---|---|
| 2006-12-29 | 40 | 40 | 40 | ambiguous (no rise observed) |

**Horse verdict: ambiguous (insufficient data)**

### Horse runner_id=518627 (Mouseen) — 17 runs, NA wins in pool

| meeting_date | course | class | finish_position | official_rating | weight_pounds | starting_price_decimal | note |
|---|---|---|---|---|---|---|---|
| 2006-05-01 | Curragh | NA | 15 | 72 | 131 | 26.0 |  |
| 2006-05-28 | Curragh | NA | 12 | 70 | 126 | 34.0 |  |
| 2006-06-05 | Naas | NA | NA | 70 | 116 | NA | NA |
| 2006-06-10 | Curragh | NA | 20 | 66 | 132 | 21.0 |  |
| 2006-06-30 | Curragh | NA | 23 | 60 | 127 | 26.0 |  |
| 2006-07-12 | Naas | NA | 11 | 55 | 122 | 34.0 |  |
| 2006-08-10 | Tipperary | NA | 1 | 58 | 120 | 15.0 | WIN |
| 2006-08-23 | Bellewstown | NA | 13 | 58 | 138 | 7.5 |  |
| 2006-09-17 | Curragh | NA | NA | 58 | 117 | NA | NA |
| 2006-12-05 | Southwell | 6 | 6 | 55 | 127 | 51.0 |  |
| 2006-12-21 | Wolverhampton | 5 | 12 | 55 | 126 | 34.0 |  |
| 2007-01-09 | Southwell | 6 | 5 | 53 | 122 | 34.0 |  |
| 2007-01-16 | Southwell | 6 | 3 | 54 | 122 | 13.0 |  |
| 2007-01-25 | Southwell | 6 | 6 | 53 | 122 | 17.0 |  |
| 2007-02-11 | Southwell | 6 | 11 | 48 | 122 | 11.0 |  |
| 2007-05-08 | Chepstow | 6 | 14 | 53 | 121 | 9.0 |  |
| 2007-06-01 | Bath | 5 | 7 | 53 | 116 | 21.0 |  |

Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):

| win_date | prior_or | win_or | next_or | verdict |
|---|---|---|---|---|
| 2006-08-10 | 55 | 58 | 58 | post-race (rose on win row) |

**Horse verdict: post-race (rose on win row)**

### Horse runner_id=559534 (Centenary) — 27 runs, NA wins in pool

| meeting_date | course | class | finish_position | official_rating | weight_pounds | starting_price_decimal | note |
|---|---|---|---|---|---|---|---|
| 2006-06-20 | Thirsk | 5 | 5 | NA | 129 | 26.0 |  |
| 2006-07-05 | Catterick | 5 | 3 | NA | 129 | 17.0 |  |
| 2006-07-18 | Newcastle | 6 | 2 | 75 | 133 | 5.5 |  |
| 2006-08-09 | Newcastle | 5 | 3 | 75 | 123 | 12.0 |  |
| 2006-08-17 | Beverley | 5 | 6 | 73 | 130 | 9.5 |  |
| 2006-08-28 | Newcastle | 3 | 3 | 72 | 125 | 17.0 |  |
| 2006-09-11 | Redcar | 5 | 4 | 70 | 129 | 5.0 |  |
| 2006-09-27 | Newcastle | 5 | 1 | 70 | 129 | 10.0 | WIN |
| 2006-10-16 | Pontefract | 5 | 11 | 68 | 130 | 13.0 |  |
| 2007-04-04 | Nottingham | 5 | 13 | 68 | 128 | 9.5 |  |
| 2007-04-26 | Beverley | 5 | NA | 68 | 126 | NA | NA |
| 2007-05-03 | Catterick | 5 | NA | 68 | 124 | NA | NA |
| 2007-05-07 | Newcastle | 5 | 15 | 68 | 126 | 15.0 |  |
| 2007-07-02 | Pontefract | 5 | 7 | 62 | 123 | 13.0 |  |
| 2007-07-29 | Carlisle | 5 | 13 | 60 | 126 | 11.0 |  |
| 2007-08-01 | Kempton | 6 | 12 | NA | 128 | 17.0 |  |
| 2007-08-27 | Ripon | 5 | 2 | 55 | 118 | 29.0 |  |
| 2007-08-29 | Ayr | 6 | NA | 55 | 123 | NA | NA |
| 2007-09-14 | Wolverhampton | 6 | 8 | NA | 121 | 15.0 |  |
| 2007-11-07 | Kempton | 6 | 8 | 50 | 122 | 15.0 |  |
| 2007-11-16 | Wolverhampton | 6 | 5 | 49 | 120 | 11.0 |  |
| 2008-05-07 | Beverley | 6 | 8 | 52 | 135 | 10.0 |  |
| 2008-07-05 | Nottingham | 6 | 7 | 48 | 139 | 8.5 |  |
| 2008-07-28 | Yarmouth | 6 | 4 | 46 | 126 | 9.5 |  |
| 2008-08-09 | Redcar | 6 | 6 | NA | 128 | 6.0 |  |
| 2009-06-06 | Newcastle | 6 | 9 | 45 | 118 | 29.0 |  |
| 2009-06-20 | Redcar | 6 | 8 | 42 | 117 | 23.0 |  |

Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):

| win_date | prior_or | win_or | next_or | verdict |
|---|---|---|---|---|
| 2006-09-27 | 70 | 70 | 68 | ambiguous (no rise observed) |

**Horse verdict: ambiguous (insufficient data)**

### Horse runner_id=621539 (Sell Out) — 16 runs, NA wins in pool

| meeting_date | course | class | finish_position | official_rating | weight_pounds | starting_price_decimal | note |
|---|---|---|---|---|---|---|---|
| 2006-10-12 | Newmarket | 4 | 15 | 76 | 124 | 51.00 |  |
| 2006-11-11 | Kempton | 5 | 1 | 76 | 126 | 41.00 | WIN |
| 2007-05-02 | Nottingham | 4 | 5 | 76 | 126 | 17.00 |  |
| 2007-05-24 | Southwell | 4 | 8 | NA | 127 | 4.33 |  |
| 2007-06-06 | Kempton | 4 | 7 | NA | 131 | 41.00 |  |
| 2007-06-26 | Newbury | 4 | 1 | 75 | 123 | 11.00 | WIN |
| 2007-07-28 | York | 3 | 2 | 79 | 132 | 7.50 |  |
| 2007-08-15 | Salisbury | 1 | 2 | 81 | 117 | 17.00 |  |
| 2007-09-19 | Yarmouth | 1 | 4 | 91 | 121 | 26.00 |  |
| 2007-10-19 | Newmarket | 1 | 4 | 98 | 123 | 11.00 |  |
| 2008-05-15 | York | 1 | 5 | 100 | 124 | 17.00 |  |
| 2008-06-26 | Newcastle | 1 | 2 | NA | 131 | 11.00 |  |
| 2008-08-03 | Newbury | 1 | NA | NA | 128 | NA | NA |
| 2008-08-16 | Newbury | 1 | 4 | NA | 126 | 34.00 |  |
| 2008-09-26 | Ascot | 1 | NA | NA | 132 | NA | NA |
| 2008-10-25 | Newbury | 1 | 3 | 109 | 126 | 13.00 |  |

Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):

| win_date | prior_or | win_or | next_or | verdict |
|---|---|---|---|---|
| 2006-11-11 | 76 | 76 | 76 | ambiguous (no rise observed) |
| 2007-06-26 | NA | 75 | 79 | ambiguous (no prior run in pool) |

**Horse verdict: ambiguous (insufficient data)**

### Horse runner_id=680043 (Pennyspider) — 18 runs, 2 wins in pool

| meeting_date | course | class | finish_position | official_rating | weight_pounds | starting_price_decimal | note |
|---|---|---|---|---|---|---|---|
| 2007-06-18 | Windsor | 4 | 11 | NA | 124 | 34.0 |  |
| 2007-06-30 | Lingfield | 5 | 7 | NA | 124 | 34.0 |  |
| 2007-07-09 | Bath | 5 | 8 | NA | 124 | 101.0 |  |
| 2007-07-26 | Bath | 5 | 3 | NA | 119 | 34.0 |  |
| 2008-04-02 | Kempton | 5 | 8 | 52 | 124 | 67.0 |  |
| 2008-04-11 | Wolverhampton | 5 | 11 | 52 | 121 | 34.0 |  |
| 2008-04-22 | Bath | 5 | 7 | 48 | 121 | 51.0 |  |
| 2008-04-29 | Bath | 5 | 1 | 48 | 116 | 21.0 | WIN |
| 2008-07-17 | Bath | 5 | 3 | 60 | 118 | 17.0 |  |
| 2008-07-24 | Bath | 5 | 4 | 62 | 123 | 4.0 |  |
| 2008-08-01 | Bath | 5 | 2 | 62 | 121 | 8.5 |  |
| 2008-08-07 | Bath | 5 | 4 | 62 | 126 | 6.0 |  |
| 2008-08-12 | Nottingham | 5 | 9 | 61 | 126 | 15.0 |  |
| 2008-08-22 | Bath | 5 | 1 | NA | 125 | 7.0 | WIN |
| 2008-09-13 | Goodwood | 5 | 6 | NA | 124 | 6.0 |  |
| 2010-03-10 | Wolverhampton | 6 | 4 | 62 | 117 | 34.0 |  |
| 2010-03-18 | Southwell | 5 | 10 | 60 | 124 | 26.0 |  |
| 2010-04-10 | Wolverhampton | 6 | 8 | 58 | 128 | 34.0 |  |

Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):

| win_date | prior_or | win_or | next_or | verdict |
|---|---|---|---|---|
| 2008-04-29 | 48 | 48 | 60 | pre-race (rose only on next run) |
| 2008-08-22 | 61 | NA | NA | ambiguous (win row OR missing) |

**Horse verdict: pre-race (rose only on next run)**

### Horse runner_id=699651 (Orpen Fire) — 6 runs, 1 wins in pool

| meeting_date | course | class | finish_position | official_rating | weight_pounds | starting_price_decimal | note |
|---|---|---|---|---|---|---|---|
| 2007-10-27 | Wolverhampton | 6 | 1 | NA | 118 | 34.00 | WIN |
| 2007-11-27 | Wolverhampton | 5 | 4 | 70 | 121 | 7.00 |  |
| 2008-05-05 | Warwick | 5 | 2 | 75 | 129 | 9.00 |  |
| 2008-06-06 | Catterick | 5 | 2 | 75 | 137 | 3.75 |  |
| 2008-06-25 | Carlisle | 4 | 3 | 76 | 123 | 4.50 |  |
| 2008-07-10 | Nottingham | 4 | 10 | NA | 130 | 4.33 |  |

Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):

| win_date | prior_or | win_or | next_or | verdict |
|---|---|---|---|---|
| 2007-10-27 | NA | NA | 70 | ambiguous (win row OR missing) |

**Horse verdict: ambiguous (insufficient data)**

### Horse runner_id=755692 (Touching) — 9 runs, 1 wins in pool

| meeting_date | course | class | finish_position | official_rating | weight_pounds | starting_price_decimal | note |
|---|---|---|---|---|---|---|---|
| 2008-06-30 | Windsor | 5 | 3 | NA | 126 | 6 |  |
| 2008-07-09 | Kempton | 5 | 1 | 83 | 126 | 4 | WIN |
| 2008-07-24 | Sandown | 1 | 3 | 87 | 124 | 8 |  |
| 2008-09-17 | Sandown | 3 | 3 | NA | 123 | 13 |  |
| 2008-10-03 | Newmarket | 1 | 6 | NA | 124 | 12 |  |
| 2009-04-18 | Newbury | 1 | 9 | 92 | 126 | 26 |  |
| 2009-08-14 | Kempton | 3 | 9 | 90 | 129 | 26 |  |
| 2009-08-22 | Sandown | 1 | 9 | 86 | 120 | 67 |  |
| 2009-10-31 | Kempton | 4 | 6 | 82 | 128 | 21 |  |

Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):

| win_date | prior_or | win_or | next_or | verdict |
|---|---|---|---|---|
| 2008-07-09 | NA | 83 | 87 | ambiguous (no prior run in pool) |

**Horse verdict: ambiguous (insufficient data)**

### Horse runner_id=727029 (Castaneous) — 16 runs, NA wins in pool

| meeting_date | course | class | finish_position | official_rating | weight_pounds | starting_price_decimal | note |
|---|---|---|---|---|---|---|---|
| 2008-11-21 | Dundalk | NA | NA | NA | 128 | NA | NA |
| 2008-11-28 | Dundalk | NA | 7 | NA | 130 | 51.00 |  |
| 2008-12-06 | Wolverhampton | 5 | 3 | NA | 134 | 34.00 |  |
| 2008-12-12 | Wolverhampton | 6 | NA | NA | 131 | NA | NA |
| 2009-01-21 | Wolverhampton | 5 | 1 | NA | 133 | 1.67 | WIN |
| 2009-01-22 | Wolverhampton | 6 | NA | NA | 130 | NA | NA |
| 2009-02-27 | Dundalk | NA | NA | NA | 126 | NA | NA |
| 2009-03-20 | Dundalk | NA | NA | NA | 116 | NA | NA |
| 2009-04-03 | Dundalk | NA | 11 | 66 | 138 | 7.00 |  |
| 2009-04-19 | Leopardstown | NA | 16 | 66 | 126 | 21.00 |  |
| 2009-05-11 | Killarney | NA | NA | NA | 139 | NA | NA |
| 2009-06-07 | Roscommon | NA | NA | NA | 139 | NA | NA |
| 2009-06-10 | Fairyhouse | NA | 14 | 64 | 129 | 17.00 |  |
| 2009-06-20 | Down_Royal | NA | NA | NA | 135 | NA | NA |
| 2009-06-21 | Down_Royal | NA | NA | NA | 135 | NA | NA |
| 2009-06-24 | Naas | NA | 11 | 60 | 117 | 15.00 |  |

Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):

| win_date | prior_or | win_or | next_or | verdict |
|---|---|---|---|---|
| 2009-01-21 | NA | NA | NA | ambiguous (win row OR missing) |

**Horse verdict: ambiguous (insufficient data)**

### Horse runner_id=1459572 (Blakey's Boy) — 11 runs, NA wins in pool

| meeting_date | course | class | finish_position | official_rating | weight_pounds | starting_price_decimal | note |
|---|---|---|---|---|---|---|---|
| 2009-07-11 | Salisbury | 4 | 1 | NA | 129 | 13.0 | WIN |
| 2009-08-15 | Newbury | 1 | 3 | NA | 126 | 9.0 |  |
| 2009-09-19 | Ayr | 2 | NA | NA | 133 | NA | NA |
| 2009-10-10 | Ascot | 1 | 8 | 90 | 126 | 17.0 |  |
| 2010-04-23 | Sandown | 2 | 7 | 89 | 124 | 23.0 |  |
| 2010-05-15 | Newbury | 2 | 10 | 87 | 128 | 26.0 |  |
| 2010-06-11 | Goodwood | 3 | 5 | 84 | 127 | 7.5 |  |
| 2010-07-10 | Salisbury | 4 | 4 | 81 | 130 | 6.5 |  |
| 2010-11-03 | Nottingham | 2 | 3 | 78 | 120 | 21.0 |  |
| 2010-12-04 | Kempton | 4 | 7 | 77 | 129 | 9.0 |  |
| 2011-01-05 | Lingfield | 5 | 7 | 75 | 133 | 9.0 |  |

Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):

| win_date | prior_or | win_or | next_or | verdict |
|---|---|---|---|---|
| 2009-07-11 | NA | NA | NA | ambiguous (win row OR missing) |

**Horse verdict: ambiguous (insufficient data)**

### Horse runner_id=1524227 (Joyously) — 27 runs, NA wins in pool

| meeting_date | course | class | finish_position | official_rating | weight_pounds | starting_price_decimal | note |
|---|---|---|---|---|---|---|---|
| 2010-04-12 | Windsor | 5 | 13 | NA | 124 | 51.0 |  |
| 2010-05-04 | Bath | 6 | 1 | NA | 118 | 4.5 | WIN |
| 2010-05-14 | Newcastle | 4 | 2 | NA | 121 | 15.0 |  |
| 2010-05-24 | Windsor | 5 | 3 | NA | 121 | 21.0 |  |
| 2010-06-01 | Yarmouth | 5 | 2 | NA | 121 | 5.5 |  |
| 2010-06-11 | Chepstow | 4 | 1 | NA | 121 | 12.0 | WIN |
| 2010-06-26 | Newmarket | 1 | NA | NA | 124 | NA | NA |
| 2010-08-19 | York | 1 | 8 | 80 | 124 | 101.0 |  |
| 2010-09-04 | Haydock | 2 | 13 | 80 | 125 | 34.0 |  |
| 2010-09-16 | Yarmouth | 4 | 6 | 78 | 132 | 23.0 |  |
| 2010-09-23 | Wolverhampton | 5 | 8 | 74 | 122 | 12.0 |  |
| 2010-09-30 | Kempton | 6 | 1 | 70 | 121 | 11.0 | WIN |
| 2010-10-13 | Kempton | 3 | 3 | 70 | 121 | 34.0 |  |
| 2010-10-18 | Pontefract | 5 | 6 | 70 | 128 | 34.0 |  |
| 2010-10-27 | Kempton | 2 | 7 | 72 | 117 | 21.0 |  |
| 2010-11-17 | Lingfield | 5 | 8 | 68 | 128 | 23.0 |  |
| 2010-11-29 | Wolverhampton | 6 | 10 | 65 | 133 | 41.0 |  |
| 2010-12-08 | Kempton | 5 | NA | NA | 124 | NA | NA |
| 2010-12-09 | Wolverhampton | 6 | 5 | 61 | 129 | 26.0 |  |
| 2010-12-16 | Kempton | 6 | 7 | 57 | 129 | 51.0 |  |
| 2011-12-02 | Wolverhampton | 6 | 10 | 59 | 132 | 26.0 |  |
| 2011-12-15 | Southwell | 6 | 10 | 57 | 129 | 34.0 |  |
| 2012-02-06 | Wolverhampton | 6 | 10 | 54 | 119 | 51.0 |  |
| 2012-12-21 | Wolverhampton | 7 | NA | NA | 131 | NA | NA |
| 2013-01-07 | Wolverhampton | 6 | NA | NA | 131 | NA | NA |
| 2013-02-28 | Kempton | 7 | 4 | 50 | 133 | 51.0 |  |
| 2013-03-15 | Wolverhampton | 7 | 10 | 50 | 133 | 9.0 |  |

Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):

| win_date | prior_or | win_or | next_or | verdict |
|---|---|---|---|---|
| 2010-05-04 | NA | NA | NA | ambiguous (win row OR missing) |
| 2010-06-11 | NA | NA | NA | ambiguous (win row OR missing) |
| 2010-09-30 | 74 | 70 | 70 | ambiguous (rating fell) |

**Horse verdict: ambiguous (insufficient data)**

### Horse runner_id=1556178 (Set To Music) — 17 runs, NA wins in pool

| meeting_date | course | class | finish_position | official_rating | weight_pounds | starting_price_decimal | note |
|---|---|---|---|---|---|---|---|
| 2010-08-07 | Newmarket | 4 | 4 | NA | 126 | 5.00 |  |
| 2010-08-23 | Kempton | 5 | 9 | NA | 126 | 7.00 |  |
| 2010-09-15 | Beverley | 5 | 3 | NA | 126 | 6.00 |  |
| 2011-04-09 | Wolverhampton | 5 | 3 | 70 | 133 | 2.75 |  |
| 2011-06-12 | Doncaster | 5 | 1 | 70 | 126 | 3.75 | WIN |
| 2011-07-02 | Nottingham | 5 | 1 | 75 | 133 | 3.50 | WIN |
| 2011-07-28 | Nottingham | 4 | 1 | 85 | 130 | 2.63 | WIN |
| 2011-08-18 | York | 1 | 1 | 92 | 120 | 9.00 | WIN |
| 2011-09-08 | Doncaster | 1 | 2 | 110 | 118 | 3.25 |  |
| 2012-05-17 | York | 1 | 6 | 110 | 124 | 8.50 |  |
| 2012-06-02 | Haydock | 1 | 2 | 109 | 124 | 3.00 |  |
| 2012-06-18 | Warwick | 1 | 1 | 105 | 124 | 2.50 | WIN |
| 2012-07-07 | Haydock | 1 | 3 | 105 | 131 | 4.00 |  |
| 2012-07-21 | Newmarket | 1 | NA | NA | 131 | NA | NA |
| 2012-08-05 | Newbury | 1 | 2 | 105 | 132 | 3.00 |  |
| 2012-09-27 | Newmarket | 1 | 7 | 105 | 132 | 9.00 |  |
| 2012-10-06 | Newmarket | 1 | 11 | 105 | 128 | 8.00 |  |

Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):

| win_date | prior_or | win_or | next_or | verdict |
|---|---|---|---|---|
| 2011-06-12 | 70 | 70 | 75 | pre-race (rose only on next run) |
| 2011-07-02 | 70 | 75 | 85 | post-race (rose on win row) |
| 2011-07-28 | 75 | 85 | 92 | post-race (rose on win row) |
| 2011-08-18 | 85 | 92 | 110 | post-race (rose on win row) |
| 2012-06-18 | 109 | 105 | 105 | ambiguous (rating fell) |

**Horse verdict: mixed (both patterns observed)**

### Horse runner_id=1531254 (Thatcherite) — 75 runs, NA wins in pool

| meeting_date | course | class | finish_position | official_rating | weight_pounds | starting_price_decimal | note |
|---|---|---|---|---|---|---|---|
| 2011-04-30 | Thirsk | 4 | 4 | NA | 129 | 101.00 |  |
| 2011-05-24 | Ripon | 5 | NA | NA | 129 | NA | NA |
| 2011-07-13 | Catterick | 6 | 3 | NA | 129 | 17.00 |  |
| 2011-07-22 | Thirsk | 5 | 1 | NA | 129 | 5.50 | WIN |
| 2011-08-06 | Redcar | 4 | 4 | 68 | 118 | 4.50 |  |
| 2011-08-26 | Newcastle | 5 | 8 | 68 | 130 | 6.00 |  |
| 2011-09-03 | Thirsk | 5 | 1 | 67 | 130 | 15.00 | WIN |
| 2011-09-20 | Beverley | 5 | 13 | 71 | 127 | 9.50 |  |
| 2011-09-30 | Wolverhampton | 5 | 5 | 71 | 129 | 8.50 |  |
| 2011-11-01 | Redcar | 5 | 6 | 71 | 130 | 10.00 |  |
| 2012-02-21 | Southwell | 5 | 5 | 70 | 133 | 7.50 |  |
| 2012-03-15 | Wolverhampton | 5 | 1 | 68 | 132 | 7.00 | WIN |
| 2012-03-17 | Wolverhampton | 5 | NA | NA | 134 | NA | NA |
| 2012-04-01 | Doncaster | 1 | 7 | 74 | 124 | 101.00 |  |
| 2012-04-09 | Redcar | 4 | NA | NA | 122 | NA | NA |
| 2012-05-12 | Thirsk | 5 | NA | NA | 132 | NA | NA |
| 2012-05-26 | York | 4 | 12 | 74 | 127 | 21.00 |  |
| 2012-06-04 | Carlisle | 4 | 7 | 72 | 125 | 17.00 |  |
| 2012-06-18 | Wolverhampton | 5 | 7 | 74 | 139 | 15.00 |  |
| 2012-07-09 | Ripon | 5 | 6 | 69 | 139 | 17.00 |  |
| 2012-09-08 | Thirsk | 5 | 3 | 67 | 125 | 8.00 |  |
| 2012-09-18 | Thirsk | 5 | NA | NA | 128 | NA | NA |
| 2012-09-20 | Pontefract | 5 | 11 | 67 | 133 | 17.00 |  |
| 2012-10-12 | Wolverhampton | 5 | 12 | 70 | 132 | 21.00 |  |
| 2012-10-27 | Wolverhampton | 6 | 5 | 68 | 131 | 51.00 |  |
| 2013-06-01 | Newcastle | 5 | NA | NA | 127 | NA | NA |
| 2013-06-06 | Thirsk | 5 | 4 | 64 | 127 | 13.00 |  |
| 2013-06-15 | Musselburgh | 6 | 7 | 63 | 131 | 12.00 |  |
| 2013-06-17 | Carlisle | 5 | NA | NA | 126 | NA | NA |
| 2013-07-04 | Haydock | 5 | 9 | 61 | 131 | 17.00 |  |
| 2013-07-08 | Ripon | 5 | 12 | 60 | 130 | 21.00 |  |
| 2013-07-21 | Redcar | 6 | 4 | 57 | 135 | 17.00 |  |
| 2013-08-16 | Catterick | 6 | 2 | 55 | 131 | 9.00 |  |
| 2013-08-23 | Newcastle | 5 | 6 | 55 | 125 | 4.33 |  |
| 2013-09-06 | Newcastle | 5 | NA | NA | 124 | NA | NA |
| 2013-09-25 | Redcar | 6 | 4 | 58 | 126 | 3.75 |  |
| 2013-10-02 | Newcastle | 6 | 1 | 58 | 131 | 3.50 | WIN |
| 2013-10-05 | Redcar | 5 | 1 | 60 | 129 | 3.25 | WIN |
| 2013-10-15 | Newcastle | 5 | NA | NA | 129 | NA | NA |
| 2014-04-12 | Thirsk | 5 | 5 | 71 | 129 | 15.00 |  |
| 2014-04-23 | Catterick | 5 | 6 | 70 | 133 | 6.00 |  |
| 2014-05-06 | Catterick | 5 | 6 | 69 | 127 | 15.00 |  |
| 2014-05-18 | Ripon | 5 | 5 | 68 | 126 | 15.00 |  |
| 2014-05-24 | Catterick | 5 | NA | NA | 126 | NA | NA |
| 2014-05-26 | Carlisle | 5 | 2 | 68 | 136 | 9.50 |  |
| 2014-06-16 | Carlisle | 5 | 9 | 70 | 140 | 7.50 |  |
| 2014-06-27 | Newcastle | 5 | 4 | 70 | 138 | 6.50 |  |
| 2014-07-05 | Beverley | 4 | 1 | 70 | 125 | 9.00 | WIN |
| 2014-07-16 | Catterick | 4 | 6 | 75 | 128 | 11.00 |  |
| 2014-07-27 | Pontefract | 3 | 6 | 75 | 125 | 15.00 |  |
| 2014-08-02 | Thirsk | 4 | NA | NA | 128 | NA | NA |
| 2014-08-06 | Pontefract | 5 | NA | NA | 136 | NA | NA |
| 2014-08-17 | Pontefract | 5 | 11 | 74 | 137 | 13.00 |  |
| 2014-08-30 | Beverley | 5 | 9 | 73 | 134 | 7.00 |  |
| 2014-09-06 | Thirsk | 4 | NA | NA | 125 | NA | NA |
| 2014-09-17 | Beverley | 5 | 5 | 72 | 132 | 11.00 |  |
| 2014-09-25 | Pontefract | 5 | 3 | 72 | 130 | 34.00 |  |
| 2015-04-10 | Wolverhampton | 5 | 8 | 71 | 129 | 51.00 |  |
| 2015-04-18 | Thirsk | 5 | 6 | 70 | 128 | 8.50 |  |
| 2015-04-29 | Pontefract | 5 | 3 | 69 | 132 | 6.00 |  |
| 2015-05-12 | Beverley | 5 | 1 | 70 | 133 | 8.00 | WIN |
| 2015-05-22 | Pontefract | 4 | 5 | 73 | 124 | 29.00 |  |
| 2015-05-26 | Redcar | 4 | 3 | 73 | 125 | 8.50 |  |
| 2015-06-08 | Pontefract | 5 | 8 | 73 | 131 | 17.00 |  |
| 2015-06-18 | Leicester | 4 | 5 | 72 | 126 | 17.00 |  |
| 2015-06-22 | Wetherby | 4 | 5 | 72 | 127 | 15.00 |  |
| 2015-07-04 | Beverley | 4 | 11 | 71 | 125 | 15.00 |  |
| 2015-07-20 | Beverley | 5 | 5 | 70 | 132 | 9.00 |  |
| 2015-08-08 | Haydock | 5 | 6 | 68 | 134 | 9.00 |  |
| 2015-08-12 | Beverley | 5 | 6 | 67 | 129 | 17.00 |  |
| 2015-08-29 | Beverley | 5 | 3 | 67 | 128 | 11.00 |  |
| 2015-09-08 | Redcar | 5 | 7 | 67 | 125 | 13.00 |  |
| 2015-09-16 | Beverley | 5 | NA | NA | 125 | NA | NA |
| 2015-09-24 | Pontefract | 5 | 3 | 65 | 123 | 10.00 |  |
| 2015-10-03 | Redcar | 5 | 1 | 65 | 128 | 5.50 | WIN |

Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):

| win_date | prior_or | win_or | next_or | verdict |
|---|---|---|---|---|
| 2011-07-22 | NA | NA | 68 | ambiguous (win row OR missing) |
| 2011-09-03 | 68 | 67 | 71 | ambiguous (rating fell) |
| 2012-03-15 | 70 | 68 | NA | ambiguous (rating fell) |
| 2013-10-02 | 58 | 58 | 60 | pre-race (rose only on next run) |
| 2013-10-05 | 58 | 60 | NA | post-race (rose on win row) |
| 2014-07-05 | 70 | 70 | 75 | pre-race (rose only on next run) |
| 2015-05-12 | 69 | 70 | 73 | post-race (rose on win row) |
| 2015-10-03 | 65 | 65 | NA | ambiguous (no rise observed) |

**Horse verdict: mixed (both patterns observed)**

### Horse runner_id=1662706 (Lord Franklin) — 50 runs, NA wins in pool

| meeting_date | course | class | finish_position | official_rating | weight_pounds | starting_price_decimal | note |
|---|---|---|---|---|---|---|---|
| 2011-08-20 | Chester | 4 | 13 | NA | 129 | 67.00 |  |
| 2011-09-13 | Haydock | 5 | 5 | NA | 129 | 34.00 |  |
| 2011-10-08 | York | 3 | 7 | NA | 129 | 51.00 |  |
| 2012-06-20 | Hamilton | 6 | 7 | 49 | 122 | 6.00 |  |
| 2012-07-09 | Ayr | 6 | 2 | 46 | 122 | 13.00 |  |
| 2012-07-19 | Hamilton | 6 | 1 | 49 | 116 | 3.00 | WIN |
| 2012-07-30 | Ayr | 6 | 4 | 55 | 123 | 3.75 |  |
| 2012-08-24 | Hamilton | 6 | 3 | 55 | 123 | 4.00 |  |
| 2012-10-02 | Ayr | 6 | 2 | 55 | 126 | 3.75 |  |
| 2012-10-16 | Wolverhampton | 6 | 5 | 55 | 129 | 5.50 |  |
| 2012-10-26 | Wolverhampton | 6 | 3 | 55 | 126 | 4.50 |  |
| 2012-11-06 | Wolverhampton | 6 | 3 | 55 | 133 | 4.33 |  |
| 2013-04-06 | Wolverhampton | 6 | 10 | 55 | 128 | 8.00 |  |
| 2013-05-06 | Warwick | 6 | 8 | 54 | 122 | 13.00 |  |
| 2013-05-21 | Newcastle | 6 | 3 | 53 | 126 | 6.50 |  |
| 2013-06-05 | Ayr | 6 | 3 | 53 | 131 | 5.50 |  |
| 2013-06-12 | Hamilton | 6 | 1 | 53 | 133 | 5.50 | WIN |
| 2013-07-01 | Pontefract | 5 | 2 | 60 | 125 | 8.00 |  |
| 2013-07-06 | Leicester | 6 | 1 | 60 | 137 | 2.88 | WIN |
| 2013-07-18 | Hamilton | 4 | 4 | 67 | 131 | 3.50 |  |
| 2013-08-02 | Musselburgh | 5 | 3 | 66 | 138 | 6.00 |  |
| 2013-08-11 | Leicester | 5 | 2 | 65 | 130 | 4.50 |  |
| 2013-09-22 | Hamilton | 5 | 2 | 69 | 135 | 5.00 |  |
| 2013-09-30 | Hamilton | 5 | NA | NA | 128 | NA | NA |
| 2014-04-08 | Pontefract | 5 | 4 | 69 | 127 | 6.00 |  |
| 2014-04-20 | Musselburgh | 4 | 6 | 69 | 123 | 4.50 |  |
| 2014-05-04 | Hamilton | 5 | 4 | 68 | 129 | 4.00 |  |
| 2014-05-23 | Haydock | 5 | 1 | 67 | 130 | 3.13 | WIN |
| 2014-05-30 | Haydock | 5 | 2 | 67 | 136 | 3.25 |  |
| 2014-06-05 | Hamilton | 4 | 4 | 72 | 125 | 4.50 |  |
| 2014-07-08 | Pontefract | 5 | 4 | 72 | 137 | 15.00 |  |
| 2014-07-17 | Hamilton | 4 | 2 | 72 | 132 | 13.00 |  |
| 2014-07-30 | Redcar | 5 | NA | NA | 137 | 5.00 | NA |
| 2014-08-28 | Hamilton | 4 | 2 | 71 | 133 | 9.00 |  |
| 2014-09-07 | York | 4 | 11 | 70 | 128 | 13.00 |  |
| 2014-09-21 | Hamilton | 5 | 1 | 70 | 136 | 5.00 | WIN |
| 2014-10-08 | Nottingham | 5 | 1 | 72 | 132 | 9.00 | WIN |
| 2014-10-20 | Pontefract | 4 | 4 | 78 | 131 | 11.00 |  |
| 2015-04-20 | Pontefract | 4 | 12 | 78 | 126 | 29.00 |  |
| 2015-04-26 | Wetherby | 4 | 9 | 78 | 131 | 26.00 |  |
| 2015-05-16 | Thirsk | 4 | 10 | 76 | 126 | 23.00 |  |
| 2015-06-04 | Hamilton | 4 | 9 | 73 | 127 | 7.00 |  |
| 2015-07-04 | Nottingham | 4 | 3 | 71 | 133 | 10.00 |  |
| 2015-07-13 | Wetherby | 5 | 1 | 69 | 133 | 6.00 | WIN |
| 2015-08-01 | Hamilton | 5 | 1 | 73 | 138 | 5.50 | WIN |
| 2015-08-20 | Hamilton | 4 | 6 | 76 | 138 | 8.50 |  |
| 2015-09-03 | Haydock | 4 | 12 | 76 | 132 | 13.00 |  |
| 2015-09-28 | Hamilton | 5 | 4 | 75 | 133 | 13.00 |  |
| 2015-09-30 | Nottingham | 3 | 1 | 75 | 126 | 17.00 | WIN |
| 2015-10-10 | York | 4 | 9 | 80 | 131 | 21.00 |  |

Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):

| win_date | prior_or | win_or | next_or | verdict |
|---|---|---|---|---|
| 2012-07-19 | 46 | 49 | 55 | post-race (rose on win row) |
| 2013-06-12 | 53 | 53 | 60 | pre-race (rose only on next run) |
| 2013-07-06 | 60 | 60 | 67 | pre-race (rose only on next run) |
| 2014-05-23 | 68 | 67 | 67 | ambiguous (rating fell) |
| 2014-09-21 | 70 | 70 | 72 | pre-race (rose only on next run) |
| 2014-10-08 | 70 | 72 | 78 | post-race (rose on win row) |
| 2015-07-13 | 71 | 69 | 73 | ambiguous (rating fell) |
| 2015-08-01 | 69 | 73 | 76 | post-race (rose on win row) |
| 2015-09-30 | 75 | 75 | 80 | pre-race (rose only on next run) |

**Horse verdict: mixed (both patterns observed)**

### Horse runner_id=1748623 (Obboorr) — 16 runs, NA wins in pool

| meeting_date | course | class | finish_position | official_rating | weight_pounds | starting_price_decimal | note |
|---|---|---|---|---|---|---|---|
| 2012-05-17 | Newmarket | 5 | 7 | NA | 129 | 17.00 |  |
| 2013-06-17 | Carlisle | 5 | 4 | NA | 140 | 26.00 |  |
| 2013-07-08 | Ripon | 5 | 4 | NA | 138 | 17.00 |  |
| 2013-07-28 | Pontefract | 4 | 3 | 64 | 124 | 23.00 |  |
| 2013-08-13 | Carlisle | 5 | 4 | 64 | 135 | 9.00 |  |
| 2013-08-19 | Thirsk | 4 | 3 | 64 | 124 | 7.00 |  |
| 2013-09-11 | Carlisle | 5 | 9 | 64 | 130 | 4.00 |  |
| 2013-09-19 | Pontefract | 4 | 4 | 64 | 123 | 11.00 |  |
| 2013-10-02 | Newcastle | 5 | 7 | 63 | 129 | 8.50 |  |
| 2013-10-18 | Redcar | 6 | 5 | 62 | 144 | 13.00 |  |
| 2014-01-22 | Kempton | 6 | 1 | 60 | 136 | 3.75 | WIN |
| 2014-01-31 | Lingfield | 5 | 4 | 60 | 150 | 3.25 |  |
| 2014-06-20 | Redcar | 5 | NA | NA | 128 | NA | NA |
| 2014-07-08 | Pontefract | 5 | 5 | 65 | 130 | 8.00 |  |
| 2014-08-06 | Pontefract | 5 | 3 | 65 | 152 | 4.00 |  |
| 2014-08-29 | Wolverhampton | 6 | 5 | 65 | 138 | 10.00 |  |

Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):

| win_date | prior_or | win_or | next_or | verdict |
|---|---|---|---|---|
| 2014-01-22 | 62 | 60 | 60 | ambiguous (rating fell) |

**Horse verdict: ambiguous (insufficient data)**

### Horse runner_id=1792985 (Mukhabarat) — 6 runs, NA wins in pool

| meeting_date | course | class | finish_position | official_rating | weight_pounds | starting_price_decimal | note |
|---|---|---|---|---|---|---|---|
| 2012-09-20 | Yarmouth | 5 | 7 | NA | 129 | 8.00 |  |
| 2013-07-31 | Redcar | 5 | NA | NA | 131 | NA | NA |
| 2013-08-08 | Chepstow | 5 | 3 | NA | 131 | 1.91 |  |
| 2013-08-17 | Doncaster | 5 | 1 | NA | 131 | 4.00 | WIN |
| 2013-09-12 | Epsom_Downs | 5 | 6 | 75 | 133 | 4.50 |  |
| 2013-09-21 | Wolverhampton | 5 | NA | 73 | 130 | 4.50 |  |

Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):

| win_date | prior_or | win_or | next_or | verdict |
|---|---|---|---|---|
| 2013-08-17 | NA | NA | 75 | ambiguous (win row OR missing) |

**Horse verdict: ambiguous (insufficient data)**

### Horse runner_id=1964073 (Speedfiend) — 10 runs, 1 wins in pool

| meeting_date | course | class | finish_position | official_rating | weight_pounds | starting_price_decimal | note |
|---|---|---|---|---|---|---|---|
| 2013-06-08 | Newmarket | 4 | 7 | NA | 131 | 7.50 |  |
| 2013-07-04 | Yarmouth | 5 | 4 | NA | 131 | 2.38 |  |
| 2013-08-16 | Nottingham | 5 | 2 | NA | 131 | 6.00 |  |
| 2013-09-25 | Kempton | 5 | 2 | 81 | 131 | 6.00 |  |
| 2013-10-12 | Newmarket | 1 | 4 | 84 | 126 | 101.00 |  |
| 2014-04-02 | Kempton | 5 | 1 | 105 | 128 | 1.03 | WIN |
| 2014-04-30 | Ascot | 1 | 7 | 105 | 126 | 7.00 |  |
| 2014-06-14 | Sandown | 1 | 7 | 105 | 126 | 29.00 |  |
| 2014-07-26 | Newmarket | 2 | 15 | 100 | 131 | 34.00 |  |
| 2015-05-24 | Curragh | NA | 11 | 95 | 135 | 12.00 |  |

Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):

| win_date | prior_or | win_or | next_or | verdict |
|---|---|---|---|---|
| 2014-04-02 | 84 | 105 | 105 | post-race (rose on win row) |

**Horse verdict: post-race (rose on win row)**

### Horse runner_id=2008091 (Rock Charm) — 17 runs, 1 wins in pool

| meeting_date | course | class | finish_position | official_rating | weight_pounds | starting_price_decimal | note |
|---|---|---|---|---|---|---|---|
| 2013-10-23 | Newmarket | 4 | 12 | NA | 126 | 67.00 |  |
| 2013-11-01 | Newmarket | 4 | 6 | NA | 126 | 101.00 |  |
| 2014-08-04 | Windsor | 5 | 8 | NA | 130 | 67.00 |  |
| 2014-10-21 | Lingfield | 6 | 4 | 51 | 125 | 13.00 |  |
| 2014-11-29 | Wolverhampton | 6 | 2 | 50 | 125 | 2.50 |  |
| 2014-12-30 | Lingfield | 6 | 3 | 51 | 126 | 3.25 |  |
| 2015-01-18 | Kempton | 6 | 6 | 51 | 125 | 2.38 |  |
| 2015-02-01 | Chelmsford_City | 6 | 1 | 51 | 129 | 6.00 | WIN |
| 2015-02-11 | Kempton | 6 | 3 | 51 | 135 | 2.75 |  |
| 2015-03-10 | Southwell | 6 | 3 | 57 | 128 | 4.00 |  |
| 2015-03-19 | Chelmsford_City | 6 | 3 | 65 | 130 | 3.00 |  |
| 2015-04-07 | Pontefract | 5 | 12 | 60 | 119 | 17.00 |  |
| 2015-04-28 | Brighton | 6 | 2 | 57 | 125 | 6.00 |  |
| 2015-06-02 | Brighton | 6 | 8 | 57 | 130 | 12.00 |  |
| 2015-06-06 | Newcastle | 6 | 12 | 57 | 128 | 34.00 |  |
| 2015-06-15 | Nottingham | 6 | 10 | 55 | 125 | 26.00 |  |
| 2015-06-26 | Wolverhampton | 6 | 10 | 52 | 133 | 17.00 |  |

Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):

| win_date | prior_or | win_or | next_or | verdict |
|---|---|---|---|---|
| 2015-02-01 | 51 | 51 | 51 | ambiguous (no rise observed) |

**Horse verdict: ambiguous (insufficient data)**

### Horse runner_id=2058841 (Go Dan Go) — 14 runs, NA wins in pool

| meeting_date | course | class | finish_position | official_rating | weight_pounds | starting_price_decimal | note |
|---|---|---|---|---|---|---|---|
| 2014-07-14 | Ayr | 4 | NA | NA | 131 | NA | NA |
| 2014-08-28 | Hamilton | 5 | 3 | NA | 131 | 10.00 |  |
| 2014-09-19 | Ayr | 4 | 8 | NA | 131 | 21.00 |  |
| 2014-10-09 | Ayr | 4 | 3 | NA | 131 | 23.00 |  |
| 2015-04-03 | Musselburgh | 4 | 2 | 67 | 126 | 13.00 |  |
| 2015-04-13 | Redcar | 5 | 2 | 68 | 126 | 9.00 |  |
| 2015-04-23 | Beverley | 5 | 1 | 68 | 131 | 3.00 | WIN |
| 2015-05-11 | Musselburgh | 5 | 1 | 74 | 132 | 3.50 | WIN |
| 2015-05-16 | Doncaster | 4 | NA | NA | 130 | NA | NA |
| 2015-05-23 | Haydock | 2 | 10 | 84 | 116 | 17.00 |  |
| 2015-06-06 | Musselburgh | 3 | 3 | 84 | 127 | 9.00 |  |
| 2015-06-13 | Sandown | 3 | 3 | 85 | 130 | 15.00 |  |
| 2015-06-24 | Carlisle | 4 | 1 | 85 | 133 | 7.50 | WIN |
| 2015-07-04 | Carlisle | 4 | 1 | 91 | 139 | 3.25 | WIN |

Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):

| win_date | prior_or | win_or | next_or | verdict |
|---|---|---|---|---|
| 2015-04-23 | 68 | 68 | 74 | pre-race (rose only on next run) |
| 2015-05-11 | 68 | 74 | NA | post-race (rose on win row) |
| 2015-06-24 | 85 | 85 | 91 | pre-race (rose only on next run) |
| 2015-07-04 | 85 | 91 | NA | post-race (rose on win row) |

**Horse verdict: mixed (both patterns observed)**

### Horse runner_id=2154724 (Time For Art) — 6 runs, 1 wins in pool

| meeting_date | course | class | finish_position | official_rating | weight_pounds | starting_price_decimal | note |
|---|---|---|---|---|---|---|---|
| 2015-08-03 | Naas | NA | 11 | NA | 126 | 34.0 |  |
| 2015-08-13 | Leopardstown | NA | 4 | NA | 126 | 26.0 |  |
| 2015-09-02 | Gowran_Park | NA | 4 | NA | 126 | 26.0 |  |
| 2015-09-18 | Listowel | NA | 1 | 69 | 126 | 7.5 | WIN |
| 2015-09-29 | Fairyhouse | NA | 12 | 69 | 132 | 10.0 |  |
| 2015-10-13 | Curragh | NA | 17 | 69 | 139 | 13.0 |  |

Win-instance diagnostics (rating on the run before the win, on the win row itself, and on the next run):

| win_date | prior_or | win_or | next_or | verdict |
|---|---|---|---|---|
| 2015-09-18 | NA | 69 | 69 | ambiguous (no prior run in pool) |

**Horse verdict: ambiguous (insufficient data)**

### Audit A summary

| runner_id | name | n_runs | n_win_instances | verdict |
|---|---|---|---|---|
| 139,213 | Dancing Mystery | 44 | 4 | mixed (both patterns observed) |
| 267,718 | Tackcoat | 16 | 1 | ambiguous (insufficient data) |
| 518,627 | Mouseen | 17 | 1 | post-race (rose on win row) |
| 559,534 | Centenary | 27 | 1 | ambiguous (insufficient data) |
| 621,539 | Sell Out | 16 | 2 | ambiguous (insufficient data) |
| 680,043 | Pennyspider | 18 | 2 | pre-race (rose only on next run) |
| 699,651 | Orpen Fire | 6 | 1 | ambiguous (insufficient data) |
| 755,692 | Touching | 9 | 1 | ambiguous (insufficient data) |
| 727,029 | Castaneous | 16 | 1 | ambiguous (insufficient data) |
| 1,459,572 | Blakey's Boy | 11 | 1 | ambiguous (insufficient data) |
| 1,524,227 | Joyously | 27 | 3 | ambiguous (insufficient data) |
| 1,556,178 | Set To Music | 17 | 5 | mixed (both patterns observed) |
| 1,531,254 | Thatcherite | 75 | 8 | mixed (both patterns observed) |
| 1,662,706 | Lord Franklin | 50 | 9 | mixed (both patterns observed) |
| 1,748,623 | Obboorr | 16 | 1 | ambiguous (insufficient data) |
| 1,792,985 | Mukhabarat | 6 | 1 | ambiguous (insufficient data) |
| 1,964,073 | Speedfiend | 10 | 1 | post-race (rose on win row) |
| 2,008,091 | Rock Charm | 17 | 1 | ambiguous (insufficient data) |
| 2,058,841 | Go Dan Go | 14 | 4 | mixed (both patterns observed) |
| 2,154,724 | Time For Art | 6 | 1 | ambiguous (insufficient data) |

| verdict | n |
|---|---|
| ambiguous (insufficient data) | 12 |
| mixed (both patterns observed) | 5 |
| post-race (rose on win row) | 2 |
| pre-race (rose only on next run) | 1 |

Ambiguous/mixed horses: 139213, 267718, 559534, 621539, 699651, 755692, 727029, 1459572, 1524227, 1556178, 1531254, 1662706, 1748623, 1792985, 2008091, 2058841, 2154724

Instance-level counts (every classifiable win, not deduplicated to one verdict per horse):

| verdict | n |
|---|---|
| post-race (rose on win row) | 14 |
| pre-race (rose only on next run) | 11 |
| ambiguous (rating fell) | 8 |
| ambiguous (win row OR missing) | 8 |
| ambiguous (no rise observed) | 5 |
| ambiguous (no prior run in pool) | 3 |

At the horse level the classifier does not resolve to a single clean pattern: 2 horses read cleanly post-race, 1 read cleanly pre-race, 5 show both patterns on different wins, and 12 are ambiguous (no prior run in pool, missing rating, or no change either way). At the win-instance level: 14 instances rose on the win row itself, 11 rose only on the following run, and 8 instances show the rating falling on or after a win — which a simple "post-race credit" story does not predict at all.

Structural point independent of the above: these are handicap races, and `historic_races`/`historic_runners` carry `weight_pounds` alongside `official_rating` on the same runner row, with weight in a handicap being a function of the rating assigned before the race (that is what "handicap" means — the weight is how the rating is applied to the race). A rating recorded as a post-race assessment would have no mechanical link to the weight shown on the same row for the same run. This favours reading the value as the mark carried INTO the race, with the rise/fall/no-change pattern around wins reflecting the BHA's own review cadence (ratings are revised periodically, not race-by-race) rather than this table recording pre- vs post-race values inconsistently. This is inference from schema structure, not a query result, and does not override the empirical counts above.

## Audit B: column population and comment vocabulary

Universe: existing qualifying modelling universe as built by `R/extract_qualifying_races.R::extract_qualifying_races()` (races, per `sql/qualifying_races.sql`) and `R/extract_runners.R::extract_runners_for_races()` (runners, R-level Non-Runner / field-size / one-winner filters), called with the same parameters as `_targets.R` (`date_from = "2006-01-01"`, `date_to = "2015-10-14"`, `aw_courses = c("Kempton", "Lingfield", "Southwell", "Wolverhampton")`), replicating the `candidate_races` -> `qualifying_runners` -> `qualifying_races` chain exactly.

candidate_races: 7507 races. qualifying_runners: 66770 runner-rows. qualifying_races (post R-level filters): 7441 races.

Discovered `tack_*` columns on `historic_runners` (8): tack_hood, tack_visor, tack_blinkers, tack_eye_shield, tack_eye_cover, tack_cheek_piece, tack_pacifiers, tack_tongue_strap

Sanity check: row count from direct query matching qualifying_runners' Non-Runner filter = 66770 (vs qualifying_runners = 66770).

### B1. Column population

| table | column | n | n_populated | pct_populated |
|---|---|---|---|---|
| historic_runners | in_race_comment | 66,770 | 66,576 | 99.71 |
| historic_runners | days_since_ran | 66,770 | 66,768 | 100.00 |
| historic_runners | long_handicap | 66,770 | 1,920 | 2.88 |
| historic_runners | last_race_beaten_fav | 66,770 | 66,768 | 100.00 |
| historic_runners | speed_rating | 66,770 | 53,722 | 80.46 |
| historic_runners | distance_travelled | 66,770 | 65,731 | 98.44 |
| historic_runners | distance_behind_winner | 66,770 | 59,320 | 88.84 |
| historic_runners | tack_hood | 66,770 | 1,155 | 1.73 |
| historic_runners | tack_visor | 66,770 | 3,943 | 5.91 |
| historic_runners | tack_blinkers | 66,770 | 6,871 | 10.29 |
| historic_runners | tack_eye_shield | 66,770 | 808 | 1.21 |
| historic_runners | tack_eye_cover | 66,770 | 43 | 0.06 |
| historic_runners | tack_cheek_piece | 66,770 | 6,281 | 9.41 |
| historic_runners | tack_pacifiers | 66,770 | 0 | 0.00 |
| historic_runners | tack_tongue_strap | 66,770 | 4,431 | 6.64 |
| historic_races | winning_time_secs | 7,441 | 7,441 | 100.00 |
| historic_races | standard_time_secs | 7,441 | 7,441 | 100.00 |

### B2. 50 randomly sampled non-empty in_race_comment values (seed 42)

1. towards rear, headway over 1f out, stayed on towards finish
2. held up, ridden over 2f out, stayed on inside final furlong, nearest finish
3. chased leaders until outpaced over 2f out, headway on outside and hung left over 1f out, stayed on well in closing stages, unable to reach leading duo
4. led narrowly, ridden 1f out, kept on until headed and no extra towards finish
5. held up, in rear, ridden 3f out, never a factor
6. led, headed over 2f out, weakened inside final furlong
7. raced wide, held up, hanging right from halfway, very wide bend into straight, no chance after
8. led, ridden and headed 2f out, no extra inside final furlong
9. mid-division, ran wide from over 4f out, awkward and weakened over 3f out
10. midfield, weakened final 2f
11. mid-division, headway over 1f out, soon chasing leaders, ridden to lead well inside final furlong, stayed on well
12. close up, ridden over 3f out, edged left and no impression from over 1f out
13. held up, ridden over 1f out, never going pace to trouble leaders
14. chased leaders, under pressure well over 3f out, soon weakened
15. behind, ridden over 2f out, slightly outpaced over 1f out, stayed on inside final furlong, not reach leaders
16. in rear, ridden over 2f out, well beaten over 1f out
17. led, ridden and headed over 1f out, weakened inside final furlong
18. took keen hold, held up towards rear, pushed along on inside and struggling 3f out
19. held up, headway over 2f out, every chance entering final furlong, ran on
20. tracked leader, led over 5f out, ridden over 1f out, kept on well inside final furlong
21. led 1f, chased leader after, not handle bend and hung right 2f out, soon ridden, weakened inside final furlong
22. chased leaders, ridden over 2f out, soon beaten
23. dwelt close up, ridden and every chance over 1f out, unable to quicken inside final furlong
24. slowly into stride, soon held up in 3rd, ridden over 3f out, chased winner 2f out, stayed on same pace, no impression
25. always in rear, struggling 3f out
26. tracked leaders, ridden and every chance over 1f out, led inside final furlong, ran on
27. held up in last pair, plugged on final 2f, went poor 4th near finish
28. tracked leaders, ridden to lead 2f out, headed over 1f out, weakened inside final furlong
29. led early, chased leaders, ridden over 1f out, kept on towards finish
30. niggled along, always towards rear
31. tracked leader, ridden and every chance over 1f out, unable to quicken inside final furlong
32. chased leaders, lost place after 3f, behind from halfway, virtually pulled up
33. tracked leader, ridden to lead well over 1f out, headed 1f out, kept on one pace
34. made all, ridden over 1f out, ran on
35. with leader, led after 2f,  ridden over 2f out, headed over 1f out, soon weakened
36. tracked leaders, led over 3f out to over 2f out, weakened 2f out
37. raced keenly, led, ridden and headed over 1f out, lost 2nd inside final furlong, weakened
38. soon pushed along towards rear, headway and switched right over 1f out, driven and strong run inside final furlong, led near finish
39. led to over 6f out, chased leader, regained lead well over 2f out, ridden over 1f out, headed and unable to quicken final 100 yards
40. keen to post, soon outpaced, eased final 3f
41. held up, headway 4f out, chased leader over 2f out, stayed on same pace
42. tracked leaders, went 2nd 5f out, led over 2f out, ridden clear over 1f out, pushed out
43. in rear, ridden 2f out, stayed on final furlong, nearest finish
44. prominent, ridden along over 3f out, driven to challenge and every chance over 1f out, stayed on same pace
45. keen early, held up on inside, not clear run over 1f out, kept on inside final furlong
46. soon led, ridden and headed over 1f out, weakened final furlong
47. held up, never dangerous
48. prominent on inside, ridden to dispute lead inside final furlong, always held by winner
49. slowly away, ridden and headway 1f out, kept on inside final furlong
50. held up in touch, driven to challenge over 2f out, soon every chance, kept on same pace, no chance with winner

### B3. First-three-words frequency (top 60, raw case, no normalisation)

| first3 | count | pct | cum_pct |
|---|---|---|---|
| held up in | 4,207 | 6.319 | 6.319 |
| slowly into stride, | 3,071 | 4.613 | 10.932 |
| tracked leaders, ridden | 2,249 | 3.378 | 14.310 |
| held up towards | 2,165 | 3.252 | 17.562 |
| chased leaders, ridden | 1,600 | 2.403 | 19.965 |
| in touch, ridden | 1,231 | 1.849 | 21.814 |
| took keen hold, | 1,133 | 1.702 | 23.516 |
| led, ridden and | 1,023 | 1.537 | 25.053 |
| held up, headway | 976 | 1.466 | 26.519 |
| held up, ridden | 908 | 1.364 | 27.883 |
| tracked leader, ridden | 886 | 1.331 | 29.214 |
| held up mid-division, | 700 | 1.051 | 30.265 |
| tracked leader, led | 688 | 1.033 | 31.298 |
| towards rear, ridden | 627 | 0.942 | 32.240 |
| close up, ridden | 535 | 0.804 | 33.044 |
| mid-division, headway over | 518 | 0.778 | 33.822 |
| took keen hold | 511 | 0.768 | 34.590 |
| in rear, ridden | 485 | 0.728 | 35.318 |
| mid-division, ridden over | 485 | 0.728 | 36.046 |
| towards rear, headway | 476 | 0.715 | 36.761 |
| steadied start, held | 472 | 0.709 | 37.470 |
| led, headed over | 462 | 0.694 | 38.164 |
| always in rear | 429 | 0.644 | 38.808 |
| led, ridden over | 428 | 0.643 | 39.451 |
| soon led, ridden | 419 | 0.629 | 40.080 |
| chased leaders on | 388 | 0.583 | 40.663 |
| mid-division, ridden and | 380 | 0.571 | 41.234 |
| always towards rear | 336 | 0.505 | 41.739 |
| made all, ridden | 329 | 0.494 | 42.233 |
| prominent, ridden over | 329 | 0.494 | 42.727 |
| always behind | 323 | 0.485 | 43.212 |
| in touch, headway | 321 | 0.482 | 43.694 |
| chased leaders, pushed | 291 | 0.437 | 44.131 |
| tracked leaders, led | 289 | 0.434 | 44.565 |
| in touch in | 278 | 0.418 | 44.983 |
| led after 1f, | 277 | 0.416 | 45.399 |
| raced wide in | 274 | 0.412 | 45.811 |
| dwelt, held up | 273 | 0.410 | 46.221 |
| tracked leaders on | 245 | 0.368 | 46.589 |
| tracked leaders in | 241 | 0.362 | 46.951 |
| chased leader, ridden | 233 | 0.350 | 47.301 |
| tracked leaders, effort | 227 | 0.341 | 47.642 |
| led, ridden 2f | 226 | 0.339 | 47.981 |
| soon led, headed | 226 | 0.339 | 48.320 |
| in rear, headway | 216 | 0.324 | 48.644 |
| chased leaders, effort | 215 | 0.323 | 48.967 |
| in touch on | 214 | 0.321 | 49.288 |
| tracked leader until | 212 | 0.318 | 49.606 |
| tracked leaders, pushed | 198 | 0.297 | 49.903 |
| held up behind, | 197 | 0.296 | 50.199 |
| chased leader, led | 195 | 0.293 | 50.492 |
| mid-division, pushed along | 192 | 0.288 | 50.780 |
| led until over | 185 | 0.278 | 51.058 |
| tracked leaders, went | 185 | 0.278 | 51.336 |
| chased leaders, went | 184 | 0.276 | 51.612 |
| went left start, | 175 | 0.263 | 51.875 |
| tracked leading pair, | 173 | 0.260 | 52.135 |
| went right start, | 165 | 0.248 | 52.383 |
| always towards rear, | 164 | 0.246 | 52.629 |
| in touch, pushed | 163 | 0.245 | 52.874 |

### B4. Riding-style pattern counts (case-insensitive substring match)

Caveat: these are raw substring matches, not word-boundaried, so some counts include false positives — e.g. "led" also matches inside "travelled"/"settled". Reported as an upper bound on true occurrence of the term, per the literal pattern list requested.

| pattern | count | pct_of_nonempty |
|---|---|---|
| made all | 742 | 1.115 |
| led | 15,971 | 23.989 |
| prominent | 2,907 | 4.366 |
| chased leaders | 5,723 | 8.596 |
| mid-division | 6,493 | 9.753 |
| held up | 14,480 | 21.750 |
| in rear | 7,986 | 11.995 |
| headway | 16,677 | 25.050 |
| hampered | 1,315 | 1.975 |
| short of room | 351 | 0.527 |
| not clear run | 1,180 | 1.772 |
| switched | 2,434 | 3.656 |
| every chance | 2,650 | 3.980 |
| stayed on | 7,731 | 11.612 |
| weakened | 16,264 | 24.429 |
| no extra | 3,677 | 5.523 |

### B5. Runs-per-horse (prior qualifying runs) distribution

| quantile | prior_runs |
|---|---|
| min | 0 |
| p10 | 0 |
| p25 | 0 |
| median | 2 |
| p75 | 7 |
| p90 | 14 |
| max | 98 |

Runner-rows with zero prior qualifying runs: 17376 of 66770 (26.024%).

## Appendix: schema

### historic_runners

| column_name | data_type |
|---|---|
| runner_id | int |
| race_id | int |
| name | varchar(255) |
| foaling_date | date |
| colour | varchar(20) |
| distance_travelled | int |
| form_figures | varchar(80) |
| gender | char(1) |
| age | tinyint |
| bred | char(3) |
| cloth_number | tinyint |
| stall_number | tinyint |
| num_fences_jumped | tinyint |
| long_handicap | int |
| how_easy_won | int |
| in_race_comment | text |
| official_rating | int |
| official_rating_type | varchar(80) |
| speed_rating | int |
| speed_rating_type | varchar(80) |
| private_handicap | int |
| private_handicap_type | varchar(80) |
| trainer_name | varchar(80) |
| trainer_id | int |
| owner_name | varchar(80) |
| owner_id | int |
| jockey_name | varchar(80) |
| jockey_id | int |
| jockey_claim | int |
| dam_name | varchar(80) |
| dam_id | int |
| sire_name | varchar(80) |
| sire_id | int |
| dam_sire_name | varchar(80) |
| dam_sire_id | int |
| forecast_price | char(10) |
| forecast_price_decimal | float(8,2) |
| starting_price | char(10) |
| starting_price_decimal | float(8,2) |
| betting_text | text |
| position_in_betting | tinyint |
| finish_position | tinyint |
| amended_position | tinyint |
| unfinished | varchar(30) |
| distance_beaten | float(8,2) |
| distance_won | float(8,2) |
| distance_behind_winner | float(8,2) |
| prize_money | float(8,2) |
| tote_win | float(8,2) |
| tote_place | float(8,2) |
| days_since_ran | int |
| last_race_type_id | int |
| last_race_type | varchar(80) |
| last_race_beaten_fav | int |
| weight_pounds | int |
| penalty_weight | int |
| over_weight | int |
| tack_hood | tinyint(1) |
| tack_visor | tinyint(1) |
| tack_blinkers | tinyint(1) |
| tack_eye_shield | tinyint(1) |
| tack_eye_cover | tinyint(1) |
| tack_cheek_piece | tinyint(1) |
| tack_pacifiers | tinyint(1) |
| tack_tongue_strap | tinyint(1) |
| loaded_at | timestamp |

### historic_races

| column_name | data_type |
|---|---|
| race_id | int |
| meeting_id | int |
| meeting_date | date |
| course | varchar(255) |
| conditions | varchar(255) |
| race_name | varchar(255) |
| race_abbrev_name | varchar(80) |
| race_type_id | int |
| race_type | varchar(80) |
| race_num | tinyint |
| going | varchar(80) |
| direction | varchar(80) |
| class | tinyint |
| draw_advantage | varchar(80) |
| num_fences | tinyint |
| handicap | tinyint(1) |
| all_weather | tinyint(1) |
| seller | tinyint(1) |
| claimer | tinyint(1) |
| apprentice | tinyint(1) |
| maiden | tinyint(1) |
| amateur | tinyint(1) |
| num_runners | tinyint |
| num_finishers | tinyint |
| rating | int |
| group_race | int |
| min_age | tinyint |
| max_age | tinyint |
| distance_yards | int |
| added_money | float(8,2) |
| official_rating | int |
| speed_rating | int |
| private_handicap | int |
| scheduled_time | datetime |
| off_time | datetime |
| winning_time_disp | varchar(20) |
| winning_time_secs | float(10,2) |
| standard_time_disp | varchar(20) |
| standard_time_secs | float(10,2) |
| loaded_at | timestamp |

