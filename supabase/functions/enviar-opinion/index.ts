// ============================================================================
// MAGANDHI · Edge Function · enviar-opinion (Software de Opiniones)
// ----------------------------------------------------------------------------
// Recibe del navegador (tienda magandhi.com) una opinion de cliente:
//   { codigo, slug, estrellas, comentario?, autor, es_prueba? }
// y la registra SOLO si el codigo corresponde a un pedido ENTREGADO que
// contenia ese producto. Toda la validacion ocurre server-side en el RPC
// SECURITY DEFINER op_registrar_opinion; esta funcion es la puerta publica que
// lo invoca con la service_role y traduce los errores a mensajes amables.
//
// ============================================================================
// LINEA ROJA DE SEGURIDAD (orden permanente del dueno · NO negociable):
//   - La tabla `opiniones` NO acepta escritura publica directa (si anon pudiera
//     insertar, cualquiera inyectaria reseñas falsas). La UNICA puerta es este
//     flujo: Edge Function (service_role) -> op_registrar_opinion.
//   - La autorizacion para opinar es la POSESION del CODIGO del pedido (no hay
//     login). El codigo es secreto por pedido y llega al cliente por correo
//     (fase siguiente). NUNCA se expone a anon ni se devuelve aqui.
//   - La SERVICE_ROLE_KEY la inyecta el runtime de Supabase en Deno.env; jamas
//     se hardcodea ni se devuelve al navegador. No se loguea ningun secreto.
//   - El codigo que escribe el cliente NO se registra en los logs (es secreto).
// ============================================================================

// supabase-js pineado a la version EXACTA del proyecto (@2.116.0), por URL desde
// esm.sh (regla B2: version fija, nunca flotante).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.116.0";

// ----------------------------------------------------------------------------
// CORS: misma lista blanca que crear-intencion-pago (tienda con/sin www + el
// subdominio de GitHub Pages de desarrollo). No se usa '*' porque la tienda
// llama con la apikey en las cabeceras.
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
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8" },
  });
}

// ----------------------------------------------------------------------------
// Traduce el codigo de error que levanta op_registrar_opinion a un mensaje
// amable + el HTTP adecuado. El RPC levanta excepciones con textos estables
// (OPINION_*); PostgREST las devuelve en error.message. Se busca por inclusion.
// ----------------------------------------------------------------------------
function traducirError(
  mensaje: string,
): { status: number; texto: string } {
  const m = mensaje || "";
  if (m.includes("OPINION_CODIGO_REQUERIDO")) {
    return { status: 400, texto: "Falta el código de reseña." };
  }
  if (m.includes("OPINION_CODIGO_INVALIDO")) {
    return { status: 404, texto: "El código de reseña no es válido." };
  }
  if (m.includes("OPINION_PEDIDO_NO_ENTREGADO")) {
    return {
      status: 409,
      texto: "Este pedido todavía no figura como entregado.",
    };
  }
  if (m.includes("OPINION_PRODUCTO_INVALIDO")) {
    return { status: 404, texto: "No encontramos el producto." };
  }
  if (m.includes("OPINION_PRODUCTO_NO_EN_PEDIDO")) {
    return {
      status: 409,
      texto: "Este código no corresponde a una compra de este producto.",
    };
  }
  if (m.includes("OPINION_YA_REGISTRADA")) {
    return {
      status: 409,
      texto: "Ya habías dejado tu opinión para este producto. ¡Gracias!",
    };
  }
  if (m.includes("OPINION_ESTRELLAS_INVALIDAS")) {
    return { status: 400, texto: "Elige entre 1 y 5 estrellas." };
  }
  if (m.includes("OPINION_AUTOR_REQUERIDO")) {
    return { status: 400, texto: "Dinos cómo quieres aparecer." };
  }
  return { status: 500, texto: "No se pudo registrar la opinión." };
}

Deno.serve(async (req: Request): Promise<Response> => {
  const origin = req.headers.get("origin");
  const cors = cabecerasCors(origin);

  // --- CORS preflight -------------------------------------------------------
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }

  // --- Solo POST ------------------------------------------------------------
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

  const codigo = typeof body?.codigo === "string" ? body.codigo.trim() : "";
  const slug = typeof body?.slug === "string" ? body.slug.trim() : "";
  const autor = typeof body?.autor === "string" ? body.autor.trim() : "";
  const comentario = typeof body?.comentario === "string"
    ? body.comentario
    : null;
  const estrellas = Number(body?.estrellas);
  const esPrueba = body?.es_prueba === true;

  // Validacion minima en el borde (el RPC vuelve a validar todo server-side).
  if (!codigo) {
    return json({ error: "Falta el código de reseña." }, 400, cors);
  }
  if (!slug) {
    return json({ error: "Falta el producto." }, 400, cors);
  }
  if (!Number.isInteger(estrellas) || estrellas < 1 || estrellas > 5) {
    return json({ error: "Elige entre 1 y 5 estrellas." }, 400, cors);
  }
  if (!autor) {
    return json({ error: "Dinos cómo quieres aparecer." }, 400, cors);
  }

  // DIAGNOSTICO: marca de entrada SIN el codigo (es secreto) ni datos sensibles.
  console.log(
    "[enviar-opinion] Opinion recibida:",
    JSON.stringify({ slug, estrellas, es_prueba: esPrueba }),
  );

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
  // Se fuerza la SERVICE_ROLE en Authorization para que el RPC definer se
  // ejecute con service_role (sin esto, supabase-js heredaria el JWT anon de la
  // peticion del navegador y op_registrar_opinion -cerrada a anon- fallaria).
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${serviceRoleKey}` } },
  });

  // --- Registrar la opinion por RPC (unica puerta de escritura) -------------
  const { data, error } = await supabase.rpc("op_registrar_opinion", {
    p_codigo: codigo,
    p_slug: slug,
    p_estrellas: estrellas,
    p_comentario: comentario,
    p_autor: autor,
    p_es_prueba: esPrueba,
  });

  if (error) {
    // DIAGNOSTICO: detalle real del fallo (sin el codigo del cliente ni secretos).
    console.error(
      "[enviar-opinion] Fallo op_registrar_opinion:",
      JSON.stringify({
        message: error?.message ?? null,
        code: (error as { code?: string } | null)?.code ?? null,
        details: (error as { details?: string } | null)?.details ?? null,
        hint: (error as { hint?: string } | null)?.hint ?? null,
        slug,
      }),
    );
    const t = traducirError(error?.message ?? "");
    return json({ error: t.texto }, t.status, cors);
  }

  // Exito: devolvemos solo el ok (el id no es necesario en el navegador).
  return json({ ok: true, id: data ?? null }, 200, cors);
});
