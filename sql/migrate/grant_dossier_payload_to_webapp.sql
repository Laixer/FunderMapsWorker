-- The API role updates dataops.dossier column by column (grant_dataops_to_webapp.sql).
-- Two newer writers were missing from that list and hit "permission denied for
-- table dossier" on prod, 2026-09-14:
--
--   * the risk follow-up snapshot (API #169): after the afronding mail the API
--     stores what the melder was told in dossier.payload -> risk_snapshot, and
--     the run after the model refresh marks it checked. First real close
--     (FM2026-000035, 11:07Z) logged the refusal; the mail itself went out.
--   * the address panel (API #171): correcting the pand the dossier was filed
--     under writes building_id + resolution_status.
--
-- Idempotent.
--
--   psql "$DB_URL" -f sql/migrate/grant_dossier_payload_to_webapp.sql

GRANT UPDATE (payload, updated_at) ON dataops.dossier TO fundermaps_webapp;
GRANT UPDATE (building_id, resolution_status) ON dataops.dossier TO fundermaps_webapp;
-- relink (POST /dataops/dossier/:id/address/relink) moves values to another address.
GRANT UPDATE (address_id, address_text) ON dataops.extraction_field TO fundermaps_webapp;
