// ============================================================
//  MAGANDHI · GUARDIA DE ACCESO INTERNO (reutilizable)
//  ------------------------------------------------------------
//  La llave que toda pagina interna futura incluye para quedar
//  cubierta con una sola linea:
//
//      <script type="module" src="auth-guard.js"></script>
//
//  Al cargar, comprueba DOS cosas: que haya una sesion valida y que su UID
//  tenga una fila en perfiles (personal interno). Una futura cuenta de cliente
//  de magandhi.com tambien tendra Supabase Auth, pero NUNCA perfil interno: se
//  cierra solo la sesion de este origen y se redirige al login.
//
//  IMPORTANTE (no te confundas de candado):
//  · Ocultar o redirigir una pagina es solo COMODIDAD DE UX, no
//    seguridad. Un usuario decidido puede saltarse el redirect.
//  · La seguridad REAL esta en las politicas RLS sobre los datos:
//    aunque alguien vea el HTML del panel, no puede leer ni modificar
//    datos sin una sesion valida y sin permiso en la base.
//  · Por eso este guardia protege la experiencia, y RLS protege los
//    datos. Los dos, juntos.
// ============================================================

import { supabase } from './supabase-config.js';
import { obtenerPerfilInterno, cerrarSesionLocal } from './acceso-interno.js';

// Ruta al login resuelta SIEMPRE respecto a la raiz del sitio, no relativa
// a la pagina actual. Asi funciona igual desde la raiz (panel.html) que
// desde subcarpetas (finanzas/*.html): sin este calculo, un 'index.html'
// relativo desde finanzas/ apuntaria a finanzas/index.html (loop).
//
// Este modulo se sirve siempre desde la raiz del sitio (../auth-guard.js
// desde finanzas/, ./auth-guard.js desde la raiz), por lo que la carpeta
// que lo contiene ES la raiz del sitio. La derivamos de import.meta.url.
const RUTA_LOGIN = new URL('index.html', import.meta.url).href;

/**
 * Devuelve la sesion actual o null.
 */
export async function obtenerSesion() {
  const { data, error } = await supabase.auth.getSession();
  if (error) {
    console.error('No se pudo leer la sesion:', error.message);
    return null;
  }
  return data.session ?? null;
}

/**
 * Exige una sesion de PERSONAL INTERNO. Una sesion Auth sin fila en perfiles
 * (caso de una cuenta cliente) falla cerrado: se elimina solo de este origen,
 * se redirige al login y devuelve null. Las RLS/RPC siguen siendo el candado
 * autoritativo de cada dato y modulo.
 */
export async function exigirSesion() {
  const sesion = await obtenerSesion();
  if (!sesion) {
    window.location.replace(RUTA_LOGIN);
    return null;
  }

  let perfil;
  try {
    perfil = await obtenerPerfilInterno(sesion);
  } catch (_) {
    // Verificacion indisponible: el panel sigue cerrado, pero no destruimos una
    // sesion que puede ser de personal. Al volver al login se podra reintentar.
    window.location.replace(RUTA_LOGIN);
    return null;
  }

  if (!perfil) {
    await cerrarSesionLocal(sesion.user.id);
    window.location.replace(RUTA_LOGIN);
    return null;
  }

  return sesion;
}

/**
 * Lee el perfil (rol y modulos) del usuario actual respetando RLS:
 * la base solo devuelve la fila cuya id coincide con auth.uid().
 * Devuelve null si no hay sesion o si no se puede leer.
 */
export async function obtenerPerfil() {
  const sesion = await obtenerSesion();
  return obtenerPerfilInterno(sesion);
}

// Auto-proteccion: al importar este modulo desde una pagina interna,
// se exige sesion inmediatamente. Una sola linea deja la pagina cubierta.
//
// NOTA (decision consciente): las paginas de finanzas ademas llaman
// asegurarAcceso(), que reejecuta exigirSesion()->getSession(). Eso hace DOS
// getSession por carga. Se mantiene a proposito: (1) esta guardia autoejecutada
// es el contrato "una sola linea protege cualquier pagina interna" (paginas sin
// modulos, como panel.html, dependen solo de ella); (2) supabase-js cachea la
// sesion en memoria/almacenamiento, asi que el segundo getSession es local y
// barato (no es un round-trip de red). El coste es un microsegundo, no un
// problema de rendimiento; unificarlo acoplaria el guardia al flujo de finanzas.
exigirSesion();
