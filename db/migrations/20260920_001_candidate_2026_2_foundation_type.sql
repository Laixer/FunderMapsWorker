-- model-2026.2 candidate: foundation type from LOCAL EVIDENCE with a cell prior.
--
-- What it is. A probabilistic foundation-type model that runs beside the
-- frozen model-2024.1 and never touches it. For every building it emits
-- P(wood), P(no_pile), P(concrete) and the class the product would show. The
-- probability comes from three levels of inspected neighbours -- the DBSCAN
-- cluster, its supercluster and the CBS neighbourhood -- shrunk, level by
-- level, onto a cell prior (era x soil x height x ground level x addresses)
-- fitted on the benchmark's train split. Five pseudo-observations per level.
--
-- Why. Candidate 2026.1 (cells only) reached 81.9% family accuracy on the
-- held-out benchmark and then over-predicted wood in every municipality it had
-- not been fitted on, because a cell cannot see where a building stands. The
-- harness sql/validate/foundation_type_local_evidence.sql (2026-09-17) showed
-- that local evidence removes that failure where it exists (per-municipality
-- wood share within a point of observed; 96.8% three-class accuracy on the
-- test half against 66.3% for the tree) and that the cell prior alone is the
-- fallback for the 77.6% of the national stock with no inspected neighbour.
--
-- Candidate discipline (docs/model-versioning.md section 6): this script builds
-- the model for the EVALUATION SAMPLE ONLY -- the benchmark v2 truth rows plus
-- the stratified population sample, ~300k buildings -- never for all 11.2M.
-- A national build is a promotion decision, taken after the scores.
--
-- Two evidence pools, so the candidate cannot mark its own homework:
--   * truth rows are scored with evidence from TRAIN rows only, leave-one-out,
--     exactly as the harness does; test rows never see other test rows.
--   * population rows (no truth) use evidence from ALL benchmark truth rows,
--     which is how the model would run in production.
-- The prior is fitted on train rows only in both cases.
--
-- Additive: one table, one function, one registry row. Reversible with
-- DROP TABLE, DROP FUNCTION and DELETE FROM data.model_version.
--
--   Applied through the ledger runner (db/migrations/README.md), never by hand:
--     bun run migrate --dry-run     then     bun run migrate --allow-prod   (as doadmin)
--   The runner wraps each file in one transaction, so this file carries no
--   BEGIN/COMMIT of its own.


-- ---------------------------------------------------------------------------
-- Feature bucketing, one place, so fit and predict cannot drift apart.
-- Same buckets as the harness and as ft_cell_2026_1 minus floor area (which
-- the harness showed adds nothing once local evidence is present).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION data.ft_cell_2026_2(
    construction_year integer, height double precision, soil_code text,
    ground_level numeric, address_count integer)
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
    (CASE WHEN address_count <= 1 THEN '0' WHEN address_count < 8 THEN '1' ELSE '2' END)
$$;

