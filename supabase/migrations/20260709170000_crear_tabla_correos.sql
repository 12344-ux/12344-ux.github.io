-- ============================================================
-- Stramont · Tabla "correos" (Base de correos — Frente A)
-- Registro OPERATIVO de correos capturados (prospectos que abren la guía
-- demo). NO es una lista de marketing. Los CLIENTES ya viven en "pedidos";
-- el tablero une ambas fuentes y deduplica.
--
-- SEGURIDAD (mismo criterio que pedido_feedback, a propósito):
--   - Contiene datos personales (correos) -> RLS activado y SIN NINGUNA
--     policy pública: la llave publishable NO puede leer NI insertar.
--   - La captura del prospecto NO es inserción pública abierta (evita
--     inundación de correos falsos). Entra por la Edge Function "captura"
--     (service_role), que valida formato + anti-abuso, y luego el tablero
--     la lee vía la función "informe" (service_role + LINK_SECRET).
--   - Dedupe por (correo, origen): el mismo correo no crea filas repetidas.
-- ============================================================

create table if not exists correos (
  id bigint generated always as identity primary key,
  correo text not null,
  origen text not null default 'prospecto_demo',
  es_prueba boolean default false,
  creado timestamptz default now(),
  constraint correos_unicos unique (correo, origen)
);

comment on table correos is 'Registro operativo de correos capturados (prospectos de la guia demo). Datos personales: sin policy publica. Acceso solo por Edge Functions (service_role). No es lista de marketing.';

create index if not exists idx_correos_creado on correos (creado desc);

-- RLS activado SIN policies: la llave publica no puede leer ni escribir.
-- Todo pasa por Edge Functions con service_role.
alter table correos enable row level security;
