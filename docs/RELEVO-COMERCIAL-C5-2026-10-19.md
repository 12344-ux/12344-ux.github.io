# Relevo de sesión · Comercial C5 · Mis compras y carrito libre · 19 de octubre de 2026

Punto general vigente para continuar el frente comercial. Leer primero este
archivo y después `docs/PLANO-COMERCIAL-C5.md`, `CONTEXTO-MAGANDHI.md`,
`docs/PLANO-FASE-COMERCIAL.md` y `supabase/INSTRUCCIONES.md`. El relevo C4 queda
como evidencia histórica de lo que hoy está desplegado en Supabase; ya no
gobierna el siguiente paso.

## 1. Respuesta corta: ¿al desplegar terminan C4 y C5?

**C5 ya está construido, fusionado y probado en CI, pero todavía no está
aplicado en Supabase.** C4 sigue siendo el backend productivo. Cuando se haga el
despliegue controlado C5 y pasen las pruebas sin dinero:

- C4 queda **superado funcionalmente** por C5 en la experiencia del carrito;
- C5 queda **cerrado estructuralmente**;
- el cierre transaccional definitivo exige además una compra C5 real autorizada
  que demuestre APPROVED, un solo pedido, inventario/proveedor, asiento, correo e
  idempotencia del webhook.

La prueba 9D de expiración del carrito bloqueado C4 deja de ser requisito del
modelo nuevo: C5 ya no bloquea ni libera el carrito al vencer. Sí debe probarse
que una intención C4 histórica siga funcionando con su contrato anterior.

Dos pendientes no desaparecen con C5:

1. **Slug automático en servidor.** El dato del Rubik se corrigió, pero todavía
   puede publicarse otra campaña sin slug. Debe ser una migración forward
   independiente; es necesario para cerrar el defecto operativo heredado de C4.
2. **Opinión autenticada.** C5 muestra la acción únicamente cuando el pedido está
   entregado y no existe opinión, pero el botón queda deliberadamente como
   «Próximamente» hasta definir el registro por cuenta. El camino histórico por
   código sigue intacto.

## 2. Estado exacto al terminar esta sesión

### Producción

- Supabase sigue aplicado hasta `20261105000000` (Comercial C4).
- Edge `crear-intencion-pago` y `estado-pago` siguen en versión C4 salvo que una
  medición posterior demuestre lo contrario.
- Último valor documentado: `carrito_habilitado=true` y Wompi `prod`.
- C4 fue probado sin dinero; no hubo pago real C3/C4/C5 en esta sesión.
- La migración C4 fue pegada por SQL Editor y probablemente no está reconciliada
  en `supabase_migrations.schema_migrations`. **No usar `supabase db push`.**

### Código fusionado

| Pieza | Estado |
|---|---|
| Backend/back-office PR #287 | Fusionado en `c8fd03c` |
| Implementación backend | `0ca9b51` |
| Matriz C5 | `60def28` |
| Banco PostgreSQL 15/Deno | run `39354906924`, `SUCCESS` |
| Tienda PR #113 | Fusionado en `4a0b439` |
| Implementación tienda | `bee2992` |
| GitHub Pages tienda | `built` para `4a0b439` |
| Migración `20261106000000` | **Solo en Git; NO aplicada** |
| Edge C5 | **Solo en Git; NO desplegadas** |

La tienda C5 ya está publicada por Pages, pero fue construida para degradar de
forma compatible mientras el backend siga en C4: compra inmediata/invitada y
checkout C4 continúan; `Mis compras` no tendrá datos reales hasta instalar la
RPC C5.

## 3. Qué quedó construido

### Backend C5

- Nuevas intenciones v2 nacen con `ciclo_carrito_version=5` y vencimiento de 30
  minutos.
- Al crear una intención, el snapshot se congela y sus líneas salen del carrito
  en la misma transacción; la versión avanza exactamente una vez.
- Retry con la versión fuente recupera la misma intención solo si sigue creada,
  vigente y sin transacción; una terminal nunca vuelve a firmarse.
- PENDING/rechazo/expiración/APPROVED/revisión C5 no tocan el carrito nuevo.
- PENDING vigente puede fijar la transacción; PENDING tardío no revive la compra.
- APPROVED directo y vigente es válido aunque no se haya recibido PENDING.
- Una transacción distinta o APPROVED tardío va a revisión y no crea otro pedido.
- Los errores técnicos de creación de pedido hacen rollback para permitir retry;
  los errores comerciales quedan en revisión.
- `mc_compras_listar()` deriva dueño/cuenta y devuelve hasta 100 tarjetas
  saneadas: intenciones C5 y pedidos históricos/manuales/C4/C5 vinculados al
  `customer_id`, sin duplicar.
- `mc_reabrir_intencion_c5(...)` solo permite a la Edge volver a firmar una
  intención propia, vigente y sin noticia bancaria.
- El panel de Ventas solo permite el siguiente estado real; un no-op no duplica
  bitácora ni correo. Un avance confirmado intenta el correo de etapa; si el
  correo falla, el pedido no retrocede y el operador puede reintentarlo.

### Tienda C5

- `Mis compras` real con filtros Todas / En proceso / Realizadas / No completadas.
- Tarjetas multiproducto, fecha real de compra, total, cantidades, imagen actual
  si el producto sigue publicado y placeholder si no.
- Seguimiento `Recibido → Preparando → En camino → Entregado` desde la misma
  fuente de verdad del panel interno.
- `Continuar pago` solo para intención vigente sin transacción.
- `Verificar estado` para confirmación bancaria/revisión.
- Aviso no bloqueante en el carrito y distintivo en Mi cuenta cuando hay compras
  en proceso.
