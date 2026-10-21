# MAGANDHI · Plano Promocionar P4 · atribución transaccional

**Estado:** desplegado, activo, medido sin dinero y **cerrado estructuralmente** el 21-oct-2026. No cerrado transaccionalmente: existe una intención atribuida sintética, pero no hubo pago ni pedido.
**Base:** P0 está cerrado como contrato documental, sin implementación ni producción; P1–P3 están desplegados y cerrados en sus alcances respectivos. P3 continúa operativo sin depender de P4. Relevo histórico de P4: `RELEVO-PROMOCIONAR-P4-CIERRE-ESTRUCTURAL-2026-10-21.md`. Continuidad vigente: `RELEVO-PROMOCIONAR-P5-CIERRE-ESTRUCTURAL-2026-10-21.md`.

## 1. Entrega

P4 conecta un enlace propio válido con la compra que originó:

```text
go.magandhi.com/<codigo>
  → destino MAGANDHI #mg_promo=<codigo>
  → visita temporal en la pestaña
  → intención de pago con FK validada
  → pedido aprobado con la misma FK
```

P4 no crea tablero, ingresos, CTR ni métricas por pieza; eso corresponde a P5.

## 2. Regla de negocio

La unidad de atribución es la intención/pedido completo, no cada línea. El último
enlace propio válido dentro de la visita gana aunque el enlace promoviera A y el
pedido contenga B o A+B. `atribucion_enlaces.campana_producto_id` conserva la
campaña/producto que originó la visita; las líneas del pedido conservan por
separado lo efectivamente comprado.

## 3. Transporte y visita

- El resolver P3 mantiene su URL interna y UTM de lista blanca.
- Con P4 habilitado, Edge añade exclusivamente `#mg_promo=<codigo>` después de
  resolver un código activo; nunca acepta un destino del request.
- La tienda retira el fragmento de la barra, valida el código mediante
  `GET https://go.magandhi.com/validar/<codigo>` y solo una respuesta autoritativa
  puede reemplazar una visita anterior.
- Estado local: `{ codigo, recibido_en, ultima_actividad }` bajo una clave propia
  de `sessionStorage`, separado de `mg_vid`, cookies y analítica.
- Vigencia: 30 minutos desde la última carga interna visible o inicio de
  checkout. No renuevan foco, movimiento, temporizadores, pestaña oculta,
  prefetch, fetch de fondo, analítica ni regreso BFCache de Wompi.
- Un código mal formado o confirmado como inexistente/desactivado no reemplaza
  uno válido. Si la validación queda incierta, la compra sigue sin atribución.

## 4. Autoridad server-side

El navegador envía como máximo `atribucion_codigo`; nunca una FK. Las RPC P4:

1. verifican gate, forma y enlace activo;
2. derivan `atribucion_enlace_id` dentro de la transacción;
3. la fijan únicamente durante el INSERT de `pagos_intencion`;
4. ignoran un código diferente en reintentos o reapertura;
5. degradan a la RPC histórica y FK nula si P4 no está disponible.

Las firmas históricas permanecen. P4 agrega puertas nominales para compra
inmediata y carrito, y envuelve la firma vigente de `pw_procesar_pago` sin
cambiar el contrato del webhook.

## 5. Copia al pedido

Cuando el procesador devuelve un `pedido_id`, el wrapper P4 localiza la intención
por ese pedido y copia exactamente la FK congelada. Solo admite `NULL → FK` o
una repetición con la misma FK; nunca reemplaza una atribución distinta. La
copia ocurre en la misma transacción que procesa el webhook. Si esa copia falla,
el pago y el pedido prevalecen: P4 registra una incidencia privada sin código,
UTM ni comprador y responde con el resultado histórico ya procesado. Un retry
del webhook autocura la incidencia; además existe una reparación SQL privada e
idempotente que solo permite `NULL → FK` desde la intención y nunca sobrescribe.

Al existir exacta propia, `pedidos.utm_campaign` queda NULL para impedir que las
lecturas legacy de Email sumen la misma venta otra vez. La UTM descriptiva sigue
en el enlace autoritativo y en la intención. Pedidos sin FK conservan el
comportamiento legacy.

## 6. Precedencia exclusiva

1. `exacta_propia`: `pedidos.atribucion_enlace_id` no nulo.
2. `legacy_email_utm`: sin FK y UTM coincidente con Email.
3. `aproximada_email`: sin FK ni legacy; último clic Resend elegible en siete días.
4. `sin_atribuir`.

La función interna P4 de clasificación aplica esta precedencia. La aproximación
Email se redefine para excluir cualquier pedido con FK.

## 7. Privacidad

P4 no crea identificador de visitante, evento de navegación, historial de
páginas ni unión del clic agregado con cuenta/cliente. El código identifica un
enlace público y la FK demuestra procedencia de una transacción. Funciona sin
consentimiento analítico y no lee ni escribe `mg_vid`.

## 8. Gate y reversa

`promocionar_p4_config.atribucion_habilitada` nace `false`. Solo puede encenderse
cuando validación pública y checkout estén marcados como verificados. Política y
versión se registran de forma informativa hasta que el dueño cierre si serán un
gate de activación.

Apagar P4 hace que nuevas intenciones nazcan sin FK; no apaga P3, carrito ni
pagos y no borra atribuciones ya congeladas.

## 9. Compatibilidad

- Clientes viejos siguen llamando las RPC históricas y crean FK nula.
- Reabrir una intención C5 no recibe código ni cambia atribución.
- Un código ausente, inválido, desactivado o una caída P4 no impide comprar.
- La migración es forward; no modifica `20261108000000` ni historia anterior.
- P3 puede redirigir sin fragmento si P4 aún no está instalado o está apagado.

## 10. Cierre estructural productivo · 21-oct-2026

- Backend PR #306 y tienda PR #118 fusionados; CI y Pages verdes.
- Migración `20261109000000` aplicada una vez; Edge `enlace-promocional` y
  `crear-intencion-pago` redesplegadas.
- Gate activo desde `2026-10-21T15:21:59.626776Z`; validación pública y checkout
  marcados verificados.
- Enlace activo: validación `204`; `HEAD 302` a destino MAGANDHI con UTM y
  fragmento P4; query hostil ignorada.
- Navegador: fragmento capturado, estado exacto en `sessionStorage`, URL limpia,
  intención `200` y llegada a `checkout.wompi.co/method`.
- Se detuvo antes de pagar. Estado posterior: 1 intención atribuida sintética,
  0 pedidos atribuidos, 0 divergencias y 0 incidencias.

Esto cierra P4 **estructuralmente en producción**. No acredita todavía copia al
pedido, webhook APPROVED/repetido, inventario, asiento, correo ni carrito real.
Una compra real expresamente autorizada es necesaria para cierre transaccional.
La evidencia completa del cierre P4 permanece en
`RELEVO-PROMOCIONAR-P4-CIERRE-ESTRUCTURAL-2026-10-21.md`; es historia. La
continuidad vigente está en
`RELEVO-PROMOCIONAR-P5-CIERRE-ESTRUCTURAL-2026-10-21.md`.
