-- ============================================================
-- Stramont · Columnas para el Correo 3 (opiniones) en "pedidos"
--
--   feedback_token (text, único): capacidad ACOTADA por pedido. Viaja en
--     el enlace del correo de opinión (?t=). La Edge Function "feedback"
--     lo valida antes de registrar la opinión. Si se filtrara, lo peor
--     posible es calificar ESE pedido (no lee ni enumera nada más).
--     Se genera al enviar el Correo 3 (no antes: un pedido sin opinión
--     solicitada no tiene token).
--   correo_feedback_enviado (timestamptz): cuándo se envió el Correo 3.
--     NULL = no enviado. IDEMPOTENCIA (no pedir opinión dos veces) y base
--     del aviso "listo para pedir opinión" del tablero.
--   recordatorio_enviado (timestamptz): se crea PERO se deja SIN USAR.
--     Habilita en el futuro (fase 2) un recordatorio de opinión sin tener
--     que rehacer el esquema.
--
-- Columnas aditivas y nullable: no afectan pedidos existentes.
-- No cambia RLS (las escribe la Edge Function con service_role).
-- ============================================================

alter table pedidos add column if not exists feedback_token text;
alter table pedidos add column if not exists correo_feedback_enviado timestamptz;
alter table pedidos add column if not exists recordatorio_enviado timestamptz;

-- Índice único parcial: dos pedidos no pueden compartir token, pero
-- muchos pueden tenerlo NULL (aún sin opinión solicitada).
create unique index if not exists idx_pedidos_feedback_token
  on pedidos (feedback_token) where feedback_token is not null;

comment on column pedidos.feedback_token is 'Token aleatorio por pedido para autorizar SU opinion (Correo 3). Capacidad acotada. Se genera al enviar el correo.';
comment on column pedidos.correo_feedback_enviado is 'Cuando se envio el Correo 3 (opinion). NULL = no enviado. Idempotencia.';
comment on column pedidos.recordatorio_enviado is 'Reservado (fase 2): recordatorio de opinion. Creado pero sin usar aun.';
