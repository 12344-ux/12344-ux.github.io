#!/usr/bin/env bash
# ============================================================
# Impulse · arma el BANCO DE PRUEBAS LOCAL en un sandbox nuevo (Amazon Linux
# 2023, con internet). Copia estas herramientas a /projects/sandbox/pruebas-em5
# (las rutas de los scripts apuntan ahi, FUERA del repo, para no commitear
# basura) e instala PostgreSQL 15 + contrib, Deno, Playwright + Chromium y Pillow.
# Uso:  bash supabase/pruebas/local/herramientas/preparar.sh
# Nunca toca Supabase ni Resend reales: todo es local y con llaves falsas.
# ============================================================
set -euo pipefail
AQUI="$(cd "$(dirname "$0")" && pwd)"
DEST=/projects/sandbox/pruebas-em5
mkdir -p "$DEST"
cp "$AQUI"/*.sh "$AQUI"/*.sql "$AQUI"/*.ts "$AQUI"/*.py "$DEST"/
chmod +x "$DEST"/*.sh

echo "== PostgreSQL 15 (+contrib: pgcrypto)"
sudo dnf install -y -q postgresql15-server postgresql15 postgresql15-contrib >/dev/null
id pg >/dev/null 2>&1 || sudo useradd pg

echo "== Deno"
[ -x "$DEST/deno/bin/deno" ] || (curl -fsSL https://deno.land/install.sh | DENO_INSTALL="$DEST/deno" sh -s -- -y >/dev/null 2>&1)

echo "== Playwright + Chromium + Pillow"
[ -x "$DEST/venv/bin/python" ] || python3 -m venv "$DEST/venv"
"$DEST/venv/bin/pip" install -q playwright pillow >/dev/null 2>&1
"$DEST/venv/bin/playwright" install chromium >/dev/null 2>&1   # sin --with-deps (no hay apt)

echo "== Listo. Prueba rapida:"
"$DEST/pg.sh" | tail -2
