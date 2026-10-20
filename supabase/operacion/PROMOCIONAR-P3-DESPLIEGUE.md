# Promocionar P3 · despliegue PostgreSQL y operación

**Estado de este corte:** artefactos preparados; migración no aplicada. Todos los gates nacen **OFF**.
**Alcance:** solo la migración PostgreSQL P3 y su operación. Edge, UI, DNS, docs generales, pruebas y P4/P5 se gestionan por separado.
**Método:** SQL Editor manual, un Run por archivo; no hay ledger productivo y no se usa `supabase db push`.

## Contrato que se instala

- Cinco tablas privadas con RLS y cero acceso directo de `anon`, `authenticated` o `service_role`; la quinta, `promocionar_p3_config_bitacora`, conserva append-only el before/after de gates y evidencia. Su conteo sí es observable; actores, roles y razones no se muestran en estado/postflight.
- Tres gates independientes: activación de enlaces, redirect y conteo. La operación global enciende o apaga los tres; el conteo también puede pausarse solo.
- Todo enlace pertenece a una `campana_producto_id` obligatoria, incluso si apunta a home. `tipo_destino` es exactamente `producto_v1` o `home_v1`; home resuelve a la home y producto al slug vigente de esa campaña.
- Crear: `promocionar_p3_crear_borrador(uuid,text,text,text,text,uuid,uuid)` con `(p_campana_producto_id,p_tipo_destino,p_canal_promocion,p_campaign_base,p_content,p_clave_idempotencia,p_reemplaza_enlace_id)`.
- Editar: `promocionar_p3_editar_borrador(uuid,timestamptz,text,text,text,text)` con `(p_enlace_id,p_actualizado_en_esperado,p_tipo_destino,p_canal_promocion,p_campaign_base,p_content)`. El `actualizado_en` devuelto es el token CAS exacto; una versión obsoleta falla con `P3_BORRADOR_VERSION_CONFLICTO`.
- Solo un borrador puede reemplazar directamente a cada enlace. El anterior debe estar desactivado y pertenecer a la misma campaña de origen; el reemplazo sí puede corregir `tipo_destino`.
- Activar un enlace ya activo devuelve idempotentemente el mismo JSON/código. Un enlace desactivado es terminal y nunca se reactiva.
- Todo JSON de enlace incluye el booleano obligatorio `resoluble`. Solo es `true` para un enlace activo que el redirect podría resolver ahora: gates de redirect/política/version/routing vigentes y, para `producto_v1`, campaña activa, publicada, no placeholder y con slug válido. Borradores, desactivados, productos no publicables o redirect apagado devuelven `false`; volver a ejecutar `promocionar_p3_listar` revalida este estado antes de distribuir.
- Todos los `SECURITY DEFINER` fijan exactamente `public, pg_temp` o, donde se usa pgcrypto, `public, extensions, pg_temp`; los roles API no pueden crear objetos en `public` ni `extensions`.

## Instalación estructural (una sola vez)

1. Confirmar backup/PITR, ventana del dueño y P1 aplicado hasta `20261107000100`.
2. Ejecutar completo `promocionar-p3-preflight.sql`. Es solo lectura: una fila, todos los checks `true`, contadores de slug `0` y `listo_para_aplicar=true`.
3. Ejecutar una sola vez `../migrations/20261108000000_promocionar_p3_enlaces.sql`. Si alcanza `COMMIT`, no volver a ejecutarla ni editarla en producción.
4. Ejecutar `promocionar-p3-postflight.sql`. Es estructural y no exige cron porque la instalación termina OFF. Debe devolver todos los booleanos `true`, incluido `clics_fecha_idx_ok=true` para el índice nominal `(fecha_colombia, enlace_id)`, `enlaces_iniciales=0`, `clics_iniciales=0`, `limites_iniciales=0`, `bitacora_inicial=1` y `postflight_ok=true`.
5. Se puede ejecutar `promocionar-p3-estado.sql` aquí: los tres gates deben estar `false`, los datos en cero y la bitácora en `1`. Las tres filas de cron mostrarán `PENDIENTE`, no una autorización para activar.

