// ============================================================
//  MAGANDHI · MODULO FINANZAS · Nucleo compartido (finanzas-core.js)
//  ------------------------------------------------------------
//  Utilidades reutilizadas por todas las paginas del area de Finanzas:
//    · Formateo COP con puntos de miles (1.200.000).
//    · Parseo de un monto escrito a ENTERO de pesos (bigint-safe).
//    · Verificacion de acceso al modulo (admin o modulos incluye 'finanzas').
//    · Montaje del header institucional (azul marino + AREA DE FINANZAS).
//
//  DECISION DE MONTOS (no negociable): en JS los montos se manejan como
//  ENTEROS de pesos COP (Number entero, sin centavos). El cuadre de la
//  partida doble se calcula SUMANDO/COMPARANDO enteros; NUNCA se usa
//  aritmetica de punto flotante para decidir si un asiento cuadra. El
//  formato con puntos de miles es solo de PRESENTACION.
//
//  Este modulo vive en finanzas/, asi que sube un nivel para importar el
//  cliente unico y el guardia compartidos (../supabase-config.js /
//  ../auth-guard.js). No crea otro cliente Supabase.
//
//  Recordatorio de seguridad: ocultar UI es solo comodidad de UX. El
//  candado real es RLS server-side (tiene_modulo('finanzas')).
// ============================================================

import { supabase } from '../supabase-config.js';
import { exigirSesion, obtenerPerfil } from '../auth-guard.js';

// Reexportamos para que las paginas importen todo desde un solo lugar.
export { supabase, exigirSesion, obtenerPerfil };

// ------------------------------------------------------------
// FORMATO / PARSEO DE MONTOS (enteros de pesos COP)
// ------------------------------------------------------------

/**
 * Formatea un ENTERO de pesos a COP con puntos de miles: 1200000 -> "1.200.000".
 * No agrega el simbolo $ (la UI decide si lo antepone). Sin decimales.
 * @param {number} entero pesos enteros
 * @returns {string}
 */
export function formatearCOP(entero) {
  const n = Math.trunc(Number(entero) || 0);
  const signo = n < 0 ? '-' : '';
  const abs = Math.abs(n).toString();
  // Inserta un punto cada 3 digitos desde la derecha.
  return signo + abs.replace(/\B(?=(\d{3})+(?!\d))/g, '.');
}

/**
 * Convierte lo que el usuario escribe en un campo de monto a un ENTERO de
 * pesos. Quita todo lo que no sea digito (puntos de miles, espacios, $, y
 * cualquier coma/decimal: los montos son enteros de pesos, sin centavos).
 * Un campo vacio -> 0.
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
 * TOPE DE MONTO POR LINEA (no negociable, ver 20250201000600_finanzas_funciones.sql).
 *
 * El cuadre en JS suma con Number entero. Number es exacto solo por debajo de
 * 2^53 (Number.MAX_SAFE_INTEGER = 9.007.199.254.740.991). Por encima de ese
 * techo dos importes distintos pueden parecer iguales y colar un asiento que
 * en realidad no cuadra. Para que el candado real cubra el rango, fijamos un
 * tope por linea de 1.000.000.000.000 (un billon de pesos COP), muy por encima
 * de cualquier operacion real de un comercio como MAGANDHI y con margen de
 * sobra bajo 2^53 (incluso sumando cientos de lineas al tope, el total sigue
 * siendo exacto). El MISMO tope se impone server-side en fz_validar_lineas, que
 * es el candado autoritativo; esta constante es solo la validacion espejo de UX.
 */
export const TOPE_MONTO_LINEA = 1000000000000;

/**
 * Escapa texto para insertarlo de forma segura via innerHTML. Evita XSS
 * almacenado cuando se pinta contenido que escribio el operador (descripcion,
 * nombre de cuenta, detalle, etc.). Compartido por diario/mayor/editar-asiento
 * para no duplicar la funcion en cada pagina.
 * @param {*} s
 * @returns {string}
 */
