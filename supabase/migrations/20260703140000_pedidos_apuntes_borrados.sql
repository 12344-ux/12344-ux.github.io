-- ============================================================
-- Stramont · Columna "apuntes_borrados" en la tabla "pedidos"
-- Marca CUÁNDO se liberaron (borraron de Storage) los apuntes crudos de
-- un pedido, conservando el registro del pedido (trazabilidad y ventas).
--   NULL      = los apuntes siguen en Storage.
--   timestamp = fecha en que se liberaron desde el tablero.
--
-- Es una columna aditiva y nullable: no afecta pedidos existentes ni
-- ninguna lógica actual. No cambia RLS (la escritura de este campo la
-- hace la Edge Function con service_role, nunca el navegador).
-- ============================================================

alter table pedidos add column if not exists apuntes_borrados timestamptz;

comment on column pedidos.apuntes_borrados is 'Cuando se liberaron (borraron de Storage) los apuntes crudos de este pedido. NULL = siguen en Storage. El registro del pedido se conserva.';
