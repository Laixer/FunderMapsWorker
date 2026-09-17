-- #152 step 2 prototype: does LOCAL EVIDENCE fix what candidate 2026.1 got wrong?
--
-- Candidate 2026.1 scored 81.9% family accuracy on the held-out benchmark but
-- over-predicted wood outside the surveyed cores (Utrecht 7.4% predicted vs
-- 0.8% observed) because its cells cannot see where a building stands. The
-- hypothesis of #152: give the model the inspected majority AND the count in
-- the building's DBSCAN cluster, its supercluster and its CBS neighbourhood,
-- as features with shrinkage, and the over-prediction disappears while the
-- recall gain stays.
--
-- Truth: benchmark v2 (data.model_evaluation_sample, sample_version 2), the
-- frozen, QuickScan-free, evidence-graded set. Split as frozen there.
--
-- Two leakage guards, both essential:
--   1. Local evidence for ANY building is computed from TRAIN buildings only,
--      and for a train building its own row is left out (leave-one-out). A
--      test building never sees another test building's answer.
--   2. The tree gets construction_year_bag only (README).
--
-- Geographic hold-out: on top of the hash split, every municipality whose
-- external_id hashes into one bucket of ten is held out entirely (its train
-- buildings are dropped from the evidence pool). Scores are reported for the
-- hash test half AND for the held-out municipalities separately. The second
-- number is the one that candidate 2026.1 would have failed.
--
-- Read-only: SELECT plus temp tables.
--   psql "$DB_URL" -f sql/validate/foundation_type_local_evidence.sql

\timing off
SET work_mem = '512MB';

-- ---------------------------------------------------------------- truth + cells
DROP TABLE IF EXISTS f;
CREATE TEMP TABLE f AS
SELECT e.building_id,
       e.observed_family = 'wood' AS is_wood,
       e.observed_family,
       e.split = 'train' AS is_train,
       data.is_wood_family(data.indicative_foundation_type(
           bp.construction_year_bag, bp.height, gr.code, bp.address_count)) AS tree_wood,
       CASE WHEN data.is_wood_family(tr.t) THEN 'wood' WHEN data.is_no_pile_family(tr.t) THEN 'no_pile'
            WHEN data.is_concrete_family(tr.t) THEN 'concrete' ELSE 'other' END AS tree_class,
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
       bc.cluster_id,
       sc.supercluster_id,
       bp.neighborhood_id,
       m.id AS municipality_id,
       m.name AS municipality,
       COALESCE((abs(hashtext(m.external_id)) % 10) = 3, false) AS geo_holdout
FROM data.model_evaluation_sample e
JOIN data.building_precomputed bp ON bp.building_id = e.building_id
LEFT JOIN data.building_geographic_region gr ON gr.building_id = e.building_id
CROSS JOIN LATERAL (SELECT data.indicative_foundation_type(bp.construction_year_bag, bp.height, gr.code, bp.address_count) AS t) tr
LEFT JOIN data.building_cluster bc ON bc.building_id = e.building_id
LEFT JOIN data.supercluster sc ON sc.cluster_id = bc.cluster_id
LEFT JOIN geocoder.neighborhood nb ON nb.id = bp.neighborhood_id
LEFT JOIN geocoder.district d ON d.id = nb.district_id
LEFT JOIN geocoder.municipality m ON m.id = d.municipality_id
WHERE e.sample_version = 2 AND e.purpose = 'truth'
  AND e.observed_family IN ('wood','no_pile','concrete');
CREATE INDEX ON f (building_id); CREATE INDEX ON f (cluster_id); CREATE INDEX ON f (supercluster_id);
CREATE INDEX ON f (neighborhood_id); ANALYZE f;

-- evidence pool: train buildings outside the geographic hold-out
DROP TABLE IF EXISTS pool;
CREATE TEMP TABLE pool AS SELECT building_id, is_wood, observed_family, cluster_id, supercluster_id, neighborhood_id
FROM f WHERE is_train AND NOT geo_holdout;
CREATE INDEX ON pool (cluster_id); CREATE INDEX ON pool (supercluster_id); CREATE INDEX ON pool (neighborhood_id); ANALYZE pool;

-- ------------------------------------------------------- cell prior (as frontier)
DROP TABLE IF EXISTS g; CREATE TEMP TABLE g AS SELECT avg(is_wood::int)::numeric AS p,
  avg((observed_family='no_pile')::int)::numeric AS p_np, avg((observed_family='concrete')::int)::numeric AS p_co FROM pool;
