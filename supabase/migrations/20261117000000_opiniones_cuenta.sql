-- ============================================================================
-- MAGANDHI · Opiniones con cuenta
-- ----------------------------------------------------------------------------
-- Decisiones del dueño (24-oct-2026):
--   · Quien tiene sesión opina sobre productos de pedidos ENTREGADOS, sin
--     código de reseña ni campo de nombre.
--   · Una sola opinión por cuenta para cada producto, aunque lo compre varias
--     veces. La regla se impone aquí, sin anunciarla en la tienda.
--   · El nombre público lo arma MAGANDHI con el nombre de la cuenta: el campo
--     «Nombre y apellido» del registro o el que entrega Google. Se publica
--     como «Nombre I.». Si la cuenta no tiene un nombre válido, se publica
--     «Cliente MAGANDHI».
--   · La persona puede editar o eliminar su opinión. Eliminar la retira de la
--     tienda, del promedio y de Métricas y le devuelve la opción de opinar.
--   · Si MAGANDHI ocultó la opinión, la cuenta no puede editarla ni
--     eliminarla: así no se salta la moderación.
--   · El código de reseña del correo sigue funcionando para invitados, pero
--     ahora respeta una opinión por cliente y producto.
--
-- Nada se borra en silencio: editar guarda la versión anterior y retirar
-- mueve la fila completa a opiniones_historial, que es de solo inserción.
-- Mover la fila (en vez de marcarla) deja intactas todas las lecturas
-- existentes de opiniones: vistas públicas, Métricas, Email marketing, SN1 y
-- Mis compras dejan de contarla sin redefinirse.
--
-- No toca pagos, carrito, inventario, pedidos ni Mis compras. Forward-only:
-- no modifica migraciones aplicadas.
-- ============================================================================

begin;
set local search_path = pg_catalog, public;
set local statement_timeout = '30s';
set local lock_timeout = '5s';

-- ----------------------------------------------------------------------------
-- (A) opiniones: origen, cuenta autora y edición
-- ----------------------------------------------------------------------------
alter table public.opiniones
  add column origen text not null default 'codigo',
  add column auth_user_id uuid,
  add column editado_en timestamptz;

alter table public.opiniones
  add constraint opiniones_origen_valido
    check (origen in ('codigo', 'cuenta')),
  add constraint opiniones_cuenta_solo_origen_cuenta
    check (origen = 'cuenta' or auth_user_id is null),
  add constraint opiniones_auth_user_id_fkey
    foreign key (auth_user_id)
    references public.cuentas_cliente(auth_user_id)
    on delete set null;

create unique index opiniones_una_por_cuenta_producto
  on public.opiniones (auth_user_id, product_id)
  where auth_user_id is not null;

comment on column public.opiniones.origen is
  'codigo = escrita con el código de reseña del correo (invitados); cuenta = escrita con sesión desde la tienda.';
comment on column public.opiniones.auth_user_id is
  'Cuenta autora de una opinión con origen cuenta. Deriva de auth.uid(); nunca llega del navegador. Queda nula si la cuenta se elimina.';
comment on column public.opiniones.editado_en is
  'Última edición hecha por su autor. La versión anterior queda en opiniones_historial.';
comment on table public.opiniones is
  'Opiniones verificadas. Escritura solo por RPC: op_registrar_opinion (código del pedido) y op_cuenta_opinar (sesión). Una por cliente y producto. Nada se borra en silencio: ocultar deja la fila; editar y retirar guardan la versión anterior en opiniones_historial.';

-- ----------------------------------------------------------------------------
-- (B) Historial de solo inserción: versiones editadas y opiniones retiradas
-- ----------------------------------------------------------------------------
create table public.opiniones_historial (
  id          bigint generated always as identity primary key,
  opinion_id  uuid        not null,
  evento      text        not null,
  motivo      text,
  datos       jsonb       not null,
  actor       uuid,
  creado      timestamptz not null default now(),
  constraint opiniones_historial_evento_valido
    check (evento in ('edicion', 'retiro')),
  constraint opiniones_historial_motivo_largo
    check (motivo is null or char_length(motivo) <= 300),
  constraint opiniones_historial_datos_objeto
    check (jsonb_typeof(datos) = 'object')
);

