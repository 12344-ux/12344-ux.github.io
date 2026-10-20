# PLANO · Promocionar P1 · Producto compartible

**Decisión del dueño:** 20 de octubre de 2026
**Estado:** implementación preparada en dos repositorios; producción pendiente
**Depende de:** `docs/PLANO-PROMOCIONAR-P0.md`
**No incluye:** estudio P2, enlaces/clics P3, atribución P4 o métricas P5.

P1 convierte cada ficha pública en una URL estable que genera una preview real
sin congelar precio, stock o disponibilidad. El HTML inicial da identidad y
confianza; la aplicación continúa leyendo la verdad comercial desde Supabase.

---

## 1. Resultado visible

Cada campaña pública tiene una ruta canónica:

```text
https://magandhi.com/producto/<slug>/
```

El HTML entregado sin ejecutar JavaScript incluye:

- nombre y description editorial;
- canonical;
- Open Graph y Twitter Card;
- imagen pública estable;
- JSON-LD `Product`;
- H1, subtítulo, imagen y descripción iniciales;
- controles de compra deshabilitados y precio neutral hasta consultar datos vivos.

No incluye estáticamente:

- `Offer`, precio o moneda;
- disponibilidad, stock o máximo comprable;
- urgencia;
- promedio o cantidad de opiniones;
- proveedor, costo o ids internos.

MAGANDHI no se declara como marca del producto en JSON-LD: es la tienda, no el
fabricante de todos los artículos.

---

## 2. Una sola ficha funcional

`magandhi/producto/index.html` permanece como fuente funcional única. Los
shells `producto/<slug>/index.html` son artefactos deterministas generados desde
esa plantilla, no páginas mantenidas a mano.

La plantilla resuelve, en este orden:

1. `?slug=` o `?id=` por compatibilidad;
2. `data-producto-id`/`data-producto-slug` del shell;
3. slug de `/producto/<slug>/`.

En un shell manda el UUID estable para consultar `catalogo_publico`; el slug
sirve para canonical, analítica y navegación. Tras validar la fila viva:

- actualiza contenido y metadata;
- obtiene precio y disponibilidad reales;
- habilita compra y WhatsApp;
- conserva el candado de retorno Wompi;
- normaliza la URL a la ruta canónica sin perder el fragmento.

Si Supabase falla o el producto está despublicado, no habilita compra y muestra
“Producto no disponible”. El HTML inicial nunca actúa como autoridad comercial.

`<base href="/producto/">` mantiene recursos e imports correctos tanto en la
plantilla como en shells a distinta profundidad.

---

## 3. Fuente SEO versionada

La tienda conserva `producto/catalogo-seo.json`, unido por UUID. Cada entrada
guarda:

- slug actual;
- aliases;
- estado retirado;
- nombre;
- subtítulo;
- descripción;
- paths de imagen pública;
- orden.

No guarda precio, stock, máximo o estado de pago.

Comandos:

```bash
node scripts/generar-productos.mjs --sync
node scripts/generar-productos.mjs
node scripts/generar-productos.mjs --check
```

- `--sync`: consulta de solo lectura a `catalogo_publico`, fusiona por UUID,
  incorpora `campana_slug_alias_publico` cuando exista, preserva aliases y marca
  retirados.
- sin bandera: regenera desde el manifiesto versionado, sin red.
- `--check`: no escribe y falla si shells, aliases, sitemap o robots tienen drift.

El generador no borra directorios y no sobrescribe un `index.html` sin marcador
P1. Esto protege páginas manuales ajenas al sistema.

---

## 4. Receta de metadata

| Campo | Fuente |
|---|---|
| title | `<nombre> · MAGANDHI` |
| description | `hook_largo`, luego subtítulo y fallback honesto; máximo 160 |
| canonical/OG URL | `https://magandhi.com/producto/<slug>/` |
| imagen | primera imagen de galería, luego banner de Campañas y `logo.png` |
| OG | `product`, site name, locale, title, description, URL, imagen segura y alt |
| Twitter | `summary_large_image`, title, description, imagen y alt |
| JSON-LD | `Product`: name, description, image y url; sin Brand u Offer inventados |

Todo texto se escapa para HTML. JSON-LD se serializa y neutraliza `<` para que
contenido editorial no pueda cerrar el `<script>`.

La URL de Storage solo se acepta si pertenece al host Supabase del proyecto y al
bucket público `campanas`; otra URL cae al fallback de marca.

---

## 5. Slugs y aliases server-side

La migración forward
`20261107000000_promocionar_p1_slug_historial.sql` crea:

```text
campana_slug_historial
  slug PK · campana_producto_id · registrado_en

campana_slug_alias_publico
  campana_producto_id · slug_anterior · slug_actual
```

