-- Phase F.1: rename misspelled report.pile_type enum value.
--   intgernally_driven  →  internally_driven
--
-- Coordinated with C# enum member rename
-- (FunderMaps.Core.Types.PileType.IntgernallyDriven → InternallyDriven).
-- Npgsql default name translator maps PascalCase ↔ snake_case, so
-- both sides must rename together.
--
-- ALTER TYPE ... RENAME VALUE is atomic and metadata-only — enums
-- are stored as integers internally; the on-disk values don't move.
-- Run as: fundermaps (owner)

ALTER TYPE report.pile_type RENAME VALUE 'intgernally_driven' TO 'internally_driven';
