-- ============================================================================
-- MAGANDHI · COMERCIAL C4 · DESACTIVACIÓN SEGURA
-- ----------------------------------------------------------------------------
-- Ejecutar COMPLETO para detener tráfico nuevo de carrito. Es idempotente:
-- dejar el flag en false cuando ya estaba false también es éxito.
--
-- Este interruptor no revierte C4, no borra datos y no resuelve intenciones en
-- revisión. Compra inmediata e invitada conservan sus caminos históricos.
-- ============================================================================

begin;
set local search_path = pg_catalog, public;
set local statement_timeout = '60s';
set local lock_timeout = '30s';

-- Serializa el cambio con migración/activación y falla si desapareció el
-- singleton: nunca afirmar OFF sin haber bloqueado exactamente su fila.
select id
  from comercial_config
 where id = 1
 for update;

do $$
begin
  if (select count(*) from comercial_config where id = 1) <> 1 then
    raise exception using
      errcode = 'P0001',
      message = 'C4_CONFIG_SINGLETON_AUSENTE';
  end if;
end;
$$;

update comercial_config
   set carrito_habilitado = false,
       actualizado = statement_timestamp()
 where id = 1
   and carrito_habilitado is distinct from false;

commit;

-- Verificación durable posterior al COMMIT.
select id,
       carrito_habilitado,
       actualizado,
       carrito_habilitado is false as apagado_confirmado
  from public.comercial_config
 where id = 1;
-- Esperado: una fila, carrito_habilitado=false, apagado_confirmado=true.
