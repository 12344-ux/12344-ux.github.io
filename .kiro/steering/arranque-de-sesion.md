---
inclusion: always
---

# MAGANDHI · arranque de sesión

Antes de proponer o tocar nada en una sesión nueva:

1. Leer `CONTEXTO-MAGANDHI.md` (realidad operativa y pendientes vigentes).
2. Leer `docs/RELEVO-COMERCIAL-C1-2026-10-16.md`: es el relevo general más
   reciente. **Comercial C1 queda desplegado y probado en estructura; no
   reconstruirlo ni afirmar una compra real de dos unidades.**
3. Leer `docs/PLANO-FASE-COMERCIAL.md`: C1 está estructuralmente listo y el
   siguiente tramo aprobado es C2, carrito autenticado persistente.
4. Si la tarea toca identidad o apertura de cuentas, leer
   `docs/CUENTAS-CLIENTE.md` y el relevo temático histórico
   `docs/RELEVO-CUENTAS-C2-2026-10-16.md`. Cuentas C2 sigue cerrado
   técnicamente en preapertura; signup está OFF y Google Testing hasta publicar
   políticas.
5. Solo si la tarea vuelve a Dropshipping, leer además
   `docs/dropshipping-envios/RELEVO-2026-10-10.md` y aplicar
   `.kiro/steering/dropshipping-magandhi.md`.

Realidad de arranque al 16-oct-2026:

- La migración más alta aplicada en producción es `20261102000000`.
- Comercial C1 está desplegado y probado en estructura: backend #276 y tienda
  #102 fusionados; postflight 9/9 `true`; `crear-intencion-pago` desplegada y
  tienda publicada.
- Cantidad 1 dio HTTP 200 y persistencia 7/7 `true`, sin pago/pedido/webhook.
  Cantidad 2 contra máximo 1 devolvió 409 `MAX_COMPRABLE`; con Grisi máximo 2 y
  `max_comprable=2`, la intención dio HTTP 200 por COP 139.800.
- El dueño confirmó selector, máximo, total, modal y compra invitada estructural.
  **No hubo compra real qty2:** no atribuirle webhook, pedido, baja2, asiento,
  correo ni repetición/idempotencia.
- El siguiente tramo aprobado es Comercial C2, carrito autenticado persistente.
  No reconstruir C1. Una prueba real qty2 es opcional y exige autorización
  expresa del dueño.
- Cuentas C1/C2 continúan desplegados; Cuentas C2 está cerrado técnicamente en
  preapertura. CAPTCHA sigue activo, signup permanece OFF y Google
  External/Testing hasta publicar políticas y avisos contextuales.
- `clientes.id` sigue siendo la identidad comercial; nunca reemplazarlo por el
  UID de Auth. `cuentas_cliente` es el puente.
- La tienda conserva compra como invitado y cuenta opcional.

Reglas que no cambian:

- Rama nueva + PR por cambio; migraciones forward; medir antes de afirmar.
- Cuando el dueño deba pegar o desplegar algo, dar **links directos**: el raw de
  GitHub fijado al commit probado (comprobado: responde 200 y coincide con lo
  probado) y la pantalla exacta del dashboard de Supabase
  (`https://supabase.com/dashboard/project/bxlzipwxyxdtffnuizbz/...`).
- En un sandbox nuevo, armar el banco con
  `bash supabase/pruebas/local/herramientas/preparar.sh` antes de dar algo por
  bueno.
