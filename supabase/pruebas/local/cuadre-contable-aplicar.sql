-- ============================================================================
-- Impulse · BANCO DE PRUEBAS · el script de cuadre del 14-oct-2026, DE VERDAD
-- ----------------------------------------------------------------------------
-- Corre el MISMO archivo que se le entrega al dueño para pegar en el SQL Editor
-- (supabase/operacion/cuadre-contable-2026-10-14.sql), sobre un estado que
-- imita producción, y comprueba las tres cosas que importan:
--
--   FASE 1 · si falta el asiento automático del COSTO del pedido de proveedor,
--            el script DEBE FALLAR y NO DEJAR NADA ESCRITO (la transacción
--            entera se deshace). Es la red de seguridad.
--   FASE 2 · con el estado completo, DEBE PASAR y dejar los saldos exactos.
--   FASE 3 · correrlo DOS VECES no duplica nada (es idempotente).
--
-- Uso: bash pgrun.sh 12344-ux.github.io/supabase/pruebas/local/cuadre-contable-aplicar.sql
-- ============================================================================
\pset pager off
\set ON_ERROR_STOP on

create temp table res (n int, prueba text, esperado text, obtenido text, veredicto text);
create or replace function pg_temp.ok(n int, prueba text, esperado text, obtenido text)
returns void language sql as $$
  insert into res values (n, prueba, esperado, obtenido,
    case when esperado = obtenido then 'PASA' else 'FALLA' end);
$$;

create or replace function pg_temp.neto(cuenta text) returns bigint
language sql as $$
  select coalesce(sum(l.debe - l.haber), 0)::bigint
    from asiento_lineas l join asientos a on a.id = l.asiento_id
   where a.estado = 'activo' and l.cuenta_codigo like cuenta;
$$;

-- Registra un asiento actuando como el admin, igual que lo hace el script real.
create or replace function pg_temp.sembrar(fecha date, descr text, lineas jsonb)
returns void language plpgsql as $$
declare v_admin uuid;
begin
  select id into v_admin from perfiles where rol = 'admin' order by creado limit 1;
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
  perform guardar_asiento(fecha, descr, lineas);
end $$;

-- ----------------------------------------------------------------------------
-- Estado que imita producción: los DOS asientos AUTOMÁTICOS de las ventas.
-- El del cubo (proveedor) lleva dentro el costo y el flete, pero NO el seguro:
-- pedido_proveedor no tiene columna donde guardarlo.
-- ----------------------------------------------------------------------------
select pg_temp.sembrar('2026-10-09', 'Venta web 69.900 (automatico F3)',
  '[{"cuenta_codigo":"138095","debe":69900,"haber":0},
     {"cuenta_codigo":"413505","debe":0,"haber":69900},
     {"cuenta_codigo":"613505","debe":47705,"haber":0},
     {"cuenta_codigo":"143505","debe":0,"haber":47705}]'::jsonb);

-- ============================ FASE 1 ========================================
-- Falta el asiento del cubo. El script tiene que negarse y no escribir nada.
\echo ''
\echo '>>> FASE 1 · falta el asiento del cubo: el script DEBE fallar'
\set ON_ERROR_STOP off
\i /projects/sandbox/12344-ux.github.io/supabase/operacion/cuadre-contable-2026-10-14.sql
\set ON_ERROR_STOP on

select pg_temp.ok(1, 'FASE 1 · no escribio ningun asiento de cuadre', '0',
  (select count(*)::text from asientos where descripcion like 'Cuadre 14-oct-2026%'));
select pg_temp.ok(2, 'FASE 1 · el inventario sigue como estaba (sin apertura)',
  (-47705)::text, pg_temp.neto('143505')::text);
select pg_temp.ok(3, 'FASE 1 · el banco sigue vacio', '0', pg_temp.neto('111005')::text);
-- Las cuentas nuevas tampoco quedan: la transaccion se deshizo entera.
select pg_temp.ok(4, 'FASE 1 · tampoco creo las cuentas nuevas', '0',
  (select count(*)::text from puc_cuentas where codigo in ('3130','313005','5230','523095')));

-- ============================ FASE 2 ========================================
-- Llega el asiento automatico del cubo, con costo y flete contra el saldo Dropi.
select pg_temp.sembrar('2026-10-10', 'Venta web 30.000 proveedor (automatico F3)',
  '[{"cuenta_codigo":"138095","debe":30000,"haber":0},
     {"cuenta_codigo":"413505","debe":0,"haber":30000},
     {"cuenta_codigo":"613505","debe":7200,"haber":0},
     {"cuenta_codigo":"523535","debe":14910,"haber":0},
     {"cuenta_codigo":"138010","debe":0,"haber":22110}]'::jsonb);

\echo ''
\echo '>>> FASE 2 · estado completo: el script DEBE pasar'
\i /projects/sandbox/12344-ux.github.io/supabase/operacion/cuadre-contable-2026-10-14.sql

select pg_temp.ok(10, 'FASE 2 · registro los 4 asientos de cuadre', '4',
  (select count(*)::text from asientos where descripcion like 'Cuadre 14-oct-2026%' and estado = 'activo'));
