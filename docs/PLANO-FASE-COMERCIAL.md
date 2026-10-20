# PLANO · Fase comercial: Carrito + Promocionar

**Decisión del dueño:** 16 de octubre de 2026  
**Estado por tramos (20-oct-2026):** **C1–C5 están cerrados estructuralmente en producción** con sus límites documentados; C4 quedó superado por C5. Carrito encendido y Wompi `prod`. Ningún tramo de carrito tiene cierre transaccional: falta un pago real autorizado. **P0 está cerrado como contrato documental. P1 tiene implementación preparada en backend y tienda, pero no está desplegado ni medido;** P2–P5 siguen pendientes. La fase completa no está cerrada hasta el cierre transaccional y Promocionar.
**Superficies:** back-office `montaguth.institute`, tienda `magandhi.com` y backend compartido en Supabase.

Este plano reúne los dos frentes comerciales elegidos para la siguiente evolución de MAGANDHI:

1. **Carrito autenticado y cantidades por pedido.**
2. **Promocionar:** enlaces, piezas y atribución comercial propias, sin Meta Ads en esta fase.

No reemplaza los planos de Pagos, Cuentas, Métricas ni Dropshipping. Los extiende sin romper sus decisiones vigentes: compra invitada, precio autoritativo server-side, idempotencia Wompi, inventario protegido, analítica consentida y proveedor privado.

---

## 0. Promesa de la fase

> MAGANDHI podrá vender varias unidades y varios productos de forma segura, y podrá preparar, compartir y medir enlaces comerciales propios sin entregar a terceros el control de la tienda ni de sus datos.

La fase no se cierra porque una interfaz se vea terminada. Se cierra cuando:

- el total cobrado coincide con las líneas congeladas en la intención;
- ningún pedido supera el stock ni el máximo comercial;
- un evento repetido de Wompi no duplica pedido, inventario ni carrito;
- una venta puede atribuirse a un enlace propio sin inventar personas;
- los enlaces retirados no se reasignan ni se convierten en redirects abiertos;
- invitado, compra inmediata y flujos históricos siguen funcionando.

---

## 1. Decisiones cerradas

### 1.1 Cantidades y carrito

1. **El límite es por pedido, no acumulado de por vida.** Una nueva compra puede volver a usar el máximo.
2. Campañas tendrá un campo obligatorio **“Máximo de unidades por pedido”**, entero entre `1` y `20`. Las campañas existentes nacen con `1`.
3. Elegir cantidad estará disponible también para invitados. **El carrito será exclusivo de cuentas autenticadas.**
4. Se conservan los dos caminos: **Comprar ahora** y **Agregar al carrito**.
5. El carrito se persiste en Supabase por `auth.uid()` y puede continuar en otro dispositivo. No guarda precio como verdad.
6. El navegador nunca envía precio confiable, `customer_id`, UID, origen interno ni stock.
7. El carrito no reserva inventario. Antes de cobrar se releen precio, publicación, máximo y disponibilidad; al aprobar el pago se validan otra vez bajo el candado de `crear_pedido`.
8. ~~El carrito solo elimina las líneas confirmadas después de un pago aprobado. Rechazo las deja editables; pendiente/revisión mantiene un bloqueo prudente.~~ **Reemplazado por C5:** al crear la intención, sus líneas pasan a Mis compras y el carrito queda libre de inmediato; rechazo o vencimiento dejan la compra como no completada, sin bloquear ni alterar el carrito nuevo.
9. El checkout invitado permanece disponible y no se fuerza registro.

### 1.2 Máximo comprable efectivo

El valor público no es “cuántas existencias hay”, sino cuánto admite agregar MAGANDHI en ese pedido.

**Producto propio:**

```text
max_comprable = max(0, min(max_campaña, existencias_disponibles))
```

**Producto de proveedor:**

```text
disponibilidad_vendible = stock_reportado − unidades_pagadas_pendientes − piso_dropi
max_comprable = max(0, min(max_campaña, disponibilidad_vendible))
```

Con piso Dropi `20`, stock reportado `24`, cero pendientes y máximo de campaña `5`, el máximo comprable es `4`. Las 20 unidades del piso quedan protegidas también **después** de la compra.