- Retorno Wompi/deep-link a Mis compras, incluso después de volver a iniciar
  sesión, sin open redirect.
- Polling prudente cada 15 s mientras haya procesos, además de focus/pageshow.
- `Volver a comprar` abre la ficha actual y recalcula precio/disponibilidad.
- `Dar mi opinión` aparece únicamente si servidor confirma entregado, no anulado,
  producto elegible y sin opinión; queda no operativo por decisión de alcance.
- Compatibilidad C4 histórica y compra inmediata/invitada conservadas.

## 4. Decisiones cerradas

- El carrito solo prepara una compra; no conserva pagos.
- Se libera al confirmar server-side la intención y el snapshot, no al iniciar
  una llamada en el navegador.
- No existe botón manual de cancelar.
- Una intención sin transacción vence a los 30 minutos.
- Una transacción bancaria PENDING no se cancela al minuto 30.
- Antes de aprobación se llama «Compra en proceso»; el pedido nace al aprobar.
- Mis compras y los correos consumen el mismo estado `pedidos.estado`.
- La opinión por cuenta solo se habilita después de `entregado`.

## 5. Orden exacto para la próxima sesión

### Fase 0 · no tocar producción todavía

1. Medir con consultas de solo lectura: migración máxima real, flag, ciclos de
   intención, pendientes/revisiones y estado del ledger.
2. Reconciliar `20261105000000` con el historial de migraciones mediante el
   procedimiento aprobado. No insertar a ciegas en tablas internas.
3. Construir/revisar el paquete operativo C5 que aún falta en Git:
   `comercial-c5-preflight.sql`, `comercial-c5-postflight.sql`,
   `comercial-c5-estado.sql`, activación/desactivación y sondas Edge.
4. Resolver slug automático como migración forward separada, o decidir
   explícitamente si se despliega C5 primero y el slug inmediatamente después.

### Fase 1 · ventana C5

1. Desplegar primero Edge C5 compatibles: `crear-intencion-pago` y `estado-pago`.
2. Ejecutar sondas sin crear intención: CORS, método, body, sesión y referencia
   inexistente.
3. Apagar carrito y confirmar `carrito_habilitado=false`.
4. Aplicar una sola vez `20261106000000_comercial_c5_mis_compras.sql` por el
   método manual aprobado.
5. Ejecutar postflight completo: objetos, constraints, grants, helpers privados,
   compatibilidad ciclos 0/4, matriz y funciones.
6. Probar `mc_compras_listar()` con cuenta propia sin exponer PII.
7. Reactivar carrito únicamente con todos los gates correctos.

### Fase 2 · pruebas sin dinero

- agregar dos productos, crear intención y confirmar que el carrito queda libre;
- confirmar versión fuente/sucesora y una sola intención al reintentar;
- ver aviso y tarjeta En proceso en Mis compras;
- continuar pago vigente sin crear otra intención;
- dejar vencer sin transacción y confirmar No completada sin cambiar carrito;
- verificar que PENDING no se reabre ni vence por los 30 minutos;
- comprobar aislamiento con segunda cuenta;
- avanzar un pedido controlado desde Ventas y verificar reflejo en Mis compras;
- comprobar que `Dar mi opinión` solo aparece en entregado;
- ejecutar regresión de compra inmediata/invitada y de un ciclo C4 histórico.

### Fase 3 · cierre transaccional

Solo con autorización expresa: pago real C5 de monto bajo. Debe probar un solo
pedido, dueño correcto, snapshot, inventario/proveedor, asiento, correo
«Recibido», webhook repetido sin duplicados y seguimiento posterior. Después se
actualizan contexto, plano, runbook y este relevo con evidencia productiva.

## 6. Riesgos que no se deben olvidar

- La tienda C5 ya está en Pages, pero eso no demuestra backend C5 desplegado.
- Wompi sigue en `prod`; no abrir/autorizar pagos como diagnóstico.
- C5 no reserva inventario al crear intención. Si se agota antes de APPROVED, el
  pago pasa a revisión y requiere tratamiento/reembolso humano.
- La expiración C5 es perezosa: ocurre al consultar/listar/reabrir/recibir evento;
  no se instaló cron.
- El correo de cambio de estado se intenta desde el panel después del commit del
  pedido; si falla queda visible y reintentable, pero no existe una outbox/worker
  autónomo nuevo en C5.
- No exponer tablas base, PII, códigos de reseña, `service_role`, referencias de
  transacción, proveedor ni motivos internos.

## 7. Prompt de arranque para el próximo chat

> Retomamos MAGANDHI en **despliegue de Comercial C5**. Lee primero
> `docs/RELEVO-COMERCIAL-C5-2026-10-19.md` y
> `docs/PLANO-COMERCIAL-C5.md`. Código C5 ya fusionado: backend PR #287
> (`c8fd03c`, banco run `39354906924` SUCCESS) y tienda PR #113 (`4a0b439`,
> Pages built). **No confundas merge con despliegue:** producción Supabase sigue
> en C4/migración `20261105000000`, último flag documentado ON y Wompi prod; la
> migración C5 `20261106000000` no se ha aplicado y las Edge C5 no se han
> desplegado. Antes de tocar producción: medir estado/ledger, reconciliar C4,
> preparar preflight/postflight/estado C5 y recordar que falta slug automático.
> Después ejecutar Edge compatibles → carrito OFF → migración manual C5 →
> postflight → carrito ON → pruebas sin dinero. Pago real solo con mi
> autorización expresa. Al final decidir cierre estructural o transaccional de
> C4/C5 según la evidencia.
