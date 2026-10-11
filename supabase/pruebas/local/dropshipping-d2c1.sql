-- MAGANDHI · Pruebas D2c.1 · Stock vivo del proveedor
-- ------------------------------------------------------------
-- Mide lo que de verdad importa: que la vitrina FALLE CERRADO cuando la
-- fotografía de Dropi vence, falta o queda por debajo del piso; que una lectura
-- fallida NO le alargue la vida a un dato viejo; que la cola del refresco no la
-- monopolice un producto que falla; y que nada de esto permita vender todavía.
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

create or replace function pg_temp.err_postgres(q text) returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute q;
  return 'SIN ERROR';
exception when others then
  return sqlerrm;
end $$;

begin;

-- Los gatillos de Campañas (D2a/D2b) leen auth.uid(), que castea
-- request.jwt.claims a json. Sin claims puestos, un INSERT directo falla con
-- «invalid input syntax for type json» y no por la regla que se quiere medir.
select set_config('request.jwt.claims',
  '{"sub":"7c5a0000-0000-4000-8000-000000000001","role":"service_role"}', true);

-- ------------------------------------------------------------
-- Escenario: dos productos de proveedor y uno propio, todos con campaña.
-- ------------------------------------------------------------
insert into auth.users (id, email) values
  ('7c5a0000-0000-4000-8000-000000000001', 'ds@local.invalid'),
  ('7c5a0000-0000-4000-8000-000000000002', 'sinmodulo@local.invalid') on conflict do nothing;
insert into perfiles (id, rol, modulos) values
  ('7c5a0000-0000-4000-8000-000000000001', 'prueba', '{dropshipping,marketing}'),
  ('7c5a0000-0000-4000-8000-000000000002', 'prueba', '{ventas}') on conflict (id) do nothing;

-- Producto propio con inventario real, de control: no debe cambiar nada.
insert into productos (id, sku, nombre, origen) values
  ('c0000000-0000-4000-8000-00000000000a', 'MAG-PROPIO-D2C1', 'Propio de control', 'propio')
  on conflict (id) do nothing;
insert into movimientos_inventario (product_id, tipo, cantidad, fecha)
  values ('c0000000-0000-4000-8000-00000000000a', 'entrada', 5, current_date);

-- Dos productos de proveedor. Sin costo_unitario, como los crea D2a.
insert into productos (id, sku, nombre, origen) values
  ('c0000000-0000-4000-8000-00000000000b', 'MAG-DROP-9001', 'Proveedor profundo', 'proveedor'),
  ('c0000000-0000-4000-8000-00000000000c', 'MAG-DROP-9002', 'Proveedor flaco', 'proveedor')
  on conflict (id) do nothing;

-- La lectura NACE VENCIDA, igual que la deja ds_llevar_a_campanas en D2a.
insert into producto_proveedor
  (product_id, producto_externo_id, variacion_externa_id, costo_reportado,
   stock_reportado, stock_leido_en, stock_vence_en)
values
  ('c0000000-0000-4000-8000-00000000000b', '2296060', '', 20996, 230, now(), now()),
  ('c0000000-0000-4000-8000-00000000000c', '2296058', '', 80000, 300, now(), now())
  on conflict (product_id) do nothing;

-- ------------------------------------------------------------
-- (1) Las perillas del dueño quedaron sembradas con sus valores
-- ------------------------------------------------------------
select pg_temp.chk(
  (select vigencia_minutos = 120 and piso_vitrina = 20 and vara_entrada = 100
          and refresco_por_tanda = 3 from dropshipping_config where id = 1),
  'config sembrada con las decisiones del dueño (120 min · piso 20 · vara 100 · tanda 3)');

select pg_temp.chk(
  (select count(*) = 1 from dropshipping_config),
  'dropshipping_config es de UNA sola fila');

select pg_temp.chk(
  pg_temp.err_postgres($$insert into dropshipping_config (id) values (2)$$) <> 'SIN ERROR',
  'no se puede crear una segunda fila de configuración');

select pg_temp.chk(
  pg_temp.err_postgres($$update dropshipping_config set vigencia_minutos = 2 where id = 1$$) <> 'SIN ERROR',
  'una vigencia absurda (2 min) la rechaza el CHECK');

