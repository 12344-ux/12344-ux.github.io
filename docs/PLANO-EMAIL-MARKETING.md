# PLANO · Email marketing + Análisis de clúster + Analítica propia

**Corte:** 8 de octubre de 2026 · **Estado:** aprobado por el dueño. EM1–EM5 en producción; **EM5.1 construido (pendiente de aplicar)**. Ver §11 (estado real y relevo).
**Piezas relacionadas:** `docs/PLANO-CORREO.md` (correos del pedido, ya en producción), `docs/PLANO-OPINIONES.md`, `docs/PLANO-VENTAS.md`.

---

## 0. Qué se construye y por qué así

Un software propio de email marketing **conectado a los datos reales de MAGANDHI**: ventas, opiniones, campañas de producto y, más adelante, comportamiento en la tienda. Ese es el diferenciador frente a Mailchimp o el propio Resend, que no saben qué compró cada cliente, cuánto pagó ni cómo calificó.

Tres piezas que se alimentan entre sí:

```
                ┌───────────────── DATOS PROPIOS ─────────────────┐
                │ Ventas · Opiniones · Campañas · Analítica tienda │
                └──────────────┬──────────────────────────────────┘
                               │  perfil por cliente (features)
                ┌──────────────▼──────────────┐
                │  ANÁLISIS DE CLÚSTER         │  Marketing Project
                │  (escupe grupos, el humano   │
                │   los lee y decide)          │
                └──────────────┬──────────────┘
                               │  "Guardar como segmento"
                ┌──────────────▼──────────────┐
                │  EMAIL MARKETING             │  Marketing → Email marketing
                │  contactos · segmentos ·     │
                │  campañas · resultados       │
                └──────────────┬──────────────┘
                               │  Broadcasts (news.magandhi.com)
                           RESEND ──► bandeja del cliente
                               │  webhook: entregado, clic, baja, rebote
                               └──► vuelve a nuestra base → resultados y
                                    ventas generadas → vuelve al perfil
```

**El ciclo se cierra:** la respuesta a cada campaña (clics, compras) vuelve al perfil del cliente y mejora el siguiente análisis.

### Principios no negociables

1. **Nuestra base es la fuente de verdad.** Resend solo recibe la copia mínima para entregar (correo, nombre, segmento).
2. **Solo recibe marketing quien lo autorizó, con prueba.** Un clúster puede incluir a todos los clientes como *análisis*, pero la audiencia de una campaña es siempre `segmento ∩ suscritos`.
3. **El botón de enviar lo pulsa una persona.** Kiro prepara borradores; un envío masivo nunca sale sin confirmación humana explícita.
4. **Impulse entrega datos, no adivina.** Igual que el resto de Marketing Project: el clúster muestra grupos con su tamaño, su calidad y su explicación. Con pocos datos lo dice en lugar de inventar patrones.
5. **Ética de datos:** primera parte (sin píxeles de terceros), sin vender ni compartir datos, sin inferir categorías sensibles, con retención limitada. Es la misma línea firme del proyecto.
6. **Clonable para Impulse.** Nada amarrado a MAGANDHI: dominio, remitente y textos de consentimiento son configuración.

---

## 1. Prerrequisitos (no bloquean construir; sí bloquean activar)

| Prerrequisito | Bloquea | Responsable |
|---|---|---|
| **Política de tratamiento de datos** publicada en magandhi.com (Ley 1581) | Captura pública de contactos (EM6) | Dueño |
| **Sección de cookies/analítica** en la política + aviso de consentimiento | Analítica propia (EM7) | Dueño + Kiro |
| Dominio `news.magandhi.com` verificado en Resend | Envío de campañas (EM4) | Dueño (guía como la de `updates`) |
| **D3 · permisos granulares** | Dar acceso a un no-admin | Kiro |

Mientras falte la política se puede construir y probar todo. La captura pública y la analítica quedan **apagadas** con un interruptor en configuración.

