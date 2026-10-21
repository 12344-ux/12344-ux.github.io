-- Promocionar P5 · diagnóstico agregado de solo lectura. No revela códigos ni PII.
begin transaction read only;
set local statement_timeout = '30s';
set local search_path = public, pg_temp;

select jsonb_build_object(
  'instalado', to_regprocedure('public.promocionar_p5_resultados(uuid,date,date)') is not null
                and to_regprocedure('public.promocionar_p5_resumen_metricas(date,date)') is not null
                and to_regprocedure('public.promocionar_p5_procedencia_pedidos(uuid[])') is not null,
  'p3', jsonb_build_object(
    'enlaces', (select count(*) from atribucion_enlaces),
    'clics_detalle_filas', (select count(*) from atribucion_clics_dia),
    'detalle_desde', (select min(fecha_colombia) from atribucion_clics_dia),
    'detalle_hasta', (select max(fecha_colombia) from atribucion_clics_dia),
    'clics_compactados_sin_fecha', (select coalesce(sum(total_aproximado_historico),0) from atribucion_enlaces)
  ),
  'p4', jsonb_build_object(
    'intenciones_atribuidas', (select count(*) from pagos_intencion where atribucion_enlace_id is not null),
    'intenciones_convertidas_approved', (select count(*) from pagos_intencion where atribucion_enlace_id is not null and entorno='prod' and estado='procesada' and estado_wompi='APPROVED' and pedido_id is not null),
    'pedidos_con_fk', (select count(*) from pedidos where atribucion_enlace_id is not null),
    'ventas_exactas_autoritativas', (select count(*) from pedidos p join pagos_intencion i on i.pedido_id=p.id and i.entorno='prod' and i.estado='procesada' and i.estado_wompi='APPROVED' and i.atribucion_enlace_id=p.atribucion_enlace_id where p.atribucion_enlace_id is not null),
    'divergencias_fk', (select count(*) from pagos_intencion i join pedidos p on p.id=i.pedido_id where i.atribucion_enlace_id is distinct from p.atribucion_enlace_id),
    'incidencias_pendientes', (select count(*) from promocionar_p4_incidencias where resuelta_en is null)
  ),
  'analitica_consentida', jsonb_build_object(
    'activa', (select coalesce(analitica_activa and politica_publicada,false) from em_config where id limit 1),
    'primer_evento', (select min(cuando) from tienda_eventos),
    'ultimo_evento', (select max(cuando) from tienda_eventos)
  ),
  'intencion_sintetica_identificable', false,
  'nota', 'No existe marca de esquema: no se intenta identificar ni eliminar la intención sintética P4.'
) as estado_promocionar_p5;

rollback;
