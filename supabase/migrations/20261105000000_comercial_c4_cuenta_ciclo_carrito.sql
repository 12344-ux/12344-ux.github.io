-- ============================================================================
-- MAGANDHI · COMERCIAL C4 · CUENTA Y CICLO DEL CARRITO
-- ----------------------------------------------------------------------------
-- Migración FORWARD sobre 20261104000000. No modifica migraciones históricas.
-- Conserva las firmas públicas y despacha v0/v1 al cuerpo literal de C3.
-- El flag comercial_config.carrito_habilitado permanece sin cambios (OFF).
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- (A) Evidencia durable del destinatario y del ciclo v2.
-- ----------------------------------------------------------------------------
alter table pedidos
  add column if not exists destinatario_nombre text,
  add column if not exists destinatario_correo text,
  add column if not exists destinatario_telefono text;

alter table pedido_items
  add column if not exists campana_id uuid references campana_producto(id) on delete restrict,
  add column if not exists campana_nombre text,
  add column if not exists campana_slug text;

comment on column pedido_items.campana_id is
  'C4 · campaña exacta congelada al crear una línea desde checkout de carrito; nullable para pedidos históricos.';
comment on column pedido_items.campana_nombre is
  'C4 · nombre de campaña congelado para correos; fallback histórico al producto cuando es null.';
comment on column pedido_items.campana_slug is
  'C4 · slug de campaña congelado para correos; nullable para pedidos históricos.';

comment on column pedidos.destinatario_nombre is
  'C4 · snapshot nullable del nombre destinatario en pedidos web. Pedidos históricos usan fallback al cliente.';
comment on column pedidos.destinatario_correo is
  'C4 · snapshot nullable del correo destinatario en pedidos web. No cambia la identidad de acceso de auth.users.';
comment on column pedidos.destinatario_telefono is
  'C4 · snapshot nullable del teléfono destinatario en pedidos web.';

alter table pagos_intencion
  add column if not exists ciclo_carrito_version smallint not null default 0,
  add column if not exists expira_en timestamptz,
  add column if not exists carrito_liberado_en timestamptz,
  add column if not exists carrito_consumido_en timestamptz,
  add column if not exists carrito_consumo_resultado text,
  add column if not exists carrito_consumo_detalle jsonb;

alter table pagos_intencion
  add constraint pagos_intencion_ciclo_carrito_version
    check (
      (version_checkout = 2 and ciclo_carrito_version in (0, 4))
      or (version_checkout in (0, 1) and ciclo_carrito_version = 0)
    ),
  add constraint pagos_intencion_expiracion_c4
    check (
      (version_checkout = 2 and ciclo_carrito_version = 4 and expira_en is not null)
      or not (version_checkout = 2 and ciclo_carrito_version = 4)
    ),
  add constraint pagos_intencion_consumo_carrito_resultado
    check (carrito_consumo_resultado is null or carrito_consumo_resultado in ('completo','parcial')),
  add constraint pagos_intencion_ciclo_carrito_solo_v2
    check (
      version_checkout = 2
      or (
        carrito_liberado_en is null
        and carrito_consumido_en is null
        and carrito_consumo_resultado is null
        and carrito_consumo_detalle is null
      )
    ),
  add constraint pagos_intencion_consumo_carrito_coherente
    check (
      (carrito_consumido_en is null and carrito_consumo_resultado is null and carrito_consumo_detalle is null)
      or
      (carrito_consumido_en is not null and carrito_consumo_resultado is not null and carrito_consumo_detalle is not null)
    );

comment on column pagos_intencion.ciclo_carrito_version is
  'C4 · 0 identifica snapshots v2 creados antes del despliegue; 4 marca intenciones nuevas con bloqueo y ciclo autoritativo C4.';
comment on column pagos_intencion.expira_en is
  'C4 · vencimiento durable fijado por servidor exactamente 30 minutos después de crear la intención; el mismo ISO8601 se firma y se envía a Wompi.';
comment on column pagos_intencion.carrito_liberado_en is
  'C4 · terminal DECLINED/VOIDED/ERROR v2 liberado una sola vez; prueba de idempotencia del incremento de versión.';
comment on column pagos_intencion.carrito_consumido_en is
  'C4 · instante en que APPROVED v2 consumió una sola vez las cantidades congeladas.';
comment on column pagos_intencion.carrito_consumo_resultado is
  'C4 · completo si se consumió todo el snapshot; parcial si alguna cantidad ya no estaba, preservando extras.';
comment on column pagos_intencion.carrito_consumo_detalle is
  'C4 · auditoría privada agregada del consumo; no contiene PII, monto ni pedido.';

create table pw_sucesiones_c4 (
  referencia_predecesora text primary key references pagos_intencion(referencia) on delete restrict,
  carrito_id uuid not null references carritos(id) on delete restrict,
  version_predecesora bigint not null,
  version_sucesora bigint not null,
  creado timestamptz not null default now(),
  constraint pw_sucesiones_c4_version check (version_sucesora = version_predecesora + 1)
);
comment on table pw_sucesiones_c4 is
  'Privada C4 · evidencia idempotente del único salto técnico que retira una intención ciclo 0 sin modificarla.';
alter table pw_sucesiones_c4 enable row level security;
revoke all on table pw_sucesiones_c4 from public, anon, authenticated, service_role;

-- Las intenciones C3 ya existentes conservan ciclo=0 y no quedan bloqueadas de
-- forma retroactiva. Toda intención v2 creada después de esta migración nace
-- con ciclo=4; v0/v1 permanecen en 0.
create function pw__marcar_ciclo_carrito_c4()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.ciclo_carrito_version := case when new.version_checkout = 2 then 4 else 0 end;
  if new.version_checkout = 2 then
    new.expira_en := date_trunc('milliseconds', transaction_timestamp() + interval '30 minutes');
  else
    new.expira_en := null;
  end if;
  return new;
end;
$$;

revoke execute on function pw__marcar_ciclo_carrito_c4() from public, anon, authenticated;
grant execute on function pw__marcar_ciclo_carrito_c4() to service_role;

create trigger trg_pw_marcar_ciclo_carrito_c4
  before insert on pagos_intencion
  for each row execute function pw__marcar_ciclo_carrito_c4();

-- Conserva la firma service_role de C3 y añade únicamente la expiración exacta
-- que fijó el trigger. El cuerpo C3 y su idempotencia permanecen intactos.
alter function pw_registrar_intencion_carrito(text, uuid, uuid, bigint, text, jsonb, text, text, text)
  rename to pw__registrar_intencion_carrito_c3;
revoke all on function pw__registrar_intencion_carrito_c3(text, uuid, uuid, bigint, text, jsonb, text, text, text)
  from public, anon, authenticated, service_role;