---

## 2. Ubicación y permisos

- **Panel:** Marketing → **Email marketing**, al lado de Campañas y Marketing Project. Mismo azul del back-office, sin color nuevo.
- **Clúster:** Marketing → Marketing Project → **Análisis de clúster** (reemplaza el hueco «Próximamente»).
- **Módulo propio `email_marketing`** (helper `tiene_acceso_email_marketing()`). La lista de contactos es información personal (PII); separarla desde el inicio deja listo D3. Admin la ve por defecto, como hoy.
- El clúster usa `tiene_acceso_marketing()`, igual que el resto de Marketing Project. Ve perfiles agregados y no necesita correos.

---

## 3. Modelo de datos (prefijo `em_`; migraciones forward)

### 3.1 Contactos y consentimiento

**`em_contactos`**: una fila por correo.

| Campo | Para qué |
|---|---|
| `id`, `correo`, `correo_norm` (único) | Identidad |
| `customer_id` → `clientes` (nullable) | Une el contacto a sus compras. Se enlaza solo si el correo coincide con un cliente |
| `nombre` | Personalización `{nombre}` |
| `estado` | `pendiente_confirmacion` · `suscrito` · `baja` · `rebotado` · `queja` |
| `fuente` | `manual` · `formulario_tienda` · `casilla_checkout` · `importacion_con_evidencia` |
| `consentimiento_en`, `consentimiento_texto`, `politica_version` | **Prueba legal:** qué texto exacto aceptó, bajo qué versión de la política y cuándo |
| `confirmado_en` | Doble confirmación (doble opt-in) |
| `evidencia` (jsonb) | Para altas manuales: "autorizó por WhatsApp el 8-oct, captura guardada por X" |
| `baja_en`, `baja_motivo` | Baja |
| `resend_contact_id`, `sincronizado_en` | Espejo en Resend |
| `creado`, `creado_por` | Auditoría |

**`em_consentimiento_bitacora`** (append-only): cada alta, confirmación, baja o cambio de estado, con actor y momento. Nada se borra; la baja **no elimina** el registro, porque hay que poder demostrar que se respetó.

**Supresión:** un contacto en `baja`, `rebotado` o `queja` queda fuera de todo envío futuro, aunque esté en un segmento.

### 3.2 Segmentos

**`em_segmentos`**: `id`, `nombre`, `tipo` (`reglas` · `cluster` · `manual`), `definicion` (jsonb), `dinamico` (bool), `origen_cluster_id`, `resend_segment_id`, `creado_por`.

- **Reglas (dinámico):** se recalcula al enviar. Ejemplo: `{ "y": [ {"campo":"ciudad","op":"=","valor":"Tunja"}, {"campo":"dias_desde_ultima_compra","op":">","valor":60} ] }`.
- **Clúster (snapshot):** se congela la lista de miembros del análisis guardado, para que la campaña sea reproducible y explicable.
- **Manual:** elegir contactos a mano.

**`em_segmento_miembros`** (para snapshots): `segmento_id`, `customer_id`, `contacto_id`, `agregado_en`.

### 3.3 Campañas

**`em_campanas`**

| Campo | Para qué |
|---|---|
| `estado` | `borrador` → `programada` → `enviando` → `enviada` · `cancelada` · `fallida` |
| `nombre_interno`, `asunto`, `preheader` | |
| `contenido` (jsonb) | Bloques estructurados (ver 3.4) |
| `segmento_id`, `tema` | A quién y bajo qué tema de preferencia ("Novedades", "Ofertas") |
| `audiencia_n` | Tamaño **congelado** al confirmar ("vas a enviar a 47") |
| `programada_para`, `enviada_en` | |
| `utm_campaign` | Etiqueta para atribuir ventas |
| `preparada_por`, `confirmada_por`, `confirmada_en` | Quién la armó (puede ser Kiro vía borrador) y **quién pulsó enviar** |
| `resend_broadcast_id` | |

