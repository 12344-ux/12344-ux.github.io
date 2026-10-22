-- MAGANDHI · Pruebas D2c.2a · La venta de proveedor
-- ------------------------------------------------------------
-- Mide lo que antes era IMPOSIBLE y lo que no debe romperse:
--   · vender un producto de proveedor (antes moría con STOCK_INSUFICIENTE);
--   · que esa venta NO toque el libro de Inventario;
--   · que anular funcione (antes habría chocado con el gatillo de D1);
--   · que un pedido propio siga comportándose EXACTAMENTE igual;
--   · que la vista pública y el checkout NO puedan discrepar.
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
    '{"sub":"7d2c0000-0000-4000-8000-000000000001","role":"service_role"}', true);
  execute q;
  return 'SIN ERROR';
exception when others then
  return sqlerrm;
end $$;

begin;

select set_config('request.jwt.claims',
  '{"sub":"7d2c0000-0000-4000-8000-000000000001","role":"service_role"}', true);

insert into auth.users (id, email) values
  ('7d2c0000-0000-4000-8000-000000000001', 'todo@local.invalid') on conflict do nothing;
insert into perfiles (id, rol, modulos) values
  ('7d2c0000-0000-4000-8000-000000000001', 'prueba',
   '{dropshipping,marketing,ventas,inventario,finanzas}') on conflict (id) do nothing;

-- Producto PROPIO de control, con inventario real.
insert into productos (id, sku, nombre, origen, costo_unitario) values
  ('d0000000-0000-4000-8000-00000000000a', 'MAG-PROPIO-D2C2', 'Propio control', 'propio', 10000)
  on conflict (id) do nothing;
insert into movimientos_inventario (product_id, tipo, cantidad, fecha)
  values ('d0000000-0000-4000-8000-00000000000a', 'entrada', 10, current_date);

-- Producto de PROVEEDOR, con lectura fresca y stock profundo.
insert into productos (id, sku, nombre, origen) values
  ('d0000000-0000-4000-8000-00000000000b', 'MAG-DROP-7001', 'Proveedor vendible', 'proveedor')
  on conflict (id) do nothing;
insert into producto_proveedor
  (product_id, producto_externo_id, variacion_externa_id, costo_reportado,
   stock_reportado, stock_leido_en, stock_vence_en)
values
  ('d0000000-0000-4000-8000-00000000000b', '2296060', '7001', 20996,
   230, now(), now() + interval '2 hours')
  on conflict (product_id) do nothing;

-- ------------------------------------------------------------
-- (1) Las cuentas que aprobó el contador
-- ------------------------------------------------------------
select pg_temp.chk(
  (select cuenta_saldo_proveedor = '138010' and cuenta_flete = '523535'
   from contabilidad_config where id = 1),
  'las cuentas aprobadas quedan en configuración (138010 saldo · 523535 flete)');

-- ------------------------------------------------------------
-- (2) Lo que antes era IMPOSIBLE: vender proveedor
-- ------------------------------------------------------------
-- Antes de D2c.2a esto moría con STOCK_INSUFICIENTE, porque un producto de
-- proveedor no tiene fila en stock_actual.
select pg_temp.chk(
  pg_temp.err($$select crear_pedido(
    p_nombre => 'Cliente Prueba', p_correo => 'cli@local.invalid',
    p_direccion => 'Calle 1', p_ciudad => 'Bogota', p_canal => 'manual',
    p_items => jsonb_build_array(jsonb_build_object(
      'product_id', 'd0000000-0000-4000-8000-00000000000b',
      'cantidad', 1, 'precio_unitario', 59900)))$$) = 'SIN ERROR',
  'se puede vender un producto de proveedor (antes era imposible)');

select pg_temp.chk(
  (select count(*) = 1 from pedido_proveedor
   where product_id = 'd0000000-0000-4000-8000-00000000000b'),
  'la venta deja su ficha de despacho en pedido_proveedor');

select pg_temp.chk(
  (select stock_al_vender = 230 and stock_leido_en is not null
   from pedido_proveedor where product_id = 'd0000000-0000-4000-8000-00000000000b'),
  'guarda la EVIDENCIA de lo que Dropi reportaba al cobrar (230)');

select pg_temp.chk(
  (select producto_externo_id = '2296060' and variacion_externa_id = '7001'
   from pedido_proveedor where product_id = 'd0000000-0000-4000-8000-00000000000b'),
  'guarda el id y la variante de Dropi que hay que pedir');

select pg_temp.chk(
  (select transcrito_en is null and pedido_externo_id is null
   from pedido_proveedor where product_id = 'd0000000-0000-4000-8000-00000000000b'),
  'nace SIN transcribir: el pedido en Dropi todavía no existe');

