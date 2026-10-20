-- ============================================================================
-- MAGANDHI · COMERCIAL C5 · MIS COMPRAS Y CARRITO LIBRE
-- ----------------------------------------------------------------------------
-- Migración FORWARD sobre 20261105000000. Nunca reescribe historia C4.
-- Nuevas intenciones v2 nacen en ciclo 5; ciclos 0/4 conservan sus cuerpos.
-- ============================================================================

begin;

-- El cambio de semántica requiere una ventana con carrito apagado. El lock se
-- conserva hasta COMMIT e impide activarlo a mitad de la migración.
do $$
declare v_habilitado boolean;
begin
  select cfg.carrito_habilitado into v_habilitado
    from comercial_config cfg where cfg.id = 1 for share;
  if not found or v_habilitado is distinct from false then
    raise exception using errcode = 'P0001', message = 'C5_REQUIERE_CARRITO_DESHABILITADO';
  end if;
end;
$$;

-- C5 separa el snapshot del carrito al crear la intención. Estas columnas son
-- evidencia privada inequívoca del origen y de la única versión sucesora.
alter table pagos_intencion
  add column if not exists carrito_separado_en timestamptz,
  add column if not exists carrito_version_sucesora bigint,
  add column if not exists carrito_separacion_detalle jsonb;

alter table pagos_intencion
  drop constraint if exists pagos_intencion_ciclo_carrito_version,
  drop constraint if exists pagos_intencion_expiracion_c4,
  add constraint pagos_intencion_ciclo_carrito_version
    check (
      (version_checkout = 2 and ciclo_carrito_version in (0, 4, 5))
      or (version_checkout in (0, 1) and ciclo_carrito_version = 0)
    ),
  add constraint pagos_intencion_expiracion_c4_c5
    check (
      (version_checkout = 2 and ciclo_carrito_version in (4, 5) and expira_en is not null)
      or not (version_checkout = 2 and ciclo_carrito_version in (4, 5))
    ),
  add constraint pagos_intencion_separacion_c5
    check (
      (
        version_checkout = 2
        and ciclo_carrito_version = 5
        and carrito_separado_en is not null
        and carrito_version_sucesora = carrito_version + 1
        and carrito_separacion_detalle is not null
        and carrito_consumido_en is null
        and carrito_consumo_resultado is null
        and carrito_consumo_detalle is null
      )
      or (
        ciclo_carrito_version <> 5
        and carrito_separado_en is null
        and carrito_version_sucesora is null
        and carrito_separacion_detalle is null
      )
    );

comment on column pagos_intencion.carrito_separado_en is
  'C5 · instante atómico en que el snapshot dejó de ser carrito y pasó a Mis compras.';
comment on column pagos_intencion.carrito_version_sucesora is
  'C5 · versión libre resultante; debe ser exactamente carrito_version + 1.';
comment on column pagos_intencion.carrito_separacion_detalle is
  'C5 · evidencia privada agregada de líneas/unidades retiradas al congelar; sin PII.';
comment on column pagos_intencion.ciclo_carrito_version is
  '0=C3 histórico, 4=C4 histórico bloqueante, 5=C5 carrito libre desde el registro.';

create index if not exists pagos_intencion_c5_propietario_idx
  on pagos_intencion (auth_user_id, creado desc)
  where version_checkout = 2 and ciclo_carrito_version = 5;
create index if not exists pagos_intencion_c5_expiracion_idx
  on pagos_intencion (expira_en)
  where ciclo_carrito_version = 5 and estado = 'creada' and transaccion_id is null;

-- El trigger C4 se reemplaza, no se acumula. Las filas existentes no se tocan.
drop trigger if exists trg_pw_marcar_ciclo_carrito_c4 on pagos_intencion;

create or replace function pw__marcar_ciclo_carrito_c5()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.ciclo_carrito_version := case when new.version_checkout = 2 then 5 else 0 end;
  if new.version_checkout = 2 then
    new.expira_en := date_trunc('milliseconds', transaction_timestamp() + interval '30 minutes');
    -- El helper C3 inserta cabecera y el wrapper C5 separa inmediatamente en la
    -- misma transacción. Precargamos la evidencia para que el CHECK sea válido
    -- durante el INSERT; si la separación/versionado falla, todo hace rollback.
    new.carrito_separado_en := transaction_timestamp();
    new.carrito_version_sucesora := new.carrito_version + 1;
    new.carrito_separacion_detalle := jsonb_build_object('estado', 'separando');
  else
    new.expira_en := null;
    new.carrito_separado_en := null;
    new.carrito_version_sucesora := null;
    new.carrito_separacion_detalle := null;
  end if;
  return new;
end;
$$;
revoke all on function pw__marcar_ciclo_carrito_c5()
  from public, anon, authenticated, service_role;

create trigger trg_pw_marcar_ciclo_carrito_c5
  before insert on pagos_intencion
  for each row execute function pw__marcar_ciclo_carrito_c5();

-- --------------------------------------------------------------------------
-- Registro C5. La firma pública y el índice único v2 histórico no cambian.
-- --------------------------------------------------------------------------
alter function pw_registrar_intencion_carrito(text, uuid, uuid, bigint, text, jsonb, text, text, text)
  rename to pw__registrar_intencion_carrito_c4;
revoke all on function pw__registrar_intencion_carrito_c4(text, uuid, uuid, bigint, text, jsonb, text, text, text)
  from public, anon, authenticated, service_role;

