-- ============================================================
-- MAGANDHI · Email marketing · TRAMO EM1 (contactos y consentimiento)
-- ------------------------------------------------------------
-- Diseno completo en docs/PLANO-EMAIL-MARKETING.md. Este tramo crea la base
-- de la lista: quien autorizo recibir novedades/ofertas, con la PRUEBA de esa
-- autorizacion, y el historial imborrable de cada cambio. No envia nada (eso
-- es EM4) y no abre ninguna puerta publica (eso es EM6, apagado hasta que
-- exista la politica de tratamiento de datos).
--
-- QUE CREA:
--   tiene_acceso_email_marketing()  -> modulo PROPIO 'email_marketing' (PII).
--   em_config                       -> fila unica: estado de la politica,
--                                      texto de consentimiento vigente,
--                                      interruptores de captura/analitica.
--   em_temas                        -> Novedades y Ofertas.
--   em_contactos                    -> la lista, con prueba de consentimiento.
--   em_consentimiento_bitacora      -> append-only: alta, baja, reactivacion,
--                                      edicion, vinculo con cliente.
--   Trigger en clientes             -> si un cliente nuevo/editado tiene el
--                                      correo de un contacto, se enlazan solos.
--   RPC: em_alta_manual, em_editar_contacto, em_dar_baja, em_resumen,
--        em_contacto_detalle, em_correos_seguimiento.
--
-- REGLAS (linea roja del dueno):
--   - Solo entra quien AUTORIZO, y el alta manual EXIGE evidencia (canal +
--     detalle + confirmacion explicita del operador).
--   - Nada se borra: la baja cambia el estado y deja rastro; hay que poder
--     demostrar que se respeto.
--   - CERO acceso anon. Lectura solo con modulo email_marketing (o admin).
--   - Escritura solo por RPC security definer.
--
-- Forward e idempotente. Default privileges del tramo 0: EXECUTE nominal.
-- REQUISITO: despues de 20261008000100_ventas_bloqueo_stock.sql.
-- ============================================================

-- ------------------------------------------------------------
-- Acceso: modulo propio (la lista es informacion personal)
-- ------------------------------------------------------------
create or replace function tiene_acceso_email_marketing()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select tiene_modulo('email_marketing');
$$;

comment on function tiene_acceso_email_marketing() is 'Acceso al Email marketing: admin o modulo email_marketing. Modulo PROPIO (no hereda marketing) porque la lista de contactos es PII; deja listo D3.';

revoke execute on function tiene_acceso_email_marketing() from public;
grant  execute on function tiene_acceso_email_marketing() to authenticated, service_role;

-- ------------------------------------------------------------
-- em_config (fila unica)
-- ------------------------------------------------------------
create table if not exists em_config (
  id                     boolean primary key default true check (id),
  politica_publicada     boolean not null default false,
  politica_url           text,
  politica_version       text not null default 'pendiente',
  texto_consentimiento   text not null,
  captura_publica_activa boolean not null default false,
  analitica_activa       boolean not null default false,
  actualizado            timestamptz not null default now(),
  actualizado_por        uuid references auth.users(id)
);

comment on table em_config is 'Configuracion unica del Email marketing: estado de la politica de tratamiento de datos, texto de consentimiento VIGENTE (se copia a cada contacto al darlo de alta, como prueba de que acepto) e interruptores de captura publica (EM6) y analitica (EM7). Ambos nacen APAGADOS.';

insert into em_config (id, texto_consentimiento)
values (true, 'Autorizo a MAGANDHI a enviarme por correo electrónico novedades y ofertas de sus productos. Puedo dejar de recibirlos en cualquier momento desde el enlace que trae cada correo.')
on conflict (id) do nothing;

-- ------------------------------------------------------------
-- em_temas
-- ------------------------------------------------------------
create table if not exists em_temas (
  codigo      text primary key check (codigo ~ '^[a-z_]+$'),
  nombre      text not null,
  descripcion text,
  orden       integer not null default 0,
  activo      boolean not null default true
);

comment on table em_temas is 'Temas de preferencia: el contacto elige que recibir (y en EM4 puede darse de baja de un tema sin irse de todo).';

