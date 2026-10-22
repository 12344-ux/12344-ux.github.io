-- ============================================================================
-- MAGANDHI · Campañas · categorías temporales manuales
-- ----------------------------------------------------------------------------
-- Agrega temporadas manuales (Navidad, Día de la Madre, etc.) sin convertirlas
-- en la clasificación principal de una campaña. Ocultar una temporada solo la
-- retira de las superficies públicas: no despublica productos, no altera stock
-- y no borra las asociaciones, que pueden reutilizarse al reactivarla.
-- ============================================================================

begin;
set local search_path = public, pg_catalog;
set local statement_timeout = '20s';
set local lock_timeout = '5s';

-- Conserva el orden de locks de la migración que creó la clasificación múltiple.
-- Si hay una escritura comercial activa, toda la forward falla limpia en lugar
-- de esperar indefinidamente o aplicar solo una parte.
lock table public.campana_producto in share row exclusive mode;
lock table public.campana_categoria in access exclusive mode;

alter table public.campana_categoria
  add column if not exists tipo text not null default 'permanente';

do $constraints$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'campana_categoria_tipo_chk'
       and conrelid = 'public.campana_categoria'::regclass
  ) then
    alter table public.campana_categoria
      add constraint campana_categoria_tipo_chk
      check (tipo in ('permanente', 'temporal'));
  end if;

  if not exists (
    select 1
      from pg_constraint
     where conname = 'campana_categoria_oficial_permanente_chk'
       and conrelid = 'public.campana_categoria'::regclass
  ) then
    alter table public.campana_categoria
      add constraint campana_categoria_oficial_permanente_chk
      check (not es_oficial or tipo = 'permanente');
  end if;
end
$constraints$;

comment on column public.campana_categoria.tipo is
  'permanente = clasificación estable y elegible como principal; temporal = colección estacional secundaria que puede ocultarse sin quitar productos de la tienda.';

-- Primera temporada acordada. El código permanece estable entre años para que
-- sus asociaciones y su URL se puedan reutilizar. El orden 5 la deja antes de
-- las categorías oficiales cuando está visible.
insert into public.campana_categoria (
  codigo, nombre, color_fuerte, color_claro, color_sombra, orden,
  icono_codigo, descripcion, activo, visible_tienda, es_oficial, tipo
) values (
  'navidad', 'Navidad', '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 5,
  'regalo', 'Regalos y detalles para compartir esta Navidad.',
  true, true, false, 'temporal'
)
on conflict (codigo) do update
set nombre = excluded.nombre,
    icono_codigo = excluded.icono_codigo,
    descripcion = excluded.descripcion,
    activo = true,
    visible_tienda = true,
    es_oficial = false,
    tipo = 'temporal',
    orden = least(public.campana_categoria.orden, excluded.orden);

-- La categoría principal es la identidad estable/legada del producto. Una
-- temporal puede acompañarla, visible u oculta, pero nunca reemplazarla.
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
    return null;
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
  if v_total > 0 and not exists (
    select 1
      from public.campana_categoria c
     where c.codigo = v_principal
       and c.tipo = 'permanente'
  ) then
    raise exception 'CM_CATEGORIA_TEMPORAL_PRINCIPAL: una categoría temporal solo puede ser secundaria.';
  end if;
  return null;
end;
$fn$;
revoke all on function public.cm__validar_principal_puente()
  from public, anon, authenticated, service_role;

-- Protege también el catálogo: futuras migraciones o puertas privilegiadas no
-- pueden convertir en temporal una categoría que ya sea principal. La UI no
-- expone este UPDATE, pero el invariante queda estructuralmente cerrado.
create or replace function public.cm__proteger_tipo_categoria()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $fn$
begin
  if new.tipo = 'temporal' and old.tipo is distinct from new.tipo and (
    exists (
      select 1
        from public.campana_producto_categoria pcc
       where pcc.categoria_codigo = old.codigo
         and pcc.es_principal
    )
    or exists (
      select 1
        from public.campana_producto cp
       where cp.categoria_codigo = old.codigo
    )
  ) then
    raise exception 'CM_CATEGORIA_TEMPORAL_PRINCIPAL: una categoría principal no puede convertirse en temporal.';
  end if;
  return new;
end;
$fn$;
revoke all on function public.cm__proteger_tipo_categoria()
  from public, anon, authenticated, service_role;

drop trigger if exists cm_categoria_proteger_tipo on public.campana_categoria;
create trigger cm_categoria_proteger_tipo
before update of tipo on public.campana_categoria
for each row execute function public.cm__proteger_tipo_categoria();

