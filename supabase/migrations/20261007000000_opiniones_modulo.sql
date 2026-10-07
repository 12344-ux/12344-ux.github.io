-- ============================================================
-- Magandhi Corporation · Software de Opiniones (reseñas de clientes)
-- ------------------------------------------------------------
-- POR QUE EXISTE: la curaduria + la CONFIANZA son el moat de MAGANDHI. Una
-- opinion anonima que cualquiera deja no vale nada y se huele a trucada; una
-- opinion VERIFICADA (de quien si compro, si recibio, si uso el producto) es
-- prueba social real. Este modulo convierte cada opinion en prueba verificada
-- y le da seguimiento interno (responder, moderar) sin romper la honestidad.
--
-- EL CANDADO (decision del dueno + regla dura del proyecto): como la tienda no
-- tiene login, la tabla de opiniones NUNCA acepta escritura publica directa (si
-- anon pudiera insertar, cualquiera inyecta reseñas falsas). En su lugar:
--   1) cada PEDIDO lleva un CODIGO DE RESEÑA unico e imposible de adivinar
--      (columna pedidos.codigo_resena, generada por trigger al crear el pedido);
--   2) el cliente opina en la tienda con ese codigo;
--   3) una Edge Function server-side (enviar-opinion) llama al RPC
--      op_registrar_opinion (security definer), que valida el codigo, confirma
--      que el pedido fue ENTREGADO y que el producto pertenecia a ese pedido, e
--      inserta UNA sola opinion por producto-pedido (quema el codigo para ese
--      producto). El codigo NO autentica por login: autentica por POSESION del
--      codigo del pedido. Por eso op_registrar_opinion NO pide tiene_modulo.
--
-- COHERENCIA DEL PROMEDIO (decision del dueno 2026-10-07): el numero grande que
-- ve el cliente es el PROMEDIO REAL (avg de estrellas), redondeado a 1 decimal,
-- SIEMPRE acompanado del total (N). Si hay 1 opinion de 5 estrellas, arriba dice
-- "5.0 · 1 opinion": no mentimos, el N avisa que es una sola. NO se usa media
-- bayesiana ni suavizado: romperia la coherencia con las tarjetas visibles.
--
-- ENTREGA DEL CODIGO AL CLIENTE (fase siguiente, NO en este archivo): el codigo
-- ya existe en cada pedido desde que se crea. Hacerlo LLEGAR al cliente (en el
-- ultimo correo de seguimiento/entrega) es la fase que sigue; hasta montarla no
-- entran opiniones reales. El motor queda listo y probable desde hoy.
--
-- MODERACION CON CONTROL DE MARCA (decision del dueno): las opiniones
-- verificadas se publican AUTOMATICAMENTE. El panel puede "borrar" una opinion,
-- pero -coherente con todo el proyecto: nada se borra en silencio- el borrado es
-- un OCULTAR con bitacora (oculta=true + quien/cuando/por que), reversible. Da
-- control de marca sin perder integridad ni dejar al negocio sin defensa ante
-- una disputa. Una opinion oculta no cuenta en el promedio ni se muestra en web.
--
-- MONTOS/CANTIDADES: no aplica (sin dinero aqui). Estrellas = smallint 1..5.
-- IDEMPOTENTE: if not exists / create or replace / unique por pedido-producto.
-- REQUISITO: correr DESPUES de pedidos, pedido_items, productos, campana_producto
-- (con slug + product_id_ref) y perfiles/tiene_modulo. No reescribe ni recrea
-- catalogo_publico (no toca sus grants).
-- ============================================================


-- ============================================================
-- BLOQUE 1 · CODIGO DE RESEÑA POR PEDIDO
-- Un codigo unico, legible y copiable (ej. "MG-A3F09B7C21"), imposible de
-- adivinar, generado automaticamente al crear cualquier pedido (manual hoy, web
-- manana con Wompi F2, sin tocar crear_pedido: lo pone un trigger). Es la unica
-- llave que habilita opinar; viaja al cliente por correo (fase siguiente) y
-- JAMAS se expone en catalogo_publico ni a anon.
-- ============================================================

