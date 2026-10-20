# PLANO · Promocionar P0 · Taxonomía y privacidad

**Decisión del dueño:** 20 de octubre de 2026
**Estado:** **contrato cerrado; sin implementación ni despliegue**
**Siguiente tramo:** P1 · Producto compartible
**Superficies futuras:** back-office `montaguth.institute`, tienda `magandhi.com` y backend compartido en Supabase.

P0 define el lenguaje, la autoridad y los límites de privacidad de Promocionar
antes de capturar un solo clic nuevo. Este cierre es documental: no crea tablas,
RPC, Edge Functions, DNS, rutas, interfaz ni eventos; no cambia Wompi, la tienda,
las políticas públicas o los interruptores de analítica.

---

## 1. Promesa y frontera

> MAGANDHI podrá reconocer qué enlace propio produjo una visita y una venta sin
> confundir clics con personas, sin aceptar destinos arbitrarios y sin convertir
> la atribución en un perfil de navegación.

P0 cierra:

- siete canales promocionales y sus nombres canónicos;
- normalización de `source`, `medium`, `campaign` y `content`;
- precedencia entre código propio, UTM y atribución aproximada histórica;
- visita promocional de 30 minutos;
- separación entre atribución transaccional y analítica consentida;
- conteo agregado, filtros y retención;
- estados e inmutabilidad de los enlaces.

P0 no construye:

- metadata o shells compartibles de producto (P1);
- estudio, textos, QR o piezas exportables (P2);
- tablas, redirector, dominio corto o conteo (P3);
- unión con intención/pedido (P4);
- panel de resultados (P5);
- Meta Ads, Pixel, Conversions API, publicación o gasto automático.

---

## 2. Vocabulario sin colisiones

Los siguientes términos son distintos y nunca se reutilizan como si fueran el
mismo dato:

| Nombre | Significado | Valores o fuente |
|---|---|---|
| `canal_promocion` | Dónde se coloca una pieza o enlace propio | Taxonomía cerrada de este plano |
| `pedidos.canal` | Cómo entró la venta | `manual` o `web` |
| `tienda_eventos.origen` | Categoría de llegada, solo en analítica consentida | `directo`, `email`, `instagram`, `facebook`, `whatsapp`, `buscador`, `otro_sitio` |
| `em_contactos.fuente` | Cómo nació un contacto de email | Contrato de Email Marketing |
| `evidencia.canal` | Canal que respalda una autorización manual | Contrato de consentimiento |
| `campana_producto_id` | Producto/presentación comercial promovida | `campana_producto` |
| `em_campana_id` | Envío de Email Marketing | `em_campanas` |
| `utm_campaign` | Etiqueta interoperable y descriptiva | No es autoridad de atribución |

En el modelo de Promocionar se usará siempre `campana_producto_id`; no se
introducirá una FK ambigua llamada solamente `campana_id`.

### Hechos que se muestran por separado

1. **Clic aproximado:** solicitud navegable aceptada por el contador agregado.
2. **Sesión medida:** navegación de una persona que aceptó analítica.
3. **Checkout iniciado:** evento consentido, si existe, o hecho operativo de la intención.
4. **Pago aprobado:** hecho de Wompi verificado.
5. **Pedido no anulado:** venta materializada.
6. **Ingreso:** valor de pedidos no anulados según la definición del tablero.

Un clic no es una persona, una sesión no es una compra y un pago no se cuenta
como ingreso si el tablero usa pedidos no anulados.

---

## 3. Taxonomía cerrada de canales

`canal_promocion` solo admite estos siete valores. `source` y `medium` se
derivan del canal; no se aceptan como autoridad desde la URL.

| `canal_promocion` | `source` | `medium` | Uso previsto |
|---|---|---|---|
| `whatsapp` | `whatsapp` | `mensajeria` | Conversaciones, estados o difusión autorizada |
| `instagram` | `instagram` | `social` | Biografía, historia, publicación o mensaje |
| `facebook` | `facebook` | `social` | Página, publicación, grupo o mensaje |
| `email` | `email` | `email` | Email Marketing propio o correo individual autorizado |
| `qr` | `qr` | `offline` | Pieza física o visual escaneable |
| `anuncio_manual` | `anuncio-manual` | `paid-manual` | Anuncio preparado y publicado manualmente |
| `otro_controlado` | `otro-controlado` | `referral` | Colocación aprobada que no cabe en los seis anteriores |