-- La ruta compatible C1 tampoco puede usar una temporada como principal,
-- incluso si una campaña aún está en borrador; el constraint diferido anterior
-- cubre inserciones y la sincronización del puente, y este gate da un error
-- temprano al editar una campaña publicada.
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
         and c.tipo = 'permanente'
    )
  ) then
    raise exception 'CM_CATEGORIA_PUBLICADA_INVALIDA: una campaña publicada requiere una categoría principal permanente, activa y visible.';
  end if;
  return new;
end;
$fn$;
revoke all on function public.cm__validar_categoria_publicada_legacy()
  from public, anon, authenticated, service_role;

-- Permite conservar una temporal secundaria aunque esté oculta. Las categorías
-- permanentes elegidas siguen requiriendo visibilidad; la principal, además,
-- debe ser permanente. Los locks serializan guardados con el interruptor de
-- temporada sin tocar la campaña ni su publicación.
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
       and (c.visible_tienda or c.tipo = 'temporal')
  ) <> v_total then
    raise exception 'CM_CATEGORIA_NO_PUBLICA: las categorías permanentes deben estar activas y visibles; una temporal puede conservarse oculta.';
  end if;

  if not exists (
    select 1
      from public.campana_categoria c
     where c.codigo = v_principal
       and c.activo
       and c.visible_tienda
       and c.tipo = 'permanente'
  ) then
    raise exception 'CM_CATEGORIA_TEMPORAL_PRINCIPAL: marca una categoría permanente y visible como principal.';
  end if;

  return v_codigos;
end;
$fn$;

comment on function public.cm__validar_categorias_seleccion(text[], text) is
  'Helper privado: valida 1..12 categorías activas, conserva temporales secundarias ocultas y exige una principal permanente y visible.';
revoke all on function public.cm__validar_categorias_seleccion(text[], text)
  from public, anon, authenticated, service_role;

-- Metadato público mínimo para que el inicio pueda anteponer temporadas
-- visibles. Se agrega al final y se conserva la forma previa de las columnas.
create or replace view public.categorias_publicas as
select
  c.codigo,
  c.nombre,
  c.icono_codigo,
  c.descripcion,
  c.orden,
  c.es_oficial,
  c.tipo
from public.campana_categoria c
where c.activo
  and c.visible_tienda;

comment on view public.categorias_publicas is
  'Lista blanca de categorías activas y visibles. Expone tipo únicamente para priorizar temporadas en navegación; nunca controles internos, colores ni asociaciones ocultas.';
revoke all on table public.categorias_publicas
  from public, anon, authenticated, service_role;
grant select on table public.categorias_publicas
  to anon, authenticated, service_role;

-- Reexpresa el alta permanente con la fila pública ampliada. La firma y su
-- comportamiento anterior permanecen intactos para todos los clientes.
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

  lock table public.campana_categoria in share row exclusive mode;
  if exists (select 1 from public.campana_categoria c where c.codigo = v_codigo) then
    raise exception 'CM_CATEGORIA_CODIGO_EXISTE: ya existe una categoría con el código "%".', v_codigo;
  end if;

  select coalesce(max(c.orden), 0) + 10
    into v_orden
    from public.campana_categoria c;

  begin
    insert into public.campana_categoria (
      codigo, nombre, color_fuerte, color_claro, color_sombra, orden,
      icono_codigo, descripcion, activo, visible_tienda, es_oficial, tipo
    ) values (
      v_codigo, v_nombre, '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', v_orden,
      v_icono, v_descripcion, true, true, false, 'permanente'
    );
  exception when unique_violation then
    raise exception 'CM_CATEGORIA_CODIGO_EXISTE: ya existe una categoría con el código "%".', v_codigo;
  end;

  return query
  select c.codigo, c.nombre, c.icono_codigo, c.descripcion, c.orden,
         c.es_oficial, c.tipo
    from public.categorias_publicas c
   where c.codigo = v_codigo;
end;
$fn$;

comment on function public.cm_crear_categoria(text, text, text) is
  'Campañas · alta autenticada de categoría permanente, activa y visible. Conserva la firma histórica y devuelve la fila pública ampliada con tipo.';
