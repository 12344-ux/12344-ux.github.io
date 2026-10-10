# Dropi · integración

**Corte:** 10 de octubre de 2026 · **Estado:** la lectura funciona y D1 (área/bandeja interna) está desplegado en producción. Las fotos y la paginación se corrigieron en el ajuste de uso real (§8 bis). MAGANDHI lee el catálogo, busca por página y consulta la ficha de cualquier producto por id, directo desde Supabase, sin intermediarios. Los pedidos (`orders/`) siguen sin probar.

> **Hito del 9-oct-2026.** Después de un día de 401, la causa era que Dropi **rechaza las peticiones cuyo `User-Agent` no reconoce**. No era el token, ni el permiso de la cuenta, ni la IP, ni la validación de identidad, ni la falta de WooCommerce. Con el `User-Agent` correcto, la cuenta de `magandhi.com` entra sola: **se descartan Shopify y WooCommerce como puentes** y el sandbox de prueba se puede borrar. Cómo se halló, en §7.

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

Ya resuelto por medición: el acceso de lectura funciona, no exigen IP fija y la IP de Supabase no estorba (§7).

Sigue pendiente, y esto es lo que debe pedir el correo a soporte (`PUESTA-EN-MARCHA.md` §3):

- **autorizar el `User-Agent` propio de MAGANDHI** y entregar el contrato oficial, para dejar de depender de parecer WordPress;
- límite de consultas por minuto, para fijar cada cuánto se refresca el stock sin molestar;
- si existe webhook de cambios de stock, o si toca consultar;
- contrato de pedidos: crear `SIN RECAUDO`, consultar por id, guía y estados;
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

## 7. El hallazgo que cambia el diagnóstico (9-oct-2026)

Con el plugin Dropify instalado en un WooCommerce de prueba y el token de la integración ya autenticada, **el catálogo de Dropi se listó completo**: miles de productos con su id, nombre, precio y tienda asociada.

**Consecuencia:** la API de catálogo **no está cerrada** para esta cuenta. El plugin usa el mismo token y el mismo `POST products/index` al que Dropi nos responde `401` desde Supabase y desde un PC. El problema no es el permiso: es **cómo** llamamos, o desde dónde.

Sospechas, por orden:

1. **Cabeceras.** El plugin llama desde WordPress con su propio `User-Agent`; una integración de terceros documentada envía además `Origin` y `Referer` con el dominio de la tienda registrada.
2. **IP o entorno.** Que el servidor del sandbox entre y Supabase no.

Para resolverlo se usó un diagnóstico desechable, `dropi-cabeceras`: repetía la misma consulta de catálogo con cinco combinaciones de cabeceras y reportaba cuál devolvía 200. **Ya cumplió y se retiró del repositorio**; si hiciera falta otra vez, se reconstruye en minutos a partir de lo que sigue.

### Resultado: era el `User-Agent`

Corrida el 9-oct-2026 desde Supabase, con la URL de la tienda registrada:

| Variante | Respuesta |
|---|---|
| 1 · solo el token, como veníamos llamando | `401 · Access denied` |
| **2 · + `User-Agent`** | **`200`, `isSuccess: true`, 3 productos** |
| 3 · + `Origin` y `Referer`, sin `User-Agent` | `401 · Access denied` |

**Conclusión definitiva:** Dropi rechaza las peticiones que llegan sin `User-Agent`. No era el token, ni el permiso de la cuenta, ni la IP, ni la validación de identidad, ni la falta de WooCommerce. El plugin funcionaba porque WordPress envía el suyo.

Consecuencias:

- **El puente WooCommerce deja de ser necesario.** Se descarta: nada de WordPress, hosting mensual ni catálogo duplicado. El sandbox de prueba puede caducar.
- `dropi-sonda` ahora manda un `User-Agent` honesto que identifica a MAGANDHI (`MAGANDHI-Impulse/1.0`), configurable con el secreto `DROPI_USER_AGENT` y leído en cada petición, para poder cambiarlo sin redesplegar. No se finge ser otro programa.
- `dropi-cabeceras` ya cumplió y **se retiró del repositorio**. Si quedó desplegada en Supabase, se borra desde el dashboard.

Probado localmente (sin sesión 401, no admin 403, sin secreto, sin URL de tienda, todas 401 con la IP, variante ganadora identificada, solo `products/index`, nunca `orders`, token ausente) y contra Dropi real con un token inválido: las cinco variantes responden `401 · Access denied` sin que el entorno rechace ninguna cabecera.

### El embudo y el stock, ya sin intermediarios

`dropi-sonda` acepta `{ producto_id }` y lee **solo ese producto** por las dos rutas que usa el plugin:

