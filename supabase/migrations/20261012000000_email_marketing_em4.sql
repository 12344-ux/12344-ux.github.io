-- ============================================================
-- MAGANDHI · Email marketing · TRAMO EM4 (campanas)
-- ------------------------------------------------------------
-- Diseno en docs/PLANO-EMAIL-MARKETING.md §3.3, §3.4 y §6.
--
-- FLUJO DE ENVIO (el boton final siempre lo pulsa una persona):
--   borrador --em_campana_confirmar--> preparando  (audiencia CONGELADA en
--            em_campana_destinatarios; exige politica publicada y que el
--            tamano coincida con el que vio el humano)
--   preparando --sincronizar contactos con Resend por tandas-->
--   preparando --em_campana_reservar_envio + Broadcast--> enviada | programada
--   borrador|preparando|programada --em_campana_cancelar--> cancelada
--
-- La Edge Function em-campana orquesta Resend (llave RESEND_MARKETING_API_KEY
-- solo en Secrets) llamando a estos RPC con el JWT del usuario: los permisos
-- se evaluan de verdad en la base. CERO acceso anon.
--
-- Audiencia = segmento ∩ estado 'suscrito' ∩ tema elegido en sus temas.
-- Forward e idempotente. REQUISITO: despues de 20261011000000.
-- ============================================================

-- ------------------------------------------------------------
-- Tablas
-- ------------------------------------------------------------
create table if not exists em_campanas (
  id                  uuid primary key default gen_random_uuid(),
  nombre_interno      text not null check (char_length(btrim(nombre_interno)) between 1 and 100),
  asunto              text not null default '' check (char_length(asunto) <= 150),
  preheader           text check (preheader is null or char_length(preheader) <= 200),
  contenido           jsonb not null default '[]'::jsonb,
  segmento_id         uuid references em_segmentos(id),
  tema                text references em_temas(codigo),
  estado              text not null default 'borrador'
                        check (estado in ('borrador','preparando','programada','enviada','cancelada','fallida')),
  audiencia_n         integer,
  programada_para     timestamptz,
  enviada_en          timestamptz,
  utm_campaign        text not null,
  resend_segment_id   text,
  resend_broadcast_id text,
  enviando_desde      timestamptz,
  error               text,
  confirmada_por      uuid references auth.users(id),
  confirmada_en       timestamptz,
  creado              timestamptz not null default now(),
  creado_por          uuid references auth.users(id) default auth.uid(),
  actualizado         timestamptz not null default now(),
  actualizado_por     uuid references auth.users(id) default auth.uid()
);

create index if not exists idx_em_campanas_estado on em_campanas (estado, actualizado desc);
create unique index if not exists em_campanas_utm_uidx on em_campanas (utm_campaign);

comment on table em_campanas is 'Campanas de email marketing. contenido = arreglo de bloques {tipo,...} validado por em__campana_validar. La audiencia se congela al confirmar (em_campana_destinatarios). confirmada_por = quien pulso enviar (siempre una persona).';

create table if not exists em_campana_destinatarios (
  campana_id        uuid not null references em_campanas(id),
  contacto_id       uuid not null references em_contactos(id),
  correo            text not null,
  nombre            text,
  customer_id       uuid references clientes(id),
  estado            text not null default 'pendiente' check (estado in ('pendiente','listo','excluido')),
  motivo            text,
  resend_contact_id text,
  procesado_en      timestamptz,
  primary key (campana_id, contacto_id)
);

create index if not exists idx_em_dest_pendientes on em_campana_destinatarios (campana_id) where estado = 'pendiente';

comment on table em_campana_destinatarios is 'Audiencia CONGELADA de una campana al confirmar el envio. Base de la atribucion de ventas (EM5). estado: pendiente (falta sincronizar con Resend), listo (en el segmento de Resend), excluido (p. ej. se dio de baja en Resend).';

create table if not exists em_campana_bitacora (
  id         uuid primary key default gen_random_uuid(),
  campana_id uuid not null references em_campanas(id),
  accion     text not null check (accion in ('crear','editar','duplicar','prueba','confirmar','enviar','programar','cancelar','fallo')),
  detalle    jsonb,
  actor      uuid references auth.users(id) default auth.uid(),
  cuando     timestamptz not null default now()
);

