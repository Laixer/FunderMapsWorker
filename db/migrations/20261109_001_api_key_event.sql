-- Who made or revoked which API key, and when (Laixer/FunderMapsStudio#40).
--
-- Every user may make their own API keys from now on, and their organisation is charged for what the keys use
-- (Yorick, 2026-11-09). Customers' finance departments will ask who made a key. Better Auth's apikey table only
-- holds the keys that still exist, without who made them, and a revoked key is gone. So the API writes one row
-- here for each key it creates or revokes, in Beheer or by the user, in the same transaction.
--
-- No foreign keys on purpose: a row has to outlive its key, its user and its organisation.
-- True on prod 2026-11-09: no such table; the keys live in auth.apikey (since 20261108_002) and application.auth_key.

CREATE TABLE application.api_key_event (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    api_key_id text NOT NULL,
    -- The key's first characters (fmsk.xxxx), so a person can tell which key it was after it's gone.
    key_start text,
    action text NOT NULL CHECK (action IN ('create', 'revoke')),
    -- The key's owner, the organisation that pays for it at that moment, and who acted: the owner, or an administrator in Beheer.
    user_id uuid NOT NULL,
    organization_id uuid,
    actor_user_id uuid NOT NULL,
    via text NOT NULL CHECK (via IN ('self', 'beheer')),
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX api_key_event_user_idx ON application.api_key_event (user_id, created_at DESC);
CREATE INDEX api_key_event_organization_idx ON application.api_key_event (organization_id, created_at DESC);
COMMENT ON TABLE application.api_key_event IS
    '[audit] Who created or revoked which API key and when (Studio #40). Written by the API with each change; rows outlive the key, the user and the organisation.';

ALTER TABLE application.api_key_event OWNER TO fundermaps;

-- The API writes and reads it; nobody updates or deletes an audit row. Revoked first, because default privileges may
-- have given more (on a database bootstrapped by scripts/init_db.sh they do; on prod only fundie_agent reads).
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'fundermaps_webapp') THEN
        RAISE NOTICE 'role fundermaps_webapp does not exist; no grants';
        RETURN;
    END IF;
    REVOKE ALL ON application.api_key_event FROM fundermaps_webapp;
    GRANT SELECT, INSERT ON application.api_key_event TO fundermaps_webapp;
    IF NOT has_table_privilege('fundermaps_webapp', 'application.api_key_event', 'SELECT, INSERT')
       OR has_table_privilege('fundermaps_webapp', 'application.api_key_event', 'UPDATE')
       OR has_table_privilege('fundermaps_webapp', 'application.api_key_event', 'DELETE') THEN
        RAISE EXCEPTION 'fundermaps_webapp has the wrong rights on application.api_key_event';
    END IF;
END
$$;
