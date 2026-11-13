-- gfm retirement (Worker #158, step 3, part 2a): the foreign keys of the area chain come off for the rekey.
--
-- The three are ON UPDATE CASCADE. Left in place, changing 13,688 neighbourhood ids would fire 13,688 cascaded updates
-- into 12.8M building rows, and the one-pass update of geocoder.building in the next migration would queue 12.8M
-- foreign-key checks in memory. They come back exactly as they were in the migration after the rekey.
-- (geocoder.municipality.state_id has no foreign key on prod, 2026-11-13; the geolock tables reference external_id,
-- which does not change.)
--
-- In a transaction of its own on purpose: DROP CONSTRAINT takes an exclusive lock on geocoder.building. Here it is held
-- for an instant. Inside the rekey it would be held for as long as the rekey runs and stop every reader of the table.
-- Apply this migration, the rekey and the restore in one run, with no BAG load going.

SET LOCAL lock_timeout = '2s';

ALTER TABLE geocoder.building DROP CONSTRAINT building_neighborhood_id_fkey;
ALTER TABLE geocoder.neighborhood DROP CONSTRAINT neighborhood_district_id_fkey;
ALTER TABLE geocoder.district DROP CONSTRAINT district_municipality_id_fkey;
