# Promocionar P5 · despliegue coordinado

**Estado:** construido en la rama `feat/promocionar-p5-lectura-comercial`, **NO desplegado y NO activo**. Este archivo es un procedimiento futuro; no acredita que SQL o Pages hayan sido publicados.

P5 solo añade lecturas, pero SQL y las tres superficies web forman un contrato único. No publicar la UI antes de la migración salvo que se acepte explícitamente su degradación “P5 no disponible”; no declarar cierre hasta medir ambos lados.

## Archivos

- Contrato: `../../docs/PLANO-PROMOCIONAR-P5.md`.
- Migración forward: `../migrations/20261110000000_promocionar_p5_lectura_comercial.sql`.
- Comprobaciones: `promocionar-p5-preflight.sql`, `promocionar-p5-postflight.sql`, `promocionar-p5-estado.sql`.
- UI: `marketing/campanas/promocionar-resultados.html`, `metricas/ventas.html` y `ventas/seguimiento-pedidos/index.html`.

## Orden futuro

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

## Casos obligatorios

- Base sin filas: las tres RPC devuelven JSON válido y arreglos vacíos.
- Rango invertido o mayor a 730 días: error `P5_PERIODO_INVALIDO`.
- P3 compactado: no se reparte el total sin fecha; tasa sobre clics no disponible.
- Analítica apagada/sin consentimiento: eventos consentidos vacíos y cobertura parcial, sin inferir personas.
- Analítica consentida: una sesión con marcador A, luego B y después checkout asigna el evento solo a B; la suma de informes por campaña reconcilia con el resumen y no hay fan-out.
- Intención creada no aprobada —incluida la sintética no identificable—: intención no aprobada, nunca pedido/ingreso.
- Venta exacta: misma FK en intención y pedido, intención `procesada`, Wompi `APPROVED`, pedido existente.
- Pedido anulado: trazabilidad separada y exclusión de vigentes/ingresos.
- Pedido con exacta y UTM: una sola categoría exacta.
- Legacy, aproximada y sin atribuir: categorías exclusivas.
- Lote duplicado, nulo o >500: rechazo; lote vacío: respuesta vacía válida.

## Reversa

P5 no tiene gate ni escritura. Ante un problema de UI, revertir la publicación de Pages sin tocar P3/P4, pagos o pedidos. Ante un problema SQL, no borrar funciones de forma improvisada ni modificar migraciones aplicadas: preparar una migración forward correctiva. Las superficies ya implementadas degradan ante RPC ausente para mantener Métricas M1 y Ventas operativos.

## Evidencia que no puede inferirse

Un merge, un archivo SQL en Git, un postflight local o una pantalla visible no prueban despliegue completo. Solo el SQL Editor productivo, Pages publicada, permisos medidos y recorridos con datos controlados permiten declarar P5 desplegado. Hasta entonces su estado permanece **construido, NO desplegado**.
