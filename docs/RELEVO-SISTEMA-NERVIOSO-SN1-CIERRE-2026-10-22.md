# Relevo de sesión · Sistema Nervioso SN1 · cierre productivo · 22 de octubre de 2026

**Estado inequívoco:** SN1-A, SN1-B y SN1-C están instaladas, desplegadas y cerradas productivamente. Búsqueda y recomendación están activas y verificadas; la telemetría consentida permanece apagada deliberadamente hasta publicar una política definitiva. SN1-D continúa futura. La primera corrida automática individual del cron no quedó documentada en este corte y permanece como seguimiento operativo no bloqueante.

Leer después `PLANO-SISTEMA-NERVIOSO.md` y `../CONTEXTO-MAGANDHI.md`. Para activar analítica en el futuro, continuar desde la sección EM7 de `RELEVO-PROMOCIONAR-P5-CIERRE-ESTRUCTURAL-2026-10-21.md`.

No reaplicar `20261111000000`, `20261112000000` ni `20261113000000`. Toda corrección SQL futura debe ser una migración forward.

## 1. Implementación y despliegue acreditados

- Tienda pública: PR #136 fusionado en `magandhi`; contiene la integración y el endurecimiento del motor consumidor, la búsqueda, recomendaciones, fallback seguro y telemetría condicionada.
- Backend y consola: PR #313 fusionado en `12344-ux.github.io`; contiene migración de cierre, Edge Function y endurecimiento de assets.
- Corrección operativa: PR #314, merge `b9c92a3ff60ad93b5c0178c92bb8909cb9e6446c`; el Banco de pruebas run `39757519014` terminó `success`. Sustituyó tres `CREATE FUNCTION` por `CREATE OR REPLACE FUNCTION` después de detectar drift productivo, sin borrar funciones ni dependencias.
- El dueño confirmó la aplicación única y ordenada de:
  1. `20261111000000_campanas_categorias_oficiales.sql`;
  2. `20261112000000_sistema_nervioso_sn1.sql`;
  3. `20261113000000_sistema_nervioso_sn1_cierre.sql`.
- El dueño confirmó el redespliegue de `tienda-eventos`, Verify JWT apagado y `SN_CONSULTA_SAL` configurada sin revelar su valor.
- El dueño confirmó correctos el postflight SQL, la purga manual, la configuración nominal de `sn-purgar-telemetria-diario` y la prueba visual.

La primera ejecución de `20261111000000` en esta sesión falló con `42723` porque `cm_crear_campana_con_categorias` ya existía con la misma identidad. La transacción no alcanzó `COMMIT` y quedó revertida. El PR #314 hizo reemplazables los tres wrappers susceptibles; después de fusionarlo, el dueño confirmó las tres migraciones aplicadas correctamente.

## 2. Diagnóstico productivo exacto

```text
migraciones_aplicadas=20261111000000,20261112000000,20261113000000
edge=tienda-eventos
verify_jwt=OFF
SN_CONSULTA_SAL=configurada; valor no registrado
postflight_sql=correcto según el dueño
motor_sn.activo=true
motor_sn.modelo_version=sn1-reglas-1
motor_sn.personalizacion_cuenta=true
motor_sn.exploracion_pct=12
sonda_anonima.busqueda=ok; modo=exploracion; productos=2
sonda_anonima.recomendacion=ok; superficie=home_principal; modulos=2; productos=2
http.home=200
http.busqueda=200
telemetria_edge.activa=false
telemetria_edge.politica_version=borrador-0
purga_manual=correcta según el dueño
cron_job=sn-purgar-telemetria-diario confirmado correcto por el dueño
cron_job_run_details=corrida programada exacta no compartida
prueba_visual=correcta según el dueño
```

`sn_config.activo=true` es el gate del motor. La respuesta `activa=false` de `tienda-eventos` pertenece al gate independiente de analítica consentida. Por tanto, búsqueda, recomendación, composición y consola funcionan, mientras el navegador no debe crear identificadores ni emitir telemetría nueva.

