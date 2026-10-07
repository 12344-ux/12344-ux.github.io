-- ============================================================
-- MAGANDHI · Correos del pedido (transaccionales) · base de correo
-- ------------------------------------------------------------
-- POR QUE EXISTE: el cliente debe recibir UN correo por cada etapa de su pedido
-- (recibido -> preparando -> en_camino -> entregado). El de "entregado" lleva el
-- CODIGO DE RESENA (pedidos.codigo_resena), que es lo unico que faltaba para que
-- el Software de Opiniones reciba opiniones reales.
--
-- QUE CREA:
--   (A) correo_plantillas: el COPY de cada etapa, editable desde el back-office
--       (ventas/correos/). Cambiar el texto NO requiere tocar codigo ni
--       redesplegar nada. Nace con copy DE PRUEBA (es_borrador = true).
--   (B) correo_envios: bitacora append-only de cada intento de envio (quien,
--       cuando, a quien, resultado del proveedor). Nada se borra.
--   (C) RPC (security definer, guardadas por tiene_acceso_ventas()):
--       correo_pedido_preparar   -> valida y reserva el envio; devuelve datos.
--       correo_pedido_resultado  -> cierra el envio (enviado / fallido).
--       correo_prueba_preparar   -> envio de prueba al correo del usuario.
--       correo_guardar_plantilla -> guarda el copy de una etapa.
--
-- ARQUITECTURA DE SEGURIDAD (linea roja del dueno):
--   - La llave de Resend vive SOLO en Supabase Secrets (Edge Function
--     enviar-correo-pedido). Nunca en el navegador ni en el repo.
--   - La Edge Function NO usa service_role: llama a estos RPC con el JWT del
--     USUARIO logueado, asi que auth.uid() y tiene_acceso_ventas() se evaluan de
--     verdad. Sin sesion de Ventas no se envia nada.
--   - El DESTINATARIO sale SIEMPRE de la base (clientes.correo del pedido), nunca
--     del navegador. Un usuario no puede usar esto para escribirle a cualquiera.
--   - CERO grant a anon en tablas y funciones de este archivo.
--
-- IDEMPOTENCIA (un correo por etapa, sin duplicados):
--   - Indice unico parcial: como maximo UN envio 'pendiente' por (pedido, etapa)
--     -> un doble clic no produce dos correos.
--   - Si la etapa ya tiene un envio 'enviado', se rechaza con CORREO_YA_ENVIADO
--     salvo que el humano pida REENVIO explicito (p_reenviar = true), que queda
--     marcado es_reenvio en la bitacora. Reenviar es para casos reales (correo
--     mal escrito, el cliente no lo encuentra), nunca para insistir.
--   - El envio_id viaja a Resend como Idempotency-Key.
--   - Un 'pendiente' de mas de 10 minutos (la funcion murio a mitad de camino)
--     se cierra como 'fallido' con motivo explicito antes de permitir otro.
--
-- REGLAS DEL PROYECTO RESPETADAS: migracion forward (no reescribe nada
-- anterior), idempotente (if not exists / create or replace / on conflict do
-- nothing), default privileges del tramo 0 (se otorga EXECUTE explicito solo a
-- authenticated y service_role).
-- REQUISITO: correr DESPUES de 20261007000000_opiniones_modulo.sql.
-- ============================================================

-- ------------------------------------------------------------
-- (A) correo_plantillas
-- ------------------------------------------------------------
create table if not exists correo_plantillas (
  etapa           text primary key
                    check (etapa in ('recibido','preparando','en_camino','entregado')),
  asunto          text not null check (length(asunto) between 1 and 150),
  preheader       text check (preheader is null or length(preheader) <= 200),
  titulo          text not null check (length(titulo) between 1 and 150),
  cuerpo          text not null check (length(cuerpo) between 1 and 4000),
  boton_texto     text check (boton_texto is null or length(boton_texto) <= 40),
  es_borrador     boolean not null default true,
  actualizado     timestamptz not null default now(),
  actualizado_por uuid references auth.users(id) default auth.uid()
);