create index opiniones_historial_opinion_idx
  on public.opiniones_historial (opinion_id, creado);

comment on table public.opiniones_historial is
  'Opiniones · copia completa de la fila antes de cada edición o retiro. Solo inserción; ningún rol API la lee ni la escribe.';
comment on column public.opiniones_historial.datos is
  'Fila completa de opiniones tal como estaba antes del evento.';
comment on column public.opiniones_historial.actor is
  'auth.uid() de quien hizo el cambio; nulo cuando lo hizo la operación por SQL.';

alter table public.opiniones_historial enable row level security;
revoke all on table public.opiniones_historial
  from public, anon, authenticated, service_role;

create function public.op__historial_inmutable()
returns trigger
language plpgsql
set search_path = pg_catalog, public
as $fn$
begin
  raise exception using errcode = 'P0001', message = 'OP_HISTORIAL_INMUTABLE';
end;
$fn$;

create trigger opiniones_historial_sin_cambios
  before update or delete on public.opiniones_historial
  for each row execute function public.op__historial_inmutable();
create trigger opiniones_historial_sin_vaciar
  before truncate on public.opiniones_historial
  for each statement execute function public.op__historial_inmutable();

-- ----------------------------------------------------------------------------
-- (C) Nombre público de la cuenta
--     op__nombre_limpio valida un nombre humano (letras latinas, espacios,
--     guion, apóstrofo y punto de inicial). op__nombre_publico lo reduce a
--     «Nombre I.». op__nombre_publico_cuenta lo toma de auth.users.
-- ----------------------------------------------------------------------------
create function public.op__nombre_limpio(p_valor text)
returns text
language plpgsql
stable
set search_path = pg_catalog, public
as $fn$
declare
  v text;
begin
  if p_valor is null then
    return null;
  end if;
  v := translate(p_valor, '’ʼ´`', repeat(chr(39), 4));
  v := btrim(regexp_replace(v, '\s+', ' ', 'g'));
  if char_length(v) < 2 or char_length(v) > 80 then
    return null;
  end if;
  if v !~ '^[A-Za-zÀ-ÖØ-öø-ÿ]+(?:[''-][A-Za-zÀ-ÖØ-öø-ÿ]+)*\.?(?: [A-Za-zÀ-ÖØ-öø-ÿ]+(?:[''-][A-Za-zÀ-ÖØ-öø-ÿ]+)*\.?)*$' then
    return null;
  end if;
  if char_length(regexp_replace(v, '[^A-Za-zÀ-ÖØ-öø-ÿ]', '', 'g')) < 2 then
    return null;
  end if;
  -- Solo se corrige el uso de mayúsculas cuando todo vino en minúsculas o en
  -- mayúsculas; un nombre escrito con mayúsculas propias se respeta.
  if v = lower(v) or v = upper(v) then
    v := initcap(v);
  end if;
  return v;
end;
$fn$;

create function public.op__nombre_publico(p_nombre text, p_apellido text default null)
returns text
language plpgsql
stable
set search_path = pg_catalog, public
as $fn$
declare
  v_nombre text := public.op__nombre_limpio(p_nombre);
  v_apellido text := public.op__nombre_limpio(p_apellido);
  v_partes text[];
  v_resto text[];
  v_primero text;
  v_inicial text;
  w text;
  c_particulas constant text[] := array[
    'de', 'del', 'la', 'las', 'los', 'lo', 'le', 'y', 'e',
    'da', 'das', 'do', 'dos', 'di', 'du', 'van', 'von', 'der'
  ];