select pg_temp.ok(11, 'FASE 2 · creo las 4 cuentas nuevas', '4',
  (select count(*)::text from puc_cuentas where codigo in ('3130','313005','5230','523095')));
select pg_temp.ok(12, 'FASE 2 · 3130 es de naturaleza credito y 313005 imputable', 'credito|true',
  (select (select naturaleza from puc_cuentas where codigo = '3130') || '|' ||
          (select imputable from puc_cuentas where codigo = '313005')::text));
select pg_temp.ok(13, 'FASE 2 · banco (111005) = 95.082', '95082', pg_temp.neto('111005')::text);
select pg_temp.ok(14, 'FASE 2 · saldo en Dropi (138010) = 27.136', '27136', pg_temp.neto('138010')::text);
select pg_temp.ok(15, 'FASE 2 · Wompi por liquidar (138095) = 0', '0', pg_temp.neto('138095')::text);
select pg_temp.ok(16, 'FASE 2 · inventario (143505) = 47.705 (1 shampoo)', '47705', pg_temp.neto('143505')::text);
select pg_temp.ok(17, 'FASE 2 · capital aportado (3130) = 145.410', '145410', (-pg_temp.neto('3130%'))::text);
select pg_temp.ok(18, 'FASE 2 · seguro en 523095 = 754', '754', pg_temp.neto('523095')::text);
select pg_temp.ok(19, 'FASE 2 · comision Wompi (530515) = 4.818', '4818', pg_temp.neto('530515')::text);
select pg_temp.ok(20, 'FASE 2 · flete (523535) = 14.910', '14910', pg_temp.neto('523535')::text);
select pg_temp.ok(21, 'FASE 2 · costo de ventas (613505) = 54.905', '54905', pg_temp.neto('613505')::text);
select pg_temp.ok(22, 'FASE 2 · ingresos (413505) = 99.900', '99900', (-pg_temp.neto('413505'))::text);

-- PLATA y utilidad, que es lo que el dueño preguntó.
select pg_temp.ok(23, 'FASE 2 · PLATA total = 122.218', '122218',
  (pg_temp.neto('111005') + pg_temp.neto('138095') + pg_temp.neto('138010'))::text);
select pg_temp.ok(24, 'FASE 2 · utilidad del ejercicio = 24.513', '24513',
  (select (coalesce(sum(l.haber-l.debe) filter (where l.cuenta_codigo like '4%'),0)
         - coalesce(sum(l.debe-l.haber) filter (where l.cuenta_codigo similar to '(5|6|7)%'),0))::text
     from asiento_lineas l join asientos a on a.id = l.asiento_id where a.estado='activo'));

-- Partida doble y cuadre del balance.
select pg_temp.ok(25, 'FASE 2 · partida doble: debe = haber',
  (select coalesce(sum(l.debe),0)::text from asiento_lineas l join asientos a on a.id=l.asiento_id where a.estado='activo'),
  (select coalesce(sum(l.haber),0)::text from asiento_lineas l join asientos a on a.id=l.asiento_id where a.estado='activo'));
select pg_temp.ok(26, 'FASE 2 · activo = pasivo + patrimonio + resultado',
  (select coalesce(sum(l.debe-l.haber) filter (where l.cuenta_codigo like '1%'),0)::text
     from asiento_lineas l join asientos a on a.id=l.asiento_id where a.estado='activo'),
  (select (coalesce(sum(l.haber-l.debe) filter (where l.cuenta_codigo like '2%'),0)
         + coalesce(sum(l.haber-l.debe) filter (where l.cuenta_codigo like '3%'),0)
         + coalesce(sum(l.haber-l.debe) filter (where l.cuenta_codigo like '4%'),0)
         - coalesce(sum(l.debe-l.haber) filter (where l.cuenta_codigo similar to '(5|6|7)%'),0))::text
     from asiento_lineas l join asientos a on a.id=l.asiento_id where a.estado='activo'));

-- ============================ FASE 3 ========================================
-- Correrlo otra vez no debe duplicar nada.
\echo ''
\echo '>>> FASE 3 · segunda corrida: no debe duplicar'
\i /projects/sandbox/12344-ux.github.io/supabase/operacion/cuadre-contable-2026-10-14.sql

select pg_temp.ok(30, 'FASE 3 · sigue habiendo 4 asientos de cuadre, no 8', '4',
  (select count(*)::text from asientos where descripcion like 'Cuadre 14-oct-2026%' and estado = 'activo'));
select pg_temp.ok(31, 'FASE 3 · el saldo en Dropi no se movio', '27136', pg_temp.neto('138010')::text);
select pg_temp.ok(32, 'FASE 3 · la PLATA no se movio', '122218',
  (pg_temp.neto('111005') + pg_temp.neto('138095') + pg_temp.neto('138010'))::text);

-- ---------------------------------------------------------------------------
select n, prueba, esperado, obtenido, veredicto from res order by n;
select veredicto, count(*) as cuantas from res group by veredicto order by veredicto;
