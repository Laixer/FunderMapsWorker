-- An account holder per organisation: the FunderMaps person an organisation's users can turn to (Laixer/FunderMapsStudio#86,
-- asked by Don on 2026-11-11). Set in Beheer; shown to the organisation's users in the map.
--
-- It points at a user instead of holding a name and a phone number of its own: the account holder is always someone at
-- FunderMaps, and their name, job title, e-mail and phone are on their own profile, which they keep up to date themselves.
-- Its own table, not a column on auth.organization, because Better Auth owns that table's shape.
--
-- No row = no account holder: the organisation's users then see the general support address. When the user is deleted,
-- so is the row.
-- True on prod 2026-11-12: no such table; auth.organization has id, name, slug, logo, metadata, created_at.

CREATE TABLE application.organization_account_holder (
    organization_id uuid PRIMARY KEY REFERENCES auth.organization(id) ON UPDATE CASCADE ON DELETE CASCADE,
    user_id uuid NOT NULL REFERENCES auth."user"(id) ON UPDATE CASCADE ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX organization_account_holder_user_idx ON application.organization_account_holder (user_id);
COMMENT ON TABLE application.organization_account_holder IS
    '[platform] The FunderMaps user who is an organisation''s fixed contact (Studio #86). No row = none; the user''s own profile holds the contact details.';

ALTER TABLE application.organization_account_holder OWNER TO fundermaps;

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_webapp') THEN
        RAISE NOTICE 'role fundermaps_webapp does not exist; no grants';
        RETURN;
    END IF;
    REVOKE ALL ON application.organization_account_holder FROM fundermaps_webapp;
    GRANT SELECT, INSERT, UPDATE, DELETE ON application.organization_account_holder TO fundermaps_webapp;
    IF NOT has_table_privilege('fundermaps_webapp', 'application.organization_account_holder', 'SELECT, INSERT, UPDATE, DELETE') THEN
        RAISE EXCEPTION 'fundermaps_webapp cannot manage application.organization_account_holder';
    END IF;
END
$$;
