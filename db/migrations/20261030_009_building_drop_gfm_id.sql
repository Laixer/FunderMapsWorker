-- gfm retirement (Worker #158, step 4b in part): geocoder.building loses its gfm- `id`; the BAG pand id is the
-- primary key (Yorick 2026-10-30: "Go ahead with 1").
--
-- Prod 2026-10-30 (read-only): nothing references building.id. All 14 foreign keys onto geocoder.building point at
-- external_id (the BAG pand id: NOT NULL, unique through building_external_id_idx). No function body uses it, no
-- API, Webservice or Windmill query names it, and the BAG load (sql/load/load_building.sql) never writes it: it
-- upserts ON CONFLICT (external_id) and left id to its default. pg_depend lists the primary key, the NOT NULL, the
-- default (geocoder.generate_id()) and one view, geocoder.building_active, which selects it. Nothing reads
-- building_active.id (no column-level dependent, no code), but a view column cannot be dropped without recreating
-- the view and everything built on it, so building_active.id now repeats external_id, same type: no gfm value is
-- left in it. The view itself is due to go with the rest of step 4b.
--
-- Like 20260918_007 for address: external_id becomes the primary key by promoting its unique index (no rebuild,
-- no rescan, the index keeps its oid and the 14 foreign keys stay attached), then the column goes. DROP COLUMN is a
-- catalog change; the 12.8M rows are not rewritten. The old id -> external_id pairs were saved before this ran.
-- geocoder.generate_id() and the geocoder_id domain stay: the CBS hierarchy still uses them (step 3).

SET LOCAL lock_timeout = '2s';

CREATE OR REPLACE VIEW geocoder.building_active AS
 SELECT external_id::geocoder.geocoder_id AS id,
    built_year,
    geom,
    external_id,
    building_type,
    neighborhood_id
   FROM geocoder.building
  WHERE active = true AND geom IS NOT NULL;

ALTER TABLE geocoder.building DROP CONSTRAINT building_pkey;
ALTER TABLE geocoder.building ADD CONSTRAINT building_pkey PRIMARY KEY USING INDEX building_external_id_idx;
ALTER TABLE geocoder.building DROP COLUMN id;
