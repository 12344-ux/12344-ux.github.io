# ANDAMIOS · próximos tramos MAGANDHI / Impulse

**Corte:** 8 de octubre de 2026
**Punto de retorno:** Email marketing **EM1–EM7 completo** y Métricas **M1 y M2** en producción. **Siguiente: aplicar `20261018000000_puesta_al_dia_sin_vista.sql` y construir Wompi F2.** La estructura interna está terminada; lo único que falta para cerrar la fase de construcción es la cadena de pagos (F2 → F3 → F4).

Este archivo contiene solo trabajo pendiente y criterios de cierre. Las fases terminadas y decisiones vigentes están consolidadas en `CONTEXTO-MAGANDHI.md`; el historial anterior permanece en Git.

## Estado resumido

| Área/tramo | Estado | Evidencia o límite |
|---|---|---|
| Acceso/Auth | ✅ Operativo | Login, panel, guardia y RLS |
| Finanzas v1 | ✅ Operativo | Partida doble, libros, informes y trazabilidad |
| Inventarios | ✅ Operativo | Libro de movimientos y stock derivado |
| Marketing Project | ✅ Operativo | Proyección, tendencia y ranking |
| Campañas | ✅ Operativo | Ficha, publicación, galería, slug, vínculo y tope |
| Ventas | ✅ Operativo | Pedidos, estados, anulación y portafolio |
| Opiniones | ✅ Operativo | Esquema, RPC y Edge Function desplegados; panel y tienda vivos |
| Correos del pedido (4 etapas + código de reseña) | ✅ Producción | Resend `updates.magandhi.com`, probado en Gmail (Principal) |
| Email marketing EM1 (contactos y consentimiento) | ✅ Aplicado | |
| Email marketing EM2 (perfiles + segmentos) | ✅ Aplicado | |
| Email marketing EM3 (análisis de clúster) | ✅ Aplicado | |
| Email marketing EM4 (campañas) | ✅ Producción | `em-campana` desplegada; envío probado por el dueño |
| Email marketing EM5 + EM5.1 (resultados y respuesta a email) | ✅ Producción | Webhook Svix conectado |
| Email marketing EM6–EM7 (captura pública y analítica) | ✅ Producción, **apagadas a propósito** | El dueño abre la tienda cuando esté todo; la política definitiva la redacta él |
| Métricas M1 (En vivo, Ventas, Tienda) | ✅ Producción | |
| Métricas M2 (Email, Opiniones, Inventario) | ✅ Producción | `20261017000000` aplicada |
| Tramo 0 | ✅ Verificado | Matriz 170/170 y anon bloqueado en superficies internas |
| Wompi F1 | ✅ Sandbox | Intención firmada y checkout cargando |
| Puesta al día 2026-10-02 | ⛔ **SUPERADA, no aplicar** | Aplicarla hoy retrocedería la vista `catalogo_publico`; ver `INSTRUCCIONES.md` §0 |
| Puesta al día forward `20261018000000` | ⏭️ **Siguiente** | Solo los 3 huecos medidos; no toca la vista. Probada 18/18 + matriz 170/170 |
| Wompi F2 | ⏭️ Siguiente | Webhook, idempotencia, intención persistida y pedido |
| Wompi F3 | ⏸️ Después de F2 | Asiento contable automático |
| Wompi F4 | ⏸️ Después de F3 | Paso controlado a producción |
| D3 permisos granulares | ⏸️ Antes de delegar | Separar capacidades antes del primer no-admin |

## Tramo inmediato P0 — puesta al día forward

### Qué aplicar

`supabase/migrations/20261018000000_puesta_al_dia_sin_vista.sql`, una sola vez en
SQL Editor. **No** aplicar `20261002000000` (superada: retrocedería la vista).

Cierra los tres huecos que se midieron en producción el 8-oct-2026:

1. `cm_publicar_campana` exige producto de Inventario ligado y activo + precio positivo.
2. Se retiran las 5 puertas latentes de escritura directa en Finanzas.
3. Marketing puede borrar imágenes huérfanas solo en el bucket `campanas`.

La vista `catalogo_publico` **no se toca**: la versión del 3-oct ya trae la regla
«campaña sin `product_id_ref` = no comprable».

### Por qué importa para F2

F2 convierte un pago aprobado en pedido y baja stock. Una campaña publicada sin
producto de Inventario ligado sería vender algo sin existencias detrás. El
candado (1) es el que lo impide.

### Evidencia obligatoria

- La consulta de verificación de `INSTRUCCIONES.md` §0 devuelve `true, 0, true, true`.
- Campaña sin Inventario ligado: no publicable. Con producto activo y precio: publicable.
- Finanzas sigue guardando asientos por RPC.
- El checkout de la tienda sigue abriendo (la intención de pago lee el catálogo).

El tramo no queda ✅ por ver "Success"; se cierra con estas comprobaciones.

### Lección registrada

