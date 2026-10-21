---
inclusion: always
---

# MAGANDHI · arranque de sesión

Antes de proponer o tocar nada en una sesión nueva:

1. Leer `docs/RELEVO-PROMOCIONAR-P5-CIERRE-ESTRUCTURAL-2026-10-21.md`: conserva el cierre productivo de lectura P5 y el límite sin dinero. Después leer `docs/PLANO-PROMOCIONAR-P5.md`. Para el contrato de captura y la historia transaccional, consultar `docs/PLANO-PROMOCIONAR-P4.md` y su relevo histórico. P3 permanece cerrado FINAL; no hay P6 definido.
2. Leer `CONTEXTO-MAGANDHI.md` §9 y `docs/PLANO-FASE-COMERCIAL.md`.
3. Para estado de carrito, Wompi o producción, consultar
   `docs/RELEVO-COMERCIAL-C5-CIERRE-2026-10-20.md` y
   `docs/PLANO-COMERCIAL-C5.md`; los relevos C1–C5 anteriores son memoria
   histórica.
4. Si la tarea toca identidad/apertura, leer `docs/CUENTAS-CLIENTE.md` y
   `docs/RELEVO-CUENTAS-C2-2026-10-16.md`.
5. Solo si vuelve Dropshipping, leer `docs/dropshipping-envios/RELEVO-2026-10-10.md`
   y `.kiro/steering/dropshipping-magandhi.md`.

## Realidad de arranque · 21-oct-2026

- **Promocionar P3 está cerrado FINAL:** desplegado, activo y medido en
  producción. La migración `20261108000000` se aplicó una vez; preflight,
  postflight y matriz quedaron verdes. Existen cinco tablas privadas. No volver
  a ejecutar la migración ni editarla: toda corrección futura es forward.
- El cron nominal es exactamente `promocionar-p3-mantenimiento-horario`,
  `7 * * * *`, dirigido a `current_database()`; el último run medido fue
  `succeeded` dentro de dos horas. No inventar ni documentar `jobid`.
- La Edge `enlace-promocional` está desplegada con Verify JWT OFF. Usa
  `PROMOCIONAR_IP_HEADER=x-real-ip` y tiene `PROMOCIONAR_IP_SAL` configurado;
  **nunca leer, copiar ni registrar el valor de esa sal**.
- El DNS autoritativo pasó de Porkbun a Cloudflare, con nameservers
  `rita.ns.cloudflare.com` y `toby.ns.cloudflare.com`; Porkbun sigue siendo el
  registrador y DNSSEC/DS quedó OFF durante el cambio. Se migraron 24 registros
  (4 A, 8 CNAME, 3 MX y 9 TXT), todos los preexistentes en DNS only; GitHub
  Pages y Zoho/Resend quedaron preservados. Worker `magandhi-go-p3` está en
  Production y atiende el custom domain `go.magandhi.com`.
- Los tres gates P3 quedaron ON el `2026-10-21 04:41:09.507253Z`; política
  `false`/`null` y fuera del gate, cuota 600 y bitácora 2 al activar. Existe un
  único enlace producto controlado activo.
- Sondas productivas: enlace activo `302`, body 0, sin `Set-Cookie`,
  `Cache-Control: no-store`, `Location` MAGANDHI exacta, query `url`/`next`
  ignorada; `HEAD 302`, `OPTIONS 204`, `POST 405`, inválidos `404`; sin banner,
  popup, modal, aviso ni consentimiento; TTFB observado 0,22–0,43 s.
- Las sondas negativas dejaron 0 clics y 0 ventanas. Dos `GET` positivos con IP
  falsa distinta terminaron en 2 clics, 1 fila diaria y 1 ventana, demostrando
  overwrite de `x-real-ip`; histórico 0 e invariantes 0. **Esos dos clics son
  sintéticos:** el enlace controlado no debe usarse para métricas reales.
