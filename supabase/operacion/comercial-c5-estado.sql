-- ============================================================================
-- MAGANDHI · COMERCIAL C5 · ESTADO OPERATIVO AGREGADO
-- Solo lectura; sin PII, referencias, UUID, transacciones, motivos ni secretos.
-- ============================================================================
begin transaction read only;
set local search_path = pg_catalog, public;
set local statement_timeout='20s';
set local lock_timeout='3s';

select cfg.carrito_habilitado, cfg.max_lineas_carrito,
       cfg.max_monto_checkout_centavos, pc.entorno as entorno_wompi,
       cfg.actualizado as flag_actualizado
  from comercial_config cfg left join pagos_config pc on pc.id=cfg.id
 where cfg.id=1;

select version_checkout, ciclo_carrito_version, estado, count(*)::bigint as cantidad
  from pagos_intencion group by version_checkout,ciclo_carrito_version,estado
 order by version_checkout,ciclo_carrito_version,estado;

select count(*) filter (where ciclo_carrito_version=5 and estado='creada'
                         and transaccion_id is null and expira_en>statement_timestamp())::bigint as c5_creadas_vigentes_sin_transaccion,
       count(*) filter (where ciclo_carrito_version=5 and estado='creada'
                         and transaccion_id is not null)::bigint as c5_confirmacion_bancaria,
       count(*) filter (where ciclo_carrito_version=5 and estado='creada'
                         and transaccion_id is null and expira_en<=statement_timestamp())::bigint as c5_expiradas_perezosas,
       count(*) filter (where ciclo_carrito_version=5 and estado='requiere_revision'
                         and resuelta_en is null)::bigint as c5_revisiones_abiertas,
       count(*) filter (where ciclo_carrito_version=5
                         and revision_motivo='C5_POSIBLE_DOBLE_COBRO'
                         and resuelta_en is null)::bigint as c5_posible_doble_cobro
  from pagos_intencion;

select count(*) filter (where ciclo_carrito_version=5)::bigint as separaciones_c5,
       count(*) filter (where ciclo_carrito_version=5
         and carrito_version_sucesora=carrito_version+1
         and carrito_separado_en is not null
         and carrito_separacion_detalle is not null)::bigint as separaciones_coherentes,
       count(*) filter (where ciclo_carrito_version=5
         and (carrito_version_sucesora is distinct from carrito_version+1
           or carrito_separado_en is null or carrito_separacion_detalle is null))::bigint as separaciones_invalidas,
       count(*) filter (where ciclo_carrito_version in (0,4)
         and (carrito_separado_en is not null or carrito_version_sucesora is not null
           or carrito_separacion_detalle is not null))::bigint as historia_c4_cero_alterada_por_c5
  from pagos_intencion;

select count(*) filter (where ciclo_carrito_version=5 and estado='procesada')::bigint as c5_procesadas,
       count(*) filter (where ciclo_carrito_version=5 and estado='procesada'
                         and pedido_id is null)::bigint as procesadas_sin_pedido,
       count(*) filter (where ciclo_carrito_version=5 and pedido_id is not null)::bigint as c5_con_pedido,
       count(distinct pedido_id) filter (where ciclo_carrito_version=5
                         and pedido_id is not null)::bigint as pedidos_c5_distintos,
       count(*) filter (where ciclo_carrito_version=5
                         and (carrito_consumido_en is not null
                           or carrito_consumo_resultado is not null
                           or carrito_consumo_detalle is not null))::bigint as c5_toco_consumo_c4
  from pagos_intencion;

select not exists (select 1 from carritos where estado='activa'
                    group by auth_user_id having count(*)>1) as sin_doble_carrito_activo,
       not exists (select 1 from carrito_items ci left join carritos c on c.id=ci.carrito_id
                    where c.id is null) as sin_lineas_huerfanas,
       not exists (select 1 from pagos_intencion where version_checkout in (0,1)
                    and ciclo_carrito_version<>0) as historia_checkout_preservada,
       not exists (select 1 from pagos_intencion where ciclo_carrito_version=5
                    and (expira_en is null
                      or carrito_version_sucesora is distinct from carrito_version+1))
         as cabeceras_c5_coherentes;
rollback;
