-- MAGANDHI · Pruebas D2c.2b · Se abre la venta de proveedor
-- ------------------------------------------------------------
-- Mide el tramo que LEVANTA EL CANDADO:
--   · publicar un producto de proveedor ya funciona, y lo que ahora se exige;
--   · el asiento descuenta del SALDO EN DROPI (138010) y lleva el flete a
--     523535, nunca contra un inventario que no existe;
--   · si falta el costo real o el flete, la venta queda PENDIENTE con un motivo
--     que dice qué hacer y dónde (Ventas, no Inventario);
--   · el circuito del despacho manual: qué transcribir y cómo se anota.
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
    '{"sub":"7e2b0000-0000-4000-8000-000000000001","role":"service_role"}', true);
  execute q;
  return 'SIN ERROR';
exception when others then
  return sqlerrm;
end $$;

begin;

select set_config('request.jwt.claims',
  '{"sub":"7e2b0000-0000-4000-8000-000000000001","role":"service_role"}', true);

insert into auth.users (id, email) values
  ('7e2b0000-0000-4000-8000-000000000001', 'todo@local.invalid') on conflict do nothing;
insert into perfiles (id, rol, modulos) values
  ('7e2b0000-0000-4000-8000-000000000001', 'prueba',
   '{dropshipping,marketing,ventas,inventario,finanzas}') on conflict (id) do nothing;

-- IVA definido: sin esto el asiento no se arma (contrato de F3).
update contabilidad_config set iva_ventas_pct = 0 where id = 1;

-- Un producto de proveedor listo para vender.
insert into productos (id, sku, nombre, origen) values
  ('e0000000-0000-4000-8000-00000000000b', 'MAG-DROP-8001', 'Serum proveedor', 'proveedor')
  on conflict (id) do nothing;
insert into producto_proveedor
  (product_id, producto_externo_id, variacion_externa_id, costo_reportado,
   stock_reportado, stock_leido_en, stock_vence_en)
values ('e0000000-0000-4000-8000-00000000000b', '2296060', '7001', 20996,
        230, now(), now() + interval '2 hours')
  on conflict (product_id) do nothing;

-- Y uno de proveedor SIN ficha: no se le puede pedir a nadie.
insert into productos (id, sku, nombre, origen) values
  ('e0000000-0000-4000-8000-00000000000f', 'MAG-DROP-8009', 'Huerfano', 'proveedor')
  on conflict (id) do nothing;

select set_config('impulse.ds_importando', 'on', true);
insert into campana_producto (id, nombre, slug, product_id_ref, precio_venta, publicado, activo)
values
  ('eb000000-0000-4000-8000-00000000000b', 'Camp serum', 'camp-serum',
   'e0000000-0000-4000-8000-00000000000b', 59900, false, true),
  ('eb000000-0000-4000-8000-00000000000f', 'Camp huerfana', 'camp-huerfana',
   'e0000000-0000-4000-8000-00000000000f', 49900, false, true)
  on conflict (id) do nothing;
select set_config('impulse.ds_importando', 'off', true);

-- ------------------------------------------------------------
-- (1) El candado quedó levantado
-- ------------------------------------------------------------
select pg_temp.chk(
  (select venta_proveedor_habilitada from dropshipping_config where id = 1) is true,
  'venta_proveedor_habilitada quedó en true: la vitrina ya no esconde al proveedor');

select pg_temp.chk(
  pg_temp.err($$select cm_publicar_campana(
    'eb000000-0000-4000-8000-00000000000b'::uuid, true)$$) = 'SIN ERROR',
  'publicar una campaña de producto de proveedor YA FUNCIONA');

select pg_temp.chk(
  (select publicado from campana_producto where id = 'eb000000-0000-4000-8000-00000000000b') is true,
  'y queda efectivamente publicada');

select pg_temp.chk(
  (select agotado from catalogo_publico where slug = 'camp-serum') is false,
  'aparece en la vitrina pública como disponible');

-- Lo que sí se sigue exigiendo: sin ficha de proveedor no se puede pedir.
select pg_temp.chk(
  pg_temp.err($$select cm_publicar_campana(
    'eb000000-0000-4000-8000-00000000000f'::uuid, true)$$) like '%DS_SIN_FICHA_PROVEEDOR%',
  'un producto de proveedor SIN ficha de Dropi no se puede publicar');

