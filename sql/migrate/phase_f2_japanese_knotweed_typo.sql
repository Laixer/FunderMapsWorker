-- Phase F.2: rename misspelled report.foundation_damage_cause enum value.
--   japanse_knotweed  →  japanese_knotweed
--
-- Coordinated with C# enum member rename
-- (FunderMaps.Core.Types.FoundationDamageCause.JapanseKnotweed → JapaneseKnotweed).
-- Npgsql default name translator maps PascalCase ↔ snake_case.
--
-- Wire format from C# is integer (no JsonStringEnumConverter), so frontend
-- TS enum members can be renamed independently — they're decoupled at runtime.
-- Only 3 records currently use this value (verified 2026-04-25).
--
-- Run as: fundermaps (owner)

ALTER TYPE report.foundation_damage_cause RENAME VALUE 'japanse_knotweed' TO 'japanese_knotweed';
