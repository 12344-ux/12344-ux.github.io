-- ============================================================
-- MAGANDHI · PUESTA AL DIA (forward) · solo los huecos reales
-- ------------------------------------------------------------
-- POR QUE EXISTE ESTA MIGRACION (leer antes de tocar nada):
--
-- La migracion 20261002000000_puesta_al_dia_seguridad_operativa.sql quedo
-- escrita el 2-oct-2026 pero NUNCA se aplico en produccion. Entre esa fecha y
-- hoy se aplicaron varias migraciones mas y una de ellas, 20261003000000
-- (campanas · jubilar hook_corto y reordenar), hizo:
--     drop view if exists catalogo_publico;  create view catalogo_publico as ...
-- es decir, RECREO la vista con una version MAS NUEVA (sin la columna
-- hook_corto, que se jubilo a proposito) que ya incluye la regla "una campana
-- sin product_id_ref se considera agotada/no comprable".
--
-- Consecuencia: aplicar hoy la del 2-oct seria un RETROCESO (devolveria la
-- vista a la version vieja y reviviria hook_corto). Por eso 20261002000000
-- queda marcada como SUPERADA y NO APLICABLE, y su contenido vigente se
-- re-emite aqui en forma forward, OMITIENDO por completo la parte (1) de la
-- vista.
--
-- Estado de produccion MEDIDO el 8-oct-2026 (consulta de solo lectura), que es
-- lo que esta migracion viene a corregir:
--     publicar_con_candado        = false   -> (2) falta
--     finanzas_puertas_latentes   = 5       -> (3) falta
--     storage_borrado_ok          = false   -> (4) falta
--     vista_es_la_del_3oct        = true    -> (1) YA ESTA: no se toca
--
-- Contenido: solo (2), (3) y (4). NADA de la vista catalogo_publico.
-- Idempotente y segura tanto en el estado de produccion (sin la del 2-oct)
-- como en un entorno donde la del 2-oct si se aplico: create or replace +
-- drop policy if exists hacen que el resultado final sea el mismo.
-- ============================================================

-- ------------------------------------------------------------
-- (2) Publicacion: doble defensa antes de exponer una campana.
-- Los borradores pueden existir incompletos; la validacion aplica al PUBLICAR.
-- Importa para Wompi F2: un pago aprobado crea pedido y baja stock, asi que una
-- campana publicada SIN producto de Inventario ligado seria vender algo que no
-- tiene existencias detras.
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

comment on function cm_publicar_campana(uuid, boolean) is 'CAMPANAS · publica/despublica sin borrar. Para publicar exige acceso Marketing, producto de Inventario ligado y activo, y precio_venta positivo. Despublicar siempre queda permitido. Re-emitida forward en 20261018000000 (la 20261002000000 quedo superada y no aplicable).';

revoke execute on function cm_publicar_campana(uuid, boolean) from public, anon;
grant execute on function cm_publicar_campana(uuid, boolean) to authenticated, service_role;

-- ------------------------------------------------------------
-- (3) Finanzas RPC-only: retirar puertas latentes de escritura directa.
-- Los SECURITY DEFINER vigentes (guardar_asiento, editar_asiento,
-- anular_asiento) no necesitan estas policies: escriben con sus propios
-- privilegios. Dejarlas es superficie de ataque sin uso.
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
