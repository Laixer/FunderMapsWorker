-- Rehearsal copy of prod's application.product_tracker (shape, grants, volume), on TimescaleDB 2.28.2 / PG 18.
-- Run as postgres on the throwaway container. Takes ~15 min for 31M rows.
SET statement_timeout = 0;
CREATE EXTENSION IF NOT EXISTS timescaledb;
DO $$ BEGIN
  CREATE ROLE fundermaps NOLOGIN; CREATE ROLE fundermaps_webservice LOGIN PASSWORD 'ws';
  CREATE ROLE fundermaps_webapp NOLOGIN; CREATE ROLE fundermaps_api LOGIN PASSWORD 'api' IN ROLE fundermaps_webapp;
  CREATE ROLE grafana NOLOGIN; CREATE ROLE fundermaps_windmill NOLOGIN; CREATE ROLE fundie_agent NOLOGIN;
END $$;
ALTER ROLE fundermaps_webservice SET statement_timeout = '60s';
ALTER ROLE fundermaps_api SET statement_timeout = '60s';

CREATE SCHEMA application AUTHORIZATION fundermaps;
CREATE SCHEMA geocoder AUTHORIZATION fundermaps;
CREATE SCHEMA data AUTHORIZATION fundermaps;
GRANT USAGE ON SCHEMA application, geocoder, data TO fundermaps_webservice, fundermaps_webapp, grafana, fundermaps_windmill, fundie_agent;

CREATE DOMAIN application.organization_id AS uuid;
CREATE DOMAIN geocoder.geocoder_id AS text;

CREATE TABLE application.organization (id application.organization_id PRIMARY KEY, name text NOT NULL);
CREATE TABLE geocoder.building (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, external_id geocoder.geocoder_id NOT NULL);
CREATE UNIQUE INDEX building_external_id_key ON geocoder.building (external_id);
GRANT SELECT ON application.organization, geocoder.building TO fundermaps_webservice, fundermaps_webapp;

INSERT INTO application.organization SELECT md5('org' || g)::uuid, 'org ' || g FROM generate_series(1, 60) g;
INSERT INTO geocoder.building (external_id) SELECT 'NL.IMBAG.PAND.' || lpad(g::text, 16, '0') FROM generate_series(1, 2000000) g;

CREATE TABLE application.product_tracker (
    organization_id application.organization_id NOT NULL,
    product text NOT NULL,
    building_id geocoder.geocoder_id NOT NULL,
    create_date timestamp with time zone NOT NULL DEFAULT CURRENT_TIMESTAMP,
    identifier text NOT NULL
);
ALTER TABLE application.product_tracker OWNER TO fundermaps;
SELECT create_hypertable('application.product_tracker', 'create_date', chunk_time_interval => interval '30 days');
GRANT SELECT, INSERT ON application.product_tracker TO fundermaps_webservice, fundermaps_webapp;
GRANT SELECT ON application.product_tracker TO grafana, fundermaps_windmill, fundie_agent;

-- 12M rows (disk budget on agent-0): 2M sparse rows 2021-10-30 → 2025-08 (old chunks), 10M over the last ~15 months
-- (prod-like weekly density, ~150k–200k rows a week), so there are ~61 monthly chunks like prod.
INSERT INTO application.product_tracker (organization_id, product, building_id, create_date, identifier)
SELECT md5('org' || (1 + (g % 60)))::uuid,
       (ARRAY['analysis3','analysis3','analysis3','analysis3','risk3','statistics3','light3','analysis','statistics','facade_scan4'])[1 + (g % 10)],
       'NL.IMBAG.PAND.' || lpad((1 + (hashint8(g) & 2147483647) % 2000000)::text, 16, '0'),
       timestamptz '2021-10-30' + (interval '1 second' * floor(extract(epoch FROM (timestamptz '2025-08-01' - timestamptz '2021-10-30')) * (g::float8 / 2000000))),
       'key-' || (g % 97)
  FROM generate_series(1, 2000000) g;
INSERT INTO application.product_tracker (organization_id, product, building_id, create_date, identifier)
SELECT md5('org' || (1 + (g % 60)))::uuid,
       (ARRAY['analysis3','analysis3','analysis3','analysis3','risk3','statistics3','light3','analysis','statistics','facade_scan4'])[1 + (g % 10)],
       'NL.IMBAG.PAND.' || lpad((1 + (hashint8(g + 7) & 2147483647) % 2000000)::text, 16, '0'),
       timestamptz '2025-08-01' + (interval '1 second' * floor(extract(epoch FROM (now() - interval '1 hour' - timestamptz '2025-08-01')) * (g::float8 / 10000000))),
       'key-' || (g % 97)
  FROM generate_series(1, 10000000) g;
-- indexes and foreign keys after the load (faster); the end state equals prod's
CREATE INDEX product_tracker_building_id_idx ON application.product_tracker USING btree (building_id);
CREATE INDEX product_tracker_org_prod_id_date_idx ON application.product_tracker USING btree (organization_id, product, identifier, create_date);
ALTER TABLE application.product_tracker
  ADD CONSTRAINT product_tracker_building_id_fkey FOREIGN KEY (building_id) REFERENCES geocoder.building (external_id) ON UPDATE CASCADE,
  ADD CONSTRAINT product_tracker_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES application.organization (id) ON UPDATE CASCADE ON DELETE CASCADE;
ANALYZE application.product_tracker;

CREATE MATERIALIZED VIEW data.product_tracker_daily AS
 SELECT (create_date AT TIME ZONE 'Europe/Amsterdam'::text)::date AS day, organization_id, product, count(*) AS calls
   FROM application.product_tracker
  GROUP BY ((create_date AT TIME ZONE 'Europe/Amsterdam'::text)::date), organization_id, product;
CREATE UNIQUE INDEX product_tracker_daily_pkey ON data.product_tracker_daily USING btree (day, organization_id, product);
ALTER MATERIALIZED VIEW data.product_tracker_daily OWNER TO fundermaps;
GRANT SELECT, MAINTAIN ON data.product_tracker_daily TO fundermaps_windmill;
GRANT SELECT ON data.product_tracker_daily TO grafana, fundie_agent;

SELECT count(*) AS chunks FROM timescaledb_information.chunks WHERE hypertable_name = 'product_tracker';
SELECT pg_size_pretty(hypertable_size('application.product_tracker')) AS size;
