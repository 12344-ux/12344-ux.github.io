-- ============================================================
-- MAGANDHI · Email marketing · TRAMO EM5 (resultados)
-- ------------------------------------------------------------
-- Diseno en docs/PLANO-EMAIL-MARKETING.md §3.5, §6 y §11.
--
-- QUE CREA:
--   em_eventos                 -> un aviso de Resend por fila (llega por el
--                                 webhook firmado). Idempotente por svix-id.
--   em_campana_resultados_archivo -> totales congelados de campanas con mas de
--                                 13 meses (retencion de eventos crudos).
--   correo_envios.*            -> entregado_en / rebote_en / rebote_tipo /
--                                 queja_en para los correos del pedido.
--   pedidos.utm_campaign       -> atribucion EXACTA; vacia hasta Wompi F2.
--   em_webhook_registrar()     -> UNICA puerta de escritura. Solo service_role
--                                 (la Edge Function em-webhook, tras verificar
--                                 la firma Svix). Ni anon ni authenticated.
--   RPC de lectura (modulo email_marketing): em_campana_resultados,
--     em_campanas_resultados_lista, em_salud_lista, em_contacto_campanas.
--   em_correos_seguimiento     -> se recrea con la columna "entrega".
--
-- DECISIONES DEL DUENO (8-oct-2026):
--   1. Atribucion aproximada: pedido NO anulado del mismo cliente, registrado
--      despues del clic y con fecha_orden entre el dia del clic y 7 dias
--      despues. Si clico varias campanas, cuenta solo la del ULTIMO clic.
--   2. Bajas por campana: a la ultima campana que la persona recibio antes de
--      darse de baja, rotuladas "aproximado".
--   3. Rebote PERMANENTE de un correo del pedido -> el contacto de marketing
--      con ese correo tambien queda 'rebotado' (el correo no existe).
--   4. email.suppressed -> 'rebotado' con motivo "suprimida por Resend".
--   5. Eventos crudos: 13 meses; despues solo los totales por campana.
--
-- REGLAS: nunca se vuelve a 'suscrito' desde un webhook; los estados solo
-- empeoran (suscrito -> baja -> rebotado -> queja); el rebote temporal NO
-- suprime; no se guardan IP ni navegador del clic.
--
-- Forward e idempotente. REQUISITO: despues de 20261012000000.
-- ============================================================

-- ------------------------------------------------------------
-- Columnas nuevas
-- ------------------------------------------------------------
alter table correo_envios add column if not exists entregado_en timestamptz;
alter table correo_envios add column if not exists rebote_en    timestamptz;
alter table correo_envios add column if not exists rebote_tipo  text;
alter table correo_envios add column if not exists queja_en     timestamptz;

comment on column correo_envios.entregado_en is 'EM5: Resend confirmo la entrega al servidor del destinatario (webhook email.delivered).';
comment on column correo_envios.rebote_en is 'EM5: el correo reboto. rebote_tipo = permanente | temporal | suprimido.';

create index if not exists idx_correo_envios_proveedor on correo_envios (proveedor_id) where proveedor_id is not null;

alter table pedidos add column if not exists utm_campaign text;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'pedidos_utm_campaign_formato') then
    alter table pedidos add constraint pedidos_utm_campaign_formato
      check (utm_campaign is null or utm_campaign ~ '^[a-z0-9-]{1,60}$');
  end if;
end $$;
comment on column pedidos.utm_campaign is 'EM5: utm_campaign con el que llego el comprador (atribucion EXACTA a una campana de email). La llena Wompi F2 desde la intencion de pago; los pedidos manuales la dejan vacia y se atribuyen de forma aproximada (clic + 7 dias).';
create index if not exists idx_pedidos_utm on pedidos (utm_campaign) where utm_campaign is not null;

create index if not exists idx_em_campanas_broadcast on em_campanas (resend_broadcast_id) where resend_broadcast_id is not null;

-- ------------------------------------------------------------
-- em_eventos
-- ------------------------------------------------------------
create table if not exists em_eventos (
  id              uuid primary key default gen_random_uuid(),
  svix_id         text not null,
  evento          text not null,
  tipo            text not null check (tipo in ('enviado','entregado','retrasado','rebote','rebote_temporal',
                                                'queja','apertura','clic','fallido','suprimido','baja','supresion')),
  origen          text not null check (origen in ('campana','pedido','contacto')),
  campana_id      uuid references em_campanas(id),
  contacto_id     uuid references em_contactos(id),
  correo_envio_id uuid references correo_envios(id),
  resend_email_id text,
  enlace          text,
  detalle         jsonb,
  cuando          timestamptz not null,
  recibido        timestamptz not null default now()
);

