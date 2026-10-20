# PLANO · Promocionar P3 · Registro y enlace corto

**Decisión del dueño:** 20 de octubre de 2026
**Estado:** **contrato de implementación en construcción; P3 no está desplegado**
**Depende de:** P0 como contrato normativo, P1 como destino canónico y P2 como estudio aprobado.
**URL cerrada:** `https://go.magandhi.com/<codigo>`; DNS, TLS y routing todavía no están desplegados.
**Activación inicial:** `activacion_habilitada`, `redirect_habilitado` y
`conteo_habilitado` permanecen **OFF**.
**Banco automatizado P3:** pendiente; no fue solicitado ni agregado en este
corte y su ausencia no bloquea por sí sola este corte con los tres gates OFF.
Sí continúa siendo requisito antes de cerrar P3 o activar cualquier gate.
**No incluye:** atribución transaccional P4, resultados/conversión P5, Meta Ads, Pixel, gasto o publicación automática.

P3 registra enlaces propios, los resuelve mediante un redirect seguro y conserva
solo un conteo diario aproximado. Este plano especializa las decisiones de
`docs/PLANO-PROMOCIONAR-P0.md`; no relaja su taxonomía, privacidad, precedencia,
inmutabilidad o retención. Se conservan íntegros los enlaces, métricas, historial,
filtros, antiabuso, retención y controles internos definidos para P3.

Para un enlace activo, la redirección pública es inmediata y no depende del
conteo. Abrirlo no usa cookies, no crea un perfil individual y no muestra banner,
popup, modal, consentimiento ni aviso intermedio. La explicación informativa se
incorporará después a la política general y no bloquea el lanzamiento ni la
activación P3; P4 y EM7 conservan sus gates propios. Esta es una decisión de
producto y técnica, no una conclusión de asesoría jurídica. La implementación
sigue en construcción: este corte no afirma despliegue, CI ni cierre de criterios.

---

## 1. Resultado de P3

Al cerrar P3, un operador autorizado podrá crear, editar y listar desde una
campaña un borrador privado **sin código**, revisar canal/UTM/destino y activarlo
una sola vez. Ese trabajo privado sigue disponible con
`activacion_habilitada=OFF`; el gate impide pasar el borrador a público, no
prepararlo. El enlace público usará:

```text
https://go.magandhi.com/<codigo>
```

Una visita válida resolverá exclusivamente un destino interno permitido,
responderá `302` con `Cache-Control: no-store` y podrá incrementar un agregado
por enlace y fecha de Colombia. El redirect debe seguir funcionando si el
contador o la cuota fallan; medir nunca puede bloquear la navegación.

P3 no determina qué venta produjo el enlace. Guardar la referencia validada en
una intención/pedido comienza en P4. Combinar clics, sesiones, checkout, pagos,
pedidos, ingreso o conversión comienza en P5.

## 2. Decisiones cerradas

### 2.1 Dominio, código y autoridad

- Dominio público elegido: `go.magandhi.com`.
- Código de **16 caracteres Crockford base32 en minúsculas**, patrón
  `^[0-9a-hjkmnp-tv-z]{16}$`.
- **80 bits** de aleatoriedad criptográfica.
- Código público, opaco, no secuencial, único y no derivado de ids internos.
- Un código activado nunca se recicla, reasigna o cambia de destino.
- El registro server-side es la autoridad; `utm_*` continúa siendo descriptivo.

P0 dejó el dominio condicionado a una decisión posterior. Este plano cierra la
elección a favor de `go.magandhi.com`; **elegirlo no significa que DNS, TLS o
routing ya existan**.

### 2.2 Destino y redirect

- El enlace guarda una referencia interna tipada; nunca una URL libre.
- Todo borrador conserva `campana_producto_id` como campaña de origen. El
  `tipo_destino` inicial puede apuntar a la ficha del producto o a `home`; ambos
  siguen asociados a ese mismo origen.
- Para la ficha del producto, el servidor usa la ficha canónica P1 de la
  campaña de origen. Para `home`, usa la home MAGANDHI sin borrar ni sustituir
  esa asociación.
