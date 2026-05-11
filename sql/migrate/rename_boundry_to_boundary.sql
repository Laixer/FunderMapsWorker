-- Fix the long-standing "boundry" misspelling on the three administrative-
-- boundary tile views in maplayer + the matching rows in maplayer.bundle.
--
-- The three views (boundry_district, boundry_municipality, boundry_neighborhood)
-- are dirt-simple `SELECT geom FROM geocoder.<tbl>` pass-throughs consumed by
-- the worker's tile-generation pipeline. The maplayer.bundle catalog drives
-- which views the worker materializes into S3-hosted vector tiles; renaming
-- the bundle row's `tileset` PK is what changes the S3 object key on the
-- next process-mapset run.
--
-- Cross-stack coordination:
--   FunderMapsWebFront's src/config/layers/boundry-*.json layer configs and
--   the useAdministrativeBoundries.ts + useMapSources.ts composables also
--   carry the typo. Ship that PR after this migration applies and after
--   process-mapset has produced boundary_*.mbtiles on S3 — otherwise the
--   WebFront map will request tiles whose key does not yet exist.
--
--   Old boundry_*.mbtiles objects on S3 are left as orphans; cleanup-storage
--   prunes them naturally.

BEGIN;

ALTER VIEW maplayer.boundry_district     RENAME TO boundary_district;
ALTER VIEW maplayer.boundry_municipality RENAME TO boundary_municipality;
ALTER VIEW maplayer.boundry_neighborhood RENAME TO boundary_neighborhood;

UPDATE maplayer.bundle SET tileset = 'boundary_district'     WHERE tileset = 'boundry_district';
UPDATE maplayer.bundle SET tileset = 'boundary_municipality' WHERE tileset = 'boundry_municipality';
UPDATE maplayer.bundle SET tileset = 'boundary_neighborhood' WHERE tileset = 'boundry_neighborhood';

COMMIT;
