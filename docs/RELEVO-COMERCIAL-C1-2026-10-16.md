# Relevo de sesión · Comercial C1 · cantidad inmediata · 16 de octubre de 2026

> **HISTÓRICO · COMERCIAL C1:** este archivo conserva la evidencia y el punto de
> avance de C1 en su fecha. El relevo general vigente es
> `docs/RELEVO-COMERCIAL-C2-2026-10-16.md`; Comercial C2 ya quedó desplegado y
> probado en estructura, apagado hasta C3. Las referencias de este documento a
> C2 como siguiente tramo son históricas y no gobiernan el arranque actual.

Este archivo ya no es un punto de arranque ni un procedimiento ejecutable.
Conserva el corte exacto de C1 para auditoría; el trabajo vigente continúa
exclusivamente desde `docs/RELEVO-COMERCIAL-C2-2026-10-16.md`. Para identidad y
apertura de cuentas, `docs/RELEVO-CUENTAS-C2-2026-10-16.md` queda como relevo
temático histórico. **No ejecutar las instrucciones de continuación de este
archivo ni reconstruir Comercial C1/C2.**

## 1. Estado exacto

**Comercial C1 queda desplegado y probado en estructura.** Permite seleccionar `1..max_comprable` en compra inmediata, también como invitado, y conserva el cálculo autoritativo de precio, cantidad, máximo y monto en servidor.

Código fusionado:

- Backend/back-office: PR `12344-ux/12344-ux.github.io#276`, fusionado a `main` en `e75dc1cbd1643d3897e851cc2e06fe47f3b87ecc`.
- Tienda: PR `12344-ux/magandhi#102`, fusionado en `db56c4f64de9dc2af5ac77b3c444467e1a72cb0c`.

Producción medida por el dueño:

- Migración máxima aplicada: `20261102000000_comercial_c1_cantidad_inmediata.sql`.
- Postflight de producción: **9/9 `true`**.
- Edge Function `crear-intencion-pago` desplegada.
- Tienda publicada.
- El dueño confirmó en la ficha el selector, el máximo, el total, el modal y la compra invitada estructural.

## 2. Qué entrega C1

- `campana_producto.max_unidades_pedido`, entero de `1` a `20`, con `default 1` para conservar campañas históricas.
- Campañas permite configurar el máximo por pedido sin reutilizar `tope_escaparate`.
- `catalogo_publico` expone solo `max_comprable` entre `0` y `20`; no expone stock, reservas, piso Dropi, proveedor ni ids externos.
- Producto propio: máximo efectivo limitado por campaña y existencias disponibles.
- Producto de proveedor: máximo efectivo limitado por campaña y disponibilidad vendible, conservando el piso Dropi después de la cantidad solicitada.
- `crear-intencion-pago`, la persistencia de intención y `crear_pedido` revalidan cantidad y máximo en servidor.
- La tienda calcula la presentación a partir del catálogo, muestra el total antes de continuar y mantiene la compra invitada.
- Cantidad `1` conserva compatibilidad con el flujo histórico.

C1 **no** entrega carrito, checkout multiproducto ni derivación de `customer_id` para checkout autenticado. Tampoco cierra por sí solo toda la fase comercial ni el frente Promocionar.

## 3. Evidencia funcional obtenida

### Cantidad 1 · estructura sin dinero

- Solicitud de intención: **HTTP 200**.
- Persistencia: **7/7 `true`**.
- Esta prueba se detuvo antes del pago: **no hubo pago, pedido ni webhook**.

### Límite efectivo

- Con máximo configurado en `1`, solicitar cantidad `2` fue rechazado con **HTTP 409** y código público `MAX_COMPRABLE`.
- Esto confirma que el navegador no puede exceder el máximo efectivo aunque envíe una cantidad mayor.

### Cantidad 2 · estructura sin cierre transaccional

- Grisi quedó configurado con máximo de campaña `2` y `max_comprable=2`.
- La intención para cantidad `2` respondió **HTTP 200** por **13.980.000 centavos**, equivalentes a **COP 139.800**.
- La prueba no continuó a un pago real.

### Tienda

El dueño confirmó la estructura publicada: selector de cantidad, copy de máximo, total actualizado, modal de compra y continuidad del camino invitado. Esta comprobación valida la interfaz y la apertura de la intención; no sustituye una prueba monetaria completa.

