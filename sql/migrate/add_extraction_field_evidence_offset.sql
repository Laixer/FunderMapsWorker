-- ClientApp #333 point 2 (Don, 2026-09-10): show proposals in the order they
-- occur in the report, not alphabetically by column name.
--
-- The model answers a fixed JSON schema, so nothing about its output order
-- says where a value sat in the document. The citation does: at ingest the
-- Worker now finds each citation in the pdftotext output and records the page
-- (evidence_page, existed but was never written) and the character offset.
-- The API orders a dossier's proposals by (address_text, evidence_offset,
-- evidence_page, id); nulls sort last, so rows read before this change keep
-- their old order until re-read.
--
-- Apply order: this DDL, then FunderMapsApi (orders on the column), then the
-- Worker (writes it). Additive, no backfill.

ALTER TABLE dataops.extraction_field
  ADD COLUMN IF NOT EXISTS evidence_offset integer;

COMMENT ON COLUMN dataops.extraction_field.evidence_page IS
  'Page the citation was found on (1-based), located at ingest in the pdftotext output. Null when not found or when the lane has no text.';
COMMENT ON COLUMN dataops.extraction_field.evidence_offset IS
  'Character offset of the citation in the pdftotext output, located at ingest. The document-order key; null sorts last.';
