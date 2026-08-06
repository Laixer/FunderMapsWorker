-- Retire the last tippecanoe tile builds (2026-08-06).
--
-- facade_scan and the four incident tilesets are now served dynamically by
-- the Martin tileserver from maplayer function sources — see
-- sql/model/create_facade_scan_tiles.sql and create_incident_tiles.sql.
-- WebFront #290 and FunderMapsReport #65 point at tiles.fundermaps.com.
--
-- Measured cost of the builds this removes (flow job 019fcdee, 2026-08-05):
--   incident_district      26.5 min   155,335 Spaces objects   1,016 features
--   incident_neighborhood  11.5 min    67,346 objects          1,530 features
--   incident                2.0 min     7,373 objects          2,728 features
--   facade_scan             1.0 min     1,090 objects          3,202 features
--   incident_municipality   0.5 min       497 objects            298 features
-- ~40 of the ~50 min process_mapset spent nightly; the whole flow should drop
-- from ~101 min to ~60 min.
--
-- ONLY generate_tileset flips. enabled and upload_dataset MUST stay true:
--   - enabled=false makes processOne skip the bundle entirely (the both-flags-
--     off early return added in #53), which would also kill the GPKG export.
--   - upload_dataset drives the nightly export to s3://fundermaps-data/mapset/,
--     the permanent history of the static model. Do not turn it off.
-- After this, no bundle generates tiles; process_mapset is a pure GPKG
-- exporter and tippecanoe is unused by the nightly flow.
--
-- Rollback: set generate_tileset = true for these five and revert the two
-- frontend PRs. The static tiles are still in fundermaps-tileset (stale from
-- whenever the purge happens) until they are deleted.

UPDATE maplayer.bundle
   SET generate_tileset = false
 WHERE tileset IN (
    'facade_scan',
    'incident',
    'incident_district',
    'incident_municipality',
    'incident_neighborhood'
 );

-- Guard: this migration must not have disabled a bundle or stopped an export.
DO $$
DECLARE
    broken integer;
BEGIN
    SELECT count(*) INTO broken
      FROM maplayer.bundle
     WHERE NOT enabled OR NOT upload_dataset;
    IF broken > 0 THEN
        RAISE EXCEPTION
            'refusing: % bundle row(s) lost enabled or upload_dataset', broken;
    END IF;
END $$;
