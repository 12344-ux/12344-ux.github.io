-- ============================================================================
-- MAGANDHI · SISTEMA NERVIOSO SN1 · CIERRE
-- Correcciones forward de búsqueda, recomendación y telemetría.
-- ----------------------------------------------------------------------------
-- Se aplica después de 20261112000000_sistema_nervioso_sn1.sql.
-- No cambia firmas públicas ni reescribe la migración base ya publicada.
-- ============================================================================

begin;
set local search_path = public, pg_catalog;
set local statement_timeout = '120s';
set local lock_timeout = '5s';

select pg_advisory_xact_lock(hashtextextended('magandhi-sistema-nervioso-sn1-v1', 0));

do $preflight$
begin
  if to_regclass('public.catalogo_publico') is null
     or to_regclass('public.sn_config') is null
     or to_regclass('public.sn_producto_config') is null
     or to_regclass('public.sn_producto_relacion') is null
     or to_regclass('public.sn_assets_publicos_v1') is null
     or to_regclass('public.em_config') is null
     or to_regclass('public.tienda_eventos') is null
     or to_regclass('public.tienda_eventos_limite') is null
     or to_regprocedure('public.sn__normalizar_texto(text)') is null
     or to_regprocedure('public.sn__contiene_pii(text)') is null
     or to_regprocedure('public.sn_purgar_telemetria()') is null
     or to_regprocedure('public.sn_buscar_v1(text,text,text,integer,integer)') is null
     or to_regprocedure('public.sn_recomendar_v1(text,jsonb,text,integer)') is null
     or to_regprocedure('public.mt_registrar_eventos(text,text,jsonb,text)') is null then
    raise exception using
      errcode = 'P0001',
      message = 'SN1_CIERRE_REQUIERE_MIGRACION_20261112000000';
  end if;

  if (
    select count(*)
      from information_schema.columns c
     where c.table_schema = 'public'
       and (
         (c.table_name = 'catalogo_publico'
          and c.column_name in ('ficha_tecnica', 'categoria_nombre', 'categoria_codigos'))
         or
         (c.table_name = 'em_config'
          and c.column_name in ('id', 'analitica_activa', 'politica_publicada', 'politica_version'))
       )
  ) <> 7 then
    raise exception using
      errcode = 'P0001',
      message = 'SN1_CIERRE_CONTRATO_DE_COLUMNAS_INVALIDO';
  end if;

  if (
    select count(*)
      from pg_roles r
     where r.rolname in ('anon', 'authenticated', 'service_role')
  ) <> 3 then
    raise exception using
      errcode = 'P0001',
      message = 'SN1_CIERRE_REQUIERE_ROLES_API';
  end if;

  if exists (
    select 1
      from (values
        ('public.sn_buscar_v1(text,text,text,integer,integer)'::regprocedure),
        ('public.sn_recomendar_v1(text,jsonb,text,integer)'::regprocedure),
        ('public.mt_registrar_eventos(text,text,jsonb,text)'::regprocedure)
      ) as f(oid)
      join pg_proc p on p.oid = f.oid
     where p.prorettype <> 'jsonb'::regtype
        or not p.prosecdef
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'SN1_CIERRE_FIRMAS_BASE_INVALIDAS';
  end if;
end;
$preflight$;

-- Proyección textual estricta de la ficha pública. No serializa el JSON ni
-- incorpora nombres estructurales o propiedades ajenas a clave/valor.
create or replace function public.sn__ficha_tecnica_texto_publico(p_ficha jsonb)
returns text
language sql
immutable
security definer
set search_path = pg_catalog
as $fn$
  select nullif(
    string_agg(valor.texto, ' ' order by elemento.orden, valor.posicion),
    ''
  )
    from jsonb_array_elements(
      case
        when jsonb_typeof(p_ficha) = 'array' then p_ficha
        else '[]'::jsonb
      end
    ) with ordinality as elemento(item, orden)
    cross join lateral (
      values
        (1, case
          when jsonb_typeof(elemento.item) = 'object'
           and jsonb_typeof(elemento.item -> 'clave') = 'string'
          then nullif(btrim(elemento.item ->> 'clave'), '')
        end),
        (2, case
          when jsonb_typeof(elemento.item) = 'object'
           and jsonb_typeof(elemento.item -> 'valor') = 'string'
          then nullif(btrim(elemento.item ->> 'valor'), '')
        end)
    ) as valor(posicion, texto)
   where valor.texto is not null;
$fn$;

comment on function public.sn__ficha_tecnica_texto_publico(jsonb) is
  'SN1 · helper privado de indexación. Proyecta en orden únicamente los strings visibles de clave y valor de la ficha técnica pública; tolera null, raíces no array y elementos mal formados, e ignora propiedades adicionales sin serializar nombres estructurales.';

revoke all on function public.sn__ficha_tecnica_texto_publico(jsonb)
  from public, anon, authenticated, service_role;

-- Búsqueda pública completa, recreada sin serialización de objetos JSON.
create or replace function public.sn_buscar_v1(
  p_consulta text default null,
  p_categoria text default null,
  p_semilla text default null,
  p_limite integer default 24,
  p_desde integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_cfg public.sn_config%rowtype;
  v_cruda text := btrim(coalesce(p_consulta, ''));
  v_consulta text;
  v_categoria text := nullif(lower(btrim(coalesce(p_categoria, ''))), '');
  v_semilla text := nullif(btrim(coalesce(p_semilla, '')), '');
  v_limite integer := coalesce(p_limite, 24);
  v_desde integer := coalesce(p_desde, 0);
  v_modo text;
  v_uid uuid := auth.uid();
  v_customer_id uuid;
  v_personaliza boolean := false;
begin
  select * into v_cfg from public.sn_config c where c.id = 1;
  if not found or not v_cfg.activo then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_APAGADO',
      'modelo_version', coalesce(v_cfg.modelo_version, 'sn1-reglas-1'),
      'modo', 'apagado', 'consulta', null, 'total', 0, 'productos', '[]'::jsonb
    );
  end if;

  if length(v_cruda) > 120 then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_CONSULTA_MUY_LARGA',
      'modelo_version', v_cfg.modelo_version,
      'modo', 'rechazada', 'consulta', null, 'total', 0, 'productos', '[]'::jsonb
    );
  end if;
  if public.sn__contiene_pii(v_cruda) then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_CONSULTA_SENSIBLE',
      'modelo_version', v_cfg.modelo_version,
      'modo', 'rechazada', 'consulta', null, 'total', 0, 'productos', '[]'::jsonb
    );
  end if;

  v_consulta := public.sn__normalizar_texto(v_cruda);
  if v_categoria is not null
     and (length(v_categoria) > 64 or v_categoria !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$') then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_CATEGORIA_INVALIDA',
      'modelo_version', v_cfg.modelo_version,
      'modo', 'rechazada', 'consulta', v_consulta,
      'total', 0, 'productos', '[]'::jsonb
    );
  end if;
  if v_semilla is not null
     and (length(v_semilla) > 80 or v_semilla !~ '^[A-Za-z0-9_-]+$') then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_SEMILLA_INVALIDA',
      'modelo_version', v_cfg.modelo_version,
      'modo', 'rechazada', 'consulta', v_consulta,
      'total', 0, 'productos', '[]'::jsonb
    );
  end if;
  if v_limite not between 1 and 60 or v_desde not between 0 and 10000 then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_PAGINACION_INVALIDA',
      'modelo_version', v_cfg.modelo_version,
      'modo', 'rechazada', 'consulta', v_consulta,
      'total', 0, 'productos', '[]'::jsonb
    );
  end if;

  v_modo := case
    when v_consulta is not null then 'busqueda'
    when v_categoria is not null then 'categoria'
    else 'exploracion'
  end;
  v_semilla := coalesce(
    v_semilla,
    concat_ws('|', v_modo, coalesce(v_consulta, ''), coalesce(v_categoria, ''),
                    (statement_timestamp() at time zone 'America/Bogota')::date::text)
  );

  if v_cfg.personalizacion_cuenta and v_uid is not null then
    select cc.customer_id into v_customer_id
      from public.cuentas_cliente cc
     where cc.auth_user_id = v_uid and cc.estado = 'activa';
    v_personaliza := found and v_customer_id is not null;
  end if;

  return (
    with ventas_popularidad_lineas as (
      select coalesce(pi.campana_id, mapa.campana_id) as campana_id,
             pi.cantidad
        from public.pedidos p
        join public.pedido_items pi on pi.pedido_id = p.id
        left join lateral (
          select cp2.id as campana_id
            from public.campana_producto cp2
           where pi.campana_id is null
             and cp2.product_id_ref = pi.product_id
           order by cp2.publicado desc, cp2.activo desc,
                    cp2.creado desc nulls last, cp2.id
           limit 1
        ) mapa on pi.campana_id is null
       where not p.anulado
         and p.estado <> 'anulado'
         and p.fecha_orden between
             (statement_timestamp() at time zone 'America/Bogota')::date - 364
             and (statement_timestamp() at time zone 'America/Bogota')::date
    ),
    ventas as (
      select vl.campana_id, sum(vl.cantidad)::bigint as unidades
        from ventas_popularidad_lineas vl
       where vl.campana_id is not null
       group by vl.campana_id
    ),
    compras_cuenta_lineas as (
      select coalesce(pi.campana_id, mapa.campana_id) as campana_id
        from public.pedidos p
        join public.pedido_items pi on pi.pedido_id = p.id
        left join lateral (
          select cp2.id as campana_id
            from public.campana_producto cp2
           where pi.campana_id is null
             and cp2.product_id_ref = pi.product_id
           order by cp2.publicado desc, cp2.activo desc,
                    cp2.creado desc nulls last, cp2.id
           limit 1
        ) mapa on pi.campana_id is null
       where v_personaliza
         and v_customer_id is not null
         and p.customer_id = v_customer_id
         and not p.anulado
         and p.estado <> 'anulado'
    ),
    mis_campanas as (
      select distinct vl.campana_id
        from compras_cuenta_lineas vl
       where vl.campana_id is not null
    ),
    perfil as (
      select
        array(
          select distinct x.codigo from (
            select pcc.categoria_codigo as codigo
              from mis_campanas mc
              join public.campana_producto_categoria pcc
                on pcc.campana_producto_id = mc.campana_id
            union
            select cp2.categoria_codigo
              from mis_campanas mc
              join public.campana_producto cp2 on cp2.id = mc.campana_id
             where cp2.categoria_codigo is not null
          ) x where x.codigo is not null
        )::text[] as categorias
    ),
    elegibles as (
      select
        c.*,
        cp.creado,
        coalesce(pc.prioridad, 0) as prioridad,
        coalesce(v.unidades, 0) as popularidad,
        coalesce(r.promedio, 0) as rating_promedio,
        coalesce(r.total, 0) as rating_total,
        public.sn__normalizar_texto(c.nombre) as nombre_n,
        -- Documento observable: solo columnas de catalogo_publico. Ninguna
        -- etiqueta, intención ni hook interno puede incluir u ordenar resultados.
        public.sn__normalizar_texto(concat_ws(' ',
          c.nombre, c.slug,
          c.categoria_nombre, array_to_string(c.categoria_codigos, ' '),
          c.detalle_presentacion, c.caracteristica_adicional, c.hook_largo,
          c.por_que_magandhi, c.sobre_este_producto, public.sn__ficha_tecnica_texto_publico(c.ficha_tecnica)
        )) as documento_n,
        public.sn__normalizar_texto(concat_ws(' ',
          c.categoria_nombre, array_to_string(c.categoria_codigos, ' ')
        )) as categorias_n
      from public.catalogo_publico c
      join public.sn_config gate
        on gate.id = 1 and gate.activo
      join public.campana_producto cp
        on cp.id = c.id
       and cp.publicado
       and cp.activo
       and not cp.es_placeholder
      left join public.sn_producto_config pc on pc.campana_producto_id = c.id
      left join ventas v on v.campana_id = c.id
      left join public.producto_rating_publico r on r.slug = c.slug
      where c.agotado = false
        and c.max_comprable > 0
        and (pc.disponible_desde is null
             or pc.disponible_desde at time zone 'America/Bogota'
                <= statement_timestamp() at time zone 'America/Bogota')
        and (pc.disponible_hasta is null
             or pc.disponible_hasta at time zone 'America/Bogota'
                > statement_timestamp() at time zone 'America/Bogota')
        and (v_categoria is null or v_categoria = any(c.categoria_codigos))
    ),
    puntuados as (
      select e.*,
        case when v_consulta is null then 0 else
          case
            when e.nombre_n = v_consulta then 100000
            when e.nombre_n like v_consulta || '%' then 80000
            when position(v_consulta in e.nombre_n) > 0 then 60000
            else 0
          end
          + case when position(v_consulta in e.categorias_n) > 0 then 20000 else 0 end
          + coalesce((
              select sum(
                case when position(t.token in e.nombre_n) > 0 then 5000 else 0 end
                + case when position(t.token in e.categorias_n) > 0 then 2500 else 0 end
                + case when position(t.token in e.documento_n) > 0 then 1000 else 0 end
              )::integer
                from regexp_split_to_table(v_consulta, ' +') as t(token)
            ), 0)
        end as relevancia_textual,
        case when v_personaliza then
          case when e.categoria_codigos && perfil.categorias then 2 else 0 end
        else 0 end as afinidad_cuenta
      from elegibles e
      cross join perfil
    ),
    filtrados as (
      select * from puntuados p
       where v_consulta is null or p.relevancia_textual > 0
    ),
    ordenados as (
      select f.*,
             row_number() over (
               order by f.relevancia_textual desc,
                        f.afinidad_cuenta desc,
                        f.prioridad desc,
                        f.popularidad desc,
                        f.rating_promedio desc,
                        f.rating_total desc,
                        f.creado desc nulls last,
                        md5(v_semilla || '|' || f.id::text)
             ) as posicion
        from filtrados f
    ),
    pagina as (
      select * from ordenados
       order by posicion
       offset v_desde limit v_limite
    )
    select jsonb_build_object(
      'ok', true,
      'modelo_version', v_cfg.modelo_version,
      'modo', v_modo,
      'consulta', coalesce(v_consulta, ''),
      'total', (select count(*) from filtrados),
      'productos', coalesce((
        select jsonb_agg(x.producto order by x.posicion)
          from (
            select p.posicion,
              jsonb_build_object(
                'id', p.id,
                'nombre', p.nombre,
                'slug', p.slug,
                'categoria_codigo', p.categoria_codigo,
                'categoria_nombre', p.categoria_nombre,
                'categoria_codigos', p.categoria_codigos,
                'detalle_presentacion', p.detalle_presentacion,
                'precio_venta', p.precio_venta,
                'imagen_banner_path', p.imagen_banner_path,
                'imagenes', p.imagenes,
                'sello_elegido', p.sello_elegido,
                'aviso_urgencia_activo', p.aviso_urgencia_activo,
                'aviso_urgencia_cantidad', p.aviso_urgencia_cantidad,
                'max_comprable', p.max_comprable,
                'asset', case when a.asset_id is null then null else jsonb_build_object(
                  'rol', a.rol, 'path', a.path, 'ancho', a.ancho, 'alto', a.alto,
                  'foco_x', a.foco_x, 'foco_y', a.foco_y, 'alt', a.alt
                ) end,
                'razon', case
                  when v_consulta is not null and position(v_consulta in p.nombre_n) > 0
                    then 'coincidencia_nombre'
                  when v_consulta is not null and position(v_consulta in p.categorias_n) > 0
                    then 'coincidencia_categoria'
                  when v_consulta is not null then 'coincidencia_contenido'
                  when p.afinidad_cuenta > 0 then 'afinidad_cuenta'
                  when p.popularidad > 0 then 'popular'
                  when p.creado >= statement_timestamp() - interval '45 days' then 'novedad'
                  else 'exploracion'
                end
              ) as producto
            from pagina p
            left join lateral (
              select av.*
                from public.sn_assets_publicos_v1 av
               where av.campana_id = p.id
               order by array_position(
                 array['cuadrado','horizontal','vertical','recorte','panoramico']::text[],
                 av.rol
               ), av.version desc
               limit 1
            ) a on true
          ) x
      ), '[]'::jsonb)
    )
  );
