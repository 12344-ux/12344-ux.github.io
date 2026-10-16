-- ============================================================
-- Dropshipping D2c.3 · el SEGURO del pedido de proveedor
-- ------------------------------------------------------------
-- Mide lo que define este tramo:
--   · el seguro es OPCIONAL de verdad: un despacho se registra y su asiento
--     CUADRA sin seguro, exactamente como antes;
--   · cuando se asegura, el gasto va a 523095 y sale del saldo en Dropi;
--   · null y 0 significan lo mismo («no se aseguro») y NUNCA bloquean, al
--     contrario que costo_real y flete, que si lo hacen;
--   · la cuenta 523095 existe, es imputable y cuelga de 5230 Seguros;
--   · la firma vieja de 8 argumentos ya no existe (si quedaran las dos,
--     PostgREST tendria dos candidatas para la misma llamada por nombre);
--   · el producto PROPIO no cambio de camino.
-- SOLO LOCAL: todo se deshace al final.
-- ============================================================
\set ON_ERROR_STOP 1
set client_min_messages = warning;
drop table if exists pg_temp.r;
create temp table r (n serial, ok boolean, que text);
create or replace function pg_temp.chk(p boolean, q text) returns void language sql as
$$ insert into pg_temp.r (ok, que) values (coalesce(p, false), q) $$;

create or replace function pg_temp.err(q text) returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"7e2b0000-0000-4000-8000-0000000000e1","role":"service_role"}', true);
  execute q;
  return 'SIN ERROR';
exception when others then
  return sqlerrm;
end $$;

begin;

select set_config('request.jwt.claims',
  '{"sub":"7e2b0000-0000-4000-8000-0000000000e1","role":"service_role"}', true);

insert into auth.users (id, email) values
  ('7e2b0000-0000-4000-8000-0000000000e1', 'seguro@local.invalid') on conflict do nothing;
insert into perfiles (id, rol, modulos) values
  ('7e2b0000-0000-4000-8000-0000000000e1', 'prueba',
   '{dropshipping,marketing,ventas,inventario,finanzas}') on conflict (id) do nothing;

update contabilidad_config set iva_ventas_pct = 0 where id = 1;

-- DOS productos de proveedor: uno se asegura y el otro no, para medir los dos
-- caminos sin que se contaminen.
insert into productos (id, sku, nombre, origen) values
  ('e1000000-0000-4000-8000-0000000000a1', 'MAG-DROP-9001', 'Cubo asegurado',  'proveedor'),
  ('e1000000-0000-4000-8000-0000000000a2', 'MAG-DROP-9002', 'Cubo sin seguro', 'proveedor')
  on conflict (id) do nothing;
insert into producto_proveedor
  (product_id, producto_externo_id, variacion_externa_id, costo_reportado,
   stock_reportado, stock_leido_en, stock_vence_en)
values
  ('e1000000-0000-4000-8000-0000000000a1', '2296061', '7101', 7200,
   300, now(), now() + interval '2 hours'),
  ('e1000000-0000-4000-8000-0000000000a2', '2296062', '7102', 7200,
   300, now(), now() + interval '2 hours')
  on conflict (product_id) do nothing;

select set_config('impulse.ds_importando', 'on', true);
insert into campana_producto (id, nombre, slug, product_id_ref, precio_venta, publicado, activo)
values
  ('eb100000-0000-4000-8000-0000000000a1', 'Camp cubo 1', 'camp-cubo-1',
   'e1000000-0000-4000-8000-0000000000a1', 29999, false, true),
  ('eb100000-0000-4000-8000-0000000000a2', 'Camp cubo 2', 'camp-cubo-2',
   'e1000000-0000-4000-8000-0000000000a2', 29999, false, true)
  on conflict (id) do nothing;
select set_config('impulse.ds_importando', 'off', true);

-- ------------------------------------------------------------
-- (1) La cuenta del seguro
-- ------------------------------------------------------------
select pg_temp.chk(
  (select cuenta_seguro from contabilidad_config where id = 1) = '523095',
  'contabilidad_config.cuenta_seguro apunta a 523095');

select pg_temp.chk(
  (select imputable and naturaleza = 'debito' and padre = '5230' and nivel = 4
   from puc_cuentas where codigo = '523095'),
  '523095 existe, es imputable, de naturaleza débito y cuelga de 5230');

select pg_temp.chk(
  (select nombre = 'SEGUROS' and not imputable from puc_cuentas where codigo = '5230'),
  '5230 SEGUROS existe como encabezado y NO es imputable');