comment on table correo_plantillas is 'COPY de los 4 correos del pedido (uno por etapa). Editable desde ventas/correos/ via correo_guardar_plantilla; cambiarlo no requiere tocar codigo ni redesplegar. Variables admitidas en asunto/preheader/titulo/cuerpo: {nombre} y {pedido}. La estructura (logo, resumen del pedido, bloque del codigo de resena) la pone la Edge Function enviar-correo-pedido.';
comment on column correo_plantillas.cuerpo is 'Texto plano. Una linea en blanco separa parrafos. Se escapa como HTML antes de insertarse en el correo (no admite etiquetas).';
comment on column correo_plantillas.boton_texto is 'Solo se usa en la etapa entregado: texto del boton que lleva a dejar la opinion.';
comment on column correo_plantillas.es_borrador is 'true = copy de prueba (el panel lo marca como BORRADOR). El dueno lo pasa a false cuando el copy es el oficial.';

-- Copy DE PRUEBA para dejar el sistema montado. Voz de marca: habla MAGANDHI /
-- el equipo, nunca una persona; trato neutro en genero. on conflict do nothing:
-- re-ejecutar NO pisa el copy que el dueno ya haya editado.
insert into correo_plantillas (etapa, asunto, preheader, titulo, cuerpo, boton_texto, es_borrador, actualizado_por) values
('recibido',
 'Recibimos tu pedido {pedido}',
 'Ya está en manos del equipo MAGANDHI.',
 'Hola, {nombre}. Recibimos tu pedido.',
 E'Tu pedido ya está en manos del equipo MAGANDHI. Antes de prepararlo, revisamos cada producto.\n\nTe escribiremos en cada etapa para que sepas siempre en qué va.',
 null, true, null),
('preparando',
 'Estamos preparando tu pedido {pedido}',
 'Revisamos y empacamos cada producto.',
 'Tu pedido se está preparando.',
 E'Hola, {nombre}. El equipo está revisando y empacando tu pedido.\n\nCuando salga hacia ti, te avisaremos por este mismo medio.',
 null, true, null),
('en_camino',
 'Tu pedido {pedido} va en camino',
 'Tu pedido ya salió hacia ti.',
 'Tu pedido va en camino.',
 E'Hola, {nombre}. Tu pedido ya salió y va hacia la dirección de entrega.\n\nSi necesitas coordinar algo de la entrega, responde este correo o escríbenos por WhatsApp.',
 null, true, null),
('entregado',
 'Tu pedido {pedido} fue entregado',
 'Gracias por elegir MAGANDHI.',
 'Tu pedido fue entregado.',
 E'Hola, {nombre}. Tu pedido figura como entregado. Gracias por elegir MAGANDHI.\n\nCuando hayas probado tu producto, nos ayudaría mucho conocer tu opinión. Tu código de reseña no vence: úsalo cuando quieras.',
 'Dejar mi opinión', true, null)
on conflict (etapa) do nothing;

-- ------------------------------------------------------------
-- (B) correo_envios: bitacora de envios (append-only desde el cliente)
-- ------------------------------------------------------------
create table if not exists correo_envios (
  id            uuid primary key default gen_random_uuid(),
  pedido_id     uuid references pedidos(id),          -- null en envios de prueba
  etapa         text not null
                  check (etapa in ('recibido','preparando','en_camino','entregado')),
  destinatario  text not null,
  asunto        text,
  estado        text not null default 'pendiente'
                  check (estado in ('pendiente','enviado','fallido')),
  es_prueba     boolean not null default false,
  es_reenvio    boolean not null default false,
  proveedor_id  text,                                 -- id del correo en Resend
  error         text,
  creado        timestamptz not null default now(),
  creado_por    uuid references auth.users(id) default auth.uid(),
  resuelto      timestamptz
);

comment on table correo_envios is 'Bitacora de cada intento de envio de un correo de pedido: a quien, que etapa, resultado del proveedor (Resend) y quien lo disparo. Solo se escribe por RPC security definer; sin policy de UPDATE/DELETE desde el cliente. Es la evidencia de que el cliente fue informado en cada etapa.';
comment on column correo_envios.destinatario is 'Correo al que se envio. Sale de la base (clientes.correo del pedido o el correo del usuario en pruebas), nunca del navegador.';
comment on column correo_envios.es_reenvio is 'true si se envio de nuevo una etapa que ya tenia un envio exitoso (decision explicita del humano).';

