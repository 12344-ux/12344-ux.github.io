# Categorías de temporada MAGANDHI · CT1

## Estado

**Implementada en código; pendiente de aplicar la migración, publicar ambos repositorios y asociar productos.**

- Forward: `supabase/migrations/20261114000000_campanas_categorias_temporada.sql`.
- Consola: `marketing/campanas/categorias.html`.
- Tienda: carril de categorías del home alimentado por `categorias_publicas`.
- Primera temporada: `Navidad`, visible del 22-oct-2026 al 7-ene-2027, fechas civiles Colombia, fijada primera mientras esté vigente.

## Decisiones permanentes

1. Las categorías permanentes conservan orden editorial estable; no se personalizan ni reordenan por persona.
2. Una categoría de temporada siempre es secundaria. Nunca puede ser principal.
3. Todo producto conserva una principal permanente: Belleza, Hogar, Juguetería, etc.
4. Finalizar una temporada oculta la categoría y su asociación pública; no despublica, desactiva ni elimina productos.
5. Las asociaciones internas se conservan para historia y reutilización.
6. `visible_tienda` es el gate manual; `visible_desde`/`visible_hasta` gobiernan la ventana automática en `America/Bogota`.
7. Una temporada fijada vigente antecede al orden editorial. El resto permanece estable.
8. No se modifica ranking, personalización, búsqueda, fallback ni telemetría de SN1.

## Operación

Desde **Marketing → Campañas → Gestionar categorías** se puede:

- crear permanentes o temporadas;
- editar nombre, descripción, icono y orden;
- programar fechas civiles Colombia;
- fijar una temporada primera;
- ocultar o desactivar con razón auditada;
- ver estados Permanente, Programada, Vigente, Finalizada, Oculta e Inactiva;
- consultar cuántas asociaciones principales y secundarias tiene.

En Agregar/Editar campaña, una temporada aparece con su estado y el rótulo “Solo secundaria”. El servidor vuelve a imponer esa regla aunque el navegador sea manipulado.

## Despliegue

1. Fusionar y publicar primero el repositorio `12344-ux.github.io`.
2. Aplicar una sola vez `20261114000000_campanas_categorias_temporada.sql` mediante SQL Editor; nunca `supabase db push`.
3. Ejecutar `supabase/operacion/categorias-temporada-postflight.sql` y verificar Navidad vigente, orden público `-2000000`, cero temporales principales y ACL exactas.
4. Verificar Navidad y la consola administrativa.
5. Asociar Navidad como secundaria a los productos elegidos, conservando su principal permanente.
6. Fusionar y publicar `magandhi`.
7. Confirmar que Navidad aparece primera en home y página de categorías.
8. Confirmar que una fecha fuera de ventana excluye la categoría sin sacar sus productos del catálogo.

## Reversa

Ante un problema visual, poner `visible_tienda=false` desde la consola. Esto retira la categoría pública sin tocar productos. No borrar asociaciones ni reejecutar migraciones; cualquier corrección SQL futura debe ser forward.
