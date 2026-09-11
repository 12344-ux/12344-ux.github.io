-- ============================================================
-- Magandhi Corporation · Modulo Finanzas · Carga del catalogo PUC
-- Datos REALES del Plan Unico de Cuentas para comerciantes
-- (Decreto 2650 de 1993 y sus modificaciones). NINGUN codigo aqui es
-- inventado: son los codigos oficiales del PUC.
--
-- ALCANCE DE ESTA CARGA (importante, no es el PUC completo de ~800 filas):
--   * TODAS las 9 clases (1 digito).
--   * TODOS los grupos reales (2 digitos) de las clases que un comercio
--     usa (1,2,3,4,5,6) y los grupos de las cuentas de orden (8,9).
--   * Las CUENTAS (4 dig) y SUBCUENTAS (6 dig) que un comercio como
--     MAGANDHI usa de verdad (caja, bancos, clientes, mercancias, IVA,
--     retenciones, proveedores, patrimonio, ingresos por venta, gastos
--     de administracion y de ventas, costo de ventas, etc.).
--
--   NO se cargan las ~800 cuentas completas del decreto. El modelo NO
--   depende de que esten todas: se pueden anadir mas en cualquier momento
--   con la PLANTILLA DE INSERT del final de este archivo (y esta anotado
--   en supabase/INSTRUCCIONES.md, seccion Finanzas > "catalogo parcial").
--   El buscador y los asientos funcionan con lo que haya cargado.
--
-- ORDEN DE INSERCION: primero clases (nivel 1), luego grupos (nivel 2),
--   luego cuentas (nivel 3), luego subcuentas (nivel 4), para respetar la
--   FK "padre". naturaleza segun la clase; imputable=true solo en el
--   nivel de detalle (subcuentas 6 dig aqui cargadas).
--
-- Idempotente: on conflict (codigo) do update, para re-ejecutar sin duplicar.
-- ============================================================

-- ------------------------------------------------------------
-- NIVEL 1 · CLASES (1 digito). naturaleza define el signo de toda la clase.
-- ------------------------------------------------------------
insert into puc_cuentas (codigo, nombre, nivel, naturaleza, imputable, padre) values
  ('1', 'ACTIVO',                     1, 'debito',  false, null),
  ('2', 'PASIVO',                     1, 'credito', false, null),
  ('3', 'PATRIMONIO',                 1, 'credito', false, null),
  ('4', 'INGRESOS',                   1, 'credito', false, null),
  ('5', 'GASTOS',                     1, 'debito',  false, null),
  ('6', 'COSTOS DE VENTAS',           1, 'debito',  false, null),
  ('7', 'COSTOS DE PRODUCCION O DE OPERACION', 1, 'debito', false, null),
  ('8', 'CUENTAS DE ORDEN DEUDORAS',  1, 'debito',  false, null),
  ('9', 'CUENTAS DE ORDEN ACREEDORAS',1, 'credito', false, null)
on conflict (codigo) do update set nombre=excluded.nombre, nivel=excluded.nivel, naturaleza=excluded.naturaleza, imputable=excluded.imputable, padre=excluded.padre;

