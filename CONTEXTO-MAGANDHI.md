# MAGANDHI + Impulse · contexto operativo vigente

**Corte:** 7 de octubre de 2026
**Producción interna:** `https://montaguth.institute`
**Tienda pública:** `https://magandhi.com`

Este archivo es la entrada única para entender dónde está parado el proyecto. Sustituye las cartas de sesión y estados intermedios que antes convivían aquí. La historia completa permanece en Git; este documento describe únicamente la realidad operativa y los pendientes vigentes.

## 1. Separación de superficies

### MAGANDHI — tienda pública

- Repositorio: `12344-ux/magandhi`.
- Dominio: `magandhi.com`.
- Atiende clientes y muestra catálogo/productos.
- Nunca menciona Impulse ni expone la arquitectura interna.
- Identidad: terracota `#A6332E`, negro `#111111`, dorado `#C28A3A`, arena `#EFE7DD`, Poppins y logo maestro SVG.

### Control interno con tecnología Impulse

- Repositorio: `12344-ux/12344-ux.github.io`.
- Dominio: `montaguth.institute`.
- Gestiona datos propios de la organización.
- MAGANDHI es el piloto de una arquitectura clonable para otras organizaciones.
- Las áreas usan azul operativo; Finanzas conserva verde funcional. El acceso general usa la identidad comercial vigente de MAGANDHI.

**Regla:** Impulse analiza y gestiona datos propios. No inventa datos de mercado, competencia o tendencias externas que la organización no posee.

## 2. Estado actual por área

### Acceso y autorización

- Login por Supabase Auth en `index.html`.
- Panel modular en `panel.html`.
- Guardia reutilizable en `auth-guard.js`.
- `perfiles` define rol y módulos.
- Las 30 páginas internas cargan la guardia.
- La visibilidad del frontend es UX; el candado real son RLS, grants y RPC.

### Finanzas — operativo

- Catálogo PUC colombiano.
- Asientos de partida doble con validación server-side.
- Libro Diario y Libro Mayor.
- Edición/anulación con bitácora; no se borra historia.
- Balance de comprobación, Estado de resultados y Balance general.
- Exportación PDF/CSV.
- Montos `bigint` en pesos enteros.
- Escritura normal únicamente mediante RPC.

Pendiente real: cierre anual cuando cambie el ejercicio fiscal y pulido de exportaciones basado en uso real.

### Producción / Inventarios — operativo

- Catálogo de productos.
- Libro append-only de movimientos.
- Stock derivado; puede ser negativo como señal honesta de conciliación.
- Alta, consulta y movimientos.
- Imágenes optimizadas.
- Inventario es la fuente de verdad de existencias; Campañas no declara stock manual.

### Marketing — operativo

**Campañas**

- Crea/edita fichas comerciales y galería.
- Liga la campaña con un producto de Inventario mediante `product_id_ref`.
- Maneja precio web, slug, publicación, sello, estrella, aviso de urgencia, tope y etiquetas.
- Sube imagen grande y variante `-sm` al bucket `campanas`.
- La categoría clasifica; no cambia la paleta pública.

**Marketing Project**

- Proyección de demanda: promedio móvil, suavización exponencial y regresión lineal.
- Medidas de tendencia central.
- Ranking por unidades o ingreso, distinguiendo fuente real/mixta/estimada.
- Clúster y elasticidad siguen como roadmap, no como módulos terminados.

### Gestión de opiniones — operativo

Quinta área del panel, en `opiniones/`. Guarda las opiniones verificadas de clientes y les da seguimiento.

- Listado de productos con opinión, ordenado por la reseña más reciente primero.
- Detalle por producto con promedio real, distribución por estrella y las opiniones de la más antigua a la más reciente.
- Respuesta pública de marca por opinión, editable y removible.
- Moderación con trazabilidad: «borrar» es ocultar con bitácora de quién, cuándo y por qué, y es reversible. Una opinión oculta sale de la web y del promedio pero no se destruye.
- Las opiniones verificadas se publican de forma automática, incluidas las negativas reales. Ocultar se reserva para abuso, spam o falsedad, nunca para silenciar críticas.
- Marcador `es_prueba` para ensayar el flujo sin contaminar promedios.

