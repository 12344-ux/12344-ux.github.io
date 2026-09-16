-- ============================================================
-- Magandhi Corporation · Area de Ventas · RLS (el candado real) + FK del enchufe
-- ------------------------------------------------------------
-- POR QUE EXISTE ESTE ARCHIVO: pone el candado real (Row Level Security) sobre
-- las tablas de Ventas y define su funcion de acceso tiene_acceso_ventas(),
-- ESPEJO EXACTO de tiene_acceso_inventario() (ver 20250301000300_inventario_rls
-- .sql). El candado de verdad esta en los DATOS, no en el HTML: ocultar una
-- pantalla en el navegador es comodidad de UX, nunca seguridad (PLANO-VENTAS §6).
--
-- ADEMAS enciende la FK del enchufe: convierte movimientos_inventario.customer_id
-- en FK real a clientes(id) (§2). Hasta hoy esa columna era uuid nullable SIN FK
-- ("enchufe apagado", ver 20250301000100_inventario_movimientos.sql). Se
-- enciende ahora porque en produccion esta VACIA (Ventas no existia), asi que
-- agregar la FK no exige migrar ni reconciliar datos viejos: es el momento
-- barato de hacerlo, y previene customer_id huerfanos imposibles de cruzar.
--
-- DATOS PERSONALES DE TERCEROS (§6.2): correos, telefonos y direcciones NUNCA se
-- exponen al rol anon/publico. CERO grant y CERO policy para anon. Todo el area
-- es tras login (authenticated).
--
-- SOLO SELECT BAJO EL WRAPPER: cada tabla recibe UNA policy FOR SELECT to
-- authenticated using (tiene_acceso_ventas()). SIN policies de INSERT/UPDATE/
-- DELETE: la escritura va SOLO por las RPC security definer (ver 20250401000400).
-- SIN DELETE en ninguna tabla: clientes se inactivan, pedidos se anulan.
--
-- IDEMPOTENTE: create or replace fn + drop policy if exists + create policy +
-- alter table enable rls (se re-asegura por si se corre suelto) + DO block que
-- consulta pg_constraint antes de agregar la FK (no falla al re-ejecutar).
-- REQUISITO: correr DESPUES de 20250401000000_ventas_clientes.sql y
-- 20250401000100_ventas_pedidos.sql. La FK requiere que movimientos_inventario
-- ya exista (modulo Inventario, 20250301000100).
-- ============================================================

-- ------------------------------------------------------------
-- tiene_acceso_ventas(): clave de acceso del Area de Ventas. ESPEJO EXACTO de
-- tiene_acceso_inventario() (language sql, stable, security definer,
-- set search_path=public). Envuelve tiene_modulo() y acepta las claves
-- equivalentes del area para que el candado de datos hable el MISMO idioma que
-- el panel y ventas-core: clave del area (ventas), de la sub-area de pedidos
-- (pedidos) y de la sub-area del portafolio (clientes / portafolio, alias).
-- admin ve todo (lo resuelve tiene_modulo). Clonable.
-- ------------------------------------------------------------
create or replace function tiene_acceso_ventas()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select tiene_modulo('ventas')        -- clave del area
      or tiene_modulo('pedidos')       -- sub-area seguimiento de pedidos
      or tiene_modulo('clientes')      -- sub-area portafolio
      or tiene_modulo('portafolio');   -- alias de la sub-area portafolio
$$;

comment on function tiene_acceso_ventas() is 'Acceso al Area de Ventas: true si el usuario tiene la clave del area (ventas), la de la sub-area de pedidos (pedidos) o la del portafolio (clientes / portafolio), o si es admin. Espejo de tiene_acceso_inventario(): envuelve tiene_modulo() para que el candado de datos, el panel y ventas-core hablen la misma convencion de claves.';

-- ------------------------------------------------------------
-- clientes: SELECT si tiene_acceso_ventas(). SIN INSERT/UPDATE/DELETE directo
-- (escritura por RPC security definer). CERO policy para anon (datos personales).
-- ------------------------------------------------------------
alter table clientes enable row level security;

drop policy if exists "clientes_select_ventas" on clientes;
create policy "clientes_select_ventas" on clientes
  for select
  to authenticated
  using (tiene_acceso_ventas());

-- ------------------------------------------------------------
-- pedidos: SELECT si tiene_acceso_ventas(). SIN INSERT/UPDATE/DELETE directo
-- (crear_pedido / anular_pedido, security definer). Sin DELETE: se anula.
-- ------------------------------------------------------------
alter table pedidos enable row level security;

drop policy if exists "pedidos_select_ventas" on pedidos;
create policy "pedidos_select_ventas" on pedidos
  for select
  to authenticated
  using (tiene_acceso_ventas());

-- ------------------------------------------------------------
-- pedido_items: SELECT si tiene_acceso_ventas(). SIN INSERT/UPDATE/DELETE
-- directo (se escriben dentro de crear_pedido, security definer).
-- ------------------------------------------------------------
alter table pedido_items enable row level security;

drop policy if exists "pedido_items_select_ventas" on pedido_items;
create policy "pedido_items_select_ventas" on pedido_items
  for select
  to authenticated
  using (tiene_acceso_ventas());

-- Sin policies de INSERT/UPDATE/DELETE en ninguna de las tres tablas: la
-- escritura pasa SOLO por las RPC security definer de 20250401000400. Cero
-- policy para anon: el area entera es tras login (authenticated).

-- ------------------------------------------------------------
-- PUENTE DE LECTURA VENTAS -> productos: SELECT adicional sobre el catalogo.
-- ESPEJO EXACTO de productos_select_marketing (ver 20250301000600_inventario_
-- marketing_lectura.sql). POR QUE: el selector de productos de registrar.html
-- (el formulario de registro de pedidos) LEE el catalogo productos para armar
-- las lineas del pedido. Pero las unicas policies de SELECT sobre productos son
-- las de Inventario (productos_select_modulo) y Marketing (productos_select_
-- marketing); un usuario SOLO de ventas quedaria bloqueado por RLS al cargar el
-- catalogo. Esta policy anade el acceso de LECTURA para el Area de Ventas.
--
-- CONVIVE sin quitar nada: en RLS basta con que UNA policy permisiva de SELECT
-- sea verdadera, asi que esta convive con las de inventario/marketing (no las
-- toca ni las reemplaza). SOLO LECTURA: el catalogo se sigue escribiendo por
-- las RPC de Inventario (inv_crear_producto / inv_editar_producto); Ventas
-- nunca escribe productos. CERO policy para anon.
-- ------------------------------------------------------------
alter table productos enable row level security;

drop policy if exists "productos_select_ventas" on productos;
create policy "productos_select_ventas" on productos
  for select
  to authenticated
  using (tiene_acceso_ventas());

-- ------------------------------------------------------------
-- ENCENDER LA FK DEL ENCHUFE: movimientos_inventario.customer_id -> clientes(id).
-- La columna existe desde 20250301000100 como uuid nullable SIN FK ("enchufe
-- apagado"). Se le agrega la FK ahora que clientes existe. La columna esta VACIA
-- en produccion (Ventas no existia), asi que la FK no exige migrar datos y su
-- costo es minimo (§2). Guard idempotente: solo se agrega si no existe ya en
-- pg_constraint, para no fallar al re-ejecutar el archivo.
-- ------------------------------------------------------------
do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'movimientos_inventario_customer_id_fkey'
       and conrelid = 'movimientos_inventario'::regclass
  ) then
    alter table movimientos_inventario
      add constraint movimientos_inventario_customer_id_fkey
      foreign key (customer_id) references clientes(id);
  end if;
end
$$;
