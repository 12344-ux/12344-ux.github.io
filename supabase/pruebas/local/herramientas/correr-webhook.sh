#!/usr/bin/env bash
# Todo en UNA invocacion: Postgres + migraciones, semilla, simulador, funcion, bateria.
set -uo pipefail
export PATH=/projects/sandbox/pruebas-em5/deno/bin:$PATH
AQUI=/projects/sandbox/pruebas-em5
REPO=/projects/sandbox/12344-ux.github.io
$AQUI/pg.sh >/dev/null 2>&1 || { echo "fallo pg.sh"; exit 1; }
export PGHOST=/var/lib/pgdata PGUSER=postgres
psql -q -d impulse_pruebas <<'SQL'
insert into em_contactos (correo, correo_norm, nombre, estado, fuente, consentimiento_en, consentimiento_texto, politica_version, evidencia)
values ('sim@x.invalid','sim@x.invalid','Sim','suscrito','manual',now(),'t','1.0','{}');
insert into em_campanas (id, nombre_interno, asunto, estado, utm_campaign, resend_broadcast_id, enviada_en)
values ('b0000000-0000-4000-8000-0000000000aa','Sim','A','enviada','sim-test','bc-sim',now());
insert into em_campana_destinatarios (campana_id, contacto_id, correo, estado)
select 'b0000000-0000-4000-8000-0000000000aa', id, correo, 'listo' from em_contactos where correo_norm='sim@x.invalid';
SQL
SECRETO="whsec_$(head -c 24 /dev/urandom | base64)"
LLAVE="servicio-falsa-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
export LLAVE_SERVICIO_FALSA=$LLAVE SECRETO
deno run -q --allow-net --allow-env --allow-run $AQUI/simulador-postgrest.ts >$AQUI/sim.log 2>&1 &
P1=$!
SUPABASE_URL=http://localhost:54321 SUPABASE_SERVICE_ROLE_KEY=$LLAVE RESEND_WEBHOOK_SECRET=$SECRETO \
  deno run -q --allow-net --allow-env $REPO/supabase/functions/em-webhook/index.ts >$AQUI/fn.log 2>&1 &
P2=$!
DENO_SERVE_ADDRESS=tcp:0.0.0.0:8001 SUPABASE_URL=http://localhost:54321 SUPABASE_SERVICE_ROLE_KEY=$LLAVE \
  deno run -q --allow-net --allow-env $REPO/supabase/functions/em-webhook/index.ts >$AQUI/fn2.log 2>&1 &
P3=$!
for i in $(seq 1 40); do curl -s -o /dev/null localhost:8000 && curl -s -o /dev/null localhost:8001 && curl -s -o /dev/null localhost:54321 && break; sleep 0.5; done
deno run -q -A $AQUI/probar-webhook.ts
echo "== logs de la funcion (no deben tener correos, cuerpos ni secretos)"
cat $AQUI/fn.log
if grep -q -e "sim@x.invalid" -e "$SECRETO" -e "$LLAVE" -e "relleno" $AQUI/fn.log $AQUI/fn2.log; then echo "FALLA | los logs filtran datos"; else echo "pasa | logs sin correos, cuerpos ni secretos"; fi
kill $P1 $P2 $P3 2>/dev/null