create unique index if not exists em_eventos_svix_uidx on em_eventos (svix_id);
create index if not exists idx_em_eventos_campana on em_eventos (campana_id, tipo) where campana_id is not null;
create index if not exists idx_em_eventos_contacto on em_eventos (contacto_id, tipo, cuando) where contacto_id is not null;
create index if not exists idx_em_eventos_cuando on em_eventos (cuando);

comment on table em_eventos is 'EM5: avisos de Resend (webhook firmado con Svix). Uno por fila, unico por svix_id (Resend repite el mismo svix-id en cada reintento). Sin IP ni navegador: solo tipo, campana, contacto, enlace y momento. Retencion 13 meses (em__depurar_eventos). Solo escribe em_webhook_registrar (service_role).';
comment on column em_eventos.detalle is 'Minimo: tipo/subtipo/mensaje del rebote, motivo del fallo o de la supresion. Nunca el HTML ni la IP/user-agent del clic.';

alter table em_eventos enable row level security;
drop policy if exists em_eventos_select on em_eventos;
create policy em_eventos_select on em_eventos for select to authenticated using (tiene_acceso_email_marketing());
grant select on table em_eventos to authenticated;

create table if not exists em_campana_resultados_archivo (
  campana_id  uuid primary key references em_campanas(id),
  resultados  jsonb not null,
  archivado_en timestamptz not null default now()
);
comment on table em_campana_resultados_archivo is 'EM5: totales congelados de una campana cuyos eventos crudos superaron los 13 meses de retencion. em_campana_resultados los devuelve tal cual (archivado=true).';
alter table em_campana_resultados_archivo enable row level security;
drop policy if exists em_cra_select on em_campana_resultados_archivo;
create policy em_cra_select on em_campana_resultados_archivo for select to authenticated using (tiene_acceso_email_marketing());
grant select on table em_campana_resultados_archivo to authenticated;

-- ------------------------------------------------------------
-- Supresion (interna): los estados solo empeoran, nunca vuelven a suscrito.
-- Rango: suscrito/pendiente (0) < baja (1) < rebotado (2) < queja (3).
-- ------------------------------------------------------------
create or replace function em__suprimir(p_contacto uuid, p_estado text, p_detalle jsonb)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ant text;
  r_ant int; r_nuevo int;
begin
  if p_contacto is null or p_estado not in ('baja','rebotado','queja') then return false; end if;
  select estado into v_ant from em_contactos where id = p_contacto for update;
  if not found then return false; end if;
  r_ant   := case v_ant when 'baja' then 1 when 'rebotado' then 2 when 'queja' then 3 else 0 end;
  r_nuevo := case p_estado when 'baja' then 1 when 'rebotado' then 2 else 3 end;
  if r_nuevo <= r_ant then return false; end if;

  update em_contactos
     set estado = p_estado,
         baja_en = case when p_estado = 'baja' then now() else baja_en end,
         baja_motivo = case when p_estado = 'baja' then 'Se dio de baja desde el enlace de un correo (Resend)' else baja_motivo end,
         actualizado = now()
   where id = p_contacto;

  insert into em_consentimiento_bitacora (contacto_id, accion, estado_anterior, estado_nuevo, detalle, actor)
  values (p_contacto, case p_estado when 'rebotado' then 'rebote' else p_estado end, v_ant, p_estado,
          coalesce(p_detalle, '{}'::jsonb) || jsonb_build_object('origen', 'resend_webhook'), null);
  return true;
end;
$$;

revoke execute on function em__suprimir(uuid, text, jsonb) from public, anon, authenticated;

-- Fecha segura: un valor mal formado da NULL (no tumba el webhook; si fallara,
-- Resend reintentaria el mismo aviso durante horas).
create or replace function em__ts(p text)
returns timestamptz
language plpgsql
immutable
set search_path = public
as $$
begin
  if p is null or p !~ '^\d{4}-\d{2}-\d{2}' then return null; end if;
  return p::timestamptz;
