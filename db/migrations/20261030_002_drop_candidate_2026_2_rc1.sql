-- Drop the tables of model candidate 2026.2-rc1 and retire its registry row (Yorick 2026-10-30: "This can go").
--
-- What it was: 20260920_001 built rc1, a probabilistic foundation-type candidate: smoothed class rates per
-- feature cell (data.foundation_type_prior_2026_2), a refit of the 2026.1 lookup on evidence-backed truth
-- (data.foundation_type_lookup_2026_2), and its output on the evaluation sample (data.foundation_type_2026_2,
-- 302,261 rows). rc2 (data.model_foundation_2026_2, 20260928_002) replaced it; rc2 is not touched here.
--
-- Nothing uses these tables (prod, 2026-10-30, read-only): no view, function, foreign key or default depends
-- on or names them; no mapset or layer refers to rc1 (the 2026.2 candidate mapset is rc2's); no live Windmill
-- script or flow and no repository names them, apart from sql/validate/candidate_2026_2_scores.sql (removed
-- with this file) and Fundie's generated schema map. Size: 57 MB. No CASCADE: if something depends on them
-- by now, this file fails and rolls back.
--
-- rc1's cell functions data.ft_cell_2026_2 and data.ft_cell_coarse_2026_2 stay for now.
-- The registry row stays, as history, with status retired.

SET LOCAL lock_timeout = '2s';

DROP TABLE data.foundation_type_2026_2;
DROP TABLE data.foundation_type_lookup_2026_2;
DROP TABLE data.foundation_type_prior_2026_2;

UPDATE data.model_version
   SET status = 'retired',
       notes = notes || ' Retired 2026-10-30: superseded by model-2026.2-rc2; its tables foundation_type_2026_2, foundation_type_lookup_2026_2 and foundation_type_prior_2026_2 were dropped by 20261030_002.'
 WHERE slug = 'model-2026.2-rc1';
