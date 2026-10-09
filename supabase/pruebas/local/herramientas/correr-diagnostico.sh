#!/usr/bin/env bash
# ============================================================
# Impulse · prueba el DIAGNÓSTICO DE PRODUCCIÓN (supabase/pruebas/
# diagnostico-produccion.sql) en tres bases locales, dentro de una transacción
# READ ONLY (si intentara escribir algo, fallaría):
#   1) "completa": todas las migraciones (F2 y F3 aplicadas).
#   2) "hoy": omite 20261002 (superada) y 20261020 (F3): producción al 9-oct,
#      con F2 desplegada y F3 por aplicar.
#   3) "antes_f2": omite además 20261018 y 20261019. Así se comprueba que el
#      diagnóstico NO se cae cuando F2 o F3 todavía no existen.
# Uso: bash supabase/pruebas/local/herramientas/correr-diagnostico.sh
# ============================================================
set -euo pipefail
D=/var/lib/pgdata
REPO=/projects/sandbox/12344-ux.github.io
AQUI=/projects/sandbox/pruebas-em5
DIAG=$REPO/supabase/pruebas/diagnostico-produccion.sql

if [ ! -f $D/PG_VERSION ]; then
  sudo mkdir -p $D && sudo chown pg:pg $D && sudo chmod 700 $D
  sudo -u pg initdb -D $D -U postgres --auth=trust >/dev/null
fi
sudo -u pg pg_ctl -D $D -l $D/pglog.log -o "-k $D -c listen_addresses=''" status >/dev/null 2>&1 || \
  sudo -u pg pg_ctl -D $D -l $D/pglog.log -o "-k $D -c listen_addresses=''" -w start >/dev/null
export PGHOST=$D PGUSER=postgres

armar() {  # $1 = base, $2.. = prefijos de migraciones a omitir
  local bd=$1; shift
  psql -v ON_ERROR_STOP=1 -q -d postgres -c "drop database if exists $bd" -c "create database $bd" >/dev/null
  psql -v ON_ERROR_STOP=1 -q -d $bd -f $REPO/supabase/pruebas/local/supabase-simulado.sql >/dev/null
  psql -v ON_ERROR_STOP=1 -q -d $bd -f $AQUI/storage-minimo.sql >/dev/null
  local n=0 f b o salta
  for f in $REPO/supabase/migrations/*.sql; do
    b=$(basename "$f"); salta=0
    for o in "$@"; do case "$b" in "$o"_*) salta=1 ;; esac; done
    [ $salta = 1 ] && continue
    psql -v ON_ERROR_STOP=1 -q -d $bd -f "$f" >/dev/null 2>$AQUI/ultimo-error.txt || {
      echo "FALLA migracion $b"; cat $AQUI/ultimo-error.txt; exit 1; }
    n=$((n+1))
  done
  echo "== base $bd: $n migraciones (omitidas: ${*:-ninguna})"
}

diagnosticar() {  # $1 = base
  psql -v ON_ERROR_STOP=1 -q -d $1 -P pager=off -c "begin read only" -f "$DIAG" -c "rollback" \
    > $AQUI/diag-$1.txt 2>&1 || { echo "FALLA | el diagnostico no corre en $1"; cat $AQUI/diag-$1.txt; exit 1; }
  cat $AQUI/diag-$1.txt
}

armar diag_completa
# Semilla minima para que las filas con datos muestren algo (producto con costo,
# campana publicada y ligada, una intencion). Va DESPUES de armar la base.
psql -v ON_ERROR_STOP=1 -q -d diag_completa <<'SQL'
insert into productos (id, sku, nombre, precio_venta, costo_unitario, activo)
  values ('b9000000-0000-4000-8000-000000000001', 'D-P1', 'Producto diagnostico', 30000, 12000, true);
insert into movimientos_inventario (product_id, tipo, cantidad, motivo)
  values ('b9000000-0000-4000-8000-000000000001', 'entrada', 4, 'semilla diagnostico');
insert into campana_producto (id, nombre, slug, precio_venta, product_id_ref, publicado, activo)
  values ('a9000000-0000-4000-8000-000000000001', 'Producto diagnostico', 'd-p1', 30000,
          'b9000000-0000-4000-8000-000000000001', true, true);
select pw_registrar_intencion('REF-DIAG-0001', 'a9000000-0000-4000-8000-000000000001'::uuid, 'd-p1',
  'Producto diagnostico', 1, 30000::bigint, 3000000::bigint, 'sandbox', '{}'::jsonb, null, null);
SQL
diagnosticar diag_completa

armar diag_hoy 20261002000000 20261020000000
diagnosticar diag_hoy

armar diag_antes_f2 20261002000000 20261018000000 20261019000000 20261020000000
diagnosticar diag_antes_f2

# Comprobaciones minimas del resultado (no solo "que corra").
ok() { grep -q -- "$2" $AQUI/diag-$1.txt && echo "pasa | $3" || echo "FALLA | $3"; }
ok diag_antes_f2 "la tabla no existe (F2 sin aplicar)" "sin F2: el diagnostico lo informa en vez de caerse"
ok diag_antes_f2 "F3 sin aplicar" "sin F3: el diagnostico lo informa en vez de caerse"
ok diag_completa "1 en total · creada=1" "con F2: cuenta la intencion de pago sembrada"
ok diag_completa "d-p1 → D-P1 · stock 4 · costo 12000" "lista la campana publicada con su producto, stock y costo"
ok diag_hoy "banco 1110 → NO IMPUTABLE" "produccion de hoy (sin F3): detecta las cuentas de grupo (H1)"
ok diag_hoy "F3 sin aplicar" "produccion de hoy: dice que F3 falta"
ok diag_completa "banco 111005 → ok" "con F3: las cuentas configuradas ya son subcuentas imputables"
ok diag_completa "puente Wompi 138095 → ok · IVA generado 240805 → ok" "con F3: cuenta puente e IVA listos"
ok diag_completa "SIN DEFINIR" "con F3: avisa que el dueno aun no define el IVA"
ok diag_completa "Asiento automático instalado *| true" "con F3: el asiento automatico figura instalado"
