# Relevo de sesión · Promocionar P0 · 20 de octubre de 2026

**Punto de arranque vigente para Promocionar.** Leer primero
`docs/PLANO-PROMOCIONAR-P0.md`; después `docs/PLANO-FASE-COMERCIAL.md` §4 y
`CONTEXTO-MAGANDHI.md` §9. El relevo Comercial C5 conserva la autoridad sobre
carrito, Wompi y producción.

## 1. Respuesta corta

- **P0 queda cerrado como contrato documental.** El cambio no contiene
  migración, Edge Function, tienda, DNS, interfaz, captura o instrucción de
  despliegue.
- Se cerraron taxonomía, normalización, código propio, precedencia, visita,
  privacidad, conteo agregado, lifecycle y retención.
- Las políticas públicas siguen en `borrador-0`; P0 define lo que deberán
  explicar, pero no las presenta como revisadas o publicadas.
- **Siguiente etapa: P1 · Producto compartible.** P2–P5 siguen pendientes.

## 2. Decisiones cerradas

1. Canales: `whatsapp`, `instagram`, `facebook`, `email`, `qr`,
   `anuncio_manual` y `otro_controlado`.
2. `source` y `medium` derivan del canal; `campaign` identifica la iniciativa y
   `content` la pieza. Todos usan normalización ASCII con guiones.
3. El código propio futuro tendrá 16 caracteres Crockford base32, será opaco,
   no secuencial, público y nunca reasignable.
4. El destino se resuelve desde una referencia interna de lista blanca; nunca
   desde `url`, `next` o `redirect`.
5. Atribución inicial: último enlace propio válido dentro de una visita de 30
   minutos y de la misma pestaña.
6. El código propio validado gana sobre UTM. Email histórico conserva
   `legacy_email_utm`, rotulada como señal no verificada; el último clic a siete
   días sigue como `aproximada_email`. Las categorías son excluyentes.
7. Sin consentimiento se admite estado breve de visita, contador diario
   agregado, FK transaccional y un hash antiabuso con sal diaria, sin cruces y
   con purga máxima de 48 horas.
8. El contador guarda una fila diaria agregada, nunca un clic individual. IP,
   referrer y User-Agent no se conservan.
9. Estados: `borrador -> activo -> desactivado`. Un activo congela autoridad;
   un desactivado es terminal.
10. Hash antiabuso: 48 horas; visita: 30 minutos; detalle diario: 13 meses;
    código activado: reservado para siempre para impedir reasignación.

## 3. Compatibilidad preservada

- Email Marketing conserva su UTM y sus ids.
- `pedidos.utm_campaign` continúa durante la transición.
- Analítica EM7 sigue condicionada a consentimiento y política publicada.
- Compra invitada, compra inmediata, carrito y Wompi no cambiaron.
- No se mezclan `canal_promocion`, canal de venta, origen de navegación, fuente
  del contacto y evidencia de consentimiento.

## 4. Qué no se hizo

- No existen todavía `atribucion_enlaces` o `atribucion_clics_dia`.
- No existe redirector ni `go.magandhi.com`.
- No existe pantalla Promocionar.
- No se guarda el código en la tienda ni en pagos/pedidos.
- No hay metadata social por producto ni sitemap.
- No hay métricas P5.
- Este cambio no contiene migraciones, Edge Functions, configuración de DNS,
  interfaz o instrucciones de despliegue para P0.
- No se ejecutó una ventana productiva ni un diagnóstico remoto como parte de
  este cierre documental. El estado medido de Supabase, flags, Auth y Wompi
  sigue siendo el del relevo Comercial C5 hasta una medición posterior.

## 5. Riesgos que gobiernan lo siguiente

- P1 mantiene `noindex` hasta comprobar HTML sin JavaScript y publicar políticas.
- P3 debe impedir open redirects, códigos secuenciales/reutilizados y conteo de
  previews como personas.
- P4 no puede confiar en UTM o FK enviadas por el navegador y no puede bloquear
  una compra si falla la atribución.
- Los plazos y excepciones deben quedar reflejados en las políticas revisadas
  antes de activar captura promocional.
- C5 sigue sin cierre monetario por carrito; dinero solo con autorización.

## 6. Prompt para continuar

> Retomamos MAGANDHI después del cierre documental de **Promocionar P0**. Lee
> `docs/PLANO-PROMOCIONAR-P0.md`, después `docs/PLANO-FASE-COMERCIAL.md` §4 y
> `CONTEXTO-MAGANDHI.md` §9. P0 es solo contrato: el cambio no contiene tablas,
> Edge, DNS, UI, captura o instrucciones de despliegue. No hubo diagnóstico
> remoto P0; el estado productivo medido sigue gobernado por el relevo C5. Las
> políticas siguen en borrador. La siguiente etapa es
> **P1 · Producto compartible**: URL canónica `/producto/<slug>/`, HTML inicial,
> title/description/canonical, Open Graph, Twitter Card, JSON-LD, imagen social,
> sitemap y compatibilidad con la ficha dinámica. Mantener `noindex` hasta
> verificar el HTML sin JavaScript y publicar políticas. No mezclar P1 con el
> redirector P3, atribución P4 o métricas P5. No tocar producción sin
> confirmación y no ejecutar pagos reales.
