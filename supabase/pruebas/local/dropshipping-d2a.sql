-- ============================================================
-- MAGANDHI · Pruebas D2a · «Llevar a Campañas»
-- ------------------------------------------------------------
-- Mide que la importación sea atómica e idempotente, que solo acepte fotos
-- propias ya subidas, que el vínculo campaña ↔ proveedor no se pueda torcer
-- desde el editor ni la API, y que nada de esto publique ni toque Inventario.
-- SOLO LOCAL: todo se deshace al final.
-- ============================================================
\set ON_ERROR_STOP 1
set client_min_messages = warning;
drop table if exists pg_temp.r;
create temp table r (n serial, ok boolean, que text);
create or replace function pg_temp.chk(p boolean, q text) returns void language sql as
$$ insert into pg_temp.r (ok, que) values (coalesce(p, false), q) $$;

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

create or replace function pg_temp.err_postgres(q text) returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute q;
  return 'SIN ERROR';
exception when others then
  return sqlerrm;
end $$;

begin;

-- Personas: el dueño real (dropshipping + marketing), y dos perfiles a medias.
insert into auth.users (id, email) values
  ('7e5a0000-0000-4000-8000-000000000001', 'duo@local.invalid'),
  ('7e5a0000-0000-4000-8000-000000000002', 'solo-ds@local.invalid'),
  ('7e5a0000-0000-4000-8000-000000000003', 'solo-mkt@local.invalid') on conflict do nothing;
insert into perfiles (id, rol, modulos) values
  ('7e5a0000-0000-4000-8000-000000000001', 'prueba', '{dropshipping,marketing}'),
  ('7e5a0000-0000-4000-8000-000000000002', 'prueba', '{dropshipping}'),
  ('7e5a0000-0000-4000-8000-000000000003', 'prueba', '{marketing}') on conflict (id) do nothing;

-- Un candidato en bandeja y uno descartado, guardados por la RPC de D1.
select pg_temp.como_json('7e5a0000-0000-4000-8000-000000000001',
  $$select to_jsonb(ds_guardar_candidato('900001', '', 'prov-9', 'Bafle Bluetooth', 'Tecnología', 40000, 80000, 100, now(), '["https://d39ru7awumhhs2.cloudfront.net/colombia/a.jpg"]'::jsonb))$$);
select pg_temp.como_json('7e5a0000-0000-4000-8000-000000000001',
  $$select to_jsonb(ds_guardar_candidato('900002', '', 'prov-9', 'Descartado', null, 1000, 2000, 3, now(), '[]'::jsonb))$$);
select pg_temp.como_json('7e5a0000-0000-4000-8000-000000000001',
  $$select to_jsonb(ds_actualizar_estado_candidato((select id from dropshipping_candidatos where producto_externo_id = '900002'), 'descartado'))$$);
create temp table c as select id from dropshipping_candidatos where producto_externo_id = '900001';
grant select on c to authenticated;

-- Las fotos YA convertidas por el panel: grande + -sm en la raíz del bucket.
insert into storage.objects (bucket_id, name) values
  ('campanas', 'mg8k2-abc123.webp'), ('campanas', 'mg8k2-abc123-sm.webp'),
  ('campanas', 'mg8k3-def456.webp'), ('campanas', 'mg8k3-def456-sm.webp'),
  ('otro-bucket', 'ajena.webp');

-- ------------------------------------------------------------------
-- 1. Quién puede llevar a Campañas
-- ------------------------------------------------------------------
select pg_temp.chk(
  pg_temp.err_como('7e5a0000-0000-4000-8000-000000000002',
    $$select ds_llevar_a_campanas((select id from c), '', null, null, 40000, 100, now(), '[]'::jsonb)$$) like 'DS_SIN_ACCESO%',
  'solo Dropshipping NO basta: crear campaña exige también Marketing');
select pg_temp.chk(
  pg_temp.err_como('7e5a0000-0000-4000-8000-000000000003',
    $$select ds_llevar_a_campanas((select id from c), '', null, null, 40000, 100, now(), '[]'::jsonb)$$) like 'DS_SIN_ACCESO%',
  'solo Marketing NO basta: crear ficha proveedor exige también Dropshipping');
