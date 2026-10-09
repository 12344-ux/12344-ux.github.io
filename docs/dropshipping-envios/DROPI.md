# Dropi · integración

**Corte:** 9 de octubre de 2026 · **Estado:** investigación. **Dropi todavía no ha confirmado nada de esto.**

## 1. Lo que se sabe

Dropi publica una especificación OpenAPI **parcial** en `https://api.dropi.co/docs`: documenta el login de integraciones, `whoiam` y unas pocas lecturas, pero no el contrato completo de catálogo y pedidos. Lo demás sale de:

- el plugin vigente de WooCommerce «Dropify» v4.7.3 (jul-2026);
- el código actual de la pantalla «Mis Integraciones» de Dropi (9-oct-2026);
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
6. **Hay dos flujos distintos bajo el nombre WooCommerce:**
   - el plugin Dropify antiguo/vigente guarda localmente el token y llama a `api.dropi.co/integrations/`;
   - la pantalla actual «Mis Integraciones» espera una tienda WooCommerce real: construye `{url}/wc-auth/v1/authorize`, pide alcance `read_write` y devuelve las credenciales a Dropi. En `https://magandhi.com` esa ruta responde 404 porque MAGANDHI no es WordPress.

Por eso registrar el dominio principal como `WOOCOMERCE` fue una prueba útil, pero **no es una integración válida ni el diseño final**. Puede explicar que el token quede sin activar. No se instala WooCommerce sobre la tienda principal.

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

El token probado salió de Dropi → Mis Integraciones → tipo **WOOCOMERCE**, porque no había un tipo «tienda propia». Después se comprobó que el flujo actual de ese tipo exige una tienda WooCommerce real por OAuth. La sonda sigue siendo válida para medir el acceso del token, pero esa integración se considera **solo una prueba diagnóstica**, no la solución.

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

**Resultado real, 9-oct-2026 (cuenta ya verificada):**

| Prueba | Respuesta |
|---|---|
| Token inicial desde Supabase (IP de Amazon) | `401 · Access denied` en `categories/` y `products/index` |
| Token inicial desde PC del dueño (IP residencial en Colombia) | `401 · No autorizado` en `categories/` |
| `POST /integrations/login` con la cuenta | **Éxito:** Dropi aceptó usuario y contraseña y expidió JWT |
| JWT anterior contra `GET /api/categories` | `401 · No autorizado` |
| Validación de identidad | Completada con documento y fotografías; facturación electrónica aún pendiente |
| Integración recreada después de validar, tipo `WOOCOMERCE`, URL `https://magandhi.com` | Token nuevo expedido |
| Token nuevo desde Supabase y desde el PC | `401 · Access denied` / `401 · No autorizado` |

**Conclusión corregida tras revisar el flujo actual de Dropi:** no es Brave, CORS, Supabase, la IP, un error de copiado, el token anterior ni la validación de identidad. **Sí existe una ruptura real:** `magandhi.com` fue registrada como WooCommerce, pero no expone el OAuth de WooCommerce; `https://magandhi.com/wc-auth/v1/authorize` responde 404. Por tanto, no se puede considerar ese token una prueba limpia de que Dropi rechaza a MAGANDHI: la integración WooCommerce quedó incompleta por diseño.

La solución final no es instalar WooCommerce sobre la tienda principal. Shopify queda descartado. WooCommerce se admite únicamente como **prueba aislada y desechable de un producto**: si completa OAuth, importa correctamente y ofrece stock actualizable, puede evaluarse como conector oculto; si falla cualquiera, se retira. La vía preferida sigue siendo acceso directo y mínimo de solo lectura por id. No se automatiza el panel privado ni se eluden sus controles.

El token inicial quedó visible en una captura y fue sustituido por uno nuevo después de validar la cuenta.

**Mientras tanto, sin API:** se publican a mano los pocos productos curados y cada pedido se crea a mano en el panel de Dropi como pagado (sin recaudo).

Pruebas locales hechas, con Dropi simulado y también contra Dropi real con un token inválido: sin sesión 401, no admin 403, sin secreto, acceso negado con IP, conexión correcta con muestra; nunca toca `orders/` y el token no aparece en la respuesta.

## Fuentes

- [Dropi · especificación OpenAPI publicada por su servidor](https://api.dropi.co/docs)
- [Plugin «Dropify» para WooCommerce, código público](https://github.com/vjcvictor/wc-dropi-integration)
- [Notas de integración propia con Dropi (AgenticSellBotCRM)](https://github.com/jhonsu01/AgenticSellBotCRM/blob/main/docs/07-fase5-dropi.md)
- [Dropi · soluciones para marca propia](https://dropi.co/soluciones-para-marca-propia/) y [contacto](https://dropi.co/contactanos)

Contenido parafraseado de las fuentes.
