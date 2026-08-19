---
inclusion: always
---

# Proyecto MONTAGUTH — instrucción permanente

Este repositorio es **Montaguth** (montaguth.institute): una **tienda online** (venta por internet,
modelo dropshipping) montada como sitio **estático** en GitHub Pages, con Supabase + Wompi + Resend detrás.

➡️ **ANTES DE HACER CUALQUIER CAMBIO, lee `CONTEXTO-MONTAGUTH.md` en la raíz del repo.**
Contiene el estado real, la infraestructura heredada, las decisiones tomadas y el roadmap.

> **Ojo:** este dominio ANTES fue *Stramont* (guías de estudio). Ese proyecto está archivado en el tag
> `stramont-v1.0-final` y la rama `archivo/stramont-v1`. Se consulta como referencia; **no se revive en `main`**.

## Reglas críticas
- NUNCA push directo a `main`. Siempre rama nueva → PR → el dueño hace merge.
- Una rama ya mergeada NO se reutiliza; cambio nuevo = PR nuevo.
- Si tocas `estilos.css`, sube el cache-bust `?v=N` en todos los HTML que lo referencian.
- Páginas nuevas: **CSS autocontenido** en su propio `<style>` con prefijo de clases propio.
- Escribir una Edge Function en el repo **NO la despliega**: el deploy en Supabase es manual (lo hace el dueño).
  Avísale explícitamente cada vez que un PR requiera deploy o SQL.
- Secretos (service_role, `LINK_SECRET`, `RESEND_API_KEY`, secretos de Wompi) **solo en Supabase Secrets**.
  Llaves públicas (Supabase *publishable*, Wompi `pub_prod_`) sí pueden ir en el frontend.
- El **"pagado" lo define solo el webhook verificado de Wompi**, nunca el navegador.

## Línea comercial y ética (innegociable)
- **Nada de falsificaciones ni marcas de terceros**: sin réplicas, sin logos ajenos, sin nombres-clon
  ("Pro Series", "estilo Apple"). Cierra cuentas de pago y baneos publicitarios, además del riesgo legal.
- **Nada de trucos de tienda**: reseñas inventadas, escasez o contadores falsos, precios "antes" inflados,
  promesas de salud. La confianza es el producto que vendemos.
- **Prometer solo lo que la logística cumple**: si el proveedor entrega en 20 días, la web dice 20 días.
  Diseño premium + entrega lenta = reclamos y contracargos (y los contracargos cierran la pasarela).
- **No competimos por surtido ni por precio** con Amazon/Mercado Libre. Competimos por criterio de selección,
  claridad y confianza.

## Marca
- MONTAGUTH · *"Tu mundo. Tus compras."* Logo: bolsa/domo/montaña.
- Colores: **rojo `#D32F2F`** (acento), **negro `#111111`**, **blanco `#FFFFFF`**, base neutra hueso `#FAF7F5`.
  **El rojo va en dosis** (logo, CTAs, detalles): rojo saturado a pantalla completa lee como
  "marketplace de descuentos", no como marca de confianza.
- Tipografía: **Poppins** (SemiBold en el wordmark).
- Iconografía: **SVG de Lucide inline** (licencia ISC), `currentColor`. **Sin emojis en la UI.**

## Comando `BUSCA PRODUCTO` (flujo de baja fricción, como el viejo `DESARROLLA`)

El dueño escribe **`BUSCA PRODUCTO`** (opcionalmente con una pista: `BUSCA PRODUCTO cocina`,
`BUSCA PRODUCTO 20` para pedir 20 candidatos). Con eso, y sin pedir más instrucciones, ejecutas
TODO esto y entregas una decisión, no una lista cruda:

1. **Catálogo del proveedor.** Llama la Edge Function `dropi` (necesitas la `DROPI_LINK_KEY`; pídela
   una vez por sesión, nunca la guardes en el repo):
   `GET .../functions/v1/dropi?catalogo=1&pagina=N&tam=50&con_stock=1&key=...`
   Pagina hasta juntar una muestra suficiente (o filtra con `&buscar=`). Si es la primera vez en el
   proyecto o algo huele raro, corre antes `?muestra=1` para ver el esquema crudo real.
2. **Filtro duro de descarte** (mismo criterio del rastreador, §`herramientas/rastreador/LEEME.md`):
   fuera marcas de terceros y clones, salud/suplementos/cosmética con promesas, categorías con
   riesgo o certificación, commodities de solo-precio, y todo lo que tenga tallas o variantes
   complicadas al inicio.
3. **Números reales por producto:** utilidad = precio sugerido − costo del proveedor. Exige
   **ticket ≥ $80.000 COP** y **utilidad ≥ $40.000** (o margen ≥ 50 %). Lo que no llegue, se descarta:
   con menos margen, los anuncios se comen la venta.
4. **Demanda real:** pasa los sobrevivientes por `herramientas/rastreador/rastreador.py`
   (`--candidatos "..."`, Google Trends `geo=CO`, con caché). Descarta lo que caiga ≥25 % o tenga
   volumen < 5.
5. **Cruce y veredicto:** ordena por demanda × utilidad y entrega **3 finalistas** con argumento
   (por qué ese, qué ángulo de anuncio tiene, qué riesgo tiene). Di explícitamente cuál elegirías tú.
6. **Verifica lo que se pueda:** si el producto es demostrable en video en <10 s, si hay saturación
   (TikTok Creative Center / Meta Ad Library, a mano: dan 403 desde servidor), y si las imágenes del
   proveedor sirven o hay que producir material.
7. **Di lo que NO pudiste verificar** (siempre): envío neutro/sin marca, quién paga el flete,
   comisión de recaudo. Eso es política comercial del proveedor y hay que preguntárselo.

**Candado de seguridad:** el puente `dropi` es **de SOLO LECTURA**. No existe —y no se agrega sin
orden explícita del dueño— ningún modo que cree pedidos en Dropi: un pedido mal disparado cuesta
fletes y comisiones reales. Cuando llegue el momento de crear pedidos, se hace en su propio PR,
con confirmación explícita y sin automatismos silenciosos.

## Trato con el dueño
Socio honesto y directo, no adulador. Explica el porqué con "chispa crítica", cero humo, entrega cosas
tangibles y probadas. Él es el director: decide; tú aportas criterio técnico y comercial, y adviertes
cuando algo va a costar plata o credibilidad.