revoke all on function public.cm_crear_categoria(text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.cm_crear_categoria(text, text, text)
  to authenticated;

-- Alta temporal versionada: reutiliza todas las validaciones del alta estable y
-- convierte la nueva fila dentro de la misma transacción. Las temporadas nuevas
-- se ordenan antes de las permanentes en el catálogo público.
create or replace function public.cm_crear_categoria_temporal(
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
  v_codigo text;
  v_orden integer;
begin
  if not public.tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;

  select creada.codigo
    into v_codigo
    from public.cm_crear_categoria($1, $2, $3) creada;

  select coalesce(min(c.orden), 10) - 10
    into v_orden
    from public.campana_categoria c
   where c.tipo = 'permanente'
     and c.activo;

  update public.campana_categoria
     set tipo = 'temporal',
         orden = v_orden
   where codigo = v_codigo;

  return query
  select c.codigo, c.nombre, c.icono_codigo, c.descripcion, c.orden,
         c.es_oficial, c.tipo
    from public.categorias_publicas c
   where c.codigo = v_codigo;
end;
$fn$;

comment on function public.cm_crear_categoria_temporal(text, text, text) is
  'Campañas · crea una temporada secundaria, activa y visible. Nunca la asigna a productos ni permite usarla como principal.';
revoke all on function public.cm_crear_categoria_temporal(text, text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.cm_crear_categoria_temporal(text, text, text)
  to authenticated;

-- Interruptor manual. Cambia únicamente la exposición de la categoría; las
-- campañas, productos y filas del puente quedan exactamente como estaban.
create or replace function public.cm_configurar_categoria_temporal(
  p_codigo text,
  p_visible_tienda boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_categoria public.campana_categoria%rowtype;
begin
  if not public.tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;
  if p_visible_tienda is null then
    raise exception 'CM_TEMPORADA_VISIBILIDAD_INVALIDA: indica si la temporada debe estar visible.';
  end if;

  select *
    into v_categoria
    from public.campana_categoria c
   where c.codigo = btrim(coalesce(p_codigo, ''))
   for update;

  if not found then
    raise exception 'CM_CATEGORIA_NO_EXISTE: la categoría indicada no existe.';
  end if;
  if v_categoria.tipo <> 'temporal' then
    raise exception 'CM_CATEGORIA_NO_TEMPORAL: solo las categorías temporales usan este interruptor.';
  end if;
  if not v_categoria.activo then
    raise exception 'CM_CATEGORIA_INACTIVA: una categoría inactiva no puede publicarse como temporada.';
  end if;

  update public.campana_categoria
     set visible_tienda = p_visible_tienda
   where codigo = v_categoria.codigo;

  return jsonb_build_object(
    'codigo', v_categoria.codigo,
    'visible_tienda', p_visible_tienda,
    'asociaciones', (
      select count(*)
        from public.campana_producto_categoria pcc
       where pcc.categoria_codigo = v_categoria.codigo
    )
  );
end;
$fn$;

comment on function public.cm_configurar_categoria_temporal(text, boolean) is
  'Campañas · muestra u oculta manualmente una temporada sin borrar asociaciones ni modificar la publicación de sus productos.';
revoke all on function public.cm_configurar_categoria_temporal(text, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.cm_configurar_categoria_temporal(text, boolean)
  to authenticated;

-- Gates estructurales: la temporada inicial existe, ninguna temporada quedó
-- como principal y las nuevas puertas conservan ACL exclusivamente interna.
do $postflight$
declare
  v_columnas text[];
begin
  if not exists (
    select 1
      from public.campana_categoria c
     where c.codigo = 'navidad'
       and c.tipo = 'temporal'
       and c.activo
       and c.visible_tienda
       and not c.es_oficial
  ) then
    raise exception 'CM_TEMPORADA_NAVIDAD_INVALIDA';
  end if;

  if exists (
    select 1
      from public.campana_producto_categoria pcc
      join public.campana_categoria c on c.codigo = pcc.categoria_codigo
     where pcc.es_principal
       and c.tipo = 'temporal'
  ) then
    raise exception 'CM_TEMPORADA_PRINCIPAL_EXISTENTE';
  end if;

  select array_agg(cols.column_name::text order by cols.ordinal_position)
    into v_columnas
    from information_schema.columns cols
   where cols.table_schema = 'public'
     and cols.table_name = 'categorias_publicas';
  if v_columnas is distinct from array[
    'codigo', 'nombre', 'icono_codigo', 'descripcion', 'orden', 'es_oficial', 'tipo'
  ]::text[] then
    raise exception 'CM_CATEGORIAS_PUBLICAS_FORMA_INVALIDA';
  end if;

  if has_function_privilege('anon', 'public.cm_crear_categoria_temporal(text,text,text)', 'execute')
     or has_function_privilege('anon', 'public.cm_configurar_categoria_temporal(text,boolean)', 'execute')
     or has_function_privilege('service_role', 'public.cm_crear_categoria_temporal(text,text,text)', 'execute')
     or has_function_privilege('service_role', 'public.cm_configurar_categoria_temporal(text,boolean)', 'execute')
     or not has_function_privilege('authenticated', 'public.cm_crear_categoria_temporal(text,text,text)', 'execute')
     or not has_function_privilege('authenticated', 'public.cm_configurar_categoria_temporal(text,boolean)', 'execute') then
    raise exception 'CM_TEMPORADAS_ACL_INVALIDA';
  end if;
end
$postflight$;

commit;
