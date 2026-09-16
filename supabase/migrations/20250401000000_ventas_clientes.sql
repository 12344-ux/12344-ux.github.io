-- ============================================================
-- Magandhi Corporation · Area de Ventas · Tabla clientes (identidad del cliente)
-- ------------------------------------------------------------
-- POR QUE EXISTE ESTE ARCHIVO: clientes es la pieza que ENCIENDE el "enchufe
-- apagado" del libro de Inventario. El id de esta tabla ES el customer_id que
-- hoy vive nullable y SIN FK en movimientos_inventario (ver
-- 20250301000100_inventario_movimientos.sql, comentario de la columna). Al
-- crearse clientes, Ventas puede estampar quien compro en cada salida del libro
-- y Marketing/Cluster podran cruzar "que compro quien" (PLANO-VENTAS §1.1-§1.2).
--
-- QUE HACE: crea la tabla clientes con su identidad de contacto, los campos de
-- terreno geografico (fase futura, sin geocoding hoy), la baja logica (activo)
-- y la auditoria. Deja lista la red anti-duplicados por debajo del algoritmo de
-- coincidencia: indices UNIQUE PARCIALES sobre correo_norm y telefono_norm, mas
-- un indice de apoyo por nombre para la busqueda por senal debil (§1.3, §4).
--
-- PAR ORIGINAL / _norm (§1.3): por cada dato de contacto guardamos dos columnas.
--   - El ORIGINAL (correo, telefono) es lo que el cliente dicto/escribio y lo
--     que se ve bonito en la ficha; no se pierde informacion.
--   - El NORMALIZADO (correo_norm, telefono_norm) es la forma canonica que
--     compara el algoritmo de coincidencia (§4) y la que lleva el indice UNIQUE
--     como piso duro anti-duplicados. Dos formas distintas de escribir el mismo
--     contacto colapsan a la misma clave.
-- La normalizacion se hace SERVER-SIDE en la RPC (crear_pedido / edicion de
-- cliente), NO en el navegador (§1.4), para que la clave unica sea consistente
-- de verdad: si cada cliente normalizara distinto, el UNIQUE no protegeria nada.
--
-- UNICIDAD PARCIAL (where ... is not null): un cliente puede no tener correo o
-- no tener telefono. Si la unicidad fuera total, dos clientes sin correo
-- chocarian por tener ambos correo_norm = NULL. La parcialidad evita ese choque
-- y solo exige unicidad cuando el valor existe (§1.3).
--
-- SIN DELETE (regla del ecosistema): un cliente nunca se borra (rompe el
-- historial de pedidos); se inactiva con activo=false (§1.2).
--
-- IDEMPOTENTE: create table if not exists / create index if not exists. Se
-- puede re-ejecutar sin fallar ni duplicar.
-- ============================================================

-- ------------------------------------------------------------
-- clientes: la identidad del cliente. id = customer_id del ecosistema.
-- ------------------------------------------------------------
create table if not exists clientes (
  id            uuid primary key default gen_random_uuid(),
  nombre        text not null,
  correo        text,
  correo_norm   text,
  telefono      text,
  telefono_norm text,
  direccion     text,
  ciudad        text,
  departamento  text,
  pais          text default 'Colombia',
  lat           double precision,   -- terreno geo futuro (sin geocoding hoy)
  lng           double precision,   -- terreno geo futuro
  notas         text,
  activo        boolean not null default true,
  creado        timestamptz default now(),
  creado_por    uuid default auth.uid(),
  actualizado   timestamptz
);

comment on table clientes is 'Identidad del cliente del Area de Ventas. Su id ES el customer_id que enciende el enchufe apagado del libro de Inventario (movimientos_inventario.customer_id) y conecta pedidos, Marketing y el Cluster futuro. Nunca se borra: baja logica con activo=false. Escritura solo por RPC security definer.';
comment on column clientes.correo is 'Correo tal como lo dicto/escribio el cliente (lo que se ve en la ficha). Su forma canonica va en correo_norm.';
comment on column clientes.correo_norm is 'Correo NORMALIZADO server-side (trim + minusculas, §1.4). Senal FUERTE del algoritmo de coincidencia (§4) y clave del indice UNIQUE parcial (piso duro anti-duplicados). Unico cuando no es nulo.';
comment on column clientes.telefono is 'Telefono tal como se capturo (lo que se ve en la ficha). Su forma canonica va en telefono_norm.';
comment on column clientes.telefono_norm is 'Telefono NORMALIZADO server-side (solo digitos, sin +57/57 ni separadores, §1.4). Segunda senal FUERTE del algoritmo (§4) y clave del indice UNIQUE parcial. Unico cuando no es nulo.';
comment on column clientes.direccion is 'Direccion de entrega en texto libre (para quien prepara y entrega). Terreno para geolocalizacion futura.';
comment on column clientes.lat is 'Latitud. TERRENO geo futuro: no se llena en fase 1 (no hay geocoding ahora).';
comment on column clientes.lng is 'Longitud. TERRENO geo futuro: no se llena en fase 1 (no hay geocoding ahora).';
comment on column clientes.activo is 'Baja logica. Un cliente NUNCA se borra (rompe el historial de pedidos): se inactiva con activo=false.';

-- ------------------------------------------------------------
-- Indices UNICOS PARCIALES = red anti-duplicados (piso duro) por debajo del
-- algoritmo de coincidencia (§4.5: el UNIQUE manda; el puntaje solo recomienda).
-- Parciales (where ... is not null) para que los nulos no choquen entre si.
-- ------------------------------------------------------------
create unique index if not exists clientes_correo_norm_uidx
  on clientes (correo_norm) where correo_norm is not null;
create unique index if not exists clientes_telefono_norm_uidx
  on clientes (telefono_norm) where telefono_norm is not null;

-- Indice de apoyo para la busqueda por nombre (senal DEBIL del algoritmo, §4.1).
create index if not exists clientes_nombre_idx on clientes (lower(nombre));
