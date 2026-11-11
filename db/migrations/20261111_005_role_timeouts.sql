-- Limits for the two roles that serve requests (Yorick 2026-11-11: "Do 9 and timeouts").
--
-- Until now the API and the Webservice had no statement timeout at all and could sit idle inside a transaction for 24
-- hours (the cluster default). One runaway query, or one request that dies with a transaction open, could hold locks
-- and a connection until someone noticed. The tile server (15 s) and Fundie (60 s) already have limits.
--
-- The slowest statement on record since 2026-10-28: 11 s for the API, 5 s for the Webservice. So:
--   fundermaps_api          statement 60 s, idle in transaction 5 min (its transactions do several steps)
--   fundermaps_webservice   statement 30 s, idle in transaction 60 s (it runs single statements)
-- Windmill keeps no limit: the model refresh runs for over an hour by design.
--
-- A role setting applies to new sessions. Behind the connection pools that means: as server connections are renewed,
-- within the hour. Skipped with a NOTICE where a role does not exist (a fresh test database has no fundermaps_api).
DO $$
DECLARE
    s record;
BEGIN
    FOR s IN SELECT * FROM (VALUES
            ('fundermaps_api',        'statement_timeout',                   '60s'),
            ('fundermaps_api',        'idle_in_transaction_session_timeout', '5min'),
            ('fundermaps_webservice', 'statement_timeout',                   '30s'),
            ('fundermaps_webservice', 'idle_in_transaction_session_timeout', '60s')
        ) v(role, name, value) LOOP
        IF EXISTS (SELECT FROM pg_roles WHERE rolname = s.role) THEN
            EXECUTE format('ALTER ROLE %I SET %I = %L', s.role, s.name, s.value);
        ELSE
            RAISE NOTICE 'role % does not exist; % not set', s.role, s.name;
        END IF;
    END LOOP;
END
$$;
