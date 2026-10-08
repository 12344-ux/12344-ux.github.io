#!/usr/bin/env bash
# ============================================================
# Impulse · prueba la puesta al dia FORWARD (20261018000000) sobre una base que
# REPRODUCE PRODUCCION: todas las migraciones EN ORDEN pero OMITIENDO
# 20261002000000 (que nunca se aplico alla) y OMITIENDO 20261018000000 (la
# aplica el propio SQL de prueba, para medir el antes y el despues).
#
# Por que existe: el arnes normal (pg.sh) aplica TODAS las migraciones, asi que
# da falsa confianza sobre cm_publicar_campana (local la tiene con candado,
# produccion no). Esto cierra esa divergencia.
#
# Uso (todo en UNA invocacion; los procesos no sobreviven entre llamadas):
#   bash supabase/pruebas/local/herramientas/correr-puesta-al-dia.sh
# ============================================================
set -uo pipefail
D=/var/lib/pgdata
REPO=/projects/sandbox/12344-ux.github.io
AQUI=/projects/sandbox/pruebas-em5
BD=puesta_al_dia

if [ ! -f $D/PG_VERSION ]; then
  sudo mkdir -p $D && sudo chown pg:pg $D && sudo chmod 700 $D
  sudo -u pg initdb -D $D -U postgres --auth=trust >/dev/null
fi
sudo -u pg pg_ctl -D $D -l $D/pglog.log -o "-k $D -c listen_addresses=''" status >/dev/null 2>&1 || \
  sudo -u pg pg_ctl -D $D -l $D/pglog.log -o "-k $D -c listen_addresses=''" -w start >/dev/null
export PGHOST=$D PGUSER=postgres

psql -v ON_ERROR_STOP=1 -q -d postgres -c "drop database if exists $BD" -c "create database $BD" >/dev/null
psql -v ON_ERROR_STOP=1 -q -d $BD -f $REPO/supabase/pruebas/local/supabase-simulado.sql >/dev/null
psql -v ON_ERROR_STOP=1 -q -d $BD -f $AQUI/storage-minimo.sql >/dev/null

n=0; omitidas=""
for f in $REPO/supabase/migrations/*.sql; do
  b=$(basename "$f")
  case "$b" in
    20261002000000_*|20261018000000_*) omitidas="$omitidas $b"; continue ;;
  esac
  psql -v ON_ERROR_STOP=1 -q -d $BD -f "$f" >/dev/null 2>$AQUI/ultimo-error.txt || {
    echo "FALLA migracion $b"; cat $AQUI/ultimo-error.txt; exit 1; }
  n=$((n+1))
done
echo "== $n migraciones aplicadas · OMITIDAS a proposito:$omitidas"

psql -v ON_ERROR_STOP=1 -q -d $BD -f $REPO/supabase/pruebas/local/puesta-al-dia-forward.sql -t -A

# La matriz de permisos DESPUES de la migracion nueva: nada se abrio de mas.
echo "== matriz de permisos (tras la puesta al dia forward)"
psql -v ON_ERROR_STOP=1 -q -d $BD -f $REPO/supabase/pruebas/matriz-permisos.sql -t -A -F' | ' > $AQUI/matriz-pad.txt 2>&1 || {
  tail -20 $AQUI/matriz-pad.txt; exit 1; }
grep -m2 -i "TODO PASA\|FALLA" $AQUI/matriz-pad.txt | head -3