-- La línea roja de D1: el proveedor no entra al libro de Inventario.
select pg_temp.chk(
  not exists (select 1 from movimientos_inventario
              where product_id = 'd0000000-0000-4000-8000-00000000000b'),
  'la venta de proveedor NO toca el libro de Inventario');

-- ------------------------------------------------------------
-- (3) El producto propio se comporta EXACTAMENTE igual
-- ------------------------------------------------------------
-- Esto es lo que más importa no romper: hoy funciona y hay dinero real detrás.
select pg_temp.chk(
  pg_temp.err($$select crear_pedido(
    p_nombre => 'Cliente Propio', p_correo => 'prop@local.invalid',
    p_direccion => 'Calle 2', p_ciudad => 'Bogota', p_canal => 'manual',
    p_items => jsonb_build_array(jsonb_build_object(
      'product_id', 'd0000000-0000-4000-8000-00000000000a',
      'cantidad', 3, 'precio_unitario', 39900)))$$) = 'SIN ERROR',
  'un pedido de producto propio sigue funcionando');

select pg_temp.chk(
  (select coalesce(sum(case when tipo = 'salida' then cantidad else 0 end), 0) = 3
   from movimientos_inventario where product_id = 'd0000000-0000-4000-8000-00000000000a'),
  'el producto propio SÍ baja del libro (salida de 3)');

select pg_temp.chk(
  (select existencias = 7 from stock_actual
   where product_id = 'd0000000-0000-4000-8000-00000000000a'),
  'y stock_actual queda en 7 (10 - 3)');

select pg_temp.chk(
  pg_temp.err($$select crear_pedido(
    p_nombre => 'Cliente Voraz', p_correo => 'voraz@local.invalid',
    p_direccion => 'Calle 3', p_ciudad => 'Bogota',
    p_items => jsonb_build_array(jsonb_build_object(
      'product_id', 'd0000000-0000-4000-8000-00000000000a',
      'cantidad', 99, 'precio_unitario', 39900)))$$) like '%Registra primero la entrada en Inventario%',
  'el bloqueo de stock propio conserva su mensaje original');

-- ------------------------------------------------------------
-- (4) El proveedor se rechaza por sus propias razones
-- ------------------------------------------------------------
insert into productos (id, sku, nombre, origen) values
  ('d0000000-0000-4000-8000-00000000000c', 'MAG-DROP-7002', 'Proveedor vencido', 'proveedor')
  on conflict (id) do nothing;
-- La vara de entrada son 100: se importa con 200 y luego se simula el vencimiento.
insert into producto_proveedor
  (product_id, producto_externo_id, stock_reportado, stock_leido_en, stock_vence_en)
values ('d0000000-0000-4000-8000-00000000000c', '2296058', 200, now(), now())
  on conflict (product_id) do nothing;

select pg_temp.chk(
  pg_temp.err($$select crear_pedido(
    p_nombre => 'Cliente X', p_correo => 'x@local.invalid',
    p_direccion => 'Calle 4', p_ciudad => 'Bogota', p_canal => 'manual',
    p_items => jsonb_build_array(jsonb_build_object(
      'product_id', 'd0000000-0000-4000-8000-00000000000c',
      'cantidad', 1, 'precio_unitario', 49900)))$$) like '%reporta 0 unidad%proveedor%',
  'una lectura VENCIDA rechaza la venta, con el mensaje propio del proveedor');

update producto_proveedor set stock_reportado = 19, stock_vence_en = now() + interval '2 hours'
  where product_id = 'd0000000-0000-4000-8000-00000000000c';
select pg_temp.chk(
  pg_temp.err($$select crear_pedido(
    p_nombre => 'Cliente Y', p_correo => 'y@local.invalid',
    p_direccion => 'Calle 5', p_ciudad => 'Bogota', p_canal => 'manual',
    p_items => jsonb_build_array(jsonb_build_object(
      'product_id', 'd0000000-0000-4000-8000-00000000000c',
      'cantidad', 1, 'precio_unitario', 49900)))$$) like '%STOCK_INSUFICIENTE%',
  'por debajo del piso (19 < 20) también rechaza la venta');

select pg_temp.chk(
  not exists (select 1 from pedido_proveedor
              where product_id = 'd0000000-0000-4000-8000-00000000000c'),
  'un rechazo no deja ficha de despacho a medias (todo o nada)');

-- ------------------------------------------------------------
-- (5) Los pedidos sin transcribir reservan unidades
-- ------------------------------------------------------------
-- La parte CONOCIDA del hueco entre el cobro y el despacho.
update producto_proveedor set stock_reportado = 22, stock_vence_en = now() + interval '2 hours'
  where product_id = 'd0000000-0000-4000-8000-00000000000b';
