-- The nalezing: Fundie re-reads a rapportage that is already in the database
-- and a person judges only what differs (Yorick 2026-09-08: 22,776 of 29,165
-- rapportages never had a second pair of eyes; foundation_research first).
--
-- An audit is a dossier of an existing rapportage: `audit_inquiry_id` names
-- it, channel 'audit', the artifact points at the existing inquiry-report/
-- file (no copy). After the read, every proposal is compared with the
-- sample it belongs to; `current_value` keeps what the database held at
-- that moment, and a proposal that agrees lands as 'agreed' -- settled,
-- never shown as open. A dossier with nothing open closes itself.
--
-- ALTER TYPE ... ADD VALUE cannot run inside a transaction with statements
-- that use the value, so this file is deliberately not wrapped in BEGIN.

ALTER TYPE dataops.intake_channel ADD VALUE IF NOT EXISTS 'audit';
ALTER TYPE dataops.review_state ADD VALUE IF NOT EXISTS 'agreed';

ALTER TABLE dataops.dossier
  ADD COLUMN IF NOT EXISTS audit_inquiry_id integer REFERENCES report.inquiry(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS dossier_audit_inquiry_id_idx
  ON dataops.dossier (audit_inquiry_id) WHERE audit_inquiry_id IS NOT NULL;
COMMENT ON COLUMN dataops.dossier.audit_inquiry_id IS
  'The rapportage this dossier re-reads (channel audit). Null on intake dossiers.';

ALTER TABLE dataops.extraction_field
  ADD COLUMN IF NOT EXISTS current_value text;
COMMENT ON COLUMN dataops.extraction_field.current_value IS
  'On an audit: what the database held for this field when the document was read. Null = the database had nothing.';

-- The rapportage's own trail gets a kind for "Fundie re-read this and a
-- person applied N corrections": 'imported' would claim the data came from
-- outside, and it did not.
ALTER TYPE report.dossier_event_kind ADD VALUE IF NOT EXISTS 'audited';
