-- ============================================================================
-- MAGANDHI · COMERCIAL C4 · CUENTA Y CICLO POSTPAGO DEL CARRITO
-- ----------------------------------------------------------------------------
-- Migración FORWARD sobre 20261104000000. Conserva las firmas v0/v1/v2,
-- mantiene el flag apagado y no reescribe ninguna migración histórica.
-- ============================================================================

begin;

-- C4 se despliega únicamente con el carrito apagado. Esta migración nunca
-- cambia el interruptor: si el entorno no cumple el corte operativo, aborta.
do $c4_flag$
begin
  if not exists (select 1 from comercial_config where id = 1) then
    raise exception using errcode = 'P0001', message = 'C4_CONFIG_AUSENTE';
  end if;
  if exists (select 1 from comercial_config where id = 1 and carrito_habilitado) then
    raise exception using errcode = 'P0001', message = 'C4_REQUIERE_FLAG_OFF';
  end if;
end
$c4_flag$;

-- ----------------------------------------------------------------------------
-- (A) Trazabilidad privada y snapshots de pedido.
-- ----------------------------------------------------------------------------
alter table pagos_intencion
  add column customer_id uuid references clientes(id) on delete restrict;

comment on column pagos_intencion.customer_id is
  'C4 · identidad comercial autoritativa del checkout con cuenta. Se deriva exclusivamente de cuentas_cliente y del correo confirmado de Auth; nunca del navegador.';

alter table pedidos
  add column destinatario_nombre text,
  add column destinatario_correo text,
  add column destinatario_telefono text;

comment on column pedidos.destinatario_nombre is
  'C4 · snapshot inmutable del nombre del destinatario de esta orden; no se reescribe al editar clientes.';
comment on column pedidos.destinatario_correo is
  'C4 · snapshot inmutable del correo de contacto indicado para esta entrega; no decide customer_id.';
comment on column pedidos.destinatario_telefono is
  'C4 · snapshot inmutable del teléfono de contacto indicado para esta entrega; no decide customer_id.';

-- Los pedidos v2 ya procesados, si existieran, son la única fuente histórica
-- legítima para completar customer_id. No se infiere identidad en creadas.
update pagos_intencion pi
   set customer_id = p.customer_id
  from pedidos p
 where pi.version_checkout = 2
   and pi.estado = 'procesada'
   and pi.pedido_id = p.id
   and pi.customer_id is null;

-- Fallar cerrado ante una historia procesada incompleta; no fabricar vínculos.
do $c4_historia_procesada$
begin
  if exists (
    select 1
      from pagos_intencion pi
     where pi.version_checkout = 2
       and pi.estado = 'procesada'
       and (pi.pedido_id is null or pi.customer_id is null)
  ) then
    raise exception using errcode = 'P0001', message = 'C4_HISTORIA_PROCESADA_INCONSISTENTE';
  end if;
end
$c4_historia_procesada$;

alter table pagos_intencion
  add constraint pagos_intencion_v2_procesada_con_propiedad
  check (
    version_checkout <> 2
    or estado <> 'procesada'
    or (pedido_id is not null and customer_id is not null)
  );

create unique index pagos_intencion_pedido_v2_uidx
  on pagos_intencion (pedido_id)
  where version_checkout = 2 and pedido_id is not null;

-- ----------------------------------------------------------------------------
-- (B) Bloqueo explícito de la tupla carrito. La referencia y la versión del
--     checkout viajan juntas; null significa editable.
-- ----------------------------------------------------------------------------
alter table carritos
  add column checkout_referencia text references pagos_intencion(referencia) on delete restrict,
  add column checkout_version bigint,
  add column checkout_bloqueado_en timestamptz,
  add constraint carritos_checkout_bloqueo_coherente check (
    (
      checkout_referencia is null
      and checkout_version is null
      and checkout_bloqueado_en is null
    )
    or
    (
      checkout_referencia is not null
      and checkout_version is not null
      and checkout_version >= 0
      and checkout_bloqueado_en is not null
    )
  );

comment on column carritos.checkout_referencia is
  'C4 · intención v2 que bloquea explícitamente este carrito durante creada/revisión. No se expone en snapshots públicos.';
comment on column carritos.checkout_version is
  'C4 · versión exacta congelada al adquirir el bloqueo de checkout.';
comment on column carritos.checkout_bloqueado_en is
  'C4 · instante de adquisición del bloqueo explícito; no implica reserva de stock.';

-- C2 concedía SELECT de tabla completa. Se conserva lectura directa de todas
-- sus columnas históricas, pero los metadatos privados del bloqueo solo salen
-- como booleano por co_carrito_listar/co__carrito_snapshot.
revoke select on table carritos from authenticated;
grant select (id, auth_user_id, estado, version, creado, actualizado)
  on table carritos to authenticated;

create unique index carritos_checkout_referencia_uidx
  on carritos (checkout_referencia)
  where checkout_referencia is not null;

-- Una intención creada por carrito es el piso duro de idempotencia durante el
-- alta. Ante duplicados históricos se aborta en vez de elegir. Las revisiones
-- C4 permanecen bloqueadas por la referencia explícita de la cabecera, pero no
-- se reinterpretan revisiones históricas de C3.
do $c4_bloqueos_duplicados$
begin
  if exists (
    select pi.carrito_id
      from pagos_intencion pi
     where pi.version_checkout = 2
       and pi.estado = 'creada'
     group by pi.carrito_id
    having count(*) > 1
  ) then
    raise exception using errcode = 'P0001', message = 'C4_INTENCIONES_CREADAS_DUPLICADAS';
  end if;
end
$c4_bloqueos_duplicados$;

create unique index pagos_intencion_carrito_creada_v2_uidx
  on pagos_intencion (carrito_id)
  where version_checkout = 2 and estado = 'creada';

