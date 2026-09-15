-- ============================================================
-- Magandhi Corporation · Modulo Inventario · GRANT de tabla (capa 1) para authenticated
-- ------------------------------------------------------------------------
-- POR QUE EXISTE ESTE ARCHIVO (misma leccion que 20250201000700_finanzas_grants.sql):
--
-- El proyecto Supabase se creo con "auto-expose new tables" en OFF (correcto
-- por seguridad, ver INSTRUCCIONES.md). Como efecto colateral, las tablas y
-- vistas creadas por las migraciones NUNCA reciben el GRANT base de tabla para
-- el rol `authenticated`. En Postgres el acceso se decide en DOS capas:
--
--   Capa 1 · GRANT de tabla: ¿el rol puede tocar el objeto en absoluto?
--   Capa 2 · RLS (policies):  ¿que FILAS de ese objeto puede ver/escribir?
--
-- Las policies RLS del modulo ya estan bien definidas (tiene_modulo('inventario'),
-- ver 20250301000300_inventario_rls.sql), pero sin el GRANT de la capa 1
-- Postgres rechaza con "permission denied for ..." ANTES de evaluar RLS. Por
-- eso el frontend (llave publishable, rol `authenticated`) recibiria 403 al
-- leer, aunque su policy lo permitiria.
--
-- QUE HACE (y que NO hace) esta migracion:
--   - Otorga los GRANT MINIMOS que el CLIENTE ejecuta DIRECTAMENTE. El frontend
--     de Inventario solo hace lecturas directas (.select) sobre productos,
--     movimientos_inventario, inventario_config y la vista stock_actual. TODA
--     la escritura va por RPC security definer (inv_crear_producto,
--     inv_registrar_movimiento, inv_editar_producto), que corren con
--     privilegios del dueno y por eso NO requieren GRANT sobre las tablas que
--     tocan por dentro.
--   - Por lo anterior: SOLO se otorga SELECT. NO se otorga INSERT/UPDATE/DELETE
--     (el cliente nunca los hace directo), NO se usa GRANT ALL, y NO se otorga
--     nada al rol `anon` (todo el modulo es tras login = `authenticated`; la
--     superficie publica de la tienda no se construye esta vuelta).
--   - NO toca ni duplica ninguna policy RLS existente. La defensa real sigue
--     siendo RLS + las RPC security definer; estos GRANT solo destraban la capa
--     1 para que RLS pueda por fin evaluarse. Minimo privilegio.
--
-- SOBRE GRANT EXECUTE: NO se incluye. En Postgres las funciones otorgan EXECUTE
-- a PUBLIC por defecto al crearse, y ninguna migracion de este repo hace
-- `revoke ... from public` sobre ellas. Por tanto `authenticated` YA puede
-- ejecutar las RPC del modulo; anadir GRANT EXECUTE seria redundante.
--
-- IDEMPOTENTE: `grant` es idempotente por naturaleza (re-otorgar no duplica ni
-- falla). Se puede re-ejecutar este archivo cuantas veces haga falta.
-- ============================================================

-- ------------------------------------------------------------
-- productos · lo leen "Ver inventario" / "Agregar a inventario" (.select de la
-- ficha). La escritura (crear/editar) va SIEMPRE por RPC security definer ->
-- sin INSERT/UPDATE/DELETE aqui. RLS: productos_select_modulo (tiene_modulo).
-- ------------------------------------------------------------
grant select on table productos to authenticated;

-- ------------------------------------------------------------
-- movimientos_inventario · lo lee "Ver inventario" (historial del libro por
-- producto) y lo leera Marketing (salidas por periodo). Append-only: se
-- escribe por inv_registrar_movimiento (security definer) -> solo SELECT.
-- RLS: movimientos_inventario_select_modulo (tiene_modulo).
-- ------------------------------------------------------------
grant select on table movimientos_inventario to authenticated;

-- ------------------------------------------------------------
-- inventario_config · lo lee el frontend para mostrar el prefijo del SKU si
-- hiciera falta. La siembra el dueno con service_role -> solo SELECT.
-- RLS: inventario_config_select_modulo (tiene_modulo).
-- ------------------------------------------------------------
grant select on table inventario_config to authenticated;

-- ------------------------------------------------------------
-- stock_actual (vista) · la lee "Ver inventario" directamente
-- (.from('stock_actual')). No es security_definer: hereda la RLS de sus tablas
-- base (productos / movimientos_inventario), ya cubiertas por los GRANT de
-- arriba. El cliente necesita SELECT sobre el objeto-vista para que PostgREST
-- lo exponga.
-- ------------------------------------------------------------
grant select on stock_actual to authenticated;