exception when others then
  return null;
end;
$$;

revoke execute on function em__ts(text) from public, anon, authenticated;

-- ------------------------------------------------------------
-- em_webhook_registrar: UNICA puerta de escritura de los avisos de Resend.
-- p_evento = cuerpo JSON del webhook ya verificado {type, created_at, data}.
-- Devuelve {estado: procesado | repetido | ignorado, ...}.
-- ------------------------------------------------------------
create or replace function em_webhook_registrar(p_svix_id text, p_evento jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type   text := p_evento->>'type';
  d        jsonb := coalesce(p_evento->'data', '{}'::jsonb);
  v_tipo   text;
  v_origen text;
  v_correo text;
  v_camp   uuid;
  v_cont   uuid;
  v_envio  uuid;
  v_email_id text := left(d->>'email_id', 100);
  v_enlace text;
  v_det    jsonb;
  v_cuando timestamptz;
  v_id     uuid;
  v_tag    text;
  v_supr   boolean := false;
begin
  if p_svix_id is null or p_svix_id !~ '^[A-Za-z0-9_-]{6,100}$' then raise exception 'EM_WEBHOOK_ID_INVALIDO'; end if;
  if p_evento is null or jsonb_typeof(p_evento) <> 'object' or v_type is null then raise exception 'EM_WEBHOOK_EVENTO_INVALIDO'; end if;

  -- Los envios de PRUEBA (a tu propio correo) no son resultados.
  v_tag := case jsonb_typeof(d->'tags')
             when 'object' then d->'tags'->>'tipo'
             when 'array'  then (select t->>'value' from jsonb_array_elements(d->'tags') t where t->>'name' = 'tipo' limit 1)
           end;
  if v_tag in ('prueba', 'prueba_campana') then
    return jsonb_build_object('estado', 'ignorado', 'motivo', 'prueba');
  end if;

  v_tipo := case v_type
    when 'email.sent'             then 'enviado'
    when 'email.delivered'        then 'entregado'
    when 'email.delivery_delayed' then 'retrasado'
    when 'email.bounced'          then case when d->'bounce'->>'type' = 'Permanent' then 'rebote' else 'rebote_temporal' end
    when 'email.complained'       then 'queja'
    when 'email.opened'           then 'apertura'
    when 'email.clicked'          then 'clic'
    when 'email.failed'           then 'fallido'
    when 'email.suppressed'       then 'suprimido'
    when 'contact.updated'        then case when d->'unsubscribed' = 'true'::jsonb then 'baja' end
    when 'suppression.added'      then 'supresion'
  end;
  if v_tipo is null then
    -- contact.updated con unsubscribed=false (incluye nuestras propias
    -- sincronizaciones), email.scheduled, dominios, temas, suppression.removed...
    -- Nada de esto cambia resultados ni vuelve a suscribir a nadie.
    return jsonb_build_object('estado', 'ignorado', 'motivo', v_type);
  end if;

  -- Correo del destinatario
  v_correo := lower(btrim(coalesce(
    case when v_type like 'email.%' then
      case jsonb_typeof(d->'to') when 'array' then d->'to'->>0 when 'string' then d->>'to' end
    else d->>'email' end, '')));
  if v_correo = '' then v_correo := null; end if;

  v_cuando := least(now() + interval '5 minutes', coalesce(
    case when v_tipo = 'clic' then em__ts(d->'click'->>'timestamp') end,
    em__ts(p_evento->>'created_at'), now()));

  -- ¿De que vino? Campana (broadcast_id) > correo del pedido (email_id) > contacto.
  if v_type like 'email.%' then
    if coalesce(d->>'broadcast_id', '') <> '' then
      select id into v_camp from em_campanas where resend_broadcast_id = d->>'broadcast_id';
    end if;
    if v_camp is not null then
      v_origen := 'campana';
      select contacto_id into v_cont from em_campana_destinatarios
       where campana_id = v_camp and lower(correo) = v_correo limit 1;
    elsif v_email_id is not null then
      select id into v_envio from correo_envios where proveedor_id = v_email_id and not es_prueba limit 1;
      if v_envio is not null then v_origen := 'pedido'; end if;
    end if;
  end if;
  if v_cont is null and v_correo is not null then
    select id into v_cont from em_contactos where correo_norm = v_correo;
  end if;
  if v_origen is null then
    if v_cont is null then
      return jsonb_build_object('estado', 'ignorado', 'motivo', 'sin_relacion');
    end if;
    -- Un evento de correo que no es de una campana ni de un pedido conocido
    -- solo importa si SUPRIME (rebote/queja/supresion) a un contacto.
    if v_type like 'email.%' and v_tipo not in ('rebote','queja','suprimido') then
      return jsonb_build_object('estado', 'ignorado', 'motivo', 'sin_relacion');
    end if;
    v_origen := 'contacto';
  end if;

  if v_tipo = 'clic' then
    v_enlace := left(d->'click'->>'link', 600);
  end if;
  v_det := jsonb_strip_nulls(jsonb_build_object(
    'rebote', case when d ? 'bounce' then jsonb_build_object(
                'tipo', left(d->'bounce'->>'type', 40), 'subtipo', left(d->'bounce'->>'subType', 60),
                'mensaje', left(d->'bounce'->>'message', 300)) end,
    'fallo', left(d->'failed'->>'reason', 200),
    'supresion', coalesce(left(d->'suppressed'->>'type', 80), left(d->>'origin', 40))
  ));
  if v_det = '{}'::jsonb then v_det := null; end if;

  insert into em_eventos (svix_id, evento, tipo, origen, campana_id, contacto_id, correo_envio_id,
                          resend_email_id, enlace, detalle, cuando)
  values (p_svix_id, left(v_type, 60), v_tipo, v_origen, v_camp, v_cont, v_envio,
          v_email_id, v_enlace, v_det, v_cuando)
  on conflict (svix_id) do nothing
  returning id into v_id;

  if v_id is null then
    return jsonb_build_object('estado', 'repetido');
  end if;

  -- Correos del pedido: dejar constancia de la entrega o del problema.
  if v_envio is not null then
    update correo_envios set
      entregado_en = case when v_tipo = 'entregado' then coalesce(entregado_en, v_cuando) else entregado_en end,
      rebote_en    = case when v_tipo in ('rebote','rebote_temporal','suprimido') then coalesce(rebote_en, v_cuando) else rebote_en end,
      rebote_tipo  = case when v_tipo = 'rebote' or v_tipo = 'suprimido' then case when v_tipo = 'rebote' then 'permanente' else 'suprimido' end
                          when v_tipo = 'rebote_temporal' and rebote_tipo is null then 'temporal'
                          else rebote_tipo end,
      queja_en     = case when v_tipo = 'queja' then coalesce(queja_en, v_cuando) else queja_en end
     where id = v_envio;
  end if;

  -- Supresion automatica (decisiones 3 y 4). El rebote TEMPORAL no suprime.
  if v_cont is not null then
    if v_tipo = 'rebote' then
      v_supr := em__suprimir(v_cont, 'rebotado', jsonb_build_object('evento', v_type, 'campana_id', v_camp, 'correo_envio_id', v_envio, 'detalle', v_det));
    elsif v_tipo = 'suprimido' then
      v_supr := em__suprimir(v_cont, 'rebotado', jsonb_build_object('evento', v_type, 'motivo', 'Suprimida por Resend', 'campana_id', v_camp, 'detalle', v_det));
    elsif v_tipo = 'supresion' then
      v_supr := em__suprimir(v_cont, case when coalesce(d->>'origin', '') ~* 'complain' then 'queja' else 'rebotado' end,
                             jsonb_build_object('evento', v_type, 'motivo', 'Agregada a la lista de supresion de Resend', 'detalle', v_det));
    elsif v_tipo = 'queja' then
      v_supr := em__suprimir(v_cont, 'queja', jsonb_build_object('evento', v_type, 'campana_id', v_camp, 'correo_envio_id', v_envio));
    elsif v_tipo = 'baja' then
      v_supr := em__suprimir(v_cont, 'baja', jsonb_build_object('evento', v_type));
    end if;
  end if;

  -- Retencion: de vez en cuando (barato si no hay nada que depurar).
  if random() < 0.02 then perform em__depurar_eventos(); end if;

  return jsonb_build_object('estado', 'procesado', 'tipo', v_tipo, 'origen', v_origen, 'suprimio', v_supr);
end;
$$;

comment on function em_webhook_registrar(text, jsonb) is 'EM5: registra un aviso de Resend YA VERIFICADO (firma Svix) por la Edge Function em-webhook. Idempotente por svix_id. Aplica la supresion automatica (rebote permanente, supresion, queja, baja) con bitacora y actor NULL. Solo service_role.';

revoke execute on function em_webhook_registrar(text, jsonb) from public, anon, authenticated;
grant  execute on function em_webhook_registrar(text, jsonb) to service_role;

-- ------------------------------------------------------------
-- Atribucion aproximada (decision 1): ultimo clic, 7 dias.
-- ------------------------------------------------------------
create or replace function em__atribucion_aproximada()
returns table (pedido_id uuid, campana_id uuid, clic_cuando timestamptz)
language sql
stable
security definer
set search_path = public
as $$
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
       and p.utm_campaign is null
       and coalesce(p.creado, p.fecha_orden::timestamptz) >= c.cuando
       and p.fecha_orden between (c.cuando at time zone 'America/Bogota')::date
                             and (c.cuando at time zone 'America/Bogota')::date + 7
  )
  select pedido_id, campana_id, cuando from cand where rn = 1;
