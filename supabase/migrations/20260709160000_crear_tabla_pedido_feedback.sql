-- ============================================================
-- Stramont · Tabla "pedido_feedback" (Correo 3 — opiniones)
-- Guarda la opinión que deja el cliente: calificación (1-5), comentario
-- opcional y, si dio permiso, el nombre a mostrar en un testimonio.
--
-- SEGURIDAD (más cerrada que pedido_intake, a propósito):
--   pedido_intake permite INSERT a la llave pública porque el propio
--   cliente lo escribe desde una página pública SIN necesidad de validar
--   nada. Aquí NO: una opinión debe validarse contra un feedback_token
--   por pedido (así nadie puede inyectar opiniones falsas para pedidos
--   ajenos). Una policy de INSERT público NO puede validar ese token
--   (RLS no ve el token del cliente contra pedidos). Por eso esta tabla
--   NO tiene NINGUNA policy pública: ni SELECT, ni INSERT, ni UPDATE.
--   TODO acceso pasa por la Edge Function "feedback" (service_role, que
--   ignora RLS) previa validación del token. Es el mismo criterio que
--   ya usan "informe" y "entrega".
-- ============================================================

create table if not exists pedido_feedback (
  id bigint generated always as identity primary key,
  pedido_id text unique not null,
  rating smallint,
  comentario text,
  permiso_publicar boolean default false,
  nombre_mostrar text,
  es_prueba boolean default false,
  feedback_recibido_at timestamptz default now(),
  comentario_recibido_at timestamptz,
  constraint rating_valido check (rating is null or (rating between 1 and 5))
);

comment on table pedido_feedback is 'Opiniones del Correo 3 (calificacion 1-5 + comentario). Una fila por pedido. Sin policy publica: solo la Edge Function feedback (service_role) escribe/lee, previa validacion del feedback_token.';

create index if not exists idx_pedido_feedback_pedido_id on pedido_feedback (pedido_id);

-- RLS activado SIN policies: la llave publica no puede leer ni escribir.
-- service_role (Edge Function) ignora RLS y es la unica via de acceso.
alter table pedido_feedback enable row level security;
