-- !! REVERTED 2026-07-23 — DO NOT RE-RUN before C# Webservice EOL (Aug 2026).
-- The "Verified 2026-07-20" claim below was wrong: the live Webservice reads
-- organization_user.role on every API-key sign-in (SignInService.
-- CreateClaimsIdentityAsync → GetOrganizationRoleByUserIdAsync), and this
-- migration broke all authenticated /api/v3 traffic until reverted.
-- See revert_organization_user_role_enum.sql.
--
-- Phase 2 follow-up (#1006 roles UI): allow dynamic custom-role names in
-- application.organization_user.role. The column was the
-- application.organization_role ENUM, which only admits the four fixed
-- names; admin-defined roles live in application.organization_custom_role
-- and carry arbitrary names, so the member column becomes text.
--
-- The ENUM TYPE itself STAYS: the C# stack registers it at startup
-- (NpgsqlDbProvider MapEnum<OrganizationRole>()) and dropping it would
-- break the Webservice. Verified 2026-07-20 that the live Webservice never
-- reads organization_user.role (its auth path is auth_key → user only);
-- only the retired WebApi touched this column. Drop the type together with
-- auth_key at C# EOL (end of Aug 2026).
--
-- Reversible while every stored value is still one of the four fixed names:
--   ALTER TABLE application.organization_user
--     ALTER COLUMN role TYPE application.organization_role
--     USING role::application.organization_role;
--
-- Run as the `fundermaps` role (owner of application.*). Idempotent.
--   psql "$DB_URL" -f sql/migrate/alter_organization_user_role_text.sql

BEGIN;

ALTER TABLE application.organization_user
  ALTER COLUMN role DROP DEFAULT;

ALTER TABLE application.organization_user
  ALTER COLUMN role TYPE text USING role::text;

ALTER TABLE application.organization_user
  ALTER COLUMN role SET DEFAULT 'reader';

COMMIT;
