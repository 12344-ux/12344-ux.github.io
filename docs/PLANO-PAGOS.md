# PLANO · Pagos web (Wompi F2 → F4)

**Corte:** 9 de octubre de 2026 · **Estado:** **F1 a F4 en producción**, verificados con una compra real el 9-oct (§11). Runbook en `supabase/INSTRUCCIONES.md` (F2 y «Pagos F3»).

Piezas de F2: migración `20261019000000`, Edge Function `wompi-webhook`, `crear-intencion-pago` modificada (persiste antes de firmar), aviso de pagos sin pedido en la portada de Ventas, y la tienda enviando comprador + procedencia.

## 0. El problema que resuelve F2

Hoy existe F1: la tienda arma una intención firmada y el checkout de Wompi abre. Pero **nadie se entera del resultado**: un pago aprobado no crea pedido, no baja stock y no deja rastro. El dinero entraría y el back-office no mostraría nada.

F2 cierra ese hueco con una sola promesa, que es el criterio de todo el tramo:

> Un pago aprobado se convierte en un pedido trazable **exactamente una vez**, sin vender existencias que no hay y sin dejar dinero huérfano.

## 1. Decisiones del dueño (cerradas el 8-oct-2026)

1. **Pago aprobado sin stock** → **no se crea el pedido**. La intención queda en `requiere_revision` y salta como **aviso rojo en el panel** para resolver a mano (reposición o devolución). Motivo: un pedido imposible ensuciaría Ventas, y plata recibida sin producto es un hecho que debe verse, no esconderse en la lista normal.
2. **Datos del comprador** → los que escribió en la tienda. **Wompi solo confirma el pago.** Se guarda todo lo útil que venga del evento (id de transacción, método de pago, correo del pagador) como respaldo, sin que desplace lo que dijo el cliente.
3. Wompi en **sandbox** hasta cerrar F4.

## 2. Flujo completo

```
TIENDA                      crear-intencion-pago            BASE
 Comprar ───────────────────▶ relee precio server-side
                              PERSISTE la intencion ───────▶ pagos_intencion (estado=creada)
                              firma integridad
 checkout Wompi ◀─────────── devuelve datos publicos
     │
     │ el cliente paga
     ▼
 WOMPI ──POST transaction.updated──▶ wompi-webhook
                                      verifica checksum (secreto de EVENTOS)
                                      ─────────────▶ pw_procesar_pago()  [1 transaccion]
                                                      · registra el evento (idempotencia)
                                                      · bloquea la intencion (for update)
                                                      · compara el monto
                                                      · APPROVED + stock  -> crea pedido web + baja stock
                                                      · APPROVED sin stock -> requiere_revision
                                                      · DECLINED/VOIDED/ERROR -> rechazada
                                      ◀───────────── resultado
                                      responde 200
```

## 3. Modelo de datos

### `pagos_intencion` — una fila por intento de pago

Clave: `referencia` (la que se firma y Wompi devuelve). Guarda el **monto firmado** para poder comparar después, la foto del producto y del comprador, y el `utm_campaign` y `mg_vid` de la visita.

Estados:

| Estado | Significado |
|---|---|
| `creada` | Se firmó y se abrió el checkout. No prueba nada todavía. |
| `procesada` | Pago aprobado y pedido creado. Lleva `pedido_id`. **Terminal.** |
| `rechazada` | Wompi informó `DECLINED`, `VOIDED` o `ERROR`. No se creó nada. **Terminal.** |
| `requiere_revision` | Pago aprobado pero **no se pudo convertir en pedido** (sin stock o monto que no coincide). Sale como aviso rojo. |

### `pagos_eventos` — el libro de avisos de Wompi

Wompi **no envía un id de evento único**, así que la idempotencia se construye con una llave única `(transaccion_id, estado_wompi)`: un reintento del mismo aviso choca contra ella y no vuelve a procesar. Un cambio legítimo de estado (`PENDING` → `APPROVED`) sí entra, porque es otra pareja.

Guarda el cuerpo completo, el checksum y el **resultado** de cada aviso, para poder auditar sin adivinar.

## 4. Reglas duras

