-- Data Ops phase 2 — the front door, and the loop that keeps it fed.
--
-- What this is for: a document arrives, we work out what it is, read what we
-- can, and hand a human either a finished answer to confirm or a document the
-- machine could not help with. Nothing here decides anything on its own; every
-- value still has to pass a person before it reaches report.inquiry_sample.
--
-- The shape is not a guess. It follows what a 1,200-document benchmark and a
-- 118-report extraction run turned up (docs/dataops-pipeline.md, §11):
--
--   * Two lanes, not one. Scanned drawings must be READ (vision, one field,
--     ~$2.89/1000). Born-digital bureau reports must be EXTRACTED (text, six
--     fields at 86-98%, ~$6.78/1000). The same document type contains both --
--     42 of 160 `foundation_research` files are scans -- so the lane is chosen
--     from the artifact, never from report.inquiry.type.
--
--   * A quarter of what we file as evidence contains none. 110 of 199 wood
--     archive documents are a photograph of the house; the model scored 2% on
--     those and 73-89% on real archive material. Classifying the page first and
--     routing photographs straight to a human is most of the value here, and it
--     costs $0.0009 a page.
--
--   * Models fabricate, rarely and silently. One groundwater level in 39 had no
--     support anywhere in the report. Indistinguishable from the other 38
--     without checking the source -- so every extracted value carries its own
--     evidence quote and page number, and nothing is auto-accepted without one.
--
--   * The label supply stops the day this works. Today's training data is the
--     invoerder's cover sheet; once the pipeline reads documents instead, no
--     more cover sheets get made. dataops.verdict exists so that every human
--     confirmation and correction is stored as a label from the first day of
--     operation, not retrofitted after a year of signal has been thrown away.
--
-- Additive only. Nothing reads these tables yet and no existing table is
-- touched. Reversible with `DROP SCHEMA dataops CASCADE`.
--
-- NOTE: creating a schema requires superuser on this cluster; run as doadmin.
--
--   psql "$DB_URL" -f sql/migrate/create_dataops_ingest.sql

BEGIN;

CREATE SCHEMA IF NOT EXISTS dataops;

-- ---------------------------------------------------------------------------
-- vocabularies
-- ---------------------------------------------------------------------------

-- Where a dossier came in. Format is orthogonal to this: an email can carry a
-- PDF, an upload can be a zip of images.
CREATE TYPE dataops.intake_channel AS ENUM (
    'email', 'upload', 'bulk_drop', 'api', 'invoer_app'
);

-- What a page actually shows, decided by a cheap vision pass before any
-- extraction is attempted. This is the routing key, and the reason the
-- expensive lanes never see a photograph.
CREATE TYPE dataops.material AS ENUM (
    'drawing',          -- oude bouwtekening: plattegrond, doorsnede, palenplan
    'archive_document', -- archiefstuk: brief, vergunning, bestek, formulier
    'report',           -- born-digital bureau report with a text layer
    'photo',            -- a picture of the building; carries no foundation data
    'map',              -- kadastrale kaart, situatietekening, luchtfoto
    'blank',            -- nothing legible
    'other'
);

-- How the artifact was read. Recorded because the two lanes have different
-- costs, different failure modes and different accuracy, and a score that
-- mixes them is meaningless.
CREATE TYPE dataops.read_lane AS ENUM ('vision', 'text', 'none');

-- Where a proposed value is in its life.
CREATE TYPE dataops.review_state AS ENUM (
    'pending',          -- waiting for a human
    'auto_accepted',    -- legacy: cleared a confidence gate that no longer exists (gone 2026-08-26); treat as pending
    'confirmed',        -- a human looked and agreed
    'corrected',        -- a human looked and changed it   <- the useful label
    'rejected',         -- a human says the document does not support any value
    'superseded'        -- a later extraction replaced this one
);