select pg_temp.chk(
  not has_function_privilege('anon', 'ds_llevar_a_campanas(uuid,text,text,text,bigint,integer,timestamptz,jsonb)'::regprocedure, 'execute')
  and has_function_privilege('authenticated', 'ds_llevar_a_campanas(uuid,text,text,text,bigint,integer,timestamptz,jsonb)'::regprocedure, 'execute'),
  'anon no ejecuta la importación; authenticated sí (la guardia interna decide)');
select pg_temp.chk(
  not has_function_privilege('authenticated', 'ds__campana_vinculo_proveedor()'::regprocedure, 'execute'),
  'el gatillo del vínculo no es una puerta del panel');

-- ------------------------------------------------------------------
-- 2. Solo fotos propias ya subidas
-- ------------------------------------------------------------------
select pg_temp.chk(
  pg_temp.err_como('7e5a0000-0000-4000-8000-000000000001',
    $$select ds_llevar_a_campanas((select id from c), '', null, null, 40000, 100, now(), '["https://d39ru7awumhhs2.cloudfront.net/colombia/a.jpg"]'::jsonb)$$) like 'DS_IMAGEN_INVALIDA%',
  'una URL remota de Dropi NO entra a Campañas');
select pg_temp.chk(
  pg_temp.err_como('7e5a0000-0000-4000-8000-000000000001',
    $$select ds_llevar_a_campanas((select id from c), '', null, null, 40000, 100, now(), '["mg8k2-abc123-sm.webp"]'::jsonb)$$) like 'DS_IMAGEN_INVALIDA%',
  'la variante -sm no se guarda como foto principal (se deriva)');
select pg_temp.chk(
  pg_temp.err_como('7e5a0000-0000-4000-8000-000000000001',
    $$select ds_llevar_a_campanas((select id from c), '', null, null, 40000, 100, now(), '["carpeta/../x.webp"]'::jsonb)$$) like 'DS_IMAGEN_INVALIDA%',
  'rutas con carpetas o .. se rechazan');
select pg_temp.chk(
  pg_temp.err_como('7e5a0000-0000-4000-8000-000000000001',
    $$select ds_llevar_a_campanas((select id from c), '', null, null, 40000, 100, now(), '["nunca-subida.webp"]'::jsonb)$$) like 'DS_IMAGEN_NO_SUBIDA%',
  'una key que no existe en el bucket se rechaza');
select pg_temp.chk(
  pg_temp.err_como('7e5a0000-0000-4000-8000-000000000001',
    $$select ds_llevar_a_campanas((select id from c), '', null, null, 40000, 100, now(), '["ajena.webp"]'::jsonb)$$) like 'DS_IMAGEN_NO_SUBIDA%',
  'una key de otro bucket no cuenta');
select pg_temp.chk(
  not exists (select 1 from productos where origen = 'proveedor' and nombre = 'Bafle Bluetooth')
  and not exists (select 1 from producto_proveedor where producto_externo_id = '900001'),
  'un intento fallido no deja producto ni ficha a medias');

-- ------------------------------------------------------------------
-- 3. La importación atómica
-- ------------------------------------------------------------------
create temp table imp as
select pg_temp.como_json('7e5a0000-0000-4000-8000-000000000001',
  $$select ds_llevar_a_campanas((select id from c), '', null, 'Bafle Bluetooth', 41000, 97, '2026-10-10 12:00:00+00', '["mg8k2-abc123.webp","mg8k3-def456.webp","mg8k2-abc123.webp"]'::jsonb)$$) as j;
select pg_temp.chk((select (j->>'ya_existia')::boolean = false and j->>'campana_id' is not null and j->>'producto_id' is not null from imp),
  'devuelve producto y campaña nuevos');
select pg_temp.chk(
  (select origen = 'proveedor' and sku ~ '^MAG-DROP-[0-9]{4}$' and costo_unitario is null and activo and categoria = 'Tecnología'
     from productos where id = (select (j->>'producto_id')::uuid from imp)),
  'producto interno proveedor con SKU MAG-DROP-NNNN y SIN costo de inventario');