$$;

revoke execute on function em__atribucion_aproximada() from public, anon, authenticated;

-- Bajas por campana (decision 2): la ultima campana recibida antes de la baja.
create or replace function em__bajas_por_campana()
returns table (contacto_id uuid, campana_id uuid, cuando timestamptz)
language sql
stable
security definer
set search_path = public
as $$
  with b as (
    select e.contacto_id, min(e.cuando) as cuando
      from em_eventos e where e.tipo = 'baja' and e.contacto_id is not null
     group by e.contacto_id
  )
  select b.contacto_id,
         (select d.campana_id
            from em_campana_destinatarios d join em_campanas c on c.id = d.campana_id
           where d.contacto_id = b.contacto_id and d.estado = 'listo' and c.resend_broadcast_id is not null
             and coalesce(c.enviada_en, c.programada_para) <= b.cuando
           order by coalesce(c.enviada_en, c.programada_para) desc limit 1),
         b.cuando
    from b;
$$;

revoke execute on function em__bajas_por_campana() from public, anon, authenticated;

-- ------------------------------------------------------------
-- Calculo de resultados de una campana (interno, sin guardia).
-- ------------------------------------------------------------
create or replace function em__resultados_calc(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_c em_campanas%rowtype;
  v jsonb;
begin
  select * into v_c from em_campanas where id = p_id;
  if not found then return null; end if;

  with ev as (
    select e.*, coalesce(e.contacto_id::text, e.resend_email_id, e.id::text) as quien
      from em_eventos e where e.campana_id = p_id
  ), exacta as (
    select p.id, p.total, p.fecha_orden, cl.nombre, 'exacta'::text as tipo
      from pedidos p join clientes cl on cl.id = p.customer_id
     where p.utm_campaign = v_c.utm_campaign and not p.anulado
  ), aprox as (
    select p.id, p.total, p.fecha_orden, cl.nombre, 'aproximada'::text as tipo
      from em__atribucion_aproximada() a
      join pedidos p on p.id = a.pedido_id
      join clientes cl on cl.id = p.customer_id
     where a.campana_id = p_id
  ), ventas as (select * from exacta union all select * from aprox)
  select jsonb_build_object(
    'destinatarios', (select count(*) from em_campana_destinatarios where campana_id = p_id and estado = 'listo'),
    'enviados',      (select count(distinct quien) from ev where tipo = 'enviado'),
    'entregados',    (select count(distinct quien) from ev where tipo = 'entregado'),
    'retrasados',    (select count(distinct quien) from ev where tipo = 'retrasado'),
    'rebotes',       (select count(distinct quien) from ev where tipo = 'rebote'),
    'rebotes_temporales', (select count(distinct quien) from ev where tipo = 'rebote_temporal'
                             and quien not in (select quien from ev where tipo in ('entregado','rebote'))),
    'suprimidos',    (select count(distinct quien) from ev where tipo = 'suprimido'),
    'fallidos',      (select count(distinct quien) from ev where tipo = 'fallido'),
    'quejas',        (select count(distinct quien) from ev where tipo = 'queja'),
    'aperturas',     (select count(distinct quien) from ev where tipo = 'apertura'),
    'clics_personas',(select count(distinct quien) from ev where tipo = 'clic'),
    'clics_total',   (select count(*) from ev where tipo = 'clic'),
    'bajas',         (select count(*) from em__bajas_por_campana() b where b.campana_id = p_id),
    'enlaces',       (select coalesce(jsonb_agg(jsonb_build_object('enlace', x.enlace, 'clics', x.n, 'personas', x.p) order by x.n desc, x.enlace), '[]')
                        from (select regexp_replace(regexp_replace(enlace, '([?&])utm_[a-z]+=[^&#]*', '\1', 'g'), '[?&]+(#|$)', '\1') as enlace,
                                     count(*) as n, count(distinct quien) as p
                                from ev where tipo = 'clic' and enlace is not null
                               group by 1 order by 2 desc limit 10) x),
    'ventas', jsonb_build_object(
       'exactas_n',     (select count(*) from exacta),
       'exactas_valor', (select coalesce(sum(total), 0) from exacta),
       'aprox_n',       (select count(*) from aprox),
       'aprox_valor',   (select coalesce(sum(total), 0) from aprox),
       'pedidos',       (select coalesce(jsonb_agg(jsonb_build_object('ref', correo_ref_pedido(id), 'fecha', fecha_orden,
                                     'total', total, 'cliente', nombre, 'tipo', tipo) order by fecha_orden desc), '[]')
                           from (select * from ventas order by fecha_orden desc limit 50) z)),
    'primer_evento', (select min(cuando) from ev),
    'ultimo_evento', (select max(recibido) from ev),
    'archivado', false
  ) into v;
  return v;
end;
$$;

revoke execute on function em__resultados_calc(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------
-- Retencion (decision 5): eventos > 13 meses se borran; antes, las campanas
-- afectadas congelan sus totales.
-- ------------------------------------------------------------
create or replace function em__depurar_eventos()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lim timestamptz := now() - interval '13 months';
  v_n int;
begin
  if not exists (select 1 from em_eventos where cuando < v_lim) then return 0; end if;
  insert into em_campana_resultados_archivo (campana_id, resultados)
  select c.id, em__resultados_calc(c.id) || jsonb_build_object('archivado', true)
    from em_campanas c
   where c.id in (select distinct campana_id from em_eventos where cuando < v_lim and campana_id is not null)
  on conflict (campana_id) do nothing;
  delete from em_eventos where cuando < v_lim;
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke execute on function em__depurar_eventos() from public, anon, authenticated;

-- ============================================================
-- RPC de lectura (modulo email_marketing)
-- ============================================================
create or replace function em_campana_resultados(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare v jsonb;
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  if not exists (select 1 from em_campanas where id = p_id) then raise exception 'EM_CAMPANA_NO_EXISTE'; end if;
  select resultados into v from em_campana_resultados_archivo where campana_id = p_id;
  if v is null then v := em__resultados_calc(p_id); end if;
  return v || jsonb_build_object('webhook_ultimo_evento', (select max(recibido) from em_eventos));
end;
$$;

create or replace function em_campanas_resultados_lista()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  return (
    with ev as (
      select campana_id, tipo, coalesce(contacto_id::text, resend_email_id, id::text) as quien
        from em_eventos where campana_id is not null
    ), por as (
      select campana_id,
             count(distinct quien) filter (where tipo = 'entregado') as entregados,
             count(distinct quien) filter (where tipo = 'clic') as clics
        from ev group by campana_id
    ), ped as (
      select c.id as campana_id, count(p.id) as pedidos
        from em_campanas c join pedidos p on p.utm_campaign = c.utm_campaign and not p.anulado group by c.id
      union all
      select campana_id, count(*) from em__atribucion_aproximada() group by campana_id
    )
    select coalesce(jsonb_object_agg(c.id, jsonb_build_object(
             'entregados', coalesce(a.resultados->'entregados', to_jsonb(coalesce(por.entregados, 0))),
             'clics', coalesce(a.resultados->'clics_personas', to_jsonb(coalesce(por.clics, 0))),
             'pedidos', coalesce(to_jsonb((a.resultados->'ventas'->>'exactas_n')::int + (a.resultados->'ventas'->>'aprox_n')::int),
                                 to_jsonb(coalesce((select sum(pedidos) from ped where ped.campana_id = c.id), 0))))), '{}')
      from em_campanas c
      left join por on por.campana_id = c.id
      left join em_campana_resultados_archivo a on a.campana_id = c.id
     where c.resend_broadcast_id is not null
  );
end;
$$;

-- Salud de la lista contra los limites de Resend (rebotes < 4 %, spam < 0,08 %).
create or replace function em_salud_lista()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  return (
    with ev as (
      select tipo, origen, coalesce(contacto_id::text, correo_envio_id::text, resend_email_id, id::text) as quien,
             coalesce(campana_id::text, correo_envio_id::text, '') as pieza
        from em_eventos where cuando >= now() - interval '60 days' and origen in ('campana','pedido')
    ), base as (
      select
        (select count(*) from em_campana_destinatarios d join em_campanas c on c.id = d.campana_id
          where d.estado = 'listo' and c.resend_broadcast_id is not null
            and coalesce(c.enviada_en, c.programada_para) >= now() - interval '60 days'
            and coalesce(c.enviada_en, c.programada_para) <= now())
        + (select count(*) from correo_envios where estado = 'enviado' and not es_prueba and creado >= now() - interval '60 days') as enviados,
        (select count(distinct (pieza, quien)) from ev where tipo = 'entregado') as entregados,
        (select count(distinct (pieza, quien)) from ev where tipo = 'rebote') as rebotes,
        (select count(distinct (pieza, quien)) from ev where tipo = 'queja') as quejas
    )
    select jsonb_build_object(
      'periodo_dias', 60,
      'enviados', enviados, 'entregados', entregados, 'rebotes', rebotes, 'quejas', quejas,
      'tasa_rebote', case when enviados > 0 then round(100.0 * rebotes / enviados, 2) end,
      'tasa_queja',  case when enviados > 0 then round(100.0 * quejas / enviados, 3) end,
      'limite_rebote', 4, 'limite_queja', 0.08,
      'ultimo_evento', (select max(recibido) from em_eventos),
      'suprimidos_auto_30d', (select count(*) from em_consentimiento_bitacora
                               where actor is null and accion in ('rebote','queja','baja')
                                 and detalle->>'origen' = 'resend_webhook' and cuando >= now() - interval '30 days')
    ) from base
  );
end;
$$;

-- Campanas recibidas por un contacto (ficha).
create or replace function em_contacto_campanas(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  return (select coalesce(jsonb_agg(x order by x->>'cuando' desc), '[]') from (
    select jsonb_build_object(
      'campana_id', c.id, 'nombre', c.nombre_interno, 'asunto', c.asunto,
      'cuando', coalesce(c.enviada_en, c.programada_para),
      'eventos', (select coalesce(jsonb_agg(distinct e.tipo), '[]') from em_eventos e where e.campana_id = c.id and e.contacto_id = p_id)
    ) as x
      from em_campana_destinatarios d join em_campanas c on c.id = d.campana_id
     where d.contacto_id = p_id and d.estado = 'listo' and c.resend_broadcast_id is not null
     order by coalesce(c.enviada_en, c.programada_para) desc
     limit 30) s);
end;
$$;

-- ------------------------------------------------------------
-- em_correos_seguimiento: misma firma de entrada, + columna "entrega".
-- (Cambia el tipo de retorno: hay que recrearla.)
-- ------------------------------------------------------------
drop function if exists em_correos_seguimiento(text, text, text, integer);
create function em_correos_seguimiento(
  p_etapa  text default null,
  p_estado text default null,
  p_buscar text default null,
  p_limite integer default 200
)
returns table (
  id uuid, creado timestamptz, etapa text, estado text, destinatario text,
  asunto text, es_prueba boolean, es_reenvio boolean, error text,
  pedido_ref text, cliente_nombre text, entrega text, entrega_en timestamptz
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
           cl.nombre,
           case when e.queja_en is not null then 'queja'
                when e.rebote_tipo in ('permanente','suprimido') then 'rebote'
                when e.entregado_en is not null then 'entregado'
                when e.rebote_tipo = 'temporal' then 'retrasado' end,
           coalesce(e.queja_en, e.rebote_en, e.entregado_en)
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

-- ------------------------------------------------------------
-- Grants (nominales)
-- ------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'em_campana_resultados(uuid)',
    'em_campanas_resultados_lista()',
    'em_salud_lista()',
    'em_contacto_campanas(uuid)',
    'em_correos_seguimiento(text, text, text, integer)'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end $$;
