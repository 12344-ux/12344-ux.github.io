-- PROMOCIONAR P1 · POSTFLIGHT · SOLO LECTURA
-- Esperado después de aplicar 20261107000000: todos los booleanos true y
-- faltantes_actuales = 0. Devuelve una sola tabla para SQL Editor.
begin read only;
set local search_path = public, pg_catalog;
set local statement_timeout = '15s';
set local lock_timeout = '3s';

with objetos as (
  select
    to_regclass('public.campana_slug_historial') is not null as historial_existe,
    to_regclass('public.campana_slug_alias_publico') is not null as vista_alias_existe,
    to_regprocedure('public.cm__validar_slug_no_reasignado()') is not null as validador_existe,
    to_regprocedure('public.cm__registrar_slug_historial()') is not null as registrador_existe
), triggers as (
  select
    exists (
      select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
      where t.tgrelid = 'public.campana_producto'::regclass
        and t.tgname = 'trg_cm_slug_automatico' and not t.tgisinternal
        and t.tgenabled = 'O' and t.tgtype = 23 and t.tgqual is null
        and array(select x from unnest(t.tgattr::smallint[]) as u(x)) = array[
          (select attnum::smallint from pg_attribute where attrelid = t.tgrelid and attname = 'slug'),
          (select attnum::smallint from pg_attribute where attrelid = t.tgrelid and attname = 'nombre')
        ]
        and p.oid = 'public.cm__asignar_slug_automatico()'::regprocedure
    ) as automatico_correcto,
    exists (
      select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
      where t.tgrelid = 'public.campana_producto'::regclass
        and t.tgname = 'trg_cm_slug_no_reasignado' and not t.tgisinternal
        and t.tgenabled = 'O' and t.tgtype = 23 and t.tgqual is null
        and array(select x from unnest(t.tgattr::smallint[]) as u(x)) = array[
          (select attnum::smallint from pg_attribute where attrelid = t.tgrelid and attname = 'slug'),
          (select attnum::smallint from pg_attribute where attrelid = t.tgrelid and attname = 'nombre')
        ]
        and p.oid = 'public.cm__validar_slug_no_reasignado()'::regprocedure
    ) as reserva_correcta,
    exists (
      select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
      where t.tgrelid = 'public.campana_producto'::regclass
        and t.tgname = 'trg_cm_slug_historial' and not t.tgisinternal
        and t.tgenabled = 'O' and t.tgtype = 21 and t.tgqual is null -- ROW + AFTER + INSERT + UPDATE
        and array(select x from unnest(t.tgattr::smallint[]) as u(x)) = array[
          (select attnum::smallint from pg_attribute where attrelid = t.tgrelid and attname = 'slug')
        ]
        and p.oid = 'public.cm__registrar_slug_historial()'::regprocedure
    ) as historial_correcto
), restricciones as (
  select
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.campana_slug_historial'::regclass
        and conname = 'campana_slug_historial_pkey' and contype = 'p' and convalidated
        and conkey::smallint[] = array[
          (select attnum::smallint from pg_attribute
            where attrelid = 'public.campana_slug_historial'::regclass and attname = 'slug')
        ]
    ) as pk_slug,
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.campana_slug_historial'::regclass
        and contype = 'f' and confrelid = 'public.campana_producto'::regclass
        and confdeltype = 'r' and convalidated
        and conkey::smallint[] = array[
          (select attnum::smallint from pg_attribute
            where attrelid = 'public.campana_slug_historial'::regclass and attname = 'campana_producto_id')
        ]
        and confkey::smallint[] = array[
          (select attnum::smallint from pg_attribute
            where attrelid = 'public.campana_producto'::regclass and attname = 'id')
        ]
    ) as fk_restrict,
    exists (
      select 1 from pg_constraint
      where conrelid = 'public.campana_slug_historial'::regclass
        and conname = 'campana_slug_historial_formato'
        and contype = 'c' and convalidated
        and conkey::smallint[] = array[
          (select attnum::smallint from pg_attribute
            where attrelid = 'public.campana_slug_historial'::regclass and attname = 'slug')
        ]
        and pg_get_constraintdef(oid, true) like '%^[a-z0-9]+(-[a-z0-9]+)*$%'
        and pg_get_constraintdef(oid, true) like '%length(slug)%180%'
    ) as check_formato
), seguridad as (
  select
    (select relrowsecurity from pg_class where oid = 'public.campana_slug_historial'::regclass)
      and not exists (select 1 from pg_policy where polrelid = 'public.campana_slug_historial'::regclass)
      as rls_sin_policies,
    not exists (
      select 1
      from pg_class c
      cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
      left join pg_roles r on r.oid = a.grantee
      where c.oid = 'public.campana_slug_historial'::regclass
        and (a.grantee = 0 or r.rolname in ('anon','authenticated','service_role'))
    ) as tabla_sin_api,
    has_table_privilege('anon', 'campana_slug_alias_publico', 'SELECT')
      and has_table_privilege('authenticated', 'campana_slug_alias_publico', 'SELECT')
      and has_table_privilege('service_role', 'campana_slug_alias_publico', 'SELECT')
      and not exists (
        select 1
        from pg_class c
        cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
        left join pg_roles r on r.oid = a.grantee
        where c.oid = 'public.campana_slug_alias_publico'::regclass
          and (a.grantee = 0 or r.rolname in ('anon','authenticated','service_role'))
          and (a.grantee = 0 or a.privilege_type <> 'SELECT')
      ) as vista_solo_lectura,
    not has_function_privilege('anon', 'cm__asignar_slug_automatico()', 'execute')
      and not has_function_privilege('authenticated', 'cm__asignar_slug_automatico()', 'execute')
      and not has_function_privilege('service_role', 'cm__asignar_slug_automatico()', 'execute')
      and not has_function_privilege('anon', 'cm__validar_slug_no_reasignado()', 'execute')
      and not has_function_privilege('authenticated', 'cm__validar_slug_no_reasignado()', 'execute')
      and not has_function_privilege('service_role', 'cm__validar_slug_no_reasignado()', 'execute')
      and not has_function_privilege('anon', 'cm__registrar_slug_historial()', 'execute')
      and not has_function_privilege('authenticated', 'cm__registrar_slug_historial()', 'execute')
      and not has_function_privilege('service_role', 'cm__registrar_slug_historial()', 'execute')
      as helpers_sin_api
), funciones as (
  select bool_and(p.prosecdef and coalesce(p.proconfig, '{}') @> array['search_path=public']) as seguras
  from pg_proc p
  where p.oid in (
    'public.cm__asignar_slug_automatico()'::regprocedure,
    'public.cm__validar_slug_no_reasignado()'::regprocedure,
    'public.cm__registrar_slug_historial()'::regprocedure
  )
), vista as (
  select
    (select array_agg(a.attname::text order by a.attnum)
       from pg_attribute a
      where a.attrelid = 'public.campana_slug_alias_publico'::regclass
        and a.attnum > 0 and not a.attisdropped)
      = array['campana_producto_id','slug_anterior','slug_actual'] as columnas_exactas,
    lower(pg_get_viewdef('public.campana_slug_alias_publico'::regclass, true)) like '%join campana_producto cp on%cp.id = h.campana_producto_id%'
      and lower(pg_get_viewdef('public.campana_slug_alias_publico'::regclass, true)) like '%join catalogo_publico cat on%cat.id = cp.id%'
      and lower(pg_get_viewdef('public.campana_slug_alias_publico'::regclass, true)) like '%h.slug <> cp.slug%'
      and lower(pg_get_viewdef('public.campana_slug_alias_publico'::regclass, true)) not like '% union %'
      as definicion_lista_blanca,
    not exists (
      (select campana_producto_id, slug_anterior, slug_actual from campana_slug_alias_publico
       except
       select h.campana_producto_id, h.slug, cp.slug
         from campana_slug_historial h
         join campana_producto cp on cp.id = h.campana_producto_id
         join catalogo_publico cat on cat.id = cp.id
        where h.slug <> cp.slug)
      union all
      (select h.campana_producto_id, h.slug, cp.slug
         from campana_slug_historial h
         join campana_producto cp on cp.id = h.campana_producto_id
         join catalogo_publico cat on cat.id = cp.id
        where h.slug <> cp.slug
       except
       select campana_producto_id, slug_anterior, slug_actual from campana_slug_alias_publico)
    ) as filas_lista_blanca
), integridad as (
  select
    (select count(*)
       from campana_producto cp
       left join campana_slug_historial h
         on h.slug = cp.slug and h.campana_producto_id = cp.id
      where h.slug is null) as faltantes_actuales,
    not exists (
      select 1
      from campana_slug_historial h
      join campana_producto cp on cp.slug = h.slug
      where cp.id <> h.campana_producto_id
    ) as sin_reasignacion,
    not exists (
      select 1 from campana_slug_alias_publico
      where slug_anterior = slug_actual
         or slug_anterior !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
         or slug_actual !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
    ) as aliases_validos
)
select
  o.historial_existe, o.vista_alias_existe, o.validador_existe, o.registrador_existe,
  t.automatico_correcto, t.reserva_correcta, t.historial_correcto,
  r.pk_slug, r.fk_restrict, r.check_formato,
  s.rls_sin_policies, s.tabla_sin_api, s.vista_solo_lectura, s.helpers_sin_api,
  f.seguras as funciones_seguras,
  v.columnas_exactas, v.definicion_lista_blanca, v.filas_lista_blanca,
  i.faltantes_actuales, i.sin_reasignacion, i.aliases_validos
from objetos o cross join triggers t cross join restricciones r
cross join seguridad s cross join funciones f cross join vista v cross join integridad i;

rollback;
