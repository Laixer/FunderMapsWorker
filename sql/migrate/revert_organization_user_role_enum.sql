-- INCIDENT REVERT 2026-07-23: restore application.organization_user.role
-- to the application.organization_role ENUM.
--
-- alter_organization_user_role_text.sql (applied 2026-07-22) converted the
-- column to text for #1006 custom-role names. Its header claimed the live
-- C# Webservice never reads this column — that verification was WRONG:
-- the API-key auth path is
--   AuthKeyAuthenticationHandler → SignInService.AuthKeySignInAsync
--   → CreateClaimsIdentityAsync
--   → OrganizationUserRepository.GetOrganizationRoleByUserIdAsync
-- which SELECTs organization_user.role into the mapped
-- MapEnum<OrganizationRole>() type. With the column as text, Dapper's enum
-- materialization threw ArgumentException on EVERY authenticated /api/v3
-- request until this revert was applied (2026-07-23 ~11:24 UTC).
--
-- Consequence: custom-role names CANNOT be stored in organization_user.role
-- while the C# Webservice is live (EOL end of Aug 2026). Until then,
-- assigning a custom role to a member will fail with an enum error at the
-- DB. Either patch the C# reader (SELECT role::text + tolerant parse) and
-- re-run the text migration, or park custom-role assignment until EOL.
--
-- Rule going forward: no DDL on application.* auth tables without checking
-- the C# surface (FunderMaps.Data repositories + NpgsqlDbProvider MapEnum
-- list) until C# EOL.
--
-- Applied to prod 2026-07-23 as doadmin. Idempotent.

BEGIN;

SET LOCAL lock_timeout = '5s';

ALTER TABLE application.organization_user
  ALTER COLUMN role DROP DEFAULT;

ALTER TABLE application.organization_user
  ALTER COLUMN role TYPE application.organization_role
  USING role::application.organization_role;

ALTER TABLE application.organization_user
  ALTER COLUMN role SET DEFAULT 'reader'::application.organization_role;

COMMIT;
