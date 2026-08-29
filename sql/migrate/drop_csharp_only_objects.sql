-- Second C# Webservice EOL sweep: objects and grants only the C# code used.
--
-- Audit 2026-08-29 over every object in schema.sql vs FunderMapsApi,
-- FunderMapsWebservice, FunderMapsWorker, the frontends, Windmill scripts
-- (23 scripts / 3 flows / 4 schedules dumped and grepped) and Grafana
-- dashboards. Zero references outside the retired C# monolith for:
--
--   report.fir_generate_id(int)  C# IncidentRepository minted 'FIR<client><year>-<n>'
--                                incident ids with it; API routes/incident.ts is read-only.
--   report.incident_id_seq       only consumer was fir_generate_id (not a column default).
--   geocoder.address_building    C# Address/Building/Neighborhood repositories joined
--                                through this view; TS uses building_geocoder / direct joins.
--   data.refresh_clusters()      orphaned since the refresh-models job was removed (8dafa9f);
--                                no Windmill script CALLs it.
--
-- Grants on role fundermaps_webservice that the Bun Webservice never exercises
-- (pg_stat_statements since 2026-08-23: it writes only product_tracker INSERT,
-- auth_key UPDATE, apikey UPDATE). All were needed by the C# WebApi era only.
-- Chunk-level grants under _timescaledb_internal are left alone on purpose.
--
-- Run as: fundermaps (owner of all objects and grantor of the privileges).

BEGIN;

DROP FUNCTION report.fir_generate_id(integer);
DROP SEQUENCE report.incident_id_seq;
DROP VIEW geocoder.address_building;
DROP PROCEDURE data.refresh_clusters();

REVOKE INSERT, UPDATE, DELETE ON
    application.organization_geolock_district,
    application.organization_geolock_municipality,
    application.organization_geolock_neighborhood
    FROM fundermaps_webservice;
REVOKE UPDATE ON application.user FROM fundermaps_webservice;
REVOKE UPDATE ON application.product_tracker FROM fundermaps_webservice;
REVOKE USAGE ON SEQUENCE
    application.attribution_id_seq,
    report.inquiry_id_seq,
    report.inquiry_sample_id_seq,
    report.recovery_id_seq,
    report.recovery_sample_id_seq
    FROM fundermaps_webservice;

COMMIT;
