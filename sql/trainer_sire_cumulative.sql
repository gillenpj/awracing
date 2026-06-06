-- trainer_sire_cumulative.sql
--
-- Pre-aggregated cumulative wins and races per (entity, meeting_date)
-- across the full historic_runners universe. The "entity" is either
-- a sire or a trainer, distinguished by `kind`. Replaces the in-R
-- `cumsum()` step from the previous build_strike_rates() that took
-- >21 hours on 1.72M rows.
--
-- Output columns:
--   kind             'sire' or 'trainer' (discriminator)
--   entity_id        sire_id when kind = 'sire', else trainer_id
--   meeting_date     date the cumulative is "as of" (inclusive)
--   wins_thru_date   cumulative wins for entity through end of meeting_date
--   races_thru_date  cumulative non-Non-Runner starts ditto
--
-- Within each (kind, entity_id), rows are unique by `meeting_date`:
-- same-day runs are collapsed in the per-day CTEs first so the
-- window function sees one row per (entity, day). This guarantees
-- the downstream `closest()` join in R has exactly one cumulative
-- record per day to match against, avoiding tie-break ambiguity.
--
-- Non-Runners are excluded to match the project-wide convention.
-- `won` is the same `coalesce(amended_position, finish_position) = 1`
-- rule used elsewhere in the pipeline.
--
-- No parameters.

WITH non_nr AS (
  SELECT
    rn.trainer_id,
    rn.sire_id,
    r.meeting_date,
    CASE
      WHEN COALESCE(rn.amended_position, rn.finish_position) = 1 THEN 1
      ELSE 0
    END AS won
  FROM historic_runners AS rn
  INNER JOIN historic_races AS r
    ON r.race_id = rn.race_id
  WHERE rn.unfinished IS NULL
     OR rn.unfinished <> 'Non-Runner'
),

sire_day AS (
  SELECT
    sire_id,
    meeting_date,
    SUM(won)  AS day_wins,
    COUNT(*)  AS day_races
  FROM non_nr
  WHERE sire_id IS NOT NULL
  GROUP BY sire_id, meeting_date
),

trainer_day AS (
  SELECT
    trainer_id,
    meeting_date,
    SUM(won)  AS day_wins,
    COUNT(*)  AS day_races
  FROM non_nr
  WHERE trainer_id IS NOT NULL
  GROUP BY trainer_id, meeting_date
),

sire_cum AS (
  SELECT
    'sire'           AS kind,
    sire_id          AS entity_id,
    meeting_date,
    SUM(day_wins) OVER (
      PARTITION BY sire_id
      ORDER BY meeting_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS wins_thru_date,
    SUM(day_races) OVER (
      PARTITION BY sire_id
      ORDER BY meeting_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS races_thru_date
  FROM sire_day
),

trainer_cum AS (
  SELECT
    'trainer'        AS kind,
    trainer_id       AS entity_id,
    meeting_date,
    SUM(day_wins) OVER (
      PARTITION BY trainer_id
      ORDER BY meeting_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS wins_thru_date,
    SUM(day_races) OVER (
      PARTITION BY trainer_id
      ORDER BY meeting_date
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS races_thru_date
  FROM trainer_day
)

SELECT * FROM sire_cum
UNION ALL
SELECT * FROM trainer_cum;