Reglas:

- backfill de todos los slugs actuales;
- un slug usado queda reservado para su campaña original;
- otra campaña no puede reutilizarlo;
- el asignador automático evita slugs históricos ajenos y usa sufijos;
- cambiar el slug registra el nuevo y conserva el anterior;
- una misma campaña puede recuperar un slug propio anterior;
- la tabla es privada; la vista anónima expone solo alias de campañas públicas;
- no se exponen precio, stock, proveedor, producto interno o auditoría.

El alias generado en GitHub Pages no puede emitir HTTP 301: devuelve
`noindex,follow`, canonical al slug actual, meta refresh, `location.replace` y
un enlace visible. Un 301 real exigiría infraestructura de borde y no pertenece
a P1.

---

## 6. Descubrimiento

La tienda genera:

- `sitemap.xml`: mientras `politicas="borrador"`, solo publica la home; al
  cambiar de forma deliberada a `publicada`, la misma generación añade los
  slugs actuales y cambia sus shells a `index,follow`. Nunca incluye
  aliases/query/cuenta/carrito;
- `robots.txt`: permite rastreo y declara el sitemap.

El gate de `robots` y el contenido del sitemap salen del mismo valor versionado,
por lo que nunca se envía una ficha al sitemap mientras declara `noindex`.

Retirar `noindex` es un gate separado que requiere:

1. políticas revisadas y publicadas;
2. shells y sitemap desplegados;
3. HTML inicial medido por HTTP sin JavaScript;
4. imagen social accesible;
5. canonical = OG URL;
6. JSON-LD parseable y sin datos comerciales estáticos;
7. producto inexistente con 404 real y aliases con destino correcto.

---

## 7. Enlaces internos

Home, carrito y Mis compras prefieren `/producto/<slug>/`. El fallback por UUID
se conserva para filas históricas sin slug utilizable. Email Marketing y otras
superficies migrarán al canonical cuando consuman P1; no se rompe la query
existente.

Analítica EM7 reconoce el slug en query, dataset o ruta canónica, siempre detrás
del consentimiento vigente. P1 no introduce un evento nuevo ni activa analítica.

---

## 8. Operación de publicación

Hasta existir una integración automática entre Campañas y GitHub Pages:

1. crear/editar/publicar o despublicar en Campañas;
2. ejecutar `node scripts/generar-productos.mjs --sync` en la tienda;
3. revisar cambios de nombre, descripción, imagen, slug y aliases;
4. ejecutar `--check`;
5. fusionar la tienda y esperar Pages;
6. medir por HTTP shell, canonical, sitemap e imagen.

Una fila pública nueva puede aparecer dinámicamente antes de tener shell. Home
usa el canonical cuando hay slug, así que la sincronización forma parte del
cierre operativo de publicación. No se afirma que un producto nuevo esté listo
para compartir hasta que su shell responda 200.

---

## 9. Orden de despliegue

1. Banco de pruebas de ambos PR.
2. Preflight P1 de solo lectura en Supabase.
3. Aplicar una vez la migración de historial.
4. Postflight de solo lectura.
5. Ejecutar `--sync` en la tienda ya con la vista de aliases.
6. Fusionar/publicar tienda.
7. Esperar Pages.
8. Medir los seis shells actuales, sitemap, robots y compatibilidad query/UUID.
9. Probar PC, móvil, JavaScript deshabilitado y fallo de Supabase.
10. Actualizar contexto con evidencia productiva; no antes.

Runbook: `supabase/operacion/PROMOCIONAR-P1-DESPLIEGUE.md`.

---

## 10. Criterios de cierre

### Código preparado

- [x] Una plantilla funcional y shells deterministas.
- [x] Metadata inicial por producto sin precio/stock.
- [x] URLs internas canónicas con fallback UUID.
- [x] Sitemap y robots.
- [x] Sin JavaScript hay identidad útil y cero compra habilitada.
- [x] Generador con sincronización y comprobación de drift.
- [x] Historial/alias server-side preparado como migración forward.
- [x] P2–P5 fuera de alcance.

### Cierre productivo pendiente

- [ ] Migración aplicada una vez con preflight/postflight correctos.
- [ ] Vista pública de aliases medida.
- [ ] Tienda fusionada y Pages terminado.
- [ ] Todos los shells responden 200 con metadata correcta.
- [ ] Compatibilidad query/UUID y retorno Wompi verificados.
- [ ] Resultado PC/móvil/sin JS archivado.
- [ ] `noindex` permanece hasta publicar políticas; su valor final se registra.

P1 no queda cerrado en producción por existir código o un PR. Requiere completar
la segunda lista con evidencia real.
