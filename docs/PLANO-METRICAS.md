# PLANO · Métricas (sexta área del back-office)

**Corte:** 8 de octubre de 2026 · **Estado:** M1 construido y probado (pendiente de aplicar/desplegar). Siguiente: M2.

## 0. Qué es

Métricas **recolecta** datos de toda la operación, los **organiza** y los **muestra** en gráficas. No los interpreta: la lectura la hace el equipo (filosofía Impulse «escupe datos»).

```
 RECOLECTA                     ORGANIZA                        MUESTRA / ALIMENTA
 Tienda (EM7) ──eventos──▶ ┌────────────────────┐ ──▶ Métricas (equipo)
 Ventas ─────────────────▶ │ Capa de datos mt_* │ ──▶ Marketing, Ventas y
 Email, Opiniones (M2) ──▶ │ (series y KPIs)    │     futuros softwares
                            └────────────────────┘
```

La **capa de datos** (funciones `mt_*` en la base) es la pieza clave: Métricas no calcula para su pantalla. Cualquier software interno pide la misma función y obtiene el mismo número.

## 1. Permisos

- Área: módulo propio `metricas` (`tiene_acceso_metricas()`). El admin la ve siempre.
- Capa de datos: `tiene_acceso_datos_metricas()` = `metricas` **o** `marketing` **o** `ventas`. Solo devuelve **agregados sin datos personales**.
- Interruptor de la analítica: solo admin, y solo con la política registrada.

## 2. M1 · lo construido

### Captura web (EM7)
- Script propio `magandhi/analitica/analitica.js`: sin Meta ni Google. Aviso con **Aceptar** y **Rechazar** del mismo tamaño. Solo mide a quien acepta; quien rechaza no recibe identificador.
- Eventos: `pagina_vista`, `producto_visto`, `clic_comprar`, `checkout_iniciado`, `llegada_campana` y `compra` (esta última llega con Wompi F2).
- Por evento se guarda:
  - el id aleatorio del navegador (`mg_vid`) y una sesión de 30 min;
  - la ruta y el slug;
  - el **origen ya clasificado** (directo, email, instagram, facebook, whatsapp, buscador, otro_sitio). Nunca se guarda la URL de procedencia;
  - el dispositivo (celular, tablet o computador);
  - la campaña (`utm_campaign`).
- Sin IP, sin navegador, sin correo. Límite de 600 eventos por hora por hash de IP (sal diaria). Bots descartados. Retención de 13 meses.
- Edge Function `tienda-eventos` (Verify JWT apagado) → `mt_registrar_eventos` (solo `service_role`).

### Capa de datos
| Función | Devuelve |
|---|---|
| `mt_en_vivo()` | Visitantes en los últimos 5 y 30 min y en el día, pedidos e ingresos de hoy frente al mismo día de la semana pasada, hoy hora a hora, páginas activas, actividad reciente y últimos pedidos (sin cliente). |
| `mt_ventas(desde, hasta)` | Totales y periodo anterior de igual largo, serie diaria, canal, productos, ciudades, mapa de calor día × hora y clientes nuevos. |
| `mt_tienda(desde, hasta)` | Visitantes, sesiones y vistas frente al periodo anterior, serie diaria, embudo, productos vistos, páginas, orígenes, dispositivos, campañas y mapa de calor. |

### Pantallas (`metricas/`)
- **En vivo**: se refresca cada 30 s y se pausa si la pestaña no está visible.
- **Ventas** y **Tienda**: periodos de 7, 30 y 90 días y 12 meses.
- Gráficas propias en SVG (`metricas-core.js`): línea con comparación, barras, ranking, reparto, mapa de calor, embudo y minigráficas. Todas se adaptan al ancho y muestran el dato exacto al pasar el cursor o tocar.
- Mismo azul marino del back-office. El color tiene función: el terracota marca «la hora actual» y verde/terracota marcan si una cifra sube o baja.

## 3. Límite honesto

Sin Wompi F2 nadie se identifica en la web. Por eso la interacción **por cliente** (por ejemplo, «vio el producto X» como variable del clúster o condición de segmento) todavía no existe. El enchufe es que F2 guarde el `mg_vid` del comprador en el pedido.

## 4. M2 · siguiente

Pestañas **Email** (lista y campañas), **Opiniones** e **Inventario** (stock, rotación y días de inventario). Conexión de la capa con el clúster y los segmentos cuando exista la identificación de F2.

## 5. Relevo para la próxima sesión: M2 (8-oct-2026)

### 5.1 Estado

