// MAGANDHI · Edge Function · enlace-promocional (Promocionar P3 + puente P4)
// Resuelve códigos, redirige y valida la captura P4. La service role nunca sale.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.116.0";
import {
  agregarCodigoAtribucion,
  crearHashIp,
  debeContar,
  esSecretoMaestroValido,
  extraerCodigoRuta,
  extraerCodigoValidacionRuta,
  fechaColombia,
  obtenerIp,
  paginaMagandhi,
  type TipoPagina,
  validarFuenteIp,
  validarResolucion,
} from "./core.ts";

declare const EdgeRuntime: {
  waitUntil(promise: Promise<unknown>): void;
};

const RESOLVER_TIMEOUT_MS = 2_500;
const CONTAR_TIMEOUT_MS = 900;
const P4_VALIDACION_TIMEOUT_MS = 1_500;
const METODOS_PERMITIDOS = "GET, HEAD, OPTIONS";
const ORIGENES_VALIDACION_P4 = new Set([
  "https://magandhi.com",
  "https://www.magandhi.com",
  "https://12344-ux.github.io",
]);
const ERROR_PLAZO_AGOTADO = Symbol("P3_PLAZO_AGOTADO");

const CABECERAS_BASE: Readonly<Record<string, string>> = Object.freeze({
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
  "X-Content-Type-Options": "nosniff",
});

