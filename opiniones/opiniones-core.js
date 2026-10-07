// ============================================================
//  MAGANDHI · GESTION DE OPINIONES · Nucleo compartido (opiniones-core.js)
//  ------------------------------------------------------------
//  Utilidades reutilizadas por las paginas del area Gestion de opiniones
//  (listado de productos con reseña + detalle de un producto). Espejo de
//  ventas-core.js / finanzas-core.js / inventario-core.js: mismo estandar de
//  calidad, mismo header institucional AZUL MARINO, mismo sello "Con tecnologia
//  Impulse" al pie, wordmark MAGANDHI.
//
//  SIN COLOR NUEVO (decision del dueno, igual que Ventas): esta area HEREDA el
//  azul marino #101C33 del back-office. El verde ya es de Finanzas; aqui NO se
//  estrena un color propio. "No quiero un arcoiris". El UNICO acento calido es
//  el DORADO oficial de marca (--acento, de marca.css) en las ESTRELLAS, porque
//  la estrella dorada es el lenguaje universal de una calificacion.
//
//  PROFUNDIDAD DE IMPORTS: este archivo vive en opiniones/, un nivel bajo la
//  raiz, asi que importa el cliente unico y el guardia con '../'. Los imports de
//  un modulo ES se resuelven relativos a ESTE archivo, no a la pagina que lo
//  importa, por eso una sola copia sirve a opiniones/index.html (./) y a
//  opiniones/producto.html (./) por igual.
//
//  SEGURIDAD: ocultar UI es solo comodidad de UX. El candado real es RLS +
//  funciones security definer guardadas por tiene_acceso_opiniones() en la
//  base (migracion 20261007000000_opiniones_modulo.sql). La escritura de
//  opiniones solo ocurre por RPC; esta pagina solo responde/oculta via los RPC
//  op_responder_opinion / op_ocultar_opinion (admin con modulo opiniones).
// ============================================================

import { supabase } from '../supabase-config.js';
import { exigirSesion, obtenerPerfil } from '../auth-guard.js';

export { supabase, exigirSesion, obtenerPerfil };

