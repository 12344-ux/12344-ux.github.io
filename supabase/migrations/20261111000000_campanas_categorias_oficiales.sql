-- ============================================================
-- MAGANDHI · Campañas · categorías oficiales y clasificación múltiple
-- Migración FORWARD posterior al ledger vigente (20261110000000).
--
-- Conserva campana_producto.categoria_codigo y las RPC C1 para clientes
-- anteriores. Los clientes nuevos usan wrappers atómicos que delegan en esas
-- RPC y escriben la relación muchos-a-muchos dentro de la misma transacción.
-- Los colores históricos siguen almacenados únicamente por compatibilidad;
-- las superficies públicas reciben siempre la paleta fija MAGANDHI.
-- ============================================================

begin;

-- ----------------------------------------------------------------------------
-- (A) Catálogo jerárquico: máximo raíz + subcategoría.
-- ----------------------------------------------------------------------------
alter table campana_categoria
  add column if not exists parent_codigo text,
  add column if not exists icono_codigo text,
  add column if not exists descripcion text,
  add column if not exists activo boolean not null default true,
  add column if not exists visible_tienda boolean not null default true;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'campana_categoria_parent_codigo_fkey'
       and conrelid = 'campana_categoria'::regclass
  ) then
    alter table campana_categoria
      add constraint campana_categoria_parent_codigo_fkey
      foreign key (parent_codigo) references campana_categoria(codigo)
      on update cascade on delete restrict;
  end if;
  if not exists (
    select 1 from pg_constraint
     where conname = 'campana_categoria_parent_distinto_chk'
       and conrelid = 'campana_categoria'::regclass
  ) then
    alter table campana_categoria
      add constraint campana_categoria_parent_distinto_chk
      check (parent_codigo is null or parent_codigo <> codigo);
  end if;
  if not exists (
    select 1 from pg_constraint
     where conname = 'campana_categoria_descripcion_breve_chk'
       and conrelid = 'campana_categoria'::regclass
  ) then
    alter table campana_categoria
      add constraint campana_categoria_descripcion_breve_chk
      check (descripcion is null or length(descripcion) <= 240);
  end if;
end
$$;

comment on column campana_categoria.parent_codigo is
  'Categoría raíz de una subcategoría. NULL identifica una categoría principal; la jerarquía admite como máximo dos niveles.';
comment on column campana_categoria.icono_codigo is
  'Código público controlado del icono; nunca contiene HTML ni una URL.';
comment on column campana_categoria.descripcion is
  'Descripción pública breve, limitada a 240 caracteres.';
comment on column campana_categoria.activo is
  'Control de selección interna. Solo categorías activas pueden guardarse mediante las RPC nuevas.';
comment on column campana_categoria.visible_tienda is
  'Control de exposición pública. categorias_publicas y catalogo_publico excluyen categorías no visibles.';
comment on column campana_categoria.color_fuerte is
  'Color histórico conservado por compatibilidad interna. La tienda pública usa siempre la paleta fija MAGANDHI.';
comment on column campana_categoria.color_claro is
  'Color histórico conservado por compatibilidad interna. La tienda pública usa siempre la paleta fija MAGANDHI.';
comment on column campana_categoria.color_sombra is
  'Color histórico conservado por compatibilidad interna. La tienda pública usa siempre la paleta fija MAGANDHI.';

