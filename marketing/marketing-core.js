// ============================================================
//  MAGANDHI · AREA DE MARKETING · Nucleo compartido (marketing-core.js)
//  ------------------------------------------------------------
//  Utilidades reutilizadas por todas las paginas del Area de Marketing y de
//  su sub-area Marketing Project. Espejo de finanzas-core.js / inventario-core.js:
//  mismo estandar de calidad, mismo header institucional AZUL MARINO, mismo
//  sello "Con tecnologia Impulse" al pie, wordmark MAGANDHI.
//
//  SIN COLOR NUEVO (decision del dueno): esta area HEREDA el azul marino
//  #101C33 del back-office; se diferencia de Finanzas y de Produccion por el
//  LAYOUT (dashboard de analisis: panel de controles + numero grande + grafico
//  + tabla de detalle), no por un color propio. El verde ya es de Finanzas.
//
//  PROFUNDIDAD DE IMPORTS (por que un solo core en marketing/):
//  Este archivo vive en marketing/, un nivel bajo la raiz, asi que importa el
//  cliente unico y el guardia con '../supabase-config.js' / '../auth-guard.js'.
//  Los imports de un modulo ES se resuelven SIEMPRE relativos al archivo que
//  los declara (este core), NO relativos a la pagina que lo importa. Por eso
//  una sola copia en marketing/ sirve tanto a marketing/index.html (que la
//  importa como './marketing-core.js') como a
//  marketing/marketing-project/*.html (que la importa como
//  '../marketing-core.js'): en ambos casos, cuando el core hace
//  '../supabase-config.js', la ruta se calcula desde marketing/ y apunta bien
//  a la raiz. No se duplica el nucleo.
//
//  Recordatorio de seguridad: ocultar UI es solo comodidad de UX. El candado
//  real es RLS server-side (tiene_modulo(...)); ver la nota de estrategia de
//  lectura en proyeccion-demanda.html.
// ============================================================

import { supabase } from '../supabase-config.js';
import { exigirSesion, obtenerPerfil } from '../auth-guard.js';

// Reexportamos para que las paginas importen todo desde un solo lugar.
export { supabase, exigirSesion, obtenerPerfil };

// ------------------------------------------------------------
// SANEAMIENTO
// ------------------------------------------------------------

/**
 * Escapa texto para insertarlo de forma segura via innerHTML (anti-XSS
 * almacenado al pintar nombre/SKU de producto, etiquetas, etc. que puedan
 * venir de datos escritos por el operador).
 * @param {*} s
 * @returns {string}
 */
