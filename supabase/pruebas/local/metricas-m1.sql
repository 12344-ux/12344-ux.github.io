-- ============================================================
-- Impulse · Pruebas de Metricas M1 (captura web + capa de datos)
-- SOLO LOCAL; todo se deshace al final.
-- ============================================================
\set ON_ERROR_STOP 1
set client_min_messages = warning;
drop table if exists pg_temp.r;
create temp table r (n serial, ok boolean, que text);
create or replace function pg_temp.chk(p boolean, q text) returns void language sql as
$$ insert into pg_temp.r (ok, que) values (coalesce(p, false), q) $$;
create or replace function pg_temp.reg(v text, s text, e jsonb, ip text) returns jsonb language plpgsql as $$
declare x jsonb; begin execute 'set local role service_role'; x := mt_registrar_eventos(v, s, e, ip); execute 'reset role'; return x; end $$;
create or replace function pg_temp.err(q text) returns text language plpgsql as $$
begin execute q; return 'SIN ERROR'; exception when others then execute 'reset role'; return sqlerrm; end $$;
grant execute on function pg_temp.err(text) to authenticated, service_role;
create or replace function pg_temp.como(uid text, q text) returns jsonb language plpgsql as $$
declare x jsonb; begin execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute q into x; execute 'reset role'; return x; end $$;

begin;
insert into auth.users (id, email) values
  ('7e570000-0000-4000-8000-0000000000a1', 'mt-met@local.invalid'), ('7e570000-0000-4000-8000-0000000000a2', 'mt-ven@local.invalid'),
  ('7e570000-0000-4000-8000-0000000000a3', 'mt-fin@local.invalid') on conflict do nothing;
insert into perfiles (id, rol, modulos) values
  ('7e570000-0000-4000-8000-0000000000a1', 'prueba', '{metricas}'), ('7e570000-0000-4000-8000-0000000000a2', 'prueba', '{ventas}'),
  ('7e570000-0000-4000-8000-0000000000a3', 'prueba', '{finanzas}') on conflict (id) do nothing;

-- 1. Apagada
select pg_temp.chk(pg_temp.err($q$select pg_temp.reg('vis-aaaaaaaaaaaaaaaa', 'ses-aaaaaaaa', '[{"tipo":"pagina_vista","ruta":"/"}]', 'ip')$q$) like 'MT_ANALITICA_APAGADA%', 'apagada: no registra nada');
select pg_temp.chk((select (mt_publico_config()->>'activa')::boolean) = false, 'config publica: apagada');
select pg_temp.chk(pg_temp.como('89e5028d-8c17-4deb-89c3-59acbd0ee2f2', $q$select to_jsonb(pg_temp.err('select mt_config_analitica(true)'))$q$)::text like '%MT_POLITICA_PENDIENTE%', 'no se enciende sin politica');
update em_config set politica_publicada = true, politica_url = 'https://magandhi.com/politicas/datos/', politica_version = 'borrador-0' where id;
select pg_temp.chk((pg_temp.como('89e5028d-8c17-4deb-89c3-59acbd0ee2f2', 'select mt_config_analitica(true)')->>'analitica_activa')::boolean, 'admin la enciende con la politica registrada');
select pg_temp.chk(pg_temp.como('7e570000-0000-4000-8000-0000000000a1', $q$select to_jsonb(pg_temp.err('select mt_config_analitica(false)'))$q$)::text like '%MT_SIN_ACCESO%', 'quien no es admin no la apaga ni enciende');

