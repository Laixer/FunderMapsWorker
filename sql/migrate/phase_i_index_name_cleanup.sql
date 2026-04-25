-- Phase I: clean up two stray index names that survived earlier sweeps.
--
--   geocoder.residence.residence_building_idx  →  residence_building_id_idx
--     Index dates back to before the column name was building_id; the
--     column itself was renamed long ago but the index kept the old
--     "building" naming.
--
--   data.building_sample.building_sample_v2_building_id_idx  →  building_sample_building_id_idx
--     Stray "v2" suffix from a previous matview reshape.
--
-- ALTER INDEX RENAME is metadata-only and transparent to applications.
-- Run as: fundermaps (owner)

BEGIN;

ALTER INDEX geocoder.residence_building_idx
    RENAME TO residence_building_id_idx;

ALTER INDEX data.building_sample_v2_building_id_idx
    RENAME TO building_sample_building_id_idx;

COMMIT;