begin
  if v_nombre is null then
    return null;
  end if;
  v_partes := string_to_array(v_nombre, ' ');
  v_primero := rtrim(v_partes[1], '.');
  if char_length(v_primero) = 1 then
    v_primero := v_primero || '.';
  end if;
  v_resto := case
    when v_apellido is not null then string_to_array(v_apellido, ' ')
    else v_partes[2:]
  end;
  foreach w in array coalesce(v_resto, '{}'::text[]) loop
    w := rtrim(w, '.');
    if w <> '' and lower(w) <> all (c_particulas) then
      v_inicial := upper(left(w, 1));
      exit;
    end if;
  end loop;
  return left(v_primero, 30) || coalesce(' ' || v_inicial || '.', '');
end;
$fn$;

create function public.op__nombre_publico_cuenta(p_uid uuid)
returns text
language plpgsql
stable
set search_path = pg_catalog, public
as $fn$
declare
  v_meta jsonb;
  v text;
begin
  select u.raw_user_meta_data
    into v_meta
    from auth.users u
   where u.id = p_uid;

  if v_meta is not null and jsonb_typeof(v_meta) = 'object' then
    -- Google puede entregar nombre y apellido por separado: dan la mejor
    -- inicial. El registro por correo guarda «Nombre y apellido» en full_name.
    if public.op__nombre_limpio(v_meta->>'given_name') is not null
       and public.op__nombre_limpio(v_meta->>'family_name') is not null then
      return public.op__nombre_publico(v_meta->>'given_name', v_meta->>'family_name');
    end if;
    v := public.op__nombre_publico(v_meta->>'full_name');
    if v is not null then
      return v;
    end if;
    v := public.op__nombre_publico(v_meta->>'name');
    if v is not null then
      return v;
    end if;
  end if;
  return 'Cliente MAGANDHI';
end;
$fn$;

comment on function public.op__nombre_limpio(text) is
  'Opiniones · normaliza y valida un nombre humano; null si no lo es.';
comment on function public.op__nombre_publico(text, text) is
  'Opiniones · reduce un nombre válido a «Nombre I.»; null si el nombre no es válido.';
comment on function public.op__nombre_publico_cuenta(uuid) is
  'Opiniones · nombre público de una cuenta desde auth.users (given/family, full_name o name). Sin nombre válido devuelve «Cliente MAGANDHI».';

-- ----------------------------------------------------------------------------
-- (D) Retiro: mueve la fila completa al historial y la quita de opiniones.
--     Privado: lo usan op_cuenta_retirar_opinion y la operación por SQL.
-- ----------------------------------------------------------------------------
create function public.op__retirar_opinion(p_id uuid, p_actor uuid, p_motivo text)
returns jsonb
language plpgsql
volatile
set search_path = pg_catalog, public
as $fn$
declare
  v_op public.opiniones%rowtype;
begin
  select * into v_op
    from public.opiniones o
   where o.id = p_id
   for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'OP_OPINION_NO_ENCONTRADA';
  end if;

  insert into public.opiniones_historial (opinion_id, evento, motivo, datos, actor)
  values (v_op.id, 'retiro', left(nullif(btrim(coalesce(p_motivo, '')), ''), 300), to_jsonb(v_op), p_actor);

  delete from public.opiniones o where o.id = v_op.id;
  return to_jsonb(v_op);
end;
$fn$;

comment on function public.op__retirar_opinion(uuid, uuid, text) is
  'Opiniones · privado. Copia la fila al historial y la retira de opiniones: sale de la tienda, del promedio y de Métricas, y libera el derecho a opinar.';

-- ----------------------------------------------------------------------------
-- (E) Puertas de la cuenta (auth.uid(); ninguna recibe identidad)
-- ----------------------------------------------------------------------------

-- Snapshot completo: nombre público, opiniones propias y estado por campaña
-- publicada de cada producto entregado (pendiente, opinada u oculta).
create function public.op_cuenta_opiniones()
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_estado text;
  v_customer uuid;
  v_opiniones jsonb;
  v_productos jsonb;
