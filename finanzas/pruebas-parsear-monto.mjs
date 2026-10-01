// ============================================================
// Pruebas del parser de montos (B1 + TRAMO 0). Sin dependencias:
//   node finanzas/pruebas-parsear-monto.mjs
// Prueba las TRES copias de analizarMonto (finanzas, inventario, ventas: se
// replican por clonabilidad) y verifica que sean IDENTICAS. Ademas prueba
// leerMontoTecleado (solo Finanzas: campos que se reformatean al escribir),
// incluida una simulacion tecla por tecla del campo real.
// ============================================================
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const aqui = dirname(fileURLToPath(import.meta.url));

// Recorta una funcion exportada del archivo fuente (conteo de llaves).
function recortar(src, nombre, ruta) {
  const marca = 'export function ' + nombre;
  const ini = src.indexOf(marca);
  if (ini === -1) throw new Error('No se encontro ' + nombre + ' en ' + ruta);
  let i = src.indexOf('{', ini);
  let prof = 0, fin = -1;
  for (; i < src.length; i++) {
    if (src[i] === '{') prof++;
    else if (src[i] === '}') { prof--; if (prof === 0) { fin = i + 1; break; } }
  }
  return src.slice(ini, fin).replace('export function', 'function');
}

function cargar(ruta, nombres) {
  const src = readFileSync(ruta, 'utf8');
  const cuerpos = nombres.map((n) => recortar(src, n, ruta)).join('\n');
  // eslint-disable-next-line no-new-func
  return new Function(cuerpos + '\nreturn {' + nombres.join(',') + '};')();
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

// --- Las tres copias deben ser identicas (clonabilidad sin deriva) ---
const copias = cores.map((r) => recortar(readFileSync(r, 'utf8'), 'analizarMonto', r));
chequear('las 3 copias de analizarMonto son identicas', copias.every((c) => c === copias[0]), true);

const ok = (valor, tieneDecimal = false) => ({ valor, tieneDecimal, invalido: false });
const inval = (tieneDecimal = false) => ({ valor: 0, tieneDecimal, invalido: true });

for (const ruta of cores) {
  console.log('\n=== ' + ruta + ' ===');
  const { analizarMonto } = cargar(ruta, ['analizarMonto']);
  const parsearMonto = (t) => analizarMonto(t).valor;

  // --- B1: criterios originales (siguen vigentes) ---
  chequear('"1.200,50" no se traga los centavos', analizarMonto('1.200,50'), ok(1200, true));
  chequear('"1.200,50" != 120050', parsearMonto('1.200,50') !== 120050, true);
  chequear('"1.200.000" -> 1200000', parsearMonto('1.200.000'), 1200000);
  chequear('"" -> 0', parsearMonto(''), 0);
  chequear('null -> 0', parsearMonto(null), 0);
  chequear('"1200,50" avisa decimal, queda 1200', analizarMonto('1200,50'), ok(1200, true));
  chequear('"1200.50" (punto decimal) avisa, queda 1200', analizarMonto('1200.50'), ok(1200, true));
  chequear('"12.5" (punto decimal corto) avisa, queda 12', analizarMonto('12.5'), ok(12, true));
  chequear('"1.200" (mil doscientos) -> 1200 sin aviso', analizarMonto('1.200'), ok(1200));
  chequear('"$ 1.200.000" con simbolo -> 1200000', parsearMonto('$ 1.200.000'), 1200000);
  chequear('"1000000" plano -> 1000000', parsearMonto('1000000'), 1000000);
  chequear('"0" -> 0 (cero legitimo)', analizarMonto('0'), ok(0));
  chequear('"12.345.678" -> 12345678', parsearMonto('12.345.678'), 12345678);
  chequear('"1.200.50" decimal tras miles -> 1200 con aviso', analizarMonto('1.200.50'), ok(1200, true));

  // --- TRAMO 0: estricto, los puntos mal agrupados NO se adivinan ---
  chequear('"12.34.567" grupo intermedio de 2 -> invalido', analizarMonto('12.34.567'), inval());
  chequear('"1.23.456.789" -> invalido', analizarMonto('1.23.456.789'), inval());
  chequear('"1.2.345" -> invalido', analizarMonto('1.2.345'), inval());
  chequear('"1234.567" primer grupo de 4 -> invalido', analizarMonto('1234.567'), inval());
  chequear('"1.2345" ultimo grupo de 4 -> invalido', analizarMonto('1.2345'), inval());
  chequear('"12.34.5" decimal + grupo malo -> invalido', analizarMonto('12.34.5'), inval(true));
  chequear('"1." punto suelto -> invalido', analizarMonto('1.'), inval());
  chequear('invalido nunca entrega un valor usable', parsearMonto('12.34.567'), 0);
}

// --- TRAMO 0: campos que se reformatean al escribir (Finanzas) ---
console.log('\n=== leerMontoTecleado (finanzas-core.js) ===');
const fz = cargar(cores[0], ['formatearCOP', 'analizarMonto', 'leerMontoTecleado']);
const sinPunto = (r) => ({ valor: r.valor, tieneDecimal: r.tieneDecimal, invalido: r.invalido });

chequear('tecleo "1.2345" -> 12345 (antes daba 1)', sinPunto(fz.leerMontoTecleado('1.2345', 'insertText', '5')), ok(12345));
chequear('borrar "24.90" -> 2490 (antes daba 24)', sinPunto(fz.leerMontoTecleado('24.90', 'deleteContentBackward', null)), ok(2490));
chequear('borrar en medio "1.24.567" -> 124567', sinPunto(fz.leerMontoTecleado('1.24.567', 'deleteContentBackward', null)), ok(124567));
chequear('coma tecleada "1.234,5" -> 1234 con aviso', sinPunto(fz.leerMontoTecleado('1.234,5', 'insertText', '5')), ok(1234, true));
chequear('punto tecleado se ignora y se avisa', fz.leerMontoTecleado('1.200.', 'insertText', '.').puntoTecleado, true);
chequear('pegar "1200.50" usa la regla estricta', sinPunto(fz.leerMontoTecleado('1200.50', 'insertFromPaste', null)), ok(1200, true));
chequear('pegar "12.34.567" -> invalido', sinPunto(fz.leerMontoTecleado('12.34.567', 'insertFromPaste', null)), inval());
chequear('sin tipo de entrada usa la regla estricta', sinPunto(fz.leerMontoTecleado('12.34.567')), inval());

// Simulacion del campo real: cada tecla reescribe el valor formateado.
function teclear(digitos) {
  let v = '';
  for (const ch of digitos) {
    v += ch;
    const r = fz.leerMontoTecleado(v, 'insertText', ch);
    if (!r.invalido) v = r.valor > 0 ? fz.formatearCOP(r.valor) : '';
  }
  return v;
}
function borrar(formateado, veces) {
  let v = formateado;
  for (let k = 0; k < veces; k++) {
    v = v.slice(0, -1);
    const r = fz.leerMontoTecleado(v, 'deleteContentBackward', null);
    if (!r.invalido) v = r.valor > 0 ? fz.formatearCOP(r.valor) : '';
  }
  return v;
}
chequear('teclear 1234567 digito a digito -> "1.234.567"', teclear('1234567'), '1.234.567');
chequear('teclear 24900 -> "24.900"', teclear('24900'), '24.900');
chequear('teclear 1000000000 -> "1.000.000.000"', teclear('1000000000'), '1.000.000.000');
chequear('borrar 1 digito de "1.234.567" -> "123.456"', borrar('1.234.567', 1), '123.456');
chequear('borrar 2 digitos de "24.900" -> "249"', borrar('24.900', 2), '249');

console.log('\n' + (fallos === 0 ? 'TODAS LAS PRUEBAS PASARON' : fallos + ' PRUEBA(S) FALLARON'));
process.exit(fallos === 0 ? 0 : 1);
