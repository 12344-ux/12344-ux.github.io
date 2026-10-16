#!/usr/bin/env bash
# C2 · Prueba locks reales: doble callback y dos cuentas por el mismo cliente.
set -euo pipefail
PGHOST="${PGHOST:-/var/lib/pgdata}"
PGUSER="${PGUSER:-postgres}"
BD="${BD_PRUEBAS:-impulse_pruebas}"
PSQL=(psql -v ON_ERROR_STOP=1 -qAt -h "$PGHOST" -U "$PGUSER" -d "$BD")
U1=7ec20000-0000-4000-8000-000000001001
U2=7ec20000-0000-4000-8000-000000001002
U3=7ec20000-0000-4000-8000-000000001003
U4=7ec20000-0000-4000-8000-000000001004
U5=7ec20000-0000-4000-8000-000000001005
U6=7ec20000-0000-4000-8000-000000001006
U7=7ec20000-0000-4000-8000-000000001007
C1=7ec21000-0000-4000-8000-000000001001
C2=7ec21000-0000-4000-8000-000000001002
C3=7ec21000-0000-4000-8000-000000001003
C4=7ec21000-0000-4000-8000-000000001004
A="$(mktemp "${TMPDIR:-/tmp}/cc2-conc-a-XXXX")"
B="$(mktemp "${TMPDIR:-/tmp}/cc2-conc-b-XXXX")"
trap 'rm -f "$A" "$B"' EXIT

esperar_marca() {
  local marca="$1" archivo="$2"
  for _ in $(seq 1 200); do
    grep -q "$marca" "$archivo" && return 0
    sleep 0.02
  done
  echo "FALLA · C2 no confirmo el primer bloqueo" >&2
  return 1
}

esperar_bloqueo() {
  local app="$1"
  for _ in $(seq 1 200); do
    [ "$("${PSQL[@]}" -c "select count(*) from pg_stat_activity where application_name='$app' and wait_event_type='Lock';")" = "1" ] && return 0
    sleep 0.02
  done
  echo "FALLA · C2 no observo la espera por lock de $app" >&2
  return 1
}

limpiar() {
  "${PSQL[@]}" -c "delete from auth.users where id in ('$U1','$U2','$U3','$U4','$U5','$U6','$U7'); delete from clientes where id in ('$C1','$C2','$C3','$C4');" >/dev/null
}
limpiar
"${PSQL[@]}" -c "insert into auth.users(id,email,email_confirmed_at) values ('$U1','misma-c2@local.invalid',now()),('$U2','misma-c2@local.invalid',now()),('$U3','doble-c2@local.invalid',now()),('$U4','fantasma-c2@local.invalid',now()),('$U5','perfil-primero-c2@local.invalid',now()),('$U6','cuenta-primero-c2@local.invalid',now()),('$U7','actualizar-c2@local.invalid',now()); insert into clientes(id,nombre,correo,correo_norm) values ('$C1','Cliente carrera C2','misma-c2@local.invalid','misma-c2@local.invalid'),('$C2','Cliente visible C2','fantasma-c2@local.invalid','fantasma-c2@local.invalid'),('$C4','Cliente update C2','actualizar-c2@local.invalid','actualizar-c2@local.invalid');"

# Dos UIDs confirmados compiten por el mismo cliente. El segundo espera el lock
# de clientes; despues nace sin customer_id y deja revision, nunca roba vinculo.
{
  printf '%s\n' 'begin;' "set local request.jwt.claims to '{\"sub\":\"$U1\",\"role\":\"authenticated\"}';" 'set local role authenticated;' 'select cc_inicializar_cuenta();' 'reset role;' '\echo CC2_CLIENTE_BLOQUEO_LISTO' 'select pg_sleep(3);' 'commit;'
} | PGAPPNAME=cc2-vinculo-primero "${PSQL[@]}" >"$A" 2>&1 &
PA=$!
esperar_marca 'CC2_CLIENTE_BLOQUEO_LISTO' "$A"
{
  printf '%s\n' 'begin;' "set local request.jwt.claims to '{\"sub\":\"$U2\",\"role\":\"authenticated\"}';" 'set local role authenticated;' 'select cc_inicializar_cuenta();' 'commit;'
} | PGAPPNAME=cc2-vinculo-segundo "${PSQL[@]}" >"$B" 2>&1 &
PB=$!
esperar_bloqueo 'cc2-vinculo-segundo'
wait "$PA"
wait "$PB"
[ "$("${PSQL[@]}" -c "select count(*) filter(where customer_id='$C1') || '|' || count(*) filter(where auth_user_id in ('$U1','$U2')) from cuentas_cliente;")" = "1|2" ]
[ "$("${PSQL[@]}" -c "select count(*) from cc_conflictos_revision where auth_user_id in ('$U1','$U2') and motivo='cliente_ya_vinculado';")" = "1" ]
echo "pasa · concurrencia C2: un solo vinculo y la otra cuenta queda en revision"

