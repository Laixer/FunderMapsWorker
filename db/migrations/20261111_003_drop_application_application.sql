-- Drop application.application and its id generator (Yorick 2026-11-10: "Then we go with you recommendation").
--
-- The registry of the old FunderMaps apps and portals. On 2026-11-10 no code in any repo reads it; its only use was as
-- the parent of application_user's foreign key. 2 of its 21 rows were referenced (app-default = the map's settings,
-- app-0blu4s39 = the old map's), the other 19 were old portals, Worker, Grafana, Report and an OAuth test, and all 21
-- held an app secret that nothing checks any more. application_user stays: it holds the map's per-user settings, and
-- its application_id becomes plain text. random_string() only filled this table's id and secret.
-- An encrypted copy of the 21 rows: loket db-app-table/ and fundermaps-archive/retired/application-table/.
SET LOCAL lock_timeout = '2s';

DO $$
BEGIN
    IF to_regclass('application.application') IS NULL THEN
        RAISE EXCEPTION 'application.application is not there; stopping';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_constraint
                WHERE contype = 'f' AND confrelid = 'application.application'::regclass
                  AND conname <> 'application_user_application_id_fkey') THEN
        RAISE EXCEPTION 'another foreign key points at application.application; stopping';
    END IF;
END
$$;

ALTER TABLE application.application_user DROP CONSTRAINT IF EXISTS application_user_application_id_fkey;
DROP TABLE application.application;
DROP FUNCTION application.random_string(integer);

COMMENT ON COLUMN application.application_user.application_id IS
    'Which app the settings belong to: app-default = the map (the API''s MAP_APP_ID). app-0blu4s39 = the old map, nothing '
    'written since 2026-04. Plain text since application.application was dropped (2026-11-10).';
