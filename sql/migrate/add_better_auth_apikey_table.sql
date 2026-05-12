-- Schema additions required by the Better Auth `@better-auth/api-key`
-- plugin (https://better-auth.com/docs/plugins/api-key).
--
-- We adopt the plugin in *dual-stack* mode: the legacy application.auth_key
-- table stays as the source of truth for existing `fmsk.`-prefixed keys
-- (paying customers; the C# Webservice reads it directly via raw SQL until
-- Dec 2026). New keys land in application.apikey via the plugin. The
-- coexistence and per-consumer cutover are documented in
-- project_better_auth_migration.md (Step 5).
--
-- Field shapes mirror the plugin's apiKeySchema declaration verbatim
-- (node_modules/@better-auth/api-key/dist/index.mjs:1939). Three indexes
-- match the plugin's declared `index: true` fields — `key` is the hot
-- lookup on every API-key request, `reference_id` is the join for
-- list-by-user, `config_id` partitions configs in the multi-config case
-- (single config today).
--
-- Cross-stack coordination: the matching Drizzle schema edit lands in
-- FunderMapsApi src/db/schema/application.ts (feat/better-auth-api-key-
-- plugin); the BA plugin is mounted in src/lib/auth.ts in the same PR.
-- No consumer middleware reads from application.apikey yet — adoption
-- happens in Phase B per the migration plan.

BEGIN;

CREATE TABLE application.apikey (
    id                       text PRIMARY KEY,
    config_id                text NOT NULL DEFAULT 'default',
    name                     text,
    start                    text,
    reference_id             uuid NOT NULL
        REFERENCES application."user"(id) ON DELETE CASCADE,
    prefix                   text,
    key                      text NOT NULL,
    refill_interval          integer,
    refill_amount            integer,
    last_refill_at           timestamp with time zone,
    enabled                  boolean DEFAULT true,
    rate_limit_enabled       boolean DEFAULT true,
    rate_limit_time_window   integer,
    rate_limit_max           integer,
    request_count            integer DEFAULT 0,
    remaining                integer,
    last_request             timestamp with time zone,
    expires_at               timestamp with time zone,
    created_at               timestamp with time zone NOT NULL,
    updated_at               timestamp with time zone NOT NULL,
    permissions              text,
    metadata                 text
);

CREATE INDEX apikey_config_id_idx    ON application.apikey (config_id);
CREATE INDEX apikey_reference_id_idx ON application.apikey (reference_id);
CREATE INDEX apikey_key_idx          ON application.apikey (key);

COMMIT;
