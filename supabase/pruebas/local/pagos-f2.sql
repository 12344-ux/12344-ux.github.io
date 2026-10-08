-- ============================================================
-- Impulse · Pruebas de PAGOS WEB · Wompi F2 (capa de datos)
-- Prueba la PROMESA del tramo con numeros, no que la funcion corra:
--   un pago aprobado se convierte en pedido EXACTAMENTE UNA VEZ.
-- SOLO LOCAL; todo se deshace al final (rollback).
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
-- La Edge Function corre como service_role.
create or replace function pg_temp.srv(q text) returns jsonb language plpgsql as $$
declare x jsonb; begin execute 'set local role service_role'; execute q into x; execute 'reset role'; return x;
exception when others then execute 'reset role'; raise; end $$;

begin;
insert into auth.users (id, email) values
  ('7e600000-0000-4000-8000-0000000000a1', 'f2-ven@local.invalid'),
  ('7e600000-0000-4000-8000-0000000000a2', 'f2-fin@local.invalid') on conflict do nothing;
insert into perfiles (id, rol, modulos) values
  ('7e600000-0000-4000-8000-0000000000a1', 'prueba', '{ventas}'),
  ('7e600000-0000-4000-8000-0000000000a2', 'prueba', '{finanzas}') on conflict (id) do nothing;

-- Producto con 5 unidades y campana ligada
insert into productos (id, sku, nombre, precio_venta, costo_unitario, activo) values
  ('b6000000-0000-4000-8000-000000000001', 'F2-P1', 'Producto F2', 30000, 10000, true);
insert into movimientos_inventario (product_id, tipo, cantidad, motivo) values
  ('b6000000-0000-4000-8000-000000000001', 'entrada', 5, 'demo F2');
insert into campana_producto (id, nombre, slug, precio_venta, product_id_ref, publicado, activo) values
  ('a6000000-0000-4000-8000-000000000001', 'Producto F2', 'f2-p1', 30000, 'b6000000-0000-4000-8000-000000000001', true, true),
  -- campana SIN producto ligado (caso de revision)
  ('a6000000-0000-4000-8000-000000000002', 'Sin ligar', 'f2-sin', 30000, null, false, true);

-- ---------- 1. Registrar la intencion ANTES de firmar ----------
select pg_temp.chk((pg_temp.srv($q$select pw_registrar_intencion('REF-F2-0001','a6000000-0000-4000-8000-000000000001','f2-p1','Producto F2',1,30000,3000000,'sandbox',
  '{"nombre":"Ana Compradora","correo":"ana@cliente.invalid","telefono":"3001112233","direccion":"Calle 1","ciudad":"Tunja","departamento":"Boyaca","pais":"CO"}'::jsonb,'camp-f2','vid-abc123')$q$)->>'ligado')::boolean,
  'intencion: se persiste antes de firmar y resuelve el producto de Inventario');
select pg_temp.chk((select estado = 'creada' and monto_centavos = 3000000 and utm_campaign = 'camp-f2' and mg_vid = 'vid-abc123'
   and comprador_nombre = 'Ana Compradora' from pagos_intencion where referencia = 'REF-F2-0001'),
  'intencion: guarda el monto firmado, el comprador de la TIENDA, utm y mg_vid');
select pg_temp.chk(pg_temp.err($q$select pg_temp.srv($$select pw_registrar_intencion('mala!','a6000000-0000-4000-8000-000000000001','x','x',1,30000,3000000,'sandbox')$$)$q$) like '%PW_REFERENCIA_INVALIDA%',
  'intencion: referencia con formato invalido se rechaza');
select pg_temp.chk(pg_temp.err($q$select pg_temp.srv($$select pw_registrar_intencion('REF-F2-ENT','a6000000-0000-4000-8000-000000000001','x','x',1,30000,3000000,'produccion')$$)$q$) like '%PW_ENTORNO_INVALIDO%',
  'intencion: entorno distinto de sandbox/prod se rechaza');

-- ---------- 2. Pago APROBADO -> un pedido ----------
create temp table p1 as select pg_temp.srv($q$select pw_procesar_pago('TX-001','APPROVED','REF-F2-0001',3000000,'COP','transaction.updated','chk1',
  '{"data":{"transaction":{"id":"TX-001"}}}'::jsonb,'NEQUI','pagador@wompi.invalid')$q$) v;
