-- The hourly Windmill sweep can finish an ingest (Worker #185).
--
-- Symptom: melding FM2026-000178 (dossier 5211) was never read. Its extraction
-- on 2026-09-18 18:04, the hour mark of f/fundermaps/dataops/ingest_pending,
-- died with `permission denied for table artifact`. The sweep is the safety net
-- for dossiers the API did not read at intake, so a failed read simply stayed
-- failed until someone noticed.
--
-- What was missing. `fundermaps_windmill` could SELECT the dossier and the
-- artifact and INSERT extractions, but ingest-dossier.ts also
--   * UPDATEs dataops.artifact       (page count, storage key, mime after normalisation)
--   * UPDATEs dataops.extraction_field (citation offsets after the page match)
-- and it had neither. The reads succeeded, the run fell over on the first write.
--
-- Deliberately not granted: INSERT on dataops.dossier. The sweep only ever
-- attaches to a dossier that already exists; creating one is the API's job.
--
-- The id columns are identity columns, so INSERT carries them; no sequence
-- grants are needed (the three USAGE grants that exist are leftovers).

GRANT UPDATE ON dataops.artifact TO fundermaps_windmill;
GRANT UPDATE ON dataops.extraction_field TO fundermaps_windmill;
