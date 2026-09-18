// ============================================================
//  PRUEBA DE VERIFICACION · B1.1 parsearMonto / analizarMonto
//  ------------------------------------------------------------
//  El sitio es JS de navegador sin build; los cores importan
//  ../supabase-config.js (side-effect que no resuelve en Node). Para
//  probar el codigo REAL que se despacha, extraemos la fuente de
//  `analizarMonto` de finanzas-core.js y la evaluamos aislada.
//
//  Ejecutar:  node finanzas/pruebas-parsear-monto.mjs
//  Criterio B1 (del ANDAMIOS):
//    · "1.200,50"  -> NO 120050 (o rechaza/avisa el decimal).
//    · "1.200.000" -> 1200000 (solo miles, correcto).
//    · ""          -> 0.
// ============================================================
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const aqui = dirname(fileURLToPath(import.meta.url));

function cargarAnalizarMonto(rutaCore) {
  const src = readFileSync(rutaCore, 'utf8');
  const marca = 'export function analizarMonto';
  const ini = src.indexOf(marca);
  if (ini === -1) throw new Error('No se encontro analizarMonto en ' + rutaCore);
  // Recorta desde la firma hasta el cierre de la funcion (conteo de llaves).
  let i = src.indexOf('{', ini);
  let prof = 0, fin = -1;
  for (; i < src.length; i++) {
    if (src[i] === '{') prof++;
    else if (src[i] === '}') { prof--; if (prof === 0) { fin = i + 1; break; } }
  }
  const cuerpo = src.slice(ini, fin).replace('export function', 'function');
  // eslint-disable-next-line no-new-func
  return new Function(cuerpo + '\nreturn analizarMonto;')();
}

let fallos = 0;
function chequear(desc, real, esperado) {
  const ok = JSON.stringify(real) === JSON.stringify(esperado);
  if (!ok) fallos++;
  console.log((ok ? 'OK  ' : 'FALLA ') + desc + '  ->  ' + JSON.stringify(real) +
    (ok ? '' : '  (esperaba ' + JSON.stringify(esperado) + ')'));
}

const cores = [
  join(aqui, 'finanzas-core.js'),
  join(aqui, '..', 'produccion', 'inventario-core.js'),
  join(aqui, '..', 'ventas', 'ventas-core.js')
];

for (const ruta of cores) {
  console.log('\n=== ' + ruta + ' ===');
  const analizarMonto = cargarAnalizarMonto(ruta);
  const parsearMonto = (t) => analizarMonto(t).valor;

  // --- Criterios explicitos del ANDAMIOS ---
  // 1.200,50 NO debe dar 120050; debe avisar el decimal y quedar en 1200 pesos.
  chequear('"1.200,50" no se traga los centavos', analizarMonto('1.200,50'),
    { valor: 1200, tieneDecimal: true, invalido: false });
  chequear('"1.200,50" != 120050', parsearMonto('1.200,50') !== 120050, true);
  // 1.200.000 (solo separadores de miles) sigue dando 1200000.
  chequear('"1.200.000" -> 1200000', parsearMonto('1.200.000'), 1200000);
  // Campo vacio sigue dando 0.
  chequear('"" -> 0', parsearMonto(''), 0);
  chequear('null -> 0', parsearMonto(null), 0);

  // --- Casos de apoyo ---
  chequear('"1200,50" avisa decimal, queda 1200', analizarMonto('1200,50'),
    { valor: 1200, tieneDecimal: true, invalido: false });
  chequear('"1200.50" (punto decimal) avisa, queda 1200', analizarMonto('1200.50'),
    { valor: 1200, tieneDecimal: true, invalido: false });
  chequear('"12.5" (punto decimal corto) avisa, queda 12', analizarMonto('12.5'),
    { valor: 12, tieneDecimal: true, invalido: false });
  chequear('"1.200" (mil doscientos) -> 1200 sin aviso', analizarMonto('1.200'),
    { valor: 1200, tieneDecimal: false, invalido: false });
  chequear('"$ 1.200.000" con simbolo -> 1200000', parsearMonto('$ 1.200.000'), 1200000);
  chequear('"1000000" plano -> 1000000', parsearMonto('1000000'), 1000000);
  chequear('"0" -> 0 (cero legitimo, no null)', parsearMonto('0'), 0);
  chequear('"12.345.678" -> 12345678', parsearMonto('12.345.678'), 12345678);
}

console.log('\n' + (fallos === 0 ? 'TODAS LAS PRUEBAS PASARON' : fallos + ' PRUEBA(S) FALLARON'));
process.exit(fallos === 0 ? 0 : 1);
