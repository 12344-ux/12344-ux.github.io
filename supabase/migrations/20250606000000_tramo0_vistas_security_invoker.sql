-- ============================================================
-- Impulse · TRAMO 0 (auditoria) · Vistas internas con SECURITY INVOKER real
-- ------------------------------------------------------------
-- EL HALLAZGO (verificado con evidencia en una base local identica):
--   movimientos_mayor, saldos_cuenta (Finanzas) y stock_actual (Inventario)
--   se crearon como vistas NORMALES. Sus comentarios decian "heredan la RLS",
--   pero en PostgreSQL una vista normal se ejecuta con los privilegios de su
--   DUENO (postgres), que salta la RLS. Como ademas tienen
--   `grant select ... to authenticated`, CUALQUIER usuario con sesion, aunque
--   no tenga el modulo, podia leer el Libro Mayor, los saldos contables y todo
--   el stock. Prueba reproducida: usuario sin modulos -> asientos = 0 filas
--   (RLS ok) pero movimientos_mayor = 2, saldos_cuenta = 2, stock_actual = 5.
--   Hoy no tiene victima (solo existe el admin), pero se activaria con el
--   primer usuario de rol reducido.
--
-- LA CORRECCION: activar security_invoker = true en las tres vistas (como ya
--   lo hace bien portafolio_metricas). Asi ejecutan con los permisos de QUIEN
--   CONSULTA y la RLS de sus tablas base aplica de verdad.
--
-- ⚠️ TRAMPA QUE ESTA MIGRACION EVITA (tambien verificada):
--   catalogo_publico (la vista que lee la TIENDA como anon) hacia
--   `left join stock_actual`. PostgreSQL evalua una vista security_invoker con
--   los permisos del usuario ACTUAL aunque se lea desde dentro de una vista del
--   dueno. Si solo se activara invoker en stock_actual, la tienda recibiria
--   `permission denied for table productos` y se caeria el catalogo entero.
--   Por eso PRIMERO se redefine catalogo_publico para calcular las existencias
--   DIRECTO del libro movimientos_inventario (misma formula que stock_actual,
--   mismo resultado), sin depender de stock_actual. catalogo_publico SIGUE
--   siendo una vista del dueno A PROPOSITO: es la unica superficie publica y
--   su candado es la lista blanca de columnas + publicado/activo.
--
-- COLUMNAS DE catalogo_publico: IDENTICAS en nombre, tipo y orden a la
--   definicion vigente (20250602000000). Por eso se usa CREATE OR REPLACE
--   VIEW (no DROP): CONSERVA los grants existentes (anon, authenticated y el
--   de service_role que necesita la Edge Function crear-intencion-pago, ver
--   la trampa documentada en 20250605000000). Igual se re-otorgan abajo como
--   cinturon de seguridad (grant es idempotente).
--
-- QUE NO CAMBIA: ninguna columna publica, ninguna formula de `agotado`, ningun
--   grant de tabla. Las RPC security definer que leen stock (inv_*) corren como
--   su dueno, asi que no se ven afectadas.
--
-- IDEMPOTENTE: create or replace view + alter view set (...) + grant. Se puede
--   re-ejecutar sin efectos secundarios.
-- REQUISITO: correr DESPUES de 20250605000000_wompi_grants_service_role.sql.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- (1) catalogo_publico deja de depender de stock_actual.
-- Las existencias se calculan con la MISMA formula de stock_actual
-- (entrada/ajuste_entrada suman, salida/ajuste_salida restan), agregadas por
-- producto en una subconsulta. El numero NUNCA se expone: solo alimenta el
-- booleano `agotado`, igual que antes.
-- ------------------------------------------------------------
create or replace view catalogo_publico as
select
  cp.id,
  cp.nombre,
  cp.slug,
  cp.categoria_codigo,
  cc.nombre        as categoria_nombre,
  cc.color_fuerte,
  cc.color_claro,
  cc.color_sombra,
  cp.detalle_presentacion,
  cp.hook_corto,
  cp.imagen_banner_path,
  cp.caracteristica_adicional,
  cp.precio_venta,
  cp.hook_largo,
  cp.por_que_magandhi,
  cp.sobre_este_producto,
  cp.ficha_tecnica,
  cp.imagenes,
  cp.sello_elegido,
  cp.estrella,
  case
    when cp.product_id_ref is null then false
    when cp.tope_escaparate is not null
      then least(coalesce(ex.existencias, 0), cp.tope_escaparate) <= 0
    else coalesce(ex.existencias, 0) <= 0
  end as agotado,
  cp.aviso_urgencia_activo,
  cp.aviso_urgencia_cantidad,
  cp.orden
from campana_producto cp
left join campana_categoria cc on cc.codigo = cp.categoria_codigo
left join (
  select
    m.product_id,
    sum(
      case m.tipo
        when 'entrada'        then  m.cantidad
        when 'ajuste_entrada' then  m.cantidad
        when 'salida'         then -m.cantidad
        when 'ajuste_salida'  then -m.cantidad
      end
    )::integer as existencias
  from movimientos_inventario m
  group by m.product_id
) ex on ex.product_id = cp.product_id_ref
where cp.publicado = true
  and cp.activo = true;

comment on view catalogo_publico is 'CAMPANAS · vista publica SEGURA que lee la tienda (magandhi.com) sin login. Vista del DUENO a proposito (no security_invoker): es la unica superficie publica; su candado es la lista blanca de columnas + publicado=true y activo=true. Expone el booleano derivado `agotado` calculado del libro movimientos_inventario (misma formula que stock_actual; desde Tramo 0 NO depende de stock_actual, que ahora es security_invoker y romperia la lectura anonima). Con tope de escaparate: agotado = least(existencias, tope) <= 0; sin tope: existencias <= 0; sin product_id_ref: false. JAMAS expone existencias, tope_escaparate, product_id_ref, es_placeholder, costo, proveedor ni etiquetas.';

-- Cinturon de seguridad: create or replace conserva los grants, pero se
-- re-otorgan explicitamente los tres roles que la leen (tienda anon, panel
-- authenticated, Edge Function service_role). Idempotente.
grant select on catalogo_publico to anon, authenticated, service_role;

-- ------------------------------------------------------------
-- (2) Las tres vistas internas pasan a SECURITY INVOKER.
-- alter view ... set no recrea la vista: conserva definicion y grants.
-- ------------------------------------------------------------
alter view movimientos_mayor set (security_invoker = true);
alter view saldos_cuenta     set (security_invoker = true);
alter view stock_actual      set (security_invoker = true);

comment on view movimientos_mayor is 'Detalle del Libro Mayor: una fila por linea de asiento ACTIVO. SECURITY INVOKER (Tramo 0): ejecuta con los permisos de quien consulta, asi la RLS de asientos/asiento_lineas/puc_cuentas (tiene_modulo(finanzas)) aplica de verdad. Derivado del diario; nunca se escribe a mano.';
comment on view saldos_cuenta is 'Saldo por cuenta derivado de los asientos ACTIVOS (debito: debe-haber; credito: haber-debe). SECURITY INVOKER (Tramo 0): hereda de verdad la RLS de finanzas. Montos bigint.';
comment on view stock_actual is 'Existencias por producto DERIVADAS del libro de movimientos. SECURITY INVOKER (Tramo 0): hereda de verdad la RLS de productos/movimientos_inventario (inventario o marketing). NO la usa catalogo_publico (calcula su propio agregado). Las existencias pueden ser negativas (senal honesta de reconciliacion).';

commit;
