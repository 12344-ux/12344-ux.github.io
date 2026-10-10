// MAGANDHI · Edge Function · estado-pago (Pagos web · D0)
// ----------------------------------------------------------------------------
// Recibe del navegador (tienda magandhi.com)  { referencia }  y responde en que
// quedo ESE pago:
//   { estado: 'pendiente' | 'aprobado' | 'revision' | 'rechazado',
//     nombre_producto, slug }
//
// PARA QUE EXISTE
//   Al volver de Wompi, la ficha del producto se veia igual que antes y el boton
//   'Comprar ahora' seguia activo: la persona podia pagar dos veces. Ahora la
//   tienda pregunta por la referencia que trae en la URL y muestra la verdad,
//   sin inventarsela.
//
// ============================================================================
// LINEA ROJA DE SEGURIDAD
//   - La autorizacion es la POSESION de la referencia, igual que la posesion del
//     codigo_resena autoriza a opinar. La genera el servidor como
//     MAG-<idcorto>-<epochms>-<aleatorio>: no se adivina.
//   - La tabla pagos_intencion NO es legible por anon y asi se queda. Esta
//     funcion es la unica puerta, y solo puede llamar al RPC porque corre con
//     service_role: pw_estado_publico no tiene grant para anon ni authenticated.
//   - Responde el MINIMO. Nunca monto, correo, telefono, direccion, pedido_id,
//     transaccion_id, metodo de pago, motivo de revision ni entorno.
//   - La referencia NO se escribe en los logs: es la llave de consulta.
//   - La SERVICE_ROLE_KEY la inyecta el runtime en Deno.env; jamas se devuelve.
//
// SOLO LECTURA: no escribe en ninguna tabla. Si falla, la tienda degrada sola y
// muestra el mensaje prudente de 'seguimos confirmando tu pago'.
//
// Verify JWT: ENCENDIDO (la tienda llama con supabase.functions.invoke, que
// adjunta la publishable key; el candado real es que el RPC solo lo ejecuta
// service_role).
// Runbook: supabase/INSTRUCCIONES.md §D0
// Migracion: supabase/migrations/20261021000000_pagos_estado_publico.sql
// ============================================================================

// supabase-js pineado a la version EXACTA del proyecto (@2.116.0), por URL desde
// esm.sh (regla B2: version fija, nunca flotante).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.116.0";

// ----------------------------------------------------------------------------
// CORS: misma lista blanca que crear-intencion-pago y enviar-opinion (tienda con
// y sin www + el subdominio de GitHub Pages de desarrollo). No se usa '*' porque
// la tienda llama con la apikey en las cabeceras.
// ----------------------------------------------------------------------------
const ORIGENES_PERMITIDOS = new Set<string>([
  "https://magandhi.com",
  "https://www.magandhi.com",
  "https://12344-ux.github.io",
]);

function cabecerasCors(origin: string | null): Record<string, string> {
  const permitido = origin && ORIGENES_PERMITIDOS.has(origin)
    ? origin
    : "https://magandhi.com";
  return {
    "Access-Control-Allow-Origin": permitido,
    "Access-Control-Allow-Headers":
      "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function json(
  cuerpo: unknown,
  status: number,
  cors: Record<string, string>,
): Response {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: {
      ...cors,
      "Content-Type": "application/json; charset=utf-8",
      // El estado de un pago cambia en segundos (lo mueve el webhook): ninguna
      // capa intermedia debe guardar esta respuesta.
      "Cache-Control": "no-store",
    },
  });
}

// Mismo formato que el check de pagos_intencion.referencia. Se valida aqui y
// otra vez dentro del RPC.
const FORMATO_REFERENCIA = /^[A-Za-z0-9_-]{6,64}$/;

// Vocabulario publico permitido. Si el RPC devolviera algo fuera de esta lista
// (porque alguien agrego un estado nuevo a pagos_intencion y olvido traducirlo),
// se responde 'pendiente': el caso prudente es decir que seguimos confirmando,
// nunca afirmar que el pago quedo listo.
const ESTADOS_PUBLICOS = new Set<string>([
  "pendiente",
  "aprobado",
  "revision",
  "rechazado",
]);

Deno.serve(async (req: Request): Promise<Response> => {
  const origin = req.headers.get("origin");
  const cors = cabecerasCors(origin);

  // --- CORS preflight -------------------------------------------------------
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }

  // --- Solo POST ------------------------------------------------------------
  // POST aunque sea una lectura: asi la referencia viaja en el cuerpo y no en la
  // URL, donde quedaria en los logs de la plataforma.
  if (req.method !== "POST") {
    return json({ error: "Metodo no permitido; usa POST." }, 405, cors);
  }

  // --- Leer y validar el body ----------------------------------------------
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Body invalido; se esperaba JSON." }, 400, cors);
  }

  const referencia = typeof body?.referencia === "string"
    ? body.referencia.trim()
    : "";

  if (!referencia || !FORMATO_REFERENCIA.test(referencia)) {
    // Mismo 404 que una referencia inexistente: no se confirma si existe o no.
    return json({ error: "Referencia no encontrada." }, 404, cors);
  }

  // --- Cliente Supabase server-side (SERVICE_ROLE, inyectada por el runtime) -
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json(
      { error: "Configuracion del servidor incompleta (Supabase)." },
      500,
      cors,
    );
  }
  // Se fuerza la SERVICE_ROLE en Authorization: sin esto supabase-js heredaria
  // el JWT anon del navegador y pw_estado_publico -cerrada a anon- fallaria.
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${serviceRoleKey}` } },
  });

  // --- Consultar por RPC (unica puerta) ------------------------------------
  const { data, error } = await supabase.rpc("pw_estado_publico", {
    p_referencia: referencia,
  });

  if (error) {
    // DIAGNOSTICO sin la referencia (es la llave) y sin secretos.
    console.error(
      "[estado-pago] Fallo pw_estado_publico:",
      JSON.stringify({
        message: error?.message ?? null,
        code: (error as { code?: string } | null)?.code ?? null,
        details: (error as { details?: string } | null)?.details ?? null,
      }),
    );
    return json({ error: "No se pudo consultar el estado del pago." }, 500, cors);
  }

  // El RPC devuelve 0 filas cuando la referencia no existe (o esta mal formada).
  const fila = Array.isArray(data) ? data[0] : data;
  if (!fila) {
    return json({ error: "Referencia no encontrada." }, 404, cors);
  }

  const bruto = typeof fila.estado === "string" ? fila.estado : "";
  const estado = ESTADOS_PUBLICOS.has(bruto) ? bruto : "pendiente";

  return json(
    {
      estado,
      nombre_producto: typeof fila.nombre_producto === "string"
        ? fila.nombre_producto
        : "",
      slug: typeof fila.slug === "string" ? fila.slug : "",
    },
    200,
    cors,
  );
});
