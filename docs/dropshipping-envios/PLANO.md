# PLANO · Dropshipping y envíos

**Corte:** 10 de octubre de 2026 · **Estado:** diseño vigente con **D1 desplegado en producción** (más su ajuste de uso real: fotos, paginación y bandeja-carrito). D1 no vende ni llama `orders/`; el resto se ajusta con la respuesta de Dropi, las cotizaciones y el contador.

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

### Decisiones del dueño (cerradas el 9–10-oct-2026)

1. **Sin Shopify. WooCommerce solo como prueba aislada:** nunca sobre `magandhi.com`, nunca como tienda pública ni fuente de verdad. Se autoriza un sandbox/subdominio desechable con un solo producto para medir si completa OAuth, importa bien y entrega stock actualizable.
2. **Área propia Dropshipping:** no es subárea de Producción ni Marketing. Allí se consulta Dropi, los candidatos elegidos caen en una bandeja privada y se ve el estado futuro de proveedor/despacho.
3. MAGANDHI no replica todo el catálogo. La búsqueda es una vista remota temporal; el dueño guarda solo un candidato en bandeja. **«Llevar a Campañas»** crea después un borrador ligado, abre nuestro editor y nunca publica solo.
4. Las fotos remotas se ven solo dentro de la bandeja. Al llevar un candidato a Campañas, se descargan únicamente las elegidas y se transforman a grande + `-sm` en nuestro bucket; el editor permite reemplazar fotos genéricas o feas antes de publicar.
5. Todo producto de proveedor tiene fila interna `productos.origen='proveedor'`, pero no admite movimientos de Inventario ni afecta stock/rotación/días de inventario propios. Una variante Dropi será un producto/campaña MAGANDHI distinta por ahora.
6. El precio comercial se define a mano. El proveedor solo informa costo interno, nunca precio público.
7. Dropi es la fuente de verdad del stock proveedor. Si la lectura vence o falla, la tienda falla cerrada como «Temporalmente no disponible».
8. Después de Wompi, el diseño objetivo es reserva automática `PENDIENTE CONFIRMACION` y botón humano **«Confirmar despacho con proveedor»** para liberarla. No se implementa hasta medir reserva, transición, cancelación e idempotencia en la cuenta MAGANDHI.
9. El sello MAGANDHI solo se habilita si existe una prueba aprobada del equipo; la UI pregunta, pero el servidor decide.
10. Cliente, pedido, correos, opiniones y métricas de relación siguen siendo MAGANDHI. La política/copy ante stock perdido después del pago queda pendiente de decisión legal/comercial.

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

## 2. Modelo de datos

| Cambio | Para qué | Estado D1 |
|---|---|---|
| `productos.origen`: `propio` \| `proveedor`, por defecto `propio` | Un producto de proveedor también vive en `productos`; Campañas y Pedido Items conservan una FK interna única | **Hecho.** Inmutable después del alta |
| `dropshipping_candidatos` | Bandeja privada: snapshot de candidato elegido, stock leído y URLs de preview, sin copiar catálogo | **Hecho.** No es producto ni campaña |
| `producto_proveedor`, 1 a 1 con los productos de proveedor | Plataforma, ids producto/variante, proveedor, costo, stock reportado y vencimiento de lectura | **Hecho como estructura.** D2 la llena al importar |
| `productos.peso_g`, `largo_cm`, `ancho_cm`, `alto_cm` | Cotizar guías | Pendiente de fase de guías |
| `despachos` | Un envío por fila: pedido, tipo, plataforma, id externo, guía, rastreo, estado, flete y fechas | Pendiente |
| `despacho_eventos` | Libro append-only de cambios de estado e idempotencia | Pendiente |
| `producto_pruebas` | La prueba del sello: quién, cuándo, notas y veredicto | Pendiente D2 |
| `campana_producto.tiempo_entrega` | La ficha muestra el tiempo de entrega, nunca el origen | Pendiente D2 |

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

- Lista cerrada de municipios con código DANE y equivalencia aceptada por Dropi. Hoy la ciudad es texto libre, y Dropi exige que coincida con su catálogo: es el requisito que **sigue abierto** y el más riesgoso, porque una ciudad que Dropi no reconoce hace fallar el pedido *después* del pago.
- Nombres y apellidos separados para el destinatario. Hoy el checkout guarda un nombre completo; Dropi pide `name` y `surname`. Se conserva el nombre completo de MAGANDHI por compatibilidad, pero el adaptador no debe inventar el apellido separando texto.
- ~~Los detalles de entrega llegan al pedido~~ y ~~confirmación al volver de Wompi~~: **hechos y desplegados** (D0, 9–10-oct-2026).
- Tiempo de entrega por producto en la ficha.

