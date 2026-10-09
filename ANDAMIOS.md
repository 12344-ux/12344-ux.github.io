# ANDAMIOS · próximos tramos MAGANDHI / Impulse

**Corte:** 9 de octubre de 2026
**Punto de retorno:** Wompi **F2 desplegado** en sandbox y **F3 construido y probado**, por aplicar. **Siguiente: aplicar F3 y después F4**, que se cierra con una compra real. La estructura interna está terminada; lo único que falta para cerrar la fase de construcción es esa cadena de pagos.

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
| Puesta al día forward `20261018000000` | ✅ Aplicada (8-oct, antes de F2) | Confirmar con las filas 3 a 5 del diagnóstico |
| Wompi F2 | ✅ Sandbox (8-oct) | Medido el 9-oct: tablas y funciones existen; `wompi-webhook` responde 401 sin firma. Falta la compra que lo compruebe (va en F4) |
| Wompi F3 | 🔨 **Construido, por aplicar** | Migración `20261020000000` + 2 Edge Functions. Runbook «Pagos F3» |
| Wompi F4 | ⏭️ Después de F3 | Bloqueador conocido: la URL de eventos de producción apunta a otro proyecto |
| D3 permisos granulares | ⏸️ Antes de delegar | Separar capacidades antes del primer no-admin |

## Tramo inmediato — aplicar F3

Runbook «Pagos F3» de `supabase/INSTRUCCIONES.md` (PF3.1 a PF3.5):

1. Migración `20261020000000_pagos_f3_asiento_automatico.sql`.
2. Definir `iva_ventas_pct` (0, 5 o 19). Es decisión del dueño con su contador y no se supone.
3. Que el producto a vender tenga `costo_unitario`, y la mercancía, su asiento de apertura.
4. Redesplegar `wompi-webhook` (Verify JWT apagado) y `enviar-correo-pedido`.
5. Diagnóstico: filas 21 y 25 a 31 como dice el runbook.

## Tramo F2 — cerrado en sandbox

Construido, probado y desplegado (diseño y criterios en `docs/PLANO-PAGOS.md`). El único criterio abierto es ver una compra real convertida en pedido, y se cumple con la compra de F4.

## Tramo F3 — asiento automático (construido, por aplicar)

Hecho y probado en local y en Actions (diseño en `docs/PLANO-PAGOS.md` §10): el asiento de la venta web real va contra la cuenta puente 138095; anular registra el contraasiento; es idempotente ante reintentos; la venta nunca falla por contabilidad; sandbox no se contabiliza; los asientos automáticos están protegidos; y el correo «Recibido» es automático. Se cierra en producción con la compra de F4 (runbook PF3.7).

Siguiente dentro de Finanzas, cuando haga falta: asiento automático de **ventas manuales** (pedir la forma de pago al registrar) y de **compras de mercancía** (costo del lote y forma de pago en «Registrar entrada»).

## Tramo F4 — producción

1. **Wompi, modo producción:** la URL de eventos debe ser la de `wompi-webhook` de este proyecto. Hoy apunta a otro proyecto (encontrado el 8-oct).
2. Secrets `WOMPI_EVENTS_PROD` y `WOMPI_INTEGRITY_PROD`, solo en Supabase.
3. `pagos_config.llave_publica_prod`, y al final `entorno = 'prod'`.
4. Recomendado antes de cobrar: tienda H2, H3 y H5 (relevo del 9-oct).
5. Compra real pequeña (un shampoo para uso del dueño), que verifica F2, F3 y F4 de una vez (PF3.7), y conciliación con la liquidación de Wompi (PF3.6).
6. Reversión: `entorno = 'sandbox'` deja de cobrar de inmediato; lo contable se corrige anulando el pedido, sin reescribir.

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
- No activar Wompi producción antes de aplicar F3 y corregir la URL de eventos de producción.
- No crear el primer usuario reducido antes de D3.
- Nunca exponer secretos o `service_role`.
- Rama y PR nuevos por cambio; nunca push directo a `main`.