select pg_temp.chk((select v->>'resultado' = 'procesado' and (v->>'pedido_id') is not null from p1),
  'aprobado: se crea el pedido');
select pg_temp.chk((select canal = 'web' and total = 30000 and estado = 'recibido'
   from pedidos where id = (select (v->>'pedido_id')::uuid from p1)),
  'aprobado: el pedido queda canal=web con el total firmado');
select pg_temp.chk((select utm_campaign = 'camp-f2' from pedidos where id = (select (v->>'pedido_id')::uuid from p1)),
  'aprobado: el pedido hereda el utm_campaign (atribucion EXACTA, ya no aproximada)');
select pg_temp.chk((select existencias = 4 from stock_actual where product_id = 'b6000000-0000-4000-8000-000000000001'),
  'aprobado: el stock bajo de 5 a 4 (una sola salida)');
select pg_temp.chk((select estado = 'procesada' and procesada_en is not null from pagos_intencion where referencia = 'REF-F2-0001'),
  'aprobado: la intencion queda procesada (terminal)');
select pg_temp.chk((select nombre = 'Ana Compradora' from clientes c
   join pedidos p on p.customer_id = c.id where p.id = (select (v->>'pedido_id')::uuid from p1)),
  'aprobado: el cliente es el que escribio en la TIENDA (Wompi solo confirmo)');

-- ---------- 3. EL MISMO EVENTO DOS VECES -> un solo pedido ----------
create temp table p2 as select pg_temp.srv($q$select pw_procesar_pago('TX-001','APPROVED','REF-F2-0001',3000000,'COP','transaction.updated','chk1',
  '{"data":{"transaction":{"id":"TX-001"}}}'::jsonb,'NEQUI','pagador@wompi.invalid')$q$) v;
select pg_temp.chk((select v->>'resultado' = 'repetido' from p2), 'reintento: el segundo aviso devuelve repetido');
select pg_temp.chk((select count(*) from pedidos where notas = 'Pago web Wompi · referencia REF-F2-0001') = 1,
  'reintento: SIGUE habiendo UN SOLO pedido (la promesa de F2)');
select pg_temp.chk((select existencias = 4 from stock_actual where product_id = 'b6000000-0000-4000-8000-000000000001'),
  'reintento: el stock NO bajo otra vez');
select pg_temp.chk((select (v->>'pedido_id')::uuid = (select (v->>'pedido_id')::uuid from p1) from p2),
  'reintento: devuelve el MISMO pedido, no otro');

-- ---------- 4. Pago RECHAZADO -> nada ----------
select pg_temp.srv($q$select pw_registrar_intencion('REF-F2-0002','a6000000-0000-4000-8000-000000000001','f2-p1','Producto F2',1,30000,3000000,'sandbox','{"nombre":"Beto"}'::jsonb)$q$);
create temp table p3 as select pg_temp.srv($q$select pw_procesar_pago('TX-002','DECLINED','REF-F2-0002',3000000,'COP','transaction.updated','chk2',null,'CARD',null)$q$) v;
select pg_temp.chk((select v->>'resultado' = 'rechazado' from p3), 'rechazado: resultado rechazado');
select pg_temp.chk((select estado = 'rechazada' and pedido_id is null from pagos_intencion where referencia = 'REF-F2-0002'),
  'rechazado: la intencion queda rechazada y SIN pedido');
select pg_temp.chk((select existencias = 4 from stock_actual where product_id = 'b6000000-0000-4000-8000-000000000001'),
  'rechazado: cero salidas de inventario');

