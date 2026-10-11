# PLANO · Dropshipping y envíos

**Corte:** 10 de octubre de 2026 · **Estado: D2c COMPLETO, desplegado y probado por el dueño de punta a punta con una venta real.** MAGANDHI ya cura, publica, vende, despacha y contabiliza productos de proveedor. La migración más alta en producción es `20261029000000`. **El despacho se crea A MANO en el panel de Dropi:** el pedido automático (`orders/`) es D3/D4 y sigue esperando el contrato oficial.

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
9. El sello MAGANDHI se habilita solo si la campaña tiene un producto ligado y la casilla simple `probado_por_magandhi` está marcada; la UI guía y el servidor decide. D2b no almacena prueba, fecha, notas, veredicto ni historial.
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
| `campana_producto.probado_por_magandhi` | Confirmación simple por presentación comercial; solo habilita el sello y exige un producto ligado | **Desplegado (D2b, 10-oct-2026).** No es una bitácora ni requiere datos históricos |
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
| **D2 / 3 · Embudo de producto Dropi y sello** | Variante exacta, importación atómica a producto + `producto_proveedor` + borrador, imágenes propias, casilla/sello server-side, municipios, stock vigente/fallo cerrado y verificación antes de Wompi | Medir frecuencia/contrato de lectura y decidir datos de destinatario |
| **D3 / 4 · Pedidos a Dropi** | Reserva `PENDIENTE CONFIRMACION`, detalle de Ventas, confirmación humana, verificación por id, guía/estado y asiento del saldo | Contrato medido de `orders/`, reserva/liberación/cancelación y contador |
| **5 · Contraentrega** | `CON RECAUDO` y su conciliación | Solo si los números lo piden |

Cada fase sigue las reglas de `CONTEXTO-MAGANDHI.md` §10: migración forward nueva, pruebas en el banco y medir en producción antes de afirmar.

### D2 en tres tramos (10-oct-2026)

D2 se parte para que cada PR desbloquee algo real sin abrir la venta antes de tiempo:

| Tramo | Entrega | Estado / decisiones pendientes |
|---|---|---|
| **D2a · Llevar a Campañas** | Relectura de la ficha, elección de variante y fotos, conversión a grande + `-sm` en el bucket propio, `ds_llevar_a_campanas` atómica e idempotente, editor en modo proveedor y candado del vínculo campaña ↔ ficha | **Desplegado y probado por el dueño (10-oct-2026)**, migración `20261024000000`. No publica ni vende. Las fotos se traen desde el navegador porque el CDN de Dropi responde CORS `*` (medido); así se reutiliza el conversor del editor sin una Edge Function nueva |
| **D2b · Sello con casilla simple** | `campana_producto.probado_por_magandhi`, casilla «Este producto fue probado por MAGANDHI» y validación en `cm_crear/editar/publicar_campana` más trigger: sin producto ligado y casilla no hay sello. Sin tabla/RPC de pruebas, formularios, fechas, notas, veredictos ni historial. Aplica a propios y proveedor | **Desplegado y verificado por el dueño (10-oct-2026, PR #261).** Campañas históricas con sello y casilla falsa se advierten al editar para que se confirme o se elija «Ninguno», sin inventar ni exigir datos históricos. No habilita publicación/venta de proveedor antes de D2c |
| **D2c · Stock vivo y venta de proveedor** | Refresco **rodante** cada minuto con `pg_cron`+`pg_net`; vencimiento que falla cerrado en `catalogo_publico` **reutilizando el booleano `agotado`** (no hay copy nuevo: uno distinto delataría el dropshipping); piso de vitrina de 20; verificación **en vivo** en `crear-intencion-pago`; `crear_pedido`/`anular_pedido` por origen; `pedido_proveedor` con la evidencia de lo reportado al cobrar; asiento contra **138010** con el flete a **523535**; y la pantalla **Ventas → Despachos de proveedor** | **DESPLEGADO y probado el 10-oct-2026** (PR #263, #264, #265; migraciones `20261026000000` a `20261029000000`). 1.065 comprobaciones en verde. Todas las decisiones quedaron cerradas: ver §4 bis |

El pedido automático a Dropi (`orders/`) sigue siendo D3/4. Municipio DANE y nombres/apellidos separados se necesitan antes de ese pedido automático; con el pedido manual de D2c el dueño transcribe los datos en Dropi.

## 4 bis. Decisiones de D2c, cerradas (10-oct-2026)

Todas discutidas con el dueño y, donde correspondía, con el contador. Los
valores numéricos viven en `dropshipping_config` y `contabilidad_config`:
cambiarlos **no exige migración**.

| Decisión | Valor | Fundamento |
|---|---|---|
| **Piso de vitrina** | **20 unidades** (configurable por producto) | Idea del dueño. **Medido:** en 8 lecturas reales el stock fue 1277, 459, 300, 300, 230, 0, 0, 0 — nada entre 1 y 229. El stock de Dropi es bimodal, así que 20 no excluye ningún producto con existencias |
| **Vara de entrada** | **100 unidades** al importar | Para no nacer al borde del piso |
| **Vigencia de la lectura** | **120 minutos** | Perilla *comercial*, no de seguridad: lo que evita vender humo es la consulta en vivo antes de pagar. Equivocarla cuesta una venta o una incomodidad, nunca vender lo que no existe |
| **Refresco** | **Rodante, 3 productos por minuto** con `pg_cron` + `pg_net` | **Medido:** Dropi responde 429 entre la petición 12 y 16 en ráfaga. Un lote grande coquetea con el techo; el goteo no. Y 15 productos quedan completos cada 5 min |
| **Copy «Temporalmente no disponible»** | **No existe.** Se reutiliza `agotado` | Un texto distinto para proveedor sería **una etiqueta que delata** el dropshipping. Cero cambios en la tienda |
| **Cuenta del saldo en Dropi** | **138010**, bajo 1380 Deudores varios | **Aprobada por el contador.** No es un anticipo: no está asignado a ningún proveedor (son muchos y cambian) y nadie ha facturado nada. Misma naturaleza que 138095 «Wompi por liquidar»: una plataforma con dinero nuestro |
| **Cuenta del flete** | **523535** Transporte, fletes y acarreos | **Aprobada por el contador.** El envío va incluido en el precio, así que no es costo de la mercancía: es gasto de vender |
| **Costo de la mercancía** | **613505 directo, sin pasar por 1435** | **Aprobado por el contador.** Nunca hay inventario que descargar. No tener la mercancía físicamente no es lo mismo que no haberla comprado: MAGANDHI es el vendedor, factura y responde por la garantía |
| **El ingreso** | **Precio completo (413505)**, no el margen | Actuamos como comerciantes, no como intermediarios |
| **Momento del asiento del costo** | **Manual**, con el cobro real de Dropi | Forzado por los hechos: **el flete no se puede cotizar por API** (medido), y depende del destino. Al vender es literalmente desconocido. Se reutiliza el mecanismo de «venta con algo pendiente» que F3 ya tiene en la portada de Finanzas |
| **Precio frente al flete variable** | **Promedio, con el flete incluido en el precio** | Se calcula a mano al investigar el producto, en Campañas. El sistema solo guarda el precio final: no hay nada que construir |
| **Flete y destino por pedido** | **Se guardan desde el primer pedido** | Sin eso, Métricas no tendría nada que analizar en tres meses y el histórico se perdería para siempre. Es lo que después permitirá centralizar destinos con datos |
| **Contraentrega** | **Descartada en esta fase** | `CON RECAUDO` está disponible en la API y nunca estuvo bloqueada, pero no hay rutas de estado ni de dinero: quedaríamos ciegos justo en lo que define el ingreso. Y el prepago **selecciona** al cliente comprometido, que es el posicionamiento elegido |
| **Guías y rastreo** | **Manuales** | Medido: el plugin oficial no tiene ninguna ruta de guía ni de estado del pedido |

**Idea aparcada:** una app propia que calcule el flete usando las tarifas reales
de Dropi, para integrarla en la tienda. Hoy **no es posible**: la API conocida no
tiene ruta de cotización de fletes (`DROPI.md` §9.3). Se retoma si soporte
entrega el contrato oficial.

## 5. Decisiones abiertas

1. Plataforma de guías para productos **propios** (cotizaciones).
2. Intermediario con IP fija, si Dropi la exige.
3. Si `devuelto` también será un estado del pedido o solo del despacho.
4. Cuándo deja de ser manual la confirmación de un clic.
5. **Política ante una entrega fallida** (devolución total, reenvío, o según el
   motivo). Es más caro para nosotros que para un vendedor de contraentrega,
   porque la plata del cliente ya se cobró. Pendiente del dueño.
6. Cuándo se debita el saldo de Dropi: al crear, al despachar o al entregar.
   **Ya es medible sin riesgo** leyendo `walletAmount` antes y después de un
   pedido hecho a mano (`DROPI.md` §9.6). El saldo arranca en 0, así que
   cualquier movimiento es evidencia directa.

## 6. Riesgos

| Riesgo | Cómo se contiene |
|---|---|
| API parcial o cambiante de Dropi | Pedir un alcance mínimo de solo lectura por id; guardar el contrato medido; sonda; aviso rojo ante cambios |
| Stock del proveedor desactualizado | Refresco de los productos seleccionados + lectura en vivo antes de Wompi + vencimiento que falla cerrado; la reserva final llega con la API de pedidos |
| Calidad del proveedor | Curaduría con muestra (`CURADURIA-Y-SELLO.md`) y opiniones verificadas |
| Devoluciones y garantías | Acuerdo por proveedor antes de publicar su producto |
