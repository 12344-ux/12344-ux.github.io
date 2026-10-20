-- ============================================================================
-- MAGANDHI · PROMOCIONAR P3 · PREFLIGHT · SOLO LECTURA
-- Esperado antes de 20261108000000: todos los checks true, contadores en cero
-- y listo_para_aplicar = true. Devuelve una sola tabla y no revela datos.
-- ============================================================================
begin transaction read only;
set local search_path = public, extensions, pg_temp;
set local statement_timeout = '20s';
set local lock_timeout = '3s';

with baseline as (
  select
    to_regclass('public.campana_producto') is not null as campanas_existe,
    to_regclass('public.campana_slug_historial') is not null as historial_p1_existe,
    to_regclass('public.campana_slug_alias_publico') is not null as aliases_p1_existe,
    to_regprocedure('public.cm__asignar_slug_automatico()') is not null
      and to_regprocedure('public.cm__validar_slug_no_reasignado()') is not null
      and to_regprocedure('public.cm__registrar_slug_historial()') is not null
      as helpers_p1_existen,
    to_regprocedure('public.tiene_acceso_marketing()') is not null as guard_marketing_existe,
    exists (
      select 1
        from pg_extension e
        join pg_namespace n on n.oid = e.extnamespace
       where e.extname = 'pgcrypto'
         and n.nspname in ('public', 'extensions')
         and to_regprocedure(format('%I.gen_random_bytes(integer)', n.nspname)) is not null
         and to_regprocedure(format('%I.digest(text,text)', n.nspname)) is not null
    ) as pgcrypto_disponible
), schemas_definer as (
  select count(*) = 3
         and bool_and(
           not has_schema_privilege(r.rolname, 'public', 'CREATE')
           and case when to_regnamespace('extensions') is null then true
                    else not has_schema_privilege(r.rolname, 'extensions', 'CREATE') end
         ) as roles_api_sin_create_definer
    from pg_roles r
   where r.rolname in ('anon', 'authenticated', 'service_role')
), p1_datos as (
  select
    count(*) filter (where cp.slug is null)::bigint as slugs_nulos,
    count(*) filter (
      where cp.slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or length(cp.slug) > 180
    )::bigint as slugs_invalidos,
    count(*) filter (where h.slug is null)::bigint as slugs_sin_historial
  from public.campana_producto cp
  left join public.campana_slug_historial h
    on h.slug = cp.slug and h.campana_producto_id = cp.id
), ausencia as (
  select
    to_regclass('public.promocionar_p3_config') is null
      and to_regclass('public.promocionar_p3_config_bitacora') is null
      and to_regclass('public.atribucion_enlaces') is null
      and to_regclass('public.atribucion_clics_dia') is null
      and to_regclass('public.atribucion_limite_temporal') is null
      as cinco_tablas_p3_ausentes,
    not exists (
      select 1
        from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname like 'promocionar\_p3\_%' escape '\'
    ) as funciones_p3_ausentes
), trigger_p1 as (
  select exists (
    select 1
      from pg_trigger t
     where t.tgrelid = 'public.campana_producto'::regclass
       and t.tgname = 'trg_cm_slug_automatico'
       and not t.tgisinternal and t.tgenabled = 'O'
       and t.tgfoid = 'public.cm__asignar_slug_automatico()'::regprocedure
  ) as trigger_slug_correcto
), resumen as (
  select b.*, s.roles_api_sin_create_definer, d.*, a.*, t.trigger_slug_correcto,
         b.campanas_existe and b.historial_p1_existe and b.aliases_p1_existe
         and b.helpers_p1_existen and b.guard_marketing_existe
         and b.pgcrypto_disponible and s.roles_api_sin_create_definer
         and t.trigger_slug_correcto
         and d.slugs_nulos = 0 and d.slugs_invalidos = 0
         and d.slugs_sin_historial = 0
         and a.cinco_tablas_p3_ausentes and a.funciones_p3_ausentes
         as listo_para_aplicar
    from baseline b
    cross join schemas_definer s
    cross join p1_datos d
    cross join ausencia a
    cross join trigger_p1 t
)
select * from resumen;

rollback;
