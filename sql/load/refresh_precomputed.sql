-- BAG import, last step (after cleanup_bag): refresh the precomputed building
-- facts the risk model reads.
--
-- data.building_precomputed holds address_count, surface_area,
-- construction_year_bag, height and ground_level per active house. It is a
-- plain table filled by data.refresh_building_precomputed()
-- (sql/model/create_building_precomputed.sql), and nothing else calls that
-- procedure: the twice-daily model refresh reads the table as is. Skipping
-- this step after an import freezes the model on the previous BAG state, and
-- because data.building_geo_hierarchy keeps only address_count > 0, every
-- building whose addresses arrived in the import stays off the map.
--
-- That is what happened after the 2026-08-09 and 2026-09-01 imports: 47,517
-- houses with addresses sat at address_count = 0 and 117,260 active houses
-- had no row at all, until a manual refill on 2026-09-16 (API #136).
--
-- TRUNCATE + INSERT of ~11.3M rows, ~7 minutes. Run it outside the 12:30 and
-- 21:00 CEST refresh windows, like the import itself.
CALL data.refresh_building_precomputed();

-- Post-check: every active house has a row, and no address count is stale.
-- Both numbers must be 0; a non-zero value means the refill did not cover the
-- import and the next model refresh will be wrong.
SELECT 'houses_without_precomputed_row' AS check, count(*) AS n
FROM geocoder.building_active ba
WHERE ba.building_type = 'house'
  AND NOT EXISTS (SELECT 1 FROM data.building_precomputed bp WHERE bp.building_id = ba.external_id)
UNION ALL
SELECT 'stale_address_count', count(*)
FROM data.building_precomputed bp
LEFT JOIN (SELECT building_id, count(*) AS c FROM geocoder.address GROUP BY building_id) a
       ON a.building_id = bp.building_id
WHERE coalesce(a.c, 0) <> bp.address_count;
