-- runners_for_races.sql
--
-- Returns all runner rows from historic_runners for a given set of race_ids.
-- Used to pull the full field for each qualifying race.
--
-- Parameter:
--   ?race_ids  Comma-separated list of race_id values, injected via
--              DBI::sqlInterpolate() wrapped in DBI::SQL().

SELECT
    runner_id,
    race_id,
    name,
    foaling_date,
    colour,
    gender,
    age,
    stall_number,
    finish_position,
    amended_position,
    unfinished,
    official_rating,
    weight_pounds,
    tack_blinkers,
    tack_visor,
    tack_cheek_piece,
    tack_tongue_strap,
    starting_price_decimal,
    trainer_id,
    jockey_id,
    sire_id,
    dam_id,
    distance_behind_winner,
    days_since_ran
FROM historic_runners
WHERE race_id IN (?race_ids);
