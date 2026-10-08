-- ============================================================
-- Impulse · Pruebas de EM6 (captura publica + doble confirmacion)
-- SOLO LOCAL; todo se deshace al final.
-- ============================================================
\set ON_ERROR_STOP 1
set client_min_messages = warning;
drop table if exists pg_temp.r;
create temp table r (n serial, ok boolean, que text);
create or replace function pg_temp.chk(p boolean, q text) returns void language sql as
$$ insert into pg_temp.r (ok, que) values (coalesce(p, false), q) $$;
-- Llama como service_role (la Edge Function).
create or replace function pg_temp.sus(c text, n text, t text[], a boolean, tok text, ip text) returns jsonb language plpgsql as $$
declare v jsonb; begin execute 'set local role service_role'; v := em_publico_suscribir(c, n, t, a, tok, ip); execute 'reset role'; return v; end $$;
create or replace function pg_temp.conf(tok text) returns jsonb language plpgsql as $$
declare v jsonb; begin execute 'set local role service_role'; v := em_publico_confirmar(tok); execute 'reset role'; return v; end $$;
create or replace function pg_temp.h(x text) returns text language sql as $$ select encode(sha256(convert_to(x, 'UTF8')), 'hex') $$;
create or replace function pg_temp.err(q text) returns text language plpgsql as $$
begin execute q; return 'SIN ERROR'; exception when others then execute 'reset role'; return sqlerrm; end $$;

begin;

-- 1. Apagado por defecto
select pg_temp.chk(pg_temp.err($q$select pg_temp.sus('a@z.invalid', null, '{novedades}', true, pg_temp.h('t1'), 'ip1')$q$) like 'EM_CAPTURA_APAGADA%', 'apagado: el servidor rechaza todo');
select pg_temp.chk(pg_temp.err($q$
  do $d$ begin set local role authenticated; perform set_config('request.jwt.claims','{"sub":"89e5028d-8c17-4deb-89c3-59acbd0ee2f2","role":"authenticated"}',true); perform em_config_captura(true); end $d$ $q$) like 'EM_POLITICA_PENDIENTE%', 'no se puede encender sin politica registrada');

-- Politica BORRADOR registrada y captura encendida (como admin)
do $$ begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"89e5028d-8c17-4deb-89c3-59acbd0ee2f2","role":"authenticated"}', true);
  perform em_config_politica(true, 'https://magandhi.com/politicas/datos/', 'borrador-0');
  perform em_config_captura(true);
  reset role;
end $$;
select pg_temp.chk((select captura_publica_activa and politica_publicada from em_config where id), 'admin enciende la captura con la politica borrador-0');
select pg_temp.chk((select (em_publico_config()->>'activa')::boolean and em_publico_config()->>'politica_url' = 'https://magandhi.com/politicas/datos/'), 'config publica: activa + enlace a la politica');

-- 2. Validaciones
select pg_temp.chk(pg_temp.err($q$select pg_temp.sus('no-es-correo', null, '{novedades}', true, pg_temp.h('t2'), 'ip1')$q$) like 'EM_CORREO_INVALIDO%', 'correo invalido');
select pg_temp.chk(pg_temp.err($q$select pg_temp.sus('a@z.invalid', null, '{novedades}', false, pg_temp.h('t2'), 'ip1')$q$) like 'EM_CONFIRMACION_REQUERIDA%', 'sin marcar la autorizacion: rechazado');
select pg_temp.chk(pg_temp.err($q$select pg_temp.sus('a@z.invalid', null, '{inventado}', true, pg_temp.h('t2'), 'ip1')$q$) like 'EM_TEMAS_REQUERIDOS%', 'tema inexistente: rechazado');
select pg_temp.chk(pg_temp.err($q$select pg_temp.sus('a@z.invalid', null, '{novedades}', true, 'token-plano', 'ip1')$q$) like 'EM_TOKEN_INVALIDO%', 'token sin hash: rechazado');