-- Backfill prudente de la intención C3 existente. Solo se bloquea cuando
-- propiedad, estado, versión y el conjunto exacto campaña/cantidad coinciden.
-- Cualquier divergencia aborta toda la migración y deja la historia intacta.
do $c4_validar_backfill$
begin
  if exists (
    select 1
      from pagos_intencion pi
      left join carritos c on c.id = pi.carrito_id
     where pi.version_checkout = 2
       and pi.estado = 'creada'
       and (
         c.id is null
         or c.estado <> 'activa'
         or c.auth_user_id is distinct from pi.auth_user_id
         or c.version is distinct from pi.carrito_version
         or exists (
           (select ci.campana_id, ci.cantidad
              from carrito_items ci
             where ci.carrito_id = pi.carrito_id)
           except
           (select pii.campana_id, pii.cantidad
              from pagos_intencion_items pii
             where pii.referencia = pi.referencia)
         )
         or exists (
           (select pii.campana_id, pii.cantidad
              from pagos_intencion_items pii
             where pii.referencia = pi.referencia)
           except
           (select ci.campana_id, ci.cantidad
              from carrito_items ci
             where ci.carrito_id = pi.carrito_id)
         )
       )
  ) then
    raise exception using errcode = 'P0001', message = 'C4_BACKFILL_CARRITO_INCONSISTENTE';
  end if;
end
$c4_validar_backfill$;

update carritos c
   set checkout_referencia = pi.referencia,
       checkout_version = pi.carrito_version,
       checkout_bloqueado_en = coalesce(pi.creado, now())
  from pagos_intencion pi
 where pi.version_checkout = 2
   and pi.estado = 'creada'
   and pi.carrito_id = c.id;

-- Completa solo la trazabilidad ya resuelta de intenciones no procesadas. La
-- aprobación volverá a leer y bloquear cuentas_cliente como autoridad final.
update pagos_intencion pi
   set customer_id = cc.customer_id
  from cuentas_cliente cc
 where pi.version_checkout = 2
   and pi.auth_user_id = cc.auth_user_id
   and pi.customer_id is null
   and cc.customer_id is not null;

-- Defensa también para escrituras privilegiadas: una línea de un carrito en
-- checkout no puede insertarse, cambiarse, moverse ni borrarse.
create or replace function co__proteger_lineas_checkout()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_carrito_id uuid := case when tg_op = 'DELETE' then old.carrito_id else new.carrito_id end;
begin
  if exists (
    select 1
      from carritos c
     where c.id = v_carrito_id
       and c.checkout_referencia is not null
  ) then
    raise exception using errcode = 'P0001', message = 'CO_CARRITO_EN_CHECKOUT';
  end if;

  if tg_op = 'UPDATE' and new.carrito_id is distinct from old.carrito_id
     and exists (
       select 1 from carritos c
        where c.id = old.carrito_id and c.checkout_referencia is not null
     ) then
    raise exception using errcode = 'P0001', message = 'CO_CARRITO_EN_CHECKOUT';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function co__proteger_lineas_checkout()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_co_proteger_lineas_checkout on carrito_items;
create trigger trg_co_proteger_lineas_checkout
  before insert or update or delete on carrito_items
  for each row execute function co__proteger_lineas_checkout();

-- Snapshot compatible: solo añade el booleano no sensible. La referencia de
-- pago, customer_id y demás datos privados permanecen fuera del navegador.
create or replace function co__carrito_snapshot()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_habilitado boolean := false;
  v_carrito_id uuid;
  v_version    bigint;
  v_bloqueado  boolean := false;
  v_lineas     bigint := 0;
  v_unidades   bigint := 0;
  v_items      jsonb := '[]'::jsonb;
begin
  select coalesce(cfg.carrito_habilitado, false)
    into v_habilitado
    from comercial_config cfg
   where cfg.id = 1;

  select c.id, c.version, c.checkout_referencia is not null
    into v_carrito_id, v_version, v_bloqueado
    from carritos c
   where c.auth_user_id = v_uid
     and c.estado = 'activa';

  if v_carrito_id is not null then
    select count(*)::bigint,
           coalesce(sum(ci.cantidad), 0)::bigint,
           coalesce(
             jsonb_agg(
               jsonb_build_object(
                 'campana_id', ci.campana_id,
                 'nombre', case when cp.id is not null then cp.nombre else null end,
                 'slug', case when cp.id is not null then cp.slug else null end,
                 'precio_unitario_actual', case when cp.id is not null then cp.precio_venta else null end,
                 'cantidad', ci.cantidad,
                 'subtotal_actual', case
                   when cp.id is not null and cp.precio_venta is not null
                     then cp.precio_venta * ci.cantidad
                   else null
                 end,
                 'max_comprable', case when cp.id is not null then cp.max_comprable else 0 end,
                 'disponible', (
                   cp.id is not null
                   and coalesce(cp.precio_venta, 0) > 0
                   and coalesce(cp.max_comprable, 0) > 0
                 ),
                 'requiere_ajuste', (
                   cp.id is null
                   or coalesce(cp.precio_venta, 0) <= 0
                   or coalesce(cp.max_comprable, 0) <= 0
                   or ci.cantidad > coalesce(cp.max_comprable, 0)
                 )
               )
               order by ci.creado, ci.campana_id
             ),
             '[]'::jsonb
           )
      into v_lineas, v_unidades, v_items
      from carrito_items ci
      left join catalogo_publico cp on cp.id = ci.campana_id
     where ci.carrito_id = v_carrito_id;
  end if;

  return jsonb_build_object(
    'habilitado', coalesce(v_habilitado, false),
    'carrito_id', v_carrito_id,
    'version', coalesce(v_version, 0),
    'bloqueado_checkout', coalesce(v_bloqueado, false),
    'cantidad_lineas', coalesce(v_lineas, 0),
    'cantidad_unidades', coalesce(v_unidades, 0),
    'items', coalesce(v_items, '[]'::jsonb)
  );
end;
$$;

comment on function co__carrito_snapshot() is
  'Interna C4 · snapshot canónico compatible del carrito; añade bloqueado_checkout sin exponer referencia, intención, cliente ni pago.';
revoke all on function co__carrito_snapshot() from public, anon, authenticated;
grant execute on function co__carrito_snapshot() to service_role;

