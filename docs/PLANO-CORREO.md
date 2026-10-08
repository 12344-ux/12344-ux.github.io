# PLANO · Correo de MAGANDHI

**Corte:** 8 de octubre de 2026. Runbook de despliegue: `supabase/INSTRUCCIONES.md` § CO.

## Decisión de arquitectura

Software propio = **el cerebro**: copys, reglas, bitácora, panel y, más adelante,
contactos, consentimiento y campañas. **El cartero es Resend**: la entrega en
bandeja depende de reputación de IPs, SPF/DKIM/DMARC y manejo de rebotes, y un
servidor propio caería en spam desde el primer día.

| | Transaccionales (este tramo) | Email marketing (después) |
|---|---|---|
| Qué | 4 avisos del pedido | Novedades masivas a un clic |
| Disparo | A mano desde Seguimiento (hoy) | Campaña desde el panel |
| Subdominio | `updates.magandhi.com` | `news.magandhi.com` |
| Consentimiento | No requerido: es parte de la compra | **Obligatorio**, registrado, con baja en cada correo (Ley 1581 y Ley 2300 de 2023) |

Subdominios separados para que una queja de marketing no afecte la llegada de
«tu pedido va en camino».

## Costo

Plan Free de Resend: 3.000 correos/mes y 100/día. Con 4 correos por pedido son
unos 25 pedidos/día y 750/mes, más las pruebas. Se paga (Pro, 20 USD/mes) solo
cuando se pase de ahí o arranque el marketing masivo.

## Este tramo (construido)

- Un correo por etapa: recibido, preparando, en camino, entregado.
- Envío **manual** desde el detalle del pedido; solo etapas ya alcanzadas.
- Copy en `correo_plantillas`. El editor `ventas/correos/` se retiró en EM1
  (decisión del dueño): los textos se cambian con un SQL que entrega Kiro. Nace como **borrador** (copy de prueba).
- «Entregado» lleva el `codigo_resena` y UN botón a la ficha del producto. El
  código viaja en el fragmento `#resena=` (no llega a servidores ni al Referer),
  la tienda lo prellena y lo borra de la URL. El código no vence, así que el
  cliente puede opinar cuando haya probado el producto.
- Un solo botón por correo, sin imágenes pesadas ni enlaces repetidos: patrón
  transaccional que entra a Principal (lección de Stramont).
- Idempotencia: un envío en vuelo por pedido y etapa; reenviar exige confirmación
  y queda marcado; Resend recibe `Idempotency-Key`.
- Seguridad: la llave solo en Secrets, sin service_role, destinatario sacado de
  la base, cero acceso anon.

## Siguientes tramos (no construidos)

1. **Política de tratamiento de datos** publicada en la tienda: requisito legal
   antes de capturar autorizaciones de marketing.
2. **Captura de consentimiento «Novedades»**: tabla de contactos con fecha,
   fuente, texto aceptado y versión de la política; doble confirmación por
   correo; baja con un clic.
3. **Software de email marketing**: segmentos, editor de campañas, envío masivo
   por lotes, bajas automáticas y métricas.
4. Opcional: enviar el aviso automáticamente al avanzar el estado (hoy es manual
   a propósito).
