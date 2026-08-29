-- Drop the two tables only the C# Webservice ever wrote or read.
--
-- The C# Webservice (Laixer/FunderMaps, /api/v3) reached end-of-life at the
-- end of August 2026: zero customer traffic since 2026-08-11, ingress parked
-- on /obsolete 2026-08-26, component deleted from the ws-prod app 2026-08-29.
--
-- application.product_tracker_mismatch — TimescaleDB hypertable (49 chunks,
--   238 MB, 2.2M rows) written by C# ProductTrackerRepository when a v3
--   product request hit a building outside the org geofence. Last row
--   2026-08-11 08:34 UTC. Verified 2026-08-29: no dependent views, no
--   Timescale jobs/policies, no function bodies, zero TS runtime readers —
--   only an orphaned Drizzle declaration in FunderMapsApi (removed
--   separately) and the INSERT grant in sql/init/grants.sql (removed here).
--   Note: this table was the only way to tell v3 from v4 traffic apart; that
--   question is moot now.
-- application.key_store — C# ASP.NET DataProtection key ring (11 rows,
--   'key-<uuid>'). Zero readers outside the retired C# apps.
--
-- Run as: fundermaps (owner of both tables).

BEGIN;

DROP TABLE application.product_tracker_mismatch;   -- cascades to its _timescaledb_internal chunks
DROP TABLE application.key_store;

COMMIT;
