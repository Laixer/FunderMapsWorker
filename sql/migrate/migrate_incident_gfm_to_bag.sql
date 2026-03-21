-- Migration: report.incident.building from GFM to BAG IDs
-- Part of GFM→BAG migration step 1 (incident table, 2,756 rows)
--
-- Prerequisites:
--   - building_external_id_idx (unique) exists on geocoder.building(external_id)
--   - Zero orphan incidents (all have matching building with external_id)
--
-- Run as: fundermaps role (owner)

BEGIN;

-- 1. Drop old FK first (points to building.id = GFM, blocks UPDATE)
ALTER TABLE report.incident
    DROP CONSTRAINT incident_building_fkey;

-- 2. Convert incident.building from GFM to BAG
UPDATE report.incident i
SET building = b.external_id
FROM geocoder.building b
WHERE i.building = b.id;

-- 3. Create new FK (points to building.external_id = BAG)
ALTER TABLE report.incident
    ADD CONSTRAINT incident_building_fkey
    FOREIGN KEY (building) REFERENCES geocoder.building(external_id)
    ON UPDATE CASCADE ON DELETE RESTRICT;

-- 4. Recreate maplayer views with updated join
--    Old: ba.id = i.building  →  New: ba.external_id = i.building

CREATE OR REPLACE VIEW maplayer.incident AS
SELECT i.id,
    i.foundation_damage_cause,
    round((GREATEST(bh.height, (0)::real))::numeric, 2) AS height,
    ba.geom
FROM report.incident i
JOIN geocoder.building_active ba ON ba.external_id = i.building
JOIN data.building_height bh ON bh.building_id = ba.external_id;

CREATE OR REPLACE VIEW maplayer.incident_neighborhood AS
SELECT n.geom,
    count(n.id) AS incident_count
FROM report.incident i
JOIN geocoder.building_active ba ON ba.external_id = i.building
JOIN geocoder.neighborhood n ON n.id = ba.neighborhood_id
GROUP BY n.id, n.geom;

CREATE OR REPLACE VIEW maplayer.incident_district AS
SELECT d.geom,
    count(d.id) AS incident_count
FROM report.incident i
JOIN geocoder.building_active ba ON ba.external_id = i.building
JOIN geocoder.neighborhood n ON n.id = ba.neighborhood_id
JOIN geocoder.district d ON d.id = n.district_id
GROUP BY d.id, d.geom;

CREATE OR REPLACE VIEW maplayer.incident_municipality AS
SELECT m.geom,
    count(m.id) AS incident_count
FROM report.incident i
JOIN geocoder.building_active ba ON ba.external_id = i.building
JOIN geocoder.neighborhood n ON n.id = ba.neighborhood_id
JOIN geocoder.district d ON d.id = n.district_id
JOIN geocoder.municipality m ON m.id = d.municipality_id
GROUP BY m.id, m.geom;

-- 5. Recreate matviews with updated join
--    These must be dropped and recreated (CREATE OR REPLACE not supported for matviews)

DROP MATERIALIZED VIEW IF EXISTS data.statistics_product_incidents;
CREATE MATERIALIZED VIEW data.statistics_product_incidents AS
SELECT ba.neighborhood_id,
    year.year,
    count(i.id) AS count
FROM report.incident i
JOIN geocoder.building_active ba ON ba.external_id = i.building,
    LATERAL CAST((date_part('year'::text, i.create_date))::integer AS integer) year(year)
GROUP BY ba.neighborhood_id, year.year;

DROP MATERIALIZED VIEW IF EXISTS data.statistics_product_incident_municipality;
CREATE MATERIALIZED VIEW data.statistics_product_incident_municipality AS
SELECT m.id AS municipality_id,
    year.year,
    count(i.id) AS count
FROM report.incident i
JOIN geocoder.building b ON b.external_id = i.building
JOIN geocoder.neighborhood n ON n.id = b.neighborhood_id
JOIN geocoder.district d ON d.id = n.district_id
JOIN geocoder.municipality m ON m.id = d.municipality_id,
    LATERAL CAST((date_part('year'::text, i.create_date))::integer AS integer) year(year)
GROUP BY m.id, year.year;

-- 6. Recreate unique indexes on matviews (for CONCURRENTLY refresh)
CREATE UNIQUE INDEX statistics_product_incidents_neighborhood_year_idx
    ON data.statistics_product_incidents (neighborhood_id, year);
CREATE UNIQUE INDEX statistics_product_incident_municipality_municipality_year_idx
    ON data.statistics_product_incident_municipality (municipality_id, year);

-- 7. Drop dead function (owned by doadmin, must run as doadmin separately)
-- DROP FUNCTION IF EXISTS public.get_all_incidents();

-- 8. Verify
DO $$
DECLARE
    gfm_count integer;
BEGIN
    SELECT count(*) INTO gfm_count
    FROM report.incident
    WHERE building LIKE 'gfm-%';

    IF gfm_count > 0 THEN
        RAISE EXCEPTION 'Migration failed: % rows still have GFM IDs', gfm_count;
    END IF;

    RAISE NOTICE 'Migration verified: 0 GFM IDs remaining in report.incident';
END $$;

COMMIT;