-- era|soil|height: the coarser cell a thin fine cell backs off to
CREATE OR REPLACE FUNCTION data.ft_cell_coarse_2026_2(cell text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT split_part(cell,'|',1) || '|' || split_part(cell,'|',2) || '|' || split_part(cell,'|',3)
$$;

-- ---------------------------------------------------------------------------
-- The prior: per-cell class rates, fitted on train rows only.
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS data.foundation_type_prior_2026_2;
CREATE TABLE data.foundation_type_prior_2026_2 (
    cell        text PRIMARY KEY,
    n           integer NOT NULL,
    p_wood      numeric(6,5) NOT NULL,
    p_no_pile   numeric(6,5) NOT NULL,
    p_concrete  numeric(6,5) NOT NULL
);
COMMENT ON TABLE data.foundation_type_prior_2026_2 IS
    'model-2026.2 candidate: smoothed class rates per cell (era|soil|height|ground level|addresses), fitted on benchmark v2 train rows. Coarse cells (era|soil|height) and the global row (cell = *) are included for back-off.';

WITH truth AS (
    SELECT e.building_id, e.observed_family,
           data.ft_cell_2026_2(bp.construction_year_bag, bp.height, gr.code, bp.ground_level, bp.address_count) AS cell
    FROM data.model_evaluation_sample e
    JOIN data.building_precomputed bp ON bp.building_id = e.building_id
    LEFT JOIN data.building_geographic_region gr ON gr.building_id = e.building_id
    WHERE e.sample_version = 2 AND e.purpose = 'truth' AND e.split = 'train'
      AND e.observed_family IN ('wood','no_pile','concrete')
), g AS (
    -- The global fallback. On an empty benchmark (a fresh database, e.g. the CI
    -- bootstrap) avg() over zero rows is NULL, which would violate the NOT NULL
    -- on p_wood; the whole build then yields no rows rather than a broken prior.
    SELECT count(*) n,
           COALESCE(avg((observed_family='wood')::int), 0) pw,
           COALESCE(avg((observed_family='no_pile')::int), 0) pn,
           COALESCE(avg((observed_family='concrete')::int), 0) pc
    FROM truth
), coarse AS (
    SELECT data.ft_cell_coarse_2026_2(cell) AS cell, count(*) n,
           avg((observed_family='wood')::int) pw, avg((observed_family='no_pile')::int) pn, avg((observed_family='concrete')::int) pc
    FROM truth GROUP BY 1
), fine AS (
    SELECT cell, count(*) n,
           avg((observed_family='wood')::int) pw, avg((observed_family='no_pile')::int) pn, avg((observed_family='concrete')::int) pc
    FROM truth GROUP BY 1
)
INSERT INTO data.foundation_type_prior_2026_2 (cell, n, p_wood, p_no_pile, p_concrete)
SELECT '*', g.n, g.pw, g.pn, g.pc FROM g WHERE g.n > 0
UNION ALL
SELECT c.cell, c.n,
       (c.pw*c.n + 20*g.pw)/(c.n+20), (c.pn*c.n + 20*g.pn)/(c.n+20), (c.pc*c.n + 20*g.pc)/(c.n+20)
FROM coarse c CROSS JOIN g
UNION ALL
SELECT f.cell, f.n,
       (f.pw*f.n + 20*COALESCE(c.pw,g.pw))/(f.n+20), (f.pn*f.n + 20*COALESCE(c.pn,g.pn))/(f.n+20), (f.pc*f.n + 20*COALESCE(c.pc,g.pc))/(f.n+20)
FROM fine f CROSS JOIN g
LEFT JOIN coarse c ON c.cell = data.ft_cell_coarse_2026_2(f.cell);

-- ---------------------------------------------------------------------------
-- The candidate output, evaluation sample only.
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS data.foundation_type_2026_2;
CREATE TABLE data.foundation_type_2026_2 (
    building_id       text PRIMARY KEY,
    purpose           text NOT NULL,             -- truth | population
    split             text,                      -- train | test | NULL
    scoring_mode      boolean NOT NULL,          -- true = train-only evidence, leave-one-out
    p_wood            numeric(6,5) NOT NULL,
    p_no_pile         numeric(6,5) NOT NULL,
    p_concrete        numeric(6,5) NOT NULL,
    predicted_family  text NOT NULL,             -- wood | no_pile | concrete
    evidence_level    text NOT NULL,             -- cluster | supercluster | neighborhood | none
    evidence_n        integer NOT NULL,          -- inspected buildings at that level (excluding itself)
    prior_cell        text NOT NULL,
    prior_p_wood      numeric(6,5) NOT NULL
);
COMMENT ON TABLE data.foundation_type_2026_2 IS
    'model-2026.2 candidate output on the evaluation sample: class probabilities from local inspected evidence (cluster > supercluster > neighbourhood) shrunk onto a cell prior. Scored, never served. See sql/model/candidate_2026_2_foundation_type.sql.';

WITH sample AS (
    -- a surveyed building can sit in the population sample too; the truth row wins
    SELECT DISTINCT ON (e.building_id) e.building_id, e.purpose, e.split, e.observed_family,
           bc.cluster_id, sc.supercluster_id, bp.neighborhood_id,
           data.ft_cell_2026_2(bp.construction_year_bag, bp.height, gr.code, bp.ground_level, bp.address_count) AS cell
    FROM data.model_evaluation_sample e
    JOIN data.building_precomputed bp ON bp.building_id = e.building_id
    LEFT JOIN data.building_geographic_region gr ON gr.building_id = e.building_id
    LEFT JOIN data.building_cluster bc ON bc.building_id = e.building_id
    LEFT JOIN data.supercluster sc ON sc.cluster_id = bc.cluster_id
    WHERE e.sample_version = 2
      AND (e.purpose = 'population' OR e.observed_family IN ('wood','no_pile','concrete'))
    ORDER BY e.building_id, (e.purpose = 'truth') DESC
), evidence AS (
    -- every truth building is evidence; the flag says whether it is train
    SELECT building_id, observed_family, cluster_id, supercluster_id, neighborhood_id, split = 'train' AS is_train
    FROM sample WHERE purpose = 'truth'
), agg AS (
    -- per level and key: class counts over ALL truth and over TRAIN truth only
    SELECT lvl, key,
           count(*) n_all, sum((observed_family='wood')::int) w_all, sum((observed_family='no_pile')::int) np_all, sum((observed_family='concrete')::int) co_all,
           count(*) FILTER (WHERE is_train) n_tr, sum((observed_family='wood')::int) FILTER (WHERE is_train) w_tr,
           sum((observed_family='no_pile')::int) FILTER (WHERE is_train) np_tr, sum((observed_family='concrete')::int) FILTER (WHERE is_train) co_tr
    FROM (
        SELECT 'c' AS lvl, cluster_id::text AS key, observed_family, is_train FROM evidence WHERE cluster_id IS NOT NULL
        UNION ALL SELECT 's', supercluster_id::text, observed_family, is_train FROM evidence WHERE supercluster_id IS NOT NULL
        UNION ALL SELECT 'n', neighborhood_id, observed_family, is_train FROM evidence WHERE neighborhood_id IS NOT NULL
    ) x GROUP BY 1,2
), pooled AS (
    -- population rows: all evidence. truth rows: train evidence only (then leave-one-out below).
    SELECT s.building_id, s.purpose, s.split, s.observed_family, s.cell,
           (s.purpose = 'truth') AS scoring_mode,
           (s.purpose = 'truth' AND s.split = 'train')::int AS self,
           COALESCE((s.observed_family='wood')::int,0) AS self_w, COALESCE((s.observed_family='no_pile')::int,0) AS self_np, COALESCE((s.observed_family='concrete')::int,0) AS self_co,
           COALESCE(CASE WHEN s.purpose='population' THEN c.n_all ELSE c.n_tr END,0) c_n,
           COALESCE(CASE WHEN s.purpose='population' THEN c.w_all ELSE c.w_tr END,0) c_w,
           COALESCE(CASE WHEN s.purpose='population' THEN c.np_all ELSE c.np_tr END,0) c_np,
           COALESCE(CASE WHEN s.purpose='population' THEN c.co_all ELSE c.co_tr END,0) c_co,
           COALESCE(CASE WHEN s.purpose='population' THEN sc.n_all ELSE sc.n_tr END,0) s_n,
           COALESCE(CASE WHEN s.purpose='population' THEN sc.w_all ELSE sc.w_tr END,0) s_w,
           COALESCE(CASE WHEN s.purpose='population' THEN sc.np_all ELSE sc.np_tr END,0) s_np,
           COALESCE(CASE WHEN s.purpose='population' THEN sc.co_all ELSE sc.co_tr END,0) s_co,
           COALESCE(CASE WHEN s.purpose='population' THEN nb.n_all ELSE nb.n_tr END,0) nb_n,
           COALESCE(CASE WHEN s.purpose='population' THEN nb.w_all ELSE nb.w_tr END,0) nb_w,
           COALESCE(CASE WHEN s.purpose='population' THEN nb.np_all ELSE nb.np_tr END,0) nb_np,
           COALESCE(CASE WHEN s.purpose='population' THEN nb.co_all ELSE nb.co_tr END,0) nb_co
    FROM sample s
    LEFT JOIN agg c  ON c.lvl = 'c'  AND c.key  = s.cluster_id::text
    LEFT JOIN agg sc ON sc.lvl = 's' AND sc.key = s.supercluster_id::text
    LEFT JOIN agg nb ON nb.lvl = 'n' AND nb.key = s.neighborhood_id
), prior AS (
    SELECT p.*, COALESCE(f.p_wood, c.p_wood, g.p_wood) pr_w, COALESCE(f.p_no_pile, c.p_no_pile, g.p_no_pile) pr_np,
           COALESCE(f.p_concrete, c.p_concrete, g.p_concrete) pr_co,
           COALESCE(CASE WHEN f.n >= 30 THEN f.cell END, CASE WHEN c.n >= 30 THEN c.cell END, '*') AS prior_cell
    FROM pooled p
    LEFT JOIN data.foundation_type_prior_2026_2 f ON f.cell = p.cell AND f.n >= 30
    LEFT JOIN data.foundation_type_prior_2026_2 c ON c.cell = data.ft_cell_coarse_2026_2(p.cell) AND c.n >= 30
    CROSS JOIN (SELECT * FROM data.foundation_type_prior_2026_2 WHERE cell = '*') g
), loo AS (
    SELECT *,
           c_n - self AS c_n1,  c_w - self*self_w AS c_w1,  c_np - self*self_np AS c_np1,  c_co - self*self_co AS c_co1,
           s_n - self AS s_n1,  s_w - self*self_w AS s_w1,  s_np - self*self_np AS s_np1,  s_co - self*self_co AS s_co1,
           nb_n - self AS nb_n1, nb_w - self*self_w AS nb_w1, nb_np - self*self_np AS nb_np1, nb_co - self*self_co AS nb_co1
    FROM prior
), l1 AS (
    SELECT *, (nb_w1 + 5*pr_w)/(nb_n1+5) p1_w, (nb_np1 + 5*pr_np)/(nb_n1+5) p1_np, (nb_co1 + 5*pr_co)/(nb_n1+5) p1_co FROM loo
), l2 AS (
    SELECT *, (s_w1 + 5*p1_w)/(s_n1+5) p2_w, (s_np1 + 5*p1_np)/(s_n1+5) p2_np, (s_co1 + 5*p1_co)/(s_n1+5) p2_co FROM l1
), l3 AS (
    SELECT *, (c_w1 + 5*p2_w)/(c_n1+5) p3_w, (c_np1 + 5*p2_np)/(c_n1+5) p3_np, (c_co1 + 5*p2_co)/(c_n1+5) p3_co FROM l2
)
INSERT INTO data.foundation_type_2026_2
SELECT building_id, purpose, split, scoring_mode,
       round(p3_w, 5), round(p3_np, 5), round(p3_co, 5),
       CASE WHEN p3_w >= 0.45 THEN 'wood' WHEN p3_np >= p3_co THEN 'no_pile' ELSE 'concrete' END,
       CASE WHEN c_n1 > 0 THEN 'cluster' WHEN s_n1 > 0 THEN 'supercluster' WHEN nb_n1 > 0 THEN 'neighborhood' ELSE 'none' END,
       CASE WHEN c_n1 > 0 THEN c_n1 WHEN s_n1 > 0 THEN s_n1 ELSE nb_n1 END,
       prior_cell, round(pr_w, 5)
FROM l3;

CREATE INDEX foundation_type_2026_2_purpose_idx ON data.foundation_type_2026_2 (purpose, split);

-- ---------------------------------------------------------------------------
-- Register the candidate. Inputs fingerprinted at build time.
-- ---------------------------------------------------------------------------
INSERT INTO data.model_version (slug, title, status, is_default, notes, inputs)
SELECT
    'model-2026.2-rc1',
    'Foundation type from local evidence with a cell prior (candidate)',
    'candidate',
    false,
    'Probabilistic foundation-type candidate: inspected class counts in the DBSCAN cluster, supercluster and CBS neighbourhood, shrunk (5 pseudo-observations per level) onto a cell prior (era, soil, height, ground level, addresses) fitted on benchmark v2 train rows. Built for the evaluation sample only. Harness sql/validate/foundation_type_local_evidence.sql, 2026-09-17: three-class family accuracy 96.8% on the test half (tree 66.3%), 60.5% in 30 held-out municipalities (tree 49.6%); 77.6% of the national stock has no local evidence and falls back to the prior.',
    jsonb_build_object(
        'note', 'row counts are fingerprints taken when this row was inserted',
        'model_evaluation_sample_v2', jsonb_build_object('rows', (SELECT count(*) FROM data.model_evaluation_sample WHERE sample_version = 2)),
        'building_cluster',          jsonb_build_object('rows', (SELECT count(*) FROM data.building_cluster)),
        'supercluster',              jsonb_build_object('rows', (SELECT count(*) FROM data.supercluster)),
        'building_precomputed',      jsonb_build_object('rows', (SELECT count(*) FROM data.building_precomputed)),
        'building_geographic_region',jsonb_build_object('rows', (SELECT count(*) FROM data.building_geographic_region))
    )
WHERE NOT EXISTS (SELECT 1 FROM data.model_version WHERE slug = 'model-2026.2-rc1');