alter table pedidos add column if not exists codigo_resena text;

comment on column pedidos.codigo_resena is 'Codigo de reseña unico e imposible de adivinar de ESTE pedido. Habilita al cliente a opinar (via Edge Function enviar-opinion + op_registrar_opinion). Se genera por trigger al crear el pedido. Secreto por pedido: viaja al cliente por correo (fase siguiente) y NUNCA se expone a anon.';

-- Unicidad del codigo (parcial: solo donde no es null).
create unique index if not exists pedidos_codigo_resena_uidx
  on pedidos (codigo_resena)
  where codigo_resena is not null;

-- Generador de codigo unico. 10 hex en mayuscula desde un uuid aleatorio, con
-- prefijo de marca "MG-". Reintenta ante colision (practicamente imposible, pero
-- la unicidad queda garantizada). No necesita grants: lo invoca el trigger (que
-- corre como el dueno de la tabla) y las default privileges del proyecto ya lo
-- cierran para anon/authenticated.
create or replace function op_generar_codigo_resena()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  v_codigo text;
begin
  loop
    v_codigo := 'MG-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    exit when not exists (select 1 from pedidos where codigo_resena = v_codigo);
  end loop;
  return v_codigo;
end;
$$;

comment on function op_generar_codigo_resena() is 'Genera un codigo de reseña unico (MG-XXXXXXXXXX). Lo usa el trigger de pedidos y el backfill. No se otorga a anon/authenticated.';

-- Trigger: asigna el codigo al crear el pedido si no viene puesto. Se dispara en
-- cualquier insert (crear_pedido manual o web futuro) sin modificar esa RPC.
create or replace function op_pedidos_asignar_codigo()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.codigo_resena is null then
    new.codigo_resena := op_generar_codigo_resena();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_pedidos_codigo_resena on pedidos;
create trigger trg_pedidos_codigo_resena
  before insert on pedidos
  for each row
  execute function op_pedidos_asignar_codigo();

-- Backfill: los pedidos ya existentes tambien reciben codigo (el trigger solo
-- cubre inserts nuevos). Idempotente: solo toca los que aun no tienen.
update pedidos set codigo_resena = op_generar_codigo_resena()
  where codigo_resena is null;


-- ============================================================
-- BLOQUE 2 · TABLA opiniones (el HECHO)
-- Una fila por opinion verificada. Guarda la fecha (creado), el autor tal como
-- quiso aparecer, la respuesta de la marca, y la bitacora de ocultamiento. El
-- promedio y los conteos se DERIVAN (vistas), igual que en todo el proyecto.
-- ============================================================

create table if not exists opiniones (
  id            uuid primary key default gen_random_uuid(),
  pedido_id     uuid not null references pedidos(id),
  product_id    uuid not null references productos(id),
  estrellas     smallint not null check (estrellas between 1 and 5),
  comentario    text check (comentario is null or char_length(comentario) <= 1000),
  autor_nombre  text not null check (char_length(btrim(autor_nombre)) between 1 and 40),
  -- respuesta de la marca (publica, opcional)
  respuesta     text check (respuesta is null or char_length(respuesta) <= 1000),
  respuesta_en  timestamptz,
  respuesta_por uuid references auth.users(id),
  -- "borrado" con control de marca = ocultar con bitacora (reversible)
  oculta        boolean not null default false,
  oculta_en     timestamptz,
  oculta_por    uuid references auth.users(id),
  oculta_motivo text,
  -- marcador de prueba: excluye del promedio/total reales (el dueno prueba el flujo)
  es_prueba     boolean not null default false,
  creado        timestamptz not null default now(),   -- LA FECHA de la opinion
  creado_por    uuid default auth.uid(),
  constraint opiniones_una_por_pedido_producto unique (pedido_id, product_id)
);