1. **Idempotencia primero.** Lo primero que hace la RPC es registrar el evento. Si la pareja ya existía, responde `repetido` y no toca nada más.
2. **El monto se compara.** Si `amount_in_cents` del evento no coincide con el monto firmado, **no se crea pedido**: va a `requiere_revision`. Nunca se confía en el monto que llega.
3. **El precio no se relee en el webhook.** Ya se releyó al firmar y quedó congelado en la intención. Si el precio subió mientras el cliente pagaba, se respeta lo que firmó.
4. **El stock lo bloquea `crear_pedido`.** F2 no reimplementa esa lógica: reutiliza el candado firme que ya existe y serializa ventas simultáneas. Si rechaza por stock, se captura y la intención va a `requiere_revision`.
5. **Códigos HTTP del webhook.** `200` para procesado, repetido, ignorado y rechazado (Wompi no debe reintentar lo que ya resolvimos). `401` si el checksum no valida. `400` si el cuerpo es inválido. `500` **solo** si el fallo es nuestro, para que Wompi reintente.
6. **`properties` se lee del evento**, nunca se fija en el código (la doc de Wompi advierte que puede cambiar).
7. **Secretos por ambiente.** `WOMPI_EVENTS_SANDBOX` y `WOMPI_EVENTS_PROD`, solo en Deno.env. El secreto de eventos es distinto del de integridad que usa F1.
8. **Nada de escritura directa.** La Edge Function escribe solo por la RPC `security definer`, ejecutable únicamente por `service_role`.
9. **Nada se borra.** Una intención no se edita a mano ni se elimina: cambia de estado y queda el libro de eventos.

## 5. Qué conecta de paso

- **`pedidos.utm_campaign`** se llena con el de la intención. Eso convierte la atribución de ventas de las campañas de email de «aproximada» a **exacta**.
- **`mg_vid`** (id aleatorio de la analítica) queda guardado en la intención. Es el enchufe que Métricas esperaba para medir el embudo real hasta la compra y, más adelante, la interacción por cliente.

## 6. Fuera del alcance de F2

Asiento contable automático (F3, §10), paso a producción (F4, §11), carrito de varios productos, multimoneda y reservas temporales de stock. La cantidad sigue fija en 1.

## 7. Criterios de cierre (no basta ver «Success»)

- El mismo evento enviado dos veces produce **un solo pedido**.
- Pago rechazado: **cero pedidos, cero salidas de inventario**.
- Pago aprobado sin stock: queda en `requiere_revision`, visible, **no se procesa en silencio**.
- Monto que no coincide: no crea pedido.
- Checksum falso o ausente: rechazado con 401.
- La referencia permite identificar la intención sin inferencias.
- El pedido aparece en Seguimiento y alimenta Portafolio, Ranking y Métricas.
- Ningún secreto llega al navegador ni a los registros.


## 8. Aviso de pagos sin pedido (portada de Ventas)

Si un pago aprobado no se pudo convertir en pedido, aparece arriba del área un bloque con el borde terracota: cuántos son, el motivo **en lenguaje claro** (no el error técnico de la base), el monto en pesos y los datos de contacto para resolverlo. Cerrarlo exige una **nota obligatoria** y queda constancia de quién y cuándo. Si no hay pendientes **no se pinta nada**: un aviso que aparece siempre deja de ser un aviso.

Corrección de paso: el encabezado del área se desbordaba en 390 px (el rótulo «ÁREA DE VENTAS» empujaba el ancho a 477 px y dejaba el avatar fuera de pantalla). Era un error previo a este tramo; se corrigió ocultando lo decorativo en pantallas angostas, como ya hacía Métricas.

## 9. Procedencia de la compra (tienda)

`window.mgProcedencia()` en `analitica/analitica.js` devuelve dos cosas con criterios distintos a propósito:

- **`utm_campaign`**: el identificador de *nuestra* campaña, tomado de la URL que la persona abrió y recordado durante la visita (para que la compra se atribuya aunque ocurra dos páginas después). No identifica a nadie, así que viaja siempre: es lo que permite decir con honestidad «esta venta vino de este correo».
- **`mg_vid`**: el identificador aleatorio del navegador. **Solo existe si la persona aceptó la analítica.** Si la rechazó, la compra no lleva identificador y no se crea uno para la ocasión.

## 10. F3 · asiento contable automático (en producción desde el 9-oct-2026)

> Cada venta web pagada **de verdad** queda en los libros exactamente una vez, cuadrada al peso, sin que nadie la escriba. Si el pedido se anula, el contraasiento la deja en cero.

### Decisiones del dueño (8 y 9-oct)

1. **La plata no entra al banco el día de la venta.** Wompi consigna días después y ya sin su comisión. La venta va contra una cuenta puente, **138095 Otros (Wompi por liquidar)**, que se salda a mano cuando llega la consignación. Si no queda en cero, falta una consignación.
2. **Comisión de Wompi → 530515 Comisiones**, en el asiento de liquidación. El evento de Wompi no la informa.
3. Las cuentas configuradas eran de grupo (no imputables) y se bajaron a subcuenta. Se agregaron las que faltaban para el ciclo de venta.
4. **La venta nunca falla por contabilidad.** Si el asiento no se puede crear, el pedido queda y la venta aparece en Finanzas con el motivo.
5. **Validación al configurar**: una cuenta de grupo o inexistente se rechaza cuando se escribe.
6. El correo **«Recibido»** de un pedido web sale solo. El texto sigue en `correo_plantillas`.

