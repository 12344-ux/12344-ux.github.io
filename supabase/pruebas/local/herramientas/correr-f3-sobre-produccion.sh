#!/usr/bin/env bash
# ============================================================
# Impulse · aplica F3 (20261020000000) sobre una base que REPRODUCE PRODUCCION
# al 9-oct-2026: todas las migraciones menos 20261002 (superada) y 20261020,
# CON datos previos: asientos manuales (uno usa 135518), un ajuste a mano del
# dueno en contabilidad_config y un pedido web de PRUEBA anterior a F3.
# Aplica F3 DOS veces (idempotencia) y comprueba que no dana nada.
# Uso: bash supabase/pruebas/local/herramientas/correr-f3-sobre-produccion.sh
# ============================================================
set -uo pipefail
D=/var/lib/pgdata
REPO=/projects/sandbox/12344-ux.github.io
AQUI=/projects/sandbox/pruebas-em5
BD=f3_sobre_produccion
F3=$REPO/supabase/migrations/20261020000000_pagos_f3_asiento_automatico.sql

sudo -u pg pg_ctl -D $D -l $D/pglog.log -o "-k $D -c listen_addresses=''" status >/dev/null 2>&1 || {
  sudo rm -f $D/postmaster.pid $D/.s.PGSQL.5432.lock
  sudo -u pg pg_ctl -D $D -l $D/pglog.log -o "-k $D -c listen_addresses=''" -w start >/dev/null
}
export PGHOST=$D PGUSER=postgres

