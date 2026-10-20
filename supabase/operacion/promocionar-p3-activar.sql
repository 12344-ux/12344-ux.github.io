-- ============================================================================
-- MAGANDHI · PROMOCIONAR P3 · ACTIVACIÓN GLOBAL CONTROLADA
-- ESCRITURA DELIBERADA. NO EJECUTAR TODAVÍA.
--
-- Antes de un Run aprobado, cambiar a true CADA confirmación técnica.
-- Este archivo no exige política ni consentimiento: P3 redirige sin cookies,
-- banner, popup, modal o aviso intermedio. Sí exige pg_cron sano
-- en current_database(), último run de ese job/base exitoso <= 2h y cero trabajo
-- de retención vencido.
-- ============================================================================
begin;
set local search_path = public, pg_catalog, pg_temp;
set local statement_timeout = '30s';
set local lock_timeout = '5s';

select id from public.promocionar_p3_config where id = 1 for update;

do $activar$
declare
  -- CONFIRMACIONES OBLIGATORIAS: editar únicamente durante la ventana aprobada.
  v_confirmo_postflight_verde boolean := false;
  v_confirmo_edge_desplegada_verify_jwt_off boolean := false;
  v_confirmo_dns_tls_y_routing boolean := false;
  v_confirmo_sondas_http_y_no_open_redirect boolean := false;
  v_job_ok boolean := false;
  v_run_ok boolean := false;
  v_ya_activo boolean := false;
  v_filas integer;
