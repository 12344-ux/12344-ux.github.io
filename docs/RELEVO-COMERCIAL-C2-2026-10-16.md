# Relevo de sesión · Comercial C2 · carrito autenticado persistente · 16 de octubre de 2026

> **Relevo histórico.** C3 ya quedó desplegado y probado en estructura el
> 17-oct-2026. El punto vigente es
> `docs/RELEVO-COMERCIAL-C3-2026-10-17.md`; las instrucciones siguientes
> conservan la evidencia de C2 en su fecha y no gobiernan el arranque actual.

Este fue el punto general vigente para continuar el frente comercial después de
C2. Leer hoy solo como memoria histórica junto con
`docs/PLANO-FASE-COMERCIAL.md` y `supabase/INSTRUCCIONES.md`.
`docs/RELEVO-COMERCIAL-C1-2026-10-16.md` conserva C1 y
`docs/RELEVO-CUENTAS-C2-2026-10-16.md` el frente temático de cuentas.
**No reconstruir Comercial C1/C2 ni confundir Comercial C2 con Cuentas C2.**

## 1. Estado exacto

**Comercial C2 desplegado y probado en estructura, apagado hasta C3**.

Código fusionado:

- Backend/back-office: PR `12344-ux/12344-ux.github.io#278`; implementación
  `f68fd24`; matriz `8d4c64d`; merge a `main`
  `a811082cc585ad8d77a98aa346ffbd06ac2ac3f4`. Pages terminó construido para ese
  merge.
- Tienda: PR `12344-ux/magandhi#104`; implementación
  `90dcb6d42eabd26935743b5bae4de9bba9692e39`; merge a `main`
  `35a104a1c12b9b9276773bc7d7c082c0733c73a9`. Pages terminó construido.

Producción medida por el dueño:

- Preflight: **3/3 `true`**.
- Migración máxima aplicada: `20261103000000`.
- Postflight: **10/10 `true`**.
- Flag OFF comprobado correcto antes de la prueba.
- Activación temporal para medir el carrito.
- Flag final: **`false`**.

## 2. Qué entrega C2

- Carrito persistente exclusivo de una cuenta autenticada válida.
- Una cesta activa por UID.
- Propiedad aislada por cuenta.
- Agregar y consolidar una línea existente.
- Cambiar cantidad y retirar líneas.
- Persistencia entre navegadores.
- Resolución de conflictos entre pestañas sin mantener dos cestas activas ni
  dejar líneas huérfanas.
- Logout que retira la cesta autenticada visible.
- Compra invitada conservada.
- Precio no persistido como autoridad del carrito; los contratos de precio,
  máximo y disponibilidad server-side permanecen vigentes.
- Superficie gobernada por flag y apagable mientras C3 no exista.

C2 entrega estructura de carrito. No entrega todavía intención ni checkout
multiproducto.

## 3. Evidencia funcional obtenida

Durante la activación temporal, el dueño confirmó:

1. agregar un producto;
2. consolidar al agregar de nuevo;
3. cambiar cantidad;
4. retirar;
5. persistencia entre navegadores;
6. aislamiento entre dos cuentas;
7. conflicto entre pestañas;
8. logout;
9. continuidad de la compra invitada;
10. `sin_doble_activo=true`;
11. `sin_huerfanas=true`.

La prueba comenzó con el flag OFF correctamente aplicado, usó una activación
temporal y terminó con el flag en `false`.

## 4. Límite de la evidencia

No hubo:

- dinero;
- Wompi;
- pedido;
- movimiento de Inventario.

C2 no congela líneas para cobro, no calcula ni firma un total multiproducto, no
crea pedido, no consume líneas después de un pago ni deriva el vínculo
transaccional de cuenta. No presentar este hito como cierre completo ni como
cierre de la fase comercial.

Comercial C1 conserva además su límite propio: no hubo pago real de cantidad 2
y para ese caso no se midieron webhook, pedido, baja de dos unidades, asiento,
correo ni repetición/idempotencia.

