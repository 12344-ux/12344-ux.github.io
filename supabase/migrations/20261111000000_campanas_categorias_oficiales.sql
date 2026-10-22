-- ============================================================
-- MAGANDHI · Campañas · categorías oficiales planas y clasificación múltiple
-- Migración FORWARD posterior al corte vigente (20261110000000).
--
-- Conserva campana_producto.categoria_codigo y las RPC C1 para clientes
-- anteriores. Los clientes nuevos usan wrappers atómicos que delegan en esas
-- RPC y escriben la relación muchos-a-muchos dentro de la misma transacción.
-- Los colores históricos siguen almacenados únicamente por compatibilidad;
-- ninguna superficie pública los usa o los expone.
-- ============================================================

begin;
set local search_path = public, pg_catalog;
set local statement_timeout = '20s';
set local lock_timeout = '5s';

-- Bloquea primero las escrituras de campañas y después el catálogo. Así una RPC
-- C1 ya iniciada puede terminar su comprobación FK antes de que el ALTER tome
-- el catálogo, y la forward no forma un ciclo campaña ↔ categoría. Las lecturas
-- públicas continúan; si hay actividad de escritura, lock_timeout hace fallar
-- toda la transacción sin aplicar cambios parciales.
lock table public.campana_producto in share row exclusive mode;
lock table public.campana_categoria in access exclusive mode;

-- ----------------------------------------------------------------------------
-- (A) Catálogo plano. Ocho categorías iniciales oficiales y altas posteriores.
-- ----------------------------------------------------------------------------
alter table public.campana_categoria
  add column if not exists icono_codigo text,
  add column if not exists descripcion text,
  add column if not exists activo boolean not null default true,
  add column if not exists visible_tienda boolean not null default true,
  add column if not exists es_oficial boolean not null default false;

do $mig$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'campana_categoria_descripcion_breve_chk'
       and conrelid = 'public.campana_categoria'::regclass
  ) then
    alter table public.campana_categoria
      add constraint campana_categoria_descripcion_breve_chk
      check (descripcion is null or length(descripcion) <= 240);
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'campana_categoria_icono_controlado_chk'
       and conrelid = 'public.campana_categoria'::regclass
  ) then
    alter table public.campana_categoria
      add constraint campana_categoria_icono_controlado_chk
      check (
        icono_codigo is null
        or icono_codigo = any (array[
          'tecnologia', 'moda', 'hogar', 'deportes',
          'belleza', 'accesorios', 'mascotas', 'jugueteria',
          'regalo', 'bienestar', 'oficina', 'viaje',
          'bebes', 'alimentos', 'coleccion'
        ]::text[])
      );
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'campana_categoria_oficial_codigo_chk'
       and conrelid = 'public.campana_categoria'::regclass
  ) then
    alter table public.campana_categoria
      add constraint campana_categoria_oficial_codigo_chk
      check (
        not es_oficial
        or codigo = any (array[
          'tecnologia', 'moda', 'hogar', 'deportes',
          'belleza', 'accesorios', 'mascotas', 'jugueteria'
        ]::text[])
      );
  end if;
end
$mig$;

comment on table public.campana_categoria is
  'Campañas · catálogo plano de clasificación. Ocho filas iniciales son oficiales y las altas posteriores son no oficiales; los colores heredados no gobiernan la presentación pública.';
comment on column public.campana_producto.categoria_codigo is
  'Categoría principal compatible con clientes y RPC C1; la selección completa vive en campana_producto_categoria.';
comment on column public.campana_categoria.icono_codigo is
  'Código de icono de lista blanca; nunca contiene HTML, una URL ni una key de Storage.';
comment on column public.campana_categoria.descripcion is
  'Texto breve para la banda pública de categoría, limitado a 240 caracteres.';
comment on column public.campana_categoria.activo is
  'Control de selección interna. Las RPC nuevas solo aceptan categorías activas.';
comment on column public.campana_categoria.visible_tienda is
  'Control de exposición pública. Las vistas públicas excluyen categorías no visibles.';
comment on column public.campana_categoria.es_oficial is
  'Distingue exclusivamente las ocho categorías iniciales definidas por MAGANDHI; las altas del panel son no oficiales.';
comment on column public.campana_categoria.color_fuerte is
  'Color histórico conservado por compatibilidad interna; no se expone públicamente.';
comment on column public.campana_categoria.color_claro is
  'Color histórico conservado por compatibilidad interna; no se expone públicamente.';
comment on column public.campana_categoria.color_sombra is
  'Color histórico conservado por compatibilidad interna; no se expone públicamente.';

-- Primero se limpia la marca oficial para que ni una fila histórica ni una alta
-- previa pueda conservarla por accidente. Las ocho filas siguientes son la única
-- semilla oficial y quedan en el orden exacto acordado.
update public.campana_categoria set es_oficial = false where es_oficial;

