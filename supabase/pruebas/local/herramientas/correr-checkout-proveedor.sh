#!/usr/bin/env bash
# ============================================================================
# MAGANDHI · D2c.2c · verificación en vivo antes de cobrar
# ----------------------------------------------------------------------------
# Ejecuta crear-intencion-pago REAL contra dobles de PostgREST y de Dropi.
# No toca red real, token real ni Wompi.
# ============================================================================
set -euo pipefail
AQUI=/projects/sandbox/pruebas-em5
REPO=/projects/sandbox/12344-ux.github.io
export REPO
export PATH="$AQUI/deno/bin:${PATH}"
"$AQUI/deno/bin/deno" run -q -A "$AQUI/probar-checkout-proveedor.ts"
