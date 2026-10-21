# MAGANDHI · Plano Promocionar P5 · lectura comercial

**Estado:** construido en la rama `feat/promocionar-p5-lectura-comercial`, **NO desplegado**. Ninguna RPC P5, página o integración descrita aquí se considera disponible en producción hasta ejecutar el despliegue coordinado y acreditar sus postflight y recorridos.

**Base:** P0–P3 cerrados; P4 desplegado, activo y cerrado estructuralmente, todavía sin cierre transaccional por una compra real autorizada. P5 es una capa de solo lectura: no cambia enlaces, intenciones, pagos, pedidos, inventario ni contabilidad.

## 1. Resultado y límites

P5 reúne tres poblaciones distintas sin fingir que son equivalentes:

1. **Aproximada:** clics diarios P3, agregados y no únicos.
2. **Consentida:** sesiones y eventos de `tienda_eventos`, existentes solo para navegadores que aceptaron analítica.
3. **Transaccional:** intenciones, pagos aprobados convertidos y pedidos, con la atribución P4 como autoridad cuando existe.

Entrega:

- resultados de una `campana_producto` y periodo para Marketing;
- un resumen agregado para Métricas;
- procedencia de un lote de pedidos para Ventas en una sola llamada, sin N+1;
- UI de Resultados hermana del Editor Promocionar;
- degradación independiente en Métricas y Ventas si P5 aún no existe o falla.

P5 **no** publica, pauta, cambia campañas, repara P4, crea identificadores, expone PII ni calcula métricas basadas en impresiones.

## 2. Fuentes y autoridad

| Lectura | Fuente | Reloj y unidad | Autoridad / límite |
|---|---|---|---|
| Clics aproximados | `atribucion_clics_dia` + `atribucion_enlaces.total_aproximado_historico` | `fecha_colombia`, día `America/Bogota` | Navegaciones agregadas; no personas, sesiones ni únicos. El compacto histórico perdió fecha. |
| Sesiones/eventos consentidos | `tienda_eventos`: último marcador anterior de la misma sesión cuya `utm_campaign` coincide con cualquier `atribucion_enlaces.campaign`; la campaña solicitada se filtra después | `cuando AT TIME ZONE 'America/Bogota'` | Solo población con consentimiento. Cada evento se asigna globalmente como máximo a un enlace (last-touch de sesión), evitando fan-out si aparecen varias campañas y haciendo reconciliables informes individuales/resumen. UTM describe procedencia, no vuelve exacta una venta. |
| Intenciones | `pagos_intencion.atribucion_enlace_id` | `creado` en Colombia | Inicio persistido de checkout; `creada` no prueba pago. |
| Pago aprobado convertido | `pagos_intencion` | `procesada_en` en Colombia | Requiere simultáneamente `entorno='prod'`, `estado='procesada'`, `estado_wompi='APPROVED'` y `pedido_id` no nulo. |
| Pedido e ingreso exactos propios | `pedidos` + intención convertida del pedido + `atribucion_enlaces` | `pedidos.creado` en Colombia; COP entero | Requiere intención atribuida en `prod`, procesada, APPROVED y el mismo pedido con la misma FK P4. El pedido completo se atribuye al enlace; no se infiere que se compró el producto promovido. |
| Email legacy | `pedidos.utm_campaign` + `em_campanas` | `pedidos.creado` en Colombia | Coincidencia histórica, inferior a exacta propia. |
| Email aproximada | `em__atribucion_aproximada()` para resúmenes vigentes; clasificación set-based P5 equivalente para el lote de Ventas | ventana histórica de 7 días | Aproximación por último clic Email elegible; la variante P5 no filtra anulados para conservar trazabilidad, sin alterar el helper histórico ni sus consumidores. Inferior a legacy y exacta propia. |
| Sin atribuir | pedido restante | `pedidos.creado` en Colombia | Ausencia de evidencia promocional bajo la precedencia cerrada. |

Las lecturas agregan hechos en CTE separados antes de unirlos para impedir fan-out y doble conteo. `pedidos.total` y `pedido_items.subtotal` son pesos COP; `pagos_intencion.monto_centavos` no se presenta como ingreso.

## 3. Fórmulas y denominadores

Para un periodo inclusivo `[desde, hasta]` de máximo 730 días:

