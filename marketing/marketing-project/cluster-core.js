// ============================================================
// MAGANDHI · Marketing Project · ANALISIS DE CLUSTER · motor (cluster-core.js)
// ------------------------------------------------------------
// Puro y sin dependencias (se prueba con node: pruebas-cluster.mjs).
// Filosofia Impulse: "escupe datos". Agrupa perfiles de cliente que vienen de
// mk_perfiles_clientes (SIN datos de contacto) y entrega grupos, su calidad y
// su retrato en palabras. No decide: la lectura la hace el humano.
//
// Metodo:
//   1. Variables elegidas -> matriz numerica. Montos y conteos con log(1+x)
//      (evita que un cliente que gasta mucho aplaste al resto). Todo se escala
//      a z (media 0, desviacion 1). Categorias -> indicadores 0/1 escalados y
//      pesados por 1/sqrt(K) para que una variable categorica pese como una.
//      Dato faltante -> valor promedio (neutro); se informa la cobertura.
//   2. k-means++ con SEMILLA FIJA y varios reinicios: mismos datos = mismo
//      resultado. Grupos ordenados por tamano (Grupo A = el mas grande).
//   3. Silueta media para k = 2..6; se sugiere el k de mayor silueta.
//   4. Mapa 2D por componentes principales (solo para ver, no para agrupar).
// ============================================================

export const SEMILLA = 20261011;
export const UMBRAL_MIN = 10;        // menos: no se agrupa
export const UMBRAL_EXPLORATORIO = 30; // menos: resultado exploratorio
export const UMBRAL_ESTRUCTURA = 0.25; // silueta menor: sin estructura clara

const FRANJAS = { madrugada: 'de madrugada', manana: 'en la mañana', tarde: 'en la tarde', noche: 'en la noche' };
const DIAS = { lunes: 'los lunes', martes: 'los martes', miercoles: 'los miércoles', jueves: 'los jueves', viernes: 'los viernes', sabado: 'los sábados', domingo: 'los domingos' };

