-- ============================================================================
-- MAGANDHI · PROMOCIONAR P4 · ATRIBUCIÓN TRANSACCIONAL
-- ----------------------------------------------------------------------------
-- Forward sobre P3 + Comercial C5. Agrega una FK nullable a intención/pedido,
-- conserva firmas históricas y nace con el gate P4 apagado.
-- ============================================================================

begin;
set local search_path = public, extensions, pg_temp;
set local statement_timeout = '90s';
set local lock_timeout = '5s';

lock table pagos_intencion, pedidos, atribucion_enlaces in share row exclusive mode;
select pg_advisory_xact_lock(hashtextextended('promocionar-p4-instalacion-v1', 0));

do $baseline$
begin
  if to_regclass('public.atribucion_enlaces') is null
     or to_regclass('public.pagos_intencion') is null
     or to_regclass('public.pedidos') is null
     or to_regprocedure('public.promocionar_p3_resolver(text)') is null
     or to_regprocedure('public.pw_registrar_intencion(text,uuid,text,text,integer,bigint,bigint,text,jsonb,text,text,text)') is null
     or to_regprocedure('public.pw_registrar_intencion_carrito(text,uuid,uuid,bigint,text,jsonb,text,text,text)') is null
     or to_regprocedure('public.pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text)') is null then
    raise exception using errcode = 'P0001', message = 'P4_REQUIERE_BASELINE_P3_C5_COMPLETO';
  end if;

  if to_regclass('public.promocionar_p4_config') is not null
     or exists (
       select 1 from information_schema.columns
        where table_schema = 'public' and table_name in ('pagos_intencion','pedidos')
          and column_name = 'atribucion_enlace_id'
     ) then
    raise exception using errcode = 'P0001', message = 'P4_REQUIERE_AUSENCIA_LIMPIA';
  end if;

  if exists (
    select pedido_id from pagos_intencion
     where pedido_id is not null group by pedido_id having count(*) > 1
  ) then
    raise exception using errcode = 'P0001', message = 'P4_PEDIDO_LIGADO_A_VARIAS_INTENCIONES';
  end if;
end;
$baseline$;

-- Gate P4 independiente de P3 y de pagos.
create table promocionar_p4_config (
  id                              smallint primary key default 1,
  atribucion_habilitada           boolean not null default false,
  validacion_publica_verificada   boolean not null default false,
  checkout_verificado             boolean not null default false,
  politica_publicada              boolean not null default false,
  politica_version                text,
  actualizado_en                  timestamptz not null default statement_timestamp(),
  actualizado_por                 uuid references auth.users(id) on delete restrict,
  actualizado_razon               text not null,
  actualizado_rol                 text not null,
  constraint promocionar_p4_config_singleton check (id = 1),
  constraint promocionar_p4_config_gates check (
    not atribucion_habilitada
    or (validacion_publica_verificada and checkout_verificado)
  ),
  constraint promocionar_p4_config_politica check (
    (not politica_publicada and politica_version is null)
    or (politica_publicada and politica_version = btrim(politica_version)
        and length(politica_version) between 1 and 120)
  ),
  constraint promocionar_p4_config_razon check (
    actualizado_razon = btrim(actualizado_razon)
    and length(actualizado_razon) between 1 and 500
  ),
  constraint promocionar_p4_config_rol check (
    actualizado_rol = btrim(actualizado_rol)
    and length(actualizado_rol) between 1 and 120
  )
);

create table promocionar_p4_config_bitacora (
  id                                    bigint generated always as identity primary key,
  registrado_en                         timestamptz not null default statement_timestamp(),
  actor_uid                             uuid,
  actor_rol                             text not null,
  razon                                 text not null,
  antes_atribucion_habilitada           boolean,
  despues_atribucion_habilitada         boolean not null,
  antes_validacion_publica_verificada   boolean,
  despues_validacion_publica_verificada boolean not null,
  antes_checkout_verificado             boolean,
  despues_checkout_verificado           boolean not null,
  antes_politica_publicada              boolean,
  despues_politica_publicada            boolean not null,
  antes_politica_version                text,
  despues_politica_version              text
);

