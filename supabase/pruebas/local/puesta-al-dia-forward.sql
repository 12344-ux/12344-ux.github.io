-- ============================================================
-- Impulse · Pruebas de la puesta al dia FORWARD (20261018000000)
-- ------------------------------------------------------------
-- Se corre sobre una base construida SIN 20261002000000, para reproducir el
-- estado REAL de produccion medido el 8-oct-2026:
--     publicar_con_candado = false · finanzas_puertas_latentes = 5
--     storage_borrado_ok = false   · vista_es_la_del_3oct = true
-- Primero comprueba que la simulacion es fiel, luego aplica la migracion nueva
-- y comprueba que cierra los tres huecos SIN tocar la vista.
-- Uso: herramientas/correr-puesta-al-dia.sh
-- SOLO LOCAL; la parte de comportamiento se deshace al final.
-- ============================================================
\set ON_ERROR_STOP 1
set client_min_messages = warning;
drop table if exists pg_temp.r;
create temp table r (n serial, ok boolean, que text);
create or replace function pg_temp.chk(p boolean, q text) returns void language sql as
$$ insert into pg_temp.r (ok, que) values (coalesce(p, false), q) $$;

-- ---------- 1. La simulacion reproduce produccion ANTES de la migracion ----------
select pg_temp.chk(
  (select pg_get_functiondef(p.oid) not like '%product_id_ref%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'cm_publicar_campana' limit 1),
  'simulacion fiel: cm_publicar_campana SIN candado (como produccion)');
select pg_temp.chk((select count(*) from pg_policies where schemaname = 'public'
    and policyname in ('asientos_insert_modulo','asientos_update_modulo',
                       'asiento_lineas_insert_modulo','asiento_lineas_update_modulo',
                       'asiento_bitacora_insert_modulo')) = 5,
  'simulacion fiel: las 5 puertas latentes de Finanzas estan presentes');
select pg_temp.chk(not exists (select 1 from pg_policies
    where tablename = 'objects' and policyname = 'campanas_delete_marketing'),
  'simulacion fiel: sin permiso de borrado en el bucket campanas');
select pg_temp.chk(
  (select obj_description('catalogo_publico'::regclass) like '%JUBILAR hook_corto%'),
  'simulacion fiel: la vista es la del 3-oct (hook_corto jubilado)');

-- Huella de la vista ANTES, para probar que la migracion NO la toca.
create temp table vista_antes as
select obj_description('catalogo_publico'::regclass) as com,
       md5(pg_get_viewdef('catalogo_publico'::regclass)) as def;

-- Campana YA PUBLICADA pero incompleta (sin producto ligado), como las que
-- pueden existir en produccion. La migracion NO debe despublicarla: el candado
-- valida al PUBLICAR, no retroactivamente. Nada se cae al aplicar.
insert into productos (id, sku, nombre, precio_venta, activo)
  values ('b4000000-0000-4000-8000-000000000001', 'PAD-PREV', 'Producto previo', 7000, true);
insert into campana_producto (id, nombre, slug, precio_venta, product_id_ref, publicado, activo) values
  ('a4000000-0000-4000-8000-000000000001', 'Publicada sin producto', 'pad-prev-sin', 7000, null, true, true),
  ('a4000000-0000-4000-8000-000000000002', 'Publicada completa',     'pad-prev-ok',  7000, 'b4000000-0000-4000-8000-000000000001', true, true);
create temp table publicadas_antes as
  select count(*) as n from campana_producto where publicado;

-- ---------- 2. Aplicar la migracion nueva ----------
\ir ../../migrations/20261018000000_puesta_al_dia_sin_vista.sql

-- ---------- 3. Los tres huecos quedaron cerrados ----------
select pg_temp.chk(
  (select pg_get_functiondef(p.oid) like '%product_id_ref%'
     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'cm_publicar_campana' limit 1),
  'despues: cm_publicar_campana YA tiene el candado');
select pg_temp.chk((select count(*) from pg_policies where schemaname = 'public'
    and policyname in ('asientos_insert_modulo','asientos_update_modulo',
                       'asiento_lineas_insert_modulo','asiento_lineas_update_modulo',
                       'asiento_bitacora_insert_modulo')) = 0,
  'despues: las 5 puertas latentes de Finanzas quedaron cerradas');
select pg_temp.chk(exists (select 1 from pg_policies
    where tablename = 'objects' and policyname = 'campanas_delete_marketing' and cmd = 'DELETE'),
  'despues: Marketing puede borrar SOLO en el bucket campanas');

-- ---------- 4. LA VISTA NO SE TOCO (el punto de todo este ejercicio) ----------
select pg_temp.chk(
  (select v.com = obj_description('catalogo_publico'::regclass)
      and v.def = md5(pg_get_viewdef('catalogo_publico'::regclass)) from vista_antes v),
  'la vista catalogo_publico quedo INTACTA (sin retroceso a la version vieja)');
select pg_temp.chk(
  (select obj_description('catalogo_publico'::regclass) like '%JUBILAR hook_corto%'),
  'la vista sigue siendo la del 3-oct (hook_corto sigue jubilado)');
select pg_temp.chk(
  has_table_privilege('service_role', 'catalogo_publico', 'select')
  and has_table_privilege('anon', 'catalogo_publico', 'select'),
  'la intencion de pago y la tienda siguen leyendo el catalogo');

-- ---------- 4bis. NADA de lo que ya funciona se cae al aplicar ----------
select pg_temp.chk((select n from publicadas_antes) = (select count(*) from campana_producto where publicado),
  'aplicar la migracion NO despublica ninguna campana existente (ni las incompletas)');
select pg_temp.chk((select publicado from campana_producto where id = 'a4000000-0000-4000-8000-000000000001'),
  'una campana publicada SIN producto ligado sigue publicada (el candado solo valida al publicar)');
select pg_temp.chk(
  (select count(*) from catalogo_publico) >= 1
  and (select agotado from catalogo_publico where slug = 'pad-prev-sin') is true,
  'la tienda sigue sirviendo el catalogo y la campana sin producto aparece como agotada (regla del 3-oct)');

-- ---------- 5. Comportamiento real del candado ----------
-- Sin begin/rollback a proposito: esta base local se recrea en cada corrida
-- (correr-puesta-al-dia.sh hace drop/create database), y un rollback aqui
-- borraria tambien las filas del informe en pg_temp.r.
insert into auth.users (id, email) values
  ('7e590000-0000-4000-8000-0000000000a1', 'pad-mkt@local.invalid') on conflict do nothing;
insert into perfiles (id, rol, modulos) values
  ('7e590000-0000-4000-8000-0000000000a1', 'prueba', '{marketing}') on conflict (id) do nothing;

-- producto activo con precio, y uno inactivo
insert into productos (id, sku, nombre, precio_venta, activo) values
  ('b3000000-0000-4000-8000-000000000001', 'PAD-OK',  'Producto ligado',  5000, true),
  ('b3000000-0000-4000-8000-000000000002', 'PAD-OFF', 'Producto inactivo', 5000, false);
-- campanas: sin producto / con producto inactivo / sin precio / completa
insert into campana_producto (id, nombre, slug, precio_venta, product_id_ref, publicado, activo) values
  ('a3000000-0000-4000-8000-000000000001', 'Sin producto',      'pad-sin',  5000, null, false, true),
  ('a3000000-0000-4000-8000-000000000002', 'Producto inactivo', 'pad-off',  5000, 'b3000000-0000-4000-8000-000000000002', false, true),
  ('a3000000-0000-4000-8000-000000000003', 'Sin precio',        'pad-prec',    0, 'b3000000-0000-4000-8000-000000000001', false, true),
  ('a3000000-0000-4000-8000-000000000004', 'Completa',          'pad-ok',   5000, 'b3000000-0000-4000-8000-000000000001', false, true);

create or replace function pg_temp.publicar(p_id uuid) returns text language plpgsql as $$
begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"7e590000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
  perform cm_publicar_campana(p_id, true);
  execute 'reset role';
  return 'PUBLICADA';
exception when others then
  execute 'reset role';
  return sqlerrm;
end $$;

select pg_temp.chk(pg_temp.publicar('a3000000-0000-4000-8000-000000000001') like '%liga primero un producto%',
  'candado: NO publica una campana sin producto de Inventario ligado');
select pg_temp.chk(pg_temp.publicar('a3000000-0000-4000-8000-000000000002') like '%inactivo%',
  'candado: NO publica si el producto de Inventario esta inactivo');
select pg_temp.chk(pg_temp.publicar('a3000000-0000-4000-8000-000000000003') like '%precio de venta mayor que cero%',
  'candado: NO publica sin precio de venta positivo');
select pg_temp.chk(pg_temp.publicar('a3000000-0000-4000-8000-000000000004') = 'PUBLICADA',
  'candado: SI publica una campana completa (producto activo + precio)');
select pg_temp.chk((select publicado from campana_producto where id = 'a3000000-0000-4000-8000-000000000004'),
  'la campana completa quedo efectivamente publicada');
select pg_temp.chk((select count(*) from campana_producto where id in
    ('a3000000-0000-4000-8000-000000000001','a3000000-0000-4000-8000-000000000002','a3000000-0000-4000-8000-000000000003')
    and publicado) = 0,
  'ninguna campana incompleta quedo publicada');
-- despublicar siempre se permite (no se castiga corregir)
select pg_temp.chk((select pg_temp.publicar('a3000000-0000-4000-8000-000000000004')) = 'PUBLICADA',
  'publicar es idempotente sobre una campana valida');

-- ---------- 6. Finanzas sigue escribiendo por RPC tras cerrar las puertas ----------
insert into auth.users (id, email) values
  ('7e590000-0000-4000-8000-0000000000a2', 'pad-fin@local.invalid') on conflict do nothing;
insert into perfiles (id, rol, modulos) values
  ('7e590000-0000-4000-8000-0000000000a2', 'prueba', '{finanzas}') on conflict (id) do nothing;
create or replace function pg_temp.asiento() returns text language plpgsql as $$
declare x jsonb;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"7e590000-0000-4000-8000-0000000000a2","role":"authenticated"}', true);
  -- firma real: guardar_asiento(date, text, jsonb) -- 3 parametros
  x := to_jsonb(guardar_asiento(current_date, 'PRUEBA puesta al dia forward',
         '[{"cuenta_codigo":"111005","debe":1000,"haber":0},{"cuenta_codigo":"413505","debe":0,"haber":1000}]'::jsonb));
  execute 'reset role';
  return 'OK';
