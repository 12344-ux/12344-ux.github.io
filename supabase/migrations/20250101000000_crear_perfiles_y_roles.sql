-- ============================================================
-- Magandhi Corporation · Tabla "perfiles" (UID -> rol -> modulos)
-- Cimiento de acceso interno del back-office (montaguth.institute).
-- Cada usuario de Supabase Auth tiene, como maximo, una fila aqui que
-- define QUE puede hacer dentro del panel interno:
--   1) rol: etiqueta de nivel ('admin', 'sin_rol', y en el futuro
--      'hermano', 'operador', etc.).
--   2) modulos: lista escalable de los modulos internos permitidos
--      (ej. '{pedidos}'). Permite delegar acceso granular SIN rehacer
--      el esquema: el dueno = admin (todo), el hermano = solo pedidos,
--      otra persona = solo otro modulo, etc.
--
-- SEGURIDAD (no negociable, consistente con el resto del proyecto):
--   - El candado real esta en los DATOS (RLS), no en el HTML. Ocultar
--     una pagina en el navegador es comodidad de UX, nunca seguridad.
--   - La llave publishable (publica, va en el cliente) queda limitada
--     por estas policies. La secret / service_role NUNCA aparece en el
--     repo ni en el navegador.
--   - SELECT restringido: cada usuario autenticado solo puede leer SU
--     PROPIA fila (auth.uid() = id). No hay SELECT publico ni SELECT de
--     todas las filas, de modo que nadie puede enumerar usuarios ni
--     descubrir quien es admin.
--   - NO se crean policies de INSERT / UPDATE / DELETE para el rol
--     "authenticated". La gestion de perfiles (asignar rol y modulos) la
--     hace el dueno con la service_role desde el dashboard de Supabase
--     (o una Edge Function futura). El cliente NUNCA se auto-asigna rol.
--
-- PATRON DE VERIFICACION DE ROL (lo usaran el frontend y las Edge
-- Functions futuras):
--   1) Leer la fila propia: select rol, modulos from perfiles
--      where id = auth.uid();
--   2) Si rol = 'admin'  -> acceso total a todos los modulos.
--   3) Si rol != 'admin' -> acceso solo a los modulos presentes en la
--      lista "modulos" (ej. si modulos = '{pedidos}', solo entra a
--      pedidos). Cualquier modulo fuera de la lista se niega.
-- ============================================================

create table if not exists perfiles (
  id uuid primary key references auth.users(id) on delete cascade,
  rol text not null default 'sin_rol',
  modulos text[] not null default '{}',
  creado timestamptz default now()
);

comment on table perfiles is 'Perfil de acceso interno por usuario de Auth. rol=admin implica todos los modulos; otros roles se restringen por la lista "modulos". SELECT solo de la propia fila via RLS; escritura solo con service_role desde el dashboard.';

-- RLS: cada usuario autenticado solo puede LEER su propia fila.
alter table perfiles enable row level security;

drop policy if exists "perfiles_lectura_propia" on perfiles;
create policy "perfiles_lectura_propia" on perfiles
  for select
  to authenticated
  using (auth.uid() = id);

-- OJO: NO se crean policies de INSERT / UPDATE / DELETE. Por lo tanto la
-- llave publishable NO puede escribir esta tabla ni auto-asignarse rol.
-- Solo service_role (que salta RLS), usado por el dueno desde el
-- dashboard o por una Edge Function futura, gestiona los perfiles.

-- ------------------------------------------------------------
-- Semilla del administrador.
-- Este INSERT lo ejecuta el DUENO desde el SQL Editor del dashboard, que
-- corre con privilegios de service_role y por tanto SALTA RLS (aunque
-- arriba no exista policy de insert para authenticated). Asigna rol
-- 'admin' y todos los modulos actuales al UID del dueno.
--
-- UID del dueno (michaelmagandhi@outlook.com): 89e5028d-8c17-4deb-89c3-59acbd0ee2f2
--
-- Nota: 'admin' implica todos los modulos por regla de negocio (ver el
-- patron de verificacion arriba); la lista de modulos que se guarda aqui
-- es solo documental/explicita. A medida que aparezcan modulos nuevos, el
-- admin los tiene todos sin necesidad de editar esta fila.
insert into perfiles (id, rol, modulos)
values ('89e5028d-8c17-4deb-89c3-59acbd0ee2f2', 'admin', '{pedidos}')
  on conflict (id) do update
    set rol = excluded.rol,
        modulos = excluded.modulos;

-- ------------------------------------------------------------
-- Helper opcional (recomendado): tiene_modulo(text).
-- Devuelve true si el usuario autenticado actual puede acceder al modulo
-- indicado, aplicando la misma regla: admin -> todo; otros -> solo si el
-- modulo esta en su lista. Las Edge Functions y policies futuras pueden
-- reutilizar esta funcion en lugar de repetir la logica.
create or replace function tiene_modulo(modulo text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from perfiles
    where id = auth.uid()
      and (rol = 'admin' or modulo = any(modulos))
  );
$$;

comment on function tiene_modulo(text) is 'Regla central de acceso por modulo: admin ve todo; otros roles solo los modulos de su lista. Reutilizable por Edge Functions y policies futuras.';