create table promocionar_p4_incidencias (
  id             bigint generated always as identity primary key,
  registrado_en  timestamptz not null default statement_timestamp(),
  tipo           text not null,
  pedido_id      uuid,
  referencia     text,
  detalle        text not null,
  resuelta_en    timestamptz,
  resultado      text,
  constraint promocionar_p4_incidencias_tipo check (
    tipo in ('copia_pedido')
  ),
  constraint promocionar_p4_incidencias_detalle check (
    detalle = btrim(detalle) and length(detalle) between 1 and 240
  ),
  constraint promocionar_p4_incidencias_resolucion check (
    (resuelta_en is null and resultado is null)
    or (resuelta_en is not null and resultado in ('autocurada','reparada'))
  )
);

insert into promocionar_p4_config (
  id, atribucion_habilitada, validacion_publica_verificada,
  checkout_verificado, politica_publicada, politica_version,
  actualizado_por, actualizado_razon, actualizado_rol
) values (
  1, false, false, false, false, null,
  auth.uid(), 'instalacion_inicial', current_user
);

insert into promocionar_p4_config_bitacora (
  actor_uid, actor_rol, razon,
  antes_atribucion_habilitada, despues_atribucion_habilitada,
  antes_validacion_publica_verificada, despues_validacion_publica_verificada,
  antes_checkout_verificado, despues_checkout_verificado,
  antes_politica_publicada, despues_politica_publicada,
  antes_politica_version, despues_politica_version
)
select auth.uid(), current_user, 'instalacion_inicial',
       null, atribucion_habilitada, null, validacion_publica_verificada,
       null, checkout_verificado, null, politica_publicada,
       null, politica_version
  from promocionar_p4_config where id = 1;

comment on table promocionar_p4_config is
  'Promocionar P4 · gate privado de atribución transaccional. Nace OFF y no altera P3 ni pagos.';
comment on column promocionar_p4_config.politica_publicada is
  'Referencia informativa hasta cerrar expresamente si política publicada será gate P4.';
comment on table promocionar_p4_config_bitacora is
  'Promocionar P4 · historial privado de cambios del gate, sin códigos ni datos de clientes.';
comment on table promocionar_p4_incidencias is
  'Promocionar P4 · fallos técnicos de copia que no deben revertir un pago aprobado; sin comprador, código ni UTM.';

alter table promocionar_p4_config enable row level security;
alter table promocionar_p4_config_bitacora enable row level security;
alter table promocionar_p4_incidencias enable row level security;
revoke all on table promocionar_p4_config from public, anon, authenticated, service_role;
revoke all on table promocionar_p4_config_bitacora from public, anon, authenticated, service_role;
revoke all on table promocionar_p4_incidencias from public, anon, authenticated, service_role;
revoke all on sequence promocionar_p4_config_bitacora_id_seq from public, anon, authenticated, service_role;
revoke all on sequence promocionar_p4_incidencias_id_seq from public, anon, authenticated, service_role;

create function promocionar_p4__auditar_config()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
begin
  if new.id <> 1 or old.id <> 1 then
    raise exception using errcode = 'P0001', message = 'P4_CONFIG_SINGLETON';
  end if;
  if new.actualizado_razon is not distinct from old.actualizado_razon then
    raise exception using errcode = 'P0001', message = 'P4_CONFIG_REQUIERE_RAZON_NUEVA';
  end if;
  new.actualizado_en := statement_timestamp();
  new.actualizado_por := auth.uid();
  new.actualizado_rol := current_user;
  insert into promocionar_p4_config_bitacora (
    actor_uid, actor_rol, razon,
    antes_atribucion_habilitada, despues_atribucion_habilitada,
    antes_validacion_publica_verificada, despues_validacion_publica_verificada,
    antes_checkout_verificado, despues_checkout_verificado,
    antes_politica_publicada, despues_politica_publicada,
    antes_politica_version, despues_politica_version
  ) values (
    auth.uid(), current_user, new.actualizado_razon,
    old.atribucion_habilitada, new.atribucion_habilitada,
    old.validacion_publica_verificada, new.validacion_publica_verificada,
    old.checkout_verificado, new.checkout_verificado,
    old.politica_publicada, new.politica_publicada,
    old.politica_version, new.politica_version
  );
  return new;
