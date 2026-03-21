-- Eliminate GFM IDs from the model pipeline
--
-- After this migration, model_risk_static.building_id = BAG ID (was GFM).
-- The external_building_id column is dropped (redundant).
--
-- Prerequisites:
--   - All FKs already point to geocoder.building(external_id)
--   - inquiry_sample.building, incident.building, address.building_id all contain BAG values
--
-- Run order:
--   1. This script (fix views, functions, building_precomputed)
--   2. sql/model/create_building_precomputed.sql (recreate table without internal_building_id)
--   3. sql/model/recreate_model_risk_dynamic_all.sql (new view outputting BAG building_id)
--   4. sql/model/recreate_model_risk_manifest.sql (recreate model_risk_static without external_building_id)
--   5. sql/model/consolidate_analysis_views.sql (analysis views join on BAG building_id)
--   6. sql/model/fix_statistics.sql (recreate stats matviews)
--   7. sql/model/create_refresh_all.sql (refresh procedure)
--   8. CALL data.refresh_building_precomputed();
--   9. REFRESH all matviews via: CALL data.refresh_all();

--------------------------------------------------------------------------------
-- 1. Fix address_building view
--    Output building_id as BAG (ba.external_id) instead of GFM (ba.id)
--    address_id stays as addr.id (GFM) — address PK migration is separate
--------------------------------------------------------------------------------

CREATE OR REPLACE VIEW geocoder.address_building AS
SELECT
    addr.id AS address_id,
    ba.external_id AS building_id,
    ba.geom
FROM geocoder.address addr
JOIN geocoder.building_active ba ON addr.building_id = ba.external_id;

--------------------------------------------------------------------------------
-- 2. Fix maplayer.building_cluster view
--    Was: ba.id = bc.building_id (GFM vs BAG — broken)
--    Fix: ba.external_id = bc.building_id (both BAG)
--------------------------------------------------------------------------------

CREATE OR REPLACE VIEW maplayer.building_cluster AS
SELECT
    bc.cluster_id,
    public.st_union(ba.geom) AS geom
FROM data.building_cluster bc
JOIN geocoder.building_active ba ON ba.external_id = bc.building_id
GROUP BY bc.cluster_id;

--------------------------------------------------------------------------------
-- 3. Fix maplayer.building_supercluster view
--    Same issue as building_cluster
--------------------------------------------------------------------------------

CREATE OR REPLACE VIEW maplayer.building_supercluster AS
SELECT
    s.supercluster_id,
    public.st_union(ba.geom) AS geom
FROM data.supercluster s
JOIN data.building_cluster bc ON bc.cluster_id = s.cluster_id
JOIN geocoder.building_active ba ON ba.external_id = bc.building_id
GROUP BY s.supercluster_id;

--------------------------------------------------------------------------------
-- 4. Fix refresh_clusters() procedure
--    Was: uses ba.id (GFM) throughout — broken since building_cluster FK requires BAG
--    Fix: use ba.external_id everywhere
--------------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE data.refresh_clusters()
LANGUAGE plpgsql
AS $$
DECLARE
    local_cluster text[];
    neighbors text[];
    counter integer := 0;
    cluster_id uuid;
BEGIN
    DROP TABLE IF EXISTS building_all;
    CREATE TEMP TABLE building_all (
        building_id text NOT NULL,
        CONSTRAINT building_all_pkey PRIMARY KEY (building_id)
    );

    INSERT INTO building_all
    SELECT ba.external_id FROM geocoder.building_active AS ba
    EXCEPT
    SELECT c.building_id FROM data.building_cluster AS c;

    TRUNCATE data.building_cluster;

    LOOP
        SELECT INTO cluster_id uuid_generate_v4();
        SELECT INTO local_cluster ARRAY[building_id] FROM building_all LIMIT 1;

        EXIT WHEN local_cluster IS NULL;

        neighbors := local_cluster;

        LOOP
            SELECT array_agg(b2.external_id) INTO neighbors
            FROM geocoder.building_active b
            JOIN geocoder.building_active b2
                ON st_intersects(b.geom, b2.geom)
                AND b.built_year = b2.built_year
                AND b2.external_id <> all(local_cluster)
            WHERE b.built_year IS NOT NULL
            AND b.external_id = any(neighbors);

            EXIT WHEN neighbors IS NULL;

            local_cluster := local_cluster || neighbors;
        END LOOP;

        IF array_length(local_cluster, 1) > 1 THEN
            INSERT INTO data.building_cluster
            SELECT unnest(local_cluster), cluster_id
            ON CONFLICT DO NOTHING;
        END IF;

        DELETE FROM building_all
        WHERE building_id = any(local_cluster);

        IF counter % 1000 = 0 THEN
            RAISE NOTICE 'Counter %', counter;
            COMMIT;
        END IF;

        IF counter % 50000 = 0 AND counter > 0 THEN
            RAISE NOTICE 'Reindex %', counter;
            REINDEX INDEX data.building_all_pk;
        END IF;

        counter := counter + 1;
    END LOOP;

    DROP TABLE building_all;
END;
$$;

--------------------------------------------------------------------------------
-- 5. Fix id_lookup() — return BAG external_id instead of GFM id
--    Also remove the 'fundermaps' (GFM) branch — no callers should send GFM
--------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION geocoder.id_lookup(input text) RETURNS text
LANGUAGE plpgsql PARALLEL SAFE
AS $$
DECLARE
    identifier geocoder.id_parser_tuple;
    result_id text;
BEGIN
    SELECT parse_result.type, parse_result.id
    INTO identifier
    FROM geocoder.id_parser(input) AS parse_result;

    CASE identifier.type
        WHEN 'fundermaps' THEN
            -- Legacy GFM lookup — translate to BAG
            SELECT ba.external_id
            INTO   result_id
            FROM   geocoder.building_active ba
            WHERE  ba.id = identifier.id
            LIMIT  1;
        WHEN 'nl_bag_building', 'nl_bag_berth', 'nl_bag_posting' THEN
            SELECT ba.external_id
            INTO   result_id
            FROM   geocoder.building_active ba
            WHERE  ba.external_id = identifier.id
            LIMIT  1;
        WHEN 'nl_bag_address' THEN
            SELECT ba.external_id
            INTO   result_id
            FROM   geocoder.address addr
            JOIN   geocoder.building_active ba ON addr.building_id = ba.external_id
            WHERE  addr.external_id = identifier.id
            LIMIT  1;
    END CASE;

    IF NOT FOUND THEN
        RAISE no_data_found;
    END IF;

    RETURN result_id;
END;
$$;

--------------------------------------------------------------------------------
-- 6. Drop building_precomputed.internal_building_id if table already exists
--    (The create script no longer includes this column, but existing table may have it)
--------------------------------------------------------------------------------

DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'data'
          AND table_name = 'building_precomputed'
          AND column_name = 'internal_building_id'
    ) THEN
        DROP INDEX IF EXISTS data.idx_bp_internal_id;
        ALTER TABLE data.building_precomputed DROP COLUMN internal_building_id;
    END IF;
END;
$$;