### 3.4 Editor estructurado de bloques

Sin arrastrar y soltar en la versión 1; los bloques van en orden y se reordenan con flechas:

- **Encabezado de marca:** fijo, con el mismo diseño de los correos del pedido.
- **Título** · **Texto** · **Imagen** (del bucket `campanas`, ≤ 1600 px) · **Botón** (un solo botón principal, por la lección de entregabilidad).
- **Producto destacado** ⭐: se elige un producto publicado de **Campañas** y trae solo foto, nombre, precio y enlace a su ficha. Es una conexión directa con lo que ya existe.
- **Separador** · **Pie legal** (fijo: dirección, por qué lo recibe y enlace de baja `{{{RESEND_UNSUBSCRIBE_URL}}}`).

Variables: `{nombre}` con respaldo ("Hola" si no hay nombre). La vista previa en computador y celular la genera la **misma** función que envía, como en los correos del pedido, para que lo que ves sea lo que llega.

### 3.5 Eventos y resultados

**`em_eventos`**: un evento por fila, llegado por webhook. Campos: `svix_id` (único, para idempotencia: Resend repite el mismo `svix-id` en cada reintento), `tipo` (`entregado`, `rebote`, `queja`, `apertura`, `clic`, `baja`), `campana_id`, `contacto_id`, `enlace`, `cuando`, `payload` mínimo.

**Ventas generadas (atribución).** Vista `em_campana_resultados`:
- **Web (desde Wompi F2):** cada enlace de campaña lleva `utm_campaign`. La tienda lo guarda en la intención de pago, así que la atribución es exacta.
- **Manual:** un pedido del mismo cliente en los **7 días** siguientes a un **clic** suyo en la campaña cuenta como "atribuido (aproximado)". Se rotula así, igual que Ranking distingue real, mixto y estimado.

Métricas por campaña: enviados, entregados, rebotes, bajas, clics (únicos), aperturas (**marcadas como aproximadas**), pedidos y valor atribuidos.

### 3.6 Correos de seguimiento (los del pedido)

Sección pequeña **«Correos de seguimiento enviados»** dentro de Email marketing: el historial de `correo_envios`, de solo lectura. En el mismo tramo se **retira** `ventas/correos/`. Los textos siguen en `correo_plantillas` y se cambian con un SQL que entrega Kiro.

---

## 4. Análisis de clúster (Marketing Project)

### 4.1 Cómo funciona (filosofía «escupe datos»)

1. Eliges qué **variables** usar (casillas agrupadas) y el periodo.
2. El sistema arma un **perfil por cliente**, normaliza las variables y busca grupos con **k-means++**. Usa semilla fija, así que con los mismos datos siempre da lo mismo.
3. Prueba de 2 a 6 grupos y sugiere el número con mejor **calidad (silueta)**. Tú puedes forzar otro.
4. Muestra cada grupo con:
   - tamaño (N y %);
   - su **retrato en palabras**, generado del centroide (*"compran poco pero caro, califican alto, Tunja, compran de noche"*);
   - una tabla de promedios contra el promedio general;
   - los clientes que lo componen.
5. Muestra la calidad global del agrupamiento con un semáforo (buena, débil o sin estructura).
6. Ofrece **Exportar** (CSV) y **Guardar como segmento** (snapshot → Email marketing).

### 4.2 Honestidad con pocos datos (regla dura)

- Con **menos de 30 clientes** con compras, el análisis corre pero se muestra como **«Exploratorio: muy pocos datos, los grupos pueden ser casualidad»**.
- Con **menos de 10**, no agrupa: muestra solo la tabla de perfiles.
- Si la silueta es menor a 0,25: **«No se encontró una estructura clara: los clientes se parecen entre sí»**. Es una respuesta válida, no un error.
- Cada variable muestra su **cobertura** ("Estrellas: 6 de 40 clientes tienen opinión"). Las variables con poca cobertura se pueden excluir.

