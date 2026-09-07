-- One-shot: WebAuthn credentials for the Better Auth passkey plugin
-- (@better-auth/passkey 1.7.3). Column names are snake_case; the API's Drizzle
-- properties carry the plugin's camelCase field keys.
--
-- Run as fundermaps so the schema's default privileges (fundermaps_webapp
-- CRUD, fundermaps_webservice + grafana SELECT) apply. Applied to prod
-- 2026-09-07, before the API deploy that enables the plugin.
CREATE TABLE application.passkey (
    id            text        PRIMARY KEY,
    name          text,
    public_key    text        NOT NULL,
    user_id       uuid        NOT NULL REFERENCES application."user"(id) ON DELETE CASCADE,
    credential_id text        NOT NULL,
    counter       integer     NOT NULL,
    device_type   text        NOT NULL,
    backed_up     boolean     NOT NULL,
    transports    text,
    created_at    timestamp   DEFAULT now(),
    aaguid        text
);
CREATE INDEX passkey_user_id_idx ON application.passkey (user_id);
CREATE UNIQUE INDEX passkey_credential_id_key ON application.passkey (credential_id);
COMMENT ON TABLE application.passkey IS 'WebAuthn credentials (Better Auth passkey plugin). One row per registered passkey; rpID fundermaps.com.';

-- The schema's ALTER DEFAULT PRIVILEGES did not cover this (verified: only the
-- owner had rights after CREATE), so grant explicitly like the other BA tables.
GRANT SELECT, INSERT, UPDATE, DELETE ON application.passkey TO fundermaps_webapp;
GRANT SELECT ON application.passkey TO fundermaps_webservice;
GRANT SELECT (id, name, user_id, device_type, backed_up, created_at, aaguid) ON application.passkey TO grafana;
