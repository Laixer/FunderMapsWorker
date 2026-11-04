-- Delete the soft-deleted inquiry samples (Yorick 2026-11-04: "Delete those samples and delete the soft delete cols").
--
-- Step 1 of removing delete_date from the five report tables: the rows go first, so the code can stop filtering on
-- the column without bringing them back. These 101 rows are the only ones that ever used it. They were set between
-- 2019-10 and 2020-09; nothing has written delete_date since, the API deletes physically.
--
-- They were half gone: the Webservice's research endpoints and the Studio's building view hide them, but
-- data.building_sample ignores delete_date, so the model still read them. For 16 buildings they were the leading
-- report's only samples on that building. After this file and the next refresh those buildings use their next
-- evidence. model-2024.1 is frozen and does not change.
--
-- Prod, 2026-11-04 (read-only): no foreign key points at report.inquiry_sample; its triggers fire on INSERT and UPDATE
-- only. One report ends up without samples (99601, audit status pending_review); reports are not touched.
-- A database bootstrapped from schema.sql has none of these rows, so the guard allows 0 or exactly 101.

SET LOCAL lock_timeout = '2s';

DO $$
DECLARE n bigint;
BEGIN
    SELECT count(*) INTO n FROM report.inquiry_sample WHERE delete_date IS NOT NULL;
    IF n NOT IN (0, 101) THEN
        RAISE EXCEPTION 'expected 0 or 101 soft-deleted inquiry samples, found %; stopping', n;
    END IF;
END
$$;

DELETE FROM report.inquiry_sample WHERE delete_date IS NOT NULL;