-- ------------------------------------------------------------
-- NIVEL 2 · GRUPOS (2 digitos). Heredan la naturaleza de su clase.
-- ------------------------------------------------------------
insert into puc_cuentas (codigo, nombre, nivel, naturaleza, imputable, padre) values
  -- Clase 1 · ACTIVO (debito)
  ('11', 'DISPONIBLE',                                  2, 'debito',  false, '1'),
  ('12', 'INVERSIONES',                                 2, 'debito',  false, '1'),
  ('13', 'DEUDORES',                                    2, 'debito',  false, '1'),
  ('14', 'INVENTARIOS',                                 2, 'debito',  false, '1'),
  ('15', 'PROPIEDADES PLANTA Y EQUIPO',                 2, 'debito',  false, '1'),
  ('16', 'INTANGIBLES',                                 2, 'debito',  false, '1'),
  ('17', 'DIFERIDOS',                                   2, 'debito',  false, '1'),
  ('18', 'OTROS ACTIVOS',                               2, 'debito',  false, '1'),
  ('19', 'VALORIZACIONES',                              2, 'debito',  false, '1'),
  -- Clase 2 · PASIVO (credito)
  ('21', 'OBLIGACIONES FINANCIERAS',                    2, 'credito', false, '2'),
  ('22', 'PROVEEDORES',                                 2, 'credito', false, '2'),
  ('23', 'CUENTAS POR PAGAR',                           2, 'credito', false, '2'),
  ('24', 'IMPUESTOS GRAVAMENES Y TASAS',                2, 'credito', false, '2'),
  ('25', 'OBLIGACIONES LABORALES',                      2, 'credito', false, '2'),
  ('26', 'PASIVOS ESTIMADOS Y PROVISIONES',             2, 'credito', false, '2'),
  ('27', 'DIFERIDOS',                                   2, 'credito', false, '2'),
  ('28', 'OTROS PASIVOS',                               2, 'credito', false, '2'),
  ('29', 'BONOS Y PAPELES COMERCIALES',                 2, 'credito', false, '2'),
  -- Clase 3 · PATRIMONIO (credito)
  ('31', 'CAPITAL SOCIAL',                              2, 'credito', false, '3'),
  ('32', 'SUPERAVIT DE CAPITAL',                        2, 'credito', false, '3'),
  ('33', 'RESERVAS',                                    2, 'credito', false, '3'),
  ('34', 'REVALORIZACION DEL PATRIMONIO',               2, 'credito', false, '3'),
  ('36', 'RESULTADOS DEL EJERCICIO',                    2, 'credito', false, '3'),
  ('37', 'RESULTADOS DE EJERCICIOS ANTERIORES',         2, 'credito', false, '3'),
  ('38', 'SUPERAVIT POR VALORIZACIONES',                2, 'credito', false, '3'),
  -- Clase 4 · INGRESOS (credito)
  ('41', 'OPERACIONALES',                               2, 'credito', false, '4'),
  ('42', 'NO OPERACIONALES',                            2, 'credito', false, '4'),
  ('47', 'AJUSTES POR INFLACION',                       2, 'credito', false, '4'),
  -- Clase 5 · GASTOS (debito)
  ('51', 'OPERACIONALES DE ADMINISTRACION',             2, 'debito',  false, '5'),
  ('52', 'OPERACIONALES DE VENTAS',                     2, 'debito',  false, '5'),
  ('53', 'NO OPERACIONALES',                            2, 'debito',  false, '5'),
  ('54', 'IMPUESTO DE RENTA Y COMPLEMENTARIOS',         2, 'debito',  false, '5'),
  ('59', 'GANANCIAS Y PERDIDAS',                        2, 'debito',  false, '5'),
  -- Clase 6 · COSTOS DE VENTAS (debito)
  ('61', 'COSTO DE VENTAS Y DE PRESTACION DE SERVICIOS',2, 'debito',  false, '6'),
  ('62', 'COMPRAS',                                     2, 'debito',  false, '6'),
  -- Clase 7 · COSTOS DE PRODUCCION O DE OPERACION (debito)
  ('71', 'MATERIA PRIMA',                               2, 'debito',  false, '7'),
  ('72', 'MANO DE OBRA DIRECTA',                        2, 'debito',  false, '7'),
  ('73', 'COSTOS INDIRECTOS',                           2, 'debito',  false, '7'),
  ('74', 'CONTRATOS DE SERVICIOS',                      2, 'debito',  false, '7'),
  -- Clase 8 · CUENTAS DE ORDEN DEUDORAS (debito)
  ('81', 'DERECHOS CONTINGENTES',                       2, 'debito',  false, '8'),
  ('82', 'DEUDORAS FISCALES',                           2, 'debito',  false, '8'),
  ('83', 'DEUDORAS DE CONTROL',                         2, 'debito',  false, '8'),
  ('84', 'DERECHOS CONTINGENTES POR CONTRA (CR)',       2, 'debito',  false, '8'),
  ('85', 'DEUDORAS FISCALES POR CONTRA (CR)',           2, 'debito',  false, '8'),
  ('86', 'DEUDORAS DE CONTROL POR CONTRA (CR)',         2, 'debito',  false, '8'),
  -- Clase 9 · CUENTAS DE ORDEN ACREEDORAS (credito)
  ('91', 'RESPONSABILIDADES CONTINGENTES',              2, 'credito', false, '9'),
  ('92', 'ACREEDORAS FISCALES',                         2, 'credito', false, '9'),
  ('93', 'ACREEDORAS DE CONTROL',                       2, 'credito', false, '9'),
  ('94', 'RESPONSABILIDADES CONTINGENTES POR CONTRA (DB)',2,'credito',false, '9'),
  ('95', 'ACREEDORAS FISCALES POR CONTRA (DB)',         2, 'credito', false, '9'),
  ('96', 'ACREEDORAS DE CONTROL POR CONTRA (DB)',       2, 'credito', false, '9')
