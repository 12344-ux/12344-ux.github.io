#!/usr/bin/env bash
# ============================================================================
# MAGANDHI · Ventas · Despachos de proveedor en Chromium (PC 1280 y celular 390)
# ----------------------------------------------------------------------------
# No necesita el doble de Dropi ni Edge Functions: lo que mide es la PANTALLA.
# ds_pedidos_por_transcribir y ds_registrar_transcripcion se responden desde
# Python con las formas exactas que devuelven en produccion.
# Uso: correr-ui-despachos.sh [carpeta-de-capturas]
# ============================================================================
set -uo pipefail
AQUI=/projects/sandbox/pruebas-em5
"$AQUI/venv/bin/python" "$AQUI/probar-ui-despachos.py" "${1:-}"
