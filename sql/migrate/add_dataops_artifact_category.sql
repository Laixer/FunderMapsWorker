-- Keep what the sender said the document is.
--
-- The public form asks one question per file -- "wat voor document is dit?" --
-- and that answer is the single most valuable signal the pipeline receives. It
-- is already wired into providers/admissibility.ts, where
-- CATEGORY_MAY_ESTABLISH marks `quickscan` as unable to establish a foundation
-- type: a QuickScan states a type it read off FunderMaps, so extracting it is a
-- loop rather than evidence. That check is why 26 of the 27 values Don rejected
-- in the 83-document review were rejected.
--
-- The intake route was dropping it. Attachments became artifact rows carrying
-- key, filename, mime and size, and the melder's own label went nowhere -- so a
-- QuickScan arriving through the form would have been read as though nobody had
-- told us what it was.
--
-- On the artifact and not on the dossier, because a submission can carry a
-- funderingsonderzoek and a QuickScan in the same delivery, and they are not
-- admissible to the same degree.
--
-- Deliberately a claim, never a finding. The sender's label decides what the
-- pipeline is ALLOWED to conclude; it never decides what the document says.
-- Classification still reads the file itself -- 42 of 160 documents filed as
-- `foundation_research` turned out to be scans.
--
-- Additive and nullable; the 891 bulk_drop artifacts have no such label and
-- never will.
--
--   psql "$DB_URL" -f sql/migrate/add_dataops_artifact_category.sql

BEGIN;

ALTER TABLE dataops.artifact
  ADD COLUMN IF NOT EXISTS declared_category text;

COMMENT ON COLUMN dataops.artifact.declared_category IS
  'What the sender said this document is (form vocabulary: archieveresearch, foundationresearch, quickscan, herstelbewijs, foto, overig). A claim, not a finding: it bounds what the pipeline may conclude, never what the document says.';

COMMIT;