-- 3. Camino feliz: solicitud NO crea contacto; confirmar si
create temp table s1 as select pg_temp.sus(' Ana@Z.invalid ', 'Ana <b>', '{novedades,ofertas}', true, pg_temp.h('tok-ana'), 'ip1') v;
select pg_temp.chk((select (v->>'enviar')::boolean from s1), 'solicitud valida: hay que enviar el correo');
select pg_temp.chk(not exists (select 1 from em_contactos where correo_norm = 'ana@z.invalid'), 'la solicitud NO crea contacto (un tercero no puede inscribir a nadie)');
select pg_temp.chk((select nombre from em_confirmaciones where correo_norm = 'ana@z.invalid') = 'Ana b', 'nombre limpio de caracteres raros');
select pg_temp.chk(not exists (select 1 from em_confirmaciones where token_hash = 'tok-ana'), 'el token nunca se guarda en claro');
select pg_temp.chk(pg_temp.conf(pg_temp.h('tok-ana'))->>'estado' = 'confirmado', 'confirmar con el token correcto');
select pg_temp.chk((select estado = 'suscrito' and fuente = 'formulario_tienda' and politica_version = 'borrador-0' and confirmado_en is not null
                       and evidencia->>'canal' = 'formulario_tienda' and evidencia ? 'solicitado_en' and temas = '{novedades,ofertas}'
                      from em_contactos where correo_norm = 'ana@z.invalid'), 'contacto suscrito con su prueba completa');
select pg_temp.chk((select count(*) from em_consentimiento_bitacora b join em_contactos c on c.id = b.contacto_id
                     where c.correo_norm = 'ana@z.invalid' and b.accion in ('alta','confirmacion') and b.actor is null) = 2, 'bitacora: alta + confirmacion');
select pg_temp.chk(pg_temp.conf(pg_temp.h('tok-ana'))->>'estado' = 'ya_confirmado', 'el enlace es de un solo uso');
select pg_temp.chk(pg_temp.conf(pg_temp.h('otro'))->>'estado' = 'invalido', 'token desconocido: invalido');
select pg_temp.chk(pg_temp.conf('x')->>'estado' = 'invalido', 'token mal formado: invalido (sin error)');

-- 4. No revela si existe: ya suscrita -> misma respuesta, sin correo
create temp table s2 as select pg_temp.sus('ana@z.invalid', null, '{novedades}', true, pg_temp.h('tok-ana2'), 'ip2') v;
select pg_temp.chk((select v->>'estado' = 'ok' and not (v->>'enviar')::boolean from s2), 'ya suscrita: respuesta igual, no se envia correo');

-- 5. Vencido
insert into em_confirmaciones (correo, correo_norm, temas, token_hash, consentimiento_texto, politica_version, creado, vence)
values ('vieja@z.invalid', 'vieja@z.invalid', '{novedades}', pg_temp.h('tok-viejo'), 't', 'borrador-0', now() - interval '3 days', now() - interval '1 day');
select pg_temp.chk(pg_temp.conf(pg_temp.h('tok-viejo'))->>'estado' = 'vencido', 'enlace de mas de 48 h: vencido');
select pg_temp.chk(not exists (select 1 from em_contactos where correo_norm = 'vieja@z.invalid'), 'vencido no crea contacto');

-- 6. Limites
select pg_temp.sus('bomba@z.invalid', null, '{novedades}', true, pg_temp.h('b' || g), 'ip-b' || g) from generate_series(1, 3) g;
select pg_temp.chk((select not (pg_temp.sus('bomba@z.invalid', null, '{novedades}', true, pg_temp.h('b4'), 'ip-b4')->>'enviar')::boolean), 'max 3 correos de confirmacion por direccion al dia');
select pg_temp.sus('x' || g || '@z.invalid', null, '{novedades}', true, pg_temp.h('ipx' || g), 'ip-abuso') from generate_series(1, 10) g;
select pg_temp.chk(pg_temp.err($q$select pg_temp.sus('x11@z.invalid', null, '{novedades}', true, pg_temp.h('ipx11'), 'ip-abuso')$q$) like 'EM_DEMASIADOS_INTENTOS%', 'max 10 solicitudes por IP al dia');
select pg_temp.chk(not exists (select 1 from em_suscripcion_intentos where ip_hash ~ '\d+\.\d+\.\d+\.\d+'), 'nunca se guarda una IP');