`otro_controlado` no permite una URL libre ni un canal escrito al vuelo. La
colocación concreta se describe internamente y, si se vuelve recurrente, exige
una nueva decisión de taxonomía en vez de multiplicar alias.

No se aceptan como canales nuevos abreviaturas como `ig`, `fb` o `wa`. Esas
formas pueden leerse por compatibilidad al clasificar tráfico histórico, pero
se guardan con el valor canónico.

---

## 4. Normalización interoperable

La misma función futura deberá normalizar cualquier valor editable de UTM:

1. convertir Unicode a NFKD;
2. retirar marcas diacríticas;
3. aplicar `trim` y minúsculas;
4. reemplazar cada secuencia fuera de `a-z0-9` por un solo guion;
5. colapsar guiones repetidos;
6. retirar guiones iniciales y finales;
7. rechazar el resultado vacío;
8. truncar sin dejar un guion final.

| Campo | Obligatorio | Máximo | Autoridad |
|---|---:|---:|---|
| `source` | Sí | 32 | Derivado de `canal_promocion` |
| `medium` | Sí | 32 | Derivado de `canal_promocion` |
| `campaign` | Sí | 60 | Identificador estable de la iniciativa |
| `content` | No | 60 | Pieza, variante o colocación; nunca una persona |

Ejemplos:

| Entrada | Resultado |
|---|---|
| ` Lanzamiento Áloe  ` | `lanzamiento-aloe` |
| `Historia / Producto 01` | `historia-producto-01` |
| `  --  ` | Rechazado: vacío |
| `María-Tunja` como audiencia | Rechazado: no se codifican personas o audiencias identificables |

### `campaign`

- Email Marketing conserva exactamente `em_campanas.utm_campaign`; es una
  excepción histórica y no se regenera.
- Promocionar genera `<base>-<aammdd>-<xxxx>`: la base normalizada ocupa como
  máximo 48 caracteres, `aammdd` usa fecha de Colombia y `xxxx` son 20 bits
  aleatorios en Crockford base32 minúscula. Los 12 caracteres reservados del
  sufijo mantienen el total en 60.
- La unicidad se comprueba server-side; una colisión genera otro `xxxx` y
  reintenta sin alterar la base.
- Una vez activado el enlace, `campaign` no cambia aunque cambie el nombre
  visible de la iniciativa.

### `content`

Identifica una pieza o colocación, no una persona. Vocabulario inicial:

- `enlace-oficial`;
- `boton-principal`;
- `imagen-01`;
- `producto`;
- `qr-cuadrado`;
- `qr-historia`;
- `qr-horizontal`.

Una revisión usa sufijo `-v02`, `-v03`, etc. No contiene nombre, correo,
teléfono, `customer_id`, audiencia ni texto sin normalizar.

---

## 5. Código propio y destino seguro

La autoridad futura será un registro de enlace, no una UTM suministrada por el
navegador.

### Código

- nombre conceptual: `codigo`;
- 16 caracteres Crockford base32 en minúsculas;
- 80 bits de aleatoriedad criptográfica;
- patrón: `^[0-9a-hjkmnp-tv-z]{16}$`;
- único, opaco y no secuencial;
- público: identifica un enlace, no autentica a una persona;
- nunca se reasigna, recicla ni deriva de ids internos.

La URL objetivo de P3 es `https://go.magandhi.com/<codigo>` si se aprueban DNS y
routing. Una ruta bajo `magandhi.com` es la alternativa; P3 decidirá la
infraestructura sin cambiar este contrato.

### Destino

El enlace guarda una referencia interna de lista blanca. El servidor construye
el destino; nunca recibe ni refleja `url`, `next`, `redirect`, `returnTo` o una
URL arbitraria de la consulta.

Destinos iniciales permitidos:

- home de MAGANDHI;
- ficha canónica de una `campana_producto` publicada;
- futuras rutas internas aprobadas mediante un tipo explícito y versionado.

