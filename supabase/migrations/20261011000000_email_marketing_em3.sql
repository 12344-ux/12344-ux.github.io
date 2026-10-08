-- ============================================================
-- MAGANDHI · Email marketing · TRAMO EM3 (Analisis de cluster -> segmento)
-- ------------------------------------------------------------
-- El analisis corre en el navegador (marketing/marketing-project/
-- cluster-core.js) sobre mk_perfiles_clientes (sin datos de contacto). Este
-- archivo agrega lo que necesita el SERVIDOR:
--   em_segmento_desde_cluster -> guarda un grupo como segmento SNAPSHOT
--                                (tipo 'cluster', miembros congelados) con su
--                                origen (variables, k, calidad, retrato).
--   em_segmentos_lista        -> redefinida para devolver tambien el origen y
--                                el numero de miembros de los snapshots.
-- Exige AMBOS permisos: Marketing (corre el analisis) y Email marketing
-- (los segmentos alimentan campanas a personas reales).
-- Forward e idempotente. REQUISITO: despues de 20261010000000.
-- ============================================================

create or replace function em_segmento_desde_cluster(
  p_nombre      text,
  p_descripcion text,
  p_clientes    uuid[],
  p_origen      jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nom   text := btrim(coalesce(p_nombre, ''));
  v_id    uuid;
  v_n     integer;
  v_susc  integer;
begin
  if not (tiene_acceso_email_marketing() and tiene_acceso_marketing()) then
    raise exception 'EM_SIN_ACCESO';
  end if;
  if v_nom = '' or char_length(v_nom) > 80 then raise exception 'EM_SEGMENTO_NOMBRE'; end if;
  if p_clientes is null or cardinality(p_clientes) = 0 then raise exception 'EM_SEGMENTO_SIN_MIEMBROS'; end if;
  if cardinality(p_clientes) > 20000 then raise exception 'EM_SEGMENTO_MUY_GRANDE'; end if;
  if p_origen is not null and (jsonb_typeof(p_origen) <> 'object' or octet_length(p_origen::text) > 20000) then
    raise exception 'EM_ORIGEN_INVALIDO';
  end if;
  if exists (select 1 from em_segmentos where lower(btrim(nombre)) = lower(v_nom) and not archivado) then
    raise exception 'EM_SEGMENTO_DUPLICADO';
  end if;

  -- Solo clientes que existen (los ids vienen del navegador).
  select count(*) into v_n from clientes c where c.id = any(p_clientes);
  if v_n = 0 then raise exception 'EM_SEGMENTO_SIN_MIEMBROS'; end if;

  insert into em_segmentos (nombre, descripcion, tipo, definicion, dinamico, origen_cluster)
  values (v_nom, nullif(btrim(coalesce(p_descripcion, '')), ''), 'cluster',
          '{"modo":"y","reglas":[]}'::jsonb, false,
          coalesce(p_origen, '{}'::jsonb) || jsonb_build_object('guardado_en', now(), 'miembros', v_n))
  returning id into v_id;

  insert into em_segmento_miembros (segmento_id, customer_id, contacto_id)
  select v_id, c.id,
         (select ct.id from em_contactos ct where ct.customer_id = c.id order by (ct.estado = 'suscrito') desc limit 1)
    from clientes c
   where c.id = any(p_clientes)
  on conflict do nothing;

  select count(*) into v_susc
    from em_segmento_miembros m join em_contactos ct on ct.customer_id = m.customer_id
   where m.segmento_id = v_id and ct.estado = 'suscrito';

  return jsonb_build_object('id', v_id, 'miembros', v_n, 'suscritos', v_susc);
end;
$$;

comment on function em_segmento_desde_cluster(text, text, uuid[], jsonb) is 'Guarda un grupo del Analisis de cluster como segmento SNAPSHOT (miembros congelados = reproducible y explicable). Ignora ids que no son clientes. Exige permisos de Marketing y de Email marketing. La audiencia de una campana sigue siendo miembros ∩ suscritos.';

revoke execute on function em_segmento_desde_cluster(text, text, uuid[], jsonb) from public;
grant  execute on function em_segmento_desde_cluster(text, text, uuid[], jsonb) to authenticated, service_role;

-- Lista: ahora incluye origen y miembros.
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
      -- Snapshot: "coinciden" = miembros congelados; "suscritos" = los que hoy reciben.
      select count(*) into v_coinciden from em_segmento_miembros m where m.segmento_id = s.id;
      select count(distinct ct.id) into v_suscritos
        from em_segmento_miembros m join em_contactos ct on ct.customer_id = m.customer_id
       where m.segmento_id = s.id and ct.estado = 'suscrito';
    end if;
    v_out := v_out || jsonb_build_array(jsonb_build_object(
      'id', s.id, 'nombre', s.nombre, 'descripcion', s.descripcion, 'tipo', s.tipo,
      'definicion', s.definicion, 'origen', s.origen_cluster, 'archivado', s.archivado,
      'actualizado', s.actualizado, 'coinciden', v_coinciden, 'suscritos', v_suscritos));
  end loop;
  return v_out;
end;
$$;

revoke execute on function em_segmentos_lista(boolean) from public;
grant  execute on function em_segmentos_lista(boolean) to authenticated, service_role;
