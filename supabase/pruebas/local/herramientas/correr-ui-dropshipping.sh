#!/usr/bin/env bash
# ============================================================================
# MAGANDHI · Dropshipping en Chromium (PC 1280 y celular 390)
# ----------------------------------------------------------------------------
# Levanta un doble de Dropi/Supabase Auth (:8810) con la forma REAL de los datos
# (urlS3 relativo, count = 0, variantes con attribute_values) y la Edge
# Function REAL dropi-sonda (:8811). Luego corre:
#   · probar-ui-dropshipping-d1.py  -> búsqueda, fotos, paginación, carrito
#   · probar-ui-dropshipping-d2a.py -> Llevar a Campañas + editor modo proveedor
# Storage, bandeja y RPC se simulan en memoria con las reglas de la migración.
# No toca Dropi, Supabase ni secretos reales.
# Uso: correr-ui-dropshipping.sh [carpeta-de-capturas]
# ============================================================================
set -uo pipefail
AQUI=/projects/sandbox/pruebas-em5
REPO=/projects/sandbox/12344-ux.github.io
DENO="$AQUI/deno/bin/deno"
PY="$AQUI/venv/bin/python"
CAPS="${1:-}"

"$DENO" run -q -A "$AQUI/doble-dropi-ui.ts" >/tmp/doble-dropi-ui.log 2>&1 &
P1=$!
SUPABASE_URL=http://127.0.0.1:8810 SUPABASE_ANON_KEY=anon \
DROPI_API_BASE=http://127.0.0.1:8810/integrations/ DROPI_TOKEN=token-falso \
PUERTO_FN=8811 MODULO_FN="$REPO/supabase/functions/dropi-sonda/index.ts" \
  "$DENO" run -q -A "$AQUI/en-puerto.ts" >/tmp/dropi-sonda-ui.log 2>&1 &
P2=$!
sleep 4

R=0
"$PY" "$AQUI/probar-ui-dropshipping-d1.py" $CAPS || R=1
"$PY" "$AQUI/probar-ui-dropshipping-d2a.py" $CAPS || R=1
kill $P1 $P2 2>/dev/null
exit $R
