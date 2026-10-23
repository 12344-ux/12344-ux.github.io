-- MAGANDHI · COMERCIAL C6 · COMPRA DIRECTA RECUPERABLE
-- ----------------------------------------------------------------------------
-- Migración FORWARD sobre C5/P4. Conserva intenciones v0/v1 históricas y C5.
-- Las nuevas compras directas siguen siendo version_checkout=1, pero quedan
-- marcadas con recuperacion_directa_version=6, vencen a los 30 minutos y se
-- autorizan por UID confirmado o por una capacidad opaca cuyo hash guarda la BD.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- (A) Modelo compatible. Nunca se guarda la capacidad en claro.
-- ----------------------------------------------------------------------------
alter table pagos_intencion
  add column if not exists recuperacion_directa_version smallint not null default 0,
  add column if not exists capacidad_reanudacion_hash text;

alter table pagos_intencion
  drop constraint if exists pagos_intencion_forma_checkout_valida,
  drop constraint if exists pagos_intencion_expiracion_c4_c5;

alter table pagos_intencion
  add constraint pagos_intencion_forma_checkout_valida
  check (
    (
      version_checkout in (0, 1)
      and cantidad is not null
      and precio_unitario is not null
      and carrito_id is null
      and carrito_version is null
      and (
        (recuperacion_directa_version = 0
          and auth_user_id is null
          and capacidad_reanudacion_hash is null)
        or
        (version_checkout = 1
          and recuperacion_directa_version = 6
          and capacidad_reanudacion_hash ~ '^[0-9a-f]{64}$')
      )
    )
    or
    (
      version_checkout = 2
      and recuperacion_directa_version = 0
      and capacidad_reanudacion_hash is null
      and campana_id is null
      and product_id is null
      and slug is null
      and nombre is null
      and cantidad is null
      and precio_unitario is null
      and auth_user_id is not null
      and carrito_id is not null
      and carrito_version is not null
      and carrito_version >= 0
    )
  ),
  add constraint pagos_intencion_expiracion_c4_c5
  check (
    (
      (version_checkout = 2 and ciclo_carrito_version in (4, 5))
      or (version_checkout = 1 and recuperacion_directa_version = 6)
    ) = (expira_en is not null)
  );

comment on column pagos_intencion.recuperacion_directa_version is
  'C6 · 6 identifica compras directas recuperables; 0 conserva v0/v1 históricos y carrito.';
comment on column pagos_intencion.capacidad_reanudacion_hash is
  'C6 · SHA-256 hexadecimal de la capacidad opaca de una compra directa. Nunca se persiste ni registra el valor en claro.';
comment on column pagos_intencion.auth_user_id is
  'C6 · dueño Auth derivado por Edge para carrito y compra directa autenticada; null conserva invitados e historia.';
comment on column pagos_intencion.expira_en is
  'C6 · vencimiento durable de C4/C5 y de compras directas recuperables, fijado exactamente 30 minutos después de crearse.';

create unique index pagos_intencion_c6_capacidad_uidx
  on pagos_intencion (capacidad_reanudacion_hash)
  where recuperacion_directa_version = 6;

-- Una cuenta no puede abrir dos procesos directos simultáneos para la misma
-- campaña. Revisión sin resolver también bloquea; rechazo, resolución o pedido
-- terminado liberan el producto para una compra nueva.
create unique index pagos_intencion_c6_cuenta_campana_activa_uidx
  on pagos_intencion (auth_user_id, campana_id)
  where recuperacion_directa_version = 6
    and auth_user_id is not null
    and (estado = 'creada' or (estado = 'requiere_revision' and resuelta_en is null));

create index pagos_intencion_c6_expiracion_idx
  on pagos_intencion (expira_en)
  where recuperacion_directa_version = 6
    and estado = 'creada' and transaccion_id is null;

-- ----------------------------------------------------------------------------
-- (B) Registro idempotente y expiración de compra directa.
-- ----------------------------------------------------------------------------
create function pw__expirar_directa_c6(p_referencia text)
returns boolean
language plpgsql
volatile
security definer
set search_path = public
as $$
declare v_filas integer;
begin
  update pagos_intencion
     set estado = 'rechazada', estado_wompi = 'EXPIRED',
         revision_motivo = 'C6_INTENCION_EXPIRADA',
         actualizado = statement_timestamp()
   where referencia = p_referencia
     and version_checkout = 1 and recuperacion_directa_version = 6
     and estado = 'creada' and expira_en <= statement_timestamp()
     and transaccion_id is null;
  get diagnostics v_filas = row_count;
  return v_filas = 1;
end;
$$;
revoke all on function pw__expirar_directa_c6(text)
  from public, anon, authenticated, service_role;

