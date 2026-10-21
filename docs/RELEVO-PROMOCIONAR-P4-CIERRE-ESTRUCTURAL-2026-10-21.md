# Relevo de sesión · Promocionar P4 · cierre estructural · 21 de octubre de 2026

> **Aviso de supersesión:** este relevo conserva la historia y los límites del cierre P4. El relevo vigente de Promocionar es `RELEVO-PROMOCIONAR-P5-CIERRE-ESTRUCTURAL-2026-10-21.md`; P5 no convirtió la prueba sin dinero de P4 en pedido o ingreso.

**Estado inequívoco:** P4 está fusionado, desplegado, activo y medido **sin dinero** en producción. Queda **cerrado estructuralmente**, no cerrado transaccionalmente: la prueba positiva congeló una FK en una intención y llegó a Wompi, pero no hubo pago APPROVED ni pedido. **P5 es el siguiente tramo.** Una futura compra real autorizada puede cerrar conjuntamente la copia intención → pedido y el pendiente transaccional de Comercial C5.

Leer después `PLANO-PROMOCIONAR-P4.md`, `PLANO-PROMOCIONAR-P0.md` y `../supabase/operacion/PROMOCIONAR-P4-DESPLIEGUE.md`. No reabrir P3/P4 salvo regresión medida.

## 1. Código fusionado

| Entrega | PR/merge |
|---|---|
| SQL, Edge, gate, intención/pedido y operación P4 | back-office #306 · `75b14b4db573d1e847bf604f7a0c1bc31930ed6c` |
| Visita por pestaña y checkout de tienda | tienda #118 · `1b22d24ff286c25aff29fee09c61949a37b1e591` |

Los dos PR quedaron sin conflictos y con CI verde. Backend run `39616029289` terminó `completed/success`: compiló 87 migraciones y pasó la matriz/bancos vigentes. Tienda tuvo comprobaciones estáticas verdes y Pages publicó exactamente el merge #118. Pages del back-office también publicó exactamente el merge #306.

## 2. Despliegue acreditado

- Migración `20261109000000_promocionar_p4_atribucion.sql` aplicada una sola vez.
- Edge `enlace-promocional` redesplegada conservando Verify JWT OFF y secretos P3.
- Edge `crear-intencion-pago` redesplegada sin cambiar secretos ni contrato público.
- No hubo cambio ni redespliegue necesario de Cloudflare Worker o `wompi-webhook`.
- Tienda publicada desde merge `1b22d24`.
- Gate P4 activo desde `2026-10-21T15:21:59.626776Z` con:
  - `atribucion_habilitada=true`;
  - `validacion_publica_verificada=true`;
  - `checkout_verificado=true`;
  - razón `activacion_controlada_p4`;
  - bitácora de configuración: 2 filas.
- `politica_publicada=false` y `politica_version=null` permanecen informativas y no bloquearon P4. No presentar esto como conclusión jurídica.

No inventar version IDs de Edge: este corte acredita código fusionado, despliegue ejecutado por el dueño y comportamiento productivo medido.

## 3. Prueba integral final sin dinero

Se usó el enlace producto controlado activo sin registrar su código en este relevo.

1. `GET /validar/<codigo-activo>` respondió `204`, cuerpo vacío, `no-store`, CORS exacto para `https://magandhi.com`, métodos `GET, OPTIONS` y sin credenciales/cookies.
2. `HEAD` al enlace corto, incluyendo query hostil `url`/`next`, respondió `302` sin contar navegación y produjo exclusivamente el destino MAGANDHI de la ficha oficial con UTM server-side y `#mg_promo=<codigo>`; la query hostil no eligió destino.
3. Un navegador real cargó la ficha publicada. El helper P4 guardó exactamente `{codigo, recibido_en, ultima_actividad}` en `sessionStorage`, separado de `mg_vid`, y retiró fragmento/query de la URL visible hasta dejar la ruta canónica.
4. Se completó el formulario con datos sintéticos de prueba, se inició compra inmediata y `crear-intencion-pago` respondió `200`.
5. El navegador llegó a `https://checkout.wompi.co/method`. Allí se detuvo la prueba: no se eligió medio, no se pagó y no hubo webhook APPROVED.
6. Diagnóstico SQL posterior:

