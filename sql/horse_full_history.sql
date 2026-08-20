-- horse_full_history.sql
--
-- Returns the complete cross-surface career history for a set of horses.
-- Joins historic_runners to historic_races to bring back race-level context
-- (date, course, type, class, going, distance) for every career run,
-- regardless of surface. Used to build form features for the qualifying AW
-- population.
--
-- `r.going` added for paper 3's going-affinity feature (R/build_going_features.R):
-- extends this existing path rather than adding a new query, per the
-- project's preference for reusing an established source over writing new
-- SQL when one already carries the needed race-level context.
--
-- Parameter:
--   ?runner_ids  Comma-separated list of runner_id values, injected via
--               DBI::sqlInterpolate() wrapped in DBI::SQL().

SELECT
    rn.runner_id,
    rn.race_id,
    rn.name,
    rn.foaling_date,
    rn.colour,
    rn.gender,
    rn.age,
    rn.stall_number,
    rn.finish_position,
    rn.amended_position,
    rn.unfinished,
    rn.official_rating,
    rn.weight_pounds,
    rn.tack_blinkers,
    rn.tack_visor,
    rn.tack_cheek_piece,
    rn.tack_tongue_strap,
    rn.starting_price_decimal,
    rn.trainer_id,
    rn.jockey_id,
    rn.sire_id,
    rn.dam_id,
    rn.distance_behind_winner,
    rn.days_since_ran,
    r.meeting_date,
    r.course,
    r.race_type,
    r.class,
    r.going,
    r.distance_yards
FROM historic_runners AS rn
INNER JOIN historic_races AS r
    ON r.race_id = rn.race_id
WHERE rn.runner_id IN (?runner_ids)
ORDER BY rn.runner_id, r.meeting_date;
