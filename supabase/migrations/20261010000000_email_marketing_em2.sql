-- ============================================================
-- MAGANDHI · Email marketing · TRAMO EM2 (perfiles + segmentos por reglas)
-- ------------------------------------------------------------
-- Diseno en docs/PLANO-EMAIL-MARKETING.md §3.2 y §4.3.
--
-- QUE CREA:
--   em__perfil_base(desde, hasta)  -> NUCLEO INTERNO (sin grant): un perfil por
--                                     cliente con TODAS las variables que salen
--                                     de datos propios (valor, precio, surtido,
--                                     opiniones, geografia, tiempo, canal).
--   mk_perfiles_clientes(desde, hasta) -> lo mismo SIN datos de contacto, para
--                                     Marketing Project / Analisis de cluster
--                                     (EM3). Guardado por tiene_acceso_marketing().
--   em_segmentos / em_segmento_miembros -> segmentos por reglas (dinamicos) y,
--                                     desde EM3, snapshots de cluster.
--   em__segmento_where(def)        -> traduce reglas a SQL con LISTA BLANCA de
--                                     campos/operadores y literales escapados.
--   RPC: em_segmento_opciones, em_segmento_previa, em_segmento_guardar,
--        em_segmento_archivar, em_segmentos_lista.
--
-- REGLAS:
--   - Las campanas iran SOLO a segmento ∩ suscritos. La previa muestra ambos.
--   - Ninguna regla llega como SQL: solo {campo, op, valor} validados contra
--     una lista blanca; los valores se insertan con format(%L).
--   - Hora de compra: zona America/Bogota. En pedidos manuales es la hora de
--     REGISTRO (aproximada); se informa la proporcion web/manual.
--   - Opiniones: se excluyen las de prueba y las ocultas.
--
-- Forward e idempotente. EXECUTE nominal (tramo 0).
-- REQUISITO: despues de 20261009000000_email_marketing_em1.sql.
-- ============================================================

