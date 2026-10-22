# Sistema nervioso MAGANDHI · SN1

> Plano de la capa backend común de búsqueda, recomendación, composición y activos para la tienda web y una futura aplicación.

## 1. Estado y corte

**SN1-A (backend), SN1-B (integración web) y SN1-C (consola editorial) están implementadas en esta entrega; permanecen pendientes de aplicación y despliegue manual.**

- Migración: `supabase/migrations/20261112000000_sistema_nervioso_sn1.sql`.
- Edge Function ampliada: `supabase/functions/tienda-eventos/index.ts`.
- Baseline obligatorio: `20261111000000_campanas_categorias_oficiales.sql` y sus dependencias de cuentas, carrito, pedidos, opiniones y Métricas M1.
- Versión inicial del motor: `sn1-reglas-1`.
- Gate inicial: `activo=true`, por decisión explícita del dueño.
- Personalización de cuenta inicial: `true`.
- Exploración inicial: `12%`.
- Zona civil para ventanas y reportes: `America/Bogota`.

SN1 no cambia `catalogo_publico`, no crea una segunda fuente de stock, no modifica migraciones históricas y no requiere extensiones nuevas.

## 2. Invariante absoluta y frontera pública

`catalogo_publico` es la frontera de elegibilidad. Una campaña solo puede aparecer en búsqueda, recomendaciones o assets públicos cuando, en la misma lectura:

1. existe en `catalogo_publico`;
2. `agotado=false`;
3. `max_comprable>0`;
4. `campana_producto.publicado=true`;
5. `campana_producto.activo=true`;
6. no es placeholder/suprimida;
7. está dentro de su ventana SN opcional; y
8. el gate global SN está activo.

Cada función pública y `sn_assets_publicos_v1` repiten estos filtros. Una prioridad alta, relación manual, señal de ventas, rating, asset activo o dato de cuenta **jamás** puede recuperar una campaña despublicada, inactiva, suprimida, agotada o no comprable.

El apagado de emergencia es exclusivamente global (`sn_config.activo`). No existe ni se permite un gate SN por producto. Despublicar o dar de baja una campaña sigue haciéndose en Campañas; SN no duplica ese control.

La invariante gobierna la **exposición en superficies**: una fila retirada o una campaña inelegible jamás se enumera ni se devuelve por la tienda, la vista o las RPC SN. Como el bucket es público, un objeto histórico puede seguir respondiendo si alguien ya conoce su URL; SN1 no promete revocación física, borrado del objeto ni invalidación de cachés.

## 3. Arquitectura

Flujo común:

```text
Campañas + categorías + etiquetas internas
                  │
                  ├── catalogo_publico ──> conjunto público elegible
                  │                              │
Pedidos no anulados + rating + carrito propio   │
                  │                              ▼
Relaciones + prioridad + ventanas ──> reglas SN1 deterministas
                                                 │
                          ┌──────────────────────┴─────────────────────┐
                          ▼                                            ▼
                    sn_buscar_v1                                sn_recomendar_v1
                          │                                            │
                          └──────── producto JSON público ─────────────┘
                                                                       │
                                                           sn_layout + assets
                                                                       │
                                                                 1–3 módulos
```

Las señales internas solo calculan orden. La respuesta se reconstruye exclusivamente con columnas públicas de `catalogo_publico` y un asset obtenido de `sn_assets_publicos_v1`.

## 4. Modelo de datos

### 4.1 `sn_config`

Singleton privado (`id=1`) con:

- `activo`: gate interno de emergencia para todo SN;
- `personalizacion_cuenta`: permite o prohíbe usar compras/carrito de la cuenta actual;
- `modelo_version`: `sn1-reglas-1` inicialmente;
- `exploracion_pct`: entero `0..100`, inicialmente `12`;
- razón, fecha y actor de actualización.

`sn_config_bitacora` conserva cada cambio. No almacena consultas, perfiles, visitantes ni clientes. Solo un usuario interno con rol `admin` puede cambiar la configuración mediante `sn_configurar_v1`.

### 4.2 `sn_producto_config`