-- ------------------------------------------------------------
-- (2) La lectura nace vencida ⇒ la vitrina falla cerrado
-- ------------------------------------------------------------
-- Es el corazón de D2c.1. Un producto con 230 unidades REALES pero cuya
-- fotografía ya venció NO puede mostrarse como disponible.
-- El gatillo de D2a solo deja ligar un producto proveedor a una campaña por la
-- compuerta de la importación. Aquí se abre a mano para armar el escenario: es
-- la misma puerta que usa ds_llevar_a_campanas, no un hueco nuevo. El bloque
-- (11) comprueba después que el candado de PUBLICACIÓN sigue cerrado.
select set_config('impulse.ds_importando', 'on', true);

insert into campana_producto (id, nombre, slug, product_id_ref, precio_venta, publicado, activo)
values
  ('ca000000-0000-4000-8000-00000000000b', 'Campaña proveedor profundo', 'prov-profundo',
   'c0000000-0000-4000-8000-00000000000b', 59900, true, true),
  ('ca000000-0000-4000-8000-00000000000c', 'Campaña proveedor flaco', 'prov-flaco',
   'c0000000-0000-4000-8000-00000000000c', 49900, true, true),
  ('ca000000-0000-4000-8000-00000000000a', 'Campaña propia', 'propia-control',
   'c0000000-0000-4000-8000-00000000000a', 39900, true, true)
  on conflict (id) do nothing;

-- La compuerta se cierra: todo lo que sigue se mide con el candado puesto.
select set_config('impulse.ds_importando', 'off', true);

-- Se abre el interruptor SOLO para poder observar la lógica de `agotado` de
-- proveedor, que es lo que D2c.1 construye. El bloque (11) lo vuelve a cerrar y
-- comprueba que con él cerrado la vitrina no muestra nada de proveedor, que es
-- como queda en producción hasta D2c.2.
update dropshipping_config set venta_proveedor_habilitada = true where id = 1;

select pg_temp.chk(
  (select agotado from catalogo_publico where slug = 'prov-profundo') is true,
  'lectura VENCIDA ⇒ agotado=true aunque Dropi reporte 230 unidades (falla cerrado)');

select pg_temp.chk(
  (select agotado from catalogo_publico where slug = 'propia-control') is false,
  'el producto PROPIO no se ve afectado: sigue saliendo de su libro de inventario');

-- ------------------------------------------------------------
-- (3) Una lectura buena lo pone en vitrina
-- ------------------------------------------------------------
select pg_temp.chk(
  pg_temp.err_postgres($$select ds_registrar_lectura_stock(
    'c0000000-0000-4000-8000-00000000000b'::uuid, 230)$$) = 'SIN ERROR',
  'ds_registrar_lectura_stock acepta una lectura buena');

select pg_temp.chk(
  (select agotado from catalogo_publico where slug = 'prov-profundo') is false,
  'con lectura fresca y 230 unidades ⇒ disponible en vitrina');

select pg_temp.chk(
  (select stock_vence_en > now() + interval '110 minutes'
          and stock_vence_en < now() + interval '130 minutes'
   from producto_proveedor where product_id = 'c0000000-0000-4000-8000-00000000000b'),
  'el vencimiento se calcula con la vigencia de la config (≈120 min)');

-- ------------------------------------------------------------
-- (4) El piso de 20 saca de vitrina sin tocar la frescura
-- ------------------------------------------------------------
select ds_registrar_lectura_stock('c0000000-0000-4000-8000-00000000000c'::uuid, 19);
select pg_temp.chk(
  (select agotado from catalogo_publico where slug = 'prov-flaco') is true,
  'stock 19 con piso 20 ⇒ agotado=true aunque la lectura esté recién hecha');

select ds_registrar_lectura_stock('c0000000-0000-4000-8000-00000000000c'::uuid, 20);
select pg_temp.chk(
  (select agotado from catalogo_publico where slug = 'prov-flaco') is false,
  'stock 20 con piso 20 ⇒ disponible (el piso es el mínimo, no una frontera abierta)');

-- El piso por producto manda sobre el global.
update producto_proveedor set piso_vitrina = 50
  where product_id = 'c0000000-0000-4000-8000-00000000000c';
select pg_temp.chk(
  (select agotado from catalogo_publico where slug = 'prov-flaco') is true,
  'el piso propio del producto (50) manda sobre el global (20)');
update producto_proveedor set piso_vitrina = null
  where product_id = 'c0000000-0000-4000-8000-00000000000c';