comment on table opiniones is 'Opiniones verificadas de clientes (una por producto-pedido). Se escriben SOLO via op_registrar_opinion (Edge Function con codigo del pedido). El promedio/total se derivan en producto_rating_publico. Nada se borra: "borrar" = oculta=true con bitacora.';
comment on column opiniones.autor_nombre is 'Como quiso aparecer el cliente (ej. su primer nombre). Lo que ve el publico; no es PII adicional.';
comment on column opiniones.oculta is 'Control de marca: true saca la opinion de la web y del promedio, con bitacora (oculta_en/por/motivo). Reversible. Nada se borra en silencio.';
comment on column opiniones.es_prueba is 'true = opinion de prueba del dueno; se EXCLUYE del promedio/total reales y de la web.';

create index if not exists opiniones_product_creado_idx on opiniones (product_id, creado);
create index if not exists opiniones_creado_idx on opiniones (creado);


-- ============================================================
-- BLOQUE 3 · RLS Y ACCESO INTERNO
-- Lectura interna solo para quien tenga el modulo 'opiniones'. Escritura: cero
-- policies -> solo por RPC security definer. anon: nada (ni lee ni escribe).
-- ============================================================

create or replace function tiene_acceso_opiniones()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select tiene_modulo('opiniones');
$$;

comment on function tiene_acceso_opiniones() is 'Acceso al Software de Opiniones: admin o modulo opiniones. Espejo de tiene_acceso_ventas/marketing/inventario.';

-- Las default privileges del proyecto (tramo 0) revocan execute de
-- anon/authenticated en funciones nuevas; hay que re-otorgar a quien la usa en
-- policies (authenticated) y a service_role (Edge Functions / RPC server-side).
revoke execute on function tiene_acceso_opiniones() from public;
grant execute on function tiene_acceso_opiniones() to authenticated, service_role;

alter table opiniones enable row level security;

drop policy if exists opiniones_select_panel on opiniones;
create policy opiniones_select_panel on opiniones
  for select
  to authenticated
  using (tiene_acceso_opiniones());

-- RLS necesita grant de tabla para que el rol siquiera alcance la policy.
grant select on opiniones to authenticated;


-- ============================================================
-- BLOQUE 4 · SUPERFICIES PUBLICAS (lo que lee la tienda, por slug, sin login)
-- Vistas security definer (como catalogo_publico): corren como su dueno, anon
-- solo recibe columnas publicas de opiniones NO ocultas y NO de prueba, de
-- productos con campania publicada+activa. Jamas exponen pedido_id, product_id,
-- creado_por, el id de la opinion, es_prueba ni la bitacora de ocultamiento.
-- ============================================================

-- 4.1 · opiniones individuales (para el grid de tarjetas y el "ver todas")
create or replace view opiniones_publicas as
select
  cp.slug         as slug,
  o.estrellas     as estrellas,
  o.comentario    as comentario,
  o.autor_nombre  as autor_nombre,
  o.respuesta     as respuesta,
  o.respuesta_en  as respuesta_en,
  o.creado        as creado
from opiniones o
join campana_producto cp on cp.product_id_ref = o.product_id
where o.oculta = false
  and o.es_prueba = false
  and cp.publicado = true
  and cp.activo = true;

comment on view opiniones_publicas is 'OPINIONES · superficie publica por slug para la tienda (magandhi.com) sin login. Solo opiniones NO ocultas, NO de prueba, de campanias publicadas+activas, y SOLO columnas publicas (estrellas, comentario, autor, respuesta de marca, fecha). JAMAS expone pedido_id, product_id, id, creado_por, es_prueba ni la bitacora. La tienda ordena/limita del lado del cliente.';

