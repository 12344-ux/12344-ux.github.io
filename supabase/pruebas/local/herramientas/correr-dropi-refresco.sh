#!/usr/bin/env bash
# ============================================================================
# MAGANDHI · D2c.1 · prueba runtime de dropi-refrescar-stock
# ----------------------------------------------------------------------------
# Ejecuta la Edge Function REAL contra dobles locales de PostgREST y de Dropi.
# No toca red real, token real, catálogo real ni orders/.
# ============================================================================
set -euo pipefail
AQUI=/projects/sandbox/pruebas-em5
REPO=/projects/sandbox/12344-ux.github.io
export REPO
export PATH="$AQUI/deno/bin:${PATH}"
"$AQUI/deno/bin/deno" run -q -A "$AQUI/probar-dropi-refresco.ts"
