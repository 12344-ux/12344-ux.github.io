// ============================================================
//  MAGANDHI · AREA DE VENTAS · Nucleo compartido (ventas-core.js)
//  ------------------------------------------------------------
//  Utilidades reutilizadas por todas las paginas del Area de Ventas y de sus
//  sub-areas (Seguimiento de pedidos, Portafolio de clientes). Espejo de
//  finanzas-core.js / inventario-core.js / marketing-core.js: mismo estandar de
//  calidad, mismo header institucional AZUL MARINO, mismo sello "Con tecnologia
//  Impulse" al pie, wordmark MAGANDHI.
//
//  SIN COLOR NUEVO (decision del dueno): esta area HEREDA el azul marino
//  #101C33 del back-office. El verde ya es de Finanzas; aqui NO se estrena un
//  color propio. Ventas se diferencia por el LAYOUT y la jerarquia (tablero de
//  pedidos + fichas de cliente), no por un tinte. "No quiero un arcoiris".
//
//  PROFUNDIDAD DE IMPORTS (por que un solo core en ventas/):
//  Este archivo vive en ventas/, un nivel bajo la raiz, asi que importa el
//  cliente unico y el guardia con '../supabase-config.js' / '../auth-guard.js'.
//  Los imports de un modulo ES se resuelven SIEMPRE relativos al archivo que
//  los declara (este core), NO relativos a la pagina que lo importa. Por eso
//  una sola copia en ventas/ sirve tanto a ventas/index.html (que la importa
//  como './ventas-core.js') como a ventas/<subarea>/*.html (que la importa como
//  '../ventas-core.js'): en ambos casos, cuando el core hace
//  '../supabase-config.js', la ruta se calcula desde ventas/ y apunta bien a la
//  raiz. No se duplica el nucleo.
//
//  Recordatorio de seguridad: ocultar UI es solo comodidad de UX. El candado
//  real es RLS server-side (tiene_acceso_ventas() sobre tiene_modulo(...)); ver
//  la migracion 20250401000300_ventas_rls.sql.
// ============================================================

import { supabase } from '../supabase-config.js';
import { exigirSesion, obtenerPerfil } from '../auth-guard.js';

// Reexportamos para que las paginas importen todo desde un solo lugar.
export { supabase, exigirSesion, obtenerPerfil };

// ------------------------------------------------------------
// FORMATO / PARSEO DE MONTOS (enteros de pesos COP)
// (Logica identica a inventario-core.js / finanzas-core.js; replicada por
//  clonabilidad para que cada area sea autocontenida.)
// ------------------------------------------------------------

/**
 * Formatea un ENTERO de pesos a COP con puntos de miles: 1200000 -> "1.200.000".
 * Sin simbolo $ ni decimales.
 * @param {number} entero
 * @returns {string}
 */
export function formatearCOP(entero) {
  const n = Math.trunc(Number(entero) || 0);
  const signo = n < 0 ? '-' : '';
  const abs = Math.abs(n).toString();
  return signo + abs.replace(/\B(?=(\d{3})+(?!\d))/g, '.');
}

/**
 * Analiza lo que el usuario escribe en un campo de monto SIN tragarse los
 * centavos en silencio (mismo comportamiento que finanzas-core.js; replicado
 * por clonabilidad). Los montos son ENTEROS de pesos COP (sin centavos): el
 * punto es separador de MILES y la coma seria separador decimal.
 *
 * Antes un replace(/[^\d]/g,'') convertia "1.200,50" en 120050 (pegaba los
 * centavos) sin avisar. Aqui el punto agrupa miles ("1.200.000" -> 1200000) y
 * cualquier parte decimal (coma, o punto que no agrupa de a tres) se descarta
 * y se avisa via `tieneDecimal`, nunca se cuela como pesos.
 * @param {string} texto
 * @returns {{ valor:number, tieneDecimal:boolean, invalido:boolean }}
 */
export function analizarMonto(texto) {
  if (texto == null) return { valor: 0, tieneDecimal: false, invalido: false };
  let limpio = String(texto).replace(/[^\d.,]/g, '');
  if (limpio === '') return { valor: 0, tieneDecimal: false, invalido: false };

  let tieneDecimal = false;

  const coma = limpio.indexOf(',');
  if (coma !== -1) {
    const decimales = limpio.slice(coma + 1).replace(/[.,]/g, '');
    if (decimales !== '') tieneDecimal = true;
    limpio = limpio.slice(0, coma);
  }

  if (limpio.indexOf('.') !== -1) {
    const grupos = limpio.split('.');
    const ultimo = grupos[grupos.length - 1];
    if (grupos.length > 1 && ultimo.length !== 3) {
      const dec = grupos.pop().replace(/\D/g, '');
      if (dec !== '') tieneDecimal = true;
      limpio = grupos.join('.');
    }
  }

  const soloDigitos = limpio.replace(/\D/g, '');
  if (soloDigitos === '') return { valor: 0, tieneDecimal, invalido: false };
  const n = parseInt(soloDigitos, 10);
  if (!Number.isFinite(n)) return { valor: 0, tieneDecimal, invalido: true };
  return { valor: n, tieneDecimal, invalido: false };
}