No se redirige a otro dominio, aunque sea de un proveedor de MAGANDHI. Un
producto retirado o enlace desactivado muestra una página MAGANDHI de enlace no
disponible; no se reasigna a otro producto.

---

## 6. Atribución y precedencia

### Modelo inicial

**Último enlace propio válido dentro de la visita.** La visita promocional dura
30 minutos desde la última actividad calificable y vive solo en
`sessionStorage`.

Estado conceptual:

```text
{ codigo, recibido_en, ultima_actividad }
```

Actividad calificable es únicamente:

- resolver un código propio válido;
- cargar visiblemente una página interna de MAGANDHI en la misma pestaña;
- iniciar checkout, después de comprobar que la visita no había vencido.

Actualizar `ultima_actividad` es estado local y no crea un evento analítico. No
la renuevan foco, movimiento, temporizadores, pestaña oculta, prefetch,
solicitudes en segundo plano ni eventos de analítica. Volver de Wompi no revive
una visita vencida ni cambia la atribución que P4 ya haya congelado.

Reglas:

1. Un código propio válido y activo inicia o reemplaza la visita promocional.
2. Otro código propio válido reemplaza al anterior.
3. Navegación interna o entrada directa durante la misma visita no lo borra y
   una carga visible interna renueva `ultima_actividad`.
4. Un código inexistente, mal formado o desactivado no atribuye ni reemplaza un
   código válido que ya estaba en la visita.
5. Tras 30 minutos sin actividad calificable se elimina antes de iniciar
   checkout.
6. Cerrar la pestaña termina la visita; no hay atribución entre navegadores o
   dispositivos.
7. El estado promocional es independiente de `mg_vid`.
8. P4 vuelve a validar server-side el código y congela la FK; el navegador no
   puede enviar `atribucion_enlace_id`.
9. Si el servicio promocional falla, la compra continúa sin atribución.

### Matriz de autoridad

| Situación | Resultado |
|---|---|
| Código propio válido + UTM coincidente | Exacta propia; manda el registro del código |
| Código propio válido + UTM diferente o inventada | Exacta propia; se ignora la UTM como autoridad |
| Código inválido/desactivado + UTM | Sin exacta propia; aplica compatibilidad legacy si corresponde |
| Email histórico con `utm_campaign` de formato válido y sin código propio | `legacy_email_utm`: señal declarada, no verificada ni exacta |
| Pedido manual sin exacta + último clic Resend elegible | `aproximada_email`, regla histórica de 7 días |
| Ninguna de las anteriores | Sin atribuir |

Una venta aparece en una sola categoría. Nunca se suma como exacta propia,
legacy UTM y aproximada al mismo tiempo.

`legacy_email_utm` conserva la lectura histórica sin elevar una cadena
controlada por el navegador a autoridad. Aunque coincida con una
`em_campanas.utm_campaign`, se rotula **legacy/no verificada**. P4 deja de crear
nuevas atribuciones de esta clase cuando todos los enlaces nuevos de Email
Marketing usen código propio; los registros históricos permanecen rotulados.

La regla histórica de Email Marketing se conserva: para un pedido manual no
anulado, el último clic del mismo cliente dentro de los siete días siguientes
puede mostrarse como aproximado. No se presenta como atribución propia exacta.

---

## 7. Privacidad y consentimiento

### Sin consentimiento de analítica

Promocionar podrá, una vez implementado:

- resolver el código y redirigir;
- conservar el código en `sessionStorage` durante la visita;
- incrementar un contador diario agregado;
- congelar la FK del enlace en una intención/pedido si hay compra;
- mantener durante un máximo de 48 horas un registro antiabuso mínimo con
  `hash_ip_dia`, ventana de cuota, conteo y expiración.

El hash antiabuso usa una sal secreta distinta por día de Colombia, no se une a
`enlace_id`, `mg_vid`, sesión, cuenta o cliente, no alimenta métricas y solo
decide si se acepta otro incremento. La IP cruda existe únicamente en memoria
durante la solicitud y nunca se persiste. La sal rota a medianoche; los
registros del día anterior se purgan antes de cumplir 48 horas, impidiendo
correlación entre días.

No podrá:

- crear `mg_vid`;
- registrar páginas o productos vistos;
- unir clics con un navegador, cuenta o cliente;
- construir historial individual;
- llamar “persona” o “visitante único” al contador.

