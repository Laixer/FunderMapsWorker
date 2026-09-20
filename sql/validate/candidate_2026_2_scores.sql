-- Scores for candidate model-2026.2, read-only.
--
-- Split out of the migration on 2026-09-20: db/migrations files run through
-- the ledger runner (postgres.js), which does not understand psql's \echo.
-- Run this after the migration has been applied:
--
--   psql "$DB_URL" -f sql/validate/candidate_2026_2_scores.sql
--
\echo ''
\echo '=== rows by purpose / evidence level ==='
SELECT purpose, evidence_level, count(*), round(100.0*avg((predicted_family='wood')::int),1) AS pct_wood
FROM data.foundation_type_2026_2 GROUP BY 1,2 ORDER BY 1,3 DESC;

\echo ''
\echo '=== three-class accuracy on truth/test (must match the harness: ~96.8%) ==='
SELECT count(*) n,
       round(100.0*count(*) FILTER (WHERE t.predicted_family = e.observed_family)/count(*),1) AS family_acc,
       round(100.0*count(*) FILTER (WHERE e.observed_family='wood' AND t.predicted_family='wood')/nullif(count(*) FILTER (WHERE e.observed_family='wood'),0),1) AS wood_recall
FROM data.foundation_type_2026_2 t
JOIN data.model_evaluation_sample e ON e.building_id = t.building_id AND e.sample_version = 2
WHERE t.purpose = 'truth' AND t.split = 'test';

\echo ''
\echo '=== national wood share, population sample, stratum-weighted: candidate vs frozen model ==='
SELECT round(100*sum(wt * (t.predicted_family='wood')::int)/sum(wt),2) AS candidate_wood_pct,
       round(100*sum(wt * data.is_wood_family(m.foundation_type)::int)/sum(wt),2) AS frozen_wood_pct
FROM data.foundation_type_2026_2 t
JOIN data.model_evaluation_sample e ON e.building_id = t.building_id AND e.sample_version = 2 AND e.purpose = 'population'
JOIN data.model_evaluation_stratum_weight sw ON sw.stratum = e.stratum AND sw.sample_version = 2
JOIN (SELECT stratum, count(*) n FROM data.model_evaluation_sample WHERE sample_version = 2 AND purpose = 'population' GROUP BY 1) cnt ON cnt.stratum = e.stratum
CROSS JOIN LATERAL (SELECT sw.national_buildings::numeric / cnt.n AS wt) w
LEFT JOIN data.model_risk_static_2024_1 m ON m.building_id = t.building_id;
