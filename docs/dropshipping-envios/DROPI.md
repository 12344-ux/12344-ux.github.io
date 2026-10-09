# Dropi · integración

**Corte:** 9 de octubre de 2026 · **Estado:** investigación. **Dropi todavía no ha confirmado nada de esto.**

## 1. Lo que se sabe

Dropi no publica documentación de su API. Lo que sigue sale de código y notas públicas de terceros (ver Fuentes):

- el plugin de WooCommerce «Dropify» v4.6.9 (feb-2025);
- las notas de otro equipo que conectó un sistema propio (ago-2026).

| Tema | Lo observado |
|---|---|
| Base (Colombia) | `https://api.dropi.co/integrations/` |
| Autenticación | Encabezado `dropi-integration-key` con el token de la tienda. Según el plugin, el token se genera al crear la tienda en «Mis tiendas» |
| Lecturas | `GET products/v2/`, `GET products/`, `GET categories/`, `GET warehouses/` |
| Crear pedido | `POST orders/myorders` |
| Consultar un pedido | `GET orders/myorders/{id}` |
| Ambientes | Desarrollo (`dev-api.dropi.co`) abierto, sin trámite. A ese equipo, producción le respondía «Access denied» mientras no tuviera una habilitación formal, y la solicitud exige **IP fija**. En sus notas aún no la tenía |

**Campos del pedido** que envía el plugin:

- comprador: `name`, `surname`, `dir`, `country`, `state`, `city`, `phone`, `client_email`;
- pedido: `total_order`, `notes`, `products` (con `id` y `variation_id`), `supplier_id`;
- `rate_type`: `CON RECAUDO` (contraentrega) o `SIN RECAUDO` (ya pagado);
- `status`: `PENDIENTE CONFIRMACION`, que es un borrador que no se despacha;
- otros: `type` (`FINAL_ORDER`), `shop_order_id` (el número de pedido de la tienda), `calculate_costs_and_shiping`.

La respuesta trae `isSuccess` y `message`.

## 2. Trampas conocidas

1. **`orders/myorders` cambia según el verbo:** `GET` consulta, `POST` crea. Un `POST` usado para consultar intenta crear un pedido real.
2. **El listado no muestra los borradores** (`PENDIENTE CONFIRMACION`). Para verificar una creación hay que consultar por id. Si uno se fía del listado, reintenta y duplica el pedido.
3. **Dropi normaliza los datos:** ciudad y departamento en mayúsculas, teléfono sin «+». No hay que compararlos con lo enviado para saber si se guardó bien.
4. **No se conoce un aviso de estado ni de guía.** En el plugin no hay código que traiga de vuelta la guía ni los estados.
5. **Variantes:** sin `variation_id`, Dropi no sabe qué unidad despachar.

## 3. Lo que falta confirmar con Dropi

Las preguntas exactas están en `PUESTA-EN-MARCHA.md` §3:

- acceso a producción para una tienda propia y documentación oficial;
- **IP fija:** nuestras Edge Functions no tienen IP fija. Si Dropi la exige, hará falta un intermediario pequeño con IP fija que solo reenvíe a Dropi;
- ambiente de pruebas;
- avisos de estado y de guía, o cada cuánto se puede consultar;
- cobro en pedidos sin recaudo: saldo (wallet), recarga y comisión;
- remitente en la guía y contenido del paquete (sin factura, precios ni publicidad del proveedor);
- devoluciones y garantías en pedidos ya pagados.

## 4. Cómo se mueve el dinero (pago por adelantado)

1. El cliente paga el total en la tienda con Wompi. Wompi descuenta su comisión (cerca del 4,3 % en la venta del 9-oct) y abona el resto.
2. MAGANDHI recarga su saldo en Dropi. *Cómo, por confirmar.*
3. Por cada pedido, Dropi descuenta del saldo el costo del proveedor y el flete. *Por confirmar.*
4. **Margen de MAGANDHI** = precio − costo del proveedor − flete − comisión de Wompi − comisión de Dropi, si la hay.

Las cuentas contables de los pasos 2 y 3 las define el contador (`PUESTA-EN-MARCHA.md` §6).

## 5. Flujo previsto

```
pago aprobado (wompi-webhook, ya en producción)
  -> pedido web con crear_pedido + correo «Recibido» (ya en producción)
  -> aviso en Ventas: «Pedido de proveedor por confirmar»
  -> el dueño lo revisa y lo confirma con un clic
  -> Edge Function: POST orders/myorders (SIN RECAUDO, shop_order_id = pedidos.id)
  -> verificación por id: GET orders/myorders/{id}
  -> consulta periódica del estado y la guía
  -> guía en el pedido + correo «En camino» con el rastreo
```

Reglas:

- **Nunca se reintenta una creación sin consultar antes por id.**
- **`shop_order_id` = `pedidos.id`**, para tener rastro en ambos sentidos.
- **Si Dropi falla, el pedido no se pierde:** queda con aviso rojo en Ventas, como hoy los pagos sin pedido.

## 6. La primera prueba: sonda de solo lectura

Cuando el token esté en Supabase (secreto `DROPI_TOKEN`), una Edge Function de solo lectura llamará `GET categories/` y `GET products/v2/`. Devolverá solo el código de respuesta y el número de resultados: no crea pedidos ni guarda datos.

Responde la pregunta grande con evidencia: **¿producción nos acepta?**

## Fuentes

- [Plugin «Dropify» para WooCommerce, código público](https://github.com/vjcvictor/wc-dropi-integration)
- [Notas de integración propia con Dropi (AgenticSellBotCRM)](https://github.com/jhonsu01/AgenticSellBotCRM/blob/main/docs/07-fase5-dropi.md)
- [Dropi · soluciones para marca propia](https://dropi.co/soluciones-para-marca-propia/) y [contacto](https://dropi.co/contactanos)

Contenido parafraseado de las fuentes.