select pg_temp.chk(
  ventas_disponible_para_venta('d0000000-0000-4000-8000-00000000000b') = 1,
  'con 22 reportadas, piso 20 y 1 pedido sin transcribir, disponible = 1');

update pedido_proveedor set cantidad = 3
  where product_id = 'd0000000-0000-4000-8000-00000000000b';
select pg_temp.chk(
  ventas_disponible_para_venta('d0000000-0000-4000-8000-00000000000b') = 0,
  'tres pendientes y piso 20 consumen el margen vendible');

update pedido_proveedor set transcrito_en = now(), pedido_externo_id = 'DROPI-123'
  where product_id = 'd0000000-0000-4000-8000-00000000000b';
select pg_temp.chk(
  ventas_disponible_para_venta('d0000000-0000-4000-8000-00000000000b') = 2,
  'al transcribir dejan de restar; el piso 20 sigue protegido');

select pg_temp.chk(
  pg_temp.err($$update pedido_proveedor set transcrito_en = now(), pedido_externo_id = null
    where product_id = 'd0000000-0000-4000-8000-00000000000b'$$) <> 'SIN ERROR',
  'no se puede marcar transcrito sin el número de pedido de Dropi');

-- ------------------------------------------------------------
-- (6) La vitrina y el checkout NO pueden discrepar
-- ------------------------------------------------------------
-- C1 expone max_comprable ya acotado y agotado deriva exactamente de él.
-- Esta prueba compara la vista con la única regla de campaña, sin volver a
-- inferir el contrato público desde existencias exactas.
select set_config('impulse.ds_importando', 'on', true);
insert into campana_producto (id, nombre, slug, categoria_codigo, product_id_ref, precio_venta, publicado, activo)
values
  ('cb000000-0000-4000-8000-00000000000b', 'Camp proveedor', 'camp-prov', 'belleza',
   'd0000000-0000-4000-8000-00000000000b', 59900, true, true),
  ('cb000000-0000-4000-8000-00000000000c', 'Camp vencida', 'camp-venc', 'belleza',
   'd0000000-0000-4000-8000-00000000000c', 49900, true, true)
  on conflict (id) do nothing;
select set_config('impulse.ds_importando', 'off', true);

update dropshipping_config set venta_proveedor_habilitada = true where id = 1;

select pg_temp.chk(
  not exists (
    select 1 from catalogo_publico c
    join campana_producto cp on cp.id = c.id
    join productos p on p.id = cp.product_id_ref
    where p.origen = 'proveedor'
      and (c.max_comprable is distinct from ventas_max_comprable_campana(cp.id)
           or c.agotado is distinct from (ventas_max_comprable_campana(cp.id) = 0))
  ),
  'la vista coincide con la regla única de máximo comprable para proveedor');

update pedido_proveedor set transcrito_en = null, pedido_externo_id = null
  where product_id = 'd0000000-0000-4000-8000-00000000000b';
update producto_proveedor set stock_reportado = 21
  where product_id = 'd0000000-0000-4000-8000-00000000000b';
select pg_temp.chk(
  (select agotado from catalogo_publico where slug = 'camp-prov') is true
  and ventas_disponible_para_venta('d0000000-0000-4000-8000-00000000000b') = 0,
  'con 21 reportadas, piso 20 y 3 reservadas queda agotado');

update producto_proveedor set stock_reportado = 22
  where product_id = 'd0000000-0000-4000-8000-00000000000b';
update pedido_proveedor set cantidad = 22
  where product_id = 'd0000000-0000-4000-8000-00000000000b';
select pg_temp.chk(
  (select agotado from catalogo_publico where slug = 'camp-prov') is true,
  'si los pedidos sin transcribir se comen todo el stock, sale de la vitrina');

update dropshipping_config set venta_proveedor_habilitada = false where id = 1;
select pg_temp.chk(
  not exists (select 1 from catalogo_publico where slug in ('camp-prov', 'camp-venc')),
  'D2c.2a SIGUE INERTE: con el interruptor cerrado no sale nada de proveedor');

-- ------------------------------------------------------------
-- (7) Anular: antes habría fallado
-- ------------------------------------------------------------
-- El gatillo de D1 rechaza movimientos de inventario de proveedor, así que la
-- compensación de anular_pedido habría hecho fallar la anulación completa.
select pg_temp.chk(
  pg_temp.err($$select anular_pedido(
    (select pedido_id from pedido_proveedor
     where product_id = 'd0000000-0000-4000-8000-00000000000b' limit 1),
    'prueba de anulacion')$$) = 'SIN ERROR',
  'anular un pedido de proveedor FUNCIONA (antes chocaba con el gatillo de D1)');

