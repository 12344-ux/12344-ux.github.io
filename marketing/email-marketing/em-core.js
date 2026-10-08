// ============================================================
// MAGANDHI · Marketing · EMAIL MARKETING · nucleo compartido (em-core.js)
// ------------------------------------------------------------
// Reutiliza el header institucional, iconos y cliente Supabase del Area de
// Marketing (marketing-core.js) y agrega lo propio del Email marketing:
//   - acceso por MODULO PROPIO 'email_marketing' (la lista es PII);
//   - sub-navegacion del area (Resumen · Contactos · ... · Seguimiento);
//   - formatos de fecha, etiquetas de estado/fuente/canal e iconos extra.
// El candado real es RLS + RPC (tiene_acceso_email_marketing()); ocultar UI
// es solo comodidad.
// ============================================================
import {
  supabase, exigirSesion, obtenerPerfil, montarHeader, ICONOS, escaparHTML, formatearNumero
} from '../marketing-core.js';

export { supabase, montarHeader, ICONOS, escaparHTML, formatearNumero };

// ------------------------------------------------------------
// Iconos extra (trazo Lucide, licencia ISC, mismo grosor del set)
// ------------------------------------------------------------
const svg = (d) => '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + d + '</svg>';
ICONOS.sobre = svg('<rect width="20" height="16" x="2" y="4" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/>');
ICONOS.usuarios = svg('<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>');
ICONOS.usuarioMas = svg('<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M19 8v6M22 11h-6"/>');
ICONOS.escudo = svg('<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/><path d="m9 12 2 2 4-4"/>');
ICONOS.historial = svg('<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5M12 7v5l4 2"/>');
ICONOS.enviar = svg('<path d="M14.536 21.686a.5.5 0 0 0 .937-.024l6.5-19a.496.496 0 0 0-.635-.635l-19 6.5a.5.5 0 0 0-.024.937l7.93 3.18a2 2 0 0 1 1.112 1.11z"/><path d="m21.854 2.147-10.94 10.939"/>');
ICONOS.capas = svg('<path d="m12.83 2.18 8.58 3.9a1 1 0 0 1 0 1.83l-8.58 3.9a2 2 0 0 1-1.66 0L2.6 7.91a1 1 0 0 1 0-1.83l8.58-3.9a2 2 0 0 1 1.66 0Z"/><path d="m2.6 12.08 8.57 3.9a2 2 0 0 0 1.66 0l8.57-3.9M2.6 16.95l8.57 3.9a2 2 0 0 0 1.66 0l8.57-3.9"/>');
ICONOS.check = svg('<path d="M20 6 9 17l-5-5"/>');
ICONOS.alerta = svg('<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4M12 17h.01"/>');
ICONOS.enlace = svg('<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>');
ICONOS.panel = svg('<rect width="7" height="9" x="3" y="3" rx="1"/><rect width="7" height="5" x="14" y="3" rx="1"/><rect width="7" height="9" x="14" y="12" rx="1"/><rect width="7" height="5" x="3" y="16" rx="1"/>');

// ------------------------------------------------------------
// Acceso
// ------------------------------------------------------------
export function tieneAccesoEM(perfil) {
  if (!perfil) return false;
  if (perfil.rol === 'admin') return true;
  const m = Array.isArray(perfil.modulos) ? perfil.modulos : [];
  return m.includes('email_marketing');
}

/** Sesion + modulo email_marketing. Sin acceso pinta el aviso y devuelve null. */
export async function asegurarAccesoEM(contenedor, volverHref) {
  const sesion = await exigirSesion();
  if (!sesion) return null;
  let perfil = null;
  try { perfil = await obtenerPerfil(); } catch (_) { perfil = null; }
  if (!tieneAccesoEM(perfil)) {
    if (contenedor) {
      contenedor.innerHTML =
        '<div class="mk-denegado">' +
          '<h2>Acceso restringido</h2>' +
          '<p>Tu cuenta no tiene habilitado el <strong>Email marketing</strong>. La lista de contactos es información personal y requiere un permiso propio. Solicítalo a un administrador.</p>' +
          '<p style="margin-top:14px"><a href="' + escaparHTML(volverHref || '../index.html') + '">Volver a Marketing</a></p>' +
        '</div>';
    }
    return null;
  }
  return { sesion, perfil };
}

// ------------------------------------------------------------
// Header + sub-navegacion del area
// ------------------------------------------------------------
const TABS = [
  { id: 'resumen', txt: 'Resumen', href: 'index.html', ico: 'panel' },
  { id: 'contactos', txt: 'Contactos', href: 'contactos.html', ico: 'usuarios' },
  { id: 'segmentos', txt: 'Segmentos', ico: 'capas', pronto: true },
  { id: 'campanas', txt: 'Campañas', ico: 'enviar', pronto: true },
  { id: 'seguimiento', txt: 'Correos de seguimiento', href: 'seguimiento.html', ico: 'historial', menor: true }
];

