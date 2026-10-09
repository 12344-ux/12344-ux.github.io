# MAGANDHI + Impulse · contexto operativo vigente

**Corte:** 9 de octubre de 2026
**Producción interna:** `https://montaguth.institute`
**Tienda pública:** `https://magandhi.com`

Este archivo es la entrada única para entender dónde está parado el proyecto: la realidad operativa (§2 a §7) y el trabajo pendiente (§9). La historia completa permanece en Git.

> **Punto de unificación · 9-oct-2026.** Se cerraron todos los frentes que estaban abiertos a la vez. Todas las migraciones hasta `20261020000000` (F3) están aplicadas en producción, salvo `20261002000000`, que quedó superada. La cadena de pagos Wompi F1 → F4 está en producción y **el dueño verificó el sistema completo con una compra real**: pago, pedido, stock, asiento contable automático, correos y opinión. Desde aquí se trabaja desde un solo lugar. `ANDAMIOS.md` y los relevos de sesión se retiraron porque ya cumplieron su función; siguen en el historial de Git.

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
- **Ventas web automáticas (F3, en producción, verificado con la compra real del 9-oct):** cada venta web real entra sola al Diario, contra la cuenta puente 138095 (Wompi por liquidar), y anular el pedido registra el contraasiento. Los asientos automáticos se marcan y no se editan desde Finanzas. Si a una venta le falta algo (el IVA o el costo), aparece en la portada con el motivo y el botón «Registrar asiento». La liquidación de Wompi sigue siendo manual. Ver `docs/PLANO-PAGOS.md` §10.

Pendiente real: cierre anual cuando cambie el ejercicio fiscal y pulido de exportaciones basado en uso real.

### Producción / Inventarios — operativo

- Catálogo de productos.
- Libro append-only de movimientos.
- Stock derivado. Las ventas no pueden dejarlo negativo (bloqueo firme en `crear_pedido`); los ajustes manuales de Inventario conservan su contrato.
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
- Análisis de clúster operativo (EM3). Elasticidad sigue como roadmap.

### Email marketing — EM1 a EM7 en producción

Marketing → Email marketing. Diseño completo en `docs/PLANO-EMAIL-MARKETING.md`.

- Módulo propio `email_marketing` (la lista es PII; el de Marketing no basta).
- Contactos con prueba del consentimiento (texto aceptado, versión de política, canal, detalle y confirmación del operador), estados y bitácora imborrable.
- Alta manual con evidencia obligatoria, edición de temas (Novedades / Ofertas), baja con motivo y reactivación solo con nueva autorización.
- Vínculo automático contacto ↔ cliente por correo (trigger).
- Resumen (suscritos, crecimiento por semana, estados, fuentes, temas, clientes con correo aún sin autorizar) y «Correos de seguimiento» (historial de los avisos del pedido).
- EM2: perfil por cliente con datos propios (valor, precio y rebajas, productos y categorías, opiniones, lugar, franja y día de compra, canal) y **Segmentos** por condiciones con vista previa en vivo; la audiencia de una campaña será siempre segmento ∩ suscritos.
- EM3: **Análisis de clúster** en Marketing Project (k-means++ con semilla fija, silueta, retrato en palabras, mapa, comparativo, CSV; reglas de pocos datos) y «Guardar como segmento» congelado.
- EM4: **Campañas** por bloques (título, texto, imagen, producto destacado, botón único, separador), vista previa PC/celular, prueba a tu correo, revisión final con N exacto, envío o programación vía Resend Broadcasts desde `news.magandhi.com`, cancelación. Envío real bloqueado hasta registrar la política publicada.
- EM5 (en producción, webhook de Resend conectado y verificado): webhook firmado `em-webhook` (Svix, Verify JWT apagado, escribe solo como service_role), supresión automática con historial, resultados por campaña (embudo, enlaces, rebotes/spam/bajas, ventas exactas y aproximadas con último clic + 7 días), salud de la lista contra los límites de Resend, entrega de los correos del pedido. Eventos crudos 13 meses.
- EM5.1: la respuesta a email alimenta el análisis. 5 variables en el clúster (campañas recibidas, % con clic, clics 90 días, días desde el último clic, compras atribuidas) y 9 condiciones en Segmentos (hizo/no hizo clic en una campaña, campañas seguidas sin clic…). Sin aperturas: son aproximadas.
- EM6 (en producción, **apagado a propósito**): formulario de novedades en magandhi.com con doble confirmación (`em-suscripcion`), apagado por defecto y encendible solo por admin con la política registrada. Política en versión `borrador-*` para probar: esos contactos nunca reciben campañas reales. Captura pública (EM6) y analítica (EM7) esperan la política.

### Métricas — M1 y M2 en producción (analítica apagada a propósito)