insert into em_temas (codigo, nombre, descripcion, orden) values
  ('novedades', 'Novedades', 'Productos nuevos y noticias de MAGANDHI.', 1),
  ('ofertas',   'Ofertas',   'Promociones y precios especiales.', 2)
on conflict (codigo) do nothing;

-- ------------------------------------------------------------
-- em_contactos
-- ------------------------------------------------------------
create table if not exists em_contactos (
  id                   uuid primary key default gen_random_uuid(),
  correo               text not null,
  correo_norm          text not null,
  customer_id          uuid references clientes(id),
  nombre               text,
  estado               text not null default 'suscrito'
                         check (estado in ('pendiente_confirmacion','suscrito','baja','rebotado','queja')),
  fuente               text not null
                         check (fuente in ('manual','formulario_tienda','casilla_checkout','importacion_con_evidencia')),
  temas                text[] not null default array['novedades','ofertas'],
  consentimiento_en    timestamptz not null,
  consentimiento_texto text not null,
  politica_version     text not null,
  confirmado_en        timestamptz,
  evidencia            jsonb,
  baja_en              timestamptz,
  baja_motivo          text,
  resend_contact_id    text,
  sincronizado_en      timestamptz,
  creado               timestamptz not null default now(),
  creado_por           uuid references auth.users(id) default auth.uid(),
  actualizado          timestamptz not null default now()
);

create unique index if not exists em_contactos_correo_norm_uidx on em_contactos (correo_norm);
create index if not exists idx_em_contactos_estado on em_contactos (estado);
create index if not exists idx_em_contactos_customer on em_contactos (customer_id);

comment on table em_contactos is 'Lista de email marketing. Solo personas que AUTORIZARON, con la prueba: texto exacto aceptado (consentimiento_texto), version de la politica, fecha, fuente y evidencia. Nunca se borra: la baja cambia el estado. customer_id enlaza el contacto con sus compras (por correo).';
comment on column em_contactos.evidencia is 'Prueba del alta manual: {canal, detalle, confirmado_por_operador, registrado_por, registrado_en}. Obligatoria para fuente=manual.';
comment on column em_contactos.politica_version is 'Version de la politica vigente cuando autorizo. "pendiente" = aun no habia politica publicada (las campanas lo tendran en cuenta en EM4).';

-- ------------------------------------------------------------
-- em_consentimiento_bitacora (append-only)
-- ------------------------------------------------------------
create table if not exists em_consentimiento_bitacora (
  id              uuid primary key default gen_random_uuid(),
  contacto_id     uuid not null references em_contactos(id),
  accion          text not null
                    check (accion in ('alta','confirmacion','baja','reactivacion','edicion','rebote','queja','vinculo_cliente')),
  estado_anterior text,
  estado_nuevo    text,
  detalle         jsonb,
  actor           uuid references auth.users(id) default auth.uid(),
  cuando          timestamptz not null default now()
);

create index if not exists idx_em_bitacora_contacto on em_consentimiento_bitacora (contacto_id, cuando);

comment on table em_consentimiento_bitacora is 'Historial imborrable del consentimiento de cada contacto. Sin policy de UPDATE/DELETE: solo crece. actor NULL = proceso automatico (p. ej. vinculo por trigger o webhook).';

-- ------------------------------------------------------------
-- RLS + grants (lectura con modulo; escritura solo RPC)
-- ------------------------------------------------------------
alter table em_config                  enable row level security;
alter table em_temas                   enable row level security;
alter table em_contactos               enable row level security;
alter table em_consentimiento_bitacora enable row level security;

drop policy if exists em_config_select on em_config;
create policy em_config_select on em_config for select to authenticated using (tiene_acceso_email_marketing());
drop policy if exists em_temas_select on em_temas;
create policy em_temas_select on em_temas for select to authenticated using (tiene_acceso_email_marketing());
drop policy if exists em_contactos_select on em_contactos;
create policy em_contactos_select on em_contactos for select to authenticated using (tiene_acceso_email_marketing());
drop policy if exists em_bitacora_select on em_consentimiento_bitacora;
create policy em_bitacora_select on em_consentimiento_bitacora for select to authenticated using (tiene_acceso_email_marketing());

grant select on table em_config, em_temas, em_contactos, em_consentimiento_bitacora to authenticated;