Reglas:

- el catálogo puede exponer `max_comprable`, que ya viene limitado por Campañas; nunca stock total, piso, reservas, proveedor ni ids externos;
- si `max_comprable = 0`, el producto se trata como agotado;
- la ficha dice **“Máximo N unidades por pedido”**, no “quedan N”;
- agregar repetidamente acumula hasta el máximo, no crea líneas para evadirlo;
- si la disponibilidad baja, la tienda explica el nuevo máximo y exige ajustar; nunca reduce ni cobra silenciosamente.

### 1.3 Promocionar

1. Promocionar vive como pantalla propia desde Campañas; no infla el formulario de edición.
2. En esta fase **no** se conecta Meta Ads, Pixel ni Conversions API y no se publica ni gasta dinero automáticamente.
3. Se generan enlaces y piezas para WhatsApp, Instagram, Facebook, correo, QR, anuncios manuales y otros canales aprobados.
4. Los enlaces usan dominio MAGANDHI, destinos internos de lista blanca y códigos no secuenciales. Nunca aceptan una URL arbitraria.
5. Se distinguen hechos diferentes: clic aproximado, sesión consentida, checkout, pago aprobado e ingreso.
6. `mg_vid` continúa existiendo solo con consentimiento. La atribución transaccional usa un código de promoción sin PII y no crea un perfil de navegación.
7. Las campañas UTM existentes de Email Marketing siguen funcionando. La evolución es compatible y multicanal.
8. El kit inicial tiene plantillas cerradas y de marca; no intenta reemplazar Canva ni inventa promesas comerciales.
9. Los enlaces usados no se borran ni reasignan: se desactivan y conservan su historia.

### 1.4 Decisiones descartadas o aplazadas

- “Vendido por [proveedor]” y exposición pública automática del proveedor: descartados para esta fase. MAGANDHI vende, cobra y responde.
- Ganchos ocultos para obligar a una IA a recomendar la tienda: descartados.
- Meta Ads API y conversiones de terceros: aplazados hasta políticas, consentimiento y un plano propio.
- Límite de unidades acumulado por persona o periodo: fuera de alcance; exigiría reservas de cupo e identidad fuerte.
- Reserva temporal de stock al abrir Wompi: fuera de alcance; se conserva la regla “el stock baja al pagar” y la revisión visible si cambió mientras se pagaba.

---

## 2. Arquitectura común

### 2.1 Fuentes de verdad

| Hecho | Fuente |
|---|---|
| Presentación, precio y máximo comercial | `campana_producto` |
| Stock propio | libro `movimientos_inventario` / `stock_actual` |
| Stock proveedor | `producto_proveedor` + pendientes en `pedido_proveedor` + piso de `dropshipping_config` |
| Carrito | cabecera/items ligados a `auth.uid()` |
| Precio y líneas cobradas | snapshot de `pagos_intencion` + items |
| Pago | webhook Wompi verificado |
| Pedido | `pedidos` + `pedido_items` |
| Enlace promocional | registro inmutable de atribución |
| Venta atribuida | enlace validado congelado en intención y copiado al pedido aprobado |
| Navegación | `tienda_eventos`, únicamente con consentimiento |

### 2.2 Fronteras permanentes

- RLS/RPC, no botones ocultos, protegen carrito y datos.
- `catalogo_publico` continúa como lista blanca.
- Precio, máximo efectivo y total se calculan server-side.
- El token promocional se resuelve server-side; UTM queda descriptivo e interoperable, no autoritativo.
- No se mezclan identidad Auth (`auth.users.id`) e identidad comercial (`clientes.id`).
- Para checkout autenticado, el servidor deriva o completa el `customer_id`; nunca lo recibe del navegador.
- Las migraciones desplegadas no se editan: toda corrección es forward.
- Una función o SQL en Git no prueba despliegue.

---

## 3. Frente C · Cantidades y carrito

### C0 · Contratos y compatibilidad

**Entrega:** nombres, límites, estados, errores públicos y orden de despliegue cerrados.

