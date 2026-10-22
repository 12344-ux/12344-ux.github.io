-- MAGANDHI · Categorías de temporada CT1 · postflight de solo lectura
select jsonb_pretty(jsonb_build_object(
  'fecha_colombia', (statement_timestamp() at time zone 'America/Bogota')::date,
  'navidad', (
    select jsonb_build_object(
      'codigo', c.codigo,
      'tipo', c.tipo,
      'visible_desde', c.visible_desde,
      'visible_hasta', c.visible_hasta,
      'fijada_primera', c.fijada_primera,
      'activo', c.activo,
      'visible_tienda', c.visible_tienda,
      'estado', public.cm__categoria_estado(
        c.activo, c.visible_tienda, c.tipo, c.visible_desde, c.visible_hasta
      ),
      'publica_ahora', exists (
        select 1 from public.categorias_publicas p where p.codigo = c.codigo
      ),
      'orden_publico', (
        select p.orden from public.categorias_publicas p where p.codigo = c.codigo
      ),
      'asociaciones_secundarias', (
        select count(*) from public.campana_producto_categoria pcc
         where pcc.categoria_codigo = c.codigo and not pcc.es_principal
      )
    )
    from public.campana_categoria c where c.codigo = 'navidad'
  ),
  'temporales_principales', (
    select count(*) from public.campana_producto_categoria pcc
    join public.campana_categoria c on c.codigo = pcc.categoria_codigo
    where pcc.es_principal and c.tipo = 'temporada'
  ),
  'categorias_publicas_ordenadas', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'codigo', p.codigo, 'nombre', p.nombre, 'orden', p.orden
    ) order by p.orden, p.codigo), '[]'::jsonb)
    from public.categorias_publicas p
  ),
  'acl', jsonb_build_object(
    'anon_lista_admin', has_function_privilege(
      'anon', 'public.cm_listar_categorias_admin_v1()', 'execute'
    ),
    'authenticated_lista_admin', has_function_privilege(
      'authenticated', 'public.cm_listar_categorias_admin_v1()', 'execute'
    ),
    'service_lista_admin', has_function_privilege(
      'service_role', 'public.cm_listar_categorias_admin_v1()', 'execute'
    ),
    'anon_guardar', has_function_privilege(
      'anon',
      'public.cm_guardar_categoria_v1(text,text,text,text,integer,text,date,date,boolean,boolean,boolean,text)',
      'execute'
    ),
    'authenticated_guardar', has_function_privilege(
      'authenticated',
      'public.cm_guardar_categoria_v1(text,text,text,text,integer,text,date,date,boolean,boolean,boolean,text)',
      'execute'
    ),
    'service_guardar', has_function_privilege(
      'service_role',
      'public.cm_guardar_categoria_v1(text,text,text,text,integer,text,date,date,boolean,boolean,boolean,text)',
      'execute'
    )
  )
));

-- Esperado al aplicar durante la ventana 22-oct-2026..7-ene-2027:
-- navidad.estado=vigente, publica_ahora=true, orden_publico=-2000000,
-- temporales_principales=0;
-- ACL: anon/service false y authenticated true para ambas RPC administrativas.