on conflict (codigo) do update set nombre=excluded.nombre, nivel=excluded.nivel, naturaleza=excluded.naturaleza, imputable=excluded.imputable, padre=excluded.padre;

-- ------------------------------------------------------------
-- NIVEL 3 · CUENTAS (4 digitos) que usa un comercio. imputable=false
-- (el detalle imputable esta en las subcuentas de 6 dig, salvo cuando el
-- PUC no baje mas). naturaleza heredada de la clase.
-- ------------------------------------------------------------
insert into puc_cuentas (codigo, nombre, nivel, naturaleza, imputable, padre) values
  -- 11 DISPONIBLE
  ('1105', 'CAJA',                                      3, 'debito',  false, '11'),
  ('1110', 'BANCOS',                                    3, 'debito',  false, '11'),
  ('1120', 'CUENTAS DE AHORRO',                         3, 'debito',  false, '11'),
  -- 12 INVERSIONES
  ('1225', 'CERTIFICADOS',                              3, 'debito',  false, '12'),
  -- 13 DEUDORES
  ('1305', 'CLIENTES',                                  3, 'debito',  false, '13'),
  ('1330', 'ANTICIPOS Y AVANCES',                       3, 'debito',  false, '13'),
  ('1355', 'ANTICIPO DE IMPUESTOS Y CONTRIBUCIONES O SALDOS A FAVOR', 3, 'debito', false, '13'),
  ('1365', 'CUENTAS POR COBRAR A TRABAJADORES',         3, 'debito',  false, '13'),
  ('1380', 'DEUDORES VARIOS',                           3, 'debito',  false, '13'),
  -- 14 INVENTARIOS
  ('1435', 'MERCANCIAS NO FABRICADAS POR LA EMPRESA',   3, 'debito',  false, '14'),
  -- 15 PROPIEDADES PLANTA Y EQUIPO
  ('1524', 'EQUIPO DE OFICINA',                         3, 'debito',  false, '15'),
  ('1528', 'EQUIPO DE COMPUTACION Y COMUNICACION',      3, 'debito',  false, '15'),
  ('1592', 'DEPRECIACION ACUMULADA',                    3, 'credito', false, '15'), -- naturaleza credito: cuenta correctora del activo
  -- 21 OBLIGACIONES FINANCIERAS
  ('2105', 'BANCOS NACIONALES',                         3, 'credito', false, '21'),
  -- 22 PROVEEDORES
  ('2205', 'PROVEEDORES NACIONALES',                    3, 'credito', false, '22'),
  -- 23 CUENTAS POR PAGAR
  ('2335', 'COSTOS Y GASTOS POR PAGAR',                 3, 'credito', false, '23'),
  ('2365', 'RETENCION EN LA FUENTE',                    3, 'credito', false, '23'),
  ('2367', 'IMPUESTO A LAS VENTAS RETENIDO',            3, 'credito', false, '23'),
  ('2368', 'IMPUESTO DE INDUSTRIA Y COMERCIO RETENIDO', 3, 'credito', false, '23'),
  ('2370', 'RETENCIONES Y APORTES DE NOMINA',           3, 'credito', false, '23'),
  ('2380', 'ACREEDORES VARIOS',                         3, 'credito', false, '23'),
  -- 24 IMPUESTOS GRAVAMENES Y TASAS
  ('2404', 'DE RENTA Y COMPLEMENTARIOS',                3, 'credito', false, '24'),
  ('2408', 'IMPUESTO SOBRE LAS VENTAS POR PAGAR',       3, 'credito', false, '24'),
  ('2412', 'DE INDUSTRIA Y COMERCIO',                   3, 'credito', false, '24'),
  -- 25 OBLIGACIONES LABORALES
  ('2505', 'SALARIOS POR PAGAR',                        3, 'credito', false, '25'),
  ('2510', 'CESANTIAS CONSOLIDADAS',                    3, 'credito', false, '25'),
  ('2515', 'INTERESES SOBRE CESANTIAS',                 3, 'credito', false, '25'),
  ('2525', 'VACACIONES CONSOLIDADAS',                   3, 'credito', false, '25'),
  -- 31 CAPITAL SOCIAL
  ('3105', 'CAPITAL SUSCRITO Y PAGADO',                 3, 'credito', false, '31'),
  ('3115', 'APORTES SOCIALES',                          3, 'credito', false, '31'),
  -- 33 RESERVAS
  ('3305', 'RESERVAS OBLIGATORIAS',                     3, 'credito', false, '33'),
  -- 36 RESULTADOS DEL EJERCICIO
  ('3605', 'UTILIDAD DEL EJERCICIO',                    3, 'credito', false, '36'),
  ('3610', 'PERDIDA DEL EJERCICIO',                     3, 'debito',  false, '36'), -- perdida: saldo debito
  -- 37 RESULTADOS DE EJERCICIOS ANTERIORES
  ('3705', 'UTILIDADES ACUMULADAS',                     3, 'credito', false, '37'),
  ('3710', 'PERDIDAS ACUMULADAS',                       3, 'debito',  false, '37'),
  -- 41 INGRESOS OPERACIONALES
  ('4135', 'COMERCIO AL POR MAYOR Y AL POR MENOR',      3, 'credito', false, '41'),
  ('4175', 'DEVOLUCIONES EN VENTAS (DB)',               3, 'debito',  false, '41'), -- devoluciones: saldo debito
  -- 42 INGRESOS NO OPERACIONALES
  ('4210', 'FINANCIEROS',                               3, 'credito', false, '42'),
  ('4295', 'DIVERSOS',                                  3, 'credito', false, '42'),
  -- 51 GASTOS OPERACIONALES DE ADMINISTRACION
  ('5105', 'GASTOS DE PERSONAL',                        3, 'debito',  false, '51'),
  ('5110', 'HONORARIOS',                                3, 'debito',  false, '51'),
  ('5115', 'IMPUESTOS',                                 3, 'debito',  false, '51'),
  ('5120', 'ARRENDAMIENTOS',                            3, 'debito',  false, '51'),
  ('5135', 'SERVICIOS',                                 3, 'debito',  false, '51'),
  ('5140', 'GASTOS LEGALES',                            3, 'debito',  false, '51'),
  ('5145', 'MANTENIMIENTO Y REPARACIONES',              3, 'debito',  false, '51'),
  ('5195', 'DIVERSOS',                                  3, 'debito',  false, '51'),
  ('5199', 'PROVISIONES',                               3, 'debito',  false, '51'),
  -- 52 GASTOS OPERACIONALES DE VENTAS
  ('5205', 'GASTOS DE PERSONAL',                        3, 'debito',  false, '52'),
  ('5235', 'SERVICIOS',                                 3, 'debito',  false, '52'),
  ('5240', 'GASTOS LEGALES',                            3, 'debito',  false, '52'),
  ('5245', 'GASTOS DE VENTA (PUBLICIDAD Y PROPAGANDA)', 3, 'debito',  false, '52'),
  ('5295', 'DIVERSOS',                                  3, 'debito',  false, '52'),
  -- 53 GASTOS NO OPERACIONALES
  ('5305', 'FINANCIEROS',                               3, 'debito',  false, '53'),
  ('5395', 'GASTOS DIVERSOS',                           3, 'debito',  false, '53'),
  -- 61 COSTO DE VENTAS
  ('6135', 'COMERCIO AL POR MAYOR Y AL POR MENOR',      3, 'debito',  false, '61'),
  -- 62 COMPRAS
  ('6205', 'DE MERCANCIAS',                             3, 'debito',  false, '62')