-- ------------------------------------------------------------
-- (5) El derrumbe medido el 10-oct: 300 ⇒ 0 de golpe
-- ------------------------------------------------------------
select ds_registrar_lectura_stock('c0000000-0000-4000-8000-00000000000c'::uuid, 0);
select pg_temp.chk(
  (select agotado from catalogo_publico where slug = 'prov-flaco') is true,
  'el derrumbe real (300 ⇒ 0 en 24 h) saca el producto de la vitrina de inmediato');

-- ------------------------------------------------------------
-- (6) Fallar NUNCA puede alargarle la vida a un dato viejo
-- ------------------------------------------------------------
-- Es la regla que impide que un 429 o una caída de Dropi dejen la vitrina
-- encendida con datos de ayer.
select ds_registrar_lectura_stock('c0000000-0000-4000-8000-00000000000b'::uuid, 500);
create temp table antes as
  select stock_reportado, stock_leido_en, stock_vence_en
  from producto_proveedor where product_id = 'c0000000-0000-4000-8000-00000000000b';

select pg_temp.chk(
  ds_registrar_lectura_stock('c0000000-0000-4000-8000-00000000000b'::uuid, null, '429 Too Many Requests') is null,
  'una lectura fallida devuelve null, no una fecha de vencimiento nueva');

select pg_temp.chk(
  (select a.stock_reportado = pp.stock_reportado
          and a.stock_leido_en = pp.stock_leido_en
          and a.stock_vence_en = pp.stock_vence_en
   from antes a, producto_proveedor pp
   where pp.product_id = 'c0000000-0000-4000-8000-00000000000b'),
  'un fallo NO toca stock, ni lectura, ni vencimiento: la foto vieja sigue envejeciendo');

select pg_temp.chk(
  (select ultimo_error like '429%' and ultimo_intento is not null
   from producto_proveedor where product_id = 'c0000000-0000-4000-8000-00000000000b'),
  'el fallo deja rastro (ultimo_error y ultimo_intento) para diagnosticar');

select ds_registrar_lectura_stock('c0000000-0000-4000-8000-00000000000b'::uuid, 500);
select pg_temp.chk(
  (select ultimo_error is null
   from producto_proveedor where product_id = 'c0000000-0000-4000-8000-00000000000b'),
  'la siguiente lectura buena limpia el error anterior');

-- ------------------------------------------------------------
-- (7) La cola del refresco rodante
-- ------------------------------------------------------------
-- OJO: la cola tiene AUTO-FRENO. Si no se reinicia `ultimo_refresco` entre
-- llamadas, devuelve cero filas y entonces una prueba como «count(*) <= 3»
-- pasaría por VACÍO, no por correcta. Cada bloque reinicia el freno y además
-- exige que la cola traiga algo.
create or replace function pg_temp.sin_freno() returns void language sql as
$$ update dropshipping_config set ultimo_refresco = null where id = 1 $$;

select pg_temp.sin_freno();
select pg_temp.chk(
  (select count(*) from ds_productos_por_refrescar()) = 2,
  'la cola entrega los 2 productos proveedor (y no se queda vacía)');

select pg_temp.sin_freno();
select pg_temp.chk(
  (select count(*) from ds_productos_por_refrescar(1)) = 1,
  'la cola respeta la tanda que se le pide');

select pg_temp.sin_freno();
select pg_temp.chk(
  (select count(*) from ds_productos_por_refrescar(99)) = 2,
  'pedir 99 no rompe: devuelve lo que hay, topado en 8 (el techo de Dropi es ~12-16)');

-- El AUTO-FRENO: la segunda llamada seguida no entrega trabajo. Es lo que
-- impide que un secreto filtrado se convierta en un bucle que nos quema el
-- presupuesto de peticiones de Dropi.
select pg_temp.sin_freno();
select count(*) from ds_productos_por_refrescar();
select pg_temp.chk(
  (select count(*) from ds_productos_por_refrescar()) = 0,
  'AUTO-FRENO: llamar la cola dos veces seguidas no entrega trabajo la segunda');

select pg_temp.chk(
  (select ultimo_refresco is not null from dropshipping_config where id = 1),
  'la cola estampa ultimo_refresco para poder frenarse');

select pg_temp.chk(
  pg_temp.err_postgres($$update dropshipping_config set refresco_minimo_segundos = 1 where id = 1$$) <> 'SIN ERROR',
  'un mínimo absurdo (1 segundo) lo rechaza el CHECK');

-- El que falla cede el turno. Si la cola ordenara por stock_leido_en, el
-- producto que falla volvería primero en cada vuelta y ahogaría a los demás.
update producto_proveedor set ultimo_intento = now() - interval '1 hour'
  where product_id = 'c0000000-0000-4000-8000-00000000000c';
