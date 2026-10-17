# Relevo de sesión · Comercial C3 · checkout multiproducto · 17 de octubre de 2026

Este es el punto general vigente para continuar el frente comercial. Leer junto
con `CONTEXTO-MAGANDHI.md`, `docs/PLANO-FASE-COMERCIAL.md` y
`supabase/INSTRUCCIONES.md`. Los relevos de Comercial C1/C2 quedan como memoria
histórica. No reconstruir C1, C2 o C3 ni confundir Comercial C4 con Cuentas C4.

## 1. Estado exacto

**Comercial C3 desplegado y probado en estructura; flag productivo final en
`false`. C4 es el siguiente tramo aprobado.**

Código fusionado:

- Backend/back-office: PR `12344-ux/12344-ux.github.io#280`; implementación
  `424e7632d214a90afdb7c9265fbe758bfa3fc580`; merge a `main`
  `275c0dd4548937075770ddd6dace1801c013c929`.
- Tienda: PR `12344-ux/magandhi#106`; implementación
  `c87934cd6034677be1c1888b8eadce95dcc348a4`; merge a `main`
  `b18c1ed4f075241a066048b0bfbe1b19d0eb96c9`; Pages construido.
- El banco de pruebas del backend pasó sobre el commit C3. Esta evidencia cubre
  migrabilidad y regresiones históricas; no sustituye un pago aprobado C3.

Producción medida por el dueño el 17-oct-2026:

- Preflight: C2 sano, `carrito_habilitado=false`, Wompi `prod`, cero revisiones,
  `sin_doble_carrito_activo=true` y `sin_lineas_huerfanas=true`.
- Migración forward
  `20261104000000_comercial_c3_checkout_multiproducto.sql` aplicada una sola vez.
- Postflight: todos los objetos, firmas, índice, RLS, grants e invariantes C3
  consultados dieron el valor esperado; máximo por checkout
  `1000000000` centavos y flag todavía `false`.
- Secrets productivos/sandbox y funciones existentes verificados sin exponer
  valores.
- `crear-intencion-pago` y `wompi-webhook` redesplegadas; `estado-pago` conservó
  su contrato y no necesitó redespliegue.
- Sondas inocuas: CORS desde `https://magandhi.com` respondió 204; carrito sin
  sesión respondió 401 `SESION_REQUERIDA`; webhook con ambiente desconocido
  respondió 400 y con ambiente `prod` sin firma respondió 401 `Firma ausente`.
- Con flag OFF se verificaron home, compra inmediata, carrito sin/con sesión,
  logout y conservación de líneas sin abrir cobros.
- En una primera activación temporal se comprobaron dos productos/cantidades,
  subtotales y total, persistencia, cambio/retiro, validaciones y modal. No se
  creó intención; el flag volvió a `false`.
- En una segunda activación temporal se creó una intención v2 productiva sin
  pagar. Wompi abrió con total exacto; el retorno quedó prudente en pendiente;
  el snapshot congeló líneas y subtotales exactos; ordinales continuos; no creó
  pedido ni evento. Un reintento desde otra sesión conservó exactamente una
  intención para UID/carrito/versión. El flag volvió a `false`.

## 2. Qué entrega C3

- Checkout del carrito autenticado con JWT validado y propietario revalidado.
- Cabecera compatible en `pagos_intencion` y líneas privadas congeladas en
  `pagos_intencion_items`.
- Precio, máximo, disponibilidad, líneas y total releídos/calculados en servidor.
- Firma Wompi sobre el monto exacto persistido como texto entero.
- Máximo de 20 líneas/cantidades y máximo monetario configurable.
- Verificación de proveedor agrupada por producto y secuencial ante Dropi.
- Una sola intención por UID, carrito y versión, incluso entre sesiones.
- Webhook preparado para monto, moneda, entorno, bigint exacto, pedido
  multiproducto e idempotencia, conservando rutas históricas v0/v1.
- Retorno prudente, memoria por cuenta/carrito/versión y bloqueo de doble pago en
  la tienda.

## 3. Límite explícito de la evidencia

Por decisión del dueño no se completó el pago productivo para no modificar
inventario. Por tanto C3 queda **correcto en estructura, no cerrado end-to-end**.
No están medidos todavía para una aprobación C3 real:

- evento Wompi válido y su repetición;
- pedido multiproducto;
- bajas exactas del inventario propio;
- pendiente/transcripción del producto proveedor;
- asiento contable;
- correo «Recibido»;
- caso de falta de stock entre intención y aprobación.

Existe una intención v2 de prueba en estado `creada`, sin pedido ni evento. Se
conserva como evidencia histórica; no borrar ni editar. No registrar en Git/chat
su referencia, UID ni datos del comprador. Si algún día se completa esa
intención, medir y documentar el resultado antes de afirmar cierre end-to-end.

Comercial C1 conserva además su límite independiente: no hubo pago real de
cantidad 2.

## 4. Siguiente tramo: Comercial C4

C4 entrega propiedad comercial y ciclo postpago coherentes:

1. derivar `customer_id` desde `cuentas_cliente` únicamente en servidor;
2. crear/vincular el cliente comercial de forma transaccional al aprobar la
   primera compra cuando todavía no exista;
3. conservar destinatario y dirección como snapshot del pedido;
4. aprobación consume solo las líneas congeladas; rechazo las desbloquea;
5. revisión mantiene un estado prudente;
6. el regreso desde Wompi identifica el checkout completo;
7. `Comprar ahora` e invitado permanecen independientes.

C4 se construye y despliega con el flag OFF. No exige completar toda la futura
pantalla de perfil/pedidos de Cuentas C3. La prueba monetaria de C3 queda como
pendiente de producción y requiere autorización expresa del dueño; no se debe
atribuir retrospectivamente como evidencia de C4.

## 5. Reglas para continuar

- No reaplicar `20261104000000`; cualquier corrección es una migración forward.
- Mantener `carrito_habilitado=false` durante construcción y despliegue de C4.
- Wompi permanece en `prod`; no cambiar globalmente a sandbox sin una ventana de
  mantenimiento, porque afectaría también `Comprar ahora`.
- No confiar en precio, monto, UID o `customer_id` enviados por navegador.
- No borrar la intención estructural de C3 ni fabricar un evento para cerrarla.
- No afirmar pedido, inventario, asiento, correo o idempotencia aprobada de C3
  hasta medirlos realmente.
- Promocionar P0–P5, Cuentas C3 y apertura pública de cuentas siguen separados.

## 6. Prompt de arranque para el próximo chat

> Retomamos MAGANDHI después de Comercial C3. Lee
> `docs/RELEVO-COMERCIAL-C3-2026-10-17.md`, `CONTEXTO-MAGANDHI.md`,
> `docs/PLANO-FASE-COMERCIAL.md` y `supabase/INSTRUCCIONES.md`. Estado exacto:
> **C3 desplegado y probado en estructura; flag final false**. Migración
> `20261104000000` aplicada; postflight C3 correcto; Edge Functions
> `crear-intencion-pago` y `wompi-webhook` redesplegadas; sondas de CORS/sesión/
> firma correctas; UI OFF/ON medida; una intención v2 productiva sin pago congeló
> líneas y total exactos, y un reintento desde otra sesión conservó una sola
> intención. No hubo aprobación, pedido, inventario, asiento, correo ni webhook
> repetido; no afirmar cierre end-to-end. No reconstruyas C1–C3. Continúa con
> **Comercial C4: vínculo server-side de `customer_id` y ciclo postpago del
> carrito**, manteniendo el flag OFF.
