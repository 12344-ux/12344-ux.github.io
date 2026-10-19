-- ============================================================================
-- MAGANDHI · COMERCIAL C4 · POSTFLIGHT DE PRODUCCIÓN
-- ----------------------------------------------------------------------------
-- Ejecutar COMPLETO, como una ejecución separada, inmediatamente después de
-- 20261105000000_comercial_c4_cuenta_ciclo_carrito.sql. La Edge estado-pago
-- C4 ya debe estar desplegada sobre el puente; este gate ocurre antes de
-- desplegar crear-intencion-pago o activar el carrito.
--
-- Es estrictamente de solo lectura. No invoca RPC mutantes: en particular NO
-- llama pw_estado_checkout_publico, porque puede expirar/liberar/versionar.
-- Devuelve únicamente metadatos, ACL y conteos agregados, sin PII ni secretos.
-- ============================================================================

begin transaction read only;
set local search_path = pg_catalog, public;
set local statement_timeout = '20s';
set local lock_timeout = '3s';

-- 1/7 · Resumen principal. Las ocho columnas deben ser true.
with columnas_esperadas(tabla, columna, tipo, nullable, tiene_default) as (
  values
    ('pedidos', 'destinatario_nombre', 'text', 'YES', false),
    ('pedidos', 'destinatario_correo', 'text', 'YES', false),
    ('pedidos', 'destinatario_telefono', 'text', 'YES', false),
    ('pedido_items', 'campana_id', 'uuid', 'YES', false),
    ('pedido_items', 'campana_nombre', 'text', 'YES', false),
    ('pedido_items', 'campana_slug', 'text', 'YES', false),
    ('pagos_intencion', 'ciclo_carrito_version', 'smallint', 'NO', true),
    ('pagos_intencion', 'expira_en', 'timestamp with time zone', 'YES', false),
    ('pagos_intencion', 'carrito_liberado_en', 'timestamp with time zone', 'YES', false),
    ('pagos_intencion', 'carrito_consumido_en', 'timestamp with time zone', 'YES', false),
    ('pagos_intencion', 'carrito_consumo_resultado', 'text', 'YES', false),
    ('pagos_intencion', 'carrito_consumo_detalle', 'jsonb', 'YES', false),
    ('pw_sucesiones_c4', 'referencia_predecesora', 'text', 'NO', false),
    ('pw_sucesiones_c4', 'carrito_id', 'uuid', 'NO', false),
    ('pw_sucesiones_c4', 'version_predecesora', 'bigint', 'NO', false),
    ('pw_sucesiones_c4', 'version_sucesora', 'bigint', 'NO', false),
    ('pw_sucesiones_c4', 'creado', 'timestamp with time zone', 'NO', true)
), columnas_cotejadas as (
  select count(c.column_name)::integer as encontradas,
         coalesce(bool_and(
           c.data_type = e.tipo
           and c.is_nullable = e.nullable
           and (c.column_default is not null) = e.tiene_default
         ), false) as definiciones_correctas
    from columnas_esperadas e
    left join information_schema.columns c
      on c.table_schema = 'public'
     and c.table_name = e.tabla
     and c.column_name = e.columna
)
select (select coalesce(
                 count(*) = 1
                 and bool_and(id = 1 and carrito_habilitado is false),
                 false
               )
          from comercial_config) as config_singleton_flag_off,
       to_regclass('public.pw_sucesiones_c4') is not null as tabla_sucesiones,
       to_regprocedure('public.pw_estado_checkout_publico(text,uuid)') is not null
         as retorno_c4,
       to_regprocedure('public.pw_resolver_revision_c4(text,text,text)') is not null
         as resolver_c4,
       exists (
         select 1
           from pg_trigger t
           join pg_class c on c.oid = t.tgrelid
           join pg_namespace n on n.oid = c.relnamespace
          where n.nspname = 'public'
            and c.relname = 'pagos_intencion'
            and t.tgname = 'trg_pw_marcar_ciclo_carrito_c4'
            and not t.tgisinternal
            and t.tgenabled <> 'D'
       ) as trigger_c4_activo,
       (select count(*) = 11 and bool_and(convalidated)
          from pg_constraint
         where conname = any(array[
           'pagos_intencion_ciclo_carrito_version',
           'pagos_intencion_expiracion_c4',
           'pagos_intencion_consumo_carrito_resultado',
           'pagos_intencion_ciclo_carrito_solo_v2',
           'pagos_intencion_consumo_carrito_coherente',
           'pw_sucesiones_c4_pkey',
           'pw_sucesiones_c4_referencia_predecesora_fkey',
           'pw_sucesiones_c4_carrito_id_fkey',
           'pw_sucesiones_c4_version',
           'pedido_items_campana_id_fkey',
           'pagos_eventos_resultado_check'
         ])) as once_constraints_c4,
       (select encontradas = 17 and definiciones_correctas
          from columnas_cotejadas) as diecisiete_columnas_c4,
       exists (
         select 1
           from pg_indexes
          where schemaname = 'public'
            and indexname = 'pagos_intencion_carrito_version_v2_uidx'
            and indexdef ilike '%(auth_user_id, carrito_id, carrito_version)%'
            and indexdef ilike '%where (version_checkout = 2)%'
       ) as indice_unico_c3_preservado;

