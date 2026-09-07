-- Create the `fundermaps_api` role for the TS API (FunderMapsApi).
--
-- Part of the 2026-09-07 cloud naming convention: one DB role per connecting
-- service, named after the service (`fundermaps_<role>`). The API used to
-- connect as `fundermaps_webapp`; that role keeps every grant it has today and
-- becomes the privilege group `fundermaps_api` inherits from, so no per-table
-- GRANT has to move. Retire `fundermaps_webapp` (move its grants to
-- `fundermaps_api` in init/grants.sql, then DROP ROLE) with the v5 database.
--
-- Applied to prod 2026-09-07. The role itself was created through the
-- DigitalOcean API (`doctl databases user create … fundermaps_api`) so the
-- App Platform database binding (${db.USERNAME}/${db.PASSWORD}) can resolve
-- its password; a role created with plain CREATE ROLE is rejected by App
-- Platform with "user password is not accessible". On a self-managed instance
-- the CREATE ROLE below is the equivalent.

-- CREATE ROLE fundermaps_api LOGIN PASSWORD '…';   -- DO: doctl databases user create
GRANT fundermaps_webapp TO fundermaps_api;

-- Verify
-- SELECT has_table_privilege('fundermaps_api', 'application.session', 'INSERT');  -- t