### 4.3 Variables disponibles (perfil por cliente)

Se calculan en el servidor con un RPC `mk_perfiles_clientes(desde, hasta)`, security definer y guardado por `tiene_acceso_marketing()`. Devuelve **un perfil por cliente sin correo ni teléfono**, solo un id interno; el análisis no necesita datos de contacto.

| Grupo | Variables | Fuente |
|---|---|---|
| **Valor (RFM)** | días desde la última compra · número de pedidos · gasto total · ticket promedio | `pedidos` no anulados |
| **Precio** | precio unitario mínimo, máximo y promedio pagado · % de compras a precio rebajado frente al precio de lista | `pedido_items` vs `productos.precio_venta` |
| **Surtido** | número de productos distintos · categoría dominante · % del gasto por categoría | `pedido_items` → `campana_producto.categoria` |
| **Opiniones** | estrellas promedio dadas · número de opiniones · % de compras opinadas · días entre entrega y opinión | `opiniones` (por `pedido_id` → cliente) |
| **Geografía** | ciudad · departamento · local (Tunja) o nacional | snapshot de dirección del pedido |
| **Tiempo** | día de la semana y franja horaria de compra · días entre compras | `pedidos` (ver 4.4) |
| **Canal** | % manual / web | `pedidos.canal` |
| **Respuesta a email** ✅ EM5.1 | suscrito sí/no · campañas recibidas · % de campañas con clic · clics en los últimos 90 días · días desde su último clic · compras atribuidas (sin aperturas: son aproximadas). NULL = nunca recibió una campaña | `em_contactos`, `em_campana_destinatarios`, `em_eventos` |
| **Comportamiento web** *(EM7)* | visitas · productos vistos · franja horaria de navegación · vistas antes de comprar | analítica propia |

Las variables de texto (ciudad, categoría) se convierten en indicadores 0/1, y todas se escalan para que ninguna domine por tener números grandes. Las opiniones se usan para **entender**, no para presionar: un grupo de calificaciones bajas apunta a "recuperar con un mejor servicio", nunca a "insistir con más correos".

### 4.4 Hora de compra: no necesita cookies

La hora del pedido ya existe en `pedidos.creado`, pero con un matiz:
- **Pedidos web (desde F2):** la hora es exacta, porque es el pago aprobado.
- **Pedidos manuales:** `creado` es la hora en que **lo registraste**, no la hora en que el cliente decidió. Se rotulan como «hora aproximada» y se pueden excluir. Opcional: un campo «hora de la venta» en Registrar pedido para hacerla exacta.

Las cookies agregan algo distinto: el comportamiento **antes** de comprar (qué miró, cuándo navega y qué no compró).

---

## 5. Analítica propia de la tienda (EM7, tipo cookies, primera parte)

### 5.1 Qué registra

Eventos mínimos: `pagina_vista`, `producto_visto`, `clic_comprar`, `checkout_iniciado`, `compra` (desde F2), `llegada_desde_campana`. Cada evento lleva un **id de visitante aleatorio** (sin nombre ni correo), la página o el slug, la hora y el origen (campaña, Instagram, directo).

### 5.2 Cómo, sin comprometer seguridad ni privacidad

- Un script propio y liviano en la tienda envía los eventos a una Edge Function pública `tienda-eventos`, que valida, limita la frecuencia por IP (la IP **no** se guarda, solo un hash diario), filtra bots y escribe en `tienda_eventos`. Sin píxeles de Meta ni de Google.
- **Solo después de aceptar** el aviso de analítica. Quien no acepta navega igual, sin registro.
- **Unión con un cliente** solo cuando la persona se identifica por sí misma: entra desde un correo de campaña (con un token opaco por envío) o compra en la web (F2 une el visitante con el pedido).
- **Retención:** eventos crudos 13 meses; después, solo agregados.
- Lo que alimenta: variables de comportamiento para el clúster, «hora pico de navegación» y la base de las futuras **recomendaciones** ("viste este producto").