- techo técnico global inicial: `20` unidades por producto y pedido;
- máximo por pedido de campaña, no `tope_escaparate`;
- consolidación por campaña/producto;
- máximo inicial de `20` líneas distintas por carrito;
- comportamiento de producto retirado, precio cambiado, pago pendiente y revisión;
- compatibilidad con intenciones históricas escalares.

**Cierre:** el plano y las firmas futuras no dejan semánticas ambiguas.

### C1 · Cantidad en compra inmediata

**Entrega:** una ficha puede comprar `1..max_comprable` sin carrito.

Backend:

- nueva columna de Campañas con `default 1` y constraint;
- alta/edición de Campañas y validación server-side;
- cálculo único del máximo efectivo para propio/proveedor;
- `catalogo_publico` expone solamente `max_comprable`;
- `crear-intencion-pago` deja de forzar `1`, valida entero y máximo;
- verificación Dropi exige que el remanente posterior conserve el piso;
- `pw_registrar_intencion` repite las reglas antes de firmar;
- `crear_pedido` impone el máximo final además del stock.

Tienda:

- selector accesible de cantidad;
- copy “Máximo N unidades por pedido”;
- total visible antes de continuar;
- compra invitada y retorno Wompi intactos.

**Cierre final del contrato:** cantidad 1 no cambia; máximo, máximo+1, baja de stock y pago repetido se comportan con verdad y sin sobreventa.

**Estado medido · 16-oct-2026: desplegado y probado en estructura.**

- Backend/back-office #276 fusionado a `main` en `e75dc1cbd1643d3897e851cc2e06fe47f3b87ecc`; tienda #102 fusionada en `db56c4f64de9dc2af5ac77b3c444467e1a72cb0c`.
- Migración `20261102000000_comercial_c1_cantidad_inmediata.sql` aplicada; postflight 9/9 `true`; `crear-intencion-pago` desplegada; tienda publicada.
- Cantidad 1: HTTP 200 y persistencia 7/7 `true`, sin pago, pedido ni webhook.
- Cantidad 2 con máximo 1: HTTP 409 `MAX_COMPRABLE`.
- Grisi con máximo 2 y `max_comprable=2`: intención HTTP 200 por 13.980.000 centavos (COP 139.800).
- El dueño confirmó selector, máximo, total, modal y compra invitada estructural.

**Límite:** no hubo pago real de dos unidades. Para cantidad 2 no se midieron webhook, pedido, baja de dos unidades, asiento, correo ni repetición/idempotencia. Por eso C1 está listo en estructura, pero esta evidencia no satisface todavía la parte transaccional de su cierre final ni relaja la definición de terminado de la fase. Una prueba monetaria qty2 es opcional y requiere autorización expresa del dueño.

### C2 · Carrito autenticado persistente

**Entrega:** guardar, editar y retirar productos sin tocar todavía Wompi multiproducto.

Modelo conceptual:

```text
carritos
  id · auth_user_id · estado · version · creado · actualizado

carrito_items
  carrito_id · campana_id · cantidad · creado · actualizado
```

Reglas:

- una cesta activa por UID;
- RLS de propietario y RPC transaccionales para agregar/cambiar/quitar;
- no se persiste precio autoritativo;
- agregar dos veces consolida cantidad;
- salida/cambio de usuario retira inmediatamente la cesta visible;
- una cuenta no disponible no puede usarla.

Tienda:

- icono junto a “Mi cuenta”, oculto hasta confirmar sesión;
- badge accesible;
- “Agregar al carrito” solo para cuenta válida;
- `/carrito/` con líneas, cantidades, subtotal actual, retirar y mensajes de cambio.

**Activación:** C2 puede desplegarse apagado, pero no se publica como promesa hasta C3.

**Estado medido · 16-oct-2026: Comercial C2 desplegado y probado en
estructura; dejó el flag final apagado para construir C3.**

- Backend/back-office PR #278 fusionado: implementación `f68fd24`, matriz
  `8d4c64d` y merge a `main` `a811082cc585ad8d77a98aa346ffbd06ac2ac3f4`;
  Pages terminó construido para ese merge.