-- ------------------------------------------------------------
-- (A) Nucleo interno del perfil por cliente
-- ------------------------------------------------------------
create or replace function em__perfil_base(p_desde date default null, p_hasta date default null)
returns table (
  customer_id              uuid,
  num_pedidos              integer,
  unidades                 integer,
  gasto_total              bigint,
  ticket_promedio          bigint,
  primera_compra           date,
  ultima_compra            date,
  dias_desde_ultima_compra integer,
  dias_entre_compras       numeric,
  precio_min               bigint,
  precio_max               bigint,
  precio_prom              bigint,
  pct_rebajado             numeric,
  productos_distintos      integer,
  productos_comprados      uuid[],
  categorias_compradas     text[],
  categoria_dominante      text,
  num_opiniones            integer,
  estrellas_prom           numeric,
  pct_opinadas             numeric,
  dias_entrega_opinion     numeric,
  ciudad                   text,
  departamento             text,
  es_local                 boolean,
  pct_web                  numeric,
  franja_moda              text,
  dia_moda                 text,
  pct_hora_exacta          numeric
)
language sql
stable
security definer
set search_path = public
as $$
with ped as (
  select p.*,
         (p.creado at time zone 'America/Bogota') as creado_local
    from pedidos p
   where not p.anulado
     and p.customer_id is not null
     and (p_desde is null or p.fecha_orden >= p_desde)
     and (p_hasta is null or p.fecha_orden <= p_hasta)
),
it as (
  select pi.pedido_id, ped.customer_id, pi.product_id, pi.cantidad, pi.precio_unitario,
         pr.precio_venta as precio_lista,
         coalesce(cc.nombre, nullif(pr.categoria, '')) as categoria,
         pi.subtotal
    from pedido_items pi
    join ped on ped.id = pi.pedido_id
    join productos pr on pr.id = pi.product_id
    left join lateral (
      select c2.categoria_codigo from campana_producto c2
       where c2.product_id_ref = pi.product_id
       order by c2.publicado desc, c2.activo desc limit 1
    ) cp on true
    left join campana_categoria cc on cc.codigo = cp.categoria_codigo
),
base as (
  select ped.customer_id,
         count(*)::int                         as num_pedidos,
         sum(ped.total)::bigint                as gasto_total,
         min(ped.fecha_orden)                  as primera_compra,
         max(ped.fecha_orden)                  as ultima_compra,
         round(avg(case when ped.canal = 'web' then 100 else 0 end), 1) as pct_web,
         round(avg(case when ped.canal = 'web' then 100 else 0 end), 1) as pct_hora_exacta
    from ped group by ped.customer_id
),
gaps as (
  select customer_id, round(avg(gap)::numeric, 1) as dias_entre_compras
    from (select customer_id, fecha_orden - lag(fecha_orden) over (partition by customer_id order by fecha_orden, creado) as gap
            from ped) g
   where gap is not null
   group by customer_id
),
prec as (
  select customer_id,
         sum(cantidad)::int as unidades,
         min(precio_unitario)::bigint as precio_min,
         max(precio_unitario)::bigint as precio_max,
         round(sum(precio_unitario * cantidad)::numeric / nullif(sum(cantidad), 0))::bigint as precio_prom,
         round(100.0 * sum(case when precio_lista > 0 and precio_unitario < precio_lista then cantidad else 0 end)
               / nullif(sum(cantidad), 0), 1) as pct_rebajado,
         count(distinct product_id)::int as productos_distintos,
         array_agg(distinct product_id) as productos_comprados,
         array_remove(array_agg(distinct categoria), null) as categorias_compradas
    from it group by customer_id
),
catdom as (
  select distinct on (customer_id) customer_id, categoria
    from (select customer_id, categoria, sum(subtotal) s from it where categoria is not null group by 1, 2) x
   order by customer_id, s desc, categoria
),
entregas as (
  select b.pedido_id, max(b.cuando) as entregado_en
    from pedido_bitacora b
    join ped on ped.id = b.pedido_id
   where b.estado_nuevo = 'entregado'
   group by b.pedido_id
),
op as (
  select ped.customer_id,
         count(*)::int as num_opiniones,
         round(avg(o.estrellas)::numeric, 2) as estrellas_prom,
         round(avg(extract(epoch from (o.creado - e.entregado_en)) / 86400.0)::numeric, 1) as dias_entrega_opinion
    from opiniones o
    join ped on ped.id = o.pedido_id
    left join entregas e on e.pedido_id = o.pedido_id
   where not o.oculta and not o.es_prueba
   group by ped.customer_id
),
opinables as (
  select ped.customer_id, count(*)::int as n
    from (select distinct pi.pedido_id, pi.product_id from pedido_items pi) x
    join ped on ped.id = x.pedido_id
   where ped.estado = 'entregado'
   group by ped.customer_id
),
geo as (
  select distinct on (customer_id) customer_id,
         nullif(btrim(ciudad), '') as ciudad, nullif(btrim(departamento), '') as departamento
    from ped order by customer_id, fecha_orden desc, creado desc
),
franja as (
  select distinct on (customer_id) customer_id, f
    from (select customer_id,
                 case when extract(hour from creado_local) < 6  then 'madrugada'
                      when extract(hour from creado_local) < 12 then 'manana'
                      when extract(hour from creado_local) < 18 then 'tarde'
                      else 'noche' end as f, count(*) n
            from ped group by 1, 2) x
   order by customer_id, n desc, f
),
dia as (
  select distinct on (customer_id) customer_id, d
    from (select customer_id, extract(isodow from creado_local)::int as d, count(*) n from ped group by 1, 2) x
   order by customer_id, n desc, d
)
select b.customer_id,
       b.num_pedidos,
       coalesce(pr.unidades, 0),
       b.gasto_total,
       round(b.gasto_total::numeric / nullif(b.num_pedidos, 0))::bigint,
       b.primera_compra,
       b.ultima_compra,
       (current_date - b.ultima_compra)::int,
       g.dias_entre_compras,
       pr.precio_min, pr.precio_max, pr.precio_prom, pr.pct_rebajado,
       coalesce(pr.productos_distintos, 0),
       coalesce(pr.productos_comprados, '{}'),
       coalesce(pr.categorias_compradas, '{}'),
       cd.categoria,
       coalesce(o.num_opiniones, 0),
       o.estrellas_prom,
       case when coalesce(ob.n, 0) > 0 then round(100.0 * coalesce(o.num_opiniones, 0) / ob.n, 1) end,
       o.dias_entrega_opinion,
       ge.ciudad, ge.departamento,
       case when ge.ciudad is null then null else lower(ge.ciudad) = 'tunja' end,
       b.pct_web,
       fr.f,
       (array['lunes','martes','miercoles','jueves','viernes','sabado','domingo'])[di.d],
       b.pct_hora_exacta
  from base b
  left join gaps g      on g.customer_id = b.customer_id
  left join prec pr     on pr.customer_id = b.customer_id
  left join catdom cd   on cd.customer_id = b.customer_id
  left join op o        on o.customer_id = b.customer_id
  left join opinables ob on ob.customer_id = b.customer_id
  left join geo ge      on ge.customer_id = b.customer_id
  left join franja fr   on fr.customer_id = b.customer_id
  left join dia di      on di.customer_id = b.customer_id;