/** Monta header institucional + sub-navegacion con la pestaña activa. */
export function montarArea({ activa, titulo, lead, sesion }) {
  montarHeader({
    titulo,
    kicker: 'MARKETING · EMAIL MARKETING',
    lead,
    sesion,
    areaLabel: 'ÁREA DE MARKETING',
    volverHref: '../index.html',
    volverTexto: 'Marketing'
  });
  const nav = document.createElement('nav');
  nav.className = 'em-subnav';
  nav.setAttribute('aria-label', 'Secciones de Email marketing');
  nav.innerHTML = '<div class="em-subnav-in">' + TABS.map((t) => {
    const cls = 'em-tab' + (t.id === activa ? ' on' : '') + (t.pronto ? ' pronto' : '') + (t.menor ? ' menor' : '');
    const cuerpo = (ICONOS[t.ico] || '') + '<span>' + escaparHTML(t.txt) + '</span>' +
      (t.pronto ? '<span class="em-pill">Pronto</span>' : '');
    return t.pronto
      ? '<span class="' + cls + '" aria-disabled="true" title="Llega en un próximo tramo">' + cuerpo + '</span>'
      : '<a class="' + cls + '" href="' + t.href + '"' + (t.id === activa ? ' aria-current="page"' : '') + '>' + cuerpo + '</a>';
  }).join('') + '</div>';
  const head = document.querySelector('.mk-screen-head');
  head.insertAdjacentElement('afterend', nav);
}

// ------------------------------------------------------------
// Etiquetas
// ------------------------------------------------------------
export const ESTADOS = {
  suscrito: { txt: 'Suscrito', cls: 'suscrito' },
  pendiente_confirmacion: { txt: 'Por confirmar', cls: 'pendiente' },
  baja: { txt: 'De baja', cls: 'baja' },
  rebotado: { txt: 'Rebotado', cls: 'problema' },
  queja: { txt: 'Marcó spam', cls: 'problema' }
};
export const FUENTES = {
  manual: 'Registro manual',
  formulario_tienda: 'Formulario de la tienda',
  casilla_checkout: 'Casilla al comprar',
  importacion_con_evidencia: 'Importación con evidencia'
};
export const CANALES = {
  whatsapp: 'WhatsApp',
  presencial: 'En persona',
  llamada: 'Llamada',
  correo: 'Correo',
  otro: 'Otro'
};
export const ETAPAS = {
  recibido: 'Recibido', preparando: 'Preparando', en_camino: 'En camino', entregado: 'Entregado'
};

export function badgeEstado(estado) {
  const e = ESTADOS[estado] || { txt: estado, cls: '' };
  return '<span class="em-badge ' + e.cls + '">' + escaparHTML(e.txt) + '</span>';
}

// ------------------------------------------------------------
// Fechas (zona local, español)
// ------------------------------------------------------------
const MESES = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

export function formatearFecha(iso) {
  if (!iso) return '—';
  const d = new Date(String(iso).length === 10 ? iso + 'T12:00:00' : iso);
  if (isNaN(d)) return '—';
  return d.getDate() + ' ' + MESES[d.getMonth()] + ' ' + d.getFullYear();
}

export function formatearMomento(iso) {
  if (!iso) return '—';
  const d = new Date(iso);
  if (isNaN(d)) return '—';
  const hh = String(d.getHours()).padStart(2, '0');
  const mm = String(d.getMinutes()).padStart(2, '0');
  return formatearFecha(iso) + ' · ' + hh + ':' + mm;
}

export function fechaRelativa(iso) {
  if (!iso) return '—';
  const d = new Date(iso);
  const dias = Math.floor((Date.now() - d.getTime()) / 86400000);
  if (dias <= 0) return 'Hoy';
  if (dias === 1) return 'Ayer';
  if (dias < 7) return 'Hace ' + dias + ' días';
  if (dias < 30) { const s = Math.floor(dias / 7); return 'Hace ' + s + (s === 1 ? ' semana' : ' semanas'); }
  if (dias < 365) { const m = Math.floor(dias / 30); return 'Hace ' + m + (m === 1 ? ' mes' : ' meses'); }
  const a = Math.floor(dias / 365); return 'Hace ' + a + (a === 1 ? ' año' : ' años');
}

export function hoyISO() {
  const d = new Date();
  return d.getFullYear() + '-' + String(d.getMonth() + 1).padStart(2, '0') + '-' + String(d.getDate()).padStart(2, '0');
}

export function formatearCOP(n) {
  return '$' + formatearNumero(n);
}

// ------------------------------------------------------------
// Errores estables de los RPC (EM_*) -> mensaje claro
// ------------------------------------------------------------
export function mensajeError(err) {
  const m = (err && err.message) || String(err || '');
  const tabla = [
    ['EM_SIN_ACCESO', 'Tu usuario no tiene el permiso de Email marketing.'],
    ['EM_CORREO_INVALIDO', 'Ese correo no parece válido. Revísalo.'],
    ['EM_CANAL_INVALIDO', 'Elige por dónde dio la autorización.'],
    ['EM_EVIDENCIA_REQUERIDA', 'Describe cómo autorizó la persona (mínimo 10 caracteres). Es la prueba legal del permiso.'],
    ['EM_CONFIRMACION_REQUERIDA', 'Marca la casilla confirmando que la persona autorizó de forma expresa.'],
    ['EM_TEMAS_REQUERIDOS', 'Elige al menos un tema (Novedades u Ofertas).'],
    ['EM_FECHA_INVALIDA', 'La fecha de autorización no puede ser futura.'],
    ['EM_CONTACTO_YA_EXISTE', 'Ese correo ya está en la lista.'],
    ['EM_CONTACTO_INACTIVO', 'Ese correo está en la lista pero inactivo (se dio de baja o tuvo un problema).'],
    ['EM_CONTACTO_NO_EXISTE', 'El contacto no existe.'],
    ['EM_MOTIVO_REQUERIDO', 'Escribe el motivo de la baja.']
  ];
  for (const [k, t] of tabla) if (m.includes(k)) return t;
  return 'No se pudo completar: ' + m;
}
