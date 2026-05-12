-- Schema additions required by the Better Auth `admin` plugin
-- (https://better-auth.com/docs/plugins/admin).
--
-- We adopt the plugin in *supplementing* mode: the existing /api/management/*
-- middleware (FunderMapsApi src/middleware/admin.ts) stays as the gate for
-- the FunderMaps-specific management surface. What the plugin actually buys
-- us is server-side ban enforcement, admin-driven session impersonation, and
-- a standard role primitive on top of the existing application.user.role
-- column. The literal 'administrator' is kept via the plugin's `adminRoles`
-- option, so no data migration is needed.
--
-- All four added columns are nullable — existing rows stay NULL, which the
-- plugin treats as "not banned" / "not impersonated". The `impersonated_by`
-- FK uses ON DELETE SET NULL so deleting the impersonating admin doesn't
-- cascade into deleting the impersonated sessions.
--
-- Cross-stack coordination: the matching Drizzle schema edit lands in
-- FunderMapsApi src/db/schema/application.ts in the paired PR; the BA
-- plugin itself is wired in src/lib/auth.ts in the same PR. No C# changes —
-- the C# Webservice does not read application.user.role (verified 2026-05-11).

BEGIN;

ALTER TABLE application."user"
    ADD COLUMN banned      boolean,
    ADD COLUMN ban_reason  text,
    ADD COLUMN ban_expires timestamp without time zone;

ALTER TABLE application.session
    ADD COLUMN impersonated_by uuid
        REFERENCES application."user"(id)
        ON DELETE SET NULL;

COMMIT;
