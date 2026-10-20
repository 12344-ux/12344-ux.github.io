-- ============================================================================
-- MAGANDHI · PROMOCIONAR P3 · REANUDAR SOLO CONTEO · IDEMPOTENTE
-- Exige redirect/evidencia vigentes y mantenimiento pg_cron realmente sano
-- en current_database().
-- ============================================================================
begin;
set local search_path = public, pg_catalog, pg_temp;
set local statement_timeout = '30s';
set local lock_timeout = '5s';

select id from public.promocionar_p3_config where id = 1 for update;
do $reanudar$
declare
  v_job_ok boolean := false;
  v_run_ok boolean := false;
begin
  if (select count(*) from public.promocionar_p3_config where id = 1) <> 1 then
    raise exception using errcode = 'P0001', message = 'P3_CONFIG_SINGLETON_AUSENTE';
  end if;
  if not exists (
    select 1 from public.promocionar_p3_config
     where id = 1 and redirect_habilitado
       and politica_publicada and routing_verificado
       and politica_version is not null
  ) then
    raise exception using errcode = 'P0001', message = 'P3_REANUDACION_REQUIERE_REDIRECT_Y_EVIDENCIA';
  end if;

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
end;
$reanudar$;

update public.promocionar_p3_config
   set conteo_habilitado = true,
       actualizado_en = greatest(
         clock_timestamp(), actualizado_en + interval '1 microsecond'
       ),
       actualizado_por = auth.uid(),
       actualizado_razon = 'reanudacion_conteo_operativa',
       actualizado_rol = current_user
 where id = 1 and conteo_habilitado is false;

commit;

select id, activacion_habilitada, redirect_habilitado, conteo_habilitado,
       politica_publicada, routing_verificado, politica_version, actualizado_en,
       (select count(*)::bigint from public.promocionar_p3_config_bitacora)
         as eventos_config,
       conteo_habilitado as conteo_reanudado_confirmado
  from public.promocionar_p3_config
 where id = 1;