// Catalogo de variables (espejo de las columnas de mk_perfiles_clientes).
export const VARIABLES = [
  { c: 'num_pedidos', g: 'Valor', l: 'Número de pedidos', t: 'num', log: true, f: 'num', alto: 'compran más veces', bajo: 'compran menos veces' },
  { c: 'gasto_total', g: 'Valor', l: 'Gasto total', t: 'num', log: true, f: 'cop', alto: 'gastan más', bajo: 'gastan menos' },
  { c: 'ticket_promedio', g: 'Valor', l: 'Valor promedio por pedido', t: 'num', log: true, f: 'cop', alto: 'hacen pedidos más grandes', bajo: 'hacen pedidos más pequeños' },
  { c: 'unidades', g: 'Valor', l: 'Unidades compradas', t: 'num', log: true, f: 'num', alto: 'llevan más unidades', bajo: 'llevan menos unidades' },
  { c: 'dias_desde_ultima_compra', g: 'Valor', l: 'Días desde la última compra', t: 'num', log: true, f: 'dias', alto: 'llevan más tiempo sin comprar', bajo: 'compraron hace poco' },
  { c: 'dias_entre_compras', g: 'Valor', l: 'Días entre compras', t: 'num', log: true, f: 'dias', alto: 'vuelven con menos frecuencia', bajo: 'vuelven con más frecuencia' },
  { c: 'precio_prom', g: 'Precio', l: 'Precio promedio pagado', t: 'num', log: true, f: 'cop', alto: 'compran productos más caros', bajo: 'compran productos más económicos' },
  { c: 'precio_min', g: 'Precio', l: 'Precio más bajo pagado', t: 'num', log: true, f: 'cop', alto: 'su compra más barata es más cara', bajo: 'incluyen productos de bajo precio' },
  { c: 'precio_max', g: 'Precio', l: 'Precio más alto pagado', t: 'num', log: true, f: 'cop', alto: 'llegan a comprar productos caros', bajo: 'no compran productos caros' },
  { c: 'pct_rebajado', g: 'Precio', l: '% comprado con rebaja', t: 'num', f: 'pct', alto: 'compran más con descuento', bajo: 'compran a precio de lista' },
  { c: 'productos_distintos', g: 'Surtido', l: 'Productos distintos', t: 'num', log: true, f: 'num', alto: 'prueban más productos', bajo: 'se quedan con pocos productos' },
  { c: 'categoria_dominante', g: 'Surtido', l: 'Categoría principal', t: 'cat', frase: (v) => 'gastan sobre todo en ' + v },
  { c: 'estrellas_prom', g: 'Opiniones', l: 'Estrellas promedio', t: 'num', f: 'estrellas', alto: 'califican más alto', bajo: 'califican más bajo' },
  { c: 'num_opiniones', g: 'Opiniones', l: 'Opiniones dejadas', t: 'num', log: true, f: 'num', alto: 'opinan más', bajo: 'opinan menos' },
  { c: 'pct_opinadas', g: 'Opiniones', l: '% de compras opinadas', t: 'num', f: 'pct', alto: 'opinan sobre más de lo que compran', bajo: 'casi no opinan sobre lo que compran' },
  { c: 'dias_entrega_opinion', g: 'Opiniones', l: 'Días hasta opinar', t: 'num', log: true, f: 'dias', alto: 'tardan más en opinar', bajo: 'opinan rápido' },
  { c: 'es_local', g: 'Lugar', l: 'Compra en Tunja', t: 'bool', alto: 'compran en Tunja', bajo: 'compran fuera de Tunja' },
  { c: 'ciudad', g: 'Lugar', l: 'Ciudad', t: 'cat', frase: (v) => 'son de ' + v },
  { c: 'franja_moda', g: 'Momento', l: 'Franja de compra', t: 'cat', frase: (v) => 'compran ' + (FRANJAS[v] || v), etiqueta: (v) => FRANJAS[v] ? FRANJAS[v].replace(/^(de |en la )/, '') : v },
  { c: 'dia_moda', g: 'Momento', l: 'Día de compra', t: 'cat', frase: (v) => 'compran ' + (DIAS[v] || v), etiqueta: (v) => DIAS[v] ? DIAS[v].replace(/^los /, '') : v },
  { c: 'pct_web', g: 'Canal', l: '% pedidos por la web', t: 'num', f: 'pct', alto: 'compran más por la web', bajo: 'compran más por canal manual' },
  { c: 'suscrito', g: 'Respuesta a email', l: 'Suscrito a correos', t: 'bool', alto: 'están suscritos a los correos', bajo: 'no están suscritos a los correos' },
  // EM5.1 · Respuesta a email. NULL = nunca recibio una campana (no es "0 clics"):
  // la cobertura lo deja ver. Sin aperturas: son aproximadas.
  { c: 'email_campanas_recibidas', g: 'Respuesta a email', l: 'Campañas recibidas', t: 'num', log: true, f: 'num', alto: 'reciben más campañas', bajo: 'reciben menos campañas' },
  { c: 'email_pct_clic', g: 'Respuesta a email', l: '% de campañas con clic', t: 'num', f: 'pct', alto: 'hacen clic en más campañas', bajo: 'casi no hacen clic en las campañas' },
  { c: 'email_clics_90d', g: 'Respuesta a email', l: 'Clics en los últimos 90 días', t: 'num', log: true, f: 'num', alto: 'hacen más clics en los correos', bajo: 'hacen pocos clics en los correos' },
  { c: 'email_dias_desde_ultimo_clic', g: 'Respuesta a email', l: 'Días desde su último clic', t: 'num', log: true, f: 'dias', alto: 'hace tiempo no hacen clic en un correo', bajo: 'hicieron clic en un correo hace poco' },
  { c: 'email_compras_atribuidas', g: 'Respuesta a email', l: 'Compras atribuidas a correos', t: 'num', log: true, f: 'num', alto: 'compran más gracias a los correos', bajo: 'compran poco a partir de los correos' }
];
export const VAR = Object.fromEntries(VARIABLES.map((v) => [v.c, v]));
export const PREDETERMINADAS = ['num_pedidos', 'gasto_total', 'dias_desde_ultima_compra', 'precio_prom', 'estrellas_prom'];

