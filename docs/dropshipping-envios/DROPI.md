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

Responde la pregunta grande con evidencia: **¿producción nos acepta?**

El token sale de Dropi → Mis Integraciones → tipo **WOOCOMERCE**, porque no hay un tipo «tienda propia». El plugin de WooCommerce solo envía ese token por HTTP, igual que lo hace nuestra función.

**Qué hace `supabase/functions/dropi-sonda`:**

- `GET categories/` y `POST products/index`, que es la búsqueda del catálogo que usa el plugin: lleva filtros, no crea nada;
- nunca llama a `orders/`, no escribe en la base y no guarda nada;
- solo la puede usar un admin con sesión, y el token nunca sale en la respuesta ni en los logs;
- devuelve si entramos, la IP desde la que nos vio Dropi (cuando niega el acceso), los campos que trae un producto y una muestra de 5 productos.

**Comportamiento medido el 9-oct-2026, con un token inválido:** Dropi responde `401 · Access denied` y devuelve la IP de origen. Con eso, si nos niegan, se sabe qué IP pedir que autoricen.

**Cómo correrla:**

1. Supabase → Edge Functions → **Deploy a new function** → nombre exacto `dropi-sonda` → pegar `supabase/functions/dropi-sonda/index.ts` → Deploy. **Verify JWT: encendido.**
2. Abrir `https://montaguth.institute/panel.html` con la sesión de admin → F12 → Consola → pegar:

   ```js
   const { supabase } = await import('/supabase-config.js');
   const r = await supabase.functions.invoke('dropi-sonda', { body: { buscar: '' } });
   console.log(JSON.stringify(r.data ?? r.error, null, 2));
   ```

   En `buscar` se puede poner una palabra, por ejemplo `'shampoo'`.
3. Leer `conclusion`. La respuesta no trae el token y se puede compartir con Kiro.

| Resultado | Qué sigue |
|---|---|
| `conectado: true` | Diseñar el arrastre de productos con `campos_disponibles` y la `muestra` |
| `Access denied` con IP | Revisar que el secreto sea el token de la tienda. Si lo es, pedirle a soporte que autorice el acceso. Las IP de Supabase no son fijas: puede hacer falta el intermediario de §3 |

**Resultado real, 9-oct-2026 (token de Mis Integraciones, tipo WOOCOMERCE):**

| Desde | Respuesta |
|---|---|
| Supabase (IP de Amazon) | `401 · Access denied` en `categories/` y en `products/index` |
| PC del dueño (IP de casa en Colombia) | `401 · No autorizado` en `categories/` |

**Conclusión:** no es solo un bloqueo por IP. Ese token, por sí solo, no abre la API de `integrations/` para esta cuenta. Hay que pedirle a soporte que habilite el acceso (`PUESTA-EN-MARCHA.md` §3). El token quedó visible en una captura: hay que generar uno nuevo antes de usarlo en serio.

**Mientras tanto, sin API:** se publican a mano los pocos productos curados y cada pedido se crea a mano en el panel de Dropi como pagado (sin recaudo).

Pruebas locales hechas, con Dropi simulado y también contra Dropi real con un token inválido: sin sesión 401, no admin 403, sin secreto, acceso negado con IP, conexión correcta con muestra; nunca toca `orders/` y el token no aparece en la respuesta.

## Fuentes

- [Plugin «Dropify» para WooCommerce, código público](https://github.com/vjcvictor/wc-dropi-integration)
- [Notas de integración propia con Dropi (AgenticSellBotCRM)](https://github.com/jhonsu01/AgenticSellBotCRM/blob/main/docs/07-fase5-dropi.md)
- [Dropi · soluciones para marca propia](https://dropi.co/soluciones-para-marca-propia/) y [contacto](https://dropi.co/contactanos)

Contenido parafraseado de las fuentes.
