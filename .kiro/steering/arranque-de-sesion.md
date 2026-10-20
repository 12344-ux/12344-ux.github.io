---
inclusion: always
---

# MAGANDHI · arranque de sesión

Antes de proponer o tocar nada en una sesión nueva:

1. Leer `docs/RELEVO-COMERCIAL-C5-2026-10-19.md`: es el relevo general vigente.
2. Leer `docs/PLANO-COMERCIAL-C5.md` y `CONTEXTO-MAGANDHI.md`.
3. Para contratos históricos, consultar `docs/PLANO-FASE-COMERCIAL.md` y el
   relevo C4; C1–C4 ya no gobiernan el arranque.
4. Si la tarea toca identidad/apertura, leer `docs/CUENTAS-CLIENTE.md` y
   `docs/RELEVO-CUENTAS-C2-2026-10-16.md`.
5. Solo si vuelve Dropshipping, leer `docs/dropshipping-envios/RELEVO-2026-10-10.md`
   y `.kiro/steering/dropshipping-magandhi.md`.

## Realidad de arranque · 19-oct-2026 noche

- C5 está construido y fusionado en Git, pero **no desplegado en Supabase**.
- Backend PR #287: merge `c8fd03c`; banco PostgreSQL 15/Deno run `39354906924`
  `SUCCESS`.
- Tienda PR #113: merge `4a0b439`; GitHub Pages `built`.
- Producción Supabase sigue en C4, migración `20261105000000`; último flag
  documentado `carrito_habilitado=true`; Wompi `prod`.
- `20261106000000_comercial_c5_mis_compras.sql` está solo en Git. Las Edge C5
  `crear-intencion-pago` y `estado-pago` también están solo en Git.
- C4 fue aplicada manualmente y su ledger puede no estar reconciliado. **Nunca
  usar `supabase db push` ni reaplicar migraciones.**
- Falta paquete operativo C5 (preflight/postflight/estado/activación) y slug
  automático server-side.
- La tienda C5 es compatible mientras el backend siga C4, pero Mis compras no
  tendrá datos reales hasta instalar la RPC C5.
- Pago real únicamente con autorización expresa del dueño.

## Siguiente secuencia

1. Diagnóstico de solo lectura y reconciliación del ledger C4.
2. Preparar paquete operativo C5 y slug forward.
3. Desplegar Edge C5 compatibles.
4. Apagar y confirmar carrito OFF.
5. Aplicar C5 manualmente una sola vez y ejecutar postflight.
6. Reactivar y probar sin dinero: separación inmediata, retry único, Mis compras,
   expiración sin transacción, PENDING bancaria, aislamiento y estados de pedido.
7. Solo con autorización, pago real para cierre transaccional.

Reglas permanentes: rama+PR, migraciones forward, medir antes de afirmar, no
exponer secretos/PII, y un comando sin error no es evidencia suficiente.
