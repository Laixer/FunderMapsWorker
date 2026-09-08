-- One-shot: report.year no longer defaults to the current date.
--
-- The domain was declared `DEFAULT CURRENT_TIMESTAMP`, so any INSERT into
-- report.inquiry_sample that omitted built_year got today's date as the
-- building's bouwjaar. Found 2026-09-08 (Don's practice test, ClientApp #321):
-- 30 samples in the table carried it, every one written by the review-lane
-- commit (FunderMapsApi #160 now sets the column explicitly). Every other
-- writer sends an explicit null, which is why only those 30 existed.
--
-- A building's construction year has no sensible default. Absent is absent.
--
-- Safe to apply live: only the domain default changes; existing values,
-- the range constraint and the not-future constraint on the column are
-- untouched.

BEGIN;

ALTER DOMAIN report.year DROP DEFAULT;

-- The 30 rows that got today's date, all review-lane commits: bouwjaar back
-- to unknown. Identified by the leak's own signature (built_year equals the
-- day the row was created) plus the commit's provenance marker.
UPDATE report.inquiry_sample
   SET built_year = NULL
 WHERE built_year::date = create_date::date
   AND metadata -> 'dataops' IS NOT NULL;

COMMIT;
