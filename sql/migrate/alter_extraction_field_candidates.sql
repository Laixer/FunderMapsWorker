-- One reading may now propose several candidates for one field.
--
-- damage_cause and damage_characteristics come back as a list (a report names
-- more than one cause; the reviewer picks). The original UNIQUE (extraction_id,
-- field) made the second candidate a constraint violation, which the
-- 2026-08-29 round-2 re-read hit on 26 dossiers. The invariant that still
-- holds is that a reading does not propose the same value twice for a field.
--
-- Applied to prod 2026-08-29 (doadmin owns the table).
ALTER TABLE dataops.extraction_field
  DROP CONSTRAINT IF EXISTS extraction_field_extraction_id_field_key;
ALTER TABLE dataops.extraction_field
  ADD CONSTRAINT extraction_field_extraction_id_field_value_key UNIQUE (extraction_id, field, value);
