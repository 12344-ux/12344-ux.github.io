#!/usr/bin/env bash
# ============================================================
# Impulse · prueba el DIAGNÓSTICO DE PRODUCCIÓN (supabase/pruebas/
# diagnostico-produccion.sql) en dos bases locales, dentro de una transacción
# READ ONLY (si intentara escribir algo, fallaría):
#   1) "completa": todas las migraciones (F2 aplicada).
#   2) "como_produccion": omite 20261002 (superada), 20261018 y 20261019, que
#      es lo último que consta como aplicado en producción. Así se comprueba
#      que el diagnóstico NO se cae cuando F2 todavía no existe.
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

armar diag_como_produccion 20261002000000 20261018000000 20261019000000
diagnosticar diag_como_produccion

# Comprobaciones minimas del resultado (no solo "que corra").
grep -q "la tabla no existe (F2 sin aplicar)" $AQUI/diag-diag_como_produccion.txt \
  && echo "pasa | sin F2: el diagnostico lo informa en vez de caerse" \
  || echo "FALLA | sin F2: no informa la ausencia de las tablas"
grep -q "1 en total · creada=1" $AQUI/diag-diag_completa.txt \
  && echo "pasa | con F2: cuenta la intencion de pago sembrada" \
  || echo "FALLA | con F2: no cuenta la intencion sembrada"
grep -q "d-p1 → D-P1 · stock 4 · costo 12000" $AQUI/diag-diag_completa.txt \
  && echo "pasa | lista la campana publicada con su producto, stock y costo" \
  || echo "FALLA | no lista la campana con producto, stock y costo"
grep -q "banco 1110 → NO IMPUTABLE" $AQUI/diag-diag_completa.txt \
  && echo "pasa | detecta que contabilidad_config apunta a cuentas no imputables" \
  || echo "FALLA | no detecta la configuracion contable no imputable"
