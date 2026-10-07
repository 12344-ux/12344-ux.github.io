# ANDAMIOS · próximos tramos MAGANDHI / Impulse

**Corte:** 7 de octubre de 2026
**Punto de retorno:** Tramo 0 cerrado; F1 Wompi operativo en sandbox; puesta al día preparada; Opiniones terminado y desplegado. Los siguientes desarrollos son el correo con el código de reseña y Wompi F2.

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
| Correo con el código de reseña | ⏭️ Siguiente | Sin él no entran opiniones reales |
| Tramo 0 | ✅ Verificado | Matriz 170/170 y anon bloqueado en superficies internas |
| Wompi F1 | ✅ Sandbox | Intención firmada y checkout cargando |
| Puesta al día 2026-10-02 | 🟡 Código listo | Falta aplicar SQL y redesplegar Edge Function |
| Wompi F2 | ⏭️ Siguiente | Webhook, idempotencia, intención persistida y pedido |
| Wompi F3 | ⏸️ Después de F2 | Asiento contable automático |
| Wompi F4 | ⏸️ Después de F3 | Paso controlado a producción |
| D3 permisos granulares | ⏸️ Antes de delegar | Separar capacidades antes del primer no-admin |

## Tramo inmediato P0 — desplegar la puesta al día

### Código ya preparado

- `supabase/migrations/20261002000000_puesta_al_dia_seguridad_operativa.sql`
- `supabase/functions/crear-intencion-pago/index.ts`

### Acciones manuales del dueño

1. Ejecutar la migración nueva una sola vez en SQL Editor.
2. Registrar fecha y resultado de la ejecución.
3. Redesplegar `crear-intencion-pago` conservando sus secrets.
4. No cambiar todavía el entorno a producción.

### Evidencia obligatoria

- Campaña sin `product_id_ref`: no se puede publicar o aparece no comprable.
- Campaña con producto activo y precio positivo: puede publicarse.
- `anon`: continúa sin leer vistas/tablas internas.
- Finanzas: asientos siguen creándose/editarse/anularse mediante RPC.
- Storage `campanas`: Marketing puede eliminar keys de un intento fallido; anon no.
- Edge Function por slug: HTTP 200 en sandbox.
- Edge Function por UUID sin slug: retorno usa `?id=`, no `?slug=` vacío.
- Cantidad distinta de 1: HTTP 400.

El tramo no queda ✅ por ver “Success”; se cierra con estas comprobaciones.

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
- Clúster y elasticidad cuando exista necesidad validada.

## Reglas duras

- Migraciones aplicadas son inmutables; toda corrección es forward.
- Nunca reejecutar una migración histórica como rollback.
- SQL escrito no está desplegado hasta ejecutarlo en Supabase.
- Edge Function escrita no está desplegada hasta redesplegarla.
- No activar Wompi producción antes de F2.
- No crear el primer usuario reducido antes de D3.
- Nunca exponer secretos o `service_role`.
- Rama y PR nuevos por cambio; nunca push directo a `main`.