end;
$fn$;
revoke all on function promocionar_p4__auditar_config()
  from public, anon, authenticated, service_role;
create trigger trg_promocionar_p4_config_auditoria
  before update on promocionar_p4_config
  for each row execute function promocionar_p4__auditar_config();

-- La atribución vive en cabecera. No hay FK por línea ni backfill desde UTM.
alter table pagos_intencion
  add column atribucion_enlace_id uuid
    references atribucion_enlaces(id) on delete restrict;
alter table pedidos
  add column atribucion_enlace_id uuid
    references atribucion_enlaces(id) on delete restrict;

create index pagos_intencion_atribucion_enlace_idx
  on pagos_intencion (atribucion_enlace_id)
  where atribucion_enlace_id is not null;
create index pedidos_atribucion_enlace_idx
  on pedidos (atribucion_enlace_id)
  where atribucion_enlace_id is not null;
create unique index pagos_intencion_pedido_unico_idx
  on pagos_intencion (pedido_id) where pedido_id is not null;

comment on column pagos_intencion.atribucion_enlace_id is
  'P4 · enlace propio validado y congelado al nacer la intención; NULL es compra normal sin exacta propia.';
comment on column pedidos.atribucion_enlace_id is
  'P4 · copia idempotente de la FK congelada en la intención aprobada; atribuye el pedido completo.';

-- Código -> FK bajo gate y candado. Nunca acepta una FK del navegador.
create function promocionar_p4__resolver_codigo(p_codigo text)
returns uuid
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $fn$
declare v_enlace_id uuid;
begin
  if p_codigo is null or p_codigo !~ '^[0-9a-hjkmnp-tv-z]{16}$' then
    return null;
  end if;
  select e.id into v_enlace_id
    from promocionar_p4_config c
    join atribucion_enlaces e
      on e.codigo = p_codigo and e.estado_enlace = 'activo'
   where c.id = 1 and c.atribucion_habilitada
   for share of c, e;
  return v_enlace_id;
end;
$fn$;
revoke all on function promocionar_p4__resolver_codigo(text)
  from public, anon, authenticated, service_role;