create index if not exists idx_em_camp_bit on em_campana_bitacora (campana_id, cuando);

alter table em_campanas enable row level security;
alter table em_campana_destinatarios enable row level security;
alter table em_campana_bitacora enable row level security;
drop policy if exists em_campanas_select on em_campanas;
create policy em_campanas_select on em_campanas for select to authenticated using (tiene_acceso_email_marketing());
drop policy if exists em_campana_dest_select on em_campana_destinatarios;
create policy em_campana_dest_select on em_campana_destinatarios for select to authenticated using (tiene_acceso_email_marketing());
drop policy if exists em_campana_bit_select on em_campana_bitacora;
create policy em_campana_bit_select on em_campana_bitacora for select to authenticated using (tiene_acceso_email_marketing());
grant select on table em_campanas, em_campana_destinatarios, em_campana_bitacora to authenticated;

-- ------------------------------------------------------------
-- Validacion de bloques (lista blanca)
-- ------------------------------------------------------------
create or replace function em__campana_validar(p jsonb)
returns void
language plpgsql
immutable
set search_path = public
as $$
declare
  b jsonb;
  v_tipo text;
  v_botones int := 0;
  v_url text;
begin
  if p is null or jsonb_typeof(p) <> 'array' then raise exception 'EM_CONTENIDO_INVALIDO: no es una lista'; end if;
  if jsonb_array_length(p) > 30 then raise exception 'EM_CONTENIDO_INVALIDO: maximo 30 bloques'; end if;
  for b in select * from jsonb_array_elements(p) loop
    if jsonb_typeof(b) <> 'object' then raise exception 'EM_CONTENIDO_INVALIDO: bloque'; end if;
    v_tipo := b->>'tipo';
    if v_tipo = 'titulo' then
      if char_length(coalesce(b->>'texto', '')) > 150 then raise exception 'EM_CONTENIDO_INVALIDO: titulo largo'; end if;
    elsif v_tipo = 'texto' then
      if char_length(coalesce(b->>'texto', '')) > 3000 then raise exception 'EM_CONTENIDO_INVALIDO: texto largo'; end if;
    elsif v_tipo = 'imagen' then
      v_url := coalesce(b->>'url', '');
      if v_url <> '' and (v_url !~ '^https://' or char_length(v_url) > 600) then raise exception 'EM_CONTENIDO_INVALIDO: imagen'; end if;
      if char_length(coalesce(b->>'alt', '')) > 150 then raise exception 'EM_CONTENIDO_INVALIDO: alt'; end if;
      if coalesce(b->>'enlace', '') <> '' and (b->>'enlace' !~ '^https://' or char_length(b->>'enlace') > 600) then raise exception 'EM_CONTENIDO_INVALIDO: enlace'; end if;
    elsif v_tipo = 'boton' then
      v_botones := v_botones + 1;
      if char_length(coalesce(b->>'texto', '')) > 40 then raise exception 'EM_CONTENIDO_INVALIDO: boton'; end if;
      if coalesce(b->>'url', '') <> '' and (b->>'url' !~ '^https://' or char_length(b->>'url') > 600) then raise exception 'EM_CONTENIDO_INVALIDO: enlace del boton'; end if;
    elsif v_tipo = 'producto' then
      if coalesce(b->>'slug', '') <> '' and b->>'slug' !~ '^[a-z0-9-]{1,120}$' then raise exception 'EM_CONTENIDO_INVALIDO: producto'; end if;
    elsif v_tipo = 'separador' then
      null;
    else
      raise exception 'EM_CONTENIDO_INVALIDO: tipo %', coalesce(v_tipo, '?');
    end if;
  end loop;
  if v_botones > 1 then raise exception 'EM_CONTENIDO_INVALIDO: un solo boton por correo'; end if;
end;
$$;

revoke execute on function em__campana_validar(jsonb) from public, anon, authenticated;