- `clics_aproximados = Σ atribucion_clics_dia.total` de enlaces y días del periodo.
- `sesiones_consentidas = count(distinct tienda_eventos.sesion)` después de asignar cada evento al último marcador UTM propio anterior dentro de su misma sesión.
- `eventos_consentidos = count(*)` del universo asignado sin fan-out, separados en llegada, producto visto y checkout iniciado.
- `intenciones = count(*)` con FK del enlace y `creado` dentro del periodo.
- `pagos_approved_convertidos = count(*)` con `entorno='prod'`, `estado='procesada'`, `estado_wompi='APPROVED'`, `pedido_id` no nulo y `procesada_en` dentro del periodo.
- `pedidos_exactos = count(distinct pedido.id)` no anulados cuya intención `prod` convertida y pedido comparten la FK exacta.
- `ingresos_exactos_cop = Σ pedido.total` de esos pedidos no anulados.
- `pedidos_exactos_anulados` e `ingresos_exactos_anulados_cop` se informan aparte y nunca se mezclan con vigentes.
- `conversion_pedido_sobre_clic = pedidos_exactos / clics_aproximados × 100`, solo si el detalle P3 cubre todo el periodo y el denominador es mayor que cero.
- `conversion_checkout_sobre_sesion = sesiones_con_checkout / sesiones_consentidas × 100`, solo sobre población consentida y con denominador mayor que cero.
- `conversion_pago_sobre_intencion = intenciones_del_cohorte_que_terminaron_procesada_y_APPROVED / intenciones_creadas_en_el_periodo × 100`, con denominador mayor que cero. El KPI de pagos procesados usa `procesada_en`; esta tasa de cohorte usa `creado` y lo declara expresamente.

Cada tasa devuelve `valor`, `numerador`, `denominador`, `denominador_etiqueta` y `disponible`. Una tasa no disponible es `null`, nunca cero inventado. No existen impresiones en P5.

## 4. Ventanas, frescura y P3 compactado

Toda frontera de día se calcula con `America/Bogota`; `desde` y `hasta` son inclusivos. El servidor rechaza nulos, periodos invertidos y ventanas superiores a 730 días.

P3 conserva detalle diario durante 13 meses y mueve días anteriores a `total_aproximado_historico`. Ese compacto es exacto como suma vitalicia por enlace, pero ya no tiene fecha. Por eso:

- el payload informa `detalle_p3_disponible_desde`, `detalle_p3_disponible_hasta`, `periodo_detalle_p3_completo`, `clics_compactados_sin_fecha` y `clics_vitalicios_aproximados`;
- el compacto **no** se reparte entre días ni se introduce en un periodo arbitrario;
- si el periodo empieza antes del primer detalle retenido y existe compacto, la serie y los clics del periodo se rotulan parciales, y la conversión cuyo denominador sean clics queda no disponible;
- un periodo sin filas pero posterior al corte es un vacío real del periodo, no un error de cobertura;
- `frescura` devuelve máximos observados por fuente y `generado_en`, sin identificadores personales. Un desfase temporal natural entre fuentes no se interpreta por sí solo como pérdida; `cobertura.razones` declara de forma machine-readable detalle compactado, analítica inactiva o ausencia de eventos consentidos atribuibles.

## 5. Anulaciones, P4 y precedencia

La distribución comercial de pedidos es exclusiva y respeta exactamente:

1. `exacta_propia`: pedido con FK propia y venta autoritativa completa (intención del pedido `procesada`, Wompi `APPROVED`, misma FK y pedido existente).
2. `legacy_email_utm`: sin exacta propia; UTM de pedido coincide con `em_campanas`.
3. `aproximada_email`: sin exacta ni legacy; para pedidos vigentes aparece en `em__atribucion_aproximada()` y el lote histórico de Ventas reproduce su candidato/ventana sin excluir anulados.
4. `sin_atribuir`.

La clasificación por lote usa una sola consulta set-based y devuelve una sola categoría por pedido solicitado. Nunca usa `pedidos.canal`, que describe la puerta operativa `manual/web`, no la procedencia promocional. Los anulados conservan categoría para trazabilidad, pero se marcan anulados y quedan fuera de pedidos/ingresos vigentes.

La venta P4 exacta autoritativa exige la cadena completa **intención atribuida en `prod` → procesada → APPROVED → pedido con la misma FK**. Una FK aislada, una intención `creada`, un pago `requiere_revision` o una incidencia pendiente no acreditan ingreso.