-- ------------------------------------------------------------
-- (2) La venta real, de punta a punta
-- ------------------------------------------------------------
select pg_temp.chk(
  pg_temp.err($$select crear_pedido(
    p_nombre => 'Cliente Real', p_correo => 'real@local.invalid',
    p_direccion => 'Calle 10 # 5-5', p_ciudad => 'Leticia',
    p_departamento => 'Amazonas', p_canal => 'manual',
    p_items => jsonb_build_array(jsonb_build_object(
      'product_id', 'e0000000-0000-4000-8000-00000000000b',
      'cantidad', 1, 'precio_unitario', 59900)))$$) = 'SIN ERROR',
  'se vende el producto de proveedor');

-- ------------------------------------------------------------
-- (3) El asiento: sin el costo real queda PENDIENTE, no inventado
-- ------------------------------------------------------------
select pg_temp.chk(
  pg_temp.err($$select fz__lineas_venta_web(
    (select pedido_id from pedido_proveedor
      where product_id = 'e0000000-0000-4000-8000-00000000000b' limit 1))$$)
  like '%DS_COSTO_PROVEEDOR_PENDIENTE%',
  'sin el costo real y el flete, el asiento NO se arma: queda pendiente');

select pg_temp.chk(
  pg_temp.err($$select fz__lineas_venta_web(
    (select pedido_id from pedido_proveedor
      where product_id = 'e0000000-0000-4000-8000-00000000000b' limit 1))$$)
  not like '%Inventario%',
  'y el motivo NO manda a Inventario, donde no hay nada que hacer');

-- ------------------------------------------------------------
-- (4) El circuito del despacho manual
-- ------------------------------------------------------------
select pg_temp.chk(
  (select count(*) = 1 from ds_pedidos_por_transcribir()),
  'el pedido aparece en la lista de «por transcribir a Dropi»');

select pg_temp.chk(
  (select dropi_id = '2296060' and variante = '7001' and ciudad = 'Leticia'
   from ds_pedidos_por_transcribir() limit 1),
  'la lista dice qué id y variante pedir, y a dónde va');

select pg_temp.chk(
  pg_temp.err($$select ds_registrar_transcripcion(
    (select pedido_id from pedido_proveedor
      where product_id = 'e0000000-0000-4000-8000-00000000000b' limit 1),
    'e0000000-0000-4000-8000-00000000000b'::uuid, '')$$) like '%DS_FALTA_PEDIDO_EXTERNO%',
  'no se puede marcar como transcrito sin el número de pedido de Dropi');

select ds_registrar_transcripcion(
  (select pedido_id from pedido_proveedor
    where product_id = 'e0000000-0000-4000-8000-00000000000b' limit 1),
  'e0000000-0000-4000-8000-00000000000b'::uuid,
  'DROPI-99881', 21000, 14500);

select pg_temp.chk(
  (select count(*) = 0 from ds_pedidos_por_transcribir()),
  'al registrarlo desaparece de la lista de pendientes');

select pg_temp.chk(
  (select transcrito_en is not null and pedido_externo_id = 'DROPI-99881'
          and costo_real = 21000 and flete = 14500
          and destino_ciudad = 'Leticia' and destino_departamento = 'Amazonas'
   from pedido_proveedor where product_id = 'e0000000-0000-4000-8000-00000000000b'),
  'guarda el número externo, el costo real, el flete y el DESTINO (para Métricas)');

select pg_temp.chk(
  (select transcrito_por = '7e2b0000-0000-4000-8000-000000000001'
   from pedido_proveedor where product_id = 'e0000000-0000-4000-8000-00000000000b'),
  'queda registrado QUIÉN transcribió el pedido, en la propia fila');

-- No se usa pedido_bitacora: su `accion` es una lista cerrada y ninguna
-- describe esto. Forzar una sería registrar un hecho falso.
select pg_temp.chk(
  not exists (select 1 from pedido_bitacora
              where detalle_cambio->>'evento' = 'transcrito_en_dropi'),
  'y NO se fuerza una acción falsa en la bitácora del pedido');

-- Idempotencia de hecho: no se re-transcribe, pero se pueden completar datos.
-- La llamada va en su PROPIA sentencia: metida dentro de un AND junto con la
-- verificación, PostgreSQL no garantiza el orden de evaluación y la lectura
-- podía ocurrir antes de la escritura.
select pg_temp.chk(
  pg_temp.err($$select ds_registrar_transcripcion(
    (select pedido_id from pedido_proveedor
      where product_id = 'e0000000-0000-4000-8000-00000000000b' limit 1),
    'e0000000-0000-4000-8000-00000000000b'::uuid, 'DROPI-OTRO', null, 16000)$$) = 'SIN ERROR',
  'una segunda llamada con otro número no falla');

