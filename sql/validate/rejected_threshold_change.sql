-- A REJECTED change. Kept because it looked obviously right, measured worse,
-- and somebody will propose it again.
--
-- `data.indicative_foundation_type` only calls a soft-soil building wooden
-- above 8.5 m. The data says the cliff is really at 10 m: in the train half,
-- the 8.5-10 m band is 34% wood and the 10-14 m band is 83%. Correcting the
-- threshold therefore looks like free accuracy.
--
-- It is not. Measured on the held-out half:
--
--     model         family acc   wood recall   non-wood recall
--     deployed        67.3%        60.2%           88.8%
--     this change     67.5%        52.4%           95.8%
--
-- +0.2 points of accuracy, -7.8 points of wood detection. The 6,798 buildings
-- it reclassifies are 42.2% genuinely wooden, so the trade is ~2,900 real
-- wooden-pile buildings in the test half alone for a rounding error.
--
-- The lesson generalises beyond this one threshold: **accuracy is the wrong
-- objective for this model.** A missed wooden pile and a wasted inspection are
-- not the same cost, and any tuning scored on accuracy alone will quietly
-- delete wooden buildings from the map. Score wood recall against false-alarm
-- rate instead — see foundation_type_frontier.sql.
--
-- The second change it bundles IS sound in isolation and worth keeping if the
-- classifier is ever rewritten: ground_level >= 8 m NAP is essentially never
-- wood (38 wood in 11,297 train buildings). It moves buildings between
-- non-wood classes only, so it costs no wood recall.
--
--   psql "$DB_URL" -f sql/validate/rejected_threshold_change.sql

CREATE TEMP TABLE t AS
SELECT DISTINCT ON (s.building_id) s.building_id, s.foundation_type AS observed
FROM report.inquiry_sample s JOIN report.inquiry i ON i.id=s.inquiry_id
WHERE s.foundation_type IS NOT NULL AND s.delete_date IS NULL
ORDER BY s.building_id, i.document_date DESC NULLS LAST, s.id DESC;
CREATE INDEX ON t(building_id); ANALYZE t;

CREATE TEMP TABLE f AS
SELECT t.building_id, t.observed, data.is_wood_family(t.observed) AS is_wood,
       bp.construction_year_bag AS yr, bp.height, bp.ground_level, bp.address_count,
       gr.code AS soil, (abs(hashtext(t.building_id)) % 10) < 7 AS is_train
FROM t JOIN data.building_precomputed bp ON bp.building_id=t.building_id
LEFT JOIN data.building_geographic_region gr ON gr.building_id=t.building_id;
ANALYZE f;

CREATE OR REPLACE FUNCTION pg_temp.ft_v3(construction_year int, height double precision,
                                         soil_code text, address_count int, glvl numeric)
RETURNS report.foundation_type LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN glvl >= 8 AND construction_year >= 1965 THEN 'concrete'::report.foundation_type
    WHEN glvl >= 8                               THEN 'no_pile'::report.foundation_type
    WHEN construction_year >= 1940 AND construction_year < 1965 AND address_count >= 8
        THEN 'concrete'::report.foundation_type
    WHEN construction_year >= 1965 AND (height < 14 OR height IS NULL)
         AND soil_code IN ('hz','ni-hz','ni-du') THEN 'no_pile'::report.foundation_type
    WHEN construction_year >= 1965 AND (height < 14 OR height IS NULL)
         AND (soil_code NOT IN ('hz','ni-hz','ni-du') OR soil_code IS NULL) THEN 'concrete'::report.foundation_type
    WHEN construction_year >= 1965 AND height >= 14 THEN 'concrete'::report.foundation_type
    WHEN construction_year >= 1700 AND construction_year < 1800
         AND (height < 14 OR height IS NULL) AND soil_code IN ('hz','ni-hz','ni-du') THEN 'no_pile'::report.foundation_type
    WHEN construction_year >= 1700 AND construction_year < 1800
         AND height >= 14 AND soil_code IN ('hz','ni-hz','ni-du') THEN 'wood'::report.foundation_type
    WHEN construction_year >= 1700 AND construction_year < 1800
         AND height < 10 AND (soil_code NOT IN ('hz','ni-hz','ni-du') OR soil_code IS NULL) THEN 'no_pile'::report.foundation_type
    WHEN construction_year >= 1700 AND construction_year < 1800
         AND (height >= 10 OR height IS NULL) AND (soil_code NOT IN ('hz','ni-hz','ni-du') OR soil_code IS NULL) THEN 'wood'::report.foundation_type
    WHEN construction_year >= 1800 AND construction_year < 1965
         AND (height < 14 OR height IS NULL) AND soil_code IN ('hz','ni-hz','ni-du') THEN 'no_pile'::report.foundation_type
    WHEN construction_year >= 1800 AND construction_year < 1965
         AND height >= 14 AND soil_code IN ('hz','ni-hz','ni-du') THEN 'wood'::report.foundation_type
    WHEN construction_year >= 1800 AND construction_year < 1965
         AND height < 10 AND soil_code NOT IN ('hz','ni-hz','ni-du') THEN 'no_pile'::report.foundation_type
    WHEN construction_year >= 1800 AND construction_year < 1920
         AND (height >= 10 OR height IS NULL)
         AND (soil_code NOT IN ('hz','ni-hz','ni-du') OR soil_code IS NULL) THEN 'wood'::report.foundation_type
    WHEN construction_year >= 1920 AND construction_year < 1965
         AND (height >= 10 OR height IS NULL)
         AND (soil_code NOT IN ('hz','ni-hz','ni-du') OR soil_code IS NULL) THEN 'wood_charger'::report.foundation_type
    WHEN construction_year < 1700 THEN 'no_pile'::report.foundation_type
    WHEN height >= 10.5 THEN 'wood'::report.foundation_type
    WHEN height < 10.5 THEN 'no_pile'::report.foundation_type
    ELSE 'other'::report.foundation_type
  END $$;

