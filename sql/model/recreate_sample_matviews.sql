-- Issue #979: Add facade_scan_risk to data.building_sample
--
-- facade_scan_risk on report.inquiry_sample is a report-provided field that,
-- when present on the building-level (established) inquiry, overrides modelled
-- drystand / dewatering / bio_infection risks (and their reliability tier) in
-- data.model_risk_dynamic_all — regardless of inquiry_type. Surfacing the
-- column on data.building_sample exposes it to the dynamic view's
-- `established.facade_scan_risk` reference.
--
-- Building-level only. cluster_sample and supercluster_sample are intentionally
-- NOT touched: facade_scan_risk must NOT propagate across clustering, since a
-- façade observation is specific to one building and not transferable.
--
-- Strategy: create v3 → REFRESH → validate → rename-swap in transaction.

--------------------------------------------------------------------------------
-- Step 1: Create v3 matview (adds facade_scan_risk column)
--------------------------------------------------------------------------------

CREATE MATERIALIZED VIEW data.building_sample_v3 AS
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
    is2.facade_scan_risk,
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
WITH NO DATA;

CREATE UNIQUE INDEX ON data.building_sample_v3 (building_id);

--------------------------------------------------------------------------------
-- Step 2: Refresh v3 (run manually)
--------------------------------------------------------------------------------
-- REFRESH MATERIALIZED VIEW data.building_sample_v3;

--------------------------------------------------------------------------------
-- Step 3: Validate — facade_scan_risk should populate where inquiry samples
-- have it set. Pre-swap, the production view has no such column.
--------------------------------------------------------------------------------
-- SELECT count(*) FILTER (WHERE facade_scan_risk IS NOT NULL) AS with_facade_risk,
--        count(*)                                              AS total
--   FROM data.building_sample_v3;

--------------------------------------------------------------------------------
-- Step 4: Rename-swap in a transaction (run manually after validation)
--------------------------------------------------------------------------------
-- BEGIN;
-- ALTER MATERIALIZED VIEW data.building_sample RENAME TO building_sample_v2_old;
-- ALTER MATERIALIZED VIEW data.building_sample_v3 RENAME TO building_sample;
-- COMMIT;
--
-- Re-grant after the swap (DROP/RENAME does not re-emit grants for the new name
-- in older PG versions; verify with \dp data.building_sample post-swap):
-- GRANT SELECT ON data.building_sample TO fundermaps_webapp;
-- GRANT SELECT ON data.building_sample TO fundermaps_webservice;
--
-- After confirming downstream views (model_risk_dynamic_all, model_risk_static
-- refresh, analysis_* views, statistics matviews) work end-to-end:
-- DROP MATERIALIZED VIEW data.building_sample_v2_old;
