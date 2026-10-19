-- ============================================================================
-- MAGANDHI · COMERCIAL C4 · ESTADO OPERATIVO AGREGADO
-- ----------------------------------------------------------------------------
-- Ejecutar después de aplicar C4 y repetir durante las pruebas. Solo lectura.
-- No devuelve PII, referencias, ids de cuenta/carrito/pedido, transacciones,
-- motivos, notas, cuerpos de webhook ni secretos.
-- ============================================================================

begin transaction read only;
set local search_path = pg_catalog, public;
set local statement_timeout = '15s';
set local lock_timeout = '3s';

-- Configuración pública para la operación (sin llaves).
select cfg.carrito_habilitado,
       cfg.max_lineas_carrito,
       cfg.max_monto_checkout_centavos,
       pc.entorno as entorno_wompi,
       cfg.actualizado as flag_actualizado
  from comercial_config cfg
  left join pagos_config pc on pc.id = cfg.id
 where cfg.id = 1;

-- Distribución agregada de intenciones.
select version_checkout,
       ciclo_carrito_version,
       estado,
       count(*)::bigint as cantidad
  from pagos_intencion
 group by version_checkout, ciclo_carrito_version, estado
 order by version_checkout, ciclo_carrito_version, estado;

-- Bloqueos, expiraciones y revisiones C4.
select count(*) filter (
         where ciclo_carrito_version = 4
           and estado = 'creada'
           and expira_en > statement_timestamp()
       )::bigint as pendientes_vigentes,
       count(*) filter (
         where ciclo_carrito_version = 4
           and estado = 'creada'
           and expira_en <= statement_timestamp()
           and carrito_liberado_en is null
       )::bigint as expiradas_aun_no_liberadas,
       count(*) filter (
         where ciclo_carrito_version = 4
           and estado = 'requiere_revision'
           and resuelta_en is null
       )::bigint as revisiones_c4_abiertas,
       count(*) filter (
         where ciclo_carrito_version = 4
           and estado = 'requiere_revision'
           and resuelta_en is not null
       )::bigint as revisiones_c4_resueltas
  from pagos_intencion;

-- Resultados de consumo/liberación sin identificar compras.
select count(*) filter (
         where ciclo_carrito_version = 4
           and carrito_consumo_resultado = 'completo'
       )::bigint as consumos_completos,
       count(*) filter (
         where ciclo_carrito_version = 4
           and carrito_consumo_resultado = 'parcial'
       )::bigint as consumos_parciales,
       count(*) filter (
         where ciclo_carrito_version = 4
           and carrito_liberado_en is not null
       )::bigint as liberaciones,
       count(*) filter (
         where ciclo_carrito_version = 4
           and estado = 'procesada'
       )::bigint as aprobadas_procesadas
  from pagos_intencion;

-- Sucesiones y coherencia de la intención predecesora C3.
select count(*)::bigint as sucesiones,
       count(*) filter (
         where s.version_sucesora <> s.version_predecesora + 1
            or s.carrito_id <> pi.carrito_id
            or s.version_predecesora <> pi.carrito_version
            or pi.version_checkout <> 2
            or pi.ciclo_carrito_version <> 0
       )::bigint as sucesiones_invalidas
  from pw_sucesiones_c4 s
  join pagos_intencion pi on pi.referencia = s.referencia_predecesora;

-- Invariantes que deben permanecer siempre en true/0.
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
       count(*) filter (
         where version_checkout in (0, 1)
           and ciclo_carrito_version <> 0
       )::bigint as historicas_reetiquetadas,
       count(*) filter (
         where ciclo_carrito_version = 0
           and (
             expira_en is not null
             or carrito_liberado_en is not null
             or carrito_consumido_en is not null
             or carrito_consumo_resultado is not null
             or carrito_consumo_detalle is not null
           )
       )::bigint as ciclo_cero_con_transicion_c4,
       count(*) filter (
         where ciclo_carrito_version = 4
           and expira_en is null
       )::bigint as c4_sin_expiracion,
       count(*) filter (
         where ciclo_carrito_version = 4
           and estado = 'rechazada'
           and carrito_liberado_en is null
       )::bigint as rechazada_sin_liberacion,
       count(*) filter (
         where carrito_consumido_en is not null
           and carrito_liberado_en is not null
       )::bigint as consumida_y_liberada,
       count(*) filter (
         where ciclo_carrito_version = 4
           and estado = 'procesada'
           and carrito_consumido_en is null
       )::bigint as procesada_sin_consumo
  from pagos_intencion;

rollback;
