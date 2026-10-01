// ============================================================
// Pruebas de las etiquetas de periodos PROYECTADOS (Tramo 0). Sin dependencias:
//   node marketing/marketing-project/pruebas-etiquetas-proyeccion.mjs
// Extrae las funciones REALES de proyeccion-demanda.html y de marketing-core.js
// y comprueba que la proyeccion continua desde el ULTIMO periodo analizado (no
// desde hoy), con el mismo formato del historico, sin saltarse meses.
// ============================================================
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const aqui = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(aqui, 'proyeccion-demanda.html'), 'utf8');
const core = readFileSync(join(aqui, '..', 'marketing-core.js'), 'utf8');

function recortar(src, firma) {
  const ini = src.indexOf(firma);
  if (ini === -1) throw new Error('No se encontro: ' + firma);
  let i = src.indexOf('{', ini), prof = 0, fin = -1;
  for (; i < src.length; i++) {
    if (src[i] === '{') prof++;
    else if (src[i] === '}') { prof--; if (prof === 0) { fin = i + 1; break; } }
  }
  return src.slice(ini, fin).replace(/^export /, '');
}

const codigo = [
  recortar(core, 'function claveSemanaISO'),
  recortar(core, 'export function clavePeriodo'),
  recortar(core, 'export function agruparPorPeriodo'),
  recortar(core, 'function secuenciaClaves'),
  recortar(core, 'function isoAFechaUTC'),
  recortar(html, 'function fechaInicioDeClave'),
  recortar(html, 'function aISO'),
  recortar(html, 'function etiquetasFuturas')
].join('\n');
// eslint-disable-next-line no-new-func
const f = new Function(codigo + '\nreturn { etiquetasFuturas, agruparPorPeriodo };')();

let fallos = 0;
function chequear(desc, real, esperado) {
  const ok = JSON.stringify(real) === JSON.stringify(esperado);
  if (!ok) fallos++;
  console.log((ok ? 'OK  ' : 'FALLA ') + desc + '  ->  ' + JSON.stringify(real) +
    (ok ? '' : '  (esperaba ' + JSON.stringify(esperado) + ')'));
}

// Continuan desde el ultimo periodo analizado, no desde hoy.
chequear('mes: tras 2025-03 vienen 2025-04..06', f.etiquetasFuturas('2025-03', 3, 'mes'), ['2025-04', '2025-05', '2025-06']);
chequear('mes: cruza de ano', f.etiquetasFuturas('2025-11', 3, 'mes'), ['2025-12', '2026-01', '2026-02']);
chequear('dia: cruza de mes y bisiesto', f.etiquetasFuturas('2024-02-28', 3, 'dia'), ['2024-02-29', '2024-03-01', '2024-03-02']);
chequear('dia: cruza de ano', f.etiquetasFuturas('2025-12-31', 2, 'dia'), ['2026-01-01', '2026-01-02']);
chequear('semana: formato ISO como el historico', f.etiquetasFuturas('2025-W10', 2, 'semana'), ['2025-W11', '2025-W12']);
chequear('semana: ano con semana 53', f.etiquetasFuturas('2020-W52', 3, 'semana'), ['2020-W53', '2021-W01', '2021-W02']);
chequear('semana: ano sin semana 53', f.etiquetasFuturas('2025-W52', 2, 'semana'), ['2026-W01', '2026-W02']);
chequear('sin historico -> sin etiquetas', f.etiquetasFuturas(null, 3, 'mes'), []);

// Integracion: el historico de un rango del 31-ene y la proyeccion encadenan
// sin huecos ni saltos (antes, setMonth desde el 31 podia saltarse febrero).
const hist = f.agruparPorPeriodo([{ fecha: '2025-01-31', cantidad: 2 }], 'mes', '2025-01-31', '2025-01-31');
chequear('historico de enero termina en 2025-01', hist.map((b) => b.clave), ['2025-01']);
chequear('proyeccion desde un 31 no salta febrero', f.etiquetasFuturas(hist[hist.length - 1].clave, 2, 'mes'), ['2025-02', '2025-03']);

console.log('\n' + (fallos === 0 ? 'TODAS LAS PRUEBAS PASARON' : fallos + ' PRUEBA(S) FALLARON'));
process.exit(fallos === 0 ? 0 : 1);