create function pw__snapshot_intencion_c5(p_referencia text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_i pagos_intencion;
  v_items jsonb;
  v_lineas integer;
  v_unidades bigint;
  v_min_ordinal integer;
  v_max_ordinal integer;
  v_total_centavos numeric;
begin
  select * into strict v_i from pagos_intencion where referencia = p_referencia;
  select count(*)::integer, coalesce(sum(i.cantidad), 0)::bigint,
         min(i.ordinal)::integer, max(i.ordinal)::integer,
         coalesce(sum(i.subtotal::numeric * 100), 0),
         coalesce(jsonb_agg(jsonb_build_object(
           'ordinal', i.ordinal, 'campana_id', i.campana_id,
           'product_id', i.product_id, 'slug', i.slug, 'nombre', i.nombre,
           'cantidad', i.cantidad, 'precio_unitario', i.precio_unitario::text,
           'subtotal', i.subtotal::text
         ) order by i.ordinal), '[]'::jsonb)
    into v_lineas, v_unidades, v_min_ordinal, v_max_ordinal,
         v_total_centavos, v_items
    from pagos_intencion_items i where i.referencia = v_i.referencia;

  if v_i.ciclo_carrito_version <> 5
     or v_i.carrito_version_sucesora <> v_i.carrito_version + 1
     or v_i.carrito_separado_en is null
     or v_i.carrito_separacion_detalle is null
     or v_lineas not between 1 and 20
     or v_min_ordinal <> 1 or v_max_ordinal <> v_lineas
     or v_total_centavos <> v_i.monto_centavos::numeric then
    raise exception using errcode = 'XX000', message = 'PW_SNAPSHOT_C5_INCONSISTENTE';
  end if;

  return jsonb_build_object(
    'referencia', v_i.referencia, 'version_checkout', 2,
    'ciclo_carrito_version', 5, 'carrito_id', v_i.carrito_id,
    'carrito_version_fuente', v_i.carrito_version,
    'carrito_version_sucesora', v_i.carrito_version_sucesora,
    'estado', v_i.estado, 'entorno', v_i.entorno,
    'monto_centavos', v_i.monto_centavos::text, 'moneda', v_i.moneda,
    'expira_en', to_char(v_i.expira_en at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'cantidad_lineas', v_lineas, 'cantidad_unidades', v_unidades,
    'items', v_items
  );
end;
$$;
revoke all on function pw__snapshot_intencion_c5(text)
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
  v_existente pagos_intencion;
  v_resultado jsonb;
  v_version_actual bigint;
  v_version_sucesora bigint;
  v_lineas integer;
  v_retiradas integer;
  v_unidades bigint;
begin
  -- Orden compatible con C3/C4: configuración -> cuenta -> carrito.
  perform 1 from comercial_config cfg where cfg.id = 1 for share;
  perform 1 from cuentas_cliente cc
   where cc.auth_user_id = p_auth_user_id and cc.estado = 'activa' for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'PW_CUENTA_NO_DISPONIBLE';
  end if;

  select c.version into v_version_actual
    from carritos c
   where c.id = p_carrito_id
     and c.auth_user_id = p_auth_user_id
     and c.estado = 'activa'
   for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'PW_CARRITO_NO_DISPONIBLE';
  end if;

  -- Idempotencia antes de comparar la versión actual: un retry con la fuente n
  -- recupera la misma intención aunque el carrito libre ya esté en n+1.
  select pi.* into v_existente
    from pagos_intencion pi
   where pi.version_checkout = 2
     and pi.auth_user_id = p_auth_user_id
     and pi.carrito_id = p_carrito_id
     and pi.carrito_version = p_version_esperada
   order by pi.referencia
   limit 1
   for update;
  if v_existente.referencia is not null then
    if v_existente.ciclo_carrito_version = 5 then
      if v_existente.estado <> 'creada'
         or v_existente.transaccion_id is not null
         or v_existente.expira_en <= statement_timestamp() then
        raise exception using errcode = 'P0001', message = 'PW_INTENCION_NO_REABRIBLE';
      end if;
      return pw__snapshot_intencion_c5(v_existente.referencia);
    end if;
    raise exception using errcode = 'P0001', message = 'PW_CARRITO_YA_PROCESADO';
  end if;

  if v_version_actual is distinct from p_version_esperada then
    raise exception using errcode = 'P0001', message = 'PW_VERSION_DESACTUALIZADA';
  end if;

  -- El cuerpo C3 congela y valida de forma autoritativa. El trigger C5 marca la
  -- nueva fila. Todo queda dentro de esta misma transacción.
  v_resultado := pw__registrar_intencion_carrito_c3(
    p_referencia, p_auth_user_id, p_carrito_id, p_version_esperada,
    p_entorno, p_comprador, p_utm_campaign, p_mg_vid, p_moneda
  );

  select count(*)::integer, coalesce(sum(i.cantidad), 0)::bigint
    into v_lineas, v_unidades
    from pagos_intencion_items i where i.referencia = p_referencia;

  delete from carrito_items ci
   using pagos_intencion_items i
   where i.referencia = p_referencia
     and ci.carrito_id = p_carrito_id
     and ci.campana_id = i.campana_id;
  get diagnostics v_retiradas = row_count;
  if v_retiradas <> v_lineas then
    raise exception using errcode = 'XX000', message = 'PW_SEPARACION_C5_LINEAS_INVALIDA';
  end if;

  update carritos
     set version = version + 1, actualizado = statement_timestamp()
   where id = p_carrito_id and version = p_version_esperada
   returning version into v_version_sucesora;
  if v_version_sucesora is null or v_version_sucesora <> p_version_esperada + 1 then
    raise exception using errcode = 'XX000', message = 'PW_SEPARACION_C5_VERSION_INVALIDA';
  end if;

  update pagos_intencion
     set carrito_separado_en = statement_timestamp(),
         carrito_version_sucesora = v_version_sucesora,
         carrito_separacion_detalle = jsonb_build_object(
           'lineas_retiradas', v_lineas, 'unidades_retiradas', v_unidades
         ),
         actualizado = statement_timestamp()
   where referencia = p_referencia and ciclo_carrito_version = 5;
  if not found then
    raise exception using errcode = 'XX000', message = 'PW_SEPARACION_C5_AUSENTE';
  end if;

  return pw__snapshot_intencion_c5(p_referencia);
end;
$$;
comment on function pw_registrar_intencion_carrito(text, uuid, uuid, bigint, text, jsonb, text, text, text) is
  'C5 · firma histórica. Congela el snapshot, retira sus líneas y avanza el carrito exactamente una versión en la misma transacción; retry por versión fuente devuelve la misma intención.';
revoke all on function pw_registrar_intencion_carrito(text, uuid, uuid, bigint, text, jsonb, text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function pw_registrar_intencion_carrito(text, uuid, uuid, bigint, text, jsonb, text, text, text)
  to service_role;

-- C5 solo expira una intención aún creada, vencida y sin noticia bancaria.
create function pw__expirar_intencion_c5(p_referencia text)
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
         revision_motivo = 'C5_INTENCION_EXPIRADA',
         actualizado = statement_timestamp()
   where referencia = p_referencia
     and version_checkout = 2 and ciclo_carrito_version = 5
     and estado = 'creada' and expira_en <= statement_timestamp()
     and transaccion_id is null;
  get diagnostics v_filas = row_count;
  return v_filas = 1;
end;
$$;
revoke all on function pw__expirar_intencion_c5(text)
  from public, anon, authenticated, service_role;

-- --------------------------------------------------------------------------
-- Procesamiento C5. C4 y ciclo 0 conservan literalmente el cuerpo anterior.
-- --------------------------------------------------------------------------
alter function pw_procesar_pago(text, text, text, bigint, text, text, text, jsonb, text, text)
  rename to pw__procesar_pago_c4;
revoke all on function pw__procesar_pago_c4(text, text, text, bigint, text, text, text, jsonb, text, text)
  from public, anon, authenticated, service_role;

create function pw__procesar_pago_c5(
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
  v_estado_evento text := upper(btrim(coalesce(p_estado_wompi, '')));
  v_ins bigint;
  v_ref_evento text;
  v_pedido_evento uuid;
  v_i pagos_intencion;
  v_auth_correo text;
  v_auth_confirmado timestamptz;
  v_auth_ok boolean := false;
  v_estado_cuenta text;
  v_motivo text;
  v_entorno_evento text;
  v_items jsonb;
  v_lineas integer;
  v_min_ordinal integer;
  v_max_ordinal integer;
  v_total_lineas numeric;
  v_pedido jsonb;
  v_pedido_id uuid;
  v_asiento jsonb;
begin
  if coalesce(btrim(p_transaccion_id), '') = '' or v_estado_evento = '' then
    raise exception 'PW_EVENTO_INVALIDO';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(
    'pw-evento:' || p_transaccion_id || ':' || v_estado_evento, 0
  ));
  select pe.referencia, pi.pedido_id into v_ref_evento, v_pedido_evento
    from pagos_eventos pe
    left join pagos_intencion pi on pi.referencia = pe.referencia
   where pe.transaccion_id = p_transaccion_id
     and pe.estado_wompi = v_estado_evento;
  if found then
    return jsonb_build_object('resultado', 'repetido', 'pedido_id', v_pedido_evento);
  end if;

  insert into pagos_eventos (
    transaccion_id, estado_wompi, referencia, evento, checksum, cuerpo, resultado
  ) values (
    p_transaccion_id, v_estado_evento, nullif(p_referencia, ''),
    p_evento, p_checksum, p_cuerpo, 'ignorado'
  ) on conflict (transaccion_id, estado_wompi) do nothing
  returning id into v_ins;
  if v_ins is null then
    select pi.pedido_id into v_pedido_evento
      from pagos_eventos pe left join pagos_intencion pi on pi.referencia = pe.referencia
     where pe.transaccion_id = p_transaccion_id and pe.estado_wompi = v_estado_evento;
    return jsonb_build_object('resultado', 'repetido', 'pedido_id', v_pedido_evento);
  end if;

  select u.email, u.email_confirmed_at into v_auth_correo, v_auth_confirmado
    from auth.users u
    join pagos_intencion pi on pi.auth_user_id = u.id
   where pi.referencia = p_referencia for update of u;
  v_auth_ok := found;
  select cc.estado into v_estado_cuenta
    from cuentas_cliente cc
    join pagos_intencion pi on pi.auth_user_id = cc.auth_user_id
   where pi.referencia = p_referencia for update of cc;
  select * into v_i from pagos_intencion where referencia = p_referencia for update;

  if not found or v_i.version_checkout <> 2 or v_i.ciclo_carrito_version <> 5 then
    update pagos_eventos set resultado = 'datos_no_coinciden' where id = v_ins;
    return jsonb_build_object('resultado', 'datos_no_coinciden');
  end if;

  -- Una intención procesada con la misma transacción es siempre un retry, aun
  -- si Wompi reenvía una variante de evento que no requiere otra mutación.
  if v_i.estado = 'procesada' and v_i.transaccion_id = p_transaccion_id then
    update pagos_eventos set resultado = 'ya_procesada' where id = v_ins;
    return jsonb_build_object('resultado', 'ya_procesada', 'pedido_id', v_i.pedido_id);
  end if;

  -- Los estados no documentados solo quedan auditados. En particular, ni una
  -- referencia a otra transacción puede hacer que muten o adquieran intención.
  if v_estado_evento not in ('PENDING', 'APPROVED', 'DECLINED', 'VOIDED', 'ERROR') then
    update pagos_eventos set resultado = 'ignorado' where id = v_ins;
    return jsonb_build_object('resultado', 'ignorado', 'estado', v_estado_evento);
  end if;

  -- Una transacción distinta nunca reemplaza la evidencia bancaria ya fijada.
  -- El evento entrante queda durable en pagos_eventos y la intención se eleva
  -- a revisión; un segundo APPROVED sobre un pedido existente es posible doble
  -- cobro, no una autorización para crear otro pedido.
  if v_i.transaccion_id is not null
     and v_i.transaccion_id <> p_transaccion_id then
    v_motivo := case
      when v_i.pedido_id is not null and v_estado_evento = 'APPROVED'
        then 'C5_POSIBLE_DOBLE_COBRO'
      else 'C5_TRANSACCION_DISTINTA'
    end;
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           resuelta_en = null, resuelta_por = null, resuelta_nota = null,
           actualizado = statement_timestamp()
     where referencia = p_referencia;
    update pagos_eventos set resultado = 'datos_no_coinciden' where id = v_ins;
    return jsonb_build_object('resultado', 'datos_no_coinciden', 'motivo', v_motivo);
  end if;

  -- Una intención procesada sin una transacción coherente no puede crear otro
  -- pedido; el caso normal con el mismo ID ya retornó arriba como retry.
  if v_i.estado = 'procesada' then
    update pagos_eventos set resultado = 'ya_procesada' where id = v_ins;
    return jsonb_build_object('resultado', 'ya_procesada', 'pedido_id', v_i.pedido_id);
  end if;

  if v_estado_evento = 'PENDING' then
    if v_i.estado <> 'creada' then
      update pagos_eventos set resultado = 'ignorado' where id = v_ins;
      return jsonb_build_object('resultado', 'ignorado', 'estado', v_i.estado);
    end if;
    if v_i.transaccion_id is null then
      if v_i.expira_en <= statement_timestamp() then
        perform pw__expirar_intencion_c5(p_referencia);
        update pagos_eventos set resultado = 'ignorado' where id = v_ins;
        return jsonb_build_object('resultado', 'ignorado', 'motivo', 'C5_PENDING_POSTERIOR_A_EXPIRACION');
      end if;
      update pagos_intencion
         set transaccion_id = p_transaccion_id, estado_wompi = 'PENDING',
             metodo_pago = coalesce(p_metodo_pago, metodo_pago),
             correo_pagador = coalesce(p_correo_pagador, correo_pagador),
             actualizado = statement_timestamp()
       where referencia = p_referencia;
    else
      update pagos_intencion
         set estado_wompi = 'PENDING',
             metodo_pago = coalesce(p_metodo_pago, metodo_pago),
             correo_pagador = coalesce(p_correo_pagador, correo_pagador),
             actualizado = statement_timestamp()
       where referencia = p_referencia;
    end if;
    update pagos_eventos set resultado = 'pendiente' where id = v_ins;
    return jsonb_build_object('resultado', 'pendiente', 'estado', 'PENDING');
  end if;

  if v_estado_evento in ('DECLINED', 'VOIDED', 'ERROR') then
    if v_i.estado in ('rechazada', 'requiere_revision') then
      update pagos_eventos set resultado = 'ignorado' where id = v_ins;
      return jsonb_build_object('resultado', 'ignorado', 'estado', v_i.estado);
    end if;
    update pagos_intencion
       set estado = 'rechazada', estado_wompi = v_estado_evento,
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = statement_timestamp()
     where referencia = p_referencia;
    update pagos_eventos set resultado = 'rechazado' where id = v_ins;
    return jsonb_build_object('resultado', 'rechazado', 'estado', v_estado_evento);
  end if;

  -- APPROVED directo es válido mientras la intención siga creada y vigente:
  -- Wompi no garantiza que nuestro webhook reciba antes un evento PENDING.
  -- Rechazos/revisión y aprobaciones posteriores al vencimiento requieren
  -- intervención, pero una aprobación vigente puede fijar su primer ID aquí.
  if v_i.estado = 'rechazada' then
    v_motivo := 'C5_APPROVED_POSTERIOR_A_RECHAZO';
  elsif v_i.estado = 'requiere_revision' then
    update pagos_eventos set resultado = 'ignorado' where id = v_ins;
    return jsonb_build_object('resultado', 'ignorado', 'estado', v_i.estado);
  elsif v_i.transaccion_id is null and v_i.expira_en <= statement_timestamp() then
    v_motivo := 'C5_APPROVED_POSTERIOR_A_EXPIRACION';
  end if;

  if v_motivo is not null then
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           resuelta_en = null, resuelta_por = null, resuelta_nota = null,
           transaccion_id = coalesce(transaccion_id, p_transaccion_id),
           estado_wompi = 'APPROVED',
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = statement_timestamp()
     where referencia = p_referencia;
    update pagos_eventos set resultado = 'datos_no_coinciden' where id = v_ins;
    return jsonb_build_object('resultado', 'datos_no_coinciden', 'motivo', v_motivo);
  end if;

  if not v_auth_ok or v_estado_cuenta is distinct from 'activa' then
    v_motivo := 'C5_IDENTIDAD_NO_DISPONIBLE';
  elsif p_monto_centavos is null or p_monto_centavos <> v_i.monto_centavos then
    v_motivo := 'C5_MONTO_NO_COINCIDE';
  end if;

  v_entorno_evento := case lower(coalesce(p_cuerpo->>'environment', ''))
    when 'test' then 'sandbox' when 'sandbox' then 'sandbox'
    when 'prod' then 'prod' when 'production' then 'prod' else null end;
  if v_motivo is null and upper(nullif(btrim(p_moneda), ''))
       is distinct from upper(nullif(btrim(v_i.moneda), '')) then
    v_motivo := 'C5_MONEDA_NO_COINCIDE';
  elsif v_motivo is null and v_entorno_evento is distinct from v_i.entorno then
    v_motivo := 'C5_ENTORNO_NO_COINCIDE';
  end if;

  select count(*)::integer, min(i.ordinal)::integer, max(i.ordinal)::integer,
         coalesce(sum(i.subtotal::numeric * 100), 0),
         coalesce(jsonb_agg(jsonb_build_object(
           'campana_id', i.campana_id, 'product_id', i.product_id,
           'nombre', i.nombre, 'slug', i.slug, 'cantidad', i.cantidad,
           'precio_unitario', i.precio_unitario
         ) order by i.ordinal), '[]'::jsonb)
    into v_lineas, v_min_ordinal, v_max_ordinal, v_total_lineas, v_items
    from pagos_intencion_items i where i.referencia = v_i.referencia;
  if v_motivo is null and (
       v_lineas not between 1 and 20 or v_min_ordinal <> 1
       or v_max_ordinal <> v_lineas
       or v_total_lineas <> v_i.monto_centavos::numeric
     ) then
    v_motivo := 'C5_SNAPSHOT_NO_COINCIDE';
  end if;

  if v_motivo is not null then
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           estado_wompi = 'APPROVED',
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = statement_timestamp()
     where referencia = p_referencia;
    update pagos_eventos
       set resultado = case when v_motivo = 'C5_MONTO_NO_COINCIDE'
                            then 'monto_no_coincide' else 'datos_no_coinciden' end
     where id = v_ins;
    return jsonb_build_object(
      'resultado', case when v_motivo = 'C5_MONTO_NO_COINCIDE'
                        then 'monto_no_coincide' else 'datos_no_coinciden' end,
      'motivo', v_motivo
    );
  end if;

  begin
    perform set_config('impulse.pago_servidor', 'on', true);
    perform set_config('impulse.checkout_legacy', 'off', true);
    v_pedido := crear_pedido_c4(
      p_auth_user_id => v_i.auth_user_id,
      p_nombre => coalesce(v_i.comprador_nombre, 'Comprador web'),
      p_correo => coalesce(
        v_i.comprador_correo,
        case when v_auth_confirmado is not null then v_auth_correo else null end,
        p_correo_pagador
      ),
      p_telefono => v_i.comprador_telefono,
      p_direccion => v_i.comprador_direccion,
      p_ciudad => v_i.comprador_ciudad,
      p_departamento => v_i.comprador_departamento,
      p_pais => v_i.comprador_pais,
      p_canal => 'web', p_fecha_orden => fz__fecha_colombia(),
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
    update pagos_intencion
       set estado = 'requiere_revision', revision_motivo = v_motivo,
           estado_wompi = 'APPROVED',
           metodo_pago = coalesce(p_metodo_pago, metodo_pago),
           correo_pagador = coalesce(p_correo_pagador, correo_pagador),
           actualizado = statement_timestamp()
     where referencia = p_referencia;
    update pagos_eventos
       set resultado = case when v_motivo like 'C4_%' or v_motivo like 'C5_%'
                            then 'datos_no_coinciden' else 'sin_stock' end
     where id = v_ins;
    return jsonb_build_object(
      'resultado', case when v_motivo like 'C4_%' or v_motivo like 'C5_%'
                        then 'datos_no_coinciden' else 'sin_stock' end,
      'motivo', v_motivo
    );
  end;

  if v_i.utm_campaign is not null then
    update pedidos set utm_campaign = v_i.utm_campaign where id = v_pedido_id;
  end if;
  update pedido_bitacora
     set detalle_cambio = coalesce(detalle_cambio, '{}'::jsonb)
       || jsonb_build_object('ciclo_carrito', jsonb_build_object(
            'resultado', 'separado_al_crear',
            'version_fuente', v_i.carrito_version,
            'version_sucesora', v_i.carrito_version_sucesora
          ))
   where pedido_id = v_pedido_id and accion = 'crear';

  update pagos_intencion
     set estado = 'procesada', pedido_id = v_pedido_id,
         transaccion_id = coalesce(transaccion_id, p_transaccion_id),
         estado_wompi = 'APPROVED',
         metodo_pago = coalesce(p_metodo_pago, metodo_pago),
         correo_pagador = coalesce(p_correo_pagador, correo_pagador),
         revision_motivo = null, procesada_en = statement_timestamp(),
         actualizado = statement_timestamp()
   where referencia = p_referencia;
  update pagos_eventos set resultado = 'procesado' where id = v_ins;

  begin
    v_asiento := fz__asiento_venta_web(v_pedido_id);
  exception when others then
    v_asiento := jsonb_build_object('resultado', 'pendiente', 'motivo', sqlerrm);
  end;

  return jsonb_build_object(
    'resultado', 'procesado', 'pedido_id', v_pedido_id,
    'consumo_carrito', 'separado_al_crear', 'asiento', v_asiento
  );
end;
$$;
revoke all on function pw__procesar_pago_c5(text, text, text, bigint, text, text, text, jsonb, text, text)
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
begin
  if exists (
    select 1 from pagos_intencion
     where referencia = p_referencia
       and version_checkout = 2 and ciclo_carrito_version = 5
  ) then
    return pw__procesar_pago_c5(
      p_transaccion_id, p_estado_wompi, p_referencia, p_monto_centavos,
      p_moneda, p_evento, p_checksum, p_cuerpo, p_metodo_pago, p_correo_pagador
    );
  end if;
  return pw__procesar_pago_c4(
    p_transaccion_id, p_estado_wompi, p_referencia, p_monto_centavos,
    p_moneda, p_evento, p_checksum, p_cuerpo, p_metodo_pago, p_correo_pagador
  );
end;
$$;
comment on function pw_procesar_pago(text, text, text, bigint, text, text, text, jsonb, text, text) is
  'C5 · despacha ciclo 5 al procesador sin carrito y conserva literal el cuerpo C4 para ciclos 0/4 y v0/v1.';
revoke all on function pw_procesar_pago(text, text, text, bigint, text, text, text, jsonb, text, text)
  from public, anon, authenticated;
grant execute on function pw_procesar_pago(text, text, text, bigint, text, text, text, jsonb, text, text)
  to service_role;

-- --------------------------------------------------------------------------
-- Mis compras: una proyección owner-safe, sin parámetros de identidad.
-- --------------------------------------------------------------------------
-- Proyección owner-safe de intenciones y del historial comercial enlazado.
create function mc_compras_listar()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_estado_cuenta text;
  v_customer_id uuid;
  v_resultado jsonb;
  v_ref text;
begin
  if v_uid is null then
    raise exception using errcode = 'P0001', message = 'MC_SESION_REQUERIDA';
  end if;
  select cc.estado, cc.customer_id into v_estado_cuenta, v_customer_id
    from cuentas_cliente cc
   where cc.auth_user_id = v_uid
   for update;
  if not found or v_estado_cuenta <> 'activa' then
    raise exception using errcode = 'P0001', message = 'MC_CUENTA_NO_DISPONIBLE';
  end if;

  for v_ref in
    select pi.referencia from pagos_intencion pi
     where pi.auth_user_id = v_uid and pi.ciclo_carrito_version = 5
       and pi.estado = 'creada' and pi.expira_en <= statement_timestamp()
       and pi.transaccion_id is null
     order by pi.referencia for update
  loop
    perform pw__expirar_intencion_c5(v_ref);
  end loop;

  with tarjetas as (
    select coalesce(pi.procesada_en, pi.creado) as orden,
           pi.referencia as desempate,
           jsonb_build_object(
      'referencia', pi.referencia,
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
      'creado_colombia', to_char(pi.creado at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS'),
      'actualizado_iso', to_char(pi.actualizado at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'total_cop', (pi.monto_centavos / 100)::bigint,
      'expira_en', to_char(pi.expira_en at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'expira_colombia', to_char(pi.expira_en at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS'),
      'puede_continuar', pi.estado = 'creada' and pi.transaccion_id is null
        and pi.expira_en > statement_timestamp(),
      'puede_verificar', (pi.estado = 'requiere_revision' and pi.resuelta_en is null)
        or (pi.estado = 'creada' and pi.transaccion_id is not null),
      'lineas', coalesce((
        select jsonb_agg(jsonb_build_object(
          'nombre', ii.nombre, 'cantidad', ii.cantidad, 'subtotal', ii.subtotal,
          'slug', cat.slug, 'id', cat.id, 'imagen', cat.imagen_banner_path,
          'puede_opinar', pi.pedido_id is not null
            and p.estado = 'entregado' and not coalesce(p.anulado, false)
            and cat.id is not null and coalesce(pr.activo, false)
            and not exists (select 1 from opiniones o
                            where o.pedido_id = pi.pedido_id
                              and o.product_id = ii.product_id)
        ) order by ii.ordinal)
        from pagos_intencion_items ii
        left join productos pr on pr.id = ii.product_id
        left join lateral (
          select cp.id, cp.slug, cp.imagen_banner_path
            from catalogo_publico cp
           where cp.id = ii.campana_id
           limit 1
        ) cat on true
        where ii.referencia = pi.referencia
      ), '[]'::jsonb),
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
            'fecha_iso', to_char(pb.cuando at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'fecha_colombia', to_char(pb.cuando at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS')
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
     where pi.auth_user_id = v_uid
       and pi.version_checkout = 2 and pi.ciclo_carrito_version = 5

    union all

    select p.creado as orden,
           'PED-' || md5(p.id::text) as desempate,
           jsonb_build_object(
      'referencia', 'PED-' || md5(p.id::text),
      'clasificacion', case when p.anulado or p.estado = 'anulado'
        then 'no_completada' else 'realizada' end,
      'estado', case when p.anulado or p.estado = 'anulado'
        then 'anulada' else 'aprobada' end,
      'etiqueta', case when p.anulado or p.estado = 'anulado'
        then 'Pedido anulado' else 'Compra realizada' end,
      'creado_iso', to_char(p.creado at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'comprado_iso', to_char(p.creado at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'creado_colombia', to_char(p.creado at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS'),
      'actualizado_iso', to_char(coalesce(p.actualizado, p.creado) at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'total_cop', p.total,
      'expira_en', null,
      'expira_colombia', null,
      'puede_continuar', false,
      'puede_verificar', false,
      'lineas', coalesce((
        select jsonb_agg(jsonb_build_object(
          'nombre', coalesce(ii.campana_nombre, cat.nombre, pr.nombre, 'Producto'),
          'cantidad', ii.cantidad, 'subtotal', ii.subtotal,
          'slug', cat.slug, 'id', cat.id, 'imagen', cat.imagen_banner_path,
          'puede_opinar', p.estado = 'entregado' and not p.anulado
            and cat.id is not null and coalesce(pr.activo, false)
            and not exists (select 1 from opiniones o
                            where o.pedido_id = p.id and o.product_id = ii.product_id)
        ) order by ii.id)
        from pedido_items ii
        left join productos pr on pr.id = ii.product_id
        left join lateral (
          select cp.id, cp.nombre, cp.slug, cp.imagen_banner_path
            from catalogo_publico cp
            join campana_producto mapa on mapa.id = cp.id
           where cp.id = ii.campana_id or mapa.product_id_ref = ii.product_id
           order by case when cp.id = ii.campana_id then 0 else 1 end, cp.id
           limit 1
        ) cat on true
        where ii.pedido_id = p.id
      ), '[]'::jsonb),
      'pedido', jsonb_build_object(
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
            'fecha_iso', to_char(pb.cuando at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
            'fecha_colombia', to_char(pb.cuando at time zone 'America/Bogota', 'YYYY-MM-DD HH24:MI:SS')
          ) order by pb.cuando, pb.id)
          from pedido_bitacora pb
          where pb.pedido_id = p.id
            and (pb.accion in ('crear','anular')
                 or pb.estado_nuevo in ('recibido','preparando','en_camino','entregado'))
        ), '[]'::jsonb)
      )
    ) as card
      from pedidos p
     where v_customer_id is not null
       and p.customer_id = v_customer_id
       and not exists (
         select 1 from pagos_intencion pi5
          where pi5.pedido_id = p.id
            and pi5.version_checkout = 2 and pi5.ciclo_carrito_version = 5
       )
  ), recientes as (
    select orden, desempate, card from tarjetas
     order by orden desc, desempate desc
     limit 100
  )
  select coalesce(jsonb_agg(card order by orden desc, desempate desc), '[]'::jsonb)
    into v_resultado
    from recientes;

  return jsonb_build_object('compras', v_resultado);
end;
$$;
comment on function mc_compras_listar() is
  'C5 · proyección owner-safe de hasta 100 intenciones C5 y pedidos del customer_id enlazado, sin duplicar pedidos representados por C5 ni exponer PII o identificadores internos de identidad.';
revoke all on function mc_compras_listar() from public, anon, authenticated, service_role;
grant execute on function mc_compras_listar() to authenticated, service_role;

-- Reapertura privada: la Edge deriva UID del JWT y service_role lo presenta.
create function mc_reabrir_intencion_c5(p_referencia text, p_auth_user_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_i pagos_intencion;
  v_estado_cuenta text;
  v_lineas integer;
  v_snapshot jsonb;
begin
  if p_referencia is null or p_referencia !~ '^[A-Za-z0-9_-]{6,64}$'
     or p_auth_user_id is null then
    raise exception using errcode = 'P0001', message = 'MC_INTENCION_NO_DISPONIBLE';
  end if;
  select cc.estado into v_estado_cuenta from cuentas_cliente cc
   where cc.auth_user_id = p_auth_user_id for update;
  select * into v_i from pagos_intencion pi
   where pi.referencia = p_referencia for update;
  if not found or v_i.auth_user_id is distinct from p_auth_user_id
     or v_i.ciclo_carrito_version <> 5 or v_estado_cuenta is distinct from 'activa' then
    raise exception using errcode = 'P0001', message = 'MC_INTENCION_NO_DISPONIBLE';
  end if;
  perform pw__expirar_intencion_c5(p_referencia);
  select * into v_i from pagos_intencion where referencia = p_referencia;
  if v_i.estado <> 'creada' or v_i.expira_en <= statement_timestamp()
     or v_i.transaccion_id is not null then
    raise exception using errcode = 'P0001', message = 'MC_INTENCION_NO_REABRIBLE';
  end if;
  v_snapshot := pw__snapshot_intencion_c5(p_referencia);
  v_lineas := (v_snapshot->>'cantidad_lineas')::integer;
  return jsonb_build_object(
    'referencia', v_i.referencia, 'monto_centavos', v_i.monto_centavos::text,
    'moneda', v_i.moneda, 'entorno', v_i.entorno,
    'expira_en', to_char(v_i.expira_en at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'nombre_producto', case when v_lineas = 1 then
      (select nombre from pagos_intencion_items where referencia = p_referencia order by ordinal limit 1)
      else v_lineas::text || ' productos' end,
    'comprador', jsonb_strip_nulls(jsonb_build_object(
      'nombre', v_i.comprador_nombre, 'correo', v_i.comprador_correo,
      'telefono', v_i.comprador_telefono, 'direccion', v_i.comprador_direccion,
      'ciudad', v_i.comprador_ciudad, 'departamento', v_i.comprador_departamento,
      'pais', v_i.comprador_pais
    ))
  );
end;
$$;
comment on function mc_reabrir_intencion_c5(text, uuid) is
  'C5 · puerta service_role owner-checked. Solo reabre una intención propia, creada, vigente y sin transacción bancaria.';
revoke all on function mc_reabrir_intencion_c5(text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function mc_reabrir_intencion_c5(text, uuid) to service_role;

-- --------------------------------------------------------------------------
-- Retorno: C5 no toca el carrito y usa descriptor tipo compra. C4 queda literal.
-- --------------------------------------------------------------------------
alter function pw_estado_checkout_publico(text, uuid)
  rename to pw__estado_checkout_publico_c4;
revoke all on function pw__estado_checkout_publico_c4(text, uuid)
  from public, anon, authenticated, service_role;

create function pw_estado_checkout_publico(p_referencia text, p_auth_user_id uuid default null)
returns table (estado text, nombre_producto text, slug text, checkout jsonb)
language plpgsql
security definer
volatile
set search_path = public
as $$
declare v_i pagos_intencion; v_lineas integer; v_nombre text; v_slug text;
begin
  if p_referencia is null or p_referencia !~ '^[A-Za-z0-9_-]{6,64}$' then return; end if;
  select * into v_i from pagos_intencion where referencia = p_referencia;
  if not found or v_i.ciclo_carrito_version <> 5 then
    return query select * from pw__estado_checkout_publico_c4(p_referencia, p_auth_user_id);
    return;
  end if;
  if p_auth_user_id is distinct from v_i.auth_user_id then return; end if;
  perform 1 from cuentas_cliente cc where cc.auth_user_id = v_i.auth_user_id for update;
  perform 1 from pagos_intencion pi where pi.referencia = p_referencia for update;
  perform pw__expirar_intencion_c5(p_referencia);
  select * into v_i from pagos_intencion where referencia = p_referencia;
  select count(*)::integer,
         case when count(*) = 1 then max(i.nombre) else count(*)::text || ' productos' end,
         case when count(*) = 1 then max(i.slug) else '' end
    into v_lineas, v_nombre, v_slug
    from pagos_intencion_items i where i.referencia = p_referencia;
  return query select
    case
      when v_i.estado = 'requiere_revision' and v_i.resuelta_en is not null then 'rechazado'
      else case v_i.estado when 'creada' then 'pendiente' when 'procesada' then 'aprobado'
        when 'rechazada' then 'rechazado' when 'requiere_revision' then 'revision'
        else 'pendiente' end
    end,
    coalesce(v_nombre, ''), coalesce(v_slug, ''),
    jsonb_build_object('tipo', 'compra', 'referencia', v_i.referencia, 'recargar', true);
end;
$$;
comment on function pw_estado_checkout_publico(text, uuid) is
  'C5 · ciclo 5 exige dueño, expira sin carrito y retorna tipo compra; ciclos históricos delegan al cuerpo C4 literal.';
revoke all on function pw_estado_checkout_publico(text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function pw_estado_checkout_publico(text, uuid) to service_role;

-- --------------------------------------------------------------------------
-- Ventas: repetir estado es no-op; cualquier salto/retroceso se rechaza.
-- --------------------------------------------------------------------------
create or replace function avanzar_estado_pedido(p_pedido_id uuid, p_nuevo_estado text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_anulado boolean;
  v_estado_ant text;
  v_siguiente text;
begin
  if not tiene_acceso_ventas() then
    raise exception 'Acceso denegado: se requiere el area de ventas.';
  end if;
  if p_nuevo_estado is null or p_nuevo_estado not in ('recibido','preparando','en_camino','entregado') then
    raise exception 'Estado invalido: %. Use recibido, preparando, en_camino o entregado (para anular use anular_pedido).', p_nuevo_estado;
  end if;
  select anulado, estado into v_anulado, v_estado_ant
    from pedidos where id = p_pedido_id for update;
  if not found then raise exception 'El pedido % no existe.', p_pedido_id; end if;
  if v_anulado then
    raise exception 'El pedido % esta anulado y no admite avance de estado.', p_pedido_id;
  end if;
  if p_nuevo_estado = v_estado_ant then
    return jsonb_build_object('pedido_id', p_pedido_id, 'estado', v_estado_ant, 'cambio', false);
  end if;
  v_siguiente := case v_estado_ant
    when 'recibido' then 'preparando'
    when 'preparando' then 'en_camino'
    when 'en_camino' then 'entregado'
    else null end;
  if p_nuevo_estado is distinct from v_siguiente then
    raise exception 'Transicion invalida: el pedido esta en % y solo puede avanzar a %.',
      v_estado_ant, coalesce(v_siguiente, 'ningun estado');
  end if;
  update pedidos set estado = p_nuevo_estado, actualizado = now()
   where id = p_pedido_id;
  insert into pedido_bitacora (
    pedido_id, accion, estado_anterior, estado_nuevo, detalle_cambio, actor
  ) values (
    p_pedido_id, 'cambio_estado', v_estado_ant, p_nuevo_estado, null, auth.uid()
  );
  return jsonb_build_object('pedido_id', p_pedido_id, 'estado', p_nuevo_estado, 'cambio', true);
end;
$$;
comment on function avanzar_estado_pedido(uuid, text) is
  'C5 · bajo FOR UPDATE, repetir el estado actual es no-op sin bitácora y solo se admite el siguiente estado real.';
revoke all on function avanzar_estado_pedido(uuid, text) from public, anon;
grant execute on function avanzar_estado_pedido(uuid, text) to authenticated, service_role;

-- Helpers internos cerrados incluso para API service_role.
revoke all on function pw__registrar_intencion_carrito_c4(text, uuid, uuid, bigint, text, jsonb, text, text, text)
  from public, anon, authenticated, service_role;
revoke all on function pw__snapshot_intencion_c5(text)
  from public, anon, authenticated, service_role;
revoke all on function pw__expirar_intencion_c5(text)
  from public, anon, authenticated, service_role;
revoke all on function pw__procesar_pago_c4(text, text, text, bigint, text, text, text, jsonb, text, text)
  from public, anon, authenticated, service_role;
revoke all on function pw__procesar_pago_c5(text, text, text, bigint, text, text, text, jsonb, text, text)
  from public, anon, authenticated, service_role;
revoke all on function pw__estado_checkout_publico_c4(text, uuid)
  from public, anon, authenticated, service_role;
revoke all on function pw__marcar_ciclo_carrito_c4()
  from public, anon, authenticated, service_role;
revoke all on function pw__marcar_ciclo_carrito_c5()
  from public, anon, authenticated, service_role;

commit;
