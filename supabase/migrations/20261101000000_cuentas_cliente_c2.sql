-- ============================================================================
-- MAGANDHI · CUENTAS DE CLIENTE C2 · ALTA TRAS CORREO CONFIRMADO
-- ----------------------------------------------------------------------------
-- Puerta unica para crear el puente de una sesion Auth confirmada. No recibe
-- UID, correo ni customer_id del navegador. El vinculo historico se hace solo
-- cuando exactamente un cliente coincide con el correo confirmado normalizado.
-- Las migraciones anteriores permanecen inmutables.
-- ============================================================================

begin;

-- Cola PRIVADA para revisar los casos que nunca deben fusionarse a ciegas.
-- No guarda el correo. Solo postgres (dueno) puede leerla o resolverla; ni el
-- navegador ni una Edge Function con service_role tienen privilegios directos.
create table if not exists cc_conflictos_revision (
  auth_user_id         uuid primary key references auth.users(id) on delete cascade,
  motivo               text not null
                         check (motivo in ('correo_ambiguo', 'cliente_ya_vinculado', 'carrera_vinculo')),
  coincidencias        integer not null check (coincidencias >= 1),
  customer_id_candidato uuid references clientes(id) on delete restrict,
  estado               text not null default 'pendiente'
                         check (estado in ('pendiente', 'resuelto')),
  detectado_en         timestamptz not null default now(),
  actualizado          timestamptz not null default now(),
  resuelto_en          timestamptz,
  notas_revision       text,
  constraint cc_conflictos_revision_resolucion_coherente check (
    (estado = 'pendiente' and resuelto_en is null)
    or (estado = 'resuelto' and resuelto_en is not null)
  )
);

comment on table cc_conflictos_revision is
  'PRIVADA · conflictos de vinculo historico C2. No contiene correos y no se expone por API. La cuenta nace sin customer_id hasta revision humana.';
comment on column cc_conflictos_revision.customer_id_candidato is
  'Solo se llena cuando hubo un unico cliente por correo pero ya estaba vinculado. Nunca se devuelve al navegador.';

alter table cc_conflictos_revision enable row level security;
revoke all on table cc_conflictos_revision from public, anon, authenticated, service_role;

-- --------------------------------------------------------------------------
-- Candado granular por correo para clientes y altas C2.
--
-- Cada INSERT/UPDATE/DELETE de clientes toma los advisory locks de todas sus formas
-- normalizadas (correo crudo y correo_norm, anteriores y nuevas). C2 toma el
-- mismo lock antes de buscar historia. Asi una escritura concurrente del mismo
-- correo termina antes de decidir el vinculo, sin bloquear pedidos o ediciones
-- de clientes con otros correos.
-- --------------------------------------------------------------------------
create or replace function cc__bloquear_correos_cliente()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_nuevo_correo text;
  v_nuevo_norm   text;
  v_anterior_correo text;
  v_anterior_norm   text;
  v_clave bigint;
begin
  if tg_op in ('INSERT', 'UPDATE') then
    v_nuevo_correo := ventas_norm_correo(new.correo);
    v_nuevo_norm := ventas_norm_correo(new.correo_norm);
  end if;
  if tg_op in ('UPDATE', 'DELETE') then
    v_anterior_correo := ventas_norm_correo(old.correo);
    v_anterior_norm := ventas_norm_correo(old.correo_norm);
  end if;

  -- Orden estable para que dos cambios cruzados de correo no formen deadlock.
  for v_clave in
    select distinct k
      from unnest(array[
        case when v_nuevo_correo is null then null else hashtextextended('cc-correo:' || v_nuevo_correo, 0) end,
        case when v_nuevo_norm is null then null else hashtextextended('cc-correo:' || v_nuevo_norm, 0) end,
        case when v_anterior_correo is null then null else hashtextextended('cc-correo:' || v_anterior_correo, 0) end,
        case when v_anterior_norm is null then null else hashtextextended('cc-correo:' || v_anterior_norm, 0) end
      ]) as claves(k)
     where k is not null
     order by k
  loop
    perform pg_advisory_xact_lock(v_clave);
  end loop;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke execute on function cc__bloquear_correos_cliente() from public, anon, authenticated;
grant execute on function cc__bloquear_correos_cliente() to service_role;

drop trigger if exists trg_cc_bloquear_correos_cliente on clientes;
drop trigger if exists trg_cc_bloquear_correos_cliente_insert_delete on clientes;
drop trigger if exists trg_cc_bloquear_correos_cliente_update on clientes;
create trigger trg_cc_bloquear_correos_cliente_insert_delete
  before insert or delete on clientes
  for each row execute function cc__bloquear_correos_cliente();
create trigger trg_cc_bloquear_correos_cliente_update
  before update of correo, correo_norm on clientes
  for each row execute function cc__bloquear_correos_cliente();

-- --------------------------------------------------------------------------
-- Alta idempotente de la cuenta de la sesion actual.
-- --------------------------------------------------------------------------
create or replace function cc_inicializar_cuenta()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid                 uuid := auth.uid();
  v_correo              text;
  v_confirmado_en       timestamptz;
  v_correo_norm         text;
  v_customer_id         uuid;
  v_customer_iter       uuid;
  v_coincidencias       integer := 0;
  v_vinculado_a         uuid;
  v_estado_cuenta       text;
  v_motivo              text;