-- 4.2 · agregado por producto: promedio REAL + total + distribucion
-- El promedio es avg(estrellas) a 1 decimal (coherente con las tarjetas, sin
-- bayesiano). El total (N) va SIEMPRE con el promedio para no inflar con pocas.
create or replace view producto_rating_publico as
select
  cp.slug as slug,
  count(*)::int                                        as total,
  round(avg(o.estrellas)::numeric, 1)                  as promedio,
  count(*) filter (where o.estrellas = 5)::int         as estrellas_5,
  count(*) filter (where o.estrellas = 4)::int         as estrellas_4,
  count(*) filter (where o.estrellas = 3)::int         as estrellas_3,
  count(*) filter (where o.estrellas = 2)::int         as estrellas_2,
  count(*) filter (where o.estrellas = 1)::int         as estrellas_1
from opiniones o
join campana_producto cp on cp.product_id_ref = o.product_id
where o.oculta = false
  and o.es_prueba = false
  and cp.publicado = true
  and cp.activo = true
group by cp.slug;

comment on view producto_rating_publico is 'OPINIONES · agregado publico por slug: total (N), promedio REAL a 1 decimal (sin bayesiano, por coherencia), y distribucion por estrella. Solo opiniones visibles de campanias publicadas+activas. La tienda muestra estado vacio hasta total>=1.';

grant select on opiniones_publicas       to anon, authenticated, service_role;
grant select on producto_rating_publico  to anon, authenticated, service_role;


-- ============================================================
-- BLOQUE 5 · RPC DE ESCRITURA PUBLICA (la Edge Function la invoca con service_role)
-- op_registrar_opinion: unica puerta de entrada de una opinion. Valida el codigo
-- del pedido, el estado ENTREGADO, que el producto pertenezca al pedido y la
-- unicidad por producto-pedido. NO pide tiene_modulo: la autorizacion es la
-- POSESION del codigo. Lanza excepciones con codigos estables que la Edge
-- Function traduce a mensajes amables.
-- ============================================================

create or replace function op_registrar_opinion(
  p_codigo     text,
  p_slug       text,
  p_estrellas  int,
  p_comentario text,
  p_autor      text,
  p_es_prueba  boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pedido     pedidos%rowtype;
  v_product_id uuid;
  v_autor      text;
  v_coment     text;
  v_id         uuid;
begin
  -- normalizacion y validacion de entradas
  if p_codigo is null or btrim(p_codigo) = '' then
    raise exception 'OPINION_CODIGO_REQUERIDO';
  end if;
  if p_estrellas is null or p_estrellas < 1 or p_estrellas > 5 then
    raise exception 'OPINION_ESTRELLAS_INVALIDAS';
  end if;
  v_autor := btrim(coalesce(p_autor, ''));
  if v_autor = '' then
    raise exception 'OPINION_AUTOR_REQUERIDO';
  end if;
  v_autor  := substr(v_autor, 1, 40);
  v_coment := nullif(btrim(coalesce(p_comentario, '')), '');
  if v_coment is not null then
    v_coment := substr(v_coment, 1, 1000);
  end if;

  -- 1) el codigo debe existir (identifica el pedido)
  select * into v_pedido
    from pedidos
   where codigo_resena = upper(btrim(p_codigo))
   limit 1;
  if not found then
    raise exception 'OPINION_CODIGO_INVALIDO';
  end if;

  -- 2) el pedido debe estar ENTREGADO (y no anulado): solo opina quien recibio
  if v_pedido.anulado or v_pedido.estado <> 'entregado' then
    raise exception 'OPINION_PEDIDO_NO_ENTREGADO';
  end if;

  -- 3) resolver el producto por su slug publico (campania publicada y activa)
  select product_id_ref into v_product_id
    from campana_producto
   where slug = p_slug
     and publicado = true
     and activo = true
     and product_id_ref is not null
   limit 1;
  if v_product_id is null then
    raise exception 'OPINION_PRODUCTO_INVALIDO';
  end if;

  -- 4) ese producto debe pertenecer a ESTE pedido
  if not exists (
    select 1 from pedido_items
     where pedido_id = v_pedido.id
       and product_id = v_product_id
  ) then
    raise exception 'OPINION_PRODUCTO_NO_EN_PEDIDO';
  end if;

  -- 5) una sola opinion por producto-pedido (ademas del unique de la tabla)
  if exists (
    select 1 from opiniones
     where pedido_id = v_pedido.id
       and product_id = v_product_id
  ) then
    raise exception 'OPINION_YA_REGISTRADA';
  end if;

  insert into opiniones (pedido_id, product_id, estrellas, comentario, autor_nombre, es_prueba)
  values (v_pedido.id, v_product_id, p_estrellas, v_coment, v_autor, coalesce(p_es_prueba, false))
  returning id into v_id;

  return v_id;
