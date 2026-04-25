-- Phase F.4: rename misspelled type + column.
--   report.wood_encroachement (type)              →  wood_encroachment
--   report.inquiry_sample.wood_encroachement (col) →  wood_encroachment
--
-- Coordinated with C# changes:
--   * type+enum identifier WoodEncroachement → WoodEncroachment
--   * file rename WoodEncroachement.cs → WoodEncroachment.cs
--   * entity property rename
--   * 8 SQL refs in InquirySampleRepository
--   * MapEnum<WoodEncroachement>() → MapEnum<WoodEncroachment>()
--
-- TS API: 1-line Drizzle column-name string update (field name was
-- already correct: woodEncroachment maps to text("wood_encroachement")).
--
-- ALTER TYPE ... RENAME and ALTER TABLE ... RENAME COLUMN are both
-- metadata-only operations. 530 non-null records out of 454,120
-- (verified 2026-04-25).
--
-- Run as: fundermaps (owner)

BEGIN;

ALTER TYPE report.wood_encroachement RENAME TO wood_encroachment;
ALTER TABLE report.inquiry_sample
    RENAME COLUMN wood_encroachement TO wood_encroachment;

COMMIT;
