-- gfm retirement, step 4a (Worker #158): the last database object that reads
-- geocoder.address.id stops doing so, so that the column can be dropped
-- (20260918_007, after the API build that no longer selects it is live).
--
-- Prod 2026-09-18: pg_depend lists four dependents of address.id — the primary
-- key, its NOT NULL, its default (geocoder_generate_id()) and this matview,
-- which only uses the column to count address rows. `id` is NOT NULL and `a`
-- is the inner side of the join, so count(a.id) = count(*): 13,591 rows and
-- the same percentages either way (checked against prod before writing this).
--
-- A matview's query cannot be altered, and building it takes ~55 s on prod.
-- The Webservice reads it (/v4/product/statistics), so the new one is built
-- beside the old one and swapped in at the end: the old matview is locked for
-- the drop and two renames, not for the build.
--
-- The runner is doadmin; the matview belongs to fundermaps and Windmill
-- refreshes it CONCURRENTLY as fundermaps_windmill (needs MAINTAIN and the
-- unique index), so owner and grants are restored as they were.

CREATE MATERIALIZED VIEW data.statistics_product_data_collected_new AS
 SELECT ba.neighborhood_id,
    count(*) FILTER (WHERE i.id IS NOT NULL)::double precision / count(*)::double precision * 100::double precision AS percentage
   FROM geocoder.address a
     JOIN geocoder.building_active ba ON a.building_id::text = ba.external_id
     LEFT JOIN report.inquiry_sample i ON i.building_id::text = a.building_id::text
  GROUP BY ba.neighborhood_id;

CREATE UNIQUE INDEX statistics_product_data_collected_new_neighborhood_idx
  ON data.statistics_product_data_collected_new USING btree (neighborhood_id);

ALTER MATERIALIZED VIEW data.statistics_product_data_collected_new OWNER TO fundermaps;
GRANT SELECT ON data.statistics_product_data_collected_new TO fundermaps_webapp, fundermaps_webservice;
GRANT SELECT, INSERT, UPDATE, DELETE, MAINTAIN ON data.statistics_product_data_collected_new TO fundermaps_windmill;

DROP MATERIALIZED VIEW data.statistics_product_data_collected;
ALTER MATERIALIZED VIEW data.statistics_product_data_collected_new RENAME TO statistics_product_data_collected;
ALTER INDEX data.statistics_product_data_collected_new_neighborhood_idx RENAME TO statistics_product_data_collected_neighborhood_idx;
