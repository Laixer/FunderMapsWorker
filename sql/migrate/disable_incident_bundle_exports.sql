-- Stop the nightly GPKG export of the four incident bundles (2026-08-07).
--
-- Follows sql/migrate/retire_tippecanoe_tilesets.sql, which turned off tile
-- generation but deliberately left enabled/upload_dataset on so the exports to
-- s3://fundermaps-data/mapset/ kept feeding the static-model history. For the
-- incident layers that history has nothing left to record:
--
--   * report.incident is FROZEN — 2,756 rows, newest create_date 2026-03-03
--     (157 days before this migration). Intake moved off our infra when the
--     KCAF loket and municipal portals were retired, so every nightly export
--     since March has been a byte-identical copy of the previous one.
--   * incident_{district,municipality,neighborhood} are pure aggregations of
--     report.incident ⋈ geocoder areas. They are fully reconstructable from the
--     incident export, and doubly so from report.incident itself.
--   * ~700 daily snapshots are already archived under mapset/, covering the
--     entire period in which incidents were actually being filed.
--
-- Setting enabled=false makes processOne take the both-flags-off early return
-- (#53) and skip the bundle entirely — no ogr2ogr dump, no queue job, no log
-- line. The layers themselves are unaffected: they are served dynamically by
-- Martin from maplayer.incident*(z,x,y), which read the *_tiles tables
-- rebuilt nightly by f/fundermaps/data/refresh_layer_tiles (flow step v).
--
-- NOT included: facade_scan. Its bundle stays enabled on purpose —
--   * it is LIVE data (new QuickScan samples arrived in Aug 2026), unlike
--     incidents;
--   * none of its attributes (skewed_*_facade, facade_type, settlement_speed,
--     facade_scan_risk, risk, priority) exist in analysis_full, so the export
--     is the only archived record of them;
--   * the planned delete-and-reimport of all 5,200+ QuickScan records would
--     otherwise destroy every trace of the pre-reimport state.
-- analysis_full likewise stays enabled — it IS the static model history.
--
-- Rollback: set enabled = true for these four. Harmless at any time; if
-- incident intake ever resumes, re-enable so the archive picks it up again.

UPDATE maplayer.bundle
   SET enabled = false
 WHERE tileset IN (
    'incident',
    'incident_district',
    'incident_municipality',
    'incident_neighborhood'
 );

-- Guard: the two bundles that must keep exporting are untouched.
DO $$
DECLARE
    broken integer;
BEGIN
    SELECT count(*) INTO broken
      FROM maplayer.bundle
     WHERE tileset IN ('analysis_full', 'facade_scan')
       AND (NOT enabled OR NOT upload_dataset);
    IF broken > 0 THEN
        RAISE EXCEPTION
            'refusing: analysis_full/facade_scan lost enabled or upload_dataset';
    END IF;
END $$;
