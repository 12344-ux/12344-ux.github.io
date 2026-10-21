-- Promocionar P5 · postflight estructural de solo lectura. No muestra PII.
begin transaction read only;
set local statement_timeout = '30s';
set local search_path = public, pg_temp;

with esperadas(firma, authenticated_e, service_e) as (
  values
    ('promocionar_p5__agregado(date,date,uuid)', false, false),
    ('promocionar_p5_resultados(uuid,date,date)', true, false),
    ('promocionar_p5_resumen_metricas(date,date)', true, true),
    ('promocionar_p5_procedencia_pedidos(uuid[])', true, false)
), funciones as (
  select e.*,
         p.oid is not null as existe,
         coalesce(p.prosecdef, false) as security_definer,
         coalesce(p.provolatile = 's', false) as stable,
         coalesce(p.proconfig = array['search_path=public, pg_temp'], false) as search_path_fijo,
         case when p.oid is null then null else has_function_privilege('anon', p.oid, 'execute') end as anon,
         case when p.oid is null then null else has_function_privilege('authenticated', p.oid, 'execute') end as authenticated,
         case when p.oid is null then null else has_function_privilege('service_role', p.oid, 'execute') end as service_role
    from esperadas e
    left join pg_proc p on p.oid = to_regprocedure('public.' || e.firma)
), id_vacio as (
  select md5('promocionar-p5-postflight-vacio-' || g::text)::uuid as id
    from generate_series(1, 32) g
   where not exists (
     select 1 from atribucion_enlaces e
      where e.campana_producto_id = md5('promocionar-p5-postflight-vacio-' || g::text)::uuid
   )
   limit 1
), corte_vacio as (
  select promocionar_p5__agregado(
    (statement_timestamp() at time zone 'America/Bogota')::date,
    (statement_timestamp() at time zone 'America/Bogota')::date,
    id_vacio.id
  ) as payload
  from id_vacio
)
select jsonb_build_object(
  'cuatro_funciones', (select count(*) = 4 and bool_and(existe) from funciones),
  'security_definer_y_path_fijo', (select bool_and(security_definer and stable and search_path_fijo) from funciones),
  'grants_nominales', (select bool_and(not coalesce(anon, true)
    and authenticated is not distinct from authenticated_e
    and service_role is not distinct from service_e) from funciones),
  'sin_tablas_p5', not exists (
    select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relname like 'promocionar_p5_%' and c.relkind in ('r','p','v','m')
  ),
  'indice_sesion_consentida', to_regclass('public.tienda_eventos_sesion_cuando_p5_idx') is not null,
  'funciones', (select jsonb_agg(jsonb_build_object(
    'firma', firma, 'existe', existe, 'security_definer', security_definer,
    'stable', stable, 'search_path_fijo', search_path_fijo,
    'anon', anon, 'authenticated', authenticated, 'service_role', service_role
  ) order by firma) from funciones),
  'corte_vacio_agregado_valido', (select
    jsonb_typeof(payload) = 'object'
    and (payload->'totales'->>'enlaces')::bigint = 0
    and (payload->'totales'->>'clics_aproximados')::bigint = 0
    and (payload->'totales'->>'sesiones_consentidas')::bigint = 0
    and (payload->'totales'->>'intenciones')::bigint = 0
    and (payload->'totales'->>'pedidos_exactos')::bigint = 0
    and (payload->'totales'->>'ingresos_exactos_cop')::bigint = 0
    and jsonb_array_length(payload->'serie') = 1
    and jsonb_array_length(payload->'desglose') = 0
    from corte_vacio),
  'nota_pruebas_con_guardia', 'Los wrappers nominales y el lote vacío se recorren con sesiones de área durante el despliegue; SQL Editor sin auth debe fallar por guardia.'
) as postflight_promocionar_p5;

rollback;
