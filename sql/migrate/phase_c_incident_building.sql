-- Phase C: rename report.incident.building to building_id.
-- Wire format preserved by app-layer aliases (Drizzle name arg).
-- Coordinated deploy required: WebApi must be on the new build before this runs.
-- Run as: fundermaps (owner)
--
-- Pre-flight verified (2026-04-25):
-- - 6 dependent views/matviews reference incident.building directly:
--     data.statistics_product_incident_municipality (matview)
--     data.statistics_product_incidents (matview)
--     maplayer.incident, maplayer.incident_district, maplayer.incident_municipality,
--     maplayer.incident_neighborhood (views)
--   PostgreSQL transparently rewrites view/matview definitions on column rename
--   (column refs are stored by attnum). No explicit recreate needed; existing
--   matview rows keep their values, next refresh uses the rewritten definition.
-- - No DB functions reference the column.
-- - Row count: 2756 — rename is metadata-only and instant.

BEGIN;

ALTER TABLE report.incident RENAME COLUMN building TO building_id;

ALTER TABLE report.incident RENAME CONSTRAINT incident_building_fkey TO incident_building_id_fkey;

ALTER INDEX report.incident_building_idx RENAME TO incident_building_id_idx;

COMMIT;