begin
  if not v_confirmo_postflight_verde
     or not v_confirmo_edge_desplegada_verify_jwt_off
     or not v_confirmo_dns_tls_y_routing
     or not v_confirmo_sondas_http_y_no_open_redirect then
    raise exception using
      errcode = 'P0001',
      message = 'P3_ACTIVACION_REQUIERE_PARAMETROS_Y_EVIDENCIA_EXPLICITOS';
  end if;

  if (select count(*) from public.promocionar_p3_config where id = 1) <> 1 then
    raise exception using errcode = 'P0001', message = 'P3_CONFIG_SINGLETON_AUSENTE';
  end if;

  if exists (
    select 1
      from pg_roles r
     where r.rolname in ('anon', 'authenticated', 'service_role')
       and (
         has_schema_privilege(r.rolname, 'public', 'CREATE')
         or case when to_regnamespace('extensions') is null then false
                 else has_schema_privilege(r.rolname, 'extensions', 'CREATE') end
       )
  ) or to_regprocedure('public.promocionar_p3_resolver(text)') is null
     or to_regprocedure('public.promocionar_p3_contar(uuid,text)') is null
     or to_regprocedure('public.promocionar_p3_mantenimiento()') is null
     or not exists (
       select 1 from pg_trigger t
        where t.tgrelid = 'public.atribucion_enlaces'::regclass
          and t.tgname = 'trg_promocionar_p3_validar_enlace'
          and not t.tgisinternal and t.tgenabled = 'O' and t.tgtype = 31
          and t.tgfoid = 'public.promocionar_p3__validar_enlace()'::regprocedure
     )
     or not exists (
       select 1 from pg_trigger t
        where t.tgrelid = 'public.promocionar_p3_config'::regclass
          and t.tgname = 'trg_promocionar_p3_auditar_config'
          and not t.tgisinternal and t.tgenabled = 'O' and t.tgtype = 17
          and t.tgfoid = 'public.promocionar_p3__auditar_config()'::regprocedure
     )
     or not exists (
       select 1 from pg_trigger t
        where t.tgrelid = 'public.promocionar_p3_config_bitacora'::regclass
          and t.tgname = 'trg_promocionar_p3_proteger_config_bitacora'
          and not t.tgisinternal and t.tgenabled = 'O' and t.tgtype = 58
          and t.tgfoid = 'public.promocionar_p3__proteger_config_bitacora()'::regprocedure
     )
     or exists (
       select 1 from pg_class c
        where c.oid = any(array[
          'public.promocionar_p3_config'::regclass,
          'public.promocionar_p3_config_bitacora'::regclass,
          'public.atribucion_enlaces'::regclass,
          'public.atribucion_clics_dia'::regclass,
          'public.atribucion_limite_temporal'::regclass
        ]) and not c.relrowsecurity
     )
     or exists (
       select 1 from pg_policy p
        where p.polrelid = any(array[
          'public.promocionar_p3_config'::regclass,
          'public.promocionar_p3_config_bitacora'::regclass,
          'public.atribucion_enlaces'::regclass,
          'public.atribucion_clics_dia'::regclass,
          'public.atribucion_limite_temporal'::regclass
        ])
     )
     or exists (
       select 1
         from pg_class c
         cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
         left join pg_roles r on r.oid = a.grantee
        where c.oid = any(array[
          'public.promocionar_p3_config'::regclass,
          'public.promocionar_p3_config_bitacora'::regclass,
          'public.atribucion_enlaces'::regclass,
          'public.atribucion_clics_dia'::regclass,
          'public.atribucion_limite_temporal'::regclass
        ]) and (a.grantee = 0 or r.rolname in ('anon','authenticated','service_role'))
     )
     or has_function_privilege('anon', 'public.promocionar_p3_resolver(text)', 'execute')
     or has_function_privilege('authenticated', 'public.promocionar_p3_resolver(text)', 'execute')
     or not has_function_privilege('service_role', 'public.promocionar_p3_resolver(text)', 'execute')
     or has_function_privilege('anon', 'public.promocionar_p3_contar(uuid,text)', 'execute')
     or has_function_privilege('authenticated', 'public.promocionar_p3_contar(uuid,text)', 'execute')
     or not has_function_privilege('service_role', 'public.promocionar_p3_contar(uuid,text)', 'execute')
     or has_function_privilege('anon', 'public.promocionar_p3_mantenimiento()', 'execute')
     or has_function_privilege('authenticated', 'public.promocionar_p3_mantenimiento()', 'execute')
     or has_function_privilege('service_role', 'public.promocionar_p3_mantenimiento()', 'execute')
     or not has_function_privilege('postgres', 'public.promocionar_p3_mantenimiento()', 'execute') then
    raise exception using errcode = 'P0001', message = 'P3_INSTALACION_NO_AUTORIZA_ACTIVACION';
  end if;

  -- Referencias dinámicas: si pg_cron o sus relaciones no existen, el archivo
  -- falla con un mensaje P3 controlado en vez de fallar durante el parseo.
  if not exists (select 1 from pg_extension where extname = 'pg_cron')
     or to_regclass('cron.job') is null
     or to_regclass('cron.job_run_details') is null then
    raise exception using errcode = 'P0001', message = 'P3_CRON_NO_INSTALADO';
  end if;

  execute $cron$
    select count(*) = 1
           and coalesce(bool_and(
             j.active
             and j.database = current_database()
             and j.schedule = '7 * * * *'
             and btrim(j.command) = 'select public.promocionar_p3_mantenimiento();'
           ), false)
      from cron.job j
     where j.jobname = 'promocionar-p3-mantenimiento-horario'
  $cron$ into v_job_ok;

  execute $cron$
    select exists (
      select 1
        from (
          select d.status, d.end_time
            from cron.job_run_details d
            join cron.job j on j.jobid = d.jobid
           where j.jobname = 'promocionar-p3-mantenimiento-horario'
             and j.database = current_database()
           order by d.runid desc
           limit 1
        ) ultimo
       where ultimo.status = 'succeeded'
         and ultimo.end_time is not null
         and ultimo.end_time >= statement_timestamp() - interval '2 hours'
         and ultimo.end_time <= statement_timestamp()
    )
  $cron$ into v_run_ok;

  if not v_job_ok then
    raise exception using errcode = 'P0001', message = 'P3_CRON_JOB_INVALIDO';
  end if;
  if not v_run_ok then
    raise exception using errcode = 'P0001', message = 'P3_CRON_ULTIMO_RUN_NO_SANO';
  end if;

  if exists (
       select 1 from public.atribucion_limite_temporal
        where expira_en <= statement_timestamp()
     ) or exists (
       select 1 from public.atribucion_clics_dia
        where fecha_colombia < (
          (statement_timestamp() at time zone 'America/Bogota')::date
          - interval '13 months'
        )::date
     ) then
    raise exception using errcode = 'P0001', message = 'P3_MANTENIMIENTO_TIENE_VENCIDOS';
  end if;

  select exists (
    select 1 from public.promocionar_p3_config
     where id = 1
       and activacion_habilitada and redirect_habilitado and conteo_habilitado
       and routing_verificado
  ) into v_ya_activo;
  if v_ya_activo then
    return;
  end if;

  if not exists (
    select 1 from public.promocionar_p3_config
     where id = 1
       and activacion_habilitada is false
       and redirect_habilitado is false
       and conteo_habilitado is false
       and url_corta_base = 'https://go.magandhi.com'
       and cuota_hora = 600
  ) then
    raise exception using errcode = 'P0001', message = 'P3_ACTIVACION_REQUIERE_SINGLETON_OFF';
  end if;

  update public.promocionar_p3_config
     set routing_verificado = true,
         activacion_habilitada = true,
         redirect_habilitado = true,
         conteo_habilitado = true,
         actualizado_en = greatest(
           clock_timestamp(), actualizado_en + interval '1 microsecond'
         ),
         actualizado_por = auth.uid(),
         actualizado_razon = 'activacion_global_p3',
         actualizado_rol = current_user
   where id = 1
     and activacion_habilitada is false
     and redirect_habilitado is false
     and conteo_habilitado is false;
  get diagnostics v_filas = row_count;
  if v_filas <> 1 then
    raise exception using errcode = 'P0001', message = 'P3_GATES_NO_ACTUALIZADOS';
  end if;
end;
$activar$;

commit;

select id, activacion_habilitada, redirect_habilitado, conteo_habilitado,
       politica_publicada, routing_verificado, politica_version,
       url_corta_base, cuota_hora, actualizado_en,
       (select count(*)::bigint from public.promocionar_p3_config_bitacora)
         as eventos_config,
       activacion_habilitada and redirect_habilitado and conteo_habilitado
         and routing_verificado as activado_confirmado
  from public.promocionar_p3_config
 where id = 1;
