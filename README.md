# Montaguth

**Tienda online** — *Tu mundo. Tus compras.*
Sitio estático publicado con GitHub Pages en **montaguth.institute**.

Venta por internet (modelo dropshipping): seleccionamos productos, los explicamos sin exagerar
y los entregamos con reglas claras — plazos reales, seguimiento y devoluciones sin peleas.

## Estado

En construcción. La portada actual es provisional (marca + lista de espera de apertura).

## Estructura

- `index.html` — portada provisional (autocontenida).
- `checkout.html` — motor de pago con Wompi (heredado; pendiente de reescribir para carrito).
- `informe.html` — tablero interno de gestión (requiere `LINK_SECRET`; no enlazado, `noindex`).
- `privacidad.html`, `condiciones.html` — legales (pendientes de reescribir para tienda).
- `por-que-wompi.html` — página de confianza sobre la pasarela de pago.
- `pago-estado.html` — página de retorno de Wompi.
- `estilos.css` — shell global heredado.
- `supabase/` — Edge Functions y migraciones SQL (pagos, correos, tablero, captura de correos).
- `ads/` — pipeline de producción de video para anuncios.

## Documentación interna

- `CONTEXTO-MONTAGUTH.md` — estado, decisiones y roadmap (leer primero).
- `.kiro/steering/montaguth.md` — reglas permanentes del proyecto.
- `.kiro/steering/anuncios.md` — receta técnica de producción de video.

## Historial

Este dominio alojó antes **Stramont**, un proyecto de guías de estudio interactivas.
Está archivado y es recuperable en el tag `stramont-v1.0-final` y la rama `archivo/stramont-v1`.
