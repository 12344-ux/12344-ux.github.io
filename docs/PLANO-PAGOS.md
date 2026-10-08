# PLANO · Pagos web (Wompi F2 → F4)

**Corte:** 8 de octubre de 2026 · **Estado:** **F2 construido y probado** (pendiente de aplicar/desplegar: runbook F2 en `supabase/INSTRUCCIONES.md`). Wompi permanece en **sandbox** hasta F4.

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

Asiento contable automático (F3), paso a producción (F4), carrito de varios productos, multimoneda y reservas temporales de stock. La cantidad sigue fija en 1.

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
