-- Migration: product_tracker building_id from GFM → BAG
--
-- Converts product_tracker.building_id from GFM format (gfm-{hex})
-- to BAG format (NL.IMBAG.PAND.{numeric}) by looking up geocoder.building.external_id.
--
-- Pre-checks confirmed:
--   - All 19.2M rows are GFM format
--   - Zero orphaned building_ids
--   - No functions, views, or matviews depend on this table
--   - Only FK constraint needs updating
--
-- Run during low-traffic window. Estimated time: 10-30 min depending on I/O.

BEGIN;

-- Step 1: Drop the FK on the parent (cascades to all partitions)
ALTER TABLE application.product_tracker
    DROP CONSTRAINT product_tracker_building_id_fkey;

-- Step 2: Update building_id per partition (smallest first)
-- 2021: 87K rows
UPDATE application.product_tracker_2021 pt
SET building_id = b.external_id
FROM geocoder.building b
WHERE pt.building_id = b.id;

-- 2022: 510K rows
UPDATE application.product_tracker_2022 pt
SET building_id = b.external_id
FROM geocoder.building b
WHERE pt.building_id = b.id;

-- 2023: 880K rows
UPDATE application.product_tracker_2023 pt
SET building_id = b.external_id
FROM geocoder.building b
WHERE pt.building_id = b.id;

-- 2024: 1.4M rows
UPDATE application.product_tracker_2024 pt
SET building_id = b.external_id
FROM geocoder.building b
WHERE pt.building_id = b.id;

-- 2026: 4.7M rows
UPDATE application.product_tracker_2026 pt
SET building_id = b.external_id
FROM geocoder.building b
WHERE pt.building_id = b.id;

-- 2025: 11.6M rows (largest, do last)
UPDATE application.product_tracker_2025 pt
SET building_id = b.external_id
FROM geocoder.building b
WHERE pt.building_id = b.id;

-- 2027 & 2028: empty but update for correctness
UPDATE application.product_tracker_2027 pt
SET building_id = b.external_id
FROM geocoder.building b
WHERE pt.building_id = b.id;

UPDATE application.product_tracker_2028 pt
SET building_id = b.external_id
FROM geocoder.building b
WHERE pt.building_id = b.id;

-- Step 3: Verify no GFM IDs remain
DO $$
DECLARE
    gfm_count bigint;
BEGIN
    SELECT count(*) INTO gfm_count
    FROM application.product_tracker
    WHERE building_id LIKE 'gfm-%';

    IF gfm_count > 0 THEN
        RAISE EXCEPTION 'Migration incomplete: % rows still have GFM IDs', gfm_count;
    END IF;
END $$;

-- Step 4: Recreate FK pointing to external_id (BAG)
ALTER TABLE application.product_tracker
    ADD CONSTRAINT product_tracker_building_id_fkey
    FOREIGN KEY (building_id) REFERENCES geocoder.building(external_id) ON UPDATE CASCADE;

COMMIT;