Verificación de compra sin inicio de sesión: cada pedido lleva un código de reseña único e imposible de adivinar (`pedidos.codigo_resena`), generado por disparador al crear el pedido. La tienda envía ese código a la Edge Function `enviar-opinion`, que llama al RPC `op_registrar_opinion`; este valida el código, exige que el pedido esté entregado, confirma que el producto pertenecía a ese pedido y admite una sola opinión por producto-pedido. La autorización es la posesión del código, no una sesión.

Coherencia del promedio, decisión del dueño: se muestra el promedio real a un decimal **siempre acompañado del total**. No se usa media bayesiana ni suavizado, porque rompería la coherencia con las tarjetas visibles.

Pendiente real: hacer llegar el código al cliente en el último correo de seguimiento. Requiere montar el envío de correos de MAGANDHI, que todavía no existe. Hasta entonces el código se comparte a mano desde el back-office.

### Ventas — operativo

- Seguimiento de pedidos.
- Registro manual con cliente, items y snapshot de dirección.
- Avance de estado con bitácora.
- Anulación transaccional y movimientos compensatorios de inventario.
- Portafolio de clientes con métricas derivadas de pedidos reales.

Pendiente real: entrada automática desde Wompi F2.

## 3. Supabase: estado acumulativo

- Un proyecto compartido por tienda y back-office.
- Auto-RLS activado y exposición automática de tablas desactivada.
- Las migraciones históricas son inmutables: nunca se reescriben ni se reejecutan para “corregir” producción.
- Toda corrección nueva se hace con migración forward.
- Las superficies anónimas deliberadas son tres y todas exponen lista blanca: `catalogo_publico`, `producto_rating_publico` y `opiniones_publicas`. Ninguna otra tabla o vista interna tiene acceso para `anon`.
- Las vistas internas sensibles son `security_invoker`.
- Tramo 0 fue verificado en producción: matriz de permisos completa, anon bloqueado en vistas/RPC internas y catálogo público disponible.

### Migración nueva de puesta al día

`supabase/migrations/20261002000000_puesta_al_dia_seguridad_operativa.sql`:

1. una campaña sin Inventario ligado se considera no comprable;
2. publicar exige producto ligado/activo y precio positivo;
3. retira policies latentes de escritura directa en Finanzas;
4. añade DELETE acotado para la compensación de imágenes del bucket `campanas`.

**Escribirla en el repo no la despliega.** Debe ejecutarse manualmente en SQL Editor y registrar evidencia.

## 4. Contrato tienda ↔ back-office

### Fuente de verdad

- Identidad del producto y costo interno: `productos`.
- Stock: suma de `movimientos_inventario`.
- Presentación y precio web: `campana_producto`.
- Catálogo anónimo: `catalogo_publico`.
- Cliente/pedido: `clientes`, `pedidos`, `pedido_items`, `pedido_bitacora`.
- Opiniones: `opiniones`; superficies anónimas `producto_rating_publico` y `opiniones_publicas`; código de verificación en `pedidos.codigo_resena`.

### Catálogo público

Expone datos necesarios para home/producto y el booleano `agotado`. Nunca expone:

- existencias exactas;
- costo o proveedor;
- `product_id_ref`;
- tope interno;
- placeholders;
- etiquetas internas.

Una campaña puede existir como borrador sin Inventario, pero no debe publicarse ni firmar checkout hasta estar ligada.

### Imágenes

- Bucket público de lectura: `campanas`.
- Escritura/borrado: sesión autenticada con acceso Marketing.
- Grande: hasta 1600px.
- Liviana: hasta 800px y sufijo `-sm`.
- Solo se guarda la key grande; la tienda deriva el nombre liviano y cae a grande si falta.
- Subidas con keys aleatorias y `upsert=false`.

