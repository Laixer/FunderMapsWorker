-- One-shot: drop application.portal (applied to prod 2026-07-22).
--
-- Legacy incident-portal lookup (FIR-id prefix → portal name). Its only
-- consumer was C# IncidentRepository in the non-deployed WebApi; the running
-- C# Webservice component ships only Oops/Product/Version controllers, and
-- the Bun stack never read it. Zero scans and zero writes over the stats
-- window. Incident intake lives in FunderMapsApi now.
--
-- Row snapshot (15 rows, for rollback):
--   (10,'Fundermaps'),(20,'Fundermaps'),(21,'Schiedam'),(22,'Veenweide Fryslan'),
--   (23,'Regiodeal'),(24,'Lansingerland'),(25,'Lingewaard'),(26,'Dordrecht'),
--   (27,'Arnhem'),(28,'Gouda'),(29,'Haarlem'),(30,'Rivierengebied'),
--   (31,'Woerden'),(62,'KCAF'),(99,'Feedback')

DROP TABLE IF EXISTS application.portal;
