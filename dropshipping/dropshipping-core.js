// MAGANDHI · DROPSHIPPING · núcleo compartido (D1)
// ----------------------------------------------------------------------------
// Una séptima área propia, no una sub-área de Inventario ni de Marketing.
// Reúne lo que puede consultar/curar MAGANDHI antes de que exista un producto
// público: candidatos, proveedor, lecturas de disponibilidad y —en tramos
// futuros— reservas/despachos. D1 es lectura + bandeja, sin orders/ ni pagos.
//
// El color no estrena una paleta: hereda azul operativo y terracota de marca.
// «No quiero un arcoíris»: el área se distingue por su contrato (proveedor ≠
// bodega propia), no por un color decorativo nuevo.
// ----------------------------------------------------------------------------

import { supabase } from '../supabase-config.js';
import { exigirSesion, obtenerPerfil } from '../auth-guard.js';

export { supabase, exigirSesion, obtenerPerfil };

export function escaparHTML(v) {
  return String(v == null ? '' : v)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

export function formatearCOP(v) {
  const n = Math.trunc(Number(v) || 0);
  const signo = n < 0 ? '-' : '';
  return signo + Math.abs(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, '.');
}

export function formatearMomento(iso) {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return String(iso);
  const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  return `${String(d.getDate()).padStart(2, '0')} ${meses[d.getMonth()]} ${d.getFullYear()}, ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
}

// UX y datos hablan las mismas claves. La seguridad real de la bandeja vive
// en tiene_acceso_dropshipping() + RLS; aquí solo se evita mostrar una pantalla
// inútil. D1 mantiene dropi-sonda como lectura exclusiva de admin hasta D3.
export function tieneAccesoDropshipping(perfil) {
  if (!perfil) return false;
  if (perfil.rol === 'admin') return true;
  const modulos = Array.isArray(perfil.modulos) ? perfil.modulos : [];
  return modulos.includes('dropshipping') || modulos.includes('proveedores') || modulos.includes('despachos');
}

export async function asegurarAcceso(contenedor, volverHref = '../panel.html') {
  const sesion = await exigirSesion();
  if (!sesion) return null;
  let perfil = null;
  try { perfil = await obtenerPerfil(); } catch (_) { perfil = null; }
  if (!tieneAccesoDropshipping(perfil)) {
    if (contenedor) {
      contenedor.innerHTML =
        '<section class="ds-denegado"><h2>Acceso restringido · Dropshipping</h2>' +
        '<p>Tu cuenta no tiene habilitada esta área. Solicita el acceso a un administrador.</p>' +
        '<p><a href="' + escaparHTML(volverHref) + '">Volver al panel</a></p></section>';
      contenedor.hidden = false;
    }
    return null;
  }
  return { sesion, perfil };
}

export const ICONOS = {
  flecha: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>',
  salir: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5M21 12H9"/></svg>',
  lupa: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>',
  caja: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m21 8-9-5-9 5 9 5 9-5Z"/><path d="M3 8v8l9 5 9-5V8"/><path d="m12 13v8"/></svg>',
  proveedor: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m7 4 10 5-10 5-4-2v6l4 2 10-5v-6L7 4Z"/><path d="M3 12V7l4-2"/><path d="M7 14v6"/><path d="M17 9v6"/><path d="m13 18 2 2 4-4"/></svg>',
  bandeja: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 5h18l-2 14H5L3 5Z"/><path d="M3 13h5l2 3h4l2-3h5"/></svg>',
  reloj: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>',
  info: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/></svg>',
  alerta: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z"/><path d="M12 9v4M12 17h.01"/></svg>',
  check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>',
  ojo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/></svg>',
  equis: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18M6 6l12 12"/></svg>',
};

export function rutaRaiz() {
  try {
    const path = window.location.pathname;
    const partes = path.split('/').filter(Boolean);
    // GitHub Pages puede servir la misma página como /dropshipping/ (sin nombre
    // de archivo) o /dropshipping/index.html. En el primer caso la única parte
    // YA es una carpeta; en el segundo, la última parte es el archivo.
    const carpetas = path.endsWith('/') ? partes.length : Math.max(partes.length - 1, 0);
    return carpetas > 0 ? '../'.repeat(carpetas) : './';
  } catch (_) { return '../'; }
}

export function montarHeader(opts = {}) {
  const email = opts.sesion?.user?.email || '';
  const inicial = (email.trim()[0] || 'M').toUpperCase();
  const raiz = rutaRaiz();
  const header = document.createElement('header');
  header.className = 'ds-header';
  header.innerHTML =
    '<div class="ds-header-left">' +
      '<a class="ds-volver" href="' + escaparHTML(opts.volverHref || '../panel.html') + '" aria-label="Volver a ' + escaparHTML(opts.volverTexto || 'Panel') + '">' +
        ICONOS.flecha + '<span>' + escaparHTML(opts.volverTexto || 'Panel') + '</span></a>' +
      '<span class="ds-sep" aria-hidden="true"></span>' +
      '<img class="ds-logo" src="' + escaparHTML(opts.logoSrc || (raiz + 'logo-mark-terracota.png?v=2')) + '" alt="Magandhi">' +
      '<span class="ds-word">MAGANDHI</span><span class="ds-sep" aria-hidden="true"></span>' +
      '<span class="ds-area">' + escaparHTML(opts.areaLabel || 'DROPSHIPPING') + '</span>' +
    '</div>' +
    '<div class="ds-header-right"><div class="ds-perfil">' +
      '<button class="ds-avatar" id="ds-avatar" type="button" aria-haspopup="menu" aria-expanded="false" aria-controls="ds-perfil-menu" title="' + escaparHTML(email) + '" aria-label="Menú de perfil">' + escaparHTML(inicial) + '</button>' +
      '<div class="ds-perfil-menu" id="ds-perfil-menu" role="menu" hidden>' +
        '<div class="ds-perfil-info"><span>Sesión iniciada como</span><b>' + escaparHTML(email || 'usuario interno') + '</b></div>' +
        '<button class="ds-perfil-salir" id="ds-perfil-salir" type="button" role="menuitem">' + ICONOS.salir + '<span>Cerrar sesión</span></button>' +
      '</div>' +
    '</div></div>';

  const screen = document.createElement('div');
  screen.className = 'ds-screen-head';
  screen.innerHTML =
    '<p class="ds-kicker">' + escaparHTML(opts.kicker || '') + '</p>' +
    '<h1 class="ds-title">' + escaparHTML(opts.titulo || '') + '</h1>' +
    (opts.lead ? '<p class="ds-lead">' + escaparHTML(opts.lead) + '</p>' : '');

  document.body.insertBefore(screen, document.body.firstChild);
  document.body.insertBefore(header, document.body.firstChild);
  montarMenuPerfil(header, raiz);
  montarSelloImpulse();
}

function montarMenuPerfil(header, raiz) {
  const avatar = header.querySelector('#ds-avatar');
  const menu = header.querySelector('#ds-perfil-menu');
  const salir = header.querySelector('#ds-perfil-salir');
  if (!avatar || !menu) return;
  const abierto = () => avatar.getAttribute('aria-expanded') === 'true';
  const cerrar = (foco = false) => { menu.hidden = true; avatar.setAttribute('aria-expanded', 'false'); if (foco) avatar.focus(); };
  avatar.addEventListener('click', (e) => { e.stopPropagation(); if (abierto()) cerrar(); else { menu.hidden = false; avatar.setAttribute('aria-expanded', 'true'); salir?.focus(); } });
  document.addEventListener('click', (e) => { if (abierto() && !menu.contains(e.target) && e.target !== avatar) cerrar(); });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && abierto()) cerrar(true); });
  salir?.addEventListener('click', async () => {
    try { await supabase.auth.signOut(); } catch (_) { /* no bloquear logout */ }
    window.location.replace(raiz + 'index.html');
  });
}

export function montarSelloImpulse() {
  if (document.querySelector('.ds-sello')) return;
  const pie = document.createElement('footer');
  pie.className = 'ds-sello';
  pie.innerHTML = 'Con tecnología <span>Impulse</span>';
  document.body.appendChild(pie);
}