- **Cierre FINAL P3:** GitHub Actions run `39549981902` terminó
  `completed/success`. La salida revisada mostró
  `RESUMEN P3 SQL | 15 comprobaciones · 0 fallan`, Deno
  `9 passed | 0 failed`, `RESUMEN P3 Worker | 7 comprobaciones · 0 fallan` y
  veredicto `Todo pasa.` El hardening de cuerpo vacío en respuestas `302` se
  fusionó en PR #304 el `2026-10-21T05:48:15Z`, merge
  `f1f61527f4535b2d09b58255d9730690bebc072f`; el dueño confirmó el
  redespliegue del Worker desde ese merge. La sonda mínima posterior, ejecutada
  el `2026-10-21T05:56:36Z`, confirmó DNS público A correcto, `GET 302`, body 0,
  sin `Set-Cookie`, `Cache-Control: no-store`, `Location` MAGANDHI exacta,
  query `url`/`next` ignorada y TTFB `0.390943s`; también `HEAD 302`,
  `OPTIONS 204` e inválido `404`.
- **Límite de evidencia no bloqueante:** el dueño recorrió guardar + activar;
  no se automatizaron ni recorrieron todas las ramas de UI interna
  —edición/CAS y fallback forzado—. Los bancos SQL/core/Worker cubren los
  contratos; no inventar ejecución visual adicional.
- P3 solo entrega **clics aproximados**. Un CTR necesita impresiones. P3
  permanece cerrado FINAL.
- **P4 está desplegado, activo y cerrado estructuralmente:** migración
  `20261109000000` aplicada una vez; Edge `enlace-promocional` y
  `crear-intencion-pago` redesplegadas; backend #306 y tienda #118 publicados.
  Gate ON desde `2026-10-21T15:21:59.626776Z`. Prueba final sin dinero:
  validación 204, redirect con fragmento, captura local, intención 200 y llegada
  a Wompi. Estado: 1 intención atribuida sintética, 0 pedidos, 0 divergencias y
  0 incidencias. No afirmar cierre transaccional: no hubo pago/webhook/pedido.
- **P5 está fusionado, publicado, instalado y cerrado estructural/productivamente:**
  PR #308, merge `3205e1b0cfcd5fc98126ccf2f37aa3cb2bf914f1` del 21-oct-2026;
  migración `20261110000000` ejecutada una vez; CI `39643360479` `success`
  (88 migraciones, matriz 230/0, `Todo pasa.`) y Pages `39645791554` `success`
  sobre el merge. El dueño recorrió Resultados, Métricas y Ventas y confirmó
  «Todo en orden». No quedaron confirmados preflight ni postflight productivos
  separados. Tampoco se acreditaron categorías con datos reales, compra, pago
  `APPROVED`, pedido atribuido ni ingreso.
- **P0 está cerrado como contrato documental, sin implementación ni producción.**
- **P1–P5 están desplegados y cerrados en sus alcances respectivos.** P3
  permanece cerrado FINAL; P4 permanece activo y cerrado estructuralmente; P5
  es productivo y de solo lectura. No hay P6 definido.
- El pendiente monetario común C5/P4/P5 exige una compra real expresamente
  autorizada; hasta entonces no afirmar cierre monetario/end-to-end.
- Reversa P3: apagar juntos los tres gates, verificar respuesta MAGANDHI no
  disponible, conservar cron, datos, códigos y bitácora, y corregir con migración
  forward. Mantener DNS/Worker mientras se diagnostica; **no borrar todavía los
  registros conservados en Porkbun**.
- **Comercial C1–C5 cerrados estructuralmente.** C4 superado por C5. Sin pago
  real por carrito: no hay cierre transaccional. Carrito ENCENDIDO
  (`carrito_habilitado=true`), Wompi `prod`, signup OFF.
- No existe tabla de ledger: migraciones manuales por SQL Editor, un Run por
  archivo. Nunca `supabase db push`; nunca reaplicar una migración histórica.
- Pago real únicamente con autorización expresa del dueño.

## Convenciones con el dueño

- Los SQL para el SQL Editor se entregan **pegados en el chat** y deben devolver
  **una sola tabla**: el editor muestra solo el último resultado.
- Antes de entregar un SQL operativo, ejecutarlo en CI y leer en el log la salida
  positiva esperada; «CI verde» no basta.
- Indicar siempre si un paso escribe o es solo lectura, y qué resultado exacto
  esperar.
- Cadencia acordada: desplegar juntos todos los componentes del tramo,
  comunicar los errores reales cuando aparezcan y concentrar la validación en
  una prueba integral grande al final; evitar rondas repetitivas de “para ver”
  salvo diagnóstico necesario.

Reglas permanentes: rama+PR, migraciones forward, medir antes de afirmar, no
exponer secretos/PII, y un comando sin error no es evidencia suficiente.
