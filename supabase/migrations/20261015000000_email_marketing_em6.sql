-- ============================================================
-- MAGANDHI · Email marketing · TRAMO EM6 (captura publica + doble confirmacion)
-- ------------------------------------------------------------
-- Diseno en docs/PLANO-EMAIL-MARKETING.md §6 y §10.6.
--
-- FLUJO:
--   tienda (formulario) --> Edge Function em-suscripcion (publica, sin sesion)
--     --> em_publico_suscribir  (solo service_role): valida, limita intentos,
--         guarda la SOLICITUD (no un contacto) con el hash del token, 48 h.
--     --> correo "Confirma tu suscripcion" con el enlace #t=<token>
--   persona abre el enlace --> em-suscripcion modo confirmar
--     --> em_publico_confirmar (solo service_role): crea/reactiva el contacto
--         'suscrito' con su PRUEBA (texto aceptado, version de la politica,
--         fecha de solicitud y de confirmacion, ip_hash diario).
--
-- REGLAS (linea roja del dueno):
--   * Un correo escrito por un tercero NO se vuelve contacto: solo existe en
--     em_confirmaciones hasta 48 h (luego se purga) y solo se vuelve contacto
--     si su dueno confirma desde su bandeja.
--   * Las respuestas al publico NUNCA revelan si un correo ya existe.
--   * Interruptor em_config.captura_publica_activa (solo admin y solo con la
--     politica registrada). Apagado: la tienda no muestra el formulario y el
--     servidor rechaza todo.
--   * Rebotados y quejas no reciben ni el correo de confirmacion (reputacion).
--   * IP: nunca se guarda; solo un hash con sal diaria, para limitar abuso.
--   * POLITICA BORRADOR: quien se suscribe bajo una version 'borrador-*' NUNCA
--     recibe una campana real: em__audiencia lo excluye en cuanto la version
--     vigente deja de ser borrador.
--
-- Forward e idempotente. REQUISITO: despues de 20261014000000.
-- ============================================================

-- ------------------------------------------------------------
-- Tablas (sin acceso de anon ni de authenticated: solo service_role via RPC;
-- el panel ve agregados por RPC)
-- ------------------------------------------------------------
create table if not exists em_confirmaciones (
  id                   uuid primary key default gen_random_uuid(),
  correo               text not null,
  correo_norm          text not null,
  nombre               text,
  temas                text[] not null,
  token_hash           text not null,
  consentimiento_texto text not null,
  politica_version     text not null,
  ip_hash              text,
  creado               timestamptz not null default now(),
  vence                timestamptz not null default now() + interval '48 hours',
  usado_en             timestamptz,
  contacto_id          uuid references em_contactos(id)
);

create unique index if not exists em_confirmaciones_token_uidx on em_confirmaciones (token_hash);
create index if not exists idx_em_conf_correo on em_confirmaciones (correo_norm, creado);
create index if not exists idx_em_conf_creado on em_confirmaciones (creado);

comment on table em_confirmaciones is 'EM6: solicitudes de suscripcion desde la tienda pendientes de doble confirmacion. NO son contactos: un correo escrito por un tercero nunca entra a la lista. Token guardado solo como hash (sha256). Vencen a las 48 h y se purgan a los 7 dias (correo incluido). Solo service_role.';

create table if not exists em_suscripcion_intentos (
  ip_hash text not null,
  dia     date not null default current_date,
  n       integer not null default 0,
  primary key (ip_hash, dia)
);

comment on table em_suscripcion_intentos is 'EM6: limite de intentos por IP (hash con sal diaria, nunca la IP). Se purga a los 2 dias.';

alter table em_confirmaciones enable row level security;
alter table em_suscripcion_intentos enable row level security;
-- Sin policies: nadie con sesion ni anon las lee. Escriben solo los RPC.

-- ------------------------------------------------------------
-- Politica borrador: excluida de campanas reales.
-- ------------------------------------------------------------
create or replace function em__version_es_borrador(p text)
returns boolean language sql immutable set search_path = public as $$
  select coalesce(lower(btrim(p)) like 'borrador%', false);
$$;
revoke execute on function em__version_es_borrador(text) from public, anon, authenticated;

create or replace function em__audiencia(p_segmento_id uuid, p_tema text)
returns setof uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  s em_segmentos%rowtype;
  v_borr_vigente boolean := em__version_es_borrador((select politica_version from em_config where id));