begin
  if v_uid is null then
    raise exception using errcode = 'P0001', message = 'OP_SESION_REQUERIDA';
  end if;

  select cc.estado, cc.customer_id
    into v_estado, v_customer
    from public.cuentas_cliente cc
   where cc.auth_user_id = v_uid
   for share;
  if not found or v_estado <> 'activa' then
    raise exception using errcode = 'P0001', message = 'OP_CUENTA_NO_DISPONIBLE';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', o.id,
           'campana_id', cat.id,
           'slug', cat.slug,
           'nombre', coalesce(cat.nombre, li.campana_nombre, pr.nombre, 'Producto'),
           'imagen', cat.imagen_banner_path,
           'estrellas', o.estrellas,
           'comentario', o.comentario,
           'autor_nombre', o.autor_nombre,
           'creado', to_char(o.creado at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
           'editado_en', case when o.editado_en is null then null
             else to_char(o.editado_en at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') end,
           'oculta', o.oculta,
           'respuesta', o.respuesta,
           'respuesta_en', case when o.respuesta_en is null then null
             else to_char(o.respuesta_en at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') end,
           'puede_editar', not o.oculta and cat.id is not null,
           'puede_eliminar', not o.oculta
         ) order by o.creado desc, o.id desc), '[]'::jsonb)
    into v_opiniones
    from public.opiniones o
    left join public.productos pr on pr.id = o.product_id
    left join lateral (
      select pi.campana_id, pi.campana_nombre
        from public.pedido_items pi
       where pi.pedido_id = o.pedido_id
         and pi.product_id = o.product_id
       order by pi.campana_id nulls last
       limit 1
    ) li on true
    left join lateral (
      select cp.id, cp.slug, cp.nombre, cp.imagen_banner_path
        from public.catalogo_publico cp
        join public.campana_producto mapa on mapa.id = cp.id
       where mapa.product_id_ref = o.product_id
       order by case when cp.id = li.campana_id then 0 else 1 end, cp.id
       limit 1
    ) cat on true
   where o.auth_user_id = v_uid;

  with entregados as (
    select distinct pi.product_id
      from public.pedidos p
      join public.pedido_items pi on pi.pedido_id = p.id
     where v_customer is not null
       and p.customer_id = v_customer
       and p.estado = 'entregado'
       and not p.anulado
  ),
  propias as (
    select o.product_id, o.id as opinion_id, o.oculta
      from public.opiniones o
     where o.auth_user_id = v_uid
  ),
  candidatos as (
    select e.product_id from entregados e
    union
    select pp.product_id from propias pp
  ),
  estados as (
    select c.product_id,
           pp.opinion_id,
           case
             when pp.opinion_id is not null and pp.oculta then 'oculta'
             when pp.opinion_id is not null then 'opinada'
             -- Una opinión anterior con código sobre un pedido de la misma
             -- persona también cuenta: una sola opinión por producto.
             when exists (
               select 1
                 from public.opiniones o
                 join public.pedidos p on p.id = o.pedido_id
                where p.customer_id = v_customer
                  and o.product_id = c.product_id
             ) then null
             when coalesce((select pr.activo from public.productos pr where pr.id = c.product_id), false)
               then 'pendiente'
             else null
           end as estado
      from candidatos c
      left join propias pp on pp.product_id = c.product_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'campana_id', cp.id,
           'slug', cp.slug,
           'nombre', cp.nombre,
           'imagen', cp.imagen_banner_path,
           'estado', s.estado,
           'opinion_id', s.opinion_id
         ) order by case s.estado when 'pendiente' then 0 when 'opinada' then 1 else 2 end,
                    cp.nombre, cp.id), '[]'::jsonb)
    into v_productos
    from estados s
    join public.campana_producto mapa on mapa.product_id_ref = s.product_id
    join public.catalogo_publico cp on cp.id = mapa.id
   where s.estado is not null;

  return jsonb_build_object(
    'nombre_publico', public.op__nombre_publico_cuenta(v_uid),
    'opiniones', v_opiniones,
    'productos', v_productos
  );
end;
$fn$;

comment on function public.op_cuenta_opiniones() is
  'Cuenta cliente · snapshot owner-safe: nombre público, opiniones propias y estado (pendiente, opinada u oculta) por cada campaña publicada de sus productos entregados.';

