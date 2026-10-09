#!/usr/bin/env bash
# ============================================================
# Impulse · prueba el CICLO COMPLETO de F3 con las Edge Functions REALES:
#   tienda -> crear-intencion-pago (PRODUCCION simulada, llaves falsas)
#   -> wompi-webhook (firma real de produccion) -> pw_procesar_pago
#   -> pedido + ASIENTO CONTABLE
#   -> enviar-correo-pedido (modo automatico) -> Resend falso: «Recibido».
# Nada toca Supabase, Wompi ni Resend reales.
# Todo en UNA invocacion (los procesos no sobreviven entre llamadas).
# Uso: bash supabase/pruebas/local/herramientas/correr-ciclo-f3.sh
# ============================================================
set -uo pipefail
export PATH=/projects/sandbox/pruebas-em5/deno/bin:$PATH
AQUI=/projects/sandbox/pruebas-em5
REPO=/projects/sandbox/12344-ux.github.io

sudo rm -f /var/lib/pgdata/postmaster.pid 2>/dev/null
$AQUI/pg.sh >/dev/null 2>&1 || { echo "fallo pg.sh"; exit 1; }
export PGHOST=/var/lib/pgdata PGUSER=postgres

# Semilla: producto con costo y 5 unidades, campana publicada y ligada,
# Wompi en PRODUCCION (simulada) y el IVA ya definido por el dueno.
psql -v ON_ERROR_STOP=1 -q -d impulse_pruebas <<'SQL'
insert into productos (id, sku, nombre, precio_venta, costo_unitario, activo)
  values ('b4000000-0000-4000-8000-000000000001', 'C3-P1', 'Shampoo ciclo F3', 69900, 25000, true);
insert into movimientos_inventario (product_id, tipo, cantidad, motivo)
  values ('b4000000-0000-4000-8000-000000000001', 'entrada', 5, 'semilla ciclo F3');
insert into campana_producto (id, nombre, slug, precio_venta, product_id_ref, publicado, activo)
  values ('a4000000-0000-4000-8000-000000000001', 'Shampoo ciclo F3', 'c3-p1', 69900,
          'b4000000-0000-4000-8000-000000000001', true, true);
update pagos_config set entorno = 'prod', llave_publica_prod = 'pub_prod_LLAVEPUBLICAFALSA' where id = 1;
update contabilidad_config set iva_ventas_pct = 0 where id = 1;
SQL

LLAVE="servicio-falsa-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
export LLAVE_SERVICIO_FALSA=$LLAVE
deno run -q -A $AQUI/simulador-v2.ts >$AQUI/sim-f3.log 2>&1 &
P1=$!

# crear-intencion-pago :8002 · enviar-correo-pedido :8001 · wompi-webhook :8000
SUPABASE_URL=http://localhost:54321 SUPABASE_SERVICE_ROLE_KEY=$LLAVE \
WOMPI_INTEGRITY_PROD=prod_integrity_SECRETOFALSO123456 \
PUERTO_FN=8002 MODULO_FN=$REPO/supabase/functions/crear-intencion-pago/index.ts \
  deno run -q -A $AQUI/en-puerto.ts >$AQUI/fn-f3-int.log 2>&1 &
P2=$!
SUPABASE_URL=http://localhost:54321 SUPABASE_SERVICE_ROLE_KEY=$LLAVE SUPABASE_ANON_KEY=anon-falsa-ciclo-f3 \
RESEND_API_KEY=re_FALSA_ciclo_f3 RESEND_API_URL=http://localhost:54322/emails \
PUERTO_FN=8001 MODULO_FN=$REPO/supabase/functions/enviar-correo-pedido/index.ts \
  deno run -q -A $AQUI/en-puerto.ts >$AQUI/fn-f3-correo.log 2>&1 &
P3=$!
SUPABASE_URL=http://localhost:54321 SUPABASE_SERVICE_ROLE_KEY=$LLAVE \
WOMPI_EVENTS_SANDBOX=test_events_SECRETOFALSOsandbox123456 \
WOMPI_EVENTS_PROD=prod_events_SECRETOFALSOprod123456789 \
CORREO_FUNCION_URL=http://localhost:8001 \
  deno run -q --allow-net --allow-env $REPO/supabase/functions/wompi-webhook/index.ts >$AQUI/fn-f3-wh.log 2>&1 &
P4=$!

for i in $(seq 1 60); do
  curl -s -o /dev/null localhost:8000 && curl -s -o /dev/null localhost:8001 && \
  curl -s -o /dev/null localhost:8002 && curl -s -o /dev/null localhost:54321 && break
  sleep 0.5
done
LLAVE_SERVICIO=$LLAVE deno run -q -A $AQUI/probar-ciclo-f3.ts

echo "== los logs no deben filtrar secretos ni datos de personas"
if grep -q -i -e "SECRETOFALSO" -e "$LLAVE" -e "re_FALSA" -e "eva@cliente" -e "fede@cliente" \
     -e "gina@cliente" -e "Compradora" $AQUI/fn-f3-int.log $AQUI/fn-f3-correo.log $AQUI/fn-f3-wh.log; then
  echo "FALLA | los logs filtran secretos o datos"
else
  echo "pasa | logs sin secretos, llaves, nombres ni correos de clientes"
fi
kill $P1 $P2 $P3 $P4 2>/dev/null