- **M1 mergeado** (back-office PR #238 y tienda PR #87). **Confirma con el dueño** si ya aplicó `20261016000000_metricas_m1.sql`, si desplegó `tienda-eventos` con Verify JWT apagado y si probó la sección MT1.3 de `INSTRUCCIONES.md`.
  - Sondeo sin escribir nada: `POST https://bxlzipwxyxdtffnuizbz.supabase.co/functions/v1/tienda-eventos` con `{"modo":"config"}` debe responder `{"activa":…}`.
  - Llamar `rpc/mt_en_vivo` con la llave publishable debe dar `permission denied` (42501). Si da «not found», la migración no está aplicada.
- **Antes de M2**, verifica también EM6 (`em-suscripcion`): el dueño no ha confirmado la prueba de su paso 5.
- Las políticas de magandhi.com son **estructura provisional** (`borrador-0`). El dueño escribirá el texto definitivo antes de abrir la tienda; no las redactes tú.

### 5.2 Qué construir en M2

1. **Pestaña Email.** Crecimiento de la lista (altas y bajas por semana, estados), campañas lado a lado (entregados, clics, pedidos) y salud de la lista frente a los límites de Resend.
   - Fuentes que ya existen: `em_resumen`, `em_campanas_resultados_lista`, `em_campana_resultados` y `em_salud_lista`.
   - Lo correcto es crear `mt_email(desde, hasta)` en la capa de datos, que reúna eso con series diarias. No llames esas funciones directo desde la página: tienen otra guardia (`email_marketing`).
2. **Pestaña Opiniones.** Promedio real (siempre con el total N, **sin** suavizado bayesiano: regla del dueño), distribución por estrellas, opiniones por mes, % de pedidos entregados con opinión y productos por promedio.
   - Fuentes: `opiniones` (excluir `es_prueba` y `oculta`) y `pedidos`.
3. **Pestaña Inventario.** Stock por producto, unidades vendidas por semana, días de inventario restante (stock ÷ venta diaria promedio de los últimos 30 días, rotulado «estimado») y alertas de bajo stock.
   - Fuentes: `stock_actual`, `movimientos_inventario`, `pedido_items` y `productos`.
4. **Conexión con el clúster y los segmentos.** Solo cuando exista la identificación de Wompi F2 (el `mg_vid` del comprador guardado en el pedido). Mientras no exista, documéntalo y no inventes la unión.

### 5.3 Cómo se agrega una pestaña

- En `metricas/metricas-core.js` se suma a `PESTANAS`. La página nueva copia la estructura de `ventas.html`: `<main id="mt-main" hidden>`, `montarArea({activa, titulo, lead})` y una sola RPC `mt_*`.
- Componentes disponibles:
  - `kpi`, `delta`, `pintarSparks`;
  - `grafLinea` (con `clase:'comp'` para comparar y `'sec'` para una serie secundaria), `grafBarras`;
  - `filas`, `reparto`, `calor`, `embudo`, `vacio`, `chipsPeriodo` y `rangoDe`.
- Cada RPC nueva va **guardada** con `tiene_acceso_datos_metricas()`, `security definer`, devuelve solo agregados y con la zona horaria `America/Bogota`. Agrégala a la **lista blanca** de `supabase/pruebas/matriz-permisos.sql`; el conteo es dinámico.
- Cache-bust: `metricas.css?v=4` hoy. Si cambias el CSS, súbelo en **todas** las páginas de `metricas/`.

### 5.4 Estándar de diseño (el dueño lo exige: es lo que el equipo verá todos los días)

- Mismo azul marino, sin color nuevo. El terracota solo para «ahora» o lo que hay que mirar; verde y terracota solo para variaciones. Cifras tabulares, y en millones con 2 decimales («$2,97 M», no «$3 M»).
- Cada tarjeta tiene título, una línea de contexto y su **estado vacío** honesto, que dice qué aparecerá y por qué todavía no hay datos.
- Revisión obligatoria en PC 1280 y celular 390:
  - sin desborde ni elementos cortados (la prueba `desb` revisa chips, KPI y títulos dentro de su contenedor);
  - lectura al pasar el cursor;
  - capturas con `--capturas` mirando **una** por mensaje.
- Errores que ya se corrigieron en M1 (no los repitas):
  - el selector de serie cortado en celular (por eso las cabeceras de tarjeta bajan a otra línea);
  - la guía de lectura visible antes de pasar el cursor;
  - la variación verde sin contraste sobre la tarjeta oscura;
  - rótulos de KPI tan largos que se parten en dos líneas.

### 5.5 Banco de pruebas

`supabase/pruebas/local/herramientas/LEEME.md`. Se arma con `bash supabase/pruebas/local/herramientas/preparar.sh` y la ejecución de M1 es `correr-ui-metricas.sh --capturas`. Para M2:

- extiende `semilla-metricas.sql` con opiniones, movimientos de inventario y eventos de email;
- crea `metricas-m2.sql` con las comprobaciones de los cálculos;
- amplía `probar-ui-metricas.py`.
