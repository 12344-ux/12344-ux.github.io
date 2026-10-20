-- ============================================================================
-- MAGANDHI · PROMOCIONAR P1 · HISTORIAL INMUTABLE DE SLUGS
-- ----------------------------------------------------------------------------
-- Cierra la permanencia de URLs compartibles:
--   · reserva cada slug que haya pertenecido a una campaña;
--   · impide que otra campaña lo reutilice;
--   · expone únicamente aliases de campañas actualmente públicas;
--   · no cambia catalogo_publico, pagos, carrito, precio ni stock.
--
-- REQUISITO: 20261106000100_campanas_slug_automatico.sql aplicada.
-- FORWARD: una sola vez. Nunca usar como rollback ni reescribir después.
-- ============================================================================

begin;
set local search_path = public, pg_catalog;
set local statement_timeout = '60s';
set local lock_timeout = '5s';

-- El lock de tabla va primero: una escritura normal obtiene ROW EXCLUSIVE antes
-- de entrar al trigger/advisory. Mantener ese orden evita un ciclo de espera.
lock table campana_producto in share row exclusive mode;
select pg_advisory_xact_lock(hashtextextended('campana-producto-slug-v1', 0));

-- Falla cerrado si se intentara aplicar sobre una base anterior al slug P1.
do $$
begin
  if to_regprocedure('public.cm__asignar_slug_automatico()') is null
     or exists (select 1 from campana_producto where slug is null) then
    raise exception using errcode = 'P0001', message = 'P1_REQUIERE_SLUG_AUTOMATICO_COMPLETO';
  end if;
end;
$$;

create table campana_slug_historial (
  slug                 text primary key,
  campana_producto_id  uuid not null references campana_producto(id) on delete restrict,
  registrado_en        timestamptz not null default now(),
  constraint campana_slug_historial_formato
    check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug) between 1 and 180)
);

comment on table campana_slug_historial is
  'Promocionar P1 · reserva inmutable de slugs por campaña. Un slug usado nunca se reasigna a otro producto.';
comment on column campana_slug_historial.slug is
  'Ruta histórica normalizada; PK global y reservada para siempre.';
comment on column campana_slug_historial.campana_producto_id is
  'Campaña propietaria original y única del slug; ON DELETE RESTRICT conserva la ruta.';

create index campana_slug_historial_campana_idx
  on campana_slug_historial (campana_producto_id, registrado_en);

alter table campana_slug_historial enable row level security;
revoke all on table campana_slug_historial
  from public, anon, authenticated, service_role;

-- Todo slug actual nace registrado antes de instalar los triggers.
insert into campana_slug_historial (slug, campana_producto_id)
select slug, id
  from campana_producto
 order by id
on conflict (slug) do update
  set campana_producto_id = excluded.campana_producto_id
where campana_slug_historial.campana_producto_id = excluded.campana_producto_id;

-- El asignador automático también consulta la reserva histórica. Una campaña
-- nueva cuyo nombre coincide con un alias ajeno recibe -2/-3 en vez de fallar;
-- la misma campaña sí puede recuperar uno de sus slugs anteriores.
create or replace function cm__asignar_slug_automatico()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_base text;
  v_candidato text;
  v_sufijo integer := 1;
begin
  if tg_op = 'UPDATE' then
    if new.slug is not distinct from old.slug and new.slug is not null then
      return new;
    end if;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('campana-producto-slug-v1', 0));

  if new.id is null then
    new.id := gen_random_uuid();
  end if;

  v_base := left(cm_normalizar_slug(new.slug), 160);
  if v_base is null then
    v_base := left(cm_normalizar_slug(new.nombre), 160);
  end if;
  if v_base is null then
    v_base := 'campana-' || replace(new.id::text, '-', '');
  end if;

  v_candidato := v_base;
  while exists (
    select 1
      from campana_producto cp
     where cp.slug = v_candidato
       and cp.id is distinct from new.id
  ) or exists (
    select 1
      from campana_slug_historial h
     where h.slug = v_candidato
       and h.campana_producto_id is distinct from new.id
  ) loop
    v_sufijo := v_sufijo + 1;
    v_candidato := v_base || '-' || v_sufijo::text;
  end loop;

  new.slug := v_candidato;
  return new;