export function escaparHTML(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// ------------------------------------------------------------
// ACCESO AL MODULO
// ------------------------------------------------------------

/**
 * True si el perfil puede usar el modulo finanzas: admin ve todo; otros
 * solo si 'finanzas' esta en su lista de modulos. El candado real es RLS;
 * esto es comodidad de UX.
 * @param {{rol?:string, modulos?:string[]}|null} perfil
 * @returns {boolean}
 */
export function tieneAccesoFinanzas(perfil) {
  if (!perfil) return false;
  if (perfil.rol === 'admin') return true;
  const modulos = Array.isArray(perfil.modulos) ? perfil.modulos : [];
  return modulos.includes('finanzas');
}

/**
 * Asegura sesion + acceso al modulo. Si no hay sesion, exigirSesion ya
 * redirige al login. Si hay sesion pero no acceso, pinta el aviso de
 * acceso denegado dentro de `contenedor` (si se pasa) y devuelve null.
 * Devuelve { sesion, perfil } cuando el acceso es correcto.
 * @param {HTMLElement} [contenedor] donde mostrar el aviso de denegado
 * @returns {Promise<{sesion:object, perfil:object}|null>}
 */
export async function asegurarAcceso(contenedor) {
  const sesion = await exigirSesion();
  if (!sesion) return null; // auth-guard ya redirige al login

  let perfil = null;
  try {
    perfil = await obtenerPerfil();
  } catch (_) {
    perfil = null;
  }

  if (!tieneAccesoFinanzas(perfil)) {
    if (contenedor) {
      contenedor.innerHTML =
        '<div class="fz-denegado">' +
          '<h2>Acceso restringido</h2>' +
          '<p>Tu cuenta no tiene habilitado el <strong>Área de Finanzas</strong>. ' +
          'Solicita el acceso a un administrador.</p>' +
          '<p style="margin-top:14px"><a href="../panel.html">Volver al panel</a></p>' +
        '</div>';
    }
    return null;
  }

  return { sesion, perfil };
}

// ------------------------------------------------------------
// ICONOS (SVG inline consistentes: lupa, +, x, check, etc.)
// ------------------------------------------------------------
export const ICONOS = {
  lupa: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>',
  mas: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v14M5 12h14"/></svg>',
  equis: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18M6 6l12 12"/></svg>',
  check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>',
  libro: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2Z"/></svg>',
  lista: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/></svg>',
  balanza: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v18M7 7h10M7 21h10"/><path d="M7 7 4 14a3 3 0 0 0 6 0L7 7ZM17 7l-3 7a3 3 0 0 0 6 0l-3-7Z"/></svg>',
  nuevo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M12 12v6M9 15h6"/></svg>',
  info: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/></svg>',
  // Icono de informe/documento con lineas: distingue el Balance de comprobacion
  // (a fecha de corte) del Libro Mayor, que ya usa 'balanza'.
  informe: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/><path d="M8 13h8M8 17h8M8 9h2"/></svg>'
};

// ------------------------------------------------------------
// HEADER INSTITUCIONAL
// ------------------------------------------------------------

// Iconos extra para navegacion / perfil (flecha de retroceso, salir).
ICONOS.flecha = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>';
ICONOS.salir = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5M21 12H9"/></svg>';

/**
 * Monta el header institucional fijo (azul marino) al inicio de <body>,
 * seguido del encabezado editorial de la pantalla (titulo + kicker).
 *
 * Incluye:
 *  · Navegacion de retroceso (izquierda, junto a la marca) con destino
 *    EXPLICITO (nunca history.back()): volverHref/volverTexto. Por defecto
 *    vuelve al home del area (index.html); cada pagina puede sobreescribir.
 *  · Avatar circular clickeable a la derecha que abre un menu de perfil
 *    con el correo del usuario y un boton "Cerrar sesion" (mismo signOut
 *    que usa panel.html). Sin subida de foto (fuera de alcance).
 *
 * @param {object} opts
 * @param {string} opts.titulo   Titulo editorial de la pantalla.
 * @param {string} opts.kicker   Kicker en terracota (mayusculas).
 * @param {string} [opts.lead]   Parrafo introductorio opcional.
 * @param {object} [opts.sesion] Sesion (para la inicial del avatar y el correo).
 * @param {string} [opts.buscarHref] href del icono de buscar (default puc.html).
 * @param {string} [opts.volverHref] destino explicito del boton volver (default index.html).
 * @param {string} [opts.volverTexto] etiqueta del boton volver (default 'Finanzas').
 */
export function montarHeader(opts) {
  const { titulo, kicker, lead, sesion, buscarHref, volverHref, volverTexto } = opts || {};
  const email = sesion?.user?.email || '';
  const inicial = (email.trim()[0] || 'F').toUpperCase();
  const hrefBuscar = buscarHref || 'puc.html';
  const hrefVolver = volverHref || 'index.html';
  const txtVolver = volverTexto || 'Finanzas';

  const header = document.createElement('header');
  header.className = 'fz-header';
  header.innerHTML =
    '<div class="fz-header-left">' +
      '<a class="fz-volver" href="' + hrefVolver + '" aria-label="Volver a ' + escaparHTML(txtVolver) + '">' +
        ICONOS.flecha +
        '<span>' + escaparHTML(txtVolver) + '</span>' +
      '</a>' +
      '<span class="fz-sep" aria-hidden="true"></span>' +
      '<img class="fz-logo" src="../logo-mark-terracota.png" alt="Magandhi">' +
      '<span class="fz-word">MAGANDHI</span>' +
      '<span class="fz-sep" aria-hidden="true"></span>' +
      '<span class="fz-area">ÁREA DE FINANZAS</span>' +
    '</div>' +
    '<div class="fz-header-right">' +
      '<a class="fz-icon-btn" href="' + hrefBuscar + '" title="Buscar en el catalogo PUC" aria-label="Buscar">' +
        ICONOS.lupa +
      '</a>' +
      '<div class="fz-perfil">' +
        '<button class="fz-avatar" id="fz-avatar" type="button" ' +
          'aria-haspopup="menu" aria-expanded="false" aria-controls="fz-perfil-menu" ' +
          'title="' + escaparHTML(email) + '" aria-label="Menu de perfil">' + escaparHTML(inicial) + '</button>' +
        '<div class="fz-perfil-menu" id="fz-perfil-menu" role="menu" aria-label="Perfil" hidden>' +
          '<div class="fz-perfil-info">' +
            '<span class="fz-perfil-lbl">Sesion iniciada como</span>' +
            '<span class="fz-perfil-email">' + escaparHTML(email || 'usuario interno') + '</span>' +
          '</div>' +
          '<button class="fz-perfil-salir" id="fz-perfil-salir" type="button" role="menuitem">' +
            ICONOS.salir + '<span>Cerrar sesion</span>' +
          '</button>' +
        '</div>' +
      '</div>' +
    '</div>';

  const screenHead = document.createElement('div');
  screenHead.className = 'fz-screen-head';
  screenHead.innerHTML =
    '<p class="fz-kicker">' + (kicker || '') + '</p>' +
    '<h1 class="fz-title">' + (titulo || '') + '</h1>' +
    (lead ? '<p class="fz-lead">' + lead + '</p>' : '');

  document.body.insertBefore(screenHead, document.body.firstChild);
  document.body.insertBefore(header, document.body.firstChild);

  montarMenuPerfil(header);
  montarSelloImpulse();
}

/**
 * Cablea el comportamiento del menu de perfil del avatar: abrir/cerrar,
 * cerrar al hacer clic afuera o con Escape, accesibilidad (aria-expanded,
 * foco) y el boton "Cerrar sesion" (mismo patron que panel.html:
 * supabase.auth.signOut() + redirect al login de la raiz).
 * @param {HTMLElement} header
 */
function montarMenuPerfil(header) {
  const avatar = header.querySelector('#fz-avatar');
  const menu = header.querySelector('#fz-perfil-menu');
  const salir = header.querySelector('#fz-perfil-salir');
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

  // Clic afuera cierra el menu.
  document.addEventListener('click', (e) => {
    if (estaAbierto() && !menu.contains(e.target) && e.target !== avatar) cerrar(false);
  });

  // Escape cierra y devuelve el foco al avatar.
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && estaAbierto()) cerrar(true);
  });

  salir?.addEventListener('click', async () => {
    try { await supabase.auth.signOut(); } catch (_) { /* ignorar */ }
    // finanzas/ vive un nivel bajo la raiz: el login esta en ../index.html.
    window.location.replace('../index.html');
  });
}

