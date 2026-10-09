-- ============================================================
-- Impulse · Pruebas de PAGOS WEB · F3 (asiento contable automatico)
-- Prueba la PROMESA del tramo con NUMEROS al peso, no que la funcion corra:
--   cada venta web real queda en los libros EXACTAMENTE UNA VEZ y cuadrada;
--   la venta nunca falla por contabilidad; anular deja el neto en cero.
-- SOLO LOCAL; todo se deshace al final (rollback).
-- ============================================================
\set ON_ERROR_STOP 1
set client_min_messages = warning;
drop table if exists pg_temp.r;
create temp table r (n serial, ok boolean, que text);
create or replace function pg_temp.chk(p boolean, q text) returns void language sql as
$$ insert into pg_temp.r (ok, que) values (coalesce(p, false), q) $$;
create or replace function pg_temp.err(q text) returns text language plpgsql as $$
begin execute q; return 'SIN ERROR'; exception when others then execute 'reset role'; return sqlerrm; end $$;
create or replace function pg_temp.como(uid text, q text) returns jsonb language plpgsql as $$
declare x jsonb; begin execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute q into x; execute 'reset role'; return x;
exception when others then execute 'reset role'; raise; end $$;
-- La Edge Function corre como service_role. Como en PostgREST, sus claims NO
-- traen sub (auth.uid() = null): se limpian para que no se cuele la ultima
-- persona simulada en esta misma transaccion de prueba.
create or replace function pg_temp.srv(q text) returns jsonb language plpgsql as $$
declare x jsonb; begin execute 'set local role service_role';
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute q into x; execute 'reset role'; return x;
exception when others then execute 'reset role'; raise; end $$;
-- Una compra completa: intencion firmada + aviso APPROVED de Wompi.
create or replace function pg_temp.pagar(ref text, campana uuid, precio bigint, entorno text, tx text)
returns jsonb language plpgsql as $$
begin
  perform pg_temp.srv(format($q$select pw_registrar_intencion(%L, %L::uuid, 'slug-f3', 'Producto F3', 1,
    %s::bigint, %s::bigint, %L,
    '{"nombre":"Compradora F3","correo":"f3@cliente.invalid","telefono":"3001112233","ciudad":"Tunja"}'::jsonb)$q$,
    ref, campana, precio, precio * 100, entorno));
  return pg_temp.srv(format($q$select pw_procesar_pago(%L, 'APPROVED', %L, %s::bigint, 'COP',
    'transaction.updated', 'chk', null, 'CARD', 'pagador@wompi.invalid')$q$, tx, ref, precio * 100));
end $$;
-- Pedido de una referencia.
create or replace function pg_temp.ped(ref text) returns uuid language sql as
$$ select pedido_id from pagos_intencion where referencia = ref $$;
-- Neto (debe - haber) de una cuenta en los asientos ACTIVOS de un pedido.
create or replace function pg_temp.neto(pedido uuid, cuenta text) returns bigint language sql as $$
  select coalesce(sum(l.debe - l.haber), 0)::bigint
    from asiento_lineas l join asientos a on a.id = l.asiento_id
   where a.estado = 'activo' and a.origen_ref = pedido and l.cuenta_codigo = cuenta $$;
-- Linea exacta de un asiento.
create or replace function pg_temp.linea(asiento uuid, cuenta text, d bigint, h bigint) returns boolean language sql as $$
  select exists (select 1 from asiento_lineas
                  where asiento_id = asiento and cuenta_codigo = cuenta and debe = d and haber = h) $$;

begin;
insert into auth.users (id, email) values
  ('7e700000-0000-4000-8000-0000000000a1', 'f3-ven@local.invalid'),
  ('7e700000-0000-4000-8000-0000000000a2', 'f3-fin@local.invalid'),
  ('7e700000-0000-4000-8000-0000000000a3', 'f3-sin@local.invalid') on conflict do nothing;
insert into perfiles (id, rol, modulos) values
  ('7e700000-0000-4000-8000-0000000000a1', 'prueba', '{ventas}'),
  ('7e700000-0000-4000-8000-0000000000a2', 'prueba', '{finanzas}'),
  ('7e700000-0000-4000-8000-0000000000a3', 'prueba', '{}') on conflict (id) do nothing;

-- Producto CON costo (10 u.) y producto SIN costo (3 u.), cada uno con campana.
insert into productos (id, sku, nombre, precio_venta, costo_unitario, activo) values
  ('b3000000-0000-4000-8000-000000000001', 'F3-P1', 'Shampoo F3', 69900, 25000, true),
  ('b3000000-0000-4000-8000-000000000002', 'F3-P2', 'Sin costo F3', 30000, null, true);
