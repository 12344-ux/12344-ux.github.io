-- ============================================================
-- Stramont · Columna "correo_confirmacion_enviado" en "pedidos"
-- Marca CUÁNDO se envió el correo automático de confirmación de compra
-- al cliente (Correo 1 de 3, vía Resend).
--   NULL      = todavía no se ha enviado.
--   timestamp = fecha/hora en que se envió.
--
-- Sirve para IDEMPOTENCIA: la Edge Function "correo-confirmacion" no
-- reenvía si esta columna ya tiene valor (evita correos duplicados y
-- cierra la puerta a que alguien dispare envíos repetidos).
--
-- Columna aditiva y nullable: no afecta pedidos existentes ni la lógica
-- actual. No cambia RLS (la escribe la Edge Function con service_role).
-- ============================================================

alter table pedidos add column if not exists correo_confirmacion_enviado timestamptz;

comment on column pedidos.correo_confirmacion_enviado is 'Cuando se envio el correo automatico de confirmacion de compra al cliente (via Resend). NULL = no enviado. Se usa para idempotencia (no reenviar).';
