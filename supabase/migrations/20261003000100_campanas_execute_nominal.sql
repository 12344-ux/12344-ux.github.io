-- ============================================================
-- Impulse · CAMPANAS · EXECUTE nominal para RPC recreadas/nueva
-- Fecha: 2026-10-03
-- ------------------------------------------------------------
-- INCIDENTE CONFIRMADO EN PRODUCCION:
--   cm_reordenar_campanas existe, pero PostgREST responde:
--   42501 "permission denied for function cm_reordenar_campanas".
--
-- CAUSA:
--   20250606000200_tramo0_execute_nominal.sql dejo DEFAULT PRIVILEGES cerrados
--   para toda funcion futura: PUBLIC, anon y authenticated nacen sin EXECUTE.
--   La migracion 20261003000000 creo cm_reordenar_campanas sin conceder el
--   grant nominal a authenticated. Ademas hizo DROP + CREATE de
--   cm_crear_campana y cm_editar_campana para quitar p_hook_corto; ese DROP
--   elimino sus ACL anteriores y las firmas nuevas nacieron igualmente cerradas.
--
-- CORRECCION:
--   - PUBLIC y anon: sin EXECUTE (menor privilegio; nunca abrir estas RPC).
--   - authenticated: EXECUTE para que el back-office pueda llamarlas; el
--     segundo candado sigue siendo tiene_acceso_marketing() dentro de cada RPC.
--   - service_role: EXECUTE, manteniendo la politica nominal de Tramo 0.
--
-- No se modifica ni reejecuta 20261003000000: las migraciones aplicadas son
-- historia inmutable. Esta correccion forward solo cambia ACL de las tres
-- firmas vivas; no toca datos, orden, RLS, vistas ni cuerpos de funciones.
--
-- IDEMPOTENTE: REVOKE/GRANT pueden repetirse sin acumular efectos.
-- REQUISITO: ejecutar DESPUES de
--   20261003000000_campanas_jubilar_hook_y_reordenar.sql.
-- ============================================================

begin;

-- cm_crear_campana viva, ya sin p_hook_corto.
revoke execute on function public.cm_crear_campana(
  text, text, text, text, text, bigint, text, text, text, jsonb, jsonb,
  boolean, boolean, integer, boolean, integer, text[], uuid, text, integer
) from public, anon;
grant execute on function public.cm_crear_campana(
  text, text, text, text, text, bigint, text, text, text, jsonb, jsonb,
  boolean, boolean, integer, boolean, integer, text[], uuid, text, integer
) to authenticated, service_role;

-- cm_editar_campana viva, ya sin p_hook_corto.
revoke execute on function public.cm_editar_campana(
  uuid, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb,
  boolean, boolean, integer, boolean, integer, text[], uuid, text, integer
) from public, anon;
grant execute on function public.cm_editar_campana(
  uuid, text, text, text, text, text, bigint, text, text, text, jsonb, jsonb,
  boolean, boolean, integer, boolean, integer, text[], uuid, text, integer
) to authenticated, service_role;

-- RPC atomica usada por el arrastrar y soltar del listado de Campanas.
revoke execute on function public.cm_reordenar_campanas(uuid[])
  from public, anon;
grant execute on function public.cm_reordenar_campanas(uuid[])
  to authenticated, service_role;

commit;
