-- ============================================================
-- Stramont · Tabla "pedidos"
-- Registra cada compra de forma trazable para:
--   1) Eliminar la colisión de carpetas (cada pedido tiene su propio
--      pedido_id, que ya viaja también en la ruta de Storage).
--   2) Dar trazabilidad al dueño (qué está pendiente de entregar/borrar).
--   3) Servir como materia prima del reporte de ventas periódico.
--
-- Seguridad (no negociable, consistente con el resto del proyecto):
--   - Nunca se usa la service_role key desde el navegador.
--   - La llave pública (anon/publishable) SOLO puede insertar filas.
--   - No hay policy de SELECT/UPDATE/DELETE para "anon": la tabla
--     contiene correos de clientes y no debe ser legible públicamente.
--   - La lectura para el informe interno se hace vía una Edge Function
--     protegida con LINK_SECRET (el mismo secreto que ya usa la función
--     "entrega"), que sí usa service_role del lado del servidor.
-- ============================================================

create table if not exists pedidos (
  id bigint generated always as identity primary key,
  pedido_id text unique not null,
  correo text not null,
  nombre text,
  tema text,
  plan text,
  dias_acceso integer,
  carpeta_storage text not null,
  fecha_compra timestamptz default now(),
  guia_entregada boolean default false,
  fecha_entrega timestamptz,
  tamano_apuntes_mb numeric
);

comment on table pedidos is 'Registro trazable de cada compra de Stramont. Contiene correos de clientes: nunca dar SELECT publico.';

alter table pedidos enable row level security;

-- Unica policy publica: permitir que el flujo de compra (llave anon/publishable
-- en simulacion.html) inserte su propio pedido. Nada de SELECT/UPDATE/DELETE
-- para el rol "anon": eso evitaria que cualquiera enumere clientes/correos.
drop policy if exists "anon puede insertar su pedido" on pedidos;
create policy "anon puede insertar su pedido"
  on pedidos
  for insert
  to anon
  with check (true);

-- Nota: las actualizaciones (marcar guia_entregada = true, fecha_entrega, tema)
-- y toda lectura para el informe interno se hacen con service_role, desde la
-- Edge Function "informe" (nunca desde el navegador con la llave publica).