Una fila opcional por `campana_producto`:

- `prioridad`: `-20..20`;
- `intenciones`: entre cero y doce casos de uso libres, únicos y canónicos;
- `disponible_desde` / `disponible_hasta`: instantes opcionales; el motor evalúa la ventana en `America/Bogota`;
- auditoría de creación y actualización.

Ausencia de fila equivale a prioridad `0`, intenciones vacías y ventana abierta. Al publicar una campaña, un trigger crea esa fila predeterminada sin reactivar ni alterar ninguna campaña. Las campañas ya publicadas reciben el mismo backfill durante la migración.

Cada intención debe tener `2..80` caracteres, estar recortada, en minúsculas y con espacios simples, y no contener saltos de línea ni PII detectable por `sn__contiene_pii`. No existe una allowlist fija de casos de uso. La unicidad se evalúa con `sn__normalizar_texto`, por lo que variantes equivalentes por acentos, signos o separación se rechazan aunque sus textos originales sean distintos. `sn_guardar_campana_v1` aplica exactamente este mismo contrato antes de escribir.

### 4.3 `sn_producto_relacion`

Relación dirigida entre dos campañas, sin autorrelación. Tipos:

- `complementa`
- `sustituye`
- `continua`
- `rutina`
- `descubrimiento`
- `excluir`

`peso` está limitado a `1..100`. `sn_guardar_campana_v1` valida primero el lote completo y luego reemplaza atómicamente las relaciones activas del origen: las anteriores pasan a baja lógica con fecha/actor/razón y se insertan filas nuevas. No se borra historia. Solo puede existir una relación activa por origen, destino y tipo.

`excluir` gana sobre cualquier señal positiva, pero no reemplaza los filtros duros de disponibilidad: esos se aplican antes.

### 4.4 `sn_asset`

Registro privado e histórico de imágenes multiformato. Cada fila tiene campaña, rol, path, MIME, dimensiones, foco, texto alternativo, versión y auditoría. La identidad visual de una versión es inmutable; retirar o sustituir solo cambia su estado de baja. Un índice parcial garantiza una sola variante activa por campaña y rol.

Roles:

- `cuadrado`
- `vertical`
- `horizontal`
- `panoramico`
- `recorte`

MIME permitidos: `image/jpeg`, `image/png`, `image/webp`, `image/avif`.

El path maestro debe:

- vivir bajo `sistema-nervioso/<campana_uuid>/`;
- contener exactamente un nombre `<rol>-<timestamp>-<random>.<ext>` bajo ese prefijo, sin subcarpetas;
- usar solo minúsculas ASCII, dígitos y guiones en el nombre, con una extensión coherente con MIME;
- no contener `..`, `//`, query string ni fragmento;
- corresponder al rol registrado y **no** terminar en `-sm.<ext>`.

La versión es autoritativa de base de datos: `sn_registrar_asset_v1` calcula el siguiente entero por campaña y rol, pero ese número no forma parte del nombre físico. La consola genera dos keys WebP inmutables con el mismo timestamp/aleatorio y registra únicamente la grande; la terminada en `-sm.webp` es la variante liviana derivada y el backend la rechaza como path maestro.

Ejemplo maestro válido:

```text
sistema-nervioso/11111111-2222-4333-8444-555555555555/cuadrado-20261112000000000-a1b2c3d4e5f60708.webp
```

### 4.5 `sn_layout`

Recetas privadas y versionadas de composición. Hay tres módulos iniciales para cada superficie:

- `home_principal`
- `home_descubrimiento`
- `categoria`
- `producto_final`
- `carrito`
- `busqueda`

Tipos permitidos:

- `mosaico`
- `carril_derecha`
- `carril_izquierda`
- `destacado_horizontal`
- `duo_vertical`
- `cuadricula`

Cada receta fija orden, peso, título, subtítulo y roles fotográficos requeridos. Solo puede haber una versión activa por superficie y slot.

### 4.6 `sn_assets_publicos_v1`

Es la única vista pública de assets SN. Expone exclusivamente:

