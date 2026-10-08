-- ============================================================
-- MAGANDHI · METRICAS · TRAMO M1 (captura web EM7 + capa de datos compartida)
-- ------------------------------------------------------------
-- Diseno: docs/PLANO-METRICAS.md (y §5 de docs/PLANO-EMAIL-MARKETING.md).
--
-- (A) CAPTURA WEB (EM7). La tienda envia eventos minimos SOLO de quien acepto
--     el aviso de analitica: pagina_vista, producto_visto, clic_comprar,
--     checkout_iniciado, compra (F2) y llegada_campana. Cada evento lleva un id
--     de visitante ALEATORIO (sin nombre ni correo), el ORIGEN ya clasificado
--     (directo, email, instagram...; nunca la URL de procedencia) y el tipo de
--     dispositivo. La IP NO se guarda: solo un hash con sal diaria, en una tabla
--     aparte, para limitar abuso. Retencion: 13 meses.
--     Escritura: solo mt_registrar_eventos (service_role, Edge Function
--     tienda-eventos). Interruptor: em_config.analitica_activa (admin, exige la
--     politica registrada).
--
-- (B) CAPA DE DATOS COMPARTIDA. Funciones mt_* que devuelven series y KPIs YA
--     CALCULADOS. Las usa el area Metricas y cualquier software interno que los
--     necesite (Marketing, Ventas): todos ven el mismo numero. Solo agregados,
--     sin datos personales. Guardia: tiene_acceso_datos_metricas() =
--     modulo metricas O marketing O ventas (admin siempre).
--
-- Zona horaria de los dias y horas: America/Bogota.
-- Forward e idempotente. REQUISITO: despues de 20261015000000.
-- ============================================================

-- ------------------------------------------------------------
-- Acceso
-- ------------------------------------------------------------
create or replace function tiene_acceso_metricas()
returns boolean language sql stable security definer set search_path = public as $$
  select tiene_modulo('metricas');
$$;
create or replace function tiene_acceso_datos_metricas()
returns boolean language sql stable security definer set search_path = public as $$
  select tiene_modulo('metricas') or tiene_modulo('marketing') or tiene_modulo('ventas');
$$;
comment on function tiene_acceso_metricas() is 'Area Metricas: admin o modulo metricas.';
comment on function tiene_acceso_datos_metricas() is 'Capa de datos de Metricas (agregados sin PII): la consumen el area Metricas y los softwares de Marketing y Ventas.';

-- ------------------------------------------------------------
-- (A) Eventos de la tienda
-- ------------------------------------------------------------
create table if not exists tienda_eventos (
  id           bigint generated always as identity primary key,
  visitante    text not null check (visitante ~ '^[A-Za-z0-9_-]{16,40}$'),
  sesion       text not null check (sesion ~ '^[A-Za-z0-9_-]{8,40}$'),
  tipo         text not null check (tipo in ('pagina_vista','producto_visto','clic_comprar','checkout_iniciado','compra','llegada_campana')),
  ruta         text check (ruta is null or (char_length(ruta) <= 120 and ruta ~ '^/')),
  slug         text check (slug is null or slug ~ '^[a-z0-9-]{1,120}$'),
  origen       text check (origen is null or origen in ('directo','email','instagram','facebook','whatsapp','buscador','otro_sitio')),
  entrada      boolean not null default false,
  utm_campaign text check (utm_campaign is null or utm_campaign ~ '^[a-z0-9-]{1,60}$'),
  dispositivo  text check (dispositivo is null or dispositivo in ('movil','tablet','pc')),
  cuando       timestamptz not null default now()
);

create index if not exists idx_te_cuando on tienda_eventos (cuando);
create index if not exists idx_te_tipo_cuando on tienda_eventos (tipo, cuando);
create index if not exists idx_te_slug on tienda_eventos (slug, cuando) where slug is not null;

