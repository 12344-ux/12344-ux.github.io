# Promocionar P5 · cierre productivo y protocolo de referencia

**Estado:** P5 está desplegado y su cierre estructural/productivo fue aceptado: **despliegue productivo acreditado con evidencia limitada; protocolo completo no recorrido**. Implementación PR #308, merge `3205e1b0cfcd5fc98126ccf2f37aa3cb2bf914f1`; migración `20261110000000_promocionar_p5_lectura_comercial.sql` ejecutada una sola vez según confirmó el dueño; Pages producción run `39645791554` `success` sobre el merge.

P5 solo añade lecturas. SQL y las tres superficies web forman un contrato único, pero este cierre no acredita una transacción real ni convierte la intención P4 existente en venta.

## Archivos

- Contrato: `../../docs/PLANO-PROMOCIONAR-P5.md`.
- Relevo vigente: `../../docs/RELEVO-PROMOCIONAR-P5-CIERRE-ESTRUCTURAL-2026-10-21.md`.
- Migración forward ya aplicada: `../migrations/20261110000000_promocionar_p5_lectura_comercial.sql`.
- Comprobaciones conservadas: `promocionar-p5-preflight.sql`, `promocionar-p5-postflight.sql`, `promocionar-p5-estado.sql`.
- UI: `marketing/campanas/promocionar-resultados.html`, `metricas/ventas.html` y `ventas/seguimiento-pedidos/index.html`.

## Evidencia exacta del cierre productivo acreditado

1. PR #308 fusionado como `3205e1b0cfcd5fc98126ccf2f37aa3cb2bf914f1` el 21-oct-2026.
2. CI de rama run `39643360479` `success`: 88 migraciones, matriz 230/0 y suite final `Todo pasa.`
3. El dueño confirmó la ejecución única de la migración `20261110000000_promocionar_p5_lectura_comercial.sql`.
4. Pages producción run `39645791554` `success` sobre el merge.
5. El dueño recorrió la prueba integral final de Resultados, Métricas y Ventas y dijo «Todo en orden».
6. Diagnóstico final:

```text
instalado=true
P3: enlaces=1; detalle_desde=null; detalle_hasta=null; clics_detalle_filas=0; compactado=0
P4: intenciones_atribuidas=1; convertidas_approved=0; pedidos_con_fk=0; ventas_exactas_autoritativas=0; divergencias_fk=0; incidencias_pendientes=0
analítica consentida: activa=false; primer_evento=2026-10-08T18:34:59.188+00:00; ultimo_evento=2026-10-08T18:34:59.188+00:00
intención sintética identificable=false
```

No quedaron confirmados preflight ni postflight productivos separados. El diagnóstico y el recorrido integral son la evidencia productiva disponible; no deben presentarse como si hubieran cubierto cada paso o caso de referencia siguiente.

## Secuencia diseñada · referencia histórica

Esta era la secuencia prevista. Se conserva para operación y auditoría; sus pasos no marcados por la evidencia anterior **no se dan por ejecutados retrospectivamente**.

