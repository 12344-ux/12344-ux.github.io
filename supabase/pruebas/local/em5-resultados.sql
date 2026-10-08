-- ============================================================
-- Impulse · Pruebas de EM5 (resultados de email marketing)
-- SOLO LOCAL: siembra datos ficticios. Correr despues de correr-local.sh:
--   psql -d impulse_pruebas -f supabase/pruebas/local/em5-resultados.sql
-- Imprime una fila por comprobacion: "pasa | ..." o "FALLA | ...".
-- ============================================================
\set ON_ERROR_STOP 1
set client_min_messages = warning;

drop table if exists pg_temp.r;
create temp table r (n serial, ok boolean, que text);
grant insert, select on pg_temp.r to service_role, authenticated, anon;
grant usage on sequence pg_temp.r_n_seq to service_role, authenticated, anon;

create or replace function pg_temp.chk(p boolean, q text) returns void language sql as
$$ insert into pg_temp.r (ok, que) values (coalesce(p, false), q) $$;

begin;  -- todo se deshace al final (rollback)

-- ---------------- Semilla ----------------
insert into auth.users (id, email) values
  ('7e550000-0000-4000-8000-000000000001', 'em5-sin@local.invalid'),
  ('7e550000-0000-4000-8000-000000000002', 'em5-em@local.invalid')
on conflict do nothing;
insert into perfiles (id, rol, modulos) values
  ('7e550000-0000-4000-8000-000000000001', 'prueba', '{ventas}'),
  ('7e550000-0000-4000-8000-000000000002', 'prueba', '{email_marketing}')
on conflict (id) do nothing;

insert into clientes (id, nombre, correo, correo_norm) values
  ('c0000000-0000-4000-8000-000000000001', 'Ana Uno',   'ana@x.invalid',   'ana@x.invalid'),
  ('c0000000-0000-4000-8000-000000000002', 'Beto Dos',  'beto@x.invalid',  'beto@x.invalid'),
  ('c0000000-0000-4000-8000-000000000003', 'Caro Tres', 'caro@x.invalid',  'caro@x.invalid');

insert into em_contactos (id, correo, correo_norm, customer_id, nombre, estado, fuente, consentimiento_en, consentimiento_texto, politica_version, evidencia) values
  ('a0000000-0000-4000-8000-000000000001', 'ana@x.invalid',  'ana@x.invalid',  'c0000000-0000-4000-8000-000000000001', 'Ana',  'suscrito', 'manual', now(), 't', '1.0', '{}'),
  ('a0000000-0000-4000-8000-000000000002', 'Beto@X.invalid', 'beto@x.invalid', 'c0000000-0000-4000-8000-000000000002', 'Beto', 'suscrito', 'manual', now(), 't', '1.0', '{}'),
  ('a0000000-0000-4000-8000-000000000003', 'caro@x.invalid', 'caro@x.invalid', 'c0000000-0000-4000-8000-000000000003', 'Caro', 'suscrito', 'manual', now(), 't', '1.0', '{}'),
  ('a0000000-0000-4000-8000-000000000004', 'dani@x.invalid', 'dani@x.invalid', null,                                  'Dani', 'suscrito', 'manual', now(), 't', '1.0', '{}'),
  ('a0000000-0000-4000-8000-000000000005', 'eli@x.invalid',  'eli@x.invalid',  null,                                  'Eli',  'suscrito', 'manual', now(), 't', '1.0', '{}');

-- Dos campanas enviadas: C1 hace 10 dias, C2 hace 3 dias.
insert into em_campanas (id, nombre_interno, asunto, estado, utm_campaign, resend_broadcast_id, enviada_en, audiencia_n) values
  ('b0000000-0000-4000-8000-000000000001', 'C1', 'Asunto 1', 'enviada', 'c1-test', 'bc-1', now() - interval '10 days', 4),
  ('b0000000-0000-4000-8000-000000000002', 'C2', 'Asunto 2', 'enviada', 'c2-test', 'bc-2', now() - interval '3 days', 3),
  ('b0000000-0000-4000-8000-000000000003', 'C3 borrador', 'x', 'borrador', 'c3-test', null, null, null);