begin
  if v_uid is null then
    raise exception using errcode = 'P0001', message = 'CC_SESION_REQUERIDA';
  end if;

  -- Este es el lock comun con los triggers de C1. Serializa callback, reintento
  -- y alta de perfiles para el mismo UID. La identidad y el correo salen solo
  -- de auth.users; no se consulta metadata de proveedor ni datos del body.
  select u.email, u.email_confirmed_at
    into v_correo, v_confirmado_en
    from auth.users u
   where u.id = v_uid
   for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'CC_SESION_INVALIDA';
  end if;

  v_correo_norm := ventas_norm_correo(v_correo);
  if v_confirmado_en is null or v_correo_norm is null then
    raise exception using errcode = 'P0001', message = 'CC_CORREO_NO_CONFIRMADO';
  end if;

  if exists (select 1 from perfiles p where p.id = v_uid) then
    raise exception using errcode = 'P0001', message = 'CC_IDENTIDAD_ES_PERSONAL';
  end if;

  -- Idempotencia fuerte: una cuenta activa ya creada no cambia de cliente ni
  -- vuelve a resolver historia en callbacks o logins posteriores. Bloqueadas y
  -- cerradas conservan su historia, pero no pueden abrir una sesion publica.
  select cc.estado
    into v_estado_cuenta
    from cuentas_cliente cc
   where cc.auth_user_id = v_uid
   for update;
  if found then
    if v_estado_cuenta = 'activa' then
      return jsonb_build_object('ok', true, 'estado', 'lista');
    end if;
    raise exception using errcode = 'P0001', message = 'CC_CUENTA_NO_DISPONIBLE';
  end if;

  -- Serializa solo las altas y escrituras comerciales que tocan este mismo
  -- correo. Los triggers trg_cc_bloquear_correos_cliente_* adoptan exactamente
  -- esta clave en todo INSERT/UPDATE/DELETE de clientes, incluidos datos
  -- antiguos con correo_norm vacio o incoherente.
  perform pg_advisory_xact_lock(hashtextextended('cc-correo:' || v_correo_norm, 0));

  -- Se normalizan AMBAS fuentes historicas. Algunos registros antiguos pueden
  -- tener correo_norm vacio/desactualizado pero conservar el correo crudo. El
  -- advisory lock mantiene estable este conjunto frente a escrituras del mismo
  -- correo sin esperar locks de fila, evitando una inversion con UPDATE.
  for v_customer_iter in
    select c.id
      from clientes c
     where ventas_norm_correo(c.correo_norm) = v_correo_norm
        or ventas_norm_correo(c.correo) = v_correo_norm
     order by c.id
  loop
    v_coincidencias := v_coincidencias + 1;
    if v_coincidencias = 1 then
      v_customer_id := v_customer_iter;
    end if;
  end loop;

  if v_coincidencias = 1 then
    select cc.auth_user_id
      into v_vinculado_a
      from cuentas_cliente cc
     where cc.customer_id = v_customer_id
     for update;

    if found and v_vinculado_a <> v_uid then
      v_motivo := 'cliente_ya_vinculado';
    else
      -- El advisory lock por correo serializa dos cuentas que compiten por el
      -- mismo cliente. UNIQUE en cuentas_cliente.customer_id sigue siendo el
      -- piso duro frente a una escritura ajena que no respete ese protocolo.
      begin
        insert into cuentas_cliente (auth_user_id, customer_id, vinculado_en)
        values (v_uid, v_customer_id, now());
      exception when unique_violation then
        v_motivo := 'carrera_vinculo';
        insert into cuentas_cliente (auth_user_id)
        values (v_uid)
        on conflict (auth_user_id) do nothing;
      end;

      if v_motivo is null then
        return jsonb_build_object('ok', true, 'estado', 'lista');
      end if;
    end if;
  elsif v_coincidencias > 1 then
    v_customer_id := null;
    v_motivo := 'correo_ambiguo';
  end if;

  -- Cero coincidencias, ambiguedad o cliente ya reclamado: cuenta valida sin
  -- customer_id. Registrarse nunca crea ni fusiona una identidad comercial.
  insert into cuentas_cliente (auth_user_id)
  values (v_uid)
  on conflict (auth_user_id) do nothing;

  if v_motivo is not null then
    insert into cc_conflictos_revision (
      auth_user_id, motivo, coincidencias, customer_id_candidato,
      estado, detectado_en, actualizado, resuelto_en, notas_revision
    ) values (
      v_uid, v_motivo, v_coincidencias,
      case when v_motivo in ('cliente_ya_vinculado', 'carrera_vinculo') then v_customer_id else null end,
      'pendiente', now(), now(), null, null
    )
    on conflict (auth_user_id) do update set
      motivo = excluded.motivo,
      coincidencias = excluded.coincidencias,
      customer_id_candidato = excluded.customer_id_candidato,
      estado = 'pendiente',
      actualizado = now(),
      resuelto_en = null,
      notas_revision = null;
  end if;

  -- Contrato deliberadamente opaco: no devuelve UID, correo, customer_id,
  -- numero de coincidencias ni si habia historia comercial.
  return jsonb_build_object('ok', true, 'estado', 'lista');
end;
$$;

comment on function cc_inicializar_cuenta() is
  'C2 · crea idempotentemente la cuenta de auth.uid() solo con email confirmado. Vincula historia solo ante una coincidencia unica; nunca recibe ni devuelve identidad o PII.';

revoke execute on function cc_inicializar_cuenta() from public, anon;
grant execute on function cc_inicializar_cuenta() to authenticated, service_role;

commit;
