-- One-shot: the Grafana "Intake pipeline" board reads the rest of the dataops
-- schema (dossier + extraction were granted with product_tracker_daily).
-- Run as doadmin (dataops owner). Applied to prod 2026-09-07.
GRANT SELECT ON dataops.dossier_entry, dataops.dossier_mail, dataops.artifact,
                dataops.extraction_field, dataops.verdict TO grafana;