---

## 6. Conexiones con Resend

| Pieza | Qué hace | Detalle |
|---|---|---|
| Dominio `news.magandhi.com` | Remitente de campañas | Reputación separada de `updates`. **Rastreo de clics encendido** aquí (no hay códigos secretos); aperturas encendidas pero rotuladas como aproximadas |
| Edge Function `em-sincronizar` | Crea o actualiza contactos y los pone en el segmento de Resend de la campaña | Respeta el límite de 10 peticiones por segundo; reintentos |
| Edge Function `em-campana` | Modos `vista` · `prueba` · `enviar` · `programar` · `cancelar` | `enviar` exige `confirmacion = audiencia_n` (lo que el humano vio) y la sesión de un usuario con módulo. Usa la API de *Broadcasts* |
| Edge Function `em-webhook` | Recibe entregado, clic, rebote, queja, baja y apertura | **Verifica la firma** (Svix, secreto `whsec_`), es idempotente por id de evento y actualiza estados. El plan gratis tiene **1 endpoint**: este mismo atiende también los rebotes de `updates` |
| Edge Functions públicas `em-suscribir` / `em-confirmar` | Formulario de la tienda + doble confirmación | Limitadas por IP, nunca revelan si un correo ya existe, el token se guarda como hash y vence a las 48 h |

**Costos (plan gratis):** marketing gratis hasta 1.000 contactos con envíos ilimitados (no gasta el cupo de los correos del pedido). Los correos de confirmación de suscripción sí gastan del cupo de 100 al día.

**Seguridad:** llaves solo en Secrets. La llave actual `RESEND_API_KEY` sigue con *Sending access* y solo para los correos del pedido. Contactos y Broadcasts exigen una llave con más permisos, así que el marketing usa **otra llave** (`RESEND_MARKETING_API_KEY`) que solo leen las funciones `em-*`: si una se filtra, la otra no queda expuesta. Nunca service_role en el navegador, cero acceso anon a `em_*`. Las únicas superficies públicas nuevas son las Edge Functions de suscripción y eventos, sin lectura.

---

## 7. Pantallas (Marketing → Email marketing)

1. **Resumen:** suscritos y su crecimiento, últimas campañas con resultados, ventas atribuidas del mes, salud de la lista (rebotes y quejas contra los límites de Resend).
2. **Contactos:** lista con filtros por estado y fuente; ficha con la prueba del consentimiento, la bitácora y las campañas recibidas; **alta manual con evidencia obligatoria**; baja manual. No hay importación masiva de listas sin prueba.
3. **Segmentos:** constructor de reglas con vista previa del tamaño en vivo ("47 suscritos cumplen"), más los segmentos que vienen de clústeres.
4. **Campañas:** lista por estado → editor de bloques → vista previa computador/celular → «Enviarme una prueba» → **revisión final** (audiencia, asunto, remitente y advertencias como "3 contactos sin nombre") → **Enviar ahora** o **Programar**.
5. **Resultado de campaña:** embudo enviados → entregados → clics → pedidos, más enlaces más clicados, bajas y rebotes.
6. **Correos de seguimiento enviados:** historial de los correos del pedido (sección pequeña).
7. **Configuración:** remitente, temas de preferencia, versión vigente del texto de consentimiento, interruptores de captura pública y analítica.

---

## 8. Tramos de construcción (cada uno se prueba y se cierra con evidencia)

