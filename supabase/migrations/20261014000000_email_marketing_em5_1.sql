-- ============================================================
-- MAGANDHI · Email marketing · TRAMO EM5.1 (la respuesta a email ALIMENTA
-- el analisis)
-- ------------------------------------------------------------
-- EM5 guarda que paso con cada correo. Este tramo convierte esos eventos en
-- VARIABLES utiles, para que:
--   * el Analisis de clúster (Marketing Project) pueda agrupar tambien por
--     como responde cada cliente a los correos, y
--   * los Segmentos puedan elegir por esa respuesta ("hizo clic en la campana
--     X", "recibio X y no hizo clic", "lleva 4 campanas sin hacer clic"...).
-- Diseno en docs/PLANO-EMAIL-MARKETING.md §4.3 (grupo "Respuesta a email").
--
-- REGLAS:
--   * Solo CLICS y compras atribuidas. Las aperturas NO entran: son
--     aproximadas (Apple Mail abre solo) y decidir con ellas seria decidir con
--     un dato que miente.
--   * Quien nunca recibio una campana NO tiene el dato (NULL), no "0 clics":
--     no es lo mismo no responder que no haber recibido nada. El clúster lo
--     muestra como cobertura.
--   * mk_perfiles_clientes sigue SIN datos de contacto (cliente_ref interno).
--
-- QUE CREA / CAMBIA:
--   em__perfil_email()         -> interno: una fila por contacto con su
--                                 respuesta a campanas.
--   em__segmento_where(jsonb)  -> misma lista blanca de EM2 + 9 campos nuevos.
--   em__segmento_contactos()   -> ahora une tambien em__perfil_email (alias e).
--   em_segmento_opciones()     -> + lista de campanas enviadas.
--   mk_perfiles_clientes()     -> + 5 columnas email_* (se recrea: cambia el
--                                 tipo de retorno; misma firma de entrada).
--
-- Forward e idempotente. REQUISITO: despues de 20261013000000.
-- ============================================================

-- ------------------------------------------------------------
-- (A) Respuesta a campanas por contacto (interno, sin grant)
-- ------------------------------------------------------------
create or replace function em__perfil_email()
returns table (
  contacto_id                uuid,
  customer_id                uuid,
  campanas_recibidas         integer,
  campanas_con_clic          integer,
  pct_campanas_clic          numeric,
  clics_90d                  integer,
  dias_desde_ultimo_clic     integer,
  campanas_seguidas_sin_clic integer,
  compras_atribuidas         integer,
  valor_atribuido            bigint,
  campanas_recibidas_ids     uuid[],
  campanas_clicadas_ids      uuid[]
)
language sql
stable
security definer
set search_path = public
as $$
with rec as (
  -- Campanas que de verdad salieron hacia el contacto.
  select d.contacto_id, c.id as campana_id, coalesce(c.enviada_en, c.programada_para) as salio
    from em_campana_destinatarios d
    join em_campanas c on c.id = d.campana_id
   where d.estado = 'listo' and c.resend_broadcast_id is not null
     and coalesce(c.enviada_en, c.programada_para) <= now()
),
clk as (
  select e.contacto_id, e.campana_id, e.cuando
    from em_eventos e
   where e.tipo = 'clic' and e.contacto_id is not null and e.campana_id is not null
),
por_rec as (
  select r.contacto_id,
         count(*)::int as recibidas,
         count(*) filter (where exists (select 1 from clk where clk.contacto_id = r.contacto_id and clk.campana_id = r.campana_id))::int as con_clic,
         array_agg(r.campana_id order by r.salio) as ids_rec
    from rec r group by r.contacto_id
),
por_clk as (
  select contacto_id,
         count(*) filter (where cuando >= now() - interval '90 days')::int as clics_90d,
         max(cuando) as ultimo_clic,
         array_agg(distinct campana_id) as ids_clk
    from clk group by contacto_id
),
seguidas as (
  -- Campanas recibidas DESPUES de la ultima campana en la que hizo clic.
  select r.contacto_id, count(*)::int as n
    from rec r
    left join lateral (
      select max(r2.salio) as salio_ult
        from rec r2
       where r2.contacto_id = r.contacto_id
         and exists (select 1 from clk where clk.contacto_id = r2.contacto_id and clk.campana_id = r2.campana_id)
    ) u on true
   where u.salio_ult is null or r.salio > u.salio_ult
   group by r.contacto_id
),
atrib as (
  -- Exactas (utm de una campana) + aproximadas (ultimo clic + 7 dias), por cliente.
  select p.customer_id, count(*)::int as n, sum(p.total)::bigint as valor
    from pedidos p
   where not p.anulado
     and (p.utm_campaign in (select utm_campaign from em_campanas)
          or p.id in (select pedido_id from em__atribucion_aproximada()))
   group by p.customer_id
)
select ct.id, ct.customer_id,
       pr.recibidas,
       pr.con_clic,
       round(100.0 * pr.con_clic / pr.recibidas, 1),
       coalesce(pc.clics_90d, 0),
       case when pc.ultimo_clic is not null then (current_date - (pc.ultimo_clic at time zone 'America/Bogota')::date)::int end,
       coalesce(sg.n, 0),
       coalesce(a.n, 0),
       coalesce(a.valor, 0),
       pr.ids_rec,
       coalesce(pc.ids_clk, '{}')
  from em_contactos ct
  join por_rec pr on pr.contacto_id = ct.id          -- solo quien recibio algo
  left join por_clk pc on pc.contacto_id = ct.id
  left join seguidas sg on sg.contacto_id = ct.id
  left join atrib a on a.customer_id = ct.customer_id;
$$;

comment on function em__perfil_email() is 'EM5.1 · NUCLEO INTERNO (sin grant): respuesta de cada contacto a las campanas enviadas (recibidas, con clic, clics 90 dias, dias desde el ultimo clic, campanas seguidas sin clic, compras atribuidas exactas + aproximadas). Sin aperturas (aproximadas). Solo contactos que recibieron al menos una campana.';

revoke execute on function em__perfil_email() from public, anon, authenticated;

-- ------------------------------------------------------------
-- (B) Traductor de reglas: la lista blanca de EM2 + "Respuesta a email".
-- Fila evaluada: alias c (em_contactos) + p (em__perfil_base, null si no
-- compra) + e (em__perfil_email, null si nunca recibio una campana).
-- ------------------------------------------------------------
create or replace function em__segmento_where(p_def jsonb)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_modo   text := coalesce(p_def->>'modo', 'y');
  v_reglas jsonb := coalesce(p_def->'reglas', '[]'::jsonb);
  r        jsonb;
  v_campo  text;
  v_op     text;
  v_val    text;
  v_expr   text;
  v_tipo   text;
  v_partes text[] := '{}';
  v_a      text;
  v_b      text;
  v_ops    constant jsonb := '{"eq":"=","ne":"<>","gt":">","gte":">=","lt":"<","lte":"<="}';
begin
  if v_modo not in ('y','o') then raise exception 'EM_REGLA_INVALIDA: modo'; end if;
  if jsonb_typeof(v_reglas) <> 'array' then raise exception 'EM_REGLA_INVALIDA: reglas'; end if;
  if jsonb_array_length(v_reglas) > 12 then raise exception 'EM_REGLA_INVALIDA: maximo 12 reglas'; end if;

  for r in select * from jsonb_array_elements(v_reglas) loop
    v_campo := r->>'campo';
    v_op    := r->>'op';
    v_val   := btrim(coalesce(r->>'valor', ''));

    -- Lista blanca: campo -> (tipo, expresion)
    select t.tipo, t.expr into v_tipo, v_expr from (values
      ('num_pedidos','num','coalesce(p.num_pedidos,0)'),
      ('unidades','num','coalesce(p.unidades,0)'),
      ('gasto_total','num','coalesce(p.gasto_total,0)'),
      ('ticket_promedio','num','p.ticket_promedio'),
      ('dias_desde_ultima_compra','num','p.dias_desde_ultima_compra'),
      ('dias_entre_compras','num','p.dias_entre_compras'),
      ('precio_min','num','p.precio_min'),
      ('precio_max','num','p.precio_max'),
      ('precio_prom','num','p.precio_prom'),
      ('pct_rebajado','num','p.pct_rebajado'),
      ('productos_distintos','num','coalesce(p.productos_distintos,0)'),
      ('num_opiniones','num','coalesce(p.num_opiniones,0)'),
      ('estrellas_prom','num','p.estrellas_prom'),
      ('pct_opinadas','num','p.pct_opinadas'),
      ('dias_en_lista','num','(current_date - c.creado::date)'),
      ('ciudad','txt','p.ciudad'),
      ('departamento','txt','p.departamento'),
      ('categoria_dominante','txt','p.categoria_dominante'),
      ('franja_moda','txt','p.franja_moda'),
      ('dia_moda','txt','p.dia_moda'),
      ('fuente','txt','c.fuente'),
      ('es_cliente','bool','(p.customer_id is not null)'),
      ('es_local','bool','coalesce(p.es_local,false)'),
      ('compro_producto','arr_uuid','coalesce(p.productos_comprados,''{}''::uuid[])'),
      ('compro_categoria','arr_txt','coalesce(p.categorias_compradas,''{}''::text[])'),
      ('tema','arr_txt','c.temas'),
      -- EM5.1 · Respuesta a email (alias e = em__perfil_email). Sin aperturas:
      -- son aproximadas y segmentar con ellas seria decidir con un dato que miente.
      ('campanas_recibidas','num','coalesce(e.campanas_recibidas,0)'),
      ('campanas_con_clic','num','coalesce(e.campanas_con_clic,0)'),
      ('pct_campanas_clic','num','e.pct_campanas_clic'),
      ('clics_90d','num','coalesce(e.clics_90d,0)'),
      ('dias_desde_ultimo_clic','num','e.dias_desde_ultimo_clic'),
      ('campanas_seguidas_sin_clic','num','coalesce(e.campanas_seguidas_sin_clic,0)'),
      ('compras_por_email','num','coalesce(e.compras_atribuidas,0)'),
      ('recibio_campana','arr_uuid','coalesce(e.campanas_recibidas_ids,''{}''::uuid[])'),
      ('clico_campana','arr_uuid','coalesce(e.campanas_clicadas_ids,''{}''::uuid[])')
    ) as t(campo, tipo, expr) where t.campo = v_campo;

    if v_tipo is null then raise exception 'EM_REGLA_INVALIDA: campo %', coalesce(v_campo, '?'); end if;

    if v_tipo = 'num' then
      if v_op = 'entre' then
        v_a := split_part(v_val, ',', 1); v_b := split_part(v_val, ',', 2);
        if v_a !~ '^-?\d+(\.\d+)?$' or v_b !~ '^-?\d+(\.\d+)?$' then raise exception 'EM_REGLA_INVALIDA: valor %', v_campo; end if;
        v_partes := v_partes || format('(%s between %L::numeric and %L::numeric)', v_expr, least(v_a::numeric, v_b::numeric), greatest(v_a::numeric, v_b::numeric));
      elsif v_op = 'tiene' then
        v_partes := v_partes || format('(%s is not null)', v_expr);
      elsif v_op = 'no_tiene' then
        v_partes := v_partes || format('(%s is null)', v_expr);
      elsif v_ops ? v_op then
        if v_val !~ '^-?\d+(\.\d+)?$' then raise exception 'EM_REGLA_INVALIDA: valor %', v_campo; end if;
        v_partes := v_partes || format('(%s %s %L::numeric)', v_expr, v_ops->>v_op, v_val);
      else raise exception 'EM_REGLA_INVALIDA: operador %', v_op; end if;

    elsif v_tipo = 'txt' then
      if v_op in ('eq','ne','contiene') and v_val = '' then raise exception 'EM_REGLA_INVALIDA: valor %', v_campo; end if;
      if v_op = 'eq' then v_partes := v_partes || format('(lower(%s) = lower(%L))', v_expr, v_val);
      elsif v_op = 'ne' then v_partes := v_partes || format('(lower(coalesce(%s,'''')) <> lower(%L))', v_expr, v_val);
      elsif v_op = 'contiene' then v_partes := v_partes || format('(lower(%s) like ''%%'' || lower(%L) || ''%%'')', v_expr, replace(replace(v_val, '%', ''), '_', ''));
      elsif v_op = 'tiene' then v_partes := v_partes || format('(%s is not null)', v_expr);
      elsif v_op = 'no_tiene' then v_partes := v_partes || format('(%s is null)', v_expr);
      else raise exception 'EM_REGLA_INVALIDA: operador %', v_op; end if;

    elsif v_tipo = 'bool' then
      if v_op <> 'es' or v_val not in ('true','false') then raise exception 'EM_REGLA_INVALIDA: valor %', v_campo; end if;
      v_partes := v_partes || format('(%s = %L::boolean)', v_expr, v_val);

    elsif v_tipo = 'arr_uuid' then
      if v_val !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then raise exception 'EM_REGLA_INVALIDA: valor %', v_campo; end if;
      if v_op = 'incluye' then v_partes := v_partes || format('(%L::uuid = any(%s))', v_val, v_expr);
      elsif v_op = 'no_incluye' then v_partes := v_partes || format('(not (%L::uuid = any(%s)))', v_val, v_expr);
      else raise exception 'EM_REGLA_INVALIDA: operador %', v_op; end if;

    elsif v_tipo = 'arr_txt' then
      if v_val = '' then raise exception 'EM_REGLA_INVALIDA: valor %', v_campo; end if;
      if v_op = 'incluye' then v_partes := v_partes || format('(%L = any(%s))', v_val, v_expr);
      elsif v_op = 'no_incluye' then v_partes := v_partes || format('(not (%L = any(%s)))', v_val, v_expr);
      else raise exception 'EM_REGLA_INVALIDA: operador %', v_op; end if;
    end if;
  end loop;

  if cardinality(v_partes) = 0 then return 'true'; end if;
  return '(' || array_to_string(v_partes, case when v_modo = 'y' then ' and ' else ' or ' end) || ')';
end;
$$;

comment on function em__segmento_where(jsonb) is 'Traduce la definicion de un segmento a un WHERE con LISTA BLANCA de campos y operadores; los valores van escapados con %L. Nunca acepta SQL del cliente. Errores EM_REGLA_INVALIDA.';

revoke execute on function em__segmento_where(jsonb) from public, anon, authenticated;

create or replace function em__segmento_contactos(p_def jsonb)
returns setof uuid
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return query execute
    'select c.id from em_contactos c'
    || ' left join em__perfil_base(null, null) p on p.customer_id = c.customer_id'
    || ' left join em__perfil_email() e on e.contacto_id = c.id where '
    || em__segmento_where(p_def);
end;
$$;

revoke execute on function em__segmento_contactos(jsonb) from public, anon, authenticated;

-- ------------------------------------------------------------
-- (C) Opciones del editor de segmentos (+ campanas enviadas)
-- ------------------------------------------------------------
create or replace function em_segmento_opciones()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  return jsonb_build_object(
    'ciudades', (select coalesce(jsonb_agg(x order by x), '[]') from (select distinct initcap(lower(btrim(ciudad))) x from pedidos where not anulado and nullif(btrim(ciudad), '') is not null) s),
    'departamentos', (select coalesce(jsonb_agg(x order by x), '[]') from (select distinct initcap(lower(btrim(departamento))) x from pedidos where not anulado and nullif(btrim(departamento), '') is not null) s),
    'categorias', (select coalesce(jsonb_agg(x order by x), '[]') from (
                     select distinct coalesce(cc.nombre, nullif(pr.categoria, '')) x
                       from pedido_items pi join productos pr on pr.id = pi.product_id
                       left join lateral (select c2.categoria_codigo from campana_producto c2 where c2.product_id_ref = pi.product_id order by c2.publicado desc limit 1) cp on true
                       left join campana_categoria cc on cc.codigo = cp.categoria_codigo) s where x is not null),
    'productos', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre) order by nombre), '[]') from (
                    select distinct pr.id, coalesce(cp.nombre, pr.nombre) nombre
                      from pedido_items pi join productos pr on pr.id = pi.product_id
                      left join lateral (select c2.nombre from campana_producto c2 where c2.product_id_ref = pr.id order by c2.publicado desc limit 1) cp on true) s),
    'temas', (select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden), '[]') from em_temas where activo),
    -- EM5.1: campanas ya enviadas (para "recibio / hizo clic en la campana X").
    'campanas', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre_interno,
                    'fecha', coalesce(enviada_en, programada_para)) order by coalesce(enviada_en, programada_para) desc), '[]')
                   from em_campanas where resend_broadcast_id is not null and coalesce(enviada_en, programada_para) <= now())
  );
end;
$$;

revoke execute on function em_segmento_opciones() from public;
grant  execute on function em_segmento_opciones() to authenticated, service_role;

-- ------------------------------------------------------------
-- (D) Perfiles para el clúster: + Respuesta a email (sin datos de contacto)
-- Cambia el tipo de retorno -> drop + create con la MISMA firma de entrada.
-- Por cliente se suman sus contactos (normalmente uno). NULL = nunca recibio
-- una campana (no es lo mismo que no responder).
-- ------------------------------------------------------------
drop function if exists mk_perfiles_clientes(date, date);
create function mk_perfiles_clientes(p_desde date default null, p_hasta date default null)
returns table (
  cliente_ref uuid, num_pedidos integer, unidades integer, gasto_total bigint, ticket_promedio bigint,
  dias_desde_ultima_compra integer, dias_entre_compras numeric,
  precio_min bigint, precio_max bigint, precio_prom bigint, pct_rebajado numeric,
  productos_distintos integer, categoria_dominante text,
  num_opiniones integer, estrellas_prom numeric, pct_opinadas numeric, dias_entrega_opinion numeric,
  ciudad text, departamento text, es_local boolean,
  pct_web numeric, franja_moda text, dia_moda text, pct_hora_exacta numeric,
  suscrito boolean,
  email_campanas_recibidas integer, email_pct_clic numeric, email_clics_90d integer,
  email_dias_desde_ultimo_clic integer, email_compras_atribuidas integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not tiene_acceso_marketing() then
    raise exception 'MK_SIN_ACCESO';
  end if;
  return query
    with em as (
      select e.customer_id,
             sum(e.campanas_recibidas)::int as recibidas,
             sum(e.campanas_con_clic)::int as con_clic,
             sum(e.clics_90d)::int as clics_90d,
             min(e.dias_desde_ultimo_clic)::int as dias_clic,
             max(e.compras_atribuidas)::int as compras
        from em__perfil_email() e
       where e.customer_id is not null
       group by e.customer_id
    )
    select b.customer_id, b.num_pedidos, b.unidades, b.gasto_total, b.ticket_promedio,
           b.dias_desde_ultima_compra, b.dias_entre_compras,
           b.precio_min, b.precio_max, b.precio_prom, b.pct_rebajado,
           b.productos_distintos, b.categoria_dominante,
           b.num_opiniones, b.estrellas_prom, b.pct_opinadas, b.dias_entrega_opinion,
           b.ciudad, b.departamento, b.es_local,
           b.pct_web, b.franja_moda, b.dia_moda, b.pct_hora_exacta,
           exists (select 1 from em_contactos c where c.customer_id = b.customer_id and c.estado = 'suscrito'),
           em.recibidas,
           case when em.recibidas > 0 then round(100.0 * em.con_clic / em.recibidas, 1) end,
           em.clics_90d,
           em.dias_clic,
           em.compras
      from em__perfil_base(p_desde, p_hasta) b
      left join em on em.customer_id = b.customer_id;
end;
$$;

comment on function mk_perfiles_clientes(date, date) is 'Perfil por cliente para analisis (Marketing Project / cluster). SIN correo, telefono ni nombre: cliente_ref es un id interno. EM5.1: + respuesta a email (campanas recibidas, % con clic, clics 90 dias, dias desde el ultimo clic, compras atribuidas); NULL = nunca recibio una campana. Guardado por tiene_acceso_marketing().';

revoke execute on function mk_perfiles_clientes(date, date) from public, anon;
grant  execute on function mk_perfiles_clientes(date, date) to authenticated, service_role;
