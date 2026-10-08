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