-- 2/7 · Historia v2 preservada e invariantes inmediatas. Antes de activar:
-- c3_preservadas=1 según el corte; c4_creadas/sucesiones/contradicciones=0.
select count(*) filter (
         where version_checkout = 2
           and ciclo_carrito_version = 0
       )::bigint as c3_preservadas,
       count(*) filter (
         where ciclo_carrito_version = 4
       )::bigint as c4_creadas,
       count(*) filter (
         where version_checkout in (0, 1)
           and ciclo_carrito_version <> 0
       )::bigint as historicas_reetiquetadas,
       count(*) filter (
         where ciclo_carrito_version = 0
           and (
             expira_en is not null
             or carrito_liberado_en is not null
             or carrito_consumido_en is not null
             or carrito_consumo_resultado is not null
             or carrito_consumo_detalle is not null
           )
       )::bigint as ciclo_cero_modificado,
       count(*) filter (
         where ciclo_carrito_version = 4
           and expira_en is null
       )::bigint as c4_sin_expiracion,
       count(*) filter (
         where carrito_consumido_en is not null
           and carrito_liberado_en is not null
       )::bigint as consumida_y_liberada,
       count(*) filter (
         where ciclo_carrito_version = 4
           and estado = 'procesada'
           and carrito_consumido_en is null
       )::bigint as procesada_sin_consumo
  from pagos_intencion;

select count(*)::bigint as sucesiones,
       count(*) filter (
         where s.version_sucesora <> s.version_predecesora + 1
            or s.carrito_id <> pi.carrito_id
            or s.version_predecesora <> pi.carrito_version
            or pi.version_checkout <> 2
            or pi.ciclo_carrito_version <> 0
       )::bigint as sucesiones_invalidas
  from pw_sucesiones_c4 s
  join pagos_intencion pi on pi.referencia = s.referencia_predecesora;

-- 3/7 · Constraints C4, todos validados.
select c.conrelid::regclass as tabla,
       c.conname as nombre_constraint,
       c.contype as tipo,
       c.convalidated as validado,
       pg_get_constraintdef(c.oid) as definicion
  from pg_constraint c
 where c.conname = any(array[
         'pagos_intencion_ciclo_carrito_version',
         'pagos_intencion_expiracion_c4',
         'pagos_intencion_consumo_carrito_resultado',
         'pagos_intencion_ciclo_carrito_solo_v2',
         'pagos_intencion_consumo_carrito_coherente',
         'pw_sucesiones_c4_pkey',
         'pw_sucesiones_c4_referencia_predecesora_fkey',
         'pw_sucesiones_c4_carrito_id_fkey',
         'pw_sucesiones_c4_version',
         'pedido_items_campana_id_fkey',
         'pagos_eventos_resultado_check'
       ])
 order by c.conrelid::regclass::text, c.conname;

-- 4/7 · Índices relevantes preservados/nuevos.
select tablename,
       indexname,
       indexdef
  from pg_indexes
 where schemaname = 'public'
   and (
     (tablename = 'pagos_intencion'
       and indexname = any(array[
         'pagos_intencion_pkey',
         'pagos_intencion_estado_idx',
         'pagos_intencion_transaccion_idx',
         'pagos_intencion_pedido_idx',
         'pagos_intencion_carrito_version_v2_uidx'
       ]))
     or (tablename = 'pw_sucesiones_c4')
   )
 order by tablename, indexname;

