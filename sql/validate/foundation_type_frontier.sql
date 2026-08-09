-- Where does the current tree sit on the recall/precision trade-off, and can a
-- probability model beat it at EVERY operating point?
--
-- Method: fit P(wood | era, soil, height, ground_level, addresses) on the train
-- half as a smoothed cell average (Laplace toward the global rate, k=20, with
-- backoff for sparse cells). Then sweep the decision threshold on the held-out
-- test half and trace recall vs false-positive rate. If that curve passes above
-- the current tree's single point, a probability model dominates it outright.

CREATE TEMP TABLE t AS
SELECT DISTINCT ON (s.building_id) s.building_id, s.foundation_type AS observed
FROM report.inquiry_sample s JOIN report.inquiry i ON i.id=s.inquiry_id
WHERE s.foundation_type IS NOT NULL AND s.delete_date IS NULL
ORDER BY s.building_id, i.document_date DESC NULLS LAST, s.id DESC;
CREATE INDEX ON t(building_id); ANALYZE t;

CREATE TEMP TABLE f AS
SELECT t.building_id, data.is_wood_family(t.observed) AS is_wood,
       data.is_wood_family(data.indicative_foundation_type(
           bp.construction_year_bag, bp.height, gr.code, bp.address_count)) AS v1_wood,
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
       (abs(hashtext(t.building_id)) % 10) < 7 AS is_train
FROM t JOIN data.building_precomputed bp ON bp.building_id=t.building_id
LEFT JOIN data.building_geographic_region gr ON gr.building_id=t.building_id;
ANALYZE f;

-- global + backoff levels, fitted on TRAIN only
CREATE TEMP TABLE g AS SELECT avg(is_wood::int)::numeric AS p FROM f WHERE is_train;
CREATE TEMP TABLE lvl2 AS SELECT era, soil, hgt, count(*) n, avg(is_wood::int)::numeric p
  FROM f WHERE is_train GROUP BY 1,2,3;
CREATE TEMP TABLE lvl1 AS SELECT era, soil, hgt, glv, addr, count(*) n, avg(is_wood::int)::numeric p
  FROM f WHERE is_train GROUP BY 1,2,3,4,5;
ANALYZE lvl2; ANALYZE lvl1;

CREATE TEMP TABLE scored AS
SELECT f.*,
       CASE WHEN l1.n >= 30 THEN (l1.p*l1.n + 20*COALESCE(l2.p,g.p)) / (l1.n + 20)
            WHEN l2.n >= 30 THEN (l2.p*l2.n + 20*g.p) / (l2.n + 20)
            ELSE g.p END AS p_wood
FROM f CROSS JOIN g
LEFT JOIN lvl1 l1 USING (era,soil,hgt,glv,addr)
LEFT JOIN lvl2 l2 USING (era,soil,hgt);
ANALYZE scored;

\echo '=== WHERE THE CURRENT TREE SITS (test half) ==='
SELECT count(*) FILTER (WHERE is_wood) AS actually_wood,
       round(100.0*count(*) FILTER (WHERE is_wood AND v1_wood)/nullif(count(*) FILTER (WHERE is_wood),0),1) AS wood_recall_pct,
       round(100.0*count(*) FILTER (WHERE NOT is_wood AND v1_wood)/nullif(count(*) FILTER (WHERE NOT is_wood),0),1) AS false_alarm_pct,
       round(100.0*count(*) FILTER (WHERE is_wood AND v1_wood)/nullif(count(*) FILTER (WHERE v1_wood),0),1) AS precision_pct
FROM scored WHERE NOT is_train;

\echo ''
\echo '=== THE FRONTIER: probability model, threshold swept (test half) ==='
WITH th AS (SELECT unnest(ARRAY[0.10,0.15,0.20,0.25,0.30,0.35,0.40,0.45,0.50,0.60,0.70]) AS c)
SELECT th.c AS threshold,
       round(100.0*count(*) FILTER (WHERE s.is_wood AND s.p_wood >= th.c)/nullif(count(*) FILTER (WHERE s.is_wood),0),1) AS wood_recall_pct,
       round(100.0*count(*) FILTER (WHERE NOT s.is_wood AND s.p_wood >= th.c)/nullif(count(*) FILTER (WHERE NOT s.is_wood),0),1) AS false_alarm_pct,
       round(100.0*count(*) FILTER (WHERE s.is_wood AND s.p_wood >= th.c)/nullif(count(*) FILTER (WHERE s.p_wood >= th.c),0),1) AS precision_pct,
       round(100.0*count(*) FILTER (WHERE s.is_wood = (s.p_wood >= th.c))/count(*),1) AS accuracy_pct
FROM th CROSS JOIN scored s WHERE NOT s.is_train
GROUP BY th.c ORDER BY th.c;

\echo ''
\echo '=== CALIBRATION: are the probabilities honest? (test half) ==='
SELECT width_bucket(p_wood, 0, 1, 10) AS bucket,
       round(min(p_wood),2) AS p_from, round(max(p_wood),2) AS p_to,
       count(*) AS n, round(100.0*avg(is_wood::int),1) AS actually_wood_pct
FROM scored WHERE NOT is_train GROUP BY 1 ORDER BY 1;
