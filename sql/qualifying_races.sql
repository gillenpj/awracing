-- qualifying_races.sql
--
-- Returns all qualifying All Weather Flat races from historic_races.
--
-- Filtering criteria:
--   - race_type = 'All Weather Flat'  (preferred over the unreliable
--     `all_weather` flag — see Session 3 review C3/W1)
--   - course: parameterised via ?aw_courses, interpolated from the
--     `aw_courses` target (single source of truth — review W4)
--   - maiden = 0       (non-maiden races only)
--   - handicap = 1     (handicap races only — conditions racing has a
--                      different weight structure and is mechanically
--                      incompatible with Owen's model)
--   - class 2 through 5 (Class 1 = Group/Listed conditions racing,
--                       excluded by the handicap filter in practice,
--                       but pinned here too for clarity)
--   - meeting_date between ?date_from and ?date_to. Lower bound is
--     2006-01-01 because the British class system was restructured
--     1 Jan 2006 and pre-2006 multi-digit class codes are incompatible
--     with the 2006+ 1-7 scheme (review C4).
--   - between 4 and 16 runners inclusive, enforced via HAVING after
--     counting runners so the count reflects the full field
--     (note: this counts *declared* runners; the post-Non-Runner
--      field-size re-check happens in R/extract_runners.R per C5).

SELECT
    r.race_id,
    r.meeting_date,
    r.course,
    r.class,
    r.going,
    r.distance_yards,
    r.handicap,
    r.direction,
    r.added_money,
    r.race_type,
    COUNT(rn.runner_id) AS num_runners

FROM historic_races AS r
INNER JOIN historic_runners AS rn
    ON rn.race_id = r.race_id

WHERE
    r.race_type = 'All Weather Flat'

    AND r.course IN (?aw_courses)

    AND r.maiden = 0

    AND r.handicap = 1

    AND r.class BETWEEN 2 AND 5

    AND r.meeting_date BETWEEN ?date_from AND ?date_to

GROUP BY
    r.race_id,
    r.meeting_date,
    r.course,
    r.class,
    r.going,
    r.distance_yards,
    r.handicap,
    r.direction,
    r.added_money,
    r.race_type

HAVING
    COUNT(rn.runner_id) BETWEEN 4 AND 16

ORDER BY
    r.meeting_date,
    r.race_id;