## 5. Contratos y reglas que no cambian

- Compra invitada permanece disponible; iniciar sesión sigue siendo opcional.
- El navegador no es autoridad para precio, monto, stock, máximo, UID ni
  `customer_id`.
- El carrito no reserva inventario.
- Precio, publicación, máximo y disponibilidad deben releerse antes de cobrar.
- `clientes.id` sigue siendo la identidad comercial; Auth no lo reemplaza.
- Una cuenta no puede ver ni operar el carrito de otra.
- Las migraciones aplicadas son historia inmutable; cualquier corrección es
  forward.
- Código fusionado y Pages construido no sustituyen la medición de producción.
- No registrar secretos, referencias de pago completas ni datos personales de
  pruebas.
- El carrito permanece apagado hasta que C3 complete su contrato.

## 6. Siguiente punto aprobado

El siguiente tramo aprobado es **Comercial C3 · intención y checkout
multiproducto**:

- cabecera de intención compatible con el flujo histórico;
- líneas congeladas con producto, cantidad, precio y subtotal;
- total calculado server-side sobre ids y cantidades;
- máximo de líneas, cantidades y monto;
- comprobación de proveedor con concurrencia baja;
- firma Wompi sobre el total persistido;
- webhook que valida monto, moneda y entorno;
- un único resultado auditable ante repetición;
- compatibilidad con intenciones históricas de una línea.

C4, Promocionar P0–P5 y la definición final de la fase siguen pendientes. La
apertura pública de Cuentas continúa separada: signup OFF y Google
External/Testing hasta publicar políticas.

## 7. Orden al retomar

1. Leer este relevo y no reconstruir C1/C2.
2. Confirmar que la tarea es Comercial C3 y mantenerla separada de Cuentas C3,
   Cuentas C4 y Promocionar.
3. Partir de la migración máxima aplicada `20261103000000`; cualquier cambio de
   base debe ser una migración forward posterior.
4. Conservar compra inmediata e invitada mientras se agrega la intención
   multiproducto compatible.
5. Congelar líneas y total con autoridad server-side antes de abrir Wompi.
6. Reutilizar los candados vigentes de máximo, disponibilidad, proveedor e
   idempotencia.
7. Mantener el carrito apagado mientras el contrato de C3 no esté completo.
8. Si una prueba llega a dinero real, pedir autorización expresa del dueño.
9. Medir despliegue y producción antes de cambiar el estado documental.
10. Mantener pendiente la definición final de la fase hasta probar sus criterios
    completos.

## 8. Prompt de arranque para el próximo chat

> Retomamos MAGANDHI después de Comercial C2. Lee
> `docs/RELEVO-COMERCIAL-C2-2026-10-16.md`, `CONTEXTO-MAGANDHI.md`,
> `docs/PLANO-FASE-COMERCIAL.md` y `supabase/INSTRUCCIONES.md`. Estado exacto:
> **Comercial C2 desplegado y probado en estructura, apagado hasta C3**. Backend
> #278: implementación `f68fd24`, matriz `8d4c64d`, merge
> `a811082cc585ad8d77a98aa346ffbd06ac2ac3f4`, Pages construido. Tienda #104:
> implementación `90dcb6d42eabd26935743b5bae4de9bba9692e39`, merge
> `35a104a1c12b9b9276773bc7d7c082c0733c73a9`, Pages construido. El dueño
> confirmó preflight 3/3 true, migración `20261103000000` aplicada, postflight
> 10/10 true, flag OFF correcto, activación temporal, agregar/consolidar/cambiar/
> retirar, persistencia entre navegadores, aislamiento entre dos cuentas,
> conflicto entre pestañas, logout/compra invitada, `sin_doble_activo=true` y
> `sin_huerfanas=true`. No hubo dinero, Wompi, pedido ni Inventario; el flag
> final quedó `false`. C1 conserva el límite de no pago real qty2. No reconstruyas
> C1/C2 ni presentes la fase como cerrada. Continúa con Comercial C3, intención y
> checkout multiproducto.
