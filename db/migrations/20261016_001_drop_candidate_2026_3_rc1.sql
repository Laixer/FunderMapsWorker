-- Drop the first model-2026.3 candidate (model-2026.3-rc1), now that model-2026.3 is the default.
--
-- What it was: 20260923_002 (edited in place by 20260928_003 and 20260928_004) computed the
-- QuickScan rules for the panden with a QuickScan class only, into data.model_risk_2026_3, with a diff
-- against model-2024.1 in data.model_compare_2026_3, refreshed by hand with
-- CALL data.refresh_model_risk_2026_3(). 20261012_002 built the first national 2026.3 on top of it;
-- 20261015_004 replaced that with the full model to the spec #283 (data.model_risk_2026_3_rows), which
-- became the default with 20261015_005 on 2026-10-16.
--
-- Nothing uses these objects any more (prod, 2026-10-16, read-only): no view or function depends on
-- the two tables or the compute function except the candidate's own refresh procedure, and no
-- repository names them outside the old migrations and schema.sql. The tables hold derived candidate
-- output (2.5 MB and 0.9 MB) that nobody refreshes since 2026-10-02. No CASCADE: if something does
-- depend on them by now, this file fails and rolls back.
--
-- The registry row stays, as history, with status retired.

DROP PROCEDURE data.refresh_model_risk_2026_3();
DROP FUNCTION data.model_risk_2026_3_compute(boolean);
DROP TABLE data.model_compare_2026_3;
DROP TABLE data.model_risk_2026_3;

UPDATE data.model_version
   SET status = 'retired',
       notes = notes || ' Retired 2026-10-16: replaced by model-2026.3 (20261015_004, the default since 20261015_005); its table, diff table, compute function and refresh procedure were dropped by 20261016_001.'
 WHERE slug = 'model-2026.3-rc1';