```json
{
  "atribucion_habilitada": true,
  "validacion_publica_verificada": true,
  "checkout_verificado": true,
  "intenciones_atribuidas": 1,
  "pedidos_atribuidos": 0,
  "divergencias": 0,
  "incidencias_pendientes": 0,
  "incidencias_resueltas": 0,
  "bitacora_config": 2
}
```

La única intención atribuida es sintética y no produjo pedido/ingreso. `pedidos_atribuidos=0` es el resultado correcto de una prueba sin dinero, no una falla.

## 4. Qué quedó cerrado

- Transporte cross-domain mediante fragmento reservado añadido solo por el resolver.
- Validación pública nominal 204/404/503 con CORS cerrado y sin conteo.
- Visita por pestaña de 30 minutos, último enlace válido, limpieza de URL y separación de analítica.
- Un resultado incierto elimina atribución sin bloquear compra; un 404 autoritativo no reemplaza la visita válida anterior.
- El navegador envía solo `atribucion_codigo`; nunca una FK.
- La base deriva y congela `pagos_intencion.atribucion_enlace_id` al insertar.
- Compra inmediata y carrito conservan firmas históricas y fallback compatible.
- Reapertura/retry no cambia la FK congelada.
- El wrapper del webhook conserva su firma; una falla P4 no revierte el pago y queda en incidencia privada reparable de forma idempotente.
- Precedencia interna exclusiva: `exacta_propia` → `legacy_email_utm` → `aproximada_email` → `sin_atribuir`.
- P3 no adquirió una segunda RPC en el redirect: `captura_p4` viaja en la resolución ya existente.

## 5. Límite honesto

No se acredita todavía:

- pedido con `atribucion_enlace_id` copiada desde intención;
- webhook APPROVED y repetido con la misma FK;
- pedido único, inventario/proveedor, asiento y correo dentro de esta prueba;
- carrito multiproducto atribuido en una transacción real;
- ingresos o conversión de P5.

Eso requiere una compra real expresamente autorizada. Hasta entonces P4 es **cierre estructural productivo**, no cierre monetario/end-to-end. No borrar ni reclasificar la intención sintética; simplemente no tratarla como venta.

## 6. Operación

- Estado: `../supabase/operacion/promocionar-p4-estado.sql`.
- Reversa: `../supabase/operacion/promocionar-p4-desactivar.sql`; apaga nuevas atribuciones sin tocar P3, pagos ni historia.
- Reparación privada: `../supabase/operacion/promocionar-p4-reparar.sql`; solo permite `NULL → FK` desde la intención y nunca sobrescribe otra atribución.
- Toda corrección SQL futura es una migración forward. No editar ni reaplicar `20261109000000`.

## 7. Continuidad

**Siguiente tramo: P5 · lectura comercial.** Debe construir paneles y lecturas para clics aproximados, sesiones consentidas, checkout, pedidos, ingresos y conversión con denominadores explícitos, manteniendo separadas las cuatro categorías de atribución. No llamar CTR a clics sin impresiones.

Al iniciar la próxima sesión:

1. leer este relevo y `PLANO-PROMOCIONAR-P4.md`;
2. tratar P3 como cerrado FINAL y P4 como cerrado estructural/productivo;
3. no volver a desplegar SQL/Edge/Pages ya acreditados salvo regresión;
4. diseñar P5 antes de implementar, usando la intención sintética solo como evidencia técnica, nunca como venta;
5. mantener dinero bajo autorización expresa.

## 8. Cadencia acordada con el dueño

Para despliegues futuros: desplegar en una sola secuencia todos los componentes necesarios, comunicar inmediatamente cualquier error real y concentrar la validación en una prueba integral grande al final. Evitar rondas repetitivas de “para ver” salvo que un fallo obligue a diagnosticar.