CREATE OR REPLACE FUNCTION pg_temp.fam3(ft report.foundation_type) RETURNS text
LANGUAGE sql IMMUTABLE AS $$ SELECT CASE WHEN ft IS NULL THEN NULL
  WHEN data.is_wood_family(ft) THEN 'wood' WHEN data.is_no_pile_family(ft) THEN 'no_pile'
  ELSE ft::text END $$;

\echo '=== TEST half: current tree vs v3 (one threshold + one guard changed) ==='
SELECT 'v1_current' AS model,
  round(100.0*count(*) FILTER (WHERE pg_temp.fam3(observed)=pg_temp.fam3(data.indicative_foundation_type(yr,height,soil,address_count)))/count(*),1) AS family_acc,
  round(100.0*count(*) FILTER (WHERE is_wood AND data.is_wood_family(data.indicative_foundation_type(yr,height,soil,address_count)))/nullif(count(*) FILTER (WHERE is_wood),0),1) AS wood_recall,
  round(100.0*count(*) FILTER (WHERE NOT is_wood AND NOT data.is_wood_family(data.indicative_foundation_type(yr,height,soil,address_count)))/nullif(count(*) FILTER (WHERE NOT is_wood),0),1) AS nonwood_recall
FROM f WHERE NOT is_train
UNION ALL
SELECT 'v3_candidate',
  round(100.0*count(*) FILTER (WHERE pg_temp.fam3(observed)=pg_temp.fam3(pg_temp.ft_v3(yr,height,soil,address_count,ground_level)))/count(*),1),
  round(100.0*count(*) FILTER (WHERE is_wood AND data.is_wood_family(pg_temp.ft_v3(yr,height,soil,address_count,ground_level)))/nullif(count(*) FILTER (WHERE is_wood),0),1),
  round(100.0*count(*) FILTER (WHERE NOT is_wood AND NOT data.is_wood_family(pg_temp.ft_v3(yr,height,soil,address_count,ground_level)))/nullif(count(*) FILTER (WHERE NOT is_wood),0),1)
FROM f WHERE NOT is_train;

\echo ''
\echo '=== where exactly does v3 differ? (test half) ==='
SELECT pg_temp.fam3(data.indicative_foundation_type(yr,height,soil,address_count)) AS v1_said,
       pg_temp.fam3(pg_temp.ft_v3(yr,height,soil,address_count,ground_level)) AS v3_says,
       count(*) AS n,
       round(100.0*count(*) FILTER (WHERE is_wood)/count(*),1) AS truly_wood_pct
FROM f WHERE NOT is_train
  AND pg_temp.fam3(data.indicative_foundation_type(yr,height,soil,address_count))
      IS DISTINCT FROM pg_temp.fam3(pg_temp.ft_v3(yr,height,soil,address_count,ground_level))
GROUP BY 1,2 ORDER BY 3 DESC;