end;
$fn$;

comment on function public.sn_buscar_v1(text, text, text, integer, integer) is
  'SN1 · búsqueda pública sobre valores observables. Categorías no se serializan como JSON y ficha_tecnica aporta únicamente los strings visibles clave/valor mediante helper privado; p_semilla conserva paginación y desempate deterministas.';

-- Recomendación completa, con semilla compuesta siempre por el servidor.
create or replace function public.sn_recomendar_v1(
  p_superficie text,
  p_contexto jsonb default '{}'::jsonb,
  p_semilla text default null,
  p_limite integer default 12
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_cfg public.sn_config%rowtype;
  v_superficie text := lower(btrim(coalesce(p_superficie, '')));
  v_contexto jsonb := coalesce(p_contexto, '{}'::jsonb);
  v_entropia text := nullif(btrim(coalesce(p_semilla, '')), '');
  v_semilla text;
  v_limite integer := coalesce(p_limite, 12);
  v_modulos integer;
  v_request_id uuid := gen_random_uuid();
  v_uid uuid := auth.uid();
  v_customer_id uuid;
  v_es_cuenta boolean := false;
  v_personaliza boolean := false;
  v_slug text;
  v_categoria text;
  v_consulta_cruda text;
  v_consulta text;
  v_contexto_id uuid;
  v_excluir text[] := '{}'::text[];
  v_item jsonb;
  v_excluir_slug text;
begin
  select * into v_cfg from public.sn_config c where c.id = 1;
  if not found or not v_cfg.activo then
    return jsonb_build_object(
      'ok', false,
      'codigo', 'SN_APAGADO',
      'request_id', v_request_id,
      'modelo_version', coalesce(v_cfg.modelo_version, 'sn1-reglas-1'),
      'modo', 'contextual',
      'superficie', v_superficie,
      'modulos', '[]'::jsonb
    );
  end if;

  if v_superficie not in (
    'home_principal','home_descubrimiento','categoria',
    'producto_final','carrito','busqueda'
  ) then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_SUPERFICIE_INVALIDA',
      'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
      'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
    );
  end if;
  if v_limite not between 1 and 36 then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_LIMITE_INVALIDO',
      'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
      'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
    );
  end if;
  if v_entropia is not null
     and (length(v_entropia) > 80 or v_entropia !~ '^[A-Za-z0-9_-]+$') then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_SEMILLA_INVALIDA',
      'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
      'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
    );
  end if;
  if jsonb_typeof(v_contexto) <> 'object' then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
      'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
      'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
    );
  end if;
  if exists (
       select 1 from jsonb_object_keys(v_contexto) as k(clave)
        where k.clave not in ('slug','categoria','consulta','excluir')
     ) then
    return jsonb_build_object(
      'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
      'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
      'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
    );
  end if;

  if v_contexto ? 'slug' then
    if jsonb_typeof(v_contexto->'slug') <> 'string' then
      return jsonb_build_object(
        'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
        'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
        'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
      );
    end if;
    v_slug := lower(btrim(v_contexto->>'slug'));
    if length(v_slug) not between 1 and 180
       or v_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
      return jsonb_build_object(
        'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
        'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
        'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
      );
    end if;
  end if;

  if v_contexto ? 'categoria' then
    if jsonb_typeof(v_contexto->'categoria') <> 'string' then
      return jsonb_build_object(
        'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
        'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
        'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
      );
    end if;
    v_categoria := lower(btrim(v_contexto->>'categoria'));
    if length(v_categoria) not between 1 and 64
       or v_categoria !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' then
      return jsonb_build_object(
        'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
        'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
        'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
      );
    end if;
  end if;

  if v_contexto ? 'consulta' then
    if jsonb_typeof(v_contexto->'consulta') <> 'string' then
      return jsonb_build_object(
        'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
        'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
        'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
      );
    end if;
    v_consulta_cruda := btrim(v_contexto->>'consulta');
    if length(v_consulta_cruda) > 120
       or public.sn__contiene_pii(v_consulta_cruda) then
      return jsonb_build_object(
        'ok', false, 'codigo', 'SN_CONTEXTO_SENSIBLE',
        'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
        'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
      );
    end if;
    v_consulta := public.sn__normalizar_texto(v_consulta_cruda);
  end if;

  if v_contexto ? 'excluir' then
    if jsonb_typeof(v_contexto->'excluir') <> 'array' then
      return jsonb_build_object(
        'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
        'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
        'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
      );
    end if;
    if jsonb_array_length(v_contexto->'excluir') > 100 then
      return jsonb_build_object(
        'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
        'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
        'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
      );
    end if;
    for v_item in select value from jsonb_array_elements(v_contexto->'excluir') as e(value)
    loop
      if jsonb_typeof(v_item) <> 'string' then
        return jsonb_build_object(
          'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
          'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
          'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
        );
      end if;
      v_excluir_slug := lower(btrim(v_item #>> '{}'));
      if length(v_excluir_slug) not between 1 and 180
         or v_excluir_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
         or v_excluir_slug = any(v_excluir) then
        return jsonb_build_object(
          'ok', false, 'codigo', 'SN_CONTEXTO_INVALIDO',
          'request_id', v_request_id, 'modelo_version', v_cfg.modelo_version,
          'modo', 'contextual', 'superficie', v_superficie, 'modulos', '[]'::jsonb
        );
      end if;
      v_excluir := array_append(v_excluir, v_excluir_slug);
    end loop;
  end if;

  -- Una campaña contextual se resuelve únicamente dentro de la frontera
  -- pública disponible; un slug retirado no se convierte en señal interna.
  if v_slug is not null then
    select c.id into v_contexto_id
      from public.catalogo_publico c
      join public.sn_config gate
        on gate.id = 1 and gate.activo
      join public.campana_producto cp
        on cp.id = c.id and cp.publicado and cp.activo and not cp.es_placeholder
      left join public.sn_producto_config pc on pc.campana_producto_id = c.id
     where c.slug = v_slug
       and c.agotado = false
       and c.max_comprable > 0
       and (pc.disponible_desde is null
            or pc.disponible_desde at time zone 'America/Bogota'
               <= statement_timestamp() at time zone 'America/Bogota')
       and (pc.disponible_hasta is null
            or pc.disponible_hasta at time zone 'America/Bogota'
               > statement_timestamp() at time zone 'America/Bogota')
     limit 1;
  end if;

  if v_cfg.personalizacion_cuenta and v_uid is not null then
    select true, cc.customer_id into v_es_cuenta, v_customer_id
      from public.cuentas_cliente cc
     where cc.auth_user_id = v_uid and cc.estado = 'activa';
    v_es_cuenta := coalesce(v_es_cuenta, false);
  end if;
  v_personaliza := v_cfg.personalizacion_cuenta and v_es_cuenta;
  v_modulos := case when v_limite <= 4 then 1 when v_limite <= 8 then 2 else 3 end;

  -- p_semilla aporta entropía, pero nunca reemplaza el contexto autoritativo.
  -- La identidad solo entra cuando esta llamada personaliza para una cuenta.
  v_semilla := concat_ws(
    '|',
    'sn-recomendar-v1',
    'entropia=' || coalesce(v_entropia, ''),
    'superficie=' || v_superficie,
    'slug=' || coalesce(v_slug, ''),
    'categoria=' || coalesce(v_categoria, ''),
    'consulta=' || coalesce(v_consulta, ''),
    'fecha_bogota=' || (statement_timestamp() at time zone 'America/Bogota')::date::text,
    case when v_personaliza then 'identidad=' || v_uid::text end
  );

  return (
    with ventas_popularidad_lineas as (
      select coalesce(pi.campana_id, mapa.campana_id) as campana_id,
             pi.cantidad
        from public.pedidos p
        join public.pedido_items pi on pi.pedido_id = p.id
        left join lateral (
          select cp2.id as campana_id
            from public.campana_producto cp2
           where pi.campana_id is null
             and cp2.product_id_ref = pi.product_id
           order by cp2.publicado desc, cp2.activo desc,
                    cp2.creado desc nulls last, cp2.id
           limit 1
        ) mapa on pi.campana_id is null
       where not p.anulado
         and p.estado <> 'anulado'
         and p.fecha_orden between
             (statement_timestamp() at time zone 'America/Bogota')::date - 364
             and (statement_timestamp() at time zone 'America/Bogota')::date
    ),
    popularidad as (
      select vl.campana_id, sum(vl.cantidad)::bigint as unidades
        from ventas_popularidad_lineas vl
       where vl.campana_id is not null
       group by vl.campana_id
    ),
    compras_cuenta as (
      select distinct coalesce(pi.campana_id, mapa.campana_id) as campana_id
        from public.pedidos p
        join public.pedido_items pi on pi.pedido_id = p.id
        left join lateral (
          select cp2.id as campana_id
            from public.campana_producto cp2
           where pi.campana_id is null
             and cp2.product_id_ref = pi.product_id
           order by cp2.publicado desc, cp2.activo desc,
                    cp2.creado desc nulls last, cp2.id
           limit 1
        ) mapa on pi.campana_id is null
       where v_personaliza
         and v_customer_id is not null
         and p.customer_id = v_customer_id
         and not p.anulado
         and p.estado <> 'anulado'
    ),
    fuentes_cuenta as (
      select vl.campana_id
        from compras_cuenta vl
       where vl.campana_id is not null
      union
      select ci.campana_id
        from public.carritos ca
        join public.carrito_items ci on ci.carrito_id = ca.id
       where v_personaliza
         and ca.auth_user_id = v_uid
         and ca.estado = 'activa'
    ),
    carrito_actual as (
      select ci.campana_id
        from public.carritos ca
        join public.carrito_items ci on ci.carrito_id = ca.id
       where v_personaliza
         and ca.auth_user_id = v_uid
         and ca.estado = 'activa'
    ),
    fuentes_relacion as (
      select v_contexto_id as campana_id where v_contexto_id is not null
      union
      select ca.campana_id from carrito_actual ca
       where v_superficie = 'carrito'
    ),
    perfil_contexto as (
      select
        array(
          select distinct codigo from (
            select pcc.categoria_codigo as codigo
              from public.campana_producto_categoria pcc
             where pcc.campana_producto_id = v_contexto_id
            union
            select cp2.categoria_codigo
              from public.campana_producto cp2
             where cp2.id = v_contexto_id and cp2.categoria_codigo is not null
          ) x where codigo is not null
        )::text[] as categorias,
        array(
          select distinct pe.etiqueta_codigo
            from public.campana_producto_etiqueta pe
            join public.campana_etiqueta et
              on et.codigo = pe.etiqueta_codigo and et.activo
           where pe.campana_producto_id = v_contexto_id
        )::text[] as etiquetas
    ),
    perfil_cuenta as (
      select
        array(
          select distinct codigo from (
            select pcc.categoria_codigo as codigo
              from fuentes_cuenta fc
              join public.campana_producto_categoria pcc
                on pcc.campana_producto_id = fc.campana_id
            union
            select cp2.categoria_codigo
              from fuentes_cuenta fc
              join public.campana_producto cp2 on cp2.id = fc.campana_id
             where cp2.categoria_codigo is not null
          ) x where codigo is not null
        )::text[] as categorias,
        array(
          select distinct pe.etiqueta_codigo
            from fuentes_cuenta fc
            join public.campana_producto_etiqueta pe
              on pe.campana_producto_id = fc.campana_id
            join public.campana_etiqueta et
              on et.codigo = pe.etiqueta_codigo and et.activo
        )::text[] as etiquetas
    ),
    elegibles as (
      select
        c.*,
        cp.creado,
        coalesce(pc.prioridad, 0) as prioridad,
        coalesce(pop.unidades, 0) as popularidad,
        coalesce(rt.promedio, 0) as rating_promedio,
        coalesce(rt.total, 0) as rating_total,
        coalesce(tags.codigos, '{}'::text[]) as etiquetas_codigos,
        -- La consulta contextual usa el mismo documento público de búsqueda.
        -- Las etiquetas internas quedan solo como afinidad no textual.
        public.sn__normalizar_texto(concat_ws(' ',
          c.nombre, c.slug,
          c.categoria_nombre, array_to_string(c.categoria_codigos, ' '),
          c.detalle_presentacion, c.caracteristica_adicional, c.hook_largo,
          c.por_que_magandhi, c.sobre_este_producto, public.sn__ficha_tecnica_texto_publico(c.ficha_tecnica)
        )) as documento_n
      from public.catalogo_publico c
      join public.sn_config gate
        on gate.id = 1 and gate.activo
      join public.campana_producto cp
        on cp.id = c.id
       and cp.publicado
       and cp.activo
       and not cp.es_placeholder
      left join public.sn_producto_config pc on pc.campana_producto_id = c.id
      left join popularidad pop on pop.campana_id = c.id
      left join public.producto_rating_publico rt on rt.slug = c.slug
      left join lateral (
        select array_agg(pe.etiqueta_codigo order by pe.etiqueta_codigo) as codigos
          from public.campana_producto_etiqueta pe
          join public.campana_etiqueta et
            on et.codigo = pe.etiqueta_codigo and et.activo
         where pe.campana_producto_id = c.id
      ) tags on true
      where c.agotado = false
        and c.max_comprable > 0
        and (pc.disponible_desde is null
             or pc.disponible_desde at time zone 'America/Bogota'
                <= statement_timestamp() at time zone 'America/Bogota')
        and (pc.disponible_hasta is null
             or pc.disponible_hasta at time zone 'America/Bogota'
                > statement_timestamp() at time zone 'America/Bogota')
        and not (c.slug = any(v_excluir))
        and (v_slug is null or c.slug <> v_slug)
        and not (
          v_superficie = 'carrito'
          and exists (select 1 from carrito_actual ca where ca.campana_id = c.id)
        )
        and not exists (
          select 1
            from public.sn_producto_relacion rx
            join fuentes_relacion fr on fr.campana_id = rx.campana_origen_id
           where rx.campana_destino_id = c.id
             and rx.activo
             and rx.tipo = 'excluir'
        )
    ),

    senales as (
      select e.*,
        rel.tipo as relacion_tipo,
        coalesce(rel.peso, 0) as relacion_peso,
        case when v_consulta is null then 0 else
          case when position(v_consulta in e.documento_n) > 0 then 5000 else 0 end
          + coalesce((
              select sum(
                case when position(t.token in e.documento_n) > 0 then 1000 else 0 end
              )::integer
                from regexp_split_to_table(v_consulta, ' +') as t(token)
            ), 0)
        end as relevancia_textual,
        (case when v_categoria is not null and v_categoria = any(e.categoria_codigos) then 3 else 0 end)
          + (case when e.categoria_codigos && pcx.categorias then 2 else 0 end)
          + (case when e.etiquetas_codigos && pcx.etiquetas then 1 else 0 end)
          as afinidad_contexto,
        case when v_personaliza then
          (case when e.categoria_codigos && pcu.categorias then 2 else 0 end)
          + (case when e.etiquetas_codigos && pcu.etiquetas then 1 else 0 end)
        else 0 end as afinidad_cuenta,
        (mod((hashtextextended(v_semilla || '|' || e.id::text, 0) & 2147483647), 100)
          < v_cfg.exploracion_pct) as explora
      from elegibles e
      cross join perfil_contexto pcx
      cross join perfil_cuenta pcu
      left join lateral (
        select r.tipo, r.peso
          from public.sn_producto_relacion r
          join fuentes_relacion fr on fr.campana_id = r.campana_origen_id
         where r.campana_destino_id = e.id
           and r.activo
           and r.tipo <> 'excluir'
         order by r.peso desc,
                  array_position(
                    array['complementa','continua','rutina','sustituye','descubrimiento']::text[],
                    r.tipo
                  ),
                  r.id
         limit 1
      ) rel on true
    ),
    puntuados as (
      select s.*,
        (s.relevancia_textual::bigint * 10000)
        + case when s.relacion_peso > 0
            then 100000 + (s.relacion_peso::bigint * 1000)
            else 0
          end
        + (s.afinidad_contexto::bigint * 500)
        + (s.afinidad_cuenta::bigint * 350)
        + ((s.prioridad + 20)::bigint * 25)
        + least(s.popularidad, 500)
        + (s.rating_promedio * 20)::bigint
        + least(s.rating_total, 100)::bigint
        + case when s.creado >= statement_timestamp() - interval '45 days' then 80 else 0 end
        + case when s.explora then greatest(0::bigint, 120 - least(s.popularidad, 120)) else 0 end
        as puntuacion,
        case
          when s.relevancia_textual > 0 then 'coincidencia_busqueda'
          when s.relacion_tipo = 'complementa' then 'complemento'
          when s.relacion_tipo = 'sustituye' then 'alternativa'
          when s.relacion_tipo = 'continua' then 'continuacion'
          when s.relacion_tipo = 'rutina' then 'rutina'
          when s.relacion_tipo = 'descubrimiento' then 'descubrimiento'
          when s.afinidad_cuenta > 0 then 'afinidad_cuenta'
          when s.afinidad_contexto > 0 then 'misma_categoria'
          when s.popularidad > 0 or s.rating_total > 0 then 'popular'
          when s.creado >= statement_timestamp() - interval '45 days' then 'novedad'
          when s.explora then 'exploracion'
          else 'descubrimiento'
        end as razon
      from senales s
    ),
    diversidad as (
      select p.*,
             row_number() over (
               partition by coalesce(p.categoria_codigo, p.id::text)
               order by p.puntuacion desc, md5(v_semilla || '|categoria|' || p.id::text)
             ) as turno_categoria
        from puntuados p
    ),
    ordenados as (
      select d.*,
             row_number() over (
               order by d.turno_categoria,
                        d.puntuacion desc,
                        md5(v_semilla || '|final|' || d.id::text)
             ) as posicion
        from diversidad d
    ),
    seleccionados as (
      select * from ordenados order by posicion limit v_limite
    ),
    layouts as (
      select
        l.*,
        case
          when l.titulo = 'Elegidos para ti'
               and v_personaliza
               and l.superficie = 'home_principal'
               and l.orden = 1 then 'Elegidos para ti'
          when l.titulo = 'Elegidos para ti' then 'Una selección para descubrir'
          when l.titulo in (
            'Una selección para descubrir',
            'También puede gustarte', 'Más por descubrir',
            'Descubre algo nuevo', 'Dos buenas ideas', 'Sigue explorando',
            'Destacados de la categoría', 'Más opciones', 'También explora',
            'Completa tu elección', 'Puede ir bien contigo', 'Otra idea',
            'Antes de terminar', 'También podrías llevar', 'Últimos descubrimientos',
            'Resultados destacados', 'Más resultados', 'También descubre'
          ) then l.titulo
          else case l.superficie
            when 'home_principal' then 'Una selección para descubrir'
            when 'home_descubrimiento' then 'Descubre algo nuevo'
            when 'categoria' then 'Destacados de la categoría'
            when 'producto_final' then 'Completa tu elección'
            when 'carrito' then 'Antes de terminar'
            when 'busqueda' then 'Resultados destacados'
          end
        end as titulo_salida
        from public.sn_layout l
       where l.superficie = v_superficie and l.activo
       order by l.peso desc, l.orden
       limit v_modulos
    )
    select jsonb_build_object(
      'ok', true,
      'request_id', v_request_id,
      'modelo_version', v_cfg.modelo_version,
      'modo', case when v_personaliza then 'personalizado' else 'contextual' end,
      'superficie', v_superficie,
      'modulos', coalesce((
        select jsonb_agg(
          jsonb_build_object(
            'id', l.codigo,
            'tipo', l.tipo,
            'titulo', l.titulo_salida,
            'subtitulo', l.subtitulo,
            'productos', coalesce((
              select jsonb_agg(x.producto order by x.posicion)
                from (
                  select s.posicion,
                    jsonb_build_object(
                      'id', s.id,
                      'nombre', s.nombre,
                      'slug', s.slug,
                      'categoria_codigo', s.categoria_codigo,
                      'categoria_nombre', s.categoria_nombre,
                      'categoria_codigos', s.categoria_codigos,
                      'detalle_presentacion', s.detalle_presentacion,
                      'precio_venta', s.precio_venta,
                      'imagen_banner_path', s.imagen_banner_path,
                      'imagenes', s.imagenes,
                      'sello_elegido', s.sello_elegido,
                      'aviso_urgencia_activo', s.aviso_urgencia_activo,
                      'aviso_urgencia_cantidad', s.aviso_urgencia_cantidad,
                      'max_comprable', s.max_comprable,
                      'asset', case when a.asset_id is null then null else jsonb_build_object(
                        'rol', a.rol, 'path', a.path, 'ancho', a.ancho, 'alto', a.alto,
                        'foco_x', a.foco_x, 'foco_y', a.foco_y, 'alt', a.alt
                      ) end,
                      'razon', s.razon
                    ) as producto
                  from seleccionados s
                  left join lateral (
                    select av.*
                      from public.sn_assets_publicos_v1 av
                     where av.campana_id = s.id
                       and av.rol = any(l.roles_requeridos)
                     order by array_position(l.roles_requeridos, av.rol), av.version desc
                     limit 1
                  ) a on true
                 where ((s.posicion - 1) % v_modulos) + 1 = l.orden
                ) x
            ), '[]'::jsonb)
          ) order by l.orden
        ) from layouts l
      ), '[]'::jsonb)
    )
  );
end;
$fn$;

comment on function public.sn_recomendar_v1(text, jsonb, text, integer) is
  'SN1 · recomendación pública. p_semilla es entropía adicional y siempre se compone con superficie, slug, categoría, consulta y fecha Bogotá; la identidad solo participa al personalizar. El texto usa la misma proyección pública estricta que búsqueda.';

-- Ingesta completa, con validación opcional de la versión inyectada por Edge.
create or replace function public.mt_registrar_eventos(
  p_visitante text,
  p_sesion text,
  p_eventos jsonb,
  p_ip_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  e jsonb;
  v_ok integer := 0;
  v_desc integer := 0;
  v_n integer;
  v_hora timestamptz := date_trunc('hour', statement_timestamp());
  v_cuando timestamptz;
  v_politica_version text;
begin
  select ec.politica_version
    into v_politica_version
    from public.em_config ec
   where ec.id
     and ec.analitica_activa
     and ec.politica_publicada
   for share;
  if not found then
    raise exception 'MT_ANALITICA_APAGADA';
  end if;
  if p_visitante is null or p_visitante !~ '^[A-Za-z0-9_-]{16,40}$'
     or p_sesion is null or p_sesion !~ '^[A-Za-z0-9_-]{8,40}$' then
    raise exception 'MT_VISITANTE_INVALIDO';
  end if;
  if p_eventos is null or jsonb_typeof(p_eventos) <> 'array'
     or jsonb_array_length(p_eventos) = 0
     or jsonb_array_length(p_eventos) > 30 then
    raise exception 'MT_EVENTOS_INVALIDOS';
  end if;

  -- Compatibilidad: los llamadores service_role históricos pueden omitir esta
  -- metadata. Cuando la Edge versionada la inyecta, todos los eventos del lote
  -- deben coincidir con la política vigente dentro de esta misma transacción;
  -- así un cambio entre el precheck HTTP y el INSERT falla cerrado.
  if exists (
       select 1
         from jsonb_array_elements(p_eventos) as j(evento)
        where j.evento ? 'politica_version'
     ) and exists (
       select 1
         from jsonb_array_elements(p_eventos) as j(evento)
        where j.evento->>'politica_version' is distinct from v_politica_version
     ) then
    raise exception 'MT_CONSENTIMIENTO_DESACTUALIZADO';
  end if;

  if p_ip_hash is not null then
    insert into public.tienda_eventos_limite (ip_hash, hora, n)
    values (left(p_ip_hash, 64), v_hora, jsonb_array_length(p_eventos))
    on conflict (ip_hash, hora) do update
      set n = public.tienda_eventos_limite.n + excluded.n
    returning n into v_n;
    if v_n > 600 then
      raise exception 'MT_DEMASIADOS_EVENTOS';
    end if;
  end if;

  for e in select value from jsonb_array_elements(p_eventos) as j(value)
  loop
    begin
      v_cuando := coalesce(public.em__ts(e->>'cuando'), now());
      if v_cuando > now()
         or v_cuando < now() - interval '10 minutes' then
        v_cuando := now();
      end if;

      -- Un clic solo cuenta si esta misma sesión ya registró la impresión del
      -- mismo elemento de respuesta. La fuente sigue siendo cliente y, por
      -- tanto, esto limita incoherencias pero no prueba una interacción real.
      if e->>'tipo' = 'recomendacion_click'
         and not exists (
           select 1
             from public.tienda_eventos te
            where te.tipo = 'recomendacion_impresion'
              and te.visitante = p_visitante
              and te.sesion = p_sesion
              and te.request_id = nullif(e->>'request_id', '')::uuid
              and te.slot = nullif(e->>'slot', '')
              and te.posicion = nullif(e->>'posicion', '')::integer
              and te.slug = nullif(e->>'slug', '')
              and te.superficie = nullif(e->>'superficie', '')
              and te.layout_codigo = nullif(e->>'layout_codigo', '')
              and te.modelo_version = nullif(e->>'modelo_version', '')
              and te.razon = nullif(e->>'razon', '')
         ) then
        v_desc := v_desc + 1;
        continue;
      end if;

      insert into public.tienda_eventos (
        visitante, sesion, tipo, ruta, slug, origen, entrada,
        utm_campaign, dispositivo, cuando,
        request_id, superficie, slot, posicion, layout_codigo,
        modelo_version, razon, cantidad_resultados, consulta_hash
      ) values (
        p_visitante,
        p_sesion,
        e->>'tipo',
        case when e->>'tipo' in (
          'pagina_vista','producto_visto','clic_comprar',
          'checkout_iniciado','compra','llegada_campana'
        ) then nullif(left(e->>'ruta', 120), '') end,
        case when e->>'tipo' in (
          'pagina_vista','producto_visto','clic_comprar','checkout_iniciado',
          'compra','llegada_campana','recomendacion_impresion','recomendacion_click'
        ) then nullif(e->>'slug', '') end,
        case when e->>'tipo' in (
          'pagina_vista','producto_visto','clic_comprar',
          'checkout_iniciado','compra','llegada_campana'
        ) then nullif(e->>'origen', '') end,
        case when e->>'tipo' in (
          'pagina_vista','producto_visto','clic_comprar',
          'checkout_iniciado','compra','llegada_campana'
        ) then coalesce((e->>'entrada')::boolean, false) else false end,
        case when e->>'tipo' in (
          'pagina_vista','producto_visto','clic_comprar',
          'checkout_iniciado','compra','llegada_campana'
        ) then nullif(e->>'utm_campaign', '') end,
        case when e->>'tipo' in (
          'pagina_vista','producto_visto','clic_comprar',
          'checkout_iniciado','compra','llegada_campana'
        ) then nullif(e->>'dispositivo', '') end,
        v_cuando,
        case when e->>'tipo' in (
          'recomendacion_impresion','recomendacion_click','busqueda_resultados'
        ) then nullif(e->>'request_id', '')::uuid end,
        case when e->>'tipo' in (
          'recomendacion_impresion','recomendacion_click','busqueda_resultados'
        ) then nullif(e->>'superficie', '') end,
        case when e->>'tipo' in (
          'recomendacion_impresion','recomendacion_click'
        ) then nullif(e->>'slot', '') end,
        case when e->>'tipo' in (
          'recomendacion_impresion','recomendacion_click'
        ) then nullif(e->>'posicion', '')::integer end,
        case when e->>'tipo' in (
          'recomendacion_impresion','recomendacion_click'
        ) then nullif(e->>'layout_codigo', '') end,
        case when e->>'tipo' in (
          'recomendacion_impresion','recomendacion_click','busqueda_resultados'
        ) then nullif(e->>'modelo_version', '') end,
        case when e->>'tipo' in (
          'recomendacion_impresion','recomendacion_click'
        ) then nullif(e->>'razon', '') end,
        case when e->>'tipo' = 'busqueda_resultados'
          then nullif(e->>'cantidad_resultados', '')::integer end,
        case when e->>'tipo' = 'busqueda_resultados'
          then nullif(e->>'consulta_hash', '') end
      );
      v_ok := v_ok + 1;
    exception
      when check_violation
        or unique_violation
        or invalid_text_representation
        or numeric_value_out_of_range then
      v_desc := v_desc + 1;
    end;
  end loop;

  -- Respaldo best-effort si el trabajo operativo deja de correr. La garantía
  -- de retención depende del mantenimiento programado y medido fuera de aquí.
  if random() < 0.01 then
    perform public.sn_purgar_telemetria();
  end if;
  return jsonb_build_object('aceptados', v_ok, 'descartados', v_desc);
end;
$fn$;

comment on function public.mt_registrar_eventos(text, text, jsonb, text) is
  'M1 + SN1 · conserva firma y seis eventos históricos. Admite tres eventos SN consentidos, aproximados y rate-limited con lista blanca; deduplica retries y descarta clic sin impresión correlacionada, pero la fuente cliente no es autoritativa. La Edge inyecta politica_version en cada lote y la RPC exige coincidencia transaccional si esa metadata está presente, sin romper llamadores service_role históricos que la omiten. consulta_hash solo HMAC hexadecimal y nunca consulta cruda. Analítica activa + política, 30/lote, 600/h por hash temporal, retención operativa 13 meses con purga probabilística de respaldo. Solo service_role.';

-- Reafirma la ACL nominal después de reemplazar las implementaciones.
revoke all on function public.sn_buscar_v1(text, text, text, integer, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.sn_recomendar_v1(text, jsonb, text, integer)
  from public, anon, authenticated, service_role;
revoke all on function public.mt_registrar_eventos(text, text, jsonb, text)
  from public, anon, authenticated, service_role;

-- El helper queda privado; las dos puertas SN conservan los tres roles públicos
-- nominales y la ingesta continúa reservada exclusivamente a service_role.
grant execute on function public.sn_buscar_v1(text, text, text, integer, integer)
  to anon, authenticated, service_role;
grant execute on function public.sn_recomendar_v1(text, jsonb, text, integer)
  to anon, authenticated, service_role;
grant execute on function public.mt_registrar_eventos(text, text, jsonb, text)
  to service_role;

do $postflight$
declare
  v_acl record;
begin
  if not (
    select p.prosecdef
       and p.provolatile = 'i'
       and p.prorettype = 'text'::regtype
       and coalesce(array_to_string(p.proconfig, ','), '') = 'search_path=pg_catalog'
      from pg_proc p
     where p.oid = 'public.sn__ficha_tecnica_texto_publico(jsonb)'::regprocedure
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'SN1_CIERRE_HELPER_INVALIDO';
  end if;

  if exists (
    select 1
      from (values
        ('public.sn_buscar_v1(text,text,text,integer,integer)'::regprocedure),
        ('public.sn_recomendar_v1(text,jsonb,text,integer)'::regprocedure),
        ('public.mt_registrar_eventos(text,text,jsonb,text)'::regprocedure)
      ) as f(oid)
      join pg_proc p on p.oid = f.oid
     where p.prorettype <> 'jsonb'::regtype
        or not p.prosecdef
        or coalesce(array_to_string(p.proconfig, ','), '') <> 'search_path=public, pg_catalog'
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'SN1_CIERRE_RPCS_INVALIDAS';
  end if;

  for v_acl in
    select * from (values
      ('public.sn__ficha_tecnica_texto_publico(jsonb)', false, false, false),
      ('public.sn_buscar_v1(text,text,text,integer,integer)', true, true, true),
      ('public.sn_recomendar_v1(text,jsonb,text,integer)', true, true, true),
      ('public.mt_registrar_eventos(text,text,jsonb,text)', false, false, true)
    ) as x(firma, anon_e, authenticated_e, service_e)
  loop
    if to_regprocedure(v_acl.firma) is null
       or has_function_privilege(
            'anon', to_regprocedure(v_acl.firma), 'execute'
          ) is distinct from v_acl.anon_e
       or has_function_privilege(
            'authenticated', to_regprocedure(v_acl.firma), 'execute'
          ) is distinct from v_acl.authenticated_e
       or has_function_privilege(
            'service_role', to_regprocedure(v_acl.firma), 'execute'
          ) is distinct from v_acl.service_e then
      raise exception using
        errcode = 'P0001',
        message = 'SN1_CIERRE_ACL_NOMINAL_INVALIDA';
    end if;
  end loop;
end;
$postflight$;

commit;
