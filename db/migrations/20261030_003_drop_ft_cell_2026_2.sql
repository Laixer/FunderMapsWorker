-- Drop the cell functions of model candidate 2026.2-rc1 (Yorick 2026-10-30: "Those ft_cell functions can go").
--
-- data.ft_cell_2026_2() turns a building's era, height, soil, ground level and address count into rc1's
-- feature cell; data.ft_cell_coarse_2026_2() maps such a cell to its coarse form. 20260920_001 created both
-- for rc1; 20261030_002 dropped rc1's tables and retired its registry row, and left these two in place.
--
-- Nothing uses them (prod, 2026-10-30, read-only): no view, function, default or constraint depends on or
-- names them, they do not call each other, and no live Windmill script or flow and no repository names them
-- outside schema.sql and that migration's comment. Plain SQL functions owned by fundermaps, default ACL.
-- No CASCADE: if something depends on them by now, this file fails and rolls back.

SET LOCAL lock_timeout = '2s';

DROP FUNCTION data.ft_cell_2026_2(integer, double precision, text, numeric, integer);
DROP FUNCTION data.ft_cell_coarse_2026_2(text);