export function escaparHTML(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/**
 * Formatea un numero a un entero con puntos de miles (1200 -> "1.200"). Las
 * cantidades del libro son unidades enteras; la proyeccion se muestra
 * redondeada a la unidad. No agrega simbolo.
 * @param {number} n
 * @returns {string}
 */
export function formatearNumero(n) {
  const x = Math.round(Number(n) || 0);
  const signo = x < 0 ? '-' : '';
  return signo + Math.abs(x).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.');
}

// ------------------------------------------------------------
// ACCESO AL AREA
// ------------------------------------------------------------

/**
 * True si el perfil puede usar el Area de Marketing / Marketing Project: admin
 * ve todo; otros solo si su lista de modulos incluye 'marketing' o
 * 'marketing-project'. El candado real es RLS; esto es comodidad de UX.
 * @param {{rol?:string, modulos?:string[]}|null} perfil
 * @returns {boolean}
 */
export function tieneAccesoMarketing(perfil) {
  if (!perfil) return false;
  if (perfil.rol === 'admin') return true;
  const modulos = Array.isArray(perfil.modulos) ? perfil.modulos : [];
  return modulos.includes('marketing') || modulos.includes('marketing-project');
}

/**
 * Asegura sesion + acceso al area. Sin sesion, exigirSesion ya redirige al
 * login. Con sesion pero sin acceso, pinta el aviso de denegado dentro de
 * `contenedor` (si se pasa) y devuelve null. Devuelve { sesion, perfil }
 * cuando el acceso es correcto.
 * @param {HTMLElement} [contenedor] donde mostrar el aviso de denegado
 * @param {string} [volverHref] destino del enlace del aviso (default ../panel.html)
 * @returns {Promise<{sesion:object, perfil:object}|null>}
 */
export async function asegurarAcceso(contenedor, volverHref) {
  const sesion = await exigirSesion();
  if (!sesion) return null; // auth-guard ya redirige al login

  let perfil = null;
  try {
    perfil = await obtenerPerfil();
  } catch (_) {
    perfil = null;
  }

  if (!tieneAccesoMarketing(perfil)) {
    if (contenedor) {
      const href = volverHref || '../panel.html';
      contenedor.innerHTML =
        '<div class="mk-denegado">' +
          '<h2>Acceso restringido</h2>' +
          '<p>Tu cuenta no tiene habilitada el <strong>Área de Marketing</strong>. ' +
          'Solicita el acceso a un administrador.</p>' +
          '<p style="margin-top:14px"><a href="' + escaparHTML(href) + '">Volver al panel</a></p>' +
        '</div>';
    }
    return null;
  }

  return { sesion, perfil };
}

// ------------------------------------------------------------
// ICONOS (SVG inline consistentes con el set de Finanzas + los del area)
// ------------------------------------------------------------
export const ICONOS = {
  lupa: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>',
  info: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/></svg>',
  lista: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/></svg>',
  // megafono: identifica el Area de Marketing.
  megafono: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m3 11 18-5v12L3 14v-3Z"/><path d="M11.6 16.8a3 3 0 1 1-5.8-1.6"/></svg>',
  // grafico: proyeccion de la demanda (barras + linea de tendencia).
  grafico: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3v18h18"/><path d="M7 16v-4M12 16V8M17 16v-7"/></svg>',
  // tendencia: linea ascendente (Marketing Project como carpeta de analisis).
  tendencia: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3v18h18"/><path d="m7 15 4-4 3 3 5-6"/><path d="M19 8h-3M19 8v3"/></svg>',
  // cluster: nodos conectados (analisis cluster futuro).
  cluster: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="6" cy="6" r="2.5"/><circle cx="18" cy="7" r="2.5"/><circle cx="9" cy="18" r="2.5"/><path d="M8 7.5 15.5 8M8 16l1-7M11 17l6-8"/></svg>',
  // brujula: oportunidades de mercado / "cosas que podria estar ignorando".
  brujula: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="m16.2 7.8-2.9 6.4-6.4 2.9 2.9-6.4 6.4-2.9Z"/></svg>',
  // etiqueta: elasticidad (precio) futura.
  etiqueta: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12.586 2.586A2 2 0 0 0 11.172 2H4a2 2 0 0 0-2 2v7.172a2 2 0 0 0 .586 1.414l8.704 8.704a2.426 2.426 0 0 0 3.42 0l6.58-6.58a2.426 2.426 0 0 0 0-3.42Z"/><circle cx="7.5" cy="7.5" r="1.5"/></svg>'
};

// Iconos extra para navegacion / perfil (flecha de retroceso, salir).
ICONOS.flecha = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>';
ICONOS.salir = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5M21 12H9"/></svg>';

// ------------------------------------------------------------
// HEADER INSTITUCIONAL
// ------------------------------------------------------------

/**
 * Calcula la ruta relativa a la RAIZ del sitio (donde vive index.html =
 * login) contando los segmentos de carpeta del pathname actual. Asi el
 * logout redirige bien tanto desde marketing/*.html ('../') como desde
 * marketing/marketing-project/*.html ('../../'). Fallback prudente: '../'.
 * @returns {string} prefijo '../' repetido hasta la raiz
 */
export function rutaRaiz() {
  try {
    const partes = window.location.pathname.split('/').filter(Boolean);
    // El ultimo segmento es el archivo .html; las carpetas por encima definen
    // cuantos '../' hay que subir. GitHub Pages sirve desde la raiz del repo.
    const carpetas = Math.max(partes.length - 1, 0);
    return carpetas > 0 ? '../'.repeat(carpetas) : './';
  } catch (_) {
    return '../';
  }
}

/**
 * Monta el header institucional fijo (azul marino) al inicio de <body>,
 * seguido del encabezado editorial (titulo + kicker + lead) y del sello
 * Impulse al pie. Espejo del header de Finanzas / Produccion: mismo wordmark
 * MAGANDHI, boton volver con destino EXPLICITO (nunca history.back()), avatar
 * con menu de perfil (correo + Cerrar sesion via supabase.auth.signOut).
 *
 * @param {object} opts
 * @param {string} opts.titulo     Titulo editorial de la pantalla.
 * @param {string} opts.kicker     Kicker en terracota (mayusculas).
 * @param {string} [opts.lead]     Parrafo introductorio opcional.
 * @param {object} [opts.sesion]   Sesion (para inicial del avatar y correo).
 * @param {string} [opts.areaLabel] Rotulo del header (default 'ÁREA DE MARKETING').
 * @param {string} [opts.volverHref] Destino del boton volver (default index.html).
 * @param {string} [opts.volverTexto] Etiqueta del boton volver (default 'Marketing').
 * @param {string} [opts.logoSrc]  Ruta al logo (default segun profundidad).
 */
export function montarHeader(opts) {
  const { titulo, kicker, lead, sesion, areaLabel, volverHref, volverTexto, logoSrc } = opts || {};
  const email = sesion?.user?.email || '';
  const inicial = (email.trim()[0] || 'M').toUpperCase();
  const raiz = rutaRaiz();
  const hrefVolver = volverHref || 'index.html';
  const txtVolver = volverTexto || 'Marketing';
  const rotulo = areaLabel || 'ÁREA DE MARKETING';
  const logo = logoSrc || (raiz + 'logo-mark-terracota.png');

  const header = document.createElement('header');
  header.className = 'mk-header';
  header.innerHTML =
    '<div class="mk-header-left">' +
      '<a class="mk-volver" href="' + escaparHTML(hrefVolver) + '" aria-label="Volver a ' + escaparHTML(txtVolver) + '">' +
        ICONOS.flecha +
        '<span>' + escaparHTML(txtVolver) + '</span>' +
      '</a>' +
      '<span class="mk-sep" aria-hidden="true"></span>' +
      '<img class="mk-logo" src="' + escaparHTML(logo) + '" alt="Magandhi">' +
      '<span class="mk-word">MAGANDHI</span>' +
      '<span class="mk-sep" aria-hidden="true"></span>' +
      '<span class="mk-area">' + escaparHTML(rotulo) + '</span>' +
    '</div>' +
    '<div class="mk-header-right">' +
      '<div class="mk-perfil">' +
        '<button class="mk-avatar" id="mk-avatar" type="button" ' +
          'aria-haspopup="menu" aria-expanded="false" aria-controls="mk-perfil-menu" ' +
          'title="' + escaparHTML(email) + '" aria-label="Menu de perfil">' + escaparHTML(inicial) + '</button>' +
        '<div class="mk-perfil-menu" id="mk-perfil-menu" role="menu" aria-label="Perfil" hidden>' +
          '<div class="mk-perfil-info">' +
            '<span class="mk-perfil-lbl">Sesion iniciada como</span>' +
            '<span class="mk-perfil-email">' + escaparHTML(email || 'usuario interno') + '</span>' +
          '</div>' +
          '<button class="mk-perfil-salir" id="mk-perfil-salir" type="button" role="menuitem">' +
            ICONOS.salir + '<span>Cerrar sesion</span>' +
          '</button>' +
        '</div>' +
      '</div>' +
    '</div>';

  const screenHead = document.createElement('div');
  screenHead.className = 'mk-screen-head';
  screenHead.innerHTML =
    '<p class="mk-kicker">' + escaparHTML(kicker || '') + '</p>' +
    '<h1 class="mk-title">' + escaparHTML(titulo || '') + '</h1>' +
    (lead ? '<p class="mk-lead">' + escaparHTML(lead) + '</p>' : '');

  document.body.insertBefore(screenHead, document.body.firstChild);
  document.body.insertBefore(header, document.body.firstChild);

  montarMenuPerfil(header, raiz);
  montarSelloImpulse();
}

/**
 * Cablea el menu de perfil del avatar: abrir/cerrar, cerrar al hacer clic
 * afuera o con Escape, accesibilidad y "Cerrar sesion" (mismo patron que
 * panel.html: supabase.auth.signOut() + redirect al login de la raiz).
 * @param {HTMLElement} header
 * @param {string} raiz prefijo relativo a la raiz del sitio
 */
function montarMenuPerfil(header, raiz) {
  const avatar = header.querySelector('#mk-avatar');
  const menu = header.querySelector('#mk-perfil-menu');
  const salir = header.querySelector('#mk-perfil-salir');
  if (!avatar || !menu) return;

  const abrir = () => {
    menu.hidden = false;
    avatar.setAttribute('aria-expanded', 'true');
    salir?.focus();
  };
  const cerrar = (devolverFoco) => {
    menu.hidden = true;
    avatar.setAttribute('aria-expanded', 'false');
    if (devolverFoco) avatar.focus();
  };
  const estaAbierto = () => avatar.getAttribute('aria-expanded') === 'true';

  avatar.addEventListener('click', (e) => {
    e.stopPropagation();
    estaAbierto() ? cerrar(false) : abrir();
  });
  document.addEventListener('click', (e) => {
    if (estaAbierto() && !menu.contains(e.target) && e.target !== avatar) cerrar(false);
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && estaAbierto()) cerrar(true);
  });

  salir?.addEventListener('click', async () => {
    try { await supabase.auth.signOut(); } catch (_) { /* ignorar */ }
    window.location.replace(raiz + 'index.html');
  });
}