insert into movimientos_inventario (product_id, tipo, cantidad, motivo) values
  ('b3000000-0000-4000-8000-000000000001', 'entrada', 10, 'semilla F3'),
  ('b3000000-0000-4000-8000-000000000002', 'entrada', 3, 'semilla F3');
insert into campana_producto (id, nombre, slug, precio_venta, product_id_ref, publicado, activo) values
  ('a3000000-0000-4000-8000-000000000001', 'Shampoo F3', 'f3-p1', 69900, 'b3000000-0000-4000-8000-000000000001', true, true),
  ('a3000000-0000-4000-8000-000000000002', 'Sin costo F3', 'f3-p2', 30000, 'b3000000-0000-4000-8000-000000000002', true, true);

-- ---------- 1. Configuracion contable (H1) y cuentas del ciclo de venta ----------
select pg_temp.chk((select cuenta_banco = '111005' and cuenta_ingreso = '413505' and cuenta_comision = '530515'
   and cuenta_costo = '613505' and cuenta_inventario = '143505' and cuenta_pasarela = '138095'
   and cuenta_iva_generado = '240805' from contabilidad_config where id = 1),
  'config: las cuentas bajaron de grupo a subcuenta (111005 · 413505 · 530515 · 613505 · 143505) + puente 138095 + IVA 240805');
select pg_temp.chk((select bool_and(p.imputable) and count(*) = 7 from contabilidad_config c
   cross join lateral (values (c.cuenta_banco),(c.cuenta_ingreso),(c.cuenta_comision),(c.cuenta_costo),
                              (c.cuenta_inventario),(c.cuenta_pasarela),(c.cuenta_iva_generado)) v(cod)
   join puc_cuentas p on p.codigo = v.cod),
  'config: las 7 cuentas existen y son IMPUTABLES (la regla de oro las acepta)');
select pg_temp.chk((select imputable and naturaleza = 'debito' and padre = '1380' and nivel = 4
   from puc_cuentas where codigo = '138095'),
  'PUC: 138095 (deudores varios · Wompi por liquidar) existe, imputable, debito, hija de 1380');
select pg_temp.chk((select nombre = 'IMPUESTO DE INDUSTRIA Y COMERCIO RETENIDO' from puc_cuentas where codigo = '135518'),
  'PUC: 135518 queda con su nombre OFICIAL (reteICA de Wompi en pagos con tarjeta)');
select pg_temp.chk((select iva_ventas_pct is null from contabilidad_config where id = 1),
  'config: el IVA de las ventas NO se supone (nace vacio)');
select pg_temp.chk(pg_temp.err($q$update contabilidad_config set cuenta_ingreso = '4135' where id = 1$q$) like '%4135%es de grupo%',
  'validacion al configurar: una cuenta de grupo (4135) se rechaza con mensaje claro');
select pg_temp.chk(pg_temp.err($q$update contabilidad_config set cuenta_pasarela = '999999' where id = 1$q$) like '%999999%no existe%',
  'validacion al configurar: una cuenta inexistente se rechaza');
select pg_temp.chk(pg_temp.err($q$update contabilidad_config set iva_ventas_pct = 7 where id = 1$q$) like '%contabilidad_config_iva_valido%',
  'validacion al configurar: un IVA que no existe en Colombia (7) se rechaza');
select pg_temp.chk((select cuenta_ingreso = '413505' and cuenta_pasarela = '138095' from contabilidad_config where id = 1),
  'validacion al configurar: los intentos rechazados no cambiaron nada');

-- ---------- 2. IVA sin definir: la venta SI se crea, el asiento queda pendiente ----------
create temp table v1 as select pg_temp.pagar('REF-F3-0001', 'a3000000-0000-4000-8000-000000000001', 69900, 'prod', 'TX-F3-1') v;
select pg_temp.chk((select v->>'resultado' = 'procesado' and v->'asiento'->>'resultado' = 'pendiente'
   and v->'asiento'->>'motivo' like '%IVA%' from v1),
  'venta nunca falla por contabilidad: sin IVA definido el pago se procesa y el asiento queda pendiente con el motivo');
select pg_temp.chk((select canal = 'web' and total = 69900 and not anulado from pedidos where id = pg_temp.ped('REF-F3-0001')),
  'venta nunca falla por contabilidad: el pedido web existe con su total');
select pg_temp.chk((select existencias = 9 from stock_actual where product_id = 'b3000000-0000-4000-8000-000000000001'),
  'venta nunca falla por contabilidad: el stock bajo 10 -> 9');
select pg_temp.chk((select count(*) = 0 from asientos where origen_ref = pg_temp.ped('REF-F3-0001')),
  'venta nunca falla por contabilidad: ningun asiento a medias');
