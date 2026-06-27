-- Issue #973 — Phase 3 (partial): delete the throwaway accounts that are
-- provably free. Self-validating: only deletes users that are a mapping SOURCE
-- (not a TARGET), have ZERO attribution references (creator or reviewer), and
-- own NO API keys (BA apikey or legacy auth_key). Accounts still tied to
-- recovery/orphan attribution, or owning keys, are left for a later step.
--
-- Cascades (by FK): organization_user, account (BA cred), session, oauth_* —
-- all expected cleanup for a dead account. Run from dir with mapping_clean.csv.
--   psql "$DB_URL" -f sql/migrate/cleanup_throwaway_accounts_safe.sql

\set SANITY_MAX 100

BEGIN;

CREATE TEMP TABLE _map (source_email text, target_email text) ON COMMIT DROP;
\copy _map FROM 'mapping_clean.csv' WITH (FORMAT csv, DELIMITER ';')

CREATE TEMP TABLE _safe ON COMMIT DROP AS
SELECT u.id, u.email
FROM application."user" u
WHERE u.email IN (SELECT source_email FROM _map)
  AND u.email NOT IN (SELECT target_email FROM _map)
  AND NOT EXISTS (SELECT 1 FROM application.attribution a
                   WHERE a.creator_id = u.id OR a.reviewer_id = u.id)
  AND NOT EXISTS (SELECT 1 FROM application.apikey k   WHERE k.reference_id = u.id)
  AND NOT EXISTS (SELECT 1 FROM application.auth_key k WHERE k.user_id      = u.id);

\echo '== accounts that will be deleted =='
SELECT email FROM _safe ORDER BY email;

\echo '== cascade preview (rows removed alongside) =='
SELECT 'organization_user' AS tbl, count(*) FROM application.organization_user x JOIN _safe s ON s.id = x.user_id
UNION ALL SELECT 'account', count(*) FROM application.account x JOIN _safe s ON s.id = x.user_id
UNION ALL SELECT 'session', count(*) FROM application.session x JOIN _safe s ON s.id = x.user_id;

-- Tripwire: refuse to run if the safe set is unexpectedly large.
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM _safe;
  IF n = 0 THEN RAISE EXCEPTION 'ABORT: safe set is empty — nothing to do (already cleaned?)'; END IF;
  IF n > 100 THEN RAISE EXCEPTION 'ABORT: safe set = % (> sanity max 100) — investigate before deleting', n; END IF;
  RAISE NOTICE 'safe set = % accounts', n;
END $$;

DELETE FROM application."user" u USING _safe s WHERE u.id = s.id;

\echo '== remaining candidates still blocked (for reference) =='
SELECT count(*) AS still_present
FROM application."user" u
WHERE u.email IN (SELECT source_email FROM _map)
  AND u.email NOT IN (SELECT target_email FROM _map);

COMMIT;
