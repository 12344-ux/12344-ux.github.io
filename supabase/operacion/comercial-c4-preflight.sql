-- ============================================================================
-- MAGANDHI · COMERCIAL C4 · PREFLIGHT DE PRODUCCIÓN
-- ----------------------------------------------------------------------------
-- Ejecutar COMPLETO en Supabase SQL Editor antes de aplicar
-- 20261105000000_comercial_c4_cuenta_ciclo_carrito.sql.
--
-- Es estrictamente de solo lectura. Devuelve únicamente conteos, booleanos y
-- configuración no secreta; nunca referencias, UID, customer_id, correos,
-- nombres, teléfonos, direcciones, cuerpos de webhook ni llaves.
--
-- Gate esperado para el corte documentado del 19-oct-2026:
--   1. Todas las filas de la primera salida deben tener coincide = true.
--   2. Debe existir exactamente una intención v2 C3, creada y sin pedido/evento.
--   3. Las cuatro invariantes comerciales deben ser true y revisiones = 0.
--   4. pagos_config debe ser singleton, entorno = prod y llave_activa = true.
-- Si algo difiere: DETENERSE. No corregir historia dentro del preflight.
-- ============================================================================

begin transaction read only;
set local search_path = pg_catalog, public;
set local statement_timeout = '15s';
set local lock_timeout = '3s';

-- 1/4 · Baseline C3, ausencia limpia de C4 y flag OFF.
with medidas(orden, comprobacion, valor, esperado) as (
  select 1,
         'C3 · tablas base presentes',
         (to_regclass('public.comercial_config') is not null
          and to_regclass('public.carritos') is not null
          and to_regclass('public.carrito_items') is not null
          and to_regclass('public.pagos_intencion_items') is not null)::text,
         'true'
  union all
  select 2,
         'C3 · RPC de intención de carrito presente',
         (to_regprocedure(
           'public.pw_registrar_intencion_carrito(text,uuid,uuid,bigint,text,jsonb,text,text,text)'
         ) is not null)::text,
         'true'
  union all
  select 3,
         'C3 · índice único de checkout v2 presente',
         exists (
           select 1
             from pg_indexes
            where schemaname = 'public'
              and indexname = 'pagos_intencion_carrito_version_v2_uidx'
         )::text,
         'true'
  union all
  select 4,
         'C4 · ausente limpiamente antes de migrar',
         (to_regclass('public.pw_sucesiones_c4') is null
          and to_regprocedure('public.pw_estado_checkout_publico(text,uuid)') is null
          and to_regprocedure('public.pw_resolver_revision_c4(text,text,text)') is null
          and not exists (
            select 1
              from information_schema.columns
             where table_schema = 'public'
               and table_name = 'pagos_intencion'
               and column_name = 'ciclo_carrito_version'
          )
          and not exists (
            select 1
              from pg_catalog.pg_trigger t
              join pg_catalog.pg_class c on c.oid = t.tgrelid
              join pg_catalog.pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'public'
               and c.relname = 'pagos_intencion'
               and t.tgname = 'trg_pw_marcar_ciclo_carrito_c4'
               and not t.tgisinternal
          ))::text,
         'true'
  union all
  select 5,
         'Configuración comercial · singleton válido y carrito OFF',
         coalesce((
           count(*) = 1
           and bool_and(
             id = 1
             and carrito_habilitado is false
             and max_lineas_carrito between 1 and 20
             and max_monto_checkout_centavos between 100 and 1000000000000
           )
         ), false)::text,
         'true'
    from comercial_config
)
select orden as "#",
       comprobacion,
       valor,
       esperado,
       valor = esperado as coincide
  from medidas
 order by orden;

-- 2/4 · Huella histórica C3 agregada. El snapshot está en pesos y la cabecera
-- está en centavos, por eso la comparación usa sum(subtotal * 100).
with lineas as (
  select i.referencia,
         count(*)::bigint as cantidad_lineas,
         min(i.ordinal)::integer as ordinal_minimo,
         max(i.ordinal)::integer as ordinal_maximo,
         sum(i.subtotal::numeric * 100) as total_centavos
    from pagos_intencion_items i
   group by i.referencia
), historia as (
  select count(*) filter (
           where pi.version_checkout = 2
         )::bigint as v2_total,
         count(*) filter (
           where pi.version_checkout = 2
             and pi.estado = 'creada'
             and pi.pedido_id is null
         )::bigint as v2_creadas_sin_pedido,
         count(*) filter (
           where pi.version_checkout = 2
             and (
               l.referencia is null
               or l.cantidad_lineas not between 1 and 20
               or l.ordinal_minimo <> 1
               or l.ordinal_maximo <> l.cantidad_lineas
               or l.total_centavos <> pi.monto_centavos::numeric
             )
         )::bigint as snapshots_invalidos,
         count(*) filter (
           where pi.version_checkout = 2
             and exists (
               select 1
                 from pagos_eventos pe
                where pe.referencia = pi.referencia
             )
         )::bigint as v2_con_evento,
         count(*) filter (
           where pi.version_checkout = 2
             and pi.pedido_id is not null
         )::bigint as v2_con_pedido
    from pagos_intencion pi
    left join lineas l using (referencia)
)
select v2_total,
       v2_creadas_sin_pedido,
       snapshots_invalidos,
       v2_con_evento,
       v2_con_pedido,
       v2_total = 1 as esperada_una_intencion_c3,
       v2_creadas_sin_pedido = 1 as esperada_preservada,
       snapshots_invalidos = 0 as snapshots_ok,
       v2_con_evento = 0 as sin_eventos,
       v2_con_pedido = 0 as sin_pedidos
  from historia;

-- 3/4 · Invariantes estructurales, sin identificar cuentas ni carritos.
select not exists (
         select 1
           from carritos
          where estado = 'activa'
          group by auth_user_id
         having count(*) > 1
       ) as sin_doble_carrito_activo,
       not exists (
         select 1
           from carrito_items ci
           left join carritos c on c.id = ci.carrito_id
          where c.id is null
       ) as sin_lineas_huerfanas,
       not exists (
         select 1
           from pagos_intencion pi
           left join cuentas_cliente cc on cc.auth_user_id = pi.auth_user_id
          where pi.version_checkout = 2
            and (cc.auth_user_id is null or cc.estado <> 'activa')
       ) as identidad_v2_coherente,
       not exists (
         select 1
           from pagos_intencion pi
          where pi.version_checkout = 2
            and (
              pi.auth_user_id is null
              or pi.carrito_id is null
              or pi.carrito_version is null
            )
       ) as propiedad_v2_completa,
       (select count(*)
          from pagos_intencion
         where estado = 'requiere_revision')::bigint as revisiones_pendientes;

-- 4/4 · Entorno y llave pública activa. No devuelve la llave.
select count(*) = 1 as singleton,
       min(id) = 1 and max(id) = 1 as id_correcto,
       min(entorno) as entorno,
       coalesce(bool_and(
         case entorno
           when 'prod' then length(btrim(llave_publica_prod)) > 0
           when 'sandbox' then length(btrim(llave_publica_sandbox)) > 0
           else false
         end
       ), false) as llave_activa_configurada,
       coalesce(bool_and(entorno = 'prod'), false) as wompi_permanece_en_prod
  from pagos_config;

rollback;
