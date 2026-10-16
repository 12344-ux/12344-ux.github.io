#!/usr/bin/env bash
# Levanta Auth/PostgREST simulados + Edge Function real cuenta-inicializar.
set -euo pipefail
export PATH=/projects/sandbox/pruebas-em5/deno/bin:$PATH
AQUI=/projects/sandbox/pruebas-em5
REPO=/projects/sandbox/12344-ux.github.io
"$AQUI/pg.sh" >/dev/null 2>&1 || { echo "fallo pg.sh"; exit 1; }
export PGHOST=/var/lib/pgdata PGUSER=postgres
export ANON_KEY_FALSA="anon-falsa-c2-$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')"
SERVICIO_PROHIBIDO="service-role-prohibida-c2-$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')"

psql -v ON_ERROR_STOP=1 -q -d impulse_pruebas <<'SQL'
insert into auth.users(id,email,email_confirmed_at) values
  ('7ec20000-0000-4000-8000-000000002001','http-password-c2@local.invalid',now()),
  ('7ec20000-0000-4000-8000-000000002002','http-google-c2@local.invalid',now()),
  ('7ec20000-0000-4000-8000-000000002003','http-no-confirmado-c2@local.invalid',null),
  ('7ec20000-0000-4000-8000-000000002004','http-bloqueada-c2@local.invalid',now()),
  ('7ec20000-0000-4000-8000-000000002005','http-cerrada-c2@local.invalid',now()),
  ('7ec20000-0000-4000-8000-000000002006','http-personal-c2@local.invalid',now());
insert into clientes(id,nombre,correo,correo_norm) values
  ('7ec21000-0000-4000-8000-000000002001','Historico HTTP C2',' HTTP-PASSWORD-C2@LOCAL.INVALID ',null);
insert into cuentas_cliente(auth_user_id,estado) values
  ('7ec20000-0000-4000-8000-000000002004','bloqueada'),
  ('7ec20000-0000-4000-8000-000000002005','cerrada');
insert into perfiles(id,rol,modulos) values
  ('7ec20000-0000-4000-8000-000000002006','prueba','{}');
SQL

ANON_KEY_FALSA="$ANON_KEY_FALSA" deno run -q --allow-net --allow-env --allow-run \
  "$AQUI/simulador-cuentas-c2.ts" >"$AQUI/sim-c2.log" 2>&1 &
P1=$!
SUPABASE_URL=http://localhost:54321 SUPABASE_ANON_KEY="$ANON_KEY_FALSA" \
  deno run -q --allow-net --allow-env "$REPO/supabase/functions/cuenta-inicializar/index.ts" \
  >"$AQUI/fn-c2.log" 2>&1 &
P2=$!
trap 'kill "$P1" "$P2" 2>/dev/null || true' EXIT

for _ in $(seq 1 60); do
  curl -s -o /dev/null http://localhost:54321/ && curl -s -o /dev/null -H 'Origin: https://magandhi.com' http://localhost:8000/ && break
  sleep 0.5
done

ANON_KEY_FALSA="$ANON_KEY_FALSA" SERVICE_ROLE_FALSA="$SERVICIO_PROHIBIDO" \
  deno run -q --allow-net --allow-env --allow-run "$AQUI/probar-cuentas-c2-http.ts"

echo "== logs cuenta-inicializar"
cat "$AQUI/fn-c2.log"
if grep -q -i -e '@local.invalid' -e '7ec20000-' -e 'jwt-' -e "$ANON_KEY_FALSA" -e "$SERVICIO_PROHIBIDO" "$AQUI/fn-c2.log"; then
  echo "FALLA | logs C2 filtran PII, JWT o llaves"
  exit 1
else
  echo "pasa | logs C2 sin PII, JWT ni llaves"
fi