begin
  select * into s from em_segmentos where id = p_segmento_id;
  if not found or s.archivado then return; end if;
  if s.tipo = 'reglas' then
    return query
      select c.id from em_contactos c
       where c.id in (select * from em__segmento_contactos(s.definicion))
         and c.estado = 'suscrito' and p_tema = any(c.temas)
         and (v_borr_vigente or not em__version_es_borrador(c.politica_version));
  else
    return query
      select distinct c.id from em_segmento_miembros m
        join em_contactos c on c.customer_id = m.customer_id
       where m.segmento_id = s.id and c.estado = 'suscrito' and p_tema = any(c.temas)
         and (v_borr_vigente or not em__version_es_borrador(c.politica_version));
  end if;
end;
$$;

revoke execute on function em__audiencia(uuid, text) from public, anon, authenticated;

-- Misma respuesta de EM4 + cuantos quedaron fuera por politica borrador.
create or replace function em_campana_audiencia(p_segmento_id uuid, p_tema text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_borr_vigente boolean := em__version_es_borrador((select politica_version from em_config where id));
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  return (
    with a as (select c.* from em_contactos c where c.id in (select * from em__audiencia(p_segmento_id, p_tema)))
    select jsonb_build_object(
      'n', (select count(*) from a),
      'sin_nombre', (select count(*) from a where nullif(btrim(coalesce(nombre, '')), '') is null),
      'politica_pendiente', (select count(*) from a where politica_version = 'pendiente'),
      'clientes', (select count(*) from a where customer_id is not null),
      'muestra', (select coalesce(jsonb_agg(jsonb_build_object('nombre', nombre, 'correo', correo) order by creado desc), '[]')
                    from (select * from a order by creado desc limit 6) m),
      'politica_publicada', (select politica_publicada from em_config where id),
      'excluidos_borrador', case when v_borr_vigente or p_segmento_id is null or p_tema is null then 0 else (
          select count(*) from em_contactos c
           where c.estado = 'suscrito' and p_tema = any(c.temas) and em__version_es_borrador(c.politica_version)
             and c.id in (select * from em__segmento_contactos((select definicion from em_segmentos where id = p_segmento_id and tipo = 'reglas')))
        ) end
    ));
end;
$$;

-- ------------------------------------------------------------
-- Interruptor de captura publica (solo admin, solo con politica registrada)
-- ------------------------------------------------------------
create or replace function em_config_captura(p_activa boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (tiene_acceso_email_marketing() and em__es_admin()) then raise exception 'EM_SIN_ACCESO'; end if;
  if coalesce(p_activa, false) and not (select politica_publicada from em_config where id) then
    raise exception 'EM_POLITICA_PENDIENTE';
  end if;
  update em_config set captura_publica_activa = coalesce(p_activa, false), actualizado = now(), actualizado_por = auth.uid() where id;
  return jsonb_build_object('captura_publica_activa', coalesce(p_activa, false));
end;
$$;

-- Estado de la captura para el Resumen.
create or replace function em_captura_estado()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  return (select jsonb_build_object(
    'activa', c.captura_publica_activa,
    'politica_publicada', c.politica_publicada,
    'politica_version', c.politica_version,
    'politica_borrador', em__version_es_borrador(c.politica_version),
    'pendientes', (select count(*) from em_confirmaciones where usado_en is null and vence > now()),
    'confirmadas_30d', (select count(*) from em_confirmaciones where usado_en >= now() - interval '30 days'),
    'solicitudes_30d', (select count(*) from em_confirmaciones where creado >= now() - interval '30 days'),
    'contactos_borrador', (select count(*) from em_contactos where em__version_es_borrador(politica_version))
  ) from em_config c where c.id);
end;
$$;

-- ------------------------------------------------------------
-- Publico (solo service_role, via la Edge Function em-suscripcion)
-- ------------------------------------------------------------
create or replace function em_publico_config()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'activa', c.captura_publica_activa and c.politica_publicada,
    'texto_consentimiento', c.texto_consentimiento,
    'politica_url', c.politica_url,
    'politica_version', c.politica_version,
    'temas', (select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre, 'descripcion', descripcion) order by orden), '[]') from em_temas where activo)
  ) from em_config c where c.id;
