-- trainer_sire_cumulative.sql
--
-- Pre-aggregated cumulative wins and races per (entity, meeting_date)
-- across the full historic_runners universe. The "entity" is a sire, a
-- trainer, or a jockey, distinguished by `kind`. Replaces the in-R
-- `cumsum()` step from the previous build_strike_rates() that took
-- >21 hours on 1.72M rows.
--
-- NOTE (paper 2): this file now also emits
--   * jockey rows (kind = 'jockey'), used for jockeySR and the jockey
--     AW premium, and
--   * two extra AW-restricted cumulative columns (aw_wins_thru_date,
--     aw_races_thru_date), the All-Weather-only analogues of the
--     overall columns, used for the trainer/sire/jockey AW-premium
--     features.
-- The trainer/sire overall columns (wins_thru_date, races_thru_date)
-- are computed identically to the earlier version, so paper 1's
-- strike_rates / fit are unaffected (build_strike_rates() reads only
-- the trainer/sire rows and the two overall columns).
--
-- Output columns:
--   kind                'sire', 'trainer', or 'jockey' (discriminator)
--   entity_id           sire_id / trainer_id / jockey_id per `kind`
--   meeting_date        date the cumulative is "as of" (inclusive)
--   wins_thru_date      cumulative wins for entity through meeting_date
--   races_thru_date     cumulative non-Non-Runner starts ditto
--   aw_wins_thru_date   cumulative wins on 'All Weather Flat' only
--   aw_races_thru_date  cumulative AW starts only
--
-- Within each (kind, entity_id), rows are unique by `meeting_date`:
-- same-day runs are collapsed in the per-day CTE first so the window
-- function sees one row per (entity, day). This guarantees the
-- downstream `closest()` join in R has exactly one cumulative record
-- per day to match against, avoiding tie-break ambiguity. The AW
-- cumulative is defined on the same per-day rows (carried forward on
-- non-AW days too), so a `closest()` lookup at any date returns the
-- correct running AW totals.
--
-- Non-Runners are excluded to match the project-wide convention.
-- `won` is the same `coalesce(amended_position, finish_position) = 1`
-- rule used elsewhere in the pipeline. `is_aw` flags the AW surface
-- via `race_type = 'All Weather Flat'` (the reliable filter — the
-- `all_weather` flag is not used, per the project data-scope decision).
--
-- No parameters.

WITH non_nr AS (
  SELECT
    rn.trainer_id,
    rn.sire_id,
    rn.jockey_id,
    r.meeting_date,
    CASE
      WHEN COALESCE(rn.amended_position, rn.finish_position) = 1 THEN 1
      ELSE 0
    END AS won,
    CASE
      WHEN r.race_type = 'All Weather Flat' THEN 1
      ELSE 0
    END AS is_aw
  FROM historic_runners AS rn
  INNER JOIN historic_races AS r
    ON r.race_id = rn.race_id
  WHERE rn.unfinished IS NULL
     OR rn.unfinished <> 'Non-Runner'
),

-- One unified long table of (kind, entity_id, ...) so the per-day
-- aggregation and the window cumulative are written once rather than
-- repeated per entity type. Rows with a NULL entity id are dropped
-- per kind (e.g. runs with no recorded sire do not contribute to a
-- sire's cumulative).
entity_runs AS (
  SELECT 'trainer' AS kind, trainer_id AS entity_id, meeting_date, won, is_aw
    FROM non_nr WHERE trainer_id IS NOT NULL
  UNION ALL
  SELECT 'sire' AS kind, sire_id AS entity_id, meeting_date, won, is_aw
    FROM non_nr WHERE sire_id IS NOT NULL
  UNION ALL
  SELECT 'jockey' AS kind, jockey_id AS entity_id, meeting_date, won, is_aw
    FROM non_nr WHERE jockey_id IS NOT NULL
),

entity_day AS (
  SELECT
    kind,
    entity_id,
    meeting_date,
    SUM(won)          AS day_wins,
    COUNT(*)          AS day_races,
    SUM(won * is_aw)  AS day_aw_wins,
    SUM(is_aw)        AS day_aw_races
  FROM entity_runs
  GROUP BY kind, entity_id, meeting_date
)

SELECT
  kind,
  entity_id,
  meeting_date,
  SUM(day_wins)     OVER w AS wins_thru_date,
  SUM(day_races)    OVER w AS races_thru_date,
  SUM(day_aw_wins)  OVER w AS aw_wins_thru_date,
  SUM(day_aw_races) OVER w AS aw_races_thru_date
FROM entity_day
WINDOW w AS (
  PARTITION BY kind, entity_id
  ORDER BY meeting_date
  ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
);
