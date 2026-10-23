// MAGANDHI · Edge Function · estado-pago (Pagos web · D0 + Comercial C5)
// ----------------------------------------------------------------------------
// Recibe { referencia }. v0/v1 conservan autorización por posesión y respuesta
// histórica. Para v2 valida, cuando exista, el JWT de usuario y la RPC exige que
// su UID sea el mismo que quedó congelado en pagos_intencion.auth_user_id.
//
// Línea roja: nunca devuelve monto, PII, pedido_id, transacción, método, motivo
// de revisión ni entorno. La referencia tampoco se escribe en logs.
// ============================================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.116.0";

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
      "Cache-Control": "no-store",
    },
  });
}

const FORMATO_REFERENCIA = /^[A-Za-z0-9_-]{6,64}$/;
const FORMATO_UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const VERSION_CARRITO = /^(0|[1-9][0-9]*)$/;

const ESTADOS_PUBLICOS = new Set<string>([
  "pendiente",
  "aprobado",
  "revision",
  "rechazado",
]);

type FilaEstado = {
  estado?: unknown;
  nombre_producto?: unknown;
  slug?: unknown;
  checkout?: unknown;
};

type CheckoutPublico =
  | {
    tipo: "carrito";
    id: string;
    version: number;
    recargar: boolean;
  }
  | {
    tipo: "compra";
    referencia: string;
    recargar: boolean;
    origen?: "directo";
    gestion?: "local" | "mis_compras";
    puede_continuar?: boolean;
  };

function checkoutSeguro(valor: unknown): CheckoutPublico | null {
  if (!valor || typeof valor !== "object" || Array.isArray(valor)) return null;
  const bruto = valor as Record<string, unknown>;

  if (bruto.tipo === "compra") {
    if (
      typeof bruto.referencia !== "string" ||
      !FORMATO_REFERENCIA.test(bruto.referencia) ||
      typeof bruto.recargar !== "boolean"
    ) return null;
    const origen = bruto.origen === "directo" ? "directo" : undefined;
    const gestion = bruto.gestion === "local" || bruto.gestion === "mis_compras"
      ? bruto.gestion
      : undefined;
    const puedeContinuar = typeof bruto.puede_continuar === "boolean"
      ? bruto.puede_continuar
      : undefined;
    return {
      tipo: "compra",
      referencia: bruto.referencia,
      recargar: bruto.recargar,
      ...(origen ? { origen } : {}),
      ...(gestion ? { gestion } : {}),
      ...(puedeContinuar !== undefined
        ? { puede_continuar: puedeContinuar }
        : {}),
    };
  }

  if (
    bruto.tipo !== "carrito" || typeof bruto.id !== "string" ||
    !FORMATO_UUID.test(bruto.id) || typeof bruto.recargar !== "boolean"
  ) return null;

  const version = bruto.version;
  const versionNumero = typeof version === "number"
    ? version
    : typeof version === "string" && VERSION_CARRITO.test(version)
    ? Number(version)
    : NaN;
  if (!Number.isSafeInteger(versionNumero) || versionNumero < 0) return null;

  return {
    tipo: "carrito",
    id: bruto.id,
    version: versionNumero,
    recargar: bruto.recargar,
  };
}

Deno.serve(async (req: Request): Promise<Response> => {
  const cors = cabecerasCors(req.headers.get("origin"));

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (req.method !== "POST") {
    return json({ error: "Metodo no permitido; usa POST." }, 405, cors);
  }

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
    return json({ error: "Referencia no encontrada." }, 404, cors);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? req.headers.get("apikey");
  if (!supabaseUrl || !serviceRoleKey || !publicKey) {
    return json(
      { error: "Configuracion del servidor incompleta (Supabase)." },
      500,
      cors,
    );
  }

  // JWT opcional: una publishable/anon key no se interpreta como usuario. Un
  // access token válido aporta exclusivamente su UID; nunca correo ni metadata.
  let authUserId: string | null = null;
  const jwt = (req.headers.get("authorization") ?? "")
    .replace(/^Bearer\s+/i, "")
    .trim();
  const credencialPublica = (req.headers.get("apikey") ?? "").trim();
  if (
    jwt && jwt !== publicKey &&
    (!credencialPublica || jwt !== credencialPublica)
  ) {
    const supabaseUsuario = createClient(supabaseUrl, publicKey, {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Authorization: `Bearer ${jwt}` } },
    });
    const { data: sesion, error: errorSesion } = await supabaseUsuario.auth
      .getUser(jwt);
    if (
      errorSesion || !sesion?.user?.id || !FORMATO_UUID.test(sesion.user.id)
    ) {
      return json({ error: "Tu sesión no es válida." }, 401, cors);
    }
    authUserId = sesion.user.id;
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${serviceRoleKey}` } },
  });

  const { data, error } = await supabase.rpc("pw_estado_checkout_publico", {
    p_referencia: referencia,
    p_auth_user_id: authUserId,
  });

  if (error) {
    console.error(
      "[estado-pago] Fallo pw_estado_checkout_publico:",
      JSON.stringify({
        message: error?.message ?? null,
        code: (error as { code?: string } | null)?.code ?? null,
        details: (error as { details?: string } | null)?.details ?? null,
      }),
    );
    return json(
      { error: "No se pudo consultar el estado del pago." },
      500,
      cors,
    );
  }

  const fila = (Array.isArray(data) ? data[0] : data) as FilaEstado | null;
  if (!fila) {
    // En v2 también cubre JWT ausente/no válido o UID distinto, sin confirmar
    // hacia fuera que la referencia existe.
    return json({ error: "Referencia no encontrada." }, 404, cors);
  }

  const bruto = typeof fila.estado === "string" ? fila.estado : "";
  if (!ESTADOS_PUBLICOS.has(bruto)) {
    console.error("[estado-pago] Estado público fuera de contrato.");
    return json(
      { error: "No se pudo validar el estado del pago." },
      500,
      cors,
    );
  }
  const estado = bruto;
  const respuesta: Record<string, unknown> = {
    estado,
    nombre_producto: typeof fila.nombre_producto === "string"
      ? fila.nombre_producto
      : "",
    slug: typeof fila.slug === "string" ? fila.slug : "",
  };

  const checkout = checkoutSeguro(fila.checkout);
  if (checkout) respuesta.checkout = checkout;

  return json(respuesta, 200, cors);
});
