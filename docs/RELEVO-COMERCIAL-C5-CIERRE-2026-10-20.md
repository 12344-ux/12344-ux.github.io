# Relevo de sesión · Cierre estructural de Comercial C5 · 20 de octubre de 2026

**Punto de arranque vigente.** Leer primero este archivo; después
`CONTEXTO-MAGANDHI.md` §9 y `docs/PLANO-FASE-COMERCIAL.md`. Los relevos C1–C5
anteriores quedan como memoria histórica.

## 1. Respuesta corta

- **Comercial C1–C5 están cerrados estructuralmente.** C4 queda además
  superado funcionalmente por C5 y conserva su compatibilidad histórica.
- El **carrito queda ENCENDIDO** por decisión del dueño (`carrito_habilitado=true`)
  y Wompi sigue en `prod`: una compra real por carrito cobraría dinero real.
  Signup está OFF, así que solo pueden usarlo las cuentas ya existentes.
- **No existe todavía cierre transaccional** de C3/C4/C5: no ha habido ningún
  pago real por carrito. Ese cierre requiere una compra autorizada (§6).
- Siguiente etapa del plano aprobado: **Promocionar P0 · taxonomía y
  privacidad** (`docs/PLANO-FASE-COMERCIAL.md` §4). El dueño confirma la etapa
  al iniciar la próxima sesión.

## 2. Estado productivo exacto al cerrar

