-- Issue #979 follow-up: source facade_scan_risk independently of inquiry priority
--
-- v3 (shipped 2026-05-05) added facade_scan_risk as a column pulled from the
-- same DISTINCT ON row used for the rest of the sample. That row is picked by
-- inquiry-type priority (foundation_research=0, …, quickscan=8, ELSE=100).
-- facade_scan inquiries fall into ELSE=100, so any other inquiry type for the
-- same building wins, and facade_scan_risk drops to NULL even when a
-- facade_scan inquiry with a value exists. Override never fires.
--
-- v4 fix: keep the existing inquiry-priority DISTINCT ON for the report fields,
-- but source facade_scan_risk from a separate per-building lookup that picks
-- the most recent inquiry whose facade_scan_risk IS NOT NULL — regardless of
-- inquiry_type (15 rows have the value set on non-facade_scan types and the
-- spec says "regardless of inquiry_type").
--
-- Building-level only. cluster_sample and supercluster_sample remain untouched.
--
-- Strategy: create v4 → REFRESH → validate → rename-swap in transaction.

--------------------------------------------------------------------------------
-- Step 1: Create v4 matview (facade_scan_risk via independent CTE)
--------------------------------------------------------------------------------

CREATE MATERIALIZED VIEW data.building_sample_v4 AS
WITH ranked AS (
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
    JOIN report.inquiry i ON is2.inquiry_id = i.id
    JOIN geocoder.building b ON b.external_id = is2.building_id::text
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
            WHEN 'archive_research' THEN 7
            WHEN 'quickscan' THEN 8
            ELSE 100
        END,
        i.document_date DESC
),
facade AS (
    SELECT DISTINCT ON (is2.building_id::text)
        is2.building_id::text AS building_id,
        is2.facade_scan_risk
    FROM report.inquiry_sample is2
    JOIN report.inquiry i ON i.id = is2.inquiry_id
    WHERE is2.facade_scan_risk IS NOT NULL
    ORDER BY is2.building_id::text, i.document_date DESC
)
SELECT r.building_id,
       r.foundation_type,
       r.enforcement_term,
       r.damage_cause,
       r.overall_quality,
       r.recovery_advised,
       r.built_year,
       r.groundwater_level,
       r.wood_level,
       r.foundation_depth,
       f.facade_scan_risk,
       r.inquiry_type,
       r.document_date,
       r.id
FROM ranked r
LEFT JOIN facade f ON f.building_id = r.building_id
WITH NO DATA;

CREATE UNIQUE INDEX ON data.building_sample_v4 (building_id);

--------------------------------------------------------------------------------
-- Step 2: Refresh v4 (run manually, ~18 min)
--------------------------------------------------------------------------------
-- REFRESH MATERIALIZED VIEW data.building_sample_v4;

--------------------------------------------------------------------------------
-- Step 3: Validate — facade_scan_risk should populate even when a non-
-- facade_scan inquiry wins the inquiry-priority DISTINCT ON.
--------------------------------------------------------------------------------
-- SELECT count(*) FILTER (WHERE facade_scan_risk IS NOT NULL) AS with_facade_risk,
--        count(*)                                              AS total
--   FROM data.building_sample_v4;
--
-- Spot-check the buildings that exposed the v3 bug:
-- SELECT building_id, inquiry_type, facade_scan_risk
--   FROM data.building_sample_v4
--  WHERE building_id IN ('NL.IMBAG.PAND.0363100012166480',
--                        'NL.IMBAG.PAND.0392100000066646',
--                        'NL.IMBAG.PAND.0344100000065540');

--------------------------------------------------------------------------------
-- Step 4: Rename-swap in a transaction (run manually after validation)
--------------------------------------------------------------------------------
-- BEGIN;
-- ALTER MATERIALIZED VIEW data.building_sample RENAME TO building_sample_v3_old;
-- ALTER INDEX data.building_sample_building_id_idx
--     RENAME TO building_sample_v3_old_building_id_idx;
-- ALTER MATERIALIZED VIEW data.building_sample_v4 RENAME TO building_sample;
-- ALTER INDEX data.building_sample_v4_building_id_idx
--     RENAME TO building_sample_building_id_idx;
-- COMMIT;
--
-- Re-grant after the swap (verify with \dp data.building_sample):
-- GRANT SELECT ON data.building_sample TO fundermaps_webapp;
-- GRANT SELECT ON data.building_sample TO fundermaps_webservice;
--
-- After confirming downstream views (model_risk_dynamic_all, model_risk_static
-- refresh, analysis_* views, statistics matviews) work end-to-end:
-- DROP MATERIALIZED VIEW data.building_sample_v3_old;
