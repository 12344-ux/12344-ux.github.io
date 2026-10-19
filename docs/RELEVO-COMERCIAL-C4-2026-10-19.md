# Relevo de sesión · Comercial C4 · cuenta y ciclo del carrito · 19 de octubre de 2026

Punto general vigente para continuar el frente comercial. Leer junto con
`supabase/operacion/COMERCIAL-C4-CIERRE.md`, `CONTEXTO-MAGANDHI.md`,
`docs/PLANO-FASE-COMERCIAL.md` y `supabase/INSTRUCCIONES.md`. Los relevos C1–C3
quedan como memoria histórica. No confundir Comercial C4 con Cuentas C4.

## 1. Estado exacto al cerrar la sesión (19-oct-2026, noche)

**C4 está aplicado, desplegado y probado sin dinero en producción. El carrito
quedó ENCENDIDO (`carrito_habilitado=true`) a propósito**, porque el dueño
continúa de inmediato en el siguiente chat. C4 no está cerrado formalmente:
falta registrar la expiración de 30 minutos, decidir el rediseño del ciclo
carrito/pago y dejar el flag en su valor final.

| Pieza | Estado |
|---|---|
| Backend/back-office PR #283 | Fusionado (`0d35d8f`), Pages `SUCCESS` |
| Tienda PR #108 | Fusionado (`55e0187`), Pages `SUCCESS` |
| Paquete operativo PR #284 | Fusionado (`0bd7546`), banco PostgreSQL 15/Deno run `39326788045` `SUCCESS` |
| Corrección UUID tienda PR #109 | Fusionado (`9ac92d8`), Pages run `39336452763` `SUCCESS` |
| Activación con vencidas PR #285 | Fusionado (`93e347a`), Pages run `39336495250` `SUCCESS` |
| Migración `20261105000000` | **Aplicada una vez** en SQL Editor |
| Edge `estado-pago` | **Desplegada** (C4), sobre el puente y luego sobre C4 |
| Edge `crear-intencion-pago` | **Desplegada** (C4), Verify JWT sin cambios |
| `carrito_habilitado` | **`true`** al cierre de la sesión |
| Wompi | `prod`; no se hizo ningún pago real |

## 2. Ejecución productiva registrada hoy

Proyecto Supabase `bxlzipwxyxdtffnuizbz`. Todos los resultados son agregados,
sin PII.

1. **Preflight** (`comercial-c4-preflight.sql`, por bloques):
   - estructura: 5/5 `coincide=true` (C3 presente, índice v2, C4 ausente,
     singleton y flag OFF);
   - historia C3: **`v2_total=0`**, frente al 1 documentado; resto en 0/`true`;
   - invariantes: 4/4 `true`, `revisiones_pendientes=0`;
   - Wompi: singleton, `prod`, llave activa configurada.
   - **Hallazgo:** en producción no existe la intención v2 que el relevo C3
     describía (abierta en Wompi sin pagar). El dueño indicó que el pago de
     prueba no se hizo. Se aceptó continuar: C4 arranca sin intención ciclo 0,
     `c3_preservadas=0` es el valor esperado y la prueba de sucesión C3 queda
     **no aplicable**. La causa exacta de la ausencia no se investigó más.
2. **Puente** `comercial-c4-puente-estado.sql`: 4/4 `true`.
3. **Edge `estado-pago`** desplegada. Sondas desde fuera: CORS 204, GET 405,
   cuerpo inválido 400, referencia inexistente 404 con `no-store`, referencia
   mal formada 404.
4. **Migración** `20261105000000_comercial_c4_cuenta_ciclo_carrito.sql`:
   `Success`, una sola ejecución. Probablemente no quedó registrada en
   `supabase_migrations.schema_migrations`; no usar `supabase db push` hasta
   reconciliar el historial.