insert into public.campana_categoria (
  codigo, nombre, color_fuerte, color_claro, color_sombra, orden,
  icono_codigo, descripcion, activo, visible_tienda, es_oficial
) values
  ('tecnologia', 'Tecnología', '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 10, 'tecnologia', 'Tecnología y dispositivos para la vida diaria.', true, true, true),
  ('moda',       'Moda',       '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 20, 'moda',       'Prendas y propuestas para vestir con intención.', true, true, true),
  ('hogar',      'Hogar',      '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 30, 'hogar',      'Objetos y soluciones para los espacios cotidianos.', true, true, true),
  ('deportes',   'Deportes',   '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 40, 'deportes',   'Productos para movimiento, entrenamiento y bienestar.', true, true, true),
  ('belleza',    'Belleza',    '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 50, 'belleza',    'Belleza, cuidado personal y rutinas de bienestar.', true, true, true),
  ('accesorios', 'Accesorios', '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 60, 'accesorios', 'Complementos funcionales y de estilo.', true, true, true),
  ('mascotas',   'Mascotas',   '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 70, 'mascotas',   'Cuidado, bienestar y accesorios para mascotas.', true, true, true),
  ('jugueteria', 'Juguetería', '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 80, 'jugueteria', 'Juegos y productos para aprender, crear y disfrutar.', true, true, true)
on conflict (codigo) do update
set nombre         = excluded.nombre,
    orden          = excluded.orden,
    icono_codigo   = excluded.icono_codigo,
    descripcion    = excluded.descripcion,
    activo         = excluded.activo,
    visible_tienda = excluded.visible_tienda,
    es_oficial     = excluded.es_oficial;

-- Estas seis categorías fueron pruebas. Se conserva cada fila y cada referencia
-- histórica, pero dejan de ser seleccionables y públicas. En particular,
-- alimentos NO se mapea a otra categoría.
update public.campana_categoria
   set activo = false,
       visible_tienda = false,
       es_oficial = false
 where codigo in (
   'cabello', 'belleza_fem', 'belleza_masc', 'cuidado_gral',
   'alimentos', 'destacado'
 );

-- Las cuatro pruebas de belleza sí tienen una equivalencia autorizada. Hogar ya
-- usa el código definitivo y se conserva tal cual; alimentos no se recategoriza.
update public.campana_producto
   set categoria_codigo = 'belleza',
       actualizado = now()
 where categoria_codigo in ('cabello', 'belleza_fem', 'belleza_masc', 'cuidado_gral');

-- Corrección puntual conocida: si la ficha comercial identificada por ese UUID
-- o una campaña ligada al producto de Inventario con ese UUID estaba sin
-- categoría, en Destacado o en la prueba Belleza masculina (ya migrada arriba
-- a Belleza), pertenece a Juguetería.
update public.campana_producto
   set categoria_codigo = 'jugueteria',
       actualizado = now()
 where (
   id = '22af3f92-3085-49e1-89b2-0dc680f4c6e2'::uuid
   or product_id_ref = '22af3f92-3085-49e1-89b2-0dc680f4c6e2'::uuid
 )
   and (categoria_codigo is null or categoria_codigo in ('destacado', 'belleza'));

-- Los segmentos dinámicos de Email Marketing guardan el nombre visible como
-- valor de regla. Al consolidar cuatro pruebas bajo Belleza, sus reglas deben
-- seguir apuntando a una categoría existente en lugar de quedar silenciosamente
-- vacías. Solo se reescriben los dos campos de categoría y los nombres
-- históricos exactos de Belleza/Hogar; el resto del JSON, el modo y el orden
-- se conservan.
with segmentos_reescritos as (
  select s.id,
         jsonb_set(
           s.definicion,
           '{reglas}',
           (
             select coalesce(
               jsonb_agg(
                 case
                   when regla ->> 'campo' in ('compro_categoria', 'categoria_dominante')
                    and lower(btrim(coalesce(regla ->> 'valor', ''))) in (
                      'cuidado del cabello', 'belleza femenina',
                      'belleza masculina', 'cuidado personal/general'
                    )
                   then jsonb_set(regla, '{valor}', to_jsonb('Belleza'::text), true)
                   when regla ->> 'campo' in ('compro_categoria', 'categoria_dominante')
                    and lower(btrim(coalesce(regla ->> 'valor', ''))) = 'hogar/limpieza'
                   then jsonb_set(regla, '{valor}', to_jsonb('Hogar'::text), true)
                   else regla
                 end
                 order by ord
               ),
               '[]'::jsonb
             )
               from jsonb_array_elements(s.definicion -> 'reglas')
                    with ordinality as r(regla, ord)
           ),
           false
         ) as definicion_nueva
    from public.em_segmentos s
   where s.tipo = 'reglas'
     and jsonb_typeof(s.definicion -> 'reglas') = 'array'
     and exists (
       select 1
         from jsonb_array_elements(s.definicion -> 'reglas') regla
        where regla ->> 'campo' in ('compro_categoria', 'categoria_dominante')
          and (
            lower(btrim(coalesce(regla ->> 'valor', ''))) in (
              'cuidado del cabello', 'belleza femenina',
              'belleza masculina', 'cuidado personal/general'
            )
            or lower(btrim(coalesce(regla ->> 'valor', ''))) = 'hogar/limpieza'
          )
     )
)
update public.em_segmentos s
   set definicion = r.definicion_nueva,
       actualizado = now()
  from segmentos_reescritos r
 where s.id = r.id
   and s.definicion is distinct from r.definicion_nueva;

-- ----------------------------------------------------------------------------
-- (B) Puente muchos-a-muchos y sincronización del campo principal legado.
-- ----------------------------------------------------------------------------
create table if not exists public.campana_producto_categoria (
  campana_producto_id uuid not null
    references public.campana_producto(id) on delete cascade,
  categoria_codigo text not null
    references public.campana_categoria(codigo) on update restrict on delete restrict,
  es_principal boolean not null default false,
  creado timestamptz not null default now(),
  primary key (campana_producto_id, categoria_codigo)
);

create unique index if not exists campana_producto_categoria_una_principal_idx
  on public.campana_producto_categoria (campana_producto_id)
  where es_principal;
create index if not exists campana_producto_categoria_categoria_idx
  on public.campana_producto_categoria (categoria_codigo, campana_producto_id);

comment on table public.campana_producto_categoria is
  'Campañas · clasificación plana muchos-a-muchos. Las RPC nuevas guardan entre 1 y 12 categorías y una principal compatible con campana_producto.categoria_codigo.';
comment on column public.campana_producto_categoria.es_principal is
  'Única categoría principal de la campaña; se refleja en campana_producto.categoria_codigo para clientes anteriores y RPC C1.';

create or replace function public.cm__proteger_clave_producto_categoria()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $fn$
begin
  if new.campana_producto_id is distinct from old.campana_producto_id
     or new.categoria_codigo is distinct from old.categoria_codigo then
    raise exception 'CM_CATEGORIA_CLAVE_INMUTABLE: elimina y crea la asociación para cambiar sus claves.';
  end if;
  return new;
end;
$fn$;
revoke all on function public.cm__proteger_clave_producto_categoria()
  from public, anon, authenticated, service_role;

drop trigger if exists cm_producto_categoria_proteger_clave on public.campana_producto_categoria;
create trigger cm_producto_categoria_proteger_clave
before update of campana_producto_id, categoria_codigo
on public.campana_producto_categoria
for each row execute function public.cm__proteger_clave_producto_categoria();

alter table public.campana_producto_categoria enable row level security;
drop policy if exists campana_producto_categoria_select_marketing on public.campana_producto_categoria;
create policy campana_producto_categoria_select_marketing
  on public.campana_producto_categoria
  for select to authenticated
  using (public.tiene_acceso_marketing());

-- La escritura normal solo ocurre desde funciones SECURITY DEFINER. Ni anon ni
-- service_role necesitan acceso directo al puente para este frente.
revoke all on table public.campana_producto_categoria
  from public, anon, authenticated, service_role;
grant select on table public.campana_producto_categoria to authenticated;

-- El backfill ocurre después de las recategorizaciones anteriores. Conserva
-- asociaciones históricas sin inventar equivalencias (incluido alimentos).
insert into public.campana_producto_categoria (
  campana_producto_id, categoria_codigo, es_principal
)
select id, categoria_codigo, true
  from public.campana_producto
 where categoria_codigo is not null
on conflict (campana_producto_id, categoria_codigo) do update
  set es_principal = true;

-- Los clientes viejos que llaman las RPC C1 continúan representando una sola
-- categoría. Su campo legado reemplaza el puente dentro de la misma transacción.
create or replace function public.cm__sincronizar_categoria_principal_legado()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $fn$
begin
  delete from public.campana_producto_categoria
   where campana_producto_id = new.id;

  if new.categoria_codigo is not null then
    insert into public.campana_producto_categoria (
      campana_producto_id, categoria_codigo, es_principal
    ) values (new.id, new.categoria_codigo, true);
  end if;
  return new;
end;
$fn$;
revoke all on function public.cm__sincronizar_categoria_principal_legado()
  from public, anon, authenticated, service_role;

drop trigger if exists cm_producto_sincronizar_categoria_legado on public.campana_producto;
create trigger cm_producto_sincronizar_categoria_legado
after insert or update of categoria_codigo on public.campana_producto
for each row execute function public.cm__sincronizar_categoria_principal_legado();

-- La compatibilidad C1 no puede convertirse en una vía para mantener publicada
-- una campaña con una categoría retirada. cm_editar_campana siempre asigna
-- categoria_codigo; si la fila ya está publicada, este trigger exige que la
-- principal siga activa y visible antes de que el trigger de sincronización
-- reduzca el puente a la selección singular del cliente antiguo.
create or replace function public.cm__validar_categoria_publicada_legacy()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $fn$
begin
  if new.publicado and (
    new.categoria_codigo is null
    or not exists (
      select 1
        from public.campana_categoria c
       where c.codigo = new.categoria_codigo
         and c.activo
         and c.visible_tienda
    )
  ) then
    raise exception 'CM_CATEGORIA_PUBLICADA_INVALIDA: una campaña publicada requiere una categoría principal activa y visible.';
  end if;
  return new;
end;
$fn$;
revoke all on function public.cm__validar_categoria_publicada_legacy()
  from public, anon, authenticated, service_role;

drop trigger if exists cm_producto_validar_categoria_publicada_legacy
  on public.campana_producto;
create trigger cm_producto_validar_categoria_publicada_legacy
before update of categoria_codigo on public.campana_producto
for each row execute function public.cm__validar_categoria_publicada_legacy();

-- Constraint diferido: los wrappers pueden reemplazar el puente y el estado
-- final debe conservar exactamente una principal igual al campo C1 legado.
create or replace function public.cm__validar_principal_puente()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $fn$
declare
  v_id uuid := coalesce(new.campana_producto_id, old.campana_producto_id);
  v_legado text;
  v_total integer;
  v_principales integer;
  v_principal text;
begin
  select cp.categoria_codigo
    into v_legado
    from public.campana_producto cp
   where cp.id = v_id;
  if not found then
    return null; -- borrado de campaña con cascada
  end if;

  select count(*),
         count(*) filter (where pcc.es_principal),
         max(pcc.categoria_codigo) filter (where pcc.es_principal)
    into v_total, v_principales, v_principal
    from public.campana_producto_categoria pcc
   where pcc.campana_producto_id = v_id;

  if v_total = 0 and v_legado is not null then
    raise exception 'CM_CATEGORIA_PRINCIPAL_INVALIDA: falta la asociación principal de la campaña.';
  end if;
  if v_total > 0 and (v_principales <> 1 or v_principal is distinct from v_legado) then
    raise exception 'CM_CATEGORIA_PRINCIPAL_INVALIDA: el puente debe tener una sola principal y coincidir con categoria_codigo.';
  end if;
  return null;
end;
$fn$;
revoke all on function public.cm__validar_principal_puente()
  from public, anon, authenticated, service_role;

drop trigger if exists cm_producto_categoria_validar_principal on public.campana_producto_categoria;
create constraint trigger cm_producto_categoria_validar_principal
after insert or update or delete on public.campana_producto_categoria
deferrable initially deferred
for each row execute function public.cm__validar_principal_puente();

-- ----------------------------------------------------------------------------
-- (C) Validación común y wrappers atómicos sobre las RPC C1 vigentes.
-- ----------------------------------------------------------------------------
create or replace function public.cm__validar_categorias_seleccion(
  p_categoria_codigos text[],
  p_categoria_principal text
)
returns text[]
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_codigos text[];
  v_principal text := btrim(coalesce(p_categoria_principal, ''));
  v_total integer;
begin
  if p_categoria_codigos is null then
    raise exception 'CM_CATEGORIAS_REQUERIDAS: elige al menos una categoría.';
  end if;

  if exists (
    select 1 from unnest(p_categoria_codigos) x
     where x is null or btrim(x) = ''
  ) then
    raise exception 'CM_CATEGORIA_INVALIDA: los códigos no pueden estar vacíos.';
  end if;

  select coalesce(array_agg(btrim(x) order by ord), '{}'::text[])
    into v_codigos
    from unnest(p_categoria_codigos) with ordinality t(x, ord);

  v_total := cardinality(v_codigos);
  if v_total < 1 then
    raise exception 'CM_CATEGORIAS_REQUERIDAS: elige al menos una categoría.';
  end if;
  if v_total > 12 then
    raise exception 'CM_CATEGORIAS_MAXIMO: elige como máximo 12 categorías.';
  end if;
  if (select count(distinct x) from unnest(v_codigos) x) <> v_total then
    raise exception 'CM_CATEGORIAS_DUPLICADAS: no repitas categorías.';
  end if;
  if v_principal = '' or not (v_principal = any(v_codigos)) then
    raise exception 'CM_CATEGORIA_PRINCIPAL_INVALIDA: la principal debe estar incluida en la selección.';
  end if;

  -- Estabiliza activo+visible hasta el fin de la transacción.
  perform 1
    from public.campana_categoria c
   where c.codigo = any(v_codigos)
   order by c.codigo
   for share;

  if (
    select count(*)
      from public.campana_categoria c
     where c.codigo = any(v_codigos)
       and c.activo
       and c.visible_tienda
  ) <> v_total then
    raise exception 'CM_CATEGORIA_NO_PUBLICA: todas las categorías deben existir y estar activas y visibles.';
  end if;

  return v_codigos;
end;
$fn$;

comment on function public.cm__validar_categorias_seleccion(text[], text) is
  'Helper privado: normaliza y valida 1..12 códigos activos y visibles, sin duplicados, con principal incluida.';
revoke all on function public.cm__validar_categorias_seleccion(text[], text)
  from public, anon, authenticated, service_role;

create or replace function public.cm_crear_campana_con_categorias(
  p_nombre                   text,
  p_detalle_presentacion     text default null,
  p_imagen_banner_path       text default null,
  p_caracteristica_adicional text default null,
  p_precio_venta             bigint default null,
  p_hook_largo               text default null,
  p_por_que_magandhi         text default null,
  p_sobre_este_producto      text default null,
  p_ficha_tecnica            jsonb default '[]'::jsonb,
  p_imagenes                 jsonb default '[]'::jsonb,
  p_sello_elegido            boolean default false,
  p_estrella                 boolean default false,
  p_stock_disponible         integer default 0,
  p_aviso_urgencia_activo    boolean default false,
  p_aviso_urgencia_cantidad  integer default null,
  p_etiquetas                text[] default '{}',
  p_product_id_ref           uuid default null,
  p_slug                     text default null,
  p_tope_escaparate          integer default null,
  p_producto_probado         boolean default false,
  p_max_unidades_pedido      integer default 1,
  p_categoria_codigos        text[] default null,
  p_categoria_principal      text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_resultado jsonb;
  v_id uuid;
  v_codigos text[];
  v_codigo text;
  v_principal text := btrim(coalesce(p_categoria_principal, ''));
begin
  if not public.tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;
  v_codigos := public.cm__validar_categorias_seleccion(p_categoria_codigos, v_principal);

  v_resultado := public.cm_crear_campana(
    p_nombre, v_principal, p_detalle_presentacion, p_imagen_banner_path,
    p_caracteristica_adicional, p_precio_venta, p_hook_largo,
    p_por_que_magandhi, p_sobre_este_producto, p_ficha_tecnica, p_imagenes,
    p_sello_elegido, p_estrella, p_stock_disponible,
    p_aviso_urgencia_activo, p_aviso_urgencia_cantidad, p_etiquetas,
    p_product_id_ref, p_slug, p_tope_escaparate, p_producto_probado,
    p_max_unidades_pedido
  );
  v_id := (v_resultado ->> 'id')::uuid;

  delete from public.campana_producto_categoria where campana_producto_id = v_id;
  foreach v_codigo in array v_codigos loop
    insert into public.campana_producto_categoria (
      campana_producto_id, categoria_codigo, es_principal
    ) values (v_id, v_codigo, v_codigo = v_principal);
  end loop;

  return v_resultado;
end;
$fn$;

comment on function public.cm_crear_campana_con_categorias(text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean, integer, text[], text) is
  'Wrapper atómico de cm_crear_campana C1: valida categorías públicas, conserva categoria_codigo como principal y reemplaza el puente en la misma transacción.';

create or replace function public.cm_editar_campana_con_categorias(
  p_id                       uuid,
  p_nombre                   text,
  p_detalle_presentacion     text default null,
  p_imagen_banner_path       text default null,
  p_caracteristica_adicional text default null,
  p_precio_venta             bigint default null,
  p_hook_largo               text default null,
  p_por_que_magandhi         text default null,
  p_sobre_este_producto      text default null,
  p_ficha_tecnica            jsonb default '[]'::jsonb,
  p_imagenes                 jsonb default '[]'::jsonb,
  p_sello_elegido            boolean default false,
  p_estrella                 boolean default false,
  p_stock_disponible         integer default 0,
  p_aviso_urgencia_activo    boolean default false,
  p_aviso_urgencia_cantidad  integer default null,
  p_etiquetas                text[] default '{}',
  p_product_id_ref           uuid default null,
  p_slug                     text default null,
  p_tope_escaparate          integer default null,
  p_producto_probado         boolean default false,
  p_max_unidades_pedido      integer default 1,
  p_categoria_codigos        text[] default null,
  p_categoria_principal      text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_resultado uuid;
  v_codigos text[];
  v_codigo text;
  v_principal text := btrim(coalesce(p_categoria_principal, ''));
begin
  if not public.tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;
  v_codigos := public.cm__validar_categorias_seleccion(p_categoria_codigos, v_principal);

  v_resultado := public.cm_editar_campana(
    p_id, p_nombre, v_principal, p_detalle_presentacion,
    p_imagen_banner_path, p_caracteristica_adicional, p_precio_venta,
    p_hook_largo, p_por_que_magandhi, p_sobre_este_producto,
    p_ficha_tecnica, p_imagenes, p_sello_elegido, p_estrella,
    p_stock_disponible, p_aviso_urgencia_activo,
    p_aviso_urgencia_cantidad, p_etiquetas, p_product_id_ref, p_slug,
    p_tope_escaparate, p_producto_probado, p_max_unidades_pedido
  );

  delete from public.campana_producto_categoria where campana_producto_id = p_id;
  foreach v_codigo in array v_codigos loop
    insert into public.campana_producto_categoria (
      campana_producto_id, categoria_codigo, es_principal
    ) values (p_id, v_codigo, v_codigo = v_principal);
  end loop;

  return v_resultado;
end;
$fn$;

comment on function public.cm_editar_campana_con_categorias(uuid, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean, integer, text[], text) is
  'Wrapper atómico de cm_editar_campana C1: valida categorías públicas, conserva categoria_codigo como principal y reemplaza el puente en la misma transacción.';

revoke all on function public.cm_crear_campana_con_categorias(text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean, integer, text[], text)
  from public, anon, authenticated, service_role;
grant execute on function public.cm_crear_campana_con_categorias(text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean, integer, text[], text)
  to authenticated, service_role;
revoke all on function public.cm_editar_campana_con_categorias(uuid, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean, integer, text[], text)
  from public, anon, authenticated, service_role;
grant execute on function public.cm_editar_campana_con_categorias(uuid, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean, integer, text[], text)
  to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (D) Publicación: conserva C1, D2b y D2c; suma el candado de clasificación.
-- ----------------------------------------------------------------------------
create or replace function public.cm_publicar_campana(
  p_id uuid,
  p_publicado boolean
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_producto_esperado uuid;
  v_producto_id uuid;
  v_precio bigint;
  v_producto_activo boolean;
  v_origen text;
  v_sello_elegido boolean;
  v_producto_probado boolean;
  v_categoria_legada text;
  v_total_publicas integer;
  v_principales integer;
  v_principales_publicas integer;
  v_principal text;
begin
  if not public.tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;

  -- Despublicar (también con NULL, por compatibilidad) omite todos los gates.
  -- Solo exige que la campaña exista; nunca borra ni modifica su clasificación.
  if not coalesce(p_publicado, false) then
    update public.campana_producto
       set publicado = false,
           actualizado = now()
     where id = p_id;
    if not found then
      raise exception 'La campana % no existe.', p_id;
    end if;
    return p_id;
  end if;

  -- C1 fija el orden común producto -> campaña. Primero se obtiene el vínculo
  -- como candidato, se bloquea ese producto y luego se bloquea/relee la campaña.
  -- Si una edición cambió el vínculo entre ambas lecturas, se falla cerrado y el
  -- operador puede reintentar sin invertir locks.
  select cp.product_id_ref
    into v_producto_esperado
    from public.campana_producto cp
   where cp.id = p_id;
  if not found then
    raise exception 'La campana % no existe.', p_id;
  end if;
  if v_producto_esperado is null then
    raise exception 'No se puede publicar: liga primero un producto de Inventario.';
  end if;

  select p.activo, p.origen
    into v_producto_activo, v_origen
    from public.productos p
   where p.id = v_producto_esperado
   for share;

  select cp.product_id_ref, cp.precio_venta, cp.sello_elegido,
         cp.probado_por_magandhi, cp.categoria_codigo
    into v_producto_id, v_precio, v_sello_elegido,
         v_producto_probado, v_categoria_legada
    from public.campana_producto cp
   where cp.id = p_id
   for update;

  if not found then
    raise exception 'La campana % no existe.', p_id;
  end if;
  if v_producto_id is distinct from v_producto_esperado then
    raise exception 'CM_PUBLICACION_REINTENTAR: el producto ligado cambió durante la publicación; vuelve a intentarlo.';
  end if;
  if coalesce(v_producto_activo, false) is not true then
    raise exception 'No se puede publicar: el producto de Inventario esta inactivo.';
  end if;

  -- D2c permanece abierto para proveedor, pero exige y estabiliza su ficha
  -- despachable mientras se completa la publicación.
  if coalesce(v_origen, 'propio') = 'proveedor' then
    perform 1
      from public.producto_proveedor pp
     where pp.product_id = v_producto_id
     for share;
    if not found then
      raise exception 'DS_SIN_FICHA_PROVEEDOR: este producto es de proveedor pero no tiene ficha con su id de Dropi, asi que no se podria pedir. Vuelve a llevarlo desde Dropshipping.';
    end if;
  end if;
  if v_precio is null or v_precio <= 0 then
    raise exception 'No se puede publicar: define un precio de venta mayor que cero.';
  end if;
  if coalesce(v_sello_elegido, false)
     and not coalesce(v_producto_probado, false) then
    raise exception 'CM_SELLO_SIN_PRUEBA: marca «Este producto fue probado por MAGANDHI» antes de publicar Elegido por MAGANDHI.';
  end if;

  -- Estabiliza la visibilidad de las categorías mientras se publica.
  perform 1
    from public.campana_producto_categoria pcc
    join public.campana_categoria c on c.codigo = pcc.categoria_codigo
   where pcc.campana_producto_id = p_id
   order by c.codigo
   for share of c;

  select count(*) filter (where c.activo and c.visible_tienda),
         count(*) filter (where pcc.es_principal),
         count(*) filter (
           where pcc.es_principal and c.activo and c.visible_tienda
         ),
         max(pcc.categoria_codigo) filter (where pcc.es_principal)
    into v_total_publicas, v_principales, v_principales_publicas, v_principal
    from public.campana_producto_categoria pcc
    join public.campana_categoria c on c.codigo = pcc.categoria_codigo
   where pcc.campana_producto_id = p_id;

  if v_total_publicas < 1
     or v_principales <> 1
     or v_principales_publicas <> 1
     or v_principal is distinct from v_categoria_legada then
    raise exception 'CM_CATEGORIAS_PUBLICACION_REQUERIDAS: elige y guarda al menos una categoría activa y visible, incluida una principal, antes de publicar.';
  end if;

  update public.campana_producto
     set publicado = true,
         actualizado = now()
   where id = p_id;

  return p_id;
end;
$fn$;

comment on function public.cm_publicar_campana(uuid, boolean) is
  'Campañas · publica o despublica. Conserva orden de locks y producto/precio C1, ficha de proveedor D2c y sello con prueba D2b. Al publicar exige una clasificación con principal activa y visible; despublicar siempre queda permitido y nunca borra la ficha.';

-- CREATE OR REPLACE conserva ACL, pero se reexpresa la superficie vigente para
-- no depender de defaults: puerta de panel/servidor, nunca anónima.
revoke all on function public.cm_publicar_campana(uuid, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.cm_publicar_campana(uuid, boolean)
  to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (E) Listas blancas públicas, sin ids privados, jerarquías ni colores.
-- ----------------------------------------------------------------------------
create or replace view public.categorias_publicas as
select
  c.codigo,
  c.nombre,
  c.icono_codigo,
  c.descripcion,
  c.orden,
  c.es_oficial
from public.campana_categoria c
where c.activo
  and c.visible_tienda;

comment on view public.categorias_publicas is
  'Lista blanca de categorías planas activas y visibles, incluidas las creadas posteriormente desde el panel. Expone código público, nombre, icono controlado, descripción, orden y distintivo oficial; nunca colores ni controles internos.';

revoke all on table public.categorias_publicas
  from public, anon, authenticated, service_role;
grant select on table public.categorias_publicas
  to anon, authenticated, service_role;

-- Misma forma C1 de 24 columnas; se agregan al FINAL categoria_codigos y
-- categorias. Los colores heredados devuelven constantes de marca, no datos del
-- catálogo interno.
create or replace view public.catalogo_publico as
select
  cp.id,
  cp.nombre,
  cp.slug,
  case when cc.codigo is not null then cp.categoria_codigo end as categoria_codigo,
  cc.nombre as categoria_nombre,
  '#C28A3A'::text as color_fuerte,
  '#D9AE6E'::text as color_claro,
  'rgba(194,138,58,.16)'::text as color_sombra,
  cp.detalle_presentacion,
  cp.imagen_banner_path,
  cp.caracteristica_adicional,
  cp.precio_venta,
  cp.hook_largo,
  cp.por_que_magandhi,
  cp.sobre_este_producto,
  cp.ficha_tecnica,
  cp.imagenes,
  cp.sello_elegido,
  cp.estrella,
  (mx.max_comprable = 0) as agotado,
  cp.aviso_urgencia_activo,
  cp.aviso_urgencia_cantidad,
  cp.orden,
  mx.max_comprable,
  cats.categoria_codigos,
  cats.categorias
from public.campana_producto cp
left join public.campana_categoria cc
  on cc.codigo = cp.categoria_codigo
 and cc.activo
 and cc.visible_tienda
left join public.productos p on p.id = cp.product_id_ref
left join (
  select dc.venta_proveedor_habilitada
    from public.dropshipping_config dc
   where dc.id = 1
) dcfg on true
cross join lateral (
  select public.ventas_max_comprable_campana(cp.id) as max_comprable
) mx
cross join lateral (
  with seleccion as (
    select pcc.categoria_codigo as codigo, pcc.es_principal
      from public.campana_producto_categoria pcc
     where pcc.campana_producto_id = cp.id
    union all
    select cp.categoria_codigo, true
     where cp.categoria_codigo is not null
       and not exists (
         select 1
           from public.campana_producto_categoria pcc
          where pcc.campana_producto_id = cp.id
       )
  )
  select
    coalesce(
      array_agg(c.codigo order by s.es_principal desc, c.orden, c.codigo),
      '{}'::text[]
    ) as categoria_codigos,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'codigo', c.codigo,
          'nombre', c.nombre,
          'icono_codigo', c.icono_codigo,
          'descripcion', c.descripcion,
          'es_oficial', c.es_oficial,
          'principal', s.es_principal
        ) order by s.es_principal desc, c.orden, c.codigo
      ),
      '[]'::jsonb
    ) as categorias
  from seleccion s
  join public.campana_categoria c
    on c.codigo = s.codigo
   and c.activo
   and c.visible_tienda
) cats
where cp.publicado
  and cp.activo
  and (
    coalesce(p.origen, 'propio') = 'propio'
    or coalesce(dcfg.venta_proveedor_habilitada, false)
  );

comment on view public.catalogo_publico is
  'Categorías planas · conserva las 24 columnas C1 y agrega al final categoria_codigos text[] y categorias jsonb. El JSON expone solo código, nombre, icono controlado, descripción, oficial y principal. Los colores compatibles son constantes MAGANDHI; nunca expone colores arbitrarios, stock, piso, reservas, origen, proveedor ni ids externos.';

revoke all on table public.catalogo_publico
  from public, anon, authenticated, service_role;
grant select on table public.catalogo_publico
  to anon, authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (F) Alta autenticada de categorías no oficiales, plana y sin uploads.
-- ----------------------------------------------------------------------------
create or replace function public.cm_crear_categoria(
  nombre text,
  descripcion text,
  icono_codigo text
)
returns setof public.categorias_publicas
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_nombre text := btrim(coalesce($1, ''));
  v_descripcion text := btrim(coalesce($2, ''));
  v_icono text := lower(btrim(coalesce($3, '')));
  v_codigo text;
  v_orden integer;
begin
  if not public.tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;

  if length(v_nombre) < 2 or length(v_nombre) > 80 then
    raise exception 'CM_CATEGORIA_NOMBRE_INVALIDO: el nombre debe tener entre 2 y 80 caracteres.';
  end if;
  if length(v_descripcion) < 1 or length(v_descripcion) > 240 then
    raise exception 'CM_CATEGORIA_DESCRIPCION_INVALIDA: la descripción debe tener entre 1 y 240 caracteres.';
  end if;
  if not (v_icono = any (array[
    'tecnologia', 'moda', 'hogar', 'deportes',
    'belleza', 'accesorios', 'mascotas', 'jugueteria',
    'regalo', 'bienestar', 'oficina', 'viaje',
    'bebes', 'alimentos', 'coleccion'
  ]::text[])) then
    raise exception 'CM_CATEGORIA_ICONO_INVALIDO: elige un icono de la lista permitida.';
  end if;

  -- Slug seguro derivado únicamente en servidor: minúsculas ASCII, guiones y
  -- máximo 64 caracteres. El código nunca llega desde el navegador.
  v_codigo := lower(v_nombre);
  v_codigo := translate(
    v_codigo,
    'áàäâãéèëêíìïîóòöôõúùüûñç',
    'aaaaaeeeeiiiiooooouuuunc'
  );
  v_codigo := regexp_replace(v_codigo, '[^a-z0-9]+', '-', 'g');
  v_codigo := regexp_replace(v_codigo, '-+', '-', 'g');
  v_codigo := btrim(v_codigo, '-');
  v_codigo := left(v_codigo, 64);
  v_codigo := regexp_replace(v_codigo, '-+$', '');

  if v_codigo = '' then
    raise exception 'CM_CATEGORIA_CODIGO_INVALIDO: el nombre no permite derivar un código seguro.';
  end if;

  -- Altas poco frecuentes: este lock evita órdenes repetidos y hace que la
  -- comprobación de colisión y el siguiente orden formen una sola decisión.
  lock table public.campana_categoria in share row exclusive mode;

  if exists (
    select 1 from public.campana_categoria c where c.codigo = v_codigo
  ) then
    raise exception 'CM_CATEGORIA_CODIGO_EXISTE: ya existe una categoría con el código "%".', v_codigo;
  end if;

  select coalesce(max(c.orden), 0) + 10
    into v_orden
    from public.campana_categoria c;

  begin
    insert into public.campana_categoria (
      codigo, nombre, color_fuerte, color_claro, color_sombra, orden,
      icono_codigo, descripcion, activo, visible_tienda, es_oficial
    ) values (
      v_codigo, v_nombre, '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', v_orden,
      v_icono, v_descripcion, true, true, false
    );
  exception when unique_violation then
    raise exception 'CM_CATEGORIA_CODIGO_EXISTE: ya existe una categoría con el código "%".', v_codigo;
  end;

  return query
  select c.codigo, c.nombre, c.icono_codigo, c.descripcion, c.orden, c.es_oficial
    from public.categorias_publicas c
   where c.codigo = v_codigo;
end;
$fn$;

comment on function public.cm_crear_categoria(text, text, text) is
  'Campañas · alta autenticada de categoría plana. Exige Marketing, valida límites e icono de lista blanca, deriva slug seguro en servidor, rechaza colisiones, asigna orden y publica de inmediato. Devuelve exactamente la fila pública; no crea ni recibe uploads.';

revoke all on function public.cm_crear_categoria(text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.cm_crear_categoria(text, text, text)
  to authenticated;

-- ----------------------------------------------------------------------------
-- (G) Gates de contrato antes de confirmar la forward.
-- ----------------------------------------------------------------------------
do $gate$
declare
  v_oficiales text[];
  v_columnas text[];
begin
  select array_agg(c.codigo order by c.orden, c.codigo)
    into v_oficiales
    from public.campana_categoria c
   where c.es_oficial;

  if v_oficiales is distinct from array[
    'tecnologia', 'moda', 'hogar', 'deportes',
    'belleza', 'accesorios', 'mascotas', 'jugueteria'
  ]::text[] then
    raise exception 'CM_CATEGORIAS_OFICIALES_INVALIDAS: deben existir exactamente las ocho categorías oficiales en el orden acordado.';
  end if;

  if exists (
    select 1
      from public.campana_categoria c
     where c.codigo in (
       'cabello', 'belleza_fem', 'belleza_masc', 'cuidado_gral',
       'alimentos', 'destacado'
     )
       and (c.activo or c.visible_tienda or c.es_oficial)
  ) then
    raise exception 'CM_CATEGORIAS_HISTORICAS_VISIBLES: una categoría de prueba quedó activa, visible u oficial.';
  end if;

  if exists (
    select 1
      from public.campana_producto cp
     where cp.categoria_codigo in ('cabello', 'belleza_fem', 'belleza_masc', 'cuidado_gral')
  ) then
    raise exception 'CM_BELLEZA_HISTORICA_SIN_MIGRAR';
  end if;

  if exists (
    select 1
      from public.campana_producto cp
     where (
       cp.id = '22af3f92-3085-49e1-89b2-0dc680f4c6e2'::uuid
       or cp.product_id_ref = '22af3f92-3085-49e1-89b2-0dc680f4c6e2'::uuid
     )
       and (cp.categoria_codigo is null or cp.categoria_codigo = 'destacado')
  ) then
    raise exception 'CM_JUGUETERIA_CONOCIDA_SIN_MIGRAR';
  end if;

  select array_agg(cols.column_name::text order by cols.ordinal_position)
    into v_columnas
    from information_schema.columns cols
   where cols.table_schema = 'public'
     and cols.table_name = 'catalogo_publico';

  if v_columnas is distinct from array[
    'id', 'nombre', 'slug', 'categoria_codigo', 'categoria_nombre',
    'color_fuerte', 'color_claro', 'color_sombra',
    'detalle_presentacion', 'imagen_banner_path', 'caracteristica_adicional',
    'precio_venta', 'hook_largo', 'por_que_magandhi', 'sobre_este_producto',
    'ficha_tecnica', 'imagenes', 'sello_elegido', 'estrella', 'agotado',
    'aviso_urgencia_activo', 'aviso_urgencia_cantidad', 'orden',
    'max_comprable', 'categoria_codigos', 'categorias'
  ]::text[] then
    raise exception 'CM_CATALOGO_CONTRATO_INVALIDO: catalogo_publico no conserva las 24 columnas C1 seguidas de las dos columnas de categorías.';
  end if;

  if not has_table_privilege('anon', 'public.categorias_publicas', 'select')
     or not has_table_privilege('authenticated', 'public.categorias_publicas', 'select')
     or not has_table_privilege('service_role', 'public.categorias_publicas', 'select')
     or not has_table_privilege('anon', 'public.catalogo_publico', 'select')
     or not has_table_privilege('authenticated', 'public.catalogo_publico', 'select')
     or not has_table_privilege('service_role', 'public.catalogo_publico', 'select') then
    raise exception 'CM_VISTAS_PUBLICAS_SELECT_FALTANTE';
  end if;

  if exists (
    select 1
      from pg_class c
      cross join lateral aclexplode(
        coalesce(c.relacl, acldefault('r', c.relowner))
      ) acl
      left join pg_roles r on r.oid = acl.grantee
     where c.oid in (
       'public.categorias_publicas'::regclass,
       'public.catalogo_publico'::regclass
     )
       and (acl.grantee = 0 or r.rolname in ('anon', 'authenticated', 'service_role'))
       and (acl.grantee = 0 or acl.privilege_type <> 'SELECT')
  ) then
    raise exception 'CM_VISTA_PUBLICA_CON_PRIVILEGIOS_EXTRA';
  end if;

  if not has_table_privilege('authenticated', 'public.campana_producto_categoria', 'select')
     or has_table_privilege('anon', 'public.campana_producto_categoria', 'select')
     or has_table_privilege('service_role', 'public.campana_producto_categoria', 'select') then
    raise exception 'CM_PUENTE_ACL_INVALIDA';
  end if;

  if has_function_privilege('anon', 'public.cm_crear_categoria(text,text,text)', 'execute')
     or not has_function_privilege('authenticated', 'public.cm_crear_categoria(text,text,text)', 'execute')
     or has_function_privilege('service_role', 'public.cm_crear_categoria(text,text,text)', 'execute') then
    raise exception 'CM_CREAR_CATEGORIA_ACL_INVALIDA';
  end if;
end
$gate$;

commit;