-- 7. Suprimidos y bajas
insert into em_contactos (correo, correo_norm, nombre, estado, fuente, consentimiento_en, consentimiento_texto, politica_version, evidencia) values
  ('reb@z.invalid', 'reb@z.invalid', 'Reb', 'rebotado', 'manual', now(), 't', '1.0', '{}'),
  ('baja@z.invalid', 'baja@z.invalid', 'Baja', 'baja', 'manual', now() - interval '60 days', 't', '1.0', '{}');
select pg_temp.chk((select not (pg_temp.sus('reb@z.invalid', null, '{novedades}', true, pg_temp.h('tok-reb'), 'ip3')->>'enviar')::boolean), 'rebotado: no se le envia ni la confirmacion');
create temp table s3 as select pg_temp.sus('baja@z.invalid', 'Bea', '{ofertas}', true, pg_temp.h('tok-baja'), 'ip3') v;
select pg_temp.chk((select (v->>'enviar')::boolean from s3), 'de baja puede volver a pedir suscripcion');
select pg_temp.chk((select estado from em_contactos where correo_norm = 'baja@z.invalid') = 'baja', 'pedirla no la reactiva: solo confirmar');
select pg_temp.chk(pg_temp.conf(pg_temp.h('tok-baja'))->>'estado' = 'confirmado', 'confirma su nueva autorizacion');
select pg_temp.chk((select estado = 'suscrito' and fuente = 'formulario_tienda' and temas = '{ofertas}' and baja_en is null from em_contactos where correo_norm = 'baja@z.invalid'), 'reactivada con nueva prueba y sus nuevos temas');
select pg_temp.chk(exists (select 1 from em_consentimiento_bitacora b join em_contactos c on c.id = b.contacto_id where c.correo_norm = 'baja@z.invalid' and b.accion = 'reactivacion'), 'bitacora: reactivacion');

-- 8. Vinculo con cliente
insert into clientes (id, nombre, correo, correo_norm) values ('c6000000-0000-4000-8000-000000000001', 'Cli', 'cli@z.invalid', 'cli@z.invalid');
select pg_temp.sus('cli@z.invalid', null, '{novedades}', true, pg_temp.h('tok-cli'), 'ip4');
select pg_temp.conf(pg_temp.h('tok-cli'));
select pg_temp.chk((select customer_id from em_contactos where correo_norm = 'cli@z.invalid') = 'c6000000-0000-4000-8000-000000000001', 'se enlaza solo con su ficha de cliente');

-- 9. Politica borrador: nunca recibe campanas reales
insert into em_segmentos (id, nombre, tipo, definicion) values ('5e600000-0000-4000-8000-000000000001', 'Todos EM6', 'reglas', '{"modo":"y","reglas":[{"campo":"dias_en_lista","op":"gte","valor":"0"}]}');
insert into em_contactos (correo, correo_norm, nombre, estado, fuente, temas, consentimiento_en, consentimiento_texto, politica_version, evidencia) values
  ('real@z.invalid', 'real@z.invalid', 'Real', 'suscrito', 'manual', '{novedades}', now(), 't', '1.0', '{}');
select pg_temp.chk((select count(*) from em__audiencia('5e600000-0000-4000-8000-000000000001', 'novedades') a join em_contactos c on c.id = a
                     where c.correo_norm in ('ana@z.invalid', 'real@z.invalid')) = 2, 'con politica borrador vigente: los de prueba si reciben (para probar)');
update em_config set politica_version = '1.0' where id;
select pg_temp.chk((select count(*) from em__audiencia('5e600000-0000-4000-8000-000000000001', 'novedades') a join em_contactos c on c.id = a
                     where c.correo_norm = 'ana@z.invalid') = 0, 'politica definitiva: los suscritos bajo borrador quedan FUERA');
select pg_temp.chk((select count(*) from em__audiencia('5e600000-0000-4000-8000-000000000001', 'novedades') a join em_contactos c on c.id = a
                     where c.correo_norm = 'real@z.invalid') = 1, 'politica definitiva: los demas siguen');