// ------------------------------------------------------------
// SELLO DE PROVEEDOR ("Con tecnologia Impulse")
// ------------------------------------------------------------

/**
 * Inserta el sello discreto "Con tecnologia Impulse" al final del <body>.
 * Idempotente. Solo back-office interno; nunca la tienda publica.
 */
export function montarSelloImpulse() {
  if (document.querySelector('.mk-sello')) return;
  const foot = document.createElement('footer');
  foot.className = 'mk-sello';
  foot.innerHTML = 'Con tecnología <span class="mk-sello-marca">Impulse</span>';
  document.body.appendChild(foot);
}

// ------------------------------------------------------------
// FECHAS
// ------------------------------------------------------------

/**
 * Fecha de hoy en formato YYYY-MM-DD (zona local) para inputs date y kickers.
 * @returns {string}
 */
export function hoyISO() {
  const d = new Date();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${d.getFullYear()}-${mm}-${dd}`;
}

/**
 * Formatea una fecha ISO (YYYY-MM-DD) a un texto legible en espanol corto,
 * evitando desfases de zona (se interpreta como fecha local, no UTC).
 * @param {string} iso
 * @returns {string}
 */
export function formatearFecha(iso) {
  if (!iso) return '';
  const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number);
  if (!y || !m || !d) return String(iso);
  const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  return `${String(d).padStart(2, '0')} ${meses[m - 1]} ${y}`;
}

// ============================================================
//  MOTOR DE PROYECCION DE LA DEMANDA (matematica pura, sin DOM)
//  ------------------------------------------------------------
//  Funciones puras y testeables: reciben arreglos de numeros (las cantidades
//  vendidas por periodo, ya agrupadas) y devuelven la proyeccion. No tocan la
//  red ni el DOM, para poder verificarlas contra un ejemplo a mano (ver el
//  bloque AUTO-CHEQUEO al final de este archivo y en proyeccion-demanda.html).
//
//  Todas trabajan sobre "buckets": un arreglo ordenado cronologicamente donde
//  cada elemento es la CANTIDAD total vendida (unidades enteras del libro,
//  tipo='salida') en ese periodo. La proyeccion es a `horizonte` periodos
//  hacia adelante.
// ============================================================

/**
 * (a) PROMEDIO MOVIL — media de los ultimos N buckets.
 * La proyeccion de cada periodo futuro es la media de las ultimas `ventana`
 * observaciones reales; es un valor PLANO (misma cifra en todo el horizonte),
 * que es la definicion clasica del pronostico por promedio movil simple.
 *
 * @param {number[]} serie  cantidades por periodo (cronologico)
 * @param {number} ventana  N periodos hacia atras a promediar (>=1)
 * @param {number} horizonte periodos a proyectar hacia adelante (>=1)
 * @returns {number[]} proyeccion de longitud `horizonte`
 */
export function promedioMovil(serie, ventana, horizonte) {
  const s = (serie || []).map((x) => Number(x) || 0);
  const N = Math.max(1, Math.min(Math.trunc(ventana) || 1, s.length || 1));
  const H = Math.max(1, Math.trunc(horizonte) || 1);
  if (!s.length) return new Array(H).fill(0);
  const ultimos = s.slice(-N);
  const media = ultimos.reduce((a, b) => a + b, 0) / ultimos.length;
  return new Array(H).fill(media);
}

/**
 * (b) SUAVIZACION EXPONENCIAL SIMPLE — recurrencia S_t = alpha*x_t + (1-alpha)*S_{t-1}.
 * Se inicializa S_0 = x_0 (primera observacion) y se recorre la serie. El
 * pronostico para todo el horizonte es el ultimo nivel suavizado S_n (metodo
 * de nivel, sin tendencia), que es plano hacia adelante — el comportamiento
 * estandar de la suavizacion exponencial simple.
 *
 * @param {number[]} serie cantidades por periodo (cronologico)
 * @param {number} alpha   factor de suavizado en (0,1]
 * @param {number} horizonte periodos a proyectar
 * @returns {{ suavizada:number[], proyeccion:number[] }}
 *   suavizada = la serie de niveles S_t (para dibujar el ajuste sobre el pasado);
 *   proyeccion = arreglo de longitud `horizonte` (constante = S_n).
 */
export function suavizacionExponencial(serie, alpha, horizonte) {
  const s = (serie || []).map((x) => Number(x) || 0);
  const a = Math.min(Math.max(Number(alpha) || 0, 0.0001), 1);
  const H = Math.max(1, Math.trunc(horizonte) || 1);
  if (!s.length) return { suavizada: [], proyeccion: new Array(H).fill(0) };
  const suavizada = [s[0]];
  for (let t = 1; t < s.length; t++) {
    suavizada.push(a * s[t] + (1 - a) * suavizada[t - 1]);
  }
  const nivel = suavizada[suavizada.length - 1];
  return { suavizada, proyeccion: new Array(H).fill(nivel) };
}

/**
 * (c) REGRESION LINEAL POR MINIMOS CUADRADOS — ajusta y = intercepto + pendiente*x
 * con x = indice del periodo (0,1,2,...) usando las sumatorias clasicas:
 *   pendiente = (n*Sxy - Sx*Sy) / (n*Sxx - Sx^2)
 *   intercepto = (Sy - pendiente*Sx) / n
 * y extrapola la recta a los periodos futuros x = n, n+1, ..., n+horizonte-1.
 * Las proyecciones se piso-limitan a 0 (una demanda negativa no tiene sentido
 * fisico; la recta puede bajar de 0 y se recorta al mostrar).
 *
 * @param {number[]} serie cantidades por periodo (cronologico)
 * @param {number} horizonte periodos a proyectar
 * @returns {{ pendiente:number, intercepto:number, ajuste:number[], proyeccion:number[] }}
 *   ajuste = valores de la recta sobre el pasado (x=0..n-1), para dibujar la
 *            linea de tendencia; proyeccion = valores sobre x=n..n+H-1.
 */
export function regresionLineal(serie, horizonte) {
  const s = (serie || []).map((x) => Number(x) || 0);
  const H = Math.max(1, Math.trunc(horizonte) || 1);
  const n = s.length;
  if (n === 0) return { pendiente: 0, intercepto: 0, ajuste: [], proyeccion: new Array(H).fill(0) };
  if (n === 1) {
    // Con una sola observacion no hay pendiente definible: recta plana.
    return { pendiente: 0, intercepto: s[0], ajuste: [s[0]], proyeccion: new Array(H).fill(Math.max(0, s[0])) };
  }
  let Sx = 0, Sy = 0, Sxy = 0, Sxx = 0;
  for (let i = 0; i < n; i++) {
    Sx += i; Sy += s[i]; Sxy += i * s[i]; Sxx += i * i;
  }
  const denom = n * Sxx - Sx * Sx;
  const pendiente = denom === 0 ? 0 : (n * Sxy - Sx * Sy) / denom;
  const intercepto = (Sy - pendiente * Sx) / n;
  const recta = (x) => intercepto + pendiente * x;
  const ajuste = [];
  for (let i = 0; i < n; i++) ajuste.push(recta(i));
  const proyeccion = [];
  for (let k = 0; k < H; k++) proyeccion.push(Math.max(0, recta(n + k)));
  return { pendiente, intercepto, ajuste, proyeccion };
}

// ------------------------------------------------------------
// BUCKETING POR PERIODO (agrupa las salidas del libro por dia/semana/mes)
// ------------------------------------------------------------

/**
 * Devuelve la clave de periodo de una fecha ISO segun la granularidad:
 *   'dia'    -> 'YYYY-MM-DD'
 *   'semana' -> 'YYYY-Www' (semana ISO, lunes como inicio)
 *   'mes'    -> 'YYYY-MM'
 * Se interpreta la fecha como local (sin desfase de zona).
 * @param {string} iso  fecha YYYY-MM-DD
 * @param {'dia'|'semana'|'mes'} granularidad
 * @returns {string} clave de bucket
 */
export function clavePeriodo(iso, granularidad) {
  const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number);
  if (!y || !m || !d) return String(iso).slice(0, 10);
  if (granularidad === 'mes') {
    return `${y}-${String(m).padStart(2, '0')}`;
  }
  if (granularidad === 'semana') {
    // Semana ISO 8601: jueves de la misma semana define el ano/semana.
    const fecha = new Date(Date.UTC(y, m - 1, d));
    const dia = fecha.getUTCDay() || 7; // domingo(0) -> 7
    fecha.setUTCDate(fecha.getUTCDate() + 4 - dia);
    const inicioAnio = new Date(Date.UTC(fecha.getUTCFullYear(), 0, 1));
    const semana = Math.ceil((((fecha - inicioAnio) / 86400000) + 1) / 7);
    return `${fecha.getUTCFullYear()}-W${String(semana).padStart(2, '0')}`;
  }
  // dia (default)
  return `${y}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;
}