insert into em_campana_destinatarios (campana_id, contacto_id, correo, nombre, customer_id, estado) values
  ('b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'ana@x.invalid',  'Ana',  'c0000000-0000-4000-8000-000000000001', 'listo'),
  ('b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000002', 'Beto@X.invalid', 'Beto', 'c0000000-0000-4000-8000-000000000002', 'listo'),
  ('b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000003', 'caro@x.invalid', 'Caro', 'c0000000-0000-4000-8000-000000000003', 'listo'),
  ('b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000004', 'dani@x.invalid', 'Dani', null, 'listo'),
  ('b0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000001', 'ana@x.invalid',  'Ana',  'c0000000-0000-4000-8000-000000000001', 'listo'),
  ('b0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000003', 'caro@x.invalid', 'Caro', 'c0000000-0000-4000-8000-000000000003', 'listo'),
  ('b0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000005', 'eli@x.invalid',  'Eli',  null, 'listo');

-- Correo del pedido (updates) ya enviado a Eli? No: a Caro, con proveedor_id.
insert into pedidos (id, customer_id, fecha_orden, total, creado) values
  ('d0000000-0000-4000-8000-000000000009', 'c0000000-0000-4000-8000-000000000003', current_date - 20, 1, now() - interval '20 days');
insert into correo_envios (id, pedido_id, etapa, destinatario, estado, proveedor_id) values
  ('e0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000009', 'recibido', 'caro@x.invalid', 'enviado', 'em-pedido-1'),
  ('e0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000009', 'preparando', 'caro@x.invalid', 'enviado', 'em-pedido-2');

-- ---------------- Llamadas como service_role ----------------
create or replace function pg_temp.ev(p_id text, p_type text, p_data jsonb, p_cuando timestamptz default now())
returns jsonb language plpgsql as $$
declare v jsonb;
begin
  execute 'set local role service_role';
  v := em_webhook_registrar(p_id, jsonb_build_object('type', p_type, 'created_at', p_cuando, 'data', p_data));
  execute 'reset role';
  return v;
end $$;

-- 1. Entregas de C1 (4) y repetido
select pg_temp.chk(pg_temp.ev('msg_c1_ana_del', 'email.delivered', '{"broadcast_id":"bc-1","email_id":"r1","to":["ana@x.invalid"]}')->>'estado' = 'procesado', 'entregado procesado');
select pg_temp.chk(pg_temp.ev('msg_c1_ana_del', 'email.delivered', '{"broadcast_id":"bc-1","email_id":"r1","to":["ana@x.invalid"]}')->>'estado' = 'repetido', 'mismo svix-id = repetido (idempotencia)');
select pg_temp.ev('msg_c1_beto_del', 'email.delivered', '{"broadcast_id":"bc-1","email_id":"r2","to":["beto@x.invalid"]}');
select pg_temp.ev('msg_c1_caro_del', 'email.delivered', '{"broadcast_id":"bc-1","email_id":"r3","to":["caro@x.invalid"]}');
select pg_temp.chk((select contacto_id from em_eventos where svix_id = 'msg_c1_beto_del') = 'a0000000-0000-4000-8000-000000000002', 'correo con mayusculas en destinatarios se enlaza al contacto');
select pg_temp.chk((select count(*) from em_eventos where svix_id = 'msg_c1_ana_del') = 1, 'una sola fila por svix-id');

-- 2. Rebote temporal (Dani) no suprime; permanente si.
select pg_temp.ev('msg_c1_dani_tmp', 'email.bounced', '{"broadcast_id":"bc-1","to":["dani@x.invalid"],"bounce":{"type":"Temporary","subType":"MailboxFull","message":"full"}}');
select pg_temp.chk((select estado from em_contactos where id = 'a0000000-0000-4000-8000-000000000004') = 'suscrito', 'rebote temporal NO suprime');
select pg_temp.chk((pg_temp.ev('msg_c1_dani_perm', 'email.bounced', '{"broadcast_id":"bc-1","to":["dani@x.invalid"],"bounce":{"type":"Permanent","subType":"General","message":"no existe"}}')->>'suprimio')::boolean, 'rebote permanente suprime');
select pg_temp.chk((select estado from em_contactos where id = 'a0000000-0000-4000-8000-000000000004') = 'rebotado', 'contacto queda rebotado');
select pg_temp.chk(exists (select 1 from em_consentimiento_bitacora where contacto_id = 'a0000000-0000-4000-8000-000000000004' and accion = 'rebote' and actor is null), 'bitacora de rebote con actor automatico');

-- 3. Clics (Ana 2 clics, Beto 1) y apertura
select pg_temp.ev('msg_c1_ana_clk1', 'email.clicked', jsonb_build_object('broadcast_id','bc-1','to',jsonb_build_array('ana@x.invalid'),'click',jsonb_build_object('link','https://magandhi.com/producto/?slug=grisi&utm_source=email&utm_medium=email&utm_campaign=c1-test','timestamp',(now() - interval '9 days')::text,'ipAddress','1.2.3.4','userAgent','UA')));
select pg_temp.ev('msg_c1_ana_clk2', 'email.clicked', jsonb_build_object('broadcast_id','bc-1','to',jsonb_build_array('ana@x.invalid'),'click',jsonb_build_object('link','https://magandhi.com/producto/?slug=grisi&utm_source=email&utm_medium=email&utm_campaign=c1-test','timestamp',(now() - interval '9 days')::text)));
select pg_temp.ev('msg_c1_beto_clk', 'email.clicked', jsonb_build_object('broadcast_id','bc-1','to',jsonb_build_array('beto@x.invalid'),'click',jsonb_build_object('link','https://magandhi.com/?utm_source=email&utm_medium=email&utm_campaign=c1-test','timestamp',(now() - interval '9 days')::text)));
select pg_temp.ev('msg_c1_ana_open', 'email.opened', '{"broadcast_id":"bc-1","to":["ana@x.invalid"]}');
select pg_temp.chk(not exists (select 1 from em_eventos where detalle::text ~ '1\.2\.3\.4|UA'), 'no se guarda IP ni navegador del clic');
select pg_temp.chk((select cuando::date from em_eventos where svix_id = 'msg_c1_ana_clk1') = (now() - interval '9 days')::date, 'momento del clic = timestamp del clic');

-- 4. Clic en C2 de Ana (hace 2 dias) -> su pedido de hoy va a C2 (ultimo clic)
select pg_temp.ev('msg_c2_ana_clk', 'email.clicked', jsonb_build_object('broadcast_id','bc-2','to',jsonb_build_array('ana@x.invalid'),'click',jsonb_build_object('link','https://magandhi.com/?utm_campaign=c2-test','timestamp',(now() - interval '2 days')::text)));
select pg_temp.ev('msg_c2_caro_clk', 'email.clicked', jsonb_build_object('broadcast_id','bc-2','to',jsonb_build_array('caro@x.invalid'),'click',jsonb_build_object('link','https://magandhi.com/','timestamp',(now() - interval '2 days')::text)));

-- Pedidos:
--  P1 Ana hoy                  -> C2 (ultimo clic, dentro de 7 dias)
--  P2 Beto hace 1 dia           -> fuera: su clic fue hace 9 dias (> 7)
--  P3 Beto hace 8 dias          -> C1 (clic hace 9 dias, dentro de 7)
--  P4 Ana hace 9.5 dias (antes del clic) -> no cuenta
--  P5 Caro hoy ANULADO          -> no cuenta
--  P6 Caro web con utm c1-test  -> exacta para C1 (aunque clico C2)
insert into pedidos (id, customer_id, fecha_orden, total, creado, anulado, canal, utm_campaign) values
  ('d0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000001', current_date,     30000, now(),                        false, 'manual', null),
  ('d0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000002', current_date - 1, 11000, now() - interval '1 day',    false, 'manual', null),
  ('d0000000-0000-4000-8000-000000000003', 'c0000000-0000-4000-8000-000000000002', (now() - interval '8 days')::date, 22000, now() - interval '8 days', false, 'manual', null),
  ('d0000000-0000-4000-8000-000000000004', 'c0000000-0000-4000-8000-000000000001', (now() - interval '9 days 12 hours')::date, 5000, now() - interval '9 days 12 hours', false, 'manual', null),
  ('d0000000-0000-4000-8000-000000000005', 'c0000000-0000-4000-8000-000000000003', current_date,     9000,  now(),                        true,  'manual', null),
  ('d0000000-0000-4000-8000-000000000006', 'c0000000-0000-4000-8000-000000000003', current_date,     40000, now(),                        false, 'web',    'c1-test');

select pg_temp.chk((select campana_id from em__atribucion_aproximada() where pedido_id = 'd0000000-0000-4000-8000-000000000001') = 'b0000000-0000-4000-8000-000000000002', 'P1: ultimo clic gana (C2)');
select pg_temp.chk(not exists (select 1 from em__atribucion_aproximada() where pedido_id = 'd0000000-0000-4000-8000-000000000002'), 'P2: fuera de 7 dias no cuenta');
select pg_temp.chk((select campana_id from em__atribucion_aproximada() where pedido_id = 'd0000000-0000-4000-8000-000000000003') = 'b0000000-0000-4000-8000-000000000001', 'P3: dentro de 7 dias cuenta (C1)');
select pg_temp.chk(not exists (select 1 from em__atribucion_aproximada() where pedido_id = 'd0000000-0000-4000-8000-000000000004'), 'P4: pedido anterior al clic no cuenta');
select pg_temp.chk(not exists (select 1 from em__atribucion_aproximada() where pedido_id = 'd0000000-0000-4000-8000-000000000005'), 'P5: anulado no cuenta');
select pg_temp.chk(not exists (select 1 from em__atribucion_aproximada() where pedido_id = 'd0000000-0000-4000-8000-000000000006'), 'P6: con utm no se duplica como aproximada');
select pg_temp.chk((select count(*) from em__atribucion_aproximada() group by pedido_id order by 1 desc limit 1) = 1, 'ningun pedido se atribuye a dos campanas');

-- 5. Baja por contact.updated (Ana) -> a la ultima campana recibida antes (C2)
select pg_temp.chk(pg_temp.ev('msg_ct_ana_upd0', 'contact.updated', '{"id":"rc","email":"ana@x.invalid","unsubscribed":false}')->>'estado' = 'ignorado', 'contact.updated sin baja se ignora');
select pg_temp.ev('msg_ct_ana_unsub', 'contact.updated', '{"id":"rc","email":"ANA@x.invalid","unsubscribed":true}');
select pg_temp.chk((select estado from em_contactos where id = 'a0000000-0000-4000-8000-000000000001') = 'baja', 'baja desde Resend aplicada');
select pg_temp.chk((select campana_id from em__bajas_por_campana() where contacto_id = 'a0000000-0000-4000-8000-000000000001') = 'b0000000-0000-4000-8000-000000000002', 'baja atribuida a la ultima campana recibida (C2)');
-- un "unsubscribed:false" posterior NO resuscribe
select pg_temp.ev('msg_ct_ana_upd1', 'contact.updated', '{"id":"rc","email":"ana@x.invalid","unsubscribed":false}');
select pg_temp.chk((select estado from em_contactos where id = 'a0000000-0000-4000-8000-000000000001') = 'baja', 'webhook NUNCA vuelve a suscrito');

-- 6. Queja (Caro en C2) > rebotado; despues un rebote no la "mejora"
select pg_temp.ev('msg_c2_caro_spam', 'email.complained', '{"broadcast_id":"bc-2","to":["caro@x.invalid"]}');
select pg_temp.chk((select estado from em_contactos where id = 'a0000000-0000-4000-8000-000000000003') = 'queja', 'queja suprime como queja');
select pg_temp.ev('msg_c2_caro_bnc', 'email.bounced', '{"broadcast_id":"bc-2","to":["caro@x.invalid"],"bounce":{"type":"Permanent"}}');
select pg_temp.chk((select estado from em_contactos where id = 'a0000000-0000-4000-8000-000000000003') = 'queja', 'estados solo empeoran (queja no pasa a rebotado)');

-- 7. Correo del pedido: entregado y rebote permanente -> marketing rebotado (decision 3)
select pg_temp.chk(pg_temp.ev('msg_ped_1_del', 'email.delivered', '{"email_id":"em-pedido-1","to":["caro@x.invalid"],"tags":{"tipo":"pedido","etapa":"recibido"}}')->>'origen' = 'pedido', 'evento de updates se reconoce por email_id');
select pg_temp.chk((select entregado_en is not null from correo_envios where id = 'e0000000-0000-4000-8000-000000000001'), 'correo del pedido marcado entregado');
-- Eli recibe un correo de pedido (sin pedido en correo_envios aqui: usamos em-pedido-2 de Caro para el rebote)
select pg_temp.ev('msg_ped_2_bnc', 'email.bounced', '{"email_id":"em-pedido-2","to":["caro@x.invalid"],"tags":{"tipo":"pedido"},"bounce":{"type":"Permanent"}}');
select pg_temp.chk((select rebote_tipo from correo_envios where id = 'e0000000-0000-4000-8000-000000000002') = 'permanente', 'correo del pedido: rebote permanente registrado');

-- 8. email.suppressed (Eli, C2) -> rebotado "suprimida por Resend" (decision 4)
select pg_temp.ev('msg_c2_eli_sup', 'email.suppressed', '{"broadcast_id":"bc-2","to":["eli@x.invalid"],"suppressed":{"type":"OnAccountSuppressionList","message":"m"}}');
select pg_temp.chk((select estado from em_contactos where id = 'a0000000-0000-4000-8000-000000000005') = 'rebotado', 'suprimida por Resend -> rebotado');
select pg_temp.chk((select detalle->>'motivo' from em_consentimiento_bitacora where contacto_id = 'a0000000-0000-4000-8000-000000000005' and accion = 'rebote') = 'Suprimida por Resend', 'motivo de supresion en la bitacora');

-- 9. Pruebas y eventos ajenos se ignoran; datos rotos no tumban
select pg_temp.chk(pg_temp.ev('msg_prueba_1', 'email.delivered', '{"email_id":"zz","to":["admin@local.invalid"],"tags":{"tipo":"prueba_campana"}}')->>'motivo' = 'prueba', 'envio de prueba ignorado');
select pg_temp.chk(pg_temp.ev('msg_desconocido', 'email.delivered', '{"broadcast_id":"otro","to":["nadie@x.invalid"]}')->>'motivo' = 'sin_relacion', 'evento sin campana ni contacto ignorado');
select pg_temp.chk(pg_temp.ev('msg_dominio', 'domain.updated', '{"id":"d"}')->>'estado' = 'ignorado', 'tipo de evento no usado ignorado');
select pg_temp.chk(pg_temp.ev('msg_fecha_rota', 'email.opened', '{"broadcast_id":"bc-2","to":["eli@x.invalid"]}', null)->>'estado' = 'procesado', 'created_at ausente no tumba el registro');
do $$ begin
  perform pg_temp.ev('x', 'email.delivered', '{}');
  perform pg_temp.chk(false, 'svix-id invalido rechazado');
exception when others then
  reset role;
  perform pg_temp.chk(sqlerrm like 'EM_WEBHOOK_ID_INVALIDO%', 'svix-id invalido rechazado');
end $$;

-- 10. Resultados de C1
set local role authenticated;
set local request.jwt.claims to '{"sub":"89e5028d-8c17-4deb-89c3-59acbd0ee2f2","role":"authenticated"}';
create temp table res1 as select em_campana_resultados('b0000000-0000-4000-8000-000000000001') as v;
reset role;
select pg_temp.chk((select (v->>'entregados')::int from res1) = 3, 'C1: 3 entregados');
select pg_temp.chk((select (v->>'rebotes')::int from res1) = 1, 'C1: 1 rebote permanente');
select pg_temp.chk((select (v->>'rebotes_temporales')::int from res1) = 0, 'C1: el temporal que luego fue permanente no se cuenta doble');
select pg_temp.chk((select (v->>'clics_personas')::int from res1) = 2 and (select (v->>'clics_total')::int from res1) = 3, 'C1: 2 personas, 3 clics');
select pg_temp.chk((select (v->>'aperturas')::int from res1) = 1, 'C1: 1 apertura');
select pg_temp.chk((select v->'enlaces'->0->>'enlace' from res1) = 'https://magandhi.com/producto/?slug=grisi', 'C1: enlace mas clicado sin parametros utm');
select pg_temp.chk((select (v->'ventas'->>'exactas_n')::int = 1 and (v->'ventas'->>'exactas_valor')::int = 40000 from res1), 'C1: 1 venta exacta por 40.000');
select pg_temp.chk((select (v->'ventas'->>'aprox_n')::int = 1 and (v->'ventas'->>'aprox_valor')::int = 22000 from res1), 'C1: 1 venta aproximada por 22.000');
select pg_temp.chk((select (v->>'bajas')::int from res1) = 0, 'C1: la baja de Ana no se cuenta aqui');

set local role authenticated;
set local request.jwt.claims to '{"sub":"89e5028d-8c17-4deb-89c3-59acbd0ee2f2","role":"authenticated"}';
create temp table res2 as select em_campana_resultados('b0000000-0000-4000-8000-000000000002') as v, em_campanas_resultados_lista() as l, em_salud_lista() as s,
                                 em_contacto_campanas('a0000000-0000-4000-8000-000000000001') as cc;
reset role;
select pg_temp.chk((select (v->>'bajas')::int = 1 and (v->>'quejas')::int = 1 and (v->>'suprimidos')::int = 1 from res2), 'C2: 1 baja, 1 queja, 1 suprimido');
select pg_temp.chk((select (v->'ventas'->>'aprox_n')::int = 1 and (v->'ventas'->>'aprox_valor')::int = 30000 from res2), 'C2: venta aproximada de Ana (30.000)');
select pg_temp.chk((select (l->'b0000000-0000-4000-8000-000000000001'->>'pedidos')::int = 2 from res2), 'lista: C1 con 2 pedidos (exacta + aproximada)');
select pg_temp.chk((select not (l ? 'b0000000-0000-4000-8000-000000000003') from res2), 'lista: el borrador no tiene resultados');
select pg_temp.chk((select (s->>'rebotes')::int >= 2 and (s->>'quejas')::int = 1 and (s->>'limite_rebote')::int = 4 from res2), 'salud de la lista con rebotes, quejas y limites');
select pg_temp.chk((select jsonb_array_length(cc) = 2 from res2), 'ficha: Ana recibio 2 campanas');

-- 11. Permisos
do $$ begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"89e5028d-8c17-4deb-89c3-59acbd0ee2f2","role":"authenticated"}', true);
  perform em_webhook_registrar('msg_admin_intento', '{"type":"email.delivered","data":{}}');
  reset role;
  perform pg_temp.chk(false, 'authenticated (incluso admin) NO puede escribir eventos');