create function promocionar_p4_validar_codigo(p_codigo text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $fn$
  select p_codigo is not null
     and p_codigo ~ '^[0-9a-hjkmnp-tv-z]{16}$'
     and exists (
       select 1 from atribucion_enlaces e
        where e.codigo = p_codigo and e.estado_enlace = 'activo'
     );
$fn$;
comment on function promocionar_p4_validar_codigo(text) is
  'P4 · validación pública mediada por Edge: confirma solo código activo, sin UUID, campaña, UTM ni datos internos.';
revoke all on function promocionar_p4_validar_codigo(text)
  from public, anon, authenticated, service_role;
grant execute on function promocionar_p4_validar_codigo(text) to service_role;

-- Evolución compatible de la RPC P3: conserva enlace_id/destino_url y agrega
-- solo el booleano captura_p4. Edge antigua ignora la clave; Edge P4 evita una
-- segunda consulta y no añade latencia al 302.
create or replace function promocionar_p3_resolver(p_codigo text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_enlace atribucion_enlaces%rowtype;
  v_slug text;
  v_destino text;
  v_captura_p4 boolean := false;
begin
  if p_codigo is null or p_codigo !~ '^[0-9a-hjkmnp-tv-z]{16}$' then
    return null;
  end if;
  if not exists (
    select 1 from promocionar_p3_config c
     where c.id = 1 and c.redirect_habilitado and c.routing_verificado
  ) then
    return null;
  end if;

  select * into v_enlace from atribucion_enlaces e
   where e.codigo = p_codigo and e.estado_enlace = 'activo';
  if not found then return null; end if;

  if v_enlace.tipo_destino = 'home_v1' then
    v_destino := 'https://magandhi.com/';
  elsif v_enlace.tipo_destino = 'producto_v1' then
    select cp.slug into v_slug from campana_producto cp
     where cp.id = v_enlace.campana_producto_id
       and cp.activo and cp.publicado and not cp.es_placeholder
       and cp.slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
       and length(cp.slug) between 1 and 180;
    if v_slug is null then return null; end if;
    v_destino := 'https://magandhi.com/producto/' || v_slug || '/';
  else
    return null;
  end if;

  v_destino := v_destino
    || '?utm_source=' || v_enlace.source
    || '&utm_medium=' || v_enlace.medium
    || '&utm_campaign=' || v_enlace.campaign;
  if v_enlace.content is not null then
    v_destino := v_destino || '&utm_content=' || v_enlace.content;
  end if;

  select c.atribucion_habilitada into v_captura_p4
    from promocionar_p4_config c where c.id = 1;
  return jsonb_build_object(
    'enlace_id', v_enlace.id,
    'destino_url', v_destino,
    'captura_p4', coalesce(v_captura_p4, false)
  );
end;
$fn$;
comment on function promocionar_p3_resolver(text) is
  'P3 + P4 · conserva resolución cerrada MAGANDHI y añade captura_p4 booleana dentro de la misma lectura, sin segunda RPC en el redirect.';
revoke all on function promocionar_p3_resolver(text)
  from public, anon, authenticated, service_role;
grant execute on function promocionar_p3_resolver(text) to service_role;

-- El INSERT ignora cualquier FK directa y solo admite el contexto abierto por
-- las puertas P4. También vuelve a comprobar gate + enlace activo.
create function pw__asignar_atribucion_p4()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_contexto text := coalesce(current_setting('impulse.atribucion_enlace_id', true), '');
  v_id uuid;
begin
  new.atribucion_enlace_id := null;
  if v_contexto = '' then return new; end if;
  begin
    v_id := v_contexto::uuid;
  exception when others then
    raise exception using errcode = 'XX000', message = 'P4_CONTEXTO_ATRIBUCION_INVALIDO';
  end;
  perform 1
    from promocionar_p4_config c
    join atribucion_enlaces e on e.id = v_id and e.estado_enlace = 'activo'
   where c.id = 1 and c.atribucion_habilitada
   for share of c, e;
  if not found then
    raise exception using errcode = 'XX000', message = 'P4_CONTEXTO_ATRIBUCION_NO_VIGENTE';
  end if;
  new.atribucion_enlace_id := v_id;
  return new;
end;
$fn$;
revoke all on function pw__asignar_atribucion_p4()
  from public, anon, authenticated, service_role;
create trigger trg_pw_p4_asignar_atribucion
  before insert on pagos_intencion
  for each row execute function pw__asignar_atribucion_p4();

create function pw__proteger_atribucion_intencion_p4()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $fn$
begin
  if new.atribucion_enlace_id is distinct from old.atribucion_enlace_id then
    raise exception using errcode = 'P0001', message = 'P4_ATRIBUCION_INTENCION_INMUTABLE';
  end if;
  return new;
end;
$fn$;
revoke all on function pw__proteger_atribucion_intencion_p4()
  from public, anon, authenticated, service_role;
create trigger trg_pw_p4_proteger_atribucion_intencion
  before update of atribucion_enlace_id on pagos_intencion
  for each row execute function pw__proteger_atribucion_intencion_p4();

create function pw__proteger_atribucion_pedido_p4()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $fn$
begin
  if new.atribucion_enlace_id is distinct from old.atribucion_enlace_id then
    if coalesce(current_setting('impulse.p4_copia_pedido', true), '') <> 'on'
       or old.atribucion_enlace_id is not null
       or new.atribucion_enlace_id is null then
      raise exception using errcode = 'P0001', message = 'P4_ATRIBUCION_PEDIDO_INMUTABLE';
    end if;
  end if;
  return new;
end;
$fn$;
revoke all on function pw__proteger_atribucion_pedido_p4()
  from public, anon, authenticated, service_role;
create trigger trg_pw_p4_proteger_atribucion_pedido
  before update of atribucion_enlace_id on pedidos
  for each row execute function pw__proteger_atribucion_pedido_p4();

-- Puerta nominal de compra inmediata. La resolución promocional falla abierta;
-- los errores comerciales/pagos de la RPC histórica siguen propagándose.
create function pw_registrar_intencion_p4(
  p_referencia text, p_campana_id uuid, p_slug text, p_nombre text,
  p_cantidad integer, p_precio_unitario bigint, p_monto_centavos bigint,
  p_entorno text, p_comprador jsonb default '{}'::jsonb,
  p_utm_campaign text default null, p_mg_vid text default null,
  p_moneda text default 'COP', p_atribucion_codigo text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_atribucion uuid;
  v_resultado jsonb;
begin
  begin
    v_atribucion := promocionar_p4__resolver_codigo(p_atribucion_codigo);
  exception when others then
    v_atribucion := null;
  end;
  perform set_config('impulse.atribucion_enlace_id', coalesce(v_atribucion::text, ''), true);
  begin
    v_resultado := pw_registrar_intencion(
      p_referencia, p_campana_id, p_slug, p_nombre, p_cantidad,
      p_precio_unitario, p_monto_centavos, p_entorno, p_comprador,
      p_utm_campaign, p_mg_vid, p_moneda
    );
  exception when others then
    perform set_config('impulse.atribucion_enlace_id', '', true);
    raise;
  end;
  perform set_config('impulse.atribucion_enlace_id', '', true);
  return v_resultado;
end;
$fn$;
revoke all on function pw_registrar_intencion_p4(text,uuid,text,text,integer,bigint,bigint,text,jsonb,text,text,text,text)
  from public, anon, authenticated, service_role;
grant execute on function pw_registrar_intencion_p4(text,uuid,text,text,integer,bigint,bigint,text,jsonb,text,text,text,text)
  to service_role;

create function pw_registrar_intencion_carrito_p4(
  p_referencia text, p_auth_user_id uuid, p_carrito_id uuid,
  p_version_esperada bigint, p_entorno text,
  p_comprador jsonb default '{}'::jsonb,
  p_utm_campaign text default null, p_mg_vid text default null,
  p_moneda text default 'COP', p_atribucion_codigo text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_atribucion uuid;
  v_resultado jsonb;
begin
  begin
    v_atribucion := promocionar_p4__resolver_codigo(p_atribucion_codigo);
  exception when others then
    v_atribucion := null;
  end;
  perform set_config('impulse.atribucion_enlace_id', coalesce(v_atribucion::text, ''), true);
  begin
    v_resultado := pw_registrar_intencion_carrito(
      p_referencia, p_auth_user_id, p_carrito_id, p_version_esperada,
      p_entorno, p_comprador, p_utm_campaign, p_mg_vid, p_moneda
    );
  exception when others then
    perform set_config('impulse.atribucion_enlace_id', '', true);
    raise;
  end;
  perform set_config('impulse.atribucion_enlace_id', '', true);
  return v_resultado;
end;
$fn$;
revoke all on function pw_registrar_intencion_carrito_p4(text,uuid,uuid,bigint,text,jsonb,text,text,text,text)
  from public, anon, authenticated, service_role;
grant execute on function pw_registrar_intencion_carrito_p4(text,uuid,uuid,bigint,text,jsonb,text,text,text,text)
  to service_role;

-- El webhook conserva firma. El wrapper copia por pedido durable, no por la
-- referencia entrante de un retry, y limpia la UTM del pedido exacto para que
-- las lecturas legacy no dupliquen la venta.
alter function pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text)
  rename to pw__procesar_pago_pre_p4;
revoke all on function pw__procesar_pago_pre_p4(text,text,text,bigint,text,text,text,jsonb,text,text)
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
as $fn$
declare
  v_resultado jsonb;
  v_pedido_id uuid;
  v_atribucion_intencion uuid;
  v_atribucion_pedido uuid;
  v_incidente text;
begin
  v_resultado := pw__procesar_pago_pre_p4(
    p_transaccion_id, p_estado_wompi, p_referencia, p_monto_centavos,
    p_moneda, p_evento, p_checksum, p_cuerpo, p_metodo_pago, p_correo_pagador
  );

  begin
    begin
      v_pedido_id := nullif(v_resultado->>'pedido_id', '')::uuid;
    exception when others then
      v_pedido_id := null;
    end;
    if v_pedido_id is null then return v_resultado; end if;

    select pi.atribucion_enlace_id into v_atribucion_intencion
      from pagos_intencion pi where pi.pedido_id = v_pedido_id for update;
    if not found then
      raise exception using errcode = 'XX000', message = 'P4_INTENCION_DEL_PEDIDO_AUSENTE';
    end if;
    select p.atribucion_enlace_id into v_atribucion_pedido
      from pedidos p where p.id = v_pedido_id for update;
    if not found then
      raise exception using errcode = 'XX000', message = 'P4_PEDIDO_DEVUELTO_AUSENTE';
    end if;

    if v_atribucion_pedido is distinct from v_atribucion_intencion then
      if v_atribucion_pedido is not null or v_atribucion_intencion is null then
        raise exception using errcode = 'XX000', message = 'P4_ATRIBUCION_PEDIDO_DIVERGENTE';
      end if;
      perform set_config('impulse.p4_copia_pedido', 'on', true);
      update pedidos
         set atribucion_enlace_id = v_atribucion_intencion,
             utm_campaign = null,
             actualizado = statement_timestamp()
       where id = v_pedido_id;
      perform set_config('impulse.p4_copia_pedido', 'off', true);
    elsif v_atribucion_intencion is not null then
      update pedidos set utm_campaign = null
       where id = v_pedido_id and utm_campaign is not null;
    end if;

    update promocionar_p4_incidencias
       set resuelta_en = statement_timestamp(), resultado = 'autocurada'
     where pedido_id = v_pedido_id and resuelta_en is null;
  exception when others then
    -- Atribución nunca revierte el pedido, inventario, asiento ni evento de un
    -- pago ya aceptado por el procesador histórico. La incidencia queda privada
    -- para diagnóstico/reparación y el webhook conserva respuesta exitosa.
    perform set_config('impulse.p4_copia_pedido', 'off', true);
    v_incidente := left(sqlstate || ':' || sqlerrm, 240);
    begin
      insert into promocionar_p4_incidencias (
        tipo, pedido_id, referencia, detalle
      ) values (
        'copia_pedido', v_pedido_id, nullif(p_referencia, ''), v_incidente
      );
    exception when others then
      raise warning 'P4_COPIA_PEDIDO_FALLO_SIN_BITACORA';
    end;
  end;

  return v_resultado;
end;
$fn$;
comment on function pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text) is
  'P4 · conserva la firma del webhook y copia idempotentemente la FK congelada de la intención al pedido completo.';
revoke all on function pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text)
  from public, anon, authenticated, service_role;
grant execute on function pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text)
  to service_role;