Si algo falla antes de `COMMIT`, repetir primero el preflight para probar reversión completa. Si hubo `COMMIT` o estado parcial, preparar otra migración forward; no corregir a mano.

## Mantenimiento obligatorio antes de activar

La activación falla cerrada salvo que exista `pg_cron` y exactamente un job nominal con este contrato literal. El job debe apuntar a la misma base en la que se ejecutan el estado, la reanudación o la activación; un job homónimo de otra base no aporta evidencia válida.

| Campo | Valor obligatorio |
|---|---|
| `jobname` | `promocionar-p3-mantenimiento-horario` |
| `database` | resultado de `current_database()` |
| `active` | `true` |
| `schedule` | `7 * * * *` |
| `command` | `select public.promocionar_p3_mantenimiento();` |

1. Habilitar `pg_cron` por el procedimiento aprobado del proyecto.
2. Comprobar primero que no exista un job nominal conflictivo y que cualquier coincidencia apunte a la base actual:

   ```sql
   select current_database() as base_actual,
          count(*) as jobs_nominales,
          bool_and(database = current_database()) as base_actual_exacta,
          bool_and(active) as todos_activos,
          bool_and(schedule = '7 * * * *') as schedule_exacto,
          bool_and(btrim(command) = 'select public.promocionar_p3_mantenimiento();') as command_exacto
     from cron.job
    where jobname = 'promocionar-p3-mantenimiento-horario';
   ```

   Si `jobs_nominales > 0` y cualquier contrato es falso —incluido `base_actual_exacta`—, detenerse y corregir el job aprobado conservando su identidad; no crear un duplicado ni cambiar el nombre. Un job que apunte a otra base nunca autoriza esta base.
3. Solo si `jobs_nominales=0`, desde el SQL Editor conectado a la base objetivo confirmada por `current_database()`, agendar exactamente:

   ```sql
   select cron.schedule(
     'promocionar-p3-mantenimiento-horario',
     '7 * * * *',
     'select public.promocionar_p3_mantenimiento();'
   );
   ```

   Repetir la consulta contractual anterior y exigir `base_actual_exacta=true`; `cron.schedule` debe haber persistido `cron.job.database = current_database()`.
4. Esperar a que el job nominal ejecute de verdad (el minuto 7 de la siguiente hora). Una llamada manual a la función puede limpiar, pero **no sustituye** la evidencia de `cron.job_run_details`.
5. Medir el último run vinculado exclusivamente al job de la base actual, sin extraer comandos, hashes ni parámetros:

   ```sql
   select d.status, d.start_time, d.end_time,
          d.end_time >= statement_timestamp() - interval '2 hours' as dentro_de_2h
     from cron.job_run_details d
     join cron.job j on j.jobid = d.jobid
    where j.jobname = 'promocionar-p3-mantenimiento-horario'
      and j.database = current_database()
    order by d.runid desc
    limit 1;
   ```

   Debe ser `succeeded`, tener `end_time` y quedar dentro de las últimas dos horas. Un run de un job homónimo ligado a otra base se ignora y no puede autorizar activación ni reanudación.
6. Ejecutar `promocionar-p3-estado.sql`: cron instalado/job/run de la base actual deben ser `true`; cuotas vencidas y detalle vencido para compactar deben ser `0`. `promocionar-p3-activar.sql` vuelve a comprobar dinámicamente todo esto y aborta si cambió.

La función compacta detalle anterior a 13 meses en el histórico dentro de la misma transacción y purga cuotas vencidas. Las cuotas nacen a 47 horas; el job horario conserva el límite estricto menor a 48 horas.

## Frontera Edge y routing (evidencia separada)

Antes de activar:

