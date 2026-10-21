-- Promocionar P4 · postflight estructural de solo lectura.
with funciones(firma, solo_service_role) as (
  values
    ('promocionar_p4_validar_codigo(text)', true),
    ('pw_registrar_intencion_p4(text,uuid,text,text,integer,bigint,bigint,text,jsonb,text,text,text,text)', true),
    ('pw_registrar_intencion_carrito_p4(text,uuid,uuid,bigint,text,jsonb,text,text,text,text)', true),
    ('pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text)', true)
), permisos as (
  select firma,
         to_regprocedure('public.' || firma) is not null as existe,
         has_function_privilege('service_role', 'public.' || firma, 'EXECUTE') as service_role,
         has_function_privilege('anon', 'public.' || firma, 'EXECUTE') as anon,
         has_function_privilege('authenticated', 'public.' || firma, 'EXECUTE') as authenticated
    from funciones
)
select jsonb_build_object(
  'gate_off', (select not atribucion_habilitada from promocionar_p4_config where id = 1),
  'verificaciones_off', (select not validacion_publica_verificada and not checkout_verificado from promocionar_p4_config where id = 1),
  'historico_intenciones_nulo', not exists (select 1 from pagos_intencion where atribucion_enlace_id is not null),
  'historico_pedidos_nulo', not exists (select 1 from pedidos where atribucion_enlace_id is not null),
  'incidencias_vacias', not exists (select 1 from promocionar_p4_incidencias),
  'tablas_privadas_rls', (
    select count(*) = 3 from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname in ('promocionar_p4_config','promocionar_p4_config_bitacora','promocionar_p4_incidencias')
       and c.relrowsecurity
  ),
  'reparacion_privada',
    to_regprocedure('public.promocionar_p4_reparar_incidencias()') is not null
    and not has_function_privilege('service_role', 'public.promocionar_p4_reparar_incidencias()', 'EXECUTE')
    and not has_function_privilege('authenticated', 'public.promocionar_p4_reparar_incidencias()', 'EXECUTE')
    and not has_function_privilege('anon', 'public.promocionar_p4_reparar_incidencias()', 'EXECUTE'),
  'sin_divergencias', not exists (
    select 1 from pagos_intencion i join pedidos p on p.id = i.pedido_id
     where i.atribucion_enlace_id is distinct from p.atribucion_enlace_id
  ),
  'funciones', (select jsonb_agg(jsonb_build_object(
    'firma', firma, 'existe', existe, 'service_role', service_role,
    'anon', anon, 'authenticated', authenticated
  ) order by firma) from permisos),
  'triggers', jsonb_build_object(
    'insert_intencion', exists (select 1 from pg_trigger where tgname = 'trg_pw_p4_asignar_atribucion' and not tgisinternal),
    'inmutable_intencion', exists (select 1 from pg_trigger where tgname = 'trg_pw_p4_proteger_atribucion_intencion' and not tgisinternal),
    'inmutable_pedido', exists (select 1 from pg_trigger where tgname = 'trg_pw_p4_proteger_atribucion_pedido' and not tgisinternal)
  )
) as postflight_promocionar_p4;