create function pw__snapshot_directa_c6(p_referencia text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_i pagos_intencion;
begin
  select * into strict v_i from pagos_intencion where referencia = p_referencia;
  if v_i.version_checkout <> 1 or v_i.recuperacion_directa_version <> 6
     or v_i.campana_id is null or v_i.product_id is null
     or v_i.cantidad is null or v_i.precio_unitario is null
     or v_i.expira_en is null or v_i.capacidad_reanudacion_hash is null then
    raise exception using errcode = 'XX000', message = 'PW_SNAPSHOT_DIRECTA_C6_INCONSISTENTE';
  end if;
  return jsonb_build_object(
    'tipo', 'directo', 'referencia', v_i.referencia,
    'estado', v_i.estado, 'campana_id', v_i.campana_id,
    'product_id', v_i.product_id, 'slug', v_i.slug, 'nombre', v_i.nombre,
    'cantidad', v_i.cantidad, 'precio_unitario', v_i.precio_unitario::text,
    'monto_centavos', v_i.monto_centavos::text, 'moneda', v_i.moneda,
    'entorno', v_i.entorno,
    'expira_en', to_char(v_i.expira_en at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'auth_user_id', v_i.auth_user_id,
    'tiene_transaccion', v_i.transaccion_id is not null,
    'comprador', jsonb_strip_nulls(jsonb_build_object(
      'nombre', v_i.comprador_nombre, 'correo', v_i.comprador_correo,
      'telefono', v_i.comprador_telefono, 'direccion', v_i.comprador_direccion,
      'ciudad', v_i.comprador_ciudad, 'departamento', v_i.comprador_departamento,
      'pais', v_i.comprador_pais
    ))
  );
end;
$$;
revoke all on function pw__snapshot_directa_c6(text)
  from public, anon, authenticated, service_role;

-- Resuelve un retry de creación por la capacidad, antes de consultar catálogo
-- o proveedor mutable. null significa que esta capacidad todavía no existe.
create function pw_recuperar_registro_directa_c6(
  p_capacidad_hash text, p_auth_user_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_i pagos_intencion;
  v_estado_cuenta text;
begin
  if p_capacidad_hash is null or p_capacidad_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = 'P0001', message = 'PW_DIRECTA_C6_SOLICITUD_INVALIDA';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('c6-capacidad:' || p_capacidad_hash, 0));
  select * into v_i from pagos_intencion
   where capacidad_reanudacion_hash = p_capacidad_hash;
  if not found then return null; end if;

  if v_i.auth_user_id is not null then
    if p_auth_user_id is distinct from v_i.auth_user_id then
      raise exception using errcode = 'P0001', message = 'PW_DIRECTA_C6_NO_DISPONIBLE';
    end if;
    select cc.estado into v_estado_cuenta from cuentas_cliente cc
     where cc.auth_user_id = p_auth_user_id for update;
    if not found or v_estado_cuenta <> 'activa' then
      raise exception using errcode = 'P0001', message = 'PW_CUENTA_NO_DISPONIBLE';
    end if;
  end if;

  select * into v_i from pagos_intencion
   where capacidad_reanudacion_hash = p_capacidad_hash for update;
  perform pw__expirar_directa_c6(v_i.referencia);
  select * into v_i from pagos_intencion where referencia = v_i.referencia;
  if v_i.recuperacion_directa_version <> 6 or v_i.estado <> 'creada'
     or v_i.transaccion_id is not null or v_i.expira_en <= statement_timestamp() then
    raise exception using errcode = 'P0001', message = 'PW_DIRECTA_C6_NO_REABRIBLE';
  end if;
  return pw__snapshot_directa_c6(v_i.referencia);
end;
$$;
comment on function pw_recuperar_registro_directa_c6(text, uuid) is
  'C6 · resuelve idempotencia por hash antes de validaciones mutables; exige dueño si la intención pertenece a una cuenta.';
revoke all on function pw_recuperar_registro_directa_c6(text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function pw_recuperar_registro_directa_c6(text, uuid) to service_role;

create function pw_registrar_intencion_directa_c6(
  p_referencia text, p_campana_id uuid, p_slug text, p_nombre text,
  p_cantidad integer, p_precio_unitario bigint, p_monto_centavos bigint,
  p_entorno text, p_comprador jsonb default '{}'::jsonb,
  p_utm_campaign text default null, p_mg_vid text default null,
  p_moneda text default 'COP', p_atribucion_codigo text default null,
  p_auth_user_id uuid default null, p_capacidad_hash text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_existente pagos_intencion;
  v_resultado jsonb;
  v_estado_cuenta text;
  v_filas integer;
begin
  if p_referencia is null or p_referencia !~ '^[A-Za-z0-9_-]{6,64}$'
     or p_capacidad_hash is null or p_capacidad_hash !~ '^[0-9a-f]{64}$' then
    raise exception using errcode = 'P0001', message = 'PW_DIRECTA_C6_SOLICITUD_INVALIDA';
  end if;

  -- La capacidad también es la llave idempotente del intento del navegador.
  -- Para cuenta se conserva el orden global cuenta -> intención.
  perform pg_advisory_xact_lock(hashtextextended('c6-capacidad:' || p_capacidad_hash, 0));
  select * into v_existente from pagos_intencion
   where capacidad_reanudacion_hash = p_capacidad_hash;
  if found then
    if p_auth_user_id is not null then
      select cc.estado into v_estado_cuenta from cuentas_cliente cc
       where cc.auth_user_id = p_auth_user_id for update;
      if not found or v_estado_cuenta <> 'activa' then
        raise exception using errcode = 'P0001', message = 'PW_CUENTA_NO_DISPONIBLE';
      end if;
    end if;
    select * into v_existente from pagos_intencion
     where capacidad_reanudacion_hash = p_capacidad_hash for update;
    perform pw__expirar_directa_c6(v_existente.referencia);
    select * into v_existente from pagos_intencion where referencia = v_existente.referencia;
    if v_existente.recuperacion_directa_version <> 6
       or v_existente.auth_user_id is distinct from p_auth_user_id
       or v_existente.campana_id is distinct from p_campana_id
       or v_existente.cantidad is distinct from p_cantidad
       or v_existente.moneda is distinct from p_moneda
       or v_existente.entorno is distinct from p_entorno then
      raise exception using errcode = 'P0001', message = 'PW_DIRECTA_C6_CAPACIDAD_REUTILIZADA';
    end if;
    if v_existente.estado <> 'creada' or v_existente.transaccion_id is not null
       or v_existente.expira_en <= statement_timestamp() then
      raise exception using errcode = 'P0001', message = 'PW_DIRECTA_C6_NO_REABRIBLE';
    end if;
    return pw__snapshot_directa_c6(v_existente.referencia);
  end if;

  if p_auth_user_id is not null then
    select cc.estado into v_estado_cuenta from cuentas_cliente cc
     where cc.auth_user_id = p_auth_user_id for update;
    if not found or v_estado_cuenta <> 'activa' then
      raise exception using errcode = 'P0001', message = 'PW_CUENTA_NO_DISPONIBLE';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(
      'c6-directa:' || p_auth_user_id::text || ':' || p_campana_id::text, 0
    ));

    -- Libera únicamente intenciones sin noticia bancaria cuyo reloj terminó.
    for v_existente in
      select pi.* from pagos_intencion pi
       where pi.recuperacion_directa_version = 6
         and pi.auth_user_id = p_auth_user_id
         and pi.campana_id = p_campana_id
         and pi.estado = 'creada' and pi.transaccion_id is null
         and pi.expira_en <= statement_timestamp()
       order by pi.referencia for update
    loop
      perform pw__expirar_directa_c6(v_existente.referencia);
    end loop;

    if exists (
      select 1 from pagos_intencion pi
       where pi.recuperacion_directa_version = 6
         and pi.auth_user_id = p_auth_user_id
         and pi.campana_id = p_campana_id
         and (pi.estado = 'creada'
              or (pi.estado = 'requiere_revision' and pi.resuelta_en is null))
    ) then
      raise exception using errcode = 'P0001', message = 'PW_DIRECTA_C6_ACTIVA';
    end if;
  end if;

  -- Reutiliza toda la validación comercial y la atribución P4 vigentes. La
  -- fila nace v1 histórica y se convierte a C6 dentro de esta transacción.
  v_resultado := pw_registrar_intencion_p4(
    p_referencia, p_campana_id, p_slug, p_nombre, p_cantidad,
    p_precio_unitario, p_monto_centavos, p_entorno, p_comprador,
    p_utm_campaign, p_mg_vid, p_moneda, p_atribucion_codigo
  );

  update pagos_intencion
     set recuperacion_directa_version = 6,
         auth_user_id = p_auth_user_id,
         capacidad_reanudacion_hash = p_capacidad_hash,
         expira_en = date_trunc('milliseconds', transaction_timestamp() + interval '30 minutes'),
         actualizado = statement_timestamp()
   where referencia = p_referencia
     and version_checkout = 1 and recuperacion_directa_version = 0;
  get diagnostics v_filas = row_count;
  if v_filas <> 1 then
    raise exception using errcode = 'XX000', message = 'PW_DIRECTA_C6_REGISTRO_INCONSISTENTE';
  end if;

  return pw__snapshot_directa_c6(p_referencia);
exception when unique_violation then
  raise exception using errcode = 'P0001', message = 'PW_DIRECTA_C6_ACTIVA';
end;
$fn$;
comment on function pw_registrar_intencion_directa_c6(text,uuid,text,text,integer,bigint,bigint,text,jsonb,text,text,text,text,uuid,text) is
  'C6 · registra una compra directa recuperable. Capacidad hash idempotente, dueño Auth opcional, bloqueo por cuenta/campaña y vencimiento de 30 minutos.';
revoke all on function pw_registrar_intencion_directa_c6(text,uuid,text,text,integer,bigint,bigint,text,jsonb,text,text,text,text,uuid,text)
  from public, anon, authenticated, service_role;
grant execute on function pw_registrar_intencion_directa_c6(text,uuid,text,text,integer,bigint,bigint,text,jsonb,text,text,text,text,uuid,text)
  to service_role;

-- ----------------------------------------------------------------------------
-- (C) Reapertura owner/capability-checked. C5 conserva su cuerpo literal.
-- ----------------------------------------------------------------------------
create function mc_reabrir_intencion_c6(
  p_referencia text, p_auth_user_id uuid default null,
  p_capacidad_hash text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_i pagos_intencion;
  v_estado_cuenta text;
  v_snapshot jsonb;
begin
  if p_referencia is null or p_referencia !~ '^[A-Za-z0-9_-]{6,64}$' then
    raise exception using errcode = 'P0001', message = 'MC_INTENCION_NO_DISPONIBLE';
  end if;
  -- Prelectura sin lock para escoger protocolo. C5 conserva su propio orden de
  -- locks; una directa autenticada toma cuenta antes de intención.
  select * into v_i from pagos_intencion where referencia = p_referencia;
  if not found then
    raise exception using errcode = 'P0001', message = 'MC_INTENCION_NO_DISPONIBLE';
  end if;
  if v_i.version_checkout = 2 and v_i.ciclo_carrito_version = 5 then
    return mc_reabrir_intencion_c5(p_referencia, p_auth_user_id);
  end if;
  if v_i.version_checkout <> 1 or v_i.recuperacion_directa_version <> 6 then
    raise exception using errcode = 'P0001', message = 'MC_INTENCION_NO_DISPONIBLE';
  end if;

  if v_i.auth_user_id is not null then
    select cc.estado into v_estado_cuenta from cuentas_cliente cc
     where cc.auth_user_id = p_auth_user_id for update;
    if p_auth_user_id is distinct from v_i.auth_user_id
       or v_estado_cuenta is distinct from 'activa' then
      raise exception using errcode = 'P0001', message = 'MC_INTENCION_NO_DISPONIBLE';
    end if;
    select * into v_i from pagos_intencion where referencia = p_referencia for update;
    if v_i.auth_user_id is distinct from p_auth_user_id
       or v_i.recuperacion_directa_version <> 6 then
      raise exception using errcode = 'P0001', message = 'MC_INTENCION_NO_DISPONIBLE';
    end if;
  else
    select * into v_i from pagos_intencion where referencia = p_referencia for update;
    if v_i.auth_user_id is not null
       or p_capacidad_hash is null
       or p_capacidad_hash !~ '^[0-9a-f]{64}$'
       or p_capacidad_hash is distinct from v_i.capacidad_reanudacion_hash then
      raise exception using errcode = 'P0001', message = 'MC_INTENCION_NO_DISPONIBLE';
    end if;
  end if;

  perform pw__expirar_directa_c6(p_referencia);
  select * into v_i from pagos_intencion where referencia = p_referencia;
  if v_i.estado <> 'creada' or v_i.transaccion_id is not null
     or v_i.expira_en <= statement_timestamp() then
    raise exception using errcode = 'P0001', message = 'MC_INTENCION_NO_REABRIBLE';
  end if;

  v_snapshot := pw__snapshot_directa_c6(p_referencia);
  return v_snapshot || jsonb_build_object(
    'gestion', case when v_i.auth_user_id is null then 'local' else 'mis_compras' end
  );
end;
$$;
comment on function mc_reabrir_intencion_c6(text, uuid, text) is
  'C6 · reabre C5 por dueño o compra directa por dueño/capacidad. Solo creada, vigente y sin transacción; nunca crea otra intención.';
revoke all on function mc_reabrir_intencion_c6(text, uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function mc_reabrir_intencion_c6(text, uuid, text) to service_role;

-- ----------------------------------------------------------------------------
-- (D) Estado mínimo. Una directa autenticada exige dueño; invitado conserva la
--     consulta mínima por referencia. Nunca expone PII, monto o transacción.
-- ----------------------------------------------------------------------------
alter function pw_estado_checkout_publico(text, uuid)
  rename to pw__estado_checkout_publico_c5;
revoke all on function pw__estado_checkout_publico_c5(text, uuid)
  from public, anon, authenticated, service_role;

create function pw_estado_checkout_publico(p_referencia text, p_auth_user_id uuid default null)
returns table (estado text, nombre_producto text, slug text, checkout jsonb)
language plpgsql
security definer
volatile
set search_path = public
as $$
declare v_i pagos_intencion;
begin
  if p_referencia is null or p_referencia !~ '^[A-Za-z0-9_-]{6,64}$' then return; end if;
  select * into v_i from pagos_intencion where referencia = p_referencia;
  if not found or v_i.recuperacion_directa_version <> 6 then
    return query select * from pw__estado_checkout_publico_c5(p_referencia, p_auth_user_id);
    return;
  end if;
  if v_i.auth_user_id is not null and p_auth_user_id is distinct from v_i.auth_user_id then return; end if;
  if v_i.auth_user_id is not null then
    perform 1 from cuentas_cliente cc
     where cc.auth_user_id = v_i.auth_user_id and cc.estado = 'activa' for update;
    if not found then return; end if;
  end if;
  perform 1 from pagos_intencion pi where pi.referencia = p_referencia for update;
  perform pw__expirar_directa_c6(p_referencia);
  select * into v_i from pagos_intencion where referencia = p_referencia;
  if v_i.estado not in ('creada','procesada','rechazada','requiere_revision') then
    raise exception using errcode = 'XX000', message = 'PW_ESTADO_DIRECTA_C6_INVALIDO';
  end if;
  return query select
    case
      when v_i.estado = 'requiere_revision' and v_i.resuelta_en is not null then 'rechazado'
      else case v_i.estado when 'creada' then 'pendiente' when 'procesada' then 'aprobado'
        when 'rechazada' then 'rechazado' when 'requiere_revision' then 'revision'
        else 'pendiente' end
    end,
    coalesce(v_i.nombre, ''), coalesce(v_i.slug, ''),
    jsonb_build_object(
      'tipo', 'compra', 'referencia', v_i.referencia, 'recargar', true,
      'origen', 'directo',
      'gestion', case when v_i.auth_user_id is null then 'local' else 'mis_compras' end,
      'puede_continuar', v_i.estado = 'creada' and v_i.transaccion_id is null
        and v_i.expira_en > statement_timestamp()
    );
end;
$$;
comment on function pw_estado_checkout_publico(text, uuid) is
  'C6 · añade compra directa recuperable: dueño para cuenta, referencia para estado invitado, expiración y descriptor de gestión sin PII. C5 e historia delegan literal.';
revoke all on function pw_estado_checkout_publico(text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function pw_estado_checkout_publico(text, uuid) to service_role;

-- ----------------------------------------------------------------------------
-- (E) Mis compras. Envuelve C5 para sumar directas autenticadas y deduplicar el
--     alias histórico del pedido materializado.
-- ----------------------------------------------------------------------------
alter function mc_compras_listar() rename to mc__compras_listar_c5;
revoke all on function mc__compras_listar_c5()
  from public, anon, authenticated, service_role;

create function mc_compras_listar()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_base jsonb;
  v_resultado jsonb;
  v_ref text;
begin
  -- El cuerpo C5 conserva su validación de cuenta, expiración y proyección.
  v_base := mc__compras_listar_c5();

  for v_ref in
    select pi.referencia from pagos_intencion pi
     where pi.auth_user_id = v_uid
       and pi.recuperacion_directa_version = 6
       and pi.estado = 'creada' and pi.transaccion_id is null
       and pi.expira_en <= statement_timestamp()
     order by pi.referencia for update
  loop
    perform pw__expirar_directa_c6(v_ref);
  end loop;

  with base_filtrada as (
    select
      coalesce(nullif(c.card->>'comprado_iso', ''), c.card->>'creado_iso')::timestamptz as orden,
      c.card->>'referencia' as desempate,
      c.card || jsonb_build_object(
        'origen', case when exists (
          select 1 from pagos_intencion pi5
           where pi5.referencia = c.card->>'referencia'
             and pi5.version_checkout = 2 and pi5.ciclo_carrito_version = 5
        ) then 'carrito' else 'historial' end
      ) as card
    from jsonb_array_elements(coalesce(v_base->'compras', '[]'::jsonb)) c(card)
    where not exists (
      select 1 from pagos_intencion d
       where d.recuperacion_directa_version = 6
         and d.auth_user_id = v_uid and d.pedido_id is not null
         and c.card->>'referencia' = 'PED-' || md5(d.pedido_id::text)
    )
  ), directas as (
    select coalesce(pi.procesada_en, pi.creado) as orden,
           pi.referencia as desempate,
           jsonb_build_object(
      'referencia', pi.referencia,
      'origen', 'directo',
      'clasificacion', case
        when coalesce(p.anulado, false) or p.estado = 'anulado' then 'no_completada'
        when pi.estado = 'procesada' then 'realizada'
        when pi.estado = 'rechazada'
          or (pi.estado = 'requiere_revision' and pi.resuelta_en is not null)
          then 'no_completada'
        else 'proceso' end,
      'estado', case
        when coalesce(p.anulado, false) or p.estado = 'anulado' then 'anulada'
        when pi.estado = 'procesada' then 'aprobada'
        when pi.estado = 'requiere_revision' and pi.resuelta_en is not null then 'no_completada'
        when pi.estado = 'requiere_revision' then 'verificacion'
        when pi.estado = 'rechazada' and pi.estado_wompi = 'EXPIRED' then 'vencida'
        when pi.estado = 'rechazada' then 'no_completada'
        when pi.estado = 'creada' and pi.transaccion_id is not null then 'confirmando_pago'
        else 'pendiente_pago' end,
      'etiqueta', case
        when coalesce(p.anulado, false) or p.estado = 'anulado' then 'Pedido anulado'
        when pi.estado = 'procesada' then 'Compra realizada'
        when pi.estado = 'requiere_revision' and pi.resuelta_en is not null then 'Pago no completado'
        when pi.estado = 'requiere_revision' then 'Estamos verificando tu pago'
        when pi.estado = 'rechazada' and pi.estado_wompi = 'EXPIRED' then 'Pago vencido'
        when pi.estado = 'rechazada' then 'Pago no completado'
        when pi.estado = 'creada' and pi.transaccion_id is not null then 'Confirmando con tu banco'
        else 'Pendiente de pago' end,
      'creado_iso', to_char(pi.creado at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'comprado_iso', case when pi.procesada_en is null then null else
        to_char(pi.procesada_en at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') end,
      'actualizado_iso', to_char(pi.actualizado at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'total_cop', (pi.monto_centavos / 100)::bigint,
      'expira_en', to_char(pi.expira_en at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'puede_continuar', pi.estado = 'creada' and pi.transaccion_id is null
        and pi.expira_en > statement_timestamp(),
      'puede_verificar', (pi.estado = 'requiere_revision' and pi.resuelta_en is null)
        or (pi.estado = 'creada' and pi.transaccion_id is not null),
      'lineas', jsonb_build_array(jsonb_build_object(
        'nombre', pi.nombre, 'cantidad', pi.cantidad,
        'subtotal', pi.precio_unitario * pi.cantidad::bigint,
        'slug', cat.slug, 'id', cat.id, 'imagen', cat.imagen_banner_path,
        'puede_opinar', pi.pedido_id is not null
          and p.estado = 'entregado' and not coalesce(p.anulado, false)
          and cat.id is not null and coalesce(pr.activo, false)
          and not exists (select 1 from opiniones o
                          where o.pedido_id = pi.pedido_id and o.product_id = pi.product_id)
      )),
      'pedido', case when pi.pedido_id is null then null else jsonb_build_object(
        'estado_logistico', case when p.anulado then 'anulado' else p.estado end,
        'etiqueta_logistica', case
          when p.anulado or p.estado = 'anulado' then 'Pedido anulado'
          when p.estado = 'recibido' then 'Pedido recibido'
          when p.estado = 'preparando' then 'Preparando pedido'
          when p.estado = 'en_camino' then 'Pedido en camino'
          when p.estado = 'entregado' then 'Pedido entregado'
          else 'Pedido en proceso' end,
        'timeline', coalesce((
          select jsonb_agg(jsonb_build_object(
            'estado', case when pb.accion = 'crear' then 'recibido'
                           when pb.accion = 'anular' then 'anulado' else pb.estado_nuevo end,
            'fecha_iso', to_char(pb.cuando at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
          ) order by pb.cuando, pb.id)
          from pedido_bitacora pb
          where pb.pedido_id = pi.pedido_id
            and (pb.accion in ('crear','anular')
                 or pb.estado_nuevo in ('recibido','preparando','en_camino','entregado'))
        ), '[]'::jsonb)
      ) end
    ) as card
      from pagos_intencion pi
      left join pedidos p on p.id = pi.pedido_id
      left join productos pr on pr.id = pi.product_id
      left join lateral (
        select cp.id, cp.slug, cp.imagen_banner_path
          from catalogo_publico cp where cp.id = pi.campana_id limit 1
      ) cat on true
     where pi.auth_user_id = v_uid
       and pi.version_checkout = 1 and pi.recuperacion_directa_version = 6
  ), todas as (
    select * from base_filtrada
    union all
    select * from directas
  ), recientes as (
    select orden, desempate, card from todas
     order by orden desc, desempate desc limit 100
  )
  select coalesce(jsonb_agg(card order by orden desc, desempate desc), '[]'::jsonb)
    into v_resultado from recientes;

  return jsonb_build_object('compras', v_resultado);
end;
$$;
comment on function mc_compras_listar() is
  'C6 · proyección owner-safe de C5, historia y compras directas autenticadas; expira, deduplica pedidos y limita a 100 sin exponer PII ni IDs de identidad.';
revoke all on function mc_compras_listar()
  from public, anon, authenticated, service_role;
grant execute on function mc_compras_listar() to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (F) Pedido autenticado para la directa. La selección interna exige llamada
-- service_role y el contexto no falsificable que ya abre el procesador.
-- ----------------------------------------------------------------------------
alter function crear_pedido(uuid,text,text,text,text,text,text,text,text,text,date,text,jsonb)
  rename to crear_pedido_c6_base;
revoke all on function crear_pedido_c6_base(uuid,text,text,text,text,text,text,text,text,text,date,text,jsonb)
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
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid_text text := coalesce(current_setting('impulse.compra_directa_auth_user_id', true), '');
begin
  if coalesce(nullif(btrim(p_canal), ''), 'manual') = 'web'
     and pw__contexto_servidor()
     and coalesce(
       nullif(current_setting('request.jwt.claim.role', true), ''),
       nullif(current_setting('request.jwt.claims', true), '')::jsonb->>'role',
       ''
     ) = 'service_role'
     and v_uid_text ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return crear_pedido_c4(
      v_uid_text::uuid, p_nombre, p_correo, p_telefono, p_direccion,
      p_ciudad, p_departamento, p_pais, null, p_canal, p_fecha_orden,
      p_notas_pedido, p_items
    );
  end if;
  return crear_pedido_c6_base(
    p_customer_id, p_nombre, p_correo, p_telefono, p_direccion,
    p_ciudad, p_departamento, p_pais, p_notas_cliente, p_canal,
    p_fecha_orden, p_notas_pedido, p_items
  );
end;
$$;
comment on function crear_pedido(uuid,text,text,text,text,text,text,text,text,text,date,text,jsonb) is
  'C6 · conserva la firma pública/manual. Solo el webhook service_role con contexto C6 deriva customer_id desde Auth mediante crear_pedido_c4; todo lo demás delega literal.';
revoke all on function crear_pedido(uuid,text,text,text,text,text,text,text,text,text,date,text,jsonb)
  from public, anon;
grant execute on function crear_pedido(uuid,text,text,text,text,text,text,text,text,text,date,text,jsonb)
  to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (G) Webhook endurecido para directas recuperables. Una segunda transacción,
--     aprobación tardía o estado ya cerrado nunca crea otro pedido.
-- ----------------------------------------------------------------------------
alter function pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text)
  rename to pw__procesar_pago_p4_c5;
revoke all on function pw__procesar_pago_p4_c5(text,text,text,bigint,text,text,text,jsonb,text,text)
  from public, anon, authenticated, service_role;

create function pw__registrar_evento_directa_c6(
  p_transaccion_id text, p_estado_wompi text, p_referencia text,
  p_evento text, p_checksum text, p_cuerpo jsonb, p_resultado text
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare v_id bigint;
begin
  insert into pagos_eventos(
    transaccion_id, estado_wompi, referencia, evento, checksum, cuerpo, resultado
  ) values (
    p_transaccion_id, p_estado_wompi, p_referencia,
    p_evento, p_checksum, p_cuerpo, p_resultado
  ) on conflict (transaccion_id, estado_wompi) do nothing
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function pw__registrar_evento_directa_c6(text,text,text,text,text,jsonb,text)
  from public, anon, authenticated, service_role;

create function pw_procesar_pago(
  p_transaccion_id text, p_estado_wompi text, p_referencia text,
  p_monto_centavos bigint, p_moneda text default null,
  p_evento text default null, p_checksum text default null,
  p_cuerpo jsonb default null, p_metodo_pago text default null,
  p_correo_pagador text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_i pagos_intencion;
  v_estado text := upper(btrim(coalesce(p_estado_wompi, '')));
  v_evento_id bigint;
  v_resultado jsonb;
  v_motivo text;
  v_referencia_evento text;
begin
  if coalesce(btrim(p_transaccion_id), '') = '' or v_estado = '' then
    raise exception 'PW_EVENTO_INVALIDO';
  end if;

  -- Serializa el evento antes de decidir protocolo. Un retry siempre usa la
  -- referencia durable y delega para conservar la autocuración P4.
  perform pg_advisory_xact_lock(hashtextextended(
    'pw-evento:' || p_transaccion_id || ':' || v_estado, 0
  ));
  select pe.referencia into v_referencia_evento
    from pagos_eventos pe
   where pe.transaccion_id = p_transaccion_id
     and pe.estado_wompi = v_estado;
  if found then
    return pw__procesar_pago_p4_c5(
      p_transaccion_id, p_estado_wompi, v_referencia_evento,
      p_monto_centavos, p_moneda, p_evento, p_checksum, p_cuerpo,
      p_metodo_pago, p_correo_pagador
    );
  end if;

  select * into v_i from pagos_intencion where referencia = p_referencia;
  if not found or v_i.recuperacion_directa_version <> 6 then
    return pw__procesar_pago_p4_c5(
      p_transaccion_id, p_estado_wompi, p_referencia, p_monto_centavos,
      p_moneda, p_evento, p_checksum, p_cuerpo, p_metodo_pago, p_correo_pagador
    );
  end if;

  if v_i.auth_user_id is not null then
    perform 1 from auth.users u where u.id = v_i.auth_user_id for update;
    perform 1 from cuentas_cliente cc where cc.auth_user_id = v_i.auth_user_id for update;
  end if;
  select * into v_i from pagos_intencion where referencia = p_referencia for update;

  if v_estado not in ('PENDING','APPROVED','DECLINED','VOIDED','ERROR') then
    v_evento_id := pw__registrar_evento_directa_c6(
      p_transaccion_id, v_estado, p_referencia, p_evento, p_checksum, p_cuerpo, 'ignorado'
    );
    return jsonb_build_object('resultado', 'ignorado', 'estado', v_estado);
  end if;

  if v_i.transaccion_id is not null and v_i.transaccion_id <> p_transaccion_id then
    v_motivo := case when v_i.pedido_id is not null and v_estado = 'APPROVED'
      then 'C6_POSIBLE_DOBLE_COBRO' else 'C6_TRANSACCION_DISTINTA' end;
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           resuelta_en = null, resuelta_por = null, resuelta_nota = null,
           actualizado = statement_timestamp()
     where referencia = p_referencia;
    v_evento_id := pw__registrar_evento_directa_c6(
      p_transaccion_id, v_estado, p_referencia, p_evento, p_checksum, p_cuerpo,
      'datos_no_coinciden'
    );
    return jsonb_build_object('resultado', 'datos_no_coinciden', 'motivo', v_motivo);
  end if;

  if v_i.estado = 'requiere_revision' then
    v_evento_id := pw__registrar_evento_directa_c6(
      p_transaccion_id, v_estado, p_referencia, p_evento, p_checksum, p_cuerpo, 'ignorado'
    );
    return jsonb_build_object('resultado', 'ignorado', 'estado', v_i.estado);
  end if;

  if v_estado = 'PENDING' then
    if v_i.estado <> 'creada' then
      v_evento_id := pw__registrar_evento_directa_c6(
        p_transaccion_id, v_estado, p_referencia, p_evento, p_checksum, p_cuerpo, 'ignorado'
      );
      return jsonb_build_object('resultado', 'ignorado', 'estado', v_i.estado);
    end if;
    if v_i.transaccion_id is null and v_i.expira_en <= statement_timestamp() then
      perform pw__expirar_directa_c6(p_referencia);
      v_evento_id := pw__registrar_evento_directa_c6(
        p_transaccion_id, v_estado, p_referencia, p_evento, p_checksum, p_cuerpo, 'ignorado'
      );
      return jsonb_build_object('resultado', 'ignorado', 'motivo', 'C6_PENDING_POSTERIOR_A_EXPIRACION');
    end if;
    update pagos_intencion
       set transaccion_id = coalesce(transaccion_id, p_transaccion_id),
           estado_wompi = 'PENDING',
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = statement_timestamp()
     where referencia = p_referencia;
    v_evento_id := pw__registrar_evento_directa_c6(
      p_transaccion_id, v_estado, p_referencia, p_evento, p_checksum, p_cuerpo, 'pendiente'
    );
    return jsonb_build_object('resultado', 'pendiente', 'estado', 'PENDING');
  end if;

  if v_estado in ('DECLINED','VOIDED','ERROR') then
    if v_i.estado <> 'creada' then
      v_evento_id := pw__registrar_evento_directa_c6(
        p_transaccion_id, v_estado, p_referencia, p_evento, p_checksum, p_cuerpo, 'ignorado'
      );
      return jsonb_build_object('resultado', 'ignorado', 'estado', v_i.estado);
    end if;
    update pagos_intencion
       set estado = 'rechazada', transaccion_id = coalesce(transaccion_id, p_transaccion_id),
           estado_wompi = v_estado,
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = statement_timestamp()
     where referencia = p_referencia;
    v_evento_id := pw__registrar_evento_directa_c6(
      p_transaccion_id, v_estado, p_referencia, p_evento, p_checksum, p_cuerpo, 'rechazado'
    );
    return jsonb_build_object('resultado', 'rechazado', 'estado', v_estado);
  end if;

  -- APPROVED: rechazo/expiración no se automatizan. Una procesada con el mismo
  -- ID cae al cuerpo histórico idempotente; una distinta ya se detuvo arriba.
  if v_i.estado = 'rechazada'
     or (v_i.estado = 'creada' and v_i.transaccion_id is null
         and v_i.expira_en <= statement_timestamp()) then
    v_motivo := case when v_i.estado = 'rechazada'
      then 'C6_APPROVED_POSTERIOR_A_RECHAZO'
      else 'C6_APPROVED_POSTERIOR_A_EXPIRACION' end;
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           resuelta_en = null, resuelta_por = null, resuelta_nota = null,
           transaccion_id = coalesce(transaccion_id, p_transaccion_id),
           estado_wompi = 'APPROVED',
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = statement_timestamp()
     where referencia = p_referencia;
    v_evento_id := pw__registrar_evento_directa_c6(
      p_transaccion_id, v_estado, p_referencia, p_evento, p_checksum, p_cuerpo,
      'datos_no_coinciden'
    );
    return jsonb_build_object('resultado', 'datos_no_coinciden', 'motivo', v_motivo);
  end if;

  perform set_config(
    'impulse.compra_directa_auth_user_id', coalesce(v_i.auth_user_id::text, ''), true
  );
  begin
    v_resultado := pw__procesar_pago_p4_c5(
      p_transaccion_id, p_estado_wompi, p_referencia, p_monto_centavos,
      p_moneda, p_evento, p_checksum, p_cuerpo, p_metodo_pago, p_correo_pagador
    );
  exception when others then
    perform set_config('impulse.compra_directa_auth_user_id', '', true);
    raise;
  end;
  perform set_config('impulse.compra_directa_auth_user_id', '', true);
  return v_resultado;
end;
$$;
comment on function pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text) is
  'C6 · endurece directas recuperables contra expiración, estados cerrados y transacciones distintas; deriva pedido desde cuenta cuando hay dueño. C5/P4/historia delegan literal.';
revoke all on function pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text)
  from public, anon, authenticated;
grant execute on function pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text)
  to service_role;

-- Helpers internos cerrados incluso para la API service_role.
revoke all on function pw__snapshot_directa_c6(text)
  from public, anon, authenticated, service_role;
revoke all on function pw__expirar_directa_c6(text)
  from public, anon, authenticated, service_role;
revoke all on function pw__registrar_evento_directa_c6(text,text,text,text,text,jsonb,text)
  from public, anon, authenticated, service_role;
revoke all on function pw__estado_checkout_publico_c5(text,uuid)
  from public, anon, authenticated, service_role;
revoke all on function mc__compras_listar_c5()
  from public, anon, authenticated, service_role;
revoke all on function crear_pedido_c6_base(uuid,text,text,text,text,text,text,text,text,text,date,text,jsonb)
  from public, anon, authenticated, service_role;
revoke all on function pw__procesar_pago_p4_c5(text,text,text,bigint,text,text,text,jsonb,text,text)
  from public, anon, authenticated, service_role;

commit;