exception when insufficient_privilege then
  reset role;
  perform pg_temp.chk(true, 'authenticated (incluso admin) NO puede escribir eventos');
end $$;
do $$ begin
  set local role anon;
  perform em_webhook_registrar('msg_anon_intento', '{"type":"email.delivered","data":{}}');
  reset role;
  perform pg_temp.chk(false, 'anon NO puede escribir eventos');
exception when insufficient_privilege then
  reset role;
  perform pg_temp.chk(true, 'anon NO puede escribir eventos');
end $$;
do $$ declare n int; begin
  set local role anon;
  select count(*) into n from em_eventos;
  reset role;
  perform pg_temp.chk(false, 'anon NO lee em_eventos');
exception when insufficient_privilege then
  reset role;
  perform pg_temp.chk(true, 'anon NO lee em_eventos');
end $$;
do $$ declare n int; begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"7e550000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  select count(*) into n from em_eventos;
  reset role;
  perform pg_temp.chk(n = 0, 'usuario solo de Ventas no ve eventos (RLS)');
end $$;
do $$ begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"7e550000-0000-4000-8000-000000000001","role":"authenticated"}', true);
  perform em_campana_resultados('b0000000-0000-4000-8000-000000000001');
  reset role;
  perform pg_temp.chk(false, 'usuario sin modulo: resultados rechazados');
