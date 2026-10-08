#!/usr/bin/env bash
# ============================================================
# Impulse · prueba el AVISO DE PAGOS SIN PEDIDO (Wompi F2) en la portada de
# Ventas, en Chromium, PC 1280 y celular 390, contra las RPC reales.
# Siembra dos casos distintos a proposito: uno sin stock y uno con monto que
# no coincide, para ver que cada motivo se explica en lenguaje claro.
# Uso: bash supabase/pruebas/local/herramientas/correr-ui-pagos.sh [--capturas]
# ============================================================
set -uo pipefail
export PATH=/projects/sandbox/pruebas-em5/deno/bin:$PATH
AQUI=/projects/sandbox/pruebas-em5

sudo rm -f /var/lib/pgdata/postmaster.pid 2>/dev/null
$AQUI/pg.sh >/dev/null 2>&1 || { echo "fallo pg.sh"; exit 1; }
export PGHOST=/var/lib/pgdata PGUSER=postgres

psql -v ON_ERROR_STOP=1 -q -d impulse_pruebas <<'SQL'
-- Producto agotado (una entrada y una salida) y campana ligada.
insert into productos (id, sku, nombre, precio_venta, costo_unitario, activo)
  values ('b9000000-0000-4000-8000-000000000001', 'UI-P1', 'Shampoo de prueba', 30000, 10000, true);
insert into movimientos_inventario (product_id, tipo, cantidad, motivo) values
  ('b9000000-0000-4000-8000-000000000001', 'entrada', 1, 'semilla ui'),
  ('b9000000-0000-4000-8000-000000000001', 'salida',  1, 'se vendio por otro lado');
insert into campana_producto (id, nombre, slug, precio_venta, product_id_ref, publicado, activo)
  values ('a9000000-0000-4000-8000-000000000001', 'Shampoo de prueba', 'ui-p1', 30000,
          'b9000000-0000-4000-8000-000000000001', true, true);

-- (1) Pago aprobado SIN STOCK
select pw_registrar_intencion('REF-UI-0001', 'a9000000-0000-4000-8000-000000000001'::uuid, 'ui-p1',
  'Shampoo de prueba', 1::integer, 30000::bigint, 3000000::bigint, 'sandbox',
  '{"nombre":"Eva Sin Stock","correo":"eva@cliente.invalid","telefono":"3009998877","ciudad":"Tunja"}'::jsonb);
select pw_procesar_pago('TX-UI-1', 'APPROVED', 'REF-UI-0001', 3000000::bigint, 'COP',
  'transaction.updated', 'chk-ui-1', null, 'NEQUI', 'eva@wompi.invalid');

-- (2) Pago aprobado con MONTO QUE NO COINCIDE
select pw_registrar_intencion('REF-UI-0002', 'a9000000-0000-4000-8000-000000000001'::uuid, 'ui-p1',
  'Shampoo de prueba', 1::integer, 30000::bigint, 3000000::bigint, 'sandbox',
  '{"nombre":"Fabio Monto","correo":"fabio@cliente.invalid","telefono":"3007776655","ciudad":"Duitama"}'::jsonb);
select pw_procesar_pago('TX-UI-2', 'APPROVED', 'REF-UI-0002', 100::bigint, 'COP',
  'transaction.updated', 'chk-ui-2', null, 'CARD', 'fabio@wompi.invalid');
SQL

export LLAVE_SERVICIO_FALSA=x SIM_PANEL_UID=89e5028d-8c17-4deb-89c3-59acbd0ee2f2
deno run -q -A $AQUI/simulador-v2.ts >$AQUI/sim-uipagos.log 2>&1 &
P1=$!
for i in $(seq 1 40); do curl -s -o /dev/null localhost:54321 && break; sleep 0.5; done
$AQUI/venv/bin/python $AQUI/probar-ui-pagos.py "$@"
kill $P1 2>/dev/null
