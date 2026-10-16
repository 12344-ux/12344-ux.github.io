// ============================================================================
// MAGANDHI · Edge Function · cuenta-inicializar (Cuentas de cliente C2)
// ----------------------------------------------------------------------------
// Puerta autenticada y delgada para POST {}. Valida el JWT con getUser y llama
// cc_inicializar_cuenta() con el MISMO JWT. No usa service_role, no acepta UID,
// correo, proveedor ni customer_id y no devuelve PII.
// ============================================================================
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.116.0";

const ORIGENES_PERMITIDOS = new Set<string>([
  "https://magandhi.com",
  "https://www.magandhi.com",
  "https://12344-ux.github.io",
]);

function cabecerasCors(origin: string | null): Record<string, string> {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers":
      "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Cache-Control": "no-store",
    Vary: "Origin",
  };
  if (origin && ORIGENES_PERMITIDOS.has(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
  }
  return headers;
}

function json(
  cuerpo: unknown,
  status: number,
  headers: Record<string, string>,
): Response {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: {
      ...headers,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
  });
}

const ERRORES: Array<[string, number, string, string]> = [
  ["CC_SESION_REQUERIDA", 401, "Inicia sesión para continuar.", "CC_SESION"],
  [
    "CC_SESION_INVALIDA",
    401,
    "Tu sesión no es válida. Vuelve a iniciar sesión.",
    "CC_SESION",
  ],
  [
    "CC_CORREO_NO_CONFIRMADO",
    403,
    "Confirma tu correo antes de continuar.",
    "CC_CONFIRMACION_REQUERIDA",
  ],
  [
    "CC_IDENTIDAD_ES_PERSONAL",
    403,
    "No pudimos habilitar esta cuenta.",
    "CC_NO_DISPONIBLE",
  ],
  [
    "CC_CUENTA_NO_DISPONIBLE",
    403,
    "No pudimos habilitar esta cuenta.",
    "CC_NO_DISPONIBLE",
  ],
];

function traducirError(mensaje: string) {
  for (const [marca, status, texto, codigo] of ERRORES) {
    if (mensaje.includes(marca)) return { status, texto, codigo };
  }
  return {
    status: 500,
    texto: "No pudimos preparar tu cuenta. Inténtalo de nuevo.",
    codigo: "CC_ERROR",
  };
}

async function leerCuerpoLimitado(
  req: Request,
  maxBytes: number,
): Promise<{ texto: string; excedido: boolean }> {
  if (!req.body) return { texto: "", excedido: false };
  const lector = req.body.getReader();
  const decoder = new TextDecoder();
  let total = 0;
  let texto = "";
  try {
    while (true) {
      const { done, value } = await lector.read();
      if (done) break;
      total += value.byteLength;
      if (total > maxBytes) {
        await lector.cancel("body demasiado grande");
        return { texto: "", excedido: true };
      }
      texto += decoder.decode(value, { stream: true });
    }
    texto += decoder.decode();
    return { texto, excedido: false };
  } finally {
    lector.releaseLock();
  }
}

Deno.serve(async (req: Request): Promise<Response> => {
  const origin = req.headers.get("origin");
  const cors = cabecerasCors(origin);

  // La Function es exclusivamente para los tres orígenes web declarados.
  if (!origin || !ORIGENES_PERMITIDOS.has(origin)) {
    return json({ error: "Origen no permitido." }, 403, cors);
  }

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (req.method !== "POST") {
    return json({ error: "Método no permitido; usa POST." }, 405, cors);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const jwt = (req.headers.get("authorization") ?? "")
    .replace(/^Bearer\s+/i, "")
    .trim();

  if (!supabaseUrl || !anonKey) {
    return json({ error: "Configuración del servidor incompleta." }, 500, cors);
  }
  if (!jwt) {
    return json(
      { error: "Inicia sesión para continuar.", codigo: "CC_SESION" },
      401,
      cors,
    );
  }

  // ANON key + JWT real de la persona. Nunca se crea un cliente service_role.
  const supabase = createClient(supabaseUrl, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });

  const { data: usuario, error: errorUsuario } =
    await supabase.auth.getUser(jwt);
  if (errorUsuario || !usuario?.user) {
    return json(
      {
        error: "Tu sesión no es válida. Vuelve a iniciar sesión.",
        codigo: "CC_SESION",
      },
      401,
      cors,
    );
  }
  // Agnóstico al proveedor: Google, password u otro flujo son equivalentes.
  // La única condición de Auth es el sello email_confirmed_at.
  if (!usuario.user.email_confirmed_at) {
    return json(
      {
        error: "Confirma tu correo antes de continuar.",
        codigo: "CC_CONFIRMACION_REQUERIDA",
      },
      403,
      cors,
    );
  }

  const cuerpo = await leerCuerpoLimitado(req, 1024);
  if (cuerpo.excedido) {
    return json({ error: "El cuerpo es demasiado grande." }, 413, cors);
  }

  let body: unknown;
  try {
    body = JSON.parse(cuerpo.texto);
  } catch {
    return json({ error: "Body inválido; se esperaba JSON." }, 400, cors);
  }

  if (
    body === null ||
    Array.isArray(body) ||
    typeof body !== "object" ||
    Object.keys(body as Record<string, unknown>).length !== 0
  ) {
    return json({ error: "Esta operación solo acepta POST {}." }, 400, cors);
  }

  const { error } = await supabase.rpc("cc_inicializar_cuenta");
  if (error) {
    const publico = traducirError(error.message ?? "");
    // Diagnóstico acotado: códigos, nunca mensaje/details/hint (podrían llevar
    // identidad), JWT, correo, UID ni cuerpo.
    console.error(
      "[cuenta-inicializar] RPC rechazada",
      JSON.stringify({
        codigo_db: error.code ?? null,
        codigo_publico: publico.codigo,
      }),
    );
    return json(
      { error: publico.texto, codigo: publico.codigo },
      publico.status,
      cors,
    );
  }

  // Respuesta deliberadamente idéntica con o sin historial/conflicto.
  return json({ ok: true }, 200, cors);
});
