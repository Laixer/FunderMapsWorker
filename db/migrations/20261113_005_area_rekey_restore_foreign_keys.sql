-- gfm retirement (Worker #158, step 3, part 2c): the foreign keys of the area chain are back, as they were, and a new
-- area row no longer gets a gfm- id by default.
--
-- ADD FOREIGN KEY checks every row once (12.8M buildings against 13,688 neighbourhoods) under a lock that lets readers
-- through and holds writers; nothing writes these tables but the BAG load, which is not running.
-- The defaults go last, so their exclusive lock on the four small tables is held for an instant. geocoder.generate_id()
-- itself stays until step 4b (geocoder.residence.id still uses it).

SET LOCAL lock_timeout = '2s';

ALTER TABLE geocoder.district ADD CONSTRAINT district_municipality_id_fkey
  FOREIGN KEY (municipality_id) REFERENCES geocoder.municipality(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE geocoder.neighborhood ADD CONSTRAINT neighborhood_district_id_fkey
  FOREIGN KEY (district_id) REFERENCES geocoder.district(id) ON UPDATE CASCADE ON DELETE CASCADE;
ALTER TABLE geocoder.building ADD CONSTRAINT building_neighborhood_id_fkey
  FOREIGN KEY (neighborhood_id) REFERENCES geocoder.neighborhood(id) ON UPDATE CASCADE ON DELETE SET NULL;

ALTER TABLE geocoder.neighborhood ALTER COLUMN id DROP DEFAULT;
ALTER TABLE geocoder.district ALTER COLUMN id DROP DEFAULT;
ALTER TABLE geocoder.municipality ALTER COLUMN id DROP DEFAULT;
ALTER TABLE geocoder.state ALTER COLUMN id DROP DEFAULT;