-- Contenido listo para ENVIAR (mas estricto que un borrador).
create or replace function em__campana_lista_para_enviar(c em_campanas)
returns void
language plpgsql
stable
set search_path = public
as $$
declare b jsonb; v_util int := 0;
begin
  if btrim(c.asunto) = '' then raise exception 'EM_CAMPANA_INCOMPLETA: asunto'; end if;
  if c.segmento_id is null then raise exception 'EM_CAMPANA_INCOMPLETA: segmento'; end if;
  if c.tema is null then raise exception 'EM_CAMPANA_INCOMPLETA: tema'; end if;
  perform em__campana_validar(c.contenido);
  for b in select * from jsonb_array_elements(c.contenido) loop
    if (b->>'tipo' in ('titulo','texto') and btrim(coalesce(b->>'texto','')) <> '')
       or (b->>'tipo' = 'imagen' and coalesce(b->>'url','') <> '')
       or (b->>'tipo' = 'producto' and coalesce(b->>'slug','') <> '') then v_util := v_util + 1; end if;
    if b->>'tipo' = 'boton' and (btrim(coalesce(b->>'texto','')) = '' or coalesce(b->>'url','') = '') then
      raise exception 'EM_CAMPANA_INCOMPLETA: boton sin texto o enlace';
    end if;
    if b->>'tipo' = 'imagen' and coalesce(b->>'url','') = '' then raise exception 'EM_CAMPANA_INCOMPLETA: imagen sin archivo'; end if;
    if b->>'tipo' = 'producto' and coalesce(b->>'slug','') = '' then raise exception 'EM_CAMPANA_INCOMPLETA: producto sin elegir'; end if;
  end loop;
  if v_util = 0 then raise exception 'EM_CAMPANA_INCOMPLETA: contenido'; end if;
end;
$$;

revoke execute on function em__campana_lista_para_enviar(em_campanas) from public, anon, authenticated;

-- Contactos de la audiencia actual (interno): segmento ∩ suscritos ∩ tema.
create or replace function em__audiencia(p_segmento_id uuid, p_tema text)
returns setof uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare s em_segmentos%rowtype;
begin
  select * into s from em_segmentos where id = p_segmento_id;
  if not found or s.archivado then return; end if;
  if s.tipo = 'reglas' then
    return query
      select c.id from em_contactos c
       where c.id in (select * from em__segmento_contactos(s.definicion))
         and c.estado = 'suscrito' and p_tema = any(c.temas);
  else
    return query
      select distinct c.id from em_segmento_miembros m
        join em_contactos c on c.customer_id = m.customer_id
       where m.segmento_id = s.id and c.estado = 'suscrito' and p_tema = any(c.temas);
  end if;
end;
$$;

revoke execute on function em__audiencia(uuid, text) from public, anon, authenticated;

create or replace function em__es_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from perfiles where id = auth.uid() and rol = 'admin');
$$;
revoke execute on function em__es_admin() from public, anon, authenticated;

-- ============================================================
-- RPC
-- ============================================================