exception when others then
  execute 'reset role';
  return sqlerrm;
end $$;
select pg_temp.chk(pg_temp.asiento() = 'OK',
  'Finanzas: guardar_asiento sigue funcionando sin las policies directas');

-- Las OTRAS dos escrituras de Finanzas (editar y anular) tambien tocan
-- asientos / asiento_lineas / asiento_bitacora. Si cerrar las puertas las
-- rompiera, se veria aqui.
create or replace function pg_temp.fin_ciclo() returns text language plpgsql as $$
declare v_id uuid;
begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"7e590000-0000-4000-8000-0000000000a2","role":"authenticated"}', true);
  v_id := guardar_asiento(current_date, 'PRUEBA ciclo completo',
            '[{"cuenta_codigo":"111005","debe":2000,"haber":0},{"cuenta_codigo":"413505","debe":0,"haber":2000}]'::jsonb);
  perform editar_asiento(v_id, current_date, 'PRUEBA ciclo editado',
            '[{"cuenta_codigo":"111005","debe":3000,"haber":0},{"cuenta_codigo":"413505","debe":0,"haber":3000}]'::jsonb);
  perform anular_asiento(v_id, 'prueba');
  execute 'reset role';
  return 'OK';
exception when others then
  execute 'reset role';
  return sqlerrm;
end $$;
select pg_temp.chk(pg_temp.fin_ciclo() = 'OK',
  'Finanzas: editar_asiento y anular_asiento tambien siguen funcionando (con bitacora)');
select pg_temp.chk((select count(*) from asiento_bitacora) >= 2,
  'Finanzas: la bitacora sigue registrando (editar y anular dejaron rastro)');

select case when ok then 'pasa' else 'FALLA' end || ' | ' || que from pg_temp.r order by n;
select 'RESUMEN | ' || count(*) || ' comprobaciones · ' || count(*) filter (where not ok) || ' fallan' from pg_temp.r;
