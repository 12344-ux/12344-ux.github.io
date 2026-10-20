-- ============================================================================
-- MAGANDHI · COMERCIAL C5 · DESACTIVACIÓN SEGURA E IDEMPOTENTE
-- No revierte C5, no borra datos y no resuelve intenciones C4/C5.
-- ============================================================================
begin;
set local search_path = pg_catalog, public;
set local statement_timeout = '60s';
set local lock_timeout = '30s';

select id from comercial_config where id=1 for update;
do $$
begin
  if (select count(*) from comercial_config where id=1) <> 1 then
    raise exception using errcode='P0001', message='C5_CONFIG_SINGLETON_AUSENTE';
  end if;
end;
$$;
update comercial_config
   set carrito_habilitado=false, actualizado=statement_timestamp()
 where id=1 and carrito_habilitado is distinct from false;
commit;

select id, carrito_habilitado, actualizado,
       carrito_habilitado is false as apagado_confirmado
  from public.comercial_config where id=1;
