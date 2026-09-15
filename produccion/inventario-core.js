// ============================================================
//  MAGANDHI · AREA DE PRODUCCION · Nucleo compartido (inventario-core.js)
//  ------------------------------------------------------------
//  Espejo de finanzas/finanzas-core.js para el Area de Produccion y su
//  sub-area Inventarios. Reune las utilidades reutilizadas por todas las
//  paginas del area:
//    · Formateo COP con puntos de miles (1.200.000) y parseo a ENTERO de
//      pesos (bigint-safe) — MISMA logica exacta que Finanzas, replicada
//      aqui con atribucion para no acoplar las dos areas (cada una es
//      clonable por separado; el ecosistema Impulse valora eso).
//    · Verificacion de acceso al area (admin o modulos incluye la clave del
//      area / sub-area).
//    · Montaje del header institucional AZUL MARINO + 'AREA DE PRODUCCION'.
//    · Sello "Con tecnologia Impulse".
//
//  PROFUNDIDAD DE RUTAS (clave): este archivo vive en produccion/. En ES
//  modules, un import se resuelve SIEMPRE relativo al archivo que lo
//  declara, NO relativo a la pagina que importa el archivo. Por eso aqui
//  siempre subimos UN nivel ('../') para llegar a la raiz, y funciona igual
//  cuando lo importa produccion/index.html ('./inventario-core.js') que
//  cuando lo importa produccion/inventarios/ver.html ('../inventario-core.js').
//  Un SOLO core sirve a las dos profundidades: no hace falta duplicarlo.
//
//  Lo que SI depende de la profundidad de la PAGINA (rutas a hojas de estilo,
//  favicon, boton volver y redirect de logout) lo resuelve cada pagina en su
//  <link>/<a>, y el logout calcula la raiz contando segmentos de la URL.
//
//  DECISION DE MONTOS (no negociable, misma que Finanzas): en JS los montos
//  se manejan como ENTEROS de pesos COP (Number entero, sin centavos). El
//  formato con puntos de miles es solo de PRESENTACION; nunca float.
//
//  Recordatorio de seguridad: ocultar UI es solo comodidad de UX. El candado
//  real es RLS server-side (tiene_modulo('inventario')) + las RPC security
//  definer (inv_crear_producto / inv_registrar_movimiento / inv_editar_producto).
// ============================================================

import { supabase } from '../supabase-config.js';
import { exigirSesion, obtenerPerfil } from '../auth-guard.js';

// Reexportamos para que las paginas importen todo desde un solo lugar.
export { supabase, exigirSesion, obtenerPerfil };

// ------------------------------------------------------------
// FORMATO / PARSEO DE MONTOS (enteros de pesos COP)
// (Logica identica a finanzas-core.js; replicada por clonabilidad.)
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
 * Convierte lo que el usuario escribe en un campo de monto a un ENTERO de
 * pesos. Quita todo lo que no sea digito. Campo vacio -> 0.
 * @param {string} texto
 * @returns {number} entero de pesos (>= 0)
 */
export function parsearMonto(texto) {
  if (texto == null) return 0;
  const soloDigitos = String(texto).replace(/[^\d]/g, '');
  if (soloDigitos === '') return 0;
  const n = parseInt(soloDigitos, 10);
  return Number.isFinite(n) ? n : 0;
}

/**
 * Parsea una cantidad de unidades a ENTERO no negativo (stock en unidades
 * enteras; el check de la BD exige cantidad > 0 al registrar movimiento).
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

/**
 * Escapa texto para insertarlo de forma segura via innerHTML (anti-XSS
 * almacenado al pintar nombre/descripcion/motivo que escribio el operador).
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
 * True si el perfil puede usar el area de Produccion / Inventarios: admin ve
 * todo; otros solo si su lista de modulos incluye la clave del area
 * ('produccion') o de la sub-area ('inventarios'). Se acepta tambien la clave
 * server-side del modulo de datos ('inventario') para que coincida con la RLS
 * (tiene_modulo('inventario')). El candado real es RLS; esto es UX.
 * @param {{rol?:string, modulos?:string[]}|null} perfil
 * @returns {boolean}
 */