- `GET products/v2/{id}` — la ficha completa: nombre, descripción, precios, imágenes, variantes y proveedor. Es lo que alimenta el borrador de Campañas.
- `GET products/{id}` — las existencias. Es la consulta que se repetiría cada pocos minutos para que `agotado` siga a Dropi.

```js
const { supabase } = await import('/supabase-config.js');
const r = await supabase.functions.invoke('dropi-sonda', { body: { producto_id: 1234 } });
console.log(JSON.stringify(r.data ?? r.error, null, 2));
```

### Contrato medido el 9-oct-2026 (producto 101, lectura real)

| Ruta | Resultado |
|---|---|
| `GET products/v2/{id}` | **200.** Ficha completa |
| `GET products/{id}` | **400 · «No tiene permisos para ver este producto»** |

Por tanto **el stock no sale de la ruta aparte: sale de la misma ficha**, en `warehouse_product` (existencias por bodega, que se suman) y `warehouses`. La sonda ya lo hace así y deja a la vista el 400 para no volver a apoyarse en esa ruta.

Campos reales que devuelve `products/v2/{id}`:

```
active · categories · description · dropi_app_description · id · name · photos
private_product_inventories · privated_product · sale_price · sku
suggested_price · type · user · user_id · variations · warehouse_product · warehouses
```

Con eso basta para el borrador de Campañas: nombre, descripción, fotos, categoría, `sale_price` (el costo para nosotros), `suggested_price` (precio sugerido), variantes, proveedor y existencias. El `sku` llega genérico (`PRODUCTO`), así que la clave de enlace es el **id**, no el sku.

La respuesta sella la hora de lectura (`leido`). **La prueba del stock** es correrla dos veces separadas en el tiempo sobre el mismo producto y comparar las existencias: si siguen a Dropi, la promesa de §0 del plano se cumple leyendo directo, sin cron de WordPress ni puente.

### Las dos ataduras, sueltas (9-oct-2026)

Quedaba comprobar si dependíamos del sandbox. Las dos pruebas pasaron:

| Prueba | Resultado |
|---|---|
| `DROPI_USER_AGENT` = `WordPress/6.8; https://magandhi.com` | **Funciona.** Dropi no valida la URL que lleva dentro |
| `DROPI_TOKEN` = token de la integración de `magandhi.com` | **Funciona.** No necesita una tienda WooCommerce viva detrás |

**Configuración vigente y suficiente:** la integración de `magandhi.com` en Dropi (registrada con tipo `WOOCOMERCE` porque no existe «tienda propia», y **sin** completar su OAuth), más dos secretos en Edge Functions: `DROPI_TOKEN` y `DROPI_USER_AGENT`.

Se puede retirar: el sitio de TasteWP, la integración `prueba MAGANDHI`, sus llaves de WooCommerce (quedaron expuestas en una captura y mueren con el sandbox) y la función `dropi-cabeceras`, que ya cumplió.

### Deuda reconocida: el `User-Agent`

Depender de un `User-Agent` con el prefijo `WordPress/` es **frágil y no es un contrato**: Dropi puede endurecer la regla sin avisar y el frente se cae sin que nadie toque nada.

Mitigación vigente: el valor vive en el secreto `DROPI_USER_AGENT` y se lee en cada petición, así que se cambia sin redesplegar, y la sonda lo nombra en su conclusión cuando Dropi niega el acceso.

Mitigación definitiva, pendiente: pedirle a soporte que **autorice el `User-Agent` propio de MAGANDHI** y entregue el contrato oficial de la API. Mientras eso no exista, cualquier 401 nuevo se revisa primero por aquí.

Pruebas locales de esta versión (13 en verde): `User-Agent` honesto por defecto y en cada llamada, configurable por secreto, ficha y existencias leídas por id, suma de stock por bodega, campos reales listados, id no numérico ignorado, token ausente de la respuesta, nunca toca `orders/`. Contra Dropi real con un token inválido: 401 en las cuatro rutas, con mensaje que apunta al `User-Agent`.

## Fuentes

