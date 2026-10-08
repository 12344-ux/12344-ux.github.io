#!/usr/bin/env bash
set -uo pipefail
export PATH=/projects/sandbox/pruebas-em5/deno/bin:$PATH
AQUI=/projects/sandbox/pruebas-em5
REPO=/projects/sandbox/12344-ux.github.io
$AQUI/pg.sh >/dev/null 2>&1 || { echo "fallo pg.sh"; exit 1; }
export PGHOST=/var/lib/pgdata PGUSER=postgres
LLAVE="servicio-falsa-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
MKT="re_mkt_falsa_$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')"
export LLAVE_SERVICIO_FALSA=$LLAVE
deno run -q -A $AQUI/simulador-v2.ts >$AQUI/sim2.log 2>&1 &
P1=$!
SUPABASE_URL=http://localhost:54321 SUPABASE_SERVICE_ROLE_KEY=$LLAVE RESEND_MARKETING_API_KEY=$MKT RESEND_API_URL_BASE=http://localhost:54322 \
  deno run -q --allow-net --allow-env $REPO/supabase/functions/tienda-eventos/index.ts >$AQUI/fn-ev.log 2>&1 &
P2=$!
for i in $(seq 1 40); do curl -s -o /dev/null localhost:8000 && curl -s -o /dev/null localhost:54321 && break; sleep 0.5; done
$AQUI/venv/bin/python $AQUI/probar-analitica.py
echo "== logs"
cat $AQUI/fn-ev.log
TOK=$(cat $AQUI/token-prueba.txt 2>/dev/null || echo NOTOKEN)
if grep -q -i -e "vis-0123" -e "$LLAVE" -e "190.5.5" -e "201.7.7" $AQUI/fn-ev.log; then echo "FALLA | los logs filtran datos"; else echo "pasa | logs sin correos, IP, tokens ni llaves"; fi
kill $P1 $P2 2>/dev/null
