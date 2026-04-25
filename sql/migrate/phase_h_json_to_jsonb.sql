-- Phase H: convert 2 stragglers from json → jsonb.
--
-- Every other JSON column in the schema is jsonb. These two were
-- left as json (text-based, no operator support, no indexable
-- internal structure). jsonb is strictly better for the same wire
-- format.
--
-- application.application_user.metadata     (162 rows)
-- application.organization_mapset.metadata  (215 rows)
--
-- DB-only change. No app coordination needed:
--   - C# Dapper handles both identically at the wire level.
--   - TS API Drizzle ALREADY declares applicationUser.metadata as
--     jsonb (this migration brings the DB into agreement with what
--     the TS code thought was already true).
--
-- ALTER COLUMN ... TYPE jsonb USING ... requires a table rewrite
-- since the on-disk format changes, but on these row counts that's
-- milliseconds.
--
-- Run as: fundermaps (owner)

BEGIN;

ALTER TABLE application.application_user
    ALTER COLUMN metadata TYPE jsonb USING metadata::jsonb;

ALTER TABLE application.organization_mapset
    ALTER COLUMN metadata TYPE jsonb USING metadata::jsonb;

COMMIT;
