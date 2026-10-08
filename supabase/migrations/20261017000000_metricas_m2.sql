-- ============================================================
-- MAGANDHI · METRICAS · TRAMO M2 (capa de datos: Email, Opiniones, Inventario)
-- ------------------------------------------------------------
-- Diseno: docs/PLANO-METRICAS.md §4 y §5.
--
-- Agrega tres funciones a la CAPA DE DATOS COMPARTIDA mt_*: devuelven series y
-- KPIs YA CALCULADOS, solo agregados y SIN datos personales. Igual que M1,
-- cada una esta guardada por tiene_acceso_datos_metricas() (modulo metricas O
-- marketing O ventas; admin siempre), es security definer y usa la zona
-- horaria America/Bogota.
--
-- POR QUE AQUI Y NO LLAMAR LAS FUNCIONES DEL AREA DE EMAIL: em_resumen,
-- em_salud_lista y em_campanas_resultados_lista tienen OTRA guardia
-- (tiene_acceso_email_marketing); un usuario de Metricas que no tenga el
-- modulo email_marketing seria rechazado por esa guardia aunque mt_email sea
-- security definer (el guardia evalua auth.uid() del llamante real). Por eso
-- mt_email reproduce el calculo AQUI, con la guardia de Metricas, para que el
-- mismo numero este disponible a quien tenga metricas/marketing/ventas.
--
--   mt_email(desde, hasta)  Crecimiento de la lista (altas/bajas por dia y en
--                           el periodo, estados, temas), campanas lado a lado
--                           (entregados, clics, pedidos) y salud de la lista
--                           frente a los limites de Resend (ventana fija 60 d).
--   mt_opiniones(desde, hasta)  Promedio REAL siempre con el total N (sin
--                           suavizado bayesiano: regla del dueno), distribucion
--                           por estrellas, opiniones por mes, cobertura (% de
--                           pedidos entregados con opinion) y productos por
--                           promedio. Excluye es_prueba y oculta.
--   mt_inventario()         Existencias por producto, unidades vendidas por
--                           semana, dias de inventario (estimado) y alertas de
--                           bajo stock. Es una foto del AHORA (sin periodo).
--
-- Forward e idempotente. REQUISITO: despues de 20261016000000.
-- ============================================================

