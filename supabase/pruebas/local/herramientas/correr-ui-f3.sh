#!/usr/bin/env bash
# ============================================================
# Impulse · prueba las PANTALLAS de F3 en Chromium (PC 1280 y celular 390)
# contra las RPC reales: el aviso «ventas web sin asiento» de la portada de
# Finanzas, el boton «Registrar asiento», la marca «Automático» en el Diario y
# el modo solo lectura en Editar asiento.
# Uso: bash supabase/pruebas/local/herramientas/correr-ui-f3.sh [--capturas]
# ============================================================
set -uo pipefail
export PATH=/projects/sandbox/pruebas-em5/deno/bin:$PATH
AQUI=/projects/sandbox/pruebas-em5

$AQUI/pg.sh >/dev/null 2>&1 || { echo "fallo pg.sh"; exit 1; }
export PGHOST=/var/lib/pgdata PGUSER=postgres

psql -v ON_ERROR_STOP=1 -q -d impulse_pruebas <<'SQL' >/dev/null
insert into productos (id, sku, nombre, precio_venta, costo_unitario, activo)
  values ('b2000000-0000-4000-8000-000000000001', 'UI3-P1', 'Shampoo pantalla F3', 69900, 25000, true);
insert into movimientos_inventario (product_id, tipo, cantidad, motivo)
  values ('b2000000-0000-4000-8000-000000000001', 'entrada', 5, 'semilla ui f3');
insert into campana_producto (id, nombre, slug, precio_venta, product_id_ref, publicado, activo)
  values ('a2000000-0000-4000-8000-000000000001', 'Shampoo pantalla F3', 'ui3-p1', 69900,
          'b2000000-0000-4000-8000-000000000001', true, true);
-- Un asiento MANUAL de siempre.
insert into asientos (id, fecha, descripcion) values
  ('c2000000-0000-4000-8000-000000000001', current_date, 'Aporte inicial (manual)');
insert into asiento_lineas (asiento_id, cuenta_codigo, debe, haber, orden) values
  ('c2000000-0000-4000-8000-000000000001', '110505', 500000, 0, 1),
  ('c2000000-0000-4000-8000-000000000001', '311505', 0, 500000, 2);
set role service_role;
-- Venta REAL con el IVA aun sin definir: el pedido entra, el asiento queda pendiente.
select pw_registrar_intencion('MAG-a2000000-1791549152798-0a1b2c3d4e5f', 'a2000000-0000-4000-8000-000000000001'::uuid, 'ui3-p1',
  'Shampoo pantalla F3', 1, 69900::bigint, 6990000::bigint, 'prod',
  '{"nombre":"Hilda Pantalla","correo":"hilda@cliente.invalid","telefono":"3014443322","ciudad":"Tunja"}'::jsonb);
select pw_procesar_pago('TX-UI3-1', 'APPROVED', 'MAG-a2000000-1791549152798-0a1b2c3d4e5f', 6990000::bigint, 'COP', 'transaction.updated',
  'chk-ui3-1', null, 'CARD', 'hilda@wompi.invalid');
-- Venta de PRUEBA (sandbox): no debe aparecer en Finanzas.
select pw_registrar_intencion('MAG-a2000000-1791549152799-9f8e7d6c5b4a', 'a2000000-0000-4000-8000-000000000001'::uuid, 'ui3-p1',
  'Shampoo pantalla F3', 1, 69900::bigint, 6990000::bigint, 'sandbox', '{"nombre":"Ivan Sandbox"}'::jsonb);
select pw_procesar_pago('TX-UI3-2', 'APPROVED', 'MAG-a2000000-1791549152799-9f8e7d6c5b4a', 6990000::bigint);
reset role;
SQL

export LLAVE_SERVICIO_FALSA=x SIM_PANEL_UID=89e5028d-8c17-4deb-89c3-59acbd0ee2f2
deno run -q -A $AQUI/simulador-v2.ts >$AQUI/sim-uif3.log 2>&1 &
P1=$!
for i in $(seq 1 40); do curl -s -o /dev/null localhost:54321 && break; sleep 0.5; done
$AQUI/venv/bin/python $AQUI/probar-ui-f3.py "$@"
kill $P1 2>/dev/null
