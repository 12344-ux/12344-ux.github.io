# Relevo de sesión · Promocionar P3 · cierre FINAL · 21 de octubre de 2026

**Estado inequívoco:** P3 está desplegado, activo, medido y **cerrado FINAL** en producción. El hardening del Worker fue fusionado, el dueño confirmó su redespliegue desde ese merge y la sonda mínima posterior quedó verde. **P4 es el siguiente tramo; P5 viene después.**

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
| Hardening final de cuerpo vacío `302` | #304 · `f1f61527f4535b2d09b58255d9730690bebc072f` · fusionado `2026-10-21T05:48:15Z` |

No inventar version IDs de Edge/Worker: este corte acredita el merge registrado,
el redespliegue confirmado por el dueño y el comportamiento medido, no
identificadores de despliegue no registrados.

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
| Sonda post-redespliegue | `2026-10-21T05:56:36Z`; DNS público A correcto |
| GET positivo | `302`, body 0, sin `Set-Cookie`, `Cache-Control: no-store` |
| Destino | `Location` MAGANDHI exacta |
| Open redirect | query `url`/`next` ignorada |
| Métodos | `HEAD 302`, `OPTIONS 204`, `POST 405` |
| Inválidos | `404` |
| Interfaz pública | sin banner, popup, modal, aviso ni consentimiento |
| TTFB post-redespliegue | `0.390943s` |

No se atribuyen pruebas de todas las ramas de UI interna. El dueño recorrió
guardar + activar; edición/CAS y fallback forzado no se automatizaron ni se
recorrieron por completo. Los bancos SQL/core/Worker cubren esos contratos y el
límite no bloquea este cierre operativo. Estas sondas acreditan únicamente el
flujo público observado.

### Conteo controlado

- Sondas negativas: 0 clics y 0 ventanas.
- Dos `GET` positivos con IP falsa distinta: 2 clics, 1 fila diaria y 1 ventana.
- El resultado demuestra overwrite de la cabecera: el Worker impone `x-real-ip` desde Cloudflare en vez de confiar en el visitante.
- Histórico 0; invariantes 0.
- **Los dos clics son sintéticos.** No distribuir el enlace controlado ni usarlo para decisiones, totales o métricas reales.

## 4. Banco y secuencia final acreditados

- Banco local acreditado en esta rama: core 9/0 y Worker 7/0.
- SQL reversible P3 integrado al workflow de CI.
- GitHub Actions run `39549981902`: `completed/success`; salida revisada:
  - `RESUMEN P3 SQL | 15 comprobaciones · 0 fallan`
  - Deno: `9 passed | 0 failed`
  - `RESUMEN P3 Worker | 7 comprobaciones · 0 fallan`
  - veredicto: `Todo pasa.`
- El banco encontró y corrigió una defensa faltante: el Worker descarta cualquier
  cuerpo accidental que Edge envíe junto a un `302`, además de retirar cabeceras
  de longitud/codificación incompatibles.
- Secuencia de cierre:
  - [x] CI verde con salida revisada.
  - [x] PR #304 fusionado el `2026-10-21T05:48:15Z`, merge
        `f1f61527f4535b2d09b58255d9730690bebc072f`.
  - [x] El dueño confirmó el redespliegue de `magandhi-go-p3` desde ese merge.
  - [x] Sonda positiva post-redespliegue a las `2026-10-21T05:56:36Z`: DNS
        público A correcto; `GET 302`, body 0, sin `Set-Cookie`, `no-store`,
        `Location` exacta, query `url`/`next` ignorada y TTFB `0.390943s`;
        `HEAD 302`, `OPTIONS 204` e inválido `404`.
  - [x] Este relevo quedó promovido a cierre FINAL.

La secuencia CI → merge → redespliegue confirmado → sonda posterior cierra P3
sin atribuir identificadores de despliegue ni evidencia no registrada.

## 5. Frontera funcional

- **P3:** enlaces y clics aproximados agregados. No son personas, impresiones, ventas ni atribución transaccional.
- **CTR:** requiere un denominador de impresiones; P3 no lo produce y no debe inferirse con clics solos.
- **P4 · siguiente tramo:** comienza al validar y congelar `atribucion_enlace_id` en intención/pedido; allí empieza la atribución de conversión/pedidos.
- **P5 · tramo posterior:** incorpora tablero e ingresos con denominadores explícitos.

## 6. Reversa segura

1. Ejecutar `../supabase/operacion/promocionar-p3-desactivar.sql` y confirmar los tres gates OFF.
2. Verificar respuesta MAGANDHI no disponible y estado SQL.
3. Conservar cron, enlaces, códigos, clics, histórico y bitácora.
4. Mantener DNS y Worker mientras se diagnostica, salvo aislamiento necesario por incidente.
5. **No borrar todavía los registros conservados en Porkbun.** Tampoco eliminar los 24 registros migrados de Cloudflare durante el diagnóstico.
6. Corregir SQL solo con migración forward; corregir Worker mediante revisión, CI, merge y redespliegue. No reactivar enlaces desactivados ni reutilizar códigos.

## 7. Cierre y continuidad

- [x] SQL P3 aplicado una vez.
- [x] Preflight, postflight y matriz verdes.
- [x] Cinco tablas y cron exacto medidos.
- [x] Edge, DNS, Worker y custom domain desplegados.
- [x] Gates ON y enlace controlado activo.
- [x] Sondas HTTP, negativas y positivas medidas.
- [x] Clics sintéticos identificados y excluidos de métricas reales.
- [x] Banco local core 9/0 y Worker 7/0.
- [x] CI del hardening declarada verde tras revisar su salida.
- [x] Hardening fusionado en #304 y Worker redesplegado desde su merge.
- [x] Sonda post-redespliegue archivada.
- [x] Cierre FINAL P3 declarado.

**Próximo tramo: P4.** P5 es posterior. No reabrir DNS, SQL, cron, gates ni
pruebas ya acreditadas salvo regresión medida.