end;
$$;

comment on function op_registrar_opinion(text, text, int, text, text, boolean) is 'Unica puerta de escritura de opiniones. Autoriza por POSESION del codigo del pedido (no por login). Valida codigo, estado entregado, pertenencia del producto al pedido y unicidad. La invoca la Edge Function enviar-opinion con service_role.';

-- Solo service_role la ejecuta (la Edge Function). anon/authenticated no.
revoke execute on function op_registrar_opinion(text, text, int, text, text, boolean) from public;
grant  execute on function op_registrar_opinion(text, text, int, text, text, boolean) to service_role;


-- ============================================================
-- BLOQUE 6 · RPC DE PANEL (las usa el back-office autenticado con modulo opiniones)
-- Leer/moderar/responder via funciones security definer guardadas por
-- tiene_acceso_opiniones(), para no chocar con la RLS de productos/campanas de
-- otros modulos (patron del proyecto: leer lo sensible por RPC definer guardado).
-- ============================================================

-- 6.1 · resumen por producto, ORDENADO por la reseña mas reciente primero
-- (el producto que acaban de opinar sube arriba, como pidio el dueno).
create or replace function op_resumen_productos()
returns table (
  product_id    uuid,
  nombre        text,
  sku           text,
  slug          text,
  total         int,
  promedio      numeric,
  ultima        timestamptz,
  sin_responder int,
  ocultas       int,
  pruebas       int
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not tiene_acceso_opiniones() then
    raise exception 'SIN_ACCESO_OPINIONES';
  end if;

  return query
    select
      p.id,
      p.nombre,
      p.sku,
      (select cp.slug
         from campana_producto cp
        where cp.product_id_ref = p.id and cp.activo = true
        order by cp.publicado desc, cp.creado desc
        limit 1) as slug,
      count(*) filter (where o.oculta = false and o.es_prueba = false)::int as total,
      round(avg(o.estrellas) filter (where o.oculta = false and o.es_prueba = false)::numeric, 1) as promedio,
      max(o.creado) as ultima,
      count(*) filter (where o.oculta = false and o.es_prueba = false and o.respuesta is null)::int as sin_responder,
      count(*) filter (where o.oculta = true)::int as ocultas,
      count(*) filter (where o.es_prueba = true)::int as pruebas
    from opiniones o
    join productos p on p.id = o.product_id
    group by p.id, p.nombre, p.sku
    order by max(o.creado) desc;
end;
$$;

comment on function op_resumen_productos() is 'Panel de Opiniones: lista de productos CON opiniones, ordenada por la reseña mas reciente primero. Promedio/total sobre opiniones visibles (no ocultas, no prueba); ademas conteos de sin_responder, ocultas y pruebas. Guardada por tiene_acceso_opiniones().';

-- 6.2 · todas las opiniones de un producto, de MAS ANTIGUA A MAS RECIENTE
-- (incluye ocultas y pruebas: el panel necesita verlas para moderar/responder).
create or replace function op_opiniones_producto(p_product_id uuid)
returns table (
  id            uuid,
  estrellas     smallint,
  comentario    text,
  autor_nombre  text,
  respuesta     text,
  respuesta_en  timestamptz,
  oculta        boolean,
  oculta_motivo text,
  es_prueba     boolean,
  creado        timestamptz,
  pedido_id     uuid
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not tiene_acceso_opiniones() then
    raise exception 'SIN_ACCESO_OPINIONES';
  end if;

  return query
    select o.id, o.estrellas, o.comentario, o.autor_nombre, o.respuesta, o.respuesta_en,
           o.oculta, o.oculta_motivo, o.es_prueba, o.creado, o.pedido_id
      from opiniones o
     where o.product_id = p_product_id
     order by o.creado asc;
end;
$$;

comment on function op_opiniones_producto(uuid) is 'Panel: todas las opiniones de un producto, de mas antigua a mas reciente (incluye ocultas y pruebas, para moderar/responder). Guardada por tiene_acceso_opiniones().';

-- 6.3 · responder una opinion (respuesta publica de la marca). Vacio => quita la respuesta.
create or replace function op_responder_opinion(p_id uuid, p_respuesta text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_resp text;
begin
  if not tiene_acceso_opiniones() then
    raise exception 'SIN_ACCESO_OPINIONES';
  end if;
  v_resp := nullif(btrim(coalesce(p_respuesta, '')), '');
  if v_resp is not null then
    v_resp := substr(v_resp, 1, 1000);
  end if;

  update opiniones
     set respuesta     = v_resp,
         respuesta_en  = case when v_resp is null then null else now() end,
         respuesta_por = case when v_resp is null then null else auth.uid() end
   where id = p_id;

  if not found then
    raise exception 'OPINION_NO_ENCONTRADA';
  end if;
end;
$$;

comment on function op_responder_opinion(uuid, text) is 'Panel: agrega/edita/quita la respuesta publica de la marca a una opinion. Guardada por tiene_acceso_opiniones().';

-- 6.4 · "borrar" = ocultar con bitacora (reversible). Nada se borra en silencio.
create or replace function op_ocultar_opinion(p_id uuid, p_oculta boolean, p_motivo text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_oculta boolean := coalesce(p_oculta, true);
begin
  if not tiene_acceso_opiniones() then
    raise exception 'SIN_ACCESO_OPINIONES';
  end if;

  update opiniones
     set oculta        = v_oculta,
         oculta_en     = case when v_oculta then now()        else null end,
         oculta_por    = case when v_oculta then auth.uid()   else null end,
         oculta_motivo = case when v_oculta then nullif(btrim(coalesce(p_motivo, '')), '') else null end
   where id = p_id;

  if not found then
    raise exception 'OPINION_NO_ENCONTRADA';
  end if;
end;
$$;

comment on function op_ocultar_opinion(uuid, boolean, text) is 'Panel: "borrar" una opinion = ocultarla (oculta=true) con bitacora (quien/cuando/por que), reversible. Una opinion oculta sale de la web y del promedio pero no se destruye.';

-- Grants de ejecucion para el back-office autenticado (las default privileges del
-- proyecto ya cerraron estas funciones a anon/authenticated al crearlas).
revoke execute on function op_resumen_productos()                 from public;
revoke execute on function op_opiniones_producto(uuid)            from public;
revoke execute on function op_responder_opinion(uuid, text)       from public;
revoke execute on function op_ocultar_opinion(uuid, boolean, text) from public;

grant execute on function op_resumen_productos()                  to authenticated, service_role;
grant execute on function op_opiniones_producto(uuid)             to authenticated, service_role;
grant execute on function op_responder_opinion(uuid, text)        to authenticated, service_role;
grant execute on function op_ocultar_opinion(uuid, boolean, text) to authenticated, service_role;


-- ============================================================
-- NOTA DE ACCESO (modulo 'opiniones'): el admin (rol='admin') ya tiene todos los
-- modulos via tiene_modulo(), asi que no requiere cambio de datos. Para delegar a
-- futuro un usuario no-admin que solo gestione opiniones, agregar 'opiniones' a
-- su perfiles.modulos (D3, con service_role, sin tocar este esquema).
-- ============================================================