exception when others then
  reset role;
  perform pg_temp.chk(sqlerrm like 'EM_SIN_ACCESO%', 'usuario sin modulo: resultados rechazados');
end $$;
do $$ declare n int; begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"7e550000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  select count(*) into n from em_eventos;
  reset role;
  perform pg_temp.chk(n > 0, 'usuario con modulo email_marketing ve eventos');
end $$;
do $$ declare n int; begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"7e550000-0000-4000-8000-000000000002","role":"authenticated"}', true);
  insert into em_eventos (svix_id, evento, tipo, origen, cuando) values ('msg_directo', 'x', 'clic', 'campana', now());
  reset role;
  perform pg_temp.chk(false, 'nadie inserta eventos directo en la tabla');
exception when insufficient_privilege then
  reset role;
  perform pg_temp.chk(true, 'nadie inserta eventos directo en la tabla');
end $$;

-- 12. Seguimiento: columna de entrega
set local role authenticated;
set local request.jwt.claims to '{"sub":"89e5028d-8c17-4deb-89c3-59acbd0ee2f2","role":"authenticated"}';
create temp table seg as select * from em_correos_seguimiento(null, null, 'caro', 50);
reset role;
select pg_temp.chk((select entrega from seg where id = 'e0000000-0000-4000-8000-000000000001') = 'entregado'
               and (select entrega from seg where id = 'e0000000-0000-4000-8000-000000000002') = 'rebote', 'seguimiento muestra entregado / rebote');

