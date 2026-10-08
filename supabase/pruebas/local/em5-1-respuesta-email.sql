-- ============================================================
-- Impulse · Pruebas de EM5.1 (la respuesta a email alimenta clúster y segmentos)
-- SOLO LOCAL: siembra datos ficticios dentro de una transaccion que se deshace.
--   psql -d impulse_pruebas -f supabase/pruebas/local/em5-1-respuesta-email.sql
-- ============================================================
\set ON_ERROR_STOP 1
set client_min_messages = warning;

drop table if exists pg_temp.r;
create temp table r (n serial, ok boolean, que text);
create or replace function pg_temp.chk(p boolean, q text) returns void language sql as
$$ insert into pg_temp.r (ok, que) values (coalesce(p, false), q) $$;

begin;

insert into auth.users (id, email) values
  ('7e551000-0000-4000-8000-000000000001', 'em51-mkt@local.invalid'),
  ('7e551000-0000-4000-8000-000000000002', 'em51-em@local.invalid') on conflict do nothing;
insert into perfiles (id, rol, modulos) values
  ('7e551000-0000-4000-8000-000000000001', 'prueba', '{marketing}'),
  ('7e551000-0000-4000-8000-000000000002', 'prueba', '{email_marketing}') on conflict (id) do nothing;

-- Clientes: Ana, Beto, Caro (con contacto), Fede (cliente SIN contacto)
insert into clientes (id, nombre, correo, correo_norm, ciudad) values
  ('c1000000-0000-4000-8000-00000000000a', 'Ana',  'ana@y.invalid',  'ana@y.invalid',  'Tunja'),
  ('c1000000-0000-4000-8000-00000000000b', 'Beto', 'beto@y.invalid', 'beto@y.invalid', 'Tunja'),
  ('c1000000-0000-4000-8000-00000000000c', 'Caro', 'caro@y.invalid', 'caro@y.invalid', 'Bogotá'),
  ('c1000000-0000-4000-8000-00000000000f', 'Fede', 'fede@y.invalid', 'fede@y.invalid', 'Tunja');
insert into em_contactos (id, correo, correo_norm, customer_id, nombre, estado, fuente, consentimiento_en, consentimiento_texto, politica_version, evidencia) values
  ('a1000000-0000-4000-8000-00000000000a', 'ana@y.invalid',  'ana@y.invalid',  'c1000000-0000-4000-8000-00000000000a', 'Ana',  'suscrito', 'manual', now(), 't', '1.0', '{}'),
  ('a1000000-0000-4000-8000-00000000000b', 'beto@y.invalid', 'beto@y.invalid', 'c1000000-0000-4000-8000-00000000000b', 'Beto', 'suscrito', 'manual', now(), 't', '1.0', '{}'),
  ('a1000000-0000-4000-8000-00000000000c', 'caro@y.invalid', 'caro@y.invalid', 'c1000000-0000-4000-8000-00000000000c', 'Caro', 'suscrito', 'manual', now(), 't', '1.0', '{}'),
  ('a1000000-0000-4000-8000-00000000000d', 'dani@y.invalid', 'dani@y.invalid', null, 'Dani', 'suscrito', 'manual', now(), 't', '1.0', '{}'),
  ('a1000000-0000-4000-8000-00000000000e', 'eli@y.invalid',  'eli@y.invalid',  null, 'Eli',  'suscrito', 'manual', now(), 't', '1.0', '{}');

-- Campanas: C0 hace 120 d, C1 hace 30 d, C2 hace 10 d, C3 hace 2 d, C4 programada a futuro, C5 borrador
insert into em_campanas (id, nombre_interno, asunto, estado, utm_campaign, resend_broadcast_id, enviada_en, programada_para) values
  ('b1000000-0000-4000-8000-000000000000', 'C0', 'a', 'enviada',    'c0-y', 'b-c0', now() - interval '120 days', null),
  ('b1000000-0000-4000-8000-000000000001', 'C1', 'a', 'enviada',    'c1-y', 'b-c1', now() - interval '30 days', null),
  ('b1000000-0000-4000-8000-000000000002', 'C2', 'a', 'enviada',    'c2-y', 'b-c2', now() - interval '10 days', null),
  ('b1000000-0000-4000-8000-000000000003', 'C3', 'a', 'enviada',    'c3-y', 'b-c3', now() - interval '2 days', null),
  ('b1000000-0000-4000-8000-000000000004', 'C4', 'a', 'programada', 'c4-y', 'b-c4', null, now() + interval '3 days'),
  ('b1000000-0000-4000-8000-000000000005', 'C5', 'a', 'borrador',   'c5-y', null, null, null);
