---
inclusion: always
---

# MAGANDHI · arranque de sesión

Antes de proponer o tocar nada en una sesión nueva:

1. Leer `docs/RELEVO-PROMOCIONAR-P2-CIERRE-2026-10-20.md`: es el
   relevo vigente del frente activo; después leer `docs/PLANO-PROMOCIONAR-P2.md`,
   `docs/PLANO-PROMOCIONAR-P3.md` y el contrato P0.
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
- Producción Supabase aplicada manualmente hasta `20261107000100` (P1:
  historial de slugs + corrección ACL). Edge de pagos permanecen en versión C5.
- **Carrito ENCENDIDO a propósito** (`carrito_habilitado=true`) y Wompi `prod`:
  cualquier compra por carrito cobra dinero real. Signup OFF.
- **No existe tabla de ledger** (`supabase_migrations.schema_migrations`): todas
  las migraciones se aplican a mano por SQL Editor, un Run por archivo. Nunca
  `supabase db push`; nunca reaplicar una migración histórica.
- Operación del carrito: `supabase/operacion/comercial-c5-estado.sql`,
  `comercial-c5-desactivar.sql`, `comercial-c5-activar.sql` y, si una
  activación falla, `comercial-c5-diagnostico-activacion.sql`.
- **Promocionar P0, P1 y P2 cerrados:** P2 fue aprobado visual/funcionalmente
  por el dueño; PR #298/#299, merge `90efd87`, Pages `39471770742` y cinco assets
  productivos HTTP 200 con comparación exacta 5/5. No hubo suite automatizada
  P2, SQL, Edge, backend o DNS. Mantener `noindex,follow` y sitemap solo home
  hasta políticas. **Siguiente etapa: P3 · Registro y enlace corto**; su contrato
  está en construcción y todos sus gates nacen OFF. No afirmar despliegue por
  código en Git ni adelantar P4/P5. Fuente:
  `docs/RELEVO-PROMOCIONAR-P2-CIERRE-2026-10-20.md`.
- **Candados documentales P3:** antes de distribuir, exigir configuración y
  enlace/resolubilidad autoritativos; un activo local no basta. Toda espera o
  falla debe degradar al enlace largo P2 dentro de un plazo total máximo de 3
  segundos. El polling refresca configuración e historial/estado; una mutación
  incierta refresca historial antes de inferir resultado o reintentar.
- El cron nominal P3 debe dirigirse a `current_database()` y su último run
  correcto pertenecer por `jobid` al job de esa base. El rollup exige índice
  encabezado por `fecha_colombia`; `text/html` solo habilita conteo con calidad
  efectiva válida `> 0` (`q` ausente = `1`). `actualizado_en` es token CAS de
  edición, no versión numérica ni clave idempotente. Crear un borrador sí usa
  una clave ligada al actor/payload para que el mismo reintento devuelva el
  existente; activar de nuevo el mismo `id` activo devuelve el mismo código. El
  banco P3 sigue pendiente: no bloquea por sí solo este corte OFF, pero sí cerrar
  P3 o activar cualquier gate.
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
