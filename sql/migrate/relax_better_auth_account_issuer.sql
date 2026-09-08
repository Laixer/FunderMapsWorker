-- One-shot: undo the Better Auth 1.7.0–1.7.2 account identity change.
--
-- 1.7.0 keyed accounts on (issuer, account_id) and made issuer NOT NULL with a
-- unique index; we applied that on 2026-08-29 (upgrade_better_auth_1_7.sql,
-- since pruned). 1.7.3 (2026-09-06) reverted to the 1.6 identity
-- (provider_id, account_id), never writes issuer, and checks the schema at
-- start-up: a NOT NULL column it never writes is a hard SCHEMA_MISMATCH that
-- rejects every auth request. Upgrade guide:
-- https://www.better-auth.com/docs/guides/1-7-upgrade-guide#account-identity-keeps-the-provider-key
--
-- Safe to apply while 1.7.2 is still deployed: 1.7.2 keeps writing issuer, it
-- just no longer has to. The column stays (nullable) so a 1.7.2 build keeps
-- working; a later migration drops it once 1.7.3 has been live for a while.
--
-- Run as doadmin. Applied to prod 2026-09-07.
ALTER TABLE application.account ALTER COLUMN issuer DROP NOT NULL;
DROP INDEX IF EXISTS application.account_issuer_account_id_key;
