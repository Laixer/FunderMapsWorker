-- Windmill runs the Data Ops ingest (f/fundermaps/dataops/ingest_pending,
-- every 15 minutes) as fundermaps_windmill. Everything background runs in
-- Windmill (Yorick 2026-08-28); the manual CLI stays as the escape hatch.
--
-- What the ingest touches: reads dossier/artifact, writes lane/page_count on
-- the artifact, inserts artifact_page/extraction/extraction_field, and on a
-- re-read marks earlier unjudged values superseded. It never writes verdict
-- or dossier outcome -- those are a person's.
--
-- Applied to prod 2026-09-01 (doadmin owns the tables).
GRANT USAGE ON SCHEMA dataops TO fundermaps_windmill;
GRANT SELECT ON dataops.dossier, dataops.verdict TO fundermaps_windmill;
GRANT SELECT, UPDATE (lane, page_count, mime_type, annotation_text, annotation_pages) ON dataops.artifact TO fundermaps_windmill;
GRANT SELECT, INSERT, UPDATE ON dataops.artifact_page TO fundermaps_windmill;
GRANT SELECT, INSERT ON dataops.extraction TO fundermaps_windmill;
GRANT SELECT, INSERT, UPDATE (state) ON dataops.extraction_field TO fundermaps_windmill;
GRANT USAGE ON SEQUENCE dataops.extraction_id_seq, dataops.extraction_field_id_seq TO fundermaps_windmill;
-- the resolver and the admissibility check read these
GRANT SELECT ON geocoder.address, geocoder.building TO fundermaps_windmill;