create temp table l1 as select pg_temp.como('7e700000-0000-4000-8000-0000000000a2', 'select fz_asientos_automaticos_pendientes()') v;
select pg_temp.chk((select (v->>'pendientes')::int = 1 and v->'lista'->0->>'tipo' = 'venta'
   and v->'lista'->0->>'motivo' like '%IVA%' and (v->'lista'->0->>'total')::bigint = 69900 from l1),
  'aviso de Finanzas: 1 venta web sin asiento, con el motivo ACTUAL (falta definir el IVA)');
select pg_temp.chk((select not (v::text ~* 'compradora|f3@cliente|3001112233') from l1),
  'aviso de Finanzas: sin datos personales del comprador (Finanzas no ve Ventas)');

-- ---------- 3. El dueno define IVA = 0 y genera el asiento desde el panel ----------
update contabilidad_config set iva_ventas_pct = 0 where id = 1;
select pg_temp.chk((select (pg_temp.como('7e700000-0000-4000-8000-0000000000a2', 'select fz_asientos_automaticos_pendientes()')->'lista'->0->'motivo') = 'null'::jsonb),
  'aviso de Finanzas: con el IVA definido la venta pasa a «lista para registrar» (motivo vacio)');
create temp table g1 as select pg_temp.como('7e700000-0000-4000-8000-0000000000a2',
  format('select fz_generar_asiento_automatico(%L)', pg_temp.ped('REF-F3-0001'))) v;
select pg_temp.chk((select v->>'resultado' = 'creado' from g1), 'Generar asiento: crea el asiento pendiente');
create temp table a1 as select (v->>'asiento_id')::uuid id from g1;
select pg_temp.chk((select a.origen = 'venta_web' and a.origen_ref = pg_temp.ped('REF-F3-0001') and a.estado = 'activo'
   and a.creado_por is null and a.fecha = p.fecha_orden
   from asientos a join pedidos p on p.id = a.origen_ref where a.id = (select id from a1)),
  'asiento: origen venta_web, ligado al pedido, fecha = fecha del pedido, escrito por el sistema');
select pg_temp.chk((select count(*) = 4 from asiento_lineas where asiento_id = (select id from a1))
  and pg_temp.linea((select id from a1), '138095', 69900, 0)
  and pg_temp.linea((select id from a1), '413505', 0, 69900)
  and pg_temp.linea((select id from a1), '613505', 25000, 0)
  and pg_temp.linea((select id from a1), '143505', 0, 25000),
  'asiento al peso: D 138095 69.900 · C 413505 69.900 · D 613505 25.000 · C 143505 25.000');
select pg_temp.chk((select sum(debe) = sum(haber) and sum(debe) = 94900 from asiento_lineas where asiento_id = (select id from a1)),
  'asiento: cuadra (debe = haber = 94.900)');
select pg_temp.chk((select actor = '7e700000-0000-4000-8000-0000000000a2' from asiento_bitacora
   where asiento_id = (select id from a1) and accion = 'crear'),
  'bitacora: queda QUIEN pulso «Generar asiento»');
select pg_temp.chk((pg_temp.como('7e700000-0000-4000-8000-0000000000a2',
   format('select fz_generar_asiento_automatico(%L)', pg_temp.ped('REF-F3-0001')))->>'resultado') = 'ya_existia'
  and (select count(*) = 1 from asientos where origen = 'venta_web' and origen_ref = pg_temp.ped('REF-F3-0001')),
  'Generar asiento dos veces: devuelve ya_existia y sigue habiendo UN asiento');
select pg_temp.chk((pg_temp.como('7e700000-0000-4000-8000-0000000000a2', 'select fz_asientos_automaticos_pendientes()')->>'pendientes')::int = 0,
  'aviso de Finanzas: sin pendientes ya no se pinta nada');

-- ---------- 4. Con el IVA definido el asiento entra SOLO, en la misma transaccion ----------
create temp table v2 as select pg_temp.pagar('REF-F3-0002', 'a3000000-0000-4000-8000-000000000001', 69900, 'prod', 'TX-F3-2') v;
select pg_temp.chk((select v->>'resultado' = 'procesado' and v->'asiento'->>'resultado' = 'creado' from v2),
  'venta real: el pago aprobado crea pedido Y asiento sin que nadie toque nada');
select pg_temp.chk(pg_temp.neto(pg_temp.ped('REF-F3-0002'), '138095') = 69900
  and pg_temp.neto(pg_temp.ped('REF-F3-0002'), '413505') = -69900
  and pg_temp.neto(pg_temp.ped('REF-F3-0002'), '613505') = 25000
  and pg_temp.neto(pg_temp.ped('REF-F3-0002'), '143505') = -25000,
  'venta real: el asiento automatico tiene los mismos montos al peso');
