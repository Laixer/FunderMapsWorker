-- One-shot: drop three dead objects (applied to prod 2026-07-22).
--
-- geocoder.country: single row (Nederland), never read. geocoder.state kept
-- its country_id COLUMN — the /api/geocoder state response returns it and the
-- value is just an opaque id to consumers — but the FK and the table go.
--   Row snapshot: {"id":"gfm-b45ab4bd3c0145a7aa5d43c9ccb9b03f",
--                  "external_id":"6030","name":"Nederland",
--                  "geom": MultiPolygon (rebuildable from CBS)}
--
-- public.model_supply: zero rows, zero references outside schema.sql.
--
-- maplayer.building_supercluster: tile-source view; bundle row disabled since
-- long, no frontend layer config, and #1005 removed the supercluster tier from
-- risk inheritance. The stale Spaces prefix
-- fundermaps-tileset/building_supercluster/ (261 MB) is deleted alongside.
-- (data.supercluster — the model input table — is alive and untouched.)

ALTER TABLE geocoder.state DROP CONSTRAINT IF EXISTS state_country_id_fkey;

DROP TABLE IF EXISTS geocoder.country;

DROP TABLE IF EXISTS public.model_supply;

DROP VIEW IF EXISTS maplayer.building_supercluster;