DROP TABLE IF EXISTS lvl2; CREATE TEMP TABLE lvl2 AS
  SELECT era, soil, hgt, count(*) n, avg(is_wood::int)::numeric p,
         avg((observed_family='no_pile')::int)::numeric p_np, avg((observed_family='concrete')::int)::numeric p_co
  FROM f WHERE is_train AND NOT geo_holdout GROUP BY 1,2,3;
DROP TABLE IF EXISTS lvl1; CREATE TEMP TABLE lvl1 AS
  SELECT era, soil, hgt, glv, addr, count(*) n, avg(is_wood::int)::numeric p,
         avg((observed_family='no_pile')::int)::numeric p_np, avg((observed_family='concrete')::int)::numeric p_co
  FROM f WHERE is_train AND NOT geo_holdout GROUP BY 1,2,3,4,5;
ANALYZE lvl2; ANALYZE lvl1;

-- ---------------------------------------------- local evidence, leave-one-out
DROP TABLE IF EXISTS agg_c; CREATE TEMP TABLE agg_c AS
  SELECT cluster_id, count(*) n, sum(is_wood::int) w, sum((observed_family='no_pile')::int) np, sum((observed_family='concrete')::int) co
  FROM pool WHERE cluster_id IS NOT NULL GROUP BY 1;
DROP TABLE IF EXISTS agg_s; CREATE TEMP TABLE agg_s AS
  SELECT supercluster_id, count(*) n, sum(is_wood::int) w, sum((observed_family='no_pile')::int) np, sum((observed_family='concrete')::int) co
  FROM pool WHERE supercluster_id IS NOT NULL GROUP BY 1;
DROP TABLE IF EXISTS agg_n; CREATE TEMP TABLE agg_n AS
  SELECT neighborhood_id, count(*) n, sum(is_wood::int) w, sum((observed_family='no_pile')::int) np, sum((observed_family='concrete')::int) co
  FROM pool WHERE neighborhood_id IS NOT NULL GROUP BY 1;
ANALYZE agg_c; ANALYZE agg_s; ANALYZE agg_n;

DROP TABLE IF EXISTS scored;
CREATE TEMP TABLE scored AS
WITH base AS (
  SELECT f.*,
         -- the building's own row is in the pool when it is a train building outside the hold-out
         (f.is_train AND NOT f.geo_holdout)::int AS self,
         CASE WHEN l1.n >= 30 THEN (l1.p*l1.n + 20*COALESCE(l2.p,g.p)) / (l1.n + 20)
              WHEN l2.n >= 30 THEN (l2.p*l2.n + 20*g.p) / (l2.n + 20)
              ELSE g.p END AS p_cell,
         CASE WHEN l1.n >= 30 THEN (l1.p_np*l1.n + 20*COALESCE(l2.p_np,g.p_np)) / (l1.n + 20)
              WHEN l2.n >= 30 THEN (l2.p_np*l2.n + 20*g.p_np) / (l2.n + 20)
              ELSE g.p_np END AS p_cell_np,
         CASE WHEN l1.n >= 30 THEN (l1.p_co*l1.n + 20*COALESCE(l2.p_co,g.p_co)) / (l1.n + 20)
              WHEN l2.n >= 30 THEN (l2.p_co*l2.n + 20*g.p_co) / (l2.n + 20)
              ELSE g.p_co END AS p_cell_co,
         COALESCE(ac.n,0) AS c_n, COALESCE(ac.w,0) AS c_w, COALESCE(ac.np,0) AS c_np, COALESCE(ac.co,0) AS c_co,
         COALESCE(as_.n,0) AS s_n, COALESCE(as_.w,0) AS s_w, COALESCE(as_.np,0) AS s_np, COALESCE(as_.co,0) AS s_co,
         COALESCE(an.n,0) AS nb_n, COALESCE(an.w,0) AS nb_w, COALESCE(an.np,0) AS nb_np, COALESCE(an.co,0) AS nb_co
  FROM f CROSS JOIN g
  LEFT JOIN lvl1 l1 USING (era,soil,hgt,glv,addr)
  LEFT JOIN lvl2 l2 USING (era,soil,hgt)
  LEFT JOIN agg_c ac ON ac.cluster_id = f.cluster_id
  LEFT JOIN agg_s as_ ON as_.supercluster_id = f.supercluster_id
  LEFT JOIN agg_n an ON an.neighborhood_id = f.neighborhood_id
), loo AS (
  -- leave-one-out: subtract the building itself from every level it contributed to
  SELECT *,
         c_n - self AS c_n1,  c_w - self*is_wood::int AS c_w1,  c_np - self*(observed_family='no_pile')::int AS c_np1,  c_co - self*(observed_family='concrete')::int AS c_co1,
         s_n - self AS s_n1,  s_w - self*is_wood::int AS s_w1,  s_np - self*(observed_family='no_pile')::int AS s_np1,  s_co - self*(observed_family='concrete')::int AS s_co1,
         nb_n - self AS nb_n1, nb_w - self*is_wood::int AS nb_w1, nb_np - self*(observed_family='no_pile')::int AS nb_np1, nb_co - self*(observed_family='concrete')::int AS nb_co1
  FROM base
), shrunk AS (
  -- hierarchical shrinkage, m = 5 pseudo-observations at each step, per class:
  -- cell prior -> neighbourhood -> supercluster -> cluster
  SELECT *,
         (nb_w1  + 5*p_cell)    / (nb_n1 + 5) AS p_nb,
         (nb_np1 + 5*p_cell_np) / (nb_n1 + 5) AS p_nb_np,
         (nb_co1 + 5*p_cell_co) / (nb_n1 + 5) AS p_nb_co
  FROM loo
), shrunk2 AS (
  SELECT *,
         (s_w1  + 5*p_nb)    / (s_n1 + 5) AS p_sc,
         (s_np1 + 5*p_nb_np) / (s_n1 + 5) AS p_sc_np,
         (s_co1 + 5*p_nb_co) / (s_n1 + 5) AS p_sc_co
  FROM shrunk
), shrunk3 AS (
  SELECT *,
         (c_w1  + 5*p_sc)    / (c_n1 + 5) AS p_local,
         (c_np1 + 5*p_sc_np) / (c_n1 + 5) AS p_local_np,
         (c_co1 + 5*p_sc_co) / (c_n1 + 5) AS p_local_co
  FROM shrunk2
)
SELECT *,
       -- the class the product would show: wood when p_wood clears 0.45, else the likelier of the other two
       CASE WHEN p_local >= 0.45 THEN 'wood' WHEN p_local_np >= p_local_co THEN 'no_pile' ELSE 'concrete' END AS local_class,
       CASE WHEN p_cell >= 0.45 THEN 'wood' WHEN p_cell_np >= p_cell_co THEN 'no_pile' ELSE 'concrete' END AS cell_class