psql -v ON_ERROR_STOP=1 -q -d postgres -c "drop database if exists $BD" -c "create database $BD" >/dev/null
psql -v ON_ERROR_STOP=1 -q -d $BD -f $REPO/supabase/pruebas/local/supabase-simulado.sql >/dev/null 2>&1
psql -v ON_ERROR_STOP=1 -q -d $BD -f $AQUI/storage-minimo.sql >/dev/null
n=0
for f in $REPO/supabase/migrations/*.sql; do
  case "$(basename $f)" in 20261002000000_*|20261020000000_*) continue ;; esac
  psql -v ON_ERROR_STOP=1 -q -d $BD -f "$f" >/dev/null 2>$AQUI/ultimo-error.txt || {
    echo "FALLA migracion $(basename $f)"; cat $AQUI/ultimo-error.txt; exit 1; }
  n=$((n+1))
done
echo "== $n migraciones (como produccion hoy: F2 si, F3 no)"

# --- Datos previos realistas -------------------------------------------------
psql -v ON_ERROR_STOP=1 -q -d $BD <<'SQL' >/dev/null
-- Asiento manual de una venta de mostrador y otro que uso 135518 con el nombre viejo.
insert into asientos (id, fecha, descripcion) values
  ('c0000000-0000-4000-8000-000000000001', '2026-10-01', 'Venta de mostrador (manual)'),
  ('c0000000-0000-4000-8000-000000000002', '2026-10-02', 'Compra con IVA descontable (manual)');
insert into asiento_lineas (asiento_id, cuenta_codigo, debe, haber, orden) values
  ('c0000000-0000-4000-8000-000000000001', '110505', 32900, 0, 1),
  ('c0000000-0000-4000-8000-000000000001', '413505', 0, 32900, 2),
  ('c0000000-0000-4000-8000-000000000002', '135518', 1900, 0, 1),
  ('c0000000-0000-4000-8000-000000000002', '110505', 0, 1900, 2);
-- El dueno ya habia ajustado a mano la comision (gastos bancarios).
update contabilidad_config set cuenta_comision = '530505' where id = 1;
-- Un pedido web de PRUEBA (sandbox) de antes de F3.
insert into productos (id, sku, nombre, precio_venta, costo_unitario, activo)
  values ('b5000000-0000-4000-8000-000000000001', 'PR-P1', 'Producto previo', 30000, 10000, true);
insert into movimientos_inventario (product_id, tipo, cantidad, motivo)
  values ('b5000000-0000-4000-8000-000000000001', 'entrada', 2, 'semilla');
insert into campana_producto (id, nombre, slug, precio_venta, product_id_ref, publicado, activo)
  values ('a5000000-0000-4000-8000-000000000001', 'Producto previo', 'pr-p1', 30000,
          'b5000000-0000-4000-8000-000000000001', true, true);
set role service_role;
select pw_registrar_intencion('REF-PREVIA-01', 'a5000000-0000-4000-8000-000000000001'::uuid, 'pr-p1', 'Producto previo',
  1, 30000::bigint, 3000000::bigint, 'sandbox', '{"nombre":"Prueba previa"}'::jsonb);
select pw_procesar_pago('TX-PREVIA-01', 'APPROVED', 'REF-PREVIA-01', 3000000::bigint);
reset role;
SQL

# --- F3 dos veces ------------------------------------------------------------
psql -v ON_ERROR_STOP=1 -q -d $BD -f $F3 >$AQUI/f3-1.log 2>&1 || { echo "FALLA | F3 no aplica sobre produccion"; cat $AQUI/f3-1.log; exit 1; }
psql -v ON_ERROR_STOP=1 -q -d $BD -f $F3 >$AQUI/f3-2.log 2>&1 || { echo "FALLA | F3 no es idempotente"; cat $AQUI/f3-2.log; exit 1; }
echo "pasa | F3 aplica sobre la base de produccion y se puede volver a correr sin error"
grep -q "135518 tiene movimientos" $AQUI/f3-1.log \
  && echo "pasa | 135518 con movimientos: NO se renombra y se avisa" \
  || echo "FALLA | 135518 con movimientos: no avisa"

psql -v ON_ERROR_STOP=1 -q -d $BD -t -A <<'SQL'
create temp table r (n serial, ok boolean, que text);
insert into r (ok, que) values
 ((select count(*) = 2 and bool_and(origen = 'manual' and origen_ref is null) from asientos),
  'los asientos que ya existian quedan como manuales, intactos'),
 ((select sum(debe) = 34800 and sum(haber) = 34800 from asiento_lineas),
  'sus lineas no cambiaron (34.800 = 34.800)'),
 ((select nombre = 'IMPUESTO SOBRE LAS VENTAS DESCONTABLE (IVA DESCONTABLE)' from puc_cuentas where codigo = '135518'),
  '135518 usada: conserva el nombre con el que se registro'),
 ((select cuenta_comision = '530505' from contabilidad_config where id = 1),
  'el ajuste a mano del dueno (comision 530505) se respeta'),
 ((select cuenta_banco = '111005' and cuenta_ingreso = '413505' and cuenta_costo = '613505'
          and cuenta_inventario = '143505' and cuenta_pasarela = '138095' from contabilidad_config where id = 1),
  'lo que seguia en grupo baja a subcuenta y aparece la cuenta puente'),
 ((select count(*) = 1 from pg_trigger where tgname = 'trg_contabilidad_config_validar'),
  'aplicarla dos veces no duplica el trigger'),
 ((select count(*) = 2 from pg_constraint where conname in ('asientos_origen_valido', 'asientos_origen_ref_coherente')),
  'aplicarla dos veces no duplica las restricciones'),
 ((select count(*) = 0 from asientos where origen <> 'manual'),
  'el pedido de prueba anterior a F3 no genera asientos'),
 ((select not has_function_privilege('authenticated', 'pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text)', 'execute')
      and has_function_privilege('service_role', 'pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text)', 'execute')),
  'pw_procesar_pago conserva sus permisos (solo service_role)'),
 ((select has_function_privilege('authenticated', 'anular_pedido(uuid,text)', 'execute')
      and has_function_privilege('authenticated', 'editar_asiento(uuid,date,text,jsonb)', 'execute')),
  'anular_pedido y editar_asiento conservan sus permisos');
select case when ok then 'pasa' else 'FALLA' end || ' | ' || que from r order by n;
SQL

echo "== matriz de permisos despues de F3"
psql -v ON_ERROR_STOP=1 -q -d $BD -f $REPO/supabase/pruebas/matriz-permisos.sql -t -A -F' | ' > $AQUI/matriz-f3p.txt 2>&1 || {
  tail -20 $AQUI/matriz-f3p.txt; exit 1; }
grep -m2 -i "TODO PASA\|FALLA" $AQUI/matriz-f3p.txt | head -3
