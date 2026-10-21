-- ============================================================================
-- MAGANDHI · PROMOCIONAR P5 · LECTURA COMERCIAL
-- ----------------------------------------------------------------------------
-- Forward sobre P3 + P4 + Métricas M1 + Email. Solo crea RPC de lectura:
-- no cambia tablas, gates, atribuciones, pedidos ni historia.
-- Estado en Git: construido; NO desplegado.
-- ============================================================================

begin;
set local search_path = public, pg_temp;
set local statement_timeout = '90s';
set local lock_timeout = '5s';

select pg_advisory_xact_lock(hashtextextended('promocionar-p5-instalacion-v1', 0));

do $baseline$
begin
  if to_regclass('public.atribucion_enlaces') is null
     or to_regclass('public.atribucion_clics_dia') is null
     or to_regclass('public.campana_producto') is null
     or to_regclass('public.tienda_eventos') is null
     or to_regclass('public.pagos_intencion') is null
     or to_regclass('public.pedidos') is null
     or to_regclass('public.em_campanas') is null
     or to_regclass('public.em_config') is null
     or to_regprocedure('public.em__atribucion_aproximada()') is null
     or to_regprocedure('public.tiene_acceso_marketing()') is null
     or to_regprocedure('public.tiene_acceso_datos_metricas()') is null
     or to_regprocedure('public.tiene_acceso_ventas()') is null then
    raise exception using errcode = 'P0001', message = 'P5_REQUIERE_BASELINE_P3_P4_M1_EMAIL_COMPLETO';
  end if;

  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'pagos_intencion'
       and column_name = 'atribucion_enlace_id'
  ) or not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'pedidos'
       and column_name = 'atribucion_enlace_id'
  ) then
    raise exception using errcode = 'P0001', message = 'P5_REQUIERE_COLUMNAS_P4';
  end if;

  if to_regprocedure('public.promocionar_p5_resultados(uuid,date,date)') is not null
     or to_regprocedure('public.promocionar_p5_resumen_metricas(date,date)') is not null
     or to_regprocedure('public.promocionar_p5_procedencia_pedidos(uuid[])') is not null
     or to_regclass('public.tienda_eventos_sesion_cuando_p5_idx') is not null then
    raise exception using errcode = 'P0001', message = 'P5_REQUIERE_AUSENCIA_LIMPIA';
  end if;

  if exists (
    select 1 from pg_roles r
     where r.rolname in ('anon', 'authenticated', 'service_role')
       and has_schema_privilege(r.rolname, 'public', 'CREATE')
  ) then
    raise exception using errcode = 'P0001', message = 'P5_SCHEMA_DEFINER_ESCRIBIBLE_POR_API';
  end if;
end;
$baseline$;

-- Índice de lectura para correlacionar eventos consentidos dentro de la sesión
-- sin barridos repetidos. No expone filas ni cambia su retención.
create index tienda_eventos_sesion_cuando_p5_idx
  on tienda_eventos (sesion, cuando desc, id desc);

