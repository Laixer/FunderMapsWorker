-- Drop the two old-name views (Yorick 2026-11-08: "go ahead with 1 and 2").
--
-- 20261030_005 renamed dataops.dossier_rapportage to dossier_inquiry and application.file_resources to file_resource, and
-- kept a view under each old name for api-prod and saved scripts. api-prod is gone (2026-11-01). On 2026-11-08 no code in
-- any repo names them, nothing in the database depends on them, no scheduled Fundie job uses them, and Fundie's database
-- map lists only the new names. No CASCADE: if anything depends on them after all, this stops and changes nothing.
SET LOCAL lock_timeout = '2s';

DO $$
BEGIN
    IF (SELECT relkind FROM pg_class WHERE oid = to_regclass('dataops.dossier_rapportage')) IS DISTINCT FROM 'v'
       OR (SELECT relkind FROM pg_class WHERE oid = to_regclass('application.file_resources')) IS DISTINCT FROM 'v' THEN
        RAISE EXCEPTION 'the two old-name views are not both there as views; stopping';
    END IF;
END
$$;

DROP VIEW dataops.dossier_rapportage;
DROP VIEW application.file_resources;