FROM shrunk3;
ANALYZE scored;

-- ------------------------------------------------------------------- reports
\echo ''
\echo '=== 0. sizes ==='
SELECT count(*) AS truth, count(*) FILTER (WHERE is_train) AS train, count(*) FILTER (WHERE NOT is_train) AS test,
       count(*) FILTER (WHERE geo_holdout) AS in_heldout_municipalities,
       count(DISTINCT municipality_id) FILTER (WHERE geo_holdout) AS heldout_municipalities,
       round(100.0*count(*) FILTER (WHERE c_n1 > 0)/count(*),1) AS pct_with_cluster_evidence,
       round(100.0*count(*) FILTER (WHERE nb_n1 > 0)/count(*),1) AS pct_with_nb_evidence
FROM scored;

\echo ''
\echo '=== 1. hash test half (not in held-out municipalities): tree vs cell prior vs local, at the tree''s false-alarm rate ==='
WITH t AS (SELECT * FROM scored WHERE NOT is_train AND NOT geo_holdout),
tree AS (
  SELECT round(100.0*count(*) FILTER (WHERE NOT is_wood AND tree_wood)/nullif(count(*) FILTER (WHERE NOT is_wood),0),2) AS fa FROM t
),
sweep AS (
  SELECT th, model,
         round(100.0*count(*) FILTER (WHERE is_wood AND p >= th)/nullif(count(*) FILTER (WHERE is_wood),0),1) AS recall,
         round(100.0*count(*) FILTER (WHERE NOT is_wood AND p >= th)/nullif(count(*) FILTER (WHERE NOT is_wood),0),2) AS fa,
         round(100.0*count(*) FILTER (WHERE is_wood = (p >= th))/count(*),1) AS acc
  FROM t, LATERAL (VALUES ('cell', p_cell), ('local', p_local)) v(model, p),
       generate_series(0.05, 0.95, 0.05) th
  GROUP BY th, model
)
SELECT 'tree' AS model, NULL::numeric AS th,
       round(100.0*count(*) FILTER (WHERE is_wood AND tree_wood)/nullif(count(*) FILTER (WHERE is_wood),0),1) AS recall,
       (SELECT fa FROM tree) AS fa,
       round(100.0*count(*) FILTER (WHERE is_wood = tree_wood)/count(*),1) AS acc
FROM t
UNION ALL
(SELECT model, th, recall, fa, acc FROM sweep s WHERE fa <= (SELECT fa FROM tree)
 ORDER BY model, th LIMIT 100)
ORDER BY 1, 2;

