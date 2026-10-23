-- The API reads the daily usage rollup again (2026-10-23): the Admin's usage
-- page, GET /api/management/usage (administrators only), takes over Grafana's
-- two usage boards ("Usage - webservice & API", "Usage - maps & studio").
-- Counting the raw application.product_tracker (26M rows) across all
-- customers on every page load is what the rollup exists to avoid.
--
-- 20261009_008 revoked this SELECT from fundermaps_webapp because no API code
-- read the rollup then; this gives that one privilege back, nothing else.
-- Approved in the terminal on 2026-10-23 ("Grant is fine").
--
-- The rollup is refreshed with REFRESH MATERIALIZED VIEW CONCURRENTLY
-- (windmill f/fundermaps/data/refresh_product_tracker_daily), which keeps
-- grants; a DROP + CREATE of it would need this grant repeated.
--
-- FunderMapsApi logs in as fundermaps_api, a member of fundermaps_webapp,
-- which holds the grants. Skipped with a NOTICE where fundermaps_webapp does
-- not exist; fails if the privilege is not there afterwards.

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_webapp') THEN
        RAISE NOTICE 'role fundermaps_webapp does not exist; nothing changed';
        RETURN;
    END IF;

    GRANT SELECT ON data.product_tracker_daily TO fundermaps_webapp;

    IF NOT has_table_privilege('fundermaps_webapp', 'data.product_tracker_daily', 'SELECT') THEN
        RAISE EXCEPTION 'fundermaps_webapp still cannot read data.product_tracker_daily';
    END IF;
END
$$;
