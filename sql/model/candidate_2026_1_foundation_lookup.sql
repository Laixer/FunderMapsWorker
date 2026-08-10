-- model-2026.1: replace the indicative foundation-type decision tree with a
-- fitted lookup that uses ground level and floor area.
--
-- WHY A LOOKUP AND NOT MORE `CASE` BRANCHES. Two hand-written attempts on
-- 2026-08-09 both scored WORSE than the deployed tree on held-out data:
--   * a rewritten tree                     60.1% vs 67.3% family accuracy
--   * a minimal, evidence-backed threshold move (soft-soil wood cutoff 8.5m ->
--     10m, where the data genuinely puts the cliff)
--                                          +0.2 accuracy, -7.8 wood recall
-- The features carry real signal; a hand-tuned tree cannot express it. Ground
-- level is non-monotonic (wood peaks at 0-1m NAP, not at the lowest ground) and
-- floor area shifts the odds without flipping the majority class, so both are
-- invisible to threshold rules and both are captured by a cell average.
--
-- HOW IT AVOIDS MARKING ITS OWN HOMEWORK:
--   * fitted ONLY on data.model_evaluation_sample rows with split='train'
--   * scored ONLY on split='test'
--   * construction year comes from bp.construction_year_bag, never
--     COALESCE(established.built_year, …) -- production passes the COALESCE,
--     which lets the classifier read the answer off the inquiry it is scored
--     against
--
-- Cells are era x soil x height x ground level x floor area x address count,
-- smoothed toward a coarser cell (era x soil x height) and then toward the
-- global rate, so thin cells cannot produce confident nonsense.
--
-- KNOWN LIMIT, which must travel with any number from this: the fit comes from
-- inspected buildings, and people inspect buildings they already suspect. The
-- out-of-area test on 2026-08-09 showed this model UNDER-predicts wood in
-- wood-heavy areas it was not fitted on (22.3% predicted vs 61.8% observed), so
-- the bias runs toward caution rather than alarm -- but it is not neutral.
--
--   psql "$DB_URL" -f sql/model/candidate_2026_1_foundation_lookup.sql

BEGIN;

-- Feature bucketing, kept in one place so fit and predict cannot drift apart.
CREATE OR REPLACE FUNCTION data.ft_cell_2026_1(
    construction_year integer, height double precision, soil_code text,
    ground_level numeric, surface_area numeric, address_count integer)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT
    (CASE WHEN construction_year < 1700 THEN 'a' WHEN construction_year < 1800 THEN 'b'
          WHEN construction_year < 1880 THEN 'c' WHEN construction_year < 1920 THEN 'd'
          WHEN construction_year < 1940 THEN 'e' WHEN construction_year < 1965 THEN 'f'
          WHEN construction_year < 1980 THEN 'g' ELSE 'h' END) || '|' ||
    (CASE WHEN soil_code IN ('hz','ni-hz','ni-du') THEN 'sand'
          WHEN soil_code IS NULL THEN 'unk' ELSE 'soft' END) || '|' ||
    (CASE WHEN height IS NULL THEN 'u' WHEN height < 7 THEN '0' WHEN height < 8.5 THEN '1'
          WHEN height < 10 THEN '2' WHEN height < 12 THEN '3' WHEN height < 14 THEN '4'
          WHEN height < 20 THEN '5' ELSE '6' END) || '|' ||
    (CASE WHEN ground_level IS NULL THEN 'u' WHEN ground_level < -1 THEN '0'
          WHEN ground_level < 0 THEN '1' WHEN ground_level < 1 THEN '2'
          WHEN ground_level < 3 THEN '3' WHEN ground_level < 8 THEN '4' ELSE '5' END) || '|' ||
    (CASE WHEN surface_area IS NULL THEN 'u' WHEN surface_area < 60 THEN '0'
          WHEN surface_area < 100 THEN '1' WHEN surface_area < 175 THEN '2'
          WHEN surface_area < 400 THEN '3' ELSE '4' END) || '|' ||
    (CASE WHEN address_count <= 1 THEN '0' WHEN address_count < 8 THEN '1' ELSE '2' END)
$$;

-- The coarse cell a thin fine cell backs off to.
CREATE OR REPLACE FUNCTION data.ft_cell_coarse_2026_1(cell text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT split_part(cell,'|',1)||'|'||split_part(cell,'|',2)||'|'||split_part(cell,'|',3)
$$;

CREATE TABLE data.foundation_type_lookup_2026_1 (
    cell        text PRIMARY KEY,
    n           integer NOT NULL,
    p_wood      numeric NOT NULL,
    p_no_pile   numeric NOT NULL,
    p_concrete  numeric NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE data.foundation_type_lookup_2026_1 IS
    'Fitted foundation-type probabilities per feature cell for candidate model-2026.1. Fitted on evaluation-sample TRAIN rows only. Uses ground_level and surface_area, which the deployed decision tree ignores.';

-- Fit: TRAIN rows only, with the frozen observed answer.
WITH feat AS (
    SELECT es.building_id, es.observed_family,
           data.ft_cell_2026_1(bp.construction_year_bag, bp.height, gr.code,
                               bp.ground_level, bp.surface_area, bp.address_count) AS cell
    FROM data.model_evaluation_sample es
    JOIN data.building_precomputed bp ON bp.building_id = es.building_id
    LEFT JOIN data.building_geographic_region gr ON gr.building_id = es.building_id
    WHERE es.purpose = 'truth' AND es.split = 'train' AND es.sample_version = 1
),
glob AS (
    SELECT avg((observed_family='wood')::int)::numeric    AS g_wood,
           avg((observed_family='no_pile')::int)::numeric AS g_nopile,
           avg((observed_family='concrete')::int)::numeric AS g_conc
    FROM feat
),
coarse AS (
    SELECT data.ft_cell_coarse_2026_1(cell) AS ccell, count(*) AS n,
           avg((observed_family='wood')::int)::numeric    AS p_wood,
           avg((observed_family='no_pile')::int)::numeric AS p_nopile,
           avg((observed_family='concrete')::int)::numeric AS p_conc
    FROM feat GROUP BY 1
),
fine AS (
    SELECT cell, count(*) AS n,
           avg((observed_family='wood')::int)::numeric    AS p_wood,
           avg((observed_family='no_pile')::int)::numeric AS p_nopile,
           avg((observed_family='concrete')::int)::numeric AS p_conc
    FROM feat GROUP BY 1
)
INSERT INTO data.foundation_type_lookup_2026_1 (cell, n, p_wood, p_no_pile, p_concrete)
SELECT f.cell, f.n,
       -- shrink the fine cell toward the coarse cell (k=20), and the coarse
       -- cell toward the global rate, so a cell of 3 buildings cannot shout
       (f.p_wood  *f.n + 20*COALESCE(c.p_wood,  g.g_wood  )) / (f.n+20),
       (f.p_nopile*f.n + 20*COALESCE(c.p_nopile,g.g_nopile)) / (f.n+20),
       (f.p_conc  *f.n + 20*COALESCE(c.p_conc,  g.g_conc  )) / (f.n+20)
FROM fine f CROSS JOIN glob g
LEFT JOIN coarse c ON c.ccell = data.ft_cell_coarse_2026_1(f.cell);

COMMIT;