| Tramo | Contenido | Depende de |
|---|---|---|
| **EM1** | `em_contactos` + bitácora + módulo/permisos + pantalla Contactos (alta manual con evidencia) + Resumen básico + «Correos de seguimiento enviados» + retiro de `ventas/correos/` | — |
| **EM2** | `mk_perfiles_clientes` (todas las variables con datos existentes) + Segmentos por reglas con vista previa de tamaño | EM1 |
| **EM3** | Análisis de clúster en Marketing Project (k-means++, silueta, retrato, reglas de pocos datos, exportar, guardar como segmento) | EM2 |
| **EM4** | Campañas: editor de bloques, producto destacado, vista previa, prueba, revisión final, envío y programación vía Broadcasts + guía para `news.magandhi.com` | EM1–EM2, dominio |
| **EM5** | Webhook firmado + eventos + resultados + atribución de ventas + supresión automática | EM4 |
| **EM6** | Captura pública: formulario y casilla en la tienda + doble confirmación (**apagado** hasta la política) | EM1, política |
| **EM7** | Analítica propia + aviso de consentimiento + variables de comportamiento en el clúster | EM3, política de cookies |
| EM8 *(futuro)* | Automatizaciones: bienvenida, reposición ("¿se te acaba tu shampoo?"), recuperación | EM5 |
| EM9 *(futuro)* | Recomendaciones por navegación | EM7 con volumen |

**Orden recomendado:** EM1 → EM2 → EM3 → EM4 → EM5. EM6 y EM7 cuando la política esté lista. Cada tramo lleva su migración probada localmente (como Opiniones, Correos y Stock), su runbook en `INSTRUCCIONES.md` y su PR.

---

## 9. Riesgos y cómo se cubren

| Riesgo | Cobertura |
|---|---|
| Enviar a quien no autorizó | Audiencia = segmento ∩ suscritos, verificado en el servidor al enviar; supresión de bajas, rebotes y quejas |
| Envío masivo por error | Confirmación con N congelado, revisión final, solo humanos, cancelación de campañas programadas |
| Clúster que "ve" patrones inexistentes | Reglas de pocos datos, silueta, cobertura por variable, rótulo «Exploratorio» |
| Webhook falsificado | Verificación de la firma Svix y rechazo si falla |
| Abuso del formulario público | Límite por IP, doble confirmación, mensajes que no revelan si un correo existe |
| Pérdida de reputación de `news` | Higiene automática; límites de Resend vigilados en el Resumen (rebotes < 4 %, spam < 0,08 %) |
| Privacidad de la analítica | Consentimiento previo, id aleatorio, sin IP, retención de 13 meses, primera parte |

---

## 10. Decisiones del dueño (cerradas)

1. ✅ Módulo propio `email_marketing` (PII; el de Marketing no basta).
2. ✅ Ventana de atribución manual: **7 días** tras un clic.
3. ✅ Umbrales del clúster: < 10 no agrupa, < 30 exploratorio, silueta < 0,25 sin estructura.
4. ✅ Temas: **Novedades** y **Ofertas**.
5. ⏸️ Campo «hora de la venta» en Registrar pedido: sin decidir (no bloquea nada).
6. ✅ Captura automática en la tienda (EM6): casilla **desmarcada y siempre visible** (nunca mostrarla u ocultarla según el correo: revelaría quién está suscrito), separada de la compra, con **doble confirmación** por correo. Se activa con la política publicada y, para la casilla del checkout, con Wompi F2.
7. ✅ El panel «Correos al cliente» se retiró: los textos de los correos del pedido se cambian con un SQL que entrega Kiro.


---

## 11. Estado real y relevo para la próxima sesión (8-oct-2026)

### 11.1 Qué está construido (todo mergeado en `main`)

