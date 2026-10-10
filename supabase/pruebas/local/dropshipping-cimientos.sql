-- ============================================================
-- MAGANDHI · Pruebas D1 · Cimientos de Dropshipping
-- ------------------------------------------------------------
-- Mide que proveedor quede separado del libro de Inventario y de sus métricas,
-- que la bandeja sea privada, y que D1 no permita publicar/vender proveedor.
-- SOLO LOCAL: todo se deshace al final.
-- ============================================================
\set ON_ERROR_STOP 1
set client_min_messages = warning;
drop table if exists pg_temp.r;
create temp table r (n serial, ok boolean, que text);
create or replace function pg_temp.chk(p boolean, q text) returns void language sql as
$$ insert into pg_temp.r (ok, que) values (coalesce(p, false), q) $$;

-- Ejecuta una consulta como un usuario autenticado concreto y devuelve JSON.
create or replace function pg_temp.como_json(uid uuid, q text) returns jsonb language plpgsql as $$
declare x jsonb;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute q into x;
  execute 'reset role';
  return x;
exception when others then
  execute 'reset role';
  raise;
end $$;

-- Igual, pero captura el error y lo hace comprobable.
create or replace function pg_temp.err_como(uid uuid, q text) returns text language plpgsql as $$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute q;
  execute 'reset role';
  return 'SIN ERROR';
exception when others then
  execute 'reset role';
  return sqlerrm;
end $$;

-- Ejecuta como postgres (sin RLS) para medir los GATILLOS de base de datos.
-- La tabla tiene defaults auth.uid(); una sesion PostgreSQL pura no trae las
-- claims JSON que Supabase siempre inyecta, asi que se simula service_role para
-- que el diagnostico llegue al trigger en vez de fallar antes en el default.
create or replace function pg_temp.err_postgres(q text) returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute q;
  return 'SIN ERROR';
exception when others then
  return sqlerrm;
end $$;

begin;

-- Personas: el operador Dropshipping no recibe Inventario/Marketing/Ventas.
insert into auth.users (id, email) values
  ('7e590000-0000-4000-8000-000000000001', 'ds@local.invalid'),
  ('7e590000-0000-4000-8000-000000000002', 'inv@local.invalid'),
  ('7e590000-0000-4000-8000-000000000003', 'mkt@local.invalid'),
  ('7e590000-0000-4000-8000-000000000004', 'met@local.invalid'),
  ('7e590000-0000-4000-8000-000000000005', 'sin@local.invalid') on conflict do nothing;
insert into perfiles (id, rol, modulos) values
  ('7e590000-0000-4000-8000-000000000001', 'prueba', '{dropshipping}'),
  ('7e590000-0000-4000-8000-000000000002', 'prueba', '{inventario}'),
  ('7e590000-0000-4000-8000-000000000003', 'prueba', '{marketing}'),
  ('7e590000-0000-4000-8000-000000000004', 'prueba', '{metricas}'),
  ('7e590000-0000-4000-8000-000000000005', 'prueba', '{}') on conflict (id) do nothing;

-- Un producto propio y uno proveedor. El proveedor tiene ficha externa pero
-- NUNCA recibirá un movimiento.
insert into productos (id, sku, nombre, costo_unitario, precio_venta, stock_minimo, activo) values
  ('d2300000-0000-4000-8000-000000000001', 'DS-PROPIO', 'Producto propio D1', 1000, 3000, 2, true);
insert into productos (id, sku, nombre, costo_unitario, precio_venta, stock_minimo, activo, origen) values
  ('d2300000-0000-4000-8000-000000000002', 'DS-PROV', 'Producto proveedor D1', 12000, 30000, 0, true, 'proveedor');
insert into producto_proveedor (
  product_id, plataforma, producto_externo_id, variacion_externa_id,
  proveedor_externo_id, costo_reportado, stock_reportado, stock_leido_en, stock_vence_en
) values (
  'd2300000-0000-4000-8000-000000000002', 'dropi', '23002', 'v1',
  'proveedor-23', 12000, 9, now(), now() + interval '5 minutes'
);
insert into movimientos_inventario (product_id, tipo, cantidad, motivo)
  values ('d2300000-0000-4000-8000-000000000001', 'entrada', 10, 'semilla D1');