// ------------------------------------------------------------
// Aleatorio con semilla (mulberry32): resultados reproducibles
// ------------------------------------------------------------
export function prng(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const esNum = (v) => v !== null && v !== undefined && v !== '' && Number.isFinite(Number(v));
const tr = (def, v) => (def.log ? Math.log1p(Math.max(0, Number(v))) : Number(v));

// ------------------------------------------------------------
// 1. Matriz
// ------------------------------------------------------------
export function cobertura(perfiles, c) {
  const def = VAR[c];
  if (!perfiles.length) return 0;
  const n = perfiles.filter((p) => def.t === 'num' ? esNum(p[c]) : (p[c] !== null && p[c] !== undefined && p[c] !== '')).length;
  return n / perfiles.length;
}

export function prepararMatriz(perfiles, variables) {
  const n = perfiles.length;
  const cols = [];      // columnas de X
  const stats = {};     // por variable
  const X = Array.from({ length: n }, () => []);
  for (const c of variables) {
    const def = VAR[c];
    if (!def) continue;
    if (def.t === 'num' || def.t === 'bool') {
      const val = perfiles.map((p) => def.t === 'bool'
        ? (p[c] === null || p[c] === undefined ? null : (p[c] === true || p[c] === 'true' ? 1 : 0))
        : (esNum(p[c]) ? tr(def, p[c]) : null));
      const pres = val.filter((v) => v !== null);
      const media = pres.length ? pres.reduce((a, b) => a + b, 0) / pres.length : 0;
      const sd = pres.length > 1 ? Math.sqrt(pres.reduce((a, b) => a + (b - media) ** 2, 0) / (pres.length - 1)) : 0;
      stats[c] = { media, sd, cobertura: n ? pres.length / n : 0, constante: !(sd > 1e-12) };
      if (stats[c].constante) continue;
      cols.push({ v: c });
      val.forEach((v, i) => X[i].push(v === null ? 0 : (v - media) / sd));
    } else {
      const val = perfiles.map((p) => (p[c] === null || p[c] === undefined || p[c] === '') ? null : String(p[c]));
      const cats = [...new Set(val.filter((v) => v !== null))].sort();
      stats[c] = { categorias: cats, cobertura: n ? val.filter((v) => v !== null).length / n : 0, constante: cats.length < 2 };
      if (stats[c].constante) continue;
      const peso = 1 / Math.sqrt(cats.length);
      for (const k of cats) {
        const p = val.filter((v) => v === k).length / n;
        const s = Math.sqrt(p * (1 - p)) || 1;
        cols.push({ v: c, cat: k });
        val.forEach((v, i) => X[i].push(v === null ? 0 : (((v === k ? 1 : 0) - p) / s) * peso));
      }
    }
  }
  return { X, cols, stats };
}

// ------------------------------------------------------------
// 2. k-means++ (con semilla y reinicios)
// ------------------------------------------------------------
const d2 = (a, b) => { let s = 0; for (let j = 0; j < a.length; j++) { const t = a[j] - b[j]; s += t * t; } return s; };

function unaCorrida(X, k, rnd, maxIter) {
  const n = X.length, d = X[0].length;
  const C = [X[Math.floor(rnd() * n)].slice()];
  const dist = X.map((x) => d2(x, C[0]));
  while (C.length < k) {
    const tot = dist.reduce((a, b) => a + b, 0);
    let idx = 0;
    if (tot > 0) { let r = rnd() * tot; for (idx = 0; idx < n - 1; idx++) { r -= dist[idx]; if (r <= 0) break; } }
    else idx = Math.floor(rnd() * n);
    C.push(X[idx].slice());
    for (let i = 0; i < n; i++) dist[i] = Math.min(dist[i], d2(X[i], X[idx]));
  }
  const lab = new Array(n).fill(-1);
  for (let it = 0; it < maxIter; it++) {
    let cambio = false;
    for (let i = 0; i < n; i++) {
      let best = 0, bd = Infinity;
      for (let c = 0; c < k; c++) { const v = d2(X[i], C[c]); if (v < bd) { bd = v; best = c; } }
      if (lab[i] !== best) { lab[i] = best; cambio = true; }
    }
    const S = Array.from({ length: k }, () => new Array(d).fill(0)), N = new Array(k).fill(0);
    for (let i = 0; i < n; i++) { N[lab[i]]++; for (let j = 0; j < d; j++) S[lab[i]][j] += X[i][j]; }
    for (let c = 0; c < k; c++) {
      if (N[c] === 0) { // grupo vacio: se reubica en el punto mas lejano
        let far = 0, fd = -1;
        for (let i = 0; i < n; i++) { const v = d2(X[i], C[lab[i]]); if (v > fd) { fd = v; far = i; } }
        C[c] = X[far].slice(); lab[far] = c; cambio = true;
      } else C[c] = S[c].map((s) => s / N[c]);
    }
    if (!cambio) break;
  }
  let inercia = 0;
  for (let i = 0; i < n; i++) inercia += d2(X[i], C[lab[i]]);
  return { lab, C, inercia };
}

export function kmeans(X, k, opts = {}) {
  const { seed = SEMILLA, reinicios = 10, maxIter = 100 } = opts;
  const rnd = prng(seed);
  let mejor = null;
  for (let r = 0; r < reinicios; r++) {
    const res = unaCorrida(X, k, rnd, maxIter);
    if (!mejor || res.inercia < mejor.inercia - 1e-9) mejor = res;
  }
  // Orden canonico: grupo 0 = el mas grande (desempate por primer indice).
  const tam = new Array(k).fill(0), primero = new Array(k).fill(Infinity);
  mejor.lab.forEach((l, i) => { tam[l]++; if (i < primero[l]) primero[l] = i; });
  const orden = [...Array(k).keys()].sort((a, b) => tam[b] - tam[a] || primero[a] - primero[b]);
  const nuevo = new Array(k); orden.forEach((viejo, i) => { nuevo[viejo] = i; });
  return { labels: mejor.lab.map((l) => nuevo[l]), centroides: orden.map((o) => mejor.C[o]), inercia: mejor.inercia };
}

// ------------------------------------------------------------
// 3. Silueta (muestra con semilla si hay muchos clientes)
// ------------------------------------------------------------
export function silueta(X, labels, k, maxMuestra = 1500) {
  const n = X.length;
  if (k < 2 || n < 3) return 0;
  let idx = [...Array(n).keys()];
  if (n > maxMuestra) {
    const rnd = prng(SEMILLA + 7);
    for (let i = n - 1; i > 0; i--) { const j = Math.floor(rnd() * (i + 1)); [idx[i], idx[j]] = [idx[j], idx[i]]; }
    idx = idx.slice(0, maxMuestra);
  }
  const tam = new Array(k).fill(0); idx.forEach((i) => tam[labels[i]]++);
  let total = 0;
  for (const i of idx) {
    const suma = new Array(k).fill(0);
    for (const j of idx) if (j !== i) suma[labels[j]] += Math.sqrt(d2(X[i], X[j]));
    const li = labels[i];
    if (tam[li] <= 1) continue; // s = 0
    const a = suma[li] / (tam[li] - 1);
    let b = Infinity;
    for (let c = 0; c < k; c++) if (c !== li && tam[c] > 0) b = Math.min(b, suma[c] / tam[c]);
    if (!Number.isFinite(b)) continue;
    const m = Math.max(a, b);
    total += m > 0 ? (b - a) / m : 0;
  }
  return total / idx.length;
}

export function explorarK(X, kMax = 6) {
  const lim = Math.min(kMax, X.length - 1);
  const res = [];
  for (let k = 2; k <= lim; k++) {
    const km = kmeans(X, k);
    res.push({ k, silueta: silueta(X, km.labels, k), km });
  }
  let sug = res[0];
  for (const r of res) if (r.silueta > sug.silueta + 1e-9) sug = r;
  return { opciones: res, sugerido: sug ? sug.k : null };
}

export function calidad(s) {
  if (s >= 0.5) return { nivel: 'clara', txt: 'Estructura clara', detalle: 'Los grupos están bien separados entre sí.' };
  if (s >= UMBRAL_ESTRUCTURA) return { nivel: 'moderada', txt: 'Estructura moderada', detalle: 'Hay grupos reconocibles, con algo de mezcla en los bordes.' };
  return { nivel: 'debil', txt: 'Sin estructura clara', detalle: 'Los clientes se parecen bastante entre sí: los grupos podrían ser casualidad. Es una respuesta válida, no un error.' };
}

// ------------------------------------------------------------
// 4. Mapa 2D (componentes principales, iteracion de potencia con semilla)
// ------------------------------------------------------------
export function pca2(X) {
  const n = X.length, d = X[0] ? X[0].length : 0;
  if (!n || !d) return X.map(() => [0, 0]);
  const media = new Array(d).fill(0);
  X.forEach((x) => x.forEach((v, j) => { media[j] += v / n; }));
  const Z = X.map((x) => x.map((v, j) => v - media[j]));
  const cov = Array.from({ length: d }, () => new Array(d).fill(0));
  Z.forEach((z) => { for (let a = 0; a < d; a++) for (let b = 0; b < d; b++) cov[a][b] += z[a] * z[b] / Math.max(1, n - 1); });
  const rnd = prng(SEMILLA + 3);
  const vecs = [];
  const M = cov.map((r) => r.slice());
  for (let c = 0; c < Math.min(2, d); c++) {
    let v = Array.from({ length: d }, () => rnd() - 0.5);
    for (let it = 0; it < 200; it++) {
      const w = M.map((r) => r.reduce((s, x, j) => s + x * v[j], 0));
      const nr = Math.hypot(...w) || 1;
      v = w.map((x) => x / nr);
    }
    const lam = M.map((r) => r.reduce((s, x, j) => s + x * v[j], 0)).reduce((s, x, j) => s + x * v[j], 0);
    vecs.push(v);
    for (let a = 0; a < d; a++) for (let b = 0; b < d; b++) M[a][b] -= lam * v[a] * v[b];
  }
  if (vecs.length < 2) vecs.push(new Array(d).fill(0));
  return Z.map((z) => vecs.map((v) => z.reduce((s, x, j) => s + x * v[j], 0)));
}

// ------------------------------------------------------------
// 5. Retrato de cada grupo
// ------------------------------------------------------------
export function formatear(def, v) {
  if (v === null || v === undefined || !Number.isFinite(v)) return '—';
  const miles = (x) => Math.round(x).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  switch (def.f) {
    case 'cop': return '$' + miles(v);
    case 'pct': return (Math.round(v * 10) / 10).toString().replace('.', ',') + '%';
    case 'dias': return miles(v) + (Math.round(v) === 1 ? ' día' : ' días');
    case 'estrellas': return (Math.round(v * 10) / 10).toFixed(1).replace('.', ',') + ' ★';
    default: return (Math.round(v * 10) / 10).toString().replace('.', ',');
  }
}

export function resumirGrupos(perfiles, labels, k, variables, stats) {
  const grupos = Array.from({ length: k }, (_, g) => ({ g, idx: [] }));
  labels.forEach((l, i) => grupos[l].idx.push(i));
  const n = perfiles.length;
  const general = {};
  for (const c of variables) {
    const def = VAR[c];
    const vals = perfiles.map((p) => p[c]);
    if (def.t === 'num') { const xs = vals.filter(esNum).map(Number); general[c] = xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null; }
    else if (def.t === 'bool') { const xs = vals.filter((v) => v !== null && v !== undefined); general[c] = xs.length ? 100 * xs.filter((v) => v === true || v === 'true').length / xs.length : null; }
    else { const cnt = {}; vals.forEach((v) => { if (v) cnt[v] = (cnt[v] || 0) + 1; }); general[c] = cnt; }
  }
  for (const G of grupos) {
    G.n = G.idx.length;
    G.pct = n ? 100 * G.n / n : 0;
    G.suscritos = G.idx.filter((i) => perfiles[i].suscrito === true).length;
    G.medias = {};
    const rasgos = [];
    for (const c of variables) {
      const def = VAR[c], st = stats[c];
      const vals = G.idx.map((i) => perfiles[i][c]);
      if (def.t === 'num') {
        const xs = vals.filter(esNum).map(Number);
        const m = xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null;
        G.medias[c] = m;
        if (m !== null && st && !st.constante) {
          const mz = xs.map((x) => tr(def, x)).reduce((a, b) => a + b, 0) / xs.length;
          const ef = (mz - st.media) / st.sd;
          if (Math.abs(ef) >= 0.5) rasgos.push({ c, ef, txt: (ef > 0 ? def.alto : def.bajo) + ' (' + formatear(def, m) + ' frente a ' + formatear(def, general[c]) + ')' });
        }
      } else if (def.t === 'bool') {
        const xs = vals.filter((v) => v !== null && v !== undefined);
        const m = xs.length ? 100 * xs.filter((v) => v === true || v === 'true').length / xs.length : null;
        G.medias[c] = m;
        if (m !== null && general[c] !== null && st && !st.constante) {
          const ef = (m / 100 - st.media) / st.sd;
          if (Math.abs(ef) >= 0.5) rasgos.push({ c, ef, txt: (ef > 0 ? def.alto : def.bajo) + ' (' + Math.round(ef > 0 ? m : 100 - m) + '%)' });
        }
      } else {
        const cnt = {}; vals.forEach((v) => { if (v) cnt[v] = (cnt[v] || 0) + 1; });
        const top = Object.entries(cnt).sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : 1))[0];
        G.medias[c] = top ? { valor: top[0], pct: 100 * top[1] / G.n } : null;
        if (top && st && !st.constante) {
          const pg = top[1] / G.n;
          const pa = (general[c][top[0]] || 0) / n;
          if (pg >= 0.5 && pg - pa >= 0.2) rasgos.push({ c, ef: (pg - pa) / Math.sqrt(pa * (1 - pa) || 0.25), txt: def.frase(top[0]) + ' (' + Math.round(pg * 100) + '%)' });
        }
      }
    }
    rasgos.sort((a, b) => Math.abs(b.ef) - Math.abs(a.ef));
    G.rasgos = rasgos.slice(0, 3);
    G.titular = G.rasgos.length
      ? G.rasgos.map((r) => r.txt.replace(/ \(.*\)$/, '')).join(', ').replace(/^./, (x) => x.toUpperCase())
      : 'Cercanos al promedio en todo';
  }
  return { grupos, general };
}

export const LETRA = (g) => 'Grupo ' + String.fromCharCode(65 + g);

// ------------------------------------------------------------
// Orquestador
// ------------------------------------------------------------
export function analizar(perfiles, variables, kForzado) {
  const n = perfiles.length;
  if (n < UMBRAL_MIN) return { estado: 'pocos', n };
  const { X, cols, stats } = prepararMatriz(perfiles, variables);
  if (!cols.length) return { estado: 'sin_variacion', n, stats };
  const exp = explorarK(X);
  if (!exp.opciones.length) return { estado: 'pocos', n };
  const k = kForzado && exp.opciones.some((o) => o.k === kForzado) ? kForzado : exp.sugerido;
  const elegido = exp.opciones.find((o) => o.k === k);
  const { grupos, general } = resumirGrupos(perfiles, elegido.km.labels, k, variables, stats);
  return {
    estado: 'ok', n, k, sugerido: exp.sugerido, exploratorio: n < UMBRAL_EXPLORATORIO,
    silueta: elegido.silueta, calidad: calidad(elegido.silueta),
    opciones: exp.opciones.map((o) => ({ k: o.k, silueta: o.silueta })),
    labels: elegido.km.labels, mapa: pca2(X), grupos, general, stats, columnas: cols.length
  };
}