insert into em_campana_destinatarios (campana_id, contacto_id, correo, estado)
select v.c::uuid, v.k::uuid, 'x', v.e from (values
  ('b1000000-0000-4000-8000-000000000000', 'a1000000-0000-4000-8000-00000000000b', 'listo'),
  ('b1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-00000000000a', 'listo'),
  ('b1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-00000000000b', 'listo'),
  ('b1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-00000000000c', 'listo'),
  ('b1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-00000000000d', 'listo'),
  ('b1000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-00000000000a', 'listo'),
  ('b1000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-00000000000b', 'listo'),
  ('b1000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-00000000000c', 'listo'),
  ('b1000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-00000000000e', 'excluido'),
  ('b1000000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-00000000000a', 'listo'),
  ('b1000000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-00000000000b', 'listo'),
  ('b1000000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-00000000000a', 'listo')
) v(c, k, e);

-- Clics: Ana en C1 (hace 29 d) y C3 (hace 1 d); Beto en C0 (hace 119 d) y C1 (hace 29 d). Caro: aperturas, sin clic.
insert into em_eventos (svix_id, evento, tipo, origen, campana_id, contacto_id, cuando) values
  ('msg_y_1', 'email.clicked', 'clic',     'campana', 'b1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-00000000000a', now() - interval '29 days'),
  ('msg_y_2', 'email.clicked', 'clic',     'campana', 'b1000000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-00000000000a', now() - interval '1 day'),
  ('msg_y_3', 'email.clicked', 'clic',     'campana', 'b1000000-0000-4000-8000-000000000000', 'a1000000-0000-4000-8000-00000000000b', now() - interval '119 days'),
  ('msg_y_4', 'email.clicked', 'clic',     'campana', 'b1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-00000000000b', now() - interval '29 days'),
  ('msg_y_5', 'email.opened',  'apertura', 'campana', 'b1000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-00000000000c', now() - interval '9 days'),
  ('msg_y_6', 'email.opened',  'apertura', 'campana', 'b1000000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-00000000000c', now() - interval '1 day');

-- Pedidos: Ana hoy (atribuido aprox. a C3), Beto y Caro hace 40 d (antes de clics recientes), Fede hace 5 d.
insert into pedidos (id, customer_id, fecha_orden, total, creado) values
  ('d1000000-0000-4000-8000-00000000000a', 'c1000000-0000-4000-8000-00000000000a', current_date, 30000, now()),
  ('d1000000-0000-4000-8000-00000000000b', 'c1000000-0000-4000-8000-00000000000b', current_date - 40, 20000, now() - interval '40 days'),
  ('d1000000-0000-4000-8000-00000000000c', 'c1000000-0000-4000-8000-00000000000c', current_date - 40, 10000, now() - interval '40 days'),
  ('d1000000-0000-4000-8000-00000000000f', 'c1000000-0000-4000-8000-00000000000f', current_date - 5, 15000, now() - interval '5 days');

-- ---------------- em__perfil_email ----------------
create temp table pe as select * from em__perfil_email();
select pg_temp.chk((select campanas_recibidas = 3 and campanas_con_clic = 2 and pct_campanas_clic = 66.7 and clics_90d = 2
                       and dias_desde_ultimo_clic = 1 and campanas_seguidas_sin_clic = 0 and compras_atribuidas = 1 and valor_atribuido = 30000
                      from pe where contacto_id = 'a1000000-0000-4000-8000-00000000000a'), 'Ana: 3 recibidas, 2 con clic, 66,7 %, 2 clics en 90 d, ultimo clic hace 1 d, 0 seguidas sin clic, 1 compra');
