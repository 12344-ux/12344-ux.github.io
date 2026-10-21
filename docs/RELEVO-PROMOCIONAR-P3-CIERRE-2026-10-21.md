# Relevo de sesión · Promocionar P3 · cierre candidato · 21 de octubre de 2026

**Estado inequívoco:** P3 está desplegado, activo y medido en producción. Este documento es un **cierre candidato**, pendiente únicamente del **merge + redespliegue del hardening del Worker + sonda mínima posterior**. No declarar cierre final hasta completar y medir esos tres pasos.

Leer después `PLANO-PROMOCIONAR-P3.md`, `../supabase/operacion/PROMOCIONAR-P3-DESPLIEGUE.md` y `PLANO-PROMOCIONAR-P0.md`. El relevo Comercial C5 continúa gobernando carrito, Wompi y su cierre monetario pendiente.

## 1. Respuesta corta

- Migración `20261108000000_promocionar_p3_enlaces.sql` aplicada una sola vez; preflight, postflight y matriz verdes; cinco tablas privadas instaladas.
- Cron exacto `promocionar-p3-mantenimiento-horario`, `7 * * * *`, misma base, activo y con último run `succeeded` dentro de dos horas.
- Edge `enlace-promocional` desplegada con Verify JWT OFF, `PROMOCIONAR_IP_SAL` configurado y `PROMOCIONAR_IP_HEADER=x-real-ip`. Nunca registrar el valor de la sal.
- DNS autoritativo movido de Porkbun a Cloudflare (`rita.ns.cloudflare.com`, `toby.ns.cloudflare.com`); Porkbun sigue como registrador y DNSSEC/DS permaneció OFF durante el cambio.
- Se migraron 24 registros: 4 A, 8 CNAME, 3 MX y 9 TXT. Los preexistentes quedaron DNS only; GitHub Pages, Zoho y Resend se preservaron.
- Worker `magandhi-go-p3` en Production con custom domain `go.magandhi.com`.
- Gates ON desde `2026-10-21 04:41:09.507253Z`; política `false`/`null` fuera del gate, cuota 600 y bitácora 2 al activar.
- Un enlace producto controlado activo; sus dos clics son sintéticos y no sirven para métricas reales.

## 2. Código y despliegues acreditados

| Entrega | PR/merge |
|---|---|
| Registro, SQL, administración y Edge P3 | #300 · `b2440c3` |
| Redirect sin aviso/consentimiento intermedio | #301 · `11d8008` |
| Redirect inmediato, independiente del conteo | #302 · `b4f8acb` |
| Worker Cloudflare y custom domain | #303 · `23ea5a2` |

No inventar version IDs de Edge/Worker: este corte acredita despliegue y comportamiento medido, no identificadores no registrados.

## 3. Evidencia productiva

### PostgreSQL y cron

- Preflight, postflight y matriz: verdes.
- Cinco tablas P3 presentes; migración aplicada una vez y no repetible.
- Cron nominal, schedule y base exactos; último run `succeeded` dentro de dos horas.
- No documentar `jobid` ni resultados de logs privados.

### DNS y routing

- Nameservers autoritativos: `rita.ns.cloudflare.com` y `toby.ns.cloudflare.com`.
- Registrador: Porkbun.
- DNSSEC/DS: OFF durante el cambio.
- 24 registros migrados y preservados: 4 A, 8 CNAME, 3 MX, 9 TXT; los preexistentes en DNS only.
- GitHub Pages y registros de Zoho/Resend preservados.
- Worker `magandhi-go-p3`: Production; custom domain `go.magandhi.com`.

### Gates y enlace controlado

- `activacion_habilitada=true`, `redirect_habilitado=true`, `conteo_habilitado=true` desde `2026-10-21 04:41:09.507253Z`.
- Política `false`/`null`; no es gate de P3.
- Cuota 600; bitácora 2 al activar.
- Un enlace producto controlado activo.

### HTTP y privacidad

| Sonda | Resultado |
|---|---|
| GET positivo | `302`, body 0, sin `Set-Cookie`, `Cache-Control: no-store` |
| Destino | `Location` MAGANDHI exacta |
| Open redirect | query `url`/`next` ignorada |
| Métodos | `HEAD 302`, `OPTIONS 204`, `POST 405` |
| Inválidos | `404` |
| Interfaz pública | sin banner, popup, modal, aviso ni consentimiento |
| TTFB observado | 0,22–0,43 s |

