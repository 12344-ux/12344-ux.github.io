# Comercial C4 · cierre operativo

**Ejecución · 19-oct-2026:** las fases A, B y C están **ejecutadas** en producción, y la fase D se abrió: **el carrito quedó ENCENDIDO**. Valores observados que difieren de lo esperado abajo:

- preflight `v2_total=0` (no existía la intención C3), por lo que `c3_preservadas=0` y la sucesión C3 no aplica;
- regresión OFF sin registro casilla por casilla.

Pendientes: expiración 9D registrada, fase E (dinero) y el valor final del flag. Evidencia y decisiones abiertas en `docs/RELEVO-COMERCIAL-C4-2026-10-19.md`. No volver a ejecutar puente ni migración.

## Archivos y orden

| Orden | Archivo/acción | Modifica BD | Momento |
|---|---|---:|---|
| 1 | `comercial-c4-preflight.sql` | No | Antes de todo |
| 2 | `comercial-c4-puente-estado.sql` | Sí, solo función/ACL | Después de aprobar preflight |
| 3 | Desplegar Edge `estado-pago` C4 | No | Con el puente ya instalado |
| 4 | `../migrations/20261105000000_comercial_c4_cuenta_ciclo_carrito.sql` | Sí | Con el retorno compatible |
| 5 | `comercial-c4-postflight.sql` | No | Inmediatamente después de migrar |
| 6 | Desplegar Edge `crear-intencion-pago` C4 | No | Solo con postflight correcto |
| 7 | `comercial-c4-estado.sql` | No | Después de C4 y durante pruebas |
| 8 | `comercial-c4-activar.sql` | Sí, flag | Solo tras regresión OFF |
| 9 | `comercial-c4-desactivar.sql` | Sí, flag | Al cerrar ventana o ante duda |

El puente evita una incompatibilidad de despliegue: la Edge C4 necesita `pw_estado_checkout_publico`, pero C3 solo tenía `pw_estado_publico`. Se instala la puerta nueva sin retirar la antigua, se despliega la Edge nueva y la migración C4 reemplaza el puente atómicamente con su implementación autoritativa. Si la migración falla y revierte, la Edge nueva continúa funcionando sobre el puente C3.

Ejecutar cada SQL completo y en Runs separados de Supabase SQL Editor. No concatenar puente, migración, postflight ni activación. Los diagnósticos usan `READ ONLY` y terminan en `ROLLBACK`.

## Reglas no negociables

- No reaplicar C1, C2 o C3. C4 se aplica una sola vez y no es un rollback.
- No ejecutar `20261002000000_puesta_al_dia_seguridad_operativa.sql`: está superada según el runbook.
- Mantener `carrito_habilitado=false` durante puente, migración, postflight, despliegues y regresión OFF.
- No borrar, editar ni reetiquetar la intención estructural C3; al migrar debe quedar en `ciclo_carrito_version=0`.
- No ejecutar RPC mutantes como diagnóstico. La versión C4 de `pw_estado_checkout_publico` puede expirar/liberar/versionar.
- No cambiar Wompi globalmente a sandbox: comparte configuración con compra inmediata.
- Ante duda, ejecutar `comercial-c4-desactivar.sql`; solo considerar apagado cuando devuelva `apagado_confirmado=true`. Si hay timeout/contención, reintentar y no continuar hasta confirmarlo.
- Una revisión C4 solo se libera después de confirmar el reembolso y usar `reembolsado_liberar` con nota.
- Ninguna prueba con dinero se hace sin autorización expresa del dueño.

## Fase A · preflight y retorno compatible

### A1. Preflight — acción del dueño

1. Abrir Supabase → SQL Editor.
2. Copiar completo `comercial-c4-preflight.sql`.
3. Ejecutar una vez.
4. Compartir las cuatro salidas completas.

Fotografía esperada del corte documentado:

- Primera salida: cinco filas con `coincide=true`.
- Historia C3: `v2_total=1`, `v2_creadas_sin_pedido=1`, `snapshots_invalidos=0`, `v2_con_evento=0`, `v2_con_pedido=0`; booleanos `true`.
- Invariantes: cuatro booleanos `true` y `revisiones_pendientes=0`.
- Pagos: `singleton=true`, `id_correcto=true`, `entorno=prod`, `llave_activa_configurada=true`, `wompi_permanece_en_prod=true`.

