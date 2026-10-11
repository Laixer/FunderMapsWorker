-- The verdict per rapportage of a dossier: dataops.dossier_rapportage (Don, 2026-10-09).
--
-- Since API #232 one melding can be committed as several rapportages, one per
-- group of documents. The verdict lives on the dossier only (dossier.outcome +
-- outcome_note), so "Inquiry 1 accepted, Inquiry 2 rejected" cannot be
-- recorded: an accepted group shows up only as a report.inquiry row, a
-- rejected one leaves no trace. Don wants the closing to stay one message to
-- the melder while the assessment and processing happen per rapportage, and
-- the database to know which was accepted and which refused, and why.
--
-- One row per group the reviewer formed at commit: its number in the dossier,
-- its documents, its panden, the verdict, the standard answer that goes into
-- the closing mail, and the inquiry it became (NULL when rejected).
--
-- On prod 2026-10-09 (read-only): dataops.dossier.id is bigint,
-- report.inquiry.id integer, application.user.id uuid; fundermaps_webapp
-- (fundermaps_api is a member) writes the other dataops tables.

CREATE TABLE dataops.dossier_rapportage (
    id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dossier_id   bigint NOT NULL REFERENCES dataops.dossier(id) ON DELETE CASCADE,
    n            integer NOT NULL CHECK (n > 0),
    artifact_ids bigint[] NOT NULL,
    address_ids  text[],
    verdict      text NOT NULL CHECK (verdict IN ('accepted', 'rejected')),
    answer       text,
    inquiry_id   integer REFERENCES report.inquiry(id) ON DELETE SET NULL,
    decided_by   uuid REFERENCES application."user"(id) ON DELETE SET NULL,
    decided_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT dossier_rapportage_once UNIQUE (dossier_id, n),
    CONSTRAINT dossier_rapportage_rejected_has_no_inquiry CHECK (verdict = 'accepted' OR inquiry_id IS NULL)
);

CREATE INDEX dossier_rapportage_inquiry_idx ON dataops.dossier_rapportage (inquiry_id) WHERE inquiry_id IS NOT NULL;

COMMENT ON TABLE dataops.dossier_rapportage IS
'The verdict per rapportage of a dossier (Don, 2026-10-09). One row per group of documents the reviewer formed at commit; the closing mail combines the answers into one message to the melder.';
COMMENT ON COLUMN dataops.dossier_rapportage.n IS 'The group''s number in the dossier, as the Studio shows it (Inquiry 1, Inquiry 2, ...).';
COMMENT ON COLUMN dataops.dossier_rapportage.artifact_ids IS 'The dataops.artifact ids of the documents in this group.';
COMMENT ON COLUMN dataops.dossier_rapportage.address_ids IS 'The BAG nummeraanduidingen this rapportage is about; NULL when the reviewer chose none and the melder''s pand was used.';
COMMENT ON COLUMN dataops.dossier_rapportage.verdict IS 'accepted: the group became report.inquiry inquiry_id. rejected: nothing was taken over from it.';
COMMENT ON COLUMN dataops.dossier_rapportage.answer IS 'The standard answer (or the reviewer''s own text) for this rapportage, as it went into the closing mail.';
COMMENT ON COLUMN dataops.dossier_rapportage.inquiry_id IS 'The rapportage this group became; NULL when rejected.';

ALTER TABLE dataops.dossier_rapportage OWNER TO fundermaps;

GRANT SELECT, INSERT ON dataops.dossier_rapportage TO fundermaps_webapp;
GRANT SELECT ON dataops.dossier_rapportage TO fundermaps_windmill;
