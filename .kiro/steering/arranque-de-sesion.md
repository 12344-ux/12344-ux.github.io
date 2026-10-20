---
inclusion: always
---

# MAGANDHI · arranque de sesión

Antes de proponer o tocar nada en una sesión nueva:

1. Leer `docs/RELEVO-PROMOCIONAR-P1-2026-10-20.md`: es el relevo vigente del
   frente activo; después leer `docs/PLANO-PROMOCIONAR-P1.md` y el contrato P0.
2. Leer `CONTEXTO-MAGANDHI.md` §9 y `docs/PLANO-FASE-COMERCIAL.md`.
3. Para estado de carrito, Wompi o producción, consultar
   `docs/RELEVO-COMERCIAL-C5-CIERRE-2026-10-20.md` y
   `docs/PLANO-COMERCIAL-C5.md`; los relevos C1–C5 anteriores son memoria
   histórica.
4. Si la tarea toca identidad/apertura, leer `docs/CUENTAS-CLIENTE.md` y
   `docs/RELEVO-CUENTAS-C2-2026-10-16.md`.
5. Solo si vuelve Dropshipping, leer `docs/dropshipping-envios/RELEVO-2026-10-10.md`
   y `.kiro/steering/dropshipping-magandhi.md`.

## Realidad de arranque · 20-oct-2026

- **Comercial C1–C5 cerrados estructuralmente.** C4 superado funcionalmente por
  C5. Sin pago real por carrito: no hay cierre transaccional.
- Producción Supabase aplicada hasta `20261106000100` (C5 + slug automático).
  Edge `crear-intencion-pago` y `estado-pago` en versión C5.
- **Carrito ENCENDIDO a propósito** (`carrito_habilitado=true`) y Wompi `prod`:
  cualquier compra por carrito cobra dinero real. Signup OFF.
- **No existe tabla de ledger** (`supabase_migrations.schema_migrations`): todas
  las migraciones se aplican a mano por SQL Editor, un Run por archivo. Nunca
  `supabase db push`; nunca reaplicar una migración histórica.
- Operación del carrito: `supabase/operacion/comercial-c5-estado.sql`,
  `comercial-c5-desactivar.sql`, `comercial-c5-activar.sql` y, si una
  activación falla, `comercial-c5-diagnostico-activacion.sql`.
- **Promocionar P0 cerrado y P1 preparado en código:** P1 tiene migración de
  historial/alias, runbook y shells de tienda, pero no está desplegado ni medido.
  Mantener `noindex,follow`; ejecutar únicamente con confirmación del dueño.
  Fuente: `docs/PLANO-PROMOCIONAR-P1.md`. P2–P5 siguen pendientes.
- Pago real únicamente con autorización expresa del dueño.

## Convenciones con el dueño

- Los SQL para el SQL Editor se entregan **pegados en el chat** y deben devolver
  **una sola tabla**: el editor muestra solo el último resultado.
- Antes de entregar un SQL operativo, ejecutarlo en CI y leer en el log la salida
  positiva esperada; «CI verde» no basta.
- Indicar siempre si un paso escribe o es solo lectura, y qué resultado exacto
  esperar.

Reglas permanentes: rama+PR, migraciones forward, medir antes de afirmar, no
exponer secretos/PII, y un comando sin error no es evidencia suficiente.