comment on table tienda_eventos is 'EM7 · analitica PROPIA de magandhi.com (sin Meta ni Google). Solo de quien acepto el aviso. visitante = id aleatorio del navegador, sin nombre ni correo. Sin IP ni URL de procedencia (solo el origen clasificado). Retencion 13 meses. Escribe solo mt_registrar_eventos (service_role).';

create table if not exists tienda_eventos_limite (
  ip_hash text not null,
  hora    timestamptz not null,
  n       integer not null default 0,
  primary key (ip_hash, hora)
);
comment on table tienda_eventos_limite is 'EM7 · limite de eventos por hora por hash de IP (sal diaria). Nunca la IP. Se purga a las 48 h.';

alter table tienda_eventos enable row level security;
alter table tienda_eventos_limite enable row level security;
-- Sin policies: nadie lee las filas crudas. El panel ve agregados por RPC.

-- Interruptor de la analitica (columna ya existe en em_config desde EM1).
create or replace function mt_config_analitica(p_activa boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not ((tiene_acceso_metricas() or tiene_acceso_email_marketing()) and em__es_admin()) then raise exception 'MT_SIN_ACCESO'; end if;
  if coalesce(p_activa, false) and not (select politica_publicada from em_config where id) then raise exception 'MT_POLITICA_PENDIENTE'; end if;
  update em_config set analitica_activa = coalesce(p_activa, false), actualizado = now(), actualizado_por = auth.uid() where id;
  return jsonb_build_object('analitica_activa', coalesce(p_activa, false));
end;
$$;

create or replace function mt_publico_config()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('activa', c.analitica_activa and c.politica_publicada, 'politica_version', c.politica_version)
    from em_config c where c.id;
$$;

-- Registra un lote (max 30) de eventos YA LIMPIOS por la Edge Function.
create or replace function mt_registrar_eventos(p_visitante text, p_sesion text, p_eventos jsonb, p_ip_hash text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  e jsonb;
  v_ok int := 0;
  v_desc int := 0;
  v_n int;
  v_hora timestamptz := date_trunc('hour', now());
  v_cuando timestamptz;
begin
  if not (select analitica_activa and politica_publicada from em_config where id) then raise exception 'MT_ANALITICA_APAGADA'; end if;
  if p_visitante is null or p_visitante !~ '^[A-Za-z0-9_-]{16,40}$' or p_sesion is null or p_sesion !~ '^[A-Za-z0-9_-]{8,40}$' then
    raise exception 'MT_VISITANTE_INVALIDO';
  end if;
  if p_eventos is null or jsonb_typeof(p_eventos) <> 'array' or jsonb_array_length(p_eventos) = 0 then raise exception 'MT_EVENTOS_INVALIDOS'; end if;
  if jsonb_array_length(p_eventos) > 30 then raise exception 'MT_EVENTOS_INVALIDOS'; end if;

  if p_ip_hash is not null then
    insert into tienda_eventos_limite (ip_hash, hora, n) values (left(p_ip_hash, 64), v_hora, jsonb_array_length(p_eventos))
    on conflict (ip_hash, hora) do update set n = tienda_eventos_limite.n + excluded.n
    returning n into v_n;
    if v_n > 600 then raise exception 'MT_DEMASIADOS_EVENTOS'; end if;
  end if;

  for e in select * from jsonb_array_elements(p_eventos) loop
    begin
      v_cuando := coalesce(em__ts(e->>'cuando'), now());
      -- El reloj del navegador puede mentir: solo se acepta hasta 10 min atras
      -- y nada en el futuro.
      if v_cuando > now() or v_cuando < now() - interval '10 minutes' then v_cuando := now(); end if;
      insert into tienda_eventos (visitante, sesion, tipo, ruta, slug, origen, entrada, utm_campaign, dispositivo, cuando)
      values (p_visitante, p_sesion, e->>'tipo', nullif(left(e->>'ruta', 120), ''), nullif(e->>'slug', ''), nullif(e->>'origen', ''),
              coalesce((e->>'entrada')::boolean, false), nullif(e->>'utm_campaign', ''), nullif(e->>'dispositivo', ''), v_cuando);
      v_ok := v_ok + 1;
    exception when check_violation or invalid_text_representation then
      v_desc := v_desc + 1;  -- un evento malo no tumba el lote
    end;
  end loop;

  if random() < 0.01 then
    delete from tienda_eventos where cuando < now() - interval '13 months';
    delete from tienda_eventos_limite where hora < now() - interval '48 hours';
  end if;
  return jsonb_build_object('aceptados', v_ok, 'descartados', v_desc);
end;
$$;

comment on function mt_registrar_eventos(text, text, jsonb, text) is 'EM7: registra hasta 30 eventos de un visitante. Exige analitica activa + politica registrada. Lista blanca por CHECK de la tabla (un evento invalido se descarta sin tumbar el lote). Limite 600 eventos/hora por hash de IP. Purga 13 meses. Solo service_role.';

-- ------------------------------------------------------------
-- (B) Capa de datos compartida
-- ------------------------------------------------------------
create or replace function mt__nombre_producto(p_slug text)
returns text language sql stable security definer set search_path = public as $$
  select coalesce((select nombre from campana_producto where slug = p_slug order by publicado desc limit 1), p_slug);
$$;
revoke execute on function mt__nombre_producto(text) from public, anon, authenticated;

-- EN VIVO: lo que pasa ahora (para refrescar cada 30 s).
create or replace function mt_en_vivo()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_hoy date := (now() at time zone 'America/Bogota')::date;
begin
  if not tiene_acceso_datos_metricas() then raise exception 'MT_SIN_ACCESO'; end if;
  return jsonb_build_object(
    'ahora', now(),
    'analitica_activa', (select analitica_activa and politica_publicada from em_config where id),
    'visitantes_5m',  (select count(distinct visitante) from tienda_eventos where cuando >= now() - interval '5 minutes'),
    'visitantes_30m', (select count(distinct visitante) from tienda_eventos where cuando >= now() - interval '30 minutes'),
    'visitantes_hoy', (select count(distinct visitante) from tienda_eventos where (cuando at time zone 'America/Bogota')::date = v_hoy),
    'vistas_hoy',     (select count(*) from tienda_eventos where tipo = 'pagina_vista' and (cuando at time zone 'America/Bogota')::date = v_hoy),
    'pedidos_hoy',    (select count(*) from pedidos where not anulado and fecha_orden = v_hoy),
    'ingresos_hoy',   (select coalesce(sum(total), 0) from pedidos where not anulado and fecha_orden = v_hoy),
    'pedidos_mismo_dia_semana_pasada', (select count(*) from pedidos where not anulado and fecha_orden = v_hoy - 7),
    'ingresos_mismo_dia_semana_pasada', (select coalesce(sum(total), 0) from pedidos where not anulado and fecha_orden = v_hoy - 7),
    'por_hora', (select coalesce(jsonb_agg(jsonb_build_object('h', h,
                   'visitantes', (select count(distinct visitante) from tienda_eventos
                                   where (cuando at time zone 'America/Bogota')::date = v_hoy and extract(hour from cuando at time zone 'America/Bogota') = h),
                   'pedidos', (select count(*) from pedidos where not anulado and fecha_orden = v_hoy
                                   and extract(hour from creado at time zone 'America/Bogota') = h)) order by h), '[]')
                 from generate_series(0, 23) h),
    'activos_por_pagina', (select coalesce(jsonb_agg(jsonb_build_object('ruta', ruta, 'slug', slug, 'nombre', case when slug is not null then mt__nombre_producto(slug) end, 'visitantes', n) order by n desc), '[]')
                 from (select ruta, max(slug) as slug, count(distinct visitante) n from tienda_eventos
                        where cuando >= now() - interval '30 minutes' and tipo = 'pagina_vista' group by ruta order by 3 desc limit 6) x),
    'eventos', (select coalesce(jsonb_agg(jsonb_build_object('tipo', tipo, 'ruta', ruta, 'slug', slug,
                   'nombre', case when slug is not null then mt__nombre_producto(slug) end,
                   'origen', origen, 'dispositivo', dispositivo, 'cuando', cuando) order by cuando desc), '[]')
                 from (select * from tienda_eventos where cuando >= now() - interval '24 hours' order by cuando desc limit 14) x),
    'pedidos', (select coalesce(jsonb_agg(jsonb_build_object('ref', correo_ref_pedido(id), 'total', total, 'canal', canal,
                   'ciudad', nullif(btrim(ciudad), ''), 'estado', estado, 'creado', creado,
                   'unidades', (select coalesce(sum(cantidad), 0) from pedido_items pi where pi.pedido_id = p.id)) order by creado desc), '[]')
                 from (select * from pedidos where not anulado order by creado desc limit 8) p)
  );
end;
$$;

-- VENTAS por periodo (+ periodo anterior de igual largo para comparar).
create or replace function mt_ventas(p_desde date, p_hasta date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_d date := coalesce(p_desde, (now() at time zone 'America/Bogota')::date - 29);
  v_h date := coalesce(p_hasta, (now() at time zone 'America/Bogota')::date);
  v_len int;
  v_pd date; v_ph date;
begin
  if not tiene_acceso_datos_metricas() then raise exception 'MT_SIN_ACCESO'; end if;
  if v_h < v_d then raise exception 'MT_PERIODO_INVALIDO'; end if;
  if v_h - v_d > 730 then raise exception 'MT_PERIODO_INVALIDO'; end if;
  v_len := v_h - v_d + 1; v_ph := v_d - 1; v_pd := v_d - v_len;

  return (
    with ped as (select * from pedidos where not anulado and fecha_orden between v_d and v_h),
         ant as (select * from pedidos where not anulado and fecha_orden between v_pd and v_ph),
         it as (
           select pi.*, ped.fecha_orden, coalesce(cp.nombre, pr.nombre) as nombre
             from pedido_items pi join ped on ped.id = pi.pedido_id
             join productos pr on pr.id = pi.product_id
             left join lateral (select c2.nombre from campana_producto c2 where c2.product_id_ref = pi.product_id order by c2.publicado desc limit 1) cp on true),
         primeras as (select customer_id, min(fecha_orden) as primera from pedidos where not anulado group by customer_id)
    select jsonb_build_object(
      'desde', v_d, 'hasta', v_h, 'anterior', jsonb_build_object('desde', v_pd, 'hasta', v_ph),
      'totales', jsonb_build_object(
         'pedidos', (select count(*) from ped), 'ingresos', (select coalesce(sum(total), 0) from ped),
         'unidades', (select coalesce(sum(cantidad), 0) from it),
         'ticket', (select coalesce(round(avg(total)), 0) from ped),
         'clientes', (select count(distinct customer_id) from ped),
         'clientes_nuevos', (select count(distinct p.customer_id) from ped p join primeras f on f.customer_id = p.customer_id where f.primera between v_d and v_h)),
      'totales_anterior', jsonb_build_object(
         'pedidos', (select count(*) from ant), 'ingresos', (select coalesce(sum(total), 0) from ant),
         'unidades', (select coalesce(sum(pi.cantidad), 0) from pedido_items pi join ant on ant.id = pi.pedido_id),
         'ticket', (select coalesce(round(avg(total)), 0) from ant),
         'clientes', (select count(distinct customer_id) from ant)),
      'serie', (select coalesce(jsonb_agg(jsonb_build_object('fecha', g::date,
                  'pedidos', (select count(*) from ped where fecha_orden = g::date),
                  'ingresos', (select coalesce(sum(total), 0) from ped where fecha_orden = g::date)) order by g), '[]')
                from generate_series(v_d, v_h, interval '1 day') g),
      'serie_anterior', (select coalesce(jsonb_agg(jsonb_build_object('fecha', g::date,
                  'ingresos', (select coalesce(sum(total), 0) from ant where fecha_orden = g::date)) order by g), '[]')
                from generate_series(v_pd, v_ph, interval '1 day') g),
      'por_canal', (select coalesce(jsonb_object_agg(canal, jsonb_build_object('pedidos', n, 'ingresos', s)), '{}')
                    from (select canal, count(*) n, sum(total) s from ped group by canal) x),
      'productos', (select coalesce(jsonb_agg(jsonb_build_object('nombre', nombre, 'unidades', u, 'ingresos', s, 'pedidos', np) order by s desc), '[]')
                    from (select nombre, sum(cantidad) u, sum(subtotal) s, count(distinct pedido_id) np from it group by nombre order by 3 desc limit 10) x),
      'ciudades', (select coalesce(jsonb_agg(jsonb_build_object('ciudad', ciudad, 'pedidos', n, 'ingresos', s) order by n desc, s desc), '[]')
                    from (select coalesce(initcap(lower(nullif(btrim(ciudad), ''))), 'Sin ciudad') ciudad, count(*) n, sum(total) s from ped group by 1 order by 2 desc limit 8) x),
      'calor', (select coalesce(jsonb_agg(jsonb_build_object('d', d, 'h', h, 'n', n)), '[]')
                from (select extract(isodow from creado at time zone 'America/Bogota')::int d,
                             extract(hour from creado at time zone 'America/Bogota')::int h, count(*) n
                        from ped group by 1, 2) x),
      'pct_hora_exacta', (select coalesce(round(100.0 * count(*) filter (where canal = 'web') / nullif(count(*), 0)), 0) from ped)
    )
  );
end;
$$;

-- TIENDA (interaccion web) por periodo.
create or replace function mt_tienda(p_desde date, p_hasta date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_d date := coalesce(p_desde, (now() at time zone 'America/Bogota')::date - 29);
  v_h date := coalesce(p_hasta, (now() at time zone 'America/Bogota')::date);
  v_len int; v_pd date; v_ph date;
begin
  if not tiene_acceso_datos_metricas() then raise exception 'MT_SIN_ACCESO'; end if;
  if v_h < v_d or v_h - v_d > 730 then raise exception 'MT_PERIODO_INVALIDO'; end if;
  v_len := v_h - v_d + 1; v_ph := v_d - 1; v_pd := v_d - v_len;

  return (
    with ev as (select *, (cuando at time zone 'America/Bogota') as local from tienda_eventos
                 where (cuando at time zone 'America/Bogota')::date between v_d and v_h),
         an as (select * from tienda_eventos where (cuando at time zone 'America/Bogota')::date between v_pd and v_ph),
         ses as (select sesion, (array_agg(origen order by cuando) filter (where origen is not null))[1] as origen,
                        (array_agg(dispositivo order by cuando) filter (where dispositivo is not null))[1] as dispositivo
                   from ev group by sesion)
    select jsonb_build_object(
      'desde', v_d, 'hasta', v_h,
      'analitica_activa', (select analitica_activa and politica_publicada from em_config where id),
      'primer_evento', (select min(cuando) from tienda_eventos),
      'totales', jsonb_build_object(
        'visitantes', (select count(distinct visitante) from ev),
        'sesiones', (select count(distinct sesion) from ev),
        'vistas', (select count(*) from ev where tipo = 'pagina_vista'),
        'productos_vistos', (select count(*) from ev where tipo = 'producto_visto'),
        'vistas_por_sesion', (select round(count(*) filter (where tipo = 'pagina_vista')::numeric / nullif(count(distinct sesion), 0), 1) from ev)),
      'totales_anterior', jsonb_build_object(
        'visitantes', (select count(distinct visitante) from an),
        'sesiones', (select count(distinct sesion) from an),
        'vistas', (select count(*) from an where tipo = 'pagina_vista'),
        'productos_vistos', (select count(*) from an where tipo = 'producto_visto')),
      'serie', (select coalesce(jsonb_agg(jsonb_build_object('fecha', g::date,
                  'visitantes', (select count(distinct visitante) from ev where local::date = g::date),
                  'vistas', (select count(*) from ev where tipo = 'pagina_vista' and local::date = g::date)) order by g), '[]')
                from generate_series(v_d, v_h, interval '1 day') g),
      'embudo', jsonb_build_object(
        'visitantes', (select count(distinct visitante) from ev),
        'vieron_producto', (select count(distinct visitante) from ev where tipo = 'producto_visto'),
        'clic_comprar', (select count(distinct visitante) from ev where tipo = 'clic_comprar'),
        'checkout', (select count(distinct visitante) from ev where tipo = 'checkout_iniciado'),
        'compra', (select count(distinct visitante) from ev where tipo = 'compra')),
      'productos', (select coalesce(jsonb_agg(jsonb_build_object('slug', slug, 'nombre', mt__nombre_producto(slug), 'vistas', v, 'visitantes', u, 'clic_comprar', c) order by v desc), '[]')
                    from (select slug, count(*) filter (where tipo = 'producto_visto') v, count(distinct visitante) filter (where tipo = 'producto_visto') u,
                                 count(distinct visitante) filter (where tipo = 'clic_comprar') c
                            from ev where slug is not null group by slug having count(*) filter (where tipo = 'producto_visto') > 0 order by 2 desc limit 10) x),
      'paginas', (select coalesce(jsonb_agg(jsonb_build_object('ruta', ruta, 'vistas', n, 'visitantes', u) order by n desc), '[]')
                    from (select ruta, count(*) n, count(distinct visitante) u from ev where tipo = 'pagina_vista' and ruta is not null group by ruta order by 2 desc limit 10) x),
      'origenes', (select coalesce(jsonb_agg(jsonb_build_object('origen', coalesce(origen, 'directo'), 'sesiones', n) order by n desc), '[]')
                    from (select coalesce(origen, 'directo') origen, count(*) n from ses group by 1) x),
      'dispositivos', (select coalesce(jsonb_agg(jsonb_build_object('dispositivo', coalesce(dispositivo, 'pc'), 'sesiones', n) order by n desc), '[]')
                    from (select coalesce(dispositivo, 'pc') dispositivo, count(*) n from ses group by 1) x),
      'campanas', (select coalesce(jsonb_agg(jsonb_build_object('utm', e.utm_campaign, 'nombre', c.nombre_interno, 'visitantes', e.u) order by e.u desc), '[]')
                    from (select utm_campaign, count(distinct visitante) u from ev where utm_campaign is not null group by 1 order by 2 desc limit 8) e
                    left join em_campanas c on c.utm_campaign = e.utm_campaign),
      'calor', (select coalesce(jsonb_agg(jsonb_build_object('d', d, 'h', h, 'n', n)), '[]')
                from (select extract(isodow from local)::int d, extract(hour from local)::int h, count(distinct sesion) n
                        from ev group by 1, 2) x)
    )
  );
end;
$$;

-- ------------------------------------------------------------
-- Grants
-- ------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array['mt_publico_config()', 'mt_registrar_eventos(text, text, jsonb, text)'] loop
    execute format('revoke execute on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
  foreach f in array array['tiene_acceso_metricas()', 'tiene_acceso_datos_metricas()', 'mt_config_analitica(boolean)',
                           'mt_en_vivo()', 'mt_ventas(date, date)', 'mt_tienda(date, date)'] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end $$;
