# Promocionar P3 · despliegue PostgreSQL y operación

**Estado productivo · 21-oct-2026:** migración aplicada una vez, cron sano, Edge/routing medidos y tres gates **ON**. Cierre candidato: faltan únicamente merge, redespliegue del hardening del Worker que fuerza cuerpo vacío en `302` y sonda mínima posterior.
**Alcance:** migración PostgreSQL P3, cron, Edge, Worker/DNS, activación, observación y reversa. P4/P5 se gestionan por separado.
**Método SQL:** SQL Editor manual, un Run por archivo; no hay ledger productivo y no se usa `supabase db push`.

## Evidencia productiva del corte

- `20261108000000_promocionar_p3_enlaces.sql` se aplicó **una sola vez**. No volver a ejecutarla ni editarla; toda corrección será forward.
- Preflight, postflight y matriz de privilegios: verdes. Modelo instalado: cinco tablas privadas.
- Cron exacto: `promocionar-p3-mantenimiento-horario`, schedule `7 * * * *`, comando `select public.promocionar_p3_mantenimiento();`, misma base (`current_database()`), activo y con último run `succeeded` dentro de dos horas. No se documenta `jobid`.
- Edge `enlace-promocional`: desplegada, Verify JWT OFF, `PROMOCIONAR_IP_HEADER=x-real-ip` y `PROMOCIONAR_IP_SAL` configurado. Nunca incluir, consultar o registrar el valor de la sal.
- DNS autoritativo en Cloudflare: `rita.ns.cloudflare.com` y `toby.ns.cloudflare.com`. Porkbun continúa como registrador; DNSSEC/DS se mantuvo OFF durante el cambio. Se migraron 24 registros: 4 A, 8 CNAME, 3 MX y 9 TXT. Todos los registros preexistentes quedaron DNS only; GitHub Pages y Zoho/Resend se preservaron.
- Worker `magandhi-go-p3`: Production, custom domain `go.magandhi.com`.
- Gates ON desde `2026-10-21 04:41:09.507253Z`; política `false`/`null` y fuera del gate, cuota 600, bitácora 2 al activar. Hay un enlace producto controlado activo.
- HTTP medido: `GET 302`, body 0, sin `Set-Cookie`, `Cache-Control: no-store`, `Location` MAGANDHI exacta y query `url`/`next` ignorada; `HEAD 302`, `OPTIONS 204`, `POST 405`, inválidos `404`; sin banner, popup, modal, aviso ni consentimiento; TTFB 0,22–0,43 s.
- Sondas negativas: 0 clics y 0 ventanas. Dos `GET` positivos con IP falsa distinta: 2 clics, 1 fila diaria y 1 ventana, lo que demuestra que la infraestructura sobrescribe `x-real-ip`. Histórico 0 e invariantes 0.
- Los dos clics son **sintéticos**. El enlace controlado no se distribuye ni se usa para métricas reales.

## Estado de código y banco

- PR/merge de implementación: #300 `b2440c3`, #301 `11d8008`, #302 `b4f8acb` y #303 `23ea5a2`.
- GitHub Actions run `39549981902` terminó `completed/success`. Su salida revisada mostró:
  - `RESUMEN P3 SQL | 15 comprobaciones · 0 fallan`
  - Deno `9 passed | 0 failed`
  - `RESUMEN P3 Worker | 7 comprobaciones · 0 fallan`
  - veredicto `Todo pasa.`
- El banco detectó y corrigió en `cloudflare/magandhi-go-p3/worker.js` la defensa para que un `302` nunca propague cuerpo accidental de Edge. Esa revisión todavía necesita merge, redespliegue de `magandhi-go-p3` y sonda mínima posterior antes de declarar cierre final.

## Contrato instalado

- Cinco tablas privadas con RLS y cero acceso directo de `anon`, `authenticated` o `service_role`; `promocionar_p3_config_bitacora` conserva append-only el before/after de gates.
- Tres gates independientes: activación, redirect y conteo. La operación global enciende o apaga los tres; el conteo puede pausarse solo.
- Todo enlace pertenece a una campaña, aun si apunta a home. `tipo_destino` es `producto_v1` o `home_v1`; el destino se resuelve server-side desde lista blanca.
- Crear y editar borradores usan idempotencia y CAS; un enlace activado conserva código/destino y un desactivado es terminal.
- Todo JSON incluye `resoluble`; distribuir exige revalidación autoritativa. P2 continúa como degradación segura.
- Los tres gates nacieron OFF. Ese hecho histórico no describe el estado actual: ahora están ON.

## Instalación estructural · ejecutada una vez