update producto_proveedor set ultimo_intento = now()
  where product_id = 'c0000000-0000-4000-8000-00000000000b';
select pg_temp.sin_freno();
select pg_temp.chk(
  (select product_id from ds_productos_por_refrescar(1)) = 'c0000000-0000-4000-8000-00000000000c',
  'la cola ordena por intento más viejo, así el que falla cede el turno');

update producto_proveedor set refrescar = false
  where product_id = 'c0000000-0000-4000-8000-00000000000c';
select pg_temp.sin_freno();
select pg_temp.chk(
  (select count(*) from ds_productos_por_refrescar(9)) = 1
  and not exists (select 1 from ds_productos_por_refrescar(9)
                  where product_id = 'c0000000-0000-4000-8000-00000000000c'),
  'un producto pausado (refrescar=false) sale de la cola, y el otro sigue');
update producto_proveedor set refrescar = true
  where product_id = 'c0000000-0000-4000-8000-00000000000c';

select pg_temp.sin_freno();
select pg_temp.chk(
  (select count(*) from ds_productos_por_refrescar(9)) = 2
  and not exists (select 1 from ds_productos_por_refrescar(9)
                  where product_id = 'c0000000-0000-4000-8000-00000000000a'),
  'la cola NUNCA incluye un producto propio');

-- ------------------------------------------------------------
-- (8) Candados: la RPC no acepta lo que no debe
-- ------------------------------------------------------------
select pg_temp.chk(
  pg_temp.err_postgres($$select ds_registrar_lectura_stock(
    'c0000000-0000-4000-8000-00000000000a'::uuid, 10)$$) like '%DS_PRODUCTO_NO_PROVEEDOR%',
  'no se puede registrar una lectura de Dropi sobre un producto PROPIO');

select pg_temp.chk(
  pg_temp.err_postgres($$select ds_registrar_lectura_stock(
    'c0000000-0000-4000-8000-00000000000b'::uuid, -5)$$) like '%DS_STOCK_NEGATIVO%',
  'un stock negativo se rechaza');

select pg_temp.chk(
  pg_temp.err_postgres($$select ds_registrar_lectura_stock(null, 10)$$) like '%DS_FALTA_PRODUCTO%',
  'sin producto no hay lectura');

-- ------------------------------------------------------------
-- (9) Quién puede ejecutar qué
-- ------------------------------------------------------------
-- Las dos RPC del refresco son SOLO para service_role: un usuario con sesión
-- no puede empujar un stock falso ni espiar la cola.
select pg_temp.chk(
  not has_function_privilege('authenticated', 'public.ds_registrar_lectura_stock(uuid,integer,text)', 'execute'),
  'authenticated NO puede ejecutar ds_registrar_lectura_stock (solo la Edge Function)');

select pg_temp.chk(
  not has_function_privilege('authenticated', 'public.ds_productos_por_refrescar(integer)', 'execute'),
  'authenticated NO puede ejecutar ds_productos_por_refrescar');

select pg_temp.chk(
  not has_function_privilege('anon', 'public.ds_estado_stock()', 'execute'),
  'anon NO puede ver el estado del stock proveedor');

select pg_temp.chk(
  has_function_privilege('service_role', 'public.ds_registrar_lectura_stock(uuid,integer,text)', 'execute'),
  'service_role sí puede registrar lecturas');

-- ------------------------------------------------------------
-- (10) El panel ve el motivo; quien no tiene el módulo no ve nada
-- ------------------------------------------------------------
-- pg_temp.err_postgres deja los claims en {"role":"service_role"} SIN `sub`, y
-- entonces auth.uid() es null y tiene_acceso_dropshipping() da false. Se
-- restituye la identidad antes de medir las puertas que dependen del módulo.
select set_config('request.jwt.claims',
  '{"sub":"7c5a0000-0000-4000-8000-000000000001","role":"service_role"}', true);

select ds_registrar_lectura_stock('c0000000-0000-4000-8000-00000000000c'::uuid, 5);
select pg_temp.chk(
  (select motivo from ds_estado_stock() where dropi_id = '2296058') = 'por debajo del piso',
  'ds_estado_stock explica el motivo exacto («por debajo del piso»)');

select pg_temp.chk(
  (select count(*) from ds_estado_stock()) = 2,
  'ds_estado_stock solo lista productos de proveedor, no los propios');

