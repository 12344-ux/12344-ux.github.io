-- ============================================================
-- Magandhi Corporation · Modulo Finanzas · Asientos (partida doble)
-- El Libro Diario: cada asiento es un hecho economico (una compra, una
-- venta, un pago...) compuesto por 2 o mas lineas que se reparten entre
-- DEBE y HABER. La contabilidad es MANUAL: el dueno (o el trabajador de
-- finanzas) escribe el asiento; el sistema solo valida y automatiza.
--
-- DECISION DE MONTOS (no negociable): los montos van en BIGINT, como
-- ENTEROS DE PESOS COLOMBIANOS (COP), SIN centavos. Colombia no maneja
-- fracciones de peso en la practica contable de un comercio, y usar
-- enteros elimina de raiz los errores de redondeo del punto flotante
-- (0.1 + 0.2 != 0.3). NUNCA usar numeric/float/real/double para montos.
-- Si en el futuro se necesitara mas granularidad, se migraria a
-- "centavos como entero" (multiplicar por 100), nunca a flotante.
--
-- REGLA DE ORO (partida doble): un asiento activo SOLO es valido si
-- sum(debe) = sum(haber) y tiene al menos 2 lineas. Se valida EN VIVO en
-- el cliente (FEAT-002) y se REFUERZA server-side (ver
-- 20250201000600_finanzas_funciones.sql). El cliente es comodidad de UX;
-- el candado real es server-side + RLS.
--
-- CORRECCIONES (modelo "punto medio"): los asientos se pueden EDITAR o
-- ANULAR (estado='anulado'), pero NADA se borra en silencio: cada cambio
-- queda en asiento_bitacora (ver 20250201000400_finanzas_trazabilidad.sql).
-- No hay borrado fisico para usuarios (sin policy de DELETE, ver RLS).
--
-- SEGURIDAD: RLS de estas tablas en 20250201000500_finanzas_rls.sql,
-- apoyada en tiene_modulo('finanzas'). Los asientos son datos sensibles.
-- ============================================================

create extension if not exists pgcrypto; -- gen_random_uuid (idempotente; Supabase ya lo trae)

-- ------------------------------------------------------------
-- Cabecera del asiento (Libro Diario).
-- ------------------------------------------------------------
create table if not exists asientos (
  id           uuid primary key default gen_random_uuid(),
  fecha        date not null,
  descripcion  text not null,
  estado       text not null default 'activo' check (estado in ('activo','anulado')),
  creado_por   uuid references auth.users(id) default auth.uid(),
  creado       timestamptz not null default now(),
  actualizado  timestamptz
);

comment on table asientos is 'Cabecera de cada asiento del Libro Diario. estado activo/anulado (nunca se borra fisicamente; las correcciones quedan en asiento_bitacora). Montos NO viven aqui: van en asiento_lineas como bigint (enteros de pesos COP).';
comment on column asientos.estado is 'activo o anulado. Solo los activos cuentan para el mayor y los saldos. Anular es la via de correccion, no el DELETE.';
comment on column asientos.creado_por is 'auth.uid() del usuario del modulo finanzas que registro el asiento.';

create index if not exists idx_asientos_fecha on asientos (fecha);
create index if not exists idx_asientos_estado on asientos (estado);

-- ------------------------------------------------------------
-- Lineas del asiento. Cada linea es DEBE o HABER (nunca ambas ni ninguna).
-- Montos en BIGINT (enteros de pesos COP). >= 0 por check.
-- ------------------------------------------------------------
create table if not exists asiento_lineas (
  id            uuid primary key default gen_random_uuid(),
  asiento_id    uuid not null references asientos(id) on delete cascade,
  cuenta_codigo text not null references puc_cuentas(codigo),
  detalle       text,
  debe          bigint not null default 0 check (debe >= 0),
  haber         bigint not null default 0 check (haber >= 0),
  orden         int,
  -- Cada linea es exclusivamente DEBE o HABER: exactamente uno > 0.
  -- (debe > 0) <> (haber > 0)  =>  XOR: uno positivo y el otro cero.
  constraint linea_debe_o_haber check ((debe > 0) <> (haber > 0))
);

comment on table asiento_lineas is 'Lineas de cada asiento. debe/haber en BIGINT (enteros de pesos COP, sin centavos; nunca float). Cada linea es DEBE o HABER exclusivamente (check linea_debe_o_haber). cuenta_codigo referencia el PUC y debe ser imputable (se refuerza en guardar_asiento).';
comment on column asiento_lineas.debe is 'Monto al DEBE en pesos enteros (bigint). Terracota en la UI. 0 si la linea es al haber.';
comment on column asiento_lineas.haber is 'Monto al HABER en pesos enteros (bigint). Azul marino en la UI. 0 si la linea es al debe.';
comment on constraint linea_debe_o_haber on asiento_lineas is 'XOR: exactamente uno de debe/haber es > 0. Impide lineas mixtas o vacias.';

create index if not exists idx_asiento_lineas_asiento on asiento_lineas (asiento_id);
create index if not exists idx_asiento_lineas_cuenta on asiento_lineas (cuenta_codigo);

-- Nota: la validacion de CUADRE (sum(debe)=sum(haber)) y de "al menos 2
-- lineas" e "imputable=true" NO se puede hacer con un simple CHECK de fila
-- (necesita ver todas las lineas del asiento). Se refuerza server-side en
-- la funcion RPC guardar_asiento(...) (20250201000600_finanzas_funciones.sql),
-- que valida y hace todos los INSERT dentro de una unica transaccion.
