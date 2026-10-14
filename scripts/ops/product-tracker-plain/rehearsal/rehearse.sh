#!/usr/bin/env bash
# Rehearse the switch on a local copy: traffic through PgBouncer (transaction mode, prepared statements, like DO's
# pools) the whole time, the steps in order, then the loss check.
#   bash rehearse.sh <run-id> [steps…]      steps may include edge:future, edge:freeze, edge:straggler
# Needs the containers from the README (l5-rehearsal on :55433, l5-pgbouncer on :56432).
set -euo pipefail
cd "$(dirname "$0")"
RUN=${1:?run id}; shift || true
STEPS=${*:-"prepare arm index matview verify swap detach"}
export DATABASE_URL=postgres://postgres:rehearsal@127.0.0.1:55433/fundermaps
export DATABASE_URL_WS=postgres://fundermaps_webservice:ws@127.0.0.1:56432/fundermaps
export DATABASE_URL_API=postgres://fundermaps_api:api@127.0.0.1:56432/fundermaps
mkdir -p out; rm -f out/$RUN.*
# The disk is shared: refuse below 12 GB free, stop the rehearsal database below 4 GB (a 31M-row run filled it once).
free_gb() { df --output=avail -BG / | tail -1 | tr -dc 0-9; }
[ "$(free_gb)" -ge 12 ] || { echo "STOP: only $(free_gb) GB free on /"; exit 1; }
( while sleep 5; do if [ "$(free_gb)" -lt 4 ]; then echo "WATCHDOG: under 4 GB free, stopping the rehearsal database"; touch out/$RUN.stop; docker stop l5-rehearsal; exit; fi; done ) &
WATCH=$!
bun load.ts "$RUN" 3600 20 10 > out/$RUN.load.log 2>&1 &
LOAD=$!
trap 'touch out/$RUN.stop; kill $WATCH 2>/dev/null || true' EXIT
sleep 15
for s in $STEPS; do
  echo "######## $s  ($(date -u +%T))"
  case "$s" in
    edge:*) bun edge.ts "${s#edge:}" 2>&1 | tee -a out/$RUN.steps.log ;;
    *)      bun ../switch.ts "$s" 2>&1 | tee -a out/$RUN.steps.log ;;
  esac
  sleep 10
done
touch out/$RUN.stop; wait $LOAD || true
echo "######## traffic"; tail -1 out/$RUN.load.log
python3 -I latency.py out/$RUN.load.log
echo "######## loss check"; bun check.ts "$RUN"
