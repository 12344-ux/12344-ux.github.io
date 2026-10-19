-- ============================================================================
-- MAGANDHI · COMERCIAL C4 · ACTIVACIÓN CONTROLADA
-- ----------------------------------------------------------------------------
-- Ejecutar COMPLETO solo después de:
--   1. migración C4 + postflight totalmente correctos;
--   2. crear-intencion-pago y estado-pago C4 desplegadas y verificadas;
--   3. Pages de back-office y tienda verificadas;
--   4. regresión con flag OFF aprobada.
--
-- Es una escritura deliberada. Falla cerrado si C4 está ausente/incompleto,
-- hay contradicciones estructurales o existe un pago C4 aún bloqueante.
-- No verifica versiones externas de Edge/Pages: ese gate es humano.
-- ============================================================================

begin;
set local search_path = pg_catalog, public;
set local statement_timeout = '20s';
set local lock_timeout = '5s';

-- Coordina con el FOR SHARE de la migración C4 y otros cambios del flag.
select id
  from comercial_config
 where id = 1
 for update;

do $$
declare
  v_filas integer;
begin
  if (select count(*) from comercial_config where id = 1) <> 1
     or not exists (
       select 1
         from comercial_config
        where id = 1
          and carrito_habilitado is false
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'C4_ACTIVACION_REQUIERE_SINGLETON_OFF';
  end if;

  if to_regclass('public.pw_sucesiones_c4') is null
     or to_regprocedure('public.pw_estado_checkout_publico(text,uuid)') is null
     or to_regprocedure('public.pw_resolver_revision_c4(text,text,text)') is null
     or to_regprocedure('public.pw__marcar_ciclo_carrito_c4()') is null
     or to_regprocedure(
       'public.pw_registrar_intencion_carrito(text,uuid,uuid,bigint,text,jsonb,text,text,text)'
     ) is null
     or to_regprocedure(
       'public.pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text)'
     ) is null
     or to_regprocedure('public.co__liberar_expiradas_c4(uuid)') is null
     or to_regprocedure('public.co__bloqueo_pago(uuid)') is null
     or not exists (
       select 1
         from pg_trigger t
         join pg_class c on c.oid = t.tgrelid
         join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relname = 'pagos_intencion'
          and t.tgname = 'trg_pw_marcar_ciclo_carrito_c4'
          and not t.tgisinternal
          and t.tgenabled <> 'D'
     )
     or (
       select count(*)
         from pg_constraint
        where convalidated
          and (
            (conrelid = 'public.pagos_intencion'::regclass
             and conname = any(array[
               'pagos_intencion_ciclo_carrito_version',
               'pagos_intencion_expiracion_c4',
               'pagos_intencion_consumo_carrito_resultado',
               'pagos_intencion_ciclo_carrito_solo_v2',
               'pagos_intencion_consumo_carrito_coherente'
             ]))
            or (conrelid = 'public.pw_sucesiones_c4'::regclass
                and conname = 'pw_sucesiones_c4_version')
          )
     ) <> 6
     or (
       select count(*)
         from information_schema.columns
        where table_schema = 'public'
          and (
            (table_name = 'pedidos' and column_name = any(array[
              'destinatario_nombre', 'destinatario_correo',
              'destinatario_telefono'
            ]))
            or (table_name = 'pedido_items' and column_name = any(array[
              'campana_id', 'campana_nombre', 'campana_slug'
            ]))
            or (table_name = 'pagos_intencion' and column_name = any(array[
              'ciclo_carrito_version', 'expira_en', 'carrito_liberado_en',
              'carrito_consumido_en', 'carrito_consumo_resultado',
              'carrito_consumo_detalle'
            ]))
          )
     ) <> 12
     or not exists (
       select 1
         from pg_class c
         join pg_namespace n on n.oid = c.relnamespace
        where n.nspname = 'public'
          and c.relname = 'pw_sucesiones_c4'
          and c.relrowsecurity
     )
     or has_table_privilege('anon', 'public.pw_sucesiones_c4', 'select')
     or has_table_privilege('authenticated', 'public.pw_sucesiones_c4', 'select')
     or has_table_privilege('service_role', 'public.pw_sucesiones_c4', 'select') then
    raise exception using
      errcode = 'P0001',
      message = 'C4_NO_INSTALADO_O_INCOMPLETO';
  end if;

  if exists (
       select 1
         from carritos
        where estado = 'activa'
        group by auth_user_id
       having count(*) > 1
     )
     or exists (
       select 1
         from carrito_items ci
         left join carritos c on c.id = ci.carrito_id
        where c.id is null
     )
     or exists (
       select 1
         from pagos_intencion
        where version_checkout in (0, 1)
          and ciclo_carrito_version <> 0
     )
     or exists (
       select 1
         from pagos_intencion
        where ciclo_carrito_version = 4
          and expira_en is null
     )
     or exists (
       select 1
         from pagos_intencion
        where ciclo_carrito_version = 4
          and estado = 'rechazada'
          and carrito_liberado_en is null
     )
     or exists (
       select 1
         from pagos_intencion
        where carrito_consumido_en is not null
          and carrito_liberado_en is not null
     )
     or exists (
       select 1
         from pagos_intencion
        where ciclo_carrito_version = 4
          and estado = 'procesada'
          and carrito_consumido_en is null
     )
     or exists (
       select 1
         from pw_sucesiones_c4 s
         join pagos_intencion pi on pi.referencia = s.referencia_predecesora
        where s.carrito_id <> pi.carrito_id
           or s.version_predecesora <> pi.carrito_version
           or s.version_sucesora <> s.version_predecesora + 1
           or pi.version_checkout <> 2
           or pi.ciclo_carrito_version <> 0
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'C4_INVARIANTES_NO_AUTORIZAN_ACTIVACION';
  end if;

  -- No reabrir mientras una intención siga vigente o haya una revisión
  -- pendiente. Una intención creada YA VENCIDA no bloquea: co__bloqueo_pago
  -- solo la considera pendiente antes de expira_en, y la liberación perezosa
  -- ocurre al siguiente acceso al carrito, que exige el flag encendido.
  if exists (
       select 1
         from pagos_intencion
        where ciclo_carrito_version = 4
          and (
            (estado = 'creada'
             and carrito_liberado_en is null
             and expira_en > statement_timestamp())
            or (estado = 'requiere_revision' and resuelta_en is null)
          )
     ) then
    raise exception using
      errcode = 'P0001',
      message = 'C4_PAGO_BLOQUEANTE_IMPIDE_ACTIVACION';
  end if;

  update comercial_config
     set carrito_habilitado = true,
         actualizado = statement_timestamp()
   where id = 1
     and carrito_habilitado is false;
  get diagnostics v_filas = row_count;

  if v_filas <> 1 then
    raise exception using
      errcode = 'P0001',
      message = 'C4_FLAG_NO_ACTUALIZADO';
  end if;
end;
$$;

commit;

-- Verificación durable posterior al COMMIT.
select id,
       carrito_habilitado,
       actualizado,
       carrito_habilitado is true as activado_confirmado
  from public.comercial_config
 where id = 1;
-- Esperado: una fila, carrito_habilitado=true, activado_confirmado=true.
