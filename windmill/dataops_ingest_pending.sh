#!/bin/bash
# Data Ops — read what arrived. Every 15 minutes: every open dossier that has a
# document nobody has read yet goes through FunderMapsWorker's ingest-dossier
# (classify pages, extract, per-address rows, admissibility). Nothing here
# decides anything: every value lands 'pending' for a person in Studio → Controle.
#
# Batch, not webhook (Yorick 2026-09-01): a sweep is idempotent and self-healing —
# a dossier missed by one run is picked up by the next; a crash mid-batch loses
# nothing because the CLI leaves no extraction behind on failure.
set -uo pipefail
pg="$1"
s3="$2"
openrouter="$3"
limit="${4:-20}"

# --- tools: the worker image lacks poppler/ImageMagick/file; install once per container
if ! command -v pdftotext >/dev/null || ! command -v convert >/dev/null || ! command -v file >/dev/null; then
  echo "installing pdf/image tools"
  apt-get update -qq >/dev/null 2>&1
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq poppler-utils imagemagick file >/dev/null 2>&1
fi

# --- worker code: FunderMapsWorker main, cached per container
D=/tmp/fundermaps-worker
if [ -d "$D/.git" ]; then
  git -C "$D" fetch -q --depth 1 origin main && git -C "$D" reset -q --hard origin/main
else
  rm -rf "$D"; git clone -q --depth 1 https://github.com/Laixer/FunderMapsWorker.git "$D"
fi
cd "$D" && bun install --frozen-lockfile --silent
echo "worker at $(git rev-parse --short HEAD)"

# --- environment from the Windmill resources (JSON in $pg / $s3)
eval "$(bun -e '
const pg = JSON.parse(process.argv[1]); const s3 = JSON.parse(process.argv[2]);
const q = (v) => JSON.stringify(String(v ?? ""));
const ep = (s3.endPoint || "ams3.digitaloceanspaces.com").replace(/^https?:\/\//, "");
console.log([
  `export FUNDERMAPS_DATABASE_HOST=${q(pg.host)}`,
  `export FUNDERMAPS_DATABASE_PORT=${q(pg.port || 25060)}`,
  `export FUNDERMAPS_DATABASE_NAME=${q(pg.dbname || "fundermaps")}`,
  `export FUNDERMAPS_DATABASE_USER=${q(pg.user)}`,
  `export FUNDERMAPS_DATABASE_PASSWORD=${q(pg.password)}`,
  `export FUNDERMAPS_S3_ENDPOINT=${q((s3.useSSL === false ? "http://" : "https://") + ep)}`,
  `export FUNDERMAPS_S3_REGION=${q(s3.region || "ams3")}`,
  `export FUNDERMAPS_S3_BUCKET=${q("fundermaps")}`,
  `export FUNDERMAPS_S3_ACCESS_KEY=${q(s3.accessKey)}`,
  `export FUNDERMAPS_S3_SECRET_KEY=${q(s3.secretKey)}`,
].join("\n"));' "$pg" "$s3")"
export OPENROUTER_API_KEY="$openrouter"
export PGHOST="$FUNDERMAPS_DATABASE_HOST" PGPORT="$FUNDERMAPS_DATABASE_PORT" PGDATABASE="$FUNDERMAPS_DATABASE_NAME" PGUSER="$FUNDERMAPS_DATABASE_USER" PGPASSWORD="$FUNDERMAPS_DATABASE_PASSWORD" PGSSLMODE=require

# --- what is waiting: open dossiers with at least one unread document
ids=$(psql -X -At -c "
  select distinct d.id
    from dataops.dossier d
    join dataops.artifact a on a.dossier_id = d.id
   where d.inquiry_id is null and d.outcome is null
     and d.channel in ('upload', 'email', 'api')
     and not exists (select 1 from dataops.extraction e where e.artifact_id = a.id)
   order by d.id
   limit $limit")
n=$(echo "$ids" | grep -c . || true)
echo "pending dossiers: $n"
[ "$n" -eq 0 ] && { echo '{"read":0,"failed":0}'; exit 0; }

ok=0; failed=0; failed_ids=""
for id in $ids; do
  if bun run src/commands/ingest-dossier.ts --dossier "$id" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E "dossier #|proposed|ERR|WRN|done"; then
    ok=$((ok+1))
  else
    failed=$((failed+1)); failed_ids="$failed_ids $id"
  fi
done
echo "{\"read\":$ok,\"failed\":$failed,\"failed_ids\":\"${failed_ids# }\"}"