La atribución del pedido demuestra la procedencia de esa transacción, no el
historial de navegación de quien compra.

### Con consentimiento de analítica

Se mantienen las reglas EM7 vigentes: `mg_vid`, sesión, páginas, producto,
dispositivo y eventos solo existen después de aceptar. El clic agregado no se
une a `mg_vid`; P5 muestra clics aproximados y sesiones consentidas como
métricas distintas.

Rechazar o retirar el consentimiento:

- no impide navegar, comprar ni usar un enlace;
- elimina el identificador local según el contrato vigente;
- detiene eventos de navegación;
- no borra pedidos ni su atribución transaccional necesaria.

Antes de activar P3/P4, las políticas públicas deberán explicar el estado de
visita, el conteo agregado, la atribución de pedidos, las duraciones y el modo de
ejercer derechos. P0 no publica esas políticas ni cambia `borrador-0`.

---

## 8. Conteo agregado

P3 usará una fila por enlace y fecha de Colombia, no una fila por clic:

```text
atribucion_clics_dia
  enlace_id · fecha_colombia · total_aproximado
```

- incremento atómico por `(enlace_id, fecha_colombia)`;
- fecha calculada en `America/Bogota`;
- cuenta solicitudes aceptadas, no personas ni clics únicos;
- no guarda timestamp individual, IP, referrer, User-Agent, `mg_vid` o sesión;
- el redirect funciona aunque la escritura del contador falle;
- la interfaz dice siempre **clics aproximados**.

### Qué cuenta

- `GET` navegable con código activo, sin señales de preview, prefetch o bot.

### Qué redirige pero no cuenta

- User-Agent vacío o identificado como bot, crawler, scanner o preview;
- cabeceras `Purpose`/`Sec-Purpose` con `prefetch`, `prerender` o `preview`;
- previews conocidos de Facebook, WhatsApp, Telegram, X/Twitter o LinkedIn;
- herramientas como Lighthouse, PageSpeed, `curl`, `wget` o librerías HTTP.

### Qué no cuenta

- `HEAD`, `OPTIONS` y cualquier método diferente de `GET`;
- código inexistente, mal formado o desactivado.

El filtro reduce ruido, pero no convierte el total en personas únicas. La
limitación de abuso usa exclusivamente el registro temporal definido en §7:
hash con sal diaria, ventana de cuota, conteo y expiración. No guarda
`enlace_id`, no se consulta para métricas o deduplicación comercial y se elimina
antes de 48 horas. Nunca se conserva la IP cruda.

---

## 9. Ciclo de vida e inmutabilidad

`estado_enlace` solo admite:

```text
borrador -> activo -> desactivado
```

- **Borrador:** se pueden editar canal, iniciativa, pieza y destino. Como nunca
  fue público, puede eliminarse antes de recibir un código definitivo.
- **Activo:** se congelan `codigo`, `campana_producto_id`, tipo/destino,
  `canal_promocion`, `source`, `medium`, `campaign` y `content`. Solo permite
  desactivar.
- **Desactivado:** estado terminal. No reactiva, no cambia destino y no se
  reasigna. Una corrección crea otro enlace con `reemplaza_enlace_id`.

No se usan `retirado`, `archivado`, `cancelado` o `baja`, porque pertenecen a
otros ciclos del sistema.

El código de un enlace activado permanece reservado para siempre, aunque sus
datos opcionales ya hayan cumplido retención. Así nunca puede apuntar después a
otro producto.

---

## 10. Retención y supresión

| Dato | Retención técnica | Salida |
|---|---|---|
| Hash temporal antiabuso | Máximo 48 horas | Eliminación automática |
| Estado de visita promocional | 30 min de inactividad y como máximo la vida de la pestaña | Eliminación de `sessionStorage` |
| Clic diario agregado | 13 meses | Se suma al total histórico no fechado y se elimina el detalle diario |
| Total histórico no fechado por enlace | Indefinido, por decisión comercial; no contiene identificadores ni fechas | Solo suma acumulada; no permite reconstruir visitas o periodos |
| Eventos EM7 consentidos | 13 meses, contrato vigente | Agregados no identificables según EM7 |
| Eventos Resend | 13 meses, contrato vigente | Totales congelados por campaña |
| Borrador nunca activado | Hasta que el operador lo elimine | Eliminación permitida porque nunca tuvo código público |
| Enlace activado | Mientras esté activo y 13 meses completos tras desactivación | Se retiran receta/texto opcional; código, estado y no-reasignación permanecen |
| FK en intención/pedido | La misma vigencia del registro transaccional | No crea una copia de PII promocional |

