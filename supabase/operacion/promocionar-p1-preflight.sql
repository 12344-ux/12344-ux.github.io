-- PROMOCIONAR P1 · PREFLIGHT · SOLO LECTURA
-- Requisito: baseline C5/slug automático ya aplicado.
-- Esperado antes de aplicar 20261107000000: listo_para_aplicar = true.
begin read only;
set local search_path = public, pg_catalog;
set local statement_timeout = '15s';
set local lock_timeout = '3s';

with trigger_slug as (
  select exists (
    select 1
      from pg_trigger t
      join pg_proc p on p.oid = t.tgfoid
     where t.tgrelid = 'public.campana_producto'::regclass
       and t.tgname = 'trg_cm_slug_automatico'
       and not t.tgisinternal
       and t.tgenabled = 'O'
       and t.tgtype = 23 -- ROW + BEFORE + INSERT + UPDATE
       and t.tgqual is null
       and array(select x from unnest(t.tgattr::smallint[]) as u(x)) = array[
         (select attnum::smallint from pg_attribute where attrelid = t.tgrelid and attname = 'slug'),
         (select attnum::smallint from pg_attribute where attrelid = t.tgrelid and attname = 'nombre')
       ]
       and p.oid = 'public.cm__asignar_slug_automatico()'::regprocedure
  ) as correcto
), estado as (
  select
    to_regclass('public.campana_slug_historial') is null as historial_no_instalado,
    to_regclass('public.campana_slug_alias_publico') is null as vista_alias_no_instalada,
    (select count(*) from campana_producto where slug is null) as slugs_nulos,
    (select count(*) from campana_producto
      where slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or length(slug) > 180) as slugs_invalidos,
    (select count(*) - count(distinct slug) from campana_producto) as slugs_repetidos
)
select
  t.correcto as trigger_slug_correcto,
  e.historial_no_instalado,
  e.vista_alias_no_instalada,
  e.slugs_nulos,
  e.slugs_invalidos,
  e.slugs_repetidos,
  t.correcto and e.historial_no_instalado and e.vista_alias_no_instalada
    and e.slugs_nulos = 0 and e.slugs_invalidos = 0 and e.slugs_repetidos = 0
    as listo_para_aplicar
from trigger_slug t cross join estado e;

rollback;
