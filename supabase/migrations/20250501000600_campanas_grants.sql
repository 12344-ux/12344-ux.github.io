-- ============================================================
-- Magandhi Corporation · Area Marketing · CAMPANAS · GRANT de tabla (capa 1)
-- ------------------------------------------------------------
-- POR QUE EXISTE (misma leccion que 20250301000500_inventario_grants.sql y
-- 20250201000700_finanzas_grants.sql): el proyecto tiene "auto-expose new
-- tables" en OFF (correcto por seguridad). Como efecto, las tablas y vistas
-- creadas por migraciones NUNCA reciben el GRANT base de tabla. En Postgres el
-- acceso se decide en DOS capas:
--   Capa 1 · GRANT de tabla: el rol puede tocar el objeto en absoluto?
--   Capa 2 · RLS (policies):  que FILAS de ese objeto puede ver?
-- Las policies RLS de Campanas ya estan bien (20250501000400), pero sin el
-- GRANT de la capa 1 Postgres rechaza con "permission denied" ANTES de evaluar
-- RLS. Este archivo destraba solo esa capa 1 con el minimo privilegio.
--
-- QUE OTORGA (y que NO):
--   - SOLO SELECT. El panel del back-office (authenticated) LEE directo las
--     tablas de Campanas. TODA la escritura va por las RPC cm_* (security
--     definer), que no requieren GRANT sobre las tablas que tocan por dentro.
--   - NO INSERT/UPDATE/DELETE, NO GRANT ALL. Minimo privilegio.
--   - A `anon` solo se le concede SELECT sobre la VISTA catalogo_publico (la
--     UNICA superficie publica). NADA a anon sobre las tablas base: alli viven
--     campos internos (product_id_ref, creado_por, etiquetas). Ese es el
--     candado publico junto con el WHERE publicado=true de la vista.
--
-- SOBRE GRANT EXECUTE: NO se incluye. En Postgres las funciones otorgan EXECUTE
-- a PUBLIC por defecto al crearse y ninguna migracion hace revoke; por tanto
-- `authenticated` ya puede ejecutar las RPC cm_*. Anadir GRANT EXECUTE seria
-- redundante.
--
-- IDEMPOTENTE: grant es idempotente por naturaleza (re-otorgar no duplica ni
-- falla).
-- REQUISITO: correr DESPUES de 20250501000000..000300 (tablas + vista) y
-- 20250501000400 (RLS).
-- ============================================================

-- ------------------------------------------------------------
-- Tablas base de Campanas · SELECT para el panel del back-office (authenticated).
-- La escritura va por las RPC cm_* -> sin INSERT/UPDATE/DELETE. RLS ya definida
-- en 20250501000400 (tiene_acceso_marketing()).
-- ------------------------------------------------------------
grant select on table campana_producto           to authenticated;
grant select on table campana_categoria          to authenticated;
grant select on table campana_etiqueta           to authenticated;
grant select on table campana_producto_etiqueta  to authenticated;

-- ------------------------------------------------------------
-- catalogo_publico (vista) · la UNICA superficie publica. La lee la tienda
-- (magandhi.com) SIN login (anon) y tambien el back-office (authenticated).
-- La vista ya filtra filas (publicado=true, activo=true) y columnas (solo
-- campos publicos). Las tablas base NO reciben grant a anon: por eso este es el
-- unico camino por el que anon ve datos, y solo ve lo publicado y publico.
-- ------------------------------------------------------------
grant select on catalogo_publico to anon, authenticated;
