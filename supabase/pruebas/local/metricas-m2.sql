-- ============================================================
-- Impulse · Pruebas de Metricas M2 (capa de datos: Email, Opiniones, Inventario)
-- SOLO LOCAL; todo se deshace al final (rollback).
-- Verifica NUMEROS, no solo que la funcion corra.
-- ============================================================
\set ON_ERROR_STOP 1
set client_min_messages = warning;
drop table if exists pg_temp.r;
create temp table r (n serial, ok boolean, que text);
create or replace function pg_temp.chk(p boolean, q text) returns void language sql as
$$ insert into pg_temp.r (ok, que) values (coalesce(p, false), q) $$;
create or replace function pg_temp.err(q text) returns text language plpgsql as $$
begin execute q; return 'SIN ERROR'; exception when others then execute 'reset role'; return sqlerrm; end $$;
create or replace function pg_temp.como(uid text, q text) returns jsonb language plpgsql as $$
declare x jsonb; begin execute 'set local role authenticated';
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated')::text, true);
  execute q into x; execute 'reset role'; return x; end $$;

begin;
-- Personas de prueba
insert into auth.users (id, email) values
  ('7e580000-0000-4000-8000-0000000000a1', 'm2-met@local.invalid'),
  ('7e580000-0000-4000-8000-0000000000a3', 'm2-fin@local.invalid') on conflict do nothing;
insert into perfiles (id, rol, modulos) values
  ('7e580000-0000-4000-8000-0000000000a1', 'prueba', '{metricas}'),
  ('7e580000-0000-4000-8000-0000000000a3', 'prueba', '{finanzas}') on conflict (id) do nothing;

-- ---------------- Datos controlados ----------------
-- Productos propios (sku unico) para asertar inventario sin depender del resto.
insert into productos (id, sku, nombre, costo_unitario, precio_venta, stock_minimo, activo) values
  ('b2000000-0000-4000-8000-000000000001', 'MT2-P1', 'Producto M2 uno', 1000, 3000, 10, true),
  ('b2000000-0000-4000-8000-000000000002', 'MT2-P2', 'Producto M2 dos', 2000, 5000, 5, true),
  ('b2000000-0000-4000-8000-000000000003', 'MT2-P3', 'Producto M2 tres', 1500, 4000, 0, true);
insert into movimientos_inventario (product_id, tipo, cantidad, motivo, fecha) values
  ('b2000000-0000-4000-8000-000000000001', 'entrada', 100, 'demo', (now() at time zone 'America/Bogota')::date - 40),
  ('b2000000-0000-4000-8000-000000000002', 'entrada', 3, 'demo', (now() at time zone 'America/Bogota')::date - 40);
-- P3 sin entrada -> existencias 0 -> agotado.

-- Clientes y pedidos entregados en el periodo
insert into clientes (id, nombre, correo, correo_norm, ciudad) values
  ('c2000000-0000-4000-8000-000000000001', 'Ana M2', 'ana-m2@z.invalid', 'ana-m2@z.invalid', 'Tunja'),
  ('c2000000-0000-4000-8000-000000000002', 'Beto M2', 'beto-m2@z.invalid', 'beto-m2@z.invalid', 'Tunja');