create function pw_registrar_intencion_carrito(
  p_referencia text, p_auth_user_id uuid, p_carrito_id uuid,
  p_version_esperada bigint, p_entorno text, p_comprador jsonb default '{}'::jsonb,
  p_utm_campaign text default null, p_mg_vid text default null,
  p_moneda text default 'COP'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_resultado jsonb;
  v_expira_en timestamptz;
  v_version_registro bigint := p_version_esperada;
  v_version_actual bigint;
  v_predecesora text;
begin
  -- Mismo prefijo de locks que C3: configuración -> cuenta -> carrito. Las
  -- transiciones que sólo liberan/avanzan retornan sin error para que hagan
  -- commit; la Edge repite una vez con reintentar_version.
  perform 1 from comercial_config cfg where cfg.id = 1 for share;
  perform 1 from cuentas_cliente cc
   where cc.auth_user_id = p_auth_user_id for update;
  select c.version into v_version_actual
    from carritos c
   where c.id = p_carrito_id
     and c.auth_user_id = p_auth_user_id
     and c.estado = 'activa'
   for update;

  if found then
    perform pi.referencia
      from pagos_intencion pi
     where pi.version_checkout = 2
       and pi.auth_user_id = p_auth_user_id
       and pi.carrito_id = p_carrito_id
       and pi.carrito_version = p_version_esperada
     order by pi.referencia
     for update;

    if v_version_actual = p_version_esperada then
      select pi.referencia into v_predecesora
        from pagos_intencion pi
       where pi.version_checkout = 2
         and pi.ciclo_carrito_version = 4
         and pi.auth_user_id = p_auth_user_id
         and pi.carrito_id = p_carrito_id
         and pi.carrito_version = p_version_esperada
         and pi.estado = 'creada'
         and pi.carrito_liberado_en is null
         and pi.expira_en <= statement_timestamp()
       order by pi.referencia limit 1;

      if v_predecesora is not null then
        update pagos_intencion
           set estado = 'rechazada', estado_wompi = 'EXPIRED',
               revision_motivo = 'C4_INTENCION_EXPIRADA',
               carrito_liberado_en = statement_timestamp(),
               actualizado = statement_timestamp()
         where referencia = v_predecesora and carrito_liberado_en is null;
        update carritos
           set version = version + 1, actualizado = statement_timestamp()
         where id = p_carrito_id
         returning version into v_version_registro;
        return jsonb_build_object('reintentar_version', v_version_registro);
      end if;

      select pi.referencia into v_predecesora
        from pagos_intencion pi
       where pi.version_checkout = 2
         and pi.ciclo_carrito_version = 0
         and pi.auth_user_id = p_auth_user_id
         and pi.carrito_id = p_carrito_id
         and pi.carrito_version = p_version_esperada
         and pi.estado in ('creada', 'rechazada')
       order by pi.referencia limit 1;

      if v_predecesora is not null then
        insert into pw_sucesiones_c4 (
          referencia_predecesora, carrito_id, version_predecesora, version_sucesora
        ) values (
          v_predecesora, p_carrito_id, p_version_esperada, p_version_esperada + 1
        ) on conflict (referencia_predecesora) do nothing;
        update carritos
           set version = version + 1, actualizado = statement_timestamp()
         where id = p_carrito_id
         returning version into v_version_registro;
        return jsonb_build_object('reintentar_version', v_version_registro);
      end if;
    elsif v_version_actual = p_version_esperada + 1 and (
      exists (
        select 1 from pw_sucesiones_c4 s
         where s.carrito_id = p_carrito_id
           and s.version_predecesora = p_version_esperada
           and s.version_sucesora = v_version_actual
      ) or exists (
        select 1 from pagos_intencion pi
         where pi.version_checkout = 2
           and pi.ciclo_carrito_version = 4
           and pi.auth_user_id = p_auth_user_id
           and pi.carrito_id = p_carrito_id
           and pi.carrito_version = p_version_esperada
           and pi.carrito_liberado_en is not null
      )
    ) then
      return jsonb_build_object('reintentar_version', v_version_actual);
    end if;
  end if;

  v_resultado := pw__registrar_intencion_carrito_c3(
    p_referencia, p_auth_user_id, p_carrito_id, v_version_registro,
    p_entorno, p_comprador, p_utm_campaign, p_mg_vid, p_moneda
  );
  select pi.expira_en into v_expira_en
    from pagos_intencion pi
   where pi.referencia = v_resultado->>'referencia';
  if v_expira_en is null then
    raise exception using errcode = 'XX000', message = 'PW_EXPIRACION_C4_AUSENTE';
  end if;
  return v_resultado || jsonb_build_object(
    'expira_en', to_char(v_expira_en at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
  );
end;
$$;

comment on function pw_registrar_intencion_carrito(text, uuid, uuid, bigint, text, jsonb, text, text, text) is
  'C4 · firma C3 intacta; devuelve el snapshot autoritativo más expira_en ISO8601 exacto fijado por servidor.';
revoke all on function pw_registrar_intencion_carrito(text, uuid, uuid, bigint, text, jsonb, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function pw_registrar_intencion_carrito(text, uuid, uuid, bigint, text, jsonb, text, text, text)
  to service_role;

-- ----------------------------------------------------------------------------
-- (B) Estado de bloqueo server-side del carrito.
-- ----------------------------------------------------------------------------
-- El llamador debe poseer el lock de la cabecera del carrito. La transición
-- creada -> rechazada/EXPIRED y el versionado quedan en la misma transacción.
create function co__liberar_expiradas_c4(p_carrito_id uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_liberadas integer := 0;
begin
  perform pi.referencia
    from pagos_intencion pi
   where pi.version_checkout = 2
     and pi.ciclo_carrito_version = 4
     and pi.carrito_id = p_carrito_id
     and pi.estado = 'creada'
     and pi.expira_en <= statement_timestamp()
   order by pi.referencia
   for update;

  update pagos_intencion pi
     set estado = 'rechazada',
         estado_wompi = 'EXPIRED',
         revision_motivo = 'C4_INTENCION_EXPIRADA',
         carrito_liberado_en = statement_timestamp(),
         actualizado = statement_timestamp()
   where pi.version_checkout = 2
     and pi.ciclo_carrito_version = 4
     and pi.carrito_id = p_carrito_id
     and pi.estado = 'creada'
     and pi.expira_en <= statement_timestamp()
     and pi.carrito_liberado_en is null;
  get diagnostics v_liberadas = row_count;

  if v_liberadas > 0 then
    update carritos
       set version = version + 1, actualizado = statement_timestamp()
     where id = p_carrito_id;
  end if;
  return v_liberadas > 0;
end;
$$;

comment on function co__liberar_expiradas_c4(uuid) is
  'Interna C4 · bajo lock de carrito expira intenciones creadas vencidas, libera y aumenta la versión exactamente una vez.';
revoke all on function co__liberar_expiradas_c4(uuid) from public, anon, authenticated, service_role;

create or replace function co__bloqueo_pago(p_carrito_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
    when exists (
      select 1 from pagos_intencion pi
       where pi.version_checkout = 2
         and pi.ciclo_carrito_version = 4
         and pi.carrito_id = p_carrito_id
         and pi.estado = 'requiere_revision'
         and pi.resuelta_en is null
    ) then 'revision'
    when exists (
      select 1 from pagos_intencion pi
       where pi.version_checkout = 2
         and pi.ciclo_carrito_version = 4
         and pi.carrito_id = p_carrito_id
         and pi.estado = 'creada'
         and pi.expira_en > statement_timestamp()
    ) then 'pendiente'
    else null
  end;
$$;

comment on function co__bloqueo_pago(uuid) is
  'Interna C4 · devuelve pendiente/revision cuando una intención v2 mantiene bloqueado el carrito; no expone la referencia.';
revoke all on function co__bloqueo_pago(uuid) from public, anon, authenticated, service_role;
grant execute on function co__bloqueo_pago(uuid) to service_role;

create or replace function co__carrito_snapshot()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid          uuid := auth.uid();
  v_habilitado   boolean := false;
  v_carrito_id   uuid;
  v_version      bigint;
  v_lineas       bigint := 0;
  v_unidades     bigint := 0;
  v_items        jsonb := '[]'::jsonb;
  v_bloqueo_pago text;
begin
  select coalesce(cfg.carrito_habilitado, false)
    into v_habilitado
    from comercial_config cfg
   where cfg.id = 1;

  select c.id, c.version
    into v_carrito_id, v_version
    from carritos c
   where c.auth_user_id = v_uid
     and c.estado = 'activa';

  if v_carrito_id is not null then
    perform co__liberar_expiradas_c4(v_carrito_id);
    select c.version into v_version from carritos c where c.id = v_carrito_id;
    v_bloqueo_pago := co__bloqueo_pago(v_carrito_id);

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
    'cantidad_lineas', coalesce(v_lineas, 0),
    'cantidad_unidades', coalesce(v_unidades, 0),
    'items', coalesce(v_items, '[]'::jsonb),
    'bloqueo_pago', v_bloqueo_pago
  );
end;
$$;

comment on function co__carrito_snapshot() is
  'Interna C2+C4 · snapshot canónico desde catalogo_publico y bloqueo_pago null|pendiente|revision, sin exponer referencia ni datos privados.';
revoke execute on function co__carrito_snapshot() from public, anon, authenticated;
grant execute on function co__carrito_snapshot() to service_role;

-- Los cuerpos C2 quedan literales y privados. Los wrappers conservan firmas,
-- errores normales y grants, pero toman cuenta/cabecera antes de comprobar C4.
alter function co_carrito_agregar(uuid, integer) rename to co__carrito_agregar_c3;
alter function co_carrito_cambiar(uuid, integer, bigint) rename to co__carrito_cambiar_c3;
alter function co_carrito_quitar(uuid, bigint) rename to co__carrito_quitar_c3;

revoke all on function co__carrito_agregar_c3(uuid, integer) from public, anon, authenticated, service_role;
revoke all on function co__carrito_cambiar_c3(uuid, integer, bigint) from public, anon, authenticated, service_role;
revoke all on function co__carrito_quitar_c3(uuid, bigint) from public, anon, authenticated, service_role;

create function co_carrito_agregar(p_campana_id uuid, p_cantidad integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_habilitado boolean;
  v_estado text;
  v_carrito_id uuid;
begin
  if v_uid is null then
    raise exception using errcode = 'P0001', message = 'CO_SESION_REQUERIDA';
  end if;
  select carrito_habilitado into v_habilitado
    from comercial_config where id = 1 for share;
  if coalesce(v_habilitado, false) is not true then
    raise exception using errcode = 'P0001', message = 'CO_CARRITO_DESHABILITADO';
  end if;
  select estado into v_estado from cuentas_cliente
   where auth_user_id = v_uid for update;
  if not found or v_estado <> 'activa' then
    raise exception using errcode = 'P0001', message = 'CO_CUENTA_NO_DISPONIBLE';
  end if;
  select id into v_carrito_id from carritos
   where auth_user_id = v_uid and estado = 'activa' for update;
  if v_carrito_id is not null and co__liberar_expiradas_c4(v_carrito_id) then
    return co__carrito_snapshot();
  end if;
  if v_carrito_id is not null and co__bloqueo_pago(v_carrito_id) is not null then
    raise exception using errcode = 'P0001', message = 'CO_CARRITO_BLOQUEADO';
  end if;
  return co__carrito_agregar_c3(p_campana_id, p_cantidad);
end;
$$;

create function co_carrito_cambiar(p_campana_id uuid, p_cantidad integer, p_version_esperada bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_habilitado boolean;
  v_estado text;
  v_carrito_id uuid;
begin
  if v_uid is null then
    raise exception using errcode = 'P0001', message = 'CO_SESION_REQUERIDA';
  end if;
  select carrito_habilitado into v_habilitado
    from comercial_config where id = 1 for share;
  if coalesce(v_habilitado, false) is not true then
    raise exception using errcode = 'P0001', message = 'CO_CARRITO_DESHABILITADO';
  end if;
  select estado into v_estado from cuentas_cliente
   where auth_user_id = v_uid for update;
  if not found or v_estado <> 'activa' then
    raise exception using errcode = 'P0001', message = 'CO_CUENTA_NO_DISPONIBLE';
  end if;
  select id into v_carrito_id from carritos
   where auth_user_id = v_uid and estado = 'activa' for update;
  if v_carrito_id is not null and co__liberar_expiradas_c4(v_carrito_id) then
    return co__carrito_snapshot();
  end if;
  if v_carrito_id is not null and co__bloqueo_pago(v_carrito_id) is not null then
    raise exception using errcode = 'P0001', message = 'CO_CARRITO_BLOQUEADO';
  end if;
  return co__carrito_cambiar_c3(p_campana_id, p_cantidad, p_version_esperada);
end;
$$;

create function co_carrito_quitar(p_campana_id uuid, p_version_esperada bigint)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_habilitado boolean;
  v_estado text;
  v_carrito_id uuid;
begin
  if v_uid is null then
    raise exception using errcode = 'P0001', message = 'CO_SESION_REQUERIDA';
  end if;
  select carrito_habilitado into v_habilitado
    from comercial_config where id = 1 for share;
  if coalesce(v_habilitado, false) is not true then
    raise exception using errcode = 'P0001', message = 'CO_CARRITO_DESHABILITADO';
  end if;
  select estado into v_estado from cuentas_cliente
   where auth_user_id = v_uid for update;
  if not found or v_estado <> 'activa' then
    raise exception using errcode = 'P0001', message = 'CO_CUENTA_NO_DISPONIBLE';
  end if;
  select id into v_carrito_id from carritos
   where auth_user_id = v_uid and estado = 'activa' for update;
  if v_carrito_id is not null and co__liberar_expiradas_c4(v_carrito_id) then
    return co__carrito_snapshot();
  end if;
  if v_carrito_id is not null and co__bloqueo_pago(v_carrito_id) is not null then
    raise exception using errcode = 'P0001', message = 'CO_CARRITO_BLOQUEADO';
  end if;
  return co__carrito_quitar_c3(p_campana_id, p_version_esperada);
end;
$$;

comment on function co_carrito_agregar(uuid, integer) is
  'Comercial C2+C4 · misma firma; tras lock cuenta/carrito rechaza CO_CARRITO_BLOQUEADO si una intención v2 está pendiente o en revisión.';
comment on function co_carrito_cambiar(uuid, integer, bigint) is
  'Comercial C2+C4 · misma firma y concurrencia optimista; no permite mutar un carrito bloqueado por pago v2.';
comment on function co_carrito_quitar(uuid, bigint) is
  'Comercial C2+C4 · misma firma; una campaña retirada se puede quitar salvo durante bloqueo de pago v2.';

revoke all on function co_carrito_agregar(uuid, integer) from public, anon, authenticated, service_role;
revoke all on function co_carrito_cambiar(uuid, integer, bigint) from public, anon, authenticated, service_role;
revoke all on function co_carrito_quitar(uuid, bigint) from public, anon, authenticated, service_role;
grant execute on function co_carrito_agregar(uuid, integer) to authenticated, service_role;
grant execute on function co_carrito_cambiar(uuid, integer, bigint) to authenticated, service_role;
grant execute on function co_carrito_quitar(uuid, bigint) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (C) La firma pública crear_pedido delega siempre al cuerpo C3. C4 usa un
--     helper privado con UID explícito; ninguna GUC selecciona este camino.
-- ----------------------------------------------------------------------------
alter function crear_pedido(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb)
  rename to crear_pedido_c3_base;
revoke all on function crear_pedido_c3_base(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb)
  from public, anon, authenticated, service_role;

create function crear_pedido_c4(
  p_auth_user_id  uuid,
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
  v_uid uuid := p_auth_user_id;
  v_customer_id uuid;
  v_estado_cuenta text;
  v_auth_correo text;
  v_confirmado_en timestamptz;
  v_correo_norm text;
  v_destinatario_correo text;
  v_cliente_correo text;
  v_item jsonb;
  v_item_pedido_id uuid;
  v_coincidencias integer;
  v_candidato uuid;
  v_vinculado_a uuid;
  v_resultado jsonb;
  v_pedido_id uuid;
  v_filas integer;
begin
  if v_uid is null then
    raise exception using errcode = 'P0001', message = 'C4_IDENTIDAD_INVALIDA';
  end if;

  -- Adquiere primero TODOS los locks comerciales en el mismo orden del núcleo.
    perform p.id
      from productos p
      join (
        select distinct (e->>'product_id')::uuid as id
          from jsonb_array_elements(p_items) e
      ) x on x.id = p.id
     order by p.id
     for update of p;

    perform cp.id
      from campana_producto cp
      join (
        select distinct nullif(e->>'campana_id', '')::uuid as id
          from jsonb_array_elements(p_items) e
      ) x on x.id = cp.id
     order by cp.id
     for update of cp;

    -- pw_procesar_pago ya posee auth.users->cuenta->carrito->intención. Esta
    -- relectura ocurre DESPUÉS de producto/campaña y no abre una ruta pública.
    select cc.customer_id, cc.estado
      into v_customer_id, v_estado_cuenta
      from cuentas_cliente cc
     where cc.auth_user_id = v_uid
     for update;
    if not found or v_estado_cuenta <> 'activa' then
      raise exception using errcode = 'P0001', message = 'C4_CUENTA_NO_DISPONIBLE';
    end if;

    select u.email, u.email_confirmed_at
      into v_auth_correo, v_confirmado_en
      from auth.users u
     where u.id = v_uid;
    v_correo_norm := ventas_norm_correo(v_auth_correo);

    if v_customer_id is null then
      if exists (
        select 1
          from cc_conflictos_revision r
         where r.auth_user_id = v_uid
           and r.estado = 'pendiente'
      ) then
        raise exception using errcode = 'P0001', message = 'C4_CONFLICTO_IDENTIDAD_PENDIENTE';
      end if;

      if v_confirmado_en is null or v_correo_norm is null then
        raise exception using errcode = 'P0001', message = 'C4_CORREO_NO_CONFIRMADO';
      end if;

      perform pg_advisory_xact_lock(hashtextextended('cc-correo:' || v_correo_norm, 0));

      select count(*)::integer, (array_agg(c.id order by c.id))[1]
        into v_coincidencias, v_candidato
        from clientes c
       where ventas_norm_correo(c.correo_norm) = v_correo_norm
          or ventas_norm_correo(c.correo) = v_correo_norm;

      if v_coincidencias > 1 then
        raise exception using errcode = 'P0001', message = 'C4_CORREO_AMBIGUO';
      elsif v_coincidencias = 1 then
        select cc.auth_user_id into v_vinculado_a
          from cuentas_cliente cc
         where cc.customer_id = v_candidato;
        if found and v_vinculado_a is distinct from v_uid then
          raise exception using errcode = 'P0001', message = 'C4_CLIENTE_YA_VINCULADO';
        end if;
        v_customer_id := v_candidato;
      else
        insert into clientes (
          nombre, correo, correo_norm, telefono, telefono_norm,
          direccion, ciudad, departamento, pais, notas
        ) values (
          left('Cliente ' || split_part(v_correo_norm, '@', 1), 120),
          v_auth_correo, v_correo_norm,
          null, null, null, null, null, null, null
        )
        returning id into v_customer_id;
      end if;

      begin
        update cuentas_cliente
           set customer_id = v_customer_id,
               vinculado_en = now(),
               actualizado = now()
         where auth_user_id = v_uid
           and customer_id is null;
        get diagnostics v_filas = row_count;
      exception when unique_violation then
        raise exception using errcode = 'P0001', message = 'C4_CONFLICTO_VINCULO';
      end;

      if v_filas = 0 then
        select customer_id into v_candidato from cuentas_cliente
         where auth_user_id = v_uid;
        if v_candidato is distinct from v_customer_id then
          raise exception using errcode = 'P0001', message = 'C4_CONFLICTO_VINCULO';
        end if;
      end if;
    else
      perform 1 from clientes where id = v_customer_id;
      if not found then
        raise exception using errcode = 'P0001', message = 'C4_CLIENTE_NO_EXISTE';
      end if;
    end if;

    select c.correo into v_cliente_correo from clientes c where c.id = v_customer_id;
    v_destinatario_correo := case
      when nullif(btrim(p_correo), '') ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
        then btrim(p_correo)
      when v_confirmado_en is not null
       and nullif(btrim(v_auth_correo), '') ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
        then btrim(v_auth_correo)
      when nullif(btrim(v_cliente_correo), '') ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
        then btrim(v_cliente_correo)
      else null
    end;

    -- El customer_id nace exclusivamente del UID explícito y la cuenta.
    v_resultado := crear_pedido_c3_base(
      p_customer_id => v_customer_id,
      p_nombre => p_nombre,
      p_correo => v_destinatario_correo,
      p_telefono => p_telefono,
      p_direccion => p_direccion,
      p_ciudad => p_ciudad,
      p_departamento => p_departamento,
      p_pais => p_pais,
      p_notas_cliente => null,
      p_canal => p_canal,
      p_fecha_orden => p_fecha_orden,
      p_notas_pedido => p_notas_pedido,
      p_items => p_items
    );

  -- Todo pedido web nuevo congela destinatario. Las columnas nullable dejan a
  -- los pedidos históricos con el fallback anterior de correo_pedido_preparar.
  if coalesce(nullif(btrim(p_canal), ''), 'manual') = 'web' then
    v_pedido_id := (v_resultado->>'pedido_id')::uuid;
    update pedidos
       set destinatario_nombre = nullif(btrim(p_nombre), ''),
           destinatario_correo = v_destinatario_correo,
           destinatario_telefono = nullif(btrim(p_telefono), '')
     where id = v_pedido_id;

    -- El cuerpo C3 crea una fila por elemento en el mismo pedido. Se reclama
    -- una fila aún no congelada por sus valores comerciales y se completa con
    -- la campaña exacta del snapshot; duplicados equivalentes siguen siendo
    -- indistinguibles en importe/cantidad, pero cada campaña queda una vez.
    for v_item in select value from jsonb_array_elements(p_items)
    loop
      select pi.id into v_item_pedido_id
        from pedido_items pi
       where pi.pedido_id = v_pedido_id
         and pi.product_id = (v_item->>'product_id')::uuid
         and pi.cantidad = (v_item->>'cantidad')::integer
         and pi.precio_unitario = (v_item->>'precio_unitario')::bigint
         and pi.campana_id is null
       order by pi.id
       limit 1
       for update;
      if v_item_pedido_id is null then
        raise exception using errcode = 'P0001', message = 'C4_LINEA_PEDIDO_NO_ENCONTRADA';
      end if;
      update pedido_items
         set campana_id = nullif(v_item->>'campana_id', '')::uuid,
             campana_nombre = nullif(v_item->>'nombre', ''),
             campana_slug = nullif(v_item->>'slug', '')
       where id = v_item_pedido_id;
      v_item_pedido_id := null;
    end loop;
  end if;

  return v_resultado;
end;
$$;

comment on function crear_pedido_c4(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb) is
  'Helper privado C4 · UID explícito, deriva cuenta/cliente sólo desde Auth confirmado, conserva destinatario en pedido y congela campaña en pedido_items.';
revoke all on function crear_pedido_c4(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb)
  from public, anon, authenticated, service_role;

create function crear_pedido(
  p_customer_id uuid default null, p_nombre text default null,
  p_correo text default null, p_telefono text default null,
  p_direccion text default null, p_ciudad text default null,
  p_departamento text default null, p_pais text default null,
  p_notas_cliente text default null, p_canal text default 'manual',
  p_fecha_orden date default current_date, p_notas_pedido text default null,
  p_items jsonb default '[]'::jsonb
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select crear_pedido_c3_base(
    p_customer_id, p_nombre, p_correo, p_telefono, p_direccion, p_ciudad,
    p_departamento, p_pais, p_notas_cliente, p_canal, p_fecha_orden,
    p_notas_pedido, p_items
  );
$$;

comment on function crear_pedido(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb) is
  'Firma pública histórica: delega exclusivamente al cuerpo C3 base. C4 sólo puede entrar por su helper privado con UID explícito.';
revoke execute on function crear_pedido(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb)
  from public, anon;
grant execute on function crear_pedido(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb)
  to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (D) Webhook C4. El cuerpo C3 se conserva literal como helper para v0/v1.
--     v2 prelee IDs sin lock y luego fija auth.users->cuenta->carrito->intención.
-- ----------------------------------------------------------------------------
alter function pw_procesar_pago(text, text, text, bigint, text, text, text, jsonb, text, text)
  rename to pw__procesar_pago_c3;
revoke all on function pw__procesar_pago_c3(text, text, text, bigint, text, text, text, jsonb, text, text)
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
  v_version_pre integer;
  v_uid_pre uuid;
  v_carrito_pre uuid;
  v_ins bigint;
  v_i pagos_intencion;
  v_auth_ok boolean;
  v_auth_correo text;
  v_auth_confirmado_en timestamptz;
  v_auth_correo_confirmado text;
  v_cuenta_ok boolean;
  v_carrito_ok boolean;
  v_estado_cuenta text;
  v_carrito_uid uuid;
  v_carrito_estado text;
  v_carrito_version bigint;
  v_estado_evento text := upper(btrim(coalesce(p_estado_wompi, '')));
  v_entorno_evento text;
  v_motivo text;
  v_items jsonb;
  v_lineas integer;
  v_min_ordinal integer;
  v_max_ordinal integer;
  v_total_lineas numeric;
  v_pedido jsonb;
  v_pedido_id uuid;
  v_asiento jsonb;
  v_req record;
  v_actual integer;
  v_faltantes integer := 0;
  v_consumidas integer := 0;
  v_resultado_consumo text;
begin
  -- Prelectura sin lock: solo decide el protocolo. v0/v1 y referencias ausentes
  -- ejecutan sin cambios el cuerpo C3 que quedó renombrado.
  select pi.version_checkout, pi.auth_user_id, pi.carrito_id
    into v_version_pre, v_uid_pre, v_carrito_pre
    from pagos_intencion pi
   where pi.referencia = p_referencia;

  if not found or v_version_pre <> 2 then
    return pw__procesar_pago_c3(
      p_transaccion_id, p_estado_wompi, p_referencia, p_monto_centavos,
      p_moneda, p_evento, p_checksum, p_cuerpo, p_metodo_pago, p_correo_pagador
    );
  end if;

  if coalesce(btrim(p_transaccion_id), '') = '' or v_estado_evento = '' then
    raise exception 'PW_EVENTO_INVALIDO';
  end if;

  insert into pagos_eventos (
    transaccion_id, estado_wompi, referencia, evento, checksum, cuerpo, resultado
  ) values (
    p_transaccion_id, v_estado_evento, nullif(p_referencia, ''),
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

  -- Orden global C4. Las ausencias se recuerdan, pero la intención se bloquea
  -- al final para poder llevar el pago a revisión de forma durable.
  select u.email, u.email_confirmed_at
    into v_auth_correo, v_auth_confirmado_en
    from auth.users u
   where u.id = v_uid_pre
   for update;
  v_auth_ok := found;
  v_auth_correo_confirmado := case
    when v_auth_confirmado_en is not null then nullif(btrim(v_auth_correo), '')
    else null
  end;

  select cc.estado into v_estado_cuenta from cuentas_cliente cc
   where cc.auth_user_id = v_uid_pre for update;
  v_cuenta_ok := found and v_estado_cuenta = 'activa';

  select c.auth_user_id, c.estado, c.version
    into v_carrito_uid, v_carrito_estado, v_carrito_version
    from carritos c where c.id = v_carrito_pre for update;
  v_carrito_ok := found
    and v_carrito_uid is not distinct from v_uid_pre
    and v_carrito_estado = 'activa';

  select * into v_i from pagos_intencion
   where referencia = p_referencia for update;

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

  -- APPROVED posterior a expiración o a cualquier rechazo nunca automatiza.
  -- Tampoco automatiza una intención vieja si ya existe una sucesora del mismo
  -- carrito: el pago se conserva en revisión y no puede crear doble pedido.
  if v_estado_evento = 'APPROVED' and (
       v_i.estado = 'rechazada'
       or (v_i.ciclo_carrito_version = 4 and v_i.expira_en <= statement_timestamp())
       or exists (
         select 1 from pagos_intencion s
          where s.version_checkout = 2
            and s.carrito_id = v_i.carrito_id
            and s.referencia <> v_i.referencia
            and (s.carrito_version > v_i.carrito_version or s.creado > v_i.creado)
       )
     ) then
    if v_i.carrito_liberado_en is null then
      update carritos set version = version + 1, actualizado = statement_timestamp()
       where id = v_i.carrito_id;
    end if;
    v_motivo := case
      when exists (
        select 1 from pagos_intencion s
         where s.version_checkout = 2 and s.carrito_id = v_i.carrito_id
           and s.referencia <> v_i.referencia
           and (s.carrito_version > v_i.carrito_version or s.creado > v_i.creado)
      ) then 'C4_APPROVED_CON_INTENCION_SUCESORA'
      when v_i.estado = 'rechazada' then 'C4_APPROVED_POSTERIOR_A_RECHAZO'
      else 'C4_APPROVED_POSTERIOR_A_EXPIRACION'
    end;
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           resuelta_en = null, resuelta_por = null, resuelta_nota = null,
           carrito_liberado_en = coalesce(carrito_liberado_en, statement_timestamp()),
           transaccion_id = p_transaccion_id, estado_wompi = 'APPROVED',
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = statement_timestamp()
     where referencia = p_referencia;
    update pagos_eventos set resultado = 'datos_no_coinciden' where id = v_ins;
    return jsonb_build_object('resultado', 'datos_no_coinciden', 'motivo', v_motivo);
  end if;

  if v_i.estado = 'rechazada' then
    update pagos_eventos set resultado = 'ignorado' where id = v_ins;
    return jsonb_build_object('resultado', 'ignorado', 'estado', 'rechazada');
  end if;
  if v_i.estado = 'requiere_revision' then
    update pagos_eventos set resultado = 'ignorado' where id = v_ins;
    return jsonb_build_object('resultado', 'ignorado', 'estado', 'requiere_revision');
  end if;

  if v_estado_evento <> 'APPROVED' then
    if v_estado_evento in ('DECLINED','VOIDED','ERROR') then
      if v_i.carrito_liberado_en is null then
        update carritos
           set version = version + 1, actualizado = now()
         where id = v_i.carrito_id;
      end if;
      update pagos_intencion
         set estado = 'rechazada', carrito_liberado_en = coalesce(carrito_liberado_en, now()),
             transaccion_id = p_transaccion_id, estado_wompi = v_estado_evento,
             metodo_pago = coalesce(p_metodo_pago, metodo_pago),
             correo_pagador = coalesce(p_correo_pagador, correo_pagador),
             actualizado = now()
       where referencia = p_referencia;
    else
      update pagos_intencion
         set transaccion_id = p_transaccion_id, estado_wompi = v_estado_evento,
             metodo_pago = coalesce(p_metodo_pago, metodo_pago),
             correo_pagador = coalesce(p_correo_pagador, correo_pagador),
             actualizado = now()
       where referencia = p_referencia;
    end if;
    update pagos_eventos set resultado = 'rechazado' where id = v_ins;
    return jsonb_build_object('resultado', 'rechazado', 'estado', v_estado_evento);
  end if;

  if not v_auth_ok or not v_cuenta_ok or not v_carrito_ok then
    v_motivo := 'C4_IDENTIDAD_O_CARRITO_NO_DISPONIBLE';
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           transaccion_id = p_transaccion_id, estado_wompi = v_estado_evento,
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = now()
     where referencia = p_referencia;
    update pagos_eventos set resultado = 'datos_no_coinciden' where id = v_ins;
    return jsonb_build_object('resultado', 'datos_no_coinciden', 'motivo', v_motivo);
  end if;

  if p_monto_centavos is null or p_monto_centavos <> v_i.monto_centavos then
    v_motivo := format('El monto informado (%s) no coincide con el firmado (%s).',
      coalesce(p_monto_centavos::text, 'nulo'), v_i.monto_centavos);
  end if;

  v_entorno_evento := case lower(coalesce(p_cuerpo->>'environment', ''))
    when 'test' then 'sandbox' when 'sandbox' then 'sandbox'
    when 'prod' then 'prod' when 'production' then 'prod' else null end;

  if v_motivo is null and upper(nullif(btrim(p_moneda), ''))
       is distinct from upper(nullif(btrim(v_i.moneda), '')) then
    v_motivo := format('La moneda informada (%s) no coincide con la intención (%s).',
      coalesce(nullif(btrim(p_moneda), ''), 'nula'), v_i.moneda);
  elsif v_motivo is null and (v_entorno_evento is null or v_entorno_evento is distinct from v_i.entorno) then
    v_motivo := format('El entorno informado (%s) no coincide con la intención (%s).',
      coalesce(nullif(p_cuerpo->>'environment', ''), 'nulo'), v_i.entorno);
  end if;

  if v_motivo is not null then
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           transaccion_id = p_transaccion_id, estado_wompi = 'APPROVED',
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador), actualizado = now()
     where referencia = p_referencia;
    update pagos_eventos set resultado = case when p_monto_centavos is distinct from v_i.monto_centavos
                                               then 'monto_no_coincide' else 'datos_no_coinciden' end
     where id = v_ins;
    return jsonb_build_object(
      'resultado', case when p_monto_centavos is distinct from v_i.monto_centavos
                        then 'monto_no_coincide' else 'datos_no_coinciden' end,
      'motivo', v_motivo
    );
  end if;

  select count(*)::integer, min(i.ordinal)::integer, max(i.ordinal)::integer,
         coalesce(sum(i.subtotal::numeric * 100), 0),
         coalesce(jsonb_agg(jsonb_build_object(
           'campana_id', i.campana_id, 'product_id', i.product_id,
           'nombre', i.nombre, 'slug', i.slug,
           'cantidad', i.cantidad, 'precio_unitario', i.precio_unitario
         ) order by i.ordinal), '[]'::jsonb)
    into v_lineas, v_min_ordinal, v_max_ordinal, v_total_lineas, v_items
    from pagos_intencion_items i where i.referencia = v_i.referencia;

  if v_lineas not between 1 and 20 or v_min_ordinal <> 1
     or v_max_ordinal <> v_lineas or v_total_lineas <> v_i.monto_centavos::numeric then
    v_motivo := 'Las líneas congeladas no coinciden con la intención firmada.';
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           transaccion_id = p_transaccion_id, estado_wompi = 'APPROVED',
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador), actualizado = now()
     where referencia = p_referencia;
    update pagos_eventos set resultado = 'datos_no_coinciden' where id = v_ins;
    return jsonb_build_object('resultado', 'datos_no_coinciden', 'motivo', v_motivo);
  end if;

  -- Congela las líneas actuales antes de producto/campaña. La cabecera ya
  -- serializa todas las RPC C4 del mismo carrito.
  perform ci.campana_id from carrito_items ci
   where ci.carrito_id = v_i.carrito_id order by ci.campana_id for update;

  begin
    -- pago_servidor conserva exclusivamente la compuerta histórica que el
    -- cuerpo C3 usa para acceso interno. No selecciona lógica C4.
    perform set_config('impulse.pago_servidor', 'on', true);
    perform set_config('impulse.checkout_legacy', 'off', true);
    v_pedido := crear_pedido_c4(
      p_auth_user_id => v_i.auth_user_id,
      p_nombre => coalesce(v_i.comprador_nombre, 'Comprador web'),
      p_correo => coalesce(v_i.comprador_correo, v_auth_correo_confirmado, p_correo_pagador),
      p_telefono => v_i.comprador_telefono,
      p_direccion => v_i.comprador_direccion,
      p_ciudad => v_i.comprador_ciudad,
      p_departamento => v_i.comprador_departamento,
      p_pais => v_i.comprador_pais,
      p_canal => 'web',
      p_fecha_orden => fz__fecha_colombia(),
      p_notas_pedido => 'Pago web Wompi · referencia ' || v_i.referencia,
      p_items => v_items
    );
    v_pedido_id := (v_pedido->>'pedido_id')::uuid;
    perform set_config('impulse.checkout_legacy', 'off', true);
    perform set_config('impulse.pago_servidor', 'off', true);
  exception when raise_exception then
    perform set_config('impulse.checkout_legacy', 'off', true);
    perform set_config('impulse.pago_servidor', 'off', true);
    v_motivo := sqlerrm;

    -- El subbloque anterior se revierte al capturar el error. La evidencia de
    -- identidad se escribe aquí, fuera de ese subbloque, para que sea durable.
    if v_motivo in ('C4_CORREO_AMBIGUO', 'C4_CLIENTE_YA_VINCULADO', 'C4_CONFLICTO_VINCULO') then
      insert into cc_conflictos_revision (
        auth_user_id, motivo, coincidencias, customer_id_candidato,
        estado, detectado_en, actualizado, resuelto_en, notas_revision
      )
      select v_i.auth_user_id,
             case v_motivo
               when 'C4_CORREO_AMBIGUO' then 'correo_ambiguo'
               when 'C4_CLIENTE_YA_VINCULADO' then 'cliente_ya_vinculado'
               else 'carrera_vinculo'
             end,
             greatest(count(c.id), 1)::integer,
             case when count(c.id) = 1 and v_motivo <> 'C4_CORREO_AMBIGUO'
                  then (array_agg(c.id order by c.id))[1] else null end,
             'pendiente', statement_timestamp(), statement_timestamp(), null, null
        from clientes c
       where ventas_norm_correo(c.correo_norm) = ventas_norm_correo(v_auth_correo)
          or ventas_norm_correo(c.correo) = ventas_norm_correo(v_auth_correo)
      on conflict (auth_user_id) do update set
        motivo = excluded.motivo,
        coincidencias = excluded.coincidencias,
        customer_id_candidato = excluded.customer_id_candidato,
        estado = 'pendiente', actualizado = statement_timestamp(),
        resuelto_en = null, notas_revision = null;
    end if;
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           transaccion_id = p_transaccion_id, estado_wompi = 'APPROVED',
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador), actualizado = now()
     where referencia = p_referencia;
    update pagos_eventos
       set resultado = case when v_motivo like 'C4_%' then 'datos_no_coinciden' else 'sin_stock' end
     where id = v_ins;
    return jsonb_build_object(
      'resultado', case when v_motivo like 'C4_%' then 'datos_no_coinciden' else 'sin_stock' end,
      'motivo', v_motivo
    );
  end;

  -- Sustrae solo cantidades/campañas congeladas. Extras y líneas nuevas quedan;
  -- drift de una intención C3 previa a C4 se registra como parcial.
  for v_req in
    select i.campana_id, i.cantidad
      from pagos_intencion_items i
     where i.referencia = v_i.referencia
     order by i.campana_id
  loop
    select ci.cantidad into v_actual from carrito_items ci
     where ci.carrito_id = v_i.carrito_id and ci.campana_id = v_req.campana_id
     for update;
    if not found then
      v_faltantes := v_faltantes + v_req.cantidad;
    elsif v_actual >= v_req.cantidad then
      v_consumidas := v_consumidas + v_req.cantidad;
      if v_actual = v_req.cantidad then
        delete from carrito_items
         where carrito_id = v_i.carrito_id and campana_id = v_req.campana_id;
      else
        update carrito_items
           set cantidad = cantidad - v_req.cantidad, actualizado = now()
         where carrito_id = v_i.carrito_id and campana_id = v_req.campana_id;
      end if;
    else
      v_consumidas := v_consumidas + v_actual;
      v_faltantes := v_faltantes + (v_req.cantidad - v_actual);
      delete from carrito_items
       where carrito_id = v_i.carrito_id and campana_id = v_req.campana_id;
    end if;
  end loop;

  update carritos set version = version + 1, actualizado = now()
   where id = v_i.carrito_id;
  v_resultado_consumo := case when v_faltantes = 0 then 'completo' else 'parcial' end;

  if v_i.utm_campaign is not null then
    update pedidos set utm_campaign = v_i.utm_campaign where id = v_pedido_id;
  end if;

  update pedidos p
     set actualizado = coalesce(p.actualizado, now())
   where p.id = v_pedido_id;

  update pedido_bitacora
     set detalle_cambio = coalesce(detalle_cambio, '{}'::jsonb) || jsonb_build_object(
       'ciclo_carrito', jsonb_build_object(
         'resultado', v_resultado_consumo,
         'unidades_consumidas', v_consumidas,
         'unidades_faltantes', v_faltantes
       )
     )
   where pedido_id = v_pedido_id and accion = 'crear';

  update pagos_intencion
     set estado = 'procesada', pedido_id = v_pedido_id,
         transaccion_id = p_transaccion_id, estado_wompi = 'APPROVED',
         metodo_pago = coalesce(p_metodo_pago, metodo_pago),
         correo_pagador = coalesce(p_correo_pagador, correo_pagador),
         revision_motivo = null, procesada_en = now(), actualizado = now(),
         carrito_consumido_en = now(),
         carrito_consumo_resultado = v_resultado_consumo,
         carrito_consumo_detalle = jsonb_build_object(
           'unidades_consumidas', v_consumidas,
           'unidades_faltantes', v_faltantes
         )
   where referencia = p_referencia;
  update pagos_eventos set resultado = 'procesado' where id = v_ins;

  begin
    v_asiento := fz__asiento_venta_web(v_pedido_id);
  exception when others then
    v_asiento := jsonb_build_object('resultado', 'pendiente', 'motivo', sqlerrm);
  end;

  return jsonb_build_object(
    'resultado', 'procesado', 'pedido_id', v_pedido_id,
    'consumo_carrito', v_resultado_consumo, 'asiento', v_asiento
  );
end;
$$;

comment on function pw_procesar_pago(text, text, text, bigint, text, text, text, jsonb, text, text) is
  'Pagos web C4 · firma histórica. v0/v1 ejecutan literalmente el cuerpo C3 privado. v2 usa locks auth.users->cuenta->carrito->intención, deriva cliente server-side, libera o consume una vez y preserva drift/extras.';
revoke execute on function pw_procesar_pago(text, text, text, bigint, text, text, text, jsonb, text, text)
  from public, anon, authenticated;
grant execute on function pw_procesar_pago(text, text, text, bigint, text, text, text, jsonb, text, text)
  to service_role;

-- El panel conserva el contrato C3 y recibe sólo el discriminador de ciclo que
-- necesita para escoger una acción de resolución segura.
alter function pw_revisiones() rename to pw__revisiones_c3;
revoke all on function pw__revisiones_c3() from public, anon, authenticated, service_role;
create function pw_revisiones()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_base jsonb;
  v_lista jsonb;
begin
  v_base := pw__revisiones_c3();
  select coalesce(jsonb_agg(x.item || jsonb_build_object(
           'ciclo_carrito_version', coalesce(pi.ciclo_carrito_version, 0)
         ) order by x.ord), '[]'::jsonb)
    into v_lista
    from jsonb_array_elements(coalesce(v_base->'lista', '[]'::jsonb))
         with ordinality as x(item, ord)
    left join pagos_intencion pi on pi.referencia = x.item->>'referencia';
  return jsonb_set(v_base, '{lista}', v_lista, true);
end;
$$;
revoke all on function pw_revisiones() from public, anon;
grant execute on function pw_revisiones() to authenticated, service_role;

-- La resolución histórica sigue disponible para v0/v1/ciclo 0, pero no puede
-- ocultar una revisión C4 sin liberar de forma explícita su carrito.
alter function pw_resolver_revision(text, text) rename to pw__resolver_revision_historica;
revoke all on function pw__resolver_revision_historica(text, text)
  from public, anon, authenticated, service_role;

create function pw_resolver_revision(p_referencia text, p_nota text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not tiene_acceso_pagos() then
    raise exception using errcode = 'P0001', message = 'PW_SIN_ACCESO';
  end if;
  if exists (
    select 1 from pagos_intencion pi
     where pi.referencia = p_referencia
       and pi.version_checkout = 2
       and pi.ciclo_carrito_version = 4
  ) then
    raise exception using errcode = 'P0001', message = 'PW_REVISION_C4_REQUIERE_ACCION';
  end if;
  return pw__resolver_revision_historica(p_referencia, p_nota);
end;
$$;

create function pw_resolver_revision_c4(
  p_referencia text,
  p_accion text,
  p_nota text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid_pre uuid;
  v_carrito_pre uuid;
  v_i pagos_intencion;
begin
  if not tiene_acceso_pagos() then
    raise exception using errcode = 'P0001', message = 'PW_SIN_ACCESO';
  end if;
  if p_accion is distinct from 'reembolsado_liberar' then
    raise exception using errcode = 'P0001', message = 'PW_ACCION_C4_INVALIDA';
  end if;
  if coalesce(btrim(p_nota), '') = '' then
    raise exception using errcode = 'P0001', message = 'PW_NOTA_OBLIGATORIA';
  end if;

  select pi.auth_user_id, pi.carrito_id
    into v_uid_pre, v_carrito_pre
    from pagos_intencion pi
   where pi.referencia = p_referencia
     and pi.version_checkout = 2
     and pi.ciclo_carrito_version = 4;
  if not found then
    raise exception using errcode = 'P0001', message = 'PW_REVISION_NO_ENCONTRADA';
  end if;

  perform 1 from cuentas_cliente cc
   where cc.auth_user_id = v_uid_pre for update;
  perform 1 from carritos c where c.id = v_carrito_pre for update;
  select * into v_i from pagos_intencion pi
   where pi.referencia = p_referencia for update;

  if v_i.estado <> 'requiere_revision' or v_i.resuelta_en is not null then
    raise exception using errcode = 'P0001', message = 'PW_REVISION_NO_ENCONTRADA';
  end if;

  if v_i.carrito_liberado_en is null then
    update carritos set version = version + 1, actualizado = statement_timestamp()
     where id = v_i.carrito_id;
  end if;
  update pagos_intencion
     set estado = 'rechazada',
         carrito_liberado_en = coalesce(carrito_liberado_en, statement_timestamp()),
         resuelta_en = statement_timestamp(), resuelta_por = auth.uid(),
         resuelta_nota = btrim(p_nota), actualizado = statement_timestamp()
   where referencia = p_referencia;

  return jsonb_build_object(
    'referencia', p_referencia, 'resuelta', true,
    'accion', 'reembolsado_liberar',
    'checkout', jsonb_build_object(
      'tipo', 'carrito', 'id', v_i.carrito_id,
      'version', (select c.version from carritos c where c.id = v_i.carrito_id),
      'recargar', true
    )
  );
end;
$$;

comment on function pw_resolver_revision_c4(text, text, text) is
  'C4 · acción explícita reembolsado_liberar con nota; bajo locks libera/versiona una vez y deja evidencia durable.';
revoke all on function pw_resolver_revision(text, text) from public, anon;
grant execute on function pw_resolver_revision(text, text) to authenticated, service_role;
revoke all on function pw_resolver_revision_c4(text, text, text) from public, anon;
grant execute on function pw_resolver_revision_c4(text, text, text) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (E) Correo: misma firma/errores/grants; snapshots primero, fallback histórico.
-- ----------------------------------------------------------------------------
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
  if not tiene_acceso_ventas() then raise exception 'CORREO_SIN_ACCESO'; end if;
  if p_etapa is null or not (p_etapa = any (v_flujo)) then raise exception 'CORREO_ETAPA_INVALIDA'; end if;

  select * into v_pedido from pedidos where id = p_pedido_id for update;
  if not found then raise exception 'CORREO_PEDIDO_NO_EXISTE'; end if;
  if v_pedido.anulado then raise exception 'CORREO_PEDIDO_ANULADO'; end if;
  if array_position(v_flujo, v_pedido.estado) is null
     or array_position(v_flujo, v_pedido.estado) < array_position(v_flujo, p_etapa) then
    raise exception 'CORREO_ETAPA_NO_ALCANZADA';
  end if;

  select coalesce(nullif(btrim(v_pedido.destinatario_nombre), ''), c.nombre),
         case
           when nullif(btrim(v_pedido.destinatario_correo), '') ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
             then btrim(v_pedido.destinatario_correo)
           when u.email_confirmed_at is not null
            and nullif(btrim(u.email), '') ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
             then btrim(u.email)
           when nullif(btrim(c.correo), '') ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'
             then btrim(c.correo)
           else null
         end
    into v_nombre, v_correo
    from clientes c
    left join cuentas_cliente cc on cc.customer_id = c.id
    left join auth.users u on u.id = cc.auth_user_id
   where c.id = v_pedido.customer_id;
  if v_correo is null or v_correo !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'CORREO_CLIENTE_SIN_CORREO';
  end if;

  select * into v_pl from correo_plantillas where etapa = p_etapa;
  if not found then raise exception 'CORREO_SIN_PLANTILLA'; end if;
  perform correo_cerrar_huerfanos(p_pedido_id, p_etapa);
  if exists (select 1 from correo_envios where pedido_id = p_pedido_id and etapa = p_etapa and estado = 'pendiente') then
    raise exception 'CORREO_EN_CURSO';
  end if;
  if exists (select 1 from correo_envios where pedido_id = p_pedido_id and etapa = p_etapa and estado = 'enviado')
     and not coalesce(p_reenviar, false) then
    raise exception 'CORREO_YA_ENVIADO';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'nombre', coalesce(pi.campana_nombre, cp.nombre, pr.nombre), 'cantidad', pi.cantidad,
           'subtotal', pi.subtotal, 'slug', coalesce(pi.campana_slug, cp.slug)
         ) order by pi.id), '[]'::jsonb)
    into v_items
    from pedido_items pi
    join productos pr on pr.id = pi.product_id
    left join lateral (
      select c2.nombre, c2.slug from campana_producto c2
       where pi.campana_id is null
         and c2.product_id_ref = pi.product_id
         and c2.publicado = true and c2.activo = true limit 1
    ) cp on true
   where pi.pedido_id = p_pedido_id;

  v_ref := correo_ref_pedido(p_pedido_id);
  insert into correo_envios (pedido_id, etapa, destinatario, asunto, estado, es_reenvio)
  values (
    p_pedido_id, p_etapa, v_correo,
    replace(replace(v_pl.asunto, '{pedido}', v_ref), '{nombre}', coalesce(split_part(btrim(v_nombre), ' ', 1), '')),
    'pendiente',
    exists (select 1 from correo_envios where pedido_id = p_pedido_id and etapa = p_etapa and estado = 'enviado')
  ) returning id into v_envio_id;

  return jsonb_build_object(
    'envio_id', v_envio_id, 'etapa', p_etapa, 'destinatario', v_correo,
    'nombre', coalesce(split_part(btrim(v_nombre), ' ', 1), ''),
    'pedido', v_ref, 'total', v_pedido.total, 'items', v_items,
    'direccion', concat_ws(', ', nullif(v_pedido.direccion, ''), nullif(v_pedido.ciudad, '')),
    'codigo_resena', case when p_etapa = 'entregado' then v_pedido.codigo_resena else null end,
    'plantilla', jsonb_build_object(
      'asunto', v_pl.asunto, 'preheader', v_pl.preheader, 'titulo', v_pl.titulo,
      'cuerpo', v_pl.cuerpo, 'boton_texto', v_pl.boton_texto),
    'es_prueba', false
  );
end;
$$;

comment on function correo_pedido_preparar(uuid, text, boolean) is
  'C4 · conserva firma, errores e idempotencia. Para pedidos nuevos usa snapshot de nombre/correo destinatario; pedidos históricos conservan fallback a clientes.';
revoke execute on function correo_pedido_preparar(uuid, text, boolean) from public;
grant execute on function correo_pedido_preparar(uuid, text, boolean) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (F) Estado público C4. La RPC histórica conserva firma, tres columnas,
--     posesión y grants para v0/v1, pero ya no es una puerta alternativa v2.
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
  v_nombre text;
  v_slug text;
begin
  if p_referencia is null or p_referencia !~ '^[A-Za-z0-9_-]{6,64}$' then return; end if;

  select pi.estado, coalesce(pi.nombre, ''), coalesce(pi.slug, '')
    into v_estado, v_nombre, v_slug
    from pagos_intencion pi
   where pi.referencia = p_referencia
     and pi.version_checkout in (0, 1);
  if not found then return; end if;

  return query select
    case v_estado when 'creada' then 'pendiente' when 'procesada' then 'aprobado'
      when 'rechazada' then 'rechazado' when 'requiere_revision' then 'revision' else 'pendiente' end,
    v_nombre,
    v_slug;
end;
$$;

comment on function pw_estado_publico(text) is
  'PAGOS WEB · contrato histórico D0 por posesión, limitado en C4 a intenciones v0/v1. Firma y retorno de tres columnas intactos; v2 usa pw_estado_checkout_publico con UID.';
revoke all on function pw_estado_publico(text) from public;
revoke all on function pw_estado_publico(text) from anon;
revoke all on function pw_estado_publico(text) from authenticated;
grant execute on function pw_estado_publico(text) to service_role;

-- La nueva RPC mantiene v0/v1 por posesión y exige UID coincidente para v2.
create function pw_estado_checkout_publico(p_referencia text, p_auth_user_id uuid default null)
returns table (
  estado text,
  nombre_producto text,
  slug text,
  checkout jsonb
)
language plpgsql
security definer
volatile
set search_path = public
as $$
declare
  v_i pagos_intencion;
  v_uid_pre uuid;
  v_carrito_pre uuid;
  v_version_pre integer;
begin
  if p_referencia is null or p_referencia !~ '^[A-Za-z0-9_-]{6,64}$' then return; end if;

  select pi.version_checkout, pi.auth_user_id, pi.carrito_id
    into v_version_pre, v_uid_pre, v_carrito_pre
    from pagos_intencion pi where pi.referencia = p_referencia;
  if not found then return; end if;
  if v_version_pre = 2 and p_auth_user_id is distinct from v_uid_pre then return; end if;

  if v_version_pre = 2 then
    perform 1 from cuentas_cliente cc where cc.auth_user_id = v_uid_pre for update;
    perform 1 from carritos c where c.id = v_carrito_pre for update;
    perform co__liberar_expiradas_c4(v_carrito_pre);
  end if;

  select * into v_i from pagos_intencion pi where pi.referencia = p_referencia;
  if not found then return; end if;

  return query select
    case v_i.estado when 'creada' then 'pendiente' when 'procesada' then 'aprobado'
      when 'rechazada' then 'rechazado' when 'requiere_revision' then 'revision' else 'pendiente' end,
    coalesce(v_i.nombre, ''),
    coalesce(v_i.slug, ''),
    case when v_i.version_checkout = 2 then jsonb_build_object(
      'tipo', 'carrito', 'id', v_i.carrito_id, 'version', v_i.carrito_version,
      'recargar', true
    ) else null end;
end;
$$;

comment on function pw_estado_checkout_publico(text, uuid) is
  'C4 · estado mínimo. v0/v1 mantienen posesión de referencia y contrato histórico; v2 exige UID coincidente y añade checkout carrito/id/version/recargar. Nunca PII, monto, pedido, transacción, motivo ni entorno.';
revoke all on function pw_estado_checkout_publico(text, uuid) from public, anon, authenticated, service_role;
grant execute on function pw_estado_checkout_publico(text, uuid) to service_role;

-- Reafirmar superficies históricas que C4 no cambia.
revoke all on function pw_registrar_intencion_carrito(text, uuid, uuid, bigint, text, jsonb, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function pw_registrar_intencion_carrito(text, uuid, uuid, bigint, text, jsonb, text, text, text)
  to service_role;
revoke all on function co_carrito_listar() from public, anon, authenticated, service_role;
grant execute on function co_carrito_listar() to authenticated, service_role;

-- service_role es la identidad privilegiada de las Edge Functions y la matriz
-- histórica exige que pueda ejecutar toda función de public. Los helpers siguen
-- cerrados a public/anon/authenticated y solo se alcanzan desde puertas C4.
grant execute on function co__carrito_agregar_c3(uuid, integer) to service_role;
grant execute on function co__carrito_cambiar_c3(uuid, integer, bigint) to service_role;
grant execute on function co__carrito_quitar_c3(uuid, bigint) to service_role;
grant execute on function co__liberar_expiradas_c4(uuid) to service_role;
grant execute on function crear_pedido_c3_base(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb) to service_role;
grant execute on function crear_pedido_c4(uuid, text, text, text, text, text, text, text, text, text, date, text, jsonb) to service_role;
grant execute on function pw__procesar_pago_c3(text, text, text, bigint, text, text, text, jsonb, text, text) to service_role;
grant execute on function pw__registrar_intencion_carrito_c3(text, uuid, uuid, bigint, text, jsonb, text, text, text) to service_role;
grant execute on function pw__resolver_revision_historica(text, text) to service_role;
grant execute on function pw__revisiones_c3() to service_role;

commit;