type BaseDatosP3 = {
  public: {
    Tables: Record<string, never>;
    Views: Record<string, never>;
    Functions: {
      promocionar_p3_resolver: {
        Args: { p_codigo: string };
        Returns: unknown;
      };
      promocionar_p3_contar: {
        Args: { p_enlace_id: string; p_ip_hash: string };
        Returns: unknown;
      };
      promocionar_p4_validar_codigo: {
        Args: { p_codigo: string };
        Returns: unknown;
      };
    };
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};

type ClienteSupabase = ReturnType<typeof createClient<BaseDatosP3>>;
type CodigoLog =
  | "P3_CONFIG_MISSING"
  | "P3_CLIENT_INIT"
  | "P3_RESOLVER_RPC"
  | "P3_RESOLVER_TIMEOUT"
  | "P3_RESOLVER_DATA"
  | "P3_COUNT_IP_HEADER_CONFIG"
  | "P3_COUNT_IP_HEADER_MISSING"
  | "P3_COUNT_IP_HEADER_INVALID"
  | "P3_COUNT_MASTER_SECRET_INVALID"
  | "P3_COUNT_HASH_FAILURE"
  | "P3_COUNT_PREP_FAILURE"
  | "P3_COUNT_RPC"
  | "P3_COUNT_TIMEOUT"
  | "P4_VALIDATION_RPC"
  | "P4_VALIDATION_TIMEOUT"
  | "P3_HANDLER_FAILURE";

type ResultadoResolver =
  | { ok: true; data: unknown }
  | { ok: false; codigo: "P3_RESOLVER_RPC" | "P3_RESOLVER_TIMEOUT" };

type ResultadoValidacionP4 =
  | { ok: true; valido: boolean }
  | { ok: false; codigo: "P4_VALIDATION_RPC" | "P4_VALIDATION_TIMEOUT" };

function logTecnico(codigo: CodigoLog): void {
  console.error(codigo);
}

function cabeceras(adicionales?: Readonly<Record<string, string>>): Headers {
  const salida = new Headers(CABECERAS_BASE);
  if (adicionales) {
    for (const [nombre, valor] of Object.entries(adicionales)) {
      salida.set(nombre, valor);
    }
  }
  return salida;
}

function respuestaHtml(
  status: number,
  tipo: TipoPagina,
  soloCabeceras: boolean,
  adicionales?: Readonly<Record<string, string>>,
): Response {
  return new Response(soloCabeceras ? null : paginaMagandhi(tipo), {
    status,
    headers: cabeceras({
      "Content-Type": "text/html; charset=utf-8",
      ...(adicionales ?? {}),
    }),
  });
}

function respuestaNoDisponible(soloCabeceras: boolean): Response {
  return respuestaHtml(404, "no_disponible", soloCabeceras);
}

function respuestaServicioNoDisponible(soloCabeceras: boolean): Response {
  return respuestaHtml(503, "servicio_no_disponible", soloCabeceras);
}

function respuestaRedirect(destinoUrl: string): Response {
  return new Response(null, {
    status: 302,
    headers: cabeceras({ Location: destinoUrl }),
  });
}

function cabecerasValidacionP4(req: Request): Record<string, string> {
  const origen = req.headers.get("origin");
  return {
    ...(origen && ORIGENES_VALIDACION_P4.has(origen)
      ? { "Access-Control-Allow-Origin": origen }
      : {}),
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "accept",
    "Access-Control-Max-Age": "300",
    Vary: "Origin",
  };
}

function respuestaValidacionP4(req: Request, status: number): Response {
  return new Response(null, {
    status,
    headers: cabeceras(cabecerasValidacionP4(req)),
  });
}

async function ejecutarConPlazo<T>(
  milisegundos: number,
  operacion: (signal: AbortSignal) => PromiseLike<T>,
): Promise<T> {
  const controller = new AbortController();
  let vencido = false;
  let temporizador: ReturnType<typeof setTimeout> | undefined;
  const limite = new Promise<never>((_, reject) => {
    temporizador = setTimeout(() => {
      vencido = true;
      controller.abort();
      reject(ERROR_PLAZO_AGOTADO);
    }, milisegundos);
  });

  try {
    return await Promise.race([
      Promise.resolve(operacion(controller.signal)),
      limite,
    ]);
  } catch (error) {
    if (vencido) throw ERROR_PLAZO_AGOTADO;
    throw error;
  } finally {
    if (temporizador !== undefined) clearTimeout(temporizador);
  }
}

async function resolver(
  supabase: ClienteSupabase,
  codigo: string,
): Promise<ResultadoResolver> {
  try {
    const { data, error } = await ejecutarConPlazo(
      RESOLVER_TIMEOUT_MS,
      (signal) =>
        supabase
          .rpc("promocionar_p3_resolver", { p_codigo: codigo })
          .abortSignal(signal),
    );
    if (error) {
      return { ok: false, codigo: "P3_RESOLVER_RPC" };
    }
    return { ok: true, data };
  } catch (error) {
    return {
      ok: false,
      codigo: error === ERROR_PLAZO_AGOTADO
        ? "P3_RESOLVER_TIMEOUT"
        : "P3_RESOLVER_RPC",
    };
  }
}

async function validarCodigoP4(
  supabase: ClienteSupabase,
  codigo: string,
  timeoutMs: number,
): Promise<ResultadoValidacionP4> {
  try {
    const { data, error } = await ejecutarConPlazo(
      timeoutMs,
      (signal) =>
        supabase
          .rpc("promocionar_p4_validar_codigo", { p_codigo: codigo })
          .abortSignal(signal),
    );
    if (error || typeof data !== "boolean") {
      return { ok: false, codigo: "P4_VALIDATION_RPC" };
    }
    return { ok: true, valido: data };
  } catch (error) {
    return {
      ok: false,
      codigo: error === ERROR_PLAZO_AGOTADO
        ? "P4_VALIDATION_TIMEOUT"
        : "P4_VALIDATION_RPC",
    };
  }
}

async function contar(
  supabase: ClienteSupabase,
  enlaceId: string,
  ipHash: string,
): Promise<void> {
  try {
    const { error } = await ejecutarConPlazo(
      CONTAR_TIMEOUT_MS,
      (signal) =>
        supabase
          .rpc("promocionar_p3_contar", {
            p_enlace_id: enlaceId,
            p_ip_hash: ipHash,
          })
          .abortSignal(signal),
    );
    if (error) logTecnico("P3_COUNT_RPC");
  } catch (error) {
    logTecnico(
      error === ERROR_PLAZO_AGOTADO ? "P3_COUNT_TIMEOUT" : "P3_COUNT_RPC",
    );
  }
}

async function intentarContar(
  req: Request,
  supabase: ClienteSupabase,
  enlaceId: string,
): Promise<void> {
  try {
    if (
      !debeContar({
        metodo: req.method,
        userAgent: req.headers.get("user-agent"),
        purpose: req.headers.get("purpose"),
        secPurpose: req.headers.get("sec-purpose"),
        secFetchMode: req.headers.get("sec-fetch-mode"),
        secFetchDest: req.headers.get("sec-fetch-dest"),
        accept: req.headers.get("accept"),
      })
    ) {
      return;
    }

    const fuenteIp = validarFuenteIp(Deno.env.get("PROMOCIONAR_IP_HEADER"));
    if (!fuenteIp) {
      logTecnico("P3_COUNT_IP_HEADER_CONFIG");
      return;
    }

    const valorCabeceraIp = req.headers.get(fuenteIp);
    if (valorCabeceraIp === null) {
      logTecnico("P3_COUNT_IP_HEADER_MISSING");
      return;
    }

    const ip = obtenerIp(fuenteIp, valorCabeceraIp);
    if (!ip) {
      logTecnico("P3_COUNT_IP_HEADER_INVALID");
      return;
    }

    const secretoMaestro = Deno.env.get("PROMOCIONAR_IP_SAL");
    if (!esSecretoMaestroValido(secretoMaestro)) {
      logTecnico("P3_COUNT_MASTER_SECRET_INVALID");
      return;
    }

    let hashIpDia: string;
    try {
      const fecha = fechaColombia(new Date());
      hashIpDia = await crearHashIp(
        secretoMaestro,
        fecha,
        ip,
        crypto.subtle,
      );
    } catch {
      logTecnico("P3_COUNT_HASH_FAILURE");
      return;
    }

    await contar(supabase, enlaceId, hashIpDia);
  } catch {
    // El conteo es secundario: ningún fallo posterior a resolver cambia el 302.
    logTecnico("P3_COUNT_PREP_FAILURE");
  }
}

async function manejarSolicitud(req: Request): Promise<Response> {
  const soloCabeceras = req.method === "HEAD";

  let pathname: string;
  try {
    // La query se ignora por completo: nunca aporta código ni destino.
    pathname = new URL(req.url).pathname;
  } catch {
    return respuestaNoDisponible(soloCabeceras);
  }

  const codigoValidacion = extraerCodigoValidacionRuta(pathname);
  const esValidacionP4 = codigoValidacion !== null;
  const codigo = codigoValidacion ?? extraerCodigoRuta(pathname);
  if (!codigo) return respuestaNoDisponible(soloCabeceras);

  if (req.method === "OPTIONS") {
    return esValidacionP4
      ? respuestaValidacionP4(req, 204)
      : new Response(null, {
        status: 204,
        headers: cabeceras({ Allow: METODOS_PERMITIDOS }),
      });
  }
  if (esValidacionP4 && req.method !== "GET") {
    return respuestaValidacionP4(req, 405);
  }
  if (!esValidacionP4 && req.method !== "GET" && req.method !== "HEAD") {
    return respuestaHtml(405, "metodo_no_permitido", false, {
      Allow: METODOS_PERMITIDOS,
    });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    logTecnico("P3_CONFIG_MISSING");
    return respuestaServicioNoDisponible(soloCabeceras);
  }

  let supabase: ClienteSupabase;
  try {
    supabase = createClient<BaseDatosP3>(supabaseUrl, serviceRoleKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false,
      },
      global: {
        headers: {
          Authorization: `Bearer ${serviceRoleKey}`,
          apikey: serviceRoleKey,
        },
      },
    });
  } catch {
    logTecnico("P3_CLIENT_INIT");
    return respuestaServicioNoDisponible(soloCabeceras);
  }

  if (esValidacionP4) {
    const validacion = await validarCodigoP4(
      supabase,
      codigo,
      P4_VALIDACION_TIMEOUT_MS,
    );
    if (!validacion.ok) {
      logTecnico(validacion.codigo);
      return respuestaValidacionP4(req, 503);
    }
    return respuestaValidacionP4(req, validacion.valido ? 204 : 404);
  }

  const resultadoRpc = await resolver(supabase, codigo);
  if (!resultadoRpc.ok) {
    logTecnico(resultadoRpc.codigo);
    return respuestaServicioNoDisponible(soloCabeceras);
  }

  const resolucion = validarResolucion(resultadoRpc.data);
  if (resolucion.tipo === "no_encontrado") {
    return respuestaNoDisponible(soloCabeceras);
  }
  if (resolucion.tipo === "invalido") {
    logTecnico("P3_RESOLVER_DATA");
    return respuestaServicioNoDisponible(soloCabeceras);
  }

  const destinoP4 = resolucion.capturaP4 === true
    ? agregarCodigoAtribucion(resolucion.destinoUrl, codigo)
    : null;
  const redirect = respuestaRedirect(destinoP4 ?? resolucion.destinoUrl);
  // Conserva el conteo completo sin retener la entrega del 302.
  EdgeRuntime.waitUntil(intentarContar(req, supabase, resolucion.enlaceId));
  return redirect;
}

Deno.serve(async (req: Request): Promise<Response> => {
  try {
    return await manejarSolicitud(req);
  } catch {
    logTecnico("P3_HANDLER_FAILURE");
    return respuestaServicioNoDisponible(req.method === "HEAD");
  }
});