# Dos callbacks del mismo UID se serializan sobre auth.users y dejan una fila.
{
  printf '%s\n' 'begin;' "set local request.jwt.claims to '{\"sub\":\"$U3\",\"role\":\"authenticated\"}';" 'set local role authenticated;' 'select cc_inicializar_cuenta();' 'reset role;' '\echo CC2_UID_BLOQUEO_LISTO' 'select pg_sleep(3);' 'commit;'
} | PGAPPNAME=cc2-uid-primero "${PSQL[@]}" >"$A" 2>&1 &
PA=$!
esperar_marca 'CC2_UID_BLOQUEO_LISTO' "$A"
{
  printf '%s\n' 'begin;' "set local request.jwt.claims to '{\"sub\":\"$U3\",\"role\":\"authenticated\"}';" 'set local role authenticated;' 'select cc_inicializar_cuenta();' 'commit;'
} | PGAPPNAME=cc2-uid-segundo "${PSQL[@]}" >"$B" 2>&1 &
PB=$!
esperar_bloqueo 'cc2-uid-segundo'
wait "$PA"
wait "$PB"
[ "$("${PSQL[@]}" -c "select count(*) from cuentas_cliente where auth_user_id='$U3';")" = "1" ]
echo "pasa · concurrencia C2: doble callback deja una sola cuenta"

# Un escritor ya activo intenta introducir una segunda coincidencia. La RPC
# espera el advisory lock del mismo correo; al continuar ve ambas filas y no vincula.
{
  printf '%s\n' 'begin;' "insert into clientes(id,nombre,correo,correo_norm) values ('$C3','Cliente fantasma C2',' FANTASMA-C2@LOCAL.INVALID ','otro-fantasma-c2@local.invalid');" '\echo CC2_ESCRITOR_BLOQUEO_LISTO' 'select pg_sleep(3);' 'commit;'
} | PGAPPNAME=cc2-cliente-escritor "${PSQL[@]}" >"$A" 2>&1 &
PA=$!
esperar_marca 'CC2_ESCRITOR_BLOQUEO_LISTO' "$A"
{
  printf '%s\n' 'begin;' "set local request.jwt.claims to '{\"sub\":\"$U4\",\"role\":\"authenticated\"}';" 'set local role authenticated;' 'select cc_inicializar_cuenta();' 'commit;'
} | PGAPPNAME=cc2-fantasma-rpc "${PSQL[@]}" >"$B" 2>&1 &
PB=$!
esperar_bloqueo 'cc2-fantasma-rpc'
wait "$PA"
wait "$PB"
[ "$("${PSQL[@]}" -c "select count(*) from cuentas_cliente where auth_user_id='$U4' and customer_id is null;")" = "1" ]
[ "$("${PSQL[@]}" -c "select count(*) from cc_conflictos_revision where auth_user_id='$U4' and motivo='correo_ambiguo' and coincidencias=2;")" = "1" ]
echo "pasa · concurrencia C2: escritura fantasma espera y termina sin vinculo"