- El servidor construye `Location` desde una lista blanca versionada.
- Se rechazan `url`, `next`, `redirect`, `returnTo` y cualquier parámetro que
  intente elegir destino.
- Un enlace activo resuelto responde de inmediato **HTTP `302`** con
  **`Cache-Control: no-store`**; no espera el conteo ni una acción del visitante.
- Abrir el enlace público P3 no usa cookies ni crea estado o perfil individual.
  Jamás intercala banner, popup, modal, aviso o pantalla de consentimiento.
- Un código inexistente, mal formado o desactivado no atribuye, no cuenta y no se
  reasigna: muestra una respuesta terminal de marca MAGANDHI de enlace no
  disponible. Esa respuesta de error no es un intermedio para enlaces activos.
- El redirect ocurre aunque el incremento del contador falle o la cuota impida
  contarlo.

### 2.3 Ciclo de vida

```text
borrador -> activo -> desactivado
```

- **Borrador:** privado, sin código, editable y eliminable. Solo en este estado
  puede cambiar canal, UTM o `tipo_destino` entre ficha del producto y `home`;
  nunca pierde su campaña de origen.
- **Activo:** nace al activar de forma autorizada, recibe el código y congela
  código, campaña, tipo/destino, canal, `source`, `medium`, `campaign` y
  `content`; solo permite desactivar.
- **Desactivado:** terminal; no reactiva ni cambia de destino. Una corrección
  crea un borrador nuevo con `reemplaza_enlace_id`: debe conservar la campaña
  de origen del reemplazado, aunque puede corregir `tipo_destino`.
- Todo borrador mutable usa `actualizado_en` como token CAS de concurrencia para
  editar. Un token esperado obsoleto devuelve conflicto y no sobrescribe
  cambios; no es una `idempotency key` ni una versión numérica.
- La creación recibe `p_clave_idempotencia`, ligada al actor y al payload
  canónico. Un reintento del mismo alta devuelve el borrador ya creado; reutilizar
  la clave con otro payload se rechaza.
- La activación también es idempotente por identidad y estado del enlace: si la
  respuesta se pierde, reintentar el mismo `id` devuelve el mismo enlace activo
  y el mismo código, sin crear una segunda activación.

### 2.4 Conteo diario y cuota temporal

- Una fila agregada por `(enlace_id, fecha_colombia)`.
- Fecha calculada en `America/Bogota`, nunca con `current_date` UTC a secas.
- Incremento atómico; la interfaz lo llama siempre **clics aproximados**.
- Solo es contabilizable una navegación positiva: `GET` con
  `Sec-Fetch-Mode: navigate`, `Sec-Fetch-Dest: document` y al menos un media
  range exacto `text/html` en `Accept` cuya calidad efectiva sea válida y mayor
  que cero. Sin parámetro `q`, la calidad efectiva es `1`; si aparece, debe ser
  sintácticamente válida y cumplir `0 < q <= 1`. `q=0`, una `q` mal formada o
  fuera de rango y la ausencia de `text/html` no incrementan. La ausencia de
  cualquiera de las tres señales positivas tampoco incrementa.
- `HEAD`, `OPTIONS`, bots, crawlers, scanners, previews, prefetch, prerender y
  herramientas automáticas tampoco incrementan.
- La operación configura **una sola** cabecera IP autoritativa y comprueba que
  la infraestructura de confianza la sobrescribe. Edge no encadena cabeceras,
  no toma “la primera disponible” y no acepta fallbacks aportados por el
  cliente.
- No se persisten clics individuales, timestamps individuales, IP, referrer,
  User-Agent, `mg_vid`, sesión, cuenta o cliente.
- Cuota temporal inicial: **600 solicitudes contabilizables por hora para cada
  `hash_ip_dia`, de forma global en P3**.
- “Global” significa que la cuota se comparte entre todos los códigos: no se
  multiplica por enlace y el registro temporal **no contiene `enlace_id`**.
