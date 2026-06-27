-- Issue #973 — Phase 3 step A: clear the attribution references still pinning
-- the throwaway accounts, so they become deletable.
--
--   1. Delete ORPHAN attribution rows tied to candidates — attribution
--      referenced by neither report.inquiry nor report.recovery (the only two
--      referencers), i.e. dangling leftovers from hard-deleted reports.
--   2. Re-point RECOVERY attribution via the same rule as Step 0:
--      creator faithful to the mapping; reviewer faithful too, except where that
--      equals the new creator → review@fundermaps.com (creator_reviewer_chk).
--
-- Run from dir with mapping_clean.csv.
--   psql "$DB_URL" -f sql/migrate/clear_throwaway_blockers.sql

BEGIN;

CREATE TEMP TABLE _map (source_email text, target_email text) ON COMMIT DROP;
\copy _map FROM 'mapping_clean.csv' WITH (FORMAT csv, DELIMITER ';')

CREATE TEMP TABLE _map_id ON COMMIT DROP AS
SELECT s.id AS source_id, t.id AS target_id
FROM _map m
JOIN application."user" s ON s.email = m.source_email
JOIN application."user" t ON t.email = m.target_email;

CREATE TEMP TABLE _cand ON COMMIT DROP AS
SELECT u.id FROM application."user" u
WHERE u.email IN (SELECT source_email FROM _map)
  AND u.email NOT IN (SELECT target_email FROM _map);

-- 1. Delete orphan attribution tied to candidates.
\echo '== deleting orphan attribution rows tied to candidates =='
DELETE FROM application.attribution a
WHERE (a.creator_id IN (SELECT id FROM _cand) OR a.reviewer_id IN (SELECT id FROM _cand))
  AND a.id NOT IN (SELECT attribution_id FROM report.inquiry)
  AND a.id NOT IN (SELECT attribution_id FROM report.recovery);

-- 2. Re-point recovery attribution (same creator-faithful / reviewer-sacrificial
--    rule as Step 0). Precompute new values, then apply only where they differ.
CREATE TEMP TABLE _rec_new ON COMMIT DROP AS
SELECT a.id,
  COALESCE(cm.target_id, a.creator_id) AS new_creator,
  CASE
    WHEN COALESCE(cm.target_id, a.creator_id) = COALESCE(rm.target_id, a.reviewer_id)
      THEN (SELECT id FROM application."user" WHERE email = 'review@fundermaps.com')
    ELSE COALESCE(rm.target_id, a.reviewer_id)
  END AS new_reviewer
FROM application.attribution a
LEFT JOIN _map_id cm ON cm.source_id = a.creator_id
LEFT JOIN _map_id rm ON rm.source_id = a.reviewer_id
WHERE a.id IN (SELECT attribution_id FROM report.recovery);

\echo '== re-pointing recovery attribution =='
UPDATE application.attribution a
SET creator_id  = n.new_creator,
    reviewer_id = n.new_reviewer
FROM _rec_new n
WHERE a.id = n.id
  AND (a.creator_id <> n.new_creator OR a.reviewer_id <> n.new_reviewer);

-- ---------------------------------------------------------------------------
-- VERIFY: no candidate should remain referenced by ANY attribution row now
-- (inquiry done in Step 0, orphans deleted, recovery re-pointed). The only
-- thing left keeping candidates alive should be API-key ownership.
-- ---------------------------------------------------------------------------
\echo '== candidates still referenced by attribution (expect 0) =='
SELECT count(*) AS candidates_still_referenced
FROM _cand c
WHERE EXISTS (SELECT 1 FROM application.attribution a
              WHERE a.creator_id = c.id OR a.reviewer_id = c.id);

\echo '== no inquiry/recovery row left self-reviewed (expect 0 each) =='
SELECT
  (SELECT count(*) FROM application.attribution a
     WHERE a.id IN (SELECT attribution_id FROM report.inquiry)  AND a.creator_id = a.reviewer_id) AS inquiry_selfrev,
  (SELECT count(*) FROM application.attribution a
     WHERE a.id IN (SELECT attribution_id FROM report.recovery) AND a.creator_id = a.reviewer_id) AS recovery_selfrev;

DO $$
DECLARE v int;
BEGIN
  SELECT count(*) INTO v FROM application.attribution a
   WHERE a.id IN (SELECT attribution_id FROM report.recovery) AND a.creator_id = a.reviewer_id;
  IF v <> 0 THEN RAISE EXCEPTION 'ABORT: % recovery rows self-reviewed after remap', v; END IF;
END $$;

COMMIT;