create temp table v2b as select pg_temp.srv($q$select pw_procesar_pago('TX-F3-2', 'APPROVED', 'REF-F3-0002', 6990000::bigint, 'COP',
  'transaction.updated', 'chk', null, 'CARD', 'pagador@wompi.invalid')$q$) v;
select pg_temp.chk((select v->>'resultado' = 'repetido' from v2b)
  and (select count(*) = 1 from asientos where origen = 'venta_web' and origen_ref = pg_temp.ped('REF-F3-0002')),
  'reintento de Wompi: repetido y SIGUE habiendo un solo asiento');
select pg_temp.chk(pg_temp.err(format($q$insert into asientos (fecha, descripcion, origen, origen_ref)
  values (current_date, 'duplicado', 'venta_web', %L)$q$, pg_temp.ped('REF-F3-0002'))) like '%asientos_un_automatico_uidx%',
  'candado de la base: un segundo asiento de venta para el mismo pedido es imposible (indice unico)');
select pg_temp.chk(pg_temp.err($q$insert into asientos (fecha, descripcion, origen) values (current_date, 'x', 'venta_web')$q$)
  like '%asientos_origen_ref_coherente%',
  'candado de la base: un asiento automatico sin pedido no puede existir');

-- ---------- 5. IVA 19 % incluido en el precio ----------
update contabilidad_config set iva_ventas_pct = 19 where id = 1;
create temp table v3 as select pg_temp.pagar('REF-F3-0003', 'a3000000-0000-4000-8000-000000000001', 69900, 'prod', 'TX-F3-3') v;
create temp table a3 as select (v->'asiento'->>'asiento_id')::uuid id from v3;
select pg_temp.chk((select count(*) = 5 from asiento_lineas where asiento_id = (select id from a3))
  and pg_temp.linea((select id from a3), '138095', 69900, 0)
  and pg_temp.linea((select id from a3), '413505', 0, 58739)
  and pg_temp.linea((select id from a3), '240805', 0, 11161)
  and pg_temp.linea((select id from a3), '613505', 25000, 0),
  'IVA 19 % incluido: base 58.739 a 413505 + IVA 11.161 a 240805 (69.900 / 1,19, redondeado al peso)');
select pg_temp.chk((select sum(debe) = sum(haber) from asiento_lineas where asiento_id = (select id from a3)),
  'IVA 19 %: el asiento cuadra (el IVA es la diferencia, nunca un redondeo suelto)');
update contabilidad_config set iva_ventas_pct = 0 where id = 1;

-- ---------- 6. Costo desconocido: no se inventa ----------
create temp table v4 as select pg_temp.pagar('REF-F3-0004', 'a3000000-0000-4000-8000-000000000002', 30000, 'prod', 'TX-F3-4') v;
select pg_temp.chk((select v->>'resultado' = 'procesado' and v->'asiento'->>'resultado' = 'pendiente'
   and v->'asiento'->>'motivo' like '%costo unitario%Sin costo F3%' from v4),
  'sin costo: la venta se crea y el asiento queda pendiente nombrando el producto (no se inventa un costo)');
select pg_temp.chk((select x->>'motivo' like '%costo%' from jsonb_array_elements(
    pg_temp.como('7e700000-0000-4000-8000-0000000000a2', 'select fz_asientos_automaticos_pendientes()')->'lista') x
   where x->>'pedido_id' = pg_temp.ped('REF-F3-0004')::text),
  'sin costo: el aviso de Finanzas dice exactamente que falta');
update productos set costo_unitario = 12000 where id = 'b3000000-0000-4000-8000-000000000002';
create temp table g4 as select pg_temp.como('7e700000-0000-4000-8000-0000000000a2',
  format('select fz_generar_asiento_automatico(%L)', pg_temp.ped('REF-F3-0004'))) v;
select pg_temp.chk((select v->>'resultado' = 'creado' from g4)
  and pg_temp.neto(pg_temp.ped('REF-F3-0004'), '613505') = 12000
  and pg_temp.neto(pg_temp.ped('REF-F3-0004'), '413505') = -30000,
  'sin costo: con el costo cargado en Inventario el asiento se genera completo (costo 12.000)');

-- ---------- 7. Un pago de PRUEBA (sandbox) no es un hecho contable ----------
create temp table v5 as select pg_temp.pagar('REF-F3-0005', 'a3000000-0000-4000-8000-000000000001', 69900, 'sandbox', 'TX-F3-5') v;
select pg_temp.chk((select v->>'resultado' = 'procesado' and v->'asiento'->>'resultado' = 'omitido' from v5)
  and (select count(*) = 0 from asientos where origen_ref = pg_temp.ped('REF-F3-0005')),
  'sandbox: crea el pedido (F2) pero NO toca los libros');
