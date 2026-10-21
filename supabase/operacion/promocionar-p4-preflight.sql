-- Promocionar P4 · preflight de solo lectura antes de aplicar 20261109000000.
select jsonb_build_object(
  'baseline_p3', to_regclass('public.atribucion_enlaces') is not null,
  'baseline_intencion_inmediata', to_regprocedure('public.pw_registrar_intencion(text,uuid,text,text,integer,bigint,bigint,text,jsonb,text,text,text)') is not null,
  'baseline_carrito_c5', to_regprocedure('public.pw_registrar_intencion_carrito(text,uuid,uuid,bigint,text,jsonb,text,text,text)') is not null,
  'baseline_webhook', to_regprocedure('public.pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text)') is not null,
  'p4_ausente', to_regclass('public.promocionar_p4_config') is null,
  'columnas_ausentes', not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name in ('pagos_intencion','pedidos')
       and column_name = 'atribucion_enlace_id'
  ),
  'pedido_sin_intenciones_duplicadas', not exists (
    select pedido_id from pagos_intencion where pedido_id is not null
     group by pedido_id having count(*) > 1
  )
) as preflight_promocionar_p4;
