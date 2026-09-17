-- ============================================================
-- Magandhi Corporation · Area Marketing · CAMPANAS · Catalogo de categorias (color)
-- ------------------------------------------------------------
-- QUE ES: catalogo CONTROLADO de categorias (patron puc_cuentas: codigo/nombre,
-- no texto libre), donde cada categoria trae su TERNA de color de marca. El
-- color de un producto es AUTOMATICO segun su categoria: NO se guarda color en
-- campana_producto, se deriva de aqui via la vista publica y el panel. Asi el
-- home se ve "coleccion curada" (misma familia calida) y nunca un arcoiris.
--
-- PALETA APROBADA POR EL DUENO (misma familia calida del home de la tienda). Se
-- guardan los tres tonos que el diseno usa por tarjeta:
--   color_fuerte  = --acento     (relleno principal)
--   color_claro   = --acento-cl  (borde/halo claro)
--   color_sombra  = --acento-sombra (sombra/fondo translucido, en rgba)
--
-- SEED idempotente (on conflict do update): re-ejecutar refresca los colores a
-- la paleta aprobada sin duplicar filas. El dueno puede AMPLIAR categorias como
-- amplia el PUC (agregando filas), respetando la familia de color.
--
-- IDEMPOTENTE: create table if not exists + on conflict do update + DO block
-- que consulta pg_constraint antes de agregar la FK (no falla al re-ejecutar).
-- REQUISITO: correr DESPUES de 20250501000000_campanas_producto.sql (la FK
-- referencia campana_producto.categoria_codigo).
-- ============================================================

-- ------------------------------------------------------------
-- campana_categoria: catalogo controlado (codigo pk) + terna de color de marca.
-- ------------------------------------------------------------
create table if not exists campana_categoria (
  codigo        text primary key,       -- ej. 'cabello', 'belleza_fem'
  nombre        text not null,          -- ej. 'Cuidado del cabello'
  color_fuerte  text not null,          -- --acento (hex), relleno principal
  color_claro   text not null,          -- --acento-cl (hex), borde/halo claro
  color_sombra  text not null,          -- --acento-sombra (rgba), sombra/fondo translucido
  orden         integer default 0       -- orden de presentacion en el panel
);

comment on table campana_categoria is 'CAMPANAS · catalogo controlado de categorias (patron puc_cuentas). Cada categoria trae su terna de color de marca (color_fuerte=--acento, color_claro=--acento-cl, color_sombra=--acento-sombra). El color del producto es AUTOMATICO segun su categoria: no se guarda color en campana_producto. El dueno amplia categorias como amplia el PUC.';
comment on column campana_categoria.color_fuerte is 'Tono --acento (hex): relleno principal del banner/tarjeta.';
comment on column campana_categoria.color_claro is 'Tono --acento-cl (hex): borde y halo claro.';
comment on column campana_categoria.color_sombra is 'Tono --acento-sombra (rgba): sombra suave y fondos translucidos.';

-- Semilla de la paleta EXACTA aprobada (misma que el home de la tienda).
insert into campana_categoria (codigo, nombre, color_fuerte, color_claro, color_sombra, orden) values
  ('cabello',      'Cuidado del cabello',        '#C9962E', '#E7C56B', 'rgba(201,150,46,.18)',  1),
  ('belleza_fem',  'Belleza femenina',           '#B5657A', '#D99FAE', 'rgba(181,101,122,.16)', 2),
  ('belleza_masc', 'Belleza masculina',          '#3A3A3A', '#7A7A7A', 'rgba(58,58,58,.14)',    3),
  ('cuidado_gral', 'Cuidado personal/general',   '#6E6A66', '#A8A29C', 'rgba(110,106,102,.15)', 4),
  ('hogar',        'Hogar/limpieza',             '#3E6B78', '#7FA6B0', 'rgba(62,107,120,.15)',  5),
  ('alimentos',    'Alimentos/naturales',        '#C0682E', '#E3A576', 'rgba(192,104,46,.16)',  6),
  ('destacado',    'Destacado/clasico',          '#B23A2E', '#D98A80', 'rgba(178,58,46,.15)',   7)
on conflict (codigo) do update
  set nombre       = excluded.nombre,
      color_fuerte = excluded.color_fuerte,
      color_claro  = excluded.color_claro,
      color_sombra = excluded.color_sombra,
      orden        = excluded.orden;

-- ------------------------------------------------------------
-- ENCENDER LA FK: campana_producto.categoria_codigo -> campana_categoria(codigo).
-- Guard idempotente: solo se agrega si no existe ya en pg_constraint, para no
-- fallar al re-ejecutar el archivo. Mismo patron que la FK del enchufe en
-- 20250401000300_ventas_rls.sql.
-- ------------------------------------------------------------
do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'campana_producto_categoria_codigo_fkey'
       and conrelid = 'campana_producto'::regclass
  ) then
    alter table campana_producto
      add constraint campana_producto_categoria_codigo_fkey
      foreign key (categoria_codigo) references campana_categoria(codigo);
  end if;
end
$$;
