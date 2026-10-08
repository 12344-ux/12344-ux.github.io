#!/usr/bin/env bash
# ============================================================
# Impulse · prueba el CICLO COMPLETO de F2 en una sola corrida:
#   crear-intencion-pago (persiste + firma)  ->  wompi-webhook (firma real)
#   ->  pw_procesar_pago  ->  pedido con su salida de inventario.
# Secretos falsos y base local: nada toca Supabase ni Wompi reales.
# Uso: bash supabase/pruebas/local/herramientas/correr-intencion-f2.sh
# ============================================================
set -uo pipefail
export PATH=/projects/sandbox/pruebas-em5/deno/bin:$PATH
AQUI=/projects/sandbox/pruebas-em5
REPO=/projects/sandbox/12344-ux.github.io

sudo rm -f /var/lib/pgdata/postmaster.pid 2>/dev/null
$AQUI/pg.sh >/dev/null 2>&1 || { echo "fallo pg.sh"; exit 1; }
export PGHOST=/var/lib/pgdata PGUSER=postgres

# Semilla: producto con 3 unidades, campana publicada y ligada, Wompi en sandbox.
psql -v ON_ERROR_STOP=1 -q -d impulse_pruebas <<'SQL'
insert into productos (id, sku, nombre, precio_venta, costo_unitario, activo)
  values ('b8000000-0000-4000-8000-000000000001', 'I-P1', 'Producto intencion', 30000, 10000, true);
insert into movimientos_inventario (product_id, tipo, cantidad, motivo)
  values ('b8000000-0000-4000-8000-000000000001', 'entrada', 3, 'semilla intencion');
insert into campana_producto (id, nombre, slug, precio_venta, product_id_ref, publicado, activo)
  values ('a8000000-0000-4000-8000-000000000001', 'Producto intencion', 'i-p1', 30000,
          'b8000000-0000-4000-8000-000000000001', true, true);
update pagos_config set entorno = 'sandbox', llave_publica_sandbox = 'pub_test_LLAVEPUBLICAFALSA' where id = 1;
SQL

LLAVE="servicio-falsa-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
export LLAVE_SERVICIO_FALSA=$LLAVE
deno run -q -A $AQUI/simulador-v2.ts >$AQUI/sim-f2.log 2>&1 &
P1=$!

# --- (A) crear-intencion-pago en el 8000 ---
SUPABASE_URL=http://localhost:54321 \
SUPABASE_SERVICE_ROLE_KEY=$LLAVE \
WOMPI_INTEGRITY_SANDBOX=test_integrity_SECRETOFALSO123456 \
  deno run -q --allow-net --allow-env $REPO/supabase/functions/crear-intencion-pago/index.ts >$AQUI/fn-int.log 2>&1 &
P2=$!
for i in $(seq 1 40); do curl -s -o /dev/null localhost:8000 && curl -s -o /dev/null localhost:54321 && break; sleep 0.5; done
deno run -q -A $AQUI/probar-intencion-f2.ts
kill $P2 2>/dev/null
sleep 1

# --- (B) ciclo completo: el webhook cobra esa misma intencion ---
REF=$(cat $AQUI/ref-intencion.txt 2>/dev/null || echo "")
SUPABASE_URL=http://localhost:54321 \
SUPABASE_SERVICE_ROLE_KEY=$LLAVE \
WOMPI_EVENTS_SANDBOX=test_events_SECRETOFALSOsandbox123456 \
WOMPI_EVENTS_PROD=prod_events_SECRETOFALSOprod123456789 \
  deno run -q --allow-net --allow-env $REPO/supabase/functions/wompi-webhook/index.ts >$AQUI/fn-wh.log 2>&1 &
P3=$!
for i in $(seq 1 40); do curl -s -o /dev/null localhost:8000 && break; sleep 0.5; done
REF_CICLO=$REF deno run -q -A $AQUI/probar-ciclo-f2.ts
kill P3 2>/dev/null; kill $P3 2>/dev/null

echo "== los logs no deben filtrar secretos ni datos de personas"
if grep -q -i -e "SECRETOFALSO" -e "$LLAVE" -e "dora@cliente" $AQUI/fn-int.log $AQUI/fn-wh.log; then
  echo "FALLA | los logs filtran secretos o datos"
else
  echo "pasa | logs sin secretos de integridad/eventos, llaves ni correos"
fi
kill $P1 2>/dev/null