- Superar la cuota evita incrementos adicionales durante la ventana, pero no
  impide el `302` al destino permitido.
- El valor 600/h es inicial y temporal; cambiarlo exige una decisión documentada,
  no una modificación silenciosa.

`hash_ip_dia` usa una llave HMAC diaria derivada criptográficamente de un
secreto maestro de al menos **32 bytes**. La derivación incorpora la fecha de
Colombia y un contexto exclusivo de P3; no se guarda una colección de “sales
del día”. La IP canónica de la única cabecera operativamente verificada se
procesa solo en memoria y nunca se persiste. Ni el secreto maestro ni la llave
diaria se registran. El hash no se une con enlace, `mg_vid`, sesión, cuenta,
cliente, intención o pedido.

### 2.5 Retención

| Dato P3 | Retención | Salida |
|---|---|---|
| Hash/cuota antiabuso | Máximo 48 horas | Eliminación automática |
| Clic diario por enlace | 13 meses | Suma al total histórico no fechado y eliminación del detalle diario |
| Total histórico no fechado | Indefinido por decisión comercial | Solo acumulado, sin fechas ni identidad |
| Borrador nunca activado | Hasta eliminación del operador | Se puede eliminar |
| Enlace activado | Activo y 13 meses completos tras desactivación | Se retira receta/texto opcional; código, estado y no-reasignación permanecen |

P3 no altera la retención de eventos EM7/Resend ni la de pedidos. Tampoco
implementa todavía la visita promocional de 30 minutos: su uso transaccional se
integra en P4.

## 3. Capa SQL

La migración P3 en construcción debe ser forward y compatible. El modelo mínimo conceptual es:

```text
atribucion_enlaces
  id · codigo · campana_producto_id de origen · canal_promocion
  source · medium · campaign · content · tipo_destino · estado_enlace
  actualizado_en como token CAS de edición · clave_idempotencia de creación
  receta/texto opcional · reemplaza_enlace_id · total_historico
  creado_en · activado_en · desactivado_en · auditoria

atribucion_clics_dia
  enlace_id · fecha_colombia · total_aproximado
  índice de rollup encabezado por fecha_colombia

cuota temporal antiabuso
  hash_ip_dia · ventana_hora · conteo · expira_en
  -- nunca enlace_id, mg_vid, sesión, cuenta, cliente, IP cruda o User-Agent

promocionar_p3_config
  activacion_habilitada · redirect_habilitado · conteo_habilitado
  -- los tres nacen OFF

bitácora de gates P3 · append-only
  antes/después · actor/rol · razón · ocurrido_en
```

Contrato de datos:

1. checks para los siete canales y sus pares `source/medium` de P0;
2. normalización única de `campaign/content` y bloqueo de PII evidente;
3. `codigo` único con forma Crockford; colisión = regenerar, nunca truncar ni
   reutilizar;
4. transiciones de estado y congelación impuestas server-side, no por botones;
5. todo borrador conserva una campaña de origen no nula; su destino tipado puede
   ser ficha del producto u home, y un reemplazo conserva ese origen aunque
   corrija el tipo;
6. `actualizado_en` funciona como token CAS obligatorio al editar un borrador;
   un valor esperado obsoleto no escribe. No es una clave idempotente ni una
   versión numérica;
7. la creación usa una clave de idempotencia ligada al actor y al payload
   canónico; el mismo reintento devuelve el borrador existente y un payload
   diferente con esa clave se rechaza. La activación es idempotente por `id` y
   estado: reintentar el mismo enlace ya activo devuelve el mismo id, estado y
   código, incluso si se perdió la respuesta original;
8. incremento atómico del agregado diario y rollup de retención idempotente;
   `atribucion_clics_dia` dispone de un índice encabezado por
   `fecha_colombia` para el corte global por fecha;
9. cuota 600/h atómica por hash diario global, sin vínculo al enlace;
10. tablas privadas con RLS/grants mínimos; ninguna escritura anónima directa;
11. funciones de administración solo para personal autorizado de Marketing; el
    CRUD/listado privado de borradores no depende de `activacion_habilitada`;