set local role authenticated;
set local request.jwt.claims to '{"sub":"89e5028d-8c17-4deb-89c3-59acbd0ee2f2","role":"authenticated"}';
create temp table aud as select em_campana_audiencia('5e600000-0000-4000-8000-000000000001', 'novedades') a, em_captura_estado() e;
reset role;
select pg_temp.chk((select (a->>'excluidos_borrador')::int >= 2 from aud), 'la revision de campana dice cuantos quedaron fuera por borrador');
select pg_temp.chk((select (e->>'contactos_borrador')::int >= 3 and (e->>'activa')::boolean and (e->>'solicitudes_30d')::int >= 1 from aud), 'estado de la captura para el Resumen');
update em_config set politica_version = 'borrador-0' where id;

-- 10. Apagar vuelve a cerrar
do $$ begin
  set local role authenticated;
  perform set_config('request.jwt.claims', '{"sub":"89e5028d-8c17-4deb-89c3-59acbd0ee2f2","role":"authenticated"}', true);
  perform em_config_captura(false);
  reset role;
end $$;
select pg_temp.chk(pg_temp.err($q$select pg_temp.sus('nueva@z.invalid', null, '{novedades}', true, pg_temp.h('tok-n'), 'ip5')$q$) like 'EM_CAPTURA_APAGADA%', 'apagada otra vez: rechaza');
select pg_temp.chk((em_publico_config()->>'activa')::boolean = false, 'config publica dice apagada (la tienda oculta el formulario)');

-- 11. Purga
insert into em_confirmaciones (correo, correo_norm, temas, token_hash, consentimiento_texto, politica_version, creado, vence)
values ('purga@z.invalid', 'purga@z.invalid', '{novedades}', pg_temp.h('tok-purga'), 't', 'b', now() - interval '8 days', now() - interval '6 days');
insert into em_suscripcion_intentos values ('viejo', current_date - 5, 3);
select em__purgar_captura();
select pg_temp.chk(not exists (select 1 from em_confirmaciones where correo_norm = 'purga@z.invalid') and not exists (select 1 from em_suscripcion_intentos where ip_hash = 'viejo'), 'purga: solicitudes de mas de 7 dias e intentos viejos');

-- 12. Permisos
select pg_temp.chk(not has_function_privilege('anon', 'em_publico_suscribir(text,text,text[],boolean,text,text)', 'execute')
               and not has_function_privilege('authenticated', 'em_publico_suscribir(text,text,text[],boolean,text,text)', 'execute')
               and has_function_privilege('service_role', 'em_publico_suscribir(text,text,text[],boolean,text,text)', 'execute'), 'suscribir: solo service_role');
select pg_temp.chk(not has_function_privilege('anon', 'em_publico_confirmar(text)', 'execute') and not has_function_privilege('authenticated', 'em_publico_confirmar(text)', 'execute'), 'confirmar: solo service_role');
select pg_temp.chk(pg_temp.err($q$do $d$ declare n int; begin set local role anon; select count(*) into n from em_confirmaciones; end $d$$q$) like 'permission denied%', 'anon no lee las solicitudes');
select pg_temp.chk(pg_temp.err($q$do $d$ declare n int; begin set local role authenticated; perform set_config('request.jwt.claims','{"sub":"89e5028d-8c17-4deb-89c3-59acbd0ee2f2","role":"authenticated"}',true); select count(*) into n from em_confirmaciones; end $d$$q$) like 'permission denied%', 'ni el admin lee las solicitudes directo (solo agregados)');
insert into auth.users (id, email) values ('7e560000-0000-4000-8000-000000000001', 'em6-em@local.invalid') on conflict do nothing;
insert into perfiles (id, rol, modulos) values ('7e560000-0000-4000-8000-000000000001', 'prueba', '{email_marketing}') on conflict (id) do nothing;
select pg_temp.chk(pg_temp.err($q$do $d$ begin set local role authenticated; perform set_config('request.jwt.claims','{"sub":"7e560000-0000-4000-8000-000000000001","role":"authenticated"}',true); perform em_config_captura(true); end $d$$q$) like 'EM_SIN_ACCESO%', 'solo un admin enciende o apaga la captura');

select case when ok then 'pasa' else 'FALLA' end || ' | ' || que from pg_temp.r order by n;
select 'RESUMEN | ' || count(*) || ' comprobaciones · ' || count(*) filter (where not ok) || ' fallan' from pg_temp.r;
rollback;
