-- ============================================================
-- Impulse · PRUEBA DE PERMISOS (RLS + EXECUTE) · matriz por persona
-- ------------------------------------------------------------
-- QUE HACE: comprueba, con datos reales del proyecto, QUE ve y QUE puede
-- ejecutar cada tipo de persona:
--   anon (visitante de la tienda) · cliente autenticado SIN perfil interno ·
--   autenticado interno SIN modulo · Finanzas · Produccion/Inventario ·
--   Marketing · Métricas · Ventas · admin · service_role (solo puertas
--   nominales de servidor; sus expectativas se validan explícitamente).
-- Para cada tabla/vista compara lo que ve la persona contra la VERDAD (lo que
-- ve postgres, que salta la RLS) y lo clasifica:
--   TODO    = ve exactamente lo mismo que la verdad
--   NADA    = 0 filas o "permission denied"
--   PROPIA  = solo su propia fila (perfiles)
--   PARCIAL = ve algo distinto a todo/nada  (casi siempre indica un problema)
-- Y compara cada resultado con lo ESPERADO por el diseno de seguridad.
--
-- ES SEGURO EN EL PROYECTO REAL: crea personas y datos de prueba (un asiento,
-- un cliente, un pedido, un movimiento) DENTRO de un bloque que SIEMPRE se
-- deshace al final. No queda NADA escrito: ni usuarios, ni perfiles, ni
-- asientos, ni stock. Solo sobrevive la tabla temporal del informe, que
-- desaparece al cerrar la sesion del editor.
--
-- COMO SE USA (SQL Editor de Supabase): pegar TODO el archivo y Run. El
-- resultado es una tabla. La primera fila es el RESUMEN: debe decir
-- "TODO PASA". Cualquier fila con veredicto FALLA indica una puerta abierta
-- (o cerrada de mas) y dice exactamente en que objeto y para que persona.
--
-- REQUISITO: correr DESPUES de las migraciones del Tramo 0 (20250606*).
-- Antes del Tramo 0 esta prueba DEBE fallar en movimientos_mayor,
-- saldos_cuenta y stock_actual para las personas sin modulo (esa es la
-- vulnerabilidad que el Tramo 0 cierra) y en el bloque de EXECUTE.
-- ============================================================

drop table if exists pg_temp.tramo0_resultado;
create temp table tramo0_resultado (
  orden     int,
  persona   text,
  objeto    text,
  esperado  text,
  obtenido  text,
  veredicto text
);

do $$
declare
  -- Personas de prueba (UUID fijos y reconocibles; se deshacen al final).
  c_cli   constant uuid := '7e570000-0000-4000-8000-000000000000';
  c_sin   constant uuid := '7e570000-0000-4000-8000-000000000001';
  c_fin   constant uuid := '7e570000-0000-4000-8000-000000000002';
  c_inv   constant uuid := '7e570000-0000-4000-8000-000000000003';
  c_mkt   constant uuid := '7e570000-0000-4000-8000-000000000004';
  c_ven   constant uuid := '7e570000-0000-4000-8000-000000000005';
  c_adm   constant uuid := '7e570000-0000-4000-8000-000000000006';
  c_met   constant uuid := '7e570000-0000-4000-8000-000000000007';

  -- Objetos a probar. Cada uno tiene su consulta de "huella": numero de filas
  -- + hash del contenido. perfiles usa una huella especial (PROPIA).
  v_obj  text[] := array[
    'perfiles',
    'puc_cuentas','asientos','asiento_lineas','asiento_bitacora',
    'movimientos_mayor','saldos_cuenta','contabilidad_config','pagos_config',
    'inventario_config','productos','movimientos_inventario','stock_actual',
    'clientes','pedidos','pedido_items','pedido_bitacora','portafolio_metricas',
    'campana_producto','campana_categoria','campana_etiqueta','campana_producto_etiqueta',
    'catalogo_publico'
  ];

  -- Personas: nombre, rol de base de datos, uid (null = sin sesion).
  v_pers text[] := array['anon','cliente','sin_modulo','finanzas','produccion','marketing','metricas','ventas','admin','service_role'];
  v_rol  text[] := array['anon','authenticated','authenticated','authenticated','authenticated','authenticated','authenticated','authenticated','authenticated','service_role'];
  v_uid  uuid[];

  -- Resultados acumulados (sobreviven al rollback del bloque interno).
  r_pers text[] := '{}';
  r_obj  text[] := '{}';
  r_esp  text[] := '{}';
  r_obt  text[] := '{}';

  v_verdad_n bigint[] := '{}';
  v_verdad_h text[]   := '{}';

  v_n   bigint;
  v_h   text;
  v_obt text;
  v_esp text;
  v_sql text;
  i int; j int;
  v_producto uuid;
  v_cliente  uuid;
  v_pedido   uuid;
  v_asiento  uuid;
  v_funcs_auth text[];
  v_p5 record;
  v_sn record;
  v_lista_blanca text[] := array[
    'agregar_cuenta_puc','anular_asiento','anular_pedido','avanzar_estado_pedido',
    'balance_comprobacion','balance_general','buscar_candidatos_cliente',
    'cm_crear_campana','cm_crear_etiqueta','cm_editar_campana','cm_editar_etiqueta',
    'cm_publicar_campana','cm_retirar_placeholder','crear_pedido','editar_asiento',
    'estado_resultados','guardar_asiento','incrementar_uso_cuenta','inv_crear_producto',
    'inv_editar_producto','inv_registrar_movimiento','pagos_config_para_intencion',
    'tiene_acceso_inventario','tiene_acceso_marketing','tiene_acceso_ventas','tiene_modulo',
    -- Campanas (reordenar), Opiniones, Correos del pedido y stock
    'cm_reordenar_campanas','op_ocultar_opinion','op_opiniones_producto','op_responder_opinion',
    'op_resumen_productos','tiene_acceso_opiniones','correo_guardar_plantilla','correo_pedido_preparar',
    'correo_pedido_resultado','correo_prueba_preparar','correo_ref_pedido','ventas_stock_disponible',
    -- Email marketing EM1-EM4 (cada una con su guardia interna)
    'tiene_acceso_email_marketing','em_alta_manual','em_editar_contacto','em_dar_baja','em_resumen',
    'em_contacto_detalle','em_correos_seguimiento','mk_perfiles_clientes','em_segmento_previa',
    'em_segmento_guardar','em_segmento_archivar','em_segmentos_lista','em_segmento_opciones',
    'em_segmento_desde_cluster','em_campana_guardar','em_campana_duplicar','em_campana_audiencia',
    'em_campanas_lista','em_campana_detalle','em_campana_registrar_prueba','em_campana_confirmar',
    'em_campana_pendientes','em_campana_set_segmento_resend','em_campana_destinatario_resultado',
    'em_campana_reservar_envio','em_campana_marcar_enviada','em_campana_cancelar','em_config_politica',
    -- EM5 (lectura). em_webhook_registrar NO va: solo service_role.
    'em_campana_resultados','em_campanas_resultados_lista','em_salud_lista','em_contacto_campanas',
    -- EM6 (panel). em_publico_* NO van: solo service_role.
    'em_config_captura','em_captura_estado',
    -- Metricas M1 (capa de datos). mt_publico_config / mt_registrar_eventos NO: solo service_role.
    'tiene_acceso_metricas','tiene_acceso_datos_metricas','mt_config_analitica','mt_en_vivo','mt_ventas','mt_tienda',
    -- Metricas M2 (capa de datos). mt_email/mt_opiniones/mt_inventario con guardia de datos.
    'mt_email','mt_opiniones','mt_inventario'
    -- Pagos web F2: las puertas del panel se agregan de manera condicional
    -- abajo: la matriz también corre fotos históricas anteriores a F2.
    -- Pagos web F3: los avisos contables se agregan condicionalmente abajo.
  ];
  v_extra text;