create or replace function em_campana_guardar(
  p_id uuid, p_nombre text, p_asunto text, p_preheader text, p_contenido jsonb, p_segmento_id uuid, p_tema text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid; v_c em_campanas%rowtype; v_nom text := btrim(coalesce(p_nombre, ''));
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  if v_nom = '' or char_length(v_nom) > 100 then raise exception 'EM_CAMPANA_NOMBRE'; end if;
  if char_length(coalesce(p_asunto, '')) > 150 or char_length(coalesce(p_preheader, '')) > 200 then raise exception 'EM_CONTENIDO_INVALIDO: asunto'; end if;
  perform em__campana_validar(coalesce(p_contenido, '[]'::jsonb));
  if p_segmento_id is not null and not exists (select 1 from em_segmentos where id = p_segmento_id and not archivado) then raise exception 'EM_SEGMENTO_NO_EXISTE'; end if;
  if p_tema is not null and not exists (select 1 from em_temas where codigo = p_tema and activo) then raise exception 'EM_TEMAS_REQUERIDOS'; end if;

  if p_id is null then
    insert into em_campanas (nombre_interno, asunto, preheader, contenido, segmento_id, tema, utm_campaign)
    values (v_nom, btrim(coalesce(p_asunto, '')), nullif(btrim(coalesce(p_preheader, '')), ''), coalesce(p_contenido, '[]'::jsonb), p_segmento_id, p_tema,
            left(regexp_replace(translate(lower(v_nom), 'áéíóúüñ', 'aeiouun'), '[^a-z0-9]+', '-', 'g'), 40) || '-' || to_char(now(), 'YYMMDD') || '-' || substr(md5(random()::text), 1, 4))
    returning id into v_id;
    insert into em_campana_bitacora (campana_id, accion) values (v_id, 'crear');
  else
    select * into v_c from em_campanas where id = p_id for update;
    if not found then raise exception 'EM_CAMPANA_NO_EXISTE'; end if;
    if v_c.estado <> 'borrador' then raise exception 'EM_CAMPANA_NO_EDITABLE'; end if;
    update em_campanas set nombre_interno = v_nom, asunto = btrim(coalesce(p_asunto, '')),
           preheader = nullif(btrim(coalesce(p_preheader, '')), ''), contenido = coalesce(p_contenido, '[]'::jsonb),
           segmento_id = p_segmento_id, tema = p_tema, actualizado = now(), actualizado_por = auth.uid(), error = null
     where id = p_id returning id into v_id;
    insert into em_campana_bitacora (campana_id, accion) values (v_id, 'editar');
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;

create or replace function em_campana_duplicar(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c em_campanas%rowtype; v_id uuid;
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  select * into v_c from em_campanas where id = p_id;
  if not found then raise exception 'EM_CAMPANA_NO_EXISTE'; end if;
  insert into em_campanas (nombre_interno, asunto, preheader, contenido, segmento_id, tema, utm_campaign)
  values (left('Copia de ' || v_c.nombre_interno, 100), v_c.asunto, v_c.preheader, v_c.contenido,
          (select id from em_segmentos where id = v_c.segmento_id and not archivado), v_c.tema,
          left(v_c.utm_campaign, 40) || '-c' || substr(md5(random()::text), 1, 4))
  returning id into v_id;
  insert into em_campana_bitacora (campana_id, accion, detalle) values (v_id, 'duplicar', jsonb_build_object('desde', p_id));
  return jsonb_build_object('id', v_id);
end;
$$;

create or replace function em_campana_audiencia(p_segmento_id uuid, p_tema text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
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
      'politica_publicada', (select politica_publicada from em_config where id)
    ));
end;
$$;

create or replace function em_campanas_lista()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'id', c.id, 'nombre_interno', c.nombre_interno, 'asunto', c.asunto,
      'estado', case when c.estado = 'programada' and c.programada_para <= now() then 'enviada' else c.estado end,
      'segmento', s.nombre, 'segmento_archivado', s.archivado, 'tema', t.nombre,
      'audiencia_n', c.audiencia_n, 'programada_para', c.programada_para,
      'enviada_en', coalesce(c.enviada_en, case when c.estado = 'programada' and c.programada_para <= now() then c.programada_para end),
      'actualizado', c.actualizado, 'bloques', jsonb_array_length(c.contenido),
      'listos', (select count(*) from em_campana_destinatarios d where d.campana_id = c.id and d.estado = 'listo'),
      'pendientes', (select count(*) from em_campana_destinatarios d where d.campana_id = c.id and d.estado = 'pendiente'),
      'error', c.error)
    order by c.actualizado desc), '[]')
    from em_campanas c left join em_segmentos s on s.id = c.segmento_id left join em_temas t on t.codigo = c.tema);
end;
$$;