-- ---------- 5. MONTO QUE NO COINCIDE -> no crea pedido ----------
select pg_temp.srv($q$select pw_registrar_intencion('REF-F2-0003','a6000000-0000-4000-8000-000000000001','f2-p1','Producto F2',1,30000,3000000,'sandbox','{"nombre":"Caro"}'::jsonb)$q$);
create temp table p4 as select pg_temp.srv($q$select pw_procesar_pago('TX-003','APPROVED','REF-F2-0003',100,'COP','transaction.updated','chk3',null,'CARD',null)$q$) v;
select pg_temp.chk((select v->>'resultado' = 'monto_no_coincide' from p4), 'monto: un monto distinto al firmado NO crea pedido');
select pg_temp.chk((select estado = 'requiere_revision' and revision_motivo like '%no coincide%' and pedido_id is null
   from pagos_intencion where referencia = 'REF-F2-0003'),
  'monto: queda en requiere_revision con el motivo explicito');

-- ---------- 6. PAGO SIN INTENCION -> no se inventa un pedido ----------
create temp table p5 as select pg_temp.srv($q$select pw_procesar_pago('TX-004','APPROVED','REF-NO-EXISTE',3000000,'COP','transaction.updated','chk4',null,null,null)$q$) v;
select pg_temp.chk((select v->>'resultado' = 'sin_intencion' from p5), 'sin intencion: no se crea nada y queda el evento');

-- ---------- 7. CAMPANA SIN PRODUCTO LIGADO -> revision ----------
select pg_temp.srv($q$select pw_registrar_intencion('REF-F2-0004','a6000000-0000-4000-8000-000000000002','f2-sin','Sin ligar',1,30000,3000000,'sandbox','{"nombre":"Dani"}'::jsonb)$q$);
create temp table p6 as select pg_temp.srv($q$select pw_procesar_pago('TX-005','APPROVED','REF-F2-0004',3000000,'COP','transaction.updated','chk5',null,null,null)$q$) v;
select pg_temp.chk((select v->>'resultado' = 'sin_stock' from p6), 'sin producto ligado: no crea pedido, pide revision');

-- ---------- 8. APROBADO SIN STOCK -> aviso rojo, nunca en silencio ----------
-- Agotar: salida de las 4 restantes
insert into movimientos_inventario (product_id, tipo, cantidad, motivo) values
  ('b6000000-0000-4000-8000-000000000001', 'salida', 4, 'agotar para la prueba');
select pg_temp.srv($q$select pw_registrar_intencion('REF-F2-0005','a6000000-0000-4000-8000-000000000001','f2-p1','Producto F2',1,30000,3000000,'sandbox','{"nombre":"Eva","correo":"eva@cliente.invalid","telefono":"3009998877"}'::jsonb)$q$);
create temp table p7 as select pg_temp.srv($q$select pw_procesar_pago('TX-006','APPROVED','REF-F2-0005',3000000,'COP','transaction.updated','chk6',null,'PSE','eva@wompi.invalid')$q$) v;
select pg_temp.chk((select v->>'resultado' = 'sin_stock' from p7), 'sin stock: el pago aprobado NO se convierte en pedido');
select pg_temp.chk((select estado = 'requiere_revision' and pedido_id is null and revision_motivo is not null
   from pagos_intencion where referencia = 'REF-F2-0005'),
  'sin stock: queda en requiere_revision con motivo (decision del dueno)');
select pg_temp.chk((select existencias = 0 from stock_actual where product_id = 'b6000000-0000-4000-8000-000000000001'),
  'sin stock: el inventario NO queda negativo');
select pg_temp.chk((select count(*) from pagos_eventos where transaccion_id = 'TX-006' and resultado = 'sin_stock') = 1,
  'sin stock: el evento queda registrado con su resultado (auditable)');

-- ---------- 9. El aviso rojo del panel ----------
create temp table pr as select pg_temp.como('7e600000-0000-4000-8000-0000000000a1', 'select pw_revisiones()') v;
select pg_temp.chk((select (v->>'pendientes')::int = 3 from pr),
  'panel: 3 pagos requieren revision (monto, sin ligar y sin stock)');
select pg_temp.chk((select exists (select 1 from pr, jsonb_array_elements(v->'lista') x
   where x->>'referencia' = 'REF-F2-0005' and x->>'telefono' = '3009998877') from pr),
  'panel: el aviso trae los datos de contacto para resolver');
select pg_temp.chk((pg_temp.como('7e600000-0000-4000-8000-0000000000a1',
   $q$select pw_resolver_revision('REF-F2-0005', 'Se devolvio el dinero por Nequi')$q$)->>'resuelta')::boolean,
  'panel: se resuelve con nota obligatoria');
