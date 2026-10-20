# Plano operativo · Comercial C5 · Mis compras

> **Estado repo-side:** el paquete operativo C5 y la migración forward de slug automático `20261106000100_campanas_slug_automatico.sql` ya están construidos en Git. No se han ejecutado en producción; C5 no está cerrado y no existe medición productiva nueva. El orden autoritativo y los gates están en `supabase/operacion/COMERCIAL-C5-CIERRE.md`. No hay puente C5.

## Contrato

Comercial C5 mantiene `version_checkout=2` y crea las nuevas intenciones con `ciclo_carrito_version=5`. Los ciclos históricos 0 y 4 conservan firmas, grants y procesamiento anterior.

Al registrar una intención desde carrito, el servidor relee catálogo, disponibilidad y precios, congela `pagos_intencion` + `pagos_intencion_items`, elimina esas líneas del carrito y avanza su versión exactamente una vez dentro de la misma transacción. `carrito_version`, `carrito_version_sucesora`, `carrito_separado_en` y `carrito_separacion_detalle` dejan evidencia de la separación. Un retry con la versión fuente solo recupera la misma intención C5 si aún está `creada`, no tiene `transaccion_id`, no venció y su snapshot conserva ordinales, total y evidencia de separación coherentes. Una intención terminal, procesada, en revisión, con confirmación bancaria o vencida responde un error estable `PW_INTENCION_NO_REABRIBLE` que la Edge traduce a `INTENCION_NO_REABRIBLE`; nunca vuelve a firmarse ni se presenta como pedido aprobado. La Edge exige además `estado="creada"` en el snapshot C5 antes de firmar.

La Edge valida antes del registro un comprador completo: nombre, correo sintácticamente válido, teléfono colombiano de 10 dígitos, dirección, ciudad, departamento y `pais="CO"`. Un contrato incompleto responde HTTP 400 con `COMPRADOR_INVALIDO`; los valores aceptados se normalizan y son los únicos enviados a la RPC.

Desde la separación, la intención vive en **Mis compras** y C5 nunca bloquea el carrito. PENDING, rechazo, expiración, APPROVED y revisión no consumen ni versionan el carrito actual. Un `PENDING` recibido mientras la intención está creada y vigente puede fijar la primera `transaccion_id`. Un PENDING tardío sin transacción expira la intención y no la revive. Con una transacción ya fijada, únicamente ese mismo ID puede avanzar; otro ID deja la intención en revisión y conserva intacta la evidencia bancaria original. Un estado Wompi desconocido queda auditado pero no adquiere ni muta la intención.

`APPROVED` directo también es válido si la intención continúa creada y vigente: Wompi no garantiza que el webhook reciba primero un `PENDING`. En ese caso la aprobación verificada fija la primera transacción y continúa el flujo normal. Una aprobación posterior a expiración/rechazo o asociada a otra transacción queda en revisión sin crear pedido. Si una intención procesada recibe la misma transacción, es retry. Si recibe un APPROVED distinto, queda marcada explícitamente como `C5_POSIBLE_DOBLE_COBRO`, conserva el pedido y la transacción originales y no crea otro pedido.

La creación del pedido captura únicamente errores comerciales `raise_exception`; esos casos quedan en revisión durable. Los errores técnicos no se convierten en un resultado comercial: se propagan para hacer rollback y permitir retry del webhook. El handler restaura tanto `impulse.checkout_legacy` como `impulse.pago_servidor` en éxito y en la captura comercial.

Superficies:

- `mc_compras_listar()` (`authenticated`) deriva `auth.uid()`, cuenta activa y su `customer_id`. Devuelve hasta 100 tarjetas recientes: una por intención C5 y una por pedido histórico/manual/C4/C5 del cliente que no esté ya representado por una intención C5. Los pedidos anulados se clasifican `no_completada`. Las referencias históricas son alias públicos opacos compatibles con `^[A-Za-z0-9_-]{6,64}$`; no son IDs del pedido.
- Las tarjetas no exponen PII, UID, `customer_id`, `pedido_id`, IDs de Auth, transacciones, códigos internos, proveedor, notas ni motivos. Items y timeline se derivan solo dentro del pedido/cliente ya autorizado. Destino, slug e imagen actuales salen de `catalogo_publico`; si la campaña dejó de estar publicada/activa, no se proyectan. `puede_opinar` exige pedido entregado, no anulado, sin opinión previa y producto/campaña actualmente elegibles.
- `creado_iso` representa la creación de la intención o pedido. `comprado_iso` usa `procesada_en` para C5 procesada y `pedidos.creado` para historia. `expira_en` es obligatorio en tarjetas en proceso y puede ser `null` en compras históricas realizadas/no completadas; el consumidor público acepta ese contrato.
- `mc_reabrir_intencion_c5(referencia, auth_user_id)` (`service_role`) recibe de la Edge el UID validado. Solo devuelve el snapshot privado mínimo de una intención propia, creada, vigente, sin transacción y con integridad C5 completa.
- `pw_estado_checkout_publico(...)` retorna para C5 descriptor `tipo:"compra"` sin tocar carrito; C4/v0/v1 se despachan al cuerpo histórico.
- `pw_procesar_pago(...)` despacha ciclo 5 al cuerpo endurecido y todo lo histórico al cuerpo C4 conservado.
- `avanzar_estado_pedido(...)` repite el estado actual como no-op (`cambio:false`) sin bitácora y solo permite el siguiente estado real. La UI interna envía correo únicamente cuando `data.cambio === true`; ante no-op recarga y comunica que otro operador ya había actualizado.