-- Reparación privada e idempotente para incidencias fail-open. Se ejecuta de
-- forma controlada desde SQL Editor; nunca está disponible a roles API.
create function promocionar_p4__reparar_incidencias()
returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_incidencia promocionar_p4_incidencias%rowtype;
  v_atribucion_intencion uuid;
  v_atribucion_pedido uuid;
  v_reparadas integer := 0;
  v_pendientes integer := 0;
begin
  for v_incidencia in
    select * from promocionar_p4_incidencias
     where resuelta_en is null
     order by id
     for update skip locked
  loop
    begin
      if exists (
        select 1 from promocionar_p4_incidencias x
         where x.id = v_incidencia.id and x.resuelta_en is not null
      ) then
        continue;
      end if;
      if v_incidencia.pedido_id is null then
        v_pendientes := v_pendientes + 1;
        continue;
      end if;
      select pi.atribucion_enlace_id into v_atribucion_intencion
        from pagos_intencion pi
       where pi.pedido_id = v_incidencia.pedido_id for update;
      if not found or v_atribucion_intencion is null then
        v_pendientes := v_pendientes + 1;
        continue;
      end if;
      select p.atribucion_enlace_id into v_atribucion_pedido
        from pedidos p where p.id = v_incidencia.pedido_id for update;
      if not found
         or (v_atribucion_pedido is not null
             and v_atribucion_pedido <> v_atribucion_intencion) then
        v_pendientes := v_pendientes + 1;
        continue;
      end if;

      if v_atribucion_pedido is null then
        perform set_config('impulse.p4_copia_pedido', 'on', true);
        update pedidos
           set atribucion_enlace_id = v_atribucion_intencion,
               utm_campaign = null,
               actualizado = statement_timestamp()
         where id = v_incidencia.pedido_id;
        perform set_config('impulse.p4_copia_pedido', 'off', true);
      elsif exists (
        select 1 from pedidos p
         where p.id = v_incidencia.pedido_id and p.utm_campaign is not null
      ) then
        update pedidos set utm_campaign = null
         where id = v_incidencia.pedido_id;
      end if;

      update promocionar_p4_incidencias
         set resuelta_en = statement_timestamp(), resultado = 'reparada'
       where pedido_id = v_incidencia.pedido_id and resuelta_en is null;
      v_reparadas := v_reparadas + 1;
    exception when others then
      perform set_config('impulse.p4_copia_pedido', 'off', true);
      v_pendientes := v_pendientes + 1;
      raise warning 'P4_REPARACION_INCIDENCIA_FALLO';
    end;
  end loop;

  select count(*)::integer into v_pendientes
    from promocionar_p4_incidencias where resuelta_en is null;
  return jsonb_build_object(
    'pedidos_reparados', v_reparadas,
    'incidencias_pendientes', v_pendientes
  );
