// ============================================================
// MAGANDHI · frontera de identidad del back-office
// ------------------------------------------------------------
// Supabase Auth identifica tanto al personal como, en el futuro, a clientes.
// Una sesion valida NO basta para entrar a montaguth.institute: la persona debe
// tener ademas una fila en public.perfiles, que existe solo para personal.
//
// Este modulo no decide modulos concretos (Finanzas, Ventas, etc.). Esa segunda
// capa sigue en perfiles.modulos + RLS. Aqui se impone la primera frontera:
// cliente autenticado != personal interno.
// ============================================================

import { supabase } from './supabase-config.js';

// Una pagina interna importa la guardia directamente y, a menudo, tambien desde
// su core de area. Compartimos la misma consulta por UID para que una carga no
// pregunte perfiles dos o tres veces ni reciba veredictos contradictorios.
let perfilUid = null;
let perfilPromesa = null;

/**
 * Devuelve el perfil interno de la sesion o null cuando se comprobo que no
 * existe. Si la comprobacion falla (red/RLS), RECHAZA: no confundimos un error
 * transitorio con «esta identidad es cliente» y no destruimos una sesion
 * administrativa valida. La UI sigue fallando cerrada.
 * @param {object|null} sesion
 * @returns {Promise<{rol:string, modulos:string[]}|null>}
 */
export function obtenerPerfilInterno(sesion) {
  const uid = sesion?.user?.id;
  if (!uid) return Promise.resolve(null);
  if (uid === perfilUid && perfilPromesa) return perfilPromesa;

  perfilUid = uid;
  perfilPromesa = (async () => {
    try {
      const { data, error } = await supabase
        .from('perfiles')
        .select('rol, modulos')
        .eq('id', uid)
        .maybeSingle();

      if (error) throw error;
      return data ?? null;
    } catch (error) {
      // Un rechazo no se memoriza: un reintento en esta misma pagina vuelve a
      // consultar. Solo cacheamos los veredictos reales (perfil o ausencia).
      if (perfilUid === uid) {
        perfilUid = null;
        perfilPromesa = null;
      }
      console.error('No se pudo comprobar el acceso interno:', error?.message || error);
      throw error;
    }
  })();

  return perfilPromesa;
}

/**
 * Cierra solo la sesion de este navegador/origen y solo si aun pertenece al
 * UID que acabamos de rechazar. La segunda comprobacion evita que una promesa
 * antigua cierre una sesion nueva iniciada mientras tanto.
 * @param {string|null} uidEsperado
 * @returns {Promise<boolean>} true si se cerro esa sesion
 */
export async function cerrarSesionLocal(uidEsperado = null) {
  try {
    const { data, error } = await supabase.auth.getSession();
    const uidActual = data?.session?.user?.id;
    if (error || !uidActual || (uidEsperado && uidActual !== uidEsperado)) {
      return false;
    }

    const { error: errorSalida } = await supabase.auth.signOut({ scope: 'local' });
    return !errorSalida;
  } catch (_) {
    return false;
  }
}