**Ventas (panel):**

- Aviso «Pedido de proveedor por confirmar», con el botón **«Confirmar despacho con proveedor»**. La reserva/conexión ya habría ocurrido antes; el botón libera el despacho solo después de revisión humana.
- Guía, transportadora y rastreo en el detalle del pedido.
- Estado del despacho, y aviso rojo si el despacho falla.
- **D1 no cambia Ventas todavía:** no existe `despachos` ni se llama `orders/` hasta medir contrato, reserva, liberación y cancelación.

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

| Fase | Entrega | Estado / depende de |
|---|---|---|
| **D1 · Cimientos internos** | Área propia, búsqueda/paginación read-only, bandeja, origen/ficha proveedor, candados de Inventario/Métricas, bloqueo de publicación | **Desplegada (10-oct-2026).** 68 migraciones y pruebas. No toca `orders/`. Ajuste de uso real: fotos directas de Dropi, 24 por página, bandeja como carrito |
| **1 · Guía manual** | `despachos` y `despacho_eventos`; pegar la guía en Seguimiento; paso a `en_camino` con el correo automático | Diseñada, no depende de nadie |
| **2 · Guías automáticas (propios)** | Peso y medidas; municipios DANE en la tienda; Edge Function para cotizar y crear la guía; avisos de estado firmados | Cotizaciones y elección de plataforma |
| **D2 / 3 · Embudo de producto Dropi y sello** | Variante exacta, importación atómica a producto + `producto_proveedor` + borrador, imágenes propias, prueba/sello server-side, municipios, stock vigente/fallo cerrado y verificación antes de Wompi | Medir frecuencia/contrato de lectura y decidir datos de destinatario |
| **D3 / 4 · Pedidos a Dropi** | Reserva `PENDIENTE CONFIRMACION`, detalle de Ventas, confirmación humana, verificación por id, guía/estado y asiento del saldo | Contrato medido de `orders/`, reserva/liberación/cancelación y contador |
| **5 · Contraentrega** | `CON RECAUDO` y su conciliación | Solo si los números lo piden |

Cada fase sigue las reglas de `CONTEXTO-MAGANDHI.md` §10: migración forward nueva, pruebas en el banco y medir en producción antes de afirmar.

### D2 en tres tramos (10-oct-2026)

D2 se parte para que cada PR desbloquee algo real sin abrir la venta antes de tiempo:

| Tramo | Entrega | Estado / decisiones pendientes |
|---|---|---|
| **D2a · Llevar a Campañas** | Relectura de la ficha, elección de variante y fotos, conversión a grande + `-sm` en el bucket propio, `ds_llevar_a_campanas` atómica e idempotente, editor en modo proveedor y candado del vínculo campaña ↔ ficha | **En PR** (migración `20261024000000`). No publica ni vende. Las fotos se traen desde el navegador porque el CDN de Dropi responde CORS `*` (medido); así se reutiliza el conversor del editor sin una Edge Function nueva |
| **D2b · Sello con prueba** | `producto_pruebas` (quién, cuándo, notas, veredicto), registro desde el editor, y validación en `cm_crear/editar/publicar_campana`: sin prueba aprobada no hay sello. Aplica a propios y proveedor | Antes de activarlo, registrar la prueba de los productos que ya llevan el sello (hoy, el shampoo GRISI) |
| **D2c · Stock vivo y venta de proveedor** | Refresco de stock desde el servidor, vencimiento que falla cerrado en `catalogo_publico`, estado «Temporalmente no disponible» en la tienda, verificación en vivo en `crear-intencion-pago`, `crear_pedido`/`anular_pedido` sin libro de Inventario para proveedor, asiento con las cuentas del saldo Dropi y aviso en Ventas para crear el pedido en Dropi a mano. Recién aquí se levanta `DS_PUBLICACION_PENDIENTE` | Decide el dueño: vigencia de la lectura y frecuencia de refresco; el contador: cuentas del costo proveedor y flete; copy de «Temporalmente no disponible» y política si el stock se pierde después del pago |

El pedido automático a Dropi (`orders/`) sigue siendo D3/4. Municipio DANE y nombres/apellidos separados se necesitan antes de ese pedido automático; con el pedido manual de D2c el dueño transcribe los datos en Dropi.

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