select pg_temp.chk(
  (select pedido_externo_id = 'DROPI-99881' and flete = 16000
   from pedido_proveedor where product_id = 'e0000000-0000-4000-8000-00000000000b'),
  'completa el flete pero NO cambia el número de pedido ya anotado');

-- ------------------------------------------------------------
-- (5) El asiento, ahora sí: contra el saldo en Dropi
-- ------------------------------------------------------------
create temp table lineas as
  select jsonb_array_elements(fz__lineas_venta_web(
    (select pedido_id from pedido_proveedor
      where product_id = 'e0000000-0000-4000-8000-00000000000b' limit 1))) as l;

select pg_temp.chk(
  exists (select 1 from lineas where l->>'cuenta_codigo' = '613505'
          and (l->>'debe')::bigint = 21000),
  'el costo va a 613505 por 21.000 (el cobro REAL de Dropi)');

select pg_temp.chk(
  exists (select 1 from lineas where l->>'cuenta_codigo' = '523535'
          and (l->>'debe')::bigint = 16000),
  'el flete va a 523535 por 16.000 (gasto de ventas)');

select pg_temp.chk(
  exists (select 1 from lineas where l->>'cuenta_codigo' = '138010'
          and (l->>'haber')::bigint = 37000),
  'y los 37.000 salen del SALDO EN DROPI (138010), no de un inventario');

select pg_temp.chk(
  not exists (select 1 from lineas where l->>'cuenta_codigo' = '143505'),
  'el inventario 143505 NO aparece: nunca hubo mercancía nuestra que descargar');

select pg_temp.chk(
  exists (select 1 from lineas where l->>'cuenta_codigo' = '138095'
          and (l->>'debe')::bigint = 59900),
  'el ingreso sigue entrando por Wompi por liquidar (138095), como en F3');

select pg_temp.chk(
  (select sum((l->>'debe')::bigint) = sum((l->>'haber')::bigint) from lineas),
  'el asiento CUADRA');

-- ------------------------------------------------------------
-- (6) El producto propio no cambió de camino
-- ------------------------------------------------------------
insert into productos (id, sku, nombre, origen, costo_unitario) values
  ('e0000000-0000-4000-8000-00000000000a', 'MAG-PROPIO-D2C2B', 'Propio control', 'propio', 12000)
  on conflict (id) do nothing;
insert into movimientos_inventario (product_id, tipo, cantidad, fecha)
  values ('e0000000-0000-4000-8000-00000000000a', 'entrada', 5, current_date);

select crear_pedido(
  p_nombre => 'Cliente Propio', p_correo => 'cp@local.invalid',
  p_direccion => 'Calle 1', p_ciudad => 'Bogota', p_canal => 'manual',
  p_items => jsonb_build_array(jsonb_build_object(
    'product_id', 'e0000000-0000-4000-8000-00000000000a',
    'cantidad', 2, 'precio_unitario', 39900)));

create temp table lineas_propio as
  select jsonb_array_elements(fz__lineas_venta_web(
    (select p.id from pedidos p join pedido_items pi on pi.pedido_id = p.id
      where pi.product_id = 'e0000000-0000-4000-8000-00000000000a' limit 1))) as l;

select pg_temp.chk(
  exists (select 1 from lineas_propio where l->>'cuenta_codigo' = '143505'
          and (l->>'haber')::bigint = 24000),
  'una venta PROPIA sigue descargando inventario 143505 (2 x 12.000)');

select pg_temp.chk(
  not exists (select 1 from lineas_propio where l->>'cuenta_codigo' in ('138010','523535')),
  'y NO toca el saldo en Dropi ni la cuenta de fletes');

-- ------------------------------------------------------------
-- (7) Permisos
-- ------------------------------------------------------------
select pg_temp.chk(
  not has_function_privilege('anon', 'public.ds_pedidos_por_transcribir()', 'execute'),
  'anon NO puede ver qué pedidos faltan por transcribir');

select pg_temp.chk(
  not has_function_privilege('anon',
    'public.ds_registrar_transcripcion(uuid,uuid,text,bigint,bigint,text,text,text,bigint)', 'execute'),
  'anon NO puede registrar una transcripción');

-- ------------------------------------------------------------
select '--- D2c.2b · se abre la venta ---' as bloque;
select n, case when ok then 'pasa' else 'FALLA' end as res, que from pg_temp.r order by n;
select
  'RESUMEN' as t,
  count(*) || ' comprobaciones' as total,
  count(*) filter (where not ok) || ' fallan' as fallan,
  case when count(*) filter (where not ok) = 0 then 'TODO PASA' else 'HAY FALLAS' end as veredicto
from pg_temp.r;

rollback;
