-- Better Auth migration Phase 2 (org plugin) — additive schema prep.
-- Companion to FunderMaps#1006: per-org configurable rights land via BA's
-- organization plugin + dynamic access control; this migration creates the
-- tables/columns BA 1.6.x expects so the plugin can be wired with schema
-- overrides onto the EXISTING org tables (no dual-write, no data moves).
--
-- Everything here is additive and therefore safe while the C# Webservice is
-- still alive (EOL end of Aug 2026): C# only reads columns that keep existing.
-- Destructive follow-ups (role enum→text for custom roles, auth_key drop)
-- explicitly wait for that EOL.
--
-- Naming note: BA's "organizationRole" model maps to
-- application.organization_custom_role because application.organization_role
-- is already taken by the role ENUM TYPE (a table would collide in pg_type).
--
-- Run as the `fundermaps` role (owner of application.*). Idempotent — safe
-- to re-run.
--   psql "$DB_URL" -f sql/migrate/add_better_auth_org_schema.sql

BEGIN;

-- ── organization: BA model fields (slug/logo/metadata/created_at) ─────────

ALTER TABLE application.organization
  ADD COLUMN IF NOT EXISTS slug text,
  ADD COLUMN IF NOT EXISTS logo text,
  ADD COLUMN IF NOT EXISTS metadata jsonb,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

-- Backfill slug from name: lowercase, non-alnum runs → '-', trimmed. On the
-- rare collision, disambiguate with the first id block (stable + readable).
UPDATE application.organization o
SET slug = sub.slug || CASE WHEN sub.dup > 1 THEN '-' || split_part(o.id::text, '-', 1) ELSE '' END
FROM (
  SELECT id,
         btrim(regexp_replace(lower(name), '[^a-z0-9]+', '-', 'g'), '-') AS slug,
         count(*) OVER (PARTITION BY btrim(regexp_replace(lower(name), '[^a-z0-9]+', '-', 'g'), '-')) AS dup
  FROM application.organization
) sub
WHERE o.id = sub.id AND o.slug IS NULL;

ALTER TABLE application.organization ALTER COLUMN slug SET NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS organization_slug_idx
  ON application.organization (slug);

-- ── organization_user: single-column id for the BA adapter ────────────────
-- BA's `member` model maps onto this table (schema override). The composite
-- PK (user_id, organization_id) stays; BA just needs a unique scalar id.

ALTER TABLE application.organization_user
  ADD COLUMN IF NOT EXISTS id uuid NOT NULL DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

CREATE UNIQUE INDEX IF NOT EXISTS organization_user_id_idx
  ON application.organization_user (id);

-- ── session: BA org plugin tracks the active organization per session ─────

ALTER TABLE application.session
  ADD COLUMN IF NOT EXISTS active_organization_id application.organization_id
    REFERENCES application.organization (id) ON DELETE SET NULL;

-- ── invitation: new (BA-managed org invites) ──────────────────────────────

CREATE TABLE IF NOT EXISTS application.invitation (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    organization_id application.organization_id NOT NULL
      REFERENCES application.organization (id) ON DELETE CASCADE,
    email text NOT NULL,
    role text NOT NULL DEFAULT 'reader',
    status text NOT NULL DEFAULT 'pending'
      CHECK (status IN ('pending', 'accepted', 'rejected', 'canceled')),
    team_id uuid,
    inviter_id application.user_id NOT NULL
      REFERENCES application."user" (id),
    expires_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE application.invitation IS
  'Better Auth organization-plugin invitations (Phase 2).';

CREATE INDEX IF NOT EXISTS invitation_organization_id_idx
  ON application.invitation (organization_id);

-- ── organization_custom_role: new (BA dynamic access control, #1006) ──────

CREATE TABLE IF NOT EXISTS application.organization_custom_role (
    id uuid DEFAULT gen_random_uuid() NOT NULL PRIMARY KEY,
    organization_id application.organization_id NOT NULL
      REFERENCES application.organization (id) ON DELETE CASCADE,
    role text NOT NULL,
    permission jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz,
    UNIQUE (organization_id, role)
);

COMMENT ON TABLE application.organization_custom_role IS
  'Better Auth dynamic access control: admin-defined per-organization roles with a JSON permission map (resource -> actions). Named *_custom_role because application.organization_role is the role enum type.';

COMMIT;
