#!/usr/bin/env bash
# Arranca PostgreSQL local (si no corre), recrea la base con TODAS las
# migraciones + matriz, y luego ejecuta los SQL extra que se pasen como args.
# Uso: pg.sh [archivo.sql ...]   (todo en UNA invocacion: los procesos no sobreviven)
set -euo pipefail
D=/var/lib/pgdata
REPO=/projects/sandbox/12344-ux.github.io
AQUI=/projects/sandbox/pruebas-em5
if [ ! -f $D/PG_VERSION ]; then
  sudo mkdir -p $D && sudo chown pg:pg $D && sudo chmod 700 $D
  sudo -u pg initdb -D $D -U postgres --auth=trust >/dev/null
fi
sudo -u pg pg_ctl -D $D -l $D/pglog.log -o "-k $D -c listen_addresses=''" status >/dev/null 2>&1 || {
  # Restos de un servidor que el sandbox mato entre llamadas: si quedan, el PID
  # reutilizado hace creer a Postgres que el socket sigue ocupado.
  sudo rm -f $D/postmaster.pid $D/.s.PGSQL.5432.lock
  sudo -u pg pg_ctl -D $D -l $D/pglog.log -o "-k $D -c listen_addresses=''" -w start >/dev/null
}
export PGHOST=$D PGUSER=postgres
BD=impulse_pruebas
psql -v ON_ERROR_STOP=1 -q -d postgres -c "drop database if exists $BD" -c "create database $BD" >/dev/null
psql -v ON_ERROR_STOP=1 -q -d $BD -f $REPO/supabase/pruebas/local/supabase-simulado.sql >/dev/null
psql -v ON_ERROR_STOP=1 -q -d $BD -f $AQUI/storage-minimo.sql >/dev/null
n=0
for f in $REPO/supabase/migrations/*.sql; do
  psql -v ON_ERROR_STOP=1 -q -d $BD -f "$f" >/dev/null 2>$AQUI/ultimo-error.txt || { echo "FALLA migracion $(basename $f)"; cat $AQUI/ultimo-error.txt; exit 1; }
  n=$((n+1))
done
echo "== $n migraciones aplicadas"
psql -v ON_ERROR_STOP=1 -q -d $BD -f $REPO/supabase/pruebas/matriz-permisos.sql -t -A -F' | ' > $AQUI/matriz.txt 2>&1 || { tail -20 $AQUI/matriz.txt; exit 1; }
psql -q -d $BD -t -A -c "select veredicto, count(*) from tramo0_resultado group by 1" 2>/dev/null || true
grep -m3 -i "TODO PASA\|FALLA" $AQUI/matriz.txt | head -5
for extra in "$@"; do
  echo "== $extra"
  psql -v ON_ERROR_STOP=1 -q -d $BD -f "$extra" -t -A
done