-- ------------------------------------------------------------
-- mt_email: crecimiento de la lista + campanas + salud
-- ------------------------------------------------------------
create or replace function mt_email(p_desde date, p_hasta date)
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
    with bit as (
      select accion, (cuando at time zone 'America/Bogota')::date as dia
        from em_consentimiento_bitacora
    ),
    ev as (
      select campana_id, tipo, coalesce(contacto_id::text, resend_email_id, id::text) as quien
        from em_eventos where campana_id is not null
    ),
    por as (
      select campana_id,
             count(distinct quien) filter (where tipo = 'entregado') as entregados,
             count(distinct quien) filter (where tipo = 'clic') as clics
        from ev group by campana_id
    ),
    ped as (
      -- Mismo criterio que em_campanas_resultados_lista: exactas por utm +
      -- aproximadas por ultimo clic (7 dias). Numeros consistentes entre areas.
      select c.id as campana_id, count(p.id) as n
        from em_campanas c join pedidos p on p.utm_campaign = c.utm_campaign and not p.anulado
       group by c.id
      union all
      select campana_id, count(*) from em__atribucion_aproximada() group by campana_id
    )
    select jsonb_build_object(
      'desde', v_d, 'hasta', v_h, 'anterior', jsonb_build_object('desde', v_pd, 'hasta', v_ph),
      'lista', jsonb_build_object(
        'total',       (select count(*) from em_contactos),
        'suscritos',   (select count(*) from em_contactos where estado = 'suscrito'),
        'pendientes',  (select count(*) from em_contactos where estado = 'pendiente_confirmacion'),
        'vinculados',  (select count(*) from em_contactos where estado = 'suscrito' and customer_id is not null),
        'por_estado',  (select coalesce(jsonb_object_agg(estado, n), '{}')
                          from (select estado, count(*) n from em_contactos group by estado) e),
        'por_tema',    (select coalesce(jsonb_agg(jsonb_build_object('codigo', t.codigo, 'nombre', t.nombre,
                            'suscritos', (select count(*) from em_contactos c where c.estado = 'suscrito' and t.codigo = any(c.temas)))
                          order by t.orden), '[]') from em_temas t where t.activo),
        'altas',          (select count(*) from bit where accion in ('alta','reactivacion') and dia between v_d and v_h),
        'bajas',          (select count(*) from bit where accion = 'baja' and dia between v_d and v_h),
        'altas_anterior', (select count(*) from bit where accion in ('alta','reactivacion') and dia between v_pd and v_ph),
        'bajas_anterior', (select count(*) from bit where accion = 'baja' and dia between v_pd and v_ph)
      ),
      'serie', (select coalesce(jsonb_agg(jsonb_build_object('fecha', g::date,
                  'altas', (select count(*) from bit where accion in ('alta','reactivacion') and dia = g::date),
                  'bajas', (select count(*) from bit where accion = 'baja' and dia = g::date)) order by g), '[]')
                from generate_series(v_d, v_h, interval '1 day') g),
      'campanas', (select coalesce(jsonb_agg(jsonb_build_object(
                      'id', c.id, 'nombre', c.nombre_interno, 'asunto', c.asunto,
                      'enviada_en', coalesce(c.enviada_en, c.programada_para),
                      'destinatarios', c.audiencia_n,
                      'entregados', coalesce((a.resultados->>'entregados')::int, por.entregados, 0),
                      'clics', coalesce((a.resultados->>'clics_personas')::int, por.clics, 0),
                      'pedidos', coalesce((a.resultados->'ventas'->>'exactas_n')::int + (a.resultados->'ventas'->>'aprox_n')::int,
                                          (select coalesce(sum(n), 0) from ped where ped.campana_id = c.id))
                    ) order by coalesce(c.enviada_en, c.programada_para) desc), '[]')
                  from em_campanas c
                  left join por on por.campana_id = c.id
                  left join em_campana_resultados_archivo a on a.campana_id = c.id
                 where c.resend_broadcast_id is not null
                   and coalesce(c.enviada_en, c.programada_para) is not null
                   and (coalesce(c.enviada_en, c.programada_para) at time zone 'America/Bogota')::date between v_d and v_h),
      'salud', (
        with evs as (
          select tipo, coalesce(contacto_id::text, correo_envio_id::text, resend_email_id, id::text) as quien,
                 coalesce(campana_id::text, correo_envio_id::text, '') as pieza
            from em_eventos where cuando >= now() - interval '60 days' and origen in ('campana','pedido')
        ), base as (
          select
            (select count(*) from em_campana_destinatarios d join em_campanas c on c.id = d.campana_id
              where d.estado = 'listo' and c.resend_broadcast_id is not null
                and coalesce(c.enviada_en, c.programada_para) >= now() - interval '60 days'
                and coalesce(c.enviada_en, c.programada_para) <= now())
            + (select count(*) from correo_envios where estado = 'enviado' and not es_prueba and creado >= now() - interval '60 days') as enviados,
            (select count(distinct (pieza, quien)) from evs where tipo = 'entregado') as entregados,
            (select count(distinct (pieza, quien)) from evs where tipo = 'rebote') as rebotes,
            (select count(distinct (pieza, quien)) from evs where tipo = 'queja') as quejas
        )
        select jsonb_build_object(
          'periodo_dias', 60, 'enviados', enviados, 'entregados', entregados, 'rebotes', rebotes, 'quejas', quejas,
          'tasa_rebote', case when enviados > 0 then round(100.0 * rebotes / enviados, 2) end,
          'tasa_queja',  case when enviados > 0 then round(100.0 * quejas / enviados, 3) end,
          'limite_rebote', 4, 'limite_queja', 0.08,
          'suprimidos_auto_30d', (select count(*) from em_consentimiento_bitacora
                                   where actor is null and accion in ('rebote','queja','baja')
                                     and detalle->>'origen' = 'resend_webhook' and cuando >= now() - interval '30 days'))
        from base),
      'seguimiento', (select jsonb_build_object(
                        'enviados', count(*) filter (where estado = 'enviado'),
                        'fallidos', count(*) filter (where estado = 'fallido'))
                        from correo_envios where not es_prueba
                          and (creado at time zone 'America/Bogota')::date between v_d and v_h),
      'ultimo_evento', (select max(recibido) from em_eventos)
    )
  );
