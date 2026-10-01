#!/usr/bin/env bash
# ============================================================
# Impulse · Corre TODAS las migraciones + las pruebas sobre un PostgreSQL
# LOCAL (nunca contra Supabase). Sirve para verificar con evidencia, antes de
# que el dueno pegue nada en el SQL Editor, que:
#   1) las migraciones aplican en orden y sin errores sobre una base vacia;
#   2) la matriz de permisos (RLS + EXECUTE) da lo esperado.
#
# Requisitos: psql y un servidor PostgreSQL 15+ accesible.
# Uso:
#   PGHOST=... PGPORT=... PGUSER=postgres ./supabase/pruebas/local/correr-local.sh
# La base de pruebas (por defecto impulse_pruebas) se BORRA y se recrea.
# ============================================================
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
RAIZ="$(cd "$AQUI/../../.." && pwd)"
BD="${BD_PRUEBAS:-impulse_pruebas}"

psql -v ON_ERROR_STOP=1 -q -d postgres -c "drop database if exists $BD" -c "create database $BD"

echo "== Entorno simulado de Supabase"
psql -v ON_ERROR_STOP=1 -q -d "$BD" -f "$AQUI/supabase-simulado.sql"

echo "== Migraciones (en orden)"
for f in "$RAIZ"/supabase/migrations/*.sql; do
  echo "   $(basename "$f")"
  psql -v ON_ERROR_STOP=1 -q -d "$BD" -f "$f" >/dev/null
done

echo "== Matriz de permisos"
psql -v ON_ERROR_STOP=1 -q -d "$BD" -f "$RAIZ/supabase/pruebas/matriz-permisos.sql"
