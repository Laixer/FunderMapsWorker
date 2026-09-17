-- One 'reviewer' extraction per artifact.
--
-- "Waarde toevoegen" (API #175) hangs the reviewer's own values on one
-- extraction with model = 'reviewer' per dossier, created on first use and
-- looked up by (artifact, model) on every later add. Two adds racing on the
-- same dossier each saw no row and created their own (API #180 fixed the
-- transaction but not the race). Model extractions keep several rows per
-- artifact (every re-read is one), so the constraint is partial.
--
-- Prod 2026-09-17: 1 reviewer extraction, no duplicates. Idempotent.
CREATE UNIQUE INDEX IF NOT EXISTS extraction_reviewer_once
  ON dataops.extraction (artifact_id)
  WHERE model = 'reviewer';