// ------------------------------------------------------------
// SANEAMIENTO (anti-XSS al pintar texto de clientes via innerHTML)
// ------------------------------------------------------------
export function escaparHTML(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ------------------------------------------------------------
// ACCESO AL AREA (espejo de tieneAccesoVentas + wrapper SQL tiene_acceso_opiniones)
// ------------------------------------------------------------
/**
 * True si el perfil puede usar Gestion de opiniones: admin ve todo; otros solo
 * si su lista de modulos incluye 'opiniones'. El candado real es RLS; esto es
 * comodidad de UX.
 * @param {{rol?:string, modulos?:string[]}|null} perfil
 * @returns {boolean}
 */
export function tieneAccesoOpiniones(perfil) {
  if (!perfil) return false;
  if (perfil.rol === 'admin') return true;
  const modulos = Array.isArray(perfil.modulos) ? perfil.modulos : [];
  return modulos.includes('opiniones');
}

/**
 * Asegura sesion + acceso al area. Sin sesion, exigirSesion redirige al login.
 * Con sesion pero sin acceso, pinta el aviso de denegado y devuelve null.
 * @param {HTMLElement} [contenedor]
 * @param {string} [volverHref]
 * @returns {Promise<{sesion:object, perfil:object}|null>}
 */
export async function asegurarAcceso(contenedor, volverHref) {
  const sesion = await exigirSesion();
  if (!sesion) return null;

  let perfil = null;
  try { perfil = await obtenerPerfil(); } catch (_) { perfil = null; }

  if (!tieneAccesoOpiniones(perfil)) {
    if (contenedor) {
      const href = volverHref || '../panel.html';
      contenedor.innerHTML =
        '<div class="op-denegado">' +
          '<h2>Acceso restringido · Gestión de opiniones</h2>' +
          '<p>Tu cuenta no tiene habilitada el área de <strong>Gestión de opiniones</strong>. ' +
          'Solicita el acceso a un administrador.</p>' +
          '<p style="margin-top:14px"><a href="' + escaparHTML(href) + '">Volver al panel</a></p>' +
        '</div>';
    }
    return null;
  }
  return { sesion, perfil };
}

// ------------------------------------------------------------
// ICONOS (SVG inline, heredan currentColor; mismo set/estilo que las otras areas)
// ------------------------------------------------------------
export const ICONOS = {
  // estrella rellena (calificacion) y su contorno (hueco)
  estrella: '<svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="m12 2 3 6.3 6.9 1-5 4.9 1.2 6.8L12 17.8 5.9 21l1.2-6.8-5-4.9 6.9-1z"/></svg>',
  estrellaHueca: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round" aria-hidden="true"><path d="m12 2 3 6.3 6.9 1-5 4.9 1.2 6.8L12 17.8 5.9 21l1.2-6.8-5-4.9 6.9-1z"/></svg>',
  // mensaje: identifica el area (opiniones / voz del cliente)
  mensaje: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/><path d="M8 10h8M8 14h5"/></svg>',
  // responder (flecha de respuesta)
  responder: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 17V11a4 4 0 0 1 4-4h8"/><path d="m21 7-4-4M21 7l-4 4"/></svg>',
  // ojo / ojo tachado (mostrar / ocultar)
  ojo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/></svg>',
  ojoTachado: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9.9 4.24A9.1 9.1 0 0 1 12 4c6.5 0 10 7 10 7a13.2 13.2 0 0 1-2.16 2.88"/><path d="M6.1 6.1C3.3 7.9 2 12 2 12s3.5 7 10 7a9 9 0 0 0 3.9-.86"/><path d="M14.1 14.1a3 3 0 1 1-4.2-4.2"/><path d="m2 2 20 20"/></svg>',
  // info, lupa, flecha, salir, equis, check
  info: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/></svg>',
  lupa: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>',
  check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>',
  checkCirculo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="m9 12 2 2 4-4"/><circle cx="12" cy="12" r="9"/></svg>',
  equis: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18M6 6l12 12"/></svg>',
  flecha: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>',
  flechaDer: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14M13 6l6 6-6 6"/></svg>',
  salir: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5M21 12H9"/></svg>',
  externo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/></svg>'
};

// ------------------------------------------------------------
// ESTRELLAS (render de calificacion con relleno fraccional exacto)
// ------------------------------------------------------------
/**
 * Devuelve el HTML de una fila de 5 estrellas con relleno proporcional al
 * promedio REAL (sin redondear a media): una capa de 5 estrellas huecas y, por
 * encima, 5 estrellas rellenas recortadas al porcentaje promedio/5. Asi "4.8"
 * se ve como 4 estrellas y 8/10 de la quinta, coherente con el numero. Color de
 * relleno: el dorado oficial de marca.
 * @param {number} promedio 0..5
 * @returns {string}
 */
export function estrellasHTML(promedio) {
  const v = Math.max(0, Math.min(5, Number(promedio) || 0));
  const pct = (v / 5) * 100;
  const cinco = (relleno) => (relleno ? ICONOS.estrella : ICONOS.estrellaHueca).repeat(5);
  return (
    '<span class="op-stars" role="img" aria-label="' + v.toFixed(1) + ' de 5 estrellas">' +
      '<span class="op-stars-bg">' + cinco(false) + '</span>' +
      '<span class="op-stars-fg" style="width:' + pct + '%">' + cinco(true) + '</span>' +
    '</span>'
  );
}

/**
 * Fila de estrellas DISCRETA (enteras) para una opinion individual: n rellenas
 * de 5. Util cuando cada opinion tiene estrellas enteras (1..5).
 * @param {number} n 1..5
 * @returns {string}
 */
export function estrellasEnteras(n) {
  const k = Math.max(0, Math.min(5, Math.round(Number(n) || 0)));
  return '<span class="op-stars op-stars--sm" role="img" aria-label="' + k + ' de 5 estrellas">' +
    '<span class="op-stars-fg op-stars-fg--static">' + ICONOS.estrella.repeat(k) + '</span>' +
    '<span class="op-stars-bg">' + ICONOS.estrellaHueca.repeat(5 - k) + '</span>' +
  '</span>';
}

/** Inicial para el avatar de un autor ("Ana" -> "A"). */
export function inicialDe(nombre) {
  const s = String(nombre || '').trim();
  return (s[0] || '·').toUpperCase();
}

// ------------------------------------------------------------
// RUTA A LA RAIZ (para logout / logo, segun profundidad)
// ------------------------------------------------------------
export function rutaRaiz() {
  try {
    const partes = window.location.pathname.split('/').filter(Boolean);
    const carpetas = Math.max(partes.length - 1, 0);
    return carpetas > 0 ? '../'.repeat(carpetas) : './';
  } catch (_) {
    return '../';
  }
}

// ------------------------------------------------------------
// HEADER INSTITUCIONAL (azul marino, espejo de las otras areas)
// ------------------------------------------------------------
export function montarHeader(opts) {
  const { titulo, kicker, lead, sesion, areaLabel, volverHref, volverTexto, logoSrc } = opts || {};
  const email = sesion?.user?.email || '';
  const inicial = (email.trim()[0] || 'M').toUpperCase();
  const raiz = rutaRaiz();
  const hrefVolver = volverHref || 'index.html';
  const txtVolver = volverTexto || 'Opiniones';
  const rotulo = areaLabel || 'GESTIÓN DE OPINIONES';
  const logo = logoSrc || (raiz + 'logo-mark-terracota.png?v=2');

  const header = document.createElement('header');
  header.className = 'op-header';
  header.innerHTML =
    '<div class="op-header-left">' +
      '<a class="op-volver" href="' + escaparHTML(hrefVolver) + '" aria-label="Volver a ' + escaparHTML(txtVolver) + '">' +
        ICONOS.flecha + '<span>' + escaparHTML(txtVolver) + '</span>' +
      '</a>' +
      '<span class="op-sep" aria-hidden="true"></span>' +
      '<img class="op-logo" src="' + escaparHTML(logo) + '" alt="Magandhi">' +
      '<span class="op-word">MAGANDHI</span>' +
      '<span class="op-sep" aria-hidden="true"></span>' +
      '<span class="op-area">' + escaparHTML(rotulo) + '</span>' +
    '</div>' +
    '<div class="op-header-right">' +
      '<div class="op-perfil">' +
        '<button class="op-avatar" id="op-avatar" type="button" ' +
          'aria-haspopup="menu" aria-expanded="false" aria-controls="op-perfil-menu" ' +
          'title="' + escaparHTML(email) + '" aria-label="Menú de perfil">' + escaparHTML(inicial) + '</button>' +
        '<div class="op-perfil-menu" id="op-perfil-menu" role="menu" aria-label="Perfil" hidden>' +
          '<div class="op-perfil-info">' +
            '<span class="op-perfil-lbl">Sesión iniciada como</span>' +
            '<span class="op-perfil-email">' + escaparHTML(email || 'usuario interno') + '</span>' +
          '</div>' +
          '<button class="op-perfil-salir" id="op-perfil-salir" type="button" role="menuitem">' +
            ICONOS.salir + '<span>Cerrar sesión</span>' +
          '</button>' +
        '</div>' +
      '</div>' +
    '</div>';

  const screenHead = document.createElement('div');
  screenHead.className = 'op-screen-head';
  screenHead.innerHTML =
    '<p class="op-kicker">' + escaparHTML(kicker || '') + '</p>' +
    '<h1 class="op-title">' + escaparHTML(titulo || '') + '</h1>' +
    (lead ? '<p class="op-lead">' + escaparHTML(lead) + '</p>' : '');

  document.body.insertBefore(screenHead, document.body.firstChild);
  document.body.insertBefore(header, document.body.firstChild);

  montarMenuPerfil(header, raiz);
  montarSelloImpulse();
}

function montarMenuPerfil(header, raiz) {
  const avatar = header.querySelector('#op-avatar');
  const menu = header.querySelector('#op-perfil-menu');
  const salir = header.querySelector('#op-perfil-salir');
  if (!avatar || !menu) return;

  const abrir = () => { menu.hidden = false; avatar.setAttribute('aria-expanded', 'true'); salir?.focus(); };
  const cerrar = (foco) => { menu.hidden = true; avatar.setAttribute('aria-expanded', 'false'); if (foco) avatar.focus(); };
  const abierto = () => avatar.getAttribute('aria-expanded') === 'true';

  avatar.addEventListener('click', (e) => { e.stopPropagation(); abierto() ? cerrar(false) : abrir(); });
  document.addEventListener('click', (e) => { if (abierto() && !menu.contains(e.target) && e.target !== avatar) cerrar(false); });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && abierto()) cerrar(true); });

  salir?.addEventListener('click', async () => {
    try { await supabase.auth.signOut(); } catch (_) { /* ignorar */ }
    window.location.replace(raiz + 'index.html');
  });
}

export function montarSelloImpulse() {
  if (document.querySelector('.op-sello')) return;
  const foot = document.createElement('footer');
  foot.className = 'op-sello';
  foot.innerHTML = 'Con tecnología <span class="op-sello-marca">Impulse</span>';
  document.body.appendChild(foot);
}

// ------------------------------------------------------------
// FECHAS
// ------------------------------------------------------------
/** Formatea un timestamptz a "05 feb 2025, 14:03" (hora local). */
export function formatearMomento(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return String(iso);
  const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  const hh = String(d.getHours()).padStart(2, '0');
  const mm = String(d.getMinutes()).padStart(2, '0');
  return `${String(d.getDate()).padStart(2, '0')} ${meses[d.getMonth()]} ${d.getFullYear()}, ${hh}:${mm}`;
}

/** Formatea un timestamptz a fecha corta "05 feb 2025" (sin hora). */
export function formatearFecha(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return String(iso);
  const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  return `${String(d.getDate()).padStart(2, '0')} ${meses[d.getMonth()]} ${d.getFullYear()}`;
}