\echo ''
\echo '=== 2. HELD-OUT MUNICIPALITIES (no local evidence from them at all): same comparison ==='
WITH t AS (SELECT * FROM scored WHERE geo_holdout),
tree AS (
  SELECT round(100.0*count(*) FILTER (WHERE NOT is_wood AND tree_wood)/nullif(count(*) FILTER (WHERE NOT is_wood),0),2) AS fa FROM t
),
sweep AS (
  SELECT th, model,
         round(100.0*count(*) FILTER (WHERE is_wood AND p >= th)/nullif(count(*) FILTER (WHERE is_wood),0),1) AS recall,
         round(100.0*count(*) FILTER (WHERE NOT is_wood AND p >= th)/nullif(count(*) FILTER (WHERE NOT is_wood),0),2) AS fa,
         round(100.0*count(*) FILTER (WHERE is_wood = (p >= th))/count(*),1) AS acc
  FROM t, LATERAL (VALUES ('cell', p_cell), ('local', p_local)) v(model, p),
       generate_series(0.05, 0.95, 0.05) th
  GROUP BY th, model
)
SELECT 'tree' AS model, NULL::numeric AS th,
       round(100.0*count(*) FILTER (WHERE is_wood AND tree_wood)/nullif(count(*) FILTER (WHERE is_wood),0),1) AS recall,
       (SELECT fa FROM tree) AS fa,
       round(100.0*count(*) FILTER (WHERE is_wood = tree_wood)/count(*),1) AS acc
FROM t
UNION ALL
(SELECT model, th, recall, fa, acc FROM sweep s WHERE fa <= (SELECT fa FROM tree)
 ORDER BY model, th LIMIT 100)
ORDER BY 1, 2;

\echo ''
\echo '=== 3. per-municipality wood share, test buildings: observed vs cell@0.45 vs local@0.45 (municipalities with >= 300 test buildings) ==='
SELECT municipality, geo_holdout AS held_out, count(*) AS n,
       round(100.0*avg(is_wood::int),1) AS observed_pct,
       round(100.0*avg((tree_wood)::int),1) AS tree_pct,
       round(100.0*avg((p_cell >= 0.45)::int),1) AS cell_pct,
       round(100.0*avg((p_local >= 0.45)::int),1) AS local_pct
FROM scored WHERE NOT is_train OR geo_holdout
GROUP BY 1,2 HAVING count(*) >= 300
ORDER BY abs(avg((p_cell >= 0.45)::int) - avg(is_wood::int)) DESC
LIMIT 25;

\echo ''
\echo '=== 4. calibration of p_local on test buildings (all) ==='
SELECT width_bucket(p_local, 0, 1, 10) AS bucket, count(*) n,
       round(100.0*avg(p_local),1) AS predicted_pct, round(100.0*avg(is_wood::int),1) AS observed_pct
FROM scored WHERE NOT is_train OR geo_holdout GROUP BY 1 ORDER BY 1;

\echo ''
\echo '=== 5. how much of the lift is the evidence: test buildings by amount of local evidence ==='
SELECT CASE WHEN c_n1 >= 3 THEN 'cluster >= 3' WHEN c_n1 >= 1 THEN 'cluster 1-2'
            WHEN nb_n1 >= 10 THEN 'buurt >= 10 only' WHEN nb_n1 >= 1 THEN 'buurt 1-9 only' ELSE 'none' END AS evidence,
       count(*) n, round(100.0*avg(is_wood::int),1) AS observed_pct,
       round(100.0*count(*) FILTER (WHERE is_wood AND p_local >= 0.45)/nullif(count(*) FILTER (WHERE is_wood),0),1) AS local_recall,
       round(100.0*count(*) FILTER (WHERE NOT is_wood AND p_local >= 0.45)/nullif(count(*) FILTER (WHERE NOT is_wood),0),1) AS local_fa,
       round(100.0*count(*) FILTER (WHERE is_wood AND p_cell >= 0.45)/nullif(count(*) FILTER (WHERE is_wood),0),1) AS cell_recall,
       round(100.0*count(*) FILTER (WHERE NOT is_wood AND p_cell >= 0.45)/nullif(count(*) FILTER (WHERE NOT is_wood),0),1) AS cell_fa
FROM scored WHERE NOT is_train OR geo_holdout
GROUP BY 1 ORDER BY 2 DESC;

