-- data.refresh_all() — Full model refresh procedure
--
-- Scheduled via pg_cron: daily at 18:00 UTC
-- Replaces the Python refresh_models.py + systemd timer for the model refresh.
--
-- Sequence:
--   1. Refresh sample matviews (building, cluster, supercluster)
--   2. Refresh model_risk_static matview (was INSERT ON CONFLICT, now matview)
--   3. Refresh all 12 statistics matviews
--   4. Rebuild maplayer.building_tiles (dynamic tileserver source)
--   5. Submit process_mapset job to worker queue (tile generation)
--
-- Each step COMMITs independently so locks are released between steps.

CREATE OR REPLACE PROCEDURE data.refresh_all()
LANGUAGE plpgsql
AS $$
BEGIN
    -- Step 1: Refresh sample matviews
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.building_sample;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.cluster_sample;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.supercluster_sample;
    COMMIT;

    -- Step 2: Refresh risk model matview
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.model_risk_static;
    COMMIT;

    -- Step 3: Refresh statistics matviews
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_product_inquiries;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_product_inquiry_municipality;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_product_incidents;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_product_incident_municipality;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_product_foundation_type;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_product_foundation_risk;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_product_data_collected;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_product_construction_years;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_product_buildings_restored;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_postal_code_foundation_type;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_postal_code_foundation_risk;
    COMMIT;
    REFRESH MATERIALIZED VIEW CONCURRENTLY data.statistics_postal_code_data_collected;
    COMMIT;

    -- Step 4: Rebuild the flat tile-source table for the Martin tileserver
    -- (sql/model/create_building_tiles.sql). Runs after model_risk_static so
    -- dynamic tiles pick up tonight's model output.
    CALL maplayer.refresh_building_tiles();
    COMMIT;

    -- Step 5: Submit process_mapset job to worker queue
    INSERT INTO application.worker_jobs (job_type, status, max_retries) VALUES ('process_mapset', 'pending', 0);
END;
$$;