on conflict (codigo) do update set nombre=excluded.nombre, nivel=excluded.nivel, naturaleza=excluded.naturaleza, imputable=excluded.imputable, padre=excluded.padre;

-- ------------------------------------------------------------
-- NIVEL 4 · SUBCUENTAS (6 digitos). imputable=true: es el nivel de
-- detalle donde se registran los asientos. naturaleza heredada.
-- Cuentas correctoras (deprecacion, devoluciones, perdidas) llevan la
-- naturaleza contraria a su clase, igual que su cuenta de 4 digitos.
-- ------------------------------------------------------------
insert into puc_cuentas (codigo, nombre, nivel, naturaleza, imputable, padre) values
  -- 1105 CAJA
  ('110505', 'CAJA GENERAL',                            4, 'debito',  true, '1105'),
  ('110510', 'CAJAS MENORES',                           4, 'debito',  true, '1105'),
  -- 1110 BANCOS
  ('111005', 'MONEDA NACIONAL',                         4, 'debito',  true, '1110'),
  ('111010', 'MONEDA EXTRANJERA',                       4, 'debito',  true, '1110'),
  -- 1120 CUENTAS DE AHORRO
  ('112005', 'BANCOS',                                  4, 'debito',  true, '1120'),
  -- 1305 CLIENTES
  ('130505', 'CLIENTES NACIONALES',                     4, 'debito',  true, '1305'),
  -- 1355 ANTICIPO DE IMPUESTOS
  ('135515', 'RETENCION EN LA FUENTE',                  4, 'debito',  true, '1355'),
  ('135517', 'IMPUESTO A LAS VENTAS RETENIDO',          4, 'debito',  true, '1355'),
  ('135518', 'IMPUESTO SOBRE LAS VENTAS DESCONTABLE (IVA DESCONTABLE)', 4, 'debito', true, '1355'),
  -- 1435 MERCANCIAS NO FABRICADAS POR LA EMPRESA
  ('143505', 'MERCANCIAS NO FABRICADAS POR LA EMPRESA', 4, 'debito',  true, '1435'),
  -- 1524 EQUIPO DE OFICINA
  ('152405', 'MUEBLES Y ENSERES',                       4, 'debito',  true, '1524'),
  -- 1528 EQUIPO DE COMPUTACION Y COMUNICACION
  ('152805', 'EQUIPOS DE PROCESAMIENTO DE DATOS',       4, 'debito',  true, '1528'),
  -- 2205 PROVEEDORES NACIONALES
  ('220505', 'PROVEEDORES NACIONALES',                  4, 'credito', true, '2205'),
  -- 2335 COSTOS Y GASTOS POR PAGAR
  ('233525', 'HONORARIOS',                              4, 'credito', true, '2335'),
  ('233540', 'ARRENDAMIENTOS',                          4, 'credito', true, '2335'),
  ('233595', 'OTROS COSTOS Y GASTOS POR PAGAR',         4, 'credito', true, '2335'),
  -- 2365 RETENCION EN LA FUENTE
  ('236505', 'SALARIOS Y PAGOS LABORALES',              4, 'credito', true, '2365'),
  ('236515', 'HONORARIOS',                              4, 'credito', true, '2365'),
  ('236520', 'COMISIONES',                              4, 'credito', true, '2365'),
  ('236525', 'SERVICIOS',                               4, 'credito', true, '2365'),
  ('236530', 'ARRENDAMIENTOS',                          4, 'credito', true, '2365'),
  ('236540', 'COMPRAS',                                 4, 'credito', true, '2365'),
  -- 2367 IMPUESTO A LAS VENTAS RETENIDO
  ('236701', 'RETENCION DE IVA (REGIMEN COMUN)',        4, 'credito', true, '2367'),
  -- 2368 IMPUESTO DE INDUSTRIA Y COMERCIO RETENIDO
  ('236805', 'IMPUESTO DE INDUSTRIA Y COMERCIO RETENIDO', 4, 'credito', true, '2368'),
  -- 2370 RETENCIONES Y APORTES DE NOMINA
  ('237005', 'APORTES A ENTIDADES PROMOTORAS DE SALUD (EPS)', 4, 'credito', true, '2370'),
  ('237006', 'APORTES A FONDOS DE PENSIONES',           4, 'credito', true, '2370'),
  -- 2404 DE RENTA Y COMPLEMENTARIOS
  ('240405', 'VIGENCIA FISCAL CORRIENTE',               4, 'credito', true, '2404'),
  -- 2408 IMPUESTO SOBRE LAS VENTAS POR PAGAR (IVA generado)
  ('240805', 'IMPUESTO SOBRE LAS VENTAS POR PAGAR (IVA GENERADO)', 4, 'credito', true, '2408'),
  -- 2412 DE INDUSTRIA Y COMERCIO
  ('241205', 'VIGENCIA FISCAL CORRIENTE',               4, 'credito', true, '2412'),
  -- 2505 SALARIOS POR PAGAR
  ('250505', 'SALARIOS POR PAGAR',                      4, 'credito', true, '2505'),
  -- 2510 CESANTIAS CONSOLIDADAS
  ('251005', 'LEY 50 DE 1990 Y NORMAS POSTERIORES',     4, 'credito', true, '2510'),
  -- 3105 CAPITAL SUSCRITO Y PAGADO
  ('310505', 'CAPITAL AUTORIZADO',                      4, 'credito', true, '3105'),
  -- 3115 APORTES SOCIALES
  ('311505', 'CUOTAS O PARTES DE INTERES SOCIAL',       4, 'credito', true, '3115'),
  -- 3305 RESERVAS OBLIGATORIAS
  ('330505', 'RESERVA LEGAL',                           4, 'credito', true, '3305'),
  -- 3605 UTILIDAD DEL EJERCICIO
  ('360505', 'UTILIDAD DEL EJERCICIO',                  4, 'credito', true, '3605'),
  -- 3705 UTILIDADES ACUMULADAS
  ('370505', 'UTILIDADES ACUMULADAS',                   4, 'credito', true, '3705'),
  -- 4135 COMERCIO AL POR MAYOR Y AL POR MENOR (ingresos por venta)
  ('413505', 'VENTA DE MERCANCIAS',                     4, 'credito', true, '4135'),
  ('413595', 'OTROS (COMERCIO AL POR MAYOR Y AL POR MENOR)', 4, 'credito', true, '4135'),
  -- 4175 DEVOLUCIONES EN VENTAS
  ('417505', 'DEVOLUCIONES EN VENTAS',                  4, 'debito',  true, '4175'),
  -- 4210 FINANCIEROS
  ('421005', 'INTERESES',                               4, 'credito', true, '4210'),
  ('421020', 'DESCUENTOS COMERCIALES CONDICIONADOS',    4, 'credito', true, '4210'),
  -- 4295 DIVERSOS
  ('429505', 'APROVECHAMIENTOS',                        4, 'credito', true, '4295'),
  -- 5105 GASTOS DE PERSONAL (administracion)
  ('510506', 'SUELDOS',                                 4, 'debito',  true, '5105'),
  ('510527', 'APORTES A ADMINISTRADORAS DE RIESGOS (ARL)', 4, 'debito', true, '5105'),
  ('510530', 'APORTES A EPS',                           4, 'debito',  true, '5105'),
  -- 5110 HONORARIOS
  ('511025', 'ASESORIA CONTABLE',                       4, 'debito',  true, '5110'),
  -- 5115 IMPUESTOS
  ('511505', 'INDUSTRIA Y COMERCIO',                    4, 'debito',  true, '5115'),
  -- 5120 ARRENDAMIENTOS
  ('512010', 'CONSTRUCCIONES Y EDIFICACIONES',          4, 'debito',  true, '5120'),
  -- 5135 SERVICIOS
  ('513525', 'ACUEDUCTO Y ALCANTARILLADO',              4, 'debito',  true, '5135'),
  ('513530', 'ENERGIA ELECTRICA',                       4, 'debito',  true, '5135'),
  ('513535', 'TELEFONO',                                4, 'debito',  true, '5135'),
  ('513595', 'OTROS (SERVICIOS, INTERNET)',             4, 'debito',  true, '5135'),
  -- 5140 GASTOS LEGALES
  ('514005', 'NOTARIALES',                              4, 'debito',  true, '5140'),
  -- 5195 DIVERSOS (administracion)
  ('519595', 'OTROS (DIVERSOS ADMINISTRACION)',         4, 'debito',  true, '5195'),
  -- 5205 GASTOS DE PERSONAL (ventas)
  ('520506', 'SUELDOS',                                 4, 'debito',  true, '5205'),
  -- 5245 GASTOS DE VENTA
  ('524505', 'PROPAGANDA Y PUBLICIDAD',                 4, 'debito',  true, '5245'),
  -- 5295 DIVERSOS (ventas)
  ('529595', 'OTROS (DIVERSOS VENTAS)',                 4, 'debito',  true, '5295'),
  -- 5305 FINANCIEROS (no operacionales)
  ('530505', 'GASTOS BANCARIOS',                        4, 'debito',  true, '5305'),
  ('530515', 'COMISIONES',                              4, 'debito',  true, '5305'),
  ('530520', 'INTERESES',                               4, 'debito',  true, '5305'),
  -- 6135 COSTO DE VENTAS · COMERCIO AL POR MAYOR Y AL POR MENOR
  ('613505', 'VENTA DE MERCANCIAS (COSTO)',             4, 'debito',  true, '6135'),
  -- 6205 COMPRAS DE MERCANCIAS
  ('620505', 'MERCANCIAS NO FABRICADAS POR LA EMPRESA', 4, 'debito',  true, '6205')