// ------------------------------------------------------------
// SELLO DE PROVEEDOR ("Con tecnologia Impulse")
// ------------------------------------------------------------

/**
 * Inserta el sello discreto de proveedor "Con tecnologia Impulse" al final
 * del <body>. Firma sobria de proveedor: gris tenue, "Impulse" con un peso
 * ligeramente destacado. Idempotente (no duplica si ya existe). Solo para el
 * back-office interno (montaguth.institute); nunca la tienda publica.
 */
export function montarSelloImpulse() {
  if (document.querySelector('.fz-sello')) return;
  const foot = document.createElement('footer');
  foot.className = 'fz-sello';
  foot.innerHTML = 'Con tecnología <span class="fz-sello-marca">Impulse</span>';
  document.body.appendChild(foot);
}

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

/**
 * Formatea un timestamptz (ISO con hora, p.ej. de asiento_bitacora.cuando) a
 * un texto legible en espanol corto con hora local: "05 feb 2025, 14:03".
 * @param {string} iso
 * @returns {string}
 */
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
// TRAZABILIDAD (bitacora de correcciones · modelo punto medio)
// ------------------------------------------------------------

/**
 * Metadatos de presentacion para cada accion de la bitacora
 * (crear | editar | anular): etiqueta legible y clase de color.
 * La UI nunca expone borrado fisico; solo estas tres acciones existen.
 */