## 5. Wompi

### F1 — terminado en sandbox

- Formulario de comprador en la tienda.
- Edge Function `crear-intencion-pago`.
- Precio releído server-side.
- Cantidad fijada a 1.
- Firma de integridad calculada con secreto de servidor.
- Checkout de Wompi cargando métodos de pago.
- Retorno por slug y respaldo por UUID.

Después de modificar la Edge Function, el archivo del repo debe redesplegarse manualmente. El repo no demuestra por sí solo qué versión está desplegada.

### F2 — siguiente tramo, todavía no existe

Debe incorporar:

- intención persistida antes de firmar;
- tabla de pagos/estado;
- webhook autenticado;
- idempotencia;
- revalidación y serialización de stock;
- creación automática de pedido una sola vez;
- ruta de recuperación para eventos fallidos.

**No activar producción ni aceptar dinero real antes de cerrar F2.**

### F3/F4

- F3: asiento contable automático desde pago aprobado.
- F4: validación integral y cambio controlado de sandbox a producción.

## 6. Seguridad vigente y deuda reconocida

- Nunca exponer `service_role`, secretos Wompi ni llaves privilegiadas en frontend/repositorio.
- La publishable key es pública por diseño; RLS/grants son el control.
- No confiar en ocultar botones como seguridad.
- No reescribir ni borrar movimientos, pedidos, asientos o bitácoras.
- D3 (permisos más granulares) sigue pendiente y debe cerrarse antes del primer usuario no-admin.
- El acceso amplio actual se tolera únicamente mientras la operación tenga un solo administrador.
- La documentación pública usa placeholders; datos personales/legales no se repiten en contexto o instrucciones.

## 7. Marca y assets

- Logo comercial maestro: repositorio `magandhi`, `marca/logo/logo-magandhi.svg`.
- Los PNG generales del back-office son copias verificadas de sus derivados actuales; no se hotlinkean entre dominios.
- `marca.css` del back-office gobierna login/panel, no toda la tienda pública.
- Favicons por área viven en `marca-areas/`.
- Los iconos de Marketing, Producción y Ventas aún comparten temporalmente el arte azul general; no son 404 ni logos oficiales distintos.

## 8. Estado de documentación

- `CONTEXTO-MAGANDHI.md`: fotografía operativa actual.
- `ANDAMIOS.md`: próximos tramos y criterios de cierre.
- `supabase/INSTRUCCIONES.md`: runbook acumulativo; sus capítulos antiguos son historia y no autorizan reaplicar migraciones.
- `docs/PLANO-INVENTARIO.md`, `docs/PLANO-VENTAS.md` y `docs/PLANO-OPINIONES.md`: memoria histórica de diseño, no DDL operativo.
- `docs/MAPA-CONEXIONES-TANDA2.md`: mapa técnico de las conexiones ya implementadas.

## 9. Próximo orden de trabajo

1. Montar el envío de correos de MAGANDHI y entregar el código de reseña en el último correo de seguimiento. Es lo único que falta para que entren opiniones reales.
2. Aplicar y verificar la migración `20261002000000`.
3. Redesplegar y verificar `crear-intencion-pago`.
4. Construir Wompi F2 en sandbox.
5. Implementar F3 y validar contabilidad.
6. Ejecutar F4 antes de producción.
7. Cerrar D3 antes de delegar accesos.
8. Crear políticas públicas en la tienda.

## 10. Reglas de entrega

- Rama nueva + PR nuevo por cambio; nunca push directo a `main`.
- Verificar si un PR ya fue fusionado antes de reutilizar una rama.
- Un comando sin error no es evidencia suficiente.
- SQL en el repositorio no equivale a SQL desplegado.
- Edge Function en el repositorio no equivale a función desplegada.
- No hacer gold-plating: construir el siguiente tramo que desbloquea la operación real.