Los conteos históricos son una fotografía, no una excusa para editar producción. Si difieren, detenerse e investigar actividad legítima posterior; las invariantes estructurales y el flag OFF sí son gates obligatorios.

### A2. Puente de estado — acción del dueño tras aprobar A1

1. Ejecutar completo `comercial-c4-puente-estado.sql`.
2. Confirmar sus cuatro booleanos en `true`.
3. No volver a ejecutar el preflight: desde este momento la nueva RPC existe deliberadamente.

El puente falla si C4 ya está instalada o si el carrito no está OFF. Solo lee estados; no expira ni modifica intenciones.

### A3. Desplegar primero `estado-pago` — acción del dueño

Desplegar `supabase/functions/estado-pago/index.ts` con **Verify JWT encendido**. Verificar:

- CORS desde `https://magandhi.com`;
- método distinto de POST rechazado;
- body inválido rechazado;
- una referencia con formato válido pero inexistente, por ejemplo `C4-SONDA-INEXISTENTE`, responde 404. Esta sonda sí atraviesa la RPC y no coincide con una intención real;
- no aparecen PII, monto, pedido, transacción, motivo ni entorno.

No usar todavía una referencia C4 real. Para comprobar la intención C3 histórica se requiere su sesión propietaria; no pegar ni registrar la referencia en documentos o logs.

## Fase B · migración y postflight

### B1. Migración — acción del dueño

1. Confirmar nuevamente flag OFF.
2. Copiar completo `../migrations/20261105000000_comercial_c4_cuenta_ciclo_carrito.sql`.
3. Ejecutarlo una sola vez.
4. Conservar salida y hora.

La migración tiene `BEGIN/COMMIT`, toma lock compartido de configuración y aborta con `C4_REQUIERE_CARRITO_DESHABILITADO` si no está OFF. Usa `CREATE OR REPLACE` para sustituir el puente sin interrumpir la Edge ya desplegada.

**Historial de Supabase:** este proyecto aplica migraciones manualmente en SQL Editor. Eso puede no registrar `20261105000000` en `supabase_migrations.schema_migrations`. Registrar la aplicación en el relevo y no usar posteriormente `supabase db push` hasta reconciliar el historial mediante el procedimiento aprobado para el proyecto. No insertar ni editar a mano tablas internas de historial durante este cierre.

### B2. Postflight — acción del dueño inmediatamente después

Ejecutar completo `comercial-c4-postflight.sql` y compartir las salidas. Gate esperado antes de tráfico C4:

- Resumen: ocho columnas `true`.
- Historia inmediata: `c3_preservadas=1`, `c4_creadas=0`; contradicciones en `0`.
- Sucesiones: `0`, `sucesiones_invalidas=0`.
- Once constraints C4 listados y validados: checks, PK/FK de sucesión, FK de campaña y vocabulario de eventos.
- Índices relevantes presentes, incluido el único v2 de C3 con sus columnas/predicado.
- RLS activo en ocho tablas, incluidas `pedidos` y `pedido_items`; `pw_sucesiones_c4` con cero policies.
- Siete verificaciones de privilegios de tabla en `true`.
- Las 30 funciones existen y muestran en `true`: `security_definer_ok`, `search_path_publico_ok`, `anon_ok`, `authenticated_ok` y `service_role_ok`.
- Inventario de 17 columnas: 12 añadidas a tablas existentes y 5 de `pw_sucesiones_c4`, con tipo/nullability/default esperados.

`ciclo_cero_modificado=0` es una comprobación inmediata de que migrar no alteró C3. Después, un webhook legítimo de esa intención histórica puede registrar liberación o consumo bajo la lógica C4; el informe de estado lo muestra como `ciclo_cero_con_transicion_c4` informativo y no lo trata automáticamente como corrupción.

Si falla una comprobación: mantener OFF. La Edge `estado-pago` se deja activa porque ya es compatible y preserva el retorno; no desplegar `crear-intencion-pago` ni activar el carrito hasta resolver.

## Fase C · Edge restante y regresión OFF

### C1. Desplegar `crear-intencion-pago`

Desplegar `supabase/functions/crear-intencion-pago/index.ts` desde el commit actual. No editar ni exponer `SUPABASE_SERVICE_ROLE_KEY`, secretos Wompi o Dropi. Comprobar CORS, método/body inválidos y que la ruta carrito sin sesión responda sesión requerida. No iniciar aún una intención.

### C2. Verificar Pages y caminos históricos

Pages ya reportó éxito; validar la superficie real con flag OFF:

- `montaguth.institute`: Ventas carga y las acciones históricas funcionan.
- `magandhi.com`: inicio/producto cargan sin errores.
- Login, logout y recuperación de sesión funcionan.
- Compra inmediata e invitada conservan su camino hasta antes de pagar.
- El carrito permanece oculto/deshabilitado con OFF.
- No abrir Wompi ni autorizar cobros.

## Fase D · ventana temporal sin dinero

### D1. Abrir ventana

Solo con A–C aprobadas, ejecutar `comercial-c4-activar.sql`. Debe devolver `carrito_habilitado=true` y `activado_confirmado=true`. El script comprueba artefactos críticos, estructura, RLS de sucesiones, contradicciones y pagos C4 bloqueantes; el postflight completo y los despliegues externos siguen siendo precondiciones humanas obligatorias.

Una intención C4 `creada` ya vencida no impide reactivar: no bloquea el carrito y se libera de forma perezosa en el siguiente acceso, que solo es posible con el flag encendido. Sí bloquean una intención vigente y una revisión abierta.

### D2. Recorridos manuales

Usar una cuenta propia confirmada y una segunda cuenta propia de prueba:

- [ ] Agregar una campaña y confirmar persistencia tras recargar.
- [ ] Consolidar la misma campaña y cambiar cantidades.
- [ ] Agregar una segunda campaña y verificar total/subtotales.
- [ ] Abrir dos pestañas y confirmar conflicto/versionado prudente.
- [ ] Confirmar que otra cuenta no ve ni modifica el carrito.
- [ ] Cerrar sesión y confirmar que no quedan controles habilitados.
- [ ] Iniciar una intención y abrir Wompi **sin pagar**.
- [ ] Confirmar `bloqueo_pago=pendiente`: no editar, retirar ni abrir segundo checkout.
- [ ] Probar retorno/recarga en otra pestaña y sin depender de `sessionStorage`.
- [ ] Esperar al menos 30 minutos y provocar recarga autoritativa.
- [ ] Confirmar expiración, líneas conservadas y un solo avance de versión.
- [ ] Ejecutar `comercial-c4-estado.sql`: sucesiones válidas, cero revisiones abiertas y contradicciones en cero.

No afirmar rechazo, PENDING del proveedor, aprobación tardía ni revisión si no se observaron realmente.

### D3. Cerrar ventana

Ejecutar siempre `comercial-c4-desactivar.sql`. Solo dar la ventana por cerrada cuando la consulta posterior al `COMMIT` muestre `carrito_habilitado=false` y `apagado_confirmado=true`. Si el script falla por lock/timeout, reintentar y escalar; no asumir que quedó OFF. Después ejecutar `comercial-c4-estado.sql` y archivar resultados.

## Fase E · dinero real, solo con autorización expresa

Preparar una compra de monto bajo y definir antes responsables de pedido, inventario/proveedor, asiento, correo y eventual reembolso. Evidencia mínima:

- [ ] `APPROVED` real y webhook recibido.
- [ ] Un solo pedido con `customer_id` derivado de la cuenta correcta.
- [ ] Snapshots de destinatario/campaña presentes y protegidos por Ventas/RLS.
- [ ] Consumo exacto del snapshot; extras/líneas posteriores preservados.
- [ ] Inventario propio o reserva/proveedor consistente.
- [ ] Asiento contable solicitado/registrado según contrato.
- [ ] Correo preparado/enviado una sola vez.
- [ ] Webhook repetido sin duplicar pedido, consumo, inventario, asiento o correo.
- [ ] Rechazo/expiración conserva líneas y libera/versiona una vez, si se mide.
- [ ] Aprobación tardía va a revisión y no crea segundo pedido, si se mide.
- [ ] Reembolso confirmado antes de `reembolsado_liberar`; nota registrada.

## Criterio de cierre

C4 solo se cierra cuando preflight, puente/retorno, migración, postflight, ambas Edge, regresión OFF, ventana ON y la evidencia realmente ejecutada estén documentados. Merge, Pages verde o intención abierta sin pagar no equivalen a cierre transaccional. Al cerrar se actualizan `docs/RELEVO-COMERCIAL-C4-2026-10-19.md`, `docs/PLANO-FASE-COMERCIAL.md`, `supabase/INSTRUCCIONES.md`, `CONTEXTO-MAGANDHI.md` y estado de tienda, y se decide explícitamente el flag final.