$$;

comment on function em__perfil_base(date, date) is 'NUCLEO INTERNO (sin grant): perfil por cliente con datos propios en el periodo (pedidos no anulados). Lo usan mk_perfiles_clientes (cluster, sin PII) y los segmentos (con contacto). Hora en America/Bogota; en pedidos manuales es la hora de registro (pct_hora_exacta = % web).';

revoke execute on function em__perfil_base(date, date) from public, anon, authenticated;

-- ------------------------------------------------------------
-- (B) Perfiles para Marketing Project (sin datos de contacto)
-- ------------------------------------------------------------
create or replace function mk_perfiles_clientes(p_desde date default null, p_hasta date default null)
returns table (
  cliente_ref uuid, num_pedidos integer, unidades integer, gasto_total bigint, ticket_promedio bigint,
  dias_desde_ultima_compra integer, dias_entre_compras numeric,
  precio_min bigint, precio_max bigint, precio_prom bigint, pct_rebajado numeric,
  productos_distintos integer, categoria_dominante text,
  num_opiniones integer, estrellas_prom numeric, pct_opinadas numeric, dias_entrega_opinion numeric,
  ciudad text, departamento text, es_local boolean,
  pct_web numeric, franja_moda text, dia_moda text, pct_hora_exacta numeric,
  suscrito boolean
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
    select b.customer_id, b.num_pedidos, b.unidades, b.gasto_total, b.ticket_promedio,
           b.dias_desde_ultima_compra, b.dias_entre_compras,
           b.precio_min, b.precio_max, b.precio_prom, b.pct_rebajado,
           b.productos_distintos, b.categoria_dominante,
           b.num_opiniones, b.estrellas_prom, b.pct_opinadas, b.dias_entrega_opinion,
           b.ciudad, b.departamento, b.es_local,
           b.pct_web, b.franja_moda, b.dia_moda, b.pct_hora_exacta,
           exists (select 1 from em_contactos c where c.customer_id = b.customer_id and c.estado = 'suscrito')
      from em__perfil_base(p_desde, p_hasta) b;
end;
$$;

comment on function mk_perfiles_clientes(date, date) is 'Perfil por cliente para analisis (Marketing Project / cluster). SIN correo, telefono ni nombre: cliente_ref es un id interno. Guardado por tiene_acceso_marketing().';

revoke execute on function mk_perfiles_clientes(date, date) from public;
grant  execute on function mk_perfiles_clientes(date, date) to authenticated, service_role;

-- ------------------------------------------------------------
-- (C) Segmentos
-- ------------------------------------------------------------
create table if not exists em_segmentos (
  id                uuid primary key default gen_random_uuid(),
  nombre            text not null check (char_length(btrim(nombre)) between 1 and 80),
  descripcion       text check (descripcion is null or char_length(descripcion) <= 300),
  tipo              text not null default 'reglas' check (tipo in ('reglas','cluster','manual')),
  definicion        jsonb not null default '{"modo":"y","reglas":[]}'::jsonb,
  dinamico          boolean not null default true,
  origen_cluster    jsonb,
  resend_segment_id text,
  archivado         boolean not null default false,
  creado            timestamptz not null default now(),
  creado_por        uuid references auth.users(id) default auth.uid(),
  actualizado       timestamptz not null default now(),
  actualizado_por   uuid references auth.users(id) default auth.uid()
);

create unique index if not exists em_segmentos_nombre_uidx on em_segmentos (lower(btrim(nombre))) where not archivado;

comment on table em_segmentos is 'Segmentos de Email marketing. tipo=reglas: definicion {modo: y|o, reglas: [{campo, op, valor}]} recalculada al usarse (dinamico). tipo=cluster (EM3): snapshot en em_segmento_miembros. La audiencia de una campana es SIEMPRE segmento ∩ suscritos.';

create table if not exists em_segmento_miembros (
  segmento_id uuid not null references em_segmentos(id),
  contacto_id uuid references em_contactos(id),
  customer_id uuid references clientes(id),
  agregado_en timestamptz not null default now(),
  primary key (segmento_id, customer_id)
);

comment on table em_segmento_miembros is 'Miembros congelados de segmentos snapshot (cluster, desde EM3). Se guarda el cliente; la campana resuelve su contacto suscrito al enviar.';

alter table em_segmentos enable row level security;
alter table em_segmento_miembros enable row level security;
drop policy if exists em_segmentos_select on em_segmentos;
create policy em_segmentos_select on em_segmentos for select to authenticated using (tiene_acceso_email_marketing());
drop policy if exists em_segmento_miembros_select on em_segmento_miembros;
create policy em_segmento_miembros_select on em_segmento_miembros for select to authenticated using (tiene_acceso_email_marketing());
grant select on table em_segmentos, em_segmento_miembros to authenticated;

-- ------------------------------------------------------------
-- (D) Traductor de reglas -> SQL (lista blanca)
-- Fila evaluada: alias c (em_contactos) + p (em__perfil_base, null si no compra).
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
      ('tema','arr_txt','c.temas')
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

-- Contactos que cumplen una definicion (interno).
create or replace function em__segmento_contactos(p_def jsonb)
returns setof uuid
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return query execute
    'select c.id from em_contactos c left join em__perfil_base(null, null) p on p.customer_id = c.customer_id where '
    || em__segmento_where(p_def);
end;
$$;

revoke execute on function em__segmento_contactos(jsonb) from public, anon, authenticated;

-- ------------------------------------------------------------
-- (E) RPC
-- ------------------------------------------------------------

-- Valores existentes para los selectores del editor.
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
    'temas', (select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'nombre', nombre) order by orden), '[]') from em_temas where activo)
  );
