#!/usr/bin/env bash
set -uo pipefail
export PATH=/projects/sandbox/pruebas-em5/deno/bin:$PATH
AQUI=/projects/sandbox/pruebas-em5
$AQUI/pg.sh >/dev/null 2>&1 || { echo "fallo pg.sh"; exit 1; }
PGHOST=/var/lib/pgdata PGUSER=postgres psql -q -d impulse_pruebas -f $AQUI/semilla-metricas.sql -t -A 2>&1 | tail -3
export LLAVE_SERVICIO_FALSA=x SIM_PANEL_UID=89e5028d-8c17-4deb-89c3-59acbd0ee2f2
deno run -q -A $AQUI/simulador-v2.ts >$AQUI/sim-mt.log 2>&1 &
P1=$!
for i in $(seq 1 40); do curl -s -o /dev/null localhost:54321 && break; sleep 0.5; done
$AQUI/venv/bin/python $AQUI/probar-ui-metricas.py "$@"
kill $P1 2>/dev/null
