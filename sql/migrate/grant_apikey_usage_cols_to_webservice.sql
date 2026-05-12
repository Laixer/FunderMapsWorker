-- Grant the Webservice role surgical UPDATE on application.apikey's
-- usage-tracking columns so its dual-read auth middleware can bump
-- last_request + request_count on cache miss (Phase B.2 of the apiKey
-- migration). Mirrors the same pattern applied to application.auth_key
-- when its last_used write was wired up (FunderMapsWebservice PR #1,
-- 2026-05-09): table-level access stays read-only; only the specific
-- observability columns are writable.
--
-- The Webservice itself never INSERTs, DELETEs, or otherwise mutates
-- apikey rows — that's the TS API's management routes (Phase B.3, gated
-- behind fundermaps_webapp which already has full r/w on the table).
-- Granting only these two columns keeps the principle of least privilege
-- intact for the billable surface.

BEGIN;

GRANT UPDATE (last_request, request_count)
   ON application.apikey
   TO fundermaps_webservice;

COMMIT;