-- 13. Retencion: eventos de hace 14 meses se borran, los totales quedan
insert into em_eventos (svix_id, evento, tipo, origen, campana_id, contacto_id, cuando)
values ('msg_viejo_1', 'email.delivered', 'entregado', 'campana', 'b0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000002', now() - interval '14 months'),
       ('msg_viejo_2', 'email.clicked', 'clic', 'campana', 'b0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000002', now() - interval '14 months');
select pg_temp.chk(em__depurar_eventos() = 2, 'retencion: 2 eventos viejos borrados');
select pg_temp.chk((select (resultados->>'entregados')::int = 1 and (resultados->>'clics_personas')::int = 1 and (resultados->>'archivado')::boolean
                      from em_campana_resultados_archivo where campana_id = 'b0000000-0000-4000-8000-000000000003'), 'retencion: totales congelados en el archivo');
select pg_temp.chk((select count(*) from em_eventos where campana_id = 'b0000000-0000-4000-8000-000000000001') > 0, 'retencion: eventos recientes intactos');
select pg_temp.chk(em__depurar_eventos() = 0, 'retencion: segunda pasada no hace nada');

-- 14. Formato de utm en pedidos
do $$ begin
  update pedidos set utm_campaign = 'Mal Formato!' where id = 'd0000000-0000-4000-8000-000000000001';
  perform pg_temp.chk(false, 'utm_campaign con formato invalido rechazado');
exception when check_violation then
  perform pg_temp.chk(true, 'utm_campaign con formato invalido rechazado');
end $$;

select case when ok then 'pasa' else 'FALLA' end || ' | ' || que from pg_temp.r order by n;
select 'RESUMEN | ' || count(*) || ' comprobaciones · ' || count(*) filter (where not ok) || ' fallan' from pg_temp.r;
rollback;
