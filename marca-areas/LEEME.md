# Logos por área — Back-office MAGANDHI

Esta carpeta guarda los íconos/logos que distinguen cada área interna de
montaguth.institute (control interno), conservando la identidad de marca
de MAGANDHI pero con una variación cromática por área.

## Favicons oficiales (SVG transparentes)

Los favicon oficiales del back-office ahora son **archivos SVG con fondo
transparente**, dibujados desde código (no imágenes con fondo blanco). Todos
comparten el mismo símbolo de MAGANDHI (el domo/templo) y solo cambia el color
del trazo por área:

- `control-interno.svg` → trazo **azul marino** `#1B2A47` (ícono GENERAL:
  login / entrada a montaguth.institute). Usado en `index.html` y `panel.html`.
- `finanzas.svg`        → trazo **verde** `#1F7A4D` (Área de Finanzas). Usado en
  todas las páginas de `finanzas/`.

Se enlazan así (con `type="image/svg+xml"` y cache-bust `?v=N`):

```html
<link rel="icon" type="image/svg+xml" href="marca-areas/control-interno.svg?v=2">
```

Cada **área futura** tendrá su propio color reutilizando el mismo domo: copia
uno de los SVG, cámbiale solo el atributo `stroke` y guárdalo como
`nombre-area.svg` (ej. `pedidos.svg`, `inventario.svg`).

## PNG antiguos

Los `control-interno.png` y `finanzas.png` (fondo blanco) se **conservan** en el
repo por si sirven para un logo grande, pero **ya no se usan como favicon**
porque su fondo blanco los hacía casi indistinguibles en la pestaña.

## Sube aquí tus archivos

Desde GitHub: **Add file → Upload files**, arrastra y **Commit**.