# Si el perfil interno gana primero el lock comun de auth.users, la RPC espera
# y luego rechaza la cuenta. No queda puente parcial.
{
  printf '%s\n' 'begin;' "select id from auth.users where id='$U5' for update;" "insert into perfiles(id,rol,modulos) values ('$U5','prueba','{}');" '\echo CC2_PERFIL_PRIMERO_LISTO' 'select pg_sleep(3);' 'commit;'
} | PGAPPNAME=cc2-perfil-primero "${PSQL[@]}" >"$A" 2>&1 &
PA=$!
esperar_marca 'CC2_PERFIL_PRIMERO_LISTO' "$A"
{
  printf '%s\n' 'begin;' "set local request.jwt.claims to '{\"sub\":\"$U5\",\"role\":\"authenticated\"}';" 'set local role authenticated;' "do \$\$ begin perform cc_inicializar_cuenta(); raise exception 'CC2_DEBIO_RECHAZAR'; exception when others then if sqlerrm <> 'CC_IDENTIDAD_ES_PERSONAL' then raise; end if; end \$\$;" 'commit;'
} | PGAPPNAME=cc2-cuenta-segunda "${PSQL[@]}" >"$B" 2>&1 &
PB=$!
esperar_bloqueo 'cc2-cuenta-segunda'
wait "$PA"
wait "$PB"
[ "$("${PSQL[@]}" -c "select (select count(*) from perfiles where id='$U5') || '|' || (select count(*) from cuentas_cliente where auth_user_id='$U5');")" = "1|0" ]
echo "pasa · concurrencia C2: perfil primero excluye la cuenta"

# Si la RPC gana primero, el trigger de perfiles espera el mismo lock y luego
# rechaza el alta interna. El UID queda exclusivamente como cliente.
{
  printf '%s\n' 'begin;' "set local request.jwt.claims to '{\"sub\":\"$U6\",\"role\":\"authenticated\"}';" 'set local role authenticated;' 'select cc_inicializar_cuenta();' 'reset role;' '\echo CC2_CUENTA_PRIMERO_LISTA' 'select pg_sleep(3);' 'commit;'
} | PGAPPNAME=cc2-cuenta-primera "${PSQL[@]}" >"$A" 2>&1 &
PA=$!
esperar_marca 'CC2_CUENTA_PRIMERO_LISTA' "$A"
{
  printf '%s\n' 'begin;' "do \$\$ begin insert into perfiles(id,rol,modulos) values ('$U6','prueba','{}'); raise exception 'CC2_DEBIO_RECHAZAR'; exception when others then if sqlerrm <> 'CC_IDENTIDAD_ES_CLIENTE' then raise; end if; end \$\$;" 'commit;'
} | PGAPPNAME=cc2-perfil-segundo "${PSQL[@]}" >"$B" 2>&1 &
PB=$!
esperar_bloqueo 'cc2-perfil-segundo'
wait "$PA"
wait "$PB"
[ "$("${PSQL[@]}" -c "select (select count(*) from cuentas_cliente where auth_user_id='$U6') || '|' || (select count(*) from perfiles where id='$U6');")" = "1|0" ]
echo "pasa · concurrencia C2: cuenta primero excluye el perfil"

# UPDATE toma su fila antes de ejecutar el trigger BEFORE. C2 toma primero el
# advisory lock, pero ya no pide FOR UPDATE sobre clientes: puede leer la versión
# confirmada, completar el vínculo y liberar el advisory sin formar deadlock.
{
  printf '%s\n' 'begin;' "select pg_advisory_xact_lock(hashtextextended('cc-correo:actualizar-c2@local.invalid',0));" '\echo CC2_ADVISORY_UPDATE_LISTO' 'select pg_sleep(1);' "set local request.jwt.claims to '{\"sub\":\"$U7\",\"role\":\"authenticated\"}';" 'set local role authenticated;' 'select cc_inicializar_cuenta();' 'commit;'
} | PGAPPNAME=cc2-rpc-con-update "${PSQL[@]}" >"$A" 2>&1 &
PA=$!
esperar_marca 'CC2_ADVISORY_UPDATE_LISTO' "$A"
{
  printf '%s\n' 'begin;' "update clientes set correo='actualizado-c2@local.invalid', correo_norm='actualizado-c2@local.invalid' where id='$C4';" 'commit;'
} | PGAPPNAME=cc2-update-con-rpc "${PSQL[@]}" >"$B" 2>&1 &
PB=$!
esperar_bloqueo 'cc2-update-con-rpc'
wait "$PA"
wait "$PB"
[ "$("${PSQL[@]}" -c "select (select count(*) from cuentas_cliente where auth_user_id='$U7' and customer_id='$C4') || '|' || (select count(*) from clientes where id='$C4' and correo_norm='actualizado-c2@local.invalid');")" = "1|1" ]
echo "pasa · concurrencia C2: UPDATE del mismo correo no forma deadlock"

echo "RESUMEN · 6 comprobaciones · 0 fallan"
limpiar
