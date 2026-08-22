-- The concrete family, for scoring only.
--
-- Don, 2026-08-22, reviewing 83 machine-read foundation types:
--
--   "Een schroefinjectiepaal is een stalen buispaal. Die wordt afgevuld met
--    beton dus behoort ook bij de funderingsfamilie betonpaal."
--   "Stalen buispalen is ook een type. Maar die worden volgestort met beton.
--    Dus betonpaal is ook juist."
--
-- Every family-level accuracy figure quoted so far folded `wood*` into wood and
-- `no_pile*` into no_pile, and left everything else standing alone -- so a
-- document read as `steel_pile` against a human's `concrete` counted as a
-- family miss when the two describe the same thing. Those figures were wrong in
-- our favour.
--
-- Deliberately NOT extended to:
--   weighted_pile  a verzwaardepuntpaal is usually concrete, but Don did not
--                  say so and I am not inferring domain rules he did not give.
--   combined       means several types under one building; that is genuinely
--                  its own case, not a member of any family.
--
-- ADDITIVE ONLY, and it must stay that way. data.is_wood_family is called by
-- compute_indicative_bio_risk and compute_restoration_costs -- both part of
-- model-2024.1, whose logic is frozen forever (docs/model-versioning.md). This
-- function is new, nothing in the model calls it, and nothing in the model may
-- start calling it. It exists so validation can group types the way a
-- foundation engineer does, without moving a single risk letter in production.
--
--   psql "$DB_URL" -f sql/migrate/create_is_concrete_family.sql

CREATE OR REPLACE FUNCTION data.is_concrete_family(ft report.foundation_type)
RETURNS boolean
LANGUAGE sql
IMMUTABLE PARALLEL SAFE
AS $$
    SELECT ft IN ('concrete', 'steel_pile');
$$;

COMMENT ON FUNCTION data.is_concrete_family(report.foundation_type) IS
    'Scoring only. A grouted steel tube pile is a concrete foundation (Don, 2026-08-22). Never call this from a model function: model-2024.1 is frozen.';