end;
$$;

comment on function mt_email(date, date) is 'Capa de datos Metricas · Email: crecimiento de la lista (altas/bajas por dia y periodo, estados, temas), campanas del periodo lado a lado (entregados, clics, pedidos exactos+aproximados, mismo criterio que el area de Email) y salud de la lista frente a los limites de Resend (ventana fija 60 d). Solo agregados. Guardia tiene_acceso_datos_metricas().';

-- ------------------------------------------------------------
-- mt_opiniones: promedio real + distribucion + cobertura + productos
-- ------------------------------------------------------------
create or replace function mt_opiniones(p_desde date, p_hasta date)
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
    -- "Real" = la opinion que cuenta: ni de prueba ni oculta (misma regla que
    -- la web y el panel de Opiniones).
    with op as (
      select o.pedido_id, o.product_id, o.estrellas, o.respuesta, o.creado,
             (o.creado at time zone 'America/Bogota')::date as dia
        from opiniones o where not o.es_prueba and not o.oculta
    ),
    opp as (select * from op where dia between v_d and v_h)
    select jsonb_build_object(
      'desde', v_d, 'hasta', v_h, 'anterior', jsonb_build_object('desde', v_pd, 'hasta', v_ph),
      'resumen', jsonb_build_object(
        'total',           (select count(*) from opp),
        'promedio',        (select round(avg(estrellas), 1) from opp),
        'con_respuesta',   (select count(*) from opp where respuesta is not null),
        'total_anterior',  (select count(*) from op where dia between v_pd and v_ph),
        'total_global',    (select count(*) from op),
        'promedio_global', (select round(avg(estrellas), 1) from op)),
      'distribucion', (select coalesce(jsonb_agg(jsonb_build_object('estrellas', s,
                          'n', (select count(*) from opp where estrellas = s)) order by s desc), '[]')
                        from generate_series(1, 5) s),
      'serie', (select coalesce(jsonb_agg(jsonb_build_object('fecha', g::date,
                  'n', (select count(*) from opp where dia = g::date)) order by g), '[]')
                from generate_series(v_d, v_h, interval '1 day') g),
      'por_mes', (select coalesce(jsonb_agg(jsonb_build_object(
                     'mes', to_char(g, 'YYYY-MM-01'),
                     'n', (select count(*) from op where date_trunc('month', dia) = g),
                     'promedio', (select round(avg(estrellas), 1) from op where date_trunc('month', dia) = g)) order by g), '[]')
                   from generate_series(date_trunc('month', (now() at time zone 'America/Bogota')::date) - interval '11 months',
                                        date_trunc('month', (now() at time zone 'America/Bogota')::date), interval '1 month') g),
      'cobertura', (select jsonb_build_object(
          'entregados',  count(*) filter (where p.estado = 'entregado'),
          'con_opinion', count(*) filter (where p.estado = 'entregado' and exists (select 1 from op where op.pedido_id = p.id)),
          'pct', case when count(*) filter (where p.estado = 'entregado') > 0
                      then round(100.0 * count(*) filter (where p.estado = 'entregado' and exists (select 1 from op where op.pedido_id = p.id))
                                 / count(*) filter (where p.estado = 'entregado')) end)
        from pedidos p where not p.anulado and p.fecha_orden between v_d and v_h),
      'productos', (select coalesce(jsonb_agg(jsonb_build_object('nombre', nombre, 'n', n, 'promedio', prom) order by prom desc, n desc), '[]')
                     from (select coalesce(cp.nombre, pr.nombre, 'Producto') nombre, count(*) n, round(avg(op.estrellas), 1) prom
                             from op
                             join productos pr on pr.id = op.product_id
                             left join lateral (select c2.nombre from campana_producto c2 where c2.product_id_ref = op.product_id order by c2.publicado desc limit 1) cp on true
                            group by 1 order by prom desc, n desc limit 10) x)
    )
  );
end;
$$;

