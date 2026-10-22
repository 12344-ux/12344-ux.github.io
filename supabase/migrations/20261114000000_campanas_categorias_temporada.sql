-- ============================================================================
-- MAGANDHI · CAMPANAS · CATEGORIAS DE TEMPORADA
-- ----------------------------------------------------------------------------
-- Forward posterior a Categorias oficiales + Sistema Nervioso SN1.
-- Añade ventanas civiles Colombia, fijacion editorial y gestion autenticada.
-- Una categoria temporal nunca puede ser principal; al vencer solo desaparece
-- la faceta publica y sus productos conservan su categoria permanente.
-- ============================================================================

begin;
set local search_path = public, pg_catalog;
set local statement_timeout = '120s';
set local lock_timeout = '5s';

select pg_advisory_xact_lock(hashtextextended('magandhi-categorias-temporada-v1', 0));

-- Preflight: esta forward solo se instala sobre el baseline ya publicado.
do $preflight$
begin
  if to_regclass('public.campana_categoria') is null
     or to_regclass('public.campana_producto') is null
     or to_regclass('public.campana_producto_categoria') is null
     or to_regclass('public.categorias_publicas') is null
     or to_regclass('public.catalogo_publico') is null
     or to_regprocedure('public.cm__validar_categorias_seleccion(text[],text)') is null
     or to_regprocedure('public.cm_crear_categoria(text,text,text)') is null then
    raise exception using
      errcode = 'P0001',
      message = 'CM_TEMPORADA_REQUIERE_20261111000000';
  end if;
end;
$preflight$;

lock table public.campana_categoria in share row exclusive mode;
lock table public.campana_producto_categoria in share row exclusive mode;
lock table public.campana_producto in share row exclusive mode;

alter table public.campana_categoria
  add column if not exists tipo text not null default 'permanente',
  add column if not exists visible_desde date,
  add column if not exists visible_hasta date,
  add column if not exists fijada_primera boolean not null default false;

do $constraints$
begin
  if exists (
    select 1 from public.campana_categoria c
     where c.orden not between -1000 and 1000000
  ) then
    raise exception 'CM_CATEGORIA_ORDEN_EXISTENTE_INVALIDO';
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'campana_categoria_orden_chk'
       and conrelid = 'public.campana_categoria'::regclass
  ) then
    alter table public.campana_categoria
      add constraint campana_categoria_orden_chk
      check (orden between -1000 and 1000000);
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'campana_categoria_tipo_chk'
       and conrelid = 'public.campana_categoria'::regclass
  ) then
    alter table public.campana_categoria
      add constraint campana_categoria_tipo_chk
      check (tipo in ('permanente', 'temporada'));
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'campana_categoria_temporada_fechas_chk'
       and conrelid = 'public.campana_categoria'::regclass
  ) then
    alter table public.campana_categoria
      add constraint campana_categoria_temporada_fechas_chk
      check (
        (tipo = 'permanente'
          and visible_desde is null
          and visible_hasta is null
          and not fijada_primera)
        or
        (tipo = 'temporada'
          and visible_desde is not null
          and visible_hasta is not null
          and visible_hasta >= visible_desde)
      );
  end if;
end;
$constraints$;

comment on column public.campana_categoria.tipo is
  'Permanente o temporada. Una temporada solo puede asociarse como secundaria.';
comment on column public.campana_categoria.visible_desde is
  'Primer dia civil Colombia en que una categoria de temporada se expone publicamente, inclusivo.';
comment on column public.campana_categoria.visible_hasta is
  'Ultimo dia civil Colombia en que una categoria de temporada se expone publicamente, inclusivo.';
comment on column public.campana_categoria.fijada_primera is
  'Si es true, la categoria de temporada vigente antecede al orden editorial publico. No personaliza categorias.';

create or replace function public.cm__categoria_estado(
  p_activo boolean,
  p_visible_tienda boolean,
  p_tipo text,
  p_visible_desde date,
  p_visible_hasta date
)
returns text
language sql
stable
security definer
set search_path = pg_catalog
as $fn$
  select case
    when not coalesce(p_activo, false) then 'inactiva'
    when not coalesce(p_visible_tienda, false) then 'oculta'
    when p_tipo = 'permanente' then 'permanente'
    when (statement_timestamp() at time zone 'America/Bogota')::date < p_visible_desde
      then 'programada'
    when (statement_timestamp() at time zone 'America/Bogota')::date > p_visible_hasta
      then 'finalizada'
    else 'vigente'
  end;