```text
asset_id, campana_id, rol, path, mime, ancho, alto,
foco_x, foco_y, alt, version
```

No expone actores, fechas de auditoría, retiros, etiquetas, proveedor, costos, stock exacto ni perfil. La vista cruza nuevamente `catalogo_publico`, campaña física, ventana y gate global.

## 5. Contratos RPC

### 5.1 Administración de campaña

```sql
sn_campana_detalle_v1(p_campana_id uuid) -> jsonb
```

Exige Marketing. Conserva en raíz `campana_id` y `nombre` para compatibilidad y añade exactamente este objeto de identidad/estado:

```json
{
  "campana": {
    "id": "uuid",
    "nombre": "Nombre de campaña",
    "publicado": true,
    "activo": true,
    "es_placeholder": false
  }
}
```

Además devuelve configuración efectiva, assets activos, assets históricos y relaciones con estado e historia, sin datos de perfil ni otros campos de campaña.

```sql
sn_guardar_campana_v1(
  p_campana_id uuid,
  p_prioridad integer,
  p_intenciones text[],
  p_disponible_desde timestamptz,
  p_disponible_hasta timestamptz,
  p_relaciones jsonb
) -> jsonb
```

Exige Marketing. `p_relaciones` es un arreglo de máximo 100 objetos con **exactamente** estas claves:

```json
{"destino_id":"uuid","tipo":"complementa","peso":80}
```

Se rechazan claves adicionales, tipos no canónicos, UUID inexistentes, autorrelaciones, pesos fuera de rango y duplicados. La configuración y el reemplazo de relaciones forman una sola transacción. Origen y destinos se bloquean en orden UUID; ya bajo esos locks deben seguir activos y no ser placeholder. Esta regla editorial no exige que un borrador real esté publicado ni tenga stock.

### 5.2 Assets

```sql
sn_registrar_asset_v1(
  p_campana_id uuid,
  p_rol text,
  p_storage_path text,
  p_mime text,
  p_ancho integer,
  p_alto integer,
  p_foco_x numeric,
  p_foco_y numeric,
  p_alt text
) -> jsonb
```

Exige Marketing. Bloquea la campaña y, ya bajo ese lock, rechaza un origen inactivo o placeholder sin exigir publicación ni stock a un borrador real. Valida la key maestra inmutable, MIME/dimensiones/foco/alt y rechaza la variante `-sm`. Si `storage_path` no existe, calcula la próxima versión interna, retira la variante activa previa del rol e inserta la nueva versión atómicamente. Si el path ya corresponde a una fila activa de la misma campaña y coinciden rol, MIME, dimensiones, foco y alt, devuelve esa misma fila sin mutarla: este es el retry seguro tras una respuesta perdida. Un path histórico/inactivo o cualquier divergencia de metadata produce un error controlado y nunca reactiva ni sobrescribe historia. No consulta Storage: la subida de la pareja grande/liviana ocurre antes en la consola y la RPC registra solo la grande.

```sql
sn_retirar_asset_v1(p_asset_id uuid) -> jsonb
```

Exige Marketing. Retiro lógico e idempotente; no borra historia ni objetos de Storage.

### 5.3 Gate global

```sql
sn_configurar_v1(
  p_activo boolean,
  p_personalizacion_cuenta boolean,
  p_exploracion_pct integer,
  p_razon text
) -> jsonb
```

Solo `admin`. Toda llamada exige razón de `3..500` caracteres y genera bitácora. Apagar SN no modifica `catalogo_publico`: la tienda puede seguir usando el catálogo tradicional.

### 5.4 Búsqueda

```sql
sn_buscar_v1(
  p_consulta text default null,
  p_categoria text default null,
  p_semilla text default null,
  p_limite integer default 24,
  p_desde integer default 0
) -> jsonb
```

Disponible para `anon`, `authenticated` y `service_role`.

Contrato de salida:

```json
{
  "ok": true,
  "modelo_version": "sn1-reglas-1",
  "modo": "busqueda",
  "consulta": "texto normalizado",
  "total": 42,
  "productos": []
}
```

Reglas:

