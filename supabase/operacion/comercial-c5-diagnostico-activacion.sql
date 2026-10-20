-- ============================================================================
-- MAGANDHI · COMERCIAL C5 · DIAGNÓSTICO DE ACTIVACIÓN (solo lectura)
-- ----------------------------------------------------------------------------
-- Evalúa por separado cada condición de comercial-c5-activar.sql y devuelve
-- UNA sola tabla: lo que hoy impediría activar (filas «FALLA ·», con detalle)
-- o una única fila «Todo correcto». El SQL Editor de Supabase muestra solo el
-- último resultado, por eso todo sale en una sola consulta.
-- No devuelve PII, referencias, UUID, transacciones, motivos ni llaves.
-- ============================================================================
begin transaction read only;
set local search_path = pg_catalog, public;
set local statement_timeout = '20s';
set local lock_timeout = '3s';

with chequeos(orden, chequeo, falla) as (values
  (101, 'el carrito no está apagado (o falta la fila única de configuración)',
    (select count(*) from comercial_config where id = 1) <> 1
    or not exists (select 1 from comercial_config
                    where id = 1 and carrito_habilitado is false)),
  (201, 'falta la función mc_compras_listar()',
    to_regprocedure('public.mc_compras_listar()') is null),
  (202, 'falta la función mc_reabrir_intencion_c5(text,uuid)',
    to_regprocedure('public.mc_reabrir_intencion_c5(text,uuid)') is null),
  (203, 'falta la función pw__procesar_pago_c5',
    to_regprocedure('public.pw__procesar_pago_c5(text,text,text,bigint,text,text,text,jsonb,text,text)') is null),
  (204, 'falta la función pw__procesar_pago_c4',
    to_regprocedure('public.pw__procesar_pago_c4(text,text,text,bigint,text,text,text,jsonb,text,text)') is null),
  (205, 'falta la función pw__estado_checkout_publico_c4(text,uuid)',
    to_regprocedure('public.pw__estado_checkout_publico_c4(text,uuid)') is null),
  (206, 'falta la función cm__asignar_slug_automatico()',
    to_regprocedure('public.cm__asignar_slug_automatico()') is null),
  (207, 'columnas C5/slug ausentes o con tipo/nulabilidad distinta',
    not (select count(c.column_name) = 4
                and bool_and(c.data_type = e.tipo and c.is_nullable = e.nullable)
           from (values
             ('pagos_intencion', 'carrito_separado_en', 'timestamp with time zone', 'YES'),
             ('pagos_intencion', 'carrito_version_sucesora', 'bigint', 'YES'),
             ('pagos_intencion', 'carrito_separacion_detalle', 'jsonb', 'YES'),
             ('campana_producto', 'slug', 'text', 'NO')
           ) e(tabla, columna, tipo, nullable)
           left join information_schema.columns c
             on c.table_schema = 'public'
            and c.table_name = e.tabla
            and c.column_name = e.columna)),
  (208, 'restricciones C4/C5 de pagos_intencion incompletas o sin validar',
    (select count(*) from pg_constraint
      where conrelid = 'public.pagos_intencion'::regclass
        and convalidated
        and conname = any(array[
          'pagos_intencion_ciclo_carrito_version',
          'pagos_intencion_expiracion_c4_c5',
          'pagos_intencion_separacion_c5',
          'pagos_intencion_consumo_carrito_resultado',
          'pagos_intencion_ciclo_carrito_solo_v2',
          'pagos_intencion_consumo_carrito_coherente'])) <> 6),
  (209, 'índice pagos_intencion_c5_propietario_idx ausente o distinto',
    not exists (select 1 from pg_index i
      join pg_class x on x.oid = i.indexrelid
      join pg_class t on t.oid = i.indrelid
      join pg_namespace n on n.oid = t.relnamespace
     where n.nspname = 'public' and t.relname = 'pagos_intencion'
       and x.relname = 'pagos_intencion_c5_propietario_idx' and not i.indisunique
       and i.indnkeyatts = 2
       and pg_get_indexdef(i.indexrelid, 1, true) = 'auth_user_id'
       and pg_get_indexdef(i.indexrelid, 2, true) = 'creado DESC'
       and pg_get_expr(i.indpred, i.indrelid) =
         '((version_checkout = 2) AND (ciclo_carrito_version = 5))')),
  (210, 'índice pagos_intencion_c5_expiracion_idx ausente o distinto',
    not exists (select 1 from pg_index i
      join pg_class x on x.oid = i.indexrelid
      join pg_class t on t.oid = i.indrelid
      join pg_namespace n on n.oid = t.relnamespace
     where n.nspname = 'public' and t.relname = 'pagos_intencion'
       and x.relname = 'pagos_intencion_c5_expiracion_idx' and not i.indisunique
       and i.indnkeyatts = 1
       and pg_get_indexdef(i.indexrelid, 1, true) = 'expira_en'
       and pg_get_expr(i.indpred, i.indrelid) =
         '((ciclo_carrito_version = 5) AND (estado = ''creada''::text) AND (transaccion_id IS NULL))')),
  (211, 'índice único pagos_intencion_carrito_version_v2_uidx ausente o distinto',
    not exists (select 1 from pg_index i
      join pg_class x on x.oid = i.indexrelid
      join pg_class t on t.oid = i.indrelid
      join pg_namespace n on n.oid = t.relnamespace
     where n.nspname = 'public' and t.relname = 'pagos_intencion'
       and x.relname = 'pagos_intencion_carrito_version_v2_uidx'
       and i.indisunique and i.indisvalid and i.indisready
       and i.indnkeyatts = 3
       and pg_get_indexdef(i.indexrelid, 1, true) = 'auth_user_id'
       and pg_get_indexdef(i.indexrelid, 2, true) = 'carrito_id'
       and pg_get_indexdef(i.indexrelid, 3, true) = 'carrito_version'
       and pg_get_expr(i.indpred, i.indrelid) = '(version_checkout = 2)')),
  (212, 'índice único campana_producto_slug_key ausente o distinto',
    not exists (select 1 from pg_index i
      join pg_class x on x.oid = i.indexrelid
      join pg_class t on t.oid = i.indrelid
      join pg_namespace n on n.oid = t.relnamespace
     where n.nspname = 'public' and t.relname = 'campana_producto'
       and x.relname = 'campana_producto_slug_key' and i.indisunique
       and i.indnkeyatts = 1
       and pg_get_indexdef(i.indexrelid, 1, true) = 'slug'
       and pg_get_expr(i.indpred, i.indrelid) = '(slug IS NOT NULL)')),
  (213, 'trigger trg_pw_marcar_ciclo_carrito_c5 ausente o distinto',
    not exists (select 1 from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'pagos_intencion'
       and t.tgname = 'trg_pw_marcar_ciclo_carrito_c5'
       and not t.tgisinternal and t.tgenabled = 'O' and t.tgtype = 7
       and t.tgfoid = to_regprocedure('public.pw__marcar_ciclo_carrito_c5()'))),
  (214, 'trigger trg_cm_slug_automatico ausente o distinto',
    not exists (select 1 from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'campana_producto'
       and t.tgname = 'trg_cm_slug_automatico'
       and not t.tgisinternal and t.tgenabled = 'O' and t.tgtype = 23
       and t.tgfoid = to_regprocedure('public.cm__asignar_slug_automatico()'))),
  (215, 'el trigger C4 trg_pw_marcar_ciclo_carrito_c4 sigue existiendo',
    exists (select 1 from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'pagos_intencion'
       and t.tgname = 'trg_pw_marcar_ciclo_carrito_c4'
       and not t.tgisinternal)),
  (250, 'la política RLS de pagos_intencion no es exactamente la esperada',
    not (select count(*) = 1 and bool_and(
           policyname = 'pagos_intencion_select_ventas'
           and cmd = 'SELECT'
           and permissive = 'PERMISSIVE'
           and roles = array['authenticated']::name[]
           and qual = 'tiene_acceso_pagos()'
           and with_check is null)
           from pg_policies
          where schemaname = 'public' and tablename = 'pagos_intencion')),
  (260, 'pw_sucesiones_c4 tiene políticas RLS (debe tener cero)',
    exists (select 1 from pg_policies
             where schemaname = 'public' and tablename = 'pw_sucesiones_c4')),
  (701, 'hay cuentas con más de un carrito activo',
    exists (select 1 from carritos where estado = 'activa'
             group by auth_user_id having count(*) > 1)),
  (702, 'hay líneas de carrito huérfanas',
    exists (select 1 from carrito_items ci
              left join carritos c on c.id = ci.carrito_id
             where c.id is null)),
  (703, 'hay intenciones históricas v0/v1 reetiquetadas',
    exists (select 1 from pagos_intencion
             where version_checkout in (0, 1) and ciclo_carrito_version <> 0)),
  (704, 'historia C3/C4 marcada con campos de separación C5',
    exists (select 1 from pagos_intencion
             where ciclo_carrito_version in (0, 4)
               and (carrito_separado_en is not null
                 or carrito_version_sucesora is not null
                 or carrito_separacion_detalle is not null))),
  (705, 'cabeceras de intenciones C5 incoherentes',
    exists (select 1 from pagos_intencion
             where ciclo_carrito_version = 5
               and (expira_en is null or carrito_separado_en is null
                 or carrito_version_sucesora is distinct from carrito_version + 1
                 or carrito_separacion_detalle is null
                 or carrito_consumido_en is not null
                 or carrito_consumo_resultado is not null
                 or carrito_consumo_detalle is not null))),
  (706, 'snapshots de intenciones C5 incoherentes',
    exists (select 1
              from pagos_intencion pi
              left join lateral (
                select count(*)::bigint as cantidad,
                       min(i.ordinal)::integer as ordinal_minimo,
                       max(i.ordinal)::integer as ordinal_maximo,
                       sum(i.subtotal::numeric * 100) as total_centavos
                  from pagos_intencion_items i
                 where i.referencia = pi.referencia
              ) l on true
             where pi.ciclo_carrito_version = 5
               and (l.cantidad not between 1 and 20
                 or l.ordinal_minimo <> 1
                 or l.ordinal_maximo <> l.cantidad
                 or l.total_centavos is distinct from pi.monto_centavos::numeric))),
  (707, 'intenciones C5 procesadas sin pedido',
    exists (select 1 from pagos_intencion
             where ciclo_carrito_version = 5
               and estado = 'procesada' and pedido_id is null)),
  (708, 'slugs vacíos, no normalizados o demasiado largos',
    exists (select 1 from campana_producto
             where slug is null or btrim(slug) = ''
                or slug is distinct from cm_normalizar_slug(slug)
                or length(slug) > 180)),
  (709, 'slugs duplicados',
    exists (select slug from campana_producto
             group by slug having count(*) > 1))
),
acl_funciones(orden, rol, firma, esperado) as (values
  (301, 'anon',          'public.mc_compras_listar()',                false),
  (302, 'authenticated', 'public.mc_compras_listar()',                true),
  (303, 'authenticated', 'public.mc_reabrir_intencion_c5(text,uuid)', false),
  (304, 'service_role',  'public.mc_reabrir_intencion_c5(text,uuid)', true),
  (305, 'service_role',  'public.cm__asignar_slug_automatico()',      false)
),
acl_tablas(orden, rol, tabla, privilegio, esperado) as (values
  (401, 'anon',          'campana_producto',      'select', false),
  (402, 'authenticated', 'campana_producto',      'select', true),
  (403, 'authenticated', 'campana_producto',      'insert', false),
  (404, 'authenticated', 'campana_producto',      'update', false),
  (405, 'authenticated', 'campana_producto',      'delete', false),
  (406, 'anon',          'catalogo_publico',      'select', true),
  (407, 'anon',          'comercial_config',      'select', false),
  (408, 'authenticated', 'comercial_config',      'select', false),
  (409, 'anon',          'pagos_intencion_items', 'select', false),
  (410, 'authenticated', 'pagos_intencion_items', 'select', false),
  (411, 'service_role',  'pagos_intencion_items', 'select', true),
  (412, 'service_role',  'pagos_intencion_items', 'insert', true),
  (413, 'service_role',  'pagos_intencion_items', 'update', true),
  (414, 'service_role',  'pagos_intencion_items', 'delete', true),
  (415, 'anon',          'pagos_intencion',       'select', false),
  (416, 'authenticated', 'pagos_intencion',       'select', true),
  (417, 'authenticated', 'pagos_intencion',       'insert', false),
  (418, 'authenticated', 'pagos_intencion',       'update', false),
  (419, 'authenticated', 'pagos_intencion',       'delete', false),
  (420, 'anon',          'pw_sucesiones_c4',      'select', false),
  (421, 'authenticated', 'pw_sucesiones_c4',      'select', false),
  (422, 'service_role',  'pw_sucesiones_c4',      'select', false),
  (423, 'authenticated', 'carritos',              'select', true),
  (424, 'authenticated', 'carritos',              'insert', false),
  (425, 'authenticated', 'carritos',              'update', false),
  (426, 'authenticated', 'carritos',              'delete', false),
  (427, 'authenticated', 'carrito_items',         'select', true),
  (428, 'authenticated', 'carrito_items',         'insert', false),
  (429, 'authenticated', 'carrito_items',         'update', false),
  (430, 'authenticated', 'carrito_items',         'delete', false),
  (431, 'anon',          'pedidos',               'select', false),
  (432, 'authenticated', 'pedidos',               'select', true),
  (433, 'authenticated', 'pedidos',               'insert', false),
  (434, 'authenticated', 'pedidos',               'update', false),
  (435, 'authenticated', 'pedidos',               'delete', false),
  (436, 'anon',          'pedido_items',          'select', false),
  (437, 'authenticated', 'pedido_items',          'select', true),
  (438, 'authenticated', 'pedido_items',          'insert', false),
  (439, 'authenticated', 'pedido_items',          'update', false),
  (440, 'authenticated', 'pedido_items',          'delete', false)
),
firmas(orden, firma, definer, anon_e, auth_e, service_e) as (values
  (601, 'public.pw_registrar_intencion_carrito(text,uuid,uuid,bigint,text,jsonb,text,text,text)', true, false, false, true),
  (602, 'public.pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text)', true, false, false, true),
  (603, 'public.pw_estado_checkout_publico(text,uuid)', true, false, false, true),
  (604, 'public.mc_compras_listar()', true, false, true, true),
  (605, 'public.mc_reabrir_intencion_c5(text,uuid)', true, false, false, true),
  (606, 'public.avanzar_estado_pedido(uuid,text)', true, false, true, true),
  (607, 'public.pw__registrar_intencion_carrito_c4(text,uuid,uuid,bigint,text,jsonb,text,text,text)', true, false, false, false),
  (608, 'public.pw__procesar_pago_c4(text,text,text,bigint,text,text,text,jsonb,text,text)', true, false, false, false),
  (609, 'public.pw__procesar_pago_c5(text,text,text,bigint,text,text,text,jsonb,text,text)', true, false, false, false),
  (610, 'public.pw__estado_checkout_publico_c4(text,uuid)', true, false, false, false),
  (611, 'public.pw__snapshot_intencion_c5(text)', true, false, false, false),
  (612, 'public.pw__expirar_intencion_c5(text)', true, false, false, false),
  (613, 'public.pw__marcar_ciclo_carrito_c5()', false, false, false, false),
  (614, 'public.cm__asignar_slug_automatico()', true, false, false, false),
  (615, 'public.cm_crear_campana(text,text,text,text,text,bigint,text,text,text,jsonb,jsonb,boolean,boolean,integer,boolean,integer,text[],uuid,text,integer,boolean,integer)', true, false, true, true),
  (616, 'public.cm_editar_campana(uuid,text,text,text,text,text,bigint,text,text,text,jsonb,jsonb,boolean,boolean,integer,boolean,integer,text[],uuid,text,integer,boolean,integer)', true, false, true, true)
),
firmas_r as (
  select f.*, to_regprocedure(f.firma) as fn
    from firmas f
),
fallas(orden, detalle) as (
  select ch.orden, 'FALLA · ' || ch.chequeo
    from chequeos ch
   where ch.falla
  union all
  select a.orden, 'FALLA · permiso EXECUTE inesperado: ' || a.rol || ' sobre '
         || a.firma || ' (esperado: '
         || case when a.esperado then 'sí' else 'no' end || ')'
    from acl_funciones a
   where has_function_privilege(a.rol::name, to_regprocedure(a.firma), 'execute')
         is distinct from a.esperado
  union all
  select t.orden, 'FALLA · privilegio de tabla inesperado: ' || t.rol || ' '
         || upper(t.privilegio) || ' en ' || t.tabla || ' (esperado: '
         || case when t.esperado then 'sí' else 'no' end || ')'
    from acl_tablas t
   where has_table_privilege(t.rol::name, 'public.' || t.tabla, t.privilegio)
         is distinct from t.esperado
  union all
  select 500, 'FALLA · RLS apagado en ' || c.relname::text
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname = any(array['comercial_config', 'carritos', 'carrito_items',
       'pagos_intencion', 'pagos_intencion_items', 'pw_sucesiones_c4',
       'pedidos', 'pedido_items', 'campana_producto'])
     and not c.relrowsecurity
  union all
  select f.orden, 'FALLA · función ' || f.firma || ': ' || concat_ws(', ',
           case when f.fn is null then 'no existe' end,
           case when f.fn is not null and p.prosecdef is distinct from f.definer
                then 'SECURITY DEFINER distinto' end,
           case when f.fn is not null
                 and coalesce('search_path=public' = any(p.proconfig), false) is not true
                then 'search_path distinto de public' end,
           case when f.fn is not null
                 and has_function_privilege('anon', f.fn, 'execute') is distinct from f.anon_e
                then 'EXECUTE de anon distinto' end,
           case when f.fn is not null
                 and has_function_privilege('authenticated', f.fn, 'execute') is distinct from f.auth_e
                then 'EXECUTE de authenticated distinto' end,
           case when f.fn is not null
                 and has_function_privilege('service_role', f.fn, 'execute') is distinct from f.service_e
                then 'EXECUTE de service_role distinto' end)
    from firmas_r f
    left join pg_proc p on p.oid = f.fn
   where f.fn is null
      or p.prosecdef is distinct from f.definer
      or coalesce('search_path=public' = any(p.proconfig), false) is not true
      or has_function_privilege('anon', f.fn, 'execute') is distinct from f.anon_e
      or has_function_privilege('authenticated', f.fn, 'execute') is distinct from f.auth_e
      or has_function_privilege('service_role', f.fn, 'execute') is distinct from f.service_e
  union all
  select 290, 'detalle · índice ' || x.relname::text || ' = '
         || pg_get_indexdef(i.indexrelid) || ' · válido=' || i.indisvalid::text
    from pg_index i
    join pg_class x on x.oid = i.indexrelid
    join pg_namespace n on n.oid = x.relnamespace
   where n.nspname = 'public'
     and x.relname = any(array['pagos_intencion_c5_propietario_idx',
       'pagos_intencion_c5_expiracion_idx',
       'pagos_intencion_carrito_version_v2_uidx',
       'campana_producto_slug_key'])
     and exists (select 1 from chequeos ch
                  where ch.falla and ch.orden between 209 and 212)
  union all
  select 291, 'detalle · trigger ' || t.tgname::text || ' en ' || c.relname::text
         || ' · tipo=' || t.tgtype::text || ' · estado=' || t.tgenabled::text
         || ' · ' || pg_get_triggerdef(t.oid)
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and not t.tgisinternal
     and t.tgname = any(array['trg_pw_marcar_ciclo_carrito_c5',
       'trg_cm_slug_automatico', 'trg_pw_marcar_ciclo_carrito_c4'])
     and exists (select 1 from chequeos ch
                  where ch.falla and ch.orden between 213 and 215)
  union all
  select 292, 'detalle · política ' || p.policyname::text || ' · ' || p.cmd
         || ' · ' || p.permissive || ' · roles=' || p.roles::text
         || ' · using=' || coalesce(p.qual, '∅')
         || ' · check=' || coalesce(p.with_check, '∅')
    from pg_policies p
   where p.schemaname = 'public' and p.tablename = 'pagos_intencion'
     and exists (select 1 from chequeos ch where ch.falla and ch.orden = 250)
  union all
  select 293, 'detalle · restricción ' || c.conname::text
         || ' · validada=' || c.convalidated::text
    from pg_constraint c
   where c.conrelid = 'public.pagos_intencion'::regclass
     and c.contype = 'c'
     and exists (select 1 from chequeos ch where ch.falla and ch.orden = 208)
  union all
  select 294, 'detalle · columna ' || col.table_name::text || '.'
         || col.column_name::text || ' · ' || col.data_type::text
         || ' · nullable=' || col.is_nullable::text
    from information_schema.columns col
   where col.table_schema = 'public'
     and ((col.table_name = 'pagos_intencion'
           and col.column_name in ('carrito_separado_en',
             'carrito_version_sucesora', 'carrito_separacion_detalle'))
       or (col.table_name = 'campana_producto' and col.column_name = 'slug'))
     and exists (select 1 from chequeos ch where ch.falla and ch.orden = 207)
)
select orden as "#", detalle as resultado
  from fallas
union all
select 0, 'Todo correcto: la activación pasará'
 where not exists (select 1 from fallas)
order by 1, 2;

rollback;