1. Desplegar y medir la Edge remota con **Verify JWT OFF** únicamente para este redirect público.
2. Configurar `PROMOCIONAR_IP_SAL` como secreto maestro aleatorio de **mínimo 32 bytes UTF-8**. La Edge deriva una llave HMAC distinta por fecha de Colombia; nunca usa la `service_role` como sal.
3. Configurar `PROMOCIONAR_IP_HEADER` con exactamente una de estas opciones: `cf-connecting-ip`, `x-real-ip` o `x-forwarded-for`. Elegirla solo después de demostrar que el último proxy la sobrescribe y que una cabecera enviada por el cliente no puede suplantarla; la Edge no prueba alternativas.
4. Configurar DNS, TLS y proxy para `https://go.magandhi.com/<codigo>` y verificar que la query no selecciona destino.
5. Medir lista blanca y ausencia de open redirect; `GET/HEAD/OPTIONS`; `302`; `Cache-Control: no-store`; CORS; código inválido/desactivado; y falla independiente del contador.
6. Confirmar que solo cuenta un `GET` con `Sec-Fetch-Mode: navigate`, `Sec-Fetch-Dest: document`, `Accept` con `text/html`, UA humano y sin señales de preview/prefetch. La ausencia de cualquiera de las tres señales positivas no cuenta.
7. Medir cuota, fecha Colombia, derivación diaria, logs sin IP/hash/URL/UA y publicar la política con su versión literal.

La presencia de archivos en Git no prueba ninguna de estas condiciones. Resolver y contar siguen separados: un fallo de conteo no cambia un destino ya resuelto. `redirect_habilitado` gobierna resolución; `conteo_habilitado`, conteo; `activacion_habilitada`, nuevas activaciones. Crear, editar y listar borradores funciona con gates OFF.

## Activación global — no ejecutar aún

Solo después de instalación, cron sano y evidencia Edge/routing:

1. En `promocionar-p3-activar.sql`, reemplazar `REEMPLAZAR_VERSION_POLITICA` y cambiar individualmente a `true` las cinco confirmaciones.
2. Ejecutar el archivo completo. Exige job nominal exacto apuntando a `current_database()`, último run de ese job/base exitoso dentro de dos horas, cero cuotas vencidas y cero detalle vencido.
3. Exigir `activado_confirmado=true`; repetir `promocionar-p3-estado.sql` y luego activar un enlace controlado para las sondas productivas.

La operación registra `auth.uid()` nullable, `current_user` y la razón `activacion_global:<version>` en la bitácora. Repetirla sobre el mismo estado/version es un no-op idempotente, pero vuelve a exigir cron sano.

## Pausar y reanudar solo el conteo

- Ejecutar `promocionar-p3-pausar-conteo.sql` para poner solo `conteo_habilitado=false`. Es idempotente y debe devolver `conteo_pausado_confirmado=true`. El lock espera los conteos ya autorizados y bloquea nuevos mientras confirma; redirect y activación no cambian.
- Ejecutar `promocionar-p3-reanudar-conteo.sql` para volver a `true`. Es idempotente, pero siempre exige redirect encendido, política/version/routing vigentes, job nominal exacto apuntando a `current_database()` y último run de ese job/base `succeeded` dentro de dos horas. También conserva el bloqueo si quedan cuotas o detalle vencidos. Debe devolver `conteo_reanudado_confirmado=true`.
- Ambas operaciones registran razón, `auth.uid()` nullable y `current_user`; nunca borran historial.

## Desactivación y reversa

Ante una falla de resolución segura, privacidad, retención o routing:

1. Ejecutar `promocionar-p3-desactivar.sql`. Es idempotente, apaga juntos los tres gates y debe devolver `apagado_confirmado=true`.
2. Verificar por HTTP la respuesta MAGANDHI no disponible y ejecutar `promocionar-p3-estado.sql`.
3. Conservar y seguir ejecutando el cron. La operación preserva enlaces, códigos, clics, histórico, política, routing y toda la bitácora.
4. Corregir PostgreSQL mediante otra migración forward. No borrar/reutilizar códigos ni reactivar enlaces desactivados.
