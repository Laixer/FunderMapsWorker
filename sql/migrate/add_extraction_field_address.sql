-- Phase B: a proposed value can belong to one address of a multi-address report.
--
-- report.inquiry_sample is per address; the pipeline used to propose one set of
-- values per document ("hoofdadres"). Now a reading may carry rows per address
-- the report examines: cracks, skew, thresholds, levels. address_text is what
-- the report wrote; address_id is the geocoder row it resolved to (null when it
-- did not -- the reviewer still sees the text).
--
-- Applied to prod 2026-08-29 (doadmin owns the table).
ALTER TABLE dataops.extraction_field
  ADD COLUMN IF NOT EXISTS address_text text,
  ADD COLUMN IF NOT EXISTS address_id   geocoder.geocoder_id REFERENCES geocoder.address (id) ON DELETE SET NULL;

-- One value per (reading, field, address); document-level rows have no address.
ALTER TABLE dataops.extraction_field
  DROP CONSTRAINT IF EXISTS extraction_field_extraction_id_field_value_key;
CREATE UNIQUE INDEX IF NOT EXISTS extraction_field_reading_field_value_addr_idx
  ON dataops.extraction_field (extraction_id, field, value, coalesce(address_text, ''));

CREATE INDEX IF NOT EXISTS extraction_field_address_idx
  ON dataops.extraction_field (address_id) WHERE address_id IS NOT NULL;
