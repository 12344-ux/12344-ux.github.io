-- ============================================================================
-- MAGANDHI · PROMOCIONAR P3 · DESACTIVACIÓN GLOBAL SEGURA E IDEMPOTENTE
-- ESCRITURA. Apaga los tres gates; no borra enlaces, códigos, clics, política,
-- routing ni bitácora. La razón y el rol quedan auditados en la quinta tabla.
-- ============================================================================
begin;
set local search_path = public, pg_catalog, pg_temp;
set local statement_timeout = '60s';
set local lock_timeout = '30s';

select id from public.promocionar_p3_config where id = 1 for update;
do $desactivar$
begin
  if (select count(*) from public.promocionar_p3_config where id = 1) <> 1 then
    raise exception using errcode = 'P0001', message = 'P3_CONFIG_SINGLETON_AUSENTE';
  end if;
end;
$desactivar$;

update public.promocionar_p3_config
   set activacion_habilitada = false,
       redirect_habilitado = false,
       conteo_habilitado = false,
       actualizado_en = greatest(
         clock_timestamp(), actualizado_en + interval '1 microsecond'
       ),
       actualizado_por = auth.uid(),
       actualizado_razon = 'desactivacion_global_operativa',
       actualizado_rol = current_user
 where id = 1
   and (activacion_habilitada or redirect_habilitado or conteo_habilitado);

commit;

select id, activacion_habilitada, redirect_habilitado, conteo_habilitado,
       politica_publicada, routing_verificado, politica_version, actualizado_en,
       (select count(*)::bigint from public.promocionar_p3_config_bitacora)
         as eventos_config,
       not activacion_habilitada and not redirect_habilitado
         and not conteo_habilitado as apagado_confirmado
  from public.promocionar_p3_config
 where id = 1;