select pg_temp.chk(
  (select producto_externo_id = '900001' and variacion_externa_id = '' and costo_reportado = 41000
      and stock_reportado = 97 and stock_vence_en = stock_leido_en and candidato_id = (select id from c)
      and proveedor_externo_id = 'prov-9'
     from producto_proveedor where product_id = (select (j->>'producto_id')::uuid from imp)),
  'ficha proveedor con costo y stock de la relectura, NACE VENCIDA (no vende) y apunta al candidato');
select pg_temp.chk(
  (select not publicado and activo and not sello_elegido and not aviso_urgencia_activo and precio_venta is null
      and slug is null and imagenes = '["mg8k2-abc123.webp","mg8k3-def456.webp"]'::jsonb
      and product_id_ref = (select (j->>'producto_id')::uuid from imp) and nombre = 'Bafle Bluetooth'
     from campana_producto where id = (select (j->>'campana_id')::uuid from imp)),
  'borrador sin publicar, sin sello, sin precio, con las fotos propias (sin duplicar) y ligado');
select pg_temp.chk(
  (select estado = 'llevado_a_campanas' from dropshipping_candidatos where id = (select id from c)),
  'el candidato queda llevado a Campañas');

-- Repetir el clic no duplica nada.
create temp table imp2 as
select pg_temp.como_json('7e5a0000-0000-4000-8000-000000000001',
  $$select ds_llevar_a_campanas((select id from c), '', null, 'Otro nombre', 1, 1, now(), '[]'::jsonb)$$) as j;
select pg_temp.chk(
  (select (imp2.j->>'ya_existia')::boolean and imp2.j->>'campana_id' = imp.j->>'campana_id' from imp, imp2)
  and (select count(*) = 1 from producto_proveedor where producto_externo_id = '900001')
  and (select count(*) = 1 from campana_producto where product_id_ref = (select (j->>'producto_id')::uuid from imp)),
  'idempotente: el segundo clic devuelve lo ya creado sin duplicar ni pisar');

-- Otra variante del mismo producto Dropi = otro producto y otra campaña.
create temp table imp3 as
select pg_temp.como_json('7e5a0000-0000-4000-8000-000000000001',
  $$select ds_llevar_a_campanas((select id from c), '55', 'Color: Negro', 'Bafle Bluetooth · Negro', 42000, null, null, '[]'::jsonb)$$) as j;
select pg_temp.chk(
  (select (j->>'ya_existia')::boolean = false from imp3)
  and (select count(*) = 2 from producto_proveedor where producto_externo_id = '900001')
  and (select variacion_nombre = 'Color: Negro' and stock_reportado is null and stock_leido_en is null and stock_vence_en is null
         from producto_proveedor where producto_externo_id = '900001' and variacion_externa_id = '55'),
  'otra variante crea su propio producto/campaña; sin lectura de stock deja los tres campos nulos');

select pg_temp.chk(
  pg_temp.err_como('7e5a0000-0000-4000-8000-000000000001',
    $$select ds_llevar_a_campanas((select id from dropshipping_candidatos where producto_externo_id = '900002'), '', null, null, 1, 1, now(), '[]'::jsonb)$$) like 'DS_CANDIDATO_DESCARTADO%',
  'un candidato descartado no se lleva hasta restaurarlo');
select pg_temp.chk(
  pg_temp.err_como('7e5a0000-0000-4000-8000-000000000001',
    $$select ds_actualizar_estado_candidato((select id from c), 'descartado')$$) like 'DS_CANDIDATO_YA_LLEVADO%',
  'un candidato ya llevado no se descarta desde la bandeja');

-- ------------------------------------------------------------------
-- 4. El vínculo no se tuerce desde el editor ni la API
-- ------------------------------------------------------------------
insert into productos (id, sku, nombre, activo) values
  ('d2a00000-0000-4000-8000-000000000001', 'D2A-PROPIO', 'Propio D2a', true);
insert into campana_producto (id, nombre, product_id_ref, activo) values
  ('d2a00000-0000-4000-8000-000000000011', 'Campaña propia', 'd2a00000-0000-4000-8000-000000000001', true);