/**
 * Agrupa un arreglo de movimientos {fecha, cantidad} en buckets cronologicos
 * segun la granularidad, sumando cantidades por periodo. Devuelve un arreglo
 * ordenado de { clave, cantidad } donde cantidad es la suma de unidades del
 * periodo. NO rellena periodos sin ventas con ceros (solo periodos con
 * movimiento real); es la serie que alimentan los tres metodos.
 * @param {Array<{fecha:string, cantidad:number}>} movimientos
 * @param {'dia'|'semana'|'mes'} granularidad
 * @returns {Array<{clave:string, cantidad:number}>}
 */
export function agruparPorPeriodo(movimientos, granularidad) {
  const mapa = new Map();
  for (const mv of (movimientos || [])) {
    const clave = clavePeriodo(mv.fecha, granularidad);
    const cant = Math.trunc(Number(mv.cantidad) || 0);
    mapa.set(clave, (mapa.get(clave) || 0) + cant);
  }
  return [...mapa.entries()]
    .map(([clave, cantidad]) => ({ clave, cantidad }))
    .sort((a, b) => (a.clave < b.clave ? -1 : a.clave > b.clave ? 1 : 0));
}

// ============================================================
//  AUTO-CHEQUEO DE LOS TRES METODOS (verificacion a mano)
//  ------------------------------------------------------------
//  Un revisor puede confirmar la correccion de la matematica con un ejemplo
//  de entrada FIJA. Serie de ejemplo: [10, 20, 30, 40] (4 periodos).
//
//  (a) PROMEDIO MOVIL, ventana=2, horizonte=3:
//      ultimos 2 buckets = [30, 40] -> media = 35.
//      => proyeccion = [35, 35, 35].  (plano)
//
//  (b) SUAVIZACION EXPONENCIAL, alpha=0.5:
//      S0 = 10
//      S1 = 0.5*20 + 0.5*10 = 15
//      S2 = 0.5*30 + 0.5*15 = 22.5
//      S3 = 0.5*40 + 0.5*22.5 = 31.25
//      => nivel = 31.25; proyeccion (horizonte 3) = [31.25, 31.25, 31.25].
//
//  (c) REGRESION LINEAL sobre x=0,1,2,3 ; y=10,20,30,40:
//      n=4, Sx=6, Sy=100, Sxy=0*10+1*20+2*30+3*40=200, Sxx=0+1+4+9=14
//      pendiente = (4*200 - 6*100) / (4*14 - 36) = (800-600)/(56-36)=200/20=10
//      intercepto = (100 - 10*6)/4 = (100-60)/4 = 10
//      recta(x) = 10 + 10x  ->  x=4:50, x=5:60, x=6:70
//      => proyeccion (horizonte 3) = [50, 60, 70].
//
//  Estas cifras estan verificadas a mano y coinciden con la implementacion de
//  arriba. Se pueden re-ejecutar en la consola importando este modulo:
//    promedioMovil([10,20,30,40], 2, 3)              -> [35, 35, 35]
//    suavizacionExponencial([10,20,30,40], 0.5, 3)   -> proyeccion [31.25,...]
//    regresionLineal([10,20,30,40], 3)               -> proyeccion [50, 60, 70]
// ============================================================