insert into pedidos (id, customer_id, fecha_orden, estado, total, creado, canal, utm_campaign) values
  ('d2000000-0000-4000-8000-000000000001', 'c2000000-0000-4000-8000-000000000001', (now() at time zone 'America/Bogota')::date - 2, 'entregado', 3000, now() - interval '2 days', 'manual', null),
  ('d2000000-0000-4000-8000-000000000002', 'c2000000-0000-4000-8000-000000000002', (now() at time zone 'America/Bogota')::date - 3, 'entregado', 3000, now() - interval '3 days', 'manual', null),
  ('d2000000-0000-4000-8000-000000000003', 'c2000000-0000-4000-8000-000000000001', (now() at time zone 'America/Bogota')::date - 4, 'entregado', 3000, now() - interval '4 days', 'manual', null),
  ('d2000000-0000-4000-8000-000000000004', 'c2000000-0000-4000-8000-000000000002', (now() at time zone 'America/Bogota')::date - 5, 'entregado', 3000, now() - interval '5 days', 'manual', null),
  ('d2000000-0000-4000-8000-000000000005', 'c2000000-0000-4000-8000-000000000001', (now() at time zone 'America/Bogota')::date - 6, 'entregado', 3000, now() - interval '6 days', 'manual', null),
  -- 3 pedidos atribuidos EXACTO a la campana (utm). Alimentan vendidas_30d de P1 (30 u.)
  ('d2000000-0000-4000-8000-000000000006', 'c2000000-0000-4000-8000-000000000002', (now() at time zone 'America/Bogota')::date - 1, 'entregado', 3000, now() - interval '1 day', 'web', 'camp-m2'),
  ('d2000000-0000-4000-8000-000000000007', 'c2000000-0000-4000-8000-000000000001', (now() at time zone 'America/Bogota')::date - 1, 'entregado', 3000, now() - interval '1 day', 'web', 'camp-m2'),
  ('d2000000-0000-4000-8000-000000000008', 'c2000000-0000-4000-8000-000000000002', (now() at time zone 'America/Bogota')::date - 1, 'entregado', 3000, now() - interval '1 day', 'web', 'camp-m2');
-- items: P1 vendido 30 u. en total dentro de 30 dias (venta diaria 1/dia -> dias_inv = 100)
insert into pedido_items (pedido_id, product_id, cantidad, precio_unitario, subtotal) values
  ('d2000000-0000-4000-8000-000000000001', 'b2000000-0000-4000-8000-000000000001', 10, 3000, 30000),
  ('d2000000-0000-4000-8000-000000000002', 'b2000000-0000-4000-8000-000000000001', 10, 3000, 30000),
  ('d2000000-0000-4000-8000-000000000003', 'b2000000-0000-4000-8000-000000000001', 10, 3000, 30000),
  ('d2000000-0000-4000-8000-000000000004', 'b2000000-0000-4000-8000-000000000002', 1, 5000, 5000),
  ('d2000000-0000-4000-8000-000000000005', 'b2000000-0000-4000-8000-000000000002', 1, 5000, 5000),
  ('d2000000-0000-4000-8000-000000000006', 'b2000000-0000-4000-8000-000000000003', 1, 4000, 4000),
  ('d2000000-0000-4000-8000-000000000007', 'b2000000-0000-4000-8000-000000000003', 1, 4000, 4000),
  ('d2000000-0000-4000-8000-000000000008', 'b2000000-0000-4000-8000-000000000003', 1, 4000, 4000);

-- Opiniones: 3 reales (5,5,4) sobre P1 en 3 pedidos distintos + 1 prueba + 1 oculta (deben EXCLUIRSE)
insert into opiniones (pedido_id, product_id, estrellas, autor_nombre, creado, respuesta) values
  ('d2000000-0000-4000-8000-000000000001', 'b2000000-0000-4000-8000-000000000001', 5, 'Ana', now() - interval '1 day', 'Gracias'),
  ('d2000000-0000-4000-8000-000000000002', 'b2000000-0000-4000-8000-000000000001', 5, 'Beto', now() - interval '2 days', null),
  ('d2000000-0000-4000-8000-000000000003', 'b2000000-0000-4000-8000-000000000001', 4, 'Ana', now() - interval '3 days', null);
insert into opiniones (pedido_id, product_id, estrellas, autor_nombre, es_prueba) values
  ('d2000000-0000-4000-8000-000000000004', 'b2000000-0000-4000-8000-000000000002', 1, 'Prueba', true);
insert into opiniones (pedido_id, product_id, estrellas, autor_nombre, oculta, oculta_motivo, oculta_en) values
  ('d2000000-0000-4000-8000-000000000006', 'b2000000-0000-4000-8000-000000000003', 1, 'Spam', true, 'spam', now());

