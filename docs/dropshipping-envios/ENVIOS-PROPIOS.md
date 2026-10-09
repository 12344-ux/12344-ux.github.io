# Envíos de productos propios

**Corte:** 9 de octubre de 2026 · **Estado:** esperando cotizaciones reales (`PUESTA-EN-MARCHA.md` §5).

Hoy un pedido propio sale sin número de guía. El objetivo es que cada envío tenga guía, transportadora y enlace de rastreo, y que el cliente los reciba en el correo «En camino».

## 1. Plataformas evaluadas

| Plataforma | Evaluación |
|---|---|
| **Mipaquete** | **Finalista.** Colombiana, con API v2 pública (ver detalle abajo). Ofrece contraentrega y la cotización trae la comisión de recaudo. |
| **Skydropx** | **Finalista.** Opera en Colombia, con API de sandbox y producción (ver detalle abajo). La contraentrega es solo en efectivo. |
| **Envíame** | Descartada por ahora. Multicourier de origen chileno, con unas 15 transportadoras en Colombia, pensado para volumen alto. |
| **Shippify** | Descartada para guías nacionales: es una red de entregas urbanas (mismo día, conductores independientes). Opción futura dentro de una ciudad, si opera en la de despacho. |

**Mipaquete · API v2:**

| Función | Servicio |
|---|---|
| Cotizar | `quoteShipping` |
| Crear el envío y la guía, con solicitud de recogida | `createSending` |
| Rastrear por guía | `getSendingTracking` |
| Cancelar | `cancelSending` |
| Municipios con código DANE | `getLocations` |
| Transportadoras | `getDeliveryCompanies` |
| Avisos a una URL nuestra, para guías y estados | `createWebHook` |

- Encabezados: `apikey` y `session-tracker`.
- La colección pública trae la URL de desarrollo. La de producción la entrega Mipaquete.

**Skydropx · API:**

- Credenciales: Client ID y Client Secret, en Conexiones → API.
- El token dura 2 horas y admite hasta 2 solicitudes por segundo. Host: `api-pro.skydropx.com`.
- Avisos firmados con HMAC para rastreo y órdenes. Se activan pidiéndolos a soporte (hola@skydropx.com).
- Si un aviso falla, hace 2 reintentos con 5 minutos de intervalo y no guarda historial de avisos.

## 2. Cómo se decide

Con la tabla de `PUESTA-EN-MARCHA.md` §5:

- precio y días por destino;
- cobertura de municipios pequeños;
- en empate, gana la que avise los cambios de estado sin que haya que preguntar.

## 3. Lo que necesita el sistema

- **Peso y medidas por producto.** Hoy `productos` no los tiene.
- **Ciudad con código DANE.** Hoy la tienda pide la ciudad como texto libre, y las dos plataformas cotizan por código de municipio. El departamento ya es una lista cerrada.
- **Dirección de origen** (desde donde se despacha). Se registra en la plataforma, no en el repositorio.

## 4. Fases

1. **Guía manual**, sin depender de nadie: el dueño crea la guía en la plataforma y la pega en el pedido. El correo «En camino» sale solo con el enlace de rastreo.
2. **Guía automática:** el panel cotiza, crea la guía con un clic y recibe los cambios de estado.

## Fuentes

- [Mipaquete · API v2 (Postman)](https://documenter.getpostman.com/view/14212363/Tzm8GFfQ) y [contraentrega](https://www.mipaquete.com/soluciones-ecommerce/envios-pago-contraentrega/)
- [Skydropx Colombia · API](https://app.skydropx.com/co/es-CO/api-docs), [webhooks](https://help.skydropx.com/articulos-cda/configuracion-de-webhooks) y [contraentrega](https://ayuda.skydropx.com.co/finanzas/contra-entrega/solicitar/)
- [Envíame en Colombia](https://enviame.io/enviame-el-marketplace-logistico-llega-a-colombia-para-automatizar-y-centralizar-envios/)
- [Shippify](https://www.shippify.cl/)

Contenido parafraseado de las fuentes.