select pg_temp.chk(not exists (select 1 from jsonb_array_elements(
    pg_temp.como('7e700000-0000-4000-8000-0000000000a2', 'select fz_asientos_automaticos_pendientes()')->'lista') x
   where x->>'pedido_id' = pg_temp.ped('REF-F3-0005')::text),
  'sandbox: no aparece como pendiente en Finanzas');
select pg_temp.chk((pg_temp.como('7e700000-0000-4000-8000-0000000000a2',
   format('select fz_generar_asiento_automatico(%L)', pg_temp.ped('REF-F3-0005')))->>'resultado') = 'omitido',
  'sandbox: ni a mano desde el panel se contabiliza');

-- ---------- 8. Los asientos automaticos no se tocan desde Finanzas ----------
select pg_temp.chk(pg_temp.err(format($q$select pg_temp.como('7e700000-0000-4000-8000-0000000000a2',
   $x$select to_jsonb(editar_asiento(%L, current_date, 'cambio', '[{"cuenta_codigo":"110505","debe":1,"haber":0},{"cuenta_codigo":"413505","debe":0,"haber":1}]'::jsonb))$x$)$q$,
   (select id from a1))) like '%genero el sistema%anula el pedido en Ventas%',
  'proteccion: editar un asiento automatico se rechaza y dice como corregirlo');
select pg_temp.chk(pg_temp.err(format($q$select pg_temp.como('7e700000-0000-4000-8000-0000000000a2',
   $x$select to_jsonb(anular_asiento(%L, 'intento'))$x$)$q$, (select id from a1))) like '%genero el sistema%',
  'proteccion: anular un asiento automatico se rechaza');
select pg_temp.chk((select estado = 'activo' from asientos where id = (select id from a1))
  and (select count(*) = 4 from asiento_lineas where asiento_id = (select id from a1)),
  'proteccion: el asiento automatico quedo intacto');
-- Asiento de APERTURA manual: la mercancia que ya habia (10 x 25.000 + 3 x 12.000).
create temp table m1 as select pg_temp.como('7e700000-0000-4000-8000-0000000000a2', format($q$select to_jsonb(guardar_asiento(%L::date,
  'Apertura: mercancia en bodega',
  '[{"cuenta_codigo":"143505","debe":286000,"haber":0},{"cuenta_codigo":"311505","debe":0,"haber":286000}]'::jsonb))$q$,
  fz__fecha_colombia())) v;
create temp table m2 as select pg_temp.como('7e700000-0000-4000-8000-0000000000a2', format($q$select to_jsonb(guardar_asiento(%L::date,
  'Manual de prueba', '[{"cuenta_codigo":"110505","debe":1000,"haber":0},{"cuenta_codigo":"311505","debe":0,"haber":1000}]'::jsonb))$q$,
  fz__fecha_colombia())) v;
