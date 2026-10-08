#!/usr/bin/env bash
# ============================================================
# Impulse · prueba wompi-webhook de punta a punta con CHECKSUMS REALES:
#   probar-wompi-webhook.ts  ->  Edge Function real (deno)  ->  simulador
#   PostgREST  ->  RPC pw_procesar_pago real  ->  Postgres local.
# Nada toca Supabase ni Wompi reales: secretos falsos y base local.
# Todo en UNA invocacion (los procesos no sobreviven entre llamadas).
# Uso: bash supabase/pruebas/local/herramientas/correr-wompi-webhook.sh
# ============================================================
set -uo pipefail
export PATH=/projects/sandbox/pruebas-em5/deno/bin:$PATH
AQUI=/projects/sandbox/pruebas-em5
REPO=/projects/sandbox/12344-ux.github.io

sudo rm -f /var/lib/pgdata/postmaster.pid 2>/dev/null
$AQUI/pg.sh >/dev/null 2>&1 || { echo "fallo pg.sh"; exit 1; }
export PGHOST=/var/lib/pgdata PGUSER=postgres

# --- Semilla: producto con 5 unidades, campana ligada e intenciones creadas ---
psql -v ON_ERROR_STOP=1 -q -d impulse_pruebas <<'SQL'
insert into productos (id, sku, nombre, precio_venta, costo_unitario, activo)
  values ('b7000000-0000-4000-8000-000000000001', 'W-P1', 'Producto webhook', 30000, 10000, true);
insert into movimientos_inventario (product_id, tipo, cantidad, motivo)
  values ('b7000000-0000-4000-8000-000000000001', 'entrada', 5, 'semilla webhook');
insert into campana_producto (id, nombre, slug, precio_venta, product_id_ref, publicado, activo)
  values ('a7000000-0000-4000-8000-000000000001', 'Producto webhook', 'w-p1', 30000,
          'b7000000-0000-4000-8000-000000000001', true, true);
do $$
declare r text;
begin
  foreach r in array array['REF-W-0001','REF-W-0002','REF-W-0003','REF-W-0004','REF-W-0005','REF-W-PROPS'] loop
    perform pw_registrar_intencion(r, 'a7000000-0000-4000-8000-000000000001'::uuid, 'w-p1', 'Producto webhook',
      1::integer, 30000::bigint, 3000000::bigint, 'sandbox',
      '{"nombre":"Cliente Webhook","correo":"cw@cliente.invalid","telefono":"3001234567","ciudad":"Tunja"}'::jsonb,
      'camp-webhook', 'vid-webhook-1');
  end loop;
end $$;
SQL

LLAVE="servicio-falsa-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
export LLAVE_SERVICIO_FALSA=$LLAVE
deno run -q -A $AQUI/simulador-v2.ts >$AQUI/sim-wompi.log 2>&1 &
P1=$!

# La Edge Function real, con los secretos de EVENTOS falsos.
SUPABASE_URL=http://localhost:54321 \
SUPABASE_SERVICE_ROLE_KEY=$LLAVE \
WOMPI_EVENTS_SANDBOX=test_events_SECRETOFALSOsandbox123456 \
WOMPI_EVENTS_PROD=prod_events_SECRETOFALSOprod123456789 \
  deno run -q --allow-net --allow-env $REPO/supabase/functions/wompi-webhook/index.ts >$AQUI/fn-wompi.log 2>&1 &
P2=$!

for i in $(seq 1 40); do curl -s -o /dev/null localhost:8000 && curl -s -o /dev/null localhost:54321 && break; sleep 0.5; done
deno run -q -A $AQUI/probar-wompi-webhook.ts

echo "== los logs no deben filtrar secretos ni datos de personas"
if grep -q -i -e "events_SECRETOFALSO" -e "$LLAVE" -e "cw@cliente" $AQUI/fn-wompi.log; then
  echo "FALLA | los logs filtran secretos o datos"
else
  echo "pasa | logs sin secretos de eventos, llaves ni correos"
fi
kill $P1 $P2 2>/dev/null
