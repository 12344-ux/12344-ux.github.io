# Relevo de sesión · Cierre aprobado de Promocionar P2 · 20 de octubre de 2026

> **Relevo histórico, superado el 21-oct-2026.** Conserva sin reescribir la
> realidad observada al cerrar P2. El estado vigente de P3 está en
> `docs/RELEVO-PROMOCIONAR-P3-CIERRE-2026-10-21.md`.

**Punto de arranque que regía al cierre P2.** Leer primero este archivo;
después `docs/PLANO-PROMOCIONAR-P2.md`,
`docs/PLANO-PROMOCIONAR-P3.md` y el contrato normativo
`docs/PLANO-PROMOCIONAR-P0.md`. El relevo Comercial C5 continúa gobernando
carrito, Wompi y su cierre monetario pendiente.

## 1. Respuesta corta

- **Promocionar P0, P1 y P2 están cerrados.** P0 como contrato, P1 desplegado y
  cerrado estructuralmente, y P2 desplegado, cerrado y aprobado por el dueño el
  20-oct-2026.
- P2 recibió aprobación **visual/funcional**. No se ejecutó ni se atribuye una
  suite automatizada específica de P2.
- PR #298 y #299 están fusionados; el cierre publicado corresponde al merge
  `90efd87ae1be07493fdf38aad5e140be558d38ac`.
- GitHub Pages run `39471770742` terminó `completed/success`.
- Los cinco assets productivos P2 respondieron HTTP 200 y coincidieron
  exactamente, byte por byte, con el merge final.
- P2 fue solo frontend: no hubo SQL, migración, RPC, Edge Function, backend, DNS,
  captura de clics ni atribución.
- **Siguiente punto: P3 · Registro y enlace corto.** Su contrato está en
  construcción; P3 no está desplegado ni tiene relevo productivo.
- La decisión final del dueño conserva íntegros enlaces, clics aproximados,
  métricas, historial, filtros, antiabuso y retención P3. El redirect activo es
  inmediato y no usa cookies, perfil individual ni UI de aviso/consentimiento;
  la explicación posterior en la política general no bloquea su lanzamiento o
  activación.

## 2. Alcance cerrado

P2 entrega desde Campañas un estudio editorial MAGANDHI que:

- usa el canonical P1 y los siete pares `source/medium` definidos por P0;
- genera UTM descriptiva, nunca autoridad de atribución;
- permite copiar enlace/texto y usar Web Share cuando está disponible;
- edita en sesión imagen, pretítulo, título, descripción, CTA, mensaje y roles de
  color dentro de presets cerrados de marca;
- produce localmente QR y PNG de 1080×1080, 1080×1920 y 1200×628;
- bloquea exportación ante publicación/shell no confirmados, contraste inválido
  o desborde, sin inutilizar el enlace protegido;
- no guarda las piezas ni sus ediciones y no adelanta P3–P5.

## 3. Evidencia de cierre

| Evidencia | Resultado |
|---|---|
| PR #298 | Base funcional del Estudio Promocionar fusionada |
| PR #299 | Identidad MAGANDHI y editor creativo final fusionados |
| Merge final | `90efd87ae1be07493fdf38aad5e140be558d38ac` |
| Pages | Run `39471770742`, `completed/success` |
| Aprobación | Dueño, revisión visual/funcional, 20-oct-2026 |
| Assets | 5/5 HTTP 200 e igualdad exacta contra el merge final |

Comparación productiva exacta:

| Asset | Bytes | SHA-256 |
|---|---:|---|
| `marketing/campanas/promocionar.html` | 20.556 | `94d7d139143df9c7547b3293cc39346bc3f80c2f8a3046fc3da5448bb38942de` |
| `marketing/campanas/promocionar.css` | 26.510 | `5d090ff621a6638f04f4e198f4938589137af8b27db11456a1d05681c37b10ee` |
| `marketing/campanas/promocionar-core.js` | 12.015 | `b6e14546a0d2a35a9f03921ffee1e34854307f7ebbc3f77f13e02d2e2222b2a3` |
| `marketing/campanas/promocionar-render.js` | 14.545 | `0ff312607f24cb5549e318d33f1bd4cd3a22d3235173abba3bc7cf39958ad14f` |
| `marketing/campanas/promocionar.js` | 29.732 | `6102c964785f90ab77c516636bd63b94324ee4a2609d9e2a94a6f6cbcb27230f` |

La comparación demuestra integridad del despliegue de esos cinco archivos. El
run de Pages y HTTP 200 tampoco sustituyen pruebas de comportamiento.

## 4. Límites de la aprobación