### Decisiones de diseño

7. **Un pago sandbox no se contabiliza.** Crea el pedido (F2), pero no movió dinero.
8. **El IVA no se supone.** `iva_ventas_pct` nace vacío. `0` = no responsable (todo el precio es ingreso); `5` o `19` = precio con IVA incluido (base = total / (1 + t), redondeada al peso, y el IVA es la diferencia). Lo confirma el contador.
9. **Un asiento automático no se edita ni se anula desde Finanzas.** Se corrige anulando el pedido. Así Ventas, Inventario y Finanzas nunca se contradicen.
10. **Fecha de Colombia (H4).** El pedido web y su asiento usan la fecha de America/Bogota, no la de UTC.

### Los dos asientos

**Al aprobarse el pago** (automático, fecha del pedido):

| Cuenta | Debe | Haber |
|---|---:|---:|
| 138095 Wompi por liquidar | precio | |
| 413505 Venta de mercancías | | precio (o base sin IVA) |
| 240805 IVA generado (solo si `iva_ventas_pct` > 0) | | IVA |
| 613505 Costo de venta | cantidad × `costo_unitario` | |
| 143505 Mercancías | | cantidad × `costo_unitario` |

**Cuando Wompi consigna** (manual, runbook PF3.6): banco por el neto, 530515 por la comisión (y su IVA si no eres responsable de IVA), retenciones de los pagos con tarjeta (135515 y 135518), contra 138095 por el bruto.

**Al anular el pedido:** las mismas cuentas con débito y crédito invertidos, con la fecha de la anulación. El asiento original no se toca.

### Piezas

- **Migración `20261020000000`.** Columnas `asientos.origen` (`manual`, `venta_web` o `reverso_venta_web`) y `origen_ref` (el pedido), más un índice único: un asiento de venta y un reverso por pedido. Los constructores internos se llaman `fz__asiento_venta_web` y `fz__reverso_venta_web`, y validan con la misma regla de oro de los manuales (`fz_validar_lineas`). También se reemitieron `pw_procesar_pago` (paso 8, el asiento), `anular_pedido` (el contraasiento) y `editar_asiento` / `anular_asiento` (protección).
- **Finanzas.** Aviso de «ventas web sin asiento» en la portada, derivado de los datos y con el motivo actual, más el botón «Registrar asiento». En el Diario, la marca «Automático» sin Editar ni Anular.
- **Correo «Recibido».** Con el pedido creado, `wompi-webhook` llama a `enviar-correo-pedido` en modo automático, autenticándose con la llave de servicio. La base limita esa puerta (`correo_auto_recibido_preparar`): solo «Recibido», solo pedidos web, al correo que está en la base y una sola vez. Si Resend falla, el envío queda «fallido» a la vista en Seguimiento, y el siguiente aviso de Wompi lo recupera. Nunca cambia la respuesta a Wompi.

### Límites conocidos (a propósito)

- El costo es el `costo_unitario` actual del producto: no hay costo por lote.
- Ventas manuales y compras de mercancía siguen con asiento manual: es el tramo P6 (b) y (c).
- Si se anula un pedido ya liquidado, 138095 queda con saldo crédito, que es la plata a devolver. Se cierra con el asiento de la devolución.

## 11. F4 · paso a producción (cerrado el 9-oct-2026)

Lo que se hizo:
- La URL de eventos de producción en Wompi apuntaba a otro proyecto de Supabase y se corrigió.
- Se cargaron los secrets `WOMPI_EVENTS_PROD` y `WOMPI_INTEGRITY_PROD`.
- Se pegó la llave pública de producción en `pagos_config` y se cambió `entorno = 'prod'`.

**Compra real del dueño:** un shampoo de $69.900, pagado con Nequi. Resultado:
- pedido web y stock −1;
- asiento automático (138095 D 69.900 · 413505 H 69.900 · 613505 D / 143505 H 47.705);
- correos de cada etapa y una opinión real.

**Lo que abonó Wompi:** $66.862,71. Descontó $3.037,29, que son 2,65 % + $700 de comisión ($2.552,35) más el IVA del 19 % sobre esa comisión ($484,95). No hubo retenciones porque no fue con tarjeta.

**Queda:** el asiento de liquidación cuando Wompi consigne (PF3.6). Los arreglos de la tienda (confirmación al volver, detalles de entrega, mensajes de error) están en `CONTEXTO-MAGANDHI.md` §9.

**Reversión:** `update pagos_config set entorno = 'sandbox' where id = 1;` deja de cobrar de inmediato. Nada contable se reescribe: lo ya registrado se corrige anulando el pedido.