-- Fundamento de por qué 523095 y no 524555 (lo que se había sugerido):
select pg_temp.chk(
  (select count(*) = 0 from puc_cuentas where codigo = '524555'),
  'no se creó 524555: 5245 es «mantenimiento y reparaciones», no seguros');

-- ------------------------------------------------------------
-- (2) La columna, y que el seguro no puede ser negativo
-- ------------------------------------------------------------
select pg_temp.chk(
  (select is_nullable = 'YES' and data_type = 'bigint'
   from information_schema.columns
   where table_name = 'pedido_proveedor' and column_name = 'seguro'),
  'pedido_proveedor.seguro existe y es NULLABLE (el seguro es opcional)');

select pg_temp.chk(
  pg_temp.err($$update pedido_proveedor set seguro = -1$$) like '%seguro_no_negativo%'
  or pg_temp.err($$insert into pedido_proveedor
       (pedido_id, product_id, producto_externo_id, cantidad, seguro)
       values (gen_random_uuid(), 'e1000000-0000-4000-8000-0000000000a1', 'x', 1, -5)$$)
     like '%seguro%',
  'un seguro negativo lo rechaza la base');

-- ------------------------------------------------------------
-- (3) La firma vieja ya no existe
-- ------------------------------------------------------------
select pg_temp.chk(
  to_regprocedure('public.ds_registrar_transcripcion(uuid,uuid,text,bigint,bigint,text,text,text,bigint)')
    is not null,
  'ds_registrar_transcripcion ahora recibe el seguro (9 argumentos)');

select pg_temp.chk(
  to_regprocedure('public.ds_registrar_transcripcion(uuid,uuid,text,bigint,bigint,text,text,text)')
    is null,
  'y la de 8 argumentos se borró: PostgREST no puede quedar con dos candidatas');

select pg_temp.chk(
  has_function_privilege('authenticated',
    'public.ds_registrar_transcripcion(uuid,uuid,text,bigint,bigint,text,text,text,bigint)', 'execute'),
  'la firma nueva conserva el grant a authenticated');

select pg_temp.chk(
  not has_function_privilege('anon',
    'public.ds_registrar_transcripcion(uuid,uuid,text,bigint,bigint,text,text,text,bigint)', 'execute'),
  'y anon sigue sin poder llamarla');

-- ------------------------------------------------------------
-- (4) EL CAMINO SIN SEGURO · lo que más importa: se puede cerrar igual
-- ------------------------------------------------------------
select crear_pedido(
  p_nombre => 'Cliente Dos', p_correo => 'dos@local.invalid',
  p_direccion => 'Calle 2 # 2-2', p_ciudad => 'Pasto',
  p_departamento => 'Narino', p_canal => 'manual',
  p_items => jsonb_build_array(jsonb_build_object(
    'product_id', 'e1000000-0000-4000-8000-0000000000a2',
    'cantidad', 1, 'precio_unitario', 29999)));

-- Se transcribe SIN pasar el seguro: ni se menciona el argumento.
select pg_temp.chk(
  pg_temp.err($$select ds_registrar_transcripcion(
    (select pedido_id from pedido_proveedor
      where product_id = 'e1000000-0000-4000-8000-0000000000a2' limit 1),
    'e1000000-0000-4000-8000-0000000000a2'::uuid,
    'DROPI-SIN-SEG', 7200, 14910)$$) = 'SIN ERROR',
  'se registra el despacho SIN seguro, sin pasar el argumento');

select pg_temp.chk(
  (select seguro is null from pedido_proveedor
    where product_id = 'e1000000-0000-4000-8000-0000000000a2'),
  'el seguro queda en null: «no se aseguró», no «falta el dato»');

create temp table sin_seg as
  select jsonb_array_elements(fz__lineas_venta_web(
    (select pedido_id from pedido_proveedor
      where product_id = 'e1000000-0000-4000-8000-0000000000a2' limit 1))) as l;

select pg_temp.chk(
  not exists (select 1 from sin_seg where l->>'cuenta_codigo' = '523095'),
  'el asiento NO lleva línea de 523095 cuando no hubo seguro');

select pg_temp.chk(
  exists (select 1 from sin_seg where l->>'cuenta_codigo' = '138010'
          and (l->>'haber')::bigint = 22110),
  'del saldo en Dropi salen sólo 22.110 = 7.200 + 14.910');

select pg_temp.chk(
  (select sum((l->>'debe')::bigint) = sum((l->>'haber')::bigint) from sin_seg),
  'y el asiento CUADRA sin seguro (el caso normal, no una excepción)');

