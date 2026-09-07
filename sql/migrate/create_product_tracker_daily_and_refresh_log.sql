-- One-shot: two small objects for the rebuilt Grafana boards (Don + Yorick
-- approved the "Grafana Dashboard Review" of 2026-09-07).
--
-- 1. data.product_tracker_daily — day × organization × product call counts.
--    The Usage & billing board reads this instead of scanning the 29 M-row
--    product_tracker hypertable on every refresh (1.27 M rows / 30 days).
--    Refreshed CONCURRENTLY by the refresh_data_model flow (twice daily), so
--    it needs a unique index. fundermaps_windmill refreshes via MAINTAIN, as
--    with the other data.* matviews.
-- 2. data.refresh_log — one row per refresh_data_model run, written by the
--    flow's last step. The Operations board's "model refresh age" stat reads
--    max(finished_at); this is the dead-man switch from the 5.0 review.
--
-- Run as doadmin. Applied to prod 2026-09-07.

CREATE MATERIALIZED VIEW data.product_tracker_daily AS
SELECT (create_date AT TIME ZONE 'Europe/Amsterdam')::date AS day,
       organization_id,
       product,
       count(*)::bigint AS calls
FROM application.product_tracker
GROUP BY 1, 2, 3
WITH DATA;

ALTER MATERIALIZED VIEW data.product_tracker_daily OWNER TO fundermaps;
CREATE UNIQUE INDEX product_tracker_daily_pkey
    ON data.product_tracker_daily (day, organization_id, product);
COMMENT ON MATERIALIZED VIEW data.product_tracker_daily IS
    'Webservice/map usage per Amsterdam-local day, organization and product. Source: application.product_tracker. Refreshed by the refresh_data_model flow.';

GRANT SELECT ON data.product_tracker_daily TO grafana, fundermaps_webapp, fundermaps_webservice;
GRANT SELECT, MAINTAIN ON data.product_tracker_daily TO fundermaps_windmill;

CREATE TABLE data.refresh_log (
    id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    job         text        NOT NULL,
    status      text        NOT NULL DEFAULT 'ok',
    finished_at timestamptz NOT NULL DEFAULT now(),
    detail      jsonb
);
ALTER TABLE data.refresh_log OWNER TO fundermaps;
CREATE INDEX refresh_log_job_finished_idx ON data.refresh_log (job, finished_at DESC);
COMMENT ON TABLE data.refresh_log IS
    'One row per completed scheduled job (e.g. refresh_data_model). Read by Grafana and, later, /health/nightly as a dead-man switch.';

GRANT SELECT ON data.refresh_log TO grafana, fundermaps_webapp, fundermaps_webservice;
GRANT SELECT, INSERT ON data.refresh_log TO fundermaps_windmill;

-- Grafana reads the intake pipeline state for the Operations board, and the
-- data schema (grants.sql lists it, prod never had it).
GRANT USAGE ON SCHEMA data TO grafana;
GRANT USAGE ON SCHEMA dataops TO grafana;
GRANT SELECT ON dataops.dossier, dataops.extraction TO grafana;

-- Bureau breakdown on the Data quality board.
GRANT SELECT ON application.contractor TO grafana;
