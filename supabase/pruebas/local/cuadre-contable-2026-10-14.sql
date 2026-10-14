-- ============================================================
-- Impulse · BANCO DE PRUEBAS · cuadre contable del 14-oct-2026
-- ------------------------------------------------------------
-- Comprueba que los asientos de cuadre que se le entregan al dueño:
--   (1) los ACEPTA el validador server-side (fz_validar_lineas / guardar_asiento),
--   (2) dejan el libro cuadrado (debe = haber y activo = pasivo+patrimonio+resultado),
--   (3) producen EXACTAMENTE la plata y los saldos esperados.
--
-- Lo hace con DOS juegos distintos de costo/flete del cubo (que al escribir esta
-- prueba todavía no se conocían) para demostrar que el cuadre NO depende de
-- esos dos números: la identidad se sostiene para cualquiera.
--
-- Uso: bash pgrun.sh 12344-ux.github.io/supabase/pruebas/local/cuadre-contable-2026-10-14.sql
-- ============================================================
\set ON_ERROR_STOP on
\pset pager off

-- ------------------------------------------------------------
-- Arnés: correr como el admin autenticado (igual que las demás suites).
-- ------------------------------------------------------------
create or replace function pg_temp.como(uid text, q text) returns text
language plpgsql as $$
declare x text;
begin
  execute 'set role authenticated';
  perform set_config('request.jwt.claims',
                     json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute q into x;
  execute 'reset role';
  return x;
exception when others then
  execute 'reset role';
  return 'ERROR: ' || sqlerrm;
end $$;

create or replace function pg_temp.asiento(fecha date, descr text, lineas jsonb) returns text
language sql as $$
  select pg_temp.como('89e5028d-8c17-4deb-89c3-59acbd0ee2f2',
    format('select guardar_asiento(%L::date, %L, %L::jsonb)::text', fecha, descr, lineas));
$$;

-- Saldo neto (debe - haber) de una cuenta, solo asientos activos.
create or replace function pg_temp.neto(cuenta text) returns bigint
language sql as $$
  select coalesce(sum(l.debe - l.haber), 0)::bigint
    from asiento_lineas l join asientos a on a.id = l.asiento_id
   where a.estado = 'activo' and l.cuenta_codigo = cuenta;
$$;

create temp table res (n int, prueba text, esperado text, obtenido text, veredicto text);
create or replace function pg_temp.ok(n int, prueba text, esperado text, obtenido text)
returns void language sql as $$
  insert into res values (n, prueba, esperado, obtenido,
    case when esperado = obtenido then 'PASA' else 'FALLA' end);
$$;

-- ------------------------------------------------------------
-- El escenario, parametrizado en costo y flete del cubo.
-- ------------------------------------------------------------
create or replace function pg_temp.escenario(p_costo bigint, p_flete bigint)
returns void language plpgsql as $$
declare
  r text;
begin
  -- Libro limpio para cada corrida. La bitácora es append-only por diseño (en
  -- producción NUNCA se borra); aquí se limpia porque es un banco de pruebas y
  -- su FK impide reutilizar el libro entre los dos juegos de números.
  delete from asiento_bitacora; delete from asiento_lineas; delete from asientos;

  -- (1) Aporte de capital en mercancía: los dos shampoos.
  r := pg_temp.asiento('2026-10-01', 'Aporte de capital del dueno en mercancia: 2 shampoos',
    '[{"cuenta_codigo":"143505","detalle":"2 shampoos a 47.705","debe":95410,"haber":0},
       {"cuenta_codigo":"310505","detalle":"aporte del dueno","debe":0,"haber":95410}]'::jsonb);
  if r like 'ERROR%' then raise exception 'asiento 1 rechazado: %', r; end if;

  -- (2) Aporte de capital en efectivo para recargar Dropi.
  r := pg_temp.asiento('2026-10-10', 'Aporte de capital del dueno: recarga del saldo en Dropi',
    '[{"cuenta_codigo":"138010","detalle":"recarga en el panel de Dropi","debe":50000,"haber":0},
       {"cuenta_codigo":"310505","detalle":"aporte del dueno","debe":0,"haber":50000}]'::jsonb);
  if r like 'ERROR%' then raise exception 'asiento 2 rechazado: %', r; end if;

  -- (3) Venta del shampoo (lo que ya hizo el asiento AUTOMATICO de F3).
  r := pg_temp.asiento('2026-10-09', 'Venta web shampoo (automatico F3)',
    '[{"cuenta_codigo":"138095","detalle":"Wompi por liquidar","debe":69900,"haber":0},
       {"cuenta_codigo":"413505","detalle":"venta","debe":0,"haber":69900},
       {"cuenta_codigo":"613505","detalle":"costo","debe":47705,"haber":0},
       {"cuenta_codigo":"143505","detalle":"salida de inventario","debe":0,"haber":47705}]'::jsonb);
  if r like 'ERROR%' then raise exception 'asiento 3 rechazado: %', r; end if;

  -- (4) Venta del cubo, producto de PROVEEDOR: no descarga inventario.
  r := pg_temp.asiento('2026-10-10', 'Venta web cubo proveedor (automatico F3)',
    '[{"cuenta_codigo":"138095","detalle":"Wompi por liquidar","debe":30000,"haber":0},
       {"cuenta_codigo":"413505","detalle":"venta","debe":0,"haber":30000}]'::jsonb);
  if r like 'ERROR%' then raise exception 'asiento 4 rechazado: %', r; end if;

  -- (5) Costo del pedido de proveedor: mercancia + flete contra el saldo en Dropi.
  r := pg_temp.asiento('2026-10-10', 'Costo del pedido en Dropi: mercancia y flete',
    format('[{"cuenta_codigo":"613505","detalle":"costo de la mercancia","debe":%s,"haber":0},
             {"cuenta_codigo":"523535","detalle":"flete","debe":%s,"haber":0},
             {"cuenta_codigo":"138010","detalle":"descontado del saldo en Dropi","debe":0,"haber":%s}]',
           p_costo, p_flete, p_costo + p_flete)::jsonb);
  if r like 'ERROR%' then raise exception 'asiento 5 rechazado: %', r; end if;

  -- (6) El SEGURO del pedido, que se habia quedado sin contabilizar.
  r := pg_temp.asiento('2026-10-10', 'Seguro del pedido en Dropi (Asegurar pedido)',
    '[{"cuenta_codigo":"523535","detalle":"seguro del envio","debe":755,"haber":0},
       {"cuenta_codigo":"138010","detalle":"descontado del saldo en Dropi","debe":0,"haber":755}]'::jsonb);
  if r like 'ERROR%' then raise exception 'asiento 6 rechazado: %', r; end if;

  -- (7) Liquidacion de Wompi: el neto al banco y la comision como gasto.
  r := pg_temp.asiento('2026-10-13', 'Liquidacion Wompi de las dos ventas',
    '[{"cuenta_codigo":"111005","detalle":"consignado por Wompi","debe":95082,"haber":0},
       {"cuenta_codigo":"530515","detalle":"comision 2,65% + 700 + IVA, dos transacciones","debe":4818,"haber":0},
       {"cuenta_codigo":"138095","detalle":"se cierra la cuenta puente","debe":0,"haber":99900}]'::jsonb);
  if r like 'ERROR%' then raise exception 'asiento 7 rechazado: %', r; end if;