La aprobación del dueño fue visual y funcional sobre el alcance P2. No quedó
registrado como ejecutado:

- un banco automatizado propio de P2;
- una auditoría formal de accesibilidad o protocolo separado de teclado/foco;
- un protocolo independiente de escaneo y zona silenciosa del QR;
- una matriz entre varios navegadores o dispositivos;
- pruebas de backend, redirect, conteo, atribución o métricas, porque pertenecen
  a P3–P5 y no existían en P2.

Los criterios del plano P2 están aceptados y marcados completos bajo ese tipo de
aprobación. Este relevo no convierte los límites anteriores en pruebas
retrospectivas.

## 5. Riesgos y deuda reconocida

1. **Sin tests P2 dedicados.** Una modificación futura del estudio necesita
   regresión explícita sobre canonical/UTM, gates, tres formatos, exportación y
   controles creativos; el cierre actual no aporta una suite reutilizable.
2. **Accesibilidad y QR sin protocolo archivado.** Teclado/foco y escaneo real
   merecen comprobaciones reproducibles si el estudio vuelve a cambiar.
3. **Publicación no equivale a comportamiento.** La igualdad 5/5 asegura qué
   bytes están en producción, no que todas las ramas interactivas se hayan
   recorrido.
4. **Edición efímera por diseño.** Imagen local, textos y ajustes no se
   persisten; recargar pierde la pieza. El registro comienza en P3 y debe
   respetar la retención de P0.
5. **Dependencia del shell P1.** Compartir/exportar conserva la confirmación
   humana de que el shell fue publicado; P2 no automatiza el despliegue de
   fichas.
6. **Políticas y gates separados.** `noindex,follow` y sitemap solo home
   conservan el gate propio de P1; EM6 y EM7 conservan sus gates de política y
   consentimiento. La política general sigue pendiente, pero ya no bloquea el
   lanzamiento, la activación, el redirect ni el conteo agregado de P3.
7. **P3 no existe en producción.** No hay backend, tablas, Edge redirectora,
   DNS/TLS de `go.magandhi.com`, contador ni feature gate P3 activado.

## 6. Siguiente punto · P3

Gobierna `docs/PLANO-PROMOCIONAR-P3.md`, en construcción. P3 debe implementar,
sin mezclar P4/P5:

- registro inmutable de enlaces y código Crockford de 16 caracteres/80 bits;
- `https://go.magandhi.com/<codigo>` mediante DNS, TLS y routing todavía
  pendientes;
- destino MAGANDHI resuelto server-side desde lista blanca;
- respuesta `302` con `Cache-Control: no-store`;
- redirección inmediata para todo enlace activo, sin cookies, perfil individual,
  banner, popup, modal, aviso intermedio ni solicitud de consentimiento al
  abrirlo; conteo, filtros y antiabuso nunca retrasan esa salida;
- ciclo `borrador -> activo -> desactivado`;
- clic diario aproximado por fecha de Colombia;
- cuota temporal inicial de 600 por hora, global por hash diario y sin vínculo
  con el enlace;
- retención y limpieza definidas por P0;
- explicación informativa posterior en la política general, fuera de los gates
  y criterios de activación P3; P4 y EM7 conservan sus gates propios;
- feature gates inicialmente OFF y activación solo con evidencia productiva.

P3 no congela atribución en intención/pedido —eso es P4— ni construye tableros o
conversión —eso es P5—. Código fusionado en Git no equivaldrá a SQL aplicado,
Edge desplegada, DNS configurado ni feature gate activo.

## 7. Arranque del próximo chat

> Retomamos MAGANDHI después del cierre aprobado de **Promocionar P2**. Leer
> `docs/RELEVO-PROMOCIONAR-P2-CIERRE-2026-10-20.md`,
> `docs/PLANO-PROMOCIONAR-P2.md`, `docs/PLANO-PROMOCIONAR-P3.md` y
> `docs/PLANO-PROMOCIONAR-P0.md`. P2 fue aprobado visual/funcionalmente; PR
> #298/#299, merge `90efd87`, Pages `39471770742` y comparación productiva exacta
> 5/5. No inventar tests P2. Siguiente tramo: P3, contrato en construcción y
> sin despliegue. Todos sus gates nacen OFF; la política general no es gate de
> lanzamiento o activación P3. Conservar enlaces, clics aproximados, métricas,
> historial, filtros, antiabuso y retención; el redirect activo es inmediato y
> no usa cookies, perfil individual ni UI de aviso/consentimiento. No afirmar
> backend o DNS por código en Git. No adelantar P4/P5 ni tocar dinero/Wompi.
