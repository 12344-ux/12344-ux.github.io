// ============================================================
//  MAGANDHI · AREA DE METRICAS · nucleo compartido (metricas-core.js)
//  ------------------------------------------------------------
//  Header institucional, pestañas, acceso y una pequeña libreria PROPIA de
//  graficas en SVG (sin dependencias externas): linea con comparacion, barras,
//  barras horizontales, reparto, mapa de calor, embudo y sparkline. Todas
//  responden al ancho real (se redibujan al cambiar el tamaño) y muestran el
//  dato exacto al pasar el cursor o tocar.
//
//  Filosofia Impulse: Metricas ORGANIZA y muestra; no interpreta. Cada numero
//  viene ya calculado de la capa de datos (RPC mt_* en la base), la misma que
//  consumen los demas softwares.
//
//  SEGURIDAD: ocultar UI es comodidad; el candado real son los RPC guardados
//  por tiene_acceso_datos_metricas() (migracion 20261016000000).
// ============================================================
import { supabase } from '../supabase-config.js';
import { exigirSesion, obtenerPerfil } from '../auth-guard.js';
export { supabase };

// ------------------------------------------------------------
// Utilidades
// ------------------------------------------------------------
export const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
export const num = (n) => Math.round(Number(n) || 0).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.');
export const cop = (n) => '$' + num(n);
export function copCorto(n) {
  const v = Number(n) || 0, a = Math.abs(v);
  if (a >= 1e9) return '$' + (v / 1e9).toFixed(1).replace('.', ',').replace(',0', '') + ' mil M';
  if (a >= 1e6) return '$' + (v / 1e6).toFixed(a < 1e7 ? 2 : 1).replace('.', ',').replace(/,?0+$/, '') + ' M';
  if (a >= 1e4) return '$' + Math.round(v / 1e3) + ' mil';
  return cop(v);
}
export const pct = (a, b) => (b ? Math.round((100 * a) / b) : 0);
const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
const DIAS = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
export const DIAS_LARGOS = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
export function fechaCorta(iso) { const d = new Date(String(iso).slice(0, 10) + 'T12:00:00'); return d.getDate() + ' ' + MESES[d.getMonth()]; }
export function fechaLarga(iso) { const d = new Date(String(iso).slice(0, 10) + 'T12:00:00'); return DIAS_LARGOS[(d.getDay() + 6) % 7] + ' ' + d.getDate() + ' de ' + MESES[d.getMonth()]; }
export function hora(iso) { const d = new Date(iso); return String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0'); }
export function haceCuanto(iso) {
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  if (s < 60) return 'hace un momento';
  if (s < 3600) return 'hace ' + Math.floor(s / 60) + ' min';
  if (s < 86400) return 'hace ' + Math.floor(s / 3600) + ' h';
  return fechaCorta(iso);
}
export function hoyLocal(desfaseDias = 0) {
  const d = new Date(); d.setDate(d.getDate() + desfaseDias);
  return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
}
export function mensajeError(e) {
  const m = (e && e.message) || String(e || '');
  if (/MT_SIN_ACCESO/.test(m)) return 'Tu usuario no tiene acceso a Métricas.';
  if (/MT_POLITICA_PENDIENTE/.test(m)) return 'Primero registra la política de tratamiento de datos (Email marketing → Resumen).';
  if (/mt_(en_vivo|ventas|tienda|config_analitica)|PGRST202|function/i.test(m)) return 'Falta aplicar la migración 20261016000000_metricas_m1.sql en Supabase.';
  return 'No se pudo cargar: ' + m;
}

const svgI = (d) => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + d + '</svg>';
export const ICONOS = {
  flecha: svgI('<path d="m15 18-6-6 6-6"/>'),
  salir: svgI('<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5M21 12H9"/>'),
  vivo: svgI('<circle cx="12" cy="12" r="2"/><path d="M16.24 7.76a6 6 0 0 1 0 8.49M7.76 16.24a6 6 0 0 1 0-8.49M19.07 4.93a10 10 0 0 1 0 14.14M4.93 19.07a10 10 0 0 1 0-14.14"/>'),
  ventas: svgI('<path d="M3 3v18h18"/><path d="m7 15 4-4 3 3 5-6"/>'),
  tienda: svgI('<path d="M3 9h18l-1.5 11H4.5Z"/><path d="M8 9V6a4 4 0 0 1 8 0v3"/>'),
  ojo: svgI('<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>'),
  bolsa: svgI('<path d="M6 2 3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4Z"/><path d="M3 6h18M16 10a4 4 0 0 1-8 0"/>'),
  tarjeta: svgI('<rect x="2" y="5" width="20" height="14" rx="2"/><path d="M2 10h20"/>'),
  cursor: svgI('<path d="m4 4 7 17 2.5-7.5L21 11Z"/>'),
  sobre: svgI('<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m2 7 10 6 10-6"/>'),
  pedido: svgI('<path d="M16 3h5v5M21 3l-7 7"/><path d="M21 14v5a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5"/>'),
  info: svgI('<circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/>'),
  escudo: svgI('<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/>'),
  vacio: svgI('<path d="M3 3v18h18"/><path d="M7 14h.01M11 10h.01M15 12h.01M19 8h.01"/>'),
  movil: svgI('<rect x="7" y="2" width="10" height="20" rx="2"/><path d="M11 18h2"/>'),
  pc: svgI('<rect x="2" y="4" width="20" height="13" rx="2"/><path d="M8 21h8M12 17v4"/>'),
  tablet: svgI('<rect x="4" y="2" width="16" height="20" rx="2"/><path d="M11 18h2"/>'),
};

// ------------------------------------------------------------
// Acceso + estructura de pagina
// ------------------------------------------------------------
export function tieneAccesoMetricas(perfil) {
  if (!perfil) return false;
  if (perfil.rol === 'admin') return true;
  return (Array.isArray(perfil.modulos) ? perfil.modulos : []).includes('metricas');
}

const PESTANAS = [
  { id: 'vivo', txt: 'En vivo', href: 'index.html', ico: 'vivo' },
  { id: 'ventas', txt: 'Ventas', href: 'ventas.html', ico: 'ventas' },
  { id: 'tienda', txt: 'Tienda', href: 'tienda.html', ico: 'tienda' },
];

export async function montarArea({ activa, titulo, lead, extraCabecera }) {
  const sesion = await exigirSesion();
  if (!sesion) return null;
  let perfil = null;
  try { perfil = await obtenerPerfil(); } catch (_) {}
  const email = sesion.user?.email || '';
  const header = document.createElement('header');
  header.className = 'mt-header';
  header.innerHTML =
    '<div class="mt-header-left"><a class="mt-volver" href="../panel.html" aria-label="Volver al panel">' + ICONOS.flecha + '<span>Panel</span></a>' +
      '<span class="mt-sep" aria-hidden="true"></span><img class="mt-logo" src="../logo-mark-terracota.png?v=2" alt="Magandhi">' +
      '<span class="mt-word">MAGANDHI</span><span class="mt-sep b" aria-hidden="true"></span><span class="mt-area">Área de métricas</span></div>' +
    '<div class="mt-perfil"><button class="mt-avatar" type="button" aria-haspopup="menu" aria-expanded="false" title="' + esc(email) + '" aria-label="Menú de perfil">' + esc((email[0] || 'M').toUpperCase()) + '</button>' +
      '<div class="mt-perfil-menu" role="menu" hidden><div class="mt-perfil-info"><span>Sesión iniciada como</span><span>' + esc(email) + '</span></div>' +
      '<button class="mt-perfil-salir" type="button" role="menuitem">' + ICONOS.salir + '<span>Cerrar sesión</span></button></div></div>';
  document.body.prepend(header);
  const av = header.querySelector('.mt-avatar'), menu = header.querySelector('.mt-perfil-menu');
  av.addEventListener('click', (e) => { e.stopPropagation(); menu.hidden = !menu.hidden; av.setAttribute('aria-expanded', String(!menu.hidden)); });
  document.addEventListener('click', (e) => { if (!menu.hidden && !menu.contains(e.target)) { menu.hidden = true; av.setAttribute('aria-expanded', 'false'); } });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !menu.hidden) { menu.hidden = true; av.setAttribute('aria-expanded', 'false'); av.focus(); } });
  header.querySelector('.mt-perfil-salir').addEventListener('click', async () => { try { await supabase.auth.signOut(); } catch (_) {} location.replace('../index.html'); });

  const sello = document.createElement('footer');
  sello.className = 'mt-sello'; sello.innerHTML = 'Con tecnología <b>Impulse</b>';
  document.body.appendChild(sello);

  const main = document.getElementById('mt-main');
  if (!tieneAccesoMetricas(perfil)) {
    main.innerHTML = '<div class="mt-denegado"><h2>Acceso restringido · Métricas</h2><p>Tu cuenta no tiene habilitada el área de <strong>Métricas</strong>. Solicítala a un administrador.</p><p><a href="../panel.html">Volver al panel</a></p></div>';
    main.hidden = false;
    return null;
  }
  const head = document.createElement('div');
  head.className = 'mt-head';
  head.innerHTML = '<p class="mt-kicker">Métricas</p><div class="mt-head-fila"><div><h1 class="mt-title">' + esc(titulo) + '</h1>' +
      (lead ? '<p class="mt-lead">' + esc(lead) + '</p>' : '') + '</div>' + (extraCabecera || '') + '</div>' +
    '<nav class="mt-tabs" aria-label="Secciones de Métricas">' + PESTANAS.map((t) =>
      '<a class="mt-tab" href="' + t.href + '"' + (t.id === activa ? ' aria-current="page"' : '') + '>' + ICONOS[t.ico] + t.txt + '</a>').join('') + '</nav>';
  main.before(head);
  main.hidden = false;
  return { sesion, perfil, esAdmin: perfil?.rol === 'admin' };
}