-- Email: contactos (5 suscritos, 1 sin confirmar, 1 baja), bitacora, campana y eventos
insert into em_contactos (id, correo, correo_norm, customer_id, estado, fuente, consentimiento_en, consentimiento_texto, politica_version, confirmado_en) values
  ('e2000000-0000-4000-8000-000000000001', 's1@z.invalid', 's1@z.invalid', 'c2000000-0000-4000-8000-000000000001', 'suscrito', 'formulario_tienda', now() - interval '10 days', 'ok', 'borrador-0', now() - interval '10 days'),
  ('e2000000-0000-4000-8000-000000000002', 's2@z.invalid', 's2@z.invalid', null, 'suscrito', 'formulario_tienda', now() - interval '9 days', 'ok', 'borrador-0', now() - interval '9 days'),
  ('e2000000-0000-4000-8000-000000000003', 's3@z.invalid', 's3@z.invalid', null, 'suscrito', 'formulario_tienda', now() - interval '8 days', 'ok', 'borrador-0', now() - interval '8 days'),
  ('e2000000-0000-4000-8000-000000000004', 's4@z.invalid', 's4@z.invalid', null, 'suscrito', 'manual', now() - interval '7 days', 'ok', 'borrador-0', now() - interval '7 days'),
  ('e2000000-0000-4000-8000-000000000005', 's5@z.invalid', 's5@z.invalid', null, 'suscrito', 'manual', now() - interval '6 days', 'ok', 'borrador-0', now() - interval '6 days'),
  ('e2000000-0000-4000-8000-000000000006', 'p1@z.invalid', 'p1@z.invalid', null, 'pendiente_confirmacion', 'formulario_tienda', now() - interval '5 days', 'ok', 'borrador-0', null),
  ('e2000000-0000-4000-8000-000000000007', 'b1@z.invalid', 'b1@z.invalid', null, 'baja', 'manual', now() - interval '20 days', 'ok', 'borrador-0', now() - interval '20 days');
insert into em_consentimiento_bitacora (contacto_id, accion, estado_nuevo, cuando)
select id, 'alta', estado, consentimiento_en from em_contactos where correo_norm like 's%@z.invalid' or correo_norm like 'p1@z.invalid' or correo_norm like 'b1@z.invalid';
insert into em_consentimiento_bitacora (contacto_id, accion, estado_nuevo, cuando) values
  ('e2000000-0000-4000-8000-000000000007', 'baja', 'baja', now() - interval '3 days');

insert into em_campanas (id, nombre_interno, asunto, utm_campaign, estado, audiencia_n, enviada_en, resend_broadcast_id) values
  ('a2000000-0000-4000-8000-000000000001', 'Campaña M2', 'Hola M2', 'camp-m2', 'enviada', 5, now() - interval '5 days', 'bc_m2');
insert into em_campana_destinatarios (campana_id, contacto_id, correo, estado, procesado_en)
select 'a2000000-0000-4000-8000-000000000001', id, correo, 'listo', now() - interval '5 days' from em_contactos where correo_norm like 's%@z.invalid';
-- 5 entregados, 2 clics
insert into em_eventos (svix_id, evento, tipo, origen, campana_id, contacto_id, cuando, recibido)
select 'svx-e-' || id, 'email.delivered', 'entregado', 'campana', 'a2000000-0000-4000-8000-000000000001', id, now() - interval '5 days', now() - interval '5 days' from em_contactos where correo_norm like 's%@z.invalid';
insert into em_eventos (svix_id, evento, tipo, origen, campana_id, contacto_id, cuando, recibido) values
  ('svx-c-1', 'email.clicked', 'clic', 'campana', 'a2000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000001', now() - interval '4 days', now() - interval '4 days'),
  ('svx-c-2', 'email.clicked', 'clic', 'campana', 'a2000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000002', now() - interval '4 days', now() - interval '4 days');

