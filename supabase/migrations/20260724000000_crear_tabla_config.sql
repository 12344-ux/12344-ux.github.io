-- ============================================================
-- Stramont · Tabla "config" (bandera de operaciones)
-- Un interruptor global para PAUSAR la recepción de nuevos pedidos pagados
-- (para no cobrar algo que no se pueda entregar en 24h). Reversible.
--
-- Diseño de una sola fila (id = 1):
--   operaciones_activas = true  -> el flujo de pago funciona normal.
--   operaciones_activas = false -> el sitio muestra el mensaje de pausa y
--                                  deshabilita el pago (los clientes que ya
--                                  pagaron NO se ven afectados).
--
-- SEGURIDAD (a propósito):
--   - Esta tabla contiene SOLO un booleano de configuración, ningún dato
--     personal ni secreto. Por eso la LECTURA PÚBLICA es aceptable: el sitio
--     (con la llave publishable) solo necesita LEER el booleano para decidir
--     qué mostrar.
--   - La ESCRITURA está cerrada a la llave pública (no hay policy de
--     insert/update/delete). La bandera SOLO se cambia desde la Edge Function
--     "informe" (service_role + LINK_SECRET), es decir, desde el tablero
--     autenticado. Así el frontend nunca puede pausar/reactivar por su cuenta.
-- ============================================================

create table if not exists config (
  id smallint primary key default 1,
  operaciones_activas boolean not null default true,
  actualizado timestamptz not null default now(),
  constraint config_una_fila check (id = 1)
);

comment on table config is 'Configuracion global (una fila, id=1). operaciones_activas: bandera para pausar la recepcion de pedidos. Lectura publica (solo booleano, sin datos sensibles); escritura solo via Edge Function informe (service_role + LINK_SECRET).';

-- Fila única inicial: arranca con operaciones ACTIVAS.
insert into config (id, operaciones_activas) values (1, true)
  on conflict (id) do nothing;

-- RLS: lectura pública del booleano (no hay datos sensibles aquí).
alter table config enable row level security;

drop policy if exists "config_lectura_publica" on config;
create policy "config_lectura_publica" on config
  for select
  using (true);

-- OJO: NO se crean policies de INSERT / UPDATE / DELETE. Por lo tanto la
-- llave publishable NO puede escribir esta tabla. Solo service_role (que
-- salta RLS), usado por la Edge Function "informe", cambia la bandera.
