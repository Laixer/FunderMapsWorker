-- Drop report.*.delete_date (Yorick 2026-11-04: "Delete those samples and delete the soft delete cols").
--
-- Step 3 of 3. Step 1 (20261104_002) deleted the only rows that used it. Step 2 took it out of the
-- API, the Webservice, the Worker and the pinned Windmill job. The only thing left naming it is
-- data.model_risk_2026_3_rows, as a filter on report.recovery_sample, where no row has it set, so the
-- function returns the same rows without the filter.
--
-- The function is rewritten from its own definition: exactly that one line goes, and its owner and
-- grants stay. No CASCADE: if anything still depends on a column, this fails and changes nothing.
-- Rollback: ADD COLUMN delete_date timestamptz on each table (every value is NULL today).
SET LOCAL lock_timeout = '2s';

DO $$
DECLARE n bigint;
BEGIN
    SELECT (SELECT count(delete_date) FROM report.incident)
         + (SELECT count(delete_date) FROM report.inquiry)
         + (SELECT count(delete_date) FROM report.inquiry_sample)
         + (SELECT count(delete_date) FROM report.recovery)
         + (SELECT count(delete_date) FROM report.recovery_sample)
      INTO n;
    IF n <> 0 THEN
        RAISE EXCEPTION 'expected no row with delete_date set, found %; stopping', n;
    END IF;
END
$$;

DO $$
DECLARE
    before text := pg_get_functiondef('data.model_risk_2026_3_rows(boolean, boolean, boolean, boolean, boolean, boolean)'::regprocedure);
    after text := regexp_replace(before, '\n\s*AND rs\.delete_date IS NULL[ \t]*(?=\n)', '');
BEGIN
    IF after = before OR after ~ 'delete_date' THEN
        RAISE EXCEPTION 'data.model_risk_2026_3_rows does not name delete_date as expected; stopping';
    END IF;
    EXECUTE after;
END
$$;

ALTER TABLE report.incident DROP COLUMN delete_date;
ALTER TABLE report.inquiry DROP COLUMN delete_date;
ALTER TABLE report.inquiry_sample DROP COLUMN delete_date;
ALTER TABLE report.recovery DROP COLUMN delete_date;
ALTER TABLE report.recovery_sample DROP COLUMN delete_date;
