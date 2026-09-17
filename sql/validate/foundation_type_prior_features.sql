-- #152, week of 2026-09-17: which inputs we ALREADY own improve the prior?
--
-- Don (2026-09-17): clusters only after they are rebuilt (#170); GeoTOP on
-- hold until Yorick has the PostGIS assessment. What is left to test without
-- either: three inputs the production tree ignores.
--
--   G  data.building_groundwater_level.level  (vendor, 11.4 M rows, m, "lower = drier")
--   P  data.building_pleistocene.depth        (depth of the pleistocene sand, m)
--   B  bouwjaar x buurt: the inspected class share in the SAME CBS buurt AND
--      era band (Don's point E: buurt alone is too weak, bouwjaar with buurt
--      is stronger evidence). Train-only, leave-one-out, shrunk onto the cell
--      prior with 5 pseudo-observations. No clusters anywhere in this script.
--
-- Prior = the frontier cell model (era x soil x height x ground level x
-- addresses), fitted on benchmark v2 train rows. Each variant adds one input
-- as an extra cell dimension (G, P: 5 buckets) or as a shrinkage level (B).
-- Scored on the hash test half and separately on 30 held-out municipalities.
-- Read-only: SELECT plus temp tables.
--
--   psql "$DB_URL" -f sql/validate/foundation_type_prior_features.sql

\timing off
SET work_mem = '512MB';

DROP TABLE IF EXISTS f;
CREATE TEMP TABLE f AS
SELECT e.building_id,
       e.observed_family = 'wood' AS is_wood, e.observed_family,
       e.split = 'train' AS is_train,
       data.is_wood_family(data.indicative_foundation_type(bp.construction_year_bag, bp.height, gr.code, bp.address_count)) AS tree_wood,
       CASE WHEN bp.construction_year_bag < 1700 THEN 0 WHEN bp.construction_year_bag < 1800 THEN 1
            WHEN bp.construction_year_bag < 1880 THEN 2 WHEN bp.construction_year_bag < 1920 THEN 3
            WHEN bp.construction_year_bag < 1940 THEN 4 WHEN bp.construction_year_bag < 1965 THEN 5
            WHEN bp.construction_year_bag < 1980 THEN 6 ELSE 7 END AS era,
       CASE WHEN gr.code IN ('hz','ni-hz','ni-du') THEN 1 WHEN gr.code IS NULL THEN 2 ELSE 0 END AS soil,
       CASE WHEN bp.height IS NULL THEN 9 WHEN bp.height < 7 THEN 0 WHEN bp.height < 8.5 THEN 1
            WHEN bp.height < 10 THEN 2 WHEN bp.height < 12 THEN 3 WHEN bp.height < 14 THEN 4
            WHEN bp.height < 20 THEN 5 ELSE 6 END AS hgt,
       CASE WHEN bp.ground_level IS NULL THEN 9 WHEN bp.ground_level < -1 THEN 0
            WHEN bp.ground_level < 0 THEN 1 WHEN bp.ground_level < 1 THEN 2
            WHEN bp.ground_level < 3 THEN 3 WHEN bp.ground_level < 8 THEN 4 ELSE 5 END AS glv,
       CASE WHEN bp.address_count <= 1 THEN 0 WHEN bp.address_count < 8 THEN 1 ELSE 2 END AS addr,
       -- G: vendor groundwater level, 5 buckets + unknown
       CASE WHEN gw.level IS NULL THEN 9 WHEN gw.level < 1.0 THEN 0 WHEN gw.level < 1.5 THEN 1
            WHEN gw.level < 2.0 THEN 2 WHEN gw.level < 3.0 THEN 3 ELSE 4 END AS gwb,
       -- P: pleistocene depth, 5 buckets + unknown
       CASE WHEN pl.depth IS NULL THEN 9 WHEN pl.depth < 5 THEN 0 WHEN pl.depth < 10 THEN 1
            WHEN pl.depth < 15 THEN 2 WHEN pl.depth < 25 THEN 3 ELSE 4 END AS plb,
       bp.neighborhood_id,
       m.id AS municipality_id, m.name AS municipality,
       COALESCE((abs(hashtext(m.external_id)) % 10) = 3, false) AS geo_holdout
FROM data.model_evaluation_sample e
JOIN data.building_precomputed bp ON bp.building_id = e.building_id
LEFT JOIN data.building_geographic_region gr ON gr.building_id = e.building_id
LEFT JOIN data.building_groundwater_level gw ON gw.building_id = e.building_id
LEFT JOIN data.building_pleistocene pl ON pl.building_id = e.building_id
LEFT JOIN geocoder.neighborhood nb ON nb.id = bp.neighborhood_id
LEFT JOIN geocoder.district d ON d.id = nb.district_id
LEFT JOIN geocoder.municipality m ON m.id = d.municipality_id
WHERE e.sample_version = 2 AND e.purpose = 'truth'
  AND e.observed_family IN ('wood','no_pile','concrete');
CREATE INDEX ON f (neighborhood_id, era); ANALYZE f;

-- ---------------------------------------------------------------- priors
DROP TABLE IF EXISTS tr; CREATE TEMP TABLE tr AS SELECT * FROM f WHERE is_train AND NOT geo_holdout; ANALYZE tr;
DROP TABLE IF EXISTS g;  CREATE TEMP TABLE g  AS SELECT avg(is_wood::int)::numeric p FROM tr;
DROP TABLE IF EXISTS l2; CREATE TEMP TABLE l2 AS SELECT era, soil, hgt, count(*) n, avg(is_wood::int)::numeric p FROM tr GROUP BY 1,2,3;
DROP TABLE IF EXISTS l1; CREATE TEMP TABLE l1 AS SELECT era, soil, hgt, glv, addr, count(*) n, avg(is_wood::int)::numeric p FROM tr GROUP BY 1,2,3,4,5;
-- G and P as an extra fine dimension each
DROP TABLE IF EXISTS lg; CREATE TEMP TABLE lg AS SELECT era, soil, hgt, glv, addr, gwb, count(*) n, avg(is_wood::int)::numeric p FROM tr GROUP BY 1,2,3,4,5,6;
DROP TABLE IF EXISTS lp; CREATE TEMP TABLE lp AS SELECT era, soil, hgt, glv, addr, plb, count(*) n, avg(is_wood::int)::numeric p FROM tr GROUP BY 1,2,3,4,5,6;
-- B: buurt x era inspected counts (train only)
DROP TABLE IF EXISTS lb; CREATE TEMP TABLE lb AS SELECT neighborhood_id, era, count(*) n, sum(is_wood::int) w FROM tr WHERE neighborhood_id IS NOT NULL GROUP BY 1,2;
ANALYZE l2; ANALYZE l1; ANALYZE lg; ANALYZE lp; ANALYZE lb;

DROP TABLE IF EXISTS scored;
CREATE TEMP TABLE scored AS
WITH base AS (
  SELECT f.*, (f.is_train AND NOT f.geo_holdout)::int AS self,
         CASE WHEN l1.n >= 30 THEN (l1.p*l1.n + 20*COALESCE(l2.p,g.p))/(l1.n+20)
              WHEN l2.n >= 30 THEN (l2.p*l2.n + 20*g.p)/(l2.n+20) ELSE g.p END AS p_cell,
         lg.n AS g_n, lg.p AS g_p, lp.n AS p_n, lp.p AS p_p,
         COALESCE(lb.n,0) AS b_n, COALESCE(lb.w,0) AS b_w
  FROM f CROSS JOIN g
  LEFT JOIN l1 USING (era,soil,hgt,glv,addr)
  LEFT JOIN l2 USING (era,soil,hgt)
  LEFT JOIN lg USING (era,soil,hgt,glv,addr,gwb)
  LEFT JOIN lp USING (era,soil,hgt,glv,addr,plb)
  LEFT JOIN lb ON lb.neighborhood_id = f.neighborhood_id AND lb.era = f.era
)
SELECT *,
       -- G, P: the finer cell shrunk onto the cell prior (k = 20), back off when thin
       CASE WHEN g_n >= 30 THEN (g_p*g_n + 20*p_cell)/(g_n+20) ELSE p_cell END AS p_g,
       CASE WHEN p_n >= 30 THEN (p_p*p_n + 20*p_cell)/(p_n+20) ELSE p_cell END AS p_p_,
       -- B: buurt x era majority, leave-one-out, 5 pseudo-observations onto the cell prior
       ((b_w - self*is_wood::int) + 5*p_cell) / ((b_n - self) + 5) AS p_b
FROM base;
ANALYZE scored;

-- ------------------------------------------------------------------ reports
\echo ''
\echo '=== 0. coverage of the three inputs (truth rows) ==='
SELECT count(*) n,
       round(100.0*count(*) FILTER (WHERE gwb <> 9)/count(*),1) pct_with_groundwater,
       round(100.0*count(*) FILTER (WHERE plb <> 9)/count(*),1) pct_with_pleistocene,
       round(100.0*count(*) FILTER (WHERE b_n - self > 0)/count(*),1) pct_with_buurt_era_evidence
FROM scored;

\echo ''
\echo '=== 1. hash test half: wood recall at the tree''s false-alarm rate, per variant (best threshold with FA <= tree) ==='
WITH t AS (SELECT * FROM scored WHERE NOT is_train AND NOT geo_holdout),
tree AS (SELECT round(100.0*count(*) FILTER (WHERE NOT is_wood AND tree_wood)/nullif(count(*) FILTER (WHERE NOT is_wood),0),2) fa,
                round(100.0*count(*) FILTER (WHERE is_wood AND tree_wood)/nullif(count(*) FILTER (WHERE is_wood),0),1) recall,
                round(100.0*count(*) FILTER (WHERE is_wood = tree_wood)/count(*),1) acc FROM t),
sweep AS (
  SELECT model, th,
         round(100.0*count(*) FILTER (WHERE is_wood AND p >= th)/nullif(count(*) FILTER (WHERE is_wood),0),1) recall,
         round(100.0*count(*) FILTER (WHERE NOT is_wood AND p >= th)/nullif(count(*) FILTER (WHERE NOT is_wood),0),2) fa,
         round(100.0*count(*) FILTER (WHERE is_wood = (p >= th))/count(*),1) acc
  FROM t, LATERAL (VALUES ('cell', p_cell), ('cell+groundwater', p_g), ('cell+pleistocene', p_p_), ('cell+buurt*era', p_b)) v(model, p),
       generate_series(0.05, 0.95, 0.05) th
  GROUP BY 1,2)
SELECT 'tree' model, NULL::numeric th, recall, fa, acc FROM tree
UNION ALL
(SELECT DISTINCT ON (model) model, th, recall, fa, acc FROM sweep WHERE fa <= (SELECT fa FROM tree) ORDER BY model, recall DESC, th)
ORDER BY 3 DESC;

\echo ''
\echo '=== 2. held-out municipalities (no local evidence from them): same ==='
WITH t AS (SELECT * FROM scored WHERE geo_holdout),
tree AS (SELECT round(100.0*count(*) FILTER (WHERE NOT is_wood AND tree_wood)/nullif(count(*) FILTER (WHERE NOT is_wood),0),2) fa,
                round(100.0*count(*) FILTER (WHERE is_wood AND tree_wood)/nullif(count(*) FILTER (WHERE is_wood),0),1) recall,
                round(100.0*count(*) FILTER (WHERE is_wood = tree_wood)/count(*),1) acc FROM t),
sweep AS (
  SELECT model, th,
         round(100.0*count(*) FILTER (WHERE is_wood AND p >= th)/nullif(count(*) FILTER (WHERE is_wood),0),1) recall,
         round(100.0*count(*) FILTER (WHERE NOT is_wood AND p >= th)/nullif(count(*) FILTER (WHERE NOT is_wood),0),2) fa,
         round(100.0*count(*) FILTER (WHERE is_wood = (p >= th))/count(*),1) acc
  FROM t, LATERAL (VALUES ('cell', p_cell), ('cell+groundwater', p_g), ('cell+pleistocene', p_p_), ('cell+buurt*era', p_b)) v(model, p),
       generate_series(0.05, 0.95, 0.05) th
  GROUP BY 1,2)
SELECT 'tree' model, NULL::numeric th, recall, fa, acc FROM tree
UNION ALL
(SELECT DISTINCT ON (model) model, th, recall, fa, acc FROM sweep WHERE fa <= (SELECT fa FROM tree) ORDER BY model, recall DESC, th)
ORDER BY 3 DESC;

\echo ''
\echo '=== 3. wood share by the raw inputs (train rows), to see the shape of the signal ==='
SELECT 'groundwater bucket' AS input, gwb::text AS bucket, count(*) n, round(100.0*avg(is_wood::int),1) wood_pct FROM tr GROUP BY 2
UNION ALL
SELECT 'pleistocene bucket', plb::text, count(*), round(100.0*avg(is_wood::int),1) FROM tr GROUP BY 2
ORDER BY 1, 2;

\echo ''
\echo '=== 4. per-municipality wood share, test buildings, cell vs cell+buurt*era (>= 300 test buildings) ==='
SELECT municipality, geo_holdout held_out, count(*) n, round(100.0*avg(is_wood::int),1) observed,
       round(100.0*avg((p_cell >= 0.45)::int),1) cell_pct, round(100.0*avg((p_b >= 0.45)::int),1) buurt_era_pct,
       round(100.0*avg((p_g >= 0.45)::int),1) groundwater_pct
FROM scored WHERE NOT is_train OR geo_holdout GROUP BY 1,2 HAVING count(*) >= 300
ORDER BY abs(avg((p_cell >= 0.45)::int) - avg(is_wood::int)) DESC LIMIT 20;