end;
$$;

revoke execute on function em_segmento_opciones() from public;
grant  execute on function em_segmento_opciones() to authenticated, service_role;

-- Vista previa en vivo: cuantos cumplen, cuantos recibirian y una muestra.
create or replace function em_segmento_previa(p_definicion jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;

  with m as (select id from em__segmento_contactos(p_definicion) as t(id)),
       c as (select c.* from em_contactos c join m on m.id = c.id)
  select jsonb_build_object(
    'coinciden', (select count(*) from c),
    'suscritos', (select count(*) from c where estado = 'suscrito'),
    'clientes',  (select count(*) from c where estado = 'suscrito' and customer_id is not null),
    'por_estado', (select coalesce(jsonb_object_agg(estado, n), '{}') from (select estado, count(*) n from c group by estado) e),
    'total_suscritos', (select count(*) from em_contactos where estado = 'suscrito'),
    'muestra', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre, 'correo', correo, 'estado', estado, 'cliente', customer_id is not null)
                  order by (estado = 'suscrito') desc, creado desc), '[]')
                  from (select * from c order by (estado = 'suscrito') desc, creado desc limit 12) s)
  ) into v;
  return v;
end;
$$;

revoke execute on function em_segmento_previa(jsonb) from public;
grant  execute on function em_segmento_previa(jsonb) to authenticated, service_role;