-- 5/7 · RLS/policies. pw_sucesiones_c4 debe tener RLS=true y 0 policies.
select c.relname as tabla,
       c.relrowsecurity as rls,
       c.relforcerowsecurity as force_rls,
       count(p.policyname)::bigint as policies
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  left join pg_policies p
    on p.schemaname = n.nspname
   and p.tablename = c.relname
 where n.nspname = 'public'
   and c.relname = any(array[
     'comercial_config', 'carritos', 'carrito_items',
     'pagos_intencion', 'pagos_intencion_items', 'pw_sucesiones_c4',
     'pedidos', 'pedido_items'
   ])
 group by c.relname, c.relrowsecurity, c.relforcerowsecurity
 order by c.relname;

select not has_table_privilege('anon', 'public.pw_sucesiones_c4', 'select')
       and not has_table_privilege('anon', 'public.pw_sucesiones_c4', 'insert')
       and not has_table_privilege('anon', 'public.pw_sucesiones_c4', 'update')
       and not has_table_privilege('anon', 'public.pw_sucesiones_c4', 'delete')
         as sucesiones_sin_anon,
       not has_table_privilege('authenticated', 'public.pw_sucesiones_c4', 'select')
       and not has_table_privilege('authenticated', 'public.pw_sucesiones_c4', 'insert')
       and not has_table_privilege('authenticated', 'public.pw_sucesiones_c4', 'update')
       and not has_table_privilege('authenticated', 'public.pw_sucesiones_c4', 'delete')
         as sucesiones_sin_authenticated,
       not has_table_privilege('service_role', 'public.pw_sucesiones_c4', 'select')
       and not has_table_privilege('service_role', 'public.pw_sucesiones_c4', 'insert')
       and not has_table_privilege('service_role', 'public.pw_sucesiones_c4', 'update')
       and not has_table_privilege('service_role', 'public.pw_sucesiones_c4', 'delete')
         as sucesiones_sin_service_role,
       has_table_privilege('authenticated', 'public.carritos', 'select')
       and not has_table_privilege('authenticated', 'public.carritos', 'insert')
       and not has_table_privilege('authenticated', 'public.carritos', 'update')
       and not has_table_privilege('authenticated', 'public.carritos', 'delete')
         as carritos_authenticated_solo_lectura,
       has_table_privilege('authenticated', 'public.carrito_items', 'select')
       and not has_table_privilege('authenticated', 'public.carrito_items', 'insert')
       and not has_table_privilege('authenticated', 'public.carrito_items', 'update')
       and not has_table_privilege('authenticated', 'public.carrito_items', 'delete')
         as items_authenticated_solo_lectura,
       not has_table_privilege('anon', 'public.pedidos', 'select')
       and has_table_privilege('authenticated', 'public.pedidos', 'select')
       and not has_table_privilege('authenticated', 'public.pedidos', 'insert')
       and not has_table_privilege('authenticated', 'public.pedidos', 'update')
       and not has_table_privilege('authenticated', 'public.pedidos', 'delete')
         as pedidos_protegidos_por_rls,
       not has_table_privilege('anon', 'public.pedido_items', 'select')
       and has_table_privilege('authenticated', 'public.pedido_items', 'select')
       and not has_table_privilege('authenticated', 'public.pedido_items', 'insert')
       and not has_table_privilege('authenticated', 'public.pedido_items', 'update')
       and not has_table_privilege('authenticated', 'public.pedido_items', 'delete')
         as pedido_items_protegidos_por_rls;