create or replace function em_campana_detalle(p_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_c em_campanas%rowtype;
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  select * into v_c from em_campanas where id = p_id;
  if not found then raise exception 'EM_CAMPANA_NO_EXISTE'; end if;
  return jsonb_build_object(
    'campana', to_jsonb(v_c) - 'enviando_desde',
    'estado_visible', case when v_c.estado = 'programada' and v_c.programada_para <= now() then 'enviada' else v_c.estado end,
    'segmento', (select jsonb_build_object('id', id, 'nombre', nombre, 'tipo', tipo, 'archivado', archivado) from em_segmentos where id = v_c.segmento_id),
    'tema', (select jsonb_build_object('codigo', codigo, 'nombre', nombre) from em_temas where codigo = v_c.tema),
    'destinatarios', (select jsonb_build_object('total', count(*), 'listos', count(*) filter (where estado = 'listo'),
                        'pendientes', count(*) filter (where estado = 'pendiente'), 'excluidos', count(*) filter (where estado = 'excluido'))
                        from em_campana_destinatarios where campana_id = p_id),
    'confirmada_por_correo', (select email from auth.users where id = v_c.confirmada_por),
    'bitacora', (select coalesce(jsonb_agg(jsonb_build_object('accion', b.accion, 'detalle', b.detalle, 'cuando', b.cuando,
                    'actor_correo', (select email from auth.users u where u.id = b.actor)) order by b.cuando desc), '[]')
                   from em_campana_bitacora b where b.campana_id = p_id)
  );
end;
$$;

create or replace function em_campana_registrar_prueba(p_id uuid, p_destinatario text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  insert into em_campana_bitacora (campana_id, accion, detalle) values (p_id, 'prueba', jsonb_build_object('a', left(p_destinatario, 254)));
end;
$$;

-- Confirmar: congela la audiencia. El N debe coincidir con el que vio el humano.
create or replace function em_campana_confirmar(p_id uuid, p_n_esperado integer, p_programada_para timestamptz default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c em_campanas%rowtype; v_n int;
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  select * into v_c from em_campanas where id = p_id for update;
  if not found then raise exception 'EM_CAMPANA_NO_EXISTE'; end if;
  if v_c.estado <> 'borrador' then raise exception 'EM_CAMPANA_NO_EDITABLE'; end if;
  if not (select politica_publicada from em_config where id) then raise exception 'EM_POLITICA_PENDIENTE'; end if;
  perform em__campana_lista_para_enviar(v_c);
  if p_programada_para is not null and (p_programada_para < now() + interval '5 minutes' or p_programada_para > now() + interval '30 days') then
    raise exception 'EM_PROGRAMACION_INVALIDA';
  end if;

  select count(*) into v_n from em__audiencia(v_c.segmento_id, v_c.tema);
  if v_n = 0 then raise exception 'EM_SIN_DESTINATARIOS'; end if;
  if p_n_esperado is distinct from v_n then raise exception 'EM_AUDIENCIA_CAMBIO:%', v_n; end if;

  insert into em_campana_destinatarios (campana_id, contacto_id, correo, nombre, customer_id, resend_contact_id)
  select p_id, c.id, c.correo, c.nombre, c.customer_id, c.resend_contact_id
    from em_contactos c where c.id in (select * from em__audiencia(v_c.segmento_id, v_c.tema))
  on conflict do nothing;

  update em_campanas set estado = 'preparando', audiencia_n = v_n, programada_para = p_programada_para,
         confirmada_por = auth.uid(), confirmada_en = now(), actualizado = now(), error = null
   where id = p_id;
  insert into em_campana_bitacora (campana_id, accion, detalle)
  values (p_id, 'confirmar', jsonb_build_object('audiencia', v_n, 'programada_para', p_programada_para));
  return jsonb_build_object('id', p_id, 'audiencia', v_n);
end;
$$;

-- Lote de destinatarios pendientes de sincronizar con Resend.
create or replace function em_campana_pendientes(p_id uuid, p_limite integer default 40)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_c em_campanas%rowtype;
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  select * into v_c from em_campanas where id = p_id;
  if not found then raise exception 'EM_CAMPANA_NO_EXISTE'; end if;
  return jsonb_build_object(
    'estado', v_c.estado, 'resend_segment_id', v_c.resend_segment_id, 'utm_campaign', v_c.utm_campaign,
    'restantes', (select count(*) from em_campana_destinatarios where campana_id = p_id and estado = 'pendiente'),
    'lote', (select coalesce(jsonb_agg(jsonb_build_object('contacto_id', d.contacto_id, 'correo', d.correo, 'nombre', d.nombre,
                'resend_contact_id', coalesce(d.resend_contact_id, c.resend_contact_id))), '[]')
               from (select * from em_campana_destinatarios where campana_id = p_id and estado = 'pendiente'
                      order by correo limit greatest(1, least(coalesce(p_limite, 40), 200))) d
               join em_contactos c on c.id = d.contacto_id));
end;
$$;

create or replace function em_campana_set_segmento_resend(p_id uuid, p_segment_id text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  update em_campanas set resend_segment_id = left(p_segment_id, 100)
   where id = p_id and estado = 'preparando' and resend_segment_id is null;
end;
$$;

-- Resultado de sincronizar un destinatario.
create or replace function em_campana_destinatario_resultado(
  p_id uuid, p_contacto_id uuid, p_resend_contact_id text, p_excluir_motivo text default null
)
returns void language plpgsql security definer set search_path = public as $$
declare v_ant text;
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  update em_campana_destinatarios
     set estado = case when p_excluir_motivo is null then 'listo' else 'excluido' end,
         motivo = left(p_excluir_motivo, 200), resend_contact_id = left(p_resend_contact_id, 100), procesado_en = now()
   where campana_id = p_id and contacto_id = p_contacto_id and estado = 'pendiente';
  if p_resend_contact_id is not null then
    update em_contactos set resend_contact_id = left(p_resend_contact_id, 100), sincronizado_en = now() where id = p_contacto_id;
  end if;
  -- Si en Resend la persona se dio de baja (enlace del correo), se respeta aqui.
  if p_excluir_motivo = 'baja_en_resend' then
    select estado into v_ant from em_contactos where id = p_contacto_id for update;
    if v_ant is distinct from 'baja' then
      update em_contactos set estado = 'baja', baja_en = now(), baja_motivo = 'Se dio de baja desde un correo (Resend)', actualizado = now() where id = p_contacto_id;
      insert into em_consentimiento_bitacora (contacto_id, accion, estado_anterior, estado_nuevo, detalle, actor)
      values (p_contacto_id, 'baja', v_ant, 'baja', jsonb_build_object('origen', 'resend', 'campana_id', p_id), null);
    end if;
  end if;
end;
$$;

-- Reserva el envio (anti doble clic / doble ejecucion) y devuelve lo necesario.
create or replace function em_campana_reservar_envio(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c em_campanas%rowtype; v_listos int;
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  select * into v_c from em_campanas where id = p_id for update;
  if not found then raise exception 'EM_CAMPANA_NO_EXISTE'; end if;
  if v_c.estado <> 'preparando' or v_c.resend_broadcast_id is not null then raise exception 'EM_CAMPANA_YA_ENVIADA'; end if;
  if v_c.enviando_desde is not null and v_c.enviando_desde > now() - interval '5 minutes' then raise exception 'EM_CAMPANA_EN_CURSO'; end if;
  if exists (select 1 from em_campana_destinatarios where campana_id = p_id and estado = 'pendiente') then raise exception 'EM_CAMPANA_SIN_SINCRONIZAR'; end if;
  if v_c.resend_segment_id is null then raise exception 'EM_CAMPANA_SIN_SINCRONIZAR'; end if;
  select count(*) into v_listos from em_campana_destinatarios where campana_id = p_id and estado = 'listo';
  if v_listos = 0 then
    update em_campanas set estado = 'fallida', error = 'Ningún destinatario quedó disponible (todos se dieron de baja).', actualizado = now() where id = p_id;
    insert into em_campana_bitacora (campana_id, accion, detalle) values (p_id, 'fallo', jsonb_build_object('motivo', 'sin destinatarios'));
    raise exception 'EM_SIN_DESTINATARIOS';
  end if;
  if v_c.programada_para is not null and v_c.programada_para < now() + interval '1 minute' then
    update em_campanas set programada_para = null where id = p_id; -- se paso la hora mientras se preparaba: sale ya
    v_c.programada_para := null;
  end if;
  update em_campanas set enviando_desde = now() where id = p_id;
  return jsonb_build_object('listos', v_listos, 'resend_segment_id', v_c.resend_segment_id, 'programada_para', v_c.programada_para,
    'asunto', v_c.asunto, 'preheader', v_c.preheader, 'contenido', v_c.contenido, 'utm_campaign', v_c.utm_campaign,
    'nombre_interno', v_c.nombre_interno, 'tema', (select nombre from em_temas where codigo = v_c.tema));
end;
$$;

create or replace function em_campana_marcar_enviada(p_id uuid, p_ok boolean, p_broadcast_id text, p_error text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c em_campanas%rowtype;
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  select * into v_c from em_campanas where id = p_id for update;
  if not found or v_c.estado <> 'preparando' then raise exception 'EM_CAMPANA_YA_ENVIADA'; end if;
  if p_ok then
    update em_campanas set estado = case when programada_para is null then 'enviada' else 'programada' end,
           resend_broadcast_id = left(p_broadcast_id, 100), enviada_en = case when programada_para is null then now() end,
           enviando_desde = null, error = null, actualizado = now()
     where id = p_id;
    insert into em_campana_bitacora (campana_id, accion, detalle)
    values (p_id, case when v_c.programada_para is null then 'enviar' else 'programar' end,
            jsonb_build_object('broadcast_id', p_broadcast_id, 'destinatarios', (select count(*) from em_campana_destinatarios where campana_id = p_id and estado = 'listo')));
  else
    update em_campanas set enviando_desde = null, error = left(coalesce(p_error, 'Error desconocido'), 500), actualizado = now() where id = p_id;
    insert into em_campana_bitacora (campana_id, accion, detalle) values (p_id, 'fallo', jsonb_build_object('error', left(p_error, 500)));
  end if;
  return jsonb_build_object('id', p_id);
end;
$$;

create or replace function em_campana_cancelar(p_id uuid, p_motivo text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_c em_campanas%rowtype;
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  select * into v_c from em_campanas where id = p_id for update;
  if not found then raise exception 'EM_CAMPANA_NO_EXISTE'; end if;
  if v_c.estado not in ('borrador','preparando','programada') or (v_c.estado = 'programada' and v_c.programada_para <= now()) then
    raise exception 'EM_CAMPANA_NO_CANCELABLE';
  end if;
  update em_campanas set estado = 'cancelada', enviando_desde = null, actualizado = now() where id = p_id;
  insert into em_campana_bitacora (campana_id, accion, detalle) values (p_id, 'cancelar', jsonb_build_object('motivo', left(p_motivo, 300), 'estado_anterior', v_c.estado));
  return jsonb_build_object('id', p_id, 'estado_anterior', v_c.estado, 'resend_broadcast_id', v_c.resend_broadcast_id);
end;
$$;

-- Politica de tratamiento de datos (solo admin): habilita los envios reales.
create or replace function em_config_politica(p_publicada boolean, p_url text, p_version text)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not (tiene_acceso_email_marketing() and em__es_admin()) then raise exception 'EM_SIN_ACCESO'; end if;
  if coalesce(p_publicada, false) then
    if coalesce(p_url, '') !~ '^https://(www\.)?magandhi\.com/' then raise exception 'EM_POLITICA_URL'; end if;
    if char_length(btrim(coalesce(p_version, ''))) not between 1 and 40 or lower(btrim(p_version)) = 'pendiente' then raise exception 'EM_POLITICA_VERSION'; end if;
  end if;
  update em_config set politica_publicada = coalesce(p_publicada, false),
         politica_url = case when p_publicada then p_url else politica_url end,
         politica_version = case when p_publicada then btrim(p_version) else politica_version end,
         actualizado = now(), actualizado_por = auth.uid()
   where id;
  return jsonb_build_object('politica_publicada', coalesce(p_publicada, false));
end;
$$;

-- ------------------------------------------------------------
-- Grants (nominales)
-- ------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'em_campana_guardar(uuid, text, text, text, jsonb, uuid, text)',
    'em_campana_duplicar(uuid)',
    'em_campana_audiencia(uuid, text)',
    'em_campanas_lista()',
    'em_campana_detalle(uuid)',
    'em_campana_registrar_prueba(uuid, text)',
    'em_campana_confirmar(uuid, integer, timestamptz)',
    'em_campana_pendientes(uuid, integer)',
    'em_campana_set_segmento_resend(uuid, text)',
    'em_campana_destinatario_resultado(uuid, uuid, text, text)',
    'em_campana_reservar_envio(uuid)',
    'em_campana_marcar_enviada(uuid, boolean, text, text)',
    'em_campana_cancelar(uuid, text)',
    'em_config_politica(boolean, text, text)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end $$;
