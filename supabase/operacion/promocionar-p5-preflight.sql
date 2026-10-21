-- Promocionar P5 · preflight de solo lectura antes de aplicar 20261110000000.
-- Todos los booleanos deben ser true. No muestra PII.
begin transaction read only;
set local statement_timeout = '30s';
set local lock_timeout = '3s';
set local search_path = public, pg_temp;

select jsonb_build_object(
  'baseline_p3', to_regclass('public.atribucion_enlaces') is not null
                 and to_regclass('public.atribucion_clics_dia') is not null,
  'baseline_p4', to_regclass('public.promocionar_p4_config') is not null
                 and exists (select 1 from information_schema.columns where table_schema='public' and table_name='pagos_intencion' and column_name='atribucion_enlace_id')
                 and exists (select 1 from information_schema.columns where table_schema='public' and table_name='pedidos' and column_name='atribucion_enlace_id'),
  'baseline_metricas_consentidas', to_regclass('public.tienda_eventos') is not null
                 and to_regprocedure('public.tiene_acceso_datos_metricas()') is not null,
  'baseline_email', to_regclass('public.em_campanas') is not null
                 and to_regclass('public.em_config') is not null
                 and to_regprocedure('public.em__atribucion_aproximada()') is not null,
  'guardias', to_regprocedure('public.tiene_acceso_marketing()') is not null
                 and to_regprocedure('public.tiene_acceso_ventas()') is not null,
  'p5_ausente', to_regprocedure('public.promocionar_p5__agregado(date,date,uuid)') is null
                 and to_regprocedure('public.promocionar_p5_resultados(uuid,date,date)') is null
                 and to_regprocedure('public.promocionar_p5_resumen_metricas(date,date)') is null
                 and to_regprocedure('public.promocionar_p5_procedencia_pedidos(uuid[])') is null
                 and to_regclass('public.tienda_eventos_sesion_cuando_p5_idx') is null,
  'sin_create_api', not exists (
    select 1 from pg_roles r where r.rolname in ('anon','authenticated','service_role')
      and has_schema_privilege(r.rolname, 'public', 'CREATE')
  ),
  'pedidos_sin_intenciones_duplicadas', not exists (
    select pedido_id from pagos_intencion where pedido_id is not null
     group by pedido_id having count(*) > 1
  )
) as preflight_promocionar_p5;

rollback;