-- 2. Registro y validaciones
select pg_temp.chk((pg_temp.reg('vis-aaaaaaaaaaaaaaaa', 'ses-aaaaaaaa', '[{"tipo":"pagina_vista","ruta":"/","origen":"instagram","entrada":true,"dispositivo":"movil"},
   {"tipo":"producto_visto","ruta":"/producto/","slug":"grisi","dispositivo":"movil"},{"tipo":"inventado"},{"tipo":"pagina_vista","ruta":"sin-barra"},
   {"tipo":"pagina_vista","ruta":"/","origen":"https://referer-completo.com/x"},{"tipo":"clic_comprar","slug":"Grisi; drop"}]', 'ipA')->>'aceptados')::int = 2,
   'lote mixto: 2 validos entran, 4 invalidos se descartan sin tumbar el lote');
select pg_temp.chk(not exists (select 1 from tienda_eventos where origen ~ 'http' or ruta !~ '^/'), 'nunca se guarda una URL de procedencia ni rutas raras');
select pg_temp.chk(pg_temp.err($q$select pg_temp.reg('corto', 'ses-aaaaaaaa', '[{"tipo":"pagina_vista","ruta":"/"}]', 'ip')$q$) like 'MT_VISITANTE_INVALIDO%', 'id de visitante mal formado: rechazado');
select pg_temp.chk(pg_temp.err($q$select pg_temp.reg('vis-aaaaaaaaaaaaaaaa', 'ses-aaaaaaaa', (select jsonb_agg('{"tipo":"pagina_vista","ruta":"/"}'::jsonb) from generate_series(1,31)), 'ip')$q$) like 'MT_EVENTOS_INVALIDOS%', 'mas de 30 eventos por lote: rechazado');
select pg_temp.reg('vis-tiempoxxxxxxxxx', 'ses-tiempo', jsonb_build_array(jsonb_build_object('tipo','pagina_vista','ruta','/','cuando',(now() + interval '2 days')::text),
                                                                           jsonb_build_object('tipo','pagina_vista','ruta','/','cuando',(now() - interval '3 days')::text)), 'ipT');
select pg_temp.chk((select bool_and(cuando between now() - interval '1 minute' and now()) from tienda_eventos where visitante = 'vis-tiempoxxxxxxxxx'), 'reloj del navegador falso (futuro o muy atras) -> hora del servidor');
do $$ begin for i in 1..20 loop perform pg_temp.reg('vis-abusoxxxxxxxxxx', 'ses-abuso', (select jsonb_agg('{"tipo":"pagina_vista","ruta":"/"}'::jsonb) from generate_series(1,30)), 'ipAbuso'); end loop; end $$;
select pg_temp.chk(pg_temp.err($q$select pg_temp.reg('vis-abusoxxxxxxxxxx', 'ses-abuso', '[{"tipo":"pagina_vista","ruta":"/"}]', 'ipAbuso')$q$) like 'MT_DEMASIADOS_EVENTOS%', 'mas de 600 eventos por hora desde una IP: rechazado');
delete from tienda_eventos where visitante in ('vis-abusoxxxxxxxxxx', 'vis-tiempoxxxxxxxxx', 'vis-aaaaaaaaaaaaaaaa');

-- 3. Datos para la capa: 3 visitantes hoy, 1 ayer; embudo
insert into tienda_eventos (visitante, sesion, tipo, ruta, slug, origen, entrada, utm_campaign, dispositivo, cuando) values
  ('vis-bbbbbbbbbbbbbbbb','ses-bbbbbbbb','pagina_vista','/',null,'email',true,'c1-test','pc', now() - interval '2 minutes'),
  ('vis-bbbbbbbbbbbbbbbb','ses-bbbbbbbb','producto_visto','/producto/','grisi',null,false,null,'pc', now() - interval '1 minute'),
  ('vis-bbbbbbbbbbbbbbbb','ses-bbbbbbbb','clic_comprar','/producto/','grisi',null,false,null,'pc', now() - interval '50 seconds'),
  ('vis-bbbbbbbbbbbbbbbb','ses-bbbbbbbb','checkout_iniciado','/producto/','grisi',null,false,null,'pc', now() - interval '40 seconds'),
  ('vis-cccccccccccccccc','ses-cccccccc','pagina_vista','/',null,'directo',true,null,'movil', now() - interval '20 minutes'),
  ('vis-dddddddddddddddd','ses-dddddddd','pagina_vista','/politicas/',null,'buscador',true,null,'tablet', now() - interval '1 day 1 hour');
insert into campana_producto (slug, nombre, publicado, activo) select 'grisi', 'Shampoo Grisi Gold', true, true
  where not exists (select 1 from campana_producto where slug = 'grisi');

-- Pedidos de hoy y de hace 7 dias
insert into clientes (id, nombre, correo, correo_norm, ciudad) values ('c7000000-0000-4000-8000-000000000001', 'Mt', 'mt@z.invalid', 'mt@z.invalid', 'Tunja');
insert into pedidos (id, customer_id, fecha_orden, total, creado, ciudad, canal) values
  ('d7000000-0000-4000-8000-000000000001', 'c7000000-0000-4000-8000-000000000001', (now() at time zone 'America/Bogota')::date, 30000, now(), 'tunja', 'manual'),
  ('d7000000-0000-4000-8000-000000000002', 'c7000000-0000-4000-8000-000000000001', (now() at time zone 'America/Bogota')::date, 20000, now(), 'Tunja', 'web'),
  ('d7000000-0000-4000-8000-000000000003', 'c7000000-0000-4000-8000-000000000001', (now() at time zone 'America/Bogota')::date - 7, 10000, now() - interval '7 days', 'Bogotá', 'manual'),
  ('d7000000-0000-4000-8000-000000000004', 'c7000000-0000-4000-8000-000000000001', (now() at time zone 'America/Bogota')::date, 99000, now(), 'Tunja', 'manual');
update pedidos set anulado = true where id = 'd7000000-0000-4000-8000-000000000004';
insert into pedido_items (pedido_id, product_id, cantidad, precio_unitario, subtotal)
select 'd7000000-0000-4000-8000-000000000001', id, 2, 15000, 30000 from productos order by creado limit 1;
insert into pedido_items (pedido_id, product_id, cantidad, precio_unitario, subtotal)
select 'd7000000-0000-4000-8000-000000000002', id, 1, 20000, 20000 from productos order by creado limit 1;

-- 4. En vivo
create temp table ev as select pg_temp.como('7e570000-0000-4000-8000-0000000000a1', 'select mt_en_vivo()') v;
select pg_temp.chk((select (v->>'visitantes_5m')::int = 1 and (v->>'visitantes_30m')::int = 2 from ev), 'en vivo: 1 visitante en 5 min, 2 en 30 min');
select pg_temp.chk((select (v->>'pedidos_hoy')::int = 2 and (v->>'ingresos_hoy')::int = 50000 from ev), 'en vivo: 2 pedidos hoy por 50.000 (el anulado no cuenta)');
select pg_temp.chk((select (v->>'pedidos_mismo_dia_semana_pasada')::int = 1 and (v->>'ingresos_mismo_dia_semana_pasada')::int = 10000 from ev), 'en vivo: comparacion con el mismo dia de la semana pasada');
select pg_temp.chk((select jsonb_array_length(v->'por_hora') = 24 from ev), 'en vivo: 24 horas');
select pg_temp.chk((select v->'eventos'->0->>'tipo' = 'checkout_iniciado' and v->'eventos'->0->>'nombre' = 'Shampoo Grisi Gold' from ev), 'en vivo: ultimo evento con el nombre comercial del producto');
select pg_temp.chk((select not ((v->'eventos')::text ~ 'vis-') from ev), 'en vivo: los eventos no exponen el id del visitante');
select pg_temp.chk((select not ((v->'pedidos')::text ~ 'mt@z|"Mt"') and v->'pedidos'->0 ? 'ref' from ev), 'en vivo: pedidos sin nombre ni correo del cliente');

-- 5. Ventas
create temp table ve as select pg_temp.como('7e570000-0000-4000-8000-0000000000a2', $q$select mt_ventas(((now() at time zone 'America/Bogota')::date - 6), (now() at time zone 'America/Bogota')::date)$q$) v;
select pg_temp.chk((select (v->'totales'->>'pedidos')::int = 2 and (v->'totales'->>'ingresos')::int = 50000 and (v->'totales'->>'ticket')::int = 25000 and (v->'totales'->>'unidades')::int = 3 from ve), 'ventas: pedidos, ingresos, ticket y unidades del periodo');
select pg_temp.chk((select (v->'totales_anterior'->>'ingresos')::int = 10000 from ve), 'ventas: periodo anterior de igual largo');
select pg_temp.chk((select jsonb_array_length(v->'serie') = 7 and jsonb_array_length(v->'serie_anterior') = 7 from ve), 'ventas: serie diaria completa (dias en cero incluidos)');
select pg_temp.chk((select v->'ciudades'->0->>'ciudad' = 'Tunja' and (v->'ciudades'->0->>'pedidos')::int = 2 from ve), 'ventas: ciudades normalizadas (tunja = Tunja)');
select pg_temp.chk((select (v->'por_canal'->'web'->>'pedidos')::int = 1 and (v->>'pct_hora_exacta')::int = 50 from ve), 'ventas: por canal y % con hora exacta');
select pg_temp.chk((select (v->'productos'->0->>'unidades')::int = 3 from ve), 'ventas: productos que mas venden');
select pg_temp.chk((select jsonb_array_length(v->'calor') >= 1 from ve), 'ventas: mapa de calor dia x hora');
select pg_temp.chk(pg_temp.err($q$select pg_temp.como('7e570000-0000-4000-8000-0000000000a1', 'select mt_ventas(''2026-02-01'', ''2026-01-01'')')$q$) like 'MT_PERIODO_INVALIDO%', 'periodo invertido: rechazado');

-- 6. Tienda
create temp table ti as select pg_temp.como('7e570000-0000-4000-8000-0000000000a1', $q$select mt_tienda(((now() at time zone 'America/Bogota')::date - 6), (now() at time zone 'America/Bogota')::date)$q$) v;
select pg_temp.chk((select (v->'totales'->>'visitantes')::int = 3 and (v->'totales'->>'sesiones')::int = 3 from ti), 'tienda: 3 visitantes y 3 sesiones (incluye el de ayer)');
select pg_temp.chk((select (v->'embudo'->>'vieron_producto')::int = 1 and (v->'embudo'->>'visitantes')::int = 3 and (v->'embudo'->>'clic_comprar')::int = 1 and (v->'embudo'->>'checkout')::int = 1 and (v->'embudo'->>'compra')::int = 0 from ti), 'tienda: embudo por visitante');
select pg_temp.chk((select v->'productos'->0->>'nombre' = 'Shampoo Grisi Gold' and (v->'productos'->0->>'clic_comprar')::int = 1 from ti), 'tienda: productos mas vistos con su nombre');
select pg_temp.chk((select exists (select 1 from jsonb_array_elements(v->'origenes') x where x->>'origen' = 'email') and exists (select 1 from jsonb_array_elements(v->'origenes') x where x->>'origen' = 'buscador') from ti), 'tienda: origenes por sesion');
select pg_temp.chk((select (select count(*) from jsonb_array_elements(v->'dispositivos')) = 3 from ti), 'tienda: celular, tablet y computador');
select pg_temp.chk((select v->'campanas'->0->>'utm' = 'c1-test' from ti), 'tienda: visitas que traen las campanas');
select pg_temp.chk((select jsonb_array_length(v->'serie') = 7 from ti), 'tienda: serie diaria');

-- 7. Permisos y privacidad
select pg_temp.chk(pg_temp.err($q$select pg_temp.como('7e570000-0000-4000-8000-0000000000a3', 'select mt_en_vivo()')$q$) like 'MT_SIN_ACCESO%', 'solo Finanzas: sin acceso a la capa');
select pg_temp.chk(pg_temp.como('7e570000-0000-4000-8000-0000000000a2', 'select mt_en_vivo()') ? 'visitantes_5m', 'Ventas consume la capa compartida');
select pg_temp.chk(pg_temp.err($q$do $d$ declare n int; begin set local role authenticated; perform set_config('request.jwt.claims','{"sub":"89e5028d-8c17-4deb-89c3-59acbd0ee2f2","role":"authenticated"}',true); select count(*) into n from tienda_eventos; end $d$$q$) like 'permission denied%', 'ni el admin lee los eventos crudos (solo agregados)');
select pg_temp.chk(pg_temp.err($q$do $d$ declare n int; begin set local role anon; select count(*) into n from tienda_eventos; end $d$$q$) like 'permission denied%', 'anon no lee eventos');
select pg_temp.chk(not has_function_privilege('anon', 'mt_registrar_eventos(text,text,jsonb,text)', 'execute') and not has_function_privilege('authenticated', 'mt_registrar_eventos(text,text,jsonb,text)', 'execute'), 'registrar: solo service_role');
select pg_temp.chk(not exists (select 1 from information_schema.columns where table_name = 'tienda_eventos' and column_name ~ '^(ip|ip_hash|referer|referrer|user_agent|navegador|correo|email)$'), 'la tabla no tiene columnas de IP, referer, navegador ni correo');

-- 8. Retencion
insert into tienda_eventos (visitante, sesion, tipo, ruta, cuando) values ('vis-viejoxxxxxxxxxx', 'ses-viejo', 'pagina_vista', '/', now() - interval '14 months');
delete from tienda_eventos where cuando < now() - interval '13 months';
select pg_temp.chk(not exists (select 1 from tienda_eventos where visitante = 'vis-viejoxxxxxxxxxx'), 'retencion de 13 meses');

select case when ok then 'pasa' else 'FALLA' end || ' | ' || que from pg_temp.r order by n;
select 'RESUMEN | ' || count(*) || ' comprobaciones · ' || count(*) filter (where not ok) || ' fallan' from pg_temp.r;
rollback;