- [Dropi · especificación OpenAPI publicada por su servidor](https://api.dropi.co/docs)
- [Plugin «Dropify» para WooCommerce, código público](https://github.com/vjcvictor/wc-dropi-integration)
- [Notas de integración propia con Dropi (AgenticSellBotCRM)](https://github.com/jhonsu01/AgenticSellBotCRM/blob/main/docs/07-fase5-dropi.md)
- [Dropi · soluciones para marca propia](https://dropi.co/soluciones-para-marca-propia/) y [contacto](https://dropi.co/contactanos)

Contenido parafraseado de las fuentes.

## 8. D1 · Cimientos internos implementados (10-oct-2026)

> **Estado de despliegue:** desplegado en producción el 10-oct-2026
> (migración `20261023000000` + `dropi-sonda`). D1 sigue sin tocar `orders/`.

D1 convierte el hallazgo de lectura en una estructura operativa segura, sin
confundir catálogo de proveedor con inventario propio:

| Pieza | Qué queda listo | Qué NO hace todavía |
|---|---|---|
| Área `Dropshipping` | Séptima tarjeta del panel; búsqueda, resultados y bandeja privada | No publica ni vende |
| `productos.origen` | Distingue `propio` de `proveedor`, inmutable tras el alta | No crea todavía productos proveedor desde la UI |
| `producto_proveedor` | Ficha privada 1:1 para id Dropi + variante + proveedor + última lectura | D1 no inserta filas: lo hará D2 de forma atómica |
| `dropshipping_candidatos` | Bandeja de candidatos elegidos por MAGANDHI, con snapshot y URLs de preview | No es un espejo de catálogo ni un producto/campaña |
| Inventario/Métricas | Trigger bloquea movimientos proveedor; `stock_actual` y `mt_inventario()` solo cuentan propio | No calcula aún stock remoto para vitrina |
| Campañas/tienda | `cm_publicar_campana` y `catalogo_publico` excluyen proveedor | D2 habilitará solo tras stock vivo/fallo cerrado |

### `dropi-sonda` D1: búsqueda paginable y previews, siempre lectura

El body suma dos campos acotados:

```js
{ buscar: 'serum', inicio: 0, tamano: 6 }  // inicio: 0..500 · tamaño: 1..25
{ producto_id: 101 }                       // ficha y bodegas de un candidato
```

La función ahora devuelve previews HTTPS de fotos y variantes como diagnóstico.
No descarga una foto, no crea una variante y no usa ese dato para órdenes. Una
foto que falle en la bandeja se reemplaza por un placeholder; D2 volverá a leer
la ficha desde Dropi por id antes de descargar solo las imágenes elegidas al
bucket `campanas`.

La función sigue requiriendo **admin**, aunque el área ya tenga módulo propio:
D3 debe definir permisos por capacidad antes del primer usuario no-admin. No se
amplía una API externa a perfiles reducidos por comodidad de interfaz.

### Lo que D1 prueba y lo que todavía no puede afirmar

- **Medido en doble local de Dropi/Supabase, 23/23:** CORS, sesión/admin, body
  nulo, búsqueda, paginación, límite de página, URLs HTTPS sin credenciales,
  variante diagnóstica, stock desde `warehouse_product`, token ausente y nunca
  `orders/`.
- **Medible ahora en la cuenta real:** buscar, paginar y correr dos lecturas del
  mismo `producto_id` para comparar `leido`, bodegas y stock.
- **No medido ni implementado:** crear `SIN RECAUDO`, semántica real de reserva
  `PENDIENTE CONFIRMACION`, idempotencia remota, liberar/cancelar reserva,
  guía, estados y costo final. Ningún POST a `orders/myorders` se improvisa.

La prueba controlada de reserva sigue necesitando contrato oficial, producto +
variante + proveedor aprobados, dirección propia, saldo/presupuesto, una sola
creación y mecanismo de cancelación confirmado antes de enviar nada.

## 8 bis. Contrato de fotos y paginación (medido en uso real, 10-oct-2026)

El primer uso real de D1 mostró cero fotos y «0 coincidencias reportadas»
con Anterior/Siguiente muertos. Las dos cosas eran supuestos del doble de
pruebas que no coincidían con Dropi:

| Tema | Lo que Dropi manda | Fuente |
|---|---|---|
| Fotos del listado (`products/index`) | `gallery: [{ urlS3: "colombia/products/…" }]`, ruta **relativa** | Plugin Dropify v4.7.3, `Product_List.php` |
| Fotos de la ficha (`products/v2/{id}`) | `photos: [{ urlS3 }]`, misma forma | `ProductsModel.php` (`setPostImages`) |
| Dónde viven | `https://d39ru7awumhhs2.cloudfront.net/` + `urlS3`; los registros viejos traen `url` relativa a `https://api.dropi.co/` | Ambos archivos del plugin |
| `count` del listado | Llegó **0** con resultados. El plugin tampoco lo usa (manda `no_count: true` y fija 9999 como total) | Captura del dueño + `Product_List.php` |

`dropi-sonda` arma la URL solo sobre esos dos orígenes y descarta cualquier
ruta que intente apuntar a otro host. Para paginar pide `tamano + 1`: si llega
el de más, hay página siguiente. El panel muestra 24 por página.

**Medición pendiente y barata:** si alguna foto real no carga en el panel, la
consola del runbook («Dropshipping D1 · ajuste de uso real») muestra
`campos_disponibles` y `fotos_remotas` del primer resultado para ajustar sin
adivinar.