select pg_temp.chk((select resuelta_nota = 'Se devolvio el dinero por Nequi' and resuelta_por is not null
   from pagos_intencion where referencia = 'REF-F2-0005'),
  'panel: queda constancia de quien resolvio y que hizo');
select pg_temp.chk(pg_temp.err($q$select pg_temp.como('7e600000-0000-4000-8000-0000000000a1', $$select pw_resolver_revision('REF-F2-0003', '')$$)$q$) like '%PW_NOTA_OBLIGATORIA%',
  'panel: no se puede cerrar una revision sin decir que se hizo');
select pg_temp.chk((select (pg_temp.como('7e600000-0000-4000-8000-0000000000a1', 'select pw_revisiones()')->>'pendientes')::int = 2),
  'panel: la resuelta sale del aviso rojo');

-- ---------- 10. Permisos y privacidad ----------
select pg_temp.chk(pg_temp.err($q$select pg_temp.como('7e600000-0000-4000-8000-0000000000a2', 'select pw_revisiones()')$q$) like '%PW_SIN_ACCESO%',
  'permisos: solo Finanzas no ve los pagos');
select pg_temp.chk(not has_function_privilege('anon', 'pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text)', 'execute')
  and not has_function_privilege('authenticated', 'pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text)', 'execute'),
  'permisos: procesar un pago es SOLO para service_role (ni el panel puede)');
select pg_temp.chk(not has_function_privilege('anon', 'pw_registrar_intencion(text,uuid,text,text,integer,bigint,bigint,text,jsonb,text,text,text)', 'execute')
  and not has_function_privilege('authenticated', 'pw_registrar_intencion(text,uuid,text,text,integer,bigint,bigint,text,jsonb,text,text,text)', 'execute'),
  'permisos: registrar la intencion es SOLO para service_role');
select pg_temp.chk(pg_temp.err($q$do $d$ declare n int; begin set local role anon; select count(*) into n from pagos_intencion; end $d$$q$) like '%permission denied%',
  'privacidad: anon no lee las intenciones de pago');
select pg_temp.chk(pg_temp.err($q$do $d$ declare n int; begin set local role authenticated;
  perform set_config('request.jwt.claims','{"sub":"7e600000-0000-4000-8000-0000000000a1","role":"authenticated"}',true);
  insert into pagos_intencion (referencia, precio_unitario, monto_centavos, entorno) values ('HACK-0001', 1, 1, 'sandbox'); end $d$$q$) <> 'SIN ERROR',
  'escritura: ni Ventas puede insertar una intencion a mano (solo por RPC)');

-- ---------- 11. La compuerta de contexto de servidor no se puede abusar ----------
select pg_temp.chk(not pw__contexto_servidor(),
  'compuerta: por defecto esta CERRADA (fuera de la transaccion del webhook)');
select pg_temp.chk((select estado = 'procesada' from pagos_intencion where referencia = 'REF-F2-0001')
  and not pw__contexto_servidor(),
  'compuerta: quedo cerrada despues de procesar un pago (no se queda abierta)');
-- Un autenticado SIN ventas sigue rechazado por crear_pedido aunque exista la compuerta.
select pg_temp.chk(pg_temp.err($q$select pg_temp.como('7e600000-0000-4000-8000-0000000000a2',
   $$select crear_pedido(p_nombre => 'Intruso', p_items => '[]'::jsonb)$$)$q$) like '%Acceso denegado%',
  'compuerta: quien no tiene ventas sigue sin poder crear pedidos');
-- El prefijo importa: una variable request.* (falsificable por cabecera) NO abre la compuerta.
select set_config('request.pago_servidor', 'on', true);
select pg_temp.chk(not pw__contexto_servidor(),
  'compuerta: una variable request.* (la unica que un cliente podria inyectar) NO la abre');

select case when ok then 'pasa' else 'FALLA' end || ' | ' || que from pg_temp.r order by n;
select 'RESUMEN | ' || count(*) || ' comprobaciones · ' || count(*) filter (where not ok) || ' fallan' from pg_temp.r;
rollback;