-- Politica publicada (algunas lecturas la consultan)
update em_config set politica_publicada = true, politica_version = 'borrador-0' where id;

-- ================= INVENTARIO =================
create temp table iv as select pg_temp.como('7e580000-0000-4000-8000-0000000000a1', 'select mt_inventario()') v;
select pg_temp.chk((select (x->>'existencias')::int = 100 and (x->>'bajo')::boolean = false and (x->>'agotado')::boolean = false and (x->>'vendidas_30d')::int = 30 and (x->>'dias_inventario')::int = 100
  from iv, jsonb_array_elements(v->'productos') x where x->>'sku' = 'MT2-P1'), 'inventario: P1 100 u., 30 vendidas en 30 d, ~100 días de inventario');
select pg_temp.chk((select (x->>'existencias')::int = 3 and (x->>'bajo')::boolean = true from iv, jsonb_array_elements(v->'productos') x where x->>'sku' = 'MT2-P2'), 'inventario: P2 bajo mínimo (3 <= 5)');
select pg_temp.chk((select (x->>'existencias')::int = 0 and (x->>'agotado')::boolean = true from iv, jsonb_array_elements(v->'productos') x where x->>'sku' = 'MT2-P3'), 'inventario: P3 agotado (sin entradas)');
select pg_temp.chk((select (v->'totales'->>'bajo_stock')::int >= 2 and (v->'totales'->>'agotados')::int >= 1 from iv), 'inventario: totales de bajo stock y agotados cuentan los míos');
select pg_temp.chk((select jsonb_array_length(v->'por_semana') = 12 from iv), 'inventario: 12 semanas de rotación');
select pg_temp.chk((select exists (select 1 from iv, jsonb_array_elements(v->'alertas') a where a->>'nombre' = 'Producto M2 dos') from iv), 'inventario: P2 aparece en alertas de bajo stock');

-- ================= OPINIONES =================
create temp table op as select pg_temp.como('7e580000-0000-4000-8000-0000000000a1', $q$select mt_opiniones(((now() at time zone 'America/Bogota')::date - 89), (now() at time zone 'America/Bogota')::date)$q$) v;
select pg_temp.chk((select (v->'resumen'->>'total')::int = 3 and v->'resumen'->>'promedio' = '4.7' from op), 'opiniones: 3 reales, promedio 4.7 (prueba y oculta excluidas)');
select pg_temp.chk((select (v->'resumen'->>'total_global')::int = 3 and v->'resumen'->>'promedio_global' = '4.7' from op), 'opiniones: total GLOBAL también excluye prueba y oculta');
select pg_temp.chk((select (v->'resumen'->>'con_respuesta')::int = 1 from op), 'opiniones: 1 con respuesta de marca');
select pg_temp.chk((select (x->>'n')::int = 2 from op, jsonb_array_elements(v->'distribucion') x where x->>'estrellas' = '5') and
                   (select (x->>'n')::int = 1 from op, jsonb_array_elements(v->'distribucion') x where x->>'estrellas' = '4'), 'opiniones: distribución 2×5★ y 1×4★');
select pg_temp.chk((select (v->'cobertura'->>'entregados')::int = 8 and (v->'cobertura'->>'con_opinion')::int = 3 and (v->'cobertura'->>'pct')::int = 38 from op), 'opiniones: cobertura 3 de 8 entregados = 38%');
select pg_temp.chk((select (x->>'promedio') = '4.7' and (x->>'n')::int = 3 from op, jsonb_array_elements(v->'productos') x where x->>'nombre' = 'Producto M2 uno'), 'opiniones: producto con su promedio real y total');
select pg_temp.chk((select coalesce(sum((x->>'n')::int), 0) = 3 from op, jsonb_array_elements(v->'por_mes') x), 'opiniones: por mes suma 3 opiniones');