// ------------------------------------------------------------
// Componentes de cifras
// ------------------------------------------------------------
export function delta(actual, anterior, { invertido = false } = {}) {
  const a = Number(actual) || 0, b = Number(anterior) || 0;
  if (!b && !a) return '<span class="mt-delta igual">=</span>';
  if (!b) return '<span class="mt-delta sube">nuevo</span>';
  const p = Math.round(((a - b) / b) * 100);
  if (p === 0) return '<span class="mt-delta igual">0%</span>';
  const sube = p > 0;
  const flecha = '<svg viewBox="0 0 10 10" aria-hidden="true"><path d="' + (sube ? 'M5 2 9 8H1Z' : 'M5 8 1 2h8Z') + '" fill="currentColor"/></svg>';
  return '<span class="mt-delta ' + ((sube !== invertido) ? 'sube' : 'baja') + '" title="' + (sube ? 'Sube ' : 'Baja ') + Math.abs(p) + '% frente al periodo de comparación">' + flecha + Math.abs(p) + '%</span>';
}
export function kpi({ k, v, pie, destacado, spark }) {
  return '<div class="mt-kpi' + (destacado ? ' destacado' : '') + '"><span class="mt-kpi-k">' + esc(k) + '</span><span class="mt-kpi-v">' + v + '</span>' +
    '<span class="mt-kpi-pie">' + (pie || '') + '</span>' + (spark ? '<div class="mt-kpi-spark" data-spark="' + esc(JSON.stringify(spark)) + '"></div>' : '') + '</div>';
}
export function vacio(titulo, texto) {
  return '<div class="mt-vacio">' + ICONOS.vacio + '<b>' + esc(titulo) + '</b><span>' + esc(texto) + '</span></div>';
}