select pg_temp.chk(
  not exists (select 1 from movimientos_inventario
              where product_id = 'd0000000-0000-4000-8000-00000000000b'),
  'anular proveedor no inventa una entrada de inventario');

select pg_temp.chk(
  ventas_disponible_para_venta('d0000000-0000-4000-8000-00000000000b') = 2,
  'un pedido anulado deja de reservar; el piso 20 permanece protegido');

-- Y anular un pedido PROPIO sigue devolviendo stock.
select pg_temp.chk(
  pg_temp.err($$select anular_pedido(
    (select p.id from pedidos p
      join pedido_items pi on pi.pedido_id = p.id
     where pi.product_id = 'd0000000-0000-4000-8000-00000000000a'
       and p.estado <> 'anulado' limit 1),
    'prueba propio')$$) = 'SIN ERROR',
  'anular un pedido propio sigue funcionando');

select pg_temp.chk(
  (select existencias = 10 from stock_actual
   where product_id = 'd0000000-0000-4000-8000-00000000000a'),
  'y DEVUELVE el stock al libro (vuelve a 10)');

-- ------------------------------------------------------------
-- (8) La vara de entrada ya no es decorativa
-- ------------------------------------------------------------
insert into productos (id, sku, nombre, origen) values
  ('d0000000-0000-4000-8000-00000000000d', 'MAG-DROP-7003', 'Proveedor flaco', 'proveedor')
  on conflict (id) do nothing;

-- La vara NO es un candado del servidor, y el documento lo dice así. Lo que se
-- comprueba es justamente eso: que no bloquee (importar con poco stock es una
-- decisión del dueño) y que el comentario no prometa un candado inexistente,
-- que era la deuda real de D2c.1.
select pg_temp.chk(
  pg_temp.err($$insert into producto_proveedor
    (product_id, producto_externo_id, stock_reportado, stock_leido_en, stock_vence_en)
    values ('d0000000-0000-4000-8000-00000000000d', '999', 30, now(), now())$$) = 'SIN ERROR',
  'la vara NO bloquea una importación: es una advertencia de curaduría, no un invariante');

select pg_temp.chk(
  (select col_description('dropshipping_config'::regclass, a.attnum) like '%NO un candado%'
     from pg_attribute a
    where a.attrelid = 'dropshipping_config'::regclass and a.attname = 'vara_entrada'),
  'y el comentario de la columna ya NO promete un candado que no existe');

-- El invariante real sí está impuesto: el piso de vitrina.
select pg_temp.chk(
  ventas_disponible_para_venta('d0000000-0000-4000-8000-00000000000d') = 0,
  'ese producto importado con 30 unidades y lectura vencida da 0 disponibles: el piso sí manda');

-- ------------------------------------------------------------
-- (9) Permisos
-- ------------------------------------------------------------
select pg_temp.chk(
  not has_function_privilege('anon', 'public.ventas_disponible_para_venta(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'public.ventas_disponible_para_venta(uuid)', 'execute'),
  'solo el servidor puede ejecutar ventas_disponible_para_venta (devuelve existencias exactas)');

select pg_temp.chk(
  not has_table_privilege('anon', 'pedido_proveedor', 'select'),
  'anon NO puede leer pedido_proveedor');

select pg_temp.chk(
  not has_table_privilege('authenticated', 'pedido_proveedor', 'insert'),
  'authenticated no escribe pedido_proveedor directo: solo las RPC');

-- ------------------------------------------------------------
-- (10) El candado de publicación sigue puesto
-- ------------------------------------------------------------
-- El candado de publicación se levantó en D2c.2b, así que su comportamiento
-- final se mide allí (dropshipping-d2c2b.sql). Lo que sí sigue siendo de este
-- tramo es que la vitrina obedezca al interruptor, ya comprobado arriba.
select pg_temp.chk(
  pg_temp.err($$select cm_publicar_campana(
    'cb000000-0000-4000-8000-00000000000b'::uuid, true)$$) = 'SIN ERROR',
  'con ficha de proveedor y precio, publicar YA funciona (el candado quedó atrás)');

-- ------------------------------------------------------------
select '--- D2c.2a · venta de proveedor ---' as bloque;
select n, case when ok then 'pasa' else 'FALLA' end as res, que from pg_temp.r order by n;
select
  'RESUMEN' as t,
  count(*) || ' comprobaciones' as total,
  count(*) filter (where not ok) || ' fallan' as fallan,
  case when count(*) filter (where not ok) = 0 then 'TODO PASA' else 'HAY FALLAS' end as veredicto
from pg_temp.r;

rollback;