| Tramo | Migración | Piezas | Estado en producción |
|---|---|---|---|
| Correos del pedido | `20261008000000` | Edge Function `enviar-correo-pedido`, bloque en Seguimiento | ✅ Desplegado y probado (Gmail → Principal) |
| Bloqueo de stock | `20261008000100` | `crear_pedido` + `ventas_stock_disponible` | ✅ Aplicado |
| EM1 Contactos | `20261009000000` | Resumen, Contactos, Correos de seguimiento | ✅ Aplicado |
| EM2 Perfiles + segmentos | `20261010000000` | `mk_perfiles_clientes`, Segmentos | ✅ Aplicado |
| EM3 Clúster | `20261011000000` | `marketing-project/analisis-cluster.html` + `cluster-core.js` | ✅ Aplicado |
| EM4 Campañas | `20261012000000` | Edge Function `em-campana`, `campanas.html` | ✅ Aplicado y desplegado; el dueño probó un envío con éxito |
| EM5 Resultados | `20261013000000` | Edge Function `em-webhook` (Verify JWT apagado, firma Svix), resultados en `campanas.html`, salud en el Resumen, entrega en Seguimiento, campañas en la ficha | ✅ Aplicado, desplegado y webhook conectado (Resend → 200) |
| EM5.1 Respuesta a email | `20261014000000` | 5 variables de email en `mk_perfiles_clientes` (clúster) + 9 condiciones de Segmentos (`em__perfil_email`) | 🟡 Construido y probado; falta aplicar (`INSTRUCCIONES.md` EM5.1) |
| EM6 Captura pública | `20261015000000` | Edge Function `em-suscripcion` (Verify JWT apagado), formulario `suscripcion/` en la tienda, `/suscripcion/confirmar/`, tarjeta «Formulario de la tienda» en el Resumen | 🟡 Construido y probado; falta aplicar/desplegar (`INSTRUCCIONES.md` EM6) |

Resend: `updates.magandhi.com` (pedidos, **sin rastreo a propósito**: el botón de reseña lleva el código) y `news.magandhi.com` (campañas, rastreo de clics/aperturas vía `links.news`), ambos verificados, región São Paulo, TLS oportunista. Secrets en Supabase: `RESEND_API_KEY` (Sending access, solo pedidos) y `RESEND_MARKETING_API_KEY` (Full access, solo funciones `em-*`). DMARC `p=none` en la raíz cubre ambos.

**Pendiente de verificar con el dueño:** si registró la política solo para probar el envío sin tenerla publicada en magandhi.com, volverla a pendiente:
`update em_config set politica_publicada = false where id;`

### 11.2 EM5 · Resultados — construido (8-oct-2026)

Runbook completo en `supabase/INSTRUCCIONES.md` §EM5. Lo esencial para quien siga:

- **Correlación:** cada aviso de Resend trae `data.broadcast_id` → `em_campanas.resend_broadcast_id`, y `data.to[0]` → `em_campana_destinatarios.correo`. Los correos del pedido se reconocen por `data.email_id` = `correo_envios.proveedor_id`. Los envíos de prueba (`tags.tipo` = `prueba` / `prueba_campana`) se ignoran.
- **Idempotencia:** por el header `svix-id` (índice único en `em_eventos.svix_id`).
- **Escritura:** solo `em_webhook_registrar(svix_id, evento)`, ejecutable **solo por service_role**. La función envía la llave de servicio en `apikey` **y** `Authorization` (lección de Wompi F1).
- **Respuestas:** 200 para procesado/repetido/ignorado; 400/401/413 para lo inválido (Resend no insiste); 500/503 solo para fallos nuestros (Resend reintenta ~28 h). Si fallara muchas veces, Resend apaga el webhook y avisa por correo.
- **Decisiones cerradas del dueño (8-oct):** (1) atribución aproximada = pedido no anulado, registrado después del clic, con `fecha_orden` entre el día del clic y +7 días, y solo para la campaña del **último** clic; (2) bajas por campaña = última campaña recibida antes de la baja, rotulado «aprox.»; (3) rebote permanente de un correo del pedido → contacto `rebotado`; (4) `email.suppressed` → `rebotado` («Suprimida por Resend»); (5) eventos crudos 13 meses, luego totales congelados en `em_campana_resultados_archivo`.
- **Reglas duras:** el rebote temporal no suprime; los estados solo empeoran (suscrito < baja < rebotado < queja); un webhook nunca vuelve a suscribir; no se guarda IP ni navegador del clic; aperturas siempre «aproximadas».
- **Atribución exacta:** `pedidos.utm_campaign` existe y está vacía. **Wompi F2** debe: (a) que la tienda conserve el `utm_campaign` de la URL de llegada y lo mande a la intención de pago, y (b) que el pedido web lo guarde. Sin eso, todo se atribuye como aproximado.
- **Matriz de permisos:** su lista blanca de `authenticated` estaba desactualizada desde Opiniones (marcaba 1 falla). Se puso al día; el conteo ahora es dinámico. Cada tramo nuevo que agregue RPC para usuarios del panel debe agregarlos ahí.
- **Arnés de pruebas de EM5:** `supabase/pruebas/local/em5-resultados.sql` (61 comprobaciones; corre después de `correr-local.sh` y lo deshace todo).

