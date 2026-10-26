-- Drop model candidate 2026.1 (Yorick 2026-10-26, cleanup step 2 of the repo audit: "Do 2.").
--
-- What it was: a probabilistic foundation-type candidate built by hand from sql/model/candidate_2026_1_*.sql
-- (before the model registry existed): an observation selection (data.building_sample_2026_1), a fitted
-- lookup per feature cell (data.foundation_type_lookup_2026_1, with the cell functions data.ft_cell_2026_1
-- and data.ft_cell_coarse_2026_1) and a one-off frozen-vs-candidate comparison (data.model_compare_2026_1).
-- Its successors are model-2026.2-rc1/rc2 and the default model-2026.3.
--
-- Nothing uses these objects (prod, 2026-10-26, read-only): no view, materialized view or function outside
-- the five depends on or mentions them; no mapset, layer or registry row refers to 2026.1; no live Windmill
-- script or flow, and no repository outside their own SQL files names them (Fundie's generated schema map
-- lists them, nothing more). Their own comments: "Served to nobody", "Not served, not refreshed. Drop freely".
-- Size: about 2.2 GB (model_compare_2026_1 2163 MB, building_sample_2026_1 45 MB, the lookup 584 kB).
-- No CASCADE: if something depends on them by now, this file fails and rolls back.

SET LOCAL lock_timeout = '2s';

DROP MATERIALIZED VIEW data.building_sample_2026_1;
DROP TABLE data.model_compare_2026_1;
DROP TABLE data.foundation_type_lookup_2026_1;
DROP FUNCTION data.ft_cell_2026_1(integer, double precision, text, numeric, numeric, integer);
DROP FUNCTION data.ft_cell_coarse_2026_1(text);