- consulta máxima de 120 caracteres;
- NFKD real, retiro de acentos, minúsculas y espacios normalizados;
- consulta vacía permitida (`categoria` o `exploracion`); toda respuesta exitosa conserva `consulta` como string y usa `""` en esos modos;
- el filtro y la relevancia textual usan **exclusivamente** campos públicos de `catalogo_publico`: nombre, slug, categorías, detalle/presentación, característica, `hook_largo`, por qué MAGANDHI, sobre el producto y ficha técnica;
- `hook_corto`, intenciones y etiquetas internas no incluyen ni ordenan resultados de búsqueda y, por tanto, no forman un oráculo anónimo; las etiquetas pueden seguir como afinidad no textual dentro de recomendaciones;
- nombre/frase y coincidencia textual se ordenan antes que personalización por categorías públicas, prioridad, popularidad, rating, novedad o desempate;
- paginación determinista con `p_semilla` y máximo 60 por página;
- no persiste la consulta;
- correo, teléfono/identificador numérico largo, UUID o `@handle` se rechazan con `SN_CONSULTA_SENSIBLE`, sin repetir el valor;
- gate apagado devuelve `ok=false`, `codigo=SN_APAGADO` y lista vacía.

### 5.5 Recomendación y composición

```sql
sn_recomendar_v1(
  p_superficie text,
  p_contexto jsonb default '{}',
  p_semilla text default null,
  p_limite integer default 12
) -> jsonb
```

Disponible para `anon`, `authenticated` y `service_role`.

`p_contexto` solo admite:

```json
{
  "slug": "producto-publico",
  "categoria": "hogar",
  "consulta": "texto opcional",
  "excluir": ["slug-a", "slug-b"]
}
```

Cualquier otra clave —incluidas `uid`, `user_id`, `customer_id`, correo o teléfono— invalida todo el contexto. La identidad de cuenta se resuelve únicamente con `auth.uid()` en servidor.

Contrato de salida:

```json
{
  "ok": true,
  "request_id": "uuid",
  "modelo_version": "sn1-reglas-1",
  "modo": "contextual",
  "superficie": "producto_final",
  "modulos": [
    {
      "id": "producto_final_01",
      "tipo": "carril_derecha",
      "titulo": "Completa tu elección",
      "subtitulo": "Productos relacionados con lo que estás viendo.",
      "productos": []
    }
  ]
}
```

El motor devuelve uno, dos o tres módulos: `1..4` productos solicitados usan un módulo, `5..8` usan dos y `9..36` usan tres. Los productos se distribuyen entre módulos y categorías para evitar una lista monótona.

Señales, en orden controlado:

1. coincidencia textual contextual calculada solo con los campos públicos de `catalogo_publico` enumerados en búsqueda;
2. relación manual dirigida;
3. categoría pública y etiquetas internas del contexto como afinidad no textual;
4. afinidad de la cuenta, si está permitida;
5. prioridad editorial;
6. popularidad de pedidos no anulados;
7. rating público real;
8. novedad;
9. exploración determinista.

Compras y carrito se consultan solo cuando hay una cuenta autenticada activa y `personalizacion_cuenta=true`. Para `carrito`, sus artículos también se excluyen de la salida. Sin esas condiciones, el modo es `contextual`; con ellas, `personalizado`.

Los títulos de salida pertenecen a una allowlist cerrada. `Elegidos para ti` solo puede aparecer en el primer módulo de `home_principal` cuando `v_personaliza=true`. Si esa receta se sirve en modo contextual —incluido un invitado— el servidor devuelve `Una selección para descubrir`; los demás módulos conservan su título editorial no personal permitido. Un título fuera de allowlist nunca se propaga: el servidor usa el fallback neutro definido para la superficie.

Razones públicas permitidas:

```text
coincidencia_busqueda, complemento, alternativa, continuacion, rutina,
descubrimiento, afinidad_cuenta, misma_categoria, popular, novedad, exploracion
```

La razón no revela etiquetas, pesos, historial, score, stock, proveedor ni identidad.

