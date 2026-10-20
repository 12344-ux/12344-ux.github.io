-- ============================================================================
-- MAGANDHI · COMERCIAL C5 + SLUG · ACTIVACIÓN CONTROLADA
-- Escritura deliberada. Solo gates estructurales/invariantes: NO bloquea por
-- intenciones o revisiones C4/C5 legítimas; C5 deja el carrito libre y C4 debe
-- conservar su procesamiento histórico. Edge/Pages/postflight son gates humanos.
-- ============================================================================
begin;
set local search_path=pg_catalog,public;
set local statement_timeout='25s';
set local lock_timeout='5s';
select id from comercial_config where id=1 for update;

do $$
declare v_filas integer;
begin
 if (select count(*) from comercial_config where id=1)<>1
    or not exists(select 1 from comercial_config where id=1 and carrito_habilitado is false) then
  raise exception using errcode='P0001',message='C5_ACTIVACION_REQUIERE_SINGLETON_OFF';
 end if;

 if to_regprocedure('public.mc_compras_listar()') is null
 or to_regprocedure('public.mc_reabrir_intencion_c5(text,uuid)') is null
 or to_regprocedure('public.pw__procesar_pago_c5(text,text,text,bigint,text,text,text,jsonb,text,text)') is null
 or to_regprocedure('public.pw__procesar_pago_c4(text,text,text,bigint,text,text,text,jsonb,text,text)') is null
 or to_regprocedure('public.pw__estado_checkout_publico_c4(text,uuid)') is null
 or to_regprocedure('public.cm__asignar_slug_automatico()') is null
 or not (select count(c.column_name)=4 and bool_and(
       c.data_type=e.tipo and c.is_nullable=e.nullable)
      from (values
       ('pagos_intencion','carrito_separado_en','timestamp with time zone','YES'),
       ('pagos_intencion','carrito_version_sucesora','bigint','YES'),
       ('pagos_intencion','carrito_separacion_detalle','jsonb','YES'),
       ('campana_producto','slug','text','NO')
      ) e(tabla,columna,tipo,nullable)
      left join information_schema.columns c on c.table_schema='public'
       and c.table_name=e.tabla and c.column_name=e.columna)
 or (select count(*) from pg_constraint where conrelid='public.pagos_intencion'::regclass
      and convalidated and conname=any(array['pagos_intencion_ciclo_carrito_version',
       'pagos_intencion_expiracion_c4_c5','pagos_intencion_separacion_c5',
       'pagos_intencion_consumo_carrito_resultado','pagos_intencion_ciclo_carrito_solo_v2',
       'pagos_intencion_consumo_carrito_coherente']))<>6
 or not exists(select 1 from pg_index i
      join pg_class x on x.oid=i.indexrelid join pg_class t on t.oid=i.indrelid
      join pg_namespace n on n.oid=t.relnamespace
      where n.nspname='public' and t.relname='pagos_intencion'
       and x.relname='pagos_intencion_c5_propietario_idx' and not i.indisunique
       and i.indnkeyatts=2 and pg_get_indexdef(i.indexrelid,1,true)='auth_user_id'
       and pg_get_indexdef(i.indexrelid,2,true)='creado'
       and (i.indoption[1] & 1) = 1
       and pg_get_expr(i.indpred,i.indrelid)=
         '((version_checkout = 2) AND (ciclo_carrito_version = 5))')
 or not exists(select 1 from pg_index i
      join pg_class x on x.oid=i.indexrelid join pg_class t on t.oid=i.indrelid
      join pg_namespace n on n.oid=t.relnamespace
      where n.nspname='public' and t.relname='pagos_intencion'
       and x.relname='pagos_intencion_c5_expiracion_idx' and not i.indisunique
       and i.indnkeyatts=1 and pg_get_indexdef(i.indexrelid,1,true)='expira_en'
       and pg_get_expr(i.indpred,i.indrelid)=
         '((ciclo_carrito_version = 5) AND (estado = ''creada''::text) AND (transaccion_id IS NULL))')
 or not exists(select 1 from pg_index i
      join pg_class x on x.oid=i.indexrelid join pg_class t on t.oid=i.indrelid
      join pg_namespace n on n.oid=t.relnamespace
      where n.nspname='public' and t.relname='pagos_intencion'
       and x.relname='pagos_intencion_carrito_version_v2_uidx'
       and i.indisunique and i.indisvalid and i.indisready
       and i.indnkeyatts=3
       and pg_get_indexdef(i.indexrelid,1,true)='auth_user_id'
       and pg_get_indexdef(i.indexrelid,2,true)='carrito_id'
       and pg_get_indexdef(i.indexrelid,3,true)='carrito_version'
       and pg_get_expr(i.indpred,i.indrelid)='(version_checkout = 2)')
 or not exists(select 1 from pg_index i
      join pg_class x on x.oid=i.indexrelid join pg_class t on t.oid=i.indrelid
      join pg_namespace n on n.oid=t.relnamespace
      where n.nspname='public' and t.relname='campana_producto'
       and x.relname='campana_producto_slug_key' and i.indisunique
       and i.indnkeyatts=1 and pg_get_indexdef(i.indexrelid,1,true)='slug'
       and pg_get_expr(i.indpred,i.indrelid)='(slug IS NOT NULL)')
 or not exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid
      join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'
      and c.relname='pagos_intencion' and t.tgname='trg_pw_marcar_ciclo_carrito_c5'
      and not t.tgisinternal and t.tgenabled='O' and t.tgtype=7
      and t.tgfoid=to_regprocedure('public.pw__marcar_ciclo_carrito_c5()'))
 or not exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid
      join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'
      and c.relname='campana_producto' and t.tgname='trg_cm_slug_automatico'
      and not t.tgisinternal and t.tgenabled='O' and t.tgtype=23
      and t.tgfoid=to_regprocedure('public.cm__asignar_slug_automatico()'))
 or exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid
      join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'
      and c.relname='pagos_intencion' and t.tgname='trg_pw_marcar_ciclo_carrito_c4'
      and not t.tgisinternal)
 or has_function_privilege('anon','public.mc_compras_listar()','execute')
 or not has_function_privilege('authenticated','public.mc_compras_listar()','execute')
 or has_function_privilege('authenticated','public.mc_reabrir_intencion_c5(text,uuid)','execute')
 or not has_function_privilege('service_role','public.mc_reabrir_intencion_c5(text,uuid)','execute')
 or has_function_privilege('service_role','public.cm__asignar_slug_automatico()','execute')
 or has_table_privilege('anon','public.campana_producto','select')
 or not has_table_privilege('authenticated','public.campana_producto','select')
 or has_table_privilege('authenticated','public.campana_producto','insert')
 or has_table_privilege('authenticated','public.campana_producto','update')
 or has_table_privilege('authenticated','public.campana_producto','delete')
 or not has_table_privilege('anon','public.catalogo_publico','select')
 or has_table_privilege('anon','public.comercial_config','select')
 or has_table_privilege('authenticated','public.comercial_config','select')
 or has_table_privilege('anon','public.pagos_intencion_items','select')
 or has_table_privilege('authenticated','public.pagos_intencion_items','select')
 or not has_table_privilege('service_role','public.pagos_intencion_items','select')
 or not has_table_privilege('service_role','public.pagos_intencion_items','insert')
 or not has_table_privilege('service_role','public.pagos_intencion_items','update')
 or not has_table_privilege('service_role','public.pagos_intencion_items','delete')
 or has_table_privilege('anon','public.pagos_intencion','select')
 or not has_table_privilege('authenticated','public.pagos_intencion','select')
 or has_table_privilege('authenticated','public.pagos_intencion','insert')
 or has_table_privilege('authenticated','public.pagos_intencion','update')
 or has_table_privilege('authenticated','public.pagos_intencion','delete')
 or not (select count(*) = 1 and bool_and(
      policyname='pagos_intencion_select_ventas'
      and cmd='SELECT'
      and permissive='PERMISSIVE'
      and roles=array['authenticated']::name[]
      and qual='tiene_acceso_pagos()'
      and with_check is null)
      from pg_policies
      where schemaname='public' and tablename='pagos_intencion')
 or has_table_privilege('anon','public.pw_sucesiones_c4','select')
 or has_table_privilege('authenticated','public.pw_sucesiones_c4','select')
 or has_table_privilege('service_role','public.pw_sucesiones_c4','select')
 or not has_table_privilege('authenticated','public.carritos','select')
 or has_table_privilege('authenticated','public.carritos','insert')
 or has_table_privilege('authenticated','public.carritos','update')
 or has_table_privilege('authenticated','public.carritos','delete')
 or not has_table_privilege('authenticated','public.carrito_items','select')
 or has_table_privilege('authenticated','public.carrito_items','insert')
 or has_table_privilege('authenticated','public.carrito_items','update')
 or has_table_privilege('authenticated','public.carrito_items','delete')
 or has_table_privilege('anon','public.pedidos','select')
 or not has_table_privilege('authenticated','public.pedidos','select')
 or has_table_privilege('authenticated','public.pedidos','insert')
 or has_table_privilege('authenticated','public.pedidos','update')
 or has_table_privilege('authenticated','public.pedidos','delete')
 or has_table_privilege('anon','public.pedido_items','select')
 or not has_table_privilege('authenticated','public.pedido_items','select')
 or has_table_privilege('authenticated','public.pedido_items','insert')
 or has_table_privilege('authenticated','public.pedido_items','update')
 or has_table_privilege('authenticated','public.pedido_items','delete')
 or exists(select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname=any(array['comercial_config','carritos',
       'carrito_items','pagos_intencion','pagos_intencion_items','pw_sucesiones_c4',
       'pedidos','pedido_items','campana_producto']) and not c.relrowsecurity)
 or exists(select 1 from pg_policies where schemaname='public'
      and tablename='pw_sucesiones_c4') then
  raise exception using errcode='P0001',message='C5_O_SLUG_NO_INSTALADO_O_INCOMPLETO';
 end if;

 -- Misma matriz de firmas del postflight: existencia, definer/search_path y
 -- EXECUTE efectivo. Impide activar sobre una sobrecarga o grant derivado.
 if exists (
   with e(firma,definer,anon_e,auth_e,service_e) as (values
    ('public.pw_registrar_intencion_carrito(text,uuid,uuid,bigint,text,jsonb,text,text,text)',true,false,false,true),
    ('public.pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text)',true,false,false,true),
    ('public.pw_estado_checkout_publico(text,uuid)',true,false,false,true),
    ('public.mc_compras_listar()',true,false,true,true),
    ('public.mc_reabrir_intencion_c5(text,uuid)',true,false,false,true),
    ('public.avanzar_estado_pedido(uuid,text)',true,false,true,true),
    ('public.pw__registrar_intencion_carrito_c4(text,uuid,uuid,bigint,text,jsonb,text,text,text)',true,false,false,false),
    ('public.pw__procesar_pago_c4(text,text,text,bigint,text,text,text,jsonb,text,text)',true,false,false,false),
    ('public.pw__procesar_pago_c5(text,text,text,bigint,text,text,text,jsonb,text,text)',true,false,false,false),
    ('public.pw__estado_checkout_publico_c4(text,uuid)',true,false,false,false),
    ('public.pw__snapshot_intencion_c5(text)',true,false,false,false),
    ('public.pw__expirar_intencion_c5(text)',true,false,false,false),
    ('public.pw__marcar_ciclo_carrito_c5()',false,false,false,false),
    ('public.cm__asignar_slug_automatico()',true,false,false,false),
    ('public.cm_crear_campana(text,text,text,text,text,bigint,text,text,text,jsonb,jsonb,boolean,boolean,integer,boolean,integer,text[],uuid,text,integer,boolean,integer)',true,false,true,true),
    ('public.cm_editar_campana(uuid,text,text,text,text,text,bigint,text,text,text,jsonb,jsonb,boolean,boolean,integer,boolean,integer,text[],uuid,text,integer,boolean,integer)',true,false,true,true)
   ), r as (select e.*,to_regprocedure(firma) oid from e)
   select 1 from r left join pg_proc p on p.oid=r.oid
    where r.oid is null or p.prosecdef is distinct from r.definer
       or coalesce('search_path=public'=any(p.proconfig),false) is not true
       or has_function_privilege('anon',r.oid,'execute') is distinct from r.anon_e
       or has_function_privilege('authenticated',r.oid,'execute') is distinct from r.auth_e
       or has_function_privilege('service_role',r.oid,'execute') is distinct from r.service_e
 ) then
  raise exception using errcode='P0001',message='C5_FIRMAS_O_ACL_NO_AUTORIZAN_ACTIVACION';
 end if;

 if exists(select 1 from carritos where estado='activa' group by auth_user_id having count(*)>1)
 or exists(select 1 from carrito_items ci left join carritos c on c.id=ci.carrito_id where c.id is null)
 or exists(select 1 from pagos_intencion where version_checkout in(0,1) and ciclo_carrito_version<>0)
 or exists(select 1 from pagos_intencion where ciclo_carrito_version in(0,4) and
      (carrito_separado_en is not null or carrito_version_sucesora is not null
       or carrito_separacion_detalle is not null))
 or exists(select 1 from pagos_intencion where ciclo_carrito_version=5 and
      (expira_en is null or carrito_separado_en is null
       or carrito_version_sucesora is distinct from carrito_version+1
       or carrito_separacion_detalle is null or carrito_consumido_en is not null
       or carrito_consumo_resultado is not null or carrito_consumo_detalle is not null))
 or exists(
      select 1
        from pagos_intencion pi
        left join lateral (
          select count(*)::bigint as cantidad,
                 min(i.ordinal)::integer as ordinal_minimo,
                 max(i.ordinal)::integer as ordinal_maximo,
                 sum(i.subtotal::numeric * 100) as total_centavos
            from pagos_intencion_items i
           where i.referencia = pi.referencia
        ) l on true
       where pi.ciclo_carrito_version = 5
         and (
           l.cantidad not between 1 and 20
           or l.ordinal_minimo <> 1
           or l.ordinal_maximo <> l.cantidad
           or l.total_centavos is distinct from pi.monto_centavos::numeric
         )
    )
 or exists(select 1 from pagos_intencion where ciclo_carrito_version=5
      and estado='procesada' and pedido_id is null)
 or exists(select 1 from campana_producto where slug is null or btrim(slug)=''
      or slug is distinct from cm_normalizar_slug(slug) or length(slug)>180)
 or exists(select slug from campana_producto group by slug having count(*)>1) then
  raise exception using errcode='P0001',message='C5_INVARIANTES_NO_AUTORIZAN_ACTIVACION';
 end if;

 -- Deliberadamente no hay gate por estado de intención C4/C5. Pendientes,
 -- expiradas perezosas y revisiones son historia/operación legítima y deben
 -- verse en comercial-c5-estado.sql, no apagar globalmente el carrito C5.
 update comercial_config set carrito_habilitado=true,actualizado=statement_timestamp()
  where id=1 and carrito_habilitado is false;
 get diagnostics v_filas=row_count;
 if v_filas<>1 then
  raise exception using errcode='P0001',message='C5_FLAG_NO_ACTUALIZADO';
 end if;
end;
$$;
commit;
select id,carrito_habilitado,actualizado,
 carrito_habilitado is true as activado_confirmado
 from public.comercial_config where id=1;
