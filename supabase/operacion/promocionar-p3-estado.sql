-- ============================================================================
-- MAGANDHI · PROMOCIONAR P3 · ESTADO OPERATIVO AGREGADO · SOLO LECTURA
-- Una sola tabla; no muestra códigos, UUID, hashes, actores, razones, secretos
-- ni PII. pg_cron se consulta dinámicamente para tolerar instalación aún OFF.
-- ============================================================================
begin transaction read only;
set local search_path = public, pg_catalog, pg_temp;
set local statement_timeout = '20s';
set local lock_timeout = '3s';

do $medir_cron$
declare
  v_instalado boolean := false;
  v_job_ok boolean := false;
  v_run_ok boolean := false;
begin
  v_instalado := exists (select 1 from pg_extension where extname = 'pg_cron')
                 and to_regclass('cron.job') is not null
                 and to_regclass('cron.job_run_details') is not null;
  if v_instalado then
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
  end if;

  perform set_config('promocionar_p3.cron_instalado', v_instalado::text, true);
  perform set_config('promocionar_p3.cron_job_ok', v_job_ok::text, true);
  perform set_config('promocionar_p3.cron_run_ok', v_run_ok::text, true);
end;
$medir_cron$;

with cfg as (
  select * from public.promocionar_p3_config where id = 1
), cron_estado as (
  select current_setting('promocionar_p3.cron_instalado')::boolean as instalado,
         current_setting('promocionar_p3.cron_job_ok')::boolean as job_ok,
         current_setting('promocionar_p3.cron_run_ok')::boolean as run_ok
), medidas(orden, metrica, valor, alerta) as (
  select 1, 'Gate · activación de enlaces',
         coalesce((select activacion_habilitada::text from cfg), 'sin fila'),
         case when (select count(*) from cfg) <> 1 then 'FALLA · singleton' else '' end
  union all
  select 2, 'Gate · redirect público',
         coalesce((select redirect_habilitado::text from cfg), 'sin fila'), ''
  union all
  select 3, 'Gate · conteo aproximado',
         coalesce((select conteo_habilitado::text from cfg), 'sin fila'), ''
  union all
  select 4, 'Política publicada',
         coalesce((select politica_publicada::text from cfg), 'sin fila'), ''
  union all
  select 5, 'Versión de política configurada',
         coalesce((select (politica_version is not null)::text from cfg), 'sin fila'), ''
  union all
  select 6, 'Routing verificado',
         coalesce((select routing_verificado::text from cfg), 'sin fila'), ''
  union all
  select 7, 'URL corta cerrada',
         coalesce((select (url_corta_base = 'https://go.magandhi.com')::text from cfg), 'sin fila'),
         case when exists (select 1 from cfg where url_corta_base <> 'https://go.magandhi.com')
              then 'FALLA · contradicción' else '' end
  union all
  select 8, 'Mantenimiento · pg_cron instalado', instalado::text,
         case when instalado then ''
              when exists (select 1 from cfg where activacion_habilitada or redirect_habilitado or conteo_habilitado)
                then 'FALLA · gates encendidos sin cron'
              else 'PENDIENTE · requerido antes de activar' end
    from cron_estado
  union all
  select 9, 'Mantenimiento · job nominal activo en base actual', job_ok::text,
         case when job_ok then ''
              when exists (select 1 from cfg where activacion_habilitada or redirect_habilitado or conteo_habilitado)
                then 'FALLA · contrato cron'
              else 'PENDIENTE · agendar antes de activar' end
    from cron_estado
  union all
  select 10, 'Mantenimiento · último run de base actual succeeded <= 2h', run_ok::text,
         case when run_ok then ''
              when exists (select 1 from cfg where activacion_habilitada or redirect_habilitado or conteo_habilitado)
                then 'FALLA · mantenimiento no sano'
              else 'PENDIENTE · esperar y medir antes de activar' end
    from cron_estado
  union all
  select 11, 'Tablas privadas P3 instaladas', count(*)::text,
         case when count(*) <> 5 then 'FALLA · se esperan cinco tablas' else '' end
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and c.relname in (
       'promocionar_p3_config','promocionar_p3_config_bitacora',
       'atribucion_enlaces','atribucion_clics_dia','atribucion_limite_temporal'
     )
     and c.relkind in ('r','p')
  union all
  select 20, 'Enlaces borrador', count(*)::text, ''
    from public.atribucion_enlaces where estado_enlace = 'borrador'
  union all
  select 21, 'Enlaces activos', count(*)::text, ''
    from public.atribucion_enlaces where estado_enlace = 'activo'
  union all
  select 22, 'Enlaces desactivados', count(*)::text, ''
    from public.atribucion_enlaces where estado_enlace = 'desactivado'
  union all
  select 23, 'Destinos producto', count(*)::text, ''
    from public.atribucion_enlaces where tipo_destino = 'producto_v1'
  union all
  select 24, 'Destinos home', count(*)::text, ''
    from public.atribucion_enlaces where tipo_destino = 'home_v1'
  union all
  select 30, 'Filas de clic diario', count(*)::text, ''
    from public.atribucion_clics_dia
  union all
  select 31, 'Clics aproximados en detalle', coalesce(sum(total), 0)::text, ''
    from public.atribucion_clics_dia
  union all
  select 32, 'Clics aproximados en histórico',
         coalesce(sum(total_aproximado_historico), 0)::text, ''
    from public.atribucion_enlaces
  union all
  select 33, 'Detalle vencido para compactar', count(*)::text,
         case when count(*) > 0 then 'FALLA · ejecutar mantenimiento antes de activar' else '' end
    from public.atribucion_clics_dia
   where fecha_colombia < (
     (statement_timestamp() at time zone 'America/Bogota')::date - interval '13 months'
   )::date
  union all
  select 40, 'Ventanas de cuota vigentes', count(*)::text, ''
    from public.atribucion_limite_temporal where expira_en > statement_timestamp()
  union all
  select 41, 'Ventanas de cuota vencidas', count(*)::text,
         case when count(*) > 0 then 'FALLA · ejecutar mantenimiento antes de activar' else '' end
    from public.atribucion_limite_temporal where expira_en <= statement_timestamp()
  union all
  select 50, 'Eventos de configuración append-only', count(*)::text,
         case when count(*) < 1 then 'FALLA · bitácora vacía' else '' end
    from public.promocionar_p3_config_bitacora
  union all
  select 60, 'Invariante · gates incoherentes', count(*)::text,
         case when count(*) > 0 then 'FALLA · contradicción' else '' end
    from public.promocionar_p3_config
   where ((activacion_habilitada or redirect_habilitado or conteo_habilitado)
          and (not politica_publicada or not routing_verificado or politica_version is null))
      or (activacion_habilitada and not redirect_habilitado)
      or (conteo_habilitado and not redirect_habilitado)
      or actualizado_razon is null or btrim(actualizado_razon) = ''
      or actualizado_rol is null or btrim(actualizado_rol) = ''
  union all
  select 61, 'Invariante · enlaces inválidos', count(*)::text,
         case when count(*) > 0 then 'FALLA · contradicción' else '' end
    from public.atribucion_enlaces
   where campana_producto_id is null
      or tipo_destino not in ('producto_v1','home_v1')
      or (estado_enlace = 'borrador' and codigo is not null)
      or (estado_enlace in ('activo','desactivado')
          and (codigo is null or codigo !~ '^[0-9a-hjkmnp-tv-z]{16}$'))
  union all
  select 62, 'Invariante · genealogía inválida', count(*)::text,
         case when count(*) > 0 then 'FALLA · reemplazo' else '' end
    from public.atribucion_enlaces e
    left join public.atribucion_enlaces anterior on anterior.id = e.reemplaza_enlace_id
   where e.reemplaza_enlace_id is not null
     and (anterior.id is null
          or anterior.estado_enlace <> 'desactivado'
          or anterior.campana_producto_id is distinct from e.campana_producto_id)
  union all
  select 63, 'Invariante · sucesores directos duplicados', count(*)::text,
         case when count(*) > 0 then 'FALLA · unicidad' else '' end
    from (
      select reemplaza_enlace_id
        from public.atribucion_enlaces
       where reemplaza_enlace_id is not null
       group by reemplaza_enlace_id
      having count(*) > 1
    ) duplicados
  union all
  select 64, 'Invariante · cuota vinculable o retención inválida', count(*)::text,
         case when count(*) > 0 then 'FALLA · contradicción' else '' end
    from public.atribucion_limite_temporal
   where conteo not between 1 and 600
      or expira_en >= creado_en + interval '48 hours'
)
select orden as "#", metrica, valor, alerta from medidas order by orden;

rollback;
