#!/usr/bin/env bash
# C1 · Demuestra con dos conexiones que un UID no puede confirmarse a la vez
# como cliente y personal. Se ejecuta solo contra el banco local/CI.
set -euo pipefail
PGHOST="${PGHOST:-/var/lib/pgdata}"
PGUSER="${PGUSER:-postgres}"
BD="${BD_PRUEBAS:-impulse_pruebas}"
PSQL=(psql -v ON_ERROR_STOP=1 -qAt -h "$PGHOST" -U "$PGUSER" -d "$BD")
U1=7ec10000-0000-4000-8000-000000001001
U2=7ec10000-0000-4000-8000-000000001002
A="$(mktemp "${TMPDIR:-/tmp}/cc-conc-a-XXXX")"
B="$(mktemp "${TMPDIR:-/tmp}/cc-conc-b-XXXX")"
trap 'rm -f "$A" "$B"' EXIT

esperar_marca() {
  local marca="$1" archivo="$2"
  for _ in $(seq 1 200); do
    grep -q "$marca" "$archivo" && return 0
    sleep 0.02
  done
  echo "FALLA · la primera transaccion no confirmo que tuviera el bloqueo" >&2
  return 1
}

esperar_bloqueo() {
  local app="$1"
  for _ in $(seq 1 200); do
    [ "$("${PSQL[@]}" -c "select count(*) from pg_stat_activity where application_name='$app' and wait_event_type='Lock';")" = "1" ] && return 0
    sleep 0.02
  done
  echo "FALLA · la segunda conexion no espero el bloqueo comun" >&2
  return 1
}

"${PSQL[@]}" -c "delete from cuentas_cliente where auth_user_id in ('$U1','$U2'); delete from perfiles where id in ('$U1','$U2'); delete from auth.users where id in ('$U1','$U2'); insert into auth.users(id,email) values ('$U1','conc-1@local.invalid'),('$U2','conc-2@local.invalid');"

# Cliente toma primero el bloqueo comun. \echo es la senal observable de que el
# trigger termino y la transaccion mantiene el lock; no se adivina con sleep.
{
  printf '%s\n' 'begin;' "insert into cuentas_cliente(auth_user_id) values ('$U1');" '\echo CC_CLIENTE_BLOQUEO_LISTO' 'select pg_sleep(3);' 'commit;'
} | PGAPPNAME=cc-cliente-primera "${PSQL[@]}" >"$A" 2>&1 &
PA=$!
esperar_marca 'CC_CLIENTE_BLOQUEO_LISTO' "$A"
set +e
PGAPPNAME=cc-perfil-segunda "${PSQL[@]}" -c "insert into perfiles(id,rol,modulos) values ('$U1','prueba','{}');" >"$B" 2>&1 &
PB=$!
set -e
esperar_bloqueo 'cc-perfil-segunda'
set +e
wait "$PA"; SA=$?
wait "$PB"; SB=$?
set -e
[ "$SA" -eq 0 ] && [ "$SB" -ne 0 ]
[ "$("${PSQL[@]}" -c "select (select count(*) from cuentas_cliente where auth_user_id='$U1') || '|' || (select count(*) from perfiles where id='$U1');")" = "1|0" ]
echo "pasa · concurrencia: cliente primero impide perfil interno"

# Carrera inversa: el perfil toma el mismo lock y la cuenta debe esperar/fallar.
{
  printf '%s\n' 'begin;' "insert into perfiles(id,rol,modulos) values ('$U2','prueba','{}');" '\echo CC_PERSONAL_BLOQUEO_LISTO' 'select pg_sleep(3);' 'commit;'
} | PGAPPNAME=cc-personal-primera "${PSQL[@]}" >"$A" 2>&1 &
PA=$!
esperar_marca 'CC_PERSONAL_BLOQUEO_LISTO' "$A"
set +e
PGAPPNAME=cc-cuenta-segunda "${PSQL[@]}" -c "insert into cuentas_cliente(auth_user_id) values ('$U2');" >"$B" 2>&1 &
PB=$!
set -e
esperar_bloqueo 'cc-cuenta-segunda'
set +e
wait "$PA"; SA=$?
wait "$PB"; SB=$?
set -e
[ "$SA" -eq 0 ] && [ "$SB" -ne 0 ]
[ "$("${PSQL[@]}" -c "select (select count(*) from cuentas_cliente where auth_user_id='$U2') || '|' || (select count(*) from perfiles where id='$U2');")" = "0|1" ]
echo "pasa · concurrencia: personal primero impide cuenta cliente"

echo "RESUMEN · 2 comprobaciones · 0 fallan"
"${PSQL[@]}" -c "delete from cuentas_cliente where auth_user_id in ('$U1','$U2'); delete from perfiles where id in ('$U1','$U2'); delete from auth.users where id in ('$U1','$U2');"
