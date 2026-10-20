# Comercial C5 · cierre operativo autoritativo

> **Ejecución · 20-oct-2026: fases A–E ejecutadas; C5 cerrado estructuralmente.** El carrito quedó **ENCENDIDO** por decisión del dueño y Wompi sigue en `prod`. Diferencias con lo previsto: el proyecto **no tiene** `supabase_migrations.schema_migrations`, así que el paso 2 no aplica; cuatro defectos de scripts se corrigieron antes de continuar (PR #290, #291, #292 y #293), sin efecto en producción. Pendiente: fase F (dinero, solo autorizada). Evidencia en `docs/RELEVO-COMERCIAL-C5-CIERRE-2026-10-20.md`. No volver a ejecutar las migraciones.
>
> El SQL Editor muestra **solo el último resultado** de cada Run. Para operar usar `comercial-c5-estado.sql` (una sola tabla) y, si una activación falla, `comercial-c5-diagnostico-activacion.sql` (solo lectura, una sola tabla con la causa exacta).

## Archivos y Runs separados

| Orden | Archivo/acción | Modifica BD |
|---:|---|---:|
| 1 | `comercial-c5-preflight.sql` | No |
| 2 | Reconciliar ledger C4 (no aplicó: el proyecto no tiene tabla de ledger) | No |
| 3 | Desplegar Edge C5 compatibles y ejecutar `COMERCIAL-C5-SONDAS.md` | No BD |
| 4 | `comercial-c5-desactivar.sql` y confirmar OFF | Sí, flag |
| 5 | `../migrations/20261106000000_comercial_c5_mis_compras.sql` | Sí |
| 6 | `../migrations/20261106000100_campanas_slug_automatico.sql` | Sí |
| 7 | `comercial-c5-postflight.sql` | No |
| 8 | Probar `mc_compras_listar()` con cuenta propia | Puede expirar C5 perezosamente |
| 9 | `comercial-c5-estado.sql` y regresión OFF | No |
| 10 | `comercial-c5-activar.sql` (si falla: `comercial-c5-diagnostico-activacion.sql`) | Sí, flag |
| 11 | Pruebas sin dinero; estado; decisión explícita del flag | Según acción |

Cada SQL se copia **completo** en una ejecución separada del SQL Editor. No concatenar desactivación, migraciones, postflight ni activación. **No existe ni debe crearse puente C5:** las Edge C5 son compatibles con C4 y se despliegan primero.

## Reglas no negociables

- No tocar producción para “probar” los archivos repo-side. El dueño ejecuta cada fase.
- No reaplicar C1–C4 ni usar una migración como rollback.
- El proyecto no tiene `supabase_migrations.schema_migrations` (medido el 20-oct-2026): todo se aplica a mano por SQL Editor. **Nunca usar `supabase db push`** ni crear o rellenar tablas internas de historial.
- Wompi permanece en `prod`; la configuración es compartida con compra inmediata.
- No abrir Wompi ni pagar como diagnóstico. Pago real C5 únicamente con autorización expresa.
- Mantener el carrito OFF durante ambas migraciones, postflight y regresión OFF.
- Los diagnósticos no listan PII, referencias, UUID, transacciones, secretos ni motivos internos.
- Una intención/revisión C4 o C5 legítima no bloquea por sí sola la activación global C5. El estado agregado la hace visible; las contradicciones estructurales sí fallan cerrado.
- Ante duda, ejecutar `comercial-c5-desactivar.sql`; solo asumir OFF cuando la consulta posterior al COMMIT diga `apagado_confirmado=true`.

## Fase A · medir y reconciliar, sin escribir

1. Ejecutar `comercial-c5-preflight.sql` completo.
2. Archivar sus cinco salidas sin añadir datos privados.
3. Confirmar baseline C4, ausencia limpia de C5/slug, ciclos agregados, slugs por completar y Wompi `prod`.
4. Comparar la migración C4 del repo con lo aplicado y reconciliar su ledger mediante el procedimiento aprobado. Si no está reconciliado, detenerse: no migrar ni usar `db push`.

Los conteos de intenciones son fotografías. Actividad C4 legítima puede cambiar respecto del relevo y se investiga, no se borra ni retoca.

## Fase B · Edge compatibles y sondas

Desplegar desde el commit revisado `crear-intencion-pago` y `estado-pago`, conservando la configuración de gateway/Verify JWT existente. Ejecutar las sondas 1–7 de `COMERCIAL-C5-SONDAS.md`: CORS para los tres orígenes permitidos y rechazo de uno ajeno, método/body inválidos, referencia inexistente, carrito sin sesión y router C5 no mutante. Estas sondas no crean intención ni abren Wompi. La sonda de reapertura con referencia válida se reserva hasta después de instalar C5, porque su RPC todavía no existe sobre C4.

## Fase C · ventana SQL controlada

1. Ejecutar `comercial-c5-desactivar.sql`; exigir `apagado_confirmado=true`.
2. En un Run nuevo, aplicar **una sola vez** `20261106000000_comercial_c5_mis_compras.sql`.
3. En otro Run nuevo, aplicar **una sola vez** `20261106000100_campanas_slug_automatico.sql`.
4. En otro Run, ejecutar `comercial-c5-postflight.sql`.
5. Con C5 instalado y aún OFF, ejecutar la sonda 8 de reapertura inexistente.

La migración slug preserva literalmente los slugs existentes, completa solo NULL de forma determinista y deja NOT NULL + trigger server-side. Un fallo en cualquiera de los Runs mantiene el carrito OFF; no se intenta “compensar” reejecutando historia.

### Gate postflight

Antes de continuar deben quedar correctos: cuatro columnas; constraints C4/C5; índices C5 y slug; trigger C5 activo y C4 retirado; trigger slug activo; ciclos 0/4 preservados; snapshots/separaciones coherentes; slug sin NULL/duplicados; RLS/ACL sin ampliación; firmas exactas, `SECURITY DEFINER`, `search_path=public` y grants nominales; Wompi `prod`.

## Fase D · owner-safe y regresión OFF

Con cuenta propia, abrir **Mis compras** y comprobar que `mc_compras_listar()` solo devuelve tarjetas de esa cuenta, sin PII ni IDs internos. Recordar que la RPC puede materializar expiración perezosa C5: no es un diagnóstico estrictamente read-only.

Con el flag aún OFF:

- back-office, login/logout y tienda cargan;
- compra inmediata e invitada conservan su camino hasta antes de pagar;
- estado de ciclos históricos continúa compatible;
- Campañas crea una ficha sin slug manual y recibe uno automático; dos nombres iguales reciben base y `-2`; editar sin cambiar slug lo preserva;
- no abrir Wompi ni autorizar cobros.

Ejecutar `comercial-c5-estado.sql`. Toda contradicción debe ser cero antes de activar.

## Fase E · ventana ON sin dinero

Solo si A–D están aprobadas, ejecutar `comercial-c5-activar.sql` y exigir `activado_confirmado=true`. SQL verifica estructura C5+slug, ACL e invariantes, pero no puede comprobar versiones Edge/Pages: esos gates son humanos.

Recorridos mínimos con dos cuentas propias:

- agregar dos productos, crear intención y confirmar separación atómica y carrito libre;
- reintentar con versión fuente: misma intención, no una segunda;
- Mis compras muestra la tarjeta En proceso y continuar pago vigente sin crear otra;
- no autorizar el widget Wompi;
- dejar vencer una intención sin transacción y confirmar No completada sin tocar el carrito actual;
- aislamiento entre cuentas y reapertura ajena indistinguible;
- comprobar que una intención C4 histórica conserva su contrato;
- probar el siguiente estado de un pedido controlado solo si existe uno autorizado; repetir estado es no-op;
- ejecutar estado agregado y archivar únicamente conteos/booleanos.

Al terminar, decidir explícitamente ON/OFF. Si la ventana se cierra o hay duda, desactivar y confirmar durablemente.

## Fase F · dinero real, solo autorizado

El cierre transaccional requiere una compra C5 real de monto bajo expresamente autorizada: APPROVED verificado, un solo pedido del dueño correcto, snapshot, inventario/proveedor, asiento (o pendiente visible según contrato), correo Recibido y webhook repetido sin duplicar pedido, inventario, asiento ni correo. Un posible doble cobro o falta de stock va a revisión humana; no se automatiza un reembolso.

## Criterio de cierre

Repo/CI, Pages verde o este runbook **no cierran C5**. Cierre estructural exige evidencia ejecutada de Edge, ambas migraciones, postflight, owner-safe y regresión sin dinero. Cierre transaccional exige además la Fase F autorizada. Solo después se actualizan contexto, plano, relevo e instrucciones con resultados reales y el valor final del flag.
