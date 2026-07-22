-- One-shot: drop geocoder.postal_code (applied to prod 2026-07-22).
--
-- 463,500 PC6 polygons (postal_code varchar(6), geom MultiPolygon 4326),
-- 1.5 GB. Loaded once, never read: zero scans over the stats window, zero
-- view dependents, zero FKs, and no code references in any repo (the many
-- "postal_code" hits elsewhere are the geocoder.address COLUMN, which stays).
-- The former statistics_postal_code_* matviews aggregated by that address
-- column too, not this table.
--
-- Rebuildable from public CBS/PDOK postal-code geometry if a postal-code
-- product ever needs polygons.

DROP TABLE IF EXISTS geocoder.postal_code;
