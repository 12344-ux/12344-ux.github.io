-- ============================================================
-- Magandhi Corporation · Area de Ventas · GRANT de tabla (capa 1) para authenticated
-- ------------------------------------------------------------
-- POR QUE EXISTE ESTE ARCHIVO (misma leccion que 20250301000500_inventario_grants
-- .sql y 20250201000700_finanzas_grants.sql):
--
-- El proyecto Supabase se creo con "auto-expose new tables" en OFF (correcto por
-- seguridad, ver INSTRUCCIONES.md). Como efecto colateral, las tablas y vistas
-- creadas por las migraciones NUNCA reciben el GRANT base de tabla para el rol
-- `authenticated`. En Postgres el acceso se decide en DOS capas:
--
--   Capa 1 · GRANT de tabla: ¿el rol puede tocar el objeto en absoluto?
--   Capa 2 · RLS (policies):  ¿que FILAS de ese objeto puede ver/escribir?
--
-- Las policies RLS de Ventas ya estan definidas (tiene_acceso_ventas(), ver
-- 20250401000300_ventas_rls.sql), pero sin el GRANT de la capa 1 Postgres
-- rechaza con "permission denied for ..." ANTES de evaluar RLS. Por eso el
-- frontend (llave publishable, rol `authenticated`) recibiria 403 al leer,
-- aunque su policy lo permitiria.
--
-- QUE HACE (y que NO hace) esta migracion:
--   - Otorga SOLO SELECT sobre lo que el CLIENTE lee DIRECTAMENTE: clientes,
--     pedidos, pedido_items y la vista portafolio_metricas. TODA la escritura va
--     por RPC security definer (crear_pedido, anular_pedido) y la lectura
--     acotada por buscar_candidatos_cliente, que corren con privilegios del
--     dueno y por eso NO requieren GRANT sobre las tablas que tocan por dentro.
--   - NO se otorga INSERT/UPDATE/DELETE (el cliente nunca los hace directo), NO
--     se usa GRANT ALL.
--   - CERO grant al rol `anon`: los datos personales de terceros (correos,
--     telefonos, direcciones) NUNCA se exponen al publico (§6.2). Todo el area es
--     tras login (`authenticated`).
--   - NO toca ni duplica ninguna policy RLS. La defensa real sigue siendo RLS +
--     las RPC security definer; estos GRANT solo destraban la capa 1.
--
-- SOBRE GRANT EXECUTE: NO se incluye. En Postgres las funciones otorgan EXECUTE
-- a PUBLIC por defecto al crearse, y ninguna migracion de este repo hace
-- `revoke ... from public` sobre ellas. Por tanto `authenticated` YA puede
-- ejecutar crear_pedido / anular_pedido / buscar_candidatos_cliente; anadir
-- GRANT EXECUTE seria redundante.
--
-- IDEMPOTENTE: `grant` es idempotente por naturaleza (re-otorgar no duplica ni
-- falla). Se puede re-ejecutar cuantas veces haga falta.
-- REQUISITO: correr DESPUES de 20250401000000..20250401000200 (los objetos ya
-- deben existir).
-- ============================================================

-- ------------------------------------------------------------
-- clientes · lo lee el Portafolio (lista/ficha del cliente). La escritura va por
-- RPC security definer -> solo SELECT. RLS: clientes_select_ventas.
-- ------------------------------------------------------------
grant select on table clientes to authenticated;

-- ------------------------------------------------------------
-- pedidos · lo lee Seguimiento de pedidos (tablero) y el Portafolio (historial).
-- La escritura va por crear_pedido / anular_pedido -> solo SELECT.
-- RLS: pedidos_select_ventas.
-- ------------------------------------------------------------
grant select on table pedidos to authenticated;

-- ------------------------------------------------------------
-- pedido_items · lo lee el detalle del pedido. Se escribe dentro de crear_pedido
-- (security definer) -> solo SELECT. RLS: pedido_items_select_ventas.
-- ------------------------------------------------------------
grant select on table pedido_items to authenticated;

-- ------------------------------------------------------------
-- portafolio_metricas (vista) · la lee el Portafolio directamente. Es SECURITY
-- INVOKER: hereda la RLS de sus tablas base (clientes / pedidos), ya cubiertas
-- por los GRANT de arriba. El cliente necesita SELECT sobre el objeto-vista para
-- que PostgREST lo exponga.
-- ------------------------------------------------------------
grant select on portafolio_metricas to authenticated;