select pg_temp.chk((select campanas_recibidas = 4 and campanas_con_clic = 2 and pct_campanas_clic = 50 and clics_90d = 1
                       and dias_desde_ultimo_clic = 29 and campanas_seguidas_sin_clic = 2 and compras_atribuidas = 0
                      from pe where contacto_id = 'a1000000-0000-4000-8000-00000000000b'), 'Beto: el clic de hace 119 d cuenta para % pero no para 90 d; 2 seguidas sin clic');
select pg_temp.chk((select campanas_recibidas = 2 and campanas_con_clic = 0 and pct_campanas_clic = 0 and clics_90d = 0
                       and dias_desde_ultimo_clic is null and campanas_seguidas_sin_clic = 2
                      from pe where contacto_id = 'a1000000-0000-4000-8000-00000000000c'), 'Caro: abrio pero no clico -> 0 % (las aperturas no cuentan)');
select pg_temp.chk(not exists (select 1 from pe where contacto_id = 'a1000000-0000-4000-8000-00000000000e'), 'Eli: excluido de C2 y sin otras -> no tiene el dato (no es 0)');
select pg_temp.chk(not exists (select 1 from pe where 'b1000000-0000-4000-8000-000000000004' = any(campanas_recibidas_ids)), 'campana programada a futuro no cuenta como recibida');
select pg_temp.chk((select campanas_recibidas_ids[1] = 'b1000000-0000-4000-8000-000000000001' from pe where contacto_id = 'a1000000-0000-4000-8000-00000000000a'), 'ids recibidos en orden de envio');

-- ---------------- Segmentos con los campos nuevos (nucleo interno) ----------------
create temp table seg as
select 'clico_c1' k, (select array_agg(nombre order by nombre) from em_contactos where id in (select * from em__segmento_contactos('{"modo":"y","reglas":[{"campo":"clico_campana","op":"incluye","valor":"b1000000-0000-4000-8000-000000000001"}]}'))) v
union all select 'recibio_c2_sin_clic', (select array_agg(nombre order by nombre) from em_contactos where id in (select * from em__segmento_contactos('{"modo":"y","reglas":[{"campo":"recibio_campana","op":"incluye","valor":"b1000000-0000-4000-8000-000000000002"},{"campo":"clico_campana","op":"no_incluye","valor":"b1000000-0000-4000-8000-000000000002"}]}')))
union all select 'seguidas_2', (select array_agg(nombre order by nombre) from em_contactos where id in (select * from em__segmento_contactos('{"modo":"y","reglas":[{"campo":"campanas_seguidas_sin_clic","op":"gte","valor":"2"}]}')))
union all select 'clics90', (select array_agg(nombre order by nombre) from em_contactos where id in (select * from em__segmento_contactos('{"modo":"y","reglas":[{"campo":"clics_90d","op":"gte","valor":"1"}]}')))
union all select 'nunca_clic', (select array_agg(nombre order by nombre) from em_contactos where correo like '%@y.invalid' and id in (select * from em__segmento_contactos('{"modo":"y","reglas":[{"campo":"dias_desde_ultimo_clic","op":"no_tiene"}]}')))
union all select 'pct50', (select array_agg(nombre order by nombre) from em_contactos where id in (select * from em__segmento_contactos('{"modo":"y","reglas":[{"campo":"pct_campanas_clic","op":"gte","valor":"50"}]}')))
union all select 'compras', (select array_agg(nombre order by nombre) from em_contactos where id in (select * from em__segmento_contactos('{"modo":"y","reglas":[{"campo":"compras_por_email","op":"gte","valor":"1"}]}')))
union all select 'cero_recibidas', (select array_agg(nombre order by nombre) from em_contactos where correo like '%@y.invalid' and id in (select * from em__segmento_contactos('{"modo":"y","reglas":[{"campo":"campanas_recibidas","op":"eq","valor":"0"}]}')))
union all select 'mixto_tunja_clic', (select array_agg(nombre order by nombre) from em_contactos where id in (select * from em__segmento_contactos('{"modo":"y","reglas":[{"campo":"ciudad","op":"eq","valor":"tunja"},{"campo":"campanas_con_clic","op":"gte","valor":"1"}]}')))
union all select 'viejo_es_cliente', (select array_agg(nombre order by nombre) from em_contactos where correo like '%@y.invalid' and id in (select * from em__segmento_contactos('{"modo":"y","reglas":[{"campo":"es_cliente","op":"es","valor":"true"}]}')));
select pg_temp.chk((select v from seg where k = 'clico_c1') = array['Ana','Beto'], 'hizo clic en C1 -> Ana, Beto');
select pg_temp.chk((select v from seg where k = 'recibio_c2_sin_clic') = array['Ana','Beto','Caro'], 'recibio C2 y no hizo clic en C2 -> Ana, Beto, Caro (Eli fue excluida)');
select pg_temp.chk((select v from seg where k = 'seguidas_2') = array['Beto','Caro'], '2+ campanas seguidas sin clic -> Beto, Caro');
select pg_temp.chk((select v from seg where k = 'clics90') = array['Ana','Beto'], 'con clic en 90 dias -> Ana, Beto');
select pg_temp.chk((select v from seg where k = 'nunca_clic') = array['Caro','Dani','Eli'], 'nunca hizo clic (no tiene el dato) -> Caro, Dani, Eli');
select pg_temp.chk((select v from seg where k = 'pct50') = array['Ana','Beto'], '% campanas con clic >= 50 -> Ana, Beto');
select pg_temp.chk((select v from seg where k = 'compras') = array['Ana'], 'compro gracias a un correo -> Ana');
select pg_temp.chk((select v from seg where k = 'cero_recibidas') = array['Eli'], '0 campanas recibidas -> Eli');
select pg_temp.chk((select v from seg where k = 'mixto_tunja_clic') = array['Ana','Beto'], 'regla vieja (ciudad) + nueva (clic) combinadas');
select pg_temp.chk((select v from seg where k = 'viejo_es_cliente') = array['Ana','Beto','Caro'], 'reglas de EM2 siguen funcionando igual');