export function tieneAccesoProduccion(perfil) {
  if (!perfil) return false;
  if (perfil.rol === 'admin') return true;
  const modulos = Array.isArray(perfil.modulos) ? perfil.modulos : [];
  return modulos.includes('produccion') ||
         modulos.includes('inventarios') ||
         modulos.includes('inventario');
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

  if (!tieneAccesoProduccion(perfil)) {
    if (contenedor) {
      const href = volverHref || '../panel.html';
      contenedor.innerHTML =
        '<div class="pr-denegado">' +
          '<h2>Acceso restringido</h2>' +
          '<p>Tu cuenta no tiene habilitada el <strong>Área de Producción</strong>. ' +
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
  mas: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v14M5 12h14"/></svg>',
  equis: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18M6 6l12 12"/></svg>',
  check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>',
  info: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/></svg>',
  lista: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/></svg>',
  // box: caja de producto (identifica Inventarios).
  box: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21 8-9-5-9 5 9 5 9-5Z"/><path d="M3 8v8l9 5 9-5V8"/><path d="m12 13v8"/></svg>',
  // warehouse: bodega / area de Produccion.
  warehouse: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 8.35V21a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V8.35a2 2 0 0 1 1.26-1.86l8-3.2a2 2 0 0 1 1.48 0l8 3.2A2 2 0 0 1 22 8.35Z"/><path d="M6 18h12M6 14h12M6 22V10h12v12"/></svg>',
  // upload: subir imagen.
  upload: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="M17 8l-5-5-5 5M12 3v12"/></svg>',
  // imagen: marcador de producto sin foto.
  imagen: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.5-3.5a2 2 0 0 0-2.8 0L4 22"/></svg>',
  // movimientos: flechas de entrada/salida.
  movimientos: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3l4 4-4 4M21 7H8M7 21l-4-4 4-4M3 17h13"/></svg>',
  // alerta: stock bajo (herramienta futura).
  alerta: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0Z"/><path d="M12 9v4M12 17h.01"/></svg>'
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
 * logout redirige bien tanto desde produccion/*.html ('../') como desde
 * produccion/inventarios/*.html ('../../'). Fallback prudente: '../'.
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
 * Impulse al pie. Espejo del header de Finanzas: mismo wordmark MAGANDHI,
 * boton volver con destino EXPLICITO (nunca history.back()), avatar con menu
 * de perfil (correo + Cerrar sesion via supabase.auth.signOut).
 *
 * @param {object} opts
 * @param {string} opts.titulo     Titulo editorial de la pantalla.
 * @param {string} opts.kicker     Kicker en terracota (mayusculas).
 * @param {string} [opts.lead]     Parrafo introductorio opcional.
 * @param {object} [opts.sesion]   Sesion (para inicial del avatar y correo).
 * @param {string} [opts.areaLabel] Rotulo del header (default 'ÁREA DE PRODUCCIÓN').
 * @param {string} [opts.volverHref] Destino del boton volver (default index.html).
 * @param {string} [opts.volverTexto] Etiqueta del boton volver (default 'Producción').
 * @param {string} [opts.logoSrc]  Ruta al logo (default segun profundidad).
 */
export function montarHeader(opts) {
  const { titulo, kicker, lead, sesion, areaLabel, volverHref, volverTexto, logoSrc } = opts || {};
  const email = sesion?.user?.email || '';
  const inicial = (email.trim()[0] || 'P').toUpperCase();
  const raiz = rutaRaiz();
  const hrefVolver = volverHref || 'index.html';
  const txtVolver = volverTexto || 'Producción';
  const rotulo = areaLabel || 'ÁREA DE PRODUCCIÓN';
  const logo = logoSrc || (raiz + 'logo-mark-terracota.png');

  const header = document.createElement('header');
  header.className = 'pr-header';
  header.innerHTML =
    '<div class="pr-header-left">' +
      '<a class="pr-volver" href="' + escaparHTML(hrefVolver) + '" aria-label="Volver a ' + escaparHTML(txtVolver) + '">' +
        ICONOS.flecha +
        '<span>' + escaparHTML(txtVolver) + '</span>' +
      '</a>' +
      '<span class="pr-sep" aria-hidden="true"></span>' +
      '<img class="pr-logo" src="' + escaparHTML(logo) + '" alt="Magandhi">' +
      '<span class="pr-word">MAGANDHI</span>' +
      '<span class="pr-sep" aria-hidden="true"></span>' +
      '<span class="pr-area">' + escaparHTML(rotulo) + '</span>' +
    '</div>' +
    '<div class="pr-header-right">' +
      '<div class="pr-perfil">' +
        '<button class="pr-avatar" id="pr-avatar" type="button" ' +
          'aria-haspopup="menu" aria-expanded="false" aria-controls="pr-perfil-menu" ' +
          'title="' + escaparHTML(email) + '" aria-label="Menu de perfil">' + escaparHTML(inicial) + '</button>' +
        '<div class="pr-perfil-menu" id="pr-perfil-menu" role="menu" aria-label="Perfil" hidden>' +
          '<div class="pr-perfil-info">' +
            '<span class="pr-perfil-lbl">Sesion iniciada como</span>' +
            '<span class="pr-perfil-email">' + escaparHTML(email || 'usuario interno') + '</span>' +
          '</div>' +
          '<button class="pr-perfil-salir" id="pr-perfil-salir" type="button" role="menuitem">' +
            ICONOS.salir + '<span>Cerrar sesion</span>' +
          '</button>' +
        '</div>' +
      '</div>' +
    '</div>';

  const screenHead = document.createElement('div');
  screenHead.className = 'pr-screen-head';
  screenHead.innerHTML =
    '<p class="pr-kicker">' + escaparHTML(kicker || '') + '</p>' +
    '<h1 class="pr-title">' + escaparHTML(titulo || '') + '</h1>' +
    (lead ? '<p class="pr-lead">' + escaparHTML(lead) + '</p>' : '');

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
  const avatar = header.querySelector('#pr-avatar');
  const menu = header.querySelector('#pr-perfil-menu');
  const salir = header.querySelector('#pr-perfil-salir');
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
  if (document.querySelector('.pr-sello')) return;
  const foot = document.createElement('footer');
  foot.className = 'pr-sello';
  foot.innerHTML = 'Con tecnología <span class="pr-sello-marca">Impulse</span>';
  document.body.appendChild(foot);
}

// ------------------------------------------------------------
// FECHAS
// ------------------------------------------------------------

/** Fecha de hoy en YYYY-MM-DD (zona local) para inputs date. */
export function hoyISO() {
  const d = new Date();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${d.getFullYear()}-${mm}-${dd}`;
}

/** Formatea una fecha ISO (YYYY-MM-DD) a texto corto en espanol, sin desfase UTC. */
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

// ------------------------------------------------------------
// IMAGENES · optimizacion en el navegador antes de subir
// ------------------------------------------------------------

/**
 * Nombre del bucket de Storage donde viven las imagenes de producto. El bucket
 * y sus policies los crea el DUENO en el dashboard de Supabase (documentado en
 * FEAT-005 / INSTRUCCIONES.md). El cliente solo sube con la SESION del usuario
 * autenticado; NUNCA con service_role.
 */
export const BUCKET_PRODUCTOS = 'productos';

/**
 * URL publica de una imagen de producto a partir de su imagen_path guardado.
 * Si no hay path, devuelve ''. Usa el bucket publico 'productos'.
 * @param {string} path imagen_path guardado en productos.imagen_path
 * @returns {string} URL publica o ''
 */
export function urlPublicaImagen(path) {
  if (!path) return '';
  try {
    const { data } = supabase.storage.from(BUCKET_PRODUCTOS).getPublicUrl(path);
    return data?.publicUrl || '';
  } catch (_) {
    return '';
  }
}

/**
 * Optimiza una imagen EN EL NAVEGADOR antes de subirla (decision explicita del
 * dueno: que el sistema ajuste las fotos para que no ocupen tanto). Redimensiona
 * al borde mayor ~maxBorde px (default 1200), re-codifica a JPEG con calidad
 * ~0.8 y devuelve un Blob. Si el archivo ya es pequeno y del formato objetivo,
 * igual se normaliza para tener un peso predecible. No sube nada: solo procesa.
 *
 * @param {File} archivo imagen original elegida por el usuario
 * @param {object} [opts]
 * @param {number} [opts.maxBorde=1200] borde mayor maximo en px
 * @param {number} [opts.calidad=0.8]  calidad JPEG (0..1)
 * @returns {Promise<{blob:Blob, ancho:number, alto:number, tipo:string}>}
 */
export async function optimizarImagen(archivo, opts) {
  const maxBorde = (opts && opts.maxBorde) || 1200;
  const calidad = (opts && typeof opts.calidad === 'number') ? opts.calidad : 0.8;

  // createImageBitmap decodifica sin insertar la imagen en el DOM (rapido y
  // sin depender de un <img> visible). Fallback a Image() si no existiera.
  let bitmap;
  if (typeof createImageBitmap === 'function') {
    bitmap = await createImageBitmap(archivo);
  } else {
    bitmap = await new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = reject;
      img.src = URL.createObjectURL(archivo);
    });
  }

  const anchoOrig = bitmap.width;
  const altoOrig = bitmap.height;
  const borde = Math.max(anchoOrig, altoOrig);
  const escala = borde > maxBorde ? maxBorde / borde : 1;
  const ancho = Math.max(1, Math.round(anchoOrig * escala));
  const alto = Math.max(1, Math.round(altoOrig * escala));

  const canvas = document.createElement('canvas');
  canvas.width = ancho;
  canvas.height = alto;
  const ctx = canvas.getContext('2d');
  // Fondo blanco para imagenes con transparencia (JPEG no tiene alpha).
  ctx.fillStyle = '#ffffff';
  ctx.fillRect(0, 0, ancho, alto);
  ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(bitmap, 0, 0, ancho, alto);
  if (bitmap.close) bitmap.close();

  const blob = await new Promise((resolve, reject) => {
    canvas.toBlob(
      (b) => (b ? resolve(b) : reject(new Error('No se pudo procesar la imagen.'))),
      'image/jpeg',
      calidad
    );
  });

  return { blob, ancho, alto, tipo: 'image/jpeg' };
}