end;
$fn$;
comment on function promocionar_p4__reparar_incidencias() is
  'P4 · reparación privada idempotente NULL→FK desde la intención; nunca sobrescribe una atribución distinta.';
revoke all on function promocionar_p4__reparar_incidencias()
  from public, anon, authenticated, service_role;

-- La aproximación histórica solo aplica cuando no existe exacta propia.
create or replace function em__atribucion_aproximada()
returns table (pedido_id uuid, campana_id uuid, clic_cuando timestamptz)
language sql
stable
security definer
set search_path = public
as $fn$
  with clics as (
    select e.campana_id, e.cuando, ct.customer_id
      from em_eventos e
      join em_contactos ct on ct.id = e.contacto_id
     where e.tipo = 'clic' and e.campana_id is not null and ct.customer_id is not null
  ), cand as (
    select p.id as pedido_id, c.campana_id, c.cuando,
           row_number() over (partition by p.id order by c.cuando desc) as rn
      from pedidos p
      join clics c on c.customer_id = p.customer_id
     where not p.anulado
       and p.atribucion_enlace_id is null
       and p.utm_campaign is null
       and coalesce(p.creado, p.fecha_orden::timestamptz) >= c.cuando
       and p.fecha_orden between (c.cuando at time zone 'America/Bogota')::date
                             and (c.cuando at time zone 'America/Bogota')::date + 7
  )
  select pedido_id, campana_id, cuando from cand where rn = 1;
