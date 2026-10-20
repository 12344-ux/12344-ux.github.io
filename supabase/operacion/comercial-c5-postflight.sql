-- ============================================================================
-- MAGANDHI · COMERCIAL C5 + SLUG · POSTFLIGHT DE PRODUCCIÓN
-- Ejecutar completo y separado después de las dos migraciones. Solo lectura;
-- no invoca RPC mutantes y no devuelve PII, referencias, UUID ni secretos.
-- ============================================================================
begin transaction read only;
set local search_path=pg_catalog,public;
set local statement_timeout='25s';
set local lock_timeout='3s';

-- 1/8 · Resumen estructural. Todas las columnas deben ser true.
with cols(tabla,columna,tipo,nullable) as (values
 ('pagos_intencion','carrito_separado_en','timestamp with time zone','YES'),
 ('pagos_intencion','carrito_version_sucesora','bigint','YES'),
 ('pagos_intencion','carrito_separacion_detalle','jsonb','YES'),
 ('campana_producto','slug','text','NO')
), cotejo as (
 select count(c.column_name)=4 and bool_and(c.data_type=e.tipo and c.is_nullable=e.nullable) ok
 from cols e left join information_schema.columns c on c.table_schema='public'
  and c.table_name=e.tabla and c.column_name=e.columna
)
select (select count(*)=1 and bool_and(id=1 and carrito_habilitado is false)
          from comercial_config) as config_singleton_flag_off,
       (select ok from cotejo) as columnas_ok,
       (select count(*)=6 and bool_and(convalidated) from pg_constraint
         where conrelid='public.pagos_intencion'::regclass and conname=any(array[
          'pagos_intencion_ciclo_carrito_version','pagos_intencion_expiracion_c4_c5',
          'pagos_intencion_separacion_c5','pagos_intencion_consumo_carrito_resultado',
          'pagos_intencion_ciclo_carrito_solo_v2','pagos_intencion_consumo_carrito_coherente']))
         as constraints_c4_c5_ok,
       exists(select 1 from pg_index i
         join pg_class x on x.oid=i.indexrelid join pg_class t on t.oid=i.indrelid
         join pg_namespace n on n.oid=t.relnamespace
         where n.nspname='public' and t.relname='pagos_intencion'
          and x.relname='pagos_intencion_c5_propietario_idx' and not i.indisunique
          and i.indnkeyatts=2 and pg_get_indexdef(i.indexrelid,1,true)='auth_user_id'
          and pg_get_indexdef(i.indexrelid,2,true)='creado DESC'
          and pg_get_expr(i.indpred,i.indrelid)=
            '((version_checkout = 2) AND (ciclo_carrito_version = 5))')
       and exists(select 1 from pg_index i
         join pg_class x on x.oid=i.indexrelid join pg_class t on t.oid=i.indrelid
         join pg_namespace n on n.oid=t.relnamespace
         where n.nspname='public' and t.relname='pagos_intencion'
          and x.relname='pagos_intencion_c5_expiracion_idx' and not i.indisunique
          and i.indnkeyatts=1 and pg_get_indexdef(i.indexrelid,1,true)='expira_en'
          and pg_get_expr(i.indpred,i.indrelid)=
            '((ciclo_carrito_version = 5) AND (estado = ''creada''::text) AND (transaccion_id IS NULL))')
       and exists(select 1 from pg_index i
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
         as indices_c5_ok,
       exists(select 1 from pg_index i
         join pg_class x on x.oid=i.indexrelid join pg_class t on t.oid=i.indrelid
         join pg_namespace n on n.oid=t.relnamespace
         where n.nspname='public' and t.relname='campana_producto'
          and x.relname='campana_producto_slug_key' and i.indisunique
          and i.indnkeyatts=1 and pg_get_indexdef(i.indexrelid,1,true)='slug'
          and pg_get_expr(i.indpred,i.indrelid)='(slug IS NOT NULL)')
         as indice_slug_preservado,
       (select count(*)=2 and bool_and(t.tgenabled='O')
          and bool_and(
            (c.relname='pagos_intencion' and t.tgname='trg_pw_marcar_ciclo_carrito_c5'
             and t.tgtype=7 and t.tgfoid=to_regprocedure('public.pw__marcar_ciclo_carrito_c5()'))
            or
            (c.relname='campana_producto' and t.tgname='trg_cm_slug_automatico'
             and t.tgtype=23 and t.tgfoid=to_regprocedure('public.cm__asignar_slug_automatico()'))
          )
        from pg_trigger t join pg_class c on c.oid=t.tgrelid
         join pg_namespace n on n.oid=c.relnamespace
        where n.nspname='public' and not t.tgisinternal and t.tgname in
          ('trg_pw_marcar_ciclo_carrito_c5','trg_cm_slug_automatico')) as triggers_ok,
       not exists(select 1 from pg_trigger t join pg_class c on c.oid=t.tgrelid
         join pg_namespace n on n.oid=c.relnamespace where n.nspname='public'
         and c.relname='pagos_intencion' and t.tgname='trg_pw_marcar_ciclo_carrito_c4'
         and not t.tgisinternal) as trigger_c4_retirado,
       to_regprocedure('public.mc_compras_listar()') is not null
         and to_regprocedure('public.mc_reabrir_intencion_c5(text,uuid)') is not null
         and to_regprocedure('public.cm__asignar_slug_automatico()') is not null as puertas_y_helper_ok;

-- 2/8 · Columnas y constraints para archivar evidencia.
select table_name,column_name,data_type,udt_name,is_nullable,column_default
 from information_schema.columns where table_schema='public' and (
  (table_name='pagos_intencion' and column_name in
   ('carrito_separado_en','carrito_version_sucesora','carrito_separacion_detalle'))
  or (table_name='campana_producto' and column_name='slug'))
 order by table_name,ordinal_position;
select c.conname,c.contype,c.convalidated,pg_get_constraintdef(c.oid) as definicion
 from pg_constraint c where c.conrelid='public.pagos_intencion'::regclass
 and c.conname=any(array['pagos_intencion_ciclo_carrito_version',
 'pagos_intencion_expiracion_c4_c5','pagos_intencion_separacion_c5',
 'pagos_intencion_consumo_carrito_resultado','pagos_intencion_ciclo_carrito_solo_v2',
 'pagos_intencion_consumo_carrito_coherente']) order by c.conname;

-- 3/8 · Índices y triggers.
select tablename,indexname,indexdef from pg_indexes where schemaname='public' and indexname=any(array[
 'pagos_intencion_carrito_version_v2_uidx','pagos_intencion_c5_propietario_idx',
 'pagos_intencion_c5_expiracion_idx','campana_producto_slug_key']) order by indexname;
select c.relname as tabla,t.tgname,t.tgenabled,pg_get_triggerdef(t.oid) as definicion
 from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
 where n.nspname='public' and not t.tgisinternal and t.tgname in
 ('trg_pw_marcar_ciclo_carrito_c5','trg_cm_slug_automatico','trg_pw_marcar_ciclo_carrito_c4')
 order by c.relname,t.tgname;

-- 4/8 · Historia 0/4, C5 y snapshots agregados.
with lineas as (
 select referencia,count(*)::bigint n,min(ordinal) minimo,max(ordinal) maximo,
        sum(subtotal::numeric*100) total
 from pagos_intencion_items group by referencia)
select count(*) filter(where pi.ciclo_carrito_version=0)::bigint as ciclo_cero,
 count(*) filter(where pi.ciclo_carrito_version=4)::bigint as ciclo_cuatro,
 count(*) filter(where pi.ciclo_carrito_version=5)::bigint as ciclo_cinco,
 count(*) filter(where pi.ciclo_carrito_version in(0,4) and
  (pi.carrito_separado_en is not null or pi.carrito_version_sucesora is not null
   or pi.carrito_separacion_detalle is not null))::bigint as historia_0_4_alterada,
 count(*) filter(where pi.ciclo_carrito_version=5 and
  (pi.carrito_separado_en is null or pi.carrito_version_sucesora is distinct from pi.carrito_version+1
   or pi.carrito_separacion_detalle is null or pi.carrito_consumido_en is not null
   or pi.carrito_consumo_resultado is not null or pi.carrito_consumo_detalle is not null))::bigint
   as separaciones_c5_invalidas,
 count(*) filter(where pi.ciclo_carrito_version=5 and
  (l.referencia is null or l.n not between 1 and 20 or l.minimo<>1 or l.maximo<>l.n
   or l.total<>pi.monto_centavos::numeric))::bigint as snapshots_c5_invalidos
 from pagos_intencion pi left join lineas l using(referencia);

select count(*) filter(where ciclo_carrito_version=5 and estado='procesada' and pedido_id is null)::bigint
         as procesadas_sin_pedido,
       count(*) filter(where ciclo_carrito_version=5 and pedido_id is not null)::bigint as enlaces_pedido,
       count(distinct pedido_id) filter(where ciclo_carrito_version=5 and pedido_id is not null)::bigint
         as pedidos_distintos,
       count(*) filter(where version_checkout in(0,1) and ciclo_carrito_version<>0)::bigint
         as historia_checkout_reetiquetada
 from pagos_intencion;

-- 5/8 · Slug: NOT NULL, unicidad y backfill completo sin revelar valores.
select count(*)::bigint as total,
 count(*) filter(where slug is null)::bigint as nulls,
 count(*)-count(distinct slug)::bigint as duplicados,
 count(*) filter(where slug is distinct from cm_normalizar_slug(slug)
                   or length(slug)>180)::bigint as no_normalizados,
 coalesce(bool_and(length(btrim(slug))>0),true) as todos_no_vacios
 from campana_producto;

-- 6/8 · RLS/policies: C5 no agrega tablas ni amplía superficie.
select c.relname as tabla,c.relrowsecurity as rls,c.relforcerowsecurity as force_rls,
 count(p.policyname)::bigint as policies
 from pg_class c join pg_namespace n on n.oid=c.relnamespace
 left join pg_policies p on p.schemaname=n.nspname and p.tablename=c.relname
 where n.nspname='public' and c.relname=any(array['comercial_config','carritos','carrito_items',
 'pagos_intencion','pagos_intencion_items','pw_sucesiones_c4','pedidos','pedido_items','campana_producto'])
 group by c.relname,c.relrowsecurity,c.relforcerowsecurity order by c.relname;
select not has_table_privilege('anon','public.comercial_config','select')
       and not has_table_privilege('authenticated','public.comercial_config','select')
         as config_sin_lectura_api,
       not has_table_privilege('anon','public.pagos_intencion','select')
       and has_table_privilege('authenticated','public.pagos_intencion','select')
       and not has_table_privilege('authenticated','public.pagos_intencion','insert')
       and not has_table_privilege('authenticated','public.pagos_intencion','update')
       and not has_table_privilege('authenticated','public.pagos_intencion','delete')
       and (select count(*) = 1 and bool_and(
          policyname = 'pagos_intencion_select_ventas'
          and cmd = 'SELECT'
          and permissive = 'PERMISSIVE'
          and roles = array['authenticated']::name[]
          and qual = 'tiene_acceso_pagos()'
          and with_check is null
        )
          from pg_policies
         where schemaname='public' and tablename='pagos_intencion')
         as intenciones_ventas_por_rls,
       not has_table_privilege('anon','public.pagos_intencion_items','select')
       and not has_table_privilege('authenticated','public.pagos_intencion_items','select')
       and has_table_privilege('service_role','public.pagos_intencion_items','select')
       and has_table_privilege('service_role','public.pagos_intencion_items','insert')
       and has_table_privilege('service_role','public.pagos_intencion_items','update')
       and has_table_privilege('service_role','public.pagos_intencion_items','delete')
         as snapshots_solo_service_role,
       not has_table_privilege('anon','public.pw_sucesiones_c4','select')
       and not has_table_privilege('authenticated','public.pw_sucesiones_c4','select')
       and not has_table_privilege('service_role','public.pw_sucesiones_c4','select')
         as sucesiones_cerradas,
       has_table_privilege('authenticated','public.carritos','select')
       and not has_table_privilege('authenticated','public.carritos','insert')
       and not has_table_privilege('authenticated','public.carritos','update')
       and not has_table_privilege('authenticated','public.carritos','delete')
         as carritos_authenticated_solo_lectura,
       has_table_privilege('authenticated','public.carrito_items','select')
       and not has_table_privilege('authenticated','public.carrito_items','insert')
       and not has_table_privilege('authenticated','public.carrito_items','update')
       and not has_table_privilege('authenticated','public.carrito_items','delete')
         as items_authenticated_solo_lectura,
       not has_table_privilege('anon','public.pedidos','select')
       and has_table_privilege('authenticated','public.pedidos','select')
       and not has_table_privilege('authenticated','public.pedidos','insert')
       and not has_table_privilege('authenticated','public.pedidos','update')
       and not has_table_privilege('authenticated','public.pedidos','delete')
         as pedidos_protegidos_por_rls,
       not has_table_privilege('anon','public.pedido_items','select')
       and has_table_privilege('authenticated','public.pedido_items','select')
       and not has_table_privilege('authenticated','public.pedido_items','insert')
       and not has_table_privilege('authenticated','public.pedido_items','update')
       and not has_table_privilege('authenticated','public.pedido_items','delete')
         as pedido_items_protegidos_por_rls,
       not has_table_privilege('anon','public.campana_producto','select')
       and has_table_privilege('authenticated','public.campana_producto','select')
       and not has_table_privilege('authenticated','public.campana_producto','insert')
       and not has_table_privilege('authenticated','public.campana_producto','update')
       and not has_table_privilege('authenticated','public.campana_producto','delete')
         as campanas_authenticated_solo_lectura,
       has_table_privilege('anon','public.catalogo_publico','select')
         as catalogo_publico_legible;

-- 7/8 · Firmas y ACL efectivas. Cada fila: existe y las cinco columnas *_ok true.
with e(etiqueta,firma,definer,anon_e,auth_e,service_e) as (values
 ('registrar','public.pw_registrar_intencion_carrito(text,uuid,uuid,bigint,text,jsonb,text,text,text)',true,false,false,true),
 ('procesar','public.pw_procesar_pago(text,text,text,bigint,text,text,text,jsonb,text,text)',true,false,false,true),
 ('estado','public.pw_estado_checkout_publico(text,uuid)',true,false,false,true),
 ('mis compras','public.mc_compras_listar()',true,false,true,true),
 ('reabrir','public.mc_reabrir_intencion_c5(text,uuid)',true,false,false,true),
 ('avanzar pedido','public.avanzar_estado_pedido(uuid,text)',true,false,true,true),
 ('registrar C4 privado','public.pw__registrar_intencion_carrito_c4(text,uuid,uuid,bigint,text,jsonb,text,text,text)',true,false,false,false),
 ('procesar C4 privado','public.pw__procesar_pago_c4(text,text,text,bigint,text,text,text,jsonb,text,text)',true,false,false,false),
 ('procesar C5 privado','public.pw__procesar_pago_c5(text,text,text,bigint,text,text,text,jsonb,text,text)',true,false,false,false),
 ('estado C4 privado','public.pw__estado_checkout_publico_c4(text,uuid)',true,false,false,false),
 ('snapshot C5','public.pw__snapshot_intencion_c5(text)',true,false,false,false),
 ('expirar C5','public.pw__expirar_intencion_c5(text)',true,false,false,false),
 ('trigger C5','public.pw__marcar_ciclo_carrito_c5()',false,false,false,false),
 ('trigger slug','public.cm__asignar_slug_automatico()',true,false,false,false),
 ('crear campaña viva','public.cm_crear_campana(text,text,text,text,text,bigint,text,text,text,jsonb,jsonb,boolean,boolean,integer,boolean,integer,text[],uuid,text,integer,boolean,integer)',true,false,true,true),
 ('editar campaña viva','public.cm_editar_campana(uuid,text,text,text,text,text,bigint,text,text,text,jsonb,jsonb,boolean,boolean,integer,boolean,integer,text[],uuid,text,integer,boolean,integer)',true,false,true,true)
), r as(select e.*,to_regprocedure(firma) oid from e), a as(
 select r.*,p.prosecdef,p.proconfig,
  case when oid is null then null else has_function_privilege('anon',oid,'execute') end anon_r,
  case when oid is null then null else has_function_privilege('authenticated',oid,'execute') end auth_r,
  case when oid is null then null else has_function_privilege('service_role',oid,'execute') end service_r
 from r left join pg_proc p on p.oid=r.oid)
select etiqueta,firma,oid is not null as existe,prosecdef=definer as security_definer_ok,
 coalesce('search_path=public'=any(proconfig),false) as search_path_publico_ok,
 anon_r=anon_e as anon_ok,auth_r=auth_e as authenticated_ok,service_r=service_e as service_role_ok
 from a order by etiqueta;

-- 8/8 · Invariantes generales y Wompi, sin datos sensibles.
select not exists(select 1 from carritos where estado='activa' group by auth_user_id having count(*)>1)
 as sin_doble_carrito_activo,
 not exists(select 1 from carrito_items ci left join carritos c on c.id=ci.carrito_id where c.id is null)
 as sin_lineas_huerfanas,
 not exists(select 1 from pagos_intencion where ciclo_carrito_version=5 and expira_en is null)
 as c5_con_expiracion,
 (select count(*)=1 and bool_and(id=1 and entorno='prod' and length(btrim(llave_publica_prod))>0)
  from pagos_config) as wompi_prod_configurado;
rollback;
