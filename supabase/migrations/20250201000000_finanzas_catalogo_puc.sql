-- ============================================================
-- Magandhi Corporation · Modulo Finanzas · Catalogo PUC (tabla)
-- Plan Unico de Cuentas para comerciantes (Decreto 2650 de 1993).
-- Es el respaldo normativo de toda la contabilidad de partida doble
-- del back-office interno: cada linea de asiento referencia un codigo
-- de esta tabla, y la NATURALEZA (debito/credito) sale de aqui.
--
-- Jerarquia de 4 niveles (nivel):
--   1 = Clase     -> 1 digito   (ej. 1 Activo)
--   2 = Grupo     -> 2 digitos  (ej. 11 Disponible)
--   3 = Cuenta    -> 4 digitos  (ej. 1105 Caja)
--   4 = Subcuenta -> 6 digitos  (ej. 110505 Caja general)  [nivel de detalle]
--
-- REGLA DE NATURALEZA por clase (se codifica en los DATOS, columna
-- "naturaleza", y se hereda hacia abajo dentro de cada clase):
--   Clase 1 Activo ...................... debito
--   Clase 2 Pasivo ...................... credito
--   Clase 3 Patrimonio .................. credito
--   Clase 4 Ingresos .................... credito
--   Clase 5 Gastos ...................... debito
--   Clase 6 Costos de ventas ............ debito
--   Clase 7 Costos de produccion ........ debito
--   Clase 8 Cuentas de orden deudoras ... debito
--   Clase 9 Cuentas de orden acreedoras . credito
--
-- imputable: true SOLO en el nivel de detalle donde de verdad se
--   registran asientos (subcuenta de 6 digitos; o la cuenta de 4 digitos
--   cuando el PUC no baja mas). Clases, grupos y cuentas de agregacion
--   van imputable=false: son totalizadores, no reciben movimiento directo.
--
-- usos: contador de frecuencia de uso. El buscador de cuentas (FEAT-002)
--   ordena por "usos" descendente para poner arriba las cuentas que el
--   dueno mas registra. Se incrementa via la funcion security definer
--   incrementar_uso_cuenta(text) (ver 20250201000600_finanzas_funciones.sql),
--   NO abriendo UPDATE del catalogo.
--
-- SEGURIDAD:
--   - El candado real esta en RLS (ver 20250201000500_finanzas_rls.sql):
--     el catalogo solo lo leen usuarios con acceso al modulo finanzas
--     (tiene_modulo('finanzas')).
--   - Los montos NUNCA viven aqui; esta tabla es solo el catalogo. Los
--     montos (bigint, enteros de pesos COP) viven en asiento_lineas.
-- ============================================================

-- gen_random_uuid() lo trae Supabase de fabrica (extension pgcrypto ya
-- instalada). Se deja el create extension defensivo por si se aplica en
-- un proyecto Postgres limpio; en Supabase es idempotente y no molesta.
create extension if not exists pgcrypto;

create table if not exists puc_cuentas (
  codigo      text primary key,                 -- codigo PUC: '1', '11', '1105', '110505'
  nombre      text not null,
  nivel       smallint not null check (nivel between 1 and 4), -- 1 Clase, 2 Grupo, 3 Cuenta, 4 Subcuenta
  naturaleza  text not null check (naturaleza in ('debito','credito')),
  imputable   boolean not null default false,   -- true solo en el nivel de detalle
  padre       text references puc_cuentas(codigo), -- jerarquia (autoreferencia)
  usos        bigint not null default 0          -- contador de frecuencia para el buscador
);

comment on table puc_cuentas is 'Catalogo PUC (Decreto 2650) de 4 niveles. naturaleza por clase (1/5/6/7/8=debito, 2/3/4/9=credito). imputable=true solo en el nivel de detalle donde se registran asientos. usos = contador de frecuencia para priorizar el buscador (se incrementa via incrementar_uso_cuenta).';

comment on column puc_cuentas.nivel is '1=Clase(1 dig), 2=Grupo(2 dig), 3=Cuenta(4 dig), 4=Subcuenta(6 dig).';
comment on column puc_cuentas.naturaleza is 'debito o credito, segun la clase PUC. Determina el signo del saldo en saldos_cuenta.';
comment on column puc_cuentas.imputable is 'true solo en el nivel de detalle: solo estas cuentas pueden recibir lineas de asiento.';
comment on column puc_cuentas.usos is 'Contador de frecuencia de uso. El buscador prioriza las cuentas mas usadas. Se incrementa via incrementar_uso_cuenta(text).';

-- Indices de apoyo al buscador (codigo ya es PK; estos aceleran nombre y orden por uso).
create index if not exists idx_puc_cuentas_imputable on puc_cuentas (imputable);
create index if not exists idx_puc_cuentas_usos on puc_cuentas (usos desc);
create index if not exists idx_puc_cuentas_padre on puc_cuentas (padre);

-- RLS de esta tabla: ver 20250201000500_finanzas_rls.sql (SELECT solo con
-- tiene_modulo('finanzas')). Se habilita alli para mantener toda la
-- politica de acceso del modulo en un unico archivo.
