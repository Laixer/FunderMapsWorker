-- Better Auth 1.7 schema upgrade — phase B. DO NOT run until FunderMapsApi
-- has been on better-auth 1.7.x for at least a week (rollback window).
--
-- 1.7 replaced oauth_application.type / .public with application_type and
-- token_endpoint_auth_method = 'none' (see upgrade_better_auth_1_7.sql).
-- Phase A kept both columns so a 1.6 build could still be redeployed; once
-- that window is closed they are dead weight.
--
-- Run as `doadmin` (table owner). Idempotent.
--   psql "$DOADMIN_URL" -v ON_ERROR_STOP=1 -f sql/migrate/drop_better_auth_legacy_client_columns.sql

BEGIN;

ALTER TABLE application.oauth_application
  DROP COLUMN IF EXISTS type,
  DROP COLUMN IF EXISTS public;

COMMIT;
