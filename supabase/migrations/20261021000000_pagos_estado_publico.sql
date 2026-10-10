-- ============================================================================
-- MAGANDHI · Pagos web · estado PUBLICO de una intencion, por referencia
-- ----------------------------------------------------------------------------
-- Corte: 9 de octubre de 2026. Migracion FORWARD (D0 · pendiente #3 de
-- CONTEXTO-MAGANDHI.md §9).
--
-- EL PROBLEMA QUE RESUELVE
--   Cuando Wompi devuelve a quien compro a la tienda, la ficha del producto se
--   ve EXACTAMENTE igual que antes y el boton 'Comprar ahora' sigue activo. La
--   persona no tiene como saber si su pago entro, asi que puede volver a pagar.
--   Con la tienda en produccion (entorno = 'prod') eso es un cobro doble real.
--
--   La tienda ya recibe la referencia de vuelta en la URL (?ref=...), porque
--   crear-intencion-pago la pone en url_redireccion. Lo que falta es una forma
--   de preguntar "¿en que quedo ESTA referencia?" sin inventarse la respuesta.
--
-- LA DECISION DE SEGURIDAD
--   La autorizacion es la POSESION de la referencia, igual que en opiniones la
--   autorizacion es la posesion de pedidos.codigo_resena. La referencia la
--   genera el servidor como MAG-<idcorto>-<epochms>-<aleatorio>: no se adivina,
--   y solo la tiene quien inicio ese pago (y Wompi).
--
--   NO se abre nada nuevo para anon. Esta funcion NO recibe grant de anon ni de
--   authenticated: la unica puerta es la Edge Function 'estado-pago', que la
--   invoca con service_role. Si algun dia esa funcion desaparece, el dato queda
--   cerrado otra vez por si solo.
--
--   Devuelve el MINIMO: en que quedo el pago, el nombre del producto y su slug.
--   Nunca el monto, el correo, el telefono, la direccion, el id del pedido, el
--   id de la transaccion, el motivo de revision ni el entorno. Quien compro ya
--   sabe cuanto pago; el resto solo serviria para filtrar datos personales a
--   quien tenga la referencia.
--
-- VOCABULARIO PUBLICO (traduccion deliberada, no se expone el interno)
--   pagos_intencion.estado      ->  lo que ve la tienda
--   ---------------------------     ----------------------------------------
--   creada                      ->  'pendiente'   el webhook aun no llega
--   procesada                   ->  'aprobado'    hay pedido y correo en camino
--   requiere_revision           ->  'revision'    el pago entro, el pedido no
--   rechazada                   ->  'rechazado'   no hubo cobro
--
--   'revision' se separa a proposito de 'aprobado': el dinero SI entro (por eso
--   nunca se le dice a la persona que su pago fallo), pero el pedido no se pudo
--   crear y ya hay un aviso rojo en Ventas. Decirle 'aprobado' seria prometer un
--   pedido que todavia no existe; decirle 'rechazado' seria mentirle.
--   Un estado desconocido cae en 'pendiente': el caso mas prudente es decir que
--   seguimos confirmando, nunca afirmar que el pago quedo listo.
--
-- REGLA DE LA CASA: esta migracion solo AGREGA una funcion. No toca
-- pagos_intencion, no toca la vista catalogo_publico, no cambia permisos
-- existentes y no reejecuta nada historico.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- (1) La funcion
-- ----------------------------------------------------------------------------
-- SECURITY DEFINER porque pagos_intencion no es legible por anon ni debe serlo.
-- STABLE porque solo lee. search_path fijo (regla del proyecto: ninguna funcion
-- definer sin search_path, para que no se la pueda secuestrar con un esquema
-- puesto adelante).
create or replace function pw_estado_publico(p_referencia text)
returns table (
  estado          text,
  nombre_producto text,
  slug            text
)
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_estado text;
  v_nombre text;
  v_slug   text;
begin
  -- Formato antes de tocar la tabla: el MISMO check que tiene
  -- pagos_intencion.referencia. Una referencia mal formada no se busca, para
  -- que la funcion no sirva de sonda contra la tabla.
  if p_referencia is null or p_referencia !~ '^[A-Za-z0-9_-]{6,64}$' then
    return;  -- cero filas: el llamador responde 404
  end if;

  select pi.estado, coalesce(pi.nombre, ''), coalesce(pi.slug, '')
    into v_estado, v_nombre, v_slug
    from pagos_intencion pi
   where pi.referencia = p_referencia;

  -- Referencia que no existe: cero filas. NO se distingue de una referencia mal
  -- formada hacia afuera (el llamador responde 404 en los dos casos), para no
  -- confirmar si una referencia dada existe o no.
  if not found then
    return;
  end if;

  return query
  select
    case v_estado
      when 'creada'            then 'pendiente'
      when 'procesada'         then 'aprobado'
      when 'rechazada'         then 'rechazado'
      when 'requiere_revision' then 'revision'
      else 'pendiente'
    end,
    v_nombre,
    v_slug;
end;
$$;

comment on function pw_estado_publico(text) is
  'PAGOS WEB · estado PUBLICO de una intencion por su referencia, para la pagina de vuelta de Wompi (D0). La autorizacion es la POSESION de la referencia (como el codigo_resena en opiniones). Devuelve el minimo: estado traducido a vocabulario publico (pendiente|aprobado|revision|rechazado), nombre del producto y slug. NUNCA monto, datos del comprador, pedido_id, transaccion_id, motivo de revision ni entorno. Solo la ejecuta service_role: la unica puerta es la Edge Function estado-pago.';

-- ----------------------------------------------------------------------------
-- (2) Permisos: explicitos, aunque el Tramo 0 ya quito el default
-- ----------------------------------------------------------------------------
-- 20250606000200_tramo0_execute_nominal.sql dejo
-- 'alter default privileges ... revoke execute on functions from public', asi
-- que una funcion nueva no deberia nacer con execute para todos. Se revoca
-- igual, explicito y por escrito: el default privilege solo aplica al rol que
-- lo configuro, y aqui la linea roja no se deja a una herencia.
revoke all on function pw_estado_publico(text) from public;
revoke all on function pw_estado_publico(text) from anon;
revoke all on function pw_estado_publico(text) from authenticated;

-- La UNICA puerta. service_role es el rol con el que corre la Edge Function.
grant execute on function pw_estado_publico(text) to service_role;