begin
  v_uid := array[null, c_cli, c_sin, c_fin, c_inv, c_mkt, c_met, c_ven, c_adm, null]::uuid[];

  begin  -- ===== bloque que SIEMPRE se deshace =====

    -- La matriz también se usa contra fotografías históricas. Los objetos de
    -- categorías se agregan solo cuando la forward que los crea está presente.
    if to_regclass('public.campana_producto_categoria') is not null
       and to_regclass('public.categorias_publicas') is not null then
      v_obj := v_obj || array['campana_producto_categoria', 'categorias_publicas'];
    end if;

    -- C1 de cuentas publicas. En fotos historicas la tabla no existe: solo se
    -- agrega cuando el esquema realmente contiene el puente.
    if to_regclass('public.cuentas_cliente') is not null then
      v_obj := v_obj || array['cuentas_cliente'];
      v_lista_blanca := v_lista_blanca || array[
        'es_personal_interno', 'es_cuenta_cliente', 'mi_cliente_id'
      ];
    end if;
    -- C2 agrega una sola puerta de alta para authenticated. La tabla privada
    -- de conflictos no entra en v_obj: ningun rol API tiene acceso a ella.
    if to_regprocedure('public.cc_inicializar_cuenta()') is not null then
      v_lista_blanca := v_lista_blanca || array['cc_inicializar_cuenta'];
    end if;

    -- Comercial C2 añade exactamente cuatro puertas autenticadas de carrito.
    -- Sus helpers, triggers y configuración permanecen fuera de la superficie
    -- API. La condición conserva las fotos históricas anteriores a C2.
    if to_regprocedure('public.co_carrito_listar()') is not null then
      v_lista_blanca := v_lista_blanca || array[
        'co_carrito_listar', 'co_carrito_agregar',
        'co_carrito_cambiar', 'co_carrito_quitar'
      ];
    end if;

    -- D1 puede no existir a propósito cuando los scripts reproducen una foto
    -- histórica anterior al 10-oct. Si la tabla existe, la lista blanca exige
    -- sus tres puertas; si no existe, exigirlas sería pedir funciones futuras
    -- en una base del pasado y convertiría el simulador en falso rojo.
    if to_regclass('public.dropshipping_candidatos') is not null then
      v_lista_blanca := v_lista_blanca || array[
        'tiene_acceso_dropshipping', 'ds_guardar_candidato', 'ds_actualizar_estado_candidato'
      ];
    end if;
    -- D2a (20261024000000): una sola puerta nueva de panel. Su gatillo
    -- ds__campana_vinculo_proveedor queda solo para service_role.
    if to_regprocedure('public.ds_llevar_a_campanas(uuid,text,text,text,bigint,integer,timestamptz,jsonb)') is not null then
      v_lista_blanca := v_lista_blanca || array['ds_llevar_a_campanas'];
    end if;
    -- D2c.1 (20261026000000): una sola puerta nueva de panel, de LECTURA
    -- (frescura del stock y por qué un producto está fuera de vitrina). Las dos
    -- RPC del refresco —ds_productos_por_refrescar y ds_registrar_lectura_stock—
    -- quedan a propósito FUERA de esta lista: solo las ejecuta service_role
    -- desde la Edge Function, nunca un usuario con sesión.
    if to_regprocedure('public.ds_estado_stock()') is not null then
      v_lista_blanca := v_lista_blanca || array['ds_estado_stock'];
    end if;
    -- D2c.2a (20261027000000) creó la puerta exacta de disponibilidad para
    -- pantallas internas de Ventas. C1 la vuelve helper privado de servidor:
    -- devuelve existencias exactas y ya no pertenece a la lista blanca de
    -- authenticated; catalogo_publico solo expone max_comprable acotado.
    -- C1 comercial: el máximo seguro (0..20) es parte del contrato público y
    -- catalogo_publico necesita poder ejecutarlo bajo anon/authenticated.
    if to_regprocedure('public.ventas_max_comprable_campana(uuid)') is not null then
      v_lista_blanca := v_lista_blanca || array['ventas_max_comprable_campana'];
    end if;

    -- SN1 añade ocho RPC nominales authenticated. Se condicionan por el
    -- singleton para conservar la matriz sobre fotografías anteriores a SN1;
    -- helpers y purga permanecen fuera de esta superficie.
    if to_regclass('public.sn_config') is not null then
      v_lista_blanca := v_lista_blanca || array[
        'sn_campana_detalle_v1', 'sn_guardar_campana_v1',
        'sn_registrar_asset_v1', 'sn_retirar_asset_v1',
        'sn_configurar_v1', 'sn_buscar_v1', 'sn_recomendar_v1',
        'sn_resumen_v1'
      ];
    end if;
    -- D2c.2b (20261028000000): las dos puertas del despacho manual. Ventas las
    -- necesita para ver qué falta transcribir a Dropi y para anotar el número
    -- externo, el costo real y el flete.
    if to_regprocedure('public.ds_pedidos_por_transcribir()') is not null then
      v_lista_blanca := v_lista_blanca || array[
        'ds_pedidos_por_transcribir', 'ds_registrar_transcripcion'
      ];
    end if;

    -- F2 solo existe desde 202610190. La matriz corre también una foto anterior
    -- a F2 para comprobar el diagnóstico, por eso la lista blanca es sensible
    -- al esquema realmente instalado, no a la versión más nueva del repo.
    if to_regclass('public.pagos_intencion') is not null then
      v_lista_blanca := v_lista_blanca || array[
        'tiene_acceso_pagos', 'pw_revisiones', 'pw_resolver_revision'
      ];
    end if;
    -- Comercial C4 añade una acción explícita de panel para confirmar un
    -- reembolso y liberar el carrito. Los helpers de ciclo siguen privados.
    if to_regprocedure('public.pw_resolver_revision_c4(text,text,text)') is not null then
      v_lista_blanca := v_lista_blanca || array['pw_resolver_revision_c4'];
    end if;

    -- Comercial C5 expone una sola puerta de cuenta pública autenticada. Deriva
    -- auth.uid()/customer_id dentro de SECURITY DEFINER y devuelve únicamente
    -- la proyección saneada de Mis compras; las tablas base siguen cerradas.
    if to_regprocedure('public.mc_compras_listar()') is not null then
      v_lista_blanca := v_lista_blanca || array['mc_compras_listar'];
    end if;

    -- Promocionar P3 expone siete puertas administrativas únicamente a
    -- authenticated. Sus helpers, mantenimiento y tablas siguen cerrados; las
    -- dos puertas públicas del redirect pertenecen solo a service_role.
    if to_regprocedure('public.promocionar_p3_config()') is not null then
      v_lista_blanca := v_lista_blanca || array[
        'promocionar_p3_config', 'promocionar_p3_listar',
        'promocionar_p3_crear_borrador', 'promocionar_p3_editar_borrador',
        'promocionar_p3_activar', 'promocionar_p3_desactivar',
        'promocionar_p3_eliminar_borrador'
      ];
    end if;

    -- Promocionar P5 expone exactamente tres lecturas autenticadas, cada una
    -- con guardia de área. El agregador promocionar_p5__agregado permanece
    -- privado y nunca entra en la superficie RPC.
    if to_regprocedure('public.promocionar_p5_resultados(uuid,date,date)') is not null then
      v_lista_blanca := v_lista_blanca || array[
        'promocionar_p5_resultados', 'promocionar_p5_resumen_metricas',
        'promocionar_p5_procedencia_pedidos'
      ];
    end if;

    -- Categorías planas: wrappers atómicos y alta del catálogo para usuarios
    -- autenticados. Los helpers cm__* continúan privados y no entran aquí.
    if to_regprocedure('public.cm_crear_campana_con_categorias(text,text,text,text,bigint,text,text,text,jsonb,jsonb,boolean,boolean,integer,boolean,integer,text[],uuid,text,integer,boolean,integer,text[],text)') is not null then
      v_lista_blanca := v_lista_blanca || array[
        'cm_crear_campana_con_categorias', 'cm_editar_campana_con_categorias'
      ];
    end if;
    if to_regprocedure('public.cm_crear_categoria(text,text,text)') is not null then
      v_lista_blanca := v_lista_blanca || array['cm_crear_categoria'];
    end if;

    -- F3 solo existe desde 202610200. Sus constructores internos siguen fuera
    -- de la lista; estas dos son las únicas puertas de panel.
    if to_regprocedure('public.fz_asientos_automaticos_pendientes()') is not null then
      v_lista_blanca := v_lista_blanca || array[
        'fz_asientos_automaticos_pendientes', 'fz_generar_asiento_automatico'
      ];
    end if;

    -- ---------- Personas de prueba ----------
    insert into auth.users (id, email) values
      (c_cli, 'prueba-cliente-publico@tramo0.invalid'),
      (c_sin, 'prueba-sin-modulo@tramo0.invalid'),
      (c_fin, 'prueba-finanzas@tramo0.invalid'),
      (c_inv, 'prueba-produccion@tramo0.invalid'),
      (c_mkt, 'prueba-marketing@tramo0.invalid'),
      (c_met, 'prueba-metricas@tramo0.invalid'),
      (c_ven, 'prueba-ventas@tramo0.invalid'),
      (c_adm, 'prueba-admin@tramo0.invalid');
    insert into perfiles (id, rol, modulos) values
      (c_sin, 'prueba', '{}'),
      (c_fin, 'prueba', '{finanzas}'),
      (c_inv, 'prueba', '{produccion}'),
      (c_mkt, 'prueba', '{marketing}'),
      (c_met, 'prueba', '{metricas}'),
      (c_ven, 'prueba', '{ventas}'),
      (c_adm, 'admin',  '{}');

    -- ---------- Datos de prueba (garantizan que cada objeto tenga filas) ----------
    select id into v_producto from productos order by creado limit 1;
    if v_producto is null then
      raise exception 'La prueba necesita al menos un producto en Inventario.';
    end if;

    insert into asientos (fecha, descripcion)
      values (current_date, 'PRUEBA TRAMO 0 (se deshace)') returning id into v_asiento;
    insert into asiento_lineas (asiento_id, cuenta_codigo, debe, haber, orden) values
      (v_asiento, '111005', 1000, 0, 1),
      (v_asiento, '413505', 0, 1000, 2);

    insert into movimientos_inventario (product_id, tipo, cantidad, motivo)
      values (v_producto, 'entrada', 7, 'PRUEBA TRAMO 0 (se deshace)');

    insert into clientes (nombre, correo) values ('Cliente prueba Tramo 0', 'cliente@tramo0.invalid')
      returning id into v_cliente;
    if to_regclass('public.cuentas_cliente') is not null then
      insert into cuentas_cliente (auth_user_id, customer_id, vinculado_en)
      values (c_cli, v_cliente, now());
    end if;
    insert into pedidos (customer_id, total) values (v_cliente, 1000) returning id into v_pedido;
    insert into pedido_items (pedido_id, product_id, cantidad, precio_unitario, subtotal)
      values (v_pedido, v_producto, 1, 1000, 1000);
    insert into pedido_bitacora (pedido_id, accion, estado_nuevo) values (v_pedido, 'crear', 'recibido');

    -- ---------- La VERDAD (postgres salta la RLS) ----------
    for i in 1 .. array_length(v_obj, 1) loop
      execute format(
        'select count(*), md5(coalesce(string_agg(t::text, %L order by t::text), %L)) from public.%I t',
        '|', '', v_obj[i]) into v_n, v_h;
      v_verdad_n := v_verdad_n || v_n;
      v_verdad_h := v_verdad_h || v_h;
    end loop;

    -- ---------- Lo que ve cada persona ----------
    for j in 1 .. array_length(v_pers, 1) loop
      execute format('set local role %I', v_rol[j]);
      perform set_config(
        'request.jwt.claims',
        case when v_uid[j] is null
             then json_build_object('role', v_rol[j])::text
             else json_build_object('sub', v_uid[j], 'role', v_rol[j])::text end,
        true);

      for i in 1 .. array_length(v_obj, 1) loop
        -- service_role (Edge Functions) solo tiene grants sobre lo que el
        -- servidor necesita hoy (auto-expose OFF, ver 20250605000000): el
        -- catalogo y las dos configuraciones. El resto no se le evalua.
        if v_pers[j] = 'service_role'
           and v_obj[i] not in ('catalogo_publico','categorias_publicas','pagos_config','contabilidad_config') then
          continue;
        end if;

        if v_obj[i] = 'perfiles' then
          v_sql := 'select count(*), case when count(*) = 1 and bool_and(id = auth.uid()) then ''PROPIA'' '
                || 'else md5(coalesce(string_agg(t::text, ''|'' order by t::text), '''')) end from public.perfiles t';
        elsif v_obj[i] = 'cuentas_cliente' then
          v_sql := 'select count(*), case when count(*) = 1 and bool_and(auth_user_id = auth.uid()) then ''PROPIA'' '
                || 'else md5(coalesce(string_agg(t::text, ''|'' order by t::text), '''')) end from public.cuentas_cliente t';
        else
          v_sql := format(
            'select count(*), md5(coalesce(string_agg(t::text, %L order by t::text), %L)) from public.%I t',
            '|', '', v_obj[i]);
        end if;

        begin
          execute v_sql into v_n, v_h;
          v_obt := case
            when v_h = 'PROPIA'                                  then 'PROPIA'
            when v_n = 0                                         then 'NADA'
            when v_n = v_verdad_n[i] and v_h = v_verdad_h[i]     then 'TODO'
            else 'PARCIAL (' || v_n || ' de ' || v_verdad_n[i] || ')'
          end;
        exception when insufficient_privilege then
          v_obt := 'NADA';
        end;

        -- ---------- Lo ESPERADO por el diseno ----------
        v_esp := case
          -- La tienda: todo el mundo ve las dos listas blancas públicas.
          when v_obj[i] in ('catalogo_publico', 'categorias_publicas') then 'TODO'
          -- service_role (Edge Function de pagos) lee las dos configuraciones.
          when v_pers[j] = 'service_role' then 'TODO'
          -- Cada integrante del personal ve SOLO su perfil. Un cliente Auth no
          -- tiene fila en perfiles y solo ve su propio puente de cuenta.
          when v_obj[i] = 'perfiles' then case when v_pers[j] in ('anon','cliente') then 'NADA' else 'PROPIA' end
          when v_obj[i] = 'cuentas_cliente' then case when v_pers[j] = 'cliente' then 'PROPIA' else 'NADA' end
          when v_pers[j] = 'admin' then 'TODO'
          -- Finanzas
          when v_obj[i] in ('puc_cuentas','asientos','asiento_lineas','asiento_bitacora',
                            'movimientos_mayor','saldos_cuenta','contabilidad_config','pagos_config')
            then case when v_pers[j] = 'finanzas' then 'TODO' else 'NADA' end
          -- Inventario: config solo inventario; libro y stock tambien Marketing
          -- (puente de lectura de la Proyeccion de demanda).
          when v_obj[i] = 'inventario_config'
            then case when v_pers[j] = 'produccion' then 'TODO' else 'NADA' end
          when v_obj[i] in ('movimientos_inventario','stock_actual')
            then case when v_pers[j] in ('produccion','marketing') then 'TODO' else 'NADA' end
          -- productos: Inventario, Marketing y Ventas (selector del pedido).
          when v_obj[i] = 'productos'
            then case when v_pers[j] in ('produccion','marketing','ventas') then 'TODO' else 'NADA' end
          -- Ventas (datos personales de terceros): SOLO Ventas.
          when v_obj[i] in ('clientes','pedidos','pedido_items','pedido_bitacora','portafolio_metricas')
            then case when v_pers[j] = 'ventas' then 'TODO' else 'NADA' end
          -- Campañas: SOLO Marketing.
          when v_obj[i] like 'campana_%'
            then case when v_pers[j] = 'marketing' then 'TODO' else 'NADA' end
          else 'SIN EXPECTATIVA'
        end;

        -- Excepcion documentada: Ventas ve productos (selector del pedido) pero
        -- NO el libro de inventario; stock_actual le muestra la lista de
        -- productos con existencias 0 (sin libro). No filtra datos que no tenga
        -- ya en productos. Se espera PARCIAL hasta el Tramo D3 (roles reales).
        if v_pers[j] = 'ventas' and v_obj[i] = 'stock_actual' then
          v_esp := 'PARCIAL';
        end if;

        r_pers := r_pers || v_pers[j];
        r_obj  := r_obj  || v_obj[i];
        r_esp  := r_esp  || v_esp;
        r_obt  := r_obt  || v_obt;
      end loop;

      execute 'reset role';
    end loop;

    -- ---------- EXECUTE: anon solo puertas públicas nominales ----------
    -- Siempre se permite el máximo seguro (0..20) usado por catalogo_publico.
    -- Cuando SN1 existe se permiten, además, únicamente sus firmas públicas de
    -- búsqueda/recomendación; un overload o cualquier otra función sigue rojo.
    select string_agg(p.proname, ', ' order by p.proname) into v_extra
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
       and has_function_privilege('anon', p.oid, 'execute')
       and p.proname <> 'ventas_max_comprable_campana'
       and (
         to_regclass('public.sn_config') is null
         or (
           p.oid <> coalesce(
             to_regprocedure('public.sn_buscar_v1(text,text,text,integer,integer)')::oid,
             0::oid
           )
           and p.oid <> coalesce(
             to_regprocedure('public.sn_recomendar_v1(text,jsonb,text,integer)')::oid,
             0::oid
           )
         )
       );
    r_pers := r_pers || 'anon'::text;
    r_obj  := r_obj  || 'EXECUTE no permitido sobre funciones de public'::text;
    r_esp  := r_esp  || 'NINGUNA'::text;
    r_obt  := r_obt  || coalesce('PUEDE: ' || v_extra, 'NINGUNA');

    -- ---------- EXECUTE: authenticated exactamente la lista blanca ----------
    select array_agg(distinct p.proname order by p.proname) into v_funcs_auth
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and not exists (select 1 from pg_depend d where d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e')
       and has_function_privilege('authenticated', p.oid, 'execute');
    r_pers := r_pers || 'authenticated'::text;
    r_obj  := r_obj  || 'EXECUTE sobre funciones de public'::text;
    r_esp  := r_esp  || ('LISTA BLANCA (' || array_length(v_lista_blanca, 1) || ')');
    -- Se compara como CONJUNTO (el orden de texto depende de la collation).
    r_obt  := r_obt  || case
      when coalesce(v_funcs_auth, '{}') @> v_lista_blanca
       and v_lista_blanca @> coalesce(v_funcs_auth, '{}') then 'LISTA BLANCA (' || array_length(v_lista_blanca, 1) || ')'
      else 'DISTINTO. Sobran: ' || coalesce((select string_agg(x, ', ') from unnest(v_funcs_auth) x where x <> all (v_lista_blanca)), '-')
        || ' · Faltan: ' || coalesce((select string_agg(x, ', ') from unnest(v_lista_blanca) x where x <> all (coalesce(v_funcs_auth, '{}'))), '-')
    end;

    -- ---------- EXECUTE: service_role solo puertas, nunca helpers internos ----------
    -- Los helpers co__*/pw__*/sn__*, los triggers privados, mantenimientos y
    -- núcleos internos se alcanzan como propietario desde SECURITY DEFINER o
    -- triggers. Las seis RPC administrativas SN son solo-panel; únicamente
    -- sn_buscar_v1/sn_recomendar_v1 son puertas service de SN.
    select string_agg(
             case
               when left(p.proname, 4) in ('co__','pw__')
                 or p.proname like 'sn\_\_%' escape '\'
                 or p.proname in (
                   'sn_campana_detalle_v1','sn_guardar_campana_v1',
                   'sn_registrar_asset_v1','sn_retirar_asset_v1',
                   'sn_configurar_v1','sn_resumen_v1',
                   'sn_purgar_telemetria'
                 )
                 or p.proname in (
                   'crear_pedido_c3_base','crear_pedido_c4',
                   'cm__asignar_slug_automatico','cm__validar_slug_no_reasignado',
                   'cm__registrar_slug_historial',
                   'cm__proteger_clave_producto_categoria',
                   'cm__sincronizar_categoria_principal_legado',
                   'cm__validar_categoria_publicada_legacy',
                   'cm__validar_categorias_seleccion',
                   'cm__validar_principal_puente',
                   'cm_crear_categoria'
                 )
                 or (
                   p.proname like 'promocionar\_p3\_%' escape '\'
                   and p.proname not in (
                     'promocionar_p3_resolver', 'promocionar_p3_contar'
                   )
                 )
                 or p.proname like 'promocionar\_p4\_\_%' escape '\'
                 or p.proname in (
                   'promocionar_p5__agregado',
                   'promocionar_p5_resultados',
                   'promocionar_p5_procedencia_pedidos'
                 )
                 then case
                   when p.proname like 'sn\_\_%' escape '\' then 'SOBRA helper SN privado: '
                   when p.proname = 'sn_purgar_telemetria' then 'SOBRA mantenimiento SN privado: '
                   when p.proname in (
                     'sn_campana_detalle_v1','sn_guardar_campana_v1',
                     'sn_registrar_asset_v1','sn_retirar_asset_v1',
                     'sn_configurar_v1','sn_resumen_v1'
                   ) then 'SOBRA puerta SN solo-panel: '
                   when p.proname = 'promocionar_p5__agregado' then 'SOBRA helper: '
                   when p.proname = 'cm_crear_categoria' then 'SOBRA puerta solo-panel: '
                   when p.proname like 'promocionar\_p5\_%' escape '\' then 'SOBRA puerta P5 no-service: '
                   else 'SOBRA helper: '
                 end
               else 'FALTA puerta: '
             end || p.proname,
             ', ' order by p.proname
           )
      into v_extra
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       -- Helper booleano histórico sin lectura/escritura de datos. Su ownership
       -- varía entre reconstrucciones antiguas; no es una puerta RPC C4.
       and p.proname <> 'pw__contexto_servidor'
       and not exists (
         select 1 from pg_depend d
          where d.classid = 'pg_proc'::regclass
            and d.objid = p.oid
            and d.deptype = 'e'
       )
       and (
         (
           left(p.proname, 4) in ('co__','pw__')
           or p.proname like 'sn\_\_%' escape '\'
           or p.proname in (
             'sn_campana_detalle_v1','sn_guardar_campana_v1',
             'sn_registrar_asset_v1','sn_retirar_asset_v1',
             'sn_configurar_v1','sn_resumen_v1',
             'sn_purgar_telemetria'
           )
           or p.proname in (
             'crear_pedido_c3_base','crear_pedido_c4',
             'cm__asignar_slug_automatico','cm__validar_slug_no_reasignado',
             'cm__registrar_slug_historial',
             'cm__proteger_clave_producto_categoria',
             'cm__sincronizar_categoria_principal_legado',
             'cm__validar_categoria_publicada_legacy',
             'cm__validar_categorias_seleccion',
             'cm__validar_principal_puente',
             'cm_crear_categoria'
           )
           or (
             p.proname like 'promocionar\_p3\_%' escape '\'
             and p.proname not in (
               'promocionar_p3_resolver', 'promocionar_p3_contar'
             )
           )
           or p.proname like 'promocionar\_p4\_\_%' escape '\'
           or p.proname in (
             'promocionar_p5__agregado',
             'promocionar_p5_resultados',
             'promocionar_p5_procedencia_pedidos'
           )
         ) = has_function_privilege('service_role', p.oid, 'execute')
       );
    r_pers := r_pers || 'service_role'::text;
    r_obj  := r_obj  || 'EXECUTE sobre puertas de public, sin helpers internos'::text;
    r_esp  := r_esp  || 'PUERTAS OK'::text;
    r_obt  := r_obt  || coalesce('DESAJUSTE: ' || v_extra, 'PUERTAS OK');

    -- ---------- ACL nominal SN1 ----------
    if to_regclass('public.sn_config') is not null then
      for v_sn in
        select * from (values
          ('sn_campana_detalle_v1', 'public.sn_campana_detalle_v1(uuid)', false, true, false),
          ('sn_guardar_campana_v1', 'public.sn_guardar_campana_v1(uuid,integer,text[],timestamptz,timestamptz,jsonb)', false, true, false),
          ('sn_registrar_asset_v1', 'public.sn_registrar_asset_v1(uuid,text,text,text,integer,integer,numeric,numeric,text)', false, true, false),
          ('sn_retirar_asset_v1', 'public.sn_retirar_asset_v1(uuid)', false, true, false),
          ('sn_configurar_v1', 'public.sn_configurar_v1(boolean,boolean,integer,text)', false, true, false),
          ('sn_buscar_v1', 'public.sn_buscar_v1(text,text,text,integer,integer)', true, true, true),
          ('sn_recomendar_v1', 'public.sn_recomendar_v1(text,jsonb,text,integer)', true, true, true),
          ('sn_resumen_v1', 'public.sn_resumen_v1(date,date)', false, true, false)
        ) as x(nombre, firma, anon_e, authenticated_e, service_e)
      loop
        r_pers := r_pers || 'roles API'::text;
        r_obj := r_obj || ('ACL SN1 ' || v_sn.nombre);
        r_esp := r_esp || format(
          'anon=%s · authenticated=%s · service_role=%s',
          case when v_sn.anon_e then 'SI' else 'NO' end,
          case when v_sn.authenticated_e then 'SI' else 'NO' end,
          case when v_sn.service_e then 'SI' else 'NO' end
        );
        r_obt := r_obt || format(
          'anon=%s · authenticated=%s · service_role=%s',
          case when has_function_privilege('anon', to_regprocedure(v_sn.firma), 'execute') then 'SI' else 'NO' end,
          case when has_function_privilege('authenticated', to_regprocedure(v_sn.firma), 'execute') then 'SI' else 'NO' end,
          case when has_function_privilege('service_role', to_regprocedure(v_sn.firma), 'execute') then 'SI' else 'NO' end
        );
      end loop;

      r_pers := r_pers || 'roles API/postgres'::text;
      r_obj := r_obj || 'ACL helpers SN1 y sn_purgar_telemetria'::text;
      r_esp := r_esp || 'helpers API=NO · purga API=NO · purga postgres=SI'::text;
      r_obt := r_obt || case
        when not exists (
          select 1
            from pg_proc p
            join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public'
             and p.proname like 'sn\_\_%' escape '\'
             and (
               has_function_privilege('anon', p.oid, 'execute')
               or has_function_privilege('authenticated', p.oid, 'execute')
               or has_function_privilege('service_role', p.oid, 'execute')
             )
        )
         and not coalesce(has_function_privilege(
           'anon', to_regprocedure('public.sn_purgar_telemetria()'), 'execute'
         ), false)
         and not coalesce(has_function_privilege(
           'authenticated', to_regprocedure('public.sn_purgar_telemetria()'), 'execute'
         ), false)
         and not coalesce(has_function_privilege(
           'service_role', to_regprocedure('public.sn_purgar_telemetria()'), 'execute'
         ), false)
         and coalesce(has_function_privilege(
           'postgres', to_regprocedure('public.sn_purgar_telemetria()'), 'execute'
         ), false)
          then 'helpers API=NO · purga API=NO · purga postgres=SI'
        else 'DESAJUSTE'
      end;
    end if;

    -- ---------- ACL nominal P5: tres puertas públicas y helper privado ----------
    if to_regprocedure('public.promocionar_p5_resultados(uuid,date,date)') is not null then
      for v_p5 in
        select * from (values
          ('promocionar_p5__agregado', 'public.promocionar_p5__agregado(date,date,uuid)', false, false, false),
          ('promocionar_p5_resultados', 'public.promocionar_p5_resultados(uuid,date,date)', false, true, false),
          ('promocionar_p5_resumen_metricas', 'public.promocionar_p5_resumen_metricas(date,date)', false, true, true),
          ('promocionar_p5_procedencia_pedidos', 'public.promocionar_p5_procedencia_pedidos(uuid[])', false, true, false)
        ) as x(nombre, firma, anon_e, authenticated_e, service_e)
      loop
        r_pers := r_pers || 'roles API'::text;
        r_obj := r_obj || ('ACL P5 ' || v_p5.nombre);
        r_esp := r_esp || format(
          'anon=%s · authenticated=%s · service_role=%s',
          case when v_p5.anon_e then 'SI' else 'NO' end,
          case when v_p5.authenticated_e then 'SI' else 'NO' end,
          case when v_p5.service_e then 'SI' else 'NO' end
        );
        r_obt := r_obt || format(
          'anon=%s · authenticated=%s · service_role=%s',
          case when has_function_privilege('anon', to_regprocedure(v_p5.firma), 'execute') then 'SI' else 'NO' end,
          case when has_function_privilege('authenticated', to_regprocedure(v_p5.firma), 'execute') then 'SI' else 'NO' end,
          case when has_function_privilege('service_role', to_regprocedure(v_p5.firma), 'execute') then 'SI' else 'NO' end
        );
      end loop;
    end if;

    -- ---------- ACL nominal de categorías planas ----------
    if to_regclass('public.categorias_publicas') is not null then
      r_pers := r_pers || 'roles API'::text;
      r_obj := r_obj || 'ACL categorias_publicas: solo SELECT'::text;
      r_esp := r_esp || 'anon/authenticated/service_role=SELECT; PUBLIC=NADA'::text;
      r_obt := r_obt || (case
        when has_table_privilege('anon', 'public.categorias_publicas', 'select')
         and has_table_privilege('authenticated', 'public.categorias_publicas', 'select')
         and has_table_privilege('service_role', 'public.categorias_publicas', 'select')
         and not exists (
           select 1
             from pg_class c
             cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
             left join pg_roles rol on rol.oid = acl.grantee
            where c.oid = 'public.categorias_publicas'::regclass
              and (acl.grantee = 0 or rol.rolname in ('anon', 'authenticated', 'service_role'))
              and (acl.grantee = 0 or acl.privilege_type <> 'SELECT')
         )
          then 'anon/authenticated/service_role=SELECT; PUBLIC=NADA'
        else 'DESAJUSTE'
      end)::text;

      r_pers := r_pers || 'roles API'::text;
      r_obj := r_obj || 'ACL campana_producto_categoria'::text;
      r_esp := r_esp || 'authenticated=SELECT+RLS; anon/service_role/PUBLIC=NADA'::text;
      r_obt := r_obt || (case
        when has_table_privilege('authenticated', 'public.campana_producto_categoria', 'select')
         and (select c.relrowsecurity from pg_class c where c.oid = 'public.campana_producto_categoria'::regclass)
         and not exists (
           select 1
             from pg_class c
             cross join lateral aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl
             left join pg_roles rol on rol.oid = acl.grantee
            where c.oid = 'public.campana_producto_categoria'::regclass
              and (
                acl.grantee = 0
                or rol.rolname in ('anon', 'service_role')
                or (rol.rolname = 'authenticated' and acl.privilege_type <> 'SELECT')
              )
         )
          then 'authenticated=SELECT+RLS; anon/service_role/PUBLIC=NADA'
        else 'DESAJUSTE'
      end)::text;

      r_pers := r_pers || 'roles API'::text;
      r_obj := r_obj || 'ACL cm_crear_categoria'::text;
      r_esp := r_esp || 'anon=NO · authenticated=SI · service_role=NO'::text;
      r_obt := r_obt || format(
        'anon=%s · authenticated=%s · service_role=%s',
        case when has_function_privilege('anon', 'public.cm_crear_categoria(text,text,text)', 'execute') then 'SI' else 'NO' end,
        case when has_function_privilege('authenticated', 'public.cm_crear_categoria(text,text,text)', 'execute') then 'SI' else 'NO' end,
        case when has_function_privilege('service_role', 'public.cm_crear_categoria(text,text,text)', 'execute') then 'SI' else 'NO' end
      );
    end if;

    -- La puerta de alta tiene EXECUTE para authenticated, pero una cuenta de
    -- cliente sin perfil interno debe ser rechazada por la guardia Marketing.
    if to_regprocedure('public.cm_crear_categoria(text,text,text)') is not null then
      execute 'set local role authenticated';
      perform set_config('request.jwt.claims', json_build_object('sub', c_cli, 'role', 'authenticated')::text, true);
      begin
        perform 1
          from cm_crear_categoria('Categoría indebida', 'No debe crearse.', 'hogar')
         limit 1;
        v_obt := 'PERMITIDO';
      exception when others then
        v_obt := case when sqlerrm like 'Acceso denegado%' then 'RECHAZADO' else 'ERROR: ' || sqlerrm end;
      end;
      execute 'reset role';
      r_pers := r_pers || 'cliente'::text;
      r_obj  := r_obj || 'llamar cm_crear_categoria sin Marketing'::text;
      r_esp  := r_esp || 'RECHAZADO'::text;
      r_obt  := r_obt || v_obt;
    end if;

    -- ---------- Comportamiento: el candado de las RPC sigue vivo ----------
    -- Una cuenta de cliente es authenticated, pero no tiene perfil ni modulo.
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', c_cli, 'role', 'authenticated')::text, true);
    begin
      perform crear_pedido(p_nombre => 'x', p_items => '[]'::jsonb);
      v_obt := 'PERMITIDO';
    exception when others then
      v_obt := case when sqlerrm like 'Acceso denegado%' then 'RECHAZADO' else 'ERROR: ' || sqlerrm end;
    end;
    execute 'reset role';
    r_pers := r_pers || 'cliente'::text;
    r_obj  := r_obj  || 'llamar crear_pedido interno'::text;
    r_esp  := r_esp  || 'RECHAZADO'::text;
    r_obt  := r_obt  || v_obt;

    -- Un autenticado SIN modulo que llama crear_pedido debe ser rechazado por
    -- el guardia interno (no por permisos de EXECUTE: crear_pedido si esta en
    -- la lista blanca).
    execute 'set local role authenticated';
    perform set_config('request.jwt.claims', json_build_object('sub', c_sin, 'role', 'authenticated')::text, true);
    begin
      perform crear_pedido(p_nombre => 'x', p_items => '[]'::jsonb);
      v_obt := 'PERMITIDO';
    exception when others then
      v_obt := case when sqlerrm like 'Acceso denegado%' then 'RECHAZADO' else 'ERROR: ' || sqlerrm end;
    end;
    execute 'reset role';
    r_pers := r_pers || 'sin_modulo'::text;
    r_obj  := r_obj  || 'llamar crear_pedido'::text;
    r_esp  := r_esp  || 'RECHAZADO'::text;
    r_obt  := r_obt  || v_obt;

    -- La tienda (anon) no puede llamar RPC internas.
    execute 'set local role anon';
    perform set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
    begin
      perform tiene_modulo('finanzas');
      v_obt := 'PERMITIDO';
    exception when insufficient_privilege then
      v_obt := 'RECHAZADO';
    end;
    execute 'reset role';
    r_pers := r_pers || 'anon'::text;
    r_obj  := r_obj  || 'llamar tiene_modulo'::text;
    r_esp  := r_esp  || 'RECHAZADO'::text;
    r_obt  := r_obt  || v_obt;

    -- La Edge Function (service_role) sigue pudiendo leer la config publica de pagos.
    execute 'set local role service_role';
    begin
      perform * from pagos_config_para_intencion();
      v_obt := 'PERMITIDO';
    exception when insufficient_privilege then
      v_obt := 'RECHAZADO';
    end;
    execute 'reset role';
    r_pers := r_pers || 'service_role'::text;
    r_obj  := r_obj  || 'llamar pagos_config_para_intencion (Edge Function)'::text;
    r_esp  := r_esp  || 'PERMITIDO'::text;
    r_obt  := r_obt  || v_obt;

    -- Deshacer TODO lo escrito arriba (personas, perfiles, asiento, pedido, stock).
    raise exception using errcode = 'P0T00', message = 'deshacer datos de prueba';
  exception when sqlstate 'P0T00' then
    null;  -- los datos de prueba ya se deshicieron; los resultados siguen en memoria
  end;

  for i in 1 .. coalesce(array_length(r_pers, 1), 0) loop
    insert into tramo0_resultado values (
      i, r_pers[i], r_obj[i], r_esp[i], r_obt[i],
      case when r_obt[i] = r_esp[i] or (r_esp[i] = 'PARCIAL' and r_obt[i] like 'PARCIAL%')
           then 'pasa' else 'FALLA' end);
  end loop;
end;
$$;

-- Informe: primero el RESUMEN, luego las FALLAS (si hay) y despues el resto.
select persona, objeto, esperado, obtenido, veredicto
from (
  select 0 as grupo, 0 as orden, 'RESUMEN' as persona,
         count(*) || ' comprobaciones' as objeto,
         '' as esperado,
         count(*) filter (where veredicto = 'FALLA') || ' fallan' as obtenido,
         case when count(*) filter (where veredicto = 'FALLA') = 0 then 'TODO PASA' else 'HAY FALLAS' end as veredicto
    from tramo0_resultado
  union all
  select case when veredicto = 'FALLA' then 1 else 2 end, orden,
         persona, objeto, esperado, obtenido, veredicto
    from tramo0_resultado
) informe
order by grupo, orden;