end;
$$;

comment on function cm__asignar_slug_automatico() is
  'Campañas P1 · asigna slug normalizado y sufijos bajo lock, evitando slugs actuales e históricos de otra campaña.';
revoke all on function cm__asignar_slug_automatico()
  from public, anon, authenticated, service_role;

-- BEFORE corre después de trg_cm_slug_automatico por orden alfabético. El slug
-- ya viene normalizado/asignado y se comprueba contra toda la historia. No se
-- inserta aquí porque en un INSERT la campaña padre aún no existe para la FK.
create or replace function cm__validar_slug_no_reasignado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dueno uuid;
begin
  -- Las RPC asignan slug en todo UPDATE aunque no cambie. Evitar el lock global
  -- en esa ruta conserva la concurrencia de ediciones ordinarias.
  if tg_op = 'UPDATE' and new.slug is not distinct from old.slug then
    return new;
  end if;

  perform pg_advisory_xact_lock(hashtextextended('campana-producto-slug-v1', 0));

  select campana_producto_id into v_dueno
    from campana_slug_historial
   where slug = new.slug;

  if v_dueno is not null and v_dueno is distinct from new.id then
    raise exception using
      errcode = '23505',
      message = 'CM_SLUG_RESERVADO',
      detail = 'El slug ya perteneció a otra campaña y no puede reasignarse.';
  end if;
  return new;
end;
$$;

comment on function cm__validar_slug_no_reasignado() is
  'Promocionar P1 · trigger interno BEFORE: bloquea la reutilización de cualquier slug histórico por otra campaña.';
revoke all on function cm__validar_slug_no_reasignado()
  from public, anon, authenticated, service_role;

create or replace function cm__registrar_slug_historial()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into campana_slug_historial (slug, campana_producto_id)
  values (new.slug, new.id)
  on conflict (slug) do nothing;
  return new;
end;
$$;

comment on function cm__registrar_slug_historial() is
  'Promocionar P1 · trigger interno AFTER: registra el slug definitivo de cada alta o cambio.';
revoke all on function cm__registrar_slug_historial()
  from public, anon, authenticated, service_role;

drop trigger if exists trg_cm_slug_no_reasignado on campana_producto;
create trigger trg_cm_slug_no_reasignado
before insert or update of slug, nombre on campana_producto
for each row execute function cm__validar_slug_no_reasignado();

drop trigger if exists trg_cm_slug_historial on campana_producto;
create trigger trg_cm_slug_historial
after insert or update of slug on campana_producto
for each row execute function cm__registrar_slug_historial();

-- Lista blanca anónima: solo aliases de una campaña que todavía pertenece al
-- catálogo público. No expone precio, stock, producto interno ni auditoría.
create or replace view campana_slug_alias_publico as
select
  h.campana_producto_id,
  h.slug as slug_anterior,
  cp.slug as slug_actual
from campana_slug_historial h
join campana_producto cp on cp.id = h.campana_producto_id
join catalogo_publico cat on cat.id = cp.id
where h.slug <> cp.slug;

comment on view campana_slug_alias_publico is
  'Promocionar P1 · lista blanca de aliases hacia el slug actual de campañas públicas; sin precio, stock o datos internos.';

grant select on campana_slug_alias_publico to anon, authenticated, service_role;

-- Invariantes de instalación: una fila por campaña actual, sin dueño cruzado y
-- ningún helper convertido en puerta API.
do $$
begin
  if exists (
    select 1
      from campana_producto cp
      left join campana_slug_historial h
        on h.slug = cp.slug and h.campana_producto_id = cp.id
     where h.slug is null
  ) then
    raise exception using errcode = 'P0001', message = 'P1_HISTORIAL_INCOMPLETO';
  end if;

  if has_function_privilege('anon', 'cm__validar_slug_no_reasignado()', 'execute')
     or has_function_privilege('authenticated', 'cm__validar_slug_no_reasignado()', 'execute')
     or has_function_privilege('anon', 'cm__registrar_slug_historial()', 'execute')
     or has_function_privilege('authenticated', 'cm__registrar_slug_historial()', 'execute') then
    raise exception using errcode = 'P0001', message = 'P1_HELPER_EXPUESTO';
  end if;
end;
$$;

commit;