1. Preflight de solo lectura: verde.
2. Migración `../migrations/20261108000000_promocionar_p3_enlaces.sql`: aplicada una sola vez.
3. Postflight y matriz: verdes; cinco tablas presentes.
4. Estado inicial medido con gates OFF y bitácora inicial 1.
5. No repetir ningún paso de escritura. Los SQL de estado, postflight y matriz siguen disponibles para diagnóstico de solo lectura.

## Mantenimiento obligatorio

El contrato literal vigente es:

| Campo | Valor obligatorio |
|---|---|
| `jobname` | `promocionar-p3-mantenimiento-horario` |
| `database` | resultado de `current_database()` |
| `active` | `true` |
| `schedule` | `7 * * * *` |
| `command` | `select public.promocionar_p3_mantenimiento();` |

Antes de reanudar conteo o reactivar tras una reversa, comprobar exactamente un job nominal en la base actual, último run de ese mismo job/base `succeeded` dentro de dos horas, y cero cuotas o detalle vencidos. Un run manual o uno homónimo de otra base no sirve. No registrar `jobid`, comandos privados, hashes o parámetros en documentación.

La función compacta detalle anterior a 13 meses en el histórico dentro de la misma transacción y purga cuotas vencidas. Las cuotas nacen a 47 horas; el job horario conserva el límite menor a 48 horas.

## Frontera Edge, Worker y DNS

- Edge pública `enlace-promocional`: Verify JWT OFF. Solo ella usa el secreto `PROMOCIONAR_IP_SAL`; el repositorio nunca contiene su valor.
- Cabecera única: `PROMOCIONAR_IP_HEADER=x-real-ip`. El Worker reemplaza cualquier valor del visitante por `CF-Connecting-IP`; no usa fallbacks.
- Worker `magandhi-go-p3` fija un único origen, no sigue el `302`, filtra cabeceras, elimina cookies y fuerza `no-store`.
- El hardening pendiente de cierre fuerza cuerpo nulo para `302` y elimina cabeceras de longitud/codificación asociadas; CI ya terminó `completed/success`, pero aún requiere merge, redespliegue y sonda mínima posterior.
- Cloudflare es DNS autoritativo; Porkbun conserva el registro del dominio. Los 24 registros migrados y los servicios GitHub Pages/Zoho/Resend no se alteran durante P3.

## Activación global · ejecutada el 21-oct-2026

`promocionar-p3-activar.sql` se ejecutó después de validar instalación, cron, Edge y routing. Los tres gates pasaron a `true` en `2026-10-21 04:41:09.507253Z`; la bitácora quedó en 2. La política permaneció `false`/`null`, explícitamente fuera del gate. La cuota quedó en 600.

Para diagnosticar usar `promocionar-p3-estado.sql`. No repetir activación como sustituto de diagnóstico. Un único enlace producto controlado permanece activo solo para operación; sus dos clics registrados son sintéticos y no deben mezclarse con métricas reales.

## Pausar y reanudar solo el conteo

- `promocionar-p3-pausar-conteo.sql` pone solo `conteo_habilitado=false`; redirect y activación no cambian.
- `promocionar-p3-reanudar-conteo.sql` exige redirect/routing vigentes, cron exacto de la base actual, último run `succeeded` dentro de dos horas y cero vencidos.
- Ambas operaciones son idempotentes y registran una transición solo cuando cambia el estado; nunca borran historial.

## Desactivación y reversa

Ante falla de resolución segura, privacidad, retención, routing o hardening:

1. Ejecutar `promocionar-p3-desactivar.sql`; debe apagar juntos los tres gates y devolver `apagado_confirmado=true`.
2. Verificar por HTTP la respuesta MAGANDHI no disponible y ejecutar `promocionar-p3-estado.sql`.
3. Mantener activo el cron. Preservar enlaces, códigos, clics, histórico y bitácora.
4. Mantener Worker y DNS mientras se diagnostica, salvo que el incidente exija aislar routing. **No borrar todavía los registros conservados en Porkbun**; tampoco borrar los 24 registros migrados de Cloudflare.
5. Corregir PostgreSQL con migración forward y el Worker mediante revisión, CI y redespliegue. Nunca reejecutar la migración P3, reutilizar códigos ni reactivar enlaces desactivados.

## Frontera P3/P4/P5

P3 produce clics aproximados, no personas ni ventas. Un CTR necesita impresiones y no puede calcularse con clics solos. P4 comienza al congelar el enlace validado en intención/pedido y atribuye conversión/pedidos. P5 incorpora tablero e ingresos con denominadores explícitos.
