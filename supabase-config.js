// ============================================================
//  MAGANDHI · CONFIG DEL CLIENTE SUPABASE (frontend interno)
//  ------------------------------------------------------------
//  Modulo ES que crea UNA sola instancia del cliente Supabase y la
//  exporta para que todas las paginas internas la reutilicen.
//
//  SEGURIDAD (lee esto antes de tocar nada):
//  · La "publishable key" de abajo es PUBLICA POR DISENO. Va en el
//    cliente, cualquiera que abra el navegador puede verla, y eso es
//    correcto: no da acceso a los datos por si sola.
//  · La seguridad REAL vive en las politicas RLS de la base de datos
//    (ver supabase/migrations/*.sql). El candado esta en los datos,
//    no en este archivo ni en el HTML.
//  · La secret key / service_role key NUNCA se pone aqui, ni en el
//    frontend, ni en el repo. Salta RLS y solo la usa el dueno desde
//    el dashboard de Supabase.
// ============================================================

// Version EXACTA (no '@2' flotante): '@2' deja que esm.sh sirva cualquier 2.x,
// incluida una futura que cambie comportamiento o, peor, una comprometida que
// correria con la sesion del usuario en todo el back-office. Al fijar 2.116.0
// el navegador siempre carga el mismo modulo auditado. Para subir de version:
// cambiar el numero aqui a proposito, verificar que esm.sh responde 200.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.116.0';

export const SUPABASE_URL = 'https://bxlzipwxyxdtffnuizbz.supabase.co';

// Publishable key: publica por diseno, protegida por RLS. NUNCA la secret.
export const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_ap4jdsO_0KPOPWhUk9Y7ZA_0jDUvHu1';

// Instancia unica del cliente. Importar { supabase } desde este modulo.
export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);

export default supabase;
