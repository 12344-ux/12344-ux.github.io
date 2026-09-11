// ============================================================
//  MAGANDHI · GUARDIA DE ACCESO INTERNO (reutilizable)
//  ------------------------------------------------------------
//  La llave que toda pagina interna futura incluye para quedar
//  cubierta con una sola linea:
//
//      <script type="module" src="auth-guard.js"></script>
//
//  Al cargar, comprueba que haya una sesion de Supabase Auth valida.
//  Si NO la hay, redirige al login (index.html) de inmediato.
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

const RUTA_LOGIN = 'index.html';

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
 * Exige una sesion valida. Si no la hay, redirige al login y devuelve
 * null. Si la hay, devuelve la sesion. Usar al inicio de cada pagina
 * interna protegida.
 */
export async function exigirSesion() {
  const sesion = await obtenerSesion();
  if (!sesion) {
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
  if (!sesion) return null;

  const { data, error } = await supabase
    .from('perfiles')
    .select('rol, modulos')
    .eq('id', sesion.user.id)
    .maybeSingle();

  if (error) {
    console.error('No se pudo leer el perfil:', error.message);
    return null;
  }
  return data;
}

// Auto-proteccion: al importar este modulo desde una pagina interna,
// se exige sesion inmediatamente. Una sola linea deja la pagina cubierta.
exigirSesion();
