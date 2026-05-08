#!/usr/bin/env bash
#
# init_db.sh — bootstrap a fresh FunderMaps Postgres database for a test VM.
#
# What it does (idempotent):
#   1. Sanity-check the target host (refuses prod).
#   2. Ensures the postgis extension is installed.
#   3. Creates roles: fundermaps, fundermaps_webapp, fundermaps_webservice, grafana.
#      Passwords come from env vars; if unset, random passwords are generated
#      and printed to stdout once.
#   4. Loads schema.sql (the schema-only dump committed at repo root).
#   5. Applies sql/init/grants.sql so the four roles get expected privileges.
#
# What it does NOT do:
#   - Create the database itself. Run `createdb fundermaps` first, or pass
#     a DATABASE_URL pointing at an existing empty database.
#   - Load seed data. Run `psql -f sql/seed.sql` (Part B) afterwards.
#   - Install timescaledb. Prod's product_tracker hypertable is irrelevant
#     for testing; vanilla tables work fine.
#   - Manage pg_cron jobs. Trigger refresh_all manually via the worker
#     or psql when needed.
#
# Usage:
#   DATABASE_URL=postgres://user:pass@host:5432/fundermaps ./scripts/init_db.sh
#
# Optional env:
#   PG_FM_PASS, PG_WEBAPP_PASS, PG_WS_PASS, PG_GRAFANA_PASS
#       Passwords for each role. Random if unset.
#   FUNDERMAPS_INIT_ALLOW_PROD=1
#       Override the prod-host refusal. Don't.

set -euo pipefail

# --- Setup ------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCHEMA_FILE="${REPO_ROOT}/schema.sql"
GRANTS_FILE="${REPO_ROOT}/sql/init/grants.sql"
PUBLIC_MODEL_DATA="${REPO_ROOT}/sql/init/public_model_data.sql"

if [[ -z "${DATABASE_URL:-}" ]]; then
    echo "error: DATABASE_URL is not set" >&2
    exit 1
fi

if [[ ! -f "${SCHEMA_FILE}" ]]; then
    echo "error: ${SCHEMA_FILE} not found" >&2
    exit 1
fi

if [[ ! -f "${GRANTS_FILE}" ]]; then
    echo "error: ${GRANTS_FILE} not found" >&2
    exit 1
fi

if [[ ! -f "${PUBLIC_MODEL_DATA}" ]]; then
    echo "error: ${PUBLIC_MODEL_DATA} not found" >&2
    exit 1
fi

# --- Prod-host guard --------------------------------------------------------
# Refuse to run against the managed prod cluster. Production hostnames look
# like "db-pg-ams3-0-do-user-871803-0.b.db.ondigitalocean.com" (or the
# private- variant). Match on the user/cluster id segment.
if [[ "${DATABASE_URL}" == *"do-user-871803"* ]] && [[ -z "${FUNDERMAPS_INIT_ALLOW_PROD:-}" ]]; then
    echo "error: DATABASE_URL appears to point at production (matched 'do-user-871803')." >&2
    echo "       Aborting. Set FUNDERMAPS_INIT_ALLOW_PROD=1 to override (don't)." >&2
    exit 1
fi

# --- Password material ------------------------------------------------------
gen_password() { LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24; }

PG_FM_PASS="${PG_FM_PASS:-$(gen_password)}"
PG_WEBAPP_PASS="${PG_WEBAPP_PASS:-$(gen_password)}"
PG_WS_PASS="${PG_WS_PASS:-$(gen_password)}"
PG_GRAFANA_PASS="${PG_GRAFANA_PASS:-$(gen_password)}"

# --- Helpers ----------------------------------------------------------------
psql_exec() {
    PGOPTIONS='--client-min-messages=warning' \
        psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -X -q "$@"
}

# --- Step 1: extensions -----------------------------------------------------
echo "==> Ensuring postgis extension"
psql_exec -c "CREATE EXTENSION IF NOT EXISTS postgis;"

# --- Step 2: roles ----------------------------------------------------------
echo "==> Creating roles (idempotent)"
psql_exec <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'fundermaps') THEN
        CREATE ROLE fundermaps LOGIN PASSWORD '${PG_FM_PASS}';
    ELSE
        ALTER ROLE fundermaps WITH LOGIN PASSWORD '${PG_FM_PASS}';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'fundermaps_webapp') THEN
        CREATE ROLE fundermaps_webapp LOGIN PASSWORD '${PG_WEBAPP_PASS}';
    ELSE
        ALTER ROLE fundermaps_webapp WITH LOGIN PASSWORD '${PG_WEBAPP_PASS}';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'fundermaps_webservice') THEN
        CREATE ROLE fundermaps_webservice LOGIN PASSWORD '${PG_WS_PASS}';
    ELSE
        ALTER ROLE fundermaps_webservice WITH LOGIN PASSWORD '${PG_WS_PASS}';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'grafana') THEN
        CREATE ROLE grafana LOGIN PASSWORD '${PG_GRAFANA_PASS}';
    ELSE
        ALTER ROLE grafana WITH LOGIN PASSWORD '${PG_GRAFANA_PASS}';
    END IF;
END
\$\$;
SQL

# --- Step 3: schema.sql -----------------------------------------------------
# pg_dump 18 emits a `\restrict <token>` directive at the top that psql ≤ 17
# does not understand. Strip it before piping in. Harmless on psql 18.
echo "==> Loading schema.sql"
sed -e '/^\\restrict /d' -e '/^\\unrestrict /d' "${SCHEMA_FILE}" \
    | PGOPTIONS='--client-min-messages=warning' \
        psql "${DATABASE_URL}" -v ON_ERROR_STOP=1 -X -q

# --- Step 4: public-schema lookup data --------------------------------------
# public.model_gevelscan and public.risk_table_priority are static lookup
# tables that drive maplayer.facade_scan. They live in 'public' for
# historical reasons (TODO to relocate). Their structure is in schema.sql,
# their data lives here.
echo "==> Loading public model lookup data"
psql_exec -f "${PUBLIC_MODEL_DATA}"

# --- Step 5: grants ---------------------------------------------------------
echo "==> Applying grants"
psql_exec -f "${GRANTS_FILE}"

# --- Done -------------------------------------------------------------------
echo
echo "==> Done. Connection strings (save these — passwords are not stored):"
# Reuse the host/port/db part of DATABASE_URL but swap user:pass.
#   postgres://user:pass@host:port/db?...
URL_TAIL="${DATABASE_URL#*@}"   # host:port/db?...
print_url() {
    local role="$1" pass="$2"
    echo "  ${role}: postgres://${role}:${pass}@${URL_TAIL}"
}
print_url fundermaps            "${PG_FM_PASS}"
print_url fundermaps_webapp     "${PG_WEBAPP_PASS}"
print_url fundermaps_webservice "${PG_WS_PASS}"
print_url grafana               "${PG_GRAFANA_PASS}"
echo
echo "Next step: load seed data with"
echo "  gunzip -c sql/seed.sql.gz | psql \"\$DATABASE_URL\""
echo "(seed.sql.gz is produced by Part B — scripts/build_seed.ts)"