5. **Postflight** en 4 bloques (versión compacta entregada en el chat):
   8/8 `true` de estructura, 11 constraints, 17 columnas e índice v2;
   historia en 0, con `c3_preservadas=0`; RLS/permisos 6/6 `true`;
   **30/30 funciones** correctas en SECURITY DEFINER, search_path y EXECUTE.
6. **Edge `crear-intencion-pago`** desplegada. Sondas: CORS 204, GET 405,
   cuerpo inválido 400, carrito mal formado 400 `CARRITO_INVALIDO`, monto
   inyectado 400, carrito sin sesión 401 `SESION_REQUERIDA`, producto
   inexistente en compra inmediata 404. Ninguna creó intenciones.
7. **Regresión OFF:** el dueño continuó directamente a la ventana ON; no quedó
   evidencia casilla por casilla del paso 7.
8. **Activación** con `comercial-c4-activar.sql`: carrito encendido.
9. **Pruebas ON sin dinero**, informadas por el dueño:
   - agregar, consolidar y cambiar cantidades funcionó con el cubo Rubik;
   - tras las dos correcciones de §3, la manzanilla y el Rubik se agregan y el
     checkout desde el carrito funciona;
   - Wompi `prod` aceptó el `expiration-time` firmado y **muestra el temporizador**;
   - con la intención pendiente, el carrito queda bloqueado: no se puede
     agregar ni cambiar hasta que vence (comportamiento C4 esperado);
   - **sin registrar:** resultado de la expiración (9D), capturas de la
     consulta de estado y prueba de aislamiento con una segunda cuenta.
10. **No ejecutado:** pago con dinero, desactivación final y decisión del flag.

## 3. Defectos encontrados en producción y corregidos