// ------------------------------------------------------------
// Graficas SVG (responsivas, con lectura al pasar el cursor)
// ------------------------------------------------------------
const observados = new WeakMap();
function alAncho(el, dibujar) {
  dibujar(el.clientWidth || 600);
  if (observados.has(el)) observados.get(el).disconnect();
  let ultimo = el.clientWidth;
  const ro = new ResizeObserver(() => { if (Math.abs(el.clientWidth - ultimo) > 4) { ultimo = el.clientWidth; dibujar(ultimo); } });
  ro.observe(el); observados.set(el, ro);
}
function escalaBonita(max, entero) {
  if (max <= 0) return { max: 1, pasos: [0, 1] };
  if (entero && max <= 4) { const top = Math.max(1, Math.ceil(max)); return { max: top, pasos: Array.from({ length: top + 1 }, (_, i) => i) }; }
  const exp = Math.pow(10, Math.floor(Math.log10(max)));
  const f = max / exp;
  const top = (f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10) * exp;
  const n = 4;
  return { max: top, pasos: Array.from({ length: n + 1 }, (_, i) => (top * i) / n) };
}
function tip(el) {
  let t = el.querySelector('.mt-tip');
  if (!t) { t = document.createElement('div'); t.className = 'mt-tip'; t.setAttribute('role', 'status'); el.appendChild(t); }
  return t;
}

