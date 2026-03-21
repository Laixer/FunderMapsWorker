-- Phase A3: Fix Sample Matviews
--
-- Bug: Current matviews use array_agg()[1] relying on subquery ORDER BY,
-- but PostgreSQL does NOT guarantee array_agg preserves subquery ordering
-- through GROUP BY. This means the "best inquiry" selection is nondeterministic.
--
-- Fix: Use DISTINCT ON with explicit ORDER BY, which guarantees deterministic
-- row selection.
--
-- Strategy: Create v2 matviews → REFRESH → validate → rename-swap in transaction.

--------------------------------------------------------------------------------
-- Step 1: Create v2 matviews
--------------------------------------------------------------------------------

-- Inquiry type priority (shared across all three matviews):
-- foundation_research (0) > inspectionpit (1) > second_opinion (2) > note (3) >
-- additional_research (4) > demolition_research (5) > architectural_research (6) >
-- archieve_research (7) > quickscan (8) > other (100)
-- Ties broken by most recent document_date.

CREATE MATERIALIZED VIEW data.building_sample_v2 AS
SELECT DISTINCT ON (b.external_id)
    b.external_id AS building_id,
    is2.foundation_type,
    is2.enforcement_term,
    is2.damage_cause,
    is2.overall_quality,
    is2.recovery_advised,
    date_part('year', is2.built_year::date)::integer AS built_year,
    is2.groundwater_level_temp AS groundwater_level,
    is2.wood_level,
    is2.foundation_depth,
    i.type AS inquiry_type,
    i.document_date,
    i.id
FROM report.inquiry_sample is2
JOIN report.inquiry i ON is2.inquiry = i.id
JOIN geocoder.building b ON b.external_id = is2.building::text
WHERE i.document_date >= b.built_year::date - interval '5 years'
ORDER BY b.external_id,
    CASE i.type
        WHEN 'foundation_research' THEN 0
        WHEN 'inspectionpit' THEN 1
        WHEN 'second_opinion' THEN 2
        WHEN 'note' THEN 3
        WHEN 'additional_research' THEN 4
        WHEN 'demolition_research' THEN 5
        WHEN 'architectural_research' THEN 6
        WHEN 'archieve_research' THEN 7
        WHEN 'quickscan' THEN 8
        ELSE 100
    END,
    i.document_date DESC
WITH NO DATA;

CREATE UNIQUE INDEX ON data.building_sample_v2 (building_id);

---

CREATE MATERIALIZED VIEW data.cluster_sample_v2 AS
SELECT DISTINCT ON (bc.cluster_id)
    bc.cluster_id,
    is2.foundation_type,
    is2.enforcement_term,
    is2.damage_cause,
    is2.overall_quality,
    is2.recovery_advised,
    date_part('year', is2.built_year::date)::integer AS built_year,
    is2.groundwater_level_temp AS groundwater_level,
    is2.wood_level,
    is2.foundation_depth,
    i.type AS inquiry_type,
    i.document_date,
    i.id
FROM data.building_cluster bc
JOIN geocoder.building b ON b.external_id = bc.building_id
JOIN report.inquiry_sample is2 ON is2.building::text = b.external_id
JOIN report.inquiry i ON is2.inquiry = i.id
WHERE i.document_date >= b.built_year::date - interval '5 years'
ORDER BY bc.cluster_id,
    CASE i.type
        WHEN 'foundation_research' THEN 0
        WHEN 'inspectionpit' THEN 1
        WHEN 'second_opinion' THEN 2
        WHEN 'note' THEN 3
        WHEN 'additional_research' THEN 4
        WHEN 'demolition_research' THEN 5
        WHEN 'architectural_research' THEN 6
        WHEN 'archieve_research' THEN 7
        WHEN 'quickscan' THEN 8
        ELSE 100
    END,
    i.document_date DESC
WITH NO DATA;

CREATE UNIQUE INDEX ON data.cluster_sample_v2 (cluster_id);

---

CREATE MATERIALIZED VIEW data.supercluster_sample_v2 AS
SELECT DISTINCT ON (s.supercluster_id)
    s.supercluster_id,
    is2.foundation_type,
    is2.enforcement_term,
    is2.damage_cause,
    is2.overall_quality,
    is2.recovery_advised,
    date_part('year', is2.built_year::date)::integer AS built_year,
    is2.groundwater_level_temp AS groundwater_level,
    is2.wood_level,
    is2.foundation_depth,
    i.type AS inquiry_type,
    i.document_date,
    i.id
FROM data.supercluster s
JOIN data.building_cluster bc ON bc.cluster_id = s.cluster_id
JOIN geocoder.building b ON b.external_id = bc.building_id
JOIN report.inquiry_sample is2 ON is2.building::text = b.external_id
JOIN report.inquiry i ON is2.inquiry = i.id
WHERE i.document_date >= b.built_year::date - interval '5 years'
ORDER BY s.supercluster_id,
    CASE i.type
        WHEN 'foundation_research' THEN 0
        WHEN 'inspectionpit' THEN 1
        WHEN 'second_opinion' THEN 2
        WHEN 'note' THEN 3
        WHEN 'additional_research' THEN 4
        WHEN 'demolition_research' THEN 5
        WHEN 'architectural_research' THEN 6
        WHEN 'archieve_research' THEN 7
        WHEN 'quickscan' THEN 8
        ELSE 100
    END,
    i.document_date DESC
WITH NO DATA;

CREATE UNIQUE INDEX ON data.supercluster_sample_v2 (supercluster_id);

--------------------------------------------------------------------------------
-- Step 2: Refresh v2 matviews (run manually)
--------------------------------------------------------------------------------
-- REFRESH MATERIALIZED VIEW data.building_sample_v2;
-- REFRESH MATERIALIZED VIEW data.cluster_sample_v2;
-- REFRESH MATERIALIZED VIEW data.supercluster_sample_v2;

--------------------------------------------------------------------------------
-- Step 3: Validate — compare v2 vs current (run manually)
--------------------------------------------------------------------------------
-- Differences are expected only where array_agg ordering was nondeterministic.
--
-- SELECT count(*) FROM data.building_sample bs
-- FULL OUTER JOIN data.building_sample_v2 bs2 ON bs.building_id = bs2.building_id
-- WHERE bs.foundation_type IS DISTINCT FROM bs2.foundation_type
--    OR bs.enforcement_term IS DISTINCT FROM bs2.enforcement_term;

--------------------------------------------------------------------------------
-- Step 4: Rename-swap in a transaction (run manually after validation)
--------------------------------------------------------------------------------
-- BEGIN;
-- ALTER MATERIALIZED VIEW data.building_sample RENAME TO building_sample_old;
-- ALTER MATERIALIZED VIEW data.building_sample_v2 RENAME TO building_sample;
-- ALTER MATERIALIZED VIEW data.cluster_sample RENAME TO cluster_sample_old;
-- ALTER MATERIALIZED VIEW data.cluster_sample_v2 RENAME TO cluster_sample;
-- ALTER MATERIALIZED VIEW data.supercluster_sample RENAME TO supercluster_sample_old;
-- ALTER MATERIALIZED VIEW data.supercluster_sample_v2 RENAME TO supercluster_sample;
-- COMMIT;
--
-- After confirming everything works:
-- DROP MATERIALIZED VIEW data.building_sample_old;
-- DROP MATERIALIZED VIEW data.cluster_sample_old;
-- DROP MATERIALIZED VIEW data.supercluster_sample_old;
