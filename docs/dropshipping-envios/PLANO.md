# PLANO · Dropshipping y envíos

**Corte:** 9 de octubre de 2026 · **Estado:** **propuesta.** Nada aprobado ni construido. Se ajusta con las respuestas de Dropi, las cotizaciones y el contador.

## 0. La promesa

> Cada pedido pagado llega **una sola vez** a quien lo despacha, con guía y rastreo visibles para el cliente. No se vende lo que no hay, y la tienda nunca muestra proveedor ni costo.

## 1. Lo que ya existe y se reutiliza

| Pieza | Qué aporta |
|---|---|
| `crear-intencion-pago` | Una unidad por compra: una compra nunca mezcla productos propios y de proveedor |
| `wompi-webhook` + `pw_procesar_pago` | Un pago aprobado crea el pedido web una sola vez |
| `crear_pedido` | Núcleo único de pedidos, con el candado de stock (`STOCK_INSUFICIENTE`) |
| `catalogo_publico` | Lista blanca anónima. Nunca expone costo ni proveedor |
| `fz__asiento_venta_web` | Asiento automático de la venta (F3), con las cuentas de `contabilidad_config` |
| `correo_plantillas` + `enviar-correo-pedido` | Un correo por etapa del pedido |
| `pw_revisiones` | Aviso rojo en Ventas cuando algo pagado no se pudo convertir en pedido |

**Ojo:** `productos.proveedor` ya existe, pero es texto libre. No sirve para la integración.

### Decisiones del dueño (cerradas el 9-oct-2026)

1. **Sin Shopify. WooCommerce solo como prueba aislada:** nunca sobre `magandhi.com`, nunca como tienda pública ni fuente de verdad. Se autoriza un sandbox/subdominio desechable con un solo producto para medir si completa OAuth, importa bien y entrega stock actualizable.
2. MAGANDHI no replica todo el catálogo. El dueño elige un producto dentro de Dropi y pega su URL/id en **Campañas → Traer desde Dropi**.
3. Una Edge Function lee solo ese producto y crea un borrador ligado a Inventario/Campañas; el dueño lo adapta, prueba y decide si lo publica.
4. Dropi es la fuente de verdad del stock de los productos de proveedor. El inventario propio conserva su libro actual.
5. Si el dato de Dropi está vencido o Dropi no responde, la tienda falla de forma segura: «Temporalmente no disponible», nunca inventa stock.

Flujo mínimo:

```text
Dropi (el dueño elige y copia URL/id)
  -> Campañas · Traer desde Dropi
  -> borrador MAGANDHI
  -> curaduría / muestra / contenido
  -> publicación
  -> refresco automático de stock de ESE producto
```

La URL actual de detalle de Dropi contiene `product-details/:id/:name`, por lo que no hace falta acceso al listado completo para identificar lo elegido.

## 2. Modelo de datos (propuesta)

| Cambio | Para qué |
|---|---|
| `productos.origen`: `propio` \| `proveedor`, por defecto `propio` | Un producto de proveedor también vive en `productos`. Así Campañas sigue ligando por `product_id_ref` y se mantiene la regla de no publicar sin producto ligado |
| `productos.peso_g`, `largo_cm`, `ancho_cm`, `alto_cm` | Cotizar guías |
| `producto_proveedor`, 1 a 1 con los productos de proveedor | Plataforma (`dropi`), ids del producto, la variante y el proveedor en Dropi, costo del proveedor, stock reportado, ciudad de la bodega y última sincronización |
| `despachos` | Un envío por fila: pedido, tipo (propio o proveedor), plataforma, id externo, transportadora, guía, enlace de rastreo, estado, flete y fechas |
| `despacho_eventos` | Libro de cambios de estado que solo crece, como `pagos_eventos`. Da idempotencia a los avisos y consultas repetidos |
| `producto_pruebas` | La prueba del sello: quién, cuándo, notas y veredicto (`CURADURIA-Y-SELLO.md`) |
| `campana_producto.tiempo_entrega` | La ficha muestra el tiempo de entrega, nunca el origen |

**Estados del despacho:** `creado`, `recogido`, `en_transito`, `novedad`, `entregado`, `devuelto`, `cancelado`.

**Relación con el estado del pedido:**

- el pedido pasa a `en_camino` cuando el despacho tiene guía;
- pasa a `entregado` cuando el despacho se entrega, y ese correo lleva el código de reseña, como hoy.

## 3. Cambios por área

**Stock:**

- **Producto propio:** todo sigue igual (libro de movimientos y candado en `crear_pedido`).
- **Producto de proveedor:**
  - no tiene movimientos de inventario;
  - `agotado` sale del stock reportado por Dropi;
  - solo se consulta cada producto que el dueño importó, no el catálogo completo;
  - refresco programado corto (frecuencia según el límite que autorice Dropi) y verificación en vivo antes de abrir Wompi;
  - si la última lectura supera el tiempo máximo permitido o Dropi falla, queda temporalmente no disponible;
  - `crear_pedido` registra el pedido sin bajar inventario, y `anular_pedido` no compensa nada;
  - si Dropi rechaza la orden por falta de stock, sale el aviso rojo en Ventas.
