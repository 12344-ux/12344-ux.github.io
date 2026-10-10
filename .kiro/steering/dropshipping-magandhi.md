---
inclusion: manual
---

# MAGANDHI · decisiones de Dropshipping y despacho de proveedor

**Decidido por el dueño:** 10 de octubre de 2026. Estas reglas gobiernan el
frente de Dropshipping mientras no haya una decisión posterior explícita.

## 1. Principio comercial

- La tienda **nunca debe «oler» a dropshipping**. MAGANDHI no replica ni publica
  el catálogo de Dropi tal cual: cada producto pasa por nuestra curaduría,
  nuestros copys, nuestro precio y el editor actual de Campañas.
- El cliente es de **MAGANDHI**, no del proveedor. El pedido, los correos, la
  atención, la reseña verificada, el pago, la analítica y las métricas de
  relación con el cliente siguen siendo de MAGANDHI.
- MAGANDHI responde frente al cliente. La tienda pública nunca muestra el
  proveedor, su costo, ids externos ni stock exacto.

## 2. Área propia

- Dropshipping será la **séptima área propia** del panel, con módulo raíz
  `dropshipping`; no es subárea de Producción ni de Marketing.
- Tendrá como mínimo: búsqueda/consulta de candidatos, bandeja de curaduría,
  productos publicados con última lectura de stock, y avisos de reservas o
  despachos que requieran acción.
- Ventas sigue siendo la fuente del pedido y de la atención al cliente. El
  detalle de Seguimiento mostrará al operador el estado de proveedor/despacho y
  el botón de confirmación; esa información nunca sale a la tienda pública.

## 3. Entrada de productos y campañas

- No se copia el catálogo completo de Dropi. La búsqueda y la ficha en el área
  Dropshipping son una **vista temporal remota** de candidatos elegidos por el
  dueño.
- Las fotos remotas pueden verse en esa bandeja privada y temporal, sin
  descargarlas todavía ni guardarlas como imágenes públicas de MAGANDHI.
- Al pulsar **«Llevar a Campañas»**, el sistema crea un producto interno y un
  borrador ligado, descarga únicamente las imágenes seleccionadas, las convierte
  al formato propio (grande + `-sm`) y las guarda en el bucket `campanas`.
- Después se abre el **editor actual de Campañas**. Allí el equipo adapta copy,
  ficha, curaduría, orden e imágenes; puede reemplazar las fotos genéricas o
  feas antes de publicar.
- Una campaña de proveedor empieza siempre como borrador: nunca se publica sola.
- El precio comercial se pone **a mano**. El costo del proveedor solo sirve a la
  operación y contabilidad interna; no calcula ni impone el precio público.

## 4. Modelo interno, inventario y variantes

- Todo producto de proveedor tendrá una fila interna en `productos`, marcada
  inequívocamente como `origen = 'proveedor'` / dropshipping. Es necesaria para
  conservar la FK de Campañas, los items de pedido y el contrato único del
  software.
- Los productos de proveedor **nunca** tienen movimientos en
  `movimientos_inventario`, ni entran a Inventario, rotación, días de inventario
  ni alertas de stock propio. Esta regla se debe imponer en base de datos y RPC,
  no solo ocultando controles en la interfaz.
- Por ahora, **una variante de Dropi = un producto interno = una campaña**.
  No se construye selector de variantes en la tienda hasta que haya necesidad
  validada.

## 5. Stock y compra

- Dropi es la fuente de verdad del stock de productos de proveedor.
- La vitrina usa la última lectura guardada únicamente si sigue vigente. Si
  falta, venció o Dropi no responde, el producto falla cerrado como
  «Temporalmente no disponible»; nunca se inventa stock.
- Antes de firmar/abrir Wompi se debe consultar el estado vivo del producto o
  de la variante correspondiente.
- La decisión de política/copy ante un pago ya hecho cuyo stock desapareció
  queda **pendiente**: la define el dueño junto con políticas, devolución o
  alternativa comercial. No se improvisa copy ni reembolso automático.

## 6. Pedido al proveedor: reserva y confirmación humana

- Tras un pago Wompi aprobado, el pedido nace normalmente en MAGANDHI y entra a
  Seguimiento como cualquier pedido: conserva correos, atención, trazabilidad,
  opinión y analítica propios.
- Diseño deseado: crear automáticamente en Dropi una reserva
  `PENDIENTE CONFIRMACION` de tipo `SIN RECAUDO` para proteger la última unidad;
  el operador revisa el pedido y luego pulsa **«Confirmar despacho con
  proveedor»** para liberarlo al despacho. El botón no debe llamarse simplemente
  «Conectar con proveedor», porque la conexión/reserva ya ocurrió antes.
- La reserva automática y la transición de confirmación solo se implementan
  cuando estén medidos el contrato de `orders/`, la reserva real por variante,
  el id remoto, la acción oficial de liberación/cancelación y la idempotencia.
- Un timeout o respuesta ambigua **nunca** se reintenta a ciegas. Se registra un
  evento/aviso rojo y se consulta el pedido remoto por su id antes de otra acción.
- `shop_order_id = pedidos.id` es la referencia bidireccional de MAGANDHI, pero
  no se presume que Dropi la use para deduplicar hasta medirlo.

## 7. Datos del destinatario

- Antes del primer pedido proveedor, el checkout debe capturar y validar los
  datos exactos que exige el contrato Dropi: nombres, apellidos, dirección,
  país, departamento, municipio, teléfono y correo.
- El nombre completo actual no sustituye automáticamente nombres + apellidos:
  se almacenan separados para el adaptador de proveedor y se conserva el nombre
  completo para compatibilidad con el cliente de MAGANDHI.
- Ciudad/municipio deja de ser texto libre para productos proveedor: debe usar
  una lista validada (DANE + equivalencia aceptada por Dropi) antes de cobrar.
- Los detalles de entrega (apartamento, torre, etc.) ya llegan al pedido y se
  conservan en el snapshot de dirección.

## 8. Sello «Elegido por MAGANDHI»

- El sello solo se habilita si el producto fue **probado por el equipo**.
- El editor de Campañas mostrará la pregunta/regla correspondiente; si no hay
  prueba aprobada, no permite seleccionar estrella/sello.
- La UI es solo guía: la validación vive también server-side y al publicar, para
  que no se pueda saltar por API o por una pantalla antigua.
- La prueba deja trazabilidad mínima (producto, resultado, fecha y notas). La
  regla aplica igual a productos propios y de proveedor.

## 9. Pruebas de Dropi antes de automatizar

- Se miden en lectura: cambios de stock de la misma ficha por id, búsqueda por
  palabra y comportamiento/paginación de `products/index`.
- No se hace un `POST orders/myorders` de prueba con datos improvisados, un
  cliente real ni una variante inferida por nombre.
- La prueba de reserva requiere: contrato oficial de creación/consulta/liberación,
  un producto y variante de prueba aprobados por el dueño/proveedor, dirección
  propia, saldo/presupuesto máximo conocidos, una única creación idempotente y
  plan de cancelación confirmado antes de enviar nada.

## 10. Regla de seguridad

- Tokens, llaves, proveedores, costos, ids externos y datos del destinatario
  viven solo en Edge Functions, Secrets y superficies internas protegidas.
- Ningún secreto va al frontend, repositorio, chat, URL pública ni logs.
- Toda corrección se hace con migración forward, pruebas locales y medición antes
  de afirmar que está desplegada.