- Tienda PR #104 fusionado: implementación
  `90dcb6d42eabd26935743b5bae4de9bba9692e39` y merge a `main`
  `35a104a1c12b9b9276773bc7d7c082c0733c73a9`; Pages terminó construido.
- Preflight de producción 3/3 `true`; migración `20261103000000` aplicada;
  postflight 10/10 `true`.
- El flag OFF se comprobó correcto. Durante una activación temporal, el dueño
  probó agregar, consolidar, cambiar y retirar; persistencia entre navegadores;
  aislamiento entre dos cuentas; conflicto entre pestañas; logout y compra
  invitada.
- Invariantes finales: `sin_doble_activo=true` y `sin_huerfanas=true`.
- No hubo dinero, Wompi, pedido ni Inventario. El flag final quedó `false`.

**Límite:** C2 entrega el carrito autenticado persistente y sus candados de
propiedad, pero no checkout multiproducto, líneas congeladas, cobro, pedido,
consumo postpago ni vínculo transaccional de cuenta. Eso comienza en C3/C4; el
cierre final de la fase permanece pendiente.

### C3 · Intención y checkout multiproducto

**Entrega:** pagar el carrito completo una sola vez.

- `pagos_intencion` pasa a cabecera compatible;
- nueva tabla de líneas congeladas con campaña, producto, nombre, cantidad, precio y subtotal;
- RPC recibe únicamente ids/cantidades, relee campañas y calcula `Σ(precio × cantidad) × 100` con enteros;
- máximo de líneas, cantidad y monto total;
- Dropi se consulta por producto con concurrencia baja para respetar el 429 medido;
- firma Wompi sobre el total exacto persistido;
- webhook compara monto, moneda y entorno, carga las líneas y reutiliza `crear_pedido`;
- referencia/transacción/pedido quedan ligados de forma única e idempotente;
- el monto del webhook no pasa por `Number` si puede perder precisión;
- intenciones históricas de una línea continúan procesables.

**Cierre:** carrito mixto propio/proveedor, cantidades, repetición de webhook y falta de stock terminan en un único resultado auditable.

**Estado medido · 17-oct-2026: desplegado y probado en estructura; flag final
`false`.**

- Backend #280 y tienda #106 fusionados; Pages construido para la tienda.
- Migración `20261104000000` aplicada; postflight de objetos, firmas, índice,
  RLS, grants e invariantes correcto.
- `crear-intencion-pago` y `wompi-webhook` redesplegadas. CORS, sesión requerida,
  ambiente desconocido y firma ausente fallaron de la forma esperada.
- Con activaciones temporales se verificaron carrito multiproducto, cantidades,
  subtotales, persistencia, formulario y retorno.
- Una intención v2 en `prod`, sin pago, congeló líneas y total exactos; Wompi
  abrió por ese total y un reintento desde otra sesión conservó una sola
  intención por UID/carrito/versión.
- No hubo aprobación, pedido, inventario, asiento, correo, webhook repetido ni
  falta de stock post-intención. Esos criterios del cierre final siguen sin
  medirse por decisión del dueño para no modificar inventario.

**Límite:** C3 está correcto en estructura, no end-to-end. La intención de prueba
permanece en `creada`, sin pedido/evento, como evidencia histórica. No se borra
ni se presenta como venta. El ciclo de consumo/desbloqueo y `customer_id`
pertenece a C4.

### C4 · Cuenta y ciclo del carrito

**Entrega:** propiedad comercial, expiración y ciclo del carrito coherentes.

- `crear-intencion-pago` valida el JWT y deriva el UID; `customer_id` se resuelve
  desde la cuenta activa y Auth, nunca desde el navegador;
- si la cuenta aún no tiene cliente comercial, se crea o vincula en la primera
  aprobación dentro de la transacción del pedido y bajo el advisory lock
  `cc-correo:` compartido con Cuentas C2;
- el destinatario y su dirección quedan como snapshot de la orden, separados de
  la identidad comercial que determina `customer_id`;
- cada intención C4 expira autoritativamente a los 30 minutos y el mismo instante
  persistido forma parte de la firma enviada a Wompi;
- la intención C3 existente conserva `ciclo=0`; el siguiente checkout registra
  su sucesión, avanza una vez la versión y reintenta sobre la versión nueva;