on conflict (codigo) do update set nombre=excluded.nombre, nivel=excluded.nivel, naturaleza=excluded.naturaleza, imputable=excluded.imputable, padre=excluded.padre;

-- ============================================================
-- PLANTILLA PARA ANADIR MAS CUENTAS DEL PUC (catalogo parcial)
-- ------------------------------------------------------------
-- Esta carga NO trae las ~800 cuentas completas del Decreto 2650: trae
-- las 9 clases, los grupos y las cuentas/subcuentas de uso real de un
-- comercio. Para anadir cualquier otra cuenta oficial del PUC, inserta
-- primero su cuenta padre (si aun no existe) y luego la subcuenta, con la
-- naturaleza de su CLASE y imputable=true solo en el nivel de detalle.
--
-- Ejemplo (reemplaza por codigos REALES del PUC, nunca inventes):
--
--   insert into puc_cuentas (codigo, nombre, nivel, naturaleza, imputable, padre)
--   values ('1345', 'INGRESOS POR COBRAR', 3, 'debito', false, '13')
--   on conflict (codigo) do update set nombre=excluded.nombre;
--
--   insert into puc_cuentas (codigo, nombre, nivel, naturaleza, imputable, padre)
--   values ('134505', 'DIVIDENDOS Y/O PARTICIPACIONES', 4, 'debito', true, '1345')
--   on conflict (codigo) do update set nombre=excluded.nombre;
--
-- Regla de naturaleza por clase (recordatorio):
--   1,5,6,7,8 -> debito     2,3,4,9 -> credito
-- Excepcion: cuentas CORRECTORAS (depreciacion 1592, devoluciones en
--   ventas 4175, perdidas) llevan la naturaleza contraria a su clase.
-- ============================================================
