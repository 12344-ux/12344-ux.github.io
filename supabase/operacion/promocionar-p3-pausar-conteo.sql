-- ============================================================================
-- MAGANDHI · PROMOCIONAR P3 · PAUSAR SOLO CONTEO · IDEMPOTENTE
-- Mantiene redirect y activación como estén. El lock exclusivo drena llamadas
-- de contar ya autorizadas porque la RPC toma FOR SHARE sobre el singleton.
-- ============================================================================
begin;
set local search_path = public, pg_catalog, pg_temp;
set local statement_timeout = '60s';
set local lock_timeout = '30s';

select id from public.promocionar_p3_config where id = 1 for update;
do $pausar$
begin
  if (select count(*) from public.promocionar_p3_config where id = 1) <> 1 then
    raise exception using errcode = 'P0001', message = 'P3_CONFIG_SINGLETON_AUSENTE';
  end if;
end;
$pausar$;

update public.promocionar_p3_config
   set conteo_habilitado = false,
       actualizado_en = greatest(
         clock_timestamp(), actualizado_en + interval '1 microsecond'
       ),
       actualizado_por = auth.uid(),
       actualizado_razon = 'pausa_conteo_operativa',
       actualizado_rol = current_user
 where id = 1 and conteo_habilitado;

commit;

select id, activacion_habilitada, redirect_habilitado, conteo_habilitado,
       politica_publicada, routing_verificado, politica_version, actualizado_en,
       (select count(*)::bigint from public.promocionar_p3_config_bitacora)
         as eventos_config,
       not conteo_habilitado as conteo_pausado_confirmado
  from public.promocionar_p3_config
 where id = 1;