## 6. Intención sintética conocida

El cierre estructural P4 dejó una intención sintética atribuida y no aprobada. El esquema no contiene una marca que permita identificarla de forma fiable. P5 no inventa heurísticas por fecha, referencia, monto, entorno o actor y no la borra.

Esa fila permanece dentro del conteo honesto de **intenciones no aprobadas** cuando cae en el periodo. Por definición nunca entra en `pagos_approved_convertidos`, pedidos exactos ni ingresos. Las UIs explican esta limitación en calidad/cobertura.

## 7. Privacidad, consentimiento y permisos

- Las RPC son `SECURITY DEFINER` con `search_path = public, pg_temp`, revocación explícita a `PUBLIC`, `anon`, `authenticated` y `service_role`, seguida solo de grants nominales.
- `promocionar_p5_resultados` exige `tiene_acceso_marketing()` y se concede a `authenticated`.
- `promocionar_p5_resumen_metricas` exige `tiene_acceso_datos_metricas()` y se concede a `authenticated` y `service_role` para conservar el patrón compartido.
- `promocionar_p5_procedencia_pedidos` exige `tiene_acceso_ventas()`, acepta máximo 500 UUID únicos y se concede a `authenticated`.
- El helper agregador queda privado para roles API.
- No se conceden lecturas nuevas sobre tablas privadas ni se crean vistas expuestas.
- Marketing/Métricas reciben solo agregados y dimensiones comerciales de lista blanca: campaña, canal, pieza y estados; nunca nombres, correos, teléfonos, dirección, IP, `mg_vid`, visitante, sesión cruda, referencia de pago o UUID de pedido.
- Ventas ya es una superficie autorizada con PII del pedido. La RPC batch solo añade procedencia comercial del lote solicitado; no devuelve PII nueva ni amplía acceso.
- La analítica consentida permanece separada de P4: no se une visitante/sesión con cliente, intención o pedido.

## 8. Contratos de payload

### 8.1 Marketing · `promocionar_p5_resultados(p_campana_producto_id, p_desde, p_hasta)`

JSON `contrato='promocionar_p5_resultados_v1'` con:

- identidad mínima de campaña (`id`, `nombre`, `estado`);
- periodo/zona/moneda y `generado_en`;
- `totales`, tasas con denominadores explícitos y tres poblaciones;
- serie diaria completa con ceros para el rango;
- desglose por enlace/canal/pieza sin código público;
- cobertura/frescura y avisos parciales;
- fórmulas textuales versionadas.

### 8.2 Métricas · `promocionar_p5_resumen_metricas(p_desde, p_hasta)`

JSON `contrato='promocionar_p5_metricas_v1'` con clics aproximados, checkouts consentidos, pedidos/ingresos exactos propios, conversión sobre clics con denominador textual, y distribución exclusiva `exacta_propia / legacy_email_utm / aproximada_email / sin_atribuir`. No devuelve PII ni detalle por pedido.

### 8.3 Ventas · `promocionar_p5_procedencia_pedidos(p_pedido_ids uuid[])`

Arreglo JSON `contrato='promocionar_p5_procedencia_v1'` de máximo 500 elementos, uno por pedido existente del lote, con `pedido_id`, `tipo`, etiqueta, evidencia comercial permitida, `anulado` y explicación. Las etiquetas UI son: **Validada · enlace propio**, **Email legacy**, **Email aproximada**, **Sin atribuir**. La ausencia/falla de P5 se pinta como **No disponible**, nunca como “Sin atribuir”.

## 9. Estados UI

Promocionar Resultados diferencia visual y semánticamente:

- **carga:** skeletons con `aria-busy`, sin datos viejos;
- **error:** consulta fallida o payload inválido, detalle prudente y botón Reintentar;
- **vacío total:** campaña sin enlaces ni hechos históricos;
- **vacío de periodo:** existe historia/enlaces, pero no hechos en la ventana elegida;
- **parcial:** datos utilizables con cobertura incompleta (detalle P3 compactado, analítica apagada o ausencia de eventos consentidos atribuibles). Los máximos de frescura se muestran por fuente, pero un desfase natural entre clic, checkout y venta no se convierte por sí solo en una falla inventada;
- **completo:** datos válidos con cobertura declarada.

