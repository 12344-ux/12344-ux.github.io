-- ============================================================
-- Stramont · Estado de pago (Wompi) en la tabla "pedidos"
-- Para pasar de "simulación" a PRODUCCIÓN con confirmación por WEBHOOK.
--
-- El estado "pagado" y el acceso se basan SOLO en el webhook verificado de
-- Wompi (server-side), nunca en un "éxito" del navegador (no falsificable).
--
-- Columnas nuevas:
--   estado_pago         'pendiente' | 'aprobado' | 'rechazado' | 'error'
--   wompi_transaction_id  id de la transacción en Wompi (para idempotencia/traza)
--   monto_cents         monto cobrado en centavos (COP)
--   moneda              'COP'
--   pagado_en           fecha/hora de la aprobación
--
-- Idempotencia: índice único parcial sobre wompi_transaction_id (si un evento
-- llega repetido, no se puede crear/duplicar).
-- ============================================================

alter table pedidos add column if not exists estado_pago text not null default 'pendiente';
alter table pedidos add column if not exists wompi_transaction_id text;
alter table pedidos add column if not exists monto_cents bigint;
alter table pedidos add column if not exists moneda text;
alter table pedidos add column if not exists pagado_en timestamptz;

comment on column pedidos.estado_pago is 'pendiente | aprobado | rechazado | error. Solo lo cambia el webhook verificado (service_role).';

-- Idempotencia por transacción de Wompi.
create unique index if not exists pedidos_wompi_tx_uq
  on pedidos (wompi_transaction_id)
  where wompi_transaction_id is not null;

-- NOTA DE SEGURIDAD (RLS intacta): la tabla sigue SIN SELECT/UPDATE público.
-- El webhook y el informe usan service_role (server-side). El navegador solo
-- puede INSERT (crear su pedido 'pendiente'); nunca puede marcarse "pagado".