-- Guardar (crear o editar).
create or replace function em_segmento_guardar(p_id uuid, p_nombre text, p_descripcion text, p_definicion jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nom text := btrim(coalesce(p_nombre, ''));
  v_id  uuid;
  v_def jsonb;
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  if v_nom = '' or char_length(v_nom) > 80 then raise exception 'EM_SEGMENTO_NOMBRE'; end if;
  v_def := jsonb_build_object('modo', coalesce(p_definicion->>'modo', 'y'), 'reglas', coalesce(p_definicion->'reglas', '[]'::jsonb));
  if jsonb_array_length(v_def->'reglas') = 0 then raise exception 'EM_SEGMENTO_SIN_REGLAS'; end if;
  perform em__segmento_where(v_def); -- valida

  if exists (select 1 from em_segmentos where lower(btrim(nombre)) = lower(v_nom) and not archivado and id is distinct from p_id) then
    raise exception 'EM_SEGMENTO_DUPLICADO';
  end if;

  if p_id is null then
    insert into em_segmentos (nombre, descripcion, tipo, definicion, dinamico)
    values (v_nom, nullif(btrim(coalesce(p_descripcion, '')), ''), 'reglas', v_def, true)
    returning id into v_id;
  else
    update em_segmentos
       set nombre = v_nom, descripcion = nullif(btrim(coalesce(p_descripcion, '')), ''),
           definicion = v_def, actualizado = now(), actualizado_por = auth.uid()
     where id = p_id and tipo = 'reglas'
    returning id into v_id;
    if v_id is null then raise exception 'EM_SEGMENTO_NO_EXISTE'; end if;
  end if;
  return jsonb_build_object('id', v_id);
end;
$$;

revoke execute on function em_segmento_guardar(uuid, text, text, jsonb) from public;
grant  execute on function em_segmento_guardar(uuid, text, text, jsonb) to authenticated, service_role;

-- Archivar / restaurar (nunca se borra: una campana puede referenciarlo).
create or replace function em_segmento_archivar(p_id uuid, p_archivar boolean)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_s em_segmentos%rowtype;
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  select * into v_s from em_segmentos where id = p_id for update;
  if not found then raise exception 'EM_SEGMENTO_NO_EXISTE'; end if;
  if not coalesce(p_archivar, true) and exists (
       select 1 from em_segmentos where lower(btrim(nombre)) = lower(btrim(v_s.nombre)) and not archivado and id <> p_id) then
    raise exception 'EM_SEGMENTO_DUPLICADO';
  end if;
  update em_segmentos set archivado = coalesce(p_archivar, true), actualizado = now(), actualizado_por = auth.uid() where id = p_id;
  return jsonb_build_object('id', p_id, 'archivado', coalesce(p_archivar, true));
end;
$$;

revoke execute on function em_segmento_archivar(uuid, boolean) from public;
grant  execute on function em_segmento_archivar(uuid, boolean) to authenticated, service_role;

-- Lista con tamanos actuales.
create or replace function em_segmentos_lista(p_archivados boolean default false)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_out jsonb := '[]';
  s em_segmentos%rowtype;
  v_coinciden int;
  v_suscritos int;
begin
  if not tiene_acceso_email_marketing() then raise exception 'EM_SIN_ACCESO'; end if;
  for s in select * from em_segmentos where archivado = coalesce(p_archivados, false) order by actualizado desc loop
    if s.tipo = 'reglas' then
      select count(*), count(*) filter (where c.estado = 'suscrito') into v_coinciden, v_suscritos
        from em_contactos c where c.id in (select * from em__segmento_contactos(s.definicion));
    else
      select count(*), count(*) filter (where c.estado = 'suscrito') into v_coinciden, v_suscritos
        from em_segmento_miembros m join em_contactos c on c.customer_id = m.customer_id where m.segmento_id = s.id;
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'id', s.id, 'nombre', s.nombre, 'descripcion', s.descripcion, 'tipo', s.tipo,
      'definicion', s.definicion, 'archivado', s.archivado, 'actualizado', s.actualizado,
      'coinciden', v_coinciden, 'suscritos', v_suscritos));
  end loop;
  return v_out;
end;
$$;

revoke execute on function em_segmentos_lista(boolean) from public;
grant  execute on function em_segmentos_lista(boolean) to authenticated, service_role;
