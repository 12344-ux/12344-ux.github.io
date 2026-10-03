# Identidad por área · back-office MAGANDHI

Estos favicons distinguen superficies internas de `montaguth.institute`. No forman parte de la tienda pública y no modifican el logo comercial maestro.

## Archivos en uso

- `control-interno.png`: login y panel general, azul operativo.
- `finanzas.png`: Finanzas, verde funcional.
- `marketing.png`: Marketing, actualmente comparte el arte azul general.
- `produccion.png`: Producción/Inventarios, actualmente comparte el arte azul general.
- `ventas.png`: Ventas, actualmente comparte el arte azul general.

Marketing, Producción y Ventas son **copias temporales deliberadas**, no tres identidades terminadas. Evitan favicons rotos y mantienen una sola familia azul mientras se decide si cada área necesita un símbolo propio. No deben describirse como “oficiales distintos”.

## Jerarquía de marca

1. El logo maestro comercial vive en el repositorio público `magandhi`, en `marca/logo/logo-magandhi.svg`.
2. Login/panel usan derivados terracota sincronizados con ese maestro.
3. Las áreas internas aplican color funcional: azul operativo y verde para Finanzas.
4. No se introduce un color nuevo por área sin una decisión explícita del sistema interno.

## Actualización

Al reemplazar un favicon:

1. partir del logo/sistema oficial, no de un JPG antiguo;
2. exportar PNG cuadrado, transparente y por debajo de 2000px;
3. conservar el nombre estable del área;
4. incrementar `?v=N` en todas las páginas que lo usan;
5. verificar por DOM que ninguna ruta produzca 404.