-- ------------------------------------------------------------
-- (5) EL CAMINO CON SEGURO
-- ------------------------------------------------------------
select crear_pedido(
  p_nombre => 'Cliente Uno', p_correo => 'uno@local.invalid',
  p_direccion => 'Calle 1 # 1-1', p_ciudad => 'Pasto',
  p_departamento => 'Narino', p_canal => 'manual',
  p_items => jsonb_build_array(jsonb_build_object(
    'product_id', 'e1000000-0000-4000-8000-0000000000a1',
    'cantidad', 1, 'precio_unitario', 29999)));

select ds_registrar_transcripcion(
  (select pedido_id from pedido_proveedor
    where product_id = 'e1000000-0000-4000-8000-0000000000a1' limit 1),
  'e1000000-0000-4000-8000-0000000000a1'::uuid,
  'DROPI-CON-SEG', 7200, 14910, null, null, null, 754);

select pg_temp.chk(
  (select seguro = 754 and costo_real = 7200 and flete = 14910
   from pedido_proveedor where product_id = 'e1000000-0000-4000-8000-0000000000a1'),
  'guarda el seguro de 754 junto al costo y el flete');

create temp table con_seg as
  select jsonb_array_elements(fz__lineas_venta_web(
    (select pedido_id from pedido_proveedor
      where product_id = 'e1000000-0000-4000-8000-0000000000a1' limit 1))) as l;

select pg_temp.chk(
  exists (select 1 from con_seg where l->>'cuenta_codigo' = '523095'
          and (l->>'debe')::bigint = 754),
  'el seguro va a 523095 por 754 (gasto de ventas)');

select pg_temp.chk(
  exists (select 1 from con_seg where l->>'cuenta_codigo' = '138010'
          and (l->>'haber')::bigint = 22864),
  'y del saldo en Dropi salen 22.864 = 7.200 + 14.910 + 754');

select pg_temp.chk(
  not exists (select 1 from con_seg where l->>'cuenta_codigo' = '143505'),
  'el inventario 143505 sigue sin aparecer: nunca hubo mercancía nuestra');

select pg_temp.chk(
  (select sum((l->>'debe')::bigint) = sum((l->>'haber')::bigint) from con_seg),
  'el asiento con seguro CUADRA');

-- Este es el peso que descuadró los libros el 14-oct: la diferencia entre los
-- dos caminos es exactamente el seguro, y ahora está contabilizada.
select pg_temp.chk(
  (select (select sum((l->>'haber')::bigint) from con_seg where l->>'cuenta_codigo' = '138010')
        - (select sum((l->>'haber')::bigint) from sin_seg where l->>'cuenta_codigo' = '138010')
        = 754),
  'la diferencia entre asegurar y no asegurar es EXACTAMENTE el seguro');

-- ------------------------------------------------------------
-- (6) Un seguro de 0 se comporta como «no se aseguró»
-- ------------------------------------------------------------
update pedido_proveedor set seguro = 0
 where product_id = 'e1000000-0000-4000-8000-0000000000a1';

create temp table cero_seg as
  select jsonb_array_elements(fz__lineas_venta_web(
    (select pedido_id from pedido_proveedor
      where product_id = 'e1000000-0000-4000-8000-0000000000a1' limit 1))) as l;

select pg_temp.chk(
  not exists (select 1 from cero_seg where l->>'cuenta_codigo' = '523095'),
  'un seguro de 0 no mete una línea de cero (la base la rechazaría)');

select pg_temp.chk(
  (select sum((l->>'debe')::bigint) = sum((l->>'haber')::bigint) from cero_seg),
  'y con seguro 0 el asiento también CUADRA');

-- ------------------------------------------------------------
-- (7) El seguro se puede completar después
-- ------------------------------------------------------------
select pg_temp.chk(
  pg_temp.err($$select ds_registrar_transcripcion(
    (select pedido_id from pedido_proveedor
      where product_id = 'e1000000-0000-4000-8000-0000000000a2' limit 1),
    'e1000000-0000-4000-8000-0000000000a2'::uuid,
    'DROPI-SIN-SEG', null, null, null, null, null, 900)$$) = 'SIN ERROR',
  'una segunda llamada puede añadir el seguro que faltaba');

select pg_temp.chk(
  (select seguro = 900 and costo_real = 7200 and flete = 14910
          and pedido_externo_id = 'DROPI-SIN-SEG'
   from pedido_proveedor where product_id = 'e1000000-0000-4000-8000-0000000000a2'),
  'lo añade sin tocar el costo, el flete ni el número de pedido ya anotados');