12. configuración persistida con `activacion_habilitada`,
    `redirect_habilitado` y `conteo_habilitado`, todos inicialmente OFF y con
    capacidades independientes;
13. cada cambio de gate inserta en la misma transacción una fila de bitácora
    append-only con antes/después, actor/rol, razón y tiempo; la bitácora no
    admite `UPDATE`, `DELETE` ni `TRUNCATE`;
14. limpieza automática mediante un cron horario nominal dirigido a
    `current_database()` para cuota antes de 48 horas y detalle diario al
    cumplir 13 meses. Su último run se identifica por `jobid` y debe pertenecer
    a ese mismo job de esa base; coincidir solo por nombre no acredita salud;
15. encender `activacion_habilitada` exige comprobar ese cron instalado, su
    último run correcto y cero filas vencidas pendientes, además de preflight,
    postflight y matriz de privilegios;
16. apagar `conteo_habilitado` no modifica ni apaga
    `redirect_habilitado`.

P3 no añade `atribucion_enlace_id` a intención o pedido. Esa FK, su revalidación
y su idempotencia son P4.

## 4. Capa Edge y routing

P3 necesita dos fronteras separadas:

### 4.1 Administración autenticada

- crear, editar, eliminar y listar borradores privados aun con
  `activacion_habilitada=OFF`; el borrador no tiene código;
- aplicar CAS con `actualizado_en` esperado a cada edición de borrador y
  mostrar conflicto sin sobrescritura silenciosa;
- activar solo con `activacion_habilitada=ON`, mediante generación
  criptográfica, comprobación de unicidad e idempotencia por id/estado ante
  reintento o respuesta perdida;
- desactivar sin borrar ni reactivar;
- crear reemplazos que conserven la campaña de origen y puedan corregir el tipo
  de destino;
- listar enlaces de la campaña y su agregado aproximado;
- derivar `source/medium`, normalizar UTM y resolver destino sin confiar en el
  navegador;
- fallar cerrado en permisos y destino.

No se concede DML directo desde la UI. La identidad del operador y la auditoría
se derivan de la sesión interna válida.

### 4.2 Redirect público

Orden obligatorio para una solicitud:

1. leer el código únicamente desde el path y validar su forma;
2. comprobar `redirect_habilitado`; si está OFF, no resolver tráfico productivo
   y mostrar la respuesta de marca;
3. resolver un registro activo;
4. construir el destino tipado desde la lista blanca server-side y la campaña
   de origen;
5. responder de inmediato el `302` válido con `Location` permitido y
   `Cache-Control: no-store`, sin cookies, perfil individual, interfaz pública o
   solicitud de consentimiento;
6. sin bloquear ni retrasar esa respuesta, y solo con
   `conteo_habilitado=ON`, aceptar para conteo exclusivamente un `GET` con las
   tres señales positivas: `Sec-Fetch-Mode: navigate`,
   `Sec-Fetch-Dest: document` y un media range exacto `text/html` en `Accept`
   con calidad efectiva válida mayor que cero (`q` ausente equivale a `1`;
   `q=0`, mal formada o fuera de `0 < q <= 1` no cuenta);
7. leer únicamente la cabecera IP configurada y verificada por operación; si
   falta o no es confiable, no contar y no probar cabeceras alternativas;
8. derivar la llave HMAC diaria desde el secreto maestro de al menos 32 bytes,
   calcular `hash_ip_dia`, aplicar la cuota global 600/h e incrementar
   atómicamente el día Colombia cuando corresponda;
9. si cualquiera de los pasos 6–8 falla, vence o no puede completarse sin
   bloquear, omitir ese incremento sin alterar la redirección ya resuelta.

El paso 5 no depende del éxito de 6–8. Apagar o fallar el conteo no cambia
`redirect_habilitado`. No se registra IP cruda ni se emite un evento individual.
Códigos inválidos/desactivados llegan a una respuesta terminal de marca y nunca
a un destino alternativo improvisado; esa respuesta no es un intermedio para un
enlace activo.

