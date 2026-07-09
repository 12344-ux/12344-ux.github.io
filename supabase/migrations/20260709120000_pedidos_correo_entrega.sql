-- ============================================================
-- Stramont · Columnas para el Correo 2 (entrega de la guía) en "pedidos"
--
--   correo_entrega_enviado (timestamptz): cuándo se envió el Correo 2 de
--     entrega al cliente. NULL = no enviado. Sirve para IDEMPOTENCIA
--     (no reenviar la guía dos veces).
--   guia_archivo (text): nombre del archivo de la guía que se entregó
--     (en el bucket privado "guias"). Queda para trazabilidad y para
--     poder regenerar el enlace/vista previa después.
--
-- Columnas aditivas y nullable: no afectan pedidos existentes ni la lógica
-- actual. La columna "tema" (que también usa el Correo 2) ya existe.
-- No cambia RLS (las escribe la Edge Function con service_role).
-- ============================================================

alter table pedidos add column if not exists correo_entrega_enviado timestamptz;
alter table pedidos add column if not exists guia_archivo text;

comment on column pedidos.correo_entrega_enviado is 'Cuando se envio el Correo 2 (entrega de la guia) al cliente. NULL = no enviado. Idempotencia.';
comment on column pedidos.guia_archivo is 'Nombre del archivo de la guia entregada (bucket privado guias).';