- el snapshot expone `bloqueo_pago: null | pendiente | revision`, sin revelar la
  referencia; pendiente y revisión impiden mutar el carrito;
- aprobación normal valida el snapshot y sustrae las cantidades congeladas,
  preservando unidades extra y líneas nuevas; un drift histórico puede dejar
  consumo parcial auditable;
- `DECLINED`, `VOIDED`, `ERROR` y la expiración conservan líneas, liberan y
  avanzan una vez la versión; `PENDING` o un estado no terminal conserva líneas,
  versión y bloqueo;
- un `APPROVED` tardío, posterior a rechazo/expiración o con sucesora, pasa a
  `requiere_revision` sin crear automáticamente otro pedido;
- la revisión solo se resuelve desde Ventas mediante la acción explícita
  `reembolsado_liberar`, después de confirmar el reembolso;
- el retorno v2 usa `estado-pago` y `pw_estado_checkout_publico`, exige JWT del
  propietario y devuelve estado más el ID/versión del carrito propio para
  recargar, sin PII, monto, pedido, transacción, motivo ni entorno;
  `pw_estado_publico` queda para v0/v1;
- los helpers propios de C4 no tienen `EXECUTE` de API; el helper booleano
  histórico `pw__contexto_servidor()` no expone ni muta datos y se excluye de
  esa auditoría por variaciones de ownership; las Edge usan puertas nominales;
- `Comprar ahora` e invitado continúan como caminos independientes.

**Relación con Cuentas:** este tramo materializa parte de C4 sin obligar a completar toda la futura pantalla C3 de perfil/pedidos.

