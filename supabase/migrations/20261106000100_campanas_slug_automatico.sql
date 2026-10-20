-- ============================================================================
-- MAGANDHI · CAMPANAS · SLUG AUTOMÁTICO SERVER-SIDE
-- ----------------------------------------------------------------------------
-- Migración forward independiente de Comercial C5. Preserva literalmente todo
-- slug existente, completa únicamente los NULL de forma determinista y cierra
-- futuras escrituras con un trigger. Nunca recrea las RPC vivas de Campañas.
-- ============================================================================

begin;
set local search_path = public, pg_catalog;
set local statement_timeout = '60s';
set local lock_timeout = '5s';

-- Serializa esta instalación con cualquier asignación concurrente del trigger.
select pg_advisory_xact_lock(hashtextextended('campana-producto-slug-v1', 0));
-- El advisory lock coordina escritores ya migrados; este lock de tabla evita
-- que una escritura heredada inserte otro NULL entre backfill y NOT NULL.
lock table campana_producto in share row exclusive mode;

-- No se cambian silenciosamente URLs históricas. La escritura normal por RPC
-- ya normaliza; si aparece una excepción heredada se detiene para decidir su
-- redirección antes de continuar.
do $$
begin
  if exists (
    select 1
      from campana_producto
     where slug is not null
       and (slug is distinct from cm_normalizar_slug(slug) or length(slug) > 180)
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'SLUG_HISTORICO_NO_NORMALIZADO';
  end if;
end;
$$;

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
  -- Un UPDATE que no quiso cambiar el slug conserva literalmente el valor
  -- histórico. INSERT, NULL/vacío y cambios explícitos pasan por servidor.
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
  ) loop
    v_sufijo := v_sufijo + 1;
    v_candidato := v_base || '-' || v_sufijo::text;
  end loop;

  new.slug := v_candidato;
  return new;
end;
$$;

comment on function cm__asignar_slug_automatico() is
  'Campañas · trigger interno: preserva slugs no modificados y asigna en servidor nombre, fallback UUID y sufijos -2/-3 bajo advisory lock.';
revoke all on function cm__asignar_slug_automatico()
  from public, anon, authenticated, service_role;

-- Backfill determinista: base normalizada + UUID ordena empates. Los slugs ya
-- presentes no se normalizan, renombran ni sustituyen.
do $backfill$
declare
  r record;
  v_base text;
  v_candidato text;
  v_sufijo integer;
begin
  for r in
    select id, nombre
      from campana_producto
     where slug is null
     order by coalesce(cm_normalizar_slug(nombre),
                       'campana-' || replace(id::text, '-', '')), id
  loop
    v_base := coalesce(
      left(cm_normalizar_slug(r.nombre), 160),
      'campana-' || replace(r.id::text, '-', '')
    );
    v_candidato := v_base;
    v_sufijo := 1;
    while exists (select 1 from campana_producto where slug = v_candidato) loop
      v_sufijo := v_sufijo + 1;
      v_candidato := v_base || '-' || v_sufijo::text;
    end loop;
    update campana_producto set slug = v_candidato where id = r.id;
  end loop;
end;
$backfill$;

alter table campana_producto alter column slug set not null;

-- El índice histórico parcial ya impone unicidad a todas las filas ahora que
-- slug es NOT NULL. Se conserva su nombre y no se amplía ninguna ACL.
drop trigger if exists trg_cm_slug_automatico on campana_producto;
create trigger trg_cm_slug_automatico
before insert or update of slug, nombre on campana_producto
for each row execute function cm__asignar_slug_automatico();

-- Defensa final: el helper nunca es una puerta API, ni siquiera service_role.
revoke all on function cm__asignar_slug_automatico()
  from public, anon, authenticated, service_role;

commit;