El embudo separa aproximada, consentida y transaccional; no dibuja continuidad causal falsa entre poblaciones. La serie SVG tiene nombre accesible y una tabla/resumen alternativo. Todo texto dinámico usa `textContent` o escape contextual; el payload se valida estrictamente. `AbortController` y un request-id impiden respuestas fuera de orden.

Métricas y Ventas degradan P5 de forma independiente: una RPC P5 ausente o fallida no invalida `mt_ventas` ni la carga/operación de pedidos.

## 10. Despliegue coordinado

Estado actual: **NO desplegado, NO activo**. P5 no necesita gate de escritura porque es lectura, pero exige publicación coordinada para evitar contratos incompletos:

1. revisar este plano y ejecutar preflight P5 de solo lectura;
2. aplicar una sola vez la migración forward `20261110000000_promocionar_p5_lectura_comercial.sql`;
3. ejecutar postflight y estado; confirmar firmas, `SECURITY DEFINER`, search path fijo, grants nominales, cero exposición de tablas/PII y seguridad con datos vacíos;
4. publicar Pages con Marketing, Métricas y Ventas en la misma ventana;
5. recorrer sesión/permisos, campañas con y sin datos, periodos 7/30/90/365, compactación parcial, RPC ausente simulada y batch de pedidos;
6. comparar agregados contra consultas controladas, incluidos anulados, cadena P4 exacta, legacy, aproximada y sin atribuir;
7. registrar evidencia. Fusionar código o aplicar solo SQL no acredita despliegue coordinado.

Reversa UI: retirar/revertir la publicación de páginas sin borrar datos. Reversa SQL: no hacer `DROP` improvisado; cualquier corrección va en migración forward. Las RPC son read-only y no cambian gates P3/P4.

## 11. Criterios de cierre

### Contrato y datos

- [ ] Migración P5 aplicada una sola vez después de `20261109000000`.
- [ ] Tres RPC nominales y helper privado compilan sobre el orden actual y con tablas vacías.
- [ ] Rangos inclusivos Colombia de 1–731 días (`hasta - desde <= 730`) validados.
- [ ] Fórmulas, denominadores, moneda COP, anulaciones, cobertura y frescura presentes en payload.
- [ ] Venta exacta exige intención `procesada`, Wompi `APPROVED`, `pedido_id` y FK coincidente en pedido.
- [ ] Precedencia exclusiva exacta > legacy > aproximada > sin atribuir acreditada sin doble conteo.
- [ ] Compacto P3 no se fecha ni se mezcla con series; periodos incompletos anulan tasas sobre clics.
- [ ] Intención sintética permanece no identificable y solo puede caer entre intenciones no aprobadas.

### Seguridad y privacidad

- [ ] Todas las funciones P5 son `SECURITY DEFINER`, search path fijo y grants nominales verificados.
- [ ] Helper sin acceso API; `anon` sin EXECUTE; ninguna tabla privada recibe grants/policies nuevas.
- [ ] Marketing/Métricas no exponen PII, referencias de pago, ids de pedido, visitante, sesión o `mg_vid`.
- [ ] Ventas recibe solo procedencia para el lote autorizado, máximo 500, en una llamada.
- [ ] Analítica consentida no se usa para identificar o unir una persona con una compra.

### UX/UI y operación

- [ ] Resultados conserva UUID, usa header Marketing y subnav Editor/Resultados, sin importar ni acoplarse al IIFE del editor.
- [ ] Selector 7/30/90/365, cabecera, KPIs definidos, poblaciones separadas, serie accesible, desglose y calidad funcionan responsive.
- [ ] Carga, error/reintento, vacío total, vacío de periodo, parcial y completo son distinguibles y accesibles.
- [ ] Payload inválido falla cerrado; request-id/abort impiden carreras; render dinámico es seguro.
- [ ] Métricas M1 y pedidos siguen operativos si P5 falla/no existe; Ventas dice “No disponible”.
- [ ] No se presenta ninguna tasa basada en impresiones.
- [ ] Cache-busting actualizado para todo CSS/JS cambiado.
- [ ] Preflight, postflight, estado, validaciones sintácticas y suite existente apropiada quedan verdes.
- [ ] Pages y SQL publicados coordinadamente, recorridos medidos y evidencia archivada antes de cambiar el estado de este plano.