Si un enlace tiene pedidos, se conserva junto a ellos el mínimo necesario para
interpretar la atribución: código, campaña de producto, canal y UTM registrada.
La duración jurídica/contable del pedido la define la política general y no se
acorta desde Promocionar.

Una solicitud de supresión elimina o anonimiza datos promocionales opcionales
cuando corresponda; no inventa un borrado de compras, contabilidad o evidencia
que deba conservarse. P0 no implementa el botón de eliminar cuenta ni cambia la
bitácora de consentimiento de Email Marketing.

Los plazos públicos y sus excepciones deberán ser revisados antes de publicar
las políticas. Hasta entonces la analítica y captura pública mantienen sus
gates actuales.

---

## 11. Compatibilidad

- Los enlaces actuales de Email Marketing siguen usando
  `utm_source=email&utm_medium=email&utm_campaign=...`.
- `em_campanas.utm_campaign` no se renombra ni regenera.
- `pedidos.utm_campaign` permanece durante la transición. La RPC histórica
  `em__resultados_calc` devuelve el tipo interno `exacta` para esa coincidencia;
  no se reescribe la migración aplicada. P0 gobierna su interpretación como
  `legacy_email_utm`, no verificada, hasta que P4/P5 migren el contrato visible.
- La clasificación histórica de `ig`, `fb` y `wa` puede seguir leyéndose, pero
  Promocionar solo genera valores canónicos.
- P4 agregará una FK separada; no sobrecargará `utm_campaign` con un UUID o el
  código opaco.
- La compra invitada, compra inmediata y carrito continúan aunque no haya
  atribución o analítica.

---

## 12. Gates para P1–P5

### P1 puede empezar cuando

- este contrato esté fusionado;
- se preserve `noindex` hasta verificar HTML inicial y políticas;
- las URLs canónicas no impriman precio o stock desactualizado como autoridad.

### P3 no puede activarse hasta que

- el esquema respete taxonomía, inmutabilidad y retención;
- el redirector pruebe lista blanca y ausencia de open redirect;
- existan filtros y limpieza de 48 horas;
- las políticas públicas hayan sido revisadas y publicadas;
- se midan método, CORS, caché y comportamiento de códigos desactivados.

### P4 no puede activarse hasta que

- el servidor derive la FK desde un código válido;
- código inventado no atribuya;
- una caída de atribución no bloquee la compra;
- intención, webhook y pedido mantengan idempotencia;
- exacta propia, legacy, aproximada y sin atribuir sean excluyentes.

### P5 no puede afirmar conversión sin

- mostrar el denominador;
- separar clic aproximado, sesión consentida, checkout, pago, pedido e ingreso;
- distinguir atribución exacta, legacy, aproximada y sin atribuir.

---

## 13. Criterios de cierre de P0

- [x] Siete canales canónicos y presets cerrados.
- [x] Campos y algoritmo de normalización definidos.
- [x] Código opaco, destino de lista blanca y prohibición de open redirect.
- [x] Último enlace válido y visita de 30 minutos definidos.
- [x] Precedencia con UTM y Email Marketing histórico definida.
- [x] Datos con y sin consentimiento separados.
- [x] Clic agregado, métodos y filtros definidos.
- [x] Estados, transiciones e inmutabilidad definidos.
- [x] Retención y salida por tipo de dato definidas.
- [x] P1–P5 y activación productiva fuera de alcance explícito.

**Evidencia del cierre:** este plano y su consistencia con
`PLANO-FASE-COMERCIAL.md`, `PLANO-EMAIL-MARKETING.md`, `PLANO-METRICAS.md` y
`CONTEXTO-MAGANDHI.md`. No existe evidencia productiva porque P0 no despliega ni
captura datos.
