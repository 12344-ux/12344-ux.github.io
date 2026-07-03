-- ============================================================
-- Stramont · Tabla "pedido_intake"
-- Guarda las respuestas del cuestionario OPCIONAL del Paso 4 de
-- simulacion.html (para qué usará la guía, qué le cuesta, algo puntual),
-- enlazadas a un pedido por pedido_id.
--
-- Por qué una tabla aparte y no columnas en "pedidos":
--   El cuestionario se responde DESPUÉS de registrar el pedido (en la
--   pantalla de éxito), y es opcional. Guardarlo como un INSERT nuevo en
--   su propia tabla evita tener que dar permiso de UPDATE a la llave
--   pública (que dejaría a cualquiera modificar pedidos existentes).
--   El informe (Edge Function, service_role) une ambas tablas por pedido_id.
--
-- Seguridad (idéntica a "pedidos"):
--   - Nunca service_role desde el navegador.
--   - La llave pública (anon) SOLO puede insertar.
--   - Sin SELECT/UPDATE/DELETE público: contiene datos de clientes.
-- ============================================================

create table if not exists pedido_intake (
  id bigint generated always as identity primary key,
  pedido_id text not null,
  uso text,
  cuesta text,
  extra text,
  creado timestamptz default now()
);

comment on table pedido_intake is 'Respuestas opcionales del cuestionario del Paso 4, enlazadas a pedidos por pedido_id. Contiene datos de clientes: nunca dar SELECT publico.';

create index if not exists idx_pedido_intake_pedido_id on pedido_intake (pedido_id);

alter table pedido_intake enable row level security;

drop policy if exists "anon inserta intake" on pedido_intake;
create policy "anon inserta intake"
  on pedido_intake
  for insert
  to anon
  with check (true);