Antes de activar se medirán explícitamente métodos, navegación positiva, la
cabecera IP única y su cadena de confianza, CORS, caché, códigos
inválidos/desactivados, filtros, cuota, derivación HMAC, falla del contador y
ausencia de open redirect. La existencia de una Edge Function en Git no prueba
que esa versión esté desplegada.

## 5. Capa UI

Esta capa pertenece exclusivamente al back-office autenticado y conserva todos
sus controles internos. El redirect público de un enlace activo no atraviesa
esta UI ni presenta al visitante banner, popup, modal, aviso intermedio o
consentimiento.

Campañas deberá incorporar P3 sin romper el estudio P2:

- P2 seguirá produciendo enlace largo y piezas cuando los tres gates P3 estén
  OFF, cuando `redirect_habilitado` se apague o cuando P3 no pueda acreditarse;
- al abrir, recuperar foco/visibilidad y después de mutaciones, la UI refrescará
  tanto la configuración como el historial/estado autoritativo de enlaces. El
  polling hará esas dos lecturas mientras la superficie P3 esté abierta; no
  bastará con refrescar solo la configuración global;
- una sección separada permitirá crear, editar, eliminar y listar el borrador
  privado desde campaña, canal y UTM ya revisados, incluso con
  `activacion_habilitada=OFF` y siempre sin código;
- el destino se elegirá entre ficha del producto y home MAGANDHI, no mediante
  un campo URL; cualquiera de los dos conservará la campaña de origen;
- las ediciones enviarán `actualizado_en` como token CAS esperado; ante
  conflicto, la UI recargará y pedirá resolverlo en vez de pisar datos;
- si una mutación termina en timeout, cancelación, error de transporte o una
  respuesta que no permite saber si el servidor escribió, la UI no inferirá el
  resultado ni reintentará a ciegas: refrescará el historial autoritativo antes
  de presentar estado final u ofrecer otro intento;
- antes de activar se mostrarán los campos que quedarán congelados;
- `activacion_habilitada` controlará solo la transición a público. La creación
  reutilizará su clave de idempotencia si la respuesta se pierde; un reintento de
  activación del mismo `id` devolverá el mismo código;
- después de activar se podrá mostrar el enlace corto y solo quedará la acción
  `Desactivar` mientras el redirect esté disponible;
- antes de **cada** distribución —copiar, QR, Web Share, PNG o cualquier otra
  exportación— una comprobación con plazo total máximo de **3 segundos**
  revalidará la configuración y, en la autoridad server-side, que el enlace
  concreto siga activo y resoluble hacia su destino permitido. Un
  `estado_enlace='activo'` conservado localmente no basta para distribuirlo;
- timeout, cancelación, error, respuesta inválida, configuración no disponible,
  `redirect_habilitado=OFF`, enlace no activo o resolución no autoritativa dentro
  de ese plazo impedirán distribuir el corto y continuarán explícitamente con
  el enlace largo P2, sin dejar la acción esperando;
- una corrección creará un borrador nuevo, referenciará el enlace reemplazado,
  conservará la campaña de origen y podrá corregir el tipo de destino;
- el total visible se rotulará `Clics aproximados` y explicará que no representa
  personas;
- estados de carga, error, vacío y cada gate OFF serán explícitos y accesibles;
- no se mostrarán sesiones, compras, ingresos ni conversión en P3.

No se pierde el enlace largo seguro si P3 falla o si se apaga el redirect. El
estudio no debe depender del redirector para seguir siendo útil.

## 6. Capa de operación

Orden mínimo de despliegue futuro:

1. cerrar la implementación en una rama/PR; el banco automatizado P3 puede
   seguir pendiente en este corte con todos los gates OFF, pero debe agregarse,
   ejecutarse y archivarse antes de cerrar P3 o activar cualquier gate;