Sexta área del panel (`metricas/`), módulo propio `metricas`. Recolecta, organiza y muestra (no interpreta). M1 (en producción): pestañas En vivo (refresco 30 s), Ventas y Tienda con gráficas propias en SVG. Capa de datos compartida `mt_*` (agregados sin PII) que también consumen Marketing y Ventas. Analítica propia de la tienda (EM7) con aviso de consentimiento, sin Meta/Google, sin IP ni URLs de procedencia, 13 meses. M2 (en producción): pestañas **Email** (crecimiento de la lista, campañas lado a lado, salud frente a Resend), **Opiniones** (promedio real con su total, distribución, por mes, cobertura, productos) e **Inventario** (existencias, rotación, días de inventario estimado, alertas). Diseño en `docs/PLANO-METRICAS.md`. Banco de pruebas local reutilizable: `supabase/pruebas/local/herramientas/LEEME.md`.

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

Entrega del código: va en el correo de «Entregado», ya en producción. Opiniones reales habilitadas.

### Ventas — operativo

- Seguimiento de pedidos.
- Registro manual con cliente, items y snapshot de dirección.
- Avance de estado con bitácora.
- Anulación transaccional y movimientos compensatorios de inventario.
- **Bloqueo firme de stock** (8-oct-2026): no se registra un pedido que pida más unidades de las disponibles en Inventario; el candado vive en `crear_pedido`, serializa ventas simultáneas y aplica también a la futura entrada web (Wompi F2). Registrar pedido muestra «Disponibles: N» y marca los agotados.
- Portafolio de clientes con métricas derivadas de pedidos reales.

- Correos del pedido: un correo por etapa, enviado a mano desde el detalle en Seguimiento. El de «Entregado» lleva el código de reseña. Proveedor: Resend, subdominio `updates.magandhi.com`. Los textos viven en `correo_plantillas` y se cambian con un SQL que entrega Kiro (el editor `ventas/correos/` se retiró en EM1). Diseño en `docs/PLANO-CORREO.md`.

- Entrada automática desde Wompi (en producción): un pago aprobado crea el pedido `canal = web` una sola vez y baja el stock, y el correo «Recibido» sale solo. Las demás etapas se envían a mano desde Seguimiento.

## 3. Supabase: estado acumulativo

- Un proyecto compartido por tienda y back-office.
- Auto-RLS activado y exposición automática de tablas desactivada.
- Las migraciones históricas son inmutables: nunca se reescriben ni se reejecutan para “corregir” producción.
- Toda corrección nueva se hace con migración forward.
- Las superficies anónimas deliberadas son tres y todas exponen lista blanca: `catalogo_publico`, `producto_rating_publico` y `opiniones_publicas`. Ninguna otra tabla o vista interna tiene acceso para `anon`.
- Las vistas internas sensibles son `security_invoker`.
- Tramo 0 fue verificado en producción: matriz de permisos completa, anon bloqueado en vistas/RPC internas y catálogo público disponible.

### Puesta al día

`20261002000000_puesta_al_dia_seguridad_operativa.sql` quedó **superada y no se aplica**: hoy haría retroceder la vista `catalogo_publico`. Su contenido vigente se reemitió forward en `20261018000000_puesta_al_dia_sin_vista.sql` (aplicada antes de F2). Detalle en `supabase/INSTRUCCIONES.md` §0.

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

## 5. Wompi · pagos web — en producción

Diseño completo en `docs/PLANO-PAGOS.md` y runbook en `supabase/INSTRUCCIONES.md` (F1, F2 y «Pagos F3»).

| Tramo | Qué hace |
|---|---|
| F1 | La tienda pide la intención y `crear-intencion-pago` relee el precio server-side, firma la integridad y abre el checkout |
| F2 | La intención se guarda antes de firmar. `wompi-webhook` verifica la firma real y el pago aprobado crea el pedido web **una sola vez**, con el candado de stock. Un pago aprobado que no se pudo convertir sale como aviso rojo en Ventas |
| F3 | Asiento contable automático de la venta real contra 138095 y contraasiento al anular. Correo «Recibido» automático. Los pagos de prueba (sandbox) no tocan los libros |
| F4 | URL de eventos de producción corregida, secretos y llave pública de producción cargados, interruptor `pagos_config.entorno` |

**Verificado el 9-oct-2026 con una compra real** (el shampoo, $69.900, pagado con Nequi):
- el pedido web y una unidad menos en Inventario;
- el asiento automático (138095 D 69.900 · 413505 H 69.900 · 613505 D / 143505 H 47.705, el costo);
- los correos de cada etapa, con el código de reseña;
- una opinión real.

Wompi abonó $66.862,71: descontó 2,65 % + $700 más el IVA de la comisión, sin retenciones porque fue con Nequi.

**Interruptor:** `entorno = 'prod'` cobra dinero real y `'sandbox'` vuelve a pruebas al instante. Lo decide el dueño según la fecha de lanzamiento.

**La liquidación es manual:** cuando Wompi consigna, el asiento lleva el banco por el neto y 530515 por la comisión con su IVA, más las retenciones si el pago fue con tarjeta, contra 138095 por el bruto. 138095 en cero = todo conciliado. Ver `supabase/INSTRUCCIONES.md` PF3.6.

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