-- ------------------------------------------------------------
-- (8) El costo y el flete SÍ siguen bloqueando (no se relajó nada)
-- ------------------------------------------------------------
insert into productos (id, sku, nombre, origen) values
  ('e1000000-0000-4000-8000-0000000000a3', 'MAG-DROP-9003', 'Cubo pendiente', 'proveedor')
  on conflict (id) do nothing;
insert into producto_proveedor
  (product_id, producto_externo_id, variacion_externa_id, costo_reportado,
   stock_reportado, stock_leido_en, stock_vence_en)
values ('e1000000-0000-4000-8000-0000000000a3', '2296063', '7103', 7200,
        300, now(), now() + interval '2 hours')
  on conflict (product_id) do nothing;
select set_config('impulse.ds_importando', 'on', true);
insert into campana_producto (id, nombre, slug, product_id_ref, precio_venta, publicado, activo)
values ('eb100000-0000-4000-8000-0000000000a3', 'Camp cubo 3', 'camp-cubo-3',
        'e1000000-0000-4000-8000-0000000000a3', 29999, false, true)
  on conflict (id) do nothing;
select set_config('impulse.ds_importando', 'off', true);

select crear_pedido(
  p_nombre => 'Cliente Tres', p_correo => 'tres@local.invalid',
  p_direccion => 'Calle 3 # 3-3', p_ciudad => 'Pasto',
  p_departamento => 'Narino', p_canal => 'manual',
  p_items => jsonb_build_array(jsonb_build_object(
    'product_id', 'e1000000-0000-4000-8000-0000000000a3',
    'cantidad', 1, 'precio_unitario', 29999)));

select pg_temp.chk(
  pg_temp.err($$select fz__lineas_venta_web(
    (select pedido_id from pedido_proveedor
      where product_id = 'e1000000-0000-4000-8000-0000000000a3' limit 1))$$)
  like '%DS_COSTO_PROVEEDOR_PENDIENTE%',
  'sin costo ni flete el asiento SIGUE pendiente: el seguro no relajó esa regla');

-- ------------------------------------------------------------
-- (9) El producto PROPIO no cambió de camino
-- ------------------------------------------------------------
insert into productos (id, sku, nombre, origen, costo_unitario) values
  ('e1000000-0000-4000-8000-0000000000b1', 'MAG-PROPIO-SEG', 'Propio control', 'propio', 12000)
  on conflict (id) do nothing;
insert into movimientos_inventario (product_id, tipo, cantidad, fecha)
  values ('e1000000-0000-4000-8000-0000000000b1', 'entrada', 5, current_date);

select crear_pedido(
  p_nombre => 'Cliente Propio', p_correo => 'propio@local.invalid',
  p_direccion => 'Calle 4 # 4-4', p_ciudad => 'Pasto',
  p_departamento => 'Narino', p_canal => 'manual',
  p_items => jsonb_build_array(jsonb_build_object(
    'product_id', 'e1000000-0000-4000-8000-0000000000b1',
    'cantidad', 1, 'precio_unitario', 30000)));

create temp table propio as
  select jsonb_array_elements(fz__lineas_venta_web(
    (select pi.pedido_id from pedido_items pi
      where pi.product_id = 'e1000000-0000-4000-8000-0000000000b1' limit 1))) as l;

select pg_temp.chk(
  exists (select 1 from propio where l->>'cuenta_codigo' = '143505'
          and (l->>'haber')::bigint = 12000),
  'el propio sigue descargando inventario contra 143505, como siempre');

select pg_temp.chk(
  not exists (select 1 from propio where l->>'cuenta_codigo' in ('138010','523095','523535')),
  'y no se le cuela ni saldo de Dropi, ni seguro, ni flete');

select pg_temp.chk(
  (select sum((l->>'debe')::bigint) = sum((l->>'haber')::bigint) from propio),
  'el asiento del propio CUADRA');

-- ------------------------------------------------------------
select '--- D2c.3 · el seguro del pedido ---' as bloque;
select n, case when ok then 'pasa' else 'FALLA' end as res, que from pg_temp.r order by n;
select
  'RESUMEN' as t,
  count(*) || ' comprobaciones' as total,
  count(*) filter (where not ok) || ' fallan' as fallan,
  case when count(*) filter (where not ok) = 0 then 'TODO PASA' else 'HAY FALLAS' end as veredicto
from pg_temp.r;

rollback;
