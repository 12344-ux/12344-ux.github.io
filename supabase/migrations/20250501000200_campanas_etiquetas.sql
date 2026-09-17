-- ============================================================
-- Magandhi Corporation · Area Marketing · CAMPANAS · Etiquetas de segmentacion (INTERNAS)
-- ------------------------------------------------------------
-- QUE ES: catalogo CONTROLADO de etiquetas de segmentacion INTERNAS (patron
-- puc_cuentas: codigo/nombre, NO texto libre) mas una tabla PUENTE que asigna
-- etiquetas a cada producto de campana. Son etiquetas de USO INTERNO del equipo
-- de Marketing (para agrupar el catalogo y alimentar el cluster/segmentacion
-- futura). Se usa catalogo controlado y no texto libre justamente para que ese
-- agrupamiento futuro sea consistente (dos personas no escriben "regalo" y
-- "regalos" y rompen el cluster).
--
-- LINEA ROJA DE SEGURIDAD: estas etiquetas NUNCA se exponen en la tienda
-- publica. La vista catalogo_publico (20250501000300) NO incluye la tabla
-- puente ni el catalogo de etiquetas. Son inteligencia interna del negocio.
--
-- NADA se borra: una etiqueta se desactiva (activo=false), no se elimina, para
-- no romper asignaciones historicas.
--
-- IDEMPOTENTE: create table if not exists + on conflict do nothing/update.
-- REQUISITO: correr DESPUES de 20250501000000_campanas_producto.sql (la tabla
-- puente referencia campana_producto).
-- ============================================================

-- ------------------------------------------------------------
-- campana_etiqueta: catalogo controlado de etiquetas de segmentacion internas.
-- ------------------------------------------------------------
create table if not exists campana_etiqueta (
  codigo      text primary key,     -- ej. 'uso_diario', 'origen_natural'
  nombre      text not null,        -- ej. 'Uso diario'
  descripcion text,                 -- para que se usa la etiqueta (guia del equipo)
  activo      boolean default true, -- baja logica: una etiqueta se desactiva, no se borra
  orden       integer default 0
);

comment on table campana_etiqueta is 'CAMPANAS · catalogo controlado de etiquetas de segmentacion INTERNAS (patron puc_cuentas, no texto libre). Uso interno de Marketing para agrupar el catalogo y alimentar la segmentacion/cluster futura. NUNCA se exponen en la tienda publica (no entran en catalogo_publico). El dueno las amplia como amplia el PUC.';
comment on column campana_etiqueta.activo is 'Baja logica: una etiqueta se desactiva (activo=false), nunca se borra, para no romper asignaciones historicas.';

-- ------------------------------------------------------------
-- campana_producto_etiqueta: tabla PUENTE producto <-> etiqueta (muchos a muchos).
-- La PK compuesta evita etiquetas duplicadas por producto.
-- ------------------------------------------------------------
create table if not exists campana_producto_etiqueta (
  campana_producto_id uuid references campana_producto(id),
  etiqueta_codigo     text references campana_etiqueta(codigo),
  primary key (campana_producto_id, etiqueta_codigo)
);

comment on table campana_producto_etiqueta is 'CAMPANAS · puente producto <-> etiqueta de segmentacion (muchos a muchos). Uso INTERNO. NUNCA se expone en la tienda publica: la vista catalogo_publico no la incluye. Las etiquetas de un producto se reemplazan en bloque desde las RPC cm_crear_campana / cm_editar_campana.';

-- Indice de apoyo para consultar por etiqueta (segmentacion inversa: que
-- productos llevan tal etiqueta).
create index if not exists campana_producto_etiqueta_etiqueta_idx
  on campana_producto_etiqueta (etiqueta_codigo);

-- ------------------------------------------------------------
-- SEED de un set inicial razonable de etiquetas de segmentacion, coherente con
-- los 5 productos del home. El dueno las AMPLIARA como amplia el PUC (agregando
-- filas). on conflict do update para refrescar nombre/descripcion sin duplicar.
-- ------------------------------------------------------------
insert into campana_etiqueta (codigo, nombre, descripcion, orden) values
  ('uso_diario',     'Uso diario',        'Producto pensado para uso cotidiano.',                     1),
  ('origen_natural', 'Origen natural',    'Ingredientes de origen botanico o natural.',               2),
  ('regalo',         'Ideal para regalo', 'Buen candidato para regalar (presentacion, precio).',      3),
  ('cuidado_facial', 'Cuidado facial',    'Rutina o cuidado del rostro.',                             4),
  ('cuidado_capilar','Cuidado capilar',   'Cuidado del cabello.',                                     5),
  ('barba',          'Barba',             'Cuidado y arreglo de la barba.',                           6),
  ('hogar',          'Hogar',             'Uso en el hogar / limpieza.',                              7),
  ('gama_alta',      'Gama alta',         'Producto de mayor valor percibido.',                       8),
  ('economico',      'Economico',         'Producto de precio accesible.',                            9)
on conflict (codigo) do update
  set nombre      = excluded.nombre,
      descripcion = excluded.descripcion,
      orden       = excluded.orden;

-- RLS de estas tablas: ver 20250501000400_campanas_rls.sql (SELECT solo con
-- tiene_acceso_marketing(); nada para anon; sin escritura directa).
