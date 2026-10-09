# RELEVO · Análisis del estado real del proyecto antes de F3

**Corte:** viernes 9 de octubre de 2026 · 7:11 a. m. hora Colombia (12:11 UTC)
**Para:** el siguiente chat de Kiro, que ya tendrá internet. Lo escribió el agente que hizo el análisis para que el siguiente siga desde aquí sin repetirlo.
**Dónde vive:** rama `test/banco-pruebas-ci`, [PR #247](https://github.com/12344-ux/12344-ux.github.io/pull/247). Si el PR ya se fusionó, todo está en `main`.

> Regla de esta revisión, pedida por el dueño: **no fiarse de la documentación**, sino del código, de GitHub y de pruebas ejecutadas. Varias frases de `CONTEXTO-MAGANDHI.md`, `ANDAMIOS.md` y de la cabecera de `supabase/INSTRUCCIONES.md` ya no son ciertas (ver §9).

---

## 0. Cómo retomar

1. Leer este archivo completo.
2. Si el dueño no los trae, pedirle dos cosas: el resultado del diagnóstico (§3) y sus respuestas a las preguntas de §6, que puede contestar por número.
3. Interpretar el diagnóstico con la tabla de §3. De ahí sale qué falta desplegar de F2.
4. **No construir F3 sin las respuestas contables de §6.** Como mínimo hacen falta P1 a P5.
5. Cada entrega lleva la evidencia del banco de pruebas (§8): local si hay internet, o GitHub Actions.

---

## 1. Qué pidió el dueño y qué se hizo

- **El pedido:** revisar todo el proyecto y ubicar exactamente dónde vamos. El dueño recordaba estar en la parte final: crear la F de los asientos contables automáticos («en compras y demás, para conectar todo») y probar con una compra real.
- **La limitación:** esta sesión no tenía internet; solo había acceso a GitHub por `gh api`. No se pudo consultar Supabase ni magandhi.com, ni instalar Postgres. Por eso las pruebas se corrieron en GitHub Actions.
- **Lo que se hizo:**
  1. Lectura del código ejecutable de los dos repos: tienda, panel, 64 migraciones y 8 Edge Functions.
  2. Revisión del estado de GitHub Pages de los dos sitios.
  3. Banco de pruebas completo en GitHub Actions, con un workflow nuevo: **324 pasan, 0 fallan**.
  4. Un diagnóstico de producción **de solo lectura** para el SQL Editor, probado con F2 aplicada y sin ella.
  5. El PR #247 con todo lo anterior y este relevo.
- **Lo que no se tocó:** nada de producción ni de las pantallas.

---

## 2. Estado real

| Pieza | Estado | Evidencia |
|---|---|---|
| Panel `montaguth.institute` | Publicado desde `main` `6d5f3f0` (8-oct, 4:44 p. m.) | API de GitHub Pages: `built`, sin errores |
| Tienda `magandhi.com` | Publicada desde `main` `782b4db` (8-oct, 4:44 p. m.) | Ídem. Ya envía el comprador y la procedencia a `crear-intencion-pago` |
| Código de F2 | Completo y coherente | Revisado parámetro por parámetro, más las pruebas en Actions (§8) |
| F2 desplegado en Supabase | **Sin evidencia.** Lo último que consta aplicado es la migración `20261017` (Métricas M2) | El agente nunca tiene acceso al dashboard, y ningún commit ni PR registra el despliegue de F2 |
| F3 | **No existe: cero código** | Ninguna función, trigger ni Edge Function crea asientos |
| Finanzas | Funciona, pero aislada: solo asientos manuales | Es lo único sin conectar. F3 es esa conexión |

La cadena de F2 en el código es:
tienda → `crear-intencion-pago` → `pw_registrar_intencion` → Wompi → `wompi-webhook` → `pw_procesar_pago` → `crear_pedido`.

**Conexiones que sí existen:**
- Inventario → Campañas (`product_id_ref`) → `catalogo_publico` (`agotado`) → tienda.
- Ventas (`crear_pedido`, con bloqueo de stock) → salida en Inventario.
- Pedido → correos por etapa (Resend) → código de reseña → Opiniones.
- Email marketing ↔ clientes, con atribución por `utm_campaign`.
- Métricas lee todo lo anterior.
- F2, una vez desplegado: pago aprobado → pedido web → stock.

### Qué falta para que F2 funcione en producción

El paso a paso está en `supabase/INSTRUCCIONES.md`, §0 y §F2.1 a §F2.6.

1. Aplicar `20261018000000_puesta_al_dia_sin_vista.sql`. **No** aplicar `20261002000000`: quedó superada y la reemplaza esta.
2. Aplicar `20261019000000_pagos_wompi_f2.sql`.
3. Crear el secret `WOMPI_EVENTS_SANDBOX`. Es el secreto de **eventos**, distinto del de integridad.
4. Desplegar `wompi-webhook` con **Verify JWT apagado**.
5. Redesplegar `crear-intencion-pago`, dejando Verify JWT como estaba.
6. Poner la URL de eventos de Wompi **sandbox**: `https://<proyecto>.supabase.co/functions/v1/wompi-webhook`.

⚠️ **El paso 2 va antes del 5.** La función nueva guarda la intención de pago antes de firmar. Si la tabla todavía no existe, **todas las compras fallan** con el mensaje «No pudimos iniciar tu pago».

---

## 3. Diagnóstico de producción

**Archivo:** `supabase/pruebas/diagnostico-produccion.sql`.
**Cómo se usa:** el dueño lo pega completo en Supabase → SQL Editor, le da Run y copia la tabla.

- Solo hace `SELECT`. Está probado dentro de una transacción `READ ONLY` en `correr-diagnostico.sh`.
- Si F2 no está aplicada, lo dice («la tabla no existe») en vez de fallar.

| # | Qué mide | Esperado | Si sale distinto |
|---|---|---|---|
| 1 | Zona horaria de la base | `UTC` / `Etc/UTC` | Confirma el hallazgo H4 (fecha de los pedidos web) |
| 2 | Hora en Colombia | informativo | — |
| 3 | `cm_publicar_campana` con candado | `true` | `false`: falta aplicar `20261018` |
| 4 | Puertas latentes de Finanzas | `0` | `5`: falta aplicar `20261018` |
| 5 | Borrado de imágenes en el bucket `campanas` | `true` | `false`: falta aplicar `20261018` |
| 6 | La vista `catalogo_publico` es la del 3-oct | `true` | `false`: **se aplicó la `20261002` (retroceso). Detenerse e investigar** |
| 7 | Tablas de F2 | `true` | `false`: falta aplicar `20261019` |
| 8 | Funciones de F2 | `4` | `0`: falta `20261019`. Otro número: aplicación parcial |
| 9 | `tiene_acceso_ventas` acepta el webhook | `true` | `false` con la fila 7 en `true` es incoherente: investigar |
| 10 | `pw_procesar_pago` cerrado a `anon` y `authenticated` | `true` | `no existe`: falta F2. `false`: **hueco de permisos**, corregir antes de seguir |
| 11 | Entorno de pagos | `sandbox` | `prod`: **detenerse.** Producción no se activa antes de F4 |
| 12 | Llave pública de sandbox | `cargada (pub_test_…)` | `VACÍA`: el checkout no abre (error 500). Hay que pegar la llave en `pagos_config` |
| 13 | Llave pública de producción | `vacía` | Puede estar cargada; no se usa hasta F4 |
| 14 | Intenciones de pago | `N en total`, con N > 0 | `0`: o `crear-intencion-pago` sigue siendo la versión F1, o nadie ha intentado comprar. Pedir un intento de checkout y volver a medir |
| 15 | Avisos de Wompi | N > 0 después de pagar en sandbox | `0` después de un pago: webhook sin desplegar, URL sin configurar, secreto equivocado o Verify JWT encendido. Mirar los Logs de la función |
| 16 | Pedidos por canal | `manual=…, web=…` | `web` > 0 solo después de una compra aprobada |
| 17 | Pagos aprobados sin pedido | `0` | > 0: hay aviso rojo en Ventas; resolverlo |
| 18 | Pedidos web con fecha distinta a la de Colombia | `0` | > 0: confirma H4 con datos reales |
| 19 | Productos comprables hoy | al menos uno | `NINGUNO`: no se puede hacer la compra de prueba. Registrar una entrada en Inventario de un producto publicado y ligado |
| 20 | Campañas publicadas → producto, stock y costo | ligado, stock > 0 y con costo | `SIN PRODUCTO LIGADO`: no se puede comprar. `stock 0`: agotado. `SIN COSTO`: F3 no podrá registrar el costo de venta |
| 21 | Cuentas que leería el asiento automático | `todas ok` | `NO IMPUTABLE` (lo esperado hoy): F3 las corrige (H1). Si ya salen `ok`, el dueño las cambió a mano y hay que respetarlo |
| 22 | Asientos registrados | informativo | Con 0 asientos, los libros están vacíos y probablemente hagan falta saldos de apertura (P5) |
| 23 | Inventario en libros (1435) frente a bodega (stock × costo) | iguales | Si libros es mucho menor que bodega, la mercancía no está en libros y hace falta asiento de apertura (P5). También cuenta los productos con stock y sin costo |
| 24 | Bancos (1110) en libros | informativo | — |

### Fuera del SQL, para que lo revise el dueño en los dashboards

- **Supabase → Edge Functions:**
  - existe `wompi-webhook`, con Verify JWT apagado;
  - `crear-intencion-pago` tiene un despliegue posterior al 8-oct a las 4:33 p. m. (hora en que se fusionó el PR #245).
- **Supabase → Secrets:** están `WOMPI_INTEGRITY_SANDBOX` y `WOMPI_EVENTS_SANDBOX`.
- **Wompi sandbox:** la URL de eventos apunta a `wompi-webhook`.

### Pruebas sin efectos que el chat con internet puede hacer solo

1. **Saber si `wompi-webhook` está desplegado.** Este POST no escribe nada:
   ```bash
   curl -s -i -X POST https://bxlzipwxyxdtffnuizbz.supabase.co/functions/v1/wompi-webhook \
        -H 'Content-Type: application/json' -d '{}'
   ```

   | Respuesta | Lectura |
   |---|---|
   | `404 NOT_FOUND` | La función no está desplegada |
   | `401 {"error":"Firma ausente."}` | Desplegada, con el secreto puesto y Verify JWT apagado. Es lo correcto |
   | `503 {"error":"Configuración incompleta."}` | Desplegada, pero falta `WOMPI_EVENTS_SANDBOX` |
   | `401` con un mensaje de JWT o de authorization | Verify JWT está encendido, así que Wompi no podrá entrar. Está mal |

2. **Ver qué se puede comprar.** Leer `catalogo_publico` con la publishable key de `supabase-config.js`; es lo mismo que hace la tienda.

**No llamar `crear-intencion-pago` para probar:** con F2 desplegado, cada llamada crea una intención de pago en la base real.

---

## 4. Hallazgos en el código

Las rutas son relativas a cada repo. Los números de línea corresponden a `main` del 8-oct.

### Graves

**H1 · La configuración contable haría fallar todos los asientos de F3.**
- `contabilidad_config` (`supabase/migrations/20250601000000_contabilidad_config.sql:52-78`) apunta a 1110, 4135, 5305, 6135 y 1435.
- Son cuentas de 4 dígitos, cargadas con `imputable=false` (`20250201000100_finanzas_carga_puc.sql:118-192`).
- `fz_validar_lineas` (`20250201000600_finanzas_funciones.sql:35`) rechaza cualquier cuenta no imputable.
- El comentario «VERIFICADO» de esa migración solo revisó que existieran y su naturaleza, no si eran imputables.
- **Arreglo, en la migración de F3:** cambiar cada cuenta a su subcuenta (111005, 413505, 530515, 613505 y 143505), pero solo si sigue con el valor viejo. Así no se pisa lo que el dueño haya cambiado a mano.

**H2 · Los detalles de entrega y el documento no llegan al pedido.**
- La tienda (`magandhi/producto/index.html`, envío del formulario hacia la línea 1856) arma `comprador` sin `detalles` ni documento. Esos dos datos solo viajan a Wompi (`irAWompi`, línea 1987; `address-line-2` en la 2049).
- El servidor (`crear-intencion-pago/index.ts:202`) tampoco tiene dónde guardarlos.
- Resultado: en Ventas el pedido aparece sin apartamento ni torre.
- **Arreglo simple, sin tocar el esquema:** en la tienda, enviar `direccion + ' · ' + detalles` como `comprador.direccion`. El servidor ya recorta a 200 caracteres.
- El documento, que haría falta para la factura, sí necesita columna nueva. Es la pregunta P10.

### Medios

**H3 · Al volver de Wompi no hay ninguna confirmación.**
- La URL de vuelta es `producto/?slug=…&ref=<referencia>` (`crear-intencion-pago/index.ts:456`).
- `cargarProducto` (`producto/index.html:1668`) solo lee `slug` e `id`, así que la página se ve igual que antes y el botón «Comprar ahora» está activo. La persona podría pagar dos veces.
- **Arreglo:** si hay `ref` en la URL, mostrar «Recibimos tu pago, lo estamos confirmando» y consultar el estado por referencia. Puede ser un modo `estado` en una Edge Function que devuelva solo `creada`, `procesada`, `rechazada` o `requiere_revision`, sin datos personales; la referencia no se puede adivinar.
- Además, restaurar el botón en el evento `pageshow`.

**H4 · Los pedidos web toman la fecha en UTC.**
- `pw_procesar_pago` (`20261019000000_pagos_wompi_f2.sql:357-370`) llama a `crear_pedido` sin `p_fecha_orden`.
- `crear_pedido` usa `current_date` por defecto (`20261008000100_ventas_bloqueo_stock.sql:46,60`), y la base está en UTC.
- Una compra después de las 7 p. m. en Colombia queda con la fecha del día siguiente. En contabilidad eso puede mover ventas de mes o de año.
- Los pedidos manuales no tienen el problema: mandan la fecha del navegador (`ventas/seguimiento-pedidos/registrar.html:528`).
- **Arreglo, en F3:** pasar `p_fecha_orden => (now() at time zone 'America/Bogota')::date` y usar esa misma fecha en el asiento.

### Menores

**H5 · Los mensajes de error de la tienda son siempre el genérico.**
- `mensajeDeError` (`producto/index.html:1971`) lee `pago.error` o `error.message`.
- Cuando la respuesta no es 2xx, supabase-js devuelve `data = null` y un `FunctionsHttpError`; el JSON real queda en `error.context`. Por eso el mensaje de «agotado» nunca aparece.
- **Arreglo:** usar el patrón de `magandhi/suscripcion/suscripcion.js:26-31`, que hace `await error.context.json()`.

**H6 · El correo de «recibido» de un pedido web no sale solo.**
- Se envía a mano desde Seguimiento (`ventas/seguimiento-pedidos/index.html:512,595`).
- `enviar-correo-pedido` usa la sesión del usuario, y `correo_pedido_preparar` exige `tiene_acceso_ventas`.
- Si se quiere automático, es la pregunta P11.

**H7 · En la lista de Seguimiento no se distingue un pedido web.** El canal solo aparece en el detalle (`index.html:495`).

**H8 · Detalles de documentación y atribución.**
- El comentario de `producto/index.html:1115` («esta etapa no guarda nada en la base») ya no es cierto.
- `utm_campaign` solo se conserva al cambiar de página si la persona aceptó la analítica: `mg_utm` lo escribe `iniciar()` (`analitica.js:118`). Si la compra ocurre en la misma página a la que llegó desde el correo, sí viaja.

**H9 · Una compra en sandbox no mueve plata, pero escribe en la base real.**
- Hay una sola base para todo, así que la compra de prueba crea un pedido real y baja el stock. Con F3 también dejará un asiento.
- Al terminar la prueba hay que **anular el pedido**: el stock vuelve y, con F3, se genera el contraasiento.

**H10 · PR abiertos que ya no sirven.**
- Panel: #227 modifica `ventas/correos/index.html`, que se eliminó en EM1. #216 son documentos del 2-oct ya superados.
- Tienda: #46, #21 y #15, de septiembre y comienzos de octubre.
- Proponer cerrarlos (P12).

---

## 5. Restricciones del código actual que F3 tiene que respetar

**Asientos.**
- `asientos` (`20250201000200`) tiene `id`, `fecha`, `descripcion`, `estado` (`activo` o `anulado`), `creado_por` (por defecto `auth.uid()`), `creado` y `actualizado`. **No tiene origen ni referencia:** hoy un asiento automático solo se reconocería por su descripción.
- `asiento_lineas` guarda `debe` y `haber` en bigint, en **pesos enteros**; cada línea es debe o haber, nunca las dos.

**Funciones de Finanzas.**
- `guardar_asiento`, `editar_asiento` y `anular_asiento` exigen `tiene_modulo('finanzas')`, que depende de `auth.uid()`. **No sirven desde el webhook (`service_role`).**
- F3 necesita una función interna, `security definer`, que reutilice `fz_validar_lineas`. Esa función valida: montos enteros, tope de 1e12 por línea, debe o haber exclusivo, cuenta existente **e imputable**, al menos 2 líneas y cuadre.
- `editar_asiento` borra y vuelve a crear las líneas. Ni editar ni anular usan `FOR UPDATE`, y hoy cualquier asiento activo se puede editar o anular.
- El trigger `registrar_bitacora_asiento` (`20250201000400:52`) anota «crear» al insertar y «anular» al anular. Con `service_role`, el actor queda nulo; se lee como «sistema».

**Informes.**
- `balance_comprobacion`, `estado_resultados` y `balance_general` solo cuentan asientos activos y cuentas imputables.
- `estado_resultados` clasifica por el primer dígito de la cuenta.
- No hay cierre anual.

**Permisos.**
- Toda función nueva nace cerrada (`20250606000200`), así que necesita `grant` explícito.
- Si el panel va a llamarla, hay que añadirla a `v_lista_blanca` en `supabase/pruebas/matriz-permisos.sql:91`.
- La matriz también exige que `service_role` pueda ejecutar todas las funciones.

**Costo.**
- `productos.costo_unitario` es bigint: `null` significa costo desconocido y `0` es un cero legítimo (`produccion/inventarios/agregar.html:216-221` y `ver.html:609-614`).
- **No hay costo por lote:** la pantalla de movimientos siempre manda `p_costo_unitario_mov: null` (`produccion/inventarios/ver.html:797`).

**Montos.** La intención de pago está en centavos (`monto_centavos`); el pedido y los asientos, en pesos. Para F3 se usan `pedidos.total` y `pedido_items`.

**Anulación de pedidos.**
- `anular_pedido` (`20250606000100:33`) no filtra por canal ni por estado: se puede anular hasta un pedido entregado.
- Devuelve el stock con entradas fechadas en la fecha del pedido.
- No toca la contabilidad, ni `pagos_intencion`, ni hace devolución en Wompi.

**Punto de enganche.**
- Es `pw_procesar_pago` (`20261019000000:253`), después del paso 7.
- Hay que volver a emitirla completa con `create or replace`, sin romper F2: `pagos-f2.sql` (40/40) y el ciclo completo (12/12) tienen que seguir pasando.

**Cuentas del PUC.**
- Subcuentas imputables ya cargadas: 110505, 111005, 112005, 130505, 135515, 135517, 135518, 143505, 220505, 236540, 240805, 413505, 413595, 417505, 530505, 530515, 613505, 620505, entre otras.
- **No existe ninguna 1380xx.** Hay que agregarla con un código oficial, por migración o con `agregar_cuenta_puc`.

**Wompi.** El evento `transaction.updated` **no trae la comisión**.

---

## 6. Preguntas para el dueño

Van numeradas para que conteste por número. La recomendación es del agente; lo de impuestos lo confirma su contador.

| # | Pregunta | Recomendación |
|---|---|---|
| P1 | ¿Dónde entra la plata de Wompi? Wompi consigna días después y ya descontada la comisión | Una cuenta puente «Wompi por liquidar» bajo 1380 Deudores varios (proponer 138095 «Otros», que hay que agregar). Se salda cuando llega la consignación. La opción simple es directo a 111005 Bancos |
| P2 | ¿MAGANDHI es responsable de IVA? Si lo es, ¿el precio web lo incluye y con qué tarifa? | No suponer nada. Si no es responsable, el ingreso va completo a 413505 |
| P3 | Comisión de Wompi | No inventarla: se registra con la liquidación, en un asiento manual o en una fase posterior |
| P4 | Costo de venta | El `costo_unitario` del producto al momento de la venta. Si no tiene costo, se registra la venta con el aviso «falta el costo», sin inventar un número |
| P5 | Inventario inicial: ¿la mercancía que ya hay está en libros? | Si no lo está (fila 23), un asiento de apertura. La contrapartida depende de cómo se compró: aporte del dueño, banco o proveedor. Lo confirma el contador |
| P6 | ¿Qué cubre F3? | **(a)** Venta web aprobada → asiento, y pedido anulado → contraasiento. Es lo que impide pasar a F4. **(b)** Compras de mercancía: una entrada en Inventario genera su asiento; «Registrar entrada» tendría que pedir el costo del lote y cómo se pagó. **(c)** Ventas manuales: pedir la forma de pago al registrar el pedido. Recomendación: (a) ahora y (b) + (c) justo después, salvo que el dueño quiera todo junto |
| P7 | ¿Se protegen los asientos automáticos? | Sí: no se editan ni se anulan desde Finanzas; se corrigen anulando el pedido. En el Diario llevan la marca «Automático · Venta web» y su referencia |
| P8 | ¿Con qué cuentas se hace el contraasiento? | Las mismas del asiento, invertidas. Otra opción es 417505 Devoluciones en ventas si el producto ya se había entregado |
| P9 | ¿Se arreglan H2, H3 y H5 en la tienda antes de la compra de prueba? | Sí. Son cambios chicos en `magandhi` |
| P10 | ¿Se guarda el documento del comprador para la factura? | Decisión del dueño. Requiere columna nueva |
| P11 | ¿El correo de «recibido» de un pedido web sale solo? | Puede seguir manual hasta F4 |
| P12 | ¿Se cierran los PR obsoletos (H10)? | Sí |
| P13 | ¿Se fusiona el PR #247 (banco en Actions, diagnóstico y este relevo)? | Sí. No toca producción: el workflow solo corre en ramas que no son `main` |

---

## 7. Diseño propuesto de F3 (borrador, se ajusta con las respuestas de §6)

**Migración:** `supabase/migrations/20261020000000_finanzas_asiento_automatico_f3.sql`, forward e idempotente.

1. **Origen en los asientos.**
   - Columnas `asientos.origen` (`manual` por defecto, `venta_web` o `reverso_venta_web`) y `asientos.origen_ref` (el `pedido_id`).
   - Índice único parcial sobre (`origen`, `origen_ref`) cuando el origen no es manual. Así se garantiza un solo asiento por pedido.
2. **Configuración contable.**
   - Pasar `contabilidad_config` a subcuentas imputables (H1), solo donde siga el valor viejo.
   - Columnas nuevas según las respuestas: cuenta puente, cuenta de IVA, tarifa de IVA (0 si no aplica) y cuenta de devolución si se elige.
   - Insertar en el PUC la subcuenta puente si se elige P1.
3. **`fz__asiento_venta_web(p_pedido_id)`**, interna y `security definer`.
   - Arma las líneas desde el pedido, sus ítems, `productos.costo_unitario` y la configuración.
   - Las valida con `fz_validar_lineas` e inserta el asiento con su origen.
   - Es idempotente: si el asiento ya existe, devuelve el mismo.
4. **`pw_procesar_pago`**, emitida otra vez completa.
   - Pasa `p_fecha_orden` en hora de Colombia (H4).
   - Después de crear el pedido, llama al constructor del asiento dentro de un bloque `begin … exception`.
   - Si el asiento falla, **el pedido se queda**: la plata recibida tiene que verse. En ese caso se marca «contabilidad pendiente» con el motivo, en una columna nueva de `pagos_intencion` o del pedido.
5. **`anular_pedido`**, emitida otra vez. Si el pedido tiene asiento de venta web y todavía no tiene reverso, crea el contraasiento con la fecha de hoy en Colombia. El asiento original no se toca.
6. **`editar_asiento` y `anular_asiento`** rechazan los asientos con origen distinto de `manual`, con el mensaje «Este asiento es automático: se corrige anulando el pedido».
7. **Panel de Finanzas.**
   - En el Diario, marca de «Automático» con la referencia del pedido, y sin los botones de editar y anular.
   - Aviso de «ventas sin asiento» con un botón «Generar asiento». Ese botón llama a una RPC con la guardia `tiene_modulo('finanzas')` y entra en la lista blanca de la matriz.
8. **Pruebas.**
   - `supabase/pruebas/local/f3-asiento-automatico.sql`: cuadre, idempotencia ante el reintento de Wompi, contraasiento, protección, fechas en el cambio de mes, costo faltante y permisos.
   - Al ciclo completo, `probar-ciclo-f2.ts`, se le agrega la comprobación del asiento.
   - Los informes deben cuadrar al peso usando `balance_comprobacion`, `estado_resultados` y `balance_general`.
9. **Runbook:** nueva sección «F3» al final de `supabase/INSTRUCCIONES.md`. Ojo: ya existe un §F3 con otro tema, el acceso a Finanzas; conviene titular la nueva «Pagos F3».

### Ejemplo de asiento

Venta web de $45.000 con costo de $25.000, sin IVA y con cuenta puente:

| Cuenta | Debe | Haber |
|---|---:|---:|
| 138095 Wompi por liquidar | 45.000 | |
| 413505 Venta de mercancías | | 45.000 |
| 613505 Costo de venta | 25.000 | |
| 143505 Mercancías | | 25.000 |

- **Con IVA incluido a la tarifa t:** base = `round(total / (1 + t))` e IVA = total − base, en 240805. Así siempre cuadra.
- **Cuando Wompi liquida** (asiento manual, por ahora): Débito 111005 por el neto, Débito 530515 por la comisión (más IVA descontable o retenciones si aplican) y Crédito 138095 por el bruto.

---

## 8. Cómo se prueba

**GitHub Actions** (`.github/workflows/banco-pruebas.yml`).
- Corre en cada push a una rama que no sea `main` y toque `supabase/**`, y también a mano.
- Instala PostgreSQL 15 y Deno, y reproduce las rutas `/projects/sandbox/...`. Así los scripts de `supabase/pruebas/local/herramientas/` se usan tal cual.
- Para leer el resultado:
  ```bash
  gh api "repos/12344-ux/12344-ux.github.io/actions/runs?branch=<rama>&per_page=1" --jq '.workflow_runs[0].id'
  gh api repos/12344-ux/12344-ux.github.io/actions/runs/<id>/jobs --jq '.jobs[0].id'
  gh api repos/12344-ux/12344-ux.github.io/actions/jobs/<job>/logs > /projects/sandbox/ci-logs/run.log
  ```
- En este sandbox `gh run list` falla porque `GH_HOST` no coincide con el remoto; hay que usar `gh api`.
- `/tmp` se borra entre llamadas a la herramienta: guardar los logs en `/projects/sandbox/ci-logs/`, fuera de los repos.
- Para F3: agregar el SQL nuevo a la lista de `pg.sh` del workflow y actualizar la matriz.

**Banco local, si el chat tiene internet:** primero `bash supabase/pruebas/local/herramientas/preparar.sh` y después los `correr-*.sh`. Cada script va en una sola invocación, porque los procesos en segundo plano no sobreviven entre llamadas.

**Resultados del 9-oct sobre `main`** (corridas `37925825400`, `37926533653` y `37926696024`):

| Prueba | Resultado |
|---|---|
| 64 migraciones en orden + matriz de permisos | 170/170 TODO PASA |
| F2 · capa de datos (`pagos-f2.sql`) | 40/40 |
| F2 · `wompi-webhook` con checksums reales | 21/21 |
| F2 · intención persistida | 19/19 |
| F2 · ciclo completo tienda → firma → webhook → pedido | 12/12 |
| Puesta al día forward sobre una base que reproduce producción | 23/23 |
| Métricas M1 / M2 | 40/40 · 26/26 |
| EM5 / EM5.1 / EM6 | 61/61 · 32/32 · 44/44 |
| Diagnóstico con y sin F2, en solo lectura | 4/4 |
| **Total** | **324 pasan · 0 fallan** |

No se volvieron a correr las pruebas de pantallas (Playwright); el último registro de esas es el del PR #246.

---

## 9. Lo que la documentación dice y ya no es cierto

Corregirlo **solo cuando el diagnóstico confirme el estado real**; documentar solo lo medido.

- `CONTEXTO-MAGANDHI.md` §5 dice «F2 — siguiente tramo, todavía no existe». Hoy el código de F2 existe y está probado; falta desplegarlo.
- `ANDAMIOS.md` marca «Wompi F2 ⏭️ Siguiente». Lo correcto sería «construido, pendiente de desplegar».
- La cabecera de `supabase/INSTRUCCIONES.md` dice «la siguiente acción es aplicar 20261018 y después construir Wompi F2». F2 ya está construido.
- `docs/PLANO-PAGOS.md` es el más exacto: «F2 construido y probado (pendiente de aplicar/desplegar)».

---

## 10. Plan en orden

1. El dueño corre el diagnóstico y revisa los dashboards (§3). El agente lo interpreta.
2. Terminar de desplegar F2 en el orden de §2.
3. **Compra de prueba de F2 en sandbox**, con las tarjetas de prueba oficiales de Wompi (verificar en docs.wompi.co). Debe quedar:
   - el pedido en Seguimiento con canal web y el stock con una unidad menos;
   - la intención en `procesada` y el aviso en `procesado`, sin duplicados;
   - un pago rechazado sin pedido.

   Al final, **anular el pedido de prueba**.
4. **Arreglos de la tienda (P9):** H2, H3 y H5 en `magandhi`, en rama y PR propios. Se pueden hacer en paralelo con F3.
5. **F3** según las respuestas de §6, con evidencia en Actions. El dueño la aplica.
6. Repetir la compra de prueba y verificar el asiento al peso en Diario, Mayor, Balance de comprobación, Estado de resultados y Balance general. Después anular el pedido: el contraasiento debe dejar el resultado neto en 0.
7. **F4:** compra real con un monto pequeño y conciliación completa. Solo después se cambia `pagos_config.entorno`.
8. **D3** (permisos más granulares) antes del primer usuario que no sea admin.

---

## 11. Reglas del proyecto que siguen vigentes

- Todo en español.
- **Rama nueva y PR nuevo por cada cambio; nunca push directo a `main`.** Antes de reutilizar una rama, verificar si su PR ya se fusionó.
- Las migraciones aplicadas no se tocan; toda corrección va en una migración forward nueva.
- SQL en el repo no significa SQL aplicado, ni una Edge Function en el repo significa desplegada. El dueño aplica y despliega a mano.
- «Success» no es evidencia: hacen falta números y comprobaciones.
- Ningún secreto en el repositorio, en tablas, en el navegador ni en los registros. La publishable key es pública por diseño.
- Impulse no inventa datos: si un dato no existe, se muestra un aviso, no una estimación.
- No hacer gold-plating: construir el siguiente tramo que desbloquea la operación real.
- Imágenes de máximo 2000 px por lado.

## 12. Ramas y PR al corte

| Repo | Rama / PR | Estado |
|---|---|---|
| Panel | `test/banco-pruebas-ci` · [#247](https://github.com/12344-ux/12344-ux.github.io/pull/247) | Abierto. Trae el workflow, el diagnóstico, `correr-diagnostico.sh`, el LEEME y este relevo |
| Panel | #227, #216 | Abiertos y obsoletos (H10) |
| Tienda | #46, #21, #15 | Abiertos y viejos (H10) |
| Panel y tienda | `main` | `6d5f3f0` / `782b4db`, iguales a lo publicado en GitHub Pages |