- `CONTEXTO-MAGANDHI.md`: fotografía operativa actual **y** trabajo pendiente (§9). Es el punto de partida de cualquier sesión.
- `supabase/INSTRUCCIONES.md`: runbook acumulativo. Sus capítulos antiguos son historia y no autorizan reaplicar migraciones.
- `docs/PLANO-PAGOS.md`: diseño de pagos web F1 a F4 y los dos asientos (venta y liquidación).
- `docs/PLANO-EMAIL-MARKETING.md` y `docs/PLANO-METRICAS.md`: diseño vigente de esas áreas.
- `docs/PLANO-INVENTARIO.md`, `docs/PLANO-VENTAS.md`, `docs/PLANO-OPINIONES.md` y `docs/PLANO-CORREO.md`: memoria histórica de diseño, no DDL operativo.
- `docs/MAPA-CONEXIONES-TANDA2.md`: mapa técnico de las conexiones ya implementadas.
- `supabase/pruebas/diagnostico-produccion.sql`: diagnóstico de solo lectura para medir producción sin fiarse de los documentos.
- `supabase/pruebas/local/herramientas/LEEME.md`: banco de pruebas local (también corre en GitHub Actions en cada rama).

Retirados el 9-oct-2026 porque ya cumplieron su función: `ANDAMIOS.md` (plan de tramos) y los relevos de sesión. Su contenido vigente quedó en §5 y §9.

## 9. Pendientes vigentes

No hay nada a medias. Lo que sigue, por orden sugerido:

**Contabilidad (lo primero, depende de Wompi):**
1. Asiento de **liquidación** de la venta del 9-oct cuando Wompi consigne, con la fecha real del abono:
   - D 111005 por lo que llegó al banco;
   - D 530515 por la diferencia hasta 69.900;
   - C 138095 69.900.

   Wompi informa $66.862,71, pero los asientos van en pesos enteros: se usa el valor entero que figure en el extracto del banco (≈ 66.863 y 3.037).
2. **Inventario inicial en libros:** si la mercancía no tiene asiento de apertura (fila 23 del diagnóstico), registrarlo. La contrapartida la define el contador según cómo se compró.

**Tienda (pequeños, antes del lanzamiento):**
3. **Confirmación al volver de Wompi.** Hoy la ficha del producto se ve igual y el botón queda activo: la persona podría pagar dos veces. La vuelta trae `?ref=`, así que hay que mostrar «Recibimos tu pago» y consultar el estado por referencia sin datos personales. También restaurar el botón en `pageshow`.
4. **Detalles de entrega** (apartamento, torre) que no llegan al pedido: enviar `direccion + ' · ' + detalles` como `comprador.direccion`. El documento del comprador solo viaja a Wompi; guardarlo para la factura es una decisión pendiente y requiere una columna nueva.
5. **Mensajes de error de pago siempre genéricos:** leer el JSON de `error.context`, con el mismo patrón de `suscripcion/suscripcion.js`.

**Producto y operación:**
6. Copys definitivos de los correos del pedido (`correo_plantillas`, hoy en borrador; se cambian por SQL) y de las políticas públicas (estructura provisional en magandhi.com/politicas/).
7. Decidir si la tienda queda en producción o vuelve a sandbox hasta el lanzamiento (§5).
8. Finanzas, siguiente: asiento automático de las **ventas manuales** (pedir la forma de pago al registrar) y de las **compras de mercancía** (costo del lote y forma de pago en «Registrar entrada»).
9. **D3** (permisos granulares por capacidad en panel, grants, RLS y RPC) antes del primer usuario que no sea admin.
10. Menores: el canal web visible en la lista de Seguimiento (hoy solo en el detalle), el cierre anual de Finanzas cuando cambie el ejercicio, el pulido de exportaciones, favicons propios para Marketing, Producción y Ventas, y la elasticidad cuando haya necesidad validada.

**Repositorios:** quedan abiertos PR viejos ya superados: panel #227 y #216; tienda #46, #21 y #15. Cerrarlos o no lo decide el dueño.

## 10. Reglas de entrega

- Rama nueva + PR nuevo por cambio; nunca push directo a `main`.
- Las migraciones aplicadas son inmutables: toda corrección es una migración forward nueva. Nunca se reejecuta una histórica como arreglo o rollback.
- Antes de afirmar qué está desplegado, medirlo (diagnóstico de solo lectura, pruebas sin efectos), no deducirlo de los documentos.
- Nunca exponer secretos ni `service_role`, y no crear el primer usuario reducido antes de D3.
- Verificar si un PR ya fue fusionado antes de reutilizar una rama.
- Un comando sin error no es evidencia suficiente.
- SQL en el repositorio no equivale a SQL desplegado.
- Edge Function en el repositorio no equivale a función desplegada.
- No hacer gold-plating: construir el siguiente tramo que desbloquea la operación real.