$fn$;

revoke all on function public.cm__categoria_estado(boolean,boolean,text,date,date)
  from public, anon, authenticated, service_role;

-- Auditoria de cambios administrativos. No se borra historia.
create table public.campana_categoria_bitacora (
  id bigint generated always as identity primary key,
  categoria_codigo text not null,
  registrado_en timestamptz not null default statement_timestamp(),
  actor_uid uuid,
  razon text not null,
  antes jsonb,
  despues jsonb not null,
  constraint campana_categoria_bitacora_razon_chk check (
    razon = btrim(razon) and length(razon) between 3 and 240
  )
);

comment on table public.campana_categoria_bitacora is
  'Campanas · historial append-only de altas y cambios de categorias, incluidas temporadas y ventanas.';

alter table public.campana_categoria_bitacora enable row level security;
drop policy if exists campana_categoria_bitacora_select_marketing
  on public.campana_categoria_bitacora;
create policy campana_categoria_bitacora_select_marketing
  on public.campana_categoria_bitacora
  for select to authenticated
  using (public.tiene_acceso_marketing());
revoke all on table public.campana_categoria_bitacora
  from public, anon, authenticated, service_role;
grant select on table public.campana_categoria_bitacora to authenticated;

-- Un codigo Navidad preexistente solo puede adoptarse si nunca fue principal.
do $navidad_preflight$
begin
  if exists (
    select 1 from public.campana_producto cp
     where cp.categoria_codigo = 'navidad'
  ) or exists (
    select 1 from public.campana_producto_categoria pcc
     where pcc.categoria_codigo = 'navidad' and pcc.es_principal
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'CM_NAVIDAD_EXISTENTE_NO_PUEDE_SER_PRINCIPAL';
  end if;
end;
$navidad_preflight$;

do $sembrar_navidad$
declare
  v_antes jsonb;
begin
  select to_jsonb(c) into v_antes
    from public.campana_categoria c
   where c.codigo = 'navidad';

  insert into public.campana_categoria (
    codigo, nombre, color_fuerte, color_claro, color_sombra, orden,
    icono_codigo, descripcion, activo, visible_tienda, es_oficial,
    tipo, visible_desde, visible_hasta, fijada_primera
  ) values (
    'navidad', 'Navidad', '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', 0,
    'regalo', 'Regalos y detalles para compartir en Navidad.', true, true, false,
    'temporada', date '2026-10-22', date '2027-01-07', true
  )
  on conflict (codigo) do update
  set nombre = excluded.nombre,
      orden = excluded.orden,
      icono_codigo = excluded.icono_codigo,
      descripcion = excluded.descripcion,
      activo = excluded.activo,
      visible_tienda = excluded.visible_tienda,
      tipo = excluded.tipo,
      visible_desde = excluded.visible_desde,
      visible_hasta = excluded.visible_hasta,
      fijada_primera = excluded.fijada_primera
  where not public.campana_categoria.es_oficial;

  insert into public.campana_categoria_bitacora (
    categoria_codigo, actor_uid, razon, antes, despues
  )
  select c.codigo, auth.uid(), 'instalacion_categoria_navidad_2026', v_antes,
         jsonb_build_object(
           'nombre', c.nombre, 'tipo', c.tipo,
           'visible_desde', c.visible_desde, 'visible_hasta', c.visible_hasta,
           'fijada_primera', c.fijada_primera,
           'activo', c.activo, 'visible_tienda', c.visible_tienda, 'orden', c.orden
         )
    from public.campana_categoria c
   where c.codigo = 'navidad';
end;
$sembrar_navidad$;

-- Defensa de tabla: ninguna operacion privilegiada puede convertir, ocultar o
-- desactivar una categoria principal, ni solapar dos temporadas fijadas.
create or replace function public.cm__proteger_categoria_temporada()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $fn$
begin
  if (new.tipo = 'temporada' or not new.activo or not new.visible_tienda)
     and exists (
       select 1 from public.campana_producto_categoria pcc
        where pcc.categoria_codigo = new.codigo and pcc.es_principal
       union all
       select 1 from public.campana_producto cp
        where cp.categoria_codigo = new.codigo
     ) then
    raise exception 'CM_CATEGORIA_PRINCIPAL_EN_USO: reasigna primero las campañas a una categoria permanente.';
  end if;

  if new.tipo = 'temporada' and new.fijada_primera
     and new.activo and new.visible_tienda and exists (
       select 1 from public.campana_categoria c
        where c.codigo <> new.codigo
          and c.tipo = 'temporada' and c.fijada_primera
          and c.activo and c.visible_tienda
          and daterange(c.visible_desde, c.visible_hasta, '[]')
              && daterange(new.visible_desde, new.visible_hasta, '[]')
     ) then
    raise exception 'CM_CATEGORIA_FIJADA_SOLAPADA: ya existe otra temporada fijada en esas fechas.';
  end if;
  return new;
end;
$fn$;
revoke all on function public.cm__proteger_categoria_temporada()
  from public, anon, authenticated, service_role;

drop trigger if exists cm_categoria_proteger_temporada
  on public.campana_categoria;
create trigger cm_categoria_proteger_temporada
before insert or update of tipo, activo, visible_tienda, visible_desde, visible_hasta, fijada_primera
on public.campana_categoria
for each row execute function public.cm__proteger_categoria_temporada();

-- La principal legada siempre debe ser permanente.
create or replace function public.cm__validar_categoria_publicada_legacy()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $fn$
begin
  if new.categoria_codigo is not null and not exists (
    select 1
      from public.campana_categoria c
     where c.codigo = new.categoria_codigo
       and c.tipo = 'permanente'
  ) then
    raise exception 'CM_CATEGORIA_PRINCIPAL_TEMPORAL: una categoria de temporada solo puede ser secundaria.';
  end if;

  if new.publicado and (
    new.categoria_codigo is null
    or not exists (
      select 1
        from public.campana_categoria c
       where c.codigo = new.categoria_codigo
         and c.tipo = 'permanente'
         and c.activo
         and c.visible_tienda
    )
  ) then
    raise exception 'CM_CATEGORIA_PUBLICADA_INVALIDA: una campaña publicada requiere una categoria principal permanente, activa y visible.';
  end if;
  return new;
end;
$fn$;
revoke all on function public.cm__validar_categoria_publicada_legacy()
  from public, anon, authenticated, service_role;

-- El constraint diferido del puente conserva una sola principal, igual al campo
-- legado, y ahora impide que una temporada sea principal incluso en borrador.
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
  if not found then return null; end if;

  select count(*),
         count(*) filter (where pcc.es_principal),
         max(pcc.categoria_codigo) filter (where pcc.es_principal)
    into v_total, v_principales, v_principal
    from public.campana_producto_categoria pcc
   where pcc.campana_producto_id = v_id;

  if v_total = 0 and v_legado is not null then
    raise exception 'CM_CATEGORIA_PRINCIPAL_INVALIDA: falta la asociacion principal de la campaña.';
  end if;
  if v_total > 0 and (v_principales <> 1 or v_principal is distinct from v_legado) then
    raise exception 'CM_CATEGORIA_PRINCIPAL_INVALIDA: el puente debe tener una sola principal y coincidir con categoria_codigo.';
  end if;
  if v_principal is not null and exists (
    select 1 from public.campana_categoria c
     where c.codigo = v_principal and c.tipo = 'temporada'
  ) then
    raise exception 'CM_CATEGORIA_PRINCIPAL_TEMPORAL: una categoria de temporada solo puede ser secundaria.';
  end if;
  return null;
end;
$fn$;
revoke all on function public.cm__validar_principal_puente()
  from public, anon, authenticated, service_role;

-- Programadas, vigentes y finalizadas pueden conservarse como secundarias para
-- reutilizar la clasificacion el siguiente año. La principal siempre es una
-- categoria permanente activa y visible.
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
    raise exception 'CM_CATEGORIAS_REQUERIDAS: elige al menos una categoria.';
  end if;
  if exists (select 1 from unnest(p_categoria_codigos) x where x is null or btrim(x) = '') then
    raise exception 'CM_CATEGORIA_INVALIDA: los codigos no pueden estar vacios.';
  end if;

  select coalesce(array_agg(btrim(x) order by ord), '{}'::text[])
    into v_codigos
    from unnest(p_categoria_codigos) with ordinality t(x, ord);
  v_total := cardinality(v_codigos);

  if v_total < 1 then raise exception 'CM_CATEGORIAS_REQUERIDAS: elige al menos una categoria.'; end if;
  if v_total > 12 then raise exception 'CM_CATEGORIAS_MAXIMO: elige como maximo 12 categorias.'; end if;
  if (select count(distinct x) from unnest(v_codigos) x) <> v_total then
    raise exception 'CM_CATEGORIAS_DUPLICADAS: no repitas categorias.';
  end if;
  if v_principal = '' or not (v_principal = any(v_codigos)) then
    raise exception 'CM_CATEGORIA_PRINCIPAL_INVALIDA: la principal debe estar incluida en la seleccion.';
  end if;

  perform 1 from public.campana_categoria c
   where c.codigo = any(v_codigos)
   order by c.codigo for share;

  if (
    select count(*) from public.campana_categoria c
     where c.codigo = any(v_codigos) and c.activo and c.visible_tienda
  ) <> v_total then
    raise exception 'CM_CATEGORIA_NO_PUBLICA: todas las categorias deben existir y estar activas y habilitadas.';
  end if;

  if not exists (
    select 1 from public.campana_categoria c
     where c.codigo = v_principal
       and c.tipo = 'permanente'
       and c.activo
       and c.visible_tienda
  ) then
    raise exception 'CM_CATEGORIA_PRINCIPAL_TEMPORAL: elige una categoria permanente como principal.';
  end if;

  return v_codigos;
end;
$fn$;
revoke all on function public.cm__validar_categorias_seleccion(text[],text)
  from public, anon, authenticated, service_role;

-- Lectura administrativa: incluye categorias fuera de ventana sin exponerlas a
-- anon. La UI puede preparar temporadas y conservar asociaciones finalizadas.
create or replace function public.cm_listar_categorias_admin_v1()
returns table (
  codigo text,
  nombre text,
  icono_codigo text,
  descripcion text,
  orden integer,
  es_oficial boolean,
  tipo text,
  visible_desde date,
  visible_hasta date,
  fijada_primera boolean,
  activo boolean,
  visible_tienda boolean,
  estado text,
  seleccionable boolean,
  principales bigint,
  secundarias bigint
)
language plpgsql
stable
security definer
set search_path = public, pg_catalog
as $fn$
begin
  if not public.tiene_acceso_marketing() then
    raise exception using errcode = '42501', message = 'CM_SIN_ACCESO';
  end if;

  return query
  select c.codigo, c.nombre, c.icono_codigo, c.descripcion, c.orden,
         c.es_oficial, c.tipo, c.visible_desde, c.visible_hasta,
         c.fijada_primera, c.activo, c.visible_tienda,
         public.cm__categoria_estado(c.activo, c.visible_tienda, c.tipo,
                                      c.visible_desde, c.visible_hasta),
         c.activo and c.visible_tienda and (
           c.tipo = 'permanente'
           or (statement_timestamp() at time zone 'America/Bogota')::date <= c.visible_hasta
         ),
         count(*) filter (where pcc.es_principal),
         count(*) filter (where not pcc.es_principal)
    from public.campana_categoria c
    left join public.campana_producto_categoria pcc
      on pcc.categoria_codigo = c.codigo
   group by c.codigo, c.nombre, c.icono_codigo, c.descripcion, c.orden,
            c.es_oficial, c.tipo, c.visible_desde, c.visible_hasta,
            c.fijada_primera, c.activo, c.visible_tienda
   order by case when c.tipo = 'temporada' and c.fijada_primera then 0 else 1 end,
            c.orden, c.codigo;
end;
$fn$;

revoke all on function public.cm_listar_categorias_admin_v1()
  from public, anon, authenticated, service_role;
grant execute on function public.cm_listar_categorias_admin_v1() to authenticated;

-- Alta/edicion unificada. El codigo se deriva solo al crear y es inmutable.
create or replace function public.cm_guardar_categoria_v1(
  p_codigo text,
  p_nombre text,
  p_descripcion text,
  p_icono_codigo text,
  p_orden integer,
  p_tipo text,
  p_visible_desde date,
  p_visible_hasta date,
  p_fijada_primera boolean,
  p_activo boolean,
  p_visible_tienda boolean,
  p_razon text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_catalog
as $fn$
declare
  v_creando boolean := nullif(btrim(coalesce(p_codigo, '')), '') is null;
  v_codigo text := nullif(lower(btrim(coalesce(p_codigo, ''))), '');
  v_nombre text := btrim(coalesce(p_nombre, ''));
  v_descripcion text := btrim(coalesce(p_descripcion, ''));
  v_icono text := lower(btrim(coalesce(p_icono_codigo, '')));
  v_tipo text := lower(btrim(coalesce(p_tipo, 'permanente')));
  v_orden integer := p_orden;
  v_activo boolean := coalesce(p_activo, true);
  v_visible boolean := coalesce(p_visible_tienda, true);
  v_fijada boolean := coalesce(p_fijada_primera, false);
  v_razon text := btrim(coalesce(p_razon, ''));
  v_antes jsonb;
  v_es_oficial boolean := false;
  v_existe boolean := false;
begin
  if not public.tiene_acceso_marketing() then
    raise exception using errcode = '42501', message = 'CM_SIN_ACCESO';
  end if;
  if length(v_nombre) not between 2 and 80 then raise exception 'CM_CATEGORIA_NOMBRE_INVALIDO'; end if;
  if length(v_descripcion) not between 1 and 240 then raise exception 'CM_CATEGORIA_DESCRIPCION_INVALIDA'; end if;
  if v_icono <> all(array[
    'tecnologia','moda','hogar','deportes','belleza','accesorios','mascotas',
    'jugueteria','regalo','bienestar','oficina','viaje','bebes','alimentos','coleccion'
  ]::text[]) then raise exception 'CM_CATEGORIA_ICONO_INVALIDO'; end if;
  if v_tipo not in ('permanente','temporada') then raise exception 'CM_CATEGORIA_TIPO_INVALIDO'; end if;
  if v_razon = '' or length(v_razon) not between 3 and 240 then raise exception 'CM_CATEGORIA_RAZON_INVALIDA'; end if;

  if v_tipo = 'permanente' then
    if p_visible_desde is not null or p_visible_hasta is not null or v_fijada then
      raise exception 'CM_CATEGORIA_PERMANENTE_SIN_VENTANA';
    end if;
  elsif p_visible_desde is null or p_visible_hasta is null
        or p_visible_hasta < p_visible_desde then
    raise exception 'CM_CATEGORIA_TEMPORADA_FECHAS_INVALIDAS';
  end if;

  if v_codigo is null then
    v_codigo := translate(lower(v_nombre),
      'áàäâãéèëêíìïîóòöôõúùüûñç',
      'aaaaaeeeeiiiiooooouuuunc');
    v_codigo := regexp_replace(v_codigo, '[^a-z0-9]+', '-', 'g');
    v_codigo := btrim(regexp_replace(v_codigo, '-+', '-', 'g'), '-');
    v_codigo := regexp_replace(left(v_codigo, 64), '-+$', '');
    if v_codigo = '' then raise exception 'CM_CATEGORIA_CODIGO_INVALIDO'; end if;
  elsif v_codigo !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' or length(v_codigo) > 64 then
    raise exception 'CM_CATEGORIA_CODIGO_INVALIDO';
  end if;

  lock table public.campana_categoria in share row exclusive mode;
  select to_jsonb(c), c.es_oficial into v_antes, v_es_oficial
    from public.campana_categoria c where c.codigo = v_codigo;
  v_existe := found;

  if v_creando and v_existe then
    raise exception 'CM_CATEGORIA_CODIGO_EXISTE: ya existe una categoria con ese codigo.';
  end if;
  if not v_creando and not v_existe then
    raise exception 'CM_CATEGORIA_NO_EXISTE';
  end if;
  if v_orden is null then
    select coalesce(max(c.orden), 0) + 10 into v_orden from public.campana_categoria c;
  end if;
  if v_orden not between -1000 and 1000000 then
    raise exception 'CM_CATEGORIA_ORDEN_INVALIDO';
  end if;

  if v_existe and v_es_oficial and v_tipo <> 'permanente' then
    raise exception 'CM_CATEGORIA_OFICIAL_PERMANENTE';
  end if;

  if (v_tipo = 'temporada' or not v_activo or not v_visible) and exists (
    select 1 from public.campana_producto_categoria pcc
     where pcc.categoria_codigo = v_codigo and pcc.es_principal
    union all
    select 1 from public.campana_producto cp
     where cp.categoria_codigo = v_codigo
  ) then
    raise exception 'CM_CATEGORIA_PRINCIPAL_EN_USO: reasigna primero las campañas a una categoria permanente.';
  end if;

  if v_tipo = 'temporada' and v_fijada and v_activo and v_visible and exists (
    select 1 from public.campana_categoria c
     where c.codigo <> v_codigo
       and c.tipo = 'temporada'
       and c.fijada_primera
       and c.activo and c.visible_tienda
       and daterange(c.visible_desde, c.visible_hasta, '[]')
           && daterange(p_visible_desde, p_visible_hasta, '[]')
  ) then
    raise exception 'CM_CATEGORIA_FIJADA_SOLAPADA: ya existe otra temporada fijada en esas fechas.';
  end if;

  if v_creando then
    insert into public.campana_categoria (
      codigo, nombre, color_fuerte, color_claro, color_sombra, orden,
      icono_codigo, descripcion, activo, visible_tienda, es_oficial,
      tipo, visible_desde, visible_hasta, fijada_primera
    ) values (
      v_codigo, v_nombre, '#C28A3A', '#D9AE6E', 'rgba(194,138,58,.16)', v_orden,
      v_icono, v_descripcion, v_activo, v_visible, false,
      v_tipo, p_visible_desde, p_visible_hasta, v_fijada
    );
  else
    update public.campana_categoria
       set nombre = v_nombre,
           icono_codigo = v_icono,
           descripcion = v_descripcion,
           orden = v_orden,
           activo = v_activo,
           visible_tienda = v_visible,
           tipo = v_tipo,
           visible_desde = p_visible_desde,
           visible_hasta = p_visible_hasta,
           fijada_primera = v_fijada
     where codigo = v_codigo;
  end if;

  insert into public.campana_categoria_bitacora (
    categoria_codigo, actor_uid, razon, antes, despues
  )
  select c.codigo, auth.uid(), v_razon, v_antes, to_jsonb(c)
    from public.campana_categoria c where c.codigo = v_codigo;

  return (
    select jsonb_build_object(
      'codigo', c.codigo, 'nombre', c.nombre,
      'icono_codigo', c.icono_codigo, 'descripcion', c.descripcion,
      'orden', c.orden, 'es_oficial', c.es_oficial, 'tipo', c.tipo,
      'visible_desde', c.visible_desde, 'visible_hasta', c.visible_hasta,
      'fijada_primera', c.fijada_primera, 'activo', c.activo,
      'visible_tienda', c.visible_tienda,
      'estado', public.cm__categoria_estado(c.activo, c.visible_tienda, c.tipo,
                                             c.visible_desde, c.visible_hasta)
    ) from public.campana_categoria c where c.codigo = v_codigo
  );
end;
$fn$;

revoke all on function public.cm_guardar_categoria_v1(text,text,text,text,integer,text,date,date,boolean,boolean,boolean,text)
  from public, anon, authenticated, service_role;
grant execute on function public.cm_guardar_categoria_v1(text,text,text,text,integer,text,date,date,boolean,boolean,boolean,text)
  to authenticated;

-- Compatibilidad: la firma histórica sigue disponible, pero delega en la
-- escritura auditada y no puede eludir las reglas nuevas.
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
  v_resultado jsonb;
begin
  v_resultado := public.cm_guardar_categoria_v1(
    null, nombre, descripcion, icono_codigo, null, 'permanente',
    null, null, false, true, true, 'alta_rpc_legacy_cm_crear_categoria'
  );
  return query
  select c.codigo, c.nombre, c.icono_codigo, c.descripcion, c.orden, c.es_oficial
    from public.categorias_publicas c
   where c.codigo = v_resultado ->> 'codigo';
end;
$fn$;
revoke all on function public.cm_crear_categoria(text,text,text)
  from public, anon, authenticated, service_role;
grant execute on function public.cm_crear_categoria(text,text,text)
  to authenticated;

-- Lista publica efectiva. Conserva exactamente sus seis columnas historicas;
-- orden negativo solo en la proyeccion para temporadas fijadas y vigentes.
create or replace view public.categorias_publicas as
select
  c.codigo,
  c.nombre,
  c.icono_codigo,
  c.descripcion,
  case when c.tipo = 'temporada' and c.fijada_primera
       then -2000000 + c.orden else c.orden end as orden,
  c.es_oficial
from public.campana_categoria c
where c.activo
  and c.visible_tienda
  and (
    c.tipo = 'permanente'
    or (
      c.tipo = 'temporada'
      and (statement_timestamp() at time zone 'America/Bogota')::date
          between c.visible_desde and c.visible_hasta
    )
  );

comment on view public.categorias_publicas is
  'Lista blanca de categorias efectivamente visibles en la fecha civil Colombia. Las temporadas fijadas anteceden al orden editorial; no existe reordenacion personal.';
revoke all on table public.categorias_publicas
  from public, anon, authenticated, service_role;
grant select on table public.categorias_publicas
  to anon, authenticated, service_role;

-- Misma forma publica de 26 columnas. Solo cambia el predicado de categoria:
-- una temporada fuera de ventana deja de proyectarse, pero no retira el producto.
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
 and cc.tipo = 'permanente'
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
         select 1 from public.campana_producto_categoria pcc
          where pcc.campana_producto_id = cp.id
       )
  )
  select
    coalesce(array_agg(c.codigo order by s.es_principal desc, c.orden, c.codigo), '{}'::text[]) as categoria_codigos,
    coalesce(jsonb_agg(jsonb_build_object(
      'codigo', c.codigo, 'nombre', c.nombre, 'icono_codigo', c.icono_codigo,
      'descripcion', c.descripcion, 'es_oficial', c.es_oficial,
      'principal', s.es_principal
    ) order by s.es_principal desc, c.orden, c.codigo), '[]'::jsonb) as categorias
  from seleccion s
  join public.campana_categoria c
    on c.codigo = s.codigo
   and c.activo
   and c.visible_tienda
   and (
     c.tipo = 'permanente'
     or (
       c.tipo = 'temporada'
       and (statement_timestamp() at time zone 'America/Bogota')::date
           between c.visible_desde and c.visible_hasta
     )
   )
) cats
where cp.publicado
  and cp.activo
  and (
    coalesce(p.origen, 'propio') = 'propio'
    or coalesce(dcfg.venta_proveedor_habilitada, false)
  );

