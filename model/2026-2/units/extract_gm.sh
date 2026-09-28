#!/usr/bin/env bash
# Read-only extract per municipality: id, RD WKT, BAG year, height (= analysis_full.height), footprint, established type, cluster.
set -euo pipefail
source ~/.claude/fundermaps-secrets.env
export PGPASSWORD=$PGPW_FUNDERMAPS PGCONNECT_TIMEOUT=10 PGOPTIONS='-c default_transaction_read_only=on'
U="postgresql://fundermaps@private-db-pg-ams3-0-do-user-871803-0.b.db.ondigitalocean.com:25060/fundermaps?sslmode=require"
cd "${UNITS_WORK:-$(dirname "$0")}"
mkdir -p gm
[ -s gm_list.txt ] || psql "$U" -X -At -c "select m.id, m.external_id from geocoder.municipality m" > gm_list.txt
extract() {
  local gid=$1 code=$2
  [ -s gm/$code.csv.gz ] && return 0
  psql "$U" -X -q -c "\copy (select b.external_id id, left(b.built_year::text,4)::int yr, m.height, round(ST_Area(g)::numeric,2) area, case when m.foundation_type_reliability::text='established' then m.foundation_type::text end ft_est, bc.cluster_id, ST_AsText(g) wkt from geocoder.building b join geocoder.neighborhood n on n.id=b.neighborhood_id join geocoder.district d on d.id=n.district_id cross join lateral (select ST_Transform(b.geom,28992) g) t left join data.model_risk_static_2024_1 m on m.building_id=b.external_id left join data.building_cluster bc on bc.building_id=b.external_id where d.municipality_id='$gid' and b.active) to program 'gzip > gm/$code.csv.gz.tmp' csv header" && mv gm/$code.csv.gz.tmp gm/$code.csv.gz
}
export -f extract; export U PGPASSWORD PGCONNECT_TIMEOUT PGOPTIONS
awk -F'|' '{print $1" "$2}' gm_list.txt | xargs -P 2 -n 2 bash -c 'extract "$0" "$1" || echo "FAIL $1"'
echo EXTRACT_DONE
