-- Everything in these schemas is owned by `fundermaps` (Yorick, 2026-09-20).
--
-- Why this file exists. The ledger runner applies as doadmin, so anything a
-- migration creates ends up owned by doadmin unless the file says otherwise.
-- That is how the 2026.2 candidate tables came out unreadable for the ETL role
-- an hour ago (20260920_002 fixed those two), and it is the same reason the
-- whole dataops schema and the Better Auth tables sit on doadmin today: they
-- were created by a superuser and never handed over.
--
-- Ownership is not the same as access: ALTER TABLE ... OWNER TO keeps every
-- existing GRANT, so the API, webservice and Windmill roles keep exactly the
-- rights they have now. What changes is who may alter the object, and that the
-- fingerprint in schema.sql stops depending on which role happened to run.
--
-- doadmin remains superuser and can still write application.schema_migrations,
-- so the runner keeps working after this file.

ALTER TABLE application.jwks OWNER TO fundermaps;
ALTER TABLE application.oauth_access_token OWNER TO fundermaps;
ALTER TABLE application.oauth_application OWNER TO fundermaps;
ALTER TABLE application.oauth_client_assertion OWNER TO fundermaps;
ALTER TABLE application.oauth_client_resource OWNER TO fundermaps;
ALTER TABLE application.oauth_consent OWNER TO fundermaps;
ALTER TABLE application.oauth_refresh_token OWNER TO fundermaps;
ALTER TABLE application.oauth_resource OWNER TO fundermaps;
ALTER TABLE application.schema_migrations OWNER TO fundermaps;
ALTER TABLE dataops.artifact OWNER TO fundermaps;
ALTER TABLE dataops.artifact_page OWNER TO fundermaps;
ALTER TABLE dataops.dossier OWNER TO fundermaps;
ALTER TABLE dataops.dossier_address OWNER TO fundermaps;
ALTER TABLE dataops.dossier_entry OWNER TO fundermaps;
ALTER TABLE dataops.dossier_mail OWNER TO fundermaps;
ALTER TABLE dataops.extraction OWNER TO fundermaps;
ALTER TABLE dataops.extraction_field OWNER TO fundermaps;
ALTER TABLE dataops.verdict OWNER TO fundermaps;
ALTER SEQUENCE dataops.artifact_id_seq OWNER TO fundermaps;
ALTER SEQUENCE dataops.dossier_address_id_seq OWNER TO fundermaps;
ALTER SEQUENCE dataops.dossier_entry_id_seq OWNER TO fundermaps;
ALTER SEQUENCE dataops.dossier_id_seq OWNER TO fundermaps;
ALTER SEQUENCE dataops.dossier_mail_id_seq OWNER TO fundermaps;
ALTER SEQUENCE dataops.dossier_reference_seq OWNER TO fundermaps;
ALTER SEQUENCE dataops.extraction_field_id_seq OWNER TO fundermaps;
ALTER SEQUENCE dataops.extraction_id_seq OWNER TO fundermaps;
ALTER SEQUENCE dataops.verdict_id_seq OWNER TO fundermaps;
