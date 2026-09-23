-- A dossier can record a herstel: dataops.dossier.recovery_id (Studio #341).
--
-- A melding "Doorgeven herstelmaatregelen" comes with a herstel drawing or an
-- oplevering. Until now the review lane could only commit a dossier as a
-- rapportage (report.inquiry); the herstel was typed into the Studio by hand
-- and the link between dossier, document and report.recovery was lost. On
-- 2026-09-23: 35 open dossiers with that topic, 71 where the reader saw a
-- herstel.
--
-- The API's "Herstel vastleggen" (POST /api/dataops/dossier/:id/recovery)
-- creates report.recovery + one recovery_sample per pand and writes the id
-- here. It does not close the dossier: the reviewer still closes it with or
-- without a rapportage (the drawing's original foundation type is rapportage
-- material), so a dossier may carry both inquiry_id and recovery_id.
--
-- On prod 2026-09-23 fundermaps_api (member of fundermaps_webapp) already has
-- INSERT on report.recovery, report.recovery_sample, application.attribution,
-- application.file_resources and report.dossier_event; dataops.dossier has
-- column-scoped UPDATE grants, so the new column needs its own.

ALTER TABLE dataops.dossier
    ADD COLUMN recovery_id integer REFERENCES report.recovery(id) ON DELETE SET NULL;

CREATE INDEX dossier_recovery_id_idx ON dataops.dossier (recovery_id) WHERE recovery_id IS NOT NULL;

COMMENT ON COLUMN dataops.dossier.recovery_id IS
'The herstel recorded from this dossier (report.recovery). Independent of inquiry_id: a herstel drawing can yield both.';

GRANT UPDATE (recovery_id) ON dataops.dossier TO fundermaps_webapp;