-- ---------------------------------------------------------------------------
-- dossier — one submission, one subject
-- ---------------------------------------------------------------------------
CREATE TABLE dataops.dossier (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    channel         dataops.intake_channel NOT NULL,

    -- Free-text identity as delivered. Deliberately not parsed on the way in:
    -- resolving an address is a later stage that can fail without losing the
    -- submission.
    subject         text,
    external_ref    text,

    -- Duplicate deliveries are structural, not errors: a bureau and the
    -- receiving corporation each send the same report. 11,346 deliveries hold
    -- 6,157 cleanly mergeable pairs. Byte hashing does not find them (the files
    -- differ), so this points at a dossier judged to be the same submission and
    -- lets both keep their own provenance.
    duplicate_of    bigint REFERENCES dataops.dossier (id),

    -- Set once the dossier has been committed into the report schema.
    inquiry_id      integer,

    received_at     timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at      timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON COLUMN dataops.dossier.duplicate_of IS
    'Same submission arriving twice through different senders. Structural, not an error -- see docs/dataops-pipeline.md.';

-- ---------------------------------------------------------------------------
-- artifact — one file, nesting for email -> attachment
-- ---------------------------------------------------------------------------
CREATE TABLE dataops.artifact (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dossier_id          bigint NOT NULL REFERENCES dataops.dossier (id) ON DELETE CASCADE,
    parent_artifact_id  bigint REFERENCES dataops.artifact (id) ON DELETE CASCADE,

    -- Where the untouched original lives. Spaces keeps the file we were sent;
    -- this schema never stores document bytes.
    storage_key         text NOT NULL,
    original_filename   text,

    -- Sniffed, never trusted from the extension. Batch 1 of the feedback corpus
    -- already held a .png with a soft hyphen in its name and three different
    -- JSON shapes.
    mime_type           text,
    size_bytes          bigint,
    page_count          integer,

    lane                dataops.read_lane NOT NULL DEFAULT 'none',

    -- Text the human who prepared this file added on top of the source: a
    -- cover sheet, or three typed lines above a scan. It states their answer,
    -- so it must never reach a model -- but it is worth keeping, because on
    -- historical documents it IS the label.
    -- 1,896 of 4,806 benchmark pages carried some.
    annotation_text     text,
    annotation_pages    integer[],

    created_at          timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX artifact_dossier_idx ON dataops.artifact (dossier_id);
CREATE INDEX artifact_parent_idx  ON dataops.artifact (parent_artifact_id)
    WHERE parent_artifact_id IS NOT NULL;

COMMENT ON COLUMN dataops.artifact.annotation_text IS
    'The preparer''s own summary, lifted off the document. Withheld from every model; kept because on historical files it is the training label.';

-- ---------------------------------------------------------------------------
-- artifact_page — what each page is, decided before anything expensive runs
-- ---------------------------------------------------------------------------
CREATE TABLE dataops.artifact_page (
    artifact_id     bigint NOT NULL REFERENCES dataops.artifact (id) ON DELETE CASCADE,
    page_no         integer NOT NULL,

    material        dataops.material,
    material_conf   numeric(4,3),

    -- true once the page has been through redaction and carries no preparer
    -- annotation. A page that cannot be vouched for is not sent to a model:
    -- unknown must never default to clean.
    is_clean        boolean NOT NULL DEFAULT false,
    redacted_boxes  integer NOT NULL DEFAULT 0,

    text_chars      integer,

    PRIMARY KEY (artifact_id, page_no)
);

COMMENT ON TABLE dataops.artifact_page IS
    'Page-level triage. Routing photographs and blanks to a human before extraction is the cheapest accuracy this pipeline has: 2% vs 73-89% on the same field.';

-- ---------------------------------------------------------------------------
-- extraction — one model pass over one artifact
-- ---------------------------------------------------------------------------
CREATE TABLE dataops.extraction (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    artifact_id     bigint NOT NULL REFERENCES dataops.artifact (id) ON DELETE CASCADE,

    -- Provenance, for the same reason data.model_version records it: without
    -- knowing which model and which prompt produced a value, a later
    -- disagreement is unreadable -- did the model change, or the document?
    model           text NOT NULL,
    prompt_version  text NOT NULL,
    lane            dataops.read_lane NOT NULL,

    pages_sent      integer,
    input_tokens    integer,
    output_tokens   integer,
    cost_usd        numeric(10,6),

    started_at      timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at     timestamptz,
    error           text
);

CREATE INDEX extraction_artifact_idx ON dataops.extraction (artifact_id);

-- ---------------------------------------------------------------------------
-- extraction_field — one proposed value, with the evidence for it
-- ---------------------------------------------------------------------------
CREATE TABLE dataops.extraction_field (
    id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    extraction_id   bigint NOT NULL REFERENCES dataops.extraction (id) ON DELETE CASCADE,

    -- Column name in report.inquiry_sample, so a confirmed value can be written
    -- straight through without a translation table drifting out of date.
    field           text NOT NULL,
    value           text,
    confidence      numeric(4,3),

    -- Non-negotiable. One groundwater level in 39 was fabricated and looked
    -- exactly like the 38 real ones. A value that cannot point at the sentence
    -- it came from does not get auto-accepted, whatever its confidence.
    evidence        text,
    evidence_page   integer,

    state           dataops.review_state NOT NULL DEFAULT 'pending',

    UNIQUE (extraction_id, field, value)   -- was (extraction_id, field); see alter_extraction_field_candidates.sql
);

CREATE INDEX extraction_field_state_idx ON dataops.extraction_field (state)
    WHERE state = 'pending';

COMMENT ON COLUMN dataops.extraction_field.evidence IS
    'The passage the value was read from. Required for auto-accept: fabrications are rare, silent, and otherwise indistinguishable from correct answers.';

-- ---------------------------------------------------------------------------
-- verdict — what the human decided. This is the training set.
-- ---------------------------------------------------------------------------
CREATE TABLE dataops.verdict (
    id                  bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    extraction_field_id bigint NOT NULL REFERENCES dataops.extraction_field (id) ON DELETE CASCADE,

    decided_by          uuid,
    decided_at          timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,

    outcome             dataops.review_state NOT NULL,

    -- What the human put instead. When outcome = 'corrected' this pair --
    -- (proposed, final) against a known document -- is exactly the training
    -- example that the cover-sheet era used to give us for free.
    final_value         text,
    note                text,

    -- Seconds the reviewer spent. The business case is "how much invoerder time
    -- did this save", and that cannot be argued without measuring it.
    review_seconds      integer,

    CHECK (outcome <> 'pending')
);

CREATE INDEX verdict_field_idx ON dataops.verdict (extraction_field_id);
CREATE INDEX verdict_decided_idx ON dataops.verdict (decided_at DESC);

COMMENT ON TABLE dataops.verdict IS
    'Every human confirmation and correction, kept as a labelled example. Today''s labels come from cover sheets an invoerder writes before uploading; once this pipeline reads documents instead, nobody writes those any more and this table becomes the only source of new training data.';

COMMIT;