Con el gate apagado, la respuesta estable es `ok=false`, `codigo=SN_APAGADO`; no se toca ni se rompe el catálogo tradicional.

### 5.6 Resumen interno

```sql
sn_resumen_v1(p_desde date, p_hasta date) -> jsonb
```

Exige Marketing y acepta hasta 730 días. Devuelve únicamente agregados consentidos: impresiones, clics, CTR, búsquedas, promedio de resultados y cortes por superficie/modelo. Nunca devuelve visitante, sesión, `request_id`, `consulta_hash` o slug individual.

## 6. Producto JSON común

Búsqueda y recomendación devuelven la misma allowlist por producto:

```text
id
nombre
slug
categoria_codigo
categoria_nombre
categoria_codigos
detalle_presentacion
precio_venta
imagen_banner_path
imagenes
sello_elegido
aviso_urgencia_activo
aviso_urgencia_cantidad
max_comprable
asset {rol,path,ancho,alto,foco_x,foco_y,alt} | null
razon
```

No se devuelve `agotado` porque un producto agotado nunca entra. Tampoco se exponen etiquetas, score, prioridad, intenciones, costos, proveedor, origen de inventario, stock exacto, reservas, piso, IDs externos, cliente o perfil.

## 7. Fotos requeridas

### 7.1 Especificación por rol

| Rol | Relación aceptada | Mínimo | Uso principal |
|---|---:|---:|---|
| `cuadrado` | 1:1, tolerancia ±3% | 1600×1600 | cuadrículas y fallback |
| `vertical` | 4:5, tolerancia ±3% | 1600×2000 | carriles y dúos |
| `horizontal` | 16:9, tolerancia ±3% | 1920×1080 | destacados |
| `panoramico` | 2:1, tolerancia ±3% | 2000×1000 | hero/bandas |
| `recorte` | 1:1, tolerancia ±3% | 2000×2000 | recorte adaptable |

Techos comunes: 8192 px por lado y 40 megapíxeles. La tolerancia se calcula como desviación relativa frente a la proporción objetivo. El procesamiento de la consola nunca agranda una imagen: aplica escala máxima `1`; si el archivo ya tiene exactamente las dimensiones recomendadas, la variante grande las conserva sin redimensionarlo. `foco_x` y `foco_y` son decimales `0..1`, medidos desde la esquina superior izquierda. `alt` es obligatorio, recortado y descriptivo, de `3..240` caracteres y sin saltos de línea. El helper server-side `sn__alt_seguro` —usado por el constraint, la RPC y como defensa adicional de la vista— también rechaza correo, teléfono, UUID, `@handle`, términos de precio/costo/stock/proveedor, símbolos de moneda e importes comerciales evidentes; esa metadata nunca se publica.

### 7.2 Paquete recomendado

Para participar correctamente en todas las composiciones, cada campaña debería tener cinco fotos activas, una por rol. El mínimo operativo es:

- `cuadrado` para resultados/listados;
- `vertical` para carriles;
- `horizontal` para destacados.

`panoramico` y `recorte` completan las composiciones de home y fallback. Si falta el rol requerido, el producto conserva sus campos públicos y `asset` puede ser `null`; el consumidor puede usar `imagen_banner_path`, que ya pertenece al contrato de `catalogo_publico`. SN nunca publica una variante retirada ni toma un asset privado por fuera de `sn_assets_publicos_v1`.

El registro en base no sube, consulta ni borra archivos de Storage. La consola debe subir primero la pareja inmutable: `<rol>-<timestamp>-<random>.webp` y `<rol>-<timestamp>-<random>-sm.webp`; después registra metadata únicamente para el archivo grande. Al retirar una versión interna, la fila histórica permanece y deja de enumerarse o devolverse por `sn_assets_publicos_v1`, búsqueda, recomendación y tienda. La eliminación física queda fuera de SN1: al ser un bucket público, quien ya conozca una URL histórica podría seguir accediéndola. El contrato es retirar exposición en superficies, no revocar físicamente el objeto.

## 8. Ranking, determinismo y diversidad