## 4. Límite de la evidencia

**No se compraron dos unidades.** Para el caso cantidad `2` no se midieron:

- webhook aprobado;
- creación del pedido;
- baja de dos unidades;
- asiento contable;
- correo del pedido;
- repetición del webhook ni idempotencia.

Por eso el cierre exacto es **“desplegado y probado en estructura”**, no “cierre transaccional de dos unidades”. La definición final del plano sigue exigiendo que monto, pedido, inventario e idempotencia se comporten correctamente bajo un pago aprobado; esa definición no se relaja.

## 5. Contratos y reglas que no cambian

- Compra invitada permanece disponible; iniciar sesión sigue siendo opcional.
- El navegador no es autoridad para precio, monto, stock, máximo, UID ni `customer_id`.
- `tope_escaparate=0` conserva su semántica histórica de apagar la oferta; un valor positivo no limita la cantidad.
- `max_unidades_pedido` es el límite comercial y `max_comprable` el límite público efectivo.
- Un producto con `max_comprable=0` se trata como agotado.
- Para proveedor, el remanente posterior debe conservar el piso Dropi.
- `clientes.id` sigue siendo la identidad comercial; Auth no lo reemplaza.
- Las migraciones aplicadas son historia inmutable; cualquier corrección es forward.
- Código fusionado no prueba despliegue: el estado se actualiza solo con medición de producción.
- No registrar secretos, llaves, referencias de pago completas, correos ni datos personales de pruebas.

## 6. Siguiente punto aprobado en aquel corte (histórico; no ejecutar)

El siguiente tramo es **Comercial C2 · carrito autenticado persistente**:

- una cesta activa por UID;
- RLS de propietario;
- agregar, consolidar, cambiar y retirar líneas;
- persistencia entre dispositivos;
- precio siempre releído, nunca guardado como autoridad;
- superficie apagable y sin prometer checkout multiproducto antes de C3.

La prueba real de cantidad `2` queda **opcional y solo puede ejecutarse con autorización expresa del dueño**. No bloquea la construcción de C2.

La apertura pública de cuentas continúa siendo un frente separado: Cuentas C2 está técnicamente cerrado en preapertura, con signup OFF y Google External/Testing hasta publicar políticas. No reabrir ese trabajo al construir el carrito.

## 7. Orden previsto en aquel corte (histórico; no ejecutar)

1. Leer este relevo y no reconstruir C1.
2. Confirmar que la tarea es Comercial C2 y mantenerla separada de Cuentas C3/C4 y Promocionar.
3. Diseñar/aplicar únicamente migraciones forward posteriores a `20261102000000`.
4. Construir modelo, RLS, RPC y UI del carrito sin tocar todavía Wompi multiproducto.
5. Mantener el carrito apagable hasta que C3 complete intención y checkout multiproducto.
6. Medir cada despliegue antes de cambiar su estado documental.

## 8. Prompt histórico (no usar para una sesión nueva)

> Retomamos MAGANDHI después de Comercial C1. Lee `docs/RELEVO-COMERCIAL-C1-2026-10-16.md`, `CONTEXTO-MAGANDHI.md`, `docs/PLANO-FASE-COMERCIAL.md` y `supabase/INSTRUCCIONES.md`. C1 cantidad inmediata está desplegado y probado en estructura: backend #276 (`e75dc1cbd1643d3897e851cc2e06fe47f3b87ecc`), tienda #102 (`db56c4f64de9dc2af5ac77b3c444467e1a72cb0c`), migración máxima `20261102000000`, postflight 9/9 true, `crear-intencion-pago` desplegada y tienda publicada. Cantidad 1 dio HTTP 200 y persistencia 7/7 true sin pago/pedido/webhook; cantidad 2 excediendo max1 dio 409 `MAX_COMPRABLE`; con Grisi max2 y `max_comprable=2`, la intención qty2 dio HTTP 200 por 13.980.000 centavos (COP 139.800). El dueño confirmó selector, máximo, total, modal y compra invitada estructural. No hubo pago real de dos unidades ni se midieron webhook, pedido, baja2, asiento, correo o idempotencia para ese caso. No reconstruyas C1 ni afirmes cierre transaccional. Continúa con Comercial C2, carrito autenticado persistente. Una prueba real qty2 es opcional y requiere autorización expresa del dueño.