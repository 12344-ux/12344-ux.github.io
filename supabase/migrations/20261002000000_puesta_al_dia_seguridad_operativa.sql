-- ============================================================
-- PUESTA AL DIA · seguridad operativa acumulativa
-- Fecha: 2026-10-02
--
-- Corrige cuatro desalineaciones sin reescribir migraciones historicas:
--   1. Una campana sin producto de Inventario ya no puede parecer comprable.
--   2. Publicar exige producto ligado, activo y precio positivo.
--   3. Finanzas elimina policies de escritura directa: toda escritura sigue RPC.
--   4. Marketing obtiene DELETE acotado en Storage para compensar huerfanos.
--
-- REQUISITO: aplicar despues de todas las migraciones 20250606*.
-- DESPLIEGUE: ejecutar UNA vez en SQL Editor y registrar evidencia.
-- ============================================================

begin;

-- ------------------------------------------------------------
-- (1) Catalogo publico: sin Inventario ligado = agotado/no comprable.
-- Conserva exactamente la lista blanca y el orden de columnas vigentes.
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
    when cp.product_id_ref is null then true
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

comment on view catalogo_publico is 'CAMPANAS · superficie publica de lista blanca para magandhi.com. Solo filas publicado=true y activo=true. agotado se deriva del libro movimientos_inventario; una campana sin product_id_ref se considera agotada/no comprable. Nunca expone existencias, tope, product_id_ref, placeholders, costos, proveedor ni etiquetas.';

grant select on catalogo_publico to anon, authenticated, service_role;

-- ------------------------------------------------------------
-- (2) Publicacion: doble defensa antes de exponer una campana.
-- Los borradores pueden existir incompletos; la validacion aplica al publicar.
-- ------------------------------------------------------------
create or replace function cm_publicar_campana(
  p_id        uuid,
  p_publicado boolean
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_producto_id     uuid;
  v_precio          bigint;
  v_producto_activo boolean;
begin
  if not tiene_acceso_marketing() then
    raise exception 'Acceso denegado: se requiere el modulo marketing.';
  end if;

  select cp.product_id_ref, cp.precio_venta, p.activo
    into v_producto_id, v_precio, v_producto_activo
    from campana_producto cp
    left join productos p on p.id = cp.product_id_ref
   where cp.id = p_id;

  if not found then
    raise exception 'La campana % no existe.', p_id;
  end if;

  if coalesce(p_publicado, false) then
    if v_producto_id is null then
      raise exception 'No se puede publicar: liga primero un producto de Inventario.';
    end if;
    if coalesce(v_producto_activo, false) is not true then
      raise exception 'No se puede publicar: el producto de Inventario esta inactivo.';
    end if;
    if v_precio is null or v_precio <= 0 then
      raise exception 'No se puede publicar: define un precio de venta mayor que cero.';
    end if;
  end if;

  update campana_producto
     set publicado   = coalesce(p_publicado, false),
         actualizado = now()
   where id = p_id;

  return p_id;
end;
$$;

comment on function cm_publicar_campana(uuid, boolean) is 'CAMPANAS · publica/despublica sin borrar. Para publicar exige acceso Marketing, producto de Inventario ligado y activo, y precio_venta positivo. Despublicar siempre queda permitido.';

revoke execute on function cm_publicar_campana(uuid, boolean) from public, anon;
grant execute on function cm_publicar_campana(uuid, boolean) to authenticated, service_role;

-- ------------------------------------------------------------
-- (3) Finanzas RPC-only: retirar puertas latentes de escritura directa.
-- Los SECURITY DEFINER vigentes no necesitan estas policies.
-- ------------------------------------------------------------
drop policy if exists "asientos_insert_modulo" on asientos;
drop policy if exists "asientos_update_modulo" on asientos;
drop policy if exists "asiento_lineas_insert_modulo" on asiento_lineas;
drop policy if exists "asiento_lineas_update_modulo" on asiento_lineas;
drop policy if exists "asiento_bitacora_insert_modulo" on asiento_bitacora;

-- ------------------------------------------------------------
-- (4) Storage: la compensacion de Campanas puede borrar SOLO en su bucket.
-- Las subidas usan keys aleatorias y upsert=false; no se concede UPDATE.
-- ------------------------------------------------------------
drop policy if exists "campanas_delete_marketing" on storage.objects;
create policy "campanas_delete_marketing"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'campanas'
  and public.tiene_acceso_marketing()
);

commit;