-- ------------------------------------------------------------------
-- 1. Origen y ficha proveedor
-- ------------------------------------------------------------------
select pg_temp.chk(
  (select origen = 'propio' from productos where id = 'd2300000-0000-4000-8000-000000000001'),
  'productos historicos/nuevos sin origen explicito siguen siendo propios');
select pg_temp.chk(
  (select origen = 'proveedor' from productos where id = 'd2300000-0000-4000-8000-000000000002'),
  'producto proveedor queda marcado internamente como proveedor');
select pg_temp.chk(
  (select producto_externo_id = '23002' and variacion_externa_id = 'v1' from producto_proveedor where product_id = 'd2300000-0000-4000-8000-000000000002'),
  'ficha proveedor conserva producto externo y variante exacta');
select pg_temp.chk(
  pg_temp.err_postgres($$update productos set origen = 'proveedor' where id = 'd2300000-0000-4000-8000-000000000001'$$)
    like 'DS_ORIGEN_INMUTABLE%',
  'gatillo de base impide reclasificar producto propio/proveedor despues del alta');
select pg_temp.chk(
  pg_temp.err_como('7e590000-0000-4000-8000-000000000001',
    $$update productos set origen = 'proveedor' where id = 'd2300000-0000-4000-8000-000000000001'$$)
    like 'permission denied%',
  'Dropshipping no puede editar productos directo (solo RPC futura)');
select pg_temp.chk(
  pg_temp.err_como('7e590000-0000-4000-8000-000000000002',
    $$insert into producto_proveedor(product_id, producto_externo_id, variacion_externa_id) values ('d2300000-0000-4000-8000-000000000001','999','')$$)
    like 'permission denied%',
  'Inventario no puede insertar fichas proveedor directo');
select pg_temp.chk(
  pg_temp.err_como('7e590000-0000-4000-8000-000000000001',
    $$select ds_guardar_candidato('23', '', null, 'Prueba', null, 1, 2, 3, now(), '["http://no-segura.invalid/a.jpg"]'::jsonb)$$)
    like 'DS_CANDIDATO_FOTO_INVALIDA%',
  'bandeja rechaza URL HTTP (solo preview HTTPS)');

-- ------------------------------------------------------------------
-- 2. Libro y vista de Inventario: proveedor queda FUERA de ambos
-- ------------------------------------------------------------------
select pg_temp.chk(
  pg_temp.err_como('7e590000-0000-4000-8000-000000000002',
    $$select inv_registrar_movimiento('d2300000-0000-4000-8000-000000000002','entrada',1,'no debe entrar',null,null,current_date)$$)
    like 'DS_PRODUCTO_PROVEEDOR_SIN_INVENTARIO%',
  'RPC de Inventario rechaza movimiento proveedor con mensaje claro');
select pg_temp.chk(
  pg_temp.err_como('7e590000-0000-4000-8000-000000000002',
    $$insert into movimientos_inventario(product_id,tipo,cantidad,motivo) values ('d2300000-0000-4000-8000-000000000002','entrada',1,'atajo')$$)
    like 'permission denied%',
  'Inventario no escribe el libro directo');
-- El gatillo se prueba como postgres, que salta RLS: asi se demuestra que no
-- depende del navegador ni de una policy.
select pg_temp.chk(
  pg_temp.err_como('7e590000-0000-4000-8000-000000000004',
    $$insert into movimientos_inventario(product_id,tipo,cantidad,motivo) values ('d2300000-0000-4000-8000-000000000002','entrada',1,'atajo')$$)
    like 'permission denied%',
  'alguien ajeno tampoco llega al libro');
select pg_temp.chk(
  (select existencias = 10 from stock_actual where product_id = 'd2300000-0000-4000-8000-000000000001'),
  'stock_actual conserva producto propio y sus existencias derivadas');
