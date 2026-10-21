-- Promocionar P4 · diagnóstico de solo lectura. No revela códigos ni PII.
select jsonb_build_object(
  'config', (select jsonb_build_object(
    'atribucion_habilitada', atribucion_habilitada,
    'validacion_publica_verificada', validacion_publica_verificada,
    'checkout_verificado', checkout_verificado,
    'politica_publicada', politica_publicada,
    'politica_version', politica_version,
    'actualizado_en', actualizado_en,
    'actualizado_razon', actualizado_razon
  ) from promocionar_p4_config where id = 1),
  'intenciones_atribuidas', (select count(*) from pagos_intencion where atribucion_enlace_id is not null),
  'pedidos_atribuidos', (select count(*) from pedidos where atribucion_enlace_id is not null),
  'divergencias', (select count(*)
    from pagos_intencion i join pedidos p on p.id = i.pedido_id
   where i.atribucion_enlace_id is distinct from p.atribucion_enlace_id),
  'incidencias_pendientes', (select count(*) from promocionar_p4_incidencias where resuelta_en is null),
  'incidencias_resueltas', (select count(*) from promocionar_p4_incidencias where resuelta_en is not null),
  'bitacora_config', (select count(*) from promocionar_p4_config_bitacora)
) as estado_promocionar_p4;