-- Validacion (lista blanca)
do $$ begin perform em__segmento_where('{"modo":"y","reglas":[{"campo":"aperturas","op":"gte","valor":"1"}]}'); perform pg_temp.chk(false, 'aperturas NO es un campo de segmento');
exception when others then perform pg_temp.chk(sqlerrm like 'EM_REGLA_INVALIDA%', 'aperturas NO es un campo de segmento'); end $$;
do $$ begin perform em__segmento_where('{"modo":"y","reglas":[{"campo":"clico_campana","op":"incluye","valor":"x''); drop table pedidos; --"}]}'); perform pg_temp.chk(false, 'inyeccion en campana rechazada');
exception when others then perform pg_temp.chk(sqlerrm like 'EM_REGLA_INVALIDA%', 'inyeccion en campana rechazada'); end $$;
do $$ begin perform em__segmento_where('{"modo":"y","reglas":[{"campo":"clics_90d","op":"gte","valor":"1 or 1=1"}]}'); perform pg_temp.chk(false, 'valor no numerico rechazado');
exception when others then perform pg_temp.chk(sqlerrm like 'EM_REGLA_INVALIDA%', 'valor no numerico rechazado'); end $$;
select pg_temp.chk(exists (select 1 from pedidos), 'la tabla pedidos sigue ahi');

-- RPC del panel: guardar, previa, lista, audiencia de campana, opciones
set local role authenticated;
set local request.jwt.claims to '{"sub":"89e5028d-8c17-4deb-89c3-59acbd0ee2f2","role":"authenticated"}';
create temp table rp as select
  em_segmento_guardar(null, 'Interesados C1', null, '{"modo":"y","reglas":[{"campo":"clico_campana","op":"incluye","valor":"b1000000-0000-4000-8000-000000000001"}]}') as g,
  em_segmento_previa('{"modo":"y","reglas":[{"campo":"campanas_seguidas_sin_clic","op":"gte","valor":"2"}]}') as pv,
  em_segmento_opciones() as op;