select pg_temp.chk(
  not exists (select 1 from stock_actual where product_id = 'd2300000-0000-4000-8000-000000000002'),
  'stock_actual excluye por completo producto proveedor');
-- El gatillo se prueba como postgres, que salta RLS: asi se demuestra que no
-- depende del navegador ni de una policy.
select pg_temp.chk(
  pg_temp.err_postgres(
    $$insert into movimientos_inventario(product_id,tipo,cantidad,motivo) values ('d2300000-0000-4000-8000-000000000002','entrada',1,'atajo postgres')$$)
    like 'DS_PRODUCTO_PROVEEDOR_SIN_INVENTARIO%',
  'gatillo de tabla rechaza proveedor incluso por encima de RLS');

-- ------------------------------------------------------------------
-- 3. Bandeja privada: guardar, descartar y reabrir sin duplicar
-- ------------------------------------------------------------------
create temp table can as
select pg_temp.como_json('7e590000-0000-4000-8000-000000000001',
  $$select to_jsonb(ds_guardar_candidato('555', '', 'prov-55', 'Candidato Dropi', 'Cuidado', 9000, 25000, 7, now(), '["https://cdn.dropi.invalid/a.jpg"]'::jsonb))$$) as j;
select pg_temp.chk((select j is not null from can),
  'operador Dropshipping puede guardar candidato via RPC');
-- La llamada anterior devuelve un UUID JSON escalar; comprobamos la fila real.
select pg_temp.chk(
  (select nombre_externo = 'Candidato Dropi' and stock_reportado = 7 and estado = 'bandeja'
     from dropshipping_candidatos where producto_externo_id = '555' and variacion_externa_id = ''),
  'candidato guarda solo snapshot interno, stock sellado y estado bandeja');
select pg_temp.chk(
  (pg_temp.como_json('7e590000-0000-4000-8000-000000000001',
    $$select jsonb_build_object('n',count(*)) from dropshipping_candidatos$$)->>'n')::int = 1,
  'modulo Dropshipping lee su bandeja');
select pg_temp.chk(
  (pg_temp.como_json('7e590000-0000-4000-8000-000000000002',
    $$select jsonb_build_object('n',count(*)) from dropshipping_candidatos$$)->>'n')::int = 0,
  'Inventario no ve la bandeja proveedor');
select pg_temp.chk(
  pg_temp.err_como('7e590000-0000-4000-8000-000000000001',
    $$insert into dropshipping_candidatos(producto_externo_id,nombre_externo) values ('777','atajo')$$)
    ~ '(permission denied|row-level security)',
  'ni Dropshipping escribe candidato directo; solo RPC');

-- Descartar y volver a guardar el mismo id/variante: debe reabrir la MISMA fila.
select pg_temp.chk(
  pg_temp.como_json('7e590000-0000-4000-8000-000000000001',
    $$select to_jsonb(ds_actualizar_estado_candidato((select id from dropshipping_candidatos where producto_externo_id='555'), 'descartado'))$$) is not null,
  'operador puede descartar candidato por RPC');
select pg_temp.chk(
  (select estado = 'descartado' from dropshipping_candidatos where producto_externo_id = '555'),
  'candidato queda descartado sin borrarse');
select pg_temp.chk(
  pg_temp.como_json('7e590000-0000-4000-8000-000000000001',
    $$select to_jsonb(ds_guardar_candidato('555', '', 'prov-55', 'Candidato Dropi actualizado', 'Cuidado', 9500, 26000, 8, now(), '["https://cdn.dropi.invalid/b.jpg"]'::jsonb))$$) is not null,
  'guardar de nuevo refresca candidato por RPC');
select pg_temp.chk(
  (select count(*) = 1 and max(estado) = 'bandeja' and max(stock_reportado) = 8
     from dropshipping_candidatos where producto_externo_id = '555'),
  'relectura no duplica: reabre la misma fila con snapshot nuevo');