Producción se había desviado del registro de migraciones y el arnés local, que
aplica **todas**, daba falsa confianza. Cuando haya desviación, simular el estado
real con `supabase/pruebas/local/herramientas/correr-puesta-al-dia.sh`.

## Tramo correo — entregar el código de reseña

### Objetivo

Que el código de reseña del pedido llegue al cliente en el **último correo de seguimiento**, cuando ya recibió el producto y puede probarlo. Es lo único que falta para que el sistema de opiniones reciba opiniones reales.

### Lo que ya existe

- `pedidos.codigo_resena` se genera solo al crear cualquier pedido, manual o web.
- El código es visible en el back-office para compartirlo a mano mientras no haya correo.
- Toda la validación server-side está desplegada y probada.

### Lo que falta decidir y construir

1. Proveedor de correo y verificación del dominio `magandhi.com`.
2. En qué punto exacto del seguimiento se dispara, atado al estado `entregado`.
3. Plantilla del correo con un solo botón o acción clara, siguiendo el patrón de correo transaccional para no caer en promociones.
4. Idempotencia: el código se envía una sola vez por pedido y no se insiste con recordatorios.

### Criterios de cierre

- Un pedido marcado como entregado produce exactamente un correo con su código.
- El código del correo permite dejar una opinión y queda quemado para ese producto.
- Ningún secreto viaja al navegador ni a los registros.

## Tramo F2 — pagos y webhook idempotente

### Objetivo

Un pago aprobado debe convertirse exactamente una vez en un pedido trazable, sin vender stock inexistente ni dejar dinero huérfano.

### Diseño mínimo obligatorio

1. Persistir una intención antes de devolver la firma:
   - referencia única;
   - campaña/producto;
   - cantidad;
   - monto firmado;
   - estado inicial;
   - timestamps.
2. Crear endpoint webhook separado de la función pública de intención.
3. Verificar autenticidad del evento Wompi server-side.
4. Guardar transición de estado de forma idempotente.
5. En `APPROVED`, dentro de una operación transaccional:
   - bloquear intención/producto;
   - releer precio y disponibilidad;
   - impedir doble procesamiento;
   - crear pedido/items;
   - registrar salida de inventario;
   - marcar intención procesada.
6. Registrar errores recuperables sin perder el evento.
7. Probar reintento y evento duplicado.

### Fuera de alcance de F2

- asiento contable automático (F3);
- producción real (F4);
- multimoneda;
- carrito de múltiples productos;
- reservas temporales complejas si cantidad sigue fija en 1.

### Criterios de cierre

- El mismo evento enviado dos veces produce un solo pedido.
- Pago rechazado no crea pedido ni salida.
- Pago aprobado sin stock queda en recuperación controlada y no se procesa en silencio.
- La referencia permite identificar la intención sin inferencias.
- Ningún secreto llega al navegador o logs.
- El pedido aparece en Seguimiento y alimenta Portafolio/Ranking.

## Tramo F3 — asiento automático

- Configurar cuentas contables mediante `contabilidad_config`.
- Crear asiento balanceado a partir de un pago aprobado/procesado.
- Idempotencia compartida con la intención/pedido.
- No duplicar ingreso, inventario o costo ante reintentos.
- Verificar al peso con Diario, Mayor, Estado de resultados y Balance general.

## Tramo F4 — producción

- Credenciales de producción únicamente en servidor/config protegida.
- Webhook de producción validado.
- URLs de retorno reales.
- Prueba de monto pequeño con conciliación completa.
- Plan de reversión sin force-push ni reescritura contable.
- Solo después cambiar el entorno activo.

## D3 — antes del primer usuario no-admin

Separar capacidades hoy agrupadas:

- Campañas: leer / editar / publicar.
- Marketing Project: análisis sin publicar.
- Ventas: pedidos / clientes / PII.
- Inventario: consulta / movimiento / administración.
- Finanzas: consulta / asiento / configuración.

La separación debe cubrir panel, grants, RLS y RPC. Ocultar tarjetas no es seguridad.

## Pendientes de producto, no bloqueadores de F2

- Políticas públicas de privacidad, entregas, cambios y condiciones.
- Repaso de textos de la sección de opiniones; su diseño ya quedó aprobado.
- Cierre anual de Finanzas cuando corresponda.
- Pulido de exportaciones tras uso real.
- Favicons finales específicos para Marketing, Producción y Ventas.
- Elasticidad cuando exista necesidad validada.

## Reglas duras

- Migraciones aplicadas son inmutables; toda corrección es forward.
- Nunca reejecutar una migración histórica como rollback.
- SQL escrito no está desplegado hasta ejecutarlo en Supabase.
- Edge Function escrita no está desplegada hasta redesplegarla.
- No activar Wompi producción antes de F2.
- No crear el primer usuario reducido antes de D3.
- Nunca exponer secretos o `service_role`.
- Rama y PR nuevos por cambio; nunca push directo a `main`.