SN1 es un modelo de reglas auditable, no un modelo opaco. `modelo_version` identifica el conjunto de reglas. La misma entrada y semilla producen el mismo desempate mientras no cambien catálogo, stock, ventanas, eventos comerciales, relaciones o configuración.

La exploración es determinista por semilla, superficie, fecha Bogotá y contexto. El porcentaje indica qué candidatos reciben oportunidad de descubrimiento; nunca salta los filtros duros. La diversidad intercala categorías antes de repetirlas. En búsqueda, la relevancia textual es la primera llave de orden y no puede ser superada por personalización.

Los pedidos anulados o con estado `anulado` no aportan popularidad ni afinidad. La popularidad global solo agrega `pedido_items` de las últimas 365 fechas civiles (hoy y 364 días previos) según `pedidos.fecha_orden` en Colombia. La afinidad de cuenta conserva su historial no anulado, pero parte desde pedidos ya filtrados por el `customer_id` derivado de `auth.uid()`; carrito se filtra por ese UID desde el origen. En ambos recorridos se usa primero `pedido_items.campana_id` y solo las líneas históricas sin ese dato resuelven el fallback por `product_id`. Así cada llamada evita construir una tabla intermedia sobre todo el historial global. Las opiniones ocultas o de prueba quedan fuera porque la señal usa `producto_rating_publico`.

`sn_buscar_v1` y `sn_recomendar_v1` leen el singleton sin `FOR SHARE`: una consulta larga no bloquea el kill switch. La sentencia de ranking vuelve a cruzar `sn_config.activo`; una petición que ya estaba en vuelo puede terminar con el snapshot de su sentencia, mientras las siguientes observan el apagado.

## 9. Privacidad y telemetría consentida

SN1 amplía `tienda_eventos` sin cambiar la firma:

```sql
mt_registrar_eventos(text, text, jsonb, text)
```

Se conservan los seis tipos anteriores y se añaden:

- `recomendacion_impresion`
- `recomendacion_click`
- `busqueda_resultados`

Campos nuevos, todos de lista blanca:

```text
request_id UUID
superficie
slot
posicion
layout_codigo
modelo_version
razon
cantidad_resultados
consulta_hash
```

Reglas de privacidad:

- la captura sigue exigiendo analítica activa, política publicada y consentimiento del navegador;
- la Edge Function no acepta ni reenvía `consulta`, `uid`, `customer_id`, correo, teléfono, referrer o payload libre;
- `request_id` es aleatorio por respuesta y no puede ser `mg_vid` ni sesión; para recomendación se reutiliza el UUID devuelto por el servidor y para el evento de búsqueda el cliente crea uno nuevo con `crypto.randomUUID()` al recibir esa respuesta;
- `razon`, `superficie`, `slot`, layout y modelo son códigos controlados;
- la Edge acepta `consulta_hash` solo como digest hexadecimal y, antes de persistirlo, lo transforma con HMAC-SHA-256 y el secreto `SN_CONSULTA_SAL`; si el secreto no existe o es demasiado corto, omite el campo;
- el navegador nunca envía la consulta cruda y el valor persistido nunca es el digest aportado por el cliente;
- los logs de la Edge Function contienen únicamente un código técnico, nunca mensaje de base, cuerpo, IDs, IP, ruta o hash;
- una clave parcial única admite como máximo una impresión y un clic por `visitante + sesion + request_id + slot + posicion + slug`, y otra admite una búsqueda por `visitante + sesion + request_id`;
- un clic sin impresión equivalente ya aceptada se descarta; los retries que chocan con cualquiera de esas claves también se cuentan como descartados sin tumbar el lote;
- se mantienen límite de 30 eventos por lote y control temporal de 600/h por hash diario de IP;
- la retención objetivo es 13 meses para eventos y 48 horas para límites: el mantenimiento programado es la vía principal y la purga probabilística del 1% durante ingestión queda solo como respaldo.

Forma de `busqueda_resultados`:

```json
{
  "tipo": "busqueda_resultados",
  "request_id": "uuid",
  "superficie": "busqueda",
  "modelo_version": "sn1-reglas-1",
  "cantidad_resultados": 12,
  "consulta_hash": "opcional-64-hex"
}
```