-- ================= EMAIL =================
create temp table em as select pg_temp.como('7e580000-0000-4000-8000-0000000000a1', $q$select mt_email(((now() at time zone 'America/Bogota')::date - 29), (now() at time zone 'America/Bogota')::date)$q$) v;
select pg_temp.chk((select (v->'lista'->>'suscritos')::int = 5 and (v->'lista'->>'pendientes')::int = 1 from em), 'email: 5 suscritos, 1 sin confirmar');
select pg_temp.chk((select (v->'lista'->>'vinculados')::int = 1 from em), 'email: 1 suscrito ya es cliente');
select pg_temp.chk((select (v->'lista'->>'altas')::int = 7 and (v->'lista'->>'bajas')::int = 1 from em), 'email: 7 altas y 1 baja en el periodo');
select pg_temp.chk((select (v->'lista'->'por_estado'->>'suscrito')::int = 5 and (v->'lista'->'por_estado'->>'baja')::int = 1 from em), 'email: reparto por estado');
select pg_temp.chk((select jsonb_array_length(v->'campanas') = 1 from em), 'email: 1 campaña en el periodo');
-- pedidos = 3 exactos (utm) + 2 aproximados (último clic, 7 días): MISMO criterio
-- que el área de Email, para que el número coincida entre superficies.
select pg_temp.chk((select (x->>'entregados')::int = 5 and (x->>'clics')::int = 2 and (x->>'pedidos')::int = 5 from em, jsonb_array_elements(v->'campanas') x limit 1), 'email: campaña con 5 entregados, 2 clics y 5 pedidos (3 exactos + 2 aproximados, como el área de Email)');
select pg_temp.chk((select (v->'salud'->>'enviados')::int = 5 and (v->'salud'->>'entregados')::int = 5 and (v->'salud'->>'rebotes')::int = 0 and (v->'salud'->>'tasa_rebote')::numeric = 0 from em), 'email: salud 5 enviados/entregados, 0 rebotes');

-- ================= PERMISOS / PRIVACIDAD =================
select pg_temp.chk(pg_temp.err($q$select pg_temp.como('7e580000-0000-4000-8000-0000000000a3', 'select mt_email(null, null)')$q$) like 'MT_SIN_ACCESO%', 'solo Finanzas: sin acceso a mt_email');
select pg_temp.chk(pg_temp.err($q$select pg_temp.como('7e580000-0000-4000-8000-0000000000a3', 'select mt_opiniones(null, null)')$q$) like 'MT_SIN_ACCESO%', 'solo Finanzas: sin acceso a mt_opiniones');
select pg_temp.chk(pg_temp.err($q$select pg_temp.como('7e580000-0000-4000-8000-0000000000a3', 'select mt_inventario()')$q$) like 'MT_SIN_ACCESO%', 'solo Finanzas: sin acceso a mt_inventario');
select pg_temp.chk(pg_temp.err($q$select pg_temp.como('7e580000-0000-4000-8000-0000000000a1', 'select mt_email(''2026-03-01'', ''2026-01-01'')')$q$) like 'MT_PERIODO_INVALIDO%', 'email: periodo invertido rechazado');
select pg_temp.chk(not has_function_privilege('anon', 'mt_email(date,date)', 'execute') and not has_function_privilege('anon', 'mt_opiniones(date,date)', 'execute') and not has_function_privilege('anon', 'mt_inventario()', 'execute'), 'anon no ejecuta ninguna función M2');
select pg_temp.chk((select not ((v->'campanas')::text ~ '@z.invalid') from em) and (select not ((v->'productos')::text ~ 'Ana|Beto') from op), 'M2: la capa no expone correos ni nombres de personas');

select case when ok then 'pasa' else 'FALLA' end || ' | ' || que from pg_temp.r order by n;
select 'RESUMEN | ' || count(*) || ' comprobaciones · ' || count(*) filter (where not ok) || ' fallan' from pg_temp.r;
rollback;