create index if not exists idx_correo_envios_pedido on correo_envios (pedido_id);
create index if not exists idx_correo_envios_creado on correo_envios (creado desc);

-- Como maximo UN envio en vuelo por pedido+etapa (anti doble clic).
create unique index if not exists correo_envios_un_pendiente_uidx
  on correo_envios (pedido_id, etapa)
  where estado = 'pendiente' and pedido_id is not null;

-- ------------------------------------------------------------
-- RLS + grants de tablas (lectura para Ventas; escritura solo por RPC)
-- ------------------------------------------------------------
alter table correo_plantillas enable row level security;
alter table correo_envios     enable row level security;

drop policy if exists correo_plantillas_select_ventas on correo_plantillas;
create policy correo_plantillas_select_ventas on correo_plantillas
  for select to authenticated using (tiene_acceso_ventas());

drop policy if exists correo_envios_select_ventas on correo_envios;
create policy correo_envios_select_ventas on correo_envios
  for select to authenticated using (tiene_acceso_ventas());

grant select on table correo_plantillas to authenticated;
grant select on table correo_envios     to authenticated;

-- ------------------------------------------------------------
-- Utilidad interna: referencia corta y legible del pedido (#A1B2C3D4).
-- ------------------------------------------------------------
create or replace function correo_ref_pedido(p_id uuid)
returns text
language sql
immutable
set search_path = public
as $$
  select '#' || upper(left(replace(p_id::text, '-', ''), 8));
$$;

comment on function correo_ref_pedido(uuid) is 'Referencia corta y legible de un pedido para el cliente (#A1B2C3D4, primeros 8 hex del uuid). No es secreta ni sirve para opinar (eso es codigo_resena).';

revoke execute on function correo_ref_pedido(uuid) from public;
grant  execute on function correo_ref_pedido(uuid) to authenticated, service_role;

-- ------------------------------------------------------------
-- Utilidad interna: cierra 'pendientes' huerfanos (> 10 min) de un pedido+etapa.
-- ------------------------------------------------------------
create or replace function correo_cerrar_huerfanos(p_pedido_id uuid, p_etapa text)
returns void
language sql
security definer
set search_path = public
as $$
  update correo_envios
     set estado = 'fallido',
         error = 'Sin confirmación del proveedor en 10 minutos. Revisa en Resend si salió antes de reenviar.',
         resuelto = now()
   where pedido_id = p_pedido_id
     and etapa = p_etapa
     and estado = 'pendiente'
     and creado < now() - interval '10 minutes';
$$;

revoke execute on function correo_cerrar_huerfanos(uuid, text) from public;
-- Solo la usan los RPC de abajo (security definer); nadie la llama directo.

-- ============================================================
-- (C.1) correo_pedido_preparar: valida y RESERVA un envio. Devuelve todo lo que
-- la Edge Function necesita para construir el correo. Codigos de error estables
-- (CORREO_*) que la funcion y el panel traducen a mensajes claros.
-- ============================================================
create or replace function correo_pedido_preparar(
  p_pedido_id uuid,
  p_etapa     text,
  p_reenviar  boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_flujo    text[] := array['recibido','preparando','en_camino','entregado'];
  v_pedido   pedidos%rowtype;
  v_nombre   text;
  v_correo   text;
  v_pl       correo_plantillas%rowtype;
  v_items    jsonb;
  v_envio_id uuid;
  v_ref      text;
begin
  if not tiene_acceso_ventas() then
    raise exception 'CORREO_SIN_ACCESO';
  end if;

  if p_etapa is null or not (p_etapa = any (v_flujo)) then
    raise exception 'CORREO_ETAPA_INVALIDA';
  end if;

  -- Bloqueo de la fila del pedido: serializa dos clics simultaneos.
  select * into v_pedido from pedidos where id = p_pedido_id for update;
  if not found then
    raise exception 'CORREO_PEDIDO_NO_EXISTE';
  end if;

  if v_pedido.anulado then
    raise exception 'CORREO_PEDIDO_ANULADO';
  end if;

  -- Solo se informa una etapa que el pedido YA alcanzo (no se anuncia "en
  -- camino" de un pedido que sigue en recibido).
  if array_position(v_flujo, v_pedido.estado) is null
     or array_position(v_flujo, v_pedido.estado) < array_position(v_flujo, p_etapa) then
    raise exception 'CORREO_ETAPA_NO_ALCANZADA';
  end if;

  select c.nombre, nullif(btrim(c.correo), '')
    into v_nombre, v_correo
    from clientes c
   where c.id = v_pedido.customer_id;

  if v_correo is null or v_correo !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'CORREO_CLIENTE_SIN_CORREO';
  end if;

  select * into v_pl from correo_plantillas where etapa = p_etapa;
  if not found then
    raise exception 'CORREO_SIN_PLANTILLA';
  end if;

  perform correo_cerrar_huerfanos(p_pedido_id, p_etapa);

  if exists (select 1 from correo_envios
              where pedido_id = p_pedido_id and etapa = p_etapa and estado = 'pendiente') then
    raise exception 'CORREO_EN_CURSO';
  end if;

  if exists (select 1 from correo_envios
              where pedido_id = p_pedido_id and etapa = p_etapa and estado = 'enviado')
     and not coalesce(p_reenviar, false) then
    raise exception 'CORREO_YA_ENVIADO';
  end if;

  -- Lineas del pedido con el nombre COMERCIAL (campania publicada) si existe, y
  -- el slug para enlazar a la ficha en la tienda. Si no hay campania, nombre
  -- interno de Inventario y sin slug.
  select coalesce(jsonb_agg(jsonb_build_object(
           'nombre',   coalesce(cp.nombre, pr.nombre),
           'cantidad', pi.cantidad,
           'subtotal', pi.subtotal,
           'slug',     cp.slug
         ) order by pi.id), '[]'::jsonb)
    into v_items
    from pedido_items pi
    join productos pr on pr.id = pi.product_id
    left join lateral (
      select c2.nombre, c2.slug
        from campana_producto c2
       where c2.product_id_ref = pi.product_id
         and c2.publicado = true
         and c2.activo = true
       limit 1
    ) cp on true
   where pi.pedido_id = p_pedido_id;

  v_ref := correo_ref_pedido(p_pedido_id);

  insert into correo_envios (pedido_id, etapa, destinatario, asunto, estado, es_reenvio)
  values (
    p_pedido_id, p_etapa, v_correo,
    replace(replace(v_pl.asunto, '{pedido}', v_ref), '{nombre}', coalesce(split_part(btrim(v_nombre), ' ', 1), '')),
    'pendiente',
    exists (select 1 from correo_envios
             where pedido_id = p_pedido_id and etapa = p_etapa and estado = 'enviado')
  )
  returning id into v_envio_id;

  return jsonb_build_object(
    'envio_id',      v_envio_id,
    'etapa',         p_etapa,
    'destinatario',  v_correo,
    'nombre',        coalesce(split_part(btrim(v_nombre), ' ', 1), ''),
    'pedido',        v_ref,
    'total',         v_pedido.total,
    'items',         v_items,
    'direccion',     concat_ws(', ', nullif(v_pedido.direccion, ''), nullif(v_pedido.ciudad, '')),
    -- El codigo de resena SOLO viaja en el correo de entregado.
    'codigo_resena', case when p_etapa = 'entregado' then v_pedido.codigo_resena else null end,
    'plantilla',     jsonb_build_object(
                       'asunto', v_pl.asunto, 'preheader', v_pl.preheader,
                       'titulo', v_pl.titulo, 'cuerpo', v_pl.cuerpo,
                       'boton_texto', v_pl.boton_texto),
    'es_prueba',     false
  );
end;
$$;

comment on function correo_pedido_preparar(uuid, text, boolean) is 'Valida (acceso Ventas, etapa alcanzada, pedido no anulado, cliente con correo, idempotencia) y RESERVA un envio pendiente en correo_envios. Devuelve destinatario (de la base), datos del pedido, copy de la plantilla y, SOLO para entregado, el codigo_resena. La llama la Edge Function enviar-correo-pedido con el JWT del usuario.';

revoke execute on function correo_pedido_preparar(uuid, text, boolean) from public;
grant  execute on function correo_pedido_preparar(uuid, text, boolean) to authenticated, service_role;

-- ============================================================
-- (C.2) correo_prueba_preparar: envio de PRUEBA de una etapa al correo del
-- PROPIO usuario logueado (auth.users), con datos de ejemplo. Sirve para ver el
-- copy en una bandeja real sin necesitar un pedido. Admite un borrador (copy no
-- guardado) para probar antes de guardar.
-- ============================================================
create or replace function correo_prueba_preparar(
  p_etapa    text,
  p_borrador jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_correo   text;
  v_pl       correo_plantillas%rowtype;
  v_envio_id uuid;
  v_asunto   text;
begin
  if not tiene_acceso_ventas() then
    raise exception 'CORREO_SIN_ACCESO';
  end if;
  if p_etapa is null or p_etapa not in ('recibido','preparando','en_camino','entregado') then
    raise exception 'CORREO_ETAPA_INVALIDA';
  end if;

  select email into v_correo from auth.users where id = auth.uid();
  if v_correo is null then
    raise exception 'CORREO_SIN_ACCESO';
  end if;

  select * into v_pl from correo_plantillas where etapa = p_etapa;
  if not found then
    raise exception 'CORREO_SIN_PLANTILLA';
  end if;

  -- Si llega un borrador, se usa en lugar del copy guardado (no se guarda).
  if p_borrador is not null and jsonb_typeof(p_borrador) = 'object' then
    v_pl.asunto      := left(coalesce(nullif(btrim(p_borrador->>'asunto'), ''), v_pl.asunto), 150);
    v_pl.preheader   := left(nullif(btrim(coalesce(p_borrador->>'preheader', '')), ''), 200);
    v_pl.titulo      := left(coalesce(nullif(btrim(p_borrador->>'titulo'), ''), v_pl.titulo), 150);
    v_pl.cuerpo      := left(coalesce(nullif(btrim(p_borrador->>'cuerpo'), ''), v_pl.cuerpo), 4000);
    v_pl.boton_texto := left(nullif(btrim(coalesce(p_borrador->>'boton_texto', '')), ''), 40);
  end if;

  v_asunto := '[Prueba] ' || replace(replace(v_pl.asunto, '{pedido}', '#PRUEBA01'), '{nombre}', 'Prueba');

  insert into correo_envios (pedido_id, etapa, destinatario, asunto, estado, es_prueba)
  values (null, p_etapa, v_correo, v_asunto, 'pendiente', true)
  returning id into v_envio_id;

  return jsonb_build_object(
    'envio_id',      v_envio_id,
    'etapa',         p_etapa,
    'destinatario',  v_correo,
    'nombre',        'Prueba',
    'pedido',        '#PRUEBA01',
    'total',         32900,
    'items',         jsonb_build_array(jsonb_build_object(
                       'nombre', 'Producto de ejemplo', 'cantidad', 1,
                       'subtotal', 32900, 'slug', 'ejemplo')),
    'direccion',     'Calle de ejemplo 1-23, Tunja',
    'codigo_resena', case when p_etapa = 'entregado' then 'MG-EJEMPLO000' else null end,
    'plantilla',     jsonb_build_object(
                       'asunto', v_pl.asunto, 'preheader', v_pl.preheader,
                       'titulo', v_pl.titulo, 'cuerpo', v_pl.cuerpo,
                       'boton_texto', v_pl.boton_texto),
    'es_prueba',     true
  );
end;
$$;

comment on function correo_prueba_preparar(text, jsonb) is 'Reserva un envio de PRUEBA de una etapa hacia el correo del propio usuario logueado (auth.users), con datos de ejemplo y, opcionalmente, un borrador de copy sin guardar. No toca pedidos. Queda en correo_envios con es_prueba=true.';

revoke execute on function correo_prueba_preparar(text, jsonb) from public;
grant  execute on function correo_prueba_preparar(text, jsonb) to authenticated, service_role;

-- ============================================================
-- (C.3) correo_pedido_resultado: cierra un envio pendiente con el resultado del
-- proveedor. Solo transiciona desde 'pendiente' (no reescribe historia).
-- ============================================================
create or replace function correo_pedido_resultado(
  p_envio_id     uuid,
  p_ok           boolean,
  p_proveedor_id text default null,
  p_error        text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_estado text;
begin
  if not tiene_acceso_ventas() then
    raise exception 'CORREO_SIN_ACCESO';
  end if;

  update correo_envios
     set estado       = case when p_ok then 'enviado' else 'fallido' end,
         proveedor_id = left(p_proveedor_id, 200),
         error        = case when p_ok then null else left(coalesce(p_error, 'Error desconocido'), 500) end,
         resuelto     = now()
   where id = p_envio_id
     and estado = 'pendiente'
  returning estado into v_estado;

  if v_estado is null then
    raise exception 'CORREO_ENVIO_NO_PENDIENTE';
  end if;

  return jsonb_build_object('envio_id', p_envio_id, 'estado', v_estado);
end;
$$;

comment on function correo_pedido_resultado(uuid, boolean, text, text) is 'Cierra un envio pendiente como enviado (con el id de Resend) o fallido (con el motivo). Solo transiciona desde pendiente. Guardado por tiene_acceso_ventas().';

revoke execute on function correo_pedido_resultado(uuid, boolean, text, text) from public;
grant  execute on function correo_pedido_resultado(uuid, boolean, text, text) to authenticated, service_role;

-- ============================================================
-- (C.4) correo_guardar_plantilla: guarda el copy de una etapa.
-- ============================================================
create or replace function correo_guardar_plantilla(
  p_etapa       text,
  p_asunto      text,
  p_preheader   text,
  p_titulo      text,
  p_cuerpo      text,
  p_boton_texto text,
  p_es_borrador boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not tiene_acceso_ventas() then
    raise exception 'CORREO_SIN_ACCESO';
  end if;
  if p_etapa is null or p_etapa not in ('recibido','preparando','en_camino','entregado') then
    raise exception 'CORREO_ETAPA_INVALIDA';
  end if;
  if nullif(btrim(coalesce(p_asunto, '')), '') is null
     or nullif(btrim(coalesce(p_titulo, '')), '') is null
     or nullif(btrim(coalesce(p_cuerpo, '')), '') is null then
    raise exception 'CORREO_PLANTILLA_INCOMPLETA';
  end if;
  if length(btrim(p_asunto)) > 150 or length(btrim(p_titulo)) > 150
     or length(btrim(p_cuerpo)) > 4000
     or length(btrim(coalesce(p_preheader, ''))) > 200
     or length(btrim(coalesce(p_boton_texto, ''))) > 40 then
    raise exception 'CORREO_PLANTILLA_MUY_LARGA';
  end if;

  update correo_plantillas
     set asunto          = btrim(p_asunto),
         preheader       = nullif(btrim(coalesce(p_preheader, '')), ''),
         titulo          = btrim(p_titulo),
         cuerpo          = btrim(p_cuerpo),
         boton_texto     = nullif(btrim(coalesce(p_boton_texto, '')), ''),
         es_borrador     = coalesce(p_es_borrador, true),
         actualizado     = now(),
         actualizado_por = auth.uid()
   where etapa = p_etapa;

  if not found then
    raise exception 'CORREO_SIN_PLANTILLA';
  end if;

  return jsonb_build_object('etapa', p_etapa, 'ok', true);
end;
$$;

comment on function correo_guardar_plantilla(text, text, text, text, text, text, boolean) is 'Guarda el copy de una etapa (asunto, preheader, titulo, cuerpo, boton) y si es borrador u oficial. Guardado por tiene_acceso_ventas(). Cambiar el copy no requiere redesplegar la Edge Function.';

revoke execute on function correo_guardar_plantilla(text, text, text, text, text, text, boolean) from public;
grant  execute on function correo_guardar_plantilla(text, text, text, text, text, text, boolean) to authenticated, service_role;