create temp table ids as select (j->>'campana_id')::uuid as campana, (j->>'producto_id')::uuid as producto from imp;
grant select on ids to authenticated;

select pg_temp.chk(
  pg_temp.err_como('7e5a0000-0000-4000-8000-000000000003',
    $$select cm_editar_campana(p_id => (select campana from ids), p_nombre => 'Bafle curado', p_precio_venta => 99000,
        p_product_id_ref => (select producto from ids))$$) = 'SIN ERROR',
  'guardar en el editor conservando el mismo producto proveedor funciona');
select pg_temp.chk(
  (select nombre = 'Bafle curado' and precio_venta = 99000 from campana_producto where id = (select campana from ids)),
  'el editor sí cambia copy y precio comercial');
select pg_temp.chk(
  pg_temp.err_como('7e5a0000-0000-4000-8000-000000000003',
    $$select cm_editar_campana(p_id => (select campana from ids), p_nombre => 'x',
        p_product_id_ref => 'd2a00000-0000-4000-8000-000000000001')$$) like 'DS_VINCULO_PROVEEDOR_FIJO%',
  'una campaña proveedor no se re-liga a un producto propio');
select pg_temp.chk(
  pg_temp.err_como('7e5a0000-0000-4000-8000-000000000003',
    $$select cm_editar_campana(p_id => (select campana from ids), p_nombre => 'x', p_product_id_ref => null)$$) like 'DS_VINCULO_PROVEEDOR_FIJO%',
  'ni se des-liga dejando la ficha proveedor huérfana');
select pg_temp.chk(
  pg_temp.err_como('7e5a0000-0000-4000-8000-000000000003',
    $$select cm_editar_campana(p_id => 'd2a00000-0000-4000-8000-000000000011', p_nombre => 'x', p_product_id_ref => (select producto from ids))$$) like 'DS_VINCULO_SOLO_IMPORTACION%',
  'una campaña propia no se liga a un producto proveedor');
select pg_temp.chk(
  pg_temp.err_como('7e5a0000-0000-4000-8000-000000000003',
    $$select cm_crear_campana(p_nombre => 'Atajo', p_product_id_ref => (select producto from ids))$$) like 'DS_VINCULO_SOLO_IMPORTACION%',
  'crear campaña a mano con producto proveedor se rechaza');
select pg_temp.chk(
  pg_temp.err_postgres(
    $$insert into campana_producto (nombre, product_id_ref) values ('Atajo privilegiado', (select producto from ids))$$) like 'DS_VINCULO_SOLO_IMPORTACION%',
  'el gatillo rige incluso por encima de RLS (service_role)');
select pg_temp.chk(
  pg_temp.err_como('7e5a0000-0000-4000-8000-000000000003',
    $$select cm_editar_campana(p_id => 'd2a00000-0000-4000-8000-000000000011', p_nombre => 'Propia sigue', p_product_id_ref => 'd2a00000-0000-4000-8000-000000000001')$$) = 'SIN ERROR',
  'las campañas propias siguen funcionando igual');

-- ------------------------------------------------------------------
-- 5. Nada de esto publica ni toca Inventario
-- ------------------------------------------------------------------
select pg_temp.chk(
  pg_temp.err_como('7e5a0000-0000-4000-8000-000000000003',
    $$select cm_publicar_campana((select campana from ids), true)$$) like 'DS_PUBLICACION_PENDIENTE%',
  'el borrador proveedor sigue sin poder publicarse (espera D2c)');
select pg_temp.chk(
  not exists (select 1 from catalogo_publico where id = (select campana from ids)),
  'no aparece en catalogo_publico');
select pg_temp.chk(
  not exists (select 1 from movimientos_inventario where product_id = (select producto from ids))
  and not exists (select 1 from stock_actual where product_id = (select producto from ids)),
  'cero movimientos de Inventario y fuera de stock_actual');

select case when ok then 'pasa' else 'FALLA' end || ' | ' || que from pg_temp.r order by n;
select 'RESUMEN | ' || count(*) || ' comprobaciones · ' || count(*) filter (where not ok) || ' fallan' from pg_temp.r;
rollback;