“Dar mi opinión” es únicamente una señal owner-safe de elegibilidad de lectura. C5 no agrega una puerta autenticada para registrar opiniones.

## Despliegue seguro

**No aplicar esta migración con `supabase db push` hasta reconciliar primero el ledger de migraciones de C4.** C4 se aplicó manualmente en producción y puede no figurar en `supabase_migrations.schema_migrations`. Confirmar que `20261105000000` representa exactamente el SQL ya aplicado antes de registrar o ejecutar C5. No editar ni reaplicar migraciones históricas.

Orden seguro:

1. Desplegar primero las Edge compatibles C5 (`crear-intencion-pago` y `estado-pago`). Las rutas históricas siguen funcionando antes de la migración; la ruta de reapertura aún no debe exponerse en tienda.
2. En ventana controlada, apagar temporalmente el carrito y aplicar manualmente, una sola vez, `20261106000000_comercial_c5_mis_compras.sql`. Verificar estructura, ACL, ciclos históricos e invariantes antes de reactivar.
3. Desplegar después la tienda que consume `mc_compras_listar()`, `{intencion:{referencia}}`, el descriptor `tipo:"compra"`, `comprado_iso`, `expira_en` nullable en historia y las versiones fuente/sucesora.
4. Reactivar el carrito solo con postflight correcto. No realizar pagos reales durante la ventana sin autorización expresa.

La Edge de creación debe configurarse con las mismas llaves públicas y secretos de integridad Wompi vigentes. La reapertura vuelve a firmar en servidor y retorna a `https://magandhi.com/carrito/?ref=...&cuenta=compras`; nunca persiste ni registra secretos en logs.

## Criterios de verificación

- Una alta nueva queda en ciclo 5, vence en 30 minutos, tiene comprador y snapshot completos, separación durable y versión sucesora exactamente `fuente + 1`.
- Repetir el registro con la versión fuente solo devuelve una intención creada, vigente y sin transacción. Todo otro estado responde `PW_INTENCION_NO_REABRIBLE`/`CARRITO_YA_PROCESADO` y no se firma.
- El carrito queda libre inmediatamente; agregar una compra posterior funciona mientras la anterior está pendiente o en revisión. C4/ciclo 0 conservan bloqueo, consumo/liberación y procesamiento histórico.
- APPROVED directo y vigente puede fijar la primera transacción y crear exactamente un pedido. Si hubo PENDING, APPROVED debe usar ese mismo ID. PENDING tardío, estados desconocidos y transacciones distintas no reemplazan evidencia; una transacción distinta abre revisión.
- APPROVED con el mismo ID crea exactamente un pedido; retries no crean otro. APPROVED distinto sobre una procesada marca posible doble cobro sin otro pedido.
- Un error comercial de creación queda en revisión; un error técnico se propaga y revierte la transacción para que Wompi reintente.
- `mc_compras_listar()` aísla por dueño, deduplica pedidos representados por C5, limita a 100 tarjetas y no expone PII ni IDs internos de identidad.
- Reapertura ajena, vencida, cerrada, corrupta o con confirmación bancaria se rechaza indistinguiblemente; una propia vigente vuelve a producir firma válida sin crear intención.
- Seguimiento solo permite `recibido → preparando → en_camino → entregado`; repetir es no-op. Solo `cambio:true` dispara correo.

## Límites operativos conocidos

C5 separa el carrito, pero no reserva inventario al crear la intención. El stock se bloquea y descuenta al convertir un APPROVED en pedido; si se agota antes, el error comercial queda en revisión para tratamiento humano/reembolso. No hay devolución automática agregada por C5. La expiración sigue siendo perezosa (consulta, reapertura, retorno o webhook); esta migración no instala un job programado.