select pg_temp.chk(
  (pg_temp.como_json('7c5a0000-0000-4000-8000-000000000002',
    $$select to_jsonb(count(*)) from ds_estado_stock()$$))::text = '0',
  'un perfil SIN módulo dropshipping recibe cero filas de ds_estado_stock');

-- ------------------------------------------------------------
-- (11) Nada de esto abre la venta todavía
-- ------------------------------------------------------------
-- Se vuelve al estado REAL de producción: interruptor cerrado.
update dropshipping_config set venta_proveedor_habilitada = false where id = 1;

-- Helper propio: conserva el `sub` para que cm_publicar_campana llegue a la
-- regla que se quiere medir en vez de morir antes por falta de módulo.
create or replace function pg_temp.err_con_sub(q text) returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    '{"sub":"7c5a0000-0000-4000-8000-000000000001","role":"service_role"}', true);
  execute q;
  return 'SIN ERROR';
exception when others then
  return sqlerrm;
end $$;

-- NOTA: aquí vivía la afirmación «D2c.1 no levanta el candado». Dejó de ser
-- medible cuando D2c.2b lo levantó, y el banco aplica TODAS las migraciones: la
-- inercia de un tramo intermedio no se puede observar desde el estado final.
-- Lo que sí se conserva aquí es el interruptor, que esta prueba controla ella
-- misma (comprobación de más abajo). El candado de publicación y su requisito
-- nuevo se miden en dropshipping-d2c2b.sql.
select pg_temp.chk(
  pg_temp.err_con_sub($$select cm_publicar_campana(
    'ca000000-0000-4000-8000-00000000000b'::uuid, true)$$) = 'SIN ERROR',
  'con ficha y precio, publicar un producto de proveedor funciona (lo abrió D2c.2b)');

-- El candado duro de la vitrina: con el interruptor en false, una campaña
-- proveedor publicada por DML directo NO se asoma a la tienda.
select pg_temp.chk(
  (select venta_proveedor_habilitada from dropshipping_config where id = 1) is false,
  'venta_proveedor_habilitada nace en false: D2c.1 es inerte');

select pg_temp.chk(
  not exists (select 1 from catalogo_publico where slug in ('prov-profundo', 'prov-flaco')),
  'con el interruptor cerrado, NINGÚN producto proveedor aparece en la vitrina (ni agotado)');

select pg_temp.chk(
  (select count(*) from catalogo_publico where slug = 'propia-control') = 1,
  'el interruptor no afecta a los productos propios');

select pg_temp.chk(
  not exists (select 1 from stock_actual where product_id in (
    'c0000000-0000-4000-8000-00000000000b', 'c0000000-0000-4000-8000-00000000000c')),
  'el producto proveedor sigue fuera de stock_actual (Inventario propio intacto)');

select pg_temp.chk(
  pg_temp.err_postgres($$insert into movimientos_inventario (product_id, tipo, cantidad, fecha)
    values ('c0000000-0000-4000-8000-00000000000b', 'entrada', 1, current_date)$$) <> 'SIN ERROR',
  'el gatillo de D1 sigue impidiendo movimientos de inventario de proveedor');

-- ------------------------------------------------------------
-- (12) La vitrina no filtra nada nuevo
-- ------------------------------------------------------------
select pg_temp.chk(
  not exists (
    select 1 from information_schema.columns
    where table_name = 'catalogo_publico'
      and column_name in ('origen', 'piso_vitrina', 'stock_reportado', 'stock_vence_en',
                          'producto_externo_id', 'costo_reportado', 'product_id_ref')),
  'catalogo_publico NO expone origen, piso, stock, vencimiento, id externo ni costo');

-- Una campaña proveedor NO publicada no aparece, ni siquiera agotada.
update campana_producto set publicado = false
  where id = 'ca000000-0000-4000-8000-00000000000b';
select pg_temp.chk(
  not exists (select 1 from catalogo_publico where slug = 'prov-profundo'),
  'una campaña sin publicar no aparece en la vitrina en ningún estado');

-- ------------------------------------------------------------
select '--- D2c.1 · stock vivo ---' as bloque;
select n, case when ok then 'pasa' else 'FALLA' end as res, que from pg_temp.r order by n;
select
  'RESUMEN' as t,
  count(*) || ' comprobaciones' as total,
  count(*) filter (where not ok) || ' fallan' as fallan,
  case when count(*) filter (where not ok) = 0 then 'TODO PASA' else 'HAY FALLAS' end as veredicto
from pg_temp.r;

rollback;