-- ----------------------------------------------------------------------------
-- (C) Resolución privada de customer_id desde cuenta + correo Auth confirmado.
--     Solo puede abrirse dentro del webhook C4.
-- ----------------------------------------------------------------------------
create or replace function co__resolver_customer_checkout(
  p_nombre text,
  p_direccion text,
  p_ciudad text,
  p_departamento text,
  p_pais text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_correo text;
  v_confirmado timestamptz;
  v_correo_norm text;
  v_estado text;
  v_customer_id uuid;
  v_iter uuid;
  v_coincidencias integer := 0;
  v_reclamado_por uuid;
begin
  if not pw__contexto_servidor()
     or coalesce(current_setting('impulse.checkout_c4', true), '') <> 'on' then
    raise exception using errcode = 'P0001', message = 'C4_CONTEXTO_INVALIDO';
  end if;

  begin
    v_uid := nullif(current_setting('impulse.checkout_auth_user_id', true), '')::uuid;
  exception when invalid_text_representation then
    raise exception using errcode = 'P0001', message = 'C4_IDENTIDAD_INVALIDA';
  end;
  if v_uid is null then
    raise exception using errcode = 'P0001', message = 'C4_IDENTIDAD_INVALIDA';
  end if;

  select u.email, u.email_confirmed_at
    into v_correo, v_confirmado
    from auth.users u
   where u.id = v_uid
   for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'C4_IDENTIDAD_INVALIDA';
  end if;

  v_correo_norm := ventas_norm_correo(v_correo);
  if v_confirmado is null or v_correo_norm is null then
    raise exception using errcode = 'P0001', message = 'C4_CORREO_NO_CONFIRMADO';
  end if;

  select cc.estado, cc.customer_id
    into v_estado, v_customer_id
    from cuentas_cliente cc
   where cc.auth_user_id = v_uid
   for update;
  if not found or v_estado <> 'activa' then
    raise exception using errcode = 'P0001', message = 'C4_CUENTA_NO_DISPONIBLE';
  end if;

  if v_customer_id is not null then
    perform 1 from clientes c where c.id = v_customer_id;
    if not found then
      raise exception using errcode = 'P0001', message = 'C4_VINCULO_INCONSISTENTE';
    end if;
    return v_customer_id;
  end if;

  -- Misma clave y protocolo que Cuentas C2 y los triggers de clientes.
  perform pg_advisory_xact_lock(hashtextextended('cc-correo:' || v_correo_norm, 0));

  for v_iter in
    select c.id
      from clientes c
     where ventas_norm_correo(c.correo_norm) = v_correo_norm
        or ventas_norm_correo(c.correo) = v_correo_norm
     order by c.id
  loop
    v_coincidencias := v_coincidencias + 1;
    if v_coincidencias = 1 then v_customer_id := v_iter; end if;
  end loop;

  if v_coincidencias > 1 then
    raise exception using errcode = 'P0001', message = 'C4_CORREO_AMBIGUO';
  end if;

  if v_coincidencias = 1 then
    select cc.auth_user_id
      into v_reclamado_por
      from cuentas_cliente cc
     where cc.customer_id = v_customer_id
     for update;
    if found and v_reclamado_por is distinct from v_uid then
      raise exception using errcode = 'P0001', message = 'C4_CLIENTE_YA_VINCULADO';
    end if;
  else
    insert into clientes (
      nombre, correo, correo_norm, direccion, ciudad, departamento, pais
    ) values (
      coalesce(nullif(btrim(p_nombre), ''), 'Comprador web'),
      v_correo, v_correo_norm, p_direccion, p_ciudad, p_departamento,
      coalesce(nullif(btrim(p_pais), ''), 'Colombia')
    )
    returning id into v_customer_id;
  end if;

  begin
    update cuentas_cliente
       set customer_id = v_customer_id,
           vinculado_en = now(),
           actualizado = now()
     where auth_user_id = v_uid
       and estado = 'activa'
       and customer_id is null;
  exception when unique_violation then
    raise exception using errcode = 'P0001', message = 'C4_CARRERA_VINCULO';
  end;

  if not found then
    select cc.customer_id into v_reclamado_por
      from cuentas_cliente cc
     where cc.auth_user_id = v_uid;
    if v_reclamado_por is distinct from v_customer_id then
      raise exception using errcode = 'P0001', message = 'C4_CARRERA_VINCULO';
    end if;
  end if;

  return v_customer_id;
end;
$$;

comment on function co__resolver_customer_checkout(text, text, text, text, text) is
  'PRIVADA C4 · deriva/vincula customer_id con cuenta activa y correo Auth confirmado bajo advisory lock. No acepta UID, correo ni customer_id del navegador.';
revoke all on function co__resolver_customer_checkout(text, text, text, text, text)
  from public, anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (D) crear_pedido conserva firma y núcleo C1/C3. El wrapper C4 solo deriva la
--     propiedad en el contexto estrecho del webhook y estampa destinatario.
-- ----------------------------------------------------------------------------
alter function crear_pedido(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb)
  rename to co__crear_pedido_c3;
revoke all on function co__crear_pedido_c3(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb)
  from public, anon, authenticated, service_role;

create function crear_pedido(
  p_customer_id    uuid    default null,
  p_nombre         text    default null,
  p_correo         text    default null,
  p_telefono       text    default null,
  p_direccion      text    default null,
  p_ciudad         text    default null,
  p_departamento   text    default null,
  p_pais           text    default null,
  p_notas_cliente  text    default null,
  p_canal          text    default 'manual',
  p_fecha_orden    date    default current_date,
  p_notas_pedido   text    default null,
  p_items          jsonb   default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_id uuid := p_customer_id;
  v_resultado jsonb;
  v_pedido_id uuid;
begin
  if coalesce(current_setting('impulse.checkout_c4', true), '') = 'on' then
    if coalesce(p_canal, 'manual') <> 'web' or not pw__contexto_servidor() then
      raise exception using errcode = 'P0001', message = 'C4_CONTEXTO_INVALIDO';
    end if;
    v_customer_id := co__resolver_customer_checkout(
      p_nombre, p_direccion, p_ciudad, p_departamento, p_pais
    );
  end if;

  v_resultado := co__crear_pedido_c3(
    v_customer_id, p_nombre, p_correo, p_telefono, p_direccion, p_ciudad,
    p_departamento, p_pais, p_notas_cliente, p_canal, p_fecha_orden,
    p_notas_pedido, p_items
  );

  v_pedido_id := nullif(v_resultado->>'pedido_id', '')::uuid;
  if v_pedido_id is null then
    raise exception using errcode = 'XX000', message = 'C4_PEDIDO_SIN_IDENTIDAD';
  end if;

  update pedidos
     set destinatario_nombre = nullif(btrim(p_nombre), ''),
         destinatario_correo = nullif(btrim(p_correo), ''),
         destinatario_telefono = nullif(btrim(p_telefono), '')
   where id = v_pedido_id;

  return v_resultado;
end;
$$;

comment on function crear_pedido(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb) is
  'Núcleo compatible de pedidos C4. Conserva la firma y el camino C1/C3; estampa snapshot de destinatario y, solo bajo contexto servidor C4, deriva customer_id desde cuenta/correo Auth confirmado.';
revoke all on function crear_pedido(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function crear_pedido(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb)
  to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (E) Registro v2 compatible. El núcleo C3 sigue congelando y revalidando; C4
--     serializa la tupla y adquiere explícitamente el bloqueo antes de commit.
-- ----------------------------------------------------------------------------
alter function pw_registrar_intencion_carrito(text, uuid, uuid, bigint, text, jsonb, text, text, text)
  rename to co__pw_registrar_intencion_carrito_c3;
revoke all on function co__pw_registrar_intencion_carrito_c3(text, uuid, uuid, bigint, text, jsonb, text, text, text)
  from public, anon, authenticated, service_role;

create function pw_registrar_intencion_carrito(
  p_referencia       text,
  p_auth_user_id     uuid,
  p_carrito_id       uuid,
  p_version_esperada bigint,
  p_entorno          text,
  p_comprador        jsonb default '{}'::jsonb,
  p_utm_campaign     text default null,
  p_mg_vid           text default null,
  p_moneda           text default 'COP'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_habilitado boolean;
  v_estado_cuenta text;
  v_carrito carritos;
  v_existente pagos_intencion;
  v_resultado jsonb;
begin
  -- Repite el prefijo determinista config -> cuenta -> carrito antes de delegar
  -- al congelado C3. La función interna volverá a tomar los mismos locks.
  select cfg.carrito_habilitado into v_habilitado
    from comercial_config cfg where cfg.id = 1 for share;
  if coalesce(v_habilitado, false) is not true then
    raise exception using errcode = 'P0001', message = 'PW_CARRITO_DESHABILITADO';
  end if;

  select cc.estado into v_estado_cuenta
    from cuentas_cliente cc
   where cc.auth_user_id = p_auth_user_id
   for update;
  if not found or v_estado_cuenta <> 'activa' then
    raise exception using errcode = 'P0001', message = 'PW_CARRITO_INVALIDO';
  end if;

  select * into v_carrito
    from carritos c
   where c.id = p_carrito_id
   for update;
  if not found
     or v_carrito.auth_user_id is distinct from p_auth_user_id
     or v_carrito.estado <> 'activa' then
    raise exception using errcode = 'P0001', message = 'PW_CARRITO_INVALIDO';
  end if;
  if p_version_esperada is null
     or v_carrito.version is distinct from p_version_esperada then
    raise exception using errcode = 'P0001', message = 'PW_VERSION_DESACTUALIZADA';
  end if;

  if v_carrito.checkout_referencia is not null then
    select * into v_existente
      from pagos_intencion pi
     where pi.referencia = v_carrito.checkout_referencia
     for update;

    if not found
       or v_existente.version_checkout <> 2
       or v_existente.auth_user_id is distinct from p_auth_user_id
       or v_existente.carrito_id is distinct from p_carrito_id
       or v_existente.carrito_version is distinct from p_version_esperada
       or v_existente.estado not in ('creada', 'requiere_revision') then
      raise exception using errcode = 'XX000', message = 'PW_BLOQUEO_INCONSISTENTE';
    end if;

    if v_existente.estado = 'requiere_revision' then
      raise exception using errcode = 'P0001', message = 'PW_CARRITO_EN_REVISION';
    end if;

    -- El núcleo C3 valida y devuelve el snapshot persistido de forma idempotente.
    return co__pw_registrar_intencion_carrito_c3(
      p_referencia, p_auth_user_id, p_carrito_id, p_version_esperada,
      p_entorno, p_comprador, p_utm_campaign, p_mg_vid, p_moneda
    );
  end if;

  if exists (
    select 1 from pagos_intencion pi
     where pi.version_checkout = 2
       and pi.carrito_id = p_carrito_id
       and pi.estado in ('creada', 'requiere_revision')
  ) then
    raise exception using errcode = 'XX000', message = 'PW_BLOQUEO_INCONSISTENTE';
  end if;

  v_resultado := co__pw_registrar_intencion_carrito_c3(
    p_referencia, p_auth_user_id, p_carrito_id, p_version_esperada,
    p_entorno, p_comprador, p_utm_campaign, p_mg_vid, p_moneda
  );

  select * into strict v_existente
    from pagos_intencion pi
   where pi.referencia = v_resultado->>'referencia'
   for update;

  if v_existente.version_checkout <> 2
     or v_existente.auth_user_id is distinct from p_auth_user_id
     or v_existente.carrito_id is distinct from p_carrito_id
     or v_existente.carrito_version is distinct from p_version_esperada
     or v_existente.estado <> 'creada' then
    raise exception using errcode = 'XX000', message = 'PW_INTENCION_C4_INCONSISTENTE';
  end if;

  update pagos_intencion
     set customer_id = (
       select cc.customer_id from cuentas_cliente cc
        where cc.auth_user_id = p_auth_user_id
     )
   where referencia = v_existente.referencia;

  update carritos
     set checkout_referencia = v_existente.referencia,
         checkout_version = p_version_esperada,
         checkout_bloqueado_en = now(),
         actualizado = now()
   where id = p_carrito_id
     and checkout_referencia is null;
  if not found then
    raise exception using errcode = 'P0001', message = 'PW_CARRITO_EN_CHECKOUT';
  end if;

  return v_resultado;
end;
$$;

comment on function pw_registrar_intencion_carrito(text, uuid, uuid, bigint, text, jsonb, text, text, text) is
  'C4 · conserva firma/retorno C3, congela la intención v2 y bloquea explícitamente la tupla de carrito en la misma transacción. Reintentos de la misma versión reutilizan el snapshot.';
revoke all on function pw_registrar_intencion_carrito(text, uuid, uuid, bigint, text, jsonb, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function pw_registrar_intencion_carrito(text, uuid, uuid, bigint, text, jsonb, text, text, text)
  to service_role;

-- ----------------------------------------------------------------------------
-- (F) Webhook. v0/v1 delegan literalmente en C3. v2 usa orden estable
--     auth -> cuenta -> carrito -> intención -> líneas -> producto -> campaña
--     y confirma pedido, propiedad y consumo en una sola transacción.
-- ----------------------------------------------------------------------------
alter function pw_procesar_pago(text, text, text, bigint, text, text, text, jsonb, text, text)
  rename to co__pw_procesar_pago_c3;
revoke all on function co__pw_procesar_pago_c3(text, text, text, bigint, text, text, text, jsonb, text, text)
  from public, anon, authenticated, service_role;

create function pw_procesar_pago(
  p_transaccion_id text,
  p_estado_wompi   text,
  p_referencia     text,
  p_monto_centavos bigint,
  p_moneda         text default null,
  p_evento         text default null,
  p_checksum       text default null,
  p_cuerpo         jsonb default null,
  p_metodo_pago    text default null,
  p_correo_pagador text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_version smallint;
  v_uid_pre uuid;
  v_carrito_pre uuid;
  v_ins bigint;
  v_i pagos_intencion;
  v_carrito carritos;
  v_estado_w text := upper(btrim(coalesce(p_estado_wompi, '')));
  v_entorno_evento text;
  v_motivo text;
  v_items jsonb;
  v_lineas integer;
  v_min_ordinal integer;
  v_max_ordinal integer;
  v_total_lineas numeric;
  v_pedido jsonb;
  v_pedido_id uuid;
  v_customer_id uuid;
  v_consumidas integer;
  v_asiento jsonb;
begin
  -- Lectura de ruteo sin lock: v0/v1 conservan exactamente el núcleo previo.
  select pi.version_checkout, pi.auth_user_id, pi.carrito_id
    into v_version, v_uid_pre, v_carrito_pre
    from pagos_intencion pi
   where pi.referencia = p_referencia;

  if not found or coalesce(v_version, 0) <> 2 then
    return co__pw_procesar_pago_c3(
      p_transaccion_id, p_estado_wompi, p_referencia, p_monto_centavos,
      p_moneda, p_evento, p_checksum, p_cuerpo, p_metodo_pago, p_correo_pagador
    );
  end if;

  if coalesce(btrim(p_transaccion_id), '') = '' or v_estado_w = '' then
    raise exception 'PW_EVENTO_INVALIDO';
  end if;

  insert into pagos_eventos (
    transaccion_id, estado_wompi, referencia, evento, checksum, cuerpo, resultado
  ) values (
    p_transaccion_id, v_estado_w, nullif(p_referencia, ''),
    p_evento, p_checksum, p_cuerpo, 'ignorado'
  )
  on conflict (transaccion_id, estado_wompi) do nothing
  returning id into v_ins;

  if v_ins is null then
    return jsonb_build_object(
      'resultado', 'repetido',
      'pedido_id', (select pedido_id from pagos_intencion where referencia = p_referencia)
    );
  end if;

  -- Orden común con Cuentas y carrito. Los datos de la lectura preliminar se
  -- revalidan al bloquear la intención.
  perform 1 from auth.users u where u.id = v_uid_pre for update;
  if not found then
    update pagos_eventos set resultado = 'datos_no_coinciden' where id = v_ins;
    return jsonb_build_object('resultado', 'datos_no_coinciden');
  end if;

  perform 1 from cuentas_cliente cc
   where cc.auth_user_id = v_uid_pre for update;
  if not found then
    update pagos_eventos set resultado = 'datos_no_coinciden' where id = v_ins;
    return jsonb_build_object('resultado', 'datos_no_coinciden');
  end if;

  select * into v_carrito
    from carritos c where c.id = v_carrito_pre for update;
  if not found then
    update pagos_eventos set resultado = 'datos_no_coinciden' where id = v_ins;
    return jsonb_build_object('resultado', 'datos_no_coinciden');
  end if;

  select * into v_i
    from pagos_intencion pi where pi.referencia = p_referencia for update;
  if not found
     or v_i.version_checkout <> 2
     or v_i.auth_user_id is distinct from v_uid_pre
     or v_i.carrito_id is distinct from v_carrito_pre then
    update pagos_eventos set resultado = 'datos_no_coinciden' where id = v_ins;
    return jsonb_build_object('resultado', 'datos_no_coinciden');
  end if;

  if v_i.estado = 'procesada' then
    update pagos_eventos set resultado = 'ya_procesada' where id = v_ins;
    return jsonb_build_object('resultado', 'ya_procesada', 'pedido_id', v_i.pedido_id);
  end if;
  if v_i.estado = 'rechazada' then
    update pagos_eventos set resultado = 'ignorado' where id = v_ins;
    return jsonb_build_object('resultado', 'rechazado', 'estado', v_i.estado_wompi);
  end if;
  if v_i.estado = 'requiere_revision' then
    update pagos_eventos set resultado = 'ignorado' where id = v_ins;
    return jsonb_build_object('resultado', 'revision');
  end if;

  -- Todo checkout creado debe poseer exactamente su bloqueo explícito.
  if v_carrito.auth_user_id is distinct from v_i.auth_user_id
     or v_carrito.estado <> 'activa'
     or v_carrito.checkout_referencia is distinct from v_i.referencia
     or v_carrito.checkout_version is distinct from v_i.carrito_version then
    v_motivo := 'El bloqueo del carrito no coincide con la intención congelada.';
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           transaccion_id = p_transaccion_id, estado_wompi = v_estado_w,
           actualizado = now()
     where referencia = p_referencia;
    update pagos_eventos set resultado = 'datos_no_coinciden' where id = v_ins;
    return jsonb_build_object('resultado', 'datos_no_coinciden', 'motivo', v_motivo);
  end if;

  -- Terminal rechazado: libera, conserva líneas y avanza exactamente una vez
  -- el reloj optimista para invalidar la versión que estuvo congelada.
  if v_estado_w in ('DECLINED', 'VOIDED', 'ERROR') then
    update pagos_intencion
       set estado = 'rechazada', transaccion_id = p_transaccion_id,
           estado_wompi = v_estado_w,
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = now()
     where referencia = p_referencia;

    update carritos
       set checkout_referencia = null,
           checkout_version = null,
           checkout_bloqueado_en = null,
           version = version + 1,
           actualizado = now()
     where id = v_i.carrito_id
       and checkout_referencia = v_i.referencia;
    if not found then
      raise exception using errcode = 'XX000', message = 'PW_BLOQUEO_INCONSISTENTE';
    end if;

    update pagos_eventos set resultado = 'rechazado' where id = v_ins;
    return jsonb_build_object('resultado', 'rechazado', 'estado', v_estado_w);
  end if;

  -- PENDING y cualquier estado no terminal/desconocido conservan intención,
  -- líneas, versión y bloqueo; nunca se presentan como aprobación.
  if v_estado_w <> 'APPROVED' then
    update pagos_intencion
       set transaccion_id = p_transaccion_id,
           estado_wompi = v_estado_w,
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = now()
     where referencia = p_referencia;
    update pagos_eventos set resultado = 'ignorado' where id = v_ins;
    return jsonb_build_object('resultado', 'pendiente', 'estado', v_estado_w);
  end if;

  if p_monto_centavos is null or p_monto_centavos <> v_i.monto_centavos then
    v_motivo := format('El monto informado (%s) no coincide con el firmado (%s).',
      coalesce(p_monto_centavos::text, 'nulo'), v_i.monto_centavos);
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           transaccion_id = p_transaccion_id, estado_wompi = 'APPROVED',
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = now()
     where referencia = p_referencia;
    update pagos_eventos set resultado = 'monto_no_coincide' where id = v_ins;
    return jsonb_build_object('resultado', 'monto_no_coincide', 'motivo', v_motivo);
  end if;

  v_entorno_evento := case lower(coalesce(p_cuerpo->>'environment', ''))
    when 'test' then 'sandbox'
    when 'sandbox' then 'sandbox'
    when 'prod' then 'prod'
    when 'production' then 'prod'
    else null
  end;

  if upper(nullif(btrim(p_moneda), ''))
       is distinct from upper(nullif(btrim(v_i.moneda), '')) then
    v_motivo := 'La moneda informada no coincide con la intención.';
  elsif v_entorno_evento is null or v_entorno_evento is distinct from v_i.entorno then
    v_motivo := 'El entorno informado no coincide con la intención.';
  elsif v_carrito.version is distinct from v_i.carrito_version then
    v_motivo := 'La versión del carrito no coincide con la intención congelada.';
  end if;

  -- Bloquea primero las líneas en orden y valida el snapshot exacto actual.
  perform ci.campana_id
    from carrito_items ci
   where ci.carrito_id = v_i.carrito_id
   order by ci.campana_id
   for update;

  select count(*)::integer, min(pii.ordinal)::integer, max(pii.ordinal)::integer,
         coalesce(sum(pii.subtotal::numeric * 100), 0),
         coalesce(jsonb_agg(jsonb_build_object(
           'campana_id', pii.campana_id,
           'product_id', pii.product_id,
           'cantidad', pii.cantidad,
           'precio_unitario', pii.precio_unitario
         ) order by pii.ordinal), '[]'::jsonb)
    into v_lineas, v_min_ordinal, v_max_ordinal, v_total_lineas, v_items
    from pagos_intencion_items pii
   where pii.referencia = v_i.referencia;

  if v_motivo is null and (
       v_lineas not between 1 and 20
       or v_min_ordinal <> 1
       or v_max_ordinal <> v_lineas
       or v_total_lineas <> v_i.monto_centavos::numeric
       or exists (
         (select ci.campana_id, ci.cantidad
            from carrito_items ci where ci.carrito_id = v_i.carrito_id)
         except
         (select pii.campana_id, pii.cantidad
            from pagos_intencion_items pii where pii.referencia = v_i.referencia)
       )
       or exists (
         (select pii.campana_id, pii.cantidad
            from pagos_intencion_items pii where pii.referencia = v_i.referencia)
         except
         (select ci.campana_id, ci.cantidad
            from carrito_items ci where ci.carrito_id = v_i.carrito_id)
       )
     ) then
    v_motivo := 'Las líneas del carrito no coinciden exactamente con el snapshot firmado.';
  end if;

  if v_motivo is not null then
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           transaccion_id = p_transaccion_id, estado_wompi = 'APPROVED',
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = now()
     where referencia = p_referencia;
    update pagos_eventos set resultado = 'datos_no_coinciden' where id = v_ins;
    return jsonb_build_object('resultado', 'datos_no_coinciden', 'motivo', v_motivo);
  end if;

  -- Locks comerciales deterministas antes de resolver correo/cliente.
  perform p.id
    from productos p
    join (select distinct pii.product_id
            from pagos_intencion_items pii
           where pii.referencia = v_i.referencia) x on x.product_id = p.id
   order by p.id
   for update of p;
  if (select count(distinct pii.product_id) from pagos_intencion_items pii
       where pii.referencia = v_i.referencia)
     <> (select count(distinct p.id) from productos p
          join pagos_intencion_items pii on pii.product_id = p.id
         where pii.referencia = v_i.referencia) then
    v_motivo := 'El snapshot contiene un producto inexistente.';
  end if;

  perform cp.id
    from campana_producto cp
    join pagos_intencion_items pii on pii.campana_id = cp.id
   where pii.referencia = v_i.referencia
   order by cp.id
   for update of cp;
  if v_motivo is null and exists (
    select 1
      from pagos_intencion_items pii
      left join campana_producto cp on cp.id = pii.campana_id
     where pii.referencia = v_i.referencia
       and (cp.id is null or cp.product_id_ref is distinct from pii.product_id)
  ) then
    v_motivo := 'El vínculo campaña/producto cambió desde el snapshot.';
  end if;

  if v_motivo is not null then
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           transaccion_id = p_transaccion_id, estado_wompi = 'APPROVED',
           actualizado = now()
     where referencia = p_referencia;
    update pagos_eventos set resultado = 'datos_no_coinciden' where id = v_ins;
    return jsonb_build_object('resultado', 'datos_no_coinciden', 'motivo', v_motivo);
  end if;

  -- Subtransacción: vínculo, pedido, inventario/reserva, consumo y estados se
  -- confirman juntos. Una falla comercial P0001 revierte el bloque y deja
  -- revisión; fallos transitorios, constraints e invariantes XX000 se relanzan
  -- para revertir también el evento y permitir una entrega posterior.
  begin
    perform set_config('impulse.pago_servidor', 'on', true);
    perform set_config('impulse.checkout_legacy', 'off', true);
    perform set_config('impulse.checkout_c4', 'on', true);
    perform set_config('impulse.checkout_auth_user_id', v_i.auth_user_id::text, true);

    v_pedido := crear_pedido(
      p_nombre        => coalesce(v_i.comprador_nombre, 'Comprador web'),
      p_correo        => coalesce(v_i.comprador_correo, p_correo_pagador),
      p_telefono      => v_i.comprador_telefono,
      p_direccion     => v_i.comprador_direccion,
      p_ciudad        => v_i.comprador_ciudad,
      p_departamento  => v_i.comprador_departamento,
      p_pais          => v_i.comprador_pais,
      p_canal         => 'web',
      p_fecha_orden   => fz__fecha_colombia(),
      p_notas_pedido  => 'Pago web Wompi · referencia ' || v_i.referencia,
      p_items         => v_items
    );
    v_pedido_id := (v_pedido->>'pedido_id')::uuid;
    v_customer_id := (v_pedido->>'customer_id')::uuid;
    if v_pedido_id is null or v_customer_id is null then
      raise exception using errcode = 'XX000', message = 'C4_PEDIDO_INCONSISTENTE';
    end if;

    -- Se libera la cabecera bajo su lock antes del DELETE; el cambio aún no es
    -- visible fuera de la transacción y permite al trigger verificar el camino.
    update carritos
       set checkout_referencia = null,
           checkout_version = null,
           checkout_bloqueado_en = null,
           version = version + 1,
           actualizado = now()
     where id = v_i.carrito_id
       and checkout_referencia = v_i.referencia
       and checkout_version = v_i.carrito_version;
    if not found then
      raise exception using errcode = 'XX000', message = 'PW_BLOQUEO_INCONSISTENTE';
    end if;

    delete from carrito_items ci
     using pagos_intencion_items pii
     where pii.referencia = v_i.referencia
       and ci.carrito_id = v_i.carrito_id
       and ci.campana_id = pii.campana_id
       and ci.cantidad = pii.cantidad;
    get diagnostics v_consumidas = row_count;
    if v_consumidas <> v_lineas then
      raise exception using errcode = 'XX000', message = 'PW_CONSUMO_INCOMPLETO';
    end if;

    if exists (select 1 from carrito_items ci where ci.carrito_id = v_i.carrito_id) then
      raise exception using errcode = 'XX000', message = 'PW_CONSUMO_SNAPSHOT_INCONSISTENTE';
    end if;

    if v_i.utm_campaign is not null then
      update pedidos set utm_campaign = v_i.utm_campaign where id = v_pedido_id;
    end if;

    update pagos_intencion
       set estado = 'procesada', pedido_id = v_pedido_id,
           customer_id = v_customer_id,
           transaccion_id = p_transaccion_id, estado_wompi = 'APPROVED',
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           revision_motivo = null, procesada_en = now(), actualizado = now()
     where referencia = p_referencia;

    perform set_config('impulse.checkout_auth_user_id', '', true);
    perform set_config('impulse.checkout_c4', 'off', true);
    perform set_config('impulse.pago_servidor', 'off', true);
  exception when raise_exception then
    perform set_config('impulse.checkout_auth_user_id', '', true);
    perform set_config('impulse.checkout_c4', 'off', true);
    perform set_config('impulse.pago_servidor', 'off', true);
    v_motivo := sqlerrm;
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           transaccion_id = p_transaccion_id, estado_wompi = 'APPROVED',
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = now()
     where referencia = p_referencia;
    update pagos_eventos set resultado = 'sin_stock' where id = v_ins;
    return jsonb_build_object('resultado', 'sin_stock', 'motivo', v_motivo);
  end;

  update pagos_eventos set resultado = 'procesado' where id = v_ins;

  begin
    v_asiento := fz__asiento_venta_web(v_pedido_id);
  exception when others then
    v_asiento := jsonb_build_object('resultado', 'pendiente', 'motivo', sqlerrm);
  end;

  return jsonb_build_object(
    'resultado', 'procesado',
    'pedido_id', v_pedido_id,
    'asiento', v_asiento
  );
end;
$$;

comment on function pw_procesar_pago(text, text, text, bigint, text, text, text, jsonb, text, text) is
  'Pagos C4 · conserva firma y delega v0/v1 al núcleo histórico. v2 revalida snapshot/bloqueo, deriva customer_id desde Auth confirmado, crea pedido y consume exactamente líneas congeladas en una transacción; rechazo desbloquea y avanza versión, pendiente/revisión conservan bloqueo.';
revoke all on function pw_procesar_pago(text, text, text, bigint, text, text, text, jsonb, text, text)
  from public, anon, authenticated, service_role;
grant execute on function pw_procesar_pago(text, text, text, bigint, text, text, text, jsonb, text, text)
  to service_role;

-- ----------------------------------------------------------------------------
-- (G) Regreso público compatible: mismos tres campos, sin PII ni importes.
-- ----------------------------------------------------------------------------
create or replace function pw_estado_publico(p_referencia text)
returns table (
  estado text,
  nombre_producto text,
  slug text
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_estado text;
  v_version smallint;
  v_nombre text;
  v_slug text;
  v_lineas integer;
begin
  if p_referencia is null or p_referencia !~ '^[A-Za-z0-9_-]{6,64}$' then
    return;
  end if;

  select pi.estado, pi.version_checkout, coalesce(pi.nombre, ''), coalesce(pi.slug, '')
    into v_estado, v_version, v_nombre, v_slug
    from pagos_intencion pi
   where pi.referencia = p_referencia;
  if not found then return; end if;

  if v_version = 2 then
    select count(*)::integer,
           case when count(*) = 1 then coalesce(max(pii.nombre), '')
                else count(*)::text || ' productos de tu carrito' end,
           case when count(*) = 1 then coalesce(max(pii.slug), '') else '' end
      into v_lineas, v_nombre, v_slug
      from pagos_intencion_items pii
     where pii.referencia = p_referencia;

    if v_lineas = 0 then
      v_nombre := 'Productos de tu carrito';
      v_slug := '';
    end if;
  end if;

  return query select
    case v_estado
      when 'creada' then 'pendiente'
      when 'procesada' then 'aprobado'
      when 'rechazada' then 'rechazado'
      when 'requiere_revision' then 'revision'
      else 'pendiente'
    end,
    v_nombre,
    v_slug;
end;
$$;

comment on function pw_estado_publico(text) is
  'PAGOS WEB C4 · conserva tres campos y vocabulario. v2 identifica un producto o N productos del carrito sin exponer monto, PII, ids privados, pedido, transacción, motivo ni entorno.';
revoke all on function pw_estado_publico(text) from public, anon, authenticated, service_role;
grant execute on function pw_estado_publico(text) to service_role;

-- Mutaciones públicas: wrappers conservan firmas y semántica C2, pero revisan
-- la cabecera bloqueada antes de cualquier operación, incluso un cambio no-op.
alter function co_carrito_agregar(uuid, integer) rename to co__carrito_agregar_c2;
alter function co_carrito_cambiar(uuid, integer, bigint) rename to co__carrito_cambiar_c2;
alter function co_carrito_quitar(uuid, bigint) rename to co__carrito_quitar_c2;

revoke all on function co__carrito_agregar_c2(uuid, integer)
  from public, anon, authenticated, service_role;
revoke all on function co__carrito_cambiar_c2(uuid, integer, bigint)
  from public, anon, authenticated, service_role;
revoke all on function co__carrito_quitar_c2(uuid, bigint)
  from public, anon, authenticated, service_role;

create function co__exigir_carrito_editable()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_habilitado boolean;
  v_estado text;
  v_checkout_referencia text;
begin
  if v_uid is null then
    raise exception using errcode = 'P0001', message = 'CO_SESION_REQUERIDA';
  end if;

  select cfg.carrito_habilitado into v_habilitado
    from comercial_config cfg where cfg.id = 1 for share;
  if coalesce(v_habilitado, false) is not true then
    raise exception using errcode = 'P0001', message = 'CO_CARRITO_DESHABILITADO';
  end if;

  select cc.estado into v_estado
    from cuentas_cliente cc
   where cc.auth_user_id = v_uid
   for update;
  if not found or v_estado <> 'activa' then
    raise exception using errcode = 'P0001', message = 'CO_CUENTA_NO_DISPONIBLE';
  end if;

  select c.checkout_referencia into v_checkout_referencia
    from carritos c
   where c.auth_user_id = v_uid
     and c.estado = 'activa'
   for update;

  if found and v_checkout_referencia is not null then
    raise exception using errcode = 'P0001', message = 'CO_CARRITO_EN_CHECKOUT';
  end if;
end;
$$;

revoke all on function co__exigir_carrito_editable()
  from public, anon, authenticated, service_role;

create function co_carrito_agregar(p_campana_id uuid, p_cantidad integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform co__exigir_carrito_editable();
  return co__carrito_agregar_c2(p_campana_id, p_cantidad);
end;
$$;

create function co_carrito_cambiar(
  p_campana_id uuid,
  p_cantidad integer,
  p_version_esperada bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform co__exigir_carrito_editable();
  return co__carrito_cambiar_c2(p_campana_id, p_cantidad, p_version_esperada);
end;
$$;

create function co_carrito_quitar(
  p_campana_id uuid,
  p_version_esperada bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform co__exigir_carrito_editable();
  return co__carrito_quitar_c2(p_campana_id, p_version_esperada);
end;
$$;

comment on function co_carrito_agregar(uuid, integer) is
  'Comercial C4 · conserva firma/semántica C2 y rechaza explícitamente cualquier carrito bloqueado por checkout.';
comment on function co_carrito_cambiar(uuid, integer, bigint) is
  'Comercial C4 · conserva firma/semántica C2 y rechaza explícitamente carrito bloqueado, incluso si la cantidad solicitada no cambia.';
comment on function co_carrito_quitar(uuid, bigint) is
  'Comercial C4 · conserva firma/semántica C2 y rechaza explícitamente cualquier carrito bloqueado por checkout.';

-- Reafirma superficie mínima de carrito: listar informa solo el booleano y las
-- tres mutaciones pasan por el guard explícito, además del trigger defensivo.
revoke all on function co_carrito_listar() from public, anon, authenticated, service_role;
revoke all on function co_carrito_agregar(uuid, integer) from public, anon, authenticated, service_role;
revoke all on function co_carrito_cambiar(uuid, integer, bigint) from public, anon, authenticated, service_role;
revoke all on function co_carrito_quitar(uuid, bigint) from public, anon, authenticated, service_role;
grant execute on function co_carrito_listar() to authenticated, service_role;
grant execute on function co_carrito_agregar(uuid, integer) to authenticated, service_role;
grant execute on function co_carrito_cambiar(uuid, integer, bigint) to authenticated, service_role;
grant execute on function co_carrito_quitar(uuid, bigint) to authenticated, service_role;

-- Convención nominal del proyecto: service_role puede ejecutar toda función de
-- public; los helpers siguen cerrados para public/anon/authenticated y ninguna
-- identidad cliente gana superficie nueva.
grant execute on function co__proteger_lineas_checkout() to service_role;
grant execute on function co__resolver_customer_checkout(text, text, text, text, text) to service_role;
grant execute on function co__crear_pedido_c3(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb) to service_role;
grant execute on function co__pw_registrar_intencion_carrito_c3(text, uuid, uuid, bigint, text, jsonb, text, text, text) to service_role;
grant execute on function co__pw_procesar_pago_c3(text, text, text, bigint, text, text, text, jsonb, text, text) to service_role;
grant execute on function co__carrito_agregar_c2(uuid, integer) to service_role;
grant execute on function co__carrito_cambiar_c2(uuid, integer, bigint) to service_role;
grant execute on function co__carrito_quitar_c2(uuid, bigint) to service_role;
grant execute on function co__exigir_carrito_editable() to service_role;

-- Las tablas privadas no ganan grants por C4.
revoke all on table pagos_intencion_items from public, anon, authenticated;
revoke all on table comercial_config from public, anon, authenticated;

commit;