- **Límite inevitable:** verificar stock antes del pago reduce el riesgo, pero solo crear/reservar la orden en Dropi inmediatamente después del pago evita que otro vendedor consuma la última unidad entre ambos momentos.

**Contabilidad:**

- La venta se registra igual que en F3.
- El costo de un producto de proveedor no sale de inventario (143505). Sale del saldo de Dropi, que es una cuenta nueva en `contabilidad_config`.
- El flete va a su propia cuenta de gasto.
- La recarga del saldo se registra como asiento manual contra el banco.
- **Los códigos los define el contador.**
- **Por decidir:** si el costo se toma de la sincronización o de lo que Dropi cobró de verdad.

**Tienda:**

- Lista cerrada de municipios con código DANE. Hoy la ciudad es texto libre, y Dropi exige que coincida con su catálogo: es el requisito que **sigue abierto** y el más riesgoso, porque una ciudad que Dropi no reconoce hace fallar el pedido *después* del pago.
- ~~Los detalles de entrega llegan al pedido~~ y ~~confirmación al volver de Wompi~~: **hechos** (D0, 9-oct-2026), pendientes de desplegar.
- Tiempo de entrega por producto en la ficha.

**Ventas (panel):**

- Aviso «Pedido de proveedor por confirmar», con el botón «Enviar al proveedor».
- Guía, transportadora y rastreo en el detalle del pedido.
- Estado del despacho, y aviso rojo si el despacho falla.

**Inventario y Métricas:**

- Los productos de proveedor no admiten movimientos.
- Quedan fuera de la rotación y de los días de inventario.

**Correos:** «En camino» sale solo cuando el despacho tiene guía, con tres variables nuevas: guía, transportadora y enlace de rastreo.

**Seguridad:**

- Secretos solo en Edge Functions: `DROPI_TOKEN`, y la llave de Mipaquete o el Client ID y Client Secret de Skydropx.
- Las Edge Functions escriben solo por RPC `security definer`, que solo puede ejecutar `service_role` (el mismo patrón de F2).
- Los avisos de las plataformas de envío se verifican: HMAC en Skydropx; en Mipaquete, por confirmar.
- **No se abre nada nuevo para `anon`.**

## 4. Fases

| Fase | Entrega | Depende de |
|---|---|---|
| **1 · Guía manual** | `despachos` y `despacho_eventos`; pegar la guía en Seguimiento; paso a `en_camino` con el correo automático | Nada |
| **2 · Guías automáticas (propios)** | Peso y medidas; municipios DANE en la tienda; Edge Function para cotizar y crear la guía; avisos de estado firmados | Cotizaciones y elección de plataforma |
| **3 · Embudo de producto Dropi y sello** | Pegar URL/id en Campañas; leer solo `products/v2/{id}` / `products/{id}`; crear borrador; refrescar stock de los seleccionados; `agotado` y fallo seguro; `producto_pruebas` y candado del sello | Acceso **de solo lectura por producto** a la API de Dropi |
| **4 · Pedidos a Dropi** | `crear_pedido` y `anular_pedido` sin inventario para proveedor; confirmación de un clic; creación con verificación por id; consulta programada de estado y guía; asiento con la cuenta del saldo | Fase 3 y contador |
| **5 · Contraentrega** | `CON RECAUDO` y su conciliación | Solo si los números lo piden |

Cada fase sigue las reglas de `CONTEXTO-MAGANDHI.md` §10: migración forward nueva, pruebas en el banco y medir en producción antes de afirmar.

## 5. Decisiones abiertas

1. Plataforma de guías (cotizaciones).
2. Cuentas del saldo de Dropi y del flete, y forma de facturar (contador).
3. Intermediario con IP fija, si Dropi la exige.
4. Si `devuelto` también será un estado del pedido o solo del despacho.
5. Cuándo deja de ser manual la confirmación de un clic.

## 6. Riesgos

| Riesgo | Cómo se contiene |
|---|---|
| API parcial o cambiante de Dropi | Pedir un alcance mínimo de solo lectura por id; guardar el contrato medido; sonda; aviso rojo ante cambios |
| Stock del proveedor desactualizado | Refresco de los productos seleccionados + lectura en vivo antes de Wompi + vencimiento que falla cerrado; la reserva final llega con la API de pedidos |
| Calidad del proveedor | Curaduría con muestra (`CURADURIA-Y-SELLO.md`) y opiniones verificadas |
| Devoluciones y garantías | Acuerdo por proveedor antes de publicar su producto |
