# MAGANDHI + Impulse · contexto operativo vigente

**Corte:** 20 de octubre de 2026
**Producción interna:** `https://montaguth.institute`
**Tienda pública:** `https://magandhi.com`

Este archivo es la entrada única para entender dónde está parado el proyecto: la realidad operativa (§2 a §7) y el trabajo pendiente (§9). La historia completa permanece en Git.

> **Punto de unificación · 9-oct-2026.** Se cerraron todos los frentes que estaban abiertos a la vez. Las migraciones hasta `20261020000000` (F3) estaban aplicadas en producción, salvo `20261002000000`, que quedó superada. La cadena de pagos Wompi F1 → F4 está en producción y **el dueño verificó el sistema completo con una compra real**: pago, pedido, stock, asiento contable automático, correos y opinión. Desde aquí se trabaja desde un solo lugar. `ANDAMIOS.md` y los relevos de sesión se retiraron porque ya cumplieron su función; siguen en el historial de Git.

> **Avance · 10-oct-2026 (desplegado).** Se aplicaron en producción tres migraciones nuevas y dos despliegues de Edge Function, todos verificados en el banco de pruebas antes de subir:
> - `20261021000000_pagos_estado_publico.sql` + Edge Function `estado-pago` (**D0**): la vuelta de Wompi ya dice en qué quedó el pago y bloquea «Comprar ahora» hasta que haya veredicto, así que se cerró el riesgo de cobro doble. Además, los detalles de entrega llegan al pedido y los errores de pago dicen el motivo real (cambios en el repo `magandhi`, PR #90).
> - `20261022000000_analitica_fecha_colombia.sql`: los días de la analítica de Email marketing se cuentan en hora de Colombia, no en UTC (corregía un desfase de un día entre las 7 p. m. y medianoche).
> - `20261023000000_dropshipping_cimientos.sql` + redespliegue de `dropi-sonda` (**Dropshipping D1**): séptima área interna, bandeja privada de candidatos, `productos.origen`, ficha `producto_proveedor`, candados que mantienen al proveedor fuera del libro de Inventario y de Métricas, y bloqueo de publicación de proveedor hasta D2.
>
> - **Ajuste de uso real de D1** (PR #258, redespliegue de `dropi-sonda`, sin migración): fotos reales de Dropi, 24 resultados por página con paginación que funciona y bandeja como carrito.
> - `20261024000000_dropshipping_d2a_llevar_a_campanas.sql` + redespliegue de `dropi-sonda` + PR #259 (**Dropshipping D2a**): «Llevar a Campañas» atómico con fotos propias; el editor abre el borrador en modo proveedor. **El dueño lo desplegó y probó el 10-oct-2026: todo en orden.**
>
> **Avance · 10-oct-2026 (desplegado).** `20261025000000_dropshipping_d2b_sello_con_prueba.sql` (**Dropshipping D2b**, PR #261): el sello «Elegido por MAGANDHI» exige una casilla simple «Este producto fue probado por MAGANDHI» en la campaña (columna `campana_producto.probado_por_magandhi`), impuesta en `cm_crear/editar/publicar_campana` y por un trigger. **El dueño lo aplicó y verificó el 10-oct-2026: funciona.** Sin Edge Functions ni secretos nuevos. No hay tabla/RPC de pruebas, fechas, notas ni historial.
>
> **Hito · 10-oct-2026 · D2c COMPLETO: MAGANDHI ya vende productos de proveedor.**
> El dueño recorrió el circuito entero con una venta real y lo confirmó. Se
> desplegaron cuatro migraciones, una Edge Function nueva y una pantalla:
> - `20261026000000` + **`dropi-refrescar-stock`** (PR #264, **D2c.1**): stock
>   vivo que **falla cerrado**, refresco **rodante cada minuto** con `pg_cron` +
>   `pg_net`, y pantalla de stock y saldo en Dropshipping.
> - `20261027000000` (PR #265, **D2c.2a**): `crear_pedido` y `anular_pedido`
>   ramifican por `productos.origen`; `pedido_proveedor` guarda qué despachar,
>   con qué flete, a dónde y la **evidencia de lo que Dropi reportaba al
>   cobrar**. Crea en el PUC las cuentas **138010** y **523535**, que no existían.
> - `20261028000000` (PR #265, **D2c.2b**): **levanta `DS_PUBLICACION_PENDIENTE`**.
>   El asiento descuenta del saldo en Dropi, y aparecen las RPC del despacho manual.
> - `20261029000000` + `crear-intencion-pago` (PR #265, **D2c.2c**):
>   **verificación en vivo contra Dropi antes de cobrar**.
> - `ventas/despachos-proveedor/` (PR #265): la pantalla del despacho manual y
>   el aviso en la portada de Ventas.
>
> Antes, el mismo día: la **sonda de dinero** (PR #263) que lee el saldo de
> Dropi sin crear pedidos. **1.065 comprobaciones en verde.**
>
> **Cuadre contable y D2c.3 · 14-oct-2026.** El saldo del panel de Dropi no
> coincidía con los libros y al medir salieron **cuatro** cosas sin contabilizar:
> el **seguro del pedido** en Dropi (754), los **dos shampoos** sin asiento de
> apertura, la **recarga de 50.000** a Dropi y la **liquidación de Wompi**. Se
> cuadró con `supabase/operacion/cuadre-contable-2026-10-14.sql` (cuatro
> asientos y cuatro cuentas nuevas) y quedó así: banco **95.082**, saldo en
> Dropi **27.136**, Wompi por liquidar **0**, inventario **47.705** (1 shampoo),
> capital aportado **145.410**, utilidad **24.513**, activo = patrimonio
> **169.923**. **Plata real: 122.218.**
>
> Dos códigos de cuenta se corrigieron contra el PUC antes de crearlos: **3120
> no es** capital de personas naturales (es «Capital asignado», de sucursales
> extranjeras) sino **3130**; y **524555 no es** una cuenta de seguros porque
> **5245 es «Mantenimiento y reparaciones»** — la de seguros de ventas es 5230 y,
> como dentro de ella no hay subcuenta de transporte de mercancías, el seguro de
> un envío de un tercero va a **523095 «Otros»**.
>
> La causa de fondo se cerró con `20261030000000` (**D2c.3**): `pedido_proveedor`
> gana la columna `seguro` y la pantalla de Despachos su campo. **Es opcional de
> verdad:** `null` o `0` significan «no se aseguró», no «falta el dato», así que
> nunca bloquea el asiento, al contrario que el costo y el flete. Banco SQL
> **613/613**, matriz **170/170**, pantalla **70/70**.
>
> **El estado actual de producción llega hasta la migración `20261106000100` (Comercial C5 + slug automático), aplicada el 20-oct-2026 por SQL Editor. El carrito quedó ENCENDIDO (`carrito_habilitado=true`) y Wompi en `prod`. El proyecto no tiene tabla de ledger de migraciones: todo se aplica a mano y nunca con `supabase db push`.**
>
> **Cuentas de cliente C1 · DESPLEGADO · 15-oct-2026 (PR #268).** El dueño
> decidió conservar compra como invitado y añadir inicio de sesión opcional en
> `magandhi.com`, con beneficios futuros sin frenar la compra. C1 mantiene
> `clientes.id` como identidad comercial, crea `cuentas_cliente` como puente
> hacia Auth y separa firmemente clientes de `perfiles` internos.
>
> **Cuentas de cliente C2 · PREAPERTURA · 16-oct-2026 (PR de backend #270 y
> tienda #93).** El código está fusionado y publicado; la migración
> `20261101000000_cuentas_cliente_c2.sql` y la Edge Function
> `cuenta-inicializar` están desplegadas. El preflight de producción dio C1 y C2
> presentes y cero inconsistencias, ambigüedades o vínculos duplicados. Login,
> inicialización idempotente, SMTP Resend, recuperación con TokenHash abierta en
> otro navegador, cambio de contraseña y segundo login fueron probados con un
> usuario controlado: una sola fila activa en `cuentas_cliente`.
>
> Supabase Auth tiene Site URL/redirects de `magandhi.com`, SMTP desde
> `cuenta@auth.magandhi.com` (dominio Resend verificado en Porkbun), plantillas
> de confirmación/recuperación y Google Provider configurado. Google permanece
> `External / Testing`; Google Identity Services se publicó mediante la tienda
> PR #95 y la prueba controlada confirmó que el selector muestra `magandhi.com`,
> conserva el mismo UID/identidad y una sola cuenta activa tras el segundo
> acceso. Turnstile quedó publicado mediante tienda #97/#98 y CAPTCHA está
> activo en Supabase: login y recuperación con token válido fueron aceptados,
> una llamada sin token fue rechazada con `captcha_failed`/400 y el widget se
> renovó tras expirar. La apertura controlada también midió un registro nuevo por
> correo —confirmación, inicialización y segundo login— y Google con un usuario
> realmente nuevo: identidades únicas y una sola cuenta activa. **C2 queda
> cerrado técnicamente en preapertura. CAPTCHA sigue activo; signup permanece
> OFF y Google External/Testing.**
>
> La apertura pública se aplaza por decisión del dueño hasta redactar, revisar y
> publicar políticas y avisos contextuales. Solo después se prepara Google
> Production y se activa signup permanente. Relevo temático de cuentas:
> `docs/RELEVO-CUENTAS-C2-2026-10-16.md`.
>
> **Comercial C1 · DESPLEGADO Y PROBADO EN ESTRUCTURA · 16-oct-2026.** Backend
> PR #276 fusionado a `main` (`e75dc1cbd1643d3897e851cc2e06fe47f3b87ecc`) y
> tienda #102 fusionada (`db56c4f64de9dc2af5ac77b3c444467e1a72cb0c`). La
> migración `20261102000000_comercial_c1_cantidad_inmediata.sql` está aplicada,
> el postflight dio 9/9 `true`, `crear-intencion-pago` está desplegada y la
> tienda publicada.
>
> Cantidad 1 respondió HTTP 200 y persistió 7/7 comprobaciones, sin llegar a
> pago, pedido o webhook. Cantidad 2 contra máximo 1 fue rechazada 409
> `MAX_COMPRABLE`; después Grisi quedó con máximo 2 y `max_comprable=2`, y su
> intención por dos unidades respondió HTTP 200 por 13.980.000 centavos (COP
> 139.800). El dueño confirmó selector, máximo, total, modal y compra invitada
> estructural. **No hubo compra real de dos unidades:** para ese caso no se
> midieron webhook, pedido, baja de dos unidades, asiento, correo ni repetición o
> idempotencia. C1 conserva ese límite propio.
>
> **Hito · Comercial C2 · 16-oct-2026.** Comercial C2 quedó desplegado y
> probado en estructura. Backend PR #278 y tienda PR #104 están fusionados;
> migración `20261103000000`, preflight 3/3 y postflight 10/10 correctos. Se
> midieron agregar/consolidar/cambiar/retirar, persistencia, aislamiento,
> conflicto entre pestañas, logout y compra invitada, sin dinero ni inventario.
>
> **Hito · Comercial C3 · 17-oct-2026.** **Desplegado y probado en estructura;
> flag productivo final `false`; C4 era el siguiente tramo.** Backend PR #280:
> implementación `424e7632d214a90afdb7c9265fbe758bfa3fc580`, merge
> `275c0dd4548937075770ddd6dace1801c013c929`. Tienda PR #106: implementación
> `c87934cd6034677be1c1888b8eadce95dcc348a4`, merge
> `b18c1ed4f075241a066048b0bfbe1b19d0eb96c9`, Pages construido.
>
> El dueño confirmó preflight limpio, migración `20261104000000` aplicada,
> postflight C3 correcto, Edge Functions redesplegadas y sondas de CORS/sesión/
> firma correctas. Con activaciones temporales se midieron UI, cantidades,
> subtotales, persistencia, formulario y una intención v2 productiva sin pago:
> Wompi abrió por el total exacto, el snapshot congeló líneas correctas y un
> reintento desde otra sesión conservó una sola intención por versión. No hubo
> aprobación, pedido, movimientos de Inventario, asiento, correo ni repetición
> real del webhook. La intención queda en `creada`, sin pedido/evento, y no se
> borra. Relevo histórico de ese corte:
> `docs/RELEVO-COMERCIAL-C3-2026-10-17.md`.
>
> **Hito · Comercial C4 · 19-oct-2026 · aplicado, desplegado y probado sin
> dinero.** PR #283, #108, #284, #109 y #285 están fusionados y Pages publicó.
> En producción ya corrieron el preflight (sin la intención C3 documentada:
> `v2_total=0`), el puente de estado, la Edge `estado-pago`, la migración
> `20261105000000` (una vez), el postflight (30/30 funciones) y la Edge
> `crear-intencion-pago`. **El carrito quedó ENCENDIDO** porque el dueño sigue de
> inmediato en otro chat. Las pruebas ON sin dinero funcionan, incluido el
> temporizador en Wompi, tras corregir dos defectos: ids de campaña rechazados
> (PR #109) y el Rubik publicado sin slug (dato corregido). Las decisiones que
> dejó abiertas (slug automático, bloqueo de 30 minutos y flag) se resolvieron
> con C5 el 20-oct-2026: C4 queda **cerrado estructuralmente y superado**.
> Relevo histórico: `docs/RELEVO-COMERCIAL-C4-2026-10-19.md`.
>
> El contrato fija una expiración autoritativa de 30 minutos firmada para Wompi.
> Si hubiera una intención C3 previa (`ciclo=0`), la conserva y registra su
> sucesión; en producción no había ninguna. El snapshot expone `bloqueo_pago` (`pendiente` o
> `revision`); el retorno v2 exige JWT del propietario mediante `estado-pago`.
> `customer_id` deriva de cuenta/Auth y el destinatario queda separado. Una
> aprobación normal consume las cantidades congeladas preservando extras;
> rechazo o expiración libera y avanza versión, PENDING no libera y APPROVED
> tardío pasa a revisión. La revisión solo se libera con la acción explícita
> `reembolsado_liberar`. Cambiaron `crear-intencion-pago`, `estado-pago` y Ventas;
> los helpers propios de C4 quedan sin `EXECUTE` de API; el helper booleano
> histórico `pw__contexto_servidor()` no expone ni muta datos y se excluye de esa
> auditoría porque su ownership varía entre reconstrucciones.
>
> **Bancos C4:** run `39320288166` (implementación) y run `39326788045`
> (paquete operativo), ambos `SUCCESS` con PostgreSQL 15/Deno. **Límite:** no
> hubo pago con dinero; aprobación, pedido, inventario, asiento, correo e
> idempotencia C4 no se midieron en producción. Relevo histórico:
> `docs/RELEVO-COMERCIAL-C4-2026-10-19.md`.
>
> **Hito · Comercial C5 · 20-oct-2026 · desplegado y cerrado
> estructuralmente.** El dueño aprobó reemplazar el bloqueo C4 por carrito
> libre + «Mis compras» (backend #287 `c8fd03c`, tienda #113 `4a0b439`). El
> 20-oct se ejecutó la ventana completa de
> `supabase/operacion/COMERCIAL-C5-CIERRE.md`: preflight, Edge C5 con sondas
> correctas, migraciones `20261106000000` (C5) y `20261106000100` (slug
> automático) una vez cada una, postflight y activación. El recorrido sin dinero
> lo confirmó el dueño: al crear la intención el carrito queda libre, la compra
> aparece en Mis compras, «Continuar pago» no duplica y la intención sin
> transacción vence. **El carrito quedó ENCENDIDO** a propósito y Wompi en
> `prod`. Se corrigieron cuatro defectos de los scripts (PR #290–#292 y el PR de
> cierre) sin efecto en producción. **Límite:** sin pago real por carrito no hay
> cierre transaccional de C3/C4/C5. Relevo vigente:
> `docs/RELEVO-COMERCIAL-C5-CIERRE-2026-10-20.md`.

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

- Login interno por Supabase Auth en `index.html`.
- Panel modular en `panel.html`.
- Guardia reutilizable en `auth-guard.js`: sesión Auth sola no basta; exige
  además una fila en `perfiles`.
- `perfiles` define rol y módulos únicamente para personal interno.
- `cuentas_cliente` separa las cuentas públicas de los perfiles internos y las
  vincula sin reemplazar `clientes.id`.
- C2 está desplegado en preapertura: correo/contraseña y Google convergen en
  `cuenta-inicializar`; CAPTCHA está activo y signup sigue apagado.
- Un mismo UID no puede existir como cliente y personal, incluso con altas
  concurrentes.
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
- **Corrección del 10-oct-2026 · los días se cuentan en Colombia.** La base corre en UTC, así que `current_date` es la fecha UTC: entre las 7 p. m. y la medianoche de Colombia, `dias_desde_ultimo_clic`, `dias_desde_ultima_compra` y `dias_en_lista` salían **con un día de más**, y eso alimenta Segmentos y el clúster. A mediodía las dos formas coinciden, y por eso pasó inadvertido. Migración forward `20261022000000`, que sólo redefine `em__perfil_base`, `em__perfil_email` y `em__segmento_where` cambiando 3 líneas. El guardián contra la clase entera de bug vive en `supabase/pruebas/local/fechas-colombia.sql` y corre en cada rama. Ver `supabase/INSTRUCCIONES.md`.
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
- **Despachos de proveedor (D2c, 10-oct-2026):** pedidos ya cobrados que hay que crear **a mano** en el panel de Dropi. La pantalla dice qué pedir (producto, variante, cantidad, destino, SIN RECAUDO), muestra cuánto lleva esperando y recibe de vuelta el número de pedido de Dropi, el costo y el flete. Mientras un pedido siga pendiente, sus unidades se descuentan del stock disponible en la tienda. El aviso aparece también en la portada del área, solo si hay alguno.
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

Expone datos necesarios para home/producto, el booleano `agotado` y
`max_comprable` (`0..20`), ya limitado por el máximo de Campañas y la
disponibilidad autoritativa. Nunca expone:

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
| D0 | **La vuelta de Wompi ya dice en qué quedó el pago** y bloquea «Comprar ahora» mientras no haya veredicto, así que nadie paga dos veces. RPC `pw_estado_publico` + Edge Function `estado-pago`: la autorización es la posesión de la referencia (como el código de reseña) y la respuesta trae solo el estado, el nombre y el slug. **No abre nada para `anon`.** Desplegado el 10-oct-2026 |
| Comercial C1 | Compra inmediata acepta la cantidad seleccionada `1..max_comprable`; servidor relee precio, máximo y disponibilidad y persiste el monto total. **Desplegado y probado en estructura:** qty1 sin pago y qty2 hasta intención; no hubo cierre transaccional real de dos unidades |

**Comercial C1 no cambia la definición de pago aprobado.** Su evidencia actual
termina en la intención; no autoriza a atribuir pedido, inventario, asiento,
correo o idempotencia a la cantidad 2.

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
- **Fechas: la base corre en UTC y la operación es de Colombia.** Toda resta de días o estampado de fecha debe ir en `America/Bogota`, con `fz__fecha_colombia()` en Finanzas o `(now() at time zone 'America/Bogota')::date` en el resto. Usar `current_date` a secas es el bug que se corrigió el 10-oct en la analítica de Email marketing. **Trampa latente reconocida:** `crear_pedido`, `inv_registrar_movimiento` y `em_registrar_contacto` conservan `default current_date` en el servidor, igual que los defaults de `pedidos.fecha_orden` y `movimientos_inventario.fecha`. Hoy no muerde porque las tres pantallas mandan la fecha explícita calculada en el navegador (`hoyISO()`, hora local = Colombia), pero una llamada sin fecha a las 8 p. m. quedaría fechada mañana, y el 31 de diciembre saltaría de año. Cerrarlo exige redefinir RPC de núcleo y merece su propio PR medido.
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
- `docs/CUENTAS-CLIENTE.md`: decisiones permanentes de identidad, compra como
  invitado y tramos C1–C4.
- `docs/PLANO-FASE-COMERCIAL.md`: evolución aprobada —cantidades, carrito
  autenticado, Mis compras y Promocionar— con fórmulas, contratos, orden de
  despliegue y criterios de cierre. **C1–C5 están cerrados estructuralmente en
  producción con los límites documentados; ninguno tiene cierre transaccional
  por carrito. P0–P5 permanecen pendientes.**
- `docs/PLANO-COMERCIAL-C5.md`: contrato técnico de carrito libre, Mis compras,
  reapertura, seguimiento y opinión tras entrega.
- `docs/RELEVO-COMERCIAL-C5-CIERRE-2026-10-20.md`: **relevo general vigente y
  punto de arranque**. Estado productivo exacto, evidencia de la ventana C5,
  pendientes y prompt de continuidad.
- `docs/RELEVO-COMERCIAL-C5-2026-10-19.md` y
  `docs/RELEVO-COMERCIAL-C4-2026-10-19.md`: relevos históricos; conservan
  diseño, plan y evidencia, pero ya no gobiernan el próximo chat.
- `supabase/operacion/COMERCIAL-C5-CIERRE.md` y `comercial-c5-*.sql`: paquete
  operativo vigente del carrito. Estado con `comercial-c5-estado.sql`, apagado
  con `comercial-c5-desactivar.sql`, reactivación con el `comercial-c5-activar.sql`
  actual y, si falla, `comercial-c5-diagnostico-activacion.sql`. El paquete C4
  queda como historia y no se usa para reactivar.
- `docs/RELEVO-COMERCIAL-C3-2026-10-17.md`: relevo histórico de C3. **Aviso:**
  la intención v2 que describe no existe en producción (preflight C4:
  `v2_total=0`).
- `docs/RELEVO-COMERCIAL-C2-2026-10-16.md`: relevo histórico de C2; conserva su
  evidencia y ya no gobierna el arranque.
- `docs/RELEVO-COMERCIAL-C1-2026-10-16.md`: relevo histórico de C1; conserva su
  evidencia y el límite de no pago real de cantidad 2.
- `docs/RELEVO-CUENTAS-C2-2026-10-16.md`: relevo histórico temático de cuentas;
  conserva la evidencia de preapertura y gobierna ese frente cuando se retome.
- `docs/RELEVO-CUENTAS-2026-10-15.md`: relevo histórico de C1 y diseño de
  entrada a C2; ya no gobierna el arranque.
- `docs/dropshipping-envios/`: frente del 9–10-oct-2026 (productos de proveedor
  con Dropi y guías para los productos propios); su relevo queda como memoria de
  ese frente, no como prioridad actual.
- `supabase/pruebas/diagnostico-produccion.sql`: diagnóstico de solo lectura para medir producción sin fiarse de los documentos.
- `supabase/pruebas/local/herramientas/LEEME.md`: banco de pruebas local (también corre en GitHub Actions en cada rama).

El relevo general vigente es
`docs/RELEVO-COMERCIAL-C5-CIERRE-2026-10-20.md`: C5 está desplegado y cerrado
estructuralmente, con el carrito encendido. Los relevos C4 y C5 del 19-oct
conservan la evidencia histórica. El relevo temático de
cuentas `docs/RELEVO-CUENTAS-C2-2026-10-16.md` conserva su evidencia histórica
y evita repetir migración, SMTP, plantillas o configuración Google al retomar
esa apertura.

## 9. Pendientes vigentes

### Fase comercial aprobada · 16-oct-2026 · estado por tramos

Gobierna `docs/PLANO-FASE-COMERCIAL.md`. No confundir la fase completa con los
cierres estructurales de sus primeros tramos:

1. **Comercial C1 · cantidad inmediata: desplegado y probado en estructura.**
   Migración `20261102000000` aplicada, postflight 9/9 `true`, Edge Function y
   tienda desplegadas. Cantidad 1 persistió correctamente sin pago; máximo+1
   devolvió 409 `MAX_COMPRABLE`; cantidad 2 abrió una intención por COP 139.800.
   El dueño confirmó selector, máximo, total, modal y compra invitada. **No hubo
   pago real de dos unidades** ni se midieron para ese caso webhook, pedido,
   baja2, asiento, correo o idempotencia.
2. **Comercial C2 · carrito autenticado persistente: cerrado
   estructuralmente.** Backend #278 y tienda #104 están fusionados; migración
   `20261103000000`, preflight 3/3 y postflight 10/10 correctos. Se midieron
   propiedad, persistencia, concurrencia y compra invitada sin dinero ni
   inventario.
3. **Comercial C3 · checkout multiproducto: desplegado y probado en
   estructura.** Backend #280 y tienda #106 están fusionados; migración
   `20261104000000` aplicada; postflight, grants/RLS y Edge Functions correctos.
   Las sondas de CORS/sesión/firma y las pruebas OFF/ON pasaron. Una intención v2
   productiva sin pago abrió Wompi con el total exacto, congeló líneas válidas y
   conservó una sola intención al reintentar desde otra sesión. El flag final es
   `false`. No hubo aprobación, pedido, inventario, asiento, correo ni repetición
   real del webhook; C3 no está cerrado end-to-end.
4. **Comercial C4 · cerrado estructuralmente y superado por C5.** Su migración
   `20261105000000` sigue en producción como base; las intenciones C4 históricas
   conservan su contrato. El bloqueo de 30 minutos y la prueba 9D ya no son el
   modelo vigente. Sin pago aprobado, su cierre es estructural.
5. **Comercial C5 · desplegado y cerrado estructuralmente (20-oct-2026).**
   Migraciones `20261106000000` y `20261106000100` (slug automático) aplicadas,
   Edge C5 desplegadas, postflight y activación correctos y recorrido sin dinero
   confirmado por el dueño. **Carrito ENCENDIDO** y Wompi `prod`. Pendientes:
   cierre transaccional con pago real autorizado, opinión autenticada por cuenta
   y los placeholders del centro de cuenta (Favoritos, Mis opiniones, Eliminar
   cuenta). Relevo vigente: `docs/RELEVO-COMERCIAL-C5-CIERRE-2026-10-20.md`.
6. **Promocionar P0–P5 · siguiente etapa del plano, empezando por P0
   (taxonomía y privacidad).** Producto compartible, estudio, enlace, atribución
   y lectura comercial siguen pendientes. Meta Ads, Pixel, Conversions API y
   publicación automática continúan fuera de alcance.

La definición final de la fase no se relaja: el carrito está cerrado en
estructura, no end-to-end. Dinero solo con autorización expresa. Cuando se
autorice un pago C5 debe demostrar monto exacto, un solo pedido, `customer_id`
correcto, snapshot, inventario/proveedor, asiento, correo «Recibido» e
idempotencia del webhook. Continuar desde
`docs/RELEVO-COMERCIAL-C5-CIERRE-2026-10-20.md`.

Cuentas de cliente sigue en **preapertura**:

1. **C1 está desplegado y cerrado** (PR #268, migración `20261031000000`):
   puente Auth→cliente, separación firme del personal, guardia interna y actor
   cliente en la matriz.
2. **C2 está cerrado técnicamente en preapertura** (backend #270, tienda #93,
   Google GIS #95 y Turnstile #97/#98). Correo/contraseña, SMTP, TokenHash,
   recuperación cross-browser, CAPTCHA, alta nueva por correo, alta Google con
   usuario nuevo e idempotencia están medidos: identidades únicas y una sola
   cuenta activa. CAPTCHA sigue activo; signup OFF y Google External/Testing.
3. **Apertura diferida por decisión del dueño:** redactar, revisar y publicar
   políticas y avisos contextuales. Solo después preparar Google Production y
   activar signup permanente. No reabrir pruebas de C1/C2 al retomar.
   Ver `docs/RELEVO-CUENTAS-C2-2026-10-16.md`.
4. Después: **C3** (Mi cuenta: perfil, direcciones y opiniones) y **C4**
   (checkout autenticado con `customer_id` derivado en servidor). Comercial
   C4/C5 ya entregaron en producción `customer_id` derivado en servidor para el
   carrito y Mis compras (pedidos y estado); retomar Cuentas C3/C4 sin
   duplicarlos.

**Contabilidad · cerrada el 14-oct-2026:** la liquidación de Wompi, el inventario
inicial, la recarga de Dropi y el seguro ya quedaron registrados y conciliados.
Wompi por liquidar está en cero; el detalle del cuadre está arriba y en
`supabase/operacion/cuadre-contable-2026-10-14.sql`.

**Desplegado el 10-oct-2026 (ya en producción):**
- `20261021000000` + Edge Function `estado-pago` (D0, runbook §D0).
- `20261022000000`: los días de la analítica de Email marketing contados en Colombia.
- `20261023000000` + redespliegue de `dropi-sonda` (Dropshipping D1, runbook §Dropshipping D1).
- Ajuste de uso real de D1: solo redespliegue de `dropi-sonda` (runbook «Dropshipping D1 · ajuste de uso real»).
- `20261024000000` + redespliegue de `dropi-sonda` (Dropshipping D2a, runbook «Dropshipping D2a»).
- `20261025000000` (Dropshipping D2b, PR #261, runbook «Dropshipping D2b»): sello con casilla simple. Sin Edge Functions ni secretos.
- `dropi-sonda` con la **sonda de dinero** (PR #263): lee el saldo de Dropi (`walletAmount`) sin crear pedidos.
- `20261026000000` + Edge Function **`dropi-refrescar-stock`** + `pg_cron`/`pg_net` + el secreto `DROPI_REFRESCO_SECRETO` (D2c.1, PR #264, runbook «Dropshipping D2c.1»).
- `20261027000000`, `20261028000000`, `20261029000000` + redespliegue de `crear-intencion-pago` + la pantalla de Despachos (D2c.2, PR #265). **Aquí se habilitó la venta de proveedor.**

**Otras decisiones del dueño aún abiertas (no bloquean C3):**
1. Los **detalles cosméticos** que mencionó al cerrar la sesión del 10-oct y no detalló. Hay que preguntárselos.
2. **¿En qué momento se debita el saldo de Dropi?** Al crear el pedido, al despacharlo o al entregarlo. Ya es medible sin riesgo leyendo `walletAmount` antes y después; puede que ya tenga el dato de la venta de prueba.
3. **Política ante una entrega fallida** (devolución total, reenvío, o según el motivo). Es más caro para nosotros que para un vendedor de contraentrega, porque la plata del cliente ya se cobró.
4. Los **fletes por destino** para afinar el precio, y el **tiempo de entrega** en la ficha del producto (prepago sin tiempo visible asusta).

**Tienda:** ~~3, 4 y 5~~ **cerrados y desplegados (D0, 9–10-oct-2026).** La vuelta de Wompi ya muestra en qué quedó el pago y bloquea «Comprar ahora» mientras no haya veredicto, así que el cobro doble está cerrado; los detalles de entrega llegan al pedido; y los errores de pago dicen el motivo real. Pendiente de decisión aparte: guardar el documento del comprador para la factura requiere una columna nueva.

**Producto y operación:**
6. Copys definitivos de los correos del pedido (`correo_plantillas`, hoy en borrador; se cambian por SQL) y de las políticas públicas (estructura provisional en magandhi.com/politicas/).
7. Decidir si la tienda queda en producción o vuelve a sandbox hasta el lanzamiento (§5).
8. Finanzas, siguiente: asiento automático de las **ventas manuales** (pedir la forma de pago al registrar) y de las **compras de mercancía** (costo del lote y forma de pago en «Registrar entrada»).
9. **D3** (permisos granulares por capacidad en panel, grants, RLS y RPC) antes del primer usuario que no sea admin.
10. Menores: el canal web visible en la lista de Seguimiento (hoy solo en el detalle), el cierre anual de Finanzas cuando cambie el ejercicio, el pulido de exportaciones, favicons propios para Marketing, Producción y Ventas, y la elasticidad cuando haya necesidad validada.

**Frente nuevo · dropshipping y envíos (9–10-oct-2026):** vender productos de proveedores de Dropi, que despacha el proveedor, y dar guía y rastreo a los pedidos propios. **Hito del 9-oct: Dropi ya le responde a MAGANDHI.** La cuenta está verificada y, desde Supabase, se lee catálogo, búsqueda y ficha completa por id, con existencias por bodega. La causa de un día entero de 401 era que Dropi rechaza los `User-Agent` que no reconoce; se resolvió sin Shopify, WooCommerce ni gasto mensual.

**D1 · cimientos internos (DESPLEGADO el 10-oct-2026):** séptima área Dropshipping; consulta/paginación de solo lectura; bandeja privada de candidatos; `productos.origen`; ficha `producto_proveedor`; trigger que bloquea proveedor en el libro de Inventario incluso por encima de RLS; proveedor fuera de `stock_actual` y de Métricas de Inventario; y bloqueo de publicación/catálogo público hasta D2c. Las fotos de la búsqueda son preview remoto (no se guardan). **D1 no crea pedido, reserva, guía ni llamada `orders/`.**

**Ajuste de uso real de D1 (DESPLEGADO el 10-oct-2026, PR #258; sin migración):** el primer uso real mostró cero fotos, solo 6 resultados y «0 coincidencias» con Anterior/Siguiente muertos. Causas medidas: Dropi manda las fotos como `{ urlS3 }` relativas a su CDN (no URLs completas) y su `count` llega 0. Ahora las fotos se ven directo desde el CDN de Dropi (sin descargarse ni guardarse), hay 24 por página con paginación que pide uno de más para saber si sigue, abrir por id muestra solo esa ficha, y la bandeja es un carrito flotante con panel lateral. Runbook «Dropshipping D1 · ajuste de uso real»; contrato en `docs/dropshipping-envios/DROPI.md` §8 bis.

**D2a · «Llevar a Campañas» (DESPLEGADO y probado por el dueño el 10-oct-2026, PR #259; migración `20261024000000` + redespliegue de `dropi-sonda`):** desde la bandeja se relee la ficha en Dropi, se elige variante y fotos, las fotos se convierten a grande + `-sm` en el bucket propio y `ds_llevar_a_campanas` crea en una transacción el producto `origen='proveedor'` (SKU `MAG-DROP-NNNN`, sin `costo_unitario`), su `producto_proveedor` (lectura de stock que nace vencida) y un borrador ligado; luego abre el editor en modo proveedor. Un gatillo impide re-ligar una campaña proveedor o ligar un producto proveedor a mano. Sigue sin publicar ni vender. D2 queda en tres tramos: D2a importación, D2b sello con casilla simple, D2c stock vivo y venta (`docs/dropshipping-envios/PLANO.md` §4). Runbook «Dropshipping D2a».

**D2b · sello con casilla simple (DESPLEGADO el 10-oct-2026, PR #261; migración `20261025000000`):** el sello «Elegido por MAGANDHI» exige la casilla «Este producto fue probado por MAGANDHI» en la campaña (columna `campana_producto.probado_por_magandhi`), con producto ligado; impuesto en `cm_crear/editar/publicar_campana` y por un trigger. **No hay `producto_pruebas`, RPC de registro, formulario, fechas, notas, veredictos ni historial.** Una campaña histórica con sello y casilla falsa se advierte al editar para confirmarla o elegir «Ninguno»; no se inventan datos históricos. No levanta `DS_PUBLICACION_PENDIENTE`: proveedor sigue sin publicarse hasta D2c.

**D2c · stock vivo y venta de proveedor (COMPLETO, desplegado y probado el 10-oct-2026, PR #263, #264 y #265):**

- **El stock vivo.** Un reloj (`pg_cron` + `pg_net`) llama cada minuto a la Edge Function `dropi-refrescar-stock`, que refresca **de forma rodante los 3 productos con la lectura más vieja**. El refresco rodante no es un detalle: Dropi responde **429 alrededor de la petición 12–16 en ráfaga** (medido), así que un lote grande coquetea con el techo y el goteo no. Una lectura fallida **no toca el stock ni la vigencia**: fallar jamás le alarga la vida a un dato viejo.
- **Falla cerrado.** `catalogo_publico` da el producto por agotado si la lectura venció (120 min), falta, o el stock está por debajo del **piso de vitrina de 20 unidades**, menos los pedidos pagados que aún no se han transcrito a Dropi. **El copy público NO cambió:** se reutiliza el booleano `agotado` que la tienda ya sabía leer, porque un texto distinto para proveedor sería **una etiqueta que delata el dropshipping**. Cero cambios en el repositorio `magandhi`.
- **Por qué falla cerrado y no «con holgura»:** se midió que dos productos pasaron de **300 unidades en 3 bodegas a 0 sin ninguna en 24 horas**, y seguían con `active: true`. Un derrumbe no avisa, así que ni el piso ni `active` protegen: solo la frescura de la lectura.
- **La venta.** `crear_pedido` y `anular_pedido` ramifican por `productos.origen`. Antes de D2c.2a vender proveedor era **imposible**: la primera lo rechazaba con `STOCK_INSUFICIENTE` (no hay fila en `stock_actual`) y la segunda habría fallado al devolver stock (el gatillo de D1 lo bloquea). Un pedido de proveedor **no toca el libro de Inventario**; deja una fila en `pedido_proveedor` con la **evidencia de lo que Dropi reportaba al cobrar**.
- **Antes de cobrar se pregunta a Dropi en vivo.** `crear-intencion-pago` consulta la ficha justo antes de abrir Wompi. Si Dropi dice que no hay, **rechaza**. Si Dropi no responde y la lectura es fresca (10 min), **permite**, porque bloquear convertiría cualquier hipo de Dropi en una tienda caída; si la lectura ya envejeció, **rechaza**.
- **El despacho es MANUAL, y no es un olvido.** Ventas → **Despachos de proveedor** dice qué pedir en Dropi (producto, variante, cantidad, destino, SIN RECAUDO) y recibe de vuelta el número de pedido, el costo y el flete. El aviso sale también en la portada del área, solo si hay pendientes.
- **Contabilidad** (cuentas aprobadas por el contador): la venta entra automática contra 138095 como siempre; el costo se registra a mano con los números reales de Dropi, **D 613505 costo + D 523535 flete contra C 138010 saldo en Dropi**, sin pasar nunca por inventario 1435. **No puede ser automático** porque el flete depende del destino y la API de Dropi **no tiene ruta de cotización** (medido). Las cuentas 138010 y 523535 **no existían en el PUC** y las crea la migración.
- Todas las perillas viven en `dropshipping_config`: cambiarlas **no exige migración**.

**Lo que sigue · D3/D4, el pedido automático a Dropi.** Faltan, y ninguno es opcional: el **contrato oficial de `orders/`** (el correo a soporte sigue sin enviar), los **municipios DANE** con equivalencia Dropi —hoy la ciudad es texto libre y una que Dropi no reconozca **hace fallar el pedido después del pago**—, **nombre y apellido separados** en el checkout, y la reserva `PENDIENTE CONFIRMACION` con su liberación, cancelación e idempotencia medidas en un protocolo controlado. **Nunca un POST improvisado a `orders/`:** crea un pedido real con plata real y duplica si uno reintenta sin consultar antes por id. Todo en `docs/dropshipping-envios/LEEME.md`, `PLANO.md` (§4 bis trae las decisiones cerradas con su fundamento), `DROPI.md` §9 (el alcance real de la API, medido) y `.kiro/steering/dropshipping-magandhi.md`.

**Repositorios:** quedan abiertos PR viejos ya superados: panel #252, #227 y #216; tienda #46, #21 y #15. Cerrarlos o no lo decide el dueño.

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