La versión `borrador-0` no autoriza a presentar la medición como activa o plenamente consentida. Cuando se publique una política definitiva, cualquier decisión local anterior deberá invalidarse y cada persona tendrá que aceptar la versión nueva.

## 3. Qué significa este cierre

MAGANDHI dispone ahora de una capa común de reglas para:

- buscar productos elegibles;
- recomendar y componer módulos en home, categoría, producto, carrito y búsqueda;
- usar prioridad, intenciones, relaciones, ventanas, popularidad y afinidad permitida sin saltar stock ni publicación;
- administrar relaciones y activos editoriales por campaña;
- reutilizar el mismo contrato JSON desde una aplicación futura;
- apagar globalmente el motor sin apagar el catálogo comercial;
- caer exclusivamente a `sn_catalogo_seguro_v1` si la RPC falla o el motor se apaga.

SN1 es un motor determinista y auditable, no un modelo de aprendizaje automático. No decide libremente qué vender: siempre parte de `catalogo_publico` y excluye campañas agotadas, no comprables, inactivas, despublicadas, suprimidas o fuera de ventana.

**Cierre productivo** significa que las superficies centrales están utilizables y no requieren otra migración o redespliegue para el alcance SN1. No significa que ya haya tráfico real medido, CTR suficiente, política definitiva, aprendizaje automático, una aplicación móvil ni evaluación estadística de relevancia.

## 4. Límite honesto

No se compartieron los conteos ni la duración exacta de la purga manual. Tampoco se compartió una fila individual de `cron.job_run_details` con `start_time`, `end_time`, `status`, duración y mensaje. La confirmación general del dueño permite registrar la función y el job como instalados y correctos, pero no escribir todavía que una ejecución automática concreta terminó `succeeded`.

La prueba visual confirmada no equivale por inferencia a una auditoría formal de accesibilidad, todos los navegadores, todos los estados de error, todas las campañas, carga y retirada de los cinco roles de asset o personalización autenticada exhaustiva.

No se registraron eventos SN nuevos como parte del cierre porque la analítica está apagada. Esto es una garantía de privacidad esperada, no una falla del motor.

## 5. Continuidad no bloqueante

### 5.1 Primera corrida natural del cron

Después de la primera ejecución programada, consultar:

```sql
select
  d.start_time,
  d.end_time,
  d.status,
  d.end_time - d.start_time as duracion,
  left(coalesce(d.return_message, ''), 160) as mensaje
from cron.job_run_details d
join cron.job j on j.jobid = d.jobid
where j.jobname = 'sn-purgar-telemetria-diario'
order by d.start_time desc
limit 10;
```

Registrar únicamente el resultado observado. Si no es `succeeded`, tratarlo como incidencia operativa; no reaplicar migraciones.

### 5.2 Política definitiva y telemetría

Cuando el dueño publique la política definitiva:

1. registrar desde Email Marketing la URL y versión exactas;
2. activar analítica desde Métricas;
3. comprobar que `tienda-eventos` devuelve `activa=true` y esa versión;
4. probar rechazo sin aceptación o con versión anterior;
5. probar aceptación vigente, un evento SN y su lectura agregada;
6. documentar el resultado sin convertir la telemetría aproximada en contabilidad.

La captura será futura y voluntaria; no reconstruirá el periodo durante el cual estuvo apagada.

### 5.3 Operación editorial

El siguiente trabajo útil no es otra migración: es configurar campañas reales con intenciones, relaciones, prioridad, ventanas y cobertura visual. Conviene completar primero `cuadrado`, `vertical` y `horizontal`; `panoramico` y `recorte` mejoran composiciones adicionales. Después se revisa manualmente la calidad de los módulos sin cambiar el algoritmo por impresiones aisladas.

### 5.4 SN1-D

SN1-D puede retomarse cuando haya una política definitiva y datos suficientes para evaluar relevancia, cobertura y CTR. Una futura aplicación debe reutilizar los contratos actuales. Cualquier cambio de reglas debe publicar una nueva `modelo_version`; no activar aprendizaje individual adicional sin una decisión y política nuevas.