1. Confirmar que producción llega exactamente hasta `20261109000000` P4 y que no existe ningún objeto P5.
2. Ejecutar `promocionar-p5-preflight.sql` en SQL Editor. Todos los booleanos deben ser `true`; no continuar con una ausencia o drift.
3. Aplicar completa y una sola vez `20261110000000_promocionar_p5_lectura_comercial.sql`. Esta base se opera manualmente; nunca usar `supabase db push` ni reaplicar historia.
4. Ejecutar `promocionar-p5-postflight.sql`. Debe acreditar cuatro funciones, `SECURITY DEFINER`, `search_path` fijo, grants nominales, el índice de sesión y un corte agregado vacío ejecutado realmente; el lote nominal vacío se recorre después con sesión Ventas porque su guardia debe rechazar SQL Editor sin identidad.
5. Ejecutar `promocionar-p5-estado.sql`. Guardar el JSON como evidencia sin copiar PII ni resultados por pedido.
6. Con sesión Marketing, medir Resultados para una campaña sin enlaces, una con enlaces sin actividad y una con actividad; recorrer 7/30/90/365, carga, error/reintento, vacío total, vacío de periodo y parcial por P3 compactado/analítica.
7. Con sesión Métricas, comprobar que M1 carga con P5 disponible y, en una versión de preproducción sin RPC P5, que M1 sigue cargando mientras el bloque promocional degrada solo.
8. Con sesión Ventas, comprobar un lote mixto y las cuatro categorías. Simular RPC ausente y verificar pedidos operativos con “No disponible”. Confirmar una sola llamada batch, nunca una por pedido.
9. Comparar contra consultas controladas: intenciones, `procesada + APPROVED + pedido`, anulaciones, ingresos COP y precedencia exacta > legacy > aproximada > sin atribuir.
10. Publicar Pages en la misma ventana y repetir recorridos. Registrar fecha, revisión, resultados y limitaciones reales antes de cambiar el estado del plano.

De esa secuencia solo se afirma lo acreditado arriba: migración única, Pages sobre el merge, diagnóstico exacto y recorrido integral final de las tres superficies. No se afirma ejecución separada de preflight/postflight ni cada variante de los pasos 6–9.

## Casos obligatorios · referencia histórica

Los casos siguientes conservan el diseño de validación. **No equivalen a casos productivos recorridos en este cierre.** En particular, no se recorrieron o confirmaron las cuatro categorías con datos reales, una compra, un pago `APPROVED`, un pedido atribuido ni un ingreso.

- Base sin filas: las tres RPC devuelven JSON válido y arreglos vacíos.
- Rango invertido o mayor a 730 días: error `P5_PERIODO_INVALIDO`.
- P3 compactado: no se reparte el total sin fecha; tasa sobre clics no disponible.
- Captura nueva de analítica voluntaria desactivada: P5 conserva cualquier evento histórico ya consentido del periodo, pero no completa los intervalos sin captura; por eso las sesiones y los checkouts pueden ser parciales. Los pedidos y los ingresos se leen por una vía transaccional independiente. Solo un caso controlado sin histórico consentido devuelve eventos vacíos, sin inferir personas.
- Analítica consentida: una sesión con marcador A, luego B y después checkout asigna el evento solo a B; la suma de informes por campaña reconcilia con el resumen y no hay fan-out.
- Intención creada no aprobada —incluida la sintética no identificable—: intención no aprobada, nunca pedido/ingreso.
- Venta exacta: misma FK en intención y pedido, intención `procesada`, Wompi `APPROVED`, pedido existente.
- Pedido anulado: trazabilidad separada y exclusión de vigentes/ingresos.
- Pedido con exacta y UTM: una sola categoría exacta.
- Legacy, aproximada y sin atribuir: categorías exclusivas.
- Lote duplicado, nulo o >500: rechazo; lote vacío: respuesta vacía válida.

El estado real observado fue analítica consentida `activa=false` y P3 `compactado=0`; no corresponde afirmar que se recorrió el caso de P3 compactado. La lectura parcial debe explicar la analítica voluntaria inactiva sin inventar histórico sin fecha.

## Reversa

P5 no tiene gate ni escritura. Ante un problema de UI, revertir la publicación de Pages sin tocar P3/P4, pagos o pedidos. Ante un problema SQL, no borrar funciones de forma improvisada ni modificar migraciones aplicadas: preparar una migración forward correctiva. Las superficies implementadas degradan ante RPC ausente para mantener Métricas M1 y Ventas operativos.

## Límite de evidencia

El cierre no se infiere del merge aislado: se apoya únicamente en el run CI, la confirmación de migración única, el run de Pages, el recorrido integral final del dueño y el diagnóstico exacto registrados arriba. No ampliar esa evidencia a preflight o postflight productivos separados, categorías con datos reales o un flujo monetario. P5 queda **cerrado estructural/productivamente**, no monetaria ni end-to-end.