comment on function mt_opiniones(date, date) is 'Capa de datos Metricas · Opiniones: promedio REAL siempre con el total N (sin suavizado bayesiano, regla del dueno), distribucion por estrellas, opiniones por dia y por mes (12 meses), cobertura (% de pedidos entregados con opinion) y productos por promedio. Excluye es_prueba y oculta. Solo agregados. Guardia tiene_acceso_datos_metricas().';

-- ------------------------------------------------------------
-- mt_inventario: existencias + rotacion + dias de inventario + alertas
-- ------------------------------------------------------------
create or replace function mt_inventario()
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
  return (
    with stock as (
      select p.id, p.sku, p.nombre, p.categoria, coalesce(p.stock_minimo, 0) as stock_minimo,
             p.activo, coalesce(p.costo_unitario, 0) as costo_unitario,
             coalesce(sum(case m.tipo
                            when 'entrada'        then  m.cantidad
                            when 'ajuste_entrada' then  m.cantidad
                            when 'salida'         then -m.cantidad
                            when 'ajuste_salida'  then -m.cantidad end), 0)::int as existencias
        from productos p
        left join movimientos_inventario m on m.product_id = p.id
       group by p.id
    ),
    venta30 as (
      -- Unidades vendidas por producto en los ultimos 30 dias (pedidos reales,
      -- no anulados). Alimenta "dias de inventario" (estimado).
      select pi.product_id, sum(pi.cantidad) as u
        from pedido_items pi join pedidos pe on pe.id = pi.pedido_id
       where not pe.anulado and pe.fecha_orden >= v_hoy - 29
       group by pi.product_id
    )
    select jsonb_build_object(
      'hoy', v_hoy,
      'totales', jsonb_build_object(
        'productos_activos', (select count(*) from stock where activo),
        'unidades_total',    (select coalesce(sum(existencias), 0) from stock where activo),
        'valor_costo',       (select coalesce(sum(existencias::bigint * costo_unitario), 0) from stock where activo),
        'bajo_stock',        (select count(*) from stock where activo and existencias <= stock_minimo),
        'agotados',          (select count(*) from stock where activo and existencias <= 0)),
      'productos', (select coalesce(jsonb_agg(jsonb_build_object(
            'nombre', s.nombre, 'sku', s.sku, 'existencias', s.existencias, 'stock_minimo', s.stock_minimo,
            'vendidas_30d', coalesce(v.u, 0),
            'dias_inventario', case when coalesce(v.u, 0) > 0 then round(s.existencias / (v.u / 30.0)) end,
            'bajo', s.existencias <= s.stock_minimo, 'agotado', s.existencias <= 0
          ) order by (s.existencias <= 0) desc, (s.existencias <= s.stock_minimo) desc, s.nombre), '[]')
        from stock s left join venta30 v on v.product_id = s.id where s.activo),
      'por_semana', (select coalesce(jsonb_agg(jsonb_build_object('semana', g::date,
            'unidades', (select coalesce(sum(pi.cantidad), 0) from pedido_items pi join pedidos pe on pe.id = pi.pedido_id
                           where not pe.anulado and pe.fecha_orden >= g::date and pe.fecha_orden < g::date + 7)) order by g), '[]')
        from generate_series(date_trunc('week', v_hoy::timestamp) - interval '11 weeks', date_trunc('week', v_hoy::timestamp), interval '1 week') g),
      'alertas', (select coalesce(jsonb_agg(jsonb_build_object('nombre', nombre, 'existencias', existencias,
            'stock_minimo', stock_minimo, 'agotado', existencias <= 0) order by existencias), '[]')
        from stock where activo and existencias <= stock_minimo)
    )
  );
end;
$$;

comment on function mt_inventario() is 'Capa de datos Metricas · Inventario: foto del AHORA. Existencias por producto (derivadas del libro), unidades vendidas en 30 dias, dias de inventario estimado (existencias / venta diaria promedio de 30 d), unidades vendidas por semana (12 semanas) y alertas de bajo stock (existencias <= stock_minimo). Solo agregados. Guardia tiene_acceso_datos_metricas().';

-- ------------------------------------------------------------
-- Grants: mismo patron que M1 (authenticated + service_role; nunca anon).
-- ------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array['mt_email(date, date)', 'mt_opiniones(date, date)', 'mt_inventario()'] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end $$;