$fn$;
revoke all on function em__atribucion_aproximada()
  from public, anon, authenticated;
grant execute on function em__atribucion_aproximada() to service_role;

create function promocionar_p4__clasificar_pedido(p_pedido_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_pedido pedidos%rowtype;
  v_email uuid;
  v_aprox uuid;
begin
  select * into v_pedido from pedidos where id = p_pedido_id;
  if not found then return null; end if;
  if v_pedido.atribucion_enlace_id is not null then
    return jsonb_build_object('tipo', 'exacta_propia', 'enlace_id', v_pedido.atribucion_enlace_id);
  end if;
  select c.id into v_email from em_campanas c
   where c.utm_campaign = v_pedido.utm_campaign limit 1;
  if v_email is not null then
    return jsonb_build_object('tipo', 'legacy_email_utm', 'campana_email_id', v_email);
  end if;
  select a.campana_id into v_aprox from em__atribucion_aproximada() a
   where a.pedido_id = p_pedido_id;
  if v_aprox is not null then
    return jsonb_build_object('tipo', 'aproximada_email', 'campana_email_id', v_aprox);
  end if;
  return jsonb_build_object('tipo', 'sin_atribuir');
end;
$fn$;
comment on function promocionar_p4__clasificar_pedido(uuid) is
  'P4 · precedencia exclusiva: exacta propia, legacy_email_utm, aproximada_email o sin_atribuir.';
revoke all on function promocionar_p4__clasificar_pedido(uuid)
  from public, anon, authenticated, service_role;

commit;
