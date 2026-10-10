-- ============================================================================
-- MAGANDHI · La analitica de Email marketing ya cuenta los dias en Colombia
-- ----------------------------------------------------------------------------
-- Corte: 10 de octubre de 2026. Migracion FORWARD. Corrige un bug de fechas
-- que llevaba latente desde EM2 y que aparecia SOLO entre las 7 p. m. y la
-- medianoche de Colombia.
--
-- EL BUG
--   La base corre en UTC, asi que `current_date` es la fecha UTC. A partir de
--   las 7 p. m. de Colombia (00:00 UTC) ya es "manana" para la base, pero sigue
--   siendo hoy aqui. Tres expresiones de la analitica comparaban ese
--   `current_date` con fechas que SI estan en hora de Colombia. Resultado:
--   todos los dias, durante cinco horas, los dias contados salian con uno de
--   mas.
--
--   Demostrado con aritmetica directa (9-oct 20:00 en Colombia, clic de hace
--   una hora):
--
--     current_date (UTC) | hoy en Colombia | fecha del clic | CALCULADO | CORRECTO
--     -------------------+-----------------+----------------+-----------+---------
--     2026-10-10         | 2026-10-09      | 2026-10-09     |         1 |        0
--
--   Un clic de hace una hora se reportaba como «hace 1 dia».
--
--   Y no era solo cosmetico: estas tres variables alimentan las condiciones de
--   **Segmentos** y las 5 variables de email del **analisis de cluster**. Una
--   condicion como «no ha hecho clic en N dias» daba de mas justo en la franja
--   de la tarde-noche, que es cuando se revisa el panel.
--
-- LO QUE SE CORRIGE
--   | Donde                                  | Variable                   |
--   |----------------------------------------|----------------------------|
--   | em__perfil_base (EM2)                  | dias_desde_ultima_compra   |
--   | em__perfil_email (EM5.1)                | dias_desde_ultimo_clic     |
--   | em__segmento_where (EM5.1, lista blanca) | dias_en_lista             |
--
--   · `dias_desde_ultima_compra` comparaba UTC contra `pedidos.fecha_orden`,
--     que en las ventas web la estampa F3 con `fz__fecha_colombia()`: mezcla.
--   · `dias_desde_ultimo_clic` mezclaba explicitamente, convirtiendo el clic a
--     Colombia y restandolo de `current_date`.
--   · `dias_en_lista` restaba dos fechas UTC: coherente entre si, pero cortaba
--     el dia a las 7 p. m. de Colombia. Ahora los dos lados van en Colombia.
--
-- POR QUE LA EXPRESION EN LINEA Y NO UNA FUNCION NUEVA
--   `(now() at time zone 'America/Bogota')::date` es EXACTAMENTE el patron que
--   Metricas M1 y M2 ya usan bien en todo su codigo. Reutilizarlo:
--     · no agrega ninguna funcion ni permiso nuevo (la matriz no cambia);
--     · funciona en cualquier contexto de ejecucion, incluido el WHERE que
--       `em__segmento_where` arma como texto y que se ejecuta mas adelante;
--     · no toca `fz__fecha_colombia()`, que es de Finanzas y a proposito no
--       tiene grants (solo corre dentro de funciones security definer).
--
-- COMO SE ESCRIBIO ESTA MIGRACION
--   Las tres funciones se copiaron LITERALMENTE de sus migraciones vigentes
--   (`20261010000000` y `20261014000000`) y se parcheo unicamente la expresion
--   de fecha, con una comprobacion que aborta si el patron no aparece
--   exactamente una vez y si queda algun `current_date`. El resto del cuerpo es
--   byte a byte el mismo: este cambio no toca ninguna otra logica.
--
-- `create or replace` conserva los permisos, pero los revoke se reemiten
-- explicitos, como en el resto del repo.
--
-- DEUDA RECONOCIDA Y NO TOCADA AQUI
--   Siguen con `default current_date` en el servidor: `crear_pedido`,
--   `inv_registrar_movimiento` y `em_registrar_contacto`, mas los defaults de
--   `pedidos.fecha_orden` y `movimientos_inventario.fecha`. Hoy NO son un bug
--   activo: las tres pantallas mandan la fecha explicita, calculada en el
--   navegador con `hoyISO()` (hora local = Colombia). Son trampas latentes: si
--   algun dia alguien llama esas RPC sin fecha a las 8 p. m., el registro
--   quedaria con la fecha de manana (y el 31 de diciembre saltaria de ano).
--   Cerrarlas exige redefinir RPC de nucleo y merece su propio PR medido.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- (A) EM2 · em__perfil_base: dias_desde_ultima_compra
-- ----------------------------------------------------------------------------
-- `b.ultima_compra` es `max(pedidos.fecha_orden)`, y en las ventas web esa
-- fecha la estampa F3 en hora de Colombia. Restarle `current_date` (UTC) daba
-- un dia de mas despues de las 7 p. m.
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
       ((now() at time zone 'America/Bogota')::date - b.ultima_compra)::int,
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

revoke execute on function em__perfil_base(date, date) from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- (B) EM5.1 · em__perfil_email: dias_desde_ultimo_clic
-- ----------------------------------------------------------------------------
-- Era la mezcla mas evidente: el clic se convertia a Colombia y se restaba de
-- `current_date`, que es UTC. Es la que delataba el bug en el banco de pruebas.
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
       case when pc.ultimo_clic is not null then ((now() at time zone 'America/Bogota')::date - (pc.ultimo_clic at time zone 'America/Bogota')::date)::int end,
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

revoke execute on function em__perfil_email() from public, anon, authenticated;

-- ----------------------------------------------------------------------------
-- (C) EM5.1 · em__segmento_where: dias_en_lista
-- ----------------------------------------------------------------------------
-- Aqui los dos lados estaban en UTC, asi que eran coherentes entre si, pero el
-- dia se cortaba a las 7 p. m. de Colombia. Ahora los dos van en Colombia.
-- Ojo: la expresion vive dentro de un literal de texto (el WHERE se arma como
-- cadena), por eso las comillas de la zona van dobladas.
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
      ('dias_en_lista','num','((now() at time zone ''America/Bogota'')::date - (c.creado at time zone ''America/Bogota'')::date)'),
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

revoke execute on function em__segmento_where(jsonb) from public, anon, authenticated;