-- 6/7 · Firmas, SECURITY DEFINER/search_path y EXECUTE efectivo por rol.
-- Cada fila debe existir y las cinco columnas *_ok deben ser true.
with esperadas(
  etiqueta, firma, security_definer, anon_exec, auth_exec, service_exec
) as (
  values
    ('puerta registrar intención',
     'public.pw_registrar_intencion_carrito(text,uuid,uuid,bigint,text,jsonb,text,text,text)',
     true, false, false, true),
    ('puerta procesar pago',
     'public.pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text)',
     true, false, false, true),
    ('puerta listar carrito',
     'public.co_carrito_listar()', true, false, true, true),
    ('puerta agregar carrito',
     'public.co_carrito_agregar(uuid,integer)', true, false, true, true),
    ('puerta cambiar carrito',
     'public.co_carrito_cambiar(uuid,integer,bigint)', true, false, true, true),
    ('puerta quitar carrito',
     'public.co_carrito_quitar(uuid,bigint)', true, false, true, true),
    ('puerta crear pedido histórica',
     'public.crear_pedido(uuid,text,text,text,text,text,text,text,text,text,date,text,jsonb)',
     true, false, true, true),
    ('puerta revisiones',
     'public.pw_revisiones()', true, false, true, true),
    ('puerta resolver histórica',
     'public.pw_resolver_revision(text,text)', true, false, true, true),
    ('puerta resolver C4',
     'public.pw_resolver_revision_c4(text,text,text)', true, false, true, true),
    ('puerta estado histórico',
     'public.pw_estado_publico(text)', true, false, false, true),
    ('puerta estado C4',
     'public.pw_estado_checkout_publico(text,uuid)', true, false, false, true),
    ('puerta correo pedido',
     'public.correo_pedido_preparar(uuid,text,boolean)', true, false, true, true),
    ('helper trigger C4',
     'public.pw__marcar_ciclo_carrito_c4()', false, false, false, false),
    ('helper liberar expiradas',
     'public.co__liberar_expiradas_c4(uuid)', true, false, false, false),
    ('helper bloqueo pago',
     'public.co__bloqueo_pago(uuid)', true, false, false, false),
    ('helper snapshot',
     'public.co__carrito_snapshot()', true, false, false, false),
    ('helper registrar C3',
     'public.pw__registrar_intencion_carrito_c3(text,uuid,uuid,bigint,text,jsonb,text,text,text)',
     true, false, false, false),
    ('helper procesar C3',
     'public.pw__procesar_pago_c3(text,text,text,bigint,text,text,text,jsonb,text,text)',
     true, false, false, false),
    ('helper pedido C3',
     'public.crear_pedido_c3_base(uuid,text,text,text,text,text,text,text,text,text,date,text,jsonb)',
     true, false, false, false),
    ('helper pedido C4',
     'public.crear_pedido_c4(uuid,text,text,text,text,text,text,text,text,text,date,text,jsonb)',
     true, false, false, false),
    ('helper proteger versión',
     'public.co__proteger_version_monotona()', false, false, false, false),
    ('helper limitar líneas',
     'public.co__limitar_lineas_carrito()', true, false, false, false),
    ('helper validar máximo',
     'public.co__validar_max_lineas_config()', true, false, false, false),
    ('helper agregar C3',
     'public.co__carrito_agregar_c3(uuid,integer)', true, false, false, false),
    ('helper cambiar C3',
     'public.co__carrito_cambiar_c3(uuid,integer,bigint)', true, false, false, false),
    ('helper quitar C3',
     'public.co__carrito_quitar_c3(uuid,bigint)', true, false, false, false),
    ('helper contexto servidor',
     'public.pw__contexto_servidor()', false, false, false, false),
    ('helper resolver histórica',
     'public.pw__resolver_revision_historica(text,text)', true, false, false, false),
    ('helper revisiones C3',
     'public.pw__revisiones_c3()', true, false, false, false)
), resueltas as (
  select e.*,
         to_regprocedure(e.firma) as oid
    from esperadas e
), auditadas as (
  select r.*,
         p.prosecdef,
         p.proconfig,
         pg_get_userbyid(p.proowner) as owner,
         case when r.oid is null then null
              else has_function_privilege('anon', r.oid, 'execute') end as anon_real,
         case when r.oid is null then null
              else has_function_privilege('authenticated', r.oid, 'execute') end as auth_real,
         case when r.oid is null then null
              else has_function_privilege('service_role', r.oid, 'execute') end as service_real
    from resueltas r
    left join pg_proc p on p.oid = r.oid
)
select etiqueta,
       firma,
       oid is not null as existe,
       prosecdef = security_definer as security_definer_ok,
       coalesce('search_path=public' = any(proconfig), false)
         as search_path_publico_ok,
       owner,
       anon_real = anon_exec as anon_ok,
       auth_real = auth_exec as authenticated_ok,
       service_real = service_exec as service_role_ok
  from auditadas
 order by etiqueta;

-- 7/7 · Snapshot detallado de columnas C4 para archivar evidencia estructural.
select table_name,
       ordinal_position,
       column_name,
       data_type,
       udt_name,
       is_nullable,
       column_default
  from information_schema.columns
 where table_schema = 'public'
   and (
     (table_name = 'pedidos' and column_name = any(array[
       'destinatario_nombre', 'destinatario_correo', 'destinatario_telefono'
     ]))
     or (table_name = 'pedido_items' and column_name = any(array[
       'campana_id', 'campana_nombre', 'campana_slug'
     ]))
     or (table_name = 'pagos_intencion' and column_name = any(array[
       'ciclo_carrito_version', 'expira_en', 'carrito_liberado_en',
       'carrito_consumido_en', 'carrito_consumo_resultado',
       'carrito_consumo_detalle'
     ]))
     or table_name = 'pw_sucesiones_c4'
   )
 order by table_name, ordinal_position;

rollback;