create temp table rp2 as select em_campana_audiencia((select (g->>'id')::uuid from rp), 'novedades') as a, em_segmentos_lista(false) as l;
reset role;
select pg_temp.chk((select (pv->>'coinciden')::int = 2 from rp), 'vista previa en vivo con campo nuevo: 2 coinciden');
select pg_temp.chk((select (a->>'n')::int = 2 from rp2), 'audiencia de campana con segmento por clic: 2');
select pg_temp.chk((select exists (select 1 from jsonb_array_elements(l) x where x->>'nombre' = 'Interesados C1' and (x->>'suscritos')::int = 2) from rp2), 'lista de segmentos calcula el tamano');
select pg_temp.chk((select jsonb_array_length(op->'campanas') >= 4
                       and not exists (select 1 from jsonb_array_elements(op->'campanas') x where x->>'nombre' in ('C4','C5'))
                      from rp), 'opciones: campanas enviadas, sin programadas a futuro ni borradores');

-- ---------------- mk_perfiles_clientes ----------------
set local role authenticated;
set local request.jwt.claims to '{"sub":"7e551000-0000-4000-8000-000000000001","role":"authenticated"}';
create temp table mk as select * from mk_perfiles_clientes();
reset role;
select pg_temp.chk((select email_campanas_recibidas = 3 and email_pct_clic = 66.7 and email_clics_90d = 2 and email_dias_desde_ultimo_clic = 1 and email_compras_atribuidas = 1
                      from mk where cliente_ref = 'c1000000-0000-4000-8000-00000000000a'), 'clúster: Ana con sus 5 variables de email');
select pg_temp.chk((select email_campanas_recibidas is null and email_pct_clic is null and email_clics_90d is null
                      from mk where cliente_ref = 'c1000000-0000-4000-8000-00000000000f'), 'clúster: cliente sin campanas -> sin dato (NULL), no ceros');
select pg_temp.chk((select email_pct_clic = 0 and email_dias_desde_ultimo_clic is null from mk where cliente_ref = 'c1000000-0000-4000-8000-00000000000c'), 'clúster: Caro 0 % y sin ultimo clic');
select pg_temp.chk((select gasto_total = 20000 and num_pedidos = 1 from mk where cliente_ref = 'c1000000-0000-4000-8000-00000000000b'), 'clúster: columnas de EM2 intactas');
select pg_temp.chk(not exists (select 1 from information_schema.routines r join information_schema.parameters p on p.specific_name = r.specific_name
                                where r.routine_name = 'mk_perfiles_clientes' and p.parameter_mode = 'OUT' and p.parameter_name ~ 'correo|nombre|telefono|email$'),
                   'clúster: el perfil sigue sin correo, nombre ni telefono');

do $$ declare n int; begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"7e551000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  select count(*) into n from mk_perfiles_clientes();
  reset role;
  perform pg_temp.chk(false, 'solo Email marketing (sin Marketing) no lee perfiles del clúster');
exception when others then reset role;
  perform pg_temp.chk(sqlerrm like 'MK_SIN_ACCESO%', 'solo Email marketing (sin Marketing) no lee perfiles del clúster');
end $$;
do $$ declare n int; begin
  set local role anon;
  select count(*) into n from mk_perfiles_clientes();
  reset role;
  perform pg_temp.chk(false, 'anon no ejecuta mk_perfiles_clientes');
exception when insufficient_privilege then reset role; perform pg_temp.chk(true, 'anon no ejecuta mk_perfiles_clientes');
end $$;
do $$ begin
  set local role authenticated;
  perform em__perfil_email();
  reset role;
  perform pg_temp.chk(false, 'nadie del panel llama em__perfil_email directo');
exception when insufficient_privilege then reset role; perform pg_temp.chk(true, 'nadie del panel llama em__perfil_email directo');
end $$;

select case when ok then 'pasa' else 'FALLA' end || ' | ' || que from pg_temp.r order by n;
select 'RESUMEN | ' || count(*) || ' comprobaciones · ' || count(*) filter (where not ok) || ' fallan' from pg_temp.r;
rollback;
