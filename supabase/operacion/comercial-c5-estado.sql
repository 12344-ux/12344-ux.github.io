-- ============================================================================
-- MAGANDHI · COMERCIAL C5 · ESTADO OPERATIVO AGREGADO
-- ----------------------------------------------------------------------------
-- Solo lectura. Devuelve UNA sola tabla (el SQL Editor de Supabase muestra
-- únicamente el último resultado). Sin PII, referencias, UUID, transacciones,
-- motivos ni secretos. Repetible en cualquier momento con el carrito ON u OFF.
--
-- Columna «alerta»:
--   (vacía)               → informativo; pendientes y vencidas son operación normal.
--   REVISAR               → requiere atención humana (revisión, posible doble cobro).
--   FALLA · contradicción → invariante estructural roto: apagar con
--                           comercial-c5-desactivar.sql y diagnosticar.
-- ============================================================================
begin transaction read only;
set local search_path = pg_catalog, public;
set local statement_timeout = '20s';
set local lock_timeout = '3s';

with m(orden, metrica, valor, alerta) as (
  select 1, 'Carrito encendido',
         coalesce((select carrito_habilitado::text from comercial_config where id = 1),
                  'sin fila'),
         ''
  union all
  select 2, 'Entorno Wompi',
         coalesce((select entorno::text from pagos_config where id = 1), 'sin fila'),
         ''
  union all
  select 10, 'C5 · intenciones totales', count(*)::text, ''
    from pagos_intencion where ciclo_carrito_version = 5
  union all
  select 11, 'C5 · en proceso vigentes, sin transacción', count(*)::text, ''
    from pagos_intencion
   where ciclo_carrito_version = 5 and estado = 'creada'
     and transaccion_id is null and expira_en > statement_timestamp()
  union all
  select 12, 'C5 · confirmando con el banco (transacción fijada)', count(*)::text, ''
    from pagos_intencion
   where ciclo_carrito_version = 5 and estado = 'creada'
     and transaccion_id is not null
  union all
  select 13, 'C5 · vencidas aún sin marcar (expiración perezosa)', count(*)::text, ''
    from pagos_intencion
   where ciclo_carrito_version = 5 and estado = 'creada'
     and transaccion_id is null and expira_en <= statement_timestamp()
  union all
  select 14, 'C5 · no completadas (rechazadas o vencidas)', count(*)::text, ''
    from pagos_intencion
   where ciclo_carrito_version = 5 and estado = 'rechazada'
  union all
  select 15, 'C5 · compras realizadas (procesadas)', count(*)::text, ''
    from pagos_intencion
   where ciclo_carrito_version = 5 and estado = 'procesada'
  union all
  select 16, 'C5 · revisiones abiertas', count(*)::text,
         case when count(*) > 0 then 'REVISAR' else '' end
    from pagos_intencion
   where ciclo_carrito_version = 5 and estado = 'requiere_revision'
     and resuelta_en is null
  union all
  select 17, 'C5 · posible doble cobro abierto', count(*)::text,
         case when count(*) > 0 then 'REVISAR' else '' end
    from pagos_intencion
   where ciclo_carrito_version = 5 and revision_motivo = 'C5_POSIBLE_DOBLE_COBRO'
     and resuelta_en is null
  union all
  select 20, 'C4 histórico · creadas vigentes', count(*)::text, ''
    from pagos_intencion
   where ciclo_carrito_version = 4 and estado = 'creada'
     and expira_en > statement_timestamp()
  union all
  select 21, 'C4 histórico · revisiones abiertas', count(*)::text,
         case when count(*) > 0 then 'REVISAR' else '' end
    from pagos_intencion
   where ciclo_carrito_version = 4 and estado = 'requiere_revision'
     and resuelta_en is null
  union all
  select 30, 'Invariante · separaciones C5 inválidas', count(*)::text,
         case when count(*) > 0 then 'FALLA · contradicción' else '' end
    from pagos_intencion
   where ciclo_carrito_version = 5
     and (expira_en is null
       or carrito_separado_en is null
       or carrito_version_sucesora is distinct from carrito_version + 1
       or carrito_separacion_detalle is null)
  union all
  select 31, 'Invariante · historia C3/C4 con campos C5', count(*)::text,
         case when count(*) > 0 then 'FALLA · contradicción' else '' end
    from pagos_intencion
   where ciclo_carrito_version in (0, 4)
     and (carrito_separado_en is not null
       or carrito_version_sucesora is not null
       or carrito_separacion_detalle is not null)
  union all
  select 32, 'Invariante · C5 procesadas sin pedido', count(*)::text,
         case when count(*) > 0 then 'FALLA · contradicción' else '' end
    from pagos_intencion
   where ciclo_carrito_version = 5 and estado = 'procesada' and pedido_id is null
  union all
  select 33, 'Invariante · C5 con consumo de carrito C4', count(*)::text,
         case when count(*) > 0 then 'FALLA · contradicción' else '' end
    from pagos_intencion
   where ciclo_carrito_version = 5
     and (carrito_consumido_en is not null
       or carrito_consumo_resultado is not null
       or carrito_consumo_detalle is not null)
  union all
  select 34, 'Invariante · pedidos C5 repetidos', (count(pedido_id) - count(distinct pedido_id))::text,
         case when count(pedido_id) > count(distinct pedido_id)
              then 'FALLA · contradicción' else '' end
    from pagos_intencion
   where ciclo_carrito_version = 5 and pedido_id is not null
  union all
  select 35, 'Invariante · cuentas con más de un carrito activo', count(*)::text,
         case when count(*) > 0 then 'FALLA · contradicción' else '' end
    from (select auth_user_id
            from carritos
           where estado = 'activa'
           group by auth_user_id
          having count(*) > 1) d
  union all
  select 36, 'Invariante · líneas de carrito huérfanas', count(*)::text,
         case when count(*) > 0 then 'FALLA · contradicción' else '' end
    from carrito_items ci
    left join carritos c on c.id = ci.carrito_id
   where c.id is null
  union all
  select 37, 'Invariante · intenciones v0/v1 reetiquetadas', count(*)::text,
         case when count(*) > 0 then 'FALLA · contradicción' else '' end
    from pagos_intencion
   where version_checkout in (0, 1) and ciclo_carrito_version <> 0
)
select orden as "#", metrica, valor, alerta
  from m
 order by orden;

rollback;