end $$;

-- ------------------------------------------------------------
-- Comprobaciones, con dos juegos de costo/flete.
-- ------------------------------------------------------------
create or replace function pg_temp.verificar(p_costo bigint, p_flete bigint, base int)
returns void language plpgsql as $$
declare
  v_debe bigint; v_haber bigint;
  v_activo bigint; v_pasivo bigint; v_patrim bigint; v_ing bigint; v_cg bigint;
  v_plata bigint;
begin
  perform pg_temp.escenario(p_costo, p_flete);

  select coalesce(sum(l.debe),0), coalesce(sum(l.haber),0) into v_debe, v_haber
    from asiento_lineas l join asientos a on a.id = l.asiento_id where a.estado='activo';

  select coalesce(sum(l.debe-l.haber) filter (where l.cuenta_codigo like '1%'),0),
         coalesce(sum(l.haber-l.debe) filter (where l.cuenta_codigo like '2%'),0),
         coalesce(sum(l.haber-l.debe) filter (where l.cuenta_codigo like '3%'),0),
         coalesce(sum(l.haber-l.debe) filter (where l.cuenta_codigo like '4%'),0),
         coalesce(sum(l.debe-l.haber) filter (where l.cuenta_codigo similar to '(5|6|7)%'),0)
    into v_activo, v_pasivo, v_patrim, v_ing, v_cg
    from asiento_lineas l join asientos a on a.id = l.asiento_id where a.estado='activo';

  v_plata := pg_temp.neto('111005') + pg_temp.neto('110505')
           + pg_temp.neto('138095') + pg_temp.neto('138010');

  perform pg_temp.ok(base + 1, 'Los 7 asientos los acepta el validador', 'si', 'si');
  perform pg_temp.ok(base + 2, 'Partida doble: total debe = total haber',
                     v_debe::text, v_haber::text);
  perform pg_temp.ok(base + 3, 'Activo = Pasivo + Patrimonio + Resultado',
                     v_activo::text, (v_pasivo + v_patrim + (v_ing - v_cg))::text);
  perform pg_temp.ok(base + 4, 'Wompi por liquidar (138095) queda en cero',
                     '0', pg_temp.neto('138095')::text);
  perform pg_temp.ok(base + 5, 'Saldo en Dropi (138010) = 50.000 - costo - flete - 755',
                     (50000 - p_costo - p_flete - 755)::text, pg_temp.neto('138010')::text);
  perform pg_temp.ok(base + 6, 'Inventario (143505) = 1 shampoo = 47.705',
                     '47705', pg_temp.neto('143505')::text);
  perform pg_temp.ok(base + 7, 'Capital aportado (310505) = 145.410',
                     '145410', (-pg_temp.neto('310505'))::text);
  perform pg_temp.ok(base + 8, 'Ingresos (413505) = 99.900',
                     '99900', (-pg_temp.neto('413505'))::text);
  perform pg_temp.ok(base + 9, 'Banco (111005) = 95.082',
                     '95082', pg_temp.neto('111005')::text);
  perform pg_temp.ok(base + 10, 'PLATA total = 144.327 - costo - flete',
                     (144327 - p_costo - p_flete)::text, v_plata::text);
  perform pg_temp.ok(base + 11, 'Resultado del ejercicio = 46.622 - costo - flete',
                     (46622 - p_costo - p_flete)::text, (v_ing - v_cg)::text);
  perform pg_temp.ok(base + 12, 'Activo total = 192.032 - costo - flete',
                     (192032 - p_costo - p_flete)::text, v_activo::text);
end $$;

-- Juego A y juego B: dos costos/fletes distintos, mismas identidades.
select pg_temp.verificar(12000, 8000, 100);
select pg_temp.verificar(18500, 13200, 200);

-- ------------------------------------------------------------
-- Resultado
-- ------------------------------------------------------------
select n, prueba, esperado, obtenido, veredicto from res order by n;
select veredicto, count(*) as cuantas from res group by veredicto order by veredicto;