/**
 * Convierte lo que el usuario escribe en un campo de monto a un ENTERO de
 * pesos (sin centavos). El punto es separador de miles; cualquier parte
 * decimal se descarta. Campo vacio -> 0. Para avisar de un decimal, usa
 * `analizarMonto` (bandera `tieneDecimal`). Firma retrocompatible.
 * @param {string} texto
 * @returns {number} entero de pesos (>= 0)
 */
export function parsearMonto(texto) {
  return analizarMonto(texto).valor;
}

/**
 * Parsea una cantidad de unidades a ENTERO no negativo (las cantidades del
 * pedido son unidades enteras; el check de la BD exige cantidad > 0).
 * @param {string} texto
 * @returns {number} entero >= 0
 */
export function parsearCantidad(texto) {
  if (texto == null) return 0;
  const soloDigitos = String(texto).replace(/[^\d]/g, '');
  if (soloDigitos === '') return 0;
  const n = parseInt(soloDigitos, 10);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

// ------------------------------------------------------------
// SANEAMIENTO
// ------------------------------------------------------------

/**
 * Escapa texto para insertarlo de forma segura via innerHTML (anti-XSS
 * almacenado al pintar nombre/correo/telefono/notas que escribio el operador o
 * que vienen de datos de clientes).
 * @param {*} s
 * @returns {string}
 */
export function escaparHTML(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ------------------------------------------------------------
// ACCESO AL AREA
// ------------------------------------------------------------

/**
 * True si el perfil puede usar el Area de Ventas / sus sub-areas: admin ve
 * todo; otros solo si su lista de modulos incluye alguna de las claves del
 * area. ESPEJO de tieneAccesoMarketing y del wrapper SQL tiene_acceso_ventas()
 * (20250401000300_ventas_rls.sql): las claves habladas son las MISMAS —
 * 'ventas' (area), 'pedidos' (sub-area de pedidos) y 'clientes'/'portafolio'
 * (sub-area del portafolio, alias). El candado real es RLS; esto es comodidad
 * de UX.
 * @param {{rol?:string, modulos?:string[]}|null} perfil
 * @returns {boolean}
 */
export function tieneAccesoVentas(perfil) {
  if (!perfil) return false;
  if (perfil.rol === 'admin') return true;
  const modulos = Array.isArray(perfil.modulos) ? perfil.modulos : [];
  return modulos.includes('ventas') ||
         modulos.includes('pedidos') ||
         modulos.includes('clientes') ||
         modulos.includes('portafolio');
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

  if (!tieneAccesoVentas(perfil)) {
    if (contenedor) {
      const href = volverHref || '../panel.html';
      contenedor.innerHTML =
        '<div class="vt-denegado">' +
          '<h2>Acceso restringido · Área de Ventas</h2>' +
          '<p>Tu cuenta no tiene habilitada el <strong>Área de Ventas</strong>. ' +
          'Solicita el acceso a un administrador.</p>' +
          '<p style="margin-top:14px"><a href="' + escaparHTML(href) + '">Volver al panel</a></p>' +
        '</div>';
    }
    return null;
  }

  return { sesion, perfil };
}

// ------------------------------------------------------------
// ICONOS (SVG inline consistentes con el set de las otras areas + los del area)
// Sin color propio: heredan currentColor.
// ------------------------------------------------------------
export const ICONOS = {
  lupa: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>',
  info: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/></svg>',
  lista: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/></svg>',
  // recibo: identifica el Area de Ventas (la orden / comprobante de venta).
  recibo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 2v20l2-1 2 1 2-1 2 1 2-1 2 1 2-1 2 1V2l-2 1-2-1-2 1-2-1-2 1-2-1-2 1-2-1Z"/><path d="M8 7h8M8 11h8M8 15h5"/></svg>',
  // carrito: alternativa para el area / accion de venta.
  carrito: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="8" cy="21" r="1"/><circle cx="19" cy="21" r="1"/><path d="M2.05 2.05h2l2.66 12.42a2 2 0 0 0 2 1.58h9.78a2 2 0 0 0 1.95-1.57l1.65-7.43H5.12"/></svg>',
  // paquete: estados de preparacion (pedido en alistamiento).
  paquete: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m7.5 4.27 9 5.15"/><path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z"/><path d="M3.3 7 12 12l8.7-5M12 22V12"/></svg>',
  // camion: estado en_camino (la etapa que el cliente mas quiere saber).
  camion: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 18V6a1 1 0 0 0-1-1H3a1 1 0 0 0-1 1v11a1 1 0 0 0 1 1h1"/><path d="M14 9h4l4 4v4a1 1 0 0 1-1 1h-1"/><circle cx="7.5" cy="18" r="2"/><circle cx="17.5" cy="18" r="2"/><path d="M10 18h4"/></svg>',
  // usuario: fichas de cliente (Portafolio de clientes).
  usuario: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>',
  // usuarios: cartera / portafolio de varios clientes.
  usuarios: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/></svg>',
  // mas: agregar (nuevo cliente / registrar pedido).
  mas: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v14M5 12h14"/></svg>',
  // equis: cerrar / anular.
  equis: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18M6 6l12 12"/></svg>',
  // check: entregado / confirmacion.
  check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>'
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
 * logout redirige bien tanto desde ventas/*.html ('../') como desde
 * ventas/<subarea>/*.html ('../../'). Fallback prudente: '../'.
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
 * Impulse al pie. Espejo del header de Finanzas / Produccion / Marketing:
 * mismo wordmark MAGANDHI, boton volver con destino EXPLICITO (nunca
 * history.back()), avatar con menu de perfil (correo + Cerrar sesion via
 * supabase.auth.signOut).
 *
 * @param {object} opts
 * @param {string} opts.titulo     Titulo editorial de la pantalla.
 * @param {string} opts.kicker     Kicker en terracota (mayusculas).
 * @param {string} [opts.lead]     Parrafo introductorio opcional.
 * @param {object} [opts.sesion]   Sesion (para inicial del avatar y correo).
 * @param {string} [opts.areaLabel] Rotulo del header (default 'ÁREA DE VENTAS').
 * @param {string} [opts.volverHref] Destino del boton volver (default index.html).
 * @param {string} [opts.volverTexto] Etiqueta del boton volver (default 'Ventas').
 * @param {string} [opts.logoSrc]  Ruta al logo (default segun profundidad).
 */
export function montarHeader(opts) {
  const { titulo, kicker, lead, sesion, areaLabel, volverHref, volverTexto, logoSrc } = opts || {};
  const email = sesion?.user?.email || '';
  const inicial = (email.trim()[0] || 'M').toUpperCase();
  const raiz = rutaRaiz();
  const hrefVolver = volverHref || 'index.html';
  const txtVolver = volverTexto || 'Ventas';
  const rotulo = areaLabel || 'ÁREA DE VENTAS';
  const logo = logoSrc || (raiz + 'logo-mark-terracota.png');

  const header = document.createElement('header');
  header.className = 'vt-header';
  header.innerHTML =
    '<div class="vt-header-left">' +
      '<a class="vt-volver" href="' + escaparHTML(hrefVolver) + '" aria-label="Volver a ' + escaparHTML(txtVolver) + '">' +
        ICONOS.flecha +
        '<span>' + escaparHTML(txtVolver) + '</span>' +
      '</a>' +
      '<span class="vt-sep" aria-hidden="true"></span>' +
      '<img class="vt-logo" src="' + escaparHTML(logo) + '" alt="Magandhi">' +
      '<span class="vt-word">MAGANDHI</span>' +
      '<span class="vt-sep" aria-hidden="true"></span>' +
      '<span class="vt-area">' + escaparHTML(rotulo) + '</span>' +
    '</div>' +
    '<div class="vt-header-right">' +
      '<div class="vt-perfil">' +
        '<button class="vt-avatar" id="vt-avatar" type="button" ' +
          'aria-haspopup="menu" aria-expanded="false" aria-controls="vt-perfil-menu" ' +
          'title="' + escaparHTML(email) + '" aria-label="Menu de perfil">' + escaparHTML(inicial) + '</button>' +
        '<div class="vt-perfil-menu" id="vt-perfil-menu" role="menu" aria-label="Perfil" hidden>' +
          '<div class="vt-perfil-info">' +
            '<span class="vt-perfil-lbl">Sesion iniciada como</span>' +
            '<span class="vt-perfil-email">' + escaparHTML(email || 'usuario interno') + '</span>' +
          '</div>' +
          '<button class="vt-perfil-salir" id="vt-perfil-salir" type="button" role="menuitem">' +
            ICONOS.salir + '<span>Cerrar sesion</span>' +
          '</button>' +
        '</div>' +
      '</div>' +
    '</div>';

  const screenHead = document.createElement('div');
  screenHead.className = 'vt-screen-head';
  screenHead.innerHTML =
    '<p class="vt-kicker">' + escaparHTML(kicker || '') + '</p>' +
    '<h1 class="vt-title">' + escaparHTML(titulo || '') + '</h1>' +
    (lead ? '<p class="vt-lead">' + escaparHTML(lead) + '</p>' : '');

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
  const avatar = header.querySelector('#vt-avatar');
  const menu = header.querySelector('#vt-perfil-menu');
  const salir = header.querySelector('#vt-perfil-salir');
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
  if (document.querySelector('.vt-sello')) return;
  const foot = document.createElement('footer');
  foot.className = 'vt-sello';
  foot.innerHTML = 'Con tecnología <span class="vt-sello-marca">Impulse</span>';
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

/** Formatea un timestamptz a "05 feb 2025, 14:03" con hora local. */
export function formatearMomento(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return String(iso);
  const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  const hh = String(d.getHours()).padStart(2, '0');
  const mm = String(d.getMinutes()).padStart(2, '0');
  return `${String(d.getDate()).padStart(2, '0')} ${meses[d.getMonth()]} ${d.getFullYear()}, ${hh}:${mm}`;
}