2. revisar diff, permisos, privacidad, retención y plan de reversa;
3. fusionar el código; **este paso todavía no despliega P3**;
4. ejecutar preflight de solo lectura;
5. aplicar una vez la migración forward por el método manual vigente;
6. ejecutar postflight y matriz de permisos;
7. instalar el cron horario de retención dirigido a `current_database()` y
   comprobar que su último run correcto se vincula por `jobid` al job nominal de
   esa misma base, además de salud y cero filas vencidas pendientes;
8. desplegar las funciones Edge y verificar su versión real;
9. configurar y comprobar DNS, TLS y routing de `go.magandhi.com`;
10. confirmar en producción los tres gates P3 OFF;
11. ejecutar sondas controladas de código, lista blanca, `302`, `no-store`,
    navegación positiva —incluidos `text/html` sin `q`, con `q>0`, `q=0` y `q`
    inválida—, cabecera IP única, HMAC diario, cuota, fecha Colombia, fallas,
    retención y degradación a P2 dentro de 3 segundos;
12. solo con banco P3 archivado, infraestructura y sondas medidas, cron horario
    sano en la base actual y cero vencidos, activar gates en una ventana
    aprobada, medir producción y documentar el resultado.

La explicación del conteo aproximado, el procesamiento antiabuso temporal y la
retención se incorporará después a la política general. Es una tarea informativa
fuera del orden de activación: no es prerrequisito, gate ni autorización de P3 y
no introduce interfaz alguna al visitante.

El banco automatizado P3 **no fue solicitado ni agregado en este corte** y
permanece pendiente. Su ausencia no bloquea por sí sola este corte documental y
de implementación con los tres gates OFF; sí bloquea declarar P3 cerrado o
activar cualquiera de sus gates. Este plano no aporta evidencia de CI, SQL
aplicado, Edge desplegada, DNS/TLS configurado, routing activo o feature gate
ON. Cada capa requiere evidencia independiente. No se crea relevo de cierre P3
hasta que exista despliegue y medición reales.

Si la escritura del contador falla, se mantiene el redirect y se alerta la
operación sin inventar datos. Si falla la resolución segura o la lista blanca,
el enlace falla cerrado hacia la respuesta de marca; nunca acepta un destino del
cliente como recuperación.

## 7. Feature gates

Los tres nombres contractuales son fijos y su estado inicial es OFF:

| Gate | Estado inicial | Semántica mientras está OFF |
|---|---|---|
| `activacion_habilitada` | OFF | Permite crear, editar, eliminar y listar borradores privados sin código; impide asignar código y pasar a `activo` |
| `redirect_habilitado` | OFF | Impide resolver códigos como tráfico productivo; la UI usa la salida larga P2 |
| `conteo_habilitado` | OFF | Impide incrementar clics diarios o crear/actualizar cuota temporal; no cambia el redirect |

Ningún gate se enciende por fusionar código. Cada transición escribe una fila en
la bitácora append-only con valor anterior/nuevo, actor/rol, razón y tiempo. No
se reescribe, borra ni trunca esa historia.

Encender `activacion_habilitada` requiere infraestructura medida —incluidos
DNS, TLS y routing—, banco P3 ejecutado y archivado, postflight correcto, sondas
verdes, cron horario dirigido a `current_database()` cuyo último run correcto
pertenezca por `jobid` a ese job de esa base, cero filas vencidas pendientes y
decisión explícita del dueño. La operación debe comprobar esas condiciones, no
inferirlas de la configuración. Publicar la política general o pedir
consentimiento al visitante no son condiciones para este ni para ningún gate P3.

Apagar `activacion_habilitada` no bloquea el trabajo privado ni invalida enlaces
existentes; su resolución depende únicamente de `redirect_habilitado`. Apagar
`conteo_habilitado` no apaga ni modifica un redirect aprobado. Apagar
`redirect_habilitado` no altera el estado almacenado del enlace, pero corta el
redirect productivo. El polling debe releer tanto configuración como
historial/estado autoritativo; además, cada distribución debe revalidar ambos y
la resolubilidad dentro de 3 segundos, sin confiar en un activo local, y degradar
a P2 ante timeout o falla. La reversa debe probar la respuesta de marca y la
ausencia de redirección abierta antes de cualquier activación.