select pg_temp.chk(pg_temp.err(format($q$select pg_temp.como('7e700000-0000-4000-8000-0000000000a2',
   $x$select to_jsonb(editar_asiento(%L, %L::date, 'Manual editado', '[{"cuenta_codigo":"110505","debe":2000,"haber":0},{"cuenta_codigo":"311505","debe":0,"haber":2000}]'::jsonb))$x$)$q$,
   (select (v #>> '{}')::uuid from m2), fz__fecha_colombia())) = 'SIN ERROR'
  and pg_temp.err(format($q$select pg_temp.como('7e700000-0000-4000-8000-0000000000a2',
   $x$select to_jsonb(anular_asiento(%L, 'prueba'))$x$)$q$, (select (v #>> '{}')::uuid from m2))) = 'SIN ERROR',
  'sin regresion: un asiento MANUAL se sigue editando y anulando como siempre');
select pg_temp.chk((select origen = 'manual' and origen_ref is null from asientos where id = (select (v #>> '{}')::uuid from m1)),
  'sin regresion: los asientos manuales nacen con origen manual');

-- ---------- 9. Anular el pedido: contraasiento y neto en cero ----------
create temp table n2 as select pg_temp.como('7e700000-0000-4000-8000-0000000000a1',
  format('select anular_pedido(%L, %L)', pg_temp.ped('REF-F3-0002'), 'El cliente desistio')) v;
create temp table r2 as select id from asientos where origen = 'reverso_venta_web' and origen_ref = pg_temp.ped('REF-F3-0002');
select pg_temp.chk((select v->'asiento_reverso'->>'resultado' = 'creado' and (v->>'revertidos')::int = 1 from n2),
  'anular: devuelve el stock Y registra el contraasiento');
select pg_temp.chk((select count(*) = 4 from asiento_lineas where asiento_id = (select id from r2))
  and pg_temp.linea((select id from r2), '138095', 0, 69900)
  and pg_temp.linea((select id from r2), '413505', 69900, 0)
  and pg_temp.linea((select id from r2), '613505', 0, 25000)
  and pg_temp.linea((select id from r2), '143505', 25000, 0),
  'contraasiento al peso: mismas cuentas con debe y haber invertidos');
select pg_temp.chk((select fecha = fz__fecha_colombia() and estado = 'activo' from asientos where id = (select id from r2)),
  'contraasiento: fechado el dia de la anulacion (Colombia)');
select pg_temp.chk((select estado = 'activo' from asientos where origen = 'venta_web' and origen_ref = pg_temp.ped('REF-F3-0002')),
  'contraasiento: el asiento original NO se toca (queda la venta y su reverso)');
select pg_temp.chk(pg_temp.neto(pg_temp.ped('REF-F3-0002'), '138095') = 0
  and pg_temp.neto(pg_temp.ped('REF-F3-0002'), '413505') = 0
  and pg_temp.neto(pg_temp.ped('REF-F3-0002'), '613505') = 0
  and pg_temp.neto(pg_temp.ped('REF-F3-0002'), '143505') = 0,
  'anular: el neto del pedido queda en CERO en las cuatro cuentas');
select pg_temp.chk((pg_temp.como('7e700000-0000-4000-8000-0000000000a1',
   format('select anular_pedido(%L)', pg_temp.ped('REF-F3-0002')))->>'revertidos')::int = 0
  and (select count(*) = 1 from asientos where origen = 'reverso_venta_web' and origen_ref = pg_temp.ped('REF-F3-0002')),
  'anular dos veces: no hay segundo contraasiento');
select pg_temp.chk((pg_temp.como('7e700000-0000-4000-8000-0000000000a1',
   format('select anular_pedido(%L)', pg_temp.ped('REF-F3-0003')))->'asiento_reverso'->>'resultado') = 'creado'
  and pg_temp.neto(pg_temp.ped('REF-F3-0003'), '240805') = 0
  and pg_temp.neto(pg_temp.ped('REF-F3-0003'), '413505') = 0,
  'anular una venta con IVA: el contraasiento tambien devuelve el IVA (240805 en cero)');
select pg_temp.chk((pg_temp.como('7e700000-0000-4000-8000-0000000000a1',
   format('select anular_pedido(%L)', pg_temp.ped('REF-F3-0005')))->'asiento_reverso'->>'resultado') = 'sin_asiento',
  'anular un pedido de prueba (sandbox): no hay nada que reversar');

-- ---------- 10. La anulacion nunca falla por contabilidad ----------
create temp table v7 as select pg_temp.pagar('REF-F3-0007', 'a3000000-0000-4000-8000-000000000001', 69900, 'prod', 'TX-F3-7') v;
update puc_cuentas set imputable = false where codigo = '138095';   -- falla provocada
create temp table n7 as select pg_temp.como('7e700000-0000-4000-8000-0000000000a1',
  format('select anular_pedido(%L)', pg_temp.ped('REF-F3-0007'))) v;
select pg_temp.chk((select v->'asiento_reverso'->>'resultado' = 'pendiente' and v->'asiento_reverso'->>'motivo' like '%138095%' from n7)
  and (select anulado from pedidos where id = pg_temp.ped('REF-F3-0007')),
  'anular nunca falla por contabilidad: el pedido se anula aunque el contraasiento no se pueda registrar');
select pg_temp.chk((select x->>'tipo' = 'reverso' and x->>'motivo' like '%138095%' from jsonb_array_elements(
    pg_temp.como('7e700000-0000-4000-8000-0000000000a2', 'select fz_asientos_automaticos_pendientes()')->'lista') x
   where x->>'pedido_id' = pg_temp.ped('REF-F3-0007')::text),
  'aviso de Finanzas: el contraasiento pendiente aparece con su motivo');
update puc_cuentas set imputable = true where codigo = '138095';
select pg_temp.chk((pg_temp.como('7e700000-0000-4000-8000-0000000000a2',
   format('select fz_generar_asiento_automatico(%L)', pg_temp.ped('REF-F3-0007')))->>'resultado') = 'creado'
  and pg_temp.neto(pg_temp.ped('REF-F3-0007'), '138095') = 0,
  'Generar asiento: registra el contraasiento pendiente y el neto queda en cero');
-- Una venta cuyo asiento quedo pendiente y luego se anula: ya no hay nada que registrar.
update contabilidad_config set iva_ventas_pct = null where id = 1;
create temp table v6 as select pg_temp.pagar('REF-F3-0006', 'a3000000-0000-4000-8000-000000000001', 69900, 'prod', 'TX-F3-6') v;
update contabilidad_config set iva_ventas_pct = 0 where id = 1;
select pg_temp.chk((pg_temp.como('7e700000-0000-4000-8000-0000000000a1',
   format('select anular_pedido(%L)', pg_temp.ped('REF-F3-0006')))->'asiento_reverso'->>'resultado') = 'sin_asiento'
  and (select count(*) = 0 from asientos where origen_ref = pg_temp.ped('REF-F3-0006')),
  'venta pendiente y anulada: no se registra nada (ni venta ni reverso)');
select pg_temp.chk((pg_temp.como('7e700000-0000-4000-8000-0000000000a2', 'select fz_asientos_automaticos_pendientes()')->>'pendientes')::int = 0,
  'aviso de Finanzas: queda vacio (nada pendiente de verdad)');
-- Un pedido MANUAL se anula como siempre: no hay asiento automatico que reversar.
create temp table pm as select pg_temp.como('7e700000-0000-4000-8000-0000000000a1', $q$select crear_pedido(
  p_nombre => 'Cliente mostrador', p_correo => 'mostrador@cliente.invalid', p_canal => 'manual',
  p_items => '[{"product_id":"b3000000-0000-4000-8000-000000000001","cantidad":1,"precio_unitario":69900}]'::jsonb)$q$) v;
select pg_temp.chk((pg_temp.como('7e700000-0000-4000-8000-0000000000a1',
   format('select anular_pedido(%L)', (select (v->>'pedido_id')::uuid from pm)))->'asiento_reverso'->>'resultado') = 'sin_asiento',
  'sin regresion: anular un pedido manual funciona igual y no inventa asientos');

-- ---------- 11. Los informes cuadran AL PESO ----------
-- Vigentes: venta 1 (69.900 / costo 25.000) y venta 4 (30.000 / costo 12.000).
-- Anuladas con reverso: 2, 3 y 7. Apertura manual: 286.000 de mercancia.
select pg_temp.chk((select monto_periodo = 99900 from estado_resultados(date_trunc('year', fz__fecha_colombia())::date, fz__fecha_colombia())
   where cuenta_codigo = '413505'),
  'Estado de resultados: ingresos 413505 = 99.900 (69.900 + 30.000; las anuladas suman cero)');
select pg_temp.chk((select monto_periodo = 37000 from estado_resultados(date_trunc('year', fz__fecha_colombia())::date, fz__fecha_colombia())
   where cuenta_codigo = '613505'),
  'Estado de resultados: costo de ventas 613505 = 37.000 (25.000 + 12.000)');
select pg_temp.chk((select monto = 99900 from balance_general(fz__fecha_colombia()) where cuenta_codigo = '138095'),
  'Balance general: Wompi por liquidar (138095) = 99.900, lo que Wompi debe consignar');
select pg_temp.chk((select monto = 249000 from balance_general(fz__fecha_colombia()) where cuenta_codigo = '143505'),
  'Balance general: inventario en libros 143505 = 249.000 (286.000 de apertura - 37.000 vendidos)');
select pg_temp.chk((select monto = 62900 from balance_general(fz__fecha_colombia()) where seccion = 'resultado'),
  'Balance general: resultado del ejercicio 62.900 (99.900 - 37.000)');
select pg_temp.chk((select sum(monto) filter (where seccion = 'activo')
                          = coalesce(sum(monto) filter (where seccion = 'pasivo'), 0)
                          + sum(monto) filter (where seccion = 'patrimonio')
                          + sum(monto) filter (where seccion = 'resultado')
                     from balance_general(fz__fecha_colombia())),
  'Balance general: ACTIVO = PASIVO + PATRIMONIO + RESULTADO (348.900 = 0 + 286.000 + 62.900)');
select pg_temp.chk((select sum(total_debe) = sum(total_haber) and sum(saldo_deudor) = sum(saldo_acreedor)
                     from balance_comprobacion(fz__fecha_colombia())),
  'Balance de comprobacion: sumas iguales y saldos iguales');
select pg_temp.chk((select coalesce(sum(monto), 0) = 0 from balance_general(fz__fecha_colombia()) where cuenta_codigo = '240805'),
  'Balance general: IVA generado 240805 en cero (la unica venta con IVA se anulo)');

-- ---------- 12. H4 · fechas de Colombia ----------
select pg_temp.chk(fz__fecha_colombia('2026-10-10 03:30:00+00') = '2026-10-09'
  and fz__fecha_colombia('2026-10-10 05:30:00+00') = '2026-10-10',
  'H4: 10:30 p. m. en Colombia (03:30 UTC del dia siguiente) sigue siendo el MISMO dia');
select pg_temp.chk(fz__fecha_colombia('2027-01-01 04:59:59+00') = '2026-12-31',
  'H4: la ultima venta del 31 de diciembre no salta de ano');
select pg_temp.chk((select bool_and(fecha_orden = (creado at time zone 'America/Bogota')::date) from pedidos where canal = 'web'),
  'H4: todos los pedidos web quedan con la fecha de Colombia');

-- ---------- 13. Correo «Recibido» automatico (capa de datos) ----------
create temp table c1 as select pg_temp.srv(format('select correo_auto_recibido_preparar(%L)', pg_temp.ped('REF-F3-0001'))) v;
select pg_temp.chk((select v->>'etapa' = 'recibido' and v->>'destinatario' = 'f3@cliente.invalid'
   and (v->>'automatico')::boolean and v->>'envio_id' is not null and v->>'codigo_resena' is null from c1),
  'correo automatico: reserva el «Recibido» con el destinatario de la BASE (sin codigo de resena)');
select pg_temp.chk((select estado = 'pendiente' and creado_por is null and not es_prueba from correo_envios
   where id = (select (v->>'envio_id')::uuid from c1)),
  'correo automatico: queda en la bitacora como envio del sistema');
select pg_temp.chk(pg_temp.err(format($q$select pg_temp.srv($x$select correo_auto_recibido_preparar(%L)$x$)$q$, pg_temp.ped('REF-F3-0001')))
  like '%CORREO_EN_CURSO%',
  'correo automatico: un segundo disparo mientras sale el primero no duplica');
select pg_temp.chk((pg_temp.srv(format('select correo_auto_resultado(%L, true, %L)', (select v->>'envio_id' from c1), 'email-f3-1'))->>'estado') = 'enviado',
  'correo automatico: se cierra como enviado con el id del proveedor');
select pg_temp.chk(pg_temp.err(format($q$select pg_temp.srv($x$select correo_auto_recibido_preparar(%L)$x$)$q$, pg_temp.ped('REF-F3-0001')))
  like '%CORREO_YA_ENVIADO%',
  'correo automatico: un reintento de Wompi despues NO lo manda dos veces');
select pg_temp.chk(pg_temp.err(format($q$select pg_temp.srv($x$select correo_auto_recibido_preparar(%L)$x$)$q$, (select (v->>'pedido_id')::uuid from pm)))
  like '%CORREO_SOLO_WEB%',
  'correo automatico: solo pedidos web (los manuales siguen a mano)');
create temp table c4 as select pg_temp.como('7e700000-0000-4000-8000-0000000000a1',
  format($q$select correo_pedido_preparar(%L, 'recibido')$q$, pg_temp.ped('REF-F3-0004'))) v;
select pg_temp.chk(pg_temp.err(format($q$select pg_temp.srv($x$select correo_auto_resultado(%L, true)$x$)$q$, (select v->>'envio_id' from c4)))
  like '%CORREO_ENVIO_NO_PENDIENTE%',
  'correo automatico: el servidor no puede cerrar un envio que reservo una persona');
select pg_temp.chk(not pw__contexto_servidor(),
  'correo automatico: la compuerta de servidor quedo cerrada');

-- ---------- 14. Permisos ----------
select pg_temp.chk(not has_function_privilege('anon', f, 'execute') and not has_function_privilege('authenticated', f, 'execute')
   and has_function_privilege('service_role', f, 'execute'), 'permisos: ' || f || ' es SOLO del servidor')
  from unnest(array['fz__asiento_venta_web(uuid)', 'fz__reverso_venta_web(uuid)', 'fz__lineas_venta_web(uuid)',
                    'fz__lineas_reverso(uuid)', 'fz__fecha_colombia(timestamptz)',
                    'correo_auto_recibido_preparar(uuid)', 'correo_auto_resultado(uuid,boolean,text,text)']) f;
select pg_temp.chk(pg_temp.err($q$select pg_temp.como('7e700000-0000-4000-8000-0000000000a1', 'select fz_asientos_automaticos_pendientes()')$q$)
  like '%Acceso denegado%', 'permisos: Ventas no ve el aviso contable de Finanzas');
select pg_temp.chk(pg_temp.err(format($q$select pg_temp.como('7e700000-0000-4000-8000-0000000000a3', $x$select fz_generar_asiento_automatico(%L)$x$)$q$,
   pg_temp.ped('REF-F3-0001'))) like '%Acceso denegado%', 'permisos: alguien sin Finanzas no puede generar asientos');
select pg_temp.chk(pg_temp.err($q$do $d$ begin set local role anon; perform fz_asientos_automaticos_pendientes(); end $d$$q$)
  like '%permission denied%', 'permisos: la tienda (anon) no llega a las funciones contables');

select case when ok then 'pasa' else 'FALLA' end || ' | ' || que from pg_temp.r order by n;
select 'RESUMEN | ' || count(*) || ' comprobaciones · ' || count(*) filter (where not ok) || ' fallan' from pg_temp.r;
rollback;