-- ------------------------------------------------------------------
-- 4. Metricas: proveedor no es rotacion/bodega, pero el resto conserva datos
-- ------------------------------------------------------------------
insert into clientes (id, nombre, correo, correo_norm) values
  ('d2300000-0000-4000-8000-000000000011', 'Cliente D1', 'd1@local.invalid', 'd1@local.invalid');
insert into pedidos (id, customer_id, fecha_orden, total, estado, canal) values
  ('d2300000-0000-4000-8000-000000000012', 'd2300000-0000-4000-8000-000000000011', (now() at time zone 'America/Bogota')::date, 30000, 'entregado', 'manual');
insert into pedido_items (pedido_id, product_id, cantidad, precio_unitario, subtotal) values
  ('d2300000-0000-4000-8000-000000000012', 'd2300000-0000-4000-8000-000000000002', 1, 30000, 30000);
create temp table mt as
select pg_temp.como_json('7e590000-0000-4000-8000-000000000004', $$select mt_inventario()$$) v;
select pg_temp.chk(
  not exists (select 1 from mt, jsonb_array_elements(v->'productos') x where x->>'sku' = 'DS-PROV'),
  'Metricas Inventario excluye proveedor de productos/rotacion/dias');
select pg_temp.chk(
  exists (select 1 from mt, jsonb_array_elements(v->'productos') x where x->>'sku' = 'DS-PROPIO'),
  'Metricas Inventario conserva producto propio');

-- ------------------------------------------------------------------
-- 5. Publicacion: proveedor no sale a tienda hasta D2
-- ------------------------------------------------------------------
insert into campana_producto (id, nombre, slug, precio_venta, product_id_ref, publicado, activo) values
  ('d2300000-0000-4000-8000-000000000021', 'Campaña proveedor D1', 'd1-proveedor', 30000, 'd2300000-0000-4000-8000-000000000002', false, true);
select pg_temp.chk(
  pg_temp.err_como('7e590000-0000-4000-8000-000000000003',
    $$select cm_publicar_campana('d2300000-0000-4000-8000-000000000021', true)$$)
    like 'DS_PUBLICACION_PENDIENTE%',
  'Marketing no puede publicar proveedor antes de stock vivo/checkout D2');
-- Incluso con un update privilegiado accidental, catalogo_publico lo oculta.
update campana_producto set publicado = true where id = 'd2300000-0000-4000-8000-000000000021';
select pg_temp.chk(
  not exists (select 1 from catalogo_publico where slug = 'd1-proveedor'),
  'catalogo_publico oculta proveedor aun ante escritura privilegiada accidental');

-- ------------------------------------------------------------------
-- 6. Privacidad y permisos nominales
-- ------------------------------------------------------------------
select pg_temp.chk(
  not has_table_privilege('anon', 'dropshipping_candidatos', 'select')
  and not has_table_privilege('anon', 'producto_proveedor', 'select'),
  'anon no puede leer candidatos ni fichas proveedor');
select pg_temp.chk(
  has_function_privilege('authenticated', 'ds_guardar_candidato(text,text,text,text,text,bigint,bigint,integer,timestamptz,jsonb)'::regprocedure, 'execute')
  and not has_function_privilege('anon', 'ds_guardar_candidato(text,text,text,text,text,bigint,bigint,integer,timestamptz,jsonb)'::regprocedure, 'execute'),
  'RPC de bandeja: authenticated si, anon no; guardia interna decide modulo');
select pg_temp.chk(
  not has_function_privilege('authenticated', 'ds__bloquear_movimiento_proveedor()'::regprocedure, 'execute')
  and has_function_privilege('service_role', 'ds__bloquear_movimiento_proveedor()'::regprocedure, 'execute'),
  'gatillo interno: solo service_role, nunca el panel');

select case when ok then 'pasa' else 'FALLA' end || ' | ' || que from pg_temp.r order by n;
select 'RESUMEN | ' || count(*) || ' comprobaciones · ' || count(*) filter (where not ok) || ' fallan' from pg_temp.r;
rollback;