Forma de impresión/clic:

```json
{
  "tipo": "recomendacion_impresion",
  "request_id": "uuid",
  "superficie": "producto_final",
  "slot": "producto_final_01",
  "posicion": 1,
  "layout_codigo": "producto_final_01",
  "modelo_version": "sn1-reglas-1",
  "razon": "complemento",
  "slug": "slug-publico"
}
```

Los eventos históricos ignoran campos SN y conservan su contrato anterior. Para eventos SN, la Edge construye el objeto desde cero: no reenvía `ruta`, origen, UTM, dispositivo ni `entrada`; solo recomendación admite el `slug` público (hasta 180 caracteres). El `id` del módulo se copia tanto a `slot` como a `layout_codigo`, ambos con máximo 80 caracteres.

Esta telemetría es **consentida, aproximada y rate-limited**, no una fuente autoritativa. Visitante, sesión y `request_id` llegan desde cliente; la correlación y los índices reducen dobles conteos accidentales, pero no demuestran una impresión humana ni evitan que un cliente permitido fabrique eventos. Por eso CTR y búsquedas sirven para tendencia operativa, no para contabilidad, facturación ni decisiones individuales.

### 9.1 Purga operativa

`sn_purgar_telemetria()` es `SECURITY DEFINER`, devuelve `eventos_purgados` y `limites_purgados`, no se concede a `anon`, `authenticated` ni `service_role`, y solo `postgres` la ejecuta. Borra `tienda_eventos` con más de 13 meses y `tienda_eventos_limite` con más de 48 horas. La migración **no** crea un trabajo ni habilita extensiones; el repositorio programa `pg_cron` manualmente.

Con `pg_cron` ya disponible y después de confirmar que no existe un job con ese nombre, el comando recomendado —una sola vez— es exactamente:

```sql
select cron.schedule(
  'sn-purgar-telemetria-diario',
  '17 5 * * *',
  $$select public.sn_purgar_telemetria();$$
);
```

La operación no se considera cerrada solo por crear el job. Primero ejecutar `select public.sn_purgar_telemetria();`, cronometrarlo y registrar los dos conteos que devuelve; después confirmar al menos una corrida programada `succeeded` y su duración en `cron.job_run_details`. Debe medirse con el volumen real y revisarse si bloquea ingestión o crece de forma sostenida. El muestreo probabilístico del 1% en `mt_registrar_eventos` sigue activo exclusivamente como respaldo si el job deja de correr.

## 10. Seguridad

- Todas las tablas SN tienen RLS activa.
- `anon` no puede leer tablas base.
- `authenticated` solo obtiene `SELECT` mediado por `tiene_acceso_marketing()`.
- No hay policies ni grants directos de `INSERT`, `UPDATE` o `DELETE`.
- Toda escritura pasa por RPC `SECURITY DEFINER` con `search_path` fijo y objetos calificados.
- Las RPC administrativas solo se conceden a `authenticated` y vuelven a comprobar Marketing/admin internamente.
- Búsqueda y recomendación se conceden nominalmente a `anon`, `authenticated` y `service_role`.
- `mt_registrar_eventos` sigue siendo únicamente `service_role`; `sn_purgar_telemetria` queda cerrada a todos los roles API y solo para `postgres`/mantenimiento manual.
- Helpers `sn__*` y triggers no son ejecutables por roles API.
- La migración termina con gates de contrato y ACL antes del `commit`.

## 11. Fases

### SN1-A · backend estructural — implementada en esta entrega; pendiente de despliegue

- gate global y auditoría;
- configuración editorial y relaciones;
- assets/versiones/layouts;
- búsqueda y recomendaciones públicas;
- resumen interno;
- telemetría consentida compatible.

### SN1-B · integración web — implementada en esta entrega; pendiente de despliegue

- consumo de `sn_buscar_v1` y `sn_recomendar_v1`;
- renderizado de módulos por `tipo`;
- telemetría emitida solo tras consentimiento;
- estados accesibles de vacío, error y `SN_APAGADO`;
- fallback al catálogo tradicional.

