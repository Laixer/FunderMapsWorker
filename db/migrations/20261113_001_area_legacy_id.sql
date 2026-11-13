-- gfm retirement (Worker #158, step 3, part 1): the four area tables keep their present id in a column of its own.
--
-- Step 3 puts the CBS code in the id of geocoder.state / municipality / district / neighborhood (the next three
-- migrations). What is derived from them (data.building_precomputed, the model snapshots, the nine
-- data.statistics_product_* views) keeps the old id until the next model refresh has rebuilt it. In that gap a reader
-- holding an old id must still find its area: legacy_id is the way back. It is also the way to undo the rekey, and the
-- record of which id became which code. It goes when step 4b tidies up.
--
-- Prod 2026-11-13 (read-only): 12 / 355 / 3,246 / 13,688 rows; every id is a gfm- value and none equals its
-- external_id; external_id is NOT NULL and unique on all four tables.
--
-- This file only adds the four columns: ADD COLUMN without a default is a catalog change, so its exclusive lock on the
-- area tables is held for an instant. The fill is the next migration, on purpose: in one transaction with the fill and
-- the indexes the lock was held for 6 seconds in the rehearsal (2026-11-13), and every reader of the area tables waited.

SET LOCAL lock_timeout = '2s';

ALTER TABLE geocoder.state ADD COLUMN legacy_id text;
ALTER TABLE geocoder.municipality ADD COLUMN legacy_id text;
ALTER TABLE geocoder.district ADD COLUMN legacy_id text;
ALTER TABLE geocoder.neighborhood ADD COLUMN legacy_id text;

COMMENT ON COLUMN geocoder.state.legacy_id IS 'The id this province had before its CBS code became the id (Worker #158). For readers of data not yet rebuilt, and to undo. Goes in step 4b.';
COMMENT ON COLUMN geocoder.municipality.legacy_id IS 'The id this municipality had before its CBS code became the id (Worker #158). For readers of data not yet rebuilt, and to undo. Goes in step 4b.';
COMMENT ON COLUMN geocoder.district.legacy_id IS 'The id this district had before its CBS code became the id (Worker #158). For readers of data not yet rebuilt, and to undo. Goes in step 4b.';
COMMENT ON COLUMN geocoder.neighborhood.legacy_id IS 'The id this neighbourhood had before its CBS code became the id (Worker #158). For readers of data not yet rebuilt, and to undo. Goes in step 4b.';