-- ------------------------------------------------------------
-- Vinculo automatico contacto <-> cliente por correo
-- ------------------------------------------------------------
create or replace function em_vincular_por_correo()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if new.correo_norm is null then
    return new;
  end if;
  for v_id in
    update em_contactos
       set customer_id = new.id, actualizado = now()
     where correo_norm = new.correo_norm
       and customer_id is null
    returning id
  loop
    insert into em_consentimiento_bitacora (contacto_id, accion, estado_anterior, estado_nuevo, detalle, actor)
    select v_id, 'vinculo_cliente', c.estado, c.estado, jsonb_build_object('customer_id', new.id), null
      from em_contactos c where c.id = v_id;
  end loop;
  return new;
end;
$$;

revoke execute on function em_vincular_por_correo() from public;

drop trigger if exists trg_clientes_em_vincular on clientes;
create trigger trg_clientes_em_vincular
  after insert or update of correo_norm on clientes
  for each row execute function em_vincular_por_correo();

-- ============================================================
-- RPC
-- ============================================================

-- ------------------------------------------------------------
-- em_alta_manual: registra (o reactiva) un contacto con EVIDENCIA.
-- ------------------------------------------------------------
create or replace function em_alta_manual(
  p_correo        text,
  p_nombre        text,
  p_temas         text[],
  p_canal         text,
  p_detalle       text,
  p_autorizado_en date    default current_date,
  p_confirmo      boolean default false,
  p_reactivar     boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_norm    text := ventas_norm_correo(p_correo);
  v_cfg     em_config%rowtype;
  v_temas   text[];
  v_exist   em_contactos%rowtype;
  v_cliente uuid;
  v_id      uuid;
  v_evid    jsonb;
  v_detalle text := btrim(coalesce(p_detalle, ''));
begin
  if not tiene_acceso_email_marketing() then
    raise exception 'EM_SIN_ACCESO';
  end if;
  if v_norm is null or v_norm !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or length(v_norm) > 254 then
    raise exception 'EM_CORREO_INVALIDO';
  end if;
  if p_canal is null or p_canal not in ('whatsapp','presencial','llamada','correo','otro') then
    raise exception 'EM_CANAL_INVALIDO';
  end if;
  if length(v_detalle) < 10 then
    raise exception 'EM_EVIDENCIA_REQUERIDA';
  end if;
  if not coalesce(p_confirmo, false) then
    raise exception 'EM_CONFIRMACION_REQUERIDA';
  end if;
  if p_autorizado_en is null or p_autorizado_en > current_date then
    raise exception 'EM_FECHA_INVALIDA';
  end if;

  select coalesce(array_agg(t order by t), '{}') into v_temas
    from (select distinct unnest(coalesce(p_temas, '{}')) as t) x
   where t in (select codigo from em_temas where activo);
  if cardinality(v_temas) = 0 then
    raise exception 'EM_TEMAS_REQUERIDOS';
  end if;

  select * into v_cfg from em_config where id;

  v_evid := jsonb_build_object(
    'canal', p_canal,
    'detalle', left(v_detalle, 1000),
    'confirmado_por_operador', true,
    'registrado_por', auth.uid(),
    'registrado_en', now()
  );

  select * into v_exist from em_contactos where correo_norm = v_norm for update;

  if found then
    if v_exist.estado in ('suscrito','pendiente_confirmacion') then
      raise exception 'EM_CONTACTO_YA_EXISTE';
    end if;
    if not coalesce(p_reactivar, false) then
      raise exception 'EM_CONTACTO_INACTIVO:%', v_exist.estado;
    end if;

    update em_contactos
       set estado = 'suscrito',
           nombre = coalesce(nullif(btrim(coalesce(p_nombre, '')), ''), nombre),
           temas = v_temas,
           fuente = 'manual',
           consentimiento_en = p_autorizado_en::timestamptz,
           consentimiento_texto = v_cfg.texto_consentimiento,
           politica_version = v_cfg.politica_version,
           evidencia = v_evid,
           baja_en = null,
           baja_motivo = null,
           actualizado = now()
     where id = v_exist.id;

    insert into em_consentimiento_bitacora (contacto_id, accion, estado_anterior, estado_nuevo, detalle)
    values (v_exist.id, 'reactivacion', v_exist.estado, 'suscrito',
            jsonb_build_object('evidencia', v_evid, 'temas', v_temas, 'politica_version', v_cfg.politica_version));

    return jsonb_build_object('id', v_exist.id, 'reactivado', true);
  end if;

  select id into v_cliente from clientes where correo_norm = v_norm limit 1;

  insert into em_contactos (
    correo, correo_norm, customer_id, nombre, estado, fuente, temas,
    consentimiento_en, consentimiento_texto, politica_version, evidencia
  ) values (
    btrim(p_correo), v_norm, v_cliente, nullif(btrim(coalesce(p_nombre, '')), ''), 'suscrito', 'manual', v_temas,
    p_autorizado_en::timestamptz, v_cfg.texto_consentimiento, v_cfg.politica_version, v_evid
  )
  returning id into v_id;

  insert into em_consentimiento_bitacora (contacto_id, accion, estado_anterior, estado_nuevo, detalle)
  values (v_id, 'alta', null, 'suscrito',
          jsonb_build_object('fuente', 'manual', 'evidencia', v_evid, 'temas', v_temas,
                             'politica_version', v_cfg.politica_version, 'customer_id', v_cliente));

  return jsonb_build_object('id', v_id, 'reactivado', false, 'vinculado_cliente', v_cliente is not null);
end;
$$;

comment on function em_alta_manual(text, text, text[], text, text, date, boolean, boolean) is 'Alta (o reactivacion explicita) de un contacto con EVIDENCIA obligatoria: canal, detalle >= 10 caracteres y confirmacion del operador. Copia el texto de consentimiento y la version de politica vigentes como prueba. Enlaza solo con el cliente del mismo correo. Errores estables EM_*.';

revoke execute on function em_alta_manual(text, text, text[], text, text, date, boolean, boolean) from public;
grant  execute on function em_alta_manual(text, text, text[], text, text, date, boolean, boolean) to authenticated, service_role;

-- ------------------------------------------------------------
-- em_editar_contacto: nombre y temas (no toca el consentimiento).
-- ------------------------------------------------------------
create or replace function em_editar_contacto(p_id uuid, p_nombre text, p_temas text[])
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c     em_contactos%rowtype;
  v_temas text[];
  v_nom   text := nullif(btrim(coalesce(p_nombre, '')), '');
begin
  if not tiene_acceso_email_marketing() then
    raise exception 'EM_SIN_ACCESO';
  end if;
  select * into v_c from em_contactos where id = p_id for update;
  if not found then
    raise exception 'EM_CONTACTO_NO_EXISTE';
  end if;

  select coalesce(array_agg(t order by t), '{}') into v_temas
    from (select distinct unnest(coalesce(p_temas, '{}')) as t) x
   where t in (select codigo from em_temas where activo);
  if cardinality(v_temas) = 0 then
    raise exception 'EM_TEMAS_REQUERIDOS';
  end if;

  if v_nom is not distinct from v_c.nombre and v_temas = v_c.temas then
    return jsonb_build_object('id', p_id, 'cambios', false);
  end if;

  update em_contactos set nombre = v_nom, temas = v_temas, actualizado = now() where id = p_id;

  insert into em_consentimiento_bitacora (contacto_id, accion, estado_anterior, estado_nuevo, detalle)
  values (p_id, 'edicion', v_c.estado, v_c.estado,
          jsonb_build_object('antes', jsonb_build_object('nombre', v_c.nombre, 'temas', v_c.temas),
                             'despues', jsonb_build_object('nombre', v_nom, 'temas', v_temas)));

  return jsonb_build_object('id', p_id, 'cambios', true);
end;
$$;

revoke execute on function em_editar_contacto(uuid, text, text[]) from public;
grant  execute on function em_editar_contacto(uuid, text, text[]) to authenticated, service_role;

-- ------------------------------------------------------------
-- em_dar_baja: baja manual (p. ej. la persona lo pidio por WhatsApp).
-- ------------------------------------------------------------
create or replace function em_dar_baja(p_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_c em_contactos%rowtype;
  v_motivo text := nullif(btrim(coalesce(p_motivo, '')), '');
begin
  if not tiene_acceso_email_marketing() then
    raise exception 'EM_SIN_ACCESO';
  end if;
  select * into v_c from em_contactos where id = p_id for update;
  if not found then
    raise exception 'EM_CONTACTO_NO_EXISTE';
  end if;
  if v_c.estado = 'baja' then
    return jsonb_build_object('id', p_id, 'cambios', false);
  end if;
  if v_motivo is null then
    raise exception 'EM_MOTIVO_REQUERIDO';
  end if;

  update em_contactos
     set estado = 'baja', baja_en = now(), baja_motivo = left(v_motivo, 500), actualizado = now()
   where id = p_id;

  insert into em_consentimiento_bitacora (contacto_id, accion, estado_anterior, estado_nuevo, detalle)
  values (p_id, 'baja', v_c.estado, 'baja', jsonb_build_object('motivo', left(v_motivo, 500), 'origen', 'manual'));

  return jsonb_build_object('id', p_id, 'cambios', true);
end;
$$;

revoke execute on function em_dar_baja(uuid, text) from public;
grant  execute on function em_dar_baja(uuid, text) to authenticated, service_role;

-- ------------------------------------------------------------
-- em_resumen: todo lo que pinta la pantalla Resumen en una llamada.
-- ------------------------------------------------------------
create or replace function em_resumen()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not tiene_acceso_email_marketing() then
    raise exception 'EM_SIN_ACCESO';
  end if;

  select jsonb_build_object(
    'total',        (select count(*) from em_contactos),
    'por_estado',   (select coalesce(jsonb_object_agg(estado, n), '{}') from
                      (select estado, count(*) n from em_contactos group by estado) e),
    'por_fuente',   (select coalesce(jsonb_object_agg(fuente, n), '{}') from
                      (select fuente, count(*) n from em_contactos where estado = 'suscrito' group by fuente) f),
    'por_tema',     (select coalesce(jsonb_agg(jsonb_build_object('codigo', t.codigo, 'nombre', t.nombre,
                        'suscritos', (select count(*) from em_contactos c where c.estado = 'suscrito' and t.codigo = any(c.temas)))
                      order by t.orden), '[]') from em_temas t where t.activo),
    'vinculados',   (select count(*) from em_contactos where estado = 'suscrito' and customer_id is not null),
    'altas_30d',    (select count(*) from em_consentimiento_bitacora where accion in ('alta','reactivacion') and cuando >= now() - interval '30 days'),
    'bajas_30d',    (select count(*) from em_consentimiento_bitacora where accion = 'baja' and cuando >= now() - interval '30 days'),
    'clientes_con_correo_sin_contacto',
                    (select count(*) from clientes cl where cl.correo_norm is not null
                       and not exists (select 1 from em_contactos c where c.correo_norm = cl.correo_norm)),
    'semanas',      (select coalesce(jsonb_agg(jsonb_build_object('semana', s.semana, 'altas', s.altas, 'bajas', s.bajas) order by s.semana), '[]')
                       from (
                         select g::date as semana,
                                (select count(*) from em_consentimiento_bitacora b
                                  where b.accion in ('alta','reactivacion')
                                    and b.cuando >= g and b.cuando < g + interval '7 days') as altas,
                                (select count(*) from em_consentimiento_bitacora b
                                  where b.accion = 'baja'
                                    and b.cuando >= g and b.cuando < g + interval '7 days') as bajas
                           from generate_series(date_trunc('week', now()) - interval '11 weeks',
                                                date_trunc('week', now()), interval '1 week') g
                       ) s),
    'seguimiento_30d', (select jsonb_build_object(
                          'enviados', count(*) filter (where estado = 'enviado'),
                          'fallidos', count(*) filter (where estado = 'fallido'),
                          'ultimo',   max(creado))
                          from correo_envios where not es_prueba and creado >= now() - interval '30 days'),
    'config',       (select jsonb_build_object('politica_publicada', politica_publicada, 'politica_version', politica_version,
                        'politica_url', politica_url, 'captura_publica_activa', captura_publica_activa,
                        'analitica_activa', analitica_activa, 'texto_consentimiento', texto_consentimiento)
                       from em_config where id)
  ) into v;

  return v;
end;
$$;

revoke execute on function em_resumen() from public;
grant  execute on function em_resumen() to authenticated, service_role;

-- ------------------------------------------------------------
-- em_contacto_detalle: ficha completa de un contacto.
-- ------------------------------------------------------------
create or replace function em_contacto_detalle(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_c em_contactos%rowtype;
begin
  if not tiene_acceso_email_marketing() then
    raise exception 'EM_SIN_ACCESO';
  end if;
  select * into v_c from em_contactos where id = p_id;
  if not found then
    raise exception 'EM_CONTACTO_NO_EXISTE';
  end if;

  return jsonb_build_object(
    'contacto', to_jsonb(v_c) - 'correo_norm',
    'registrado_por_correo', (select u.email from auth.users u where u.id = v_c.creado_por),
    'bitacora', (select coalesce(jsonb_agg(jsonb_build_object(
                    'accion', b.accion, 'estado_anterior', b.estado_anterior, 'estado_nuevo', b.estado_nuevo,
                    'detalle', b.detalle, 'cuando', b.cuando,
                    'actor_correo', (select u.email from auth.users u where u.id = b.actor))
                  order by b.cuando desc), '[]')
                   from em_consentimiento_bitacora b where b.contacto_id = p_id),
    'cliente', (select jsonb_build_object(
                  'id', cl.id, 'nombre', cl.nombre, 'ciudad', cl.ciudad,
                  'pedidos', (select count(*) from pedidos p where p.customer_id = cl.id and not p.anulado),
                  'total', (select coalesce(sum(p.total), 0) from pedidos p where p.customer_id = cl.id and not p.anulado),
                  'ultima_compra', (select max(p.fecha_orden) from pedidos p where p.customer_id = cl.id and not p.anulado))
                 from clientes cl where cl.id = v_c.customer_id),
    'seguimiento', (select coalesce(jsonb_agg(jsonb_build_object(
                      'etapa', e.etapa, 'estado', e.estado, 'creado', e.creado,
                      'pedido', case when e.pedido_id is null then null else correo_ref_pedido(e.pedido_id) end)
                    order by e.creado desc), '[]')
                     from (select * from correo_envios
                            where lower(destinatario) = v_c.correo_norm and not es_prueba
                            order by creado desc limit 20) e)
  );
end;
$$;

revoke execute on function em_contacto_detalle(uuid) from public;
grant  execute on function em_contacto_detalle(uuid) to authenticated, service_role;

-- ------------------------------------------------------------
-- em_correos_seguimiento: historial de los correos del pedido (solo lectura).
-- ------------------------------------------------------------
create or replace function em_correos_seguimiento(
  p_etapa  text default null,
  p_estado text default null,
  p_buscar text default null,
  p_limite integer default 200
)
returns table (
  id uuid, creado timestamptz, etapa text, estado text, destinatario text,
  asunto text, es_prueba boolean, es_reenvio boolean, error text,
  pedido_ref text, cliente_nombre text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_b text := nullif(btrim(lower(coalesce(p_buscar, ''))), '');
begin
  if not (tiene_acceso_email_marketing() or tiene_acceso_ventas()) then
    raise exception 'EM_SIN_ACCESO';
  end if;
  return query
    select e.id, e.creado, e.etapa, e.estado, e.destinatario, e.asunto, e.es_prueba, e.es_reenvio, e.error,
           case when e.pedido_id is null then null else correo_ref_pedido(e.pedido_id) end,
           cl.nombre
      from correo_envios e
      left join pedidos p on p.id = e.pedido_id
      left join clientes cl on cl.id = p.customer_id
     where (p_etapa is null or e.etapa = p_etapa)
       and (p_estado is null or e.estado = p_estado)
       and (v_b is null
            or lower(e.destinatario) like '%' || v_b || '%'
            or lower(coalesce(cl.nombre, '')) like '%' || v_b || '%'
            or (e.pedido_id is not null and lower(correo_ref_pedido(e.pedido_id)) like '%' || ltrim(v_b, '#') || '%'))
     order by e.creado desc
     limit greatest(1, least(coalesce(p_limite, 200), 1000));
end;
$$;

revoke execute on function em_correos_seguimiento(text, text, text, integer) from public;
grant  execute on function em_correos_seguimiento(text, text, text, integer) to authenticated, service_role;