### SN1-C · consola editorial — implementada en esta entrega; pendiente de despliegue

- UI para prioridades, intenciones, ventanas, relaciones y assets;
- subida inmutable de la pareja grande/liviana a Storage antes de registrar la metadata maestra;
- vista previa por superficie.

### SN1-D · futura aplicación/evaluación

- reutilizar exactamente los contratos JSON;
- medir relevancia, CTR y cobertura sin PII;
- versionar cualquier cambio de reglas/layouts;
- no activar aprendizaje individual adicional sin decisión y política nuevas.

## 12. Despliegue manual

### 12.1 Preflight

1. Confirmar que `20261111000000_campanas_categorias_oficiales.sql` fue aplicada.
2. Confirmar que existen `catalogo_publico`, cuentas, carrito, pedidos, opiniones, Métricas M1 y `mt_registrar_eventos(text,text,jsonb,text)`.
3. Confirmar una ventana sin escrituras administrativas de Campañas/Métricas; la migración usa `lock_timeout=5s` y revierte completa si no obtiene locks.
4. Conservar una copia del resultado actual de los grants de `mt_registrar_eventos`.

### 12.2 Base de datos

En Supabase SQL Editor, ejecutar **una sola vez y completo**:

```text
supabase/migrations/20261112000000_sistema_nervioso_sn1.sql
```

La forward es transaccional. Si falla baseline, lock, constraint o gate, no debe quedar un SN parcial.

### 12.3 Edge Function

Desplegar el contenido de:

```text
supabase/functions/tienda-eventos/index.ts
```

Nombre exacto: `tienda-eventos`. Mantener **Verify JWT apagado**, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, el secreto recomendado `EM_IP_SAL` y el secreto dedicado `SN_CONSULTA_SAL` de al menos 16 caracteres. Si falta este último, la Edge omite `consulta_hash` en vez de persistir un digest no protegido. La función pública eleva solo para invocar la RPC service-role; CORS no se considera autorización.

Orden recomendado: migración primero, Edge Function después. Una Edge antigua descartaría los campos SN; una Edge nueva antes de la migración produciría eventos que la restricción histórica rechazaría.

### 12.4 Postflight operativo

Comprobar manualmente:

- `sn_config` tiene una sola fila con `activo=true`, personalización `true`, modelo `sn1-reglas-1`, exploración `12`;
- cada una de las seis superficies tiene tres layouts activos;
- `anon` puede ejecutar únicamente `sn_buscar_v1` y `sn_recomendar_v1` de SN, además del máximo público seguro ya usado por catálogo, y puede leer `sn_assets_publicos_v1`, pero no tablas base;
- `authenticated` tiene las ocho RPC SN nominales y sus guardias internas siguen separando Marketing/admin; `service_role` solo tiene como puertas SN búsqueda y recomendación;
- solo `service_role` ejecuta `mt_registrar_eventos`; ningún rol API ejecuta helpers `sn__*` ni `sn_purgar_telemetria`, que conserva `postgres`;
- un retry idéntico de asset devuelve la fila activa existente; metadata divergente o path histórico se rechazan;
- una impresión/clic y una búsqueda duplicadas se descartan, y un clic sin impresión equivalente no se inserta;
- una campaña agotada, despublicada o inactiva no aparece en búsqueda, recomendación ni assets públicos;
- una cuenta solo cambia a modo personalizado con sesión propia y gate permitido;
- eventos anteriores siguen registrándose sin campos SN.

### 12.5 Emergencia y reversa

La reversa operativa es apagar el gate global mediante `sn_configurar_v1(false, ..., razon)` con una cuenta admin. Esto hace que recomendaciones respondan `SN_APAGADO`, que búsqueda entregue lista vacía y que la vista pública de assets SN quede vacía, sin tocar `catalogo_publico` ni borrar historia.

No se recomienda un downgrade destructivo: relaciones, assets, versiones y bitácoras son historia. Corregir mediante una nueva migración forward y reactivar solo después de verificar la causa.
