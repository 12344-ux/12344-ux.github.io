-- ============================================================================
-- MAGANDHI · COMERCIAL C5 + SLUG · PREFLIGHT DE PRODUCCIÓN
-- Solo lectura, agregado y sin PII/UUID/referencias/secretos.
-- Ejecutar completo antes de cualquier despliegue o escritura C5.
-- ============================================================================
begin transaction read only;
set local search_path = pg_catalog, public;
set local statement_timeout = '20s';
set local lock_timeout = '3s';

-- 1/5 · Ledger y configuración. La versión máxima es evidencia, no permiso para
-- db push: C4 manual debe reconciliarse por el procedimiento aprobado.
select (select max(version) from supabase_migrations.schema_migrations) as version_maxima_ledger,
       count(*) = 1 as config_singleton,
       coalesce(bool_and(id = 1), false) as config_id_correcto,
       min(carrito_habilitado::text)::boolean as carrito_habilitado,
       coalesce(bool_and(max_lineas_carrito between 1 and 20), false) as limites_validos
  from comercial_config;

-- 2/5 · Baseline C4 y ausencia limpia del tramo C5/slug.
with medidas(orden, comprobacion, coincide) as (
  values
  (1, 'C4 · tabla privada y retorno presentes',
    to_regclass('public.pw_sucesiones_c4') is not null
    and to_regprocedure('public.pw_estado_checkout_publico(text,uuid)') is not null),
  (2, 'C4 · trigger activo', exists (
    select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid
    join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname='pagos_intencion'
      and t.tgname='trg_pw_marcar_ciclo_carrito_c4' and not t.tgisinternal
      and t.tgenabled <> 'D')),
  (3, 'C5 · columnas aún ausentes', not exists (
    select 1 from information_schema.columns where table_schema='public'
      and table_name='pagos_intencion'
      and column_name in ('carrito_separado_en','carrito_version_sucesora','carrito_separacion_detalle'))),
  (4, 'C5 · puertas aún ausentes',
    to_regprocedure('public.mc_compras_listar()') is null
    and to_regprocedure('public.mc_reabrir_intencion_c5(text,uuid)') is null
    and to_regprocedure('public.pw__procesar_pago_c5(text,text,text,bigint,text,text,text,jsonb,text,text)') is null),
  (5, 'Slug automático · aún ausente',
    to_regprocedure('public.cm__asignar_slug_automatico()') is null
    and not exists (select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid
      join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'
      and c.relname='campana_producto' and t.tgname='trg_cm_slug_automatico'
      and not t.tgisinternal))
)
select orden as "#", comprobacion, coincide from medidas order by orden;

-- 3/5 · Estado agregado de ciclos e intenciones. Las intenciones/revisiones
-- legítimas C4 no son corrupción ni se editan desde este diagnóstico.
select version_checkout, ciclo_carrito_version, estado, count(*)::bigint as cantidad
  from pagos_intencion
 group by version_checkout, ciclo_carrito_version, estado
 order by version_checkout, ciclo_carrito_version, estado;

select count(*) filter (where ciclo_carrito_version=4 and estado='creada'
                         and expira_en > statement_timestamp())::bigint as c4_creadas_vigentes,
       count(*) filter (where ciclo_carrito_version=4 and estado='requiere_revision'
                         and resuelta_en is null)::bigint as c4_revisiones_abiertas,
       count(*) filter (where ciclo_carrito_version=5)::bigint as c5_debe_ser_cero,
       count(*) filter (where version_checkout in (0,1)
                         and ciclo_carrito_version<>0)::bigint as historicas_reetiquetadas,
       count(*) filter (where carrito_consumido_en is not null
                         and carrito_liberado_en is not null)::bigint as consumidas_y_liberadas
  from pagos_intencion;

-- 4/5 · Slug agregado. No lista nombres, slugs ni ids.
select count(*)::bigint as campanas_total,
       count(*) filter (where slug is null)::bigint as slugs_null_a_completar,
       count(*) filter (where slug is not null)::bigint as slugs_existentes_a_preservar,
       (count(*) filter (where slug is not null)
         - count(distinct slug) filter (where slug is not null))::bigint
         as duplicados_no_null,
       count(*) filter (
         where slug is not null
           and (slug is distinct from cm_normalizar_slug(slug) or length(slug) > 180)
       )::bigint as slugs_historicos_no_normalizados,
       (select is_nullable='YES' from information_schema.columns
         where table_schema='public' and table_name='campana_producto'
           and column_name='slug') as slug_aun_nullable,
       exists (select 1 from pg_indexes where schemaname='public'
         and indexname='campana_producto_slug_key') as indice_slug_presente
  from campana_producto;

-- 5/5 · Wompi permanece productivo; nunca devuelve la llave.
select count(*)=1 as singleton, min(id)=1 and max(id)=1 as id_correcto,
       min(entorno) as entorno,
       coalesce(bool_and(case entorno when 'prod' then length(btrim(llave_publica_prod))>0
         when 'sandbox' then length(btrim(llave_publica_sandbox))>0 else false end),false)
         as llave_activa_configurada,
       coalesce(bool_and(entorno='prod'),false) as wompi_permanece_en_prod
  from pagos_config;
rollback;
