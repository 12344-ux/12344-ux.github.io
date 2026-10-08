// ============================================================
// Pruebas del motor de Analisis de cluster. Sin dependencias:
//   node marketing/marketing-project/pruebas-cluster.mjs
// ============================================================
import {
  analizar, kmeans, silueta, prepararMatriz, prng, cobertura, UMBRAL_MIN, UMBRAL_EXPLORATORIO
} from './cluster-core.js';

let fallos = 0;
const ok = (n, c) => { console.log((c ? 'OK   ' : 'FALLO ') + n); if (!c) fallos++; };

// Tres grupos claros: frecuentes caros de Tunja / ocasionales economicos que
// califican bajo / nuevos de noche que no opinan.
const rnd = prng(42);
const ruido = (s) => (rnd() - 0.5) * s;
const perfiles = [];
for (let i = 0; i < 20; i++) perfiles.push({ cliente_ref: 'a' + i, num_pedidos: 8 + Math.round(ruido(3)), gasto_total: 400000 + ruido(60000), precio_prom: 45000 + ruido(5000), estrellas_prom: 4.8 + ruido(0.3), dias_desde_ultima_compra: 10 + Math.round(ruido(6)), es_local: true, franja_moda: 'tarde', suscrito: true });
for (let i = 0; i < 15; i++) perfiles.push({ cliente_ref: 'b' + i, num_pedidos: 2 + Math.round(ruido(1)), gasto_total: 30000 + ruido(8000), precio_prom: 12000 + ruido(2000), estrellas_prom: 2.2 + ruido(0.6), dias_desde_ultima_compra: 120 + Math.round(ruido(30)), es_local: false, franja_moda: 'manana', suscrito: false });
for (let i = 0; i < 10; i++) perfiles.push({ cliente_ref: 'c' + i, num_pedidos: 1, gasto_total: 90000 + ruido(15000), precio_prom: 30000 + ruido(4000), estrellas_prom: null, dias_desde_ultima_compra: 5 + Math.round(ruido(4)), es_local: true, franja_moda: 'noche', suscrito: true });

const vars = ['num_pedidos', 'gasto_total', 'precio_prom', 'estrellas_prom', 'dias_desde_ultima_compra', 'es_local', 'franja_moda'];
const r = analizar(perfiles, vars);
ok('encuentra 3 grupos con datos de 3 grupos', r.estado === 'ok' && r.k === 3 && r.sugerido === 3);
ok('calidad clara (silueta ' + r.silueta.toFixed(2) + ')', r.silueta >= 0.5 && r.calidad.nivel === 'clara');
ok('no es exploratorio con 45 clientes', r.n === 45 && !r.exploratorio);
ok('Grupo A es el más grande (20)', r.grupos[0].n === 20 && r.grupos[1].n === 15 && r.grupos[2].n === 10);
const puro = (pref) => new Set(r.labels.filter((_, i) => perfiles[i].cliente_ref.startsWith(pref))).size === 1;
ok('cada grupo real queda junto', puro('a') && puro('b') && puro('c'));
const A = r.grupos[0].titular.toLowerCase(), B = r.grupos[1].titular.toLowerCase();
ok('retrato A habla de frecuencia o gasto: «' + r.grupos[0].titular + '»', /compran más veces|gastan más|productos más caros/.test(A));
ok('retrato B: «' + r.grupos[1].titular + '»', /sin comprar|califican más bajo|menos|económicos/.test(B));
ok('retrato C menciona la noche: «' + r.grupos[2].rasgos.map((x) => x.txt).join(' | ') + '»', r.grupos[2].rasgos.some((x) => /noche|hace poco|una vez|menos veces/.test(x.txt)));
ok('suscritos por grupo', r.grupos[0].suscritos === 20 && r.grupos[1].suscritos === 0);
ok('mapa 2D para cada cliente', r.mapa.length === 45 && r.mapa.every((p) => p.length === 2 && p.every(Number.isFinite)));
ok('cobertura de estrellas = 35/45', Math.abs(cobertura(perfiles, 'estrellas_prom') - 35 / 45) < 1e-9);

// Determinismo
const r2 = analizar(perfiles, vars);
ok('mismos datos = mismo resultado', JSON.stringify(r.labels) === JSON.stringify(r2.labels) && r.silueta === r2.silueta);

// Forzar k
const r4 = analizar(perfiles, vars, 4);
ok('se puede forzar 4 grupos', r4.k === 4 && r4.sugerido === 3 && r4.grupos.length === 4);

// Umbrales
ok('menos de ' + UMBRAL_MIN + ' clientes: no agrupa', analizar(perfiles.slice(0, 9), vars).estado === 'pocos');
const pocos = [...perfiles.slice(0, 8), ...perfiles.slice(20, 28), ...perfiles.slice(35, 40)];
const rp = analizar(pocos, vars);
ok('entre 10 y ' + (UMBRAL_EXPLORATORIO - 1) + ': exploratorio', rp.estado === 'ok' && rp.exploratorio && rp.n === 21);

// Sin estructura: datos homogeneos
const r_ = prng(7);
const homo = Array.from({ length: 60 }, (_, i) => ({ cliente_ref: 'h' + i, gasto_total: 50000 + (r_() - 0.5) * 20000, num_pedidos: 3 + Math.round((r_() - 0.5) * 2), precio_prom: 20000 + (r_() - 0.5) * 6000 }));
const rh = analizar(homo, ['gasto_total', 'num_pedidos', 'precio_prom']);
ok('datos homogéneos: silueta baja (' + rh.silueta.toFixed(2) + ')', rh.silueta < 0.5 && rh.calidad.nivel !== 'clara');

// Variable constante se ignora; todo constante -> sin_variacion
const cte = Array.from({ length: 12 }, (_, i) => ({ cliente_ref: 'k' + i, num_pedidos: 1, es_local: true }));
ok('todas constantes: sin variación', analizar(cte, ['num_pedidos', 'es_local']).estado === 'sin_variacion');
const { cols, stats } = prepararMatriz(perfiles, ['num_pedidos', 'franja_moda']);
ok('categoría en indicadores (1 + 3 columnas)', cols.length === 4 && stats.franja_moda.categorias.length === 3);

// Faltantes no rompen
const conHuecos = perfiles.map((p, i) => ({ ...p, gasto_total: i % 3 ? p.gasto_total : null }));
const rf = analizar(conHuecos, vars);
ok('datos faltantes se imputan sin romper', rf.estado === 'ok' && rf.labels.every((l) => l >= 0));

// Silueta de referencia: 2 puntos lejanos por grupo
const Xs = [[0, 0], [0, 1], [10, 10], [10, 11]];
ok('silueta de manual (≈0,93)', Math.abs(silueta(Xs, [0, 0, 1, 1], 2) - 0.929) < 0.01);
ok('k-means separa el caso de manual', (() => { const k = kmeans(Xs, 2); return k.labels[0] === k.labels[1] && k.labels[2] === k.labels[3] && k.labels[0] !== k.labels[2]; })());

console.log(fallos ? '\n' + fallos + ' FALLOS' : '\nTODO OK');
process.exit(fallos ? 1 : 0);