comment on view public.catalogo_publico is
  'Categorias de temporada · conserva las 26 columnas publicas. Una temporada fuera de ventana desaparece de la clasificacion sin despublicar el producto; la principal siempre es permanente.';
revoke all on table public.catalogo_publico
  from public, anon, authenticated, service_role;
grant select on table public.catalogo_publico
  to anon, authenticated, service_role;

-- Postflight transaccional: contrato, semilla, invariantes y ACL.
do $postflight$
begin
  if (
    select count(*) from information_schema.columns c
     where c.table_schema = 'public' and c.table_name = 'campana_categoria'
       and c.column_name in ('tipo','visible_desde','visible_hasta','fijada_primera')
  ) <> 4 then
    raise exception 'CM_TEMPORADA_COLUMNAS_INVALIDAS';
  end if;

  if not exists (
    select 1 from public.campana_categoria c
     where c.codigo = 'navidad' and c.nombre = 'Navidad'
       and c.tipo = 'temporada' and c.visible_desde = date '2026-10-22'
       and c.visible_hasta = date '2027-01-07' and c.fijada_primera
       and c.activo and c.visible_tienda and not c.es_oficial
  ) then
    raise exception 'CM_TEMPORADA_NAVIDAD_INVALIDA';
  end if;

  if exists (
    select 1 from public.campana_producto_categoria pcc
    join public.campana_categoria c on c.codigo = pcc.categoria_codigo
    where pcc.es_principal and c.tipo = 'temporada'
  ) or exists (
    select 1 from public.campana_producto cp
    join public.campana_categoria c on c.codigo = cp.categoria_codigo
    where c.tipo = 'temporada'
  ) then
    raise exception 'CM_TEMPORADA_PRINCIPAL_INVALIDA';
  end if;

  if has_function_privilege('anon', 'public.cm_listar_categorias_admin_v1()', 'execute')
     or has_function_privilege('service_role', 'public.cm_listar_categorias_admin_v1()', 'execute')
     or not has_function_privilege('authenticated', 'public.cm_listar_categorias_admin_v1()', 'execute')
     or has_function_privilege('anon', 'public.cm_guardar_categoria_v1(text,text,text,text,integer,text,date,date,boolean,boolean,boolean,text)', 'execute')
     or has_function_privilege('service_role', 'public.cm_guardar_categoria_v1(text,text,text,text,integer,text,date,date,boolean,boolean,boolean,text)', 'execute')
     or not has_function_privilege('authenticated', 'public.cm_guardar_categoria_v1(text,text,text,text,integer,text,date,date,boolean,boolean,boolean,text)', 'execute') then
    raise exception 'CM_TEMPORADA_ACL_INVALIDA';
  end if;
end;
$postflight$;

commit;
