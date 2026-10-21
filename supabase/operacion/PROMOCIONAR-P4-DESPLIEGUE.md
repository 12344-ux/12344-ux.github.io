# Promocionar P4 · despliegue controlado

P4 no está desplegado por el hecho de fusionar código. La migración es forward y
se aplica una sola vez. No usar `supabase db push` en esta base.

## Orden

1. Ejecutar `promocionar-p4-preflight.sql`; todos los booleanos deben ser `true`.
2. Aplicar una sola vez `20261109000000_promocionar_p4_atribucion.sql`.
3. Ejecutar `promocionar-p4-postflight.sql`; gate/verificaciones OFF, historia
   nula, funciones solo service role y tres triggers presentes.
4. Desplegar `enlace-promocional`; con gate OFF los enlaces P3 deben conservar
   exactamente el redirect sin fragmento.
5. Publicar la tienda y desplegar `crear-intencion-pago`. Clientes viejos y
   nuevos deben comprar normalmente con gate OFF.
6. Medir `GET /validar/<codigo-activo>`: `204` con CORS desde MAGANDHI; código
   inventado/desactivado: `404`; falla interna: `503`. No cuenta clics.
7. En transacción controlada/rollback, comprobar las RPC P4 con gate ON:
   código activo fija FK; inventado deja NULL; retry conserva la primera FK.
8. Marcar validación y checkout verificados, activar con
   `promocionar-p4-activar.sql` y repetir sonda de redirect: `Location` debe ser
   MAGANDHI con UTM y `#mg_promo=<codigo>`.
9. Medir intención sin dinero: FK correcta, respuesta pública sin FK/código,
   carrito libre e idempotencia intactos. `promocionar-p4-estado.sql` debe
   mostrar cero divergencias y cero incidencias pendientes. Si una copia
   fail-open dejó incidencia, ejecutar `promocionar-p4-reparar.sql`; la puerta
   solo permite restaurar `NULL → FK` desde la intención y nunca sobrescribe.
10. Una compra APPROVED real requiere autorización expresa del dueño. Debe
    demostrar la misma FK en intención/pedido, un pedido, inventario/proveedor,
    asiento, correo y retry de webhook sin duplicación.

## Reversa

Ejecutar `promocionar-p4-desactivar.sql`. Las nuevas intenciones quedan sin FK;
P3, enlaces, carrito, pagos e historia atribuida permanecen. No borrar columnas,
links ni pedidos durante diagnóstico.

## Evidencia que no puede inferirse

No declarar desplegado, activo o cerrado por merge. Registrar versión/fecha de
migración, despliegues Edge/Pages, estado del gate, sondas HTTP y resultado de la
prueba transaccional. Sin pago autorizado, el máximo cierre posible es
estructural.