No se atribuyen pruebas de UI interna no ejecutadas. Estas sondas acreditan el flujo público observado.

### Conteo controlado

- Sondas negativas: 0 clics y 0 ventanas.
- Dos `GET` positivos con IP falsa distinta: 2 clics, 1 fila diaria y 1 ventana.
- El resultado demuestra overwrite de la cabecera: el Worker impone `x-real-ip` desde Cloudflare en vez de confiar en el visitante.
- Histórico 0; invariantes 0.
- **Los dos clics son sintéticos.** No distribuir el enlace controlado ni usarlo para decisiones, totales o métricas reales.

## 4. Banco acreditado y único pendiente

- Banco local acreditado en esta rama: core 9/0 y Worker 7/0.
- SQL reversible P3 integrado al workflow de CI.
- GitHub Actions run `39549981902`: `completed/success`; salida revisada:
  - `RESUMEN P3 SQL | 15 comprobaciones · 0 fallan`
  - Deno: `9 passed | 0 failed`
  - `RESUMEN P3 Worker | 7 comprobaciones · 0 fallan`
  - veredicto: `Todo pasa.`
- El banco encontró y corrigió una defensa faltante: el Worker ahora descarta cualquier cuerpo accidental que Edge envíe junto a un `302`, además de retirar cabeceras de longitud/codificación incompatibles.
- Esa versión de `worker.js` todavía requiere:
  - [x] CI verde con salida revisada.
  - [ ] Merge del hardening.
  - [ ] Redespliegue de `magandhi-go-p3`.
  - [ ] Repetir sonda positiva y confirmar `302`, body 0, sin cookies y `no-store`.
  - [ ] Convertir este relevo de cierre candidato en cierre final.

Hasta entonces P3 productivo sigue operativo con la evidencia ya medida, pero el cierre documental no es final.

## 5. Frontera funcional

- **P3:** enlaces y clics aproximados agregados. No son personas, impresiones, ventas ni atribución transaccional.
- **CTR:** requiere un denominador de impresiones; P3 no lo produce y no debe inferirse con clics solos.
- **P4:** comienza al validar y congelar `atribucion_enlace_id` en intención/pedido; allí empieza la atribución de conversión/pedidos.
- **P5:** incorpora tablero e ingresos con denominadores explícitos.

## 6. Reversa segura

1. Ejecutar `../supabase/operacion/promocionar-p3-desactivar.sql` y confirmar los tres gates OFF.
2. Verificar respuesta MAGANDHI no disponible y estado SQL.
3. Conservar cron, enlaces, códigos, clics, histórico y bitácora.
4. Mantener DNS y Worker mientras se diagnostica, salvo aislamiento necesario por incidente.
5. **No borrar todavía los registros conservados en Porkbun.** Tampoco eliminar los 24 registros migrados de Cloudflare durante el diagnóstico.
6. Corregir SQL solo con migración forward; corregir Worker mediante revisión, CI, merge y redespliegue. No reactivar enlaces desactivados ni reutilizar códigos.

## 7. Estado para la próxima sesión

- [x] SQL P3 aplicado una vez.
- [x] Preflight, postflight y matriz verdes.
- [x] Cinco tablas y cron exacto medidos.
- [x] Edge, DNS, Worker y custom domain desplegados.
- [x] Gates ON y enlace controlado activo.
- [x] Sondas HTTP, negativas y positivas medidas.
- [x] Clics sintéticos identificados y excluidos de métricas reales.
- [x] Banco local core 9/0 y Worker 7/0.
- [x] CI del hardening declarada verde tras revisar su salida.
- [ ] Hardening fusionado y Worker redesplegado.
- [ ] Sonda post-redespliegue archivada.
- [ ] Cierre final P3 declarado.

**Próximo paso único:** completar merge + redespliegue del hardening de cuerpo `302`; volver a medir la sonda mínima y solo entonces finalizar el cierre. No reabrir DNS, SQL, cron, gates ni pruebas ya acreditadas salvo que esa sonda revele regresión.