-- Crea o edita la única opinión de la cuenta sobre el producto de la campaña.
-- Fija un estado deseado: repetir la misma opinión no cambia nada.
create function public.op_cuenta_opinar(
  p_campana_id uuid,
  p_estrellas integer,
  p_comentario text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_estado text;
  v_customer uuid;
  v_product uuid;
  v_comentario text;
  v_nombre text;
  v_pedido uuid;
  v_op public.opiniones%rowtype;
begin
  if v_uid is null then
    raise exception using errcode = 'P0001', message = 'OP_SESION_REQUERIDA';
  end if;

  select cc.estado, cc.customer_id
    into v_estado, v_customer
    from public.cuentas_cliente cc
   where cc.auth_user_id = v_uid
   for update;
  if not found or v_estado <> 'activa' then
    raise exception using errcode = 'P0001', message = 'OP_CUENTA_NO_DISPONIBLE';
  end if;

  if p_campana_id is null or p_estrellas is null then
    raise exception using errcode = 'P0001', message = 'OP_SOLICITUD_INVALIDA';
  end if;
  if p_estrellas < 1 or p_estrellas > 5 then
    raise exception using errcode = 'P0001', message = 'OP_ESTRELLAS_INVALIDAS';
  end if;
  v_comentario := nullif(btrim(coalesce(p_comentario, '')), '');
  if v_comentario is not null and char_length(v_comentario) > 1000 then
    raise exception using errcode = 'P0001', message = 'OP_COMENTARIO_INVALIDO';
  end if;

  -- Solo campañas que hoy están en la tienda; de ahí sale el producto.
  select mapa.product_id_ref
    into v_product
    from public.campana_producto mapa
   where mapa.id = p_campana_id
     and mapa.product_id_ref is not null
     and exists (select 1 from public.catalogo_publico cp where cp.id = mapa.id);
  if v_product is null then
    raise exception using errcode = 'P0001', message = 'OP_PRODUCTO_NO_DISPONIBLE';
  end if;

  v_nombre := public.op__nombre_publico_cuenta(v_uid);

  select * into v_op
    from public.opiniones o
   where o.auth_user_id = v_uid
     and o.product_id = v_product
   for update;

  if found then
    if v_op.oculta then
      raise exception using errcode = 'P0001', message = 'OP_OPINION_OCULTA';
    end if;
    if v_op.estrellas = p_estrellas
       and v_op.comentario is not distinct from v_comentario
       and v_op.autor_nombre = v_nombre then
      return public.op_cuenta_opiniones();
    end if;
    insert into public.opiniones_historial (opinion_id, evento, datos, actor)
    values (v_op.id, 'edicion', to_jsonb(v_op), v_uid);
    update public.opiniones o
       set estrellas = p_estrellas,
           comentario = v_comentario,
           autor_nombre = v_nombre,
           editado_en = now()
     where o.id = v_op.id;
    return public.op_cuenta_opiniones();
  end if;

  if v_customer is null then
    raise exception using errcode = 'P0001', message = 'OP_NO_ELEGIBLE';
  end if;

  -- Serializa con el código de reseña: una sola opinión por cliente y producto.
  perform pg_advisory_xact_lock(hashtextextended(
    'op-cliente-producto:' || v_customer::text || ':' || v_product::text, 0
  ));

  if not exists (
    select 1 from public.productos pr where pr.id = v_product and pr.activo
  ) then
    raise exception using errcode = 'P0001', message = 'OP_PRODUCTO_NO_DISPONIBLE';
  end if;

  if exists (
    select 1
      from public.opiniones o
      join public.pedidos p on p.id = o.pedido_id
     where p.customer_id = v_customer
       and o.product_id = v_product
  ) then
    raise exception using errcode = 'P0001', message = 'OP_YA_OPINADO';
  end if;

  select p.id
    into v_pedido
    from public.pedidos p
   where p.customer_id = v_customer
     and p.estado = 'entregado'
     and not p.anulado
     and exists (
       select 1 from public.pedido_items pi
        where pi.pedido_id = p.id and pi.product_id = v_product
     )
   order by p.creado desc nulls last, p.id desc
   limit 1;
  if v_pedido is null then
    raise exception using errcode = 'P0001', message = 'OP_NO_ELEGIBLE';
  end if;

  begin
    insert into public.opiniones (
      pedido_id, product_id, estrellas, comentario, autor_nombre,
      origen, auth_user_id, creado_por
    ) values (
      v_pedido, v_product, p_estrellas, v_comentario, v_nombre,
      'cuenta', v_uid, v_uid
    );
  exception when unique_violation then
    raise exception using errcode = 'P0001', message = 'OP_YA_OPINADO';
  end;

  return public.op_cuenta_opiniones();
end;
$fn$;

comment on function public.op_cuenta_opinar(uuid, integer, text) is
  'Cuenta cliente · crea o edita su única opinión sobre el producto de una campaña publicada. Crear exige un pedido propio entregado; editar guarda la versión anterior. Una opinión oculta no se edita. Devuelve el snapshot completo.';

-- Retira la opinión propia. Repetir el retiro devuelve el mismo snapshot.
create function public.op_cuenta_retirar_opinion(p_opinion_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = pg_catalog, public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_estado text;
  v_op public.opiniones%rowtype;
begin
  if v_uid is null then
    raise exception using errcode = 'P0001', message = 'OP_SESION_REQUERIDA';
  end if;

  select cc.estado
    into v_estado
    from public.cuentas_cliente cc
   where cc.auth_user_id = v_uid
   for update;
  if not found or v_estado <> 'activa' then
    raise exception using errcode = 'P0001', message = 'OP_CUENTA_NO_DISPONIBLE';
  end if;

  if p_opinion_id is null then
    raise exception using errcode = 'P0001', message = 'OP_SOLICITUD_INVALIDA';
  end if;

  select * into v_op
    from public.opiniones o
   where o.id = p_opinion_id
     and o.auth_user_id = v_uid
   for update;
  if not found then
    if exists (
      select 1
        from public.opiniones_historial h
       where h.opinion_id = p_opinion_id
         and h.evento = 'retiro'
         and h.actor = v_uid
    ) then
      return public.op_cuenta_opiniones();
    end if;
    raise exception using errcode = 'P0001', message = 'OP_OPINION_NO_ENCONTRADA';
  end if;

  if v_op.oculta then
    raise exception using errcode = 'P0001', message = 'OP_OPINION_OCULTA';
  end if;

  perform public.op__retirar_opinion(v_op.id, v_uid, 'cliente');
  return public.op_cuenta_opiniones();
end;
$fn$;

comment on function public.op_cuenta_retirar_opinion(uuid) is
  'Cuenta cliente · retira su opinión: sale de la tienda y del promedio, queda en el historial y la cuenta puede volver a opinar. Una opinión oculta por MAGANDHI no se retira desde la cuenta.';

-- ----------------------------------------------------------------------------
-- (F) Código de reseña: misma firma y errores. Ahora respeta una opinión por
--     cliente y producto, y una carrera contra el unique devuelve el error
--     estable en vez de un 500.
-- ----------------------------------------------------------------------------
create or replace function public.op_registrar_opinion(
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

  select * into v_pedido
    from pedidos
   where codigo_resena = upper(btrim(p_codigo))
   limit 1;
  if not found then
    raise exception 'OPINION_CODIGO_INVALIDO';
  end if;

  if v_pedido.anulado or v_pedido.estado <> 'entregado' then
    raise exception 'OPINION_PEDIDO_NO_ENTREGADO';
  end if;

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

  if not exists (
    select 1 from pedido_items
     where pedido_id = v_pedido.id
       and product_id = v_product_id
  ) then
    raise exception 'OPINION_PRODUCTO_NO_EN_PEDIDO';
  end if;

  -- Misma llave que op_cuenta_opinar: serializa por cliente y producto.
  perform pg_advisory_xact_lock(hashtextextended(
    'op-cliente-producto:' || v_pedido.customer_id::text || ':' || v_product_id::text, 0
  ));

  -- Una opinión por producto-pedido y, además, una por cliente y producto
  -- (con código o con cuenta).
  if exists (
    select 1 from opiniones
     where pedido_id = v_pedido.id
       and product_id = v_product_id
  ) or exists (
    select 1
      from opiniones o
      join pedidos p on p.id = o.pedido_id
     where p.customer_id = v_pedido.customer_id
       and o.product_id = v_product_id
  ) then
    raise exception 'OPINION_YA_REGISTRADA';
  end if;

  begin
    insert into opiniones (pedido_id, product_id, estrellas, comentario, autor_nombre, es_prueba, origen)
    values (v_pedido.id, v_product_id, p_estrellas, v_coment, v_autor, coalesce(p_es_prueba, false), 'codigo')
    returning id into v_id;
  exception when unique_violation then
    raise exception 'OPINION_YA_REGISTRADA';
  end;

  return v_id;
end;
$$;

comment on function public.op_registrar_opinion(text, text, int, text, text, boolean) is
  'Puerta de opiniones con código de reseña (invitados). Autoriza por POSESION del código del pedido. Valida código, entrega, pertenencia del producto y una opinión por cliente y producto. La invoca la Edge Function enviar-opinion con service_role.';

revoke all on function public.op_registrar_opinion(text, text, int, text, text, boolean)
  from public, anon, authenticated;
grant execute on function public.op_registrar_opinion(text, text, int, text, text, boolean)
  to service_role;

-- ----------------------------------------------------------------------------
-- (G) Vista pública: misma forma, más «editada» al final. Las retiradas ya no
--     están en opiniones, así que tampoco aparecen aquí ni en el promedio.
-- ----------------------------------------------------------------------------
create or replace view public.opiniones_publicas as
select
  cp.slug         as slug,
  o.estrellas     as estrellas,
  o.comentario    as comentario,
  o.autor_nombre  as autor_nombre,
  o.respuesta     as respuesta,
  o.respuesta_en  as respuesta_en,
  o.creado        as creado,
  (o.editado_en is not null) as editada
from public.opiniones o
join public.campana_producto cp on cp.product_id_ref = o.product_id
where o.oculta = false
  and o.es_prueba = false
  and cp.publicado = true
  and cp.activo = true;

comment on view public.opiniones_publicas is
  'OPINIONES · superficie pública por slug. Solo opiniones no ocultas, no de prueba, de campañas publicadas y activas, con columnas públicas (estrellas, comentario, autor, respuesta de marca, fecha y si fue editada). Nunca expone pedido, producto, cuenta, id ni bitácora.';

-- ----------------------------------------------------------------------------
-- (H) Permisos exactos
-- ----------------------------------------------------------------------------
revoke all on function public.op__historial_inmutable()
  from public, anon, authenticated, service_role;
revoke all on function public.op__nombre_limpio(text)
  from public, anon, authenticated, service_role;
revoke all on function public.op__nombre_publico(text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.op__nombre_publico_cuenta(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.op__retirar_opinion(uuid, uuid, text)
  from public, anon, authenticated, service_role;

revoke all on function public.op_cuenta_opiniones()
  from public, anon, authenticated, service_role;
revoke all on function public.op_cuenta_opinar(uuid, integer, text)
  from public, anon, authenticated, service_role;
revoke all on function public.op_cuenta_retirar_opinion(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.op_cuenta_opiniones()
  to authenticated, service_role;
grant execute on function public.op_cuenta_opinar(uuid, integer, text)
  to authenticated, service_role;
grant execute on function public.op_cuenta_retirar_opinion(uuid)
  to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (I) Gates estructurales: la forward falla completa ante una superficie
--     distinta de la acordada.
-- ----------------------------------------------------------------------------
do $postflight$
declare
  v_listar oid := to_regprocedure('public.op_cuenta_opiniones()');
  v_opinar oid := to_regprocedure('public.op_cuenta_opinar(uuid,integer,text)');
  v_retirar oid := to_regprocedure('public.op_cuenta_retirar_opinion(uuid)');
  v_helpers oid[] := array[
    to_regprocedure('public.op__historial_inmutable()'),
    to_regprocedure('public.op__nombre_limpio(text)'),
    to_regprocedure('public.op__nombre_publico(text,text)'),
    to_regprocedure('public.op__nombre_publico_cuenta(uuid)'),
    to_regprocedure('public.op__retirar_opinion(uuid,uuid,text)')
  ];
  v_rol text;
  v_oid oid;
begin
  if v_listar is null or v_opinar is null or v_retirar is null
     or array_position(v_helpers, null) is not null
     or exists (
       select 1
         from pg_proc p
         join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public'
          and p.proname in ('op_cuenta_opiniones', 'op_cuenta_opinar', 'op_cuenta_retirar_opinion')
          and p.oid not in (v_listar, v_opinar, v_retirar)
     ) then
    raise exception using errcode = 'P0001', message = 'OP_FIRMAS_INVALIDAS';
  end if;

  if exists (
    select 1
      from pg_proc p
     where p.oid in (v_listar, v_opinar, v_retirar)
       and (
         not p.prosecdef
         or p.prorettype <> 'jsonb'::regtype
         or coalesce(p.proconfig, '{}'::text[])
              <> array['search_path=pg_catalog, public']::text[]
       )
  ) then
    raise exception using errcode = 'P0001', message = 'OP_FUNCIONES_INVALIDAS';
  end if;

  foreach v_oid in array array[v_listar, v_opinar, v_retirar] loop
    if has_function_privilege('anon', v_oid, 'execute')
       or not has_function_privilege('authenticated', v_oid, 'execute')
       or not has_function_privilege('service_role', v_oid, 'execute') then
      raise exception using errcode = 'P0001', message = 'OP_RPC_ACL_INVALIDA';
    end if;
  end loop;

  foreach v_oid in array v_helpers loop
    foreach v_rol in array array['anon', 'authenticated', 'service_role'] loop
      if has_function_privilege(v_rol, v_oid, 'execute') then
        raise exception using errcode = 'P0001', message = 'OP_HELPER_EXPUESTO';
      end if;
    end loop;
  end loop;

  if has_function_privilege('anon', 'public.op_registrar_opinion(text,text,integer,text,text,boolean)', 'execute')
     or has_function_privilege('authenticated', 'public.op_registrar_opinion(text,text,integer,text,text,boolean)', 'execute')
     or not has_function_privilege('service_role', 'public.op_registrar_opinion(text,text,integer,text,text,boolean)', 'execute') then
    raise exception using errcode = 'P0001', message = 'OP_CODIGO_ACL_INVALIDA';
  end if;

  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.opiniones_historial'::regclass)
     or exists (select 1 from pg_policy p where p.polrelid = 'public.opiniones_historial'::regclass)
     or has_table_privilege('anon', 'public.opiniones_historial', 'select,insert,update,delete')
     or has_table_privilege('authenticated', 'public.opiniones_historial', 'select,insert,update,delete')
     or has_table_privilege('service_role', 'public.opiniones_historial', 'select,insert,update,delete') then
    raise exception using errcode = 'P0001', message = 'OP_HISTORIAL_ACCESO_INVALIDO';
  end if;

  if has_table_privilege('anon', 'public.opiniones', 'select,insert,update,delete')
     or has_table_privilege('authenticated', 'public.opiniones', 'insert,update,delete') then
    raise exception using errcode = 'P0001', message = 'OP_TABLA_ACCESO_INVALIDO';
  end if;

  if (
    select array_agg(a.attname::text order by a.attnum)
      from pg_attribute a
     where a.attrelid = 'public.opiniones_publicas'::regclass
       and a.attnum > 0
       and not a.attisdropped
  ) <> array['slug', 'estrellas', 'comentario', 'autor_nombre', 'respuesta', 'respuesta_en', 'creado', 'editada']
     or not has_table_privilege('anon', 'public.opiniones_publicas', 'select') then
    raise exception using errcode = 'P0001', message = 'OP_VISTA_PUBLICA_INVALIDA';
  end if;
end;
$postflight$;

commit;