## 8. Riesgos y candados

| Riesgo | Candado P3 |
|---|---|
| Open redirect o phishing | referencia interna + lista blanca server-side; ignorar parámetros URL |
| Código predecible o colisión | 80 bits criptográficos + unicidad + regeneración |
| Reasignación de un enlace usado | ciclo terminal y código reservado para siempre |
| Alta o activación con respuesta perdida | crear reutiliza la clave ligada a actor/payload; activar el mismo `id` devuelve el mismo enlace/código |
| Edición concurrente pisa cambios | `actualizado_en` es token CAS de edición, no versión numérica; valor obsoleto falla sin escribir |
| Mutación con resultado incierto | releer historial autoritativo antes de inferir estado o reintentar |
| Reemplazo cambia de campaña | origen inmutable; solo puede corregir el tipo ficha/home |
| Redirect cacheado después de desactivar | `302` + `Cache-Control: no-store` |
| Bot presentado como persona | navegación positiva `navigate`/`document` + `text/html` con calidad efectiva válida `> 0` + filtros + rótulo `clics aproximados` |
| Cabecera IP falsificada o ambigua | una sola cabecera elegida y verificada por operación; sin fallbacks |
| Secreto diario débil o acumulado | HMAC diario derivado de secreto maestro de al menos 32 bytes |
| Multiplicar la cuota por enlace | hash diario global sin `enlace_id` |
| Cookies o perfil individual en P3 | el flujo público no lee ni escribe cookies, no crea identificador o evento individual y no se une con `mg_vid`/sesión/cuenta |
| Aviso o consentimiento interrumpe el enlace | `302` inmediato sin banner, popup, modal, aviso intermedio ni acción del visitante; la UI P3 permanece interna |
| Día incorrecto entre 19:00 y 00:00 Colombia | `America/Bogota`, no `current_date` UTC |
| Limpieza ejecutada en otra base | job nominal dirigido a `current_database()` y último run unido por `jobid` a ese job de esa base |
| Rollup crece por barrido global | índice de `atribucion_clics_dia` encabezado por `fecha_colombia` |
| Contador caído bloquea campaña | redirect independiente del incremento |
| Corto local obsoleto o lectura suspendida | antes de cada distribución, configuración + enlace/resolubilidad autoritativos con plazo máximo de 3 s; toda falla usa P2 |
| Polling solo refresca gates | refresca configuración e historial/estado autoritativo mientras P3 esté abierto |
| Git confundido con producción | evidencia separada de SQL, Edge, DNS, gates y HTTP |
| P3 invade ventas o métricas | P4/P5 separados y sin FK/panel en este tramo |

## 9. Criterios de cierre

P3 permanece **en construcción** hasta que todos estén completos y exista
aprobación explícita del dueño:

### Implementación y seguridad

- [ ] Esquema forward con checks, RLS/grants mínimos, los tres gates OFF y
      bitácora de gates append-only.
- [ ] CRUD/listado privado funciona con `activacion_habilitada=OFF`, siempre con
      borradores sin código.
- [ ] Todo borrador conserva campaña de origen y admite destino tipado ficha u
      home; el reemplazo puede corregir tipo sin cambiar origen.
- [ ] Edición de borrador usa `actualizado_en` como token CAS de edición y
      rechaza un valor obsoleto sin sobrescribir; no se presenta como versión
      numérica ni clave idempotente.
- [ ] Creación idempotente devuelve el mismo borrador al reintentar la misma
      clave/actor/payload y rechaza reutilizarla con otro payload.
- [ ] Activación idempotente devuelve el mismo enlace/código al reintentar el
      mismo `id` después de perder una respuesta.
- [ ] Código Crockford de 16 caracteres/80 bits generado y único server-side.
- [ ] Ciclo `borrador -> activo -> desactivado` e inmutabilidad impuestos en base.
- [ ] Destino construido solo desde lista blanca; pruebas negativas de open redirect.
- [ ] Redirect activo responde `302` + `Cache-Control: no-store`.
- [ ] Código inválido/desactivado no cuenta, no atribuye y muestra respuesta MAGANDHI.
- [ ] Falla de contador o cuota no bloquea un destino válido.