**Estado productivo · 19-oct-2026:** C4 está **aplicado, desplegado y probado
sin dinero**. La migración `20261105000000` se aplicó una vez y el postflight
dio 30/30 funciones correctas. El puente de estado y las Edge `estado-pago` y
`crear-intencion-pago` están en producción, igual que Ventas y la tienda
(PR #283, #108, #284, #109 y #285). **El carrito quedó encendido** al cierre de
la sesión. Se corrigieron en producción dos defectos: ids de campaña rechazados
por la tienda y una campaña publicada sin slug. Sin pago aprobado no hay cierre
transaccional. Detalle y decisiones abiertas en
`docs/RELEVO-COMERCIAL-C4-2026-10-19.md`.

**C5 · desplegado y cerrado estructuralmente el 20-oct-2026:** el dueño eligió
separar carrito y pago. Al crear correctamente la intención, las líneas congeladas se vuelven
una compra en proceso y el carrito queda libre en la misma transacción. «Mis
compras» lista procesos, realizadas y no completadas; permite continuar solo
sin transacción bancaria y verificar PENDING/revisión. El estado logístico sale
de `pedidos.estado`, el panel intenta el correo de cada avance y la opinión solo
se habilita tras entregado. Backend #287 (`c8fd03c`) y tienda #113 (`4a0b439`)
están fusionados. Migraciones `20261106000000` y `20261106000100` aplicadas,
Edge C5 desplegadas, postflight y activación correctos, y recorrido sin dinero
confirmado por el dueño. Contrato en `docs/PLANO-COMERCIAL-C5.md`; evidencia en
`docs/RELEVO-COMERCIAL-C5-CIERRE-2026-10-20.md`.

**Resuelto:** slug automático server-side (`20261106000100`): trigger, backfill
determinista y `NOT NULL`; ninguna campaña puede publicarse sin slug.

---

## 4. Frente P · Promocionar

### P0 · Taxonomía y privacidad

**Estado · 20-oct-2026:** **cerrado como contrato documental**, sin cambios de
esquema, Edge Functions, tienda, DNS, políticas publicadas o producción. Fuente
de verdad: `docs/PLANO-PROMOCIONAR-P0.md`; relevo:
`docs/RELEVO-PROMOCIONAR-P0-2026-10-20.md`.

**Entrega cerrada:** contrato de atribución antes de capturar datos.

- canales canónicos: `whatsapp`, `instagram`, `facebook`, `email`, `qr`,
  `anuncio_manual` y `otro_controlado`;
- `source`, `medium`, `campaign` y `content` normalizados con un algoritmo único;
- código propio opaco y autoritativo; UTM descriptivo y compatible;
- modelo inicial de último enlace propio válido dentro de una visita de 30 minutos;
- clic diario agregado sin perfil individual ni historial de IP/referrer/User-Agent;
- `mg_vid` y eventos de navegación solo con consentimiento;
- precedencia excluyente entre exacta propia, legacy UTM de email,
  aproximada de email y sin atribuir;
- retención, desactivación, estados e inmutabilidad de enlaces definidos.

**Límite:** P0 no implementó captura. Las políticas públicas siguen en
`borrador-0`; deben incorporar y revisar este contrato antes de activar P3/P4.
P1 puede avanzar sin adelantar redirector, atribución transaccional o métricas.

### P1 · Producto compartible

**Estado · 20-oct-2026:** implementación preparada en backend y tienda;
producción pendiente. Contrato y gates en `docs/PLANO-PROMOCIONAR-P1.md`;
relevo en `docs/RELEVO-PROMOCIONAR-P1-2026-10-20.md`.

**Entrega preparada:** la URL de cada producto genera confianza y una preview real.

- URL canónica estable `/producto/<slug>/`;
- HTML inicial por producto con título, description, canonical, Open Graph, Twitter Card y JSON-LD;
- imagen social pública y estable;
- sitemap y robots;
- compatibilidad con `/producto/?slug=` y UUID;
- historial/alias server-side si cambia un slug;
- precio, stock y máximo continúan vivos y nunca son metadata estática;
- `noindex,follow` permanece hasta comprobar producción sin JavaScript y publicar políticas.

La tienda genera shells completos y deterministas desde una única plantilla y
un manifiesto unido por UUID. La migración P1 reserva cada slug histórico para
su campaña original y expone una vista mínima alias → slug actual. Ninguno de
estos hechos se considera desplegado hasta ejecutar el runbook y medir Pages.

### P2 · Estudio Promocionar

**Entrega:** utilidad comercial completa aun sin medición.

Nueva acción `Promocionar` desde una campaña guardada/publicada:

- enlace oficial;
- presets por canal;
- generador UTM;
- copiar y Web Share;
- vista previa interna;
- textos deterministas y editables a partir de contenido aprobado;
- QR local, sin enviar la URL a un tercero;
- kit inicial: cuadrado `1080×1080`, historia `1080×1920` y horizontal;
- exportación local; sin publicación automática.

### P3 · Registro y enlace corto

**Entrega:** piezas versionadas y enlaces controlados.

Modelo conceptual:

```text
atribucion_enlaces
  id · codigo · campana_producto_id · canal_promocion
  source · medium · campaign · content · tipo_destino · estado_enlace
  receta/texto opcional · reemplaza_enlace_id · auditoria

atribucion_clics_dia
  enlace_id · fecha_colombia · total_aproximado
```

Los nombres, estados, normalización e inmutabilidad los gobierna
`docs/PLANO-PROMOCIONAR-P0.md`; este bosquejo no los redefine.

- códigos aleatorios, no secretos ni secuenciales;
- destino resuelto desde campaña, nunca desde `?url=`;
- desactivar sin borrar/reasignar;
- filtro de bots, previews, HEAD y prefetch;
- conteo diario agregado, sin almacenar persona, IP, referrer o user-agent como historial;
- rate limit con el patrón temporal ya usado en `tienda-eventos`.

URL objetivo: `go.magandhi.com/<codigo>` si el routing/DNS se aprueba. Alternativa inicial: ruta de marca menos elegante sin mover el dominio principal.

### P4 · Atribución exacta hasta la venta

**Entrega:** saber qué enlace produjo qué resultado sin depender de una UTM inventada.

- la tienda conserva el código propio separado de `mg_vid`;
- la Edge Function lo valida y congela `atribucion_enlace_id` en la intención;
- el webhook copia esa FK al pedido aprobado;
- `utm_campaign` de Email se conserva durante la transición;
- enlaces inventados no se atribuyen;
- una caída del sistema promocional no debe impedir una compra normal;
- compra exacta, atribución aproximada y sin atribuir se muestran separadas.

### P5 · Lectura comercial

**Entrega:** panel accionable en Campañas/Métricas/Ventas.

Por enlace/pieza/producto/canal:

- clics aproximados;
- sesiones medidas con consentimiento;
- producto visto;
- checkout iniciado;
- pagos aprobados;
- pedidos no anulados;
- ingresos;
- conversión con denominador explícito.

Ventas muestra la procedencia validada. Los pedidos manuales pueden tener una fuente declarada por el operador, rotulada como manual y distinta de la atribución exacta.

---

## 5. Orden de construcción

Los dos frentes se desarrollan por PR y se activan solo cuando cada contrato está completo. Estado actual (20-oct-2026): C1–C5 cerrados estructuralmente en producción; falta el cierre transaccional por carrito. **P0 está cerrado como contrato documental**, P1 es el siguiente tramo y P2–P5 permanecen pendientes.

1. **Plano y arranque — cerrado.** Este documento y referencias de contexto.
2. **C1 · cantidad inmediata — estructura lista.** Valor comercial rápido y cimiento de carrito; sin afirmar cierre transaccional de qty2.
3. **C2 · carrito persistente — estructura lista y flag OFF.** Datos/RLS/UI medidos.
4. **C3 · intención y checkout multiproducto — estructura lista y flag OFF.** Líneas congeladas, total autoritativo, Wompi abierto sin pago e idempotencia de intención medida.
5. **C4 · cuenta y ciclo bloqueante — cerrado estructuralmente y superado por C5.** Conserva compatibilidad histórica; no tuvo cierre monetario propio.
6. **C5 · Mis compras y carrito libre — cerrado estructuralmente el 20-oct-2026.** Edge, migración C5, slug automático, postflight, activación y recorrido sin dinero ejecutados; carrito encendido. Cierre transaccional pendiente de un pago real autorizado.
7. **P0 · taxonomía y privacidad — contrato cerrado.** Decisiones completas en `docs/PLANO-PROMOCIONAR-P0.md`; cero captura y cero producción.
8. **P1 · producto compartible — implementación preparada; producción pendiente.** Shells, metadata, sitemap, URLs limpias e historial/alias están en dos ramas coordinadas. Cierre según `docs/PLANO-PROMOCIONAR-P1.md` y runbook manual; no inferir despliegue por los PR.
9. **P2 · estudio Promocionar — pendiente.** Enlaces largos, textos, preview, QR y kit; no comienza antes de cerrar o aceptar expresamente el límite productivo P1.
10. **P3–P4 · enlace corto y atribución — pendiente.** Backend, routing y pago.
11. **P5 · lectura comercial — pendiente.** Métricas sobre hechos ya capturados.

P1 está preparado en código pero aún requiere despliegue coordinado y medición.
No se mezclan metadata, estudio, redirector, atribución y métricas en una sola
migración o despliegue.

---

## 6. Orden de despliegue por tramo

1. Migración forward compatible.
2. Matriz de permisos y diagnósticos de solo lectura.
3. Edge Functions compatibles con clientes viejos.
4. Back-office.
5. Tienda oculta o con feature flag.
6. Prueba controlada sin dinero cuando sea posible.
7. Prueba de dinero únicamente si el tramo toca Wompi y el dueño la autoriza.
8. Activación.
9. Medición de producción.
10. Actualización de este plano y `CONTEXTO-MAGANDHI.md` con evidencia real.

Nunca inferir “desplegado” porque el código esté fusionado.

**C1 siguió este orden hasta la medición estructural:** migración aplicada,
postflight 9/9 `true`, `crear-intencion-pago` desplegada, tienda publicada y
pruebas controladas sin dinero. No se ejecutó el paso monetario opcional para
cantidad 2; por tanto no se atribuyen a ese caso webhook, pedido, inventario,
asiento, correo ni idempotencia.

**C2 siguió el orden hasta la medición estructural:** código fusionado y Pages
construido en backend/back-office y tienda, preflight 3/3 `true`, migración
`20261103000000` aplicada, postflight 10/10 `true`, flag OFF verificado,
activación temporal y pruebas de carrito entre navegadores, cuentas y pestañas.
No hubo dinero, Wompi, pedido ni Inventario; el flag final quedó `false`.

**C3 siguió este orden hasta la medición estructural:** preflight limpio,
migración `20261104000000` aplicada, postflight correcto, Edge Functions
redesplegadas, sondas técnicas y regresión con flag OFF. Dos activaciones
temporales midieron UI y una intención v2 sin pago: total/líneas exactos,
retorno pendiente y una sola intención al reintentar entre sesiones. No hubo
aprobación, pedido, inventario, asiento, correo ni repetición real del webhook;
el flag final quedó `false`.

El gate local/CI de C4 ya está cumplido: el workflow «Banco de pruebas» run
`39320288166` terminó `SUCCESS` sobre `90fbdf2` de
`feat/comercial-c4-ciclo-carrito`, usando PostgreSQL 15 y Deno; pasaron las
migraciones y el banco CI, además de los checks de Node, el diff y la revisión.
`90fbdf2`/`2483bb2` acreditan la implementación inicial. El banco del paquete, run `39326788045`, terminó `SUCCESS` sobre `efa253f` con PostgreSQL 15/Deno; los seis SQL operativos pasaron además parser PostgreSQL. Este resultado no modifica producción.

**C4 recorrió la operación productiva el 19-oct-2026** con
`supabase/operacion/COMERCIAL-C4-CIERRE.md`: preflight, puente, `estado-pago`,
migración, postflight, `crear-intencion-pago` y ventana ON sin dinero. El
carrito quedó encendido. Faltan el pago con dinero (solo con autorización) y
el valor final del flag. La intención v2 que describía el relevo C3 no existe
en producción (`v2_total=0`), por lo que la sucesión C3 no aplicó.

**C5 recorrió la operación productiva el 20-oct-2026** con
`supabase/operacion/COMERCIAL-C5-CIERRE.md`: preflight, Edge C5 y sondas,
carrito OFF, migración C5, migración slug, postflight, activación y recorrido
sin dinero confirmado por el dueño. El proyecto no tiene tabla de ledger, así
que no hubo nada que reconciliar. Cuatro defectos de scripts se corrigieron
antes de continuar, sin efecto en producción. El carrito quedó encendido por
decisión del dueño; falta el pago con dinero, solo con autorización.

---

## 7. Riesgos que gobiernan la implementación

| Riesgo | Candado |
|---|---|
| Precio o máximo manipulado | relectura y cálculo server-side |
| Dos líneas evaden máximo | consolidación y validación final |
| Stock Dropi bajo el piso | validar remanente posterior a la cantidad |
| 429 de Dropi en carrito | consultas secuenciales/concurrencia baja |
| Pago duplicado | referencia, evento y pedido idempotentes |
| Carrito perdido al volver | consumir solo tras aprobación |
| Carrito de otro usuario | RLS por UID y limpieza al salir/cambiar cuenta |
| UTM inventada | código propio resuelto server-side |
| Link de phishing | destinos internos, sin open redirect |
| Bot contado como persona | clic aproximado separado de sesión consentida |
| Metadata social genérica | HTML inicial por producto, no meta tardía por JS |
| Drift entre planes y producción | diagnóstico y evidencia antes de actualizar estado |

---

## 8. Definición de terminado de la fase

- Cantidad `1` conserva exactamente el flujo vigente.
- Propio y proveedor respetan máximo y disponibilidad efectiva.
- Un carrito autenticado sobrevive otro dispositivo y nunca cruza usuarios.
- Invitado puede seguir comprando sin cuenta.
- Wompi cobra la suma exacta y un webhook repetido produce un pedido.
- Con C5, crear la intención libera el carrito y la compra vive en Mis compras; aprobación, rechazo o vencimiento nunca alteran el carrito nuevo.
- Producto compartido presenta nombre, imagen y marca correctos.
- Promocionar genera piezas útiles sin Meta ni servicios externos obligatorios.
- Un enlace propio no puede redirigir fuera de MAGANDHI.
- Las métricas no presentan clics como personas ni sesiones sin consentimiento.
- Documentación, permisos, diagnósticos y estado productivo quedan actualizados.