$$;

create or replace function em__purgar_captura()
returns void language sql security definer set search_path = public as $$
  delete from em_confirmaciones where creado < now() - interval '7 days';
  delete from em_suscripcion_intentos where dia < current_date - 2;
$$;
revoke execute on function em__purgar_captura() from public, anon, authenticated;

-- Devuelve {estado, enviar, confirmacion_id, correo, nombre}. El token lo
-- genera la funcion; aqui solo llega su hash.
create or replace function em_publico_suscribir(
  p_correo text, p_nombre text, p_temas text[], p_acepto boolean, p_token_hash text, p_ip_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cfg   em_config%rowtype;
  v_norm  text := ventas_norm_correo(p_correo);
  v_temas text[];
  v_c     em_contactos%rowtype;
  v_n     int;
  v_id    uuid;
  v_nom   text := nullif(left(regexp_replace(btrim(coalesce(p_nombre, '')), '[<>{}|"]', '', 'g'), 60), '');
begin
  select * into v_cfg from em_config where id;
  if not (v_cfg.captura_publica_activa and v_cfg.politica_publicada) then raise exception 'EM_CAPTURA_APAGADA'; end if;
  if v_norm is null or v_norm !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_norm) > 254 then raise exception 'EM_CORREO_INVALIDO'; end if;
  if not coalesce(p_acepto, false) then raise exception 'EM_CONFIRMACION_REQUERIDA'; end if;
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then raise exception 'EM_TOKEN_INVALIDO'; end if;

  select coalesce(array_agg(t order by t), '{}') into v_temas
    from (select distinct unnest(coalesce(p_temas, '{}')) t) x where t in (select codigo from em_temas where activo);
  if cardinality(v_temas) = 0 then raise exception 'EM_TEMAS_REQUERIDOS'; end if;

  perform em__purgar_captura();

  -- Limite por IP (hash diario): 10 solicitudes al dia.
  if p_ip_hash is not null then
    insert into em_suscripcion_intentos (ip_hash, dia, n) values (left(p_ip_hash, 64), current_date, 1)
    on conflict (ip_hash, dia) do update set n = em_suscripcion_intentos.n + 1
    returning n into v_n;
    if v_n > 10 then raise exception 'EM_DEMASIADOS_INTENTOS'; end if;
  end if;

  -- A partir de aqui la respuesta publica es SIEMPRE la misma ("revisa tu
  -- correo"); 'enviar' le dice a la funcion si de verdad manda el correo.
  select * into v_c from em_contactos where correo_norm = v_norm;
  if found and v_c.estado = 'suscrito' then
    return jsonb_build_object('estado', 'ok', 'enviar', false, 'motivo', 'ya_suscrito');
  end if;
  if found and v_c.estado in ('rebotado', 'queja') then
    return jsonb_build_object('estado', 'ok', 'enviar', false, 'motivo', 'suprimido');
  end if;
  -- Maximo 3 correos de confirmacion por direccion al dia (anti "bombardeo").
  if (select count(*) from em_confirmaciones where correo_norm = v_norm and creado >= now() - interval '24 hours') >= 3 then
    return jsonb_build_object('estado', 'ok', 'enviar', false, 'motivo', 'limite_correo');
  end if;

  insert into em_confirmaciones (correo, correo_norm, nombre, temas, token_hash, consentimiento_texto, politica_version, ip_hash)
  values (btrim(p_correo), v_norm, v_nom, v_temas, p_token_hash, v_cfg.texto_consentimiento, v_cfg.politica_version, left(p_ip_hash, 64))
  returning id into v_id;

  return jsonb_build_object('estado', 'ok', 'enviar', true, 'confirmacion_id', v_id, 'correo', btrim(p_correo), 'nombre', v_nom);
end;
$$;

comment on function em_publico_suscribir(text, text, text[], boolean, text, text) is 'EM6: registra una SOLICITUD de suscripcion (no un contacto) desde la tienda. Exige captura activa + politica registrada, aceptacion explicita y al menos un tema. Limita 10 por IP-hash al dia y 3 correos por direccion al dia. Nunca revela si el correo existe. Solo service_role.';

create or replace function em_publico_confirmar(p_token_hash text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_s   em_confirmaciones%rowtype;
  v_c   em_contactos%rowtype;
  v_cli uuid;
  v_id  uuid;
  v_evid jsonb;
begin
  if p_token_hash is null or p_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('estado', 'invalido');
  end if;
  select * into v_s from em_confirmaciones where token_hash = p_token_hash for update;
  if not found then return jsonb_build_object('estado', 'invalido'); end if;
  if v_s.usado_en is not null then return jsonb_build_object('estado', 'ya_confirmado'); end if;
  if v_s.vence < now() then return jsonb_build_object('estado', 'vencido'); end if;

  v_evid := jsonb_build_object('canal', 'formulario_tienda', 'detalle', 'Doble confirmación: la persona pidió suscribirse en magandhi.com y confirmó desde su correo.',
                               'solicitado_en', v_s.creado, 'confirmado_en', now(), 'ip_hash', v_s.ip_hash, 'confirmacion_id', v_s.id);

  select * into v_c from em_contactos where correo_norm = v_s.correo_norm for update;
  if found then
    if v_c.estado in ('rebotado', 'queja') then
      update em_confirmaciones set usado_en = now() where id = v_s.id;
      return jsonb_build_object('estado', 'no_disponible');
    end if;
    if v_c.estado = 'suscrito' then
      update em_confirmaciones set usado_en = now(), contacto_id = v_c.id where id = v_s.id;
      return jsonb_build_object('estado', 'ya_confirmado');
    end if;
    -- baja (o pendiente): la persona vuelve a autorizar con nueva prueba.
    update em_contactos
       set estado = 'suscrito', nombre = coalesce(v_s.nombre, nombre), temas = v_s.temas, fuente = 'formulario_tienda',
           consentimiento_en = v_s.creado, consentimiento_texto = v_s.consentimiento_texto, politica_version = v_s.politica_version,
           confirmado_en = now(), evidencia = v_evid, baja_en = null, baja_motivo = null, actualizado = now()
     where id = v_c.id;
    insert into em_consentimiento_bitacora (contacto_id, accion, estado_anterior, estado_nuevo, detalle, actor)
    values (v_c.id, 'reactivacion', v_c.estado, 'suscrito', jsonb_build_object('fuente', 'formulario_tienda', 'evidencia', v_evid,
            'temas', v_s.temas, 'politica_version', v_s.politica_version), null);
    v_id := v_c.id;
  else
    select id into v_cli from clientes where correo_norm = v_s.correo_norm limit 1;
    insert into em_contactos (correo, correo_norm, customer_id, nombre, estado, fuente, temas, consentimiento_en,
                              consentimiento_texto, politica_version, confirmado_en, evidencia, creado_por)
    values (v_s.correo, v_s.correo_norm, v_cli, v_s.nombre, 'suscrito', 'formulario_tienda', v_s.temas, v_s.creado,
            v_s.consentimiento_texto, v_s.politica_version, now(), v_evid, null)
    returning id into v_id;
    insert into em_consentimiento_bitacora (contacto_id, accion, estado_anterior, estado_nuevo, detalle, actor)
    values (v_id, 'alta', null, 'suscrito', jsonb_build_object('fuente', 'formulario_tienda', 'evidencia', v_evid,
            'temas', v_s.temas, 'politica_version', v_s.politica_version, 'customer_id', v_cli), null);
  end if;
  insert into em_consentimiento_bitacora (contacto_id, accion, estado_anterior, estado_nuevo, detalle, actor)
  values (v_id, 'confirmacion', 'suscrito', 'suscrito', jsonb_build_object('confirmacion_id', v_s.id), null);

  update em_confirmaciones set usado_en = now(), contacto_id = v_id where id = v_s.id;
  return jsonb_build_object('estado', 'confirmado');
end;
$$;

comment on function em_publico_confirmar(text) is 'EM6: confirma una solicitud por el hash de su token (48 h, un solo uso). Crea o reactiva el contacto suscrito con la prueba completa (texto aceptado, version, solicitud y confirmacion, ip_hash). Rebotados/quejas no se reactivan. Solo service_role.';

-- ------------------------------------------------------------
-- Grants
-- ------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array['em_publico_config()', 'em_publico_suscribir(text, text, text[], boolean, text, text)', 'em_publico_confirmar(text)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
  foreach f in array array['em_config_captura(boolean)', 'em_captura_estado()', 'em_campana_audiencia(uuid, text)'] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end $$;