-- Núcleo agregado privado. El UUID NULL significa todas las campañas y solo se
-- usa desde el wrapper de Métricas. Cada población se agrega antes de unirla.
create function promocionar_p5__agregado(
  p_desde date,
  p_hasta date,
  p_campana_producto_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_desde date := p_desde;
  v_hasta date := p_hasta;
  v_inicio timestamptz;
  v_fin_exclusivo timestamptz;
  v_corte_p3 date := ((statement_timestamp() at time zone 'America/Bogota')::date - interval '13 months')::date;
  v_compactado bigint := 0;
  v_clicks_detalle bigint := 0;
  v_clicks_vida bigint := 0;
  v_detalle_completo boolean := true;
  v_analitica_activa boolean := false;
  v_salida jsonb;
begin
  if v_desde is null or v_hasta is null or v_hasta < v_desde or v_hasta - v_desde > 730 then
    raise exception using errcode = '22023', message = 'P5_PERIODO_INVALIDO';
  end if;

  -- Fronteras civiles de Bogotá como timestamptz semiabiertos. Así los filtros
  -- usan los índices temporales directos y la proyección conserva el día local.
  v_inicio := v_desde::timestamp at time zone 'America/Bogota';
  v_fin_exclusivo := (v_hasta + 1)::timestamp at time zone 'America/Bogota';

  select coalesce(sum(e.total_aproximado_historico), 0)::bigint,
         coalesce(sum(e.total_aproximado_historico), 0)::bigint
           + coalesce((
               select sum(d.total)::bigint
                 from atribucion_clics_dia d
                 join atribucion_enlaces ex on ex.id = d.enlace_id
                where p_campana_producto_id is null
                   or ex.campana_producto_id = p_campana_producto_id
             ), 0)::bigint
    into v_compactado, v_clicks_vida
    from atribucion_enlaces e
   where p_campana_producto_id is null
      or e.campana_producto_id = p_campana_producto_id;

  select coalesce(sum(d.total), 0)::bigint into v_clicks_detalle
    from atribucion_clics_dia d
    join atribucion_enlaces e on e.id = d.enlace_id
   where d.fecha_colombia between v_desde and v_hasta
     and (p_campana_producto_id is null or e.campana_producto_id = p_campana_producto_id);

  v_detalle_completo := v_desde >= v_corte_p3 or v_compactado = 0;
  select coalesce(c.analitica_activa and c.politica_publicada, false)
    into v_analitica_activa
    from em_config c where c.id limit 1;

  with
  enlaces_todos as (
    select e.id, e.campana_producto_id, e.canal_promocion, e.source,
           e.medium, e.campaign, e.content, e.estado_enlace,
           e.total_aproximado_historico
      from atribucion_enlaces e
  ),
  enlaces as (
    select e.* from enlaces_todos e
     where p_campana_producto_id is null
        or e.campana_producto_id = p_campana_producto_id
  ),
  clics_enlace as (
    select d.enlace_id, coalesce(sum(d.total), 0)::bigint as clics
      from atribucion_clics_dia d
      join enlaces e on e.id = d.enlace_id
     where d.fecha_colombia between v_desde and v_hasta
     group by d.enlace_id
  ),
  clics_dia as (
    select d.fecha_colombia as fecha, sum(d.total)::bigint as clics
      from atribucion_clics_dia d
      join enlaces e on e.id = d.enlace_id
     where d.fecha_colombia between v_desde and v_hasta
     group by d.fecha_colombia
  ),
  eventos_base as (
    -- La UTM vive en la llegada. Los eventos posteriores de la misma sesión
    -- consentida se asignan al último marcador propio anterior (last-touch de
    -- sesión). Una subconsulta lateral devuelve como máximo un enlace y evita
    -- fan-out cuando una sesión encuentra más de una campaña.
    select te.*, marca.enlace_id,
           (te.cuando at time zone 'America/Bogota')::date as fecha_colombia
      from tienda_eventos te
      join lateral (
        select e.id as enlace_id
          from tienda_eventos marcador
          join enlaces_todos e on e.campaign = marcador.utm_campaign
         where marcador.sesion = te.sesion
           and (
             marcador.cuando < te.cuando
             or (marcador.cuando = te.cuando and marcador.id <= te.id)
           )
         order by marcador.cuando desc, marcador.id desc
         limit 1
      ) marca on true
      join enlaces elegido on elegido.id = marca.enlace_id
     where te.cuando >= v_inicio
       and te.cuando < v_fin_exclusivo
  ),
  eventos_enlace as (
    select enlace_id,
           count(*)::bigint as eventos,
           count(distinct sesion)::bigint as sesiones,
           count(*) filter (where tipo = 'llegada_campana')::bigint as llegadas,
           count(*) filter (where tipo = 'producto_visto')::bigint as productos_vistos,
           count(*) filter (where tipo = 'checkout_iniciado')::bigint as checkouts_eventos,
           count(distinct sesion) filter (where tipo = 'checkout_iniciado')::bigint as sesiones_checkout
      from eventos_base group by enlace_id
  ),
  eventos_dia as (
    select fecha_colombia as fecha,
           count(distinct sesion)::bigint as sesiones,
           count(*) filter (where tipo = 'checkout_iniciado')::bigint as checkouts
      from eventos_base group by fecha_colombia
  ),
  intenciones_base as (
    select i.*, (i.creado at time zone 'America/Bogota')::date as fecha_colombia
      from pagos_intencion i
      join enlaces e on e.id = i.atribucion_enlace_id
     where i.creado >= v_inicio
       and i.creado < v_fin_exclusivo
  ),
  intenciones_enlace as (
    select atribucion_enlace_id as enlace_id,
           count(*)::bigint as intenciones,
           count(*) filter (
             where not (estado = 'procesada' and entorno = 'prod' and estado_wompi = 'APPROVED' and pedido_id is not null)
           )::bigint as no_aprobadas
      from intenciones_base group by atribucion_enlace_id
  ),
  pagos_base as (
    select i.atribucion_enlace_id as enlace_id, i.procesada_en,
           (i.procesada_en at time zone 'America/Bogota')::date as fecha_colombia
      from pagos_intencion i
      join enlaces e on e.id = i.atribucion_enlace_id
     where i.estado = 'procesada' and i.entorno = 'prod' and i.estado_wompi = 'APPROVED'
       and i.pedido_id is not null and i.procesada_en is not null
       and i.procesada_en >= v_inicio
       and i.procesada_en < v_fin_exclusivo
  ),
  pagos_enlace as (
    select enlace_id, count(*)::bigint as pagos
      from pagos_base group by enlace_id
  ),
  intenciones_dia as (
    select fecha_colombia as fecha, count(*)::bigint as intenciones
      from intenciones_base group by fecha_colombia
  ),
  pagos_dia as (
    select fecha_colombia as fecha, count(*)::bigint as pagos
      from pagos_base group by fecha_colombia
  ),
  ventas_exactas as (
    select p.id, p.atribucion_enlace_id as enlace_id, p.total, p.anulado, p.creado,
           (p.creado at time zone 'America/Bogota')::date as fecha_colombia
      from pedidos p
      join pagos_intencion i
        on i.pedido_id = p.id
       and i.estado = 'procesada'
       and i.entorno = 'prod'
       and i.estado_wompi = 'APPROVED'
       and i.atribucion_enlace_id = p.atribucion_enlace_id
      join enlaces e on e.id = p.atribucion_enlace_id
     where p.creado is not null
       and p.creado >= v_inicio
       and p.creado < v_fin_exclusivo
  ),
  ventas_enlace as (
    select enlace_id,
           count(*) filter (where not anulado)::bigint as pedidos,
           coalesce(sum(total) filter (where not anulado), 0)::bigint as ingresos,
           count(*) filter (where anulado)::bigint as pedidos_anulados,
           coalesce(sum(total) filter (where anulado), 0)::bigint as ingresos_anulados
      from ventas_exactas group by enlace_id
  ),
  ventas_dia as (
    select fecha_colombia as fecha,
           count(*) filter (where not anulado)::bigint as pedidos,
           coalesce(sum(total) filter (where not anulado), 0)::bigint as ingresos
      from ventas_exactas group by fecha_colombia
  ),
  tot_eventos as (
    select count(*)::bigint as eventos,
           count(distinct sesion)::bigint as sesiones,
           count(*) filter (where tipo = 'llegada_campana')::bigint as llegadas,
           count(*) filter (where tipo = 'producto_visto')::bigint as productos_vistos,
           count(*) filter (where tipo = 'checkout_iniciado')::bigint as checkouts_eventos,
           count(distinct sesion) filter (where tipo = 'checkout_iniciado')::bigint as sesiones_checkout
      from eventos_base
  ),
  tot_intenciones as (
    select count(*)::bigint as intenciones,
           count(*) filter (
             where estado = 'procesada' and entorno = 'prod' and estado_wompi = 'APPROVED' and pedido_id is not null
           )::bigint as aprobadas_cohorte,
           count(*) filter (
             where not (estado = 'procesada' and entorno = 'prod' and estado_wompi = 'APPROVED' and pedido_id is not null)
           )::bigint as no_aprobadas
      from intenciones_base
  ),
  tot_pagos as (
    select count(*)::bigint as pagos from pagos_base
  ),
  tot_ventas as (
    select count(*) filter (where not anulado)::bigint as pedidos,
           coalesce(sum(total) filter (where not anulado), 0)::bigint as ingresos,
           count(*) filter (where anulado)::bigint as pedidos_anulados,
           coalesce(sum(total) filter (where anulado), 0)::bigint as ingresos_anulados
      from ventas_exactas
  ),
  serie as (
    select g::date as fecha,
           coalesce(c.clics, 0)::bigint as clics,
           coalesce(ev.sesiones, 0)::bigint as sesiones,
           coalesce(ev.checkouts, 0)::bigint as checkouts,
           coalesce(ib.intenciones, 0)::bigint as intenciones,
           coalesce(pg.pagos, 0)::bigint as pagos,
           coalesce(v.pedidos, 0)::bigint as pedidos,
           coalesce(v.ingresos, 0)::bigint as ingresos
      from generate_series(v_desde, v_hasta, interval '1 day') g
      left join clics_dia c on c.fecha = g::date
      left join eventos_dia ev on ev.fecha = g::date
      left join intenciones_dia ib on ib.fecha = g::date
      left join pagos_dia pg on pg.fecha = g::date
      left join ventas_dia v on v.fecha = g::date
  ),
  desglose as (
    select e.id, e.canal_promocion, e.source, e.medium, e.campaign, e.content,
           e.estado_enlace,
           coalesce(c.clics, 0)::bigint as clics,
           coalesce(ev.sesiones, 0)::bigint as sesiones,
           coalesce(ev.checkouts_eventos, 0)::bigint as checkouts,
           coalesce(i.intenciones, 0)::bigint as intenciones,
           coalesce(pg.pagos, 0)::bigint as pagos,
           coalesce(v.pedidos, 0)::bigint as pedidos,
           coalesce(v.ingresos, 0)::bigint as ingresos
      from enlaces e
      left join clics_enlace c on c.enlace_id = e.id
      left join eventos_enlace ev on ev.enlace_id = e.id
      left join intenciones_enlace i on i.enlace_id = e.id
      left join pagos_enlace pg on pg.enlace_id = e.id
      left join ventas_enlace v on v.enlace_id = e.id
  )
  select jsonb_build_object(
    'periodo', jsonb_build_object(
      'desde', v_desde, 'hasta', v_hasta,
      'zona_horaria', 'America/Bogota', 'moneda', 'COP'
    ),
    'generado_en', statement_timestamp(),
    'poblaciones', jsonb_build_object(
      'aproximada', 'clics diarios agregados, no únicos',
      'consentida', 'sesiones y eventos solo con consentimiento analítico',
      'transaccional', 'intenciones y ventas bajo autoridad server-side P4'
    ),
    'totales', jsonb_build_object(
      'enlaces', (select count(*) from enlaces),
      'clics_aproximados', v_clicks_detalle,
      'sesiones_consentidas', (select sesiones from tot_eventos),
      'eventos_consentidos', (select eventos from tot_eventos),
      'llegadas_consentidas', (select llegadas from tot_eventos),
      'productos_vistos_consentidos', (select productos_vistos from tot_eventos),
      'checkouts_consentidos', (select checkouts_eventos from tot_eventos),
      'sesiones_con_checkout', (select sesiones_checkout from tot_eventos),
      'intenciones', (select intenciones from tot_intenciones),
      'intenciones_no_aprobadas', (select no_aprobadas from tot_intenciones),
      'intenciones_aprobadas_cohorte', (select aprobadas_cohorte from tot_intenciones),
      'pagos_approved_convertidos', (select pagos from tot_pagos),
      'pedidos_exactos', (select pedidos from tot_ventas),
      'ingresos_exactos_cop', (select ingresos from tot_ventas),
      'pedidos_exactos_anulados', (select pedidos_anulados from tot_ventas),
      'ingresos_exactos_anulados_cop', (select ingresos_anulados from tot_ventas)
    ),
    'tasas', jsonb_build_object(
      'pedido_sobre_clic', jsonb_build_object(
        'valor', case when v_detalle_completo and v_clicks_detalle > 0
          then round(100.0 * (select pedidos from tot_ventas) / v_clicks_detalle, 2) else null end,
        'numerador', (select pedidos from tot_ventas),
        'denominador', v_clicks_detalle,
        'denominador_etiqueta', 'clics aproximados no únicos del periodo',
        'disponible', v_detalle_completo and v_clicks_detalle > 0
      ),
      'checkout_sobre_sesion', jsonb_build_object(
        'valor', case when (select sesiones from tot_eventos) > 0
          then round(100.0 * (select sesiones_checkout from tot_eventos) / (select sesiones from tot_eventos), 2) else null end,
        'numerador', (select sesiones_checkout from tot_eventos),
        'denominador', (select sesiones from tot_eventos),
        'denominador_etiqueta', 'sesiones consentidas del periodo',
        'disponible', (select sesiones from tot_eventos) > 0
      ),
      'pago_sobre_intencion', jsonb_build_object(
        'valor', case when (select intenciones from tot_intenciones) > 0
          then round(100.0 * (select aprobadas_cohorte from tot_intenciones) / (select intenciones from tot_intenciones), 2) else null end,
        'numerador', (select aprobadas_cohorte from tot_intenciones),
        'denominador', (select intenciones from tot_intenciones),
        'denominador_etiqueta', 'intenciones atribuidas creadas en el periodo (cohorte)',
        'disponible', (select intenciones from tot_intenciones) > 0
      )
    ),
    'serie', (select coalesce(jsonb_agg(jsonb_build_object(
      'fecha', fecha, 'clics_aproximados', clics,
      'sesiones_consentidas', sesiones, 'checkouts_consentidos', checkouts,
      'intenciones', intenciones, 'pagos_approved_convertidos', pagos,
      'pedidos_exactos', pedidos, 'ingresos_exactos_cop', ingresos
    ) order by fecha), '[]'::jsonb) from serie),
    'desglose', (select coalesce(jsonb_agg(jsonb_build_object(
      'enlace_id', id, 'canal', canal_promocion, 'source', source,
      'medium', medium, 'campaign', campaign, 'pieza', content,
      'estado', estado_enlace, 'clics_aproximados', clics,
      'sesiones_consentidas', sesiones, 'checkouts_consentidos', checkouts,
      'intenciones', intenciones, 'pagos_approved_convertidos', pagos,
      'pedidos_exactos', pedidos, 'ingresos_exactos_cop', ingresos
    ) order by pedidos desc, ingresos desc, clics desc, id), '[]'::jsonb) from desglose),
    'cobertura', jsonb_build_object(
      'estado', case
        when not v_detalle_completo
          or not v_analitica_activa
          or ((select count(*) from enlaces) > 0 and (select eventos from tot_eventos) = 0)
        then 'parcial'
        else 'completa'
      end,
      'razones', to_jsonb(array_remove(array[
        case when not v_detalle_completo then 'detalle_p3_compactado' end,
        case when not v_analitica_activa then 'analitica_consentida_inactiva' end,
        case when v_analitica_activa and (select count(*) from enlaces) > 0
               and (select eventos from tot_eventos) = 0
             then 'sin_eventos_consentidos_periodo' end
      ]::text[], null)),
      'analitica_consentida_activa', v_analitica_activa,
      'detalle_p3_disponible_desde', v_corte_p3,
      'detalle_p3_disponible_hasta', (select max(d.fecha_colombia) from atribucion_clics_dia d join enlaces e on e.id = d.enlace_id),
      'periodo_detalle_p3_completo', v_detalle_completo,
      'clics_compactados_sin_fecha', v_compactado,
      'clics_vitalicios_aproximados', v_clicks_vida,
      'intencion_sintetica_identificable', false,
      'nota_intencion_sintetica', 'El esquema no permite identificarla; permanece entre intenciones no aprobadas y nunca cuenta como pedido o ingreso.'
    ),
    'frescura', jsonb_build_object(
      'alcance', 'máximos observados dentro del periodo solicitado',
      'ultimo_clic_fecha_colombia', (select max(fecha) from clics_dia),
      'ultimo_evento_consentido', (select max(cuando) from eventos_base),
      'ultima_intencion', (select max(creado) from intenciones_base),
      'ultimo_pago_convertido', (select max(procesada_en) from pagos_base),
      'ultimo_pedido_exacto', (select max(creado) from ventas_exactas),
      'politica', 'Un desfase entre fuentes puede ser comportamiento real. No se inventa pérdida solo por el desfase; ausencia consentida e interruptor se declaran en cobertura.'
    ),
    'formulas', jsonb_build_object(
      'clics_aproximados', 'suma del detalle diario P3 retenido dentro del periodo; no únicos',
      'venta_exacta', 'intencion prod procesada + Wompi APPROVED + pedido + misma FK P4; anulados separados',
      'ingresos_exactos_cop', 'suma de pedidos.total no anulados con venta exacta; pesos COP enteros',
      'precedencia', 'exacta_propia > legacy_email_utm > aproximada_email > sin_atribuir'
    )
  ) into v_salida;

  return v_salida;
end;
$fn$;
comment on function promocionar_p5__agregado(date,date,uuid) is
  'P5 privado · agrega poblaciones aproximada, consentida y transaccional sin PII ni fan-out.';
revoke all on function promocionar_p5__agregado(date,date,uuid)
  from public, anon, authenticated, service_role;

-- Marketing: una campaña/producto y un periodo.
create function promocionar_p5_resultados(
  p_campana_producto_id uuid,
  p_desde date,
  p_hasta date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_campana jsonb;
  v_base jsonb;
begin
  if not tiene_acceso_marketing() then
    raise exception using errcode = '42501', message = 'P5_ACCESO_MARKETING_REQUERIDO';
  end if;
  if p_campana_producto_id is null then
    raise exception using errcode = '22023', message = 'P5_CAMPANA_REQUERIDA';
  end if;

  select jsonb_build_object(
    'id', cp.id,
    'nombre', cp.nombre,
    'categoria_codigo', cp.categoria_codigo,
    'slug', cp.slug,
    'publicado', cp.publicado,
    'activo', cp.activo,
    'es_placeholder', cp.es_placeholder,
    'estado', case
      when not cp.activo then 'retirada'
      when cp.es_placeholder then 'ejemplo'
      when cp.publicado then 'publicada'
      else 'borrador'
    end
  ) into v_campana
  from campana_producto cp where cp.id = p_campana_producto_id;

  if v_campana is null then
    raise exception using errcode = 'P0002', message = 'P5_CAMPANA_NO_ENCONTRADA';
  end if;

  v_base := promocionar_p5__agregado(p_desde, p_hasta, p_campana_producto_id);
  return jsonb_build_object('contrato', 'promocionar_p5_resultados_v1', 'campana', v_campana) || v_base;
end;
$fn$;
comment on function promocionar_p5_resultados(uuid,date,date) is
  'P5 Marketing · resultados agregados de una campana_producto y periodo Colombia; sin PII.';
revoke all on function promocionar_p5_resultados(uuid,date,date)
  from public, anon, authenticated, service_role;
grant execute on function promocionar_p5_resultados(uuid,date,date) to authenticated;

-- Métricas: resumen global P5 y distribución exclusiva de pedidos no anulados.
create function promocionar_p5_resumen_metricas(p_desde date, p_hasta date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_base jsonb;
  v_distribucion jsonb;
begin
  if not tiene_acceso_datos_metricas() then
    raise exception using errcode = '42501', message = 'P5_ACCESO_METRICAS_REQUERIDO';
  end if;
  if p_desde is null or p_hasta is null or p_hasta < p_desde or p_hasta - p_desde > 730 then
    raise exception using errcode = '22023', message = 'P5_PERIODO_INVALIDO';
  end if;

  v_base := promocionar_p5__agregado(p_desde, p_hasta, null);

  with lote as (
    select p.id, p.total, p.atribucion_enlace_id, p.utm_campaign
      from pedidos p
     where not p.anulado and p.creado is not null
       and (p.creado at time zone 'America/Bogota')::date between p_desde and p_hasta
  ), aproximadas as (
    select a.pedido_id, a.campana_id
      from em__atribucion_aproximada() a
      join lote l on l.id = a.pedido_id
  ), clasificados as (
    select l.id, l.total,
           case
             when exists (
               select 1 from pagos_intencion i
                where i.pedido_id = l.id
                  and i.estado = 'procesada'
                  and i.entorno = 'prod'
                  and i.estado_wompi = 'APPROVED'
                  and i.atribucion_enlace_id = l.atribucion_enlace_id
                  and l.atribucion_enlace_id is not null
             ) then 'exacta_propia'
             when l.atribucion_enlace_id is null and ec.id is not null then 'legacy_email_utm'
             when l.atribucion_enlace_id is null and ec.id is null and a.campana_id is not null then 'aproximada_email'
             else 'sin_atribuir'
           end as tipo
      from lote l
      left join em_campanas ec on ec.utm_campaign = l.utm_campaign
      left join aproximadas a on a.pedido_id = l.id
  ), categorias(tipo, orden) as (
    values ('exacta_propia', 1), ('legacy_email_utm', 2),
           ('aproximada_email', 3), ('sin_atribuir', 4)
  ), agregado as (
    select c.tipo, c.orden, count(x.id)::bigint as pedidos,
           coalesce(sum(x.total), 0)::bigint as ingresos
      from categorias c left join clasificados x on x.tipo = c.tipo
     group by c.tipo, c.orden
  )
  select jsonb_agg(jsonb_build_object(
    'tipo', tipo,
    'etiqueta', case tipo
      when 'exacta_propia' then 'Validada · enlace propio'
      when 'legacy_email_utm' then 'Email legacy'
      when 'aproximada_email' then 'Email aproximada'
      else 'Sin atribuir'
    end,
    'pedidos', pedidos, 'ingresos_cop', ingresos
  ) order by orden) into v_distribucion from agregado;

  return jsonb_build_object(
    'contrato', 'promocionar_p5_metricas_v1',
    'periodo', v_base->'periodo',
    'generado_en', v_base->'generado_en',
    'totales', v_base->'totales',
    'tasas', v_base->'tasas',
    'distribucion', coalesce(v_distribucion, '[]'::jsonb),
    'cobertura', v_base->'cobertura',
    'frescura', v_base->'frescura',
    'formulas', v_base->'formulas'
  );
end;
$fn$;
comment on function promocionar_p5_resumen_metricas(date,date) is
  'P5 Metricas · resumen agregado y distribucion exclusiva; no expone pedidos ni PII.';
revoke all on function promocionar_p5_resumen_metricas(date,date)
  from public, anon, authenticated, service_role;
grant execute on function promocionar_p5_resumen_metricas(date,date)
  to authenticated, service_role;

-- Ventas: clasificación set-based de un lote visible. Una llamada por tablero.
create function promocionar_p5_procedencia_pedidos(p_pedido_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_salida jsonb;
  v_solicitados integer;
begin
  if not tiene_acceso_ventas() then
    raise exception using errcode = '42501', message = 'P5_ACCESO_VENTAS_REQUERIDO';
  end if;
  if p_pedido_ids is null then
    raise exception using errcode = '22023', message = 'P5_LOTE_REQUERIDO';
  end if;
  v_solicitados := cardinality(p_pedido_ids);
  if v_solicitados > 500 or array_position(p_pedido_ids, null) is not null
     or (select count(distinct u.id) from unnest(p_pedido_ids) as u(id)) <> v_solicitados then
    raise exception using errcode = '22023', message = 'P5_LOTE_INVALIDO';
  end if;
  if v_solicitados = 0 then
    return jsonb_build_object(
      'contrato', 'promocionar_p5_procedencia_v1',
      'solicitados', 0, 'devueltos', 0, 'pedidos', '[]'::jsonb
    );
  end if;

  with solicitados as (
    select id, min(ord)::integer as ord
      from unnest(p_pedido_ids) with ordinality u(id, ord)
     group by id
  ), lote as (
    select s.ord, p.id, p.anulado, p.atribucion_enlace_id, p.utm_campaign,
           p.customer_id, p.creado, p.fecha_orden
      from solicitados s join pedidos p on p.id = s.id
  ), clics_email as (
    select e.campana_id, e.cuando, ct.customer_id
      from em_eventos e
      join em_contactos ct on ct.id = e.contacto_id
     where e.tipo = 'clic'
       and e.campana_id is not null
       and ct.customer_id is not null
  ), candidatos_aproximados as (
    -- Clasificación histórica propia de P5: reproduce candidato y ventana de
    -- em__atribucion_aproximada(), pero conserva la procedencia al anular.
    select l.id as pedido_id, c.campana_id, c.cuando,
           row_number() over (partition by l.id order by c.cuando desc) as rn
      from lote l
      join clics_email c on c.customer_id = l.customer_id
     where l.atribucion_enlace_id is null
       and l.utm_campaign is null
       and coalesce(l.creado, l.fecha_orden::timestamptz) >= c.cuando
       and l.fecha_orden between (c.cuando at time zone 'America/Bogota')::date
                             and (c.cuando at time zone 'America/Bogota')::date + 7
  ), aproximadas as (
    select pedido_id, campana_id
      from candidatos_aproximados
     where rn = 1
  ), filas as (
    select l.ord, l.id, l.anulado,
           case
             when exacta.es_valida then 'exacta_propia'
             when l.atribucion_enlace_id is null and legacy.id is not null then 'legacy_email_utm'
             when l.atribucion_enlace_id is null and legacy.id is null and aprox.campana_id is not null then 'aproximada_email'
             else 'sin_atribuir'
           end as tipo,
           e.canal_promocion as canal,
           e.content as pieza,
           e.campaign as campana_utm,
           cp.nombre as campana_producto,
           coalesce(legacy.nombre_interno, email_aprox.nombre_interno) as campana_email
      from lote l
      left join lateral (
        select true as es_valida
          from pagos_intencion i
         where i.pedido_id = l.id
           and i.estado = 'procesada'
           and i.entorno = 'prod'
           and i.estado_wompi = 'APPROVED'
           and i.atribucion_enlace_id = l.atribucion_enlace_id
           and l.atribucion_enlace_id is not null
         limit 1
      ) exacta on true
      left join atribucion_enlaces e
        on e.id = l.atribucion_enlace_id and coalesce(exacta.es_valida, false)
      left join campana_producto cp on cp.id = e.campana_producto_id
      left join em_campanas legacy
        on legacy.utm_campaign = l.utm_campaign and l.atribucion_enlace_id is null
      left join aproximadas aprox on aprox.pedido_id = l.id
      left join em_campanas email_aprox on email_aprox.id = aprox.campana_id
  )
  select jsonb_build_object(
    'contrato', 'promocionar_p5_procedencia_v1',
    'solicitados', v_solicitados,
    'devueltos', count(*),
    'pedidos', coalesce(jsonb_agg(jsonb_build_object(
      'pedido_id', id,
      'tipo', tipo,
      'etiqueta', case tipo
        when 'exacta_propia' then 'Validada · enlace propio'
        when 'legacy_email_utm' then 'Email legacy'
        when 'aproximada_email' then 'Email aproximada'
        else 'Sin atribuir'
      end,
      'explicacion', case tipo
        when 'exacta_propia' then 'Intención prod procesada, pago APPROVED y pedido comparten la atribución P4.'
        when 'legacy_email_utm' then 'Coincidencia histórica con la UTM de una campaña de Email.'
        when 'aproximada_email' then 'Último clic Email elegible en la ventana histórica; no es atribución exacta.'
        else 'No existe evidencia promocional bajo la precedencia P5.'
      end,
      'canal', case when tipo = 'exacta_propia' then canal else null end,
      'pieza', case when tipo = 'exacta_propia' then pieza else null end,
      'campana', case
        when tipo = 'exacta_propia' then campana_utm
        else campana_email
      end,
      'producto_promovido', case when tipo = 'exacta_propia' then campana_producto else null end,
      'anulado', anulado
    ) order by ord), '[]'::jsonb)
  ) into v_salida
  from filas;

  return v_salida;
end;
$fn$;
comment on function promocionar_p5_procedencia_pedidos(uuid[]) is
  'P5 Ventas · procedencia de hasta 500 pedidos en lote; no usa pedidos.canal ni expone PII nueva.';
revoke all on function promocionar_p5_procedencia_pedidos(uuid[])
  from public, anon, authenticated, service_role;
grant execute on function promocionar_p5_procedencia_pedidos(uuid[]) to authenticated;

-- Matriz mínima dentro de la migración: si hay drift de firma, search_path o ACL,
-- todo el archivo revierte. No exige datos iniciales y es seguro con tablas vacías.
do $invariantes$
declare
  v_f record;
  v_oid regprocedure;
begin
  if not exists (
    select 1 from pg_index i join pg_class c on c.oid = i.indexrelid
     where c.oid = 'public.tienda_eventos_sesion_cuando_p5_idx'::regclass
       and i.indrelid = 'public.tienda_eventos'::regclass
       and i.indisvalid
  ) then
    raise exception using errcode = 'P0001', message = 'P5_INDICE_SESION_AUSENTE';
  end if;

  for v_f in
    select * from (values
      ('public.promocionar_p5__agregado(date,date,uuid)', false, false),
      ('public.promocionar_p5_resultados(uuid,date,date)', true, false),
      ('public.promocionar_p5_resumen_metricas(date,date)', true, true),
      ('public.promocionar_p5_procedencia_pedidos(uuid[])', true, false)
    ) as x(firma, authenticated_e, service_e)
  loop
    v_oid := to_regprocedure(v_f.firma);
    if v_oid is null then
      raise exception using errcode = 'P0001', message = 'P5_FUNCION_AUSENTE_' || v_f.firma;
    end if;
    if not (select p.prosecdef and coalesce(p.proconfig = array['search_path=public, pg_temp'], false)
              from pg_proc p where p.oid = v_oid)
       or has_function_privilege('anon', v_oid, 'execute')
       or has_function_privilege('authenticated', v_oid, 'execute') is distinct from v_f.authenticated_e
       or has_function_privilege('service_role', v_oid, 'execute') is distinct from v_f.service_e then
      raise exception using errcode = 'P0001', message = 'P5_FUNCION_O_ACL_INVALIDA_' || v_f.firma;
    end if;
  end loop;
end;
$invariantes$;

commit;