-- Los colores de filas nuevas satisfacen el contrato NOT NULL heredado. En
-- conflictos no se pisan colores previos: quedan como dato histórico.
insert into campana_categoria (
  codigo, nombre, color_fuerte, color_claro, color_sombra, orden,
  parent_codigo, icono_codigo, descripcion, activo, visible_tienda
) values
  ('tecnologia', 'Tecnología', '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 10, null, 'tecnologia', 'Tecnología y dispositivos para la vida diaria.', true, true),
  ('moda',       'Moda', '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 20, null, 'moda', 'Prendas y propuestas para vestir con intención.', true, true),
  ('hogar',      'Hogar', '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 30, null, 'hogar', 'Objetos y soluciones para los espacios cotidianos.', true, true),
  ('deportes',   'Deportes', '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 40, null, 'deportes', 'Productos para movimiento, entrenamiento y bienestar.', true, true),
  ('belleza',    'Belleza y cuidado personal', '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 50, null, 'belleza', 'Cuidado personal, belleza y rutinas de bienestar.', true, true),
  ('accesorios', 'Accesorios', '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 60, null, 'accesorios', 'Complementos funcionales y de estilo.', true, true),
  ('jugueteria', 'Juguetería', '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 70, null, 'jugueteria', 'Juegos y productos para aprender, crear y disfrutar.', true, true),
  ('mascotas',   'Mascotas', '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 80, null, 'mascotas', 'Cuidado, bienestar y accesorios para mascotas.', true, true),
  ('alimentos',  'Alimentos y bebidas', '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 90, null, 'alimentos', 'Alimentos, bebidas y opciones para disfrutar cada día.', true, true),
  ('cabello',      'Cuidado del cabello', '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 51, 'belleza', 'cabello', 'Productos para limpiar, tratar y cuidar el cabello.', true, true),
  ('belleza_fem',  'Cuidado femenino', '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 52, 'belleza', 'belleza_fem', 'Rutinas y productos de cuidado seleccionados.', true, true),
  ('belleza_masc', 'Belleza y cuidado masculino', '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 53, 'belleza', 'belleza_masc', 'Cuidado personal y rutinas para hombre.', true, true),
  ('cuidado_gral', 'Cuidado corporal e higiene', '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 54, 'belleza', 'cuidado_gral', 'Bienestar e higiene para todos los días.', true, true)
on conflict (codigo) do update
set nombre          = excluded.nombre,
    orden           = excluded.orden,
    parent_codigo   = excluded.parent_codigo,
    icono_codigo    = excluded.icono_codigo,
    descripcion     = excluded.descripcion,
    activo          = excluded.activo,
    visible_tienda  = excluded.visible_tienda;

-- Destacado deja de ser taxonomía seleccionable o pública, sin borrar su fila
-- ni romper referencias históricas.
update campana_categoria
   set nombre = 'Destacado (histórico)',
       parent_codigo = null,
       icono_codigo = null,
       descripcion = null,
       activo = false,
       visible_tienda = false
 where codigo = 'destacado';

create or replace function cm__validar_jerarquia_categoria()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_parent_parent text;
  v_parent_activo boolean;
  v_parent_visible boolean;
  v_codigo_anterior text;
begin
  if tg_op = 'UPDATE' then
    v_codigo_anterior := old.codigo;
  end if;

  if new.parent_codigo is null then
    if (not new.activo and exists (
          select 1 from campana_categoria hija
           where hija.parent_codigo in (new.codigo, v_codigo_anterior)
             and hija.activo = true
       )) or (not new.visible_tienda and exists (
          select 1 from campana_categoria hija
           where hija.parent_codigo in (new.codigo, v_codigo_anterior)
             and hija.visible_tienda = true
       )) then
      raise exception 'CM_CATEGORIA_PARENT_INACTIVO: desactiva u oculta primero sus subcategorías.';
    end if;
    return new;
  end if;

  select parent_codigo, activo, visible_tienda
    into v_parent_parent, v_parent_activo, v_parent_visible
    from campana_categoria
   where codigo = new.parent_codigo;
  if not found then
    raise exception 'CM_CATEGORIA_PARENT_INEXISTENTE: la categoría padre % no existe.', new.parent_codigo;
  end if;
  if v_parent_parent is not null then
    raise exception 'CM_CATEGORIA_JERARQUIA_INVALIDA: solo se permiten dos niveles.';
  end if;
  if new.activo and not v_parent_activo then
    raise exception 'CM_CATEGORIA_PARENT_INACTIVO: una subcategoría activa requiere una categoría padre activa.';
  end if;
  if new.visible_tienda and not v_parent_visible then
    raise exception 'CM_CATEGORIA_PARENT_OCULTO: una subcategoría visible requiere una categoría padre visible.';
  end if;
  if exists (
    select 1 from campana_categoria hija
     where hija.parent_codigo in (new.codigo, v_codigo_anterior)
       and hija.codigo <> new.codigo
  ) then
    raise exception 'CM_CATEGORIA_JERARQUIA_INVALIDA: una categoría con subcategorías no puede depender de otra.';
  end if;
  return new;
end;
$$;

revoke all on function cm__validar_jerarquia_categoria() from public, anon, authenticated, service_role;

drop trigger if exists cm_categoria_validar_jerarquia on campana_categoria;
create trigger cm_categoria_validar_jerarquia
before insert or update of codigo, parent_codigo, activo, visible_tienda on campana_categoria
for each row execute function cm__validar_jerarquia_categoria();

-- Verificación inmediata del histórico ya reclasificado.
do $$
begin
  if exists (
    select 1
      from campana_categoria hija
      join campana_categoria padre on padre.codigo = hija.parent_codigo
     where padre.parent_codigo is not null
  ) then
    raise exception 'CM_CATEGORIA_JERARQUIA_INVALIDA: existen más de dos niveles.';
  end if;
end
$$;

-- ----------------------------------------------------------------------------
-- (B) Puente muchos-a-muchos y sincronización del campo principal legado.
-- ----------------------------------------------------------------------------
create table if not exists campana_producto_categoria (
  campana_producto_id uuid not null
    references campana_producto(id) on delete cascade,
  categoria_codigo text not null
    references campana_categoria(codigo) on update cascade on delete restrict,
  es_principal boolean not null default false,
  creado timestamptz not null default now(),
  primary key (campana_producto_id, categoria_codigo)
);

create unique index if not exists campana_producto_categoria_una_principal_idx
  on campana_producto_categoria (campana_producto_id)
  where es_principal;
create index if not exists campana_producto_categoria_categoria_idx
  on campana_producto_categoria (categoria_codigo, campana_producto_id);

comment on table campana_producto_categoria is
  'Campañas · clasificación muchos-a-muchos. Cada campaña administrada por las RPC nuevas tiene entre 1 y 12 categorías y exactamente una asociación principal.';
comment on column campana_producto_categoria.es_principal is
  'Única categoría principal de la campaña; se refleja en campana_producto.categoria_codigo para clientes anteriores.';

-- Las claves del puente son identidad, no campos editables. Las operaciones
-- válidas reemplazan asociaciones mediante DELETE + INSERT; esto evita que una
-- actualización de mantenimiento deje sin validar la campaña de origen.
create or replace function cm__proteger_clave_producto_categoria()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.campana_producto_id is distinct from old.campana_producto_id
     or new.categoria_codigo is distinct from old.categoria_codigo then
    raise exception 'CM_CATEGORIA_CLAVE_INMUTABLE: elimina y crea la asociación para cambiar sus claves.';
  end if;
  return new;
end;
$$;
revoke all on function cm__proteger_clave_producto_categoria() from public, anon, authenticated, service_role;

drop trigger if exists cm_producto_categoria_proteger_clave on campana_producto_categoria;
create trigger cm_producto_categoria_proteger_clave
before update of campana_producto_id, categoria_codigo on campana_producto_categoria
for each row execute function cm__proteger_clave_producto_categoria();

alter table campana_producto_categoria enable row level security;
drop policy if exists campana_producto_categoria_select_marketing on campana_producto_categoria;
create policy campana_producto_categoria_select_marketing
  on campana_producto_categoria
  for select to authenticated
  using (tiene_acceso_marketing());

revoke all on table campana_producto_categoria from public, anon, authenticated;
grant select on table campana_producto_categoria to authenticated;
grant select, insert, update, delete on table campana_producto_categoria to service_role;

-- Backfill fiel del campo histórico, incluso si la categoría ya no es activa.
insert into campana_producto_categoria (
  campana_producto_id, categoria_codigo, es_principal
)
select id, categoria_codigo, true
  from campana_producto
 where categoria_codigo is not null
on conflict (campana_producto_id, categoria_codigo) do update
  set es_principal = true;

-- Mantiene funcionales los clientes viejos que solo llaman cm_crear_campana o
-- cm_editar_campana: su categoría única reemplaza el puente. Los wrappers nuevos
-- llaman esas RPC y, acto seguido, reemplazan este resultado por la selección
-- completa dentro de la misma transacción.
create or replace function cm__sincronizar_categoria_principal_legado()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  -- El trigger ya está restringido a INSERT o UPDATE OF categoria_codigo. Se
  -- sincroniza siempre, incluso cuando un cliente viejo reenvía la misma
  -- principal: para ese cliente el contrato continúa siendo de categoría única.
  if tg_op in ('INSERT', 'UPDATE') then
    delete from campana_producto_categoria
     where campana_producto_id = new.id;

    if new.categoria_codigo is not null then
      insert into campana_producto_categoria (
        campana_producto_id, categoria_codigo, es_principal
      ) values (new.id, new.categoria_codigo, true);
    end if;
  end if;
  return new;
end;
$$;

revoke all on function cm__sincronizar_categoria_principal_legado() from public, anon, authenticated, service_role;

drop trigger if exists cm_producto_sincronizar_categoria_legado on campana_producto;
create trigger cm_producto_sincronizar_categoria_legado
after insert or update of categoria_codigo on campana_producto
for each row execute function cm__sincronizar_categoria_principal_legado();

-- Constraint diferido: permite que los wrappers reemplacen el puente y valida
-- el estado final de la transacción. Si hay asociaciones debe existir una sola
-- principal y coincidir con el campo legado.
create or replace function cm__validar_principal_puente()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_id uuid := coalesce(new.campana_producto_id, old.campana_producto_id);
  v_legado text;
  v_total integer;
  v_principales integer;
  v_principal text;
begin
  select categoria_codigo into v_legado
    from campana_producto
   where id = v_id;
  if not found then
    return null; -- borrado de campaña con cascada
  end if;

  select count(*),
         count(*) filter (where es_principal),
         max(categoria_codigo) filter (where es_principal)
    into v_total, v_principales, v_principal
    from campana_producto_categoria
   where campana_producto_id = v_id;

  if v_total = 0 and v_legado is not null then
    raise exception 'CM_CATEGORIA_PRINCIPAL_INVALIDA: falta la asociación principal de la campaña.';
  end if;
  if v_total > 0 and (v_principales <> 1 or v_principal is distinct from v_legado) then
    raise exception 'CM_CATEGORIA_PRINCIPAL_INVALIDA: el puente debe tener una sola principal y coincidir con categoria_codigo.';
  end if;
  return null;
end;
$$;

revoke all on function cm__validar_principal_puente() from public, anon, authenticated, service_role;

drop trigger if exists cm_producto_categoria_validar_principal on campana_producto_categoria;
create constraint trigger cm_producto_categoria_validar_principal
after insert or update or delete on campana_producto_categoria
deferrable initially deferred
for each row execute function cm__validar_principal_puente();

-- ----------------------------------------------------------------------------
-- (C) Validación común y wrappers atómicos sobre las RPC C1 vigentes.
-- ----------------------------------------------------------------------------
create or replace function cm__validar_categorias_seleccion(
  p_categoria_codigos text[],
  p_categoria_principal text
)
returns text[]
language plpgsql
security definer
set search_path = public
as $$
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

  -- Estabiliza la decisión activo=true hasta el fin de la transacción para que
  -- una baja concurrente no quede intercalada entre validar y escribir.
  perform 1
    from campana_categoria c
   where c.codigo = any(v_codigos)
   order by c.codigo
   for share;

  if (
    select count(*)
      from campana_categoria c
     where c.codigo = any(v_codigos)
       and c.activo = true
  ) <> v_total then
    raise exception 'CM_CATEGORIA_INACTIVA: todas las categorías deben existir y estar activas.';
  end if;

  return v_codigos;
end;
$$;

comment on function cm__validar_categorias_seleccion(text[], text) is
  'Helper privado: normaliza y valida 1..12 códigos activos, sin duplicados, con principal incluida.';
revoke all on function cm__validar_categorias_seleccion(text[], text) from public, anon, authenticated, service_role;

create function cm_crear_campana_con_categorias(
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
set search_path = public
as $$
declare
  v_resultado jsonb;
  v_id uuid;
  v_codigos text[];
  v_codigo text;
  v_principal text := btrim(coalesce(p_categoria_principal, ''));
begin
  if not tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;
  v_codigos := cm__validar_categorias_seleccion(p_categoria_codigos, v_principal);

  v_resultado := cm_crear_campana(
    p_nombre, v_principal, p_detalle_presentacion, p_imagen_banner_path,
    p_caracteristica_adicional, p_precio_venta, p_hook_largo,
    p_por_que_magandhi, p_sobre_este_producto, p_ficha_tecnica, p_imagenes,
    p_sello_elegido, p_estrella, p_stock_disponible,
    p_aviso_urgencia_activo, p_aviso_urgencia_cantidad, p_etiquetas,
    p_product_id_ref, p_slug, p_tope_escaparate, p_producto_probado,
    p_max_unidades_pedido
  );
  v_id := (v_resultado ->> 'id')::uuid;

  delete from campana_producto_categoria where campana_producto_id = v_id;
  foreach v_codigo in array v_codigos loop
    insert into campana_producto_categoria (
      campana_producto_id, categoria_codigo, es_principal
    ) values (v_id, v_codigo, v_codigo = v_principal);
  end loop;

  return v_resultado;
end;
$$;

comment on function cm_crear_campana_con_categorias(text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean, integer, text[], text) is
  'Wrapper atómico de cm_crear_campana C1: valida categorías, conserva categoria_codigo como principal y reemplaza el puente en la misma transacción.';

create function cm_editar_campana_con_categorias(
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
set search_path = public
as $$
declare
  v_resultado uuid;
  v_codigos text[];
  v_codigo text;
  v_principal text := btrim(coalesce(p_categoria_principal, ''));
begin
  if not tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;
  v_codigos := cm__validar_categorias_seleccion(p_categoria_codigos, v_principal);

  v_resultado := cm_editar_campana(
    p_id, p_nombre, v_principal, p_detalle_presentacion,
    p_imagen_banner_path, p_caracteristica_adicional, p_precio_venta,
    p_hook_largo, p_por_que_magandhi, p_sobre_este_producto,
    p_ficha_tecnica, p_imagenes, p_sello_elegido, p_estrella,
    p_stock_disponible, p_aviso_urgencia_activo,
    p_aviso_urgencia_cantidad, p_etiquetas, p_product_id_ref, p_slug,
    p_tope_escaparate, p_producto_probado, p_max_unidades_pedido
  );

  delete from campana_producto_categoria where campana_producto_id = p_id;
  foreach v_codigo in array v_codigos loop
    insert into campana_producto_categoria (
      campana_producto_id, categoria_codigo, es_principal
    ) values (p_id, v_codigo, v_codigo = v_principal);
  end loop;

  return v_resultado;
end;
$$;

comment on function cm_editar_campana_con_categorias(uuid, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean, integer, text[], text) is
  'Wrapper atómico de cm_editar_campana C1: valida categorías, conserva categoria_codigo como principal y reemplaza el puente en la misma transacción.';

revoke all on function cm_crear_campana_con_categorias(text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean, integer, text[], text) from public, anon, authenticated;
grant execute on function cm_crear_campana_con_categorias(text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean, integer, text[], text) to authenticated, service_role;
revoke all on function cm_editar_campana_con_categorias(uuid, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean, integer, text[], text) from public, anon, authenticated;
grant execute on function cm_editar_campana_con_categorias(uuid, text, text, text, text, bigint, text, text, text, jsonb, jsonb, boolean, boolean, integer, boolean, integer, text[], uuid, text, integer, boolean, integer, text[], text) to authenticated, service_role;

-- ----------------------------------------------------------------------------
-- (D) Listas blancas públicas. Sin colores históricos ni metadatos internos.
-- ----------------------------------------------------------------------------
create or replace view categorias_publicas as
select
  codigo,
  nombre,
  icono_codigo,
  descripcion,
  orden
from campana_categoria
where parent_codigo is null
  and activo = true
  and visible_tienda = true;

comment on view categorias_publicas is
  'Lista blanca anónima de categorías principales activas y visibles. La presentación usa siempre la paleta fija MAGANDHI; no expone colores históricos ni controles internos.';
revoke all on categorias_publicas from public;
grant select on categorias_publicas to anon, authenticated, service_role;

-- Misma forma C1 de 24 columnas; se agregan al FINAL categoria_codigos y
-- categorias. Los tres colores heredados ahora devuelven constantes MAGANDHI.
create or replace view catalogo_publico as
select
  cp.id,
  cp.nombre,
  cp.slug,
  case when cc.codigo is not null then cp.categoria_codigo end as categoria_codigo,
  cc.nombre        as categoria_nombre,
  '#C28A3A'::text  as color_fuerte,
  '#D9AE6E'::text  as color_claro,
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
from campana_producto cp
left join campana_categoria cc
  on cc.codigo = cp.categoria_codigo
 and cc.activo = true
 and cc.visible_tienda = true
left join productos p on p.id = cp.product_id_ref
left join (select venta_proveedor_habilitada
             from dropshipping_config where id = 1) dcfg on true
cross join lateral (
  select ventas_max_comprable_campana(cp.id) as max_comprable
) mx
cross join lateral (
  with seleccion as (
    select pcc.categoria_codigo as codigo, pcc.es_principal
      from campana_producto_categoria pcc
     where pcc.campana_producto_id = cp.id
    union all
    select cp.categoria_codigo, true
     where cp.categoria_codigo is not null
       and not exists (
         select 1 from campana_producto_categoria pcc
          where pcc.campana_producto_id = cp.id
       )
  ), expandida as (
    select s.codigo, true as seleccionada, s.es_principal
      from seleccion s
    union all
    select c.parent_codigo, false, false
      from seleccion s
      join campana_categoria c on c.codigo = s.codigo
     where c.parent_codigo is not null
  ), consol as (
    select e.codigo,
           bool_or(e.seleccionada) as seleccionada,
           bool_or(e.es_principal) as es_principal
      from expandida e
     group by e.codigo
  )
  select
    coalesce(
      array_agg(c.codigo order by c.orden, c.codigo),
      '{}'::text[]
    ) as categoria_codigos,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'codigo', c.codigo,
          'nombre', c.nombre,
          'parent_codigo', c.parent_codigo,
          'icono_codigo', c.icono_codigo,
          'descripcion', c.descripcion,
          'seleccionada', x.seleccionada,
          'principal', x.es_principal
        ) order by c.orden, c.codigo
      ),
      '[]'::jsonb
    ) as categorias
  from consol x
  join campana_categoria c on c.codigo = x.codigo
   and c.activo = true
   and c.visible_tienda = true
) cats
where cp.publicado = true
  and cp.activo = true
  and (
    coalesce(p.origen, 'propio') = 'propio'
    or coalesce(dcfg.venta_proveedor_habilitada, false)
  );

comment on view catalogo_publico is
  'Categorías oficiales · conserva las 24 columnas C1 y agrega al final categoria_codigos y categorias. Los códigos incluyen selección y ancestros visibles (belleza encuentra cabello). El JSON es lista blanca segura. Los colores compatibles siempre son la paleta fija MAGANDHI; no expone colores históricos, stock, piso, reservas, origen, proveedor ni ids externos.';

grant select on catalogo_publico to anon, authenticated, service_role;

commit;