/** Linea (area suave) con serie de comparacion opcional.
 *  o = { etiquetas:[iso], series:[{nombre, datos:[n], clase:''|'comp'|'sec', area:bool}], formato:(n)=>str, alto, etiquetaTip:(i)=>str } */
export function grafLinea(el, o) {
  el.classList.add('mt-chart');
  const alto = o.alto || 240, padL = 52, padR = 12, padT = 12, padB = 28;
  const fmt = o.formato || num;
  const n = o.etiquetas.length;
  const maxV = Math.max(0, ...o.series.flatMap((s) => s.datos.map(Number)));
  const esc_ = escalaBonita(maxV, o.series.every((se) => se.datos.every((v) => Number.isInteger(Number(v)))));
  alAncho(el, (W) => {
    const iw = W - padL - padR, ih = alto - padT - padB;
    const x = (i) => padL + (n <= 1 ? iw / 2 : (iw * i) / (n - 1));
    const y = (v) => padT + ih - (ih * (Number(v) || 0)) / esc_.max;
    const cada = Math.max(1, Math.ceil(n / Math.max(2, Math.floor(iw / 70))));
    let s = '<svg viewBox="0 0 ' + W + ' ' + alto + '" height="' + alto + '" role="img" aria-label="' + esc(o.aria || 'Gráfica') + '">' +
      '<defs><linearGradient id="mtg-' + (el.id || 'g') + '" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#101C33" stop-opacity=".16"/><stop offset="1" stop-color="#101C33" stop-opacity="0"/></linearGradient></defs>';
    esc_.pasos.forEach((v) => {
      s += '<line class="rejilla" x1="' + padL + '" x2="' + (W - padR) + '" y1="' + y(v) + '" y2="' + y(v) + '"/>' +
        '<text class="lbl" x="' + (padL - 8) + '" y="' + (y(v) + 4) + '" text-anchor="end">' + esc(o.formatoEje ? o.formatoEje(v) : fmt(v)) + '</text>';
    });
    for (let i = 0; i < n; i += cada) s += '<text class="lbl" x="' + x(i) + '" y="' + (alto - 8) + '" text-anchor="middle">' + esc(o.etiquetaEje ? o.etiquetaEje(o.etiquetas[i], i) : fechaCorta(o.etiquetas[i])) + '</text>';
    o.series.slice().reverse().forEach((se) => {
      const pts = se.datos.map((v, i) => [x(i), y(v)]);
      if (!pts.length) return;
      const d = pts.map((p, i) => (i ? 'L' : 'M') + p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join(' ');
      if (se.area) s += '<path d="' + d + ' L' + x(pts.length - 1) + ' ' + (padT + ih) + ' L' + x(0) + ' ' + (padT + ih) + ' Z" fill="url(#mtg-' + (el.id || 'g') + ')"/>';
      s += '<path class="linea ' + (se.clase || '') + '" d="' + d + '"/>';
      if (n === 1) s += '<circle class="punto" cx="' + pts[0][0] + '" cy="' + pts[0][1] + '" r="4"/>';
    });
    s += '<g class="lectura" style="opacity:0"><line class="guia" y1="' + padT + '" y2="' + (padT + ih) + '" x1="0" x2="0"/><circle class="punto" r="4.5" cx="0" cy="0"/></g>' +
      '<rect x="' + padL + '" y="' + padT + '" width="' + iw + '" height="' + ih + '" fill="transparent" class="zona"/></svg>';
    const viejo = el.querySelector('svg'); if (viejo) viejo.remove();
    el.insertAdjacentHTML('afterbegin', s);
    const svg = el.querySelector('svg'), lect = svg.querySelector('.lectura'), guia = lect.querySelector('.guia'), pto = lect.querySelector('.punto'), t = tip(el);
    const mover = (cx) => {
      const r = svg.getBoundingClientRect();
      const px = ((cx - r.left) / r.width) * W;
      const i = Math.max(0, Math.min(n - 1, Math.round(n <= 1 ? 0 : ((px - padL) / iw) * (n - 1))));
      const xx = x(i), yy = y(o.series[0].datos[i]);
      guia.setAttribute('x1', xx); guia.setAttribute('x2', xx); pto.setAttribute('cx', xx); pto.setAttribute('cy', yy); lect.style.opacity = '1';
      t.innerHTML = '<span class="t">' + esc(o.etiquetaTip ? o.etiquetaTip(i) : fechaLarga(o.etiquetas[i])) + '</span>' +
        o.series.map((se) => '<div><i style="background:' + (se.clase === 'comp' ? '#8FA3C4' : se.clase === 'sec' ? '#2F4A7A' : '#fff') + '"></i>' + esc(se.nombre) + ': <b>' + esc(fmt(se.datos[i])) + '</b></div>').join('');
      t.style.left = Math.min(88, Math.max(12, (xx / W) * 100)) + '%'; t.style.top = (yy / alto) * r.height + 'px'; t.classList.add('visible');
    };
    const salir = () => { t.classList.remove('visible'); lect.style.opacity = '0'; };
    const zona = svg.querySelector('.zona');
    zona.addEventListener('mousemove', (e) => mover(e.clientX));
    zona.addEventListener('mouseleave', salir);
    zona.addEventListener('touchstart', (e) => mover(e.touches[0].clientX), { passive: true });
    zona.addEventListener('touchmove', (e) => mover(e.touches[0].clientX), { passive: true });
  });
}

/** Barras verticales. o = { datos:[{et, v, clase, tip}], formato, alto } */
export function grafBarras(el, o) {
  el.classList.add('mt-chart');
  const alto = o.alto || 200, padL = 40, padR = 6, padT = 10, padB = 24;
  const fmt = o.formato || num;
  const n = o.datos.length;
  const esc_ = escalaBonita(Math.max(0, ...o.datos.map((d) => Number(d.v) || 0)), o.datos.every((d) => Number.isInteger(Number(d.v))));
  alAncho(el, (W) => {
    const iw = W - padL - padR, ih = alto - padT - padB, paso = iw / n, bw = Math.max(2, Math.min(34, paso * 0.64));
    const y = (v) => padT + ih - (ih * (Number(v) || 0)) / esc_.max;
    const cada = Math.max(1, Math.ceil(n / Math.max(2, Math.floor(iw / 34))));
    let s = '<svg viewBox="0 0 ' + W + ' ' + alto + '" height="' + alto + '" role="img" aria-label="' + esc(o.aria || 'Gráfica de barras') + '">';
    esc_.pasos.forEach((v) => { s += '<line class="rejilla" x1="' + padL + '" x2="' + (W - padR) + '" y1="' + y(v) + '" y2="' + y(v) + '"/><text class="lbl" x="' + (padL - 7) + '" y="' + (y(v) + 4) + '" text-anchor="end">' + esc(o.formatoEje ? o.formatoEje(v) : fmt(v)) + '</text>'; });
    o.datos.forEach((d, i) => {
      const cx = padL + paso * i + paso / 2, yy = y(d.v), h = padT + ih - yy;
      s += '<rect class="barra ' + (d.clase || '') + '" data-b="' + i + '" x="' + (cx - bw / 2) + '" y="' + (h > 0 ? yy : padT + ih - 1) + '" width="' + bw + '" height="' + Math.max(1, h) + '" rx="' + Math.min(4, bw / 3) + '"/>' +
        '<rect class="col" data-i="' + i + '" x="' + (padL + paso * i) + '" y="' + padT + '" width="' + paso + '" height="' + ih + '" fill="transparent"/>';
      if (i % cada === 0) s += '<text class="lbl" x="' + cx + '" y="' + (alto - 7) + '" text-anchor="middle">' + esc(d.et) + '</text>';
    });
    s += '</svg>';
    const viejo = el.querySelector('svg'); if (viejo) viejo.remove();
    el.insertAdjacentHTML('afterbegin', s);
    const t = tip(el), svg = el.querySelector('svg');
    svg.querySelectorAll('.col').forEach((col) => {
      const i = Number(col.dataset.i), b = svg.querySelector('[data-b="' + i + '"]');
      const ver = () => {
        const d = o.datos[i], r = svg.getBoundingClientRect(), bx = Number(b.getAttribute('x')) + Number(b.getAttribute('width')) / 2;
        t.innerHTML = d.tip || ('<span class="t">' + esc(d.et) + '</span><b>' + esc(fmt(d.v)) + '</b>');
        t.style.left = Math.min(92, Math.max(8, (bx / W) * 100)) + '%'; t.style.top = (Number(b.getAttribute('y')) / alto) * r.height + 'px'; t.classList.add('visible');
        svg.querySelectorAll('.barra').forEach((x) => { x.style.opacity = x === b ? '1' : '.55'; });
      };
      col.addEventListener('mouseenter', ver); col.addEventListener('touchstart', ver, { passive: true });
      col.addEventListener('mouseleave', () => { t.classList.remove('visible'); svg.querySelectorAll('.barra').forEach((x) => { x.style.opacity = ''; }); });
    });
  });
}

/** Barras horizontales (ranking). items = [{n, v, sub, ico}] */
export function filas(items, { formato = num, max } = {}) {
  if (!items.length) return '';
  const m = max || Math.max(...items.map((x) => Number(x.v) || 0), 1);
  return '<ul class="mt-filas">' + items.map((x) =>
    '<li class="mt-fila"><span class="n" title="' + esc(x.n) + '">' + (x.ico || '') + esc(x.n) + '</span><span class="v">' + esc(formato(x.v)) + (x.sub ? '<small>' + esc(x.sub) + '</small>' : '') + '</span>' +
    '<span class="b"><span style="width:' + Math.max(2, (100 * (Number(x.v) || 0)) / m) + '%"></span></span></li>').join('') + '</ul>';
}

const PALETA = ['#101C33', '#2F4A7A', '#5B76A6', '#8FA3C4', '#C7D2E3', '#A6332E', '#C28A3A'];
/** Reparto en una barra + leyenda. items = [{n, v}] */
export function reparto(items, { formato = num } = {}) {
  const tot = items.reduce((a, x) => a + (Number(x.v) || 0), 0);
  if (!tot) return '';
  return '<div class="mt-reparto" role="img" aria-label="Reparto">' + items.map((x, i) => '<span style="width:' + (100 * x.v) / tot + '%;background:' + PALETA[i % PALETA.length] + '" title="' + esc(x.n) + '"></span>').join('') + '</div>' +
    '<div class="mt-reparto-ley">' + items.map((x, i) => '<div><i style="background:' + PALETA[i % PALETA.length] + '"></i>' + (x.ico || '') + esc(x.n) + '<b>' + esc(formato(x.v)) + '</b><small>' + pct(x.v, tot) + '%</small></div>').join('') + '</div>';
}

/** Mapa de calor dia (1..7, ISO) x hora (0..23). celdas = [{d, h, n}] */
export function calor(celdas, { unidad = '' } = {}) {
  const m = {}; let max = 0;
  celdas.forEach((c) => { m[c.d + '-' + c.h] = c.n; max = Math.max(max, c.n); });
  const col = (v) => {
    if (!v) return 'background:#EEF1F6';
    const t = v / max;
    return 'background:rgba(16,28,51,' + (0.14 + 0.86 * t).toFixed(3) + ')';
  };
  let s = '<div class="mt-calor" role="img" aria-label="Mapa de calor por día y hora"><span></span>';
  for (let h = 0; h < 24; h++) s += '<span class="h">' + (h % 3 === 0 ? h : '') + '</span>';
  for (let d = 1; d <= 7; d++) {
    s += '<span class="d">' + DIAS[d - 1] + '</span>';
    for (let h = 0; h < 24; h++) { const v = m[d + '-' + h] || 0; s += '<span class="c" style="' + col(v) + '" title="' + DIAS_LARGOS[d - 1] + ' ' + h + ':00 · ' + v + (unidad ? ' ' + unidad : '') + '"></span>'; }
  }
  return s + '</div><div class="mt-calor-ley">Menos<span style="background:#EEF1F6"></span><span style="background:rgba(16,28,51,.35)"></span><span style="background:rgba(16,28,51,.65)"></span><span style="background:#101C33"></span>Más</div>';
}

/** Embudo. pasos = [{et, sub, v}] (el primero es la base) */
export function embudo(pasos) {
  const base = Number(pasos[0]?.v) || 0;
  return '<div class="mt-embudo">' + pasos.map((p, i) => {
    const prev = i ? Number(pasos[i - 1].v) || 0 : 0;
    return (i ? '<div class="mt-conv">↳ <b>' + pct(p.v, prev) + '%</b> del paso anterior</div>' : '') +
      '<div class="mt-paso"><span class="et">' + esc(p.et) + (p.sub ? '<small>' + esc(p.sub) + '</small>' : '') + '</span>' +
      '<span class="bar"><span style="width:' + (base ? Math.max(1.5, (100 * p.v) / base) : 0) + '%"></span></span>' +
      '<span class="num">' + num(p.v) + '<small>' + pct(p.v, base) + '%</small></span></div>';
  }).join('') + '</div>';
}

/** Sparklines declarados con data-spark en los KPI. */
export function pintarSparks(raiz) {
  raiz.querySelectorAll('[data-spark]').forEach((el) => {
    const v = JSON.parse(el.dataset.spark || '[]').map(Number);
    if (v.length < 2) { el.remove(); return; }
    const W = 200, H = 30, max = Math.max(...v, 1);
    const pts = v.map((x, i) => [(W * i) / (v.length - 1), H - 3 - ((H - 6) * x) / max]);
    const d = pts.map((p, i) => (i ? 'L' : 'M') + p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join(' ');
    const claro = el.closest('.destacado');
    el.innerHTML = '<svg viewBox="0 0 ' + W + ' ' + H + '" preserveAspectRatio="none" aria-hidden="true"><path d="' + d + ' L' + W + ' ' + H + ' L0 ' + H + ' Z" fill="' + (claro ? 'rgba(255,255,255,.12)' : 'rgba(16,28,51,.07)') + '"/>' +
      '<path d="' + d + '" fill="none" stroke="' + (claro ? '#fff' : '#101C33') + '" stroke-width="1.6" vector-effect="non-scaling-stroke"/></svg>';
  });
}

// ------------------------------------------------------------
// Periodos
// ------------------------------------------------------------
export const PERIODOS = [
  { id: '7', txt: '7 días', dias: 7 }, { id: '30', txt: '30 días', dias: 30 },
  { id: '90', txt: '90 días', dias: 90 }, { id: '365', txt: '12 meses', dias: 365 },
];
export function rangoDe(id) { const p = PERIODOS.find((x) => x.id === id) || PERIODOS[1]; return { desde: hoyLocal(-(p.dias - 1)), hasta: hoyLocal(0), p }; }
export function chipsPeriodo(actual) {
  return '<div class="mt-chips" role="group" aria-label="Periodo">' + PERIODOS.map((p) => '<button type="button" class="mt-chip" data-periodo="' + p.id + '" aria-pressed="' + (p.id === actual) + '">' + p.txt + '</button>').join('') + '</div>';
}
export const ORIGENES = { directo: 'Directo', email: 'Correos de campaña', instagram: 'Instagram', facebook: 'Facebook', whatsapp: 'WhatsApp', buscador: 'Buscadores', otro_sitio: 'Otros sitios' };
export const DISPOSITIVOS = { movil: 'Celular', pc: 'Computador', tablet: 'Tablet' };
export const CANALES = { manual: 'Registro manual', web: 'Tienda web' };