1. **IDs de campaña rechazados por la tienda (PR #109).** `carrito-core.js`
   exigía UUID RFC 4122. Las campañas sembradas en 2025 tienen ids válidos para
   PostgreSQL pero sin versión (`00000000-0000-0000-0000-0000000c0001`). Por
   eso **5 de 6 campañas publicadas** no podían agregarse, y la tienda mostraba
   "revisa tu conexión". Se aceptó la forma canónica 8-4-4-4-12, se agregaron
   mensajes claros para `CO_CAMPANA_NO_COMPRABLE`, `CO_MAX_COMPRABLE` y
   `CO_SOLICITUD_INVALIDA`, y se renovó la caché (`?v=3` / `carrito-ui.js?v=5`).
2. **Producto publicado sin slug (dato corregido; falta prevención).** El cubo
   Rubik estaba publicado con `slug=null`. El checkout multiproducto exige slug
   y respondía `PW_CAMPANA_NO_COMPRABLE` → `CARRITO_NO_DISPONIBLE`; la tienda
   mostraba en bucle "Una línea ya no se puede comprar como estaba". El dueño
   le asignó `cubo-rubik-4x4-qiyi` desde el back-office (verificado en
   `catalogo_publico`). **Hoy cualquier campaña nueva puede volver a publicarse
   sin slug**; ver decisión A en §4.
3. **Reactivación bloqueada por intenciones ya vencidas (PR #285).** El script
   de activación rechazaba cualquier intención `creada` sin liberar, aunque
   estuviera vencida. Como la liberación es perezosa y exige el flag encendido,
   apagar con una vencida dejaba el carrito imposible de reactivar. Ahora solo
   bloquean una intención vigente o una revisión abierta.

## 4. Decisiones abiertas para el próximo chat (recordárselas al dueño)

### A. Dirección web (slug) obligatoria — el dueño pidió corregirlo

Propuesta: **generación automática en servidor**.

- Trigger en `campana_producto`: si el slug queda vacío al crear o editar, se
  genera con `cm_normalizar_slug(nombre)`.
- Si el slug ya existe, se agrega el sufijo `-2`, `-3`, etc., bajo un advisory
  lock. Si el nombre normalizado queda vacío, se usa `producto-<8 hex del id>`.
- Cubre back-office, Dropshipping y SQL manual. Al migrar se rellenan las
  campañas existentes sin slug.
- Texto de ayuda del formulario: "Si la dejas vacía, se genera desde el nombre".
- Complemento recomendado: que el carrito marque como "no se puede pagar" una
  línea sin slug, en lugar de entrar en bucle.
- Los enlaces de Promocionar (P3) son una capa aparte con su propio código; no
  reemplazan ni cambian el slug base.

### B. Bloqueo de 30 minutos — el dueño lo considera mala experiencia

Hoy, si la persona se arrepiente en Wompi, no puede tocar su carrito hasta que
vence la intención. Hay dos caminos; el dueño se inclina por el segundo:

**B1 · Botón "Cancelar este pago"** (cambio menor sobre C4):

- RPC autenticada que pasa la intención propia a `rechazada`, la libera y
  versiona una sola vez.
- **Regla:** solo se puede cancelar si Wompi todavía no reportó transacción
  (`transaccion_id` nulo). Si ya hay un pago en proceso (PSE/Nequi), responde
  "tu banco está confirmando el pago".
- Confirmación previa: "Si ya completaste el pago, no lo canceles".
- Red de seguridad existente: un APPROVED posterior queda en revisión, sin
  pedido doble.

**B2 · Carrito libre + "Mis compras"** (propuesta del dueño, C5):

- Al crear la intención, las líneas congeladas pasan a ser una **compra en
  proceso** y el carrito queda libre al instante. El carrito solo prepara
  pedidos; nunca guarda pagos.
- La compra en proceso vive en **Mis compras**. El dueño ya tiene pensada esta
  sección y la describirá en el próximo chat.
- Opinión registrada: es el mejor modelo y simplifica C4, porque desaparecen el
  bloqueo y el consumo del carrito al aprobar. Gran parte ya existe: el snapshot
  `pagos_intencion_items` es esa compra.

Decisiones a tomar en B2, con la recomendación entre paréntesis:

1. Nombre: "intento de pago" mientras no se apruebe y "pedido" solo al
   aprobarse (Ventas no debe llenarse de intentos; el stock baja solo al pagar).
2. Momento de liberar el carrito: al **crear** la intención, no al volver de
   Wompi (muchos cierran Wompi y no regresan).
3. Si vuelve sin pagar: aviso en el carrito "Tienes un pago pendiente con N
   productos", con *Pagar ahora* (si sigue vigente), *Cancelar* y *Devolver al
   carrito*.
4. Cancelado o no pagado: queda en Mis compras con *Volver a comprar* o
   *Devolver al carrito*; precio y disponibilidad se recalculan en servidor.
5. Cancelar: botón en Mis compras con la misma regla de B1.
6. Pagar dos veces: avisar cuando un producto del carrito ya está en un intento
   pendiente. Si igual ocurre, son dos pedidos legítimos o caen en revisión por
   falta de stock.
7. APPROVED después de cancelar o vencer: sigue en revisión, como hoy.
8. Mis compras se cruza con Cuentas C3 (perfil/pedidos): diseñarlas juntas.

Encaje propuesto: cerrar C4 tal como está (técnicamente probado) y construir
B2 como **C5**, en una migración forward nueva sobre C4 sin rehacer nada. El
slug (A) va antes, como cambio independiente.

### C. Valor del flag mientras se diseña

El carrito quedó **encendido**. Mientras siga así, cualquier cuenta existente
puede usarlo y **pagar con dinero real** (Wompi `prod`), con el bloqueo de 30
minutos de C4. El signup está OFF, así que solo afectan cuentas ya creadas.
Decidir al inicio del próximo chat si se mantiene encendido o se apaga con
`comercial-c4-desactivar.sql` hasta tener A/B.

### D. Pendientes menores

- Registrar la prueba 9D (expiración, versión +1, líneas conservadas) con la
  consulta de estado compacta (§5).
- Prueba de aislamiento con una segunda cuenta en C4.
- Regresión OFF casilla por casilla, si se apaga el flag.
- Reconciliar el historial de migraciones antes de cualquier `db push`.
- Prueba con dinero: solo con autorización expresa (C1 qty2, C3 y C4 siguen sin
  cierre end-to-end).
- Corregir el relevo C3: la intención v2 descrita no existe en producción.

## 5. Consulta de estado compacta (solo lectura)

La que se usó hoy en el chat. Devuelve una fila, sin PII.

```sql
begin transaction read only;
set local search_path = pg_catalog, public;
set local statement_timeout = '15s';
select
  (select carrito_habilitado from comercial_config where id = 1) as carrito_encendido,
  count(*) filter (where ciclo_carrito_version = 4) as intenciones_c4,
  count(*) filter (where ciclo_carrito_version = 4 and estado = 'creada'
                     and expira_en > statement_timestamp()) as pendientes_vigentes,
  count(*) filter (where ciclo_carrito_version = 4 and estado = 'creada'
                     and expira_en <= statement_timestamp()
                     and carrito_liberado_en is null) as vencidas_sin_liberar,
  count(*) filter (where ciclo_carrito_version = 4 and estado = 'rechazada'
                     and carrito_liberado_en is not null) as liberadas,
  count(*) filter (where ciclo_carrito_version = 4 and estado = 'procesada') as aprobadas,
  count(*) filter (where estado = 'requiere_revision' and resuelta_en is null) as revisiones_abiertas,
  (select count(*) from pw_sucesiones_c4) as sucesiones
from pagos_intencion;
rollback;
```

## 6. Contrato C4 vigente en producción (resumen)

- Expiración autoritativa de 30 minutos fijada en servidor e incluida en la
  firma Wompi.
- `customer_id` derivado de cuenta/Auth bajo el lock `cc-correo:`;
  destinatario separado de la identidad.
- `bloqueo_pago` `null|pendiente|revision` en el snapshot. Las mutaciones
  rechazan `CO_CARRITO_BLOQUEADO`.
- APPROVED consume solo lo congelado y preserva extras. DECLINED/VOIDED/ERROR y
  expiración liberan y versionan una vez. PENDING bloquea. APPROVED tardío pasa
  a revisión. La revisión se resuelve solo con
  `pw_resolver_revision_c4(..., 'reembolsado_liberar', nota)`.
- El retorno v2 exige JWT del propietario. La respuesta lleva estado e
  id/versión del carrito propio, sin PII, monto, pedido ni transacción.
- Los helpers internos no tienen EXECUTE de API. Compra inmediata e invitada no
  cambian.

## 7. Reglas para continuar

- No reaplicar migraciones; todo cambio nuevo (slug, C5) es forward.
- No borrar ni editar intenciones o eventos para "limpiar" pruebas.
- Wompi permanece en `prod`; dinero solo con autorización expresa.
- Ante comportamiento raro: `comercial-c4-desactivar.sql` y confirmar
  `apagado_confirmado=true`.
- Reactivar solo con el `comercial-c4-activar.sql` actual de `main`.

## 8. Prompt de arranque para el próximo chat

> Retomamos MAGANDHI en **Comercial C4**. Lee este relevo primero,
> `supabase/operacion/COMERCIAL-C4-CIERRE.md` y `CONTEXTO-MAGANDHI.md`. Estado:
> C4 está aplicado y desplegado en producción (migración `20261105000000`, ambas
> Edge, postflight 30/30), con PR #283/#108/#284/#109/#285 fusionados. **El
> carrito quedó encendido.** Pruebas sin dinero OK tras corregir los ids de
> campaña (PR #109) y el slug faltante del Rubik. Antes de seguir, recuérdame
> las decisiones abiertas de §4: (C) si dejo el carrito encendido; (A) slug
> automático en servidor; (B) bloqueo de 30 min → B1 botón cancelar o B2
> carrito libre + "Mis compras" (mi preferencia; te describiré Mis compras), con
> sus 8 decisiones. Después cerramos C4 formalmente y planeamos el siguiente
> tramo. No toques producción sin mi confirmación.