| Pieza | Estado |
|---|---|
| Migraciones Supabase | Aplicadas hasta **`20261106000100`**: C5 `20261106000000` y slug automático `20261106000100`, cada una una sola vez por SQL Editor el 20-oct-2026. `20261002000000` sigue superada y no se aplica |
| Historial de migraciones | **No existe** `supabase_migrations.schema_migrations` en el proyecto (medido). No hay ledger que reconciliar: todo se aplica manualmente por SQL Editor. **Nunca usar `supabase db push`** |
| Edge `crear-intencion-pago` | Versión C5 desplegada desde `main`, Verify JWT sin cambios |
| Edge `estado-pago` | Versión C5 desplegada desde `main` |
| `carrito_habilitado` | `true`, activado con `comercial-c5-activar.sql` (`activado_confirmado=true`) |
| Wompi | `prod`; ningún pago real por carrito |
| Tienda | C5 publicada (PR #113); Mis compras ya lee la RPC real |
| Slugs | 6/6 campañas publicadas con slug; trigger server-side activo |

## 3. Ventana ejecutada el 20-oct-2026

1. **Preflight** (`comercial-c5-preflight.sql`): las cinco comprobaciones de
   baseline C4 y ausencia limpia de C5/slug en `true`; ledger ausente.
2. **Edge C5 desplegadas** y sondas 1–7 de `COMERCIAL-C5-SONDAS.md` ejecutadas
   desde fuera: CORS `204` con origen permitido, origen ajeno no reflejado,
   `GET` `405`, JSON inválido `400`, referencia inexistente `404` con
   `no-store`, ruta C5 `{intencion:{}}` `400 INTENCION_INVALIDA`, carrito sin
   sesión válida `401 SESION_REQUERIDA`. Ninguna creó intenciones.
3. **Carrito OFF** durante las migraciones (la migración C5 aborta si no lo está
   y pasó).
4. **Migración C5** aplicada una vez. Verificado después: `mc_compras_listar`
   existe y rechaza a `anon` (`42501`).
5. **Migración slug**: el primer intento falló con `42501` porque el
   `search_path` creaba el helper en `pg_catalog`; revirtió completo
   (verificado: helper/trigger ausentes y `slug` aún nullable). Corregida en
   PR #291 y aplicada en un segundo Run con `COMMIT`.
6. **Postflight** ejecutado; invariantes finales en `true`. El SQL Editor solo
   mostró el último resultado; la activación y el diagnóstico repiten todos los
   gates en una sola evaluación.
7. **Activación**: el primer intento se detuvo con
   `C5_O_SLUG_NO_INSTALADO_O_INCOMPLETO` por un defecto del propio gate (ver §4)
   sin cambiar nada. Corregido, el segundo devolvió `activado_confirmado=true`.
8. **Prueba sin dinero**, informada por el dueño como correcta: dos productos,
   intención creada y Wompi cerrado sin pagar, carrito libre de inmediato,
   tarjeta en Mis compras · En proceso, «Continuar pago» por el mismo total sin
   crear otra intención, carrito usable mientras tanto y vencimiento sin
   transacción. No se archivaron capturas ni el estado agregado.

## 4. Defectos encontrados y corregidos (todos en scripts del repositorio)

| PR | Defecto | Efecto en producción |
|---|---|---|
| #290 | El preflight consultaba un ledger que no existe | Ninguno; solo lectura |
| #291 | La migración slug creaba el helper en `pg_catalog` | Ninguno; revirtió completa |
| #292 | `oid` ambiguo en la auditoría del postflight | Ninguno; solo lectura |
| #293 | El gate comparaba el índice DESC con `creado DESC`, texto que PostgreSQL nunca devuelve por columna | Ninguno; la activación se detuvo sola |
| #293 | El banco no detectaba errores `psql` de los scripts operativos | Ahora el veredicto los detecta y CI ejecuta diagnóstico → postflight → estado → activar → desactivar sobre PostgreSQL 15 con resultado positivo verificado |

Lecciones vigentes:

- El SQL Editor de Supabase muestra **solo el último resultado**. Todo SQL de
  diagnóstico para el dueño debe devolver una sola tabla y entregarse pegado en
  el chat.
- «CI verde» no basta: hay que leer en el log la salida positiva esperada.
- Si una activación falla, ejecutar `comercial-c5-diagnostico-activacion.sql`
  (solo lectura): lista exactamente qué condición falla.

## 5. Qué queda cerrado

- **C5:** separación atómica, carrito libre, Mis compras owner-safe,
  continuar/verificar pago, expiración perezosa, seguimiento desde
  `pedidos.estado`, Ventas solo avanza al siguiente estado y opinión visible
  solo tras entregado.
- **C4:** su bloqueo de 30 minutos y la prueba 9D dejan de ser requisito; las
  intenciones C4 históricas siguen despachándose a su cuerpo literal.
- **Slug automático:** defecto heredado de C4 cerrado en servidor; ninguna
  campaña nueva puede publicarse sin slug.

## 6. Pendiente, sin bloquear la siguiente etapa

1. **Cierre transaccional** (solo con autorización expresa): pago real C5 de
   monto bajo que demuestre APPROVED, un solo pedido con `customer_id`
   correcto, snapshot, inventario/proveedor, asiento, correo «Recibido»,
   webhook repetido sin duplicados y seguimiento en Mis compras. C1 cantidad 2
   tampoco tiene pago real.
2. **Opinión autenticada por cuenta:** el botón sigue «Próximamente»; el camino
   por código de reseña está intacto.
3. **Centro de cuenta:** Favoritos, Mis opiniones y Eliminar cuenta siguen como
   placeholders.
4. **Límites conocidos de C5:** no reserva inventario al crear la intención (un
   agotado antes de APPROVED va a revisión y reembolso humano), expiración
   perezosa sin cron, correo de etapa sin outbox y sin reembolso automático.
5. Opcional: archivar `comercial-c5-estado.sql` (ahora una sola tabla) y la
   sonda 8 de reapertura inexistente con token propio.

## 7. Operación con el carrito encendido

- Estado en cualquier momento: `supabase/operacion/comercial-c5-estado.sql`.
  `REVISAR` pide atención humana; `FALLA · contradicción` obliga a apagar.
- Apagar ante cualquier duda: `comercial-c5-desactivar.sql` y exigir
  `apagado_confirmado=true`.
- Reactivar solo con el `comercial-c5-activar.sql` actual de `main`; si falla,
  `comercial-c5-diagnostico-activacion.sql`.
- Una revisión no se resuelve sin confirmar el reembolso; no editar ni borrar
  intenciones, eventos ni pedidos para «limpiar» pruebas.

## 8. Prompt de arranque para el próximo chat

> Retomamos MAGANDHI tras el **cierre estructural de Comercial C5**. Lee primero
> `docs/RELEVO-COMERCIAL-C5-CIERRE-2026-10-20.md`, después `CONTEXTO-MAGANDHI.md`
> §9 y `docs/PLANO-FASE-COMERCIAL.md`. Estado: producción aplicada hasta
> `20261106000100` (C5 + slug automático), Edge C5 desplegadas, carrito
> **ENCENDIDO** a propósito y Wompi `prod`, sin pagos reales por carrito. No
> existe tabla de ledger: las migraciones se aplican solo a mano por SQL Editor
> y nunca con `supabase db push`. C1–C5 están cerrados estructuralmente; el
> cierre transaccional requiere un pago real que solo yo autorizo. La siguiente
> etapa del plano es **Promocionar P0 (taxonomía y privacidad)**: confírmame la
> etapa antes de construir. Entrégame los SQL pegados en el chat, de una sola
> tabla de resultado, y no toques producción sin mi confirmación.
