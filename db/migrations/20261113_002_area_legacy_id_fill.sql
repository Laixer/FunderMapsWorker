-- gfm retirement (Worker #158, step 3, part 1b): legacy_id takes the present id of every area row, and gets its index.
--
-- Row locks and index builds only: readers of the four area tables are not held up (the columns came in the migration
-- before this one, in a transaction of its own). 17,301 small rows. Until the rekey legacy_id simply repeats id, so
-- this can be applied well ahead of it.

UPDATE geocoder.state SET legacy_id = id;
UPDATE geocoder.municipality SET legacy_id = id;
UPDATE geocoder.district SET legacy_id = id;
UPDATE geocoder.neighborhood SET legacy_id = id;

CREATE UNIQUE INDEX state_legacy_id_idx ON geocoder.state (legacy_id);
CREATE UNIQUE INDEX municipality_legacy_id_idx ON geocoder.municipality (legacy_id);
CREATE UNIQUE INDEX district_legacy_id_idx ON geocoder.district (legacy_id);
CREATE UNIQUE INDEX neighborhood_legacy_id_idx ON geocoder.neighborhood (legacy_id);
