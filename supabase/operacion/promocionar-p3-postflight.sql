-- ============================================================================
-- MAGANDHI · PROMOCIONAR P3 · POSTFLIGHT ESTRUCTURAL · SOLO LECTURA
-- No exige pg_cron: la instalación termina OFF y el cron se agenda después.
-- Esperado: booleanos true, datos iniciales en cero, bitácora_inicial=1 y
-- postflight_ok=true. Una sola fila, sin UUID, actores, códigos, hashes ni PII.
-- ============================================================================
begin transaction read only;
set local search_path = public, pg_catalog, pg_temp;
set local statement_timeout = '25s';
set local lock_timeout = '3s';

with config as (
  select count(*) = 1
         and bool_and(
           id = 1
           and activacion_habilitada is false
           and redirect_habilitado is false
           and conteo_habilitado is false
           and politica_publicada is false
           and routing_verificado is false
           and politica_version is null
           and url_corta_base = 'https://go.magandhi.com'
           and cuota_hora = 600
           and actualizado_razon = 'instalacion_inicial'
           and actualizado_rol <> ''
         ) as config_singleton_off
    from public.promocionar_p3_config
), schemas_definer as (
  select count(*) = 3
         and bool_and(
           not has_schema_privilege(r.rolname, 'public', 'CREATE')
           and case when to_regnamespace('extensions') is null then true
                    else not has_schema_privilege(r.rolname, 'extensions', 'CREATE') end
         ) as roles_api_sin_create_definer
    from pg_roles r
   where r.rolname in ('anon', 'authenticated', 'service_role')
), relaciones as (
  select
    count(*) = 5 as cinco_tablas,
    bool_and(c.relrowsecurity) as rls_habilitada,
    not exists (
      select 1 from pg_policy p
       where p.polrelid = any(array[
         'public.promocionar_p3_config'::regclass,
         'public.promocionar_p3_config_bitacora'::regclass,
         'public.atribucion_enlaces'::regclass,
         'public.atribucion_clics_dia'::regclass,
         'public.atribucion_limite_temporal'::regclass
       ])
    ) as sin_policies,
    not exists (
      select 1
        from pg_class x
        cross join lateral aclexplode(coalesce(x.relacl, acldefault('r', x.relowner))) a
        left join pg_roles r on r.oid = a.grantee
       where x.oid = any(array[
         'public.promocionar_p3_config'::regclass,
         'public.promocionar_p3_config_bitacora'::regclass,
         'public.atribucion_enlaces'::regclass,
         'public.atribucion_clics_dia'::regclass,
         'public.atribucion_limite_temporal'::regclass
       ])
         and (a.grantee = 0 or r.rolname in ('anon','authenticated','service_role'))
    ) as tablas_sin_acl_api,
    not exists (
      select 1
        from pg_class x
        cross join lateral aclexplode(coalesce(x.relacl, acldefault('S', x.relowner))) a
        left join pg_roles r on r.oid = a.grantee
       where x.oid = 'public.promocionar_p3_config_bitacora_id_seq'::regclass
         and (a.grantee = 0 or r.rolname in ('anon','authenticated','service_role'))
    ) as secuencia_sin_acl_api
  from pg_class c
  where c.oid = any(array[
    'public.promocionar_p3_config'::regclass,
    'public.promocionar_p3_config_bitacora'::regclass,
    'public.atribucion_enlaces'::regclass,
    'public.atribucion_clics_dia'::regclass,
    'public.atribucion_limite_temporal'::regclass
  ])
), restricciones as (
  select
    count(*) filter (where conrelid = 'public.promocionar_p3_config'::regclass
      and conname = any(array[
        'promocionar_p3_config_singleton','promocionar_p3_config_url_fija',
        'promocionar_p3_config_cuota_fija','promocionar_p3_config_razon_valida',
        'promocionar_p3_config_rol_valido','promocionar_p3_config_version_valida',
        'promocionar_p3_config_gates_coherentes'
      ]) and convalidated) = 7 as config_constraints_ok,
    count(*) filter (where conrelid = 'public.promocionar_p3_config_bitacora'::regclass
      and conname = any(array[
        'promocionar_p3_config_bitacora_razon_valida',
        'promocionar_p3_config_bitacora_rol_valido',
        'promocionar_p3_config_bitacora_antes_completo'
      ]) and convalidated) = 3 as bitacora_constraints_ok,
    count(*) filter (where conrelid = 'public.atribucion_enlaces'::regclass
      and conname = any(array[
        'atribucion_enlaces_codigo_unico','atribucion_enlaces_campaign_unico',
        'atribucion_enlaces_idempotencia_unica',
        'atribucion_enlaces_idempotencia_hash_formato',
        'atribucion_enlaces_codigo_estado_enlace',
        'atribucion_enlaces_estado_enlace_valido',
        'atribucion_enlaces_destino_tipado','atribucion_enlaces_canal_utm',
        'atribucion_enlaces_campaign_base_formato',
        'atribucion_enlaces_campaign_formato','atribucion_enlaces_content_formato',
        'atribucion_enlaces_no_autorreemplazo',
        'atribucion_enlaces_total_no_negativo',
        'atribucion_enlaces_auditoria_estado_enlace'
      ]) and convalidated) = 14 as enlaces_constraints_ok,
    count(*) filter (where conrelid = 'public.atribucion_clics_dia'::regclass
      and conname in ('atribucion_clics_dia_pkey','atribucion_clics_dia_total_positivo')
      and convalidated) = 2 as clics_constraints_ok,
    count(*) filter (where conrelid = 'public.atribucion_limite_temporal'::regclass
      and conname = any(array[
        'atribucion_limite_temporal_pkey','atribucion_limite_temporal_hash_formato',
        'atribucion_limite_temporal_ventana_hora','atribucion_limite_temporal_conteo',
        'atribucion_limite_temporal_expiracion'
      ]) and convalidated) = 5 as limite_constraints_ok
  from pg_constraint
), indices as (
  select exists (
    select 1
      from pg_index i
      join pg_class x on x.oid = i.indexrelid
      join pg_am am on am.oid = x.relam
     where i.indrelid = 'public.atribucion_clics_dia'::regclass
       and x.relname = 'atribucion_clics_dia_fecha_idx'
       and am.amname = 'btree'
       and not i.indisunique
       and i.indisvalid
       and i.indisready
       and i.indnkeyatts = 2
       and i.indnatts = 2
       and pg_get_indexdef(i.indexrelid, 1, true) = 'fecha_colombia'
       and pg_get_indexdef(i.indexrelid, 2, true) = 'enlace_id'
       and i.indpred is null
       and i.indexprs is null
  ) as clics_fecha_idx_ok
), destino_genealogia as (
  select
    exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = 'atribucion_enlaces'
         and column_name = 'campana_producto_id' and data_type = 'uuid'
         and is_nullable = 'NO'
    ) and exists (
      select 1 from pg_constraint
       where conrelid = 'public.atribucion_enlaces'::regclass
         and conname = 'atribucion_enlaces_destino_tipado' and convalidated
         and pg_get_constraintdef(oid, true) like '%producto_v1%'
         and pg_get_constraintdef(oid, true) like '%home_v1%'
    ) as destino_explicito_ok,
    exists (
      select 1
        from pg_index i
        join pg_class x on x.oid = i.indexrelid
       where i.indrelid = 'public.atribucion_enlaces'::regclass
         and x.relname = 'atribucion_enlaces_reemplaza_unico_idx'
         and i.indisunique and i.indpred is not null
    ) as reemplazo_directo_unico
), temporal as (
  select not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'atribucion_limite_temporal'
       and column_name in (
         'enlace_id','ip','ip_cruda','mg_vid','sesion_id','cuenta_id',
         'cliente_id','customer_id','user_agent','referrer'
       )
  ) and exists (
    select 1 from pg_constraint
     where conrelid = 'public.atribucion_limite_temporal'::regclass
       and conname = 'atribucion_limite_temporal_expiracion'
       and pg_get_constraintdef(oid, true) like '%expira_en <%'
       and (pg_get_constraintdef(oid, true) like '%48 hours%'
            or pg_get_constraintdef(oid, true) like '%48:00:00%')
  ) as limite_sin_vinculo_y_menor_48h
), contratos as (
  select
    (
      select count(*) = 3
        from information_schema.columns
       where table_schema = 'public' and table_name = 'promocionar_p3_config'
         and column_name = any(array[
           'activacion_habilitada','redirect_habilitado','conteo_habilitado'
         ]) and data_type = 'boolean' and is_nullable = 'NO'
    ) as tres_gates_persistidos,
    (
      select count(*) = 2
        from information_schema.columns
       where table_schema = 'public' and table_name = 'promocionar_p3_config'
         and column_name in ('actualizado_razon','actualizado_rol')
         and data_type = 'text' and is_nullable = 'NO'
    ) as config_auditoria_contractual,
    coalesce((
      select p.proargnames = array[
        'p_campana_producto_id','p_tipo_destino','p_canal_promocion',
        'p_campaign_base','p_content','p_clave_idempotencia',
        'p_reemplaza_enlace_id'
      ]::text[]
        from pg_proc p
       where p.oid = to_regprocedure(
         'public.promocionar_p3_crear_borrador(uuid,text,text,text,text,uuid,uuid)'
       )
    ), false) as firma_crear_exacta,
    coalesce((
      select p.proargnames = array[
        'p_enlace_id','p_actualizado_en_esperado','p_tipo_destino',
        'p_canal_promocion','p_campaign_base','p_content'
      ]::text[]
        from pg_proc p
       where p.oid = to_regprocedure(
         'public.promocionar_p3_editar_borrador(uuid,timestamptz,text,text,text,text)'
       )
    ), false) as firma_editar_exacta
), triggers as (
  select
    exists (
      select 1 from pg_trigger t
       where t.tgrelid = 'public.atribucion_enlaces'::regclass
         and t.tgname = 'trg_promocionar_p3_validar_enlace'
         and not t.tgisinternal and t.tgenabled = 'O' and t.tgtype = 31
         and t.tgfoid = 'public.promocionar_p3__validar_enlace()'::regprocedure
    ) as trigger_enlaces_ok,
    exists (
      select 1 from pg_trigger t
       where t.tgrelid = 'public.promocionar_p3_config'::regclass
         and t.tgname = 'trg_promocionar_p3_proteger_config'
         and not t.tgisinternal and t.tgenabled = 'O' and t.tgtype = 31
         and t.tgfoid = 'public.promocionar_p3__proteger_config()'::regprocedure
    ) as trigger_config_ok,
    exists (
      select 1 from pg_trigger t
       where t.tgrelid = 'public.promocionar_p3_config'::regclass
         and t.tgname = 'trg_promocionar_p3_auditar_config'
         and not t.tgisinternal and t.tgenabled = 'O' and t.tgtype = 17
         and t.tgfoid = 'public.promocionar_p3__auditar_config()'::regprocedure
    ) as trigger_auditoria_ok,
    exists (
      select 1 from pg_trigger t
       where t.tgrelid = 'public.promocionar_p3_config_bitacora'::regclass
         and t.tgname = 'trg_promocionar_p3_proteger_config_bitacora'
         and not t.tgisinternal and t.tgenabled = 'O' and t.tgtype = 58
         and t.tgfoid = 'public.promocionar_p3__proteger_config_bitacora()'::regprocedure
    ) as trigger_bitacora_append_only_ok
), esperadas(firma, auth_e, service_e) as (values
  ('public.promocionar_p3__normalizar(text,integer)', false, false),
  ('public.promocionar_p3__contiene_pii(text)', false, false),
  ('public.promocionar_p3__canal_utm(text)', false, false),
  ('public.promocionar_p3__crockford(integer)', false, false),
  ('public.promocionar_p3__campaign_candidato(text)', false, false),
  ('public.promocionar_p3__enlace_json(atribucion_enlaces)', false, false),
  ('public.promocionar_p3__proteger_config()', false, false),
  ('public.promocionar_p3__auditar_config()', false, false),
  ('public.promocionar_p3__proteger_config_bitacora()', false, false),
  ('public.promocionar_p3__validar_enlace()', false, false),
  ('public.promocionar_p3_config()', true, false),
  ('public.promocionar_p3_listar(uuid)', true, false),
  ('public.promocionar_p3_crear_borrador(uuid,text,text,text,text,uuid,uuid)', true, false),
  ('public.promocionar_p3_editar_borrador(uuid,timestamptz,text,text,text,text)', true, false),
  ('public.promocionar_p3_activar(uuid)', true, false),
  ('public.promocionar_p3_desactivar(uuid)', true, false),
  ('public.promocionar_p3_eliminar_borrador(uuid)', true, false),
  ('public.promocionar_p3_resolver(text)', false, true),
  ('public.promocionar_p3_contar(uuid,text)', false, true),
  ('public.promocionar_p3_mantenimiento()', false, false)
), funciones as (
  select count(*) = 20
         and bool_and(oid is not null)
         and bool_and(prosecdef)
         and bool_and(coalesce(
           proconfig = array[
             'search_path=' || case
               when firma in (
                 'public.promocionar_p3__crockford(integer)',
                 'public.promocionar_p3_crear_borrador(uuid,text,text,text,text,uuid,uuid)'
               ) then 'public, extensions, pg_temp'
               else 'public, pg_temp'
             end
           ], false
         ))
         and bool_and(not anon_r)
         and bool_and(auth_r is not distinct from auth_e)
         and bool_and(service_r is not distinct from service_e)
         as funciones_paths_y_acl_ok
  from (
    select e.*, p.oid, p.prosecdef, p.proconfig,
           case when p.oid is null then null else has_function_privilege('anon', p.oid, 'execute') end anon_r,
           case when p.oid is null then null else has_function_privilege('authenticated', p.oid, 'execute') end auth_r,
           case when p.oid is null then null else has_function_privilege('service_role', p.oid, 'execute') end service_r
      from esperadas e
      left join pg_proc p on p.oid = to_regprocedure(e.firma)
  ) f
), datos as (
  select
    (select count(*)::bigint from public.atribucion_enlaces) as enlaces_iniciales,
    (select count(*)::bigint from public.atribucion_clics_dia) as clics_iniciales,
    (select count(*)::bigint from public.atribucion_limite_temporal) as limites_iniciales,
    (select count(*)::bigint from public.promocionar_p3_config_bitacora) as bitacora_inicial,
    exists (
      select 1 from public.promocionar_p3_config_bitacora
       where razon = 'instalacion_inicial'
         and antes_activacion_habilitada is null
         and antes_redirect_habilitado is null
         and antes_conteo_habilitado is null
         and despues_activacion_habilitada is false
         and despues_redirect_habilitado is false
         and despues_conteo_habilitado is false
         and despues_politica_publicada is false
         and despues_routing_verificado is false
         and despues_politica_version is null
    ) as bitacora_estado_inicial_ok
), base as (
  select c.config_singleton_off,
         s.roles_api_sin_create_definer,
         r.cinco_tablas, r.rls_habilitada, r.sin_policies,
         r.tablas_sin_acl_api, r.secuencia_sin_acl_api,
         x.config_constraints_ok, x.bitacora_constraints_ok,
         x.enlaces_constraints_ok, x.clics_constraints_ok, x.limite_constraints_ok,
         i.clics_fecha_idx_ok,
         g.destino_explicito_ok, g.reemplazo_directo_unico,
         tm.limite_sin_vinculo_y_menor_48h,
         ct.tres_gates_persistidos, ct.config_auditoria_contractual,
         ct.firma_crear_exacta, ct.firma_editar_exacta,
         t.trigger_enlaces_ok, t.trigger_config_ok, t.trigger_auditoria_ok,
         t.trigger_bitacora_append_only_ok,
         f.funciones_paths_y_acl_ok,
         has_function_privilege('postgres', 'public.promocionar_p3_mantenimiento()', 'execute')
           as mantenimiento_postgres_ok,
         d.enlaces_iniciales, d.clics_iniciales, d.limites_iniciales,
         d.bitacora_inicial, d.bitacora_estado_inicial_ok
    from config c
    cross join schemas_definer s
    cross join relaciones r
    cross join restricciones x
    cross join indices i
    cross join destino_genealogia g
    cross join temporal tm
    cross join contratos ct
    cross join triggers t
    cross join funciones f
    cross join datos d
), resumen as (
  select b.*,
         b.config_singleton_off and b.roles_api_sin_create_definer
         and b.cinco_tablas and b.rls_habilitada and b.sin_policies
         and b.tablas_sin_acl_api and b.secuencia_sin_acl_api
         and b.config_constraints_ok and b.bitacora_constraints_ok
         and b.enlaces_constraints_ok and b.clics_constraints_ok
         and b.limite_constraints_ok and b.clics_fecha_idx_ok
         and b.destino_explicito_ok
         and b.reemplazo_directo_unico and b.limite_sin_vinculo_y_menor_48h
         and b.tres_gates_persistidos and b.config_auditoria_contractual
         and b.firma_crear_exacta and b.firma_editar_exacta
         and b.trigger_enlaces_ok and b.trigger_config_ok
         and b.trigger_auditoria_ok and b.trigger_bitacora_append_only_ok
         and b.funciones_paths_y_acl_ok and b.mantenimiento_postgres_ok
         and b.enlaces_iniciales = 0 and b.clics_iniciales = 0
         and b.limites_iniciales = 0 and b.bitacora_inicial = 1
         and b.bitacora_estado_inicial_ok as postflight_ok
    from base b
)
select * from resumen;

rollback;