export const ACCIONES_BITACORA = {
  crear:  { etiqueta: 'Creado',  clase: 'crear' },
  editar: { etiqueta: 'Editado', clase: 'editar' },
  anular: { etiqueta: 'Anulado', clase: 'anular' }
};

/**
 * Lee el historial de correcciones de un asiento desde asiento_bitacora,
 * ordenado cronologicamente (mas reciente primero). Solo lectura; nada se
 * borra en silencio (el trigger server-side alimenta esta tabla).
 * @param {string} asientoId uuid del asiento
 * @returns {Promise<Array<{accion:string, cuando:string, actor:string, detalle_cambio:object}>>}
 */
export async function cargarBitacora(asientoId) {
  const { data, error } = await supabase
    .from('asiento_bitacora')
    .select('accion, cuando, actor, detalle_cambio')
    .eq('asiento_id', asientoId)
    .order('cuando', { ascending: false });
  if (error) throw error;
  return data || [];
}

// ------------------------------------------------------------
// DESCARGA DE ARCHIVOS (helper compartido para exportaciones)
// ------------------------------------------------------------

/**
 * Dispara la descarga de un Blob con un nombre de archivo dado, usando el
 * patron estandar de navegador: URL.createObjectURL + un <a download>
 * sintetico + revoke del objeto URL. Compartido por las exportaciones
 * (CSV/PDF) del area para no duplicar la fontaneria de descarga.
 * @param {string} nombre nombre de archivo sugerido (p.ej. 'balance.csv')
 * @param {Blob} blob contenido a descargar
 */
export function descargarArchivo(nombre, blob) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = nombre;
  document.body.appendChild(a);
  a.click();
  a.remove();
  // Libera el objeto URL tras un tick para no cancelar la descarga.
  setTimeout(() => URL.revokeObjectURL(url), 0);
}