\echo ''
\echo '=== 6. NATIONAL COVERAGE: how much of the building stock has any local evidence (population sample, stratum-weighted; pool = all benchmark v2 truth) ==='
WITH pool AS (
  SELECT e.building_id, bc.cluster_id, sc.supercluster_id, bp.neighborhood_id
  FROM data.model_evaluation_sample e
  JOIN data.building_precomputed bp ON bp.building_id = e.building_id
  LEFT JOIN data.building_cluster bc ON bc.building_id = e.building_id
  LEFT JOIN data.supercluster sc ON sc.cluster_id = bc.cluster_id
  WHERE e.sample_version = 2 AND e.purpose = 'truth'
), ac AS (SELECT cluster_id, count(*) n FROM pool WHERE cluster_id IS NOT NULL GROUP BY 1),
   asc_ AS (SELECT supercluster_id, count(*) n FROM pool WHERE supercluster_id IS NOT NULL GROUP BY 1),
   an AS (SELECT neighborhood_id, count(*) n FROM pool WHERE neighborhood_id IS NOT NULL GROUP BY 1),
pop AS (
  SELECT e.building_id, e.stratum, COALESCE(ac.n,0) c_n, COALESCE(asc_.n,0) s_n, COALESCE(an.n,0) nb_n
  FROM data.model_evaluation_sample e
  JOIN data.building_precomputed bp ON bp.building_id = e.building_id
  LEFT JOIN data.building_cluster bc ON bc.building_id = e.building_id
  LEFT JOIN data.supercluster sc ON sc.cluster_id = bc.cluster_id
  LEFT JOIN ac ON ac.cluster_id = bc.cluster_id
  LEFT JOIN asc_ ON asc_.supercluster_id = sc.supercluster_id
  LEFT JOIN an ON an.neighborhood_id = bp.neighborhood_id
  WHERE e.sample_version = 2 AND e.purpose = 'population'
), w AS (
  SELECT p.*, sw.national_buildings::numeric / NULLIF(cnt.n,0) AS wt
  FROM pop p
  JOIN data.model_evaluation_stratum_weight sw ON sw.stratum = p.stratum AND sw.sample_version = 2
  JOIN (SELECT stratum, count(*) n FROM data.model_evaluation_sample WHERE sample_version = 2 AND purpose = 'population' GROUP BY 1) cnt ON cnt.stratum = p.stratum
)
SELECT count(*) AS sample_rows, round(sum(wt)) AS national_buildings,
       round(100*sum(wt) FILTER (WHERE c_n >= 1)/sum(wt),1) AS pct_cluster_ge1,
       round(100*sum(wt) FILTER (WHERE c_n >= 3)/sum(wt),1) AS pct_cluster_ge3,
       round(100*sum(wt) FILTER (WHERE s_n >= 1)/sum(wt),1) AS pct_supercluster_ge1,
       round(100*sum(wt) FILTER (WHERE nb_n >= 1)/sum(wt),1) AS pct_buurt_ge1,
       round(100*sum(wt) FILTER (WHERE nb_n >= 10)/sum(wt),1) AS pct_buurt_ge10,
       round(100*sum(wt) FILTER (WHERE c_n = 0 AND s_n = 0 AND nb_n = 0)/sum(wt),1) AS pct_no_evidence
FROM w;

\echo ''
\echo '=== 7. THREE-CLASS family accuracy (wood / no_pile / concrete): tree vs cell vs local, test half and held-out municipalities ==='
SELECT CASE WHEN geo_holdout THEN 'held-out municipalities' ELSE 'hash test half' END AS set, count(*) AS n,
       round(100.0*count(*) FILTER (WHERE tree_class = observed_family)/count(*),1) AS tree_acc,
       round(100.0*count(*) FILTER (WHERE cell_class = observed_family)/count(*),1) AS cell_acc,
       round(100.0*count(*) FILTER (WHERE local_class = observed_family)/count(*),1) AS local_acc
FROM scored WHERE NOT is_train OR geo_holdout GROUP BY 1 ORDER BY 1 DESC;

\echo ''
\echo '=== 7b. per-class recall, hash test half ==='
SELECT observed_family, count(*) AS n,
       round(100.0*count(*) FILTER (WHERE tree_class = observed_family)/count(*),1) AS tree_recall,
       round(100.0*count(*) FILTER (WHERE cell_class = observed_family)/count(*),1) AS cell_recall,
       round(100.0*count(*) FILTER (WHERE local_class = observed_family)/count(*),1) AS local_recall
FROM scored WHERE NOT is_train AND NOT geo_holdout GROUP BY 1 ORDER BY 2 DESC;

\echo ''
\echo '=== 7c. confusion of the local model, hash test half (observed -> predicted) ==='
SELECT observed_family, local_class, count(*) FROM scored WHERE NOT is_train AND NOT geo_holdout GROUP BY 1,2 ORDER BY 1, 3 DESC;