### 11.3 Endpoints de Resend ya verificados (EM4)

- `POST /contacts` `{email, first_name, unsubscribed, segments:[{id}]}` · `GET /contacts/{id|email}` · `PATCH /contacts/{id|email}`.
- `POST /contacts/{contact_id}/segments/{segment_id}` · `POST /segments {name}`.
- `POST /broadcasts {segment_id, from, subject, html, text, reply_to, name, topic_id?, send, scheduled_at?}` · `POST /broadcasts/{id}/cancel`.
- Marcadores en el HTML: `{{{RESEND_UNSUBSCRIBE_URL}}}` y `{{{contact.first_name|alternativa}}}`.
- Límite: 10 peticiones/s por equipo (la función pausa 220 ms y reintenta en 429).

### 11.4 Cómo se probó cada tramo (repetir el método en EM6/EM7)

PostgreSQL 15 local con `supabase/pruebas/local/supabase-simulado.sql` + todas las migraciones + matriz de permisos (171/171) + pruebas SQL por tramo; Edge Functions con `deno check` y un simulador local de Supabase/Resend; interfaz en Chromium headless (PC 1280 y celular 390) con Supabase simulado, comprobando DOM, desbordes y errores de JS. Capturas solo de 1280×900 o menores. En EM5 se simuló además la firma Svix (válida, inválida, vencida, repetida y cruzada con la librería oficial `npm:svix`) con un PostgREST mínimo que ejecuta el RPC real como service_role. Ojo: el sandbox bloquea `python -m http.server` lanzado desde bash; el servidor estático para Chromium se levanta dentro del propio script de prueba.

### 11.5 Después de EM5

EM6 construido (formulario + doble confirmación, apagado por defecto; ver §11.6). Siguiente: **EM7** (analítica propia + aviso de cookies), luego **Wompi F2** (incluye la casilla de suscripción del checkout). **D3** antes de delegar accesos. Las políticas existen como estructura provisional en `magandhi.com/politicas/`; el dueño redacta el texto final antes de abrir la tienda.

### 11.6 EM6 · decisiones de implementación (8-oct-2026)

- **La solicitud no es un contacto.** Vive en `em_confirmaciones` (48 h, purga a 7 días). Solo al confirmar se crea o reactiva el contacto, con la prueba completa. Un tercero que escribe un correo ajeno no lo inscribe.
- **Token** de 256 bits en el **fragmento** del enlace (`#t=`, no viaja a ningún servidor ni en el referer); en la base, solo sha256. La página de confirmación lo borra de la barra de direcciones.
- **Respuesta pública única** exista o no el correo. Límites: 10 solicitudes por IP-hash al día, 3 correos por dirección al día. Campo trampa.
- **Política borrador:** quien se suscribe bajo `borrador-*` queda excluido de `em__audiencia` en cuanto la versión vigente deja de ser borrador.
- El correo de confirmación sale por `news.magandhi.com` con `RESEND_MARKETING_API_KEY`, `tags.tipo=confirmacion_suscripcion`.
- **Pendiente para Wompi F2:** la casilla de suscripción en el checkout reutilizará `em_publico_suscribir` (misma doble confirmación).