### Conteo y privacidad

- [ ] Incremento atómico por enlace y fecha `America/Bogota`.
- [ ] Solo `GET` con `navigate`, `document` y un media range `text/html` con
      calidad efectiva válida `> 0` puede contar (`q` ausente = `1`); `q=0`,
      inválida o fuera de rango, HEAD/OPTIONS, bots, previews, prefetch y
      herramientas automáticas no cuentan.
- [ ] Operación verifica una sola cabecera IP autoritativa y Edge no usa fallbacks.
- [ ] Llave HMAC diaria deriva de secreto maestro de al menos 32 bytes; secreto,
      llave e IP cruda nunca se persisten.
- [ ] Cuota inicial 600/h global por `hash_ip_dia`, sin `enlace_id`, comprobada.
- [ ] Hash sin unión y purga antes de 48 horas comprobados.
- [ ] Detalle diario conserva 13 meses, cuenta con índice encabezado por
      `fecha_colombia` y luego pasa a total no fechado de forma idempotente.
- [ ] UI y documentación dicen `clics aproximados`, nunca personas o únicos.

### UI, operación y producción

- [ ] P2 sigue funcionando con los tres gates P3 OFF, ante falla de P3 y al
      apagar solo `redirect_habilitado`.
- [ ] UI refresca configuración **e** historial/estado autoritativo al abrir,
      recuperar foco/visibilidad, después de mutaciones y durante polling.
- [ ] Antes de cada distribución, UI revalida configuración, enlace activo y
      resolubilidad autoritativa con plazo total máximo de 3 segundos; un activo
      local no basta y timeout/falla/respuesta inválida degrada sin espera al
      enlace largo P2.
- [ ] Una mutación con resultado incierto refresca historial autoritativo antes
      de inferir resultado u ofrecer reintento.
- [ ] UI cubre borrador privado, CAS/conflicto, activación idempotente por el
      mismo `id`, campos congelados, desactivación, reemplazo y errores.
- [ ] Apertura pública de un enlace activo redirige de inmediato, sin cookies,
      perfil individual, banner, popup, modal, aviso intermedio o consentimiento;
      conteo, cuota o métricas nunca bloquean la salida.
- [ ] Cron horario de retención instalado para `current_database()`; su último
      run correcto está unido por `jobid` al job nominal de esa misma base y el
      postflight informa cero filas vencidas antes de habilitar activación.
- [ ] Preflight, postflight, matriz y banco automatizado P3 ejecutados con
      resultados archivados.
- [ ] SQL aplicado, Edge desplegada y versión productiva verificados por separado.
- [ ] DNS, TLS y routing de `go.magandhi.com` comprobados en producción.
- [ ] Gates nacen OFF y toda transición queda en bitácora append-only.
- [ ] HTTP productivo verifica código activo, inválido, desactivado, caché y lista blanca.
- [ ] Retención/limpieza y reversa operativa quedan programadas y medidas.
- [ ] P4/P5 continúan fuera del diff y no se afirma atribución o conversión.
- [ ] Tras medir despliegue, plano de fase y contexto incorporan la evidencia
      productiva; solo entonces se crea un relevo de cierre P3.

**Tarea informativa posterior y no bloqueante:** la política general incorporará
la explicación del conteo aproximado, el procesamiento antiabuso temporal y la
retención. No es un criterio de cierre o activación P3 y no habilita ninguna UI
para el visitante.

**Estado de este corte:** implementación y contrato en construcción; los tres
gates permanecen OFF y ningún criterio se marca como completo. El banco
automatizado P3 sigue pendiente porque no fue solicitado ni agregado; su
ausencia no bloquea por sí sola este corte OFF, pero sí cualquier cierre o
activación posterior. Este corte no acredita SQL aplicado, Edge, DNS, TLS,
routing, despliegue o CI P3.
