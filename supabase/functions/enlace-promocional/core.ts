// MAGANDHI · Promocionar P3 · reglas puras del enlace público.
// No lee variables de entorno, no usa red y no persiste ni registra datos.

export const FORMATO_CODIGO = /^[0-9a-hjkmnp-tv-z]{16}$/;

const RUTA_ENLACE =
  /^(?:\/functions\/v1\/enlace-promocional|\/enlace-promocional)?\/([0-9a-hjkmnp-tv-z]{16})$/;
const RUTA_VALIDACION =
  /^(?:\/functions\/v1\/enlace-promocional|\/enlace-promocional)?\/validar\/([0-9a-hjkmnp-tv-z]{16})$/;
const FORMATO_UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const FORMATO_SLUG = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const FORMATO_UTM = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const ORIGEN_MAGANDHI = "https://magandhi.com";
const PROPOSITO_LLAVE_DIARIA = "promocionar-p3-sal";
const PROPOSITO_HASH_IP = "promocionar-p3-ip";
const MINIMO_SECRETO_MAESTRO_BYTES = 32;

const LIMITES_UTM: Readonly<Record<string, number>> = Object.freeze({
  utm_source: 32,
  utm_medium: 32,
  utm_campaign: 60,
  utm_content: 60,
});

const PARES_SOURCE_MEDIUM = new Set([
  "whatsapp|mensajeria",
  "instagram|social",
  "facebook|social",
  "email|email",
  "qr|offline",
  "anuncio-manual|paid-manual",
  "otro-controlado|referral",
]);

// Usa firmas de robots, previews concretos y clientes HTTP sin navegador.
// Nombres de apps (FBAN/FBAV, Twitter, LinkedIn, etc.) también aparecen en
// navegadores integrados de personas y no son señal suficiente por sí solos.
const AGENTE_NO_HUMANO =
  /bot|crawl|spider|scanner|headless|slurp|facebookexternalhit|facebot|twitterbot|linkedinbot|telegrambot|^whatsapp(?:\/[\d.]+)?(?:\s|$)|bingpreview|skypeuripreview|lighthouse|pagespeed|curl|wget|libcurl|axios|node-fetch|undici|superagent|python-requests|python-urllib|aiohttp|httpx|go-http-client|okhttp|apache-httpclient|httpclient|http-client|libwww-perl|lwp::|guzzle|restsharp|reqwest|postmanruntime|insomnia|powershell|faraday|mechanize|scrapy|dalvik|java\//i;
const PROPOSITO_NO_NAVEGABLE = /prefetch|prerender|preview/i;

export type ResolucionValidada =
  | { tipo: "no_encontrado" }
  | { tipo: "invalido" }
  | {
    tipo: "encontrado";
    enlaceId: string;
    destinoUrl: string;
    capturaP4?: true;
  };

export type SenalesConteo = Readonly<{
  metodo: string;
  userAgent: string | null;
  purpose: string | null;
  secPurpose: string | null;
  secFetchMode: string | null;
  secFetchDest: string | null;
  accept: string | null;
}>;

export type FuenteIp =
  | "cf-connecting-ip"
  | "x-real-ip"
  | "x-forwarded-for";

export type TipoPagina =
  | "no_disponible"
  | "servicio_no_disponible"
  | "metodo_no_permitido";

/**
 * Acepta exclusivamente el path público y los dos paths nativos del proxy.
 * La query nunca participa en esta decisión.
 */
export function extraerCodigoRuta(pathname: string): string | null {
  const coincidencia = RUTA_ENLACE.exec(pathname);
  const codigo = coincidencia?.[1] ?? "";
  return FORMATO_CODIGO.test(codigo) ? codigo : null;
}

/** Ruta nominal P4: valida un código sin redirigir ni contar. */
export function extraerCodigoValidacionRuta(pathname: string): string | null {
  const coincidencia = RUTA_VALIDACION.exec(pathname);
  const codigo = coincidencia?.[1] ?? "";
  return FORMATO_CODIGO.test(codigo) ? codigo : null;
}

/**
 * Revalida el destino construido por SQL. No corrige ni completa URLs: solo
 * devuelve exactamente la cadena recibida cuando ya es canónica y segura.
 */
export function validarDestinoUrl(valor: unknown): string | null {
  if (typeof valor !== "string" || valor.length === 0 || valor.length > 512) {
    return null;
  }
  if (valor !== valor.trim()) return null;

  let destino: URL;
  try {
    destino = new URL(valor);
  } catch {
    return null;
  }

  if (
    destino.href !== valor ||
    destino.origin !== ORIGEN_MAGANDHI ||
    destino.protocol !== "https:" ||
    destino.username !== "" ||
    destino.password !== "" ||
    destino.hash !== ""
  ) {
    return null;
  }

  const esHome = destino.pathname === "/";
  const producto = /^\/producto\/([^/]+)\/$/.exec(destino.pathname);
  if (!esHome && (!producto || !FORMATO_SLUG.test(producto[1]))) return null;

  const vistos = new Set<string>();
  const utm = new Map<string, string>();
  for (const [clave, contenido] of destino.searchParams) {
    const limite = LIMITES_UTM[clave];
    if (
      !limite ||
      vistos.has(clave) ||
      contenido.length === 0 ||
      contenido.length > limite ||
      !FORMATO_UTM.test(contenido)
    ) {
      return null;
    }
    vistos.add(clave);
    utm.set(clave, contenido);
  }

  const source = utm.get("utm_source");
  const medium = utm.get("utm_medium");
  if (
    !source ||
    !medium ||
    !utm.has("utm_campaign") ||
    !PARES_SOURCE_MEDIUM.has(`${source}|${medium}`)
  ) {
    return null;
  }

  return valor;
}

/**
 * Añade el código P4 como fragmento reservado a un destino P3 ya validado.
 * El fragmento no viaja en la petición HTTP de la página ni en el referrer.
 */
export function agregarCodigoAtribucion(
  destinoUrl: string,
  codigo: string,
): string | null {
  const seguro = validarDestinoUrl(destinoUrl);
  if (!seguro || !FORMATO_CODIGO.test(codigo)) return null;
  const destino = new URL(seguro);
  destino.hash = `mg_promo=${codigo}`;
  return destino.href;
}

export function validarResolucion(valor: unknown): ResolucionValidada {
  if (valor === null) return { tipo: "no_encontrado" };
  if (!valor || typeof valor !== "object" || Array.isArray(valor)) {
    return { tipo: "invalido" };
  }

  const fila = valor as Record<string, unknown>;
  const enlaceId = typeof fila.enlace_id === "string" ? fila.enlace_id : "";
  const destinoUrl = validarDestinoUrl(fila.destino_url);
  if (
    !FORMATO_UUID.test(enlaceId) || !destinoUrl ||
    (Object.prototype.hasOwnProperty.call(fila, "captura_p4") &&
      typeof fila.captura_p4 !== "boolean")
  ) {
    return { tipo: "invalido" };
  }

  return {
    tipo: "encontrado",
    enlaceId,
    destinoUrl,
    ...(fila.captura_p4 === true ? { capturaP4: true as const } : {}),
  };
}

const FORMATO_CALIDAD_HTTP = /^(?:0(?:\.[0-9]{0,3})?|1(?:\.0{0,3})?)$/;

function dividirFueraDeComillas(
  valor: string,
  separador: "," | ";",
): string[] | null {
  const partes: string[] = [];
  let inicio = 0;
  let entreComillas = false;
  let escapado = false;

  for (let indice = 0; indice < valor.length; indice += 1) {
    const caracter = valor[indice];
    if (escapado) {
      escapado = false;
      continue;
    }
    if (entreComillas && caracter === "\\") {
      escapado = true;
      continue;
    }
    if (caracter === '"') {
      entreComillas = !entreComillas;
      continue;
    }
    if (!entreComillas && caracter === separador) {
      partes.push(valor.slice(inicio, indice));
      inicio = indice + 1;
    }
  }

  if (entreComillas || escapado) return null;
  partes.push(valor.slice(inicio));
  return partes;
}

function aceptaHtml(valor: string | null): boolean {
  if (valor === null) return false;

  const rangos = dividirFueraDeComillas(valor, ",");
  if (rangos === null) return false;

  return rangos.some((rango) => {
    const partes = dividirFueraDeComillas(rango, ";");
    if (partes === null) return false;

    const [tipo, ...parametros] = partes;
    if (tipo.trim().toLowerCase() !== "text/html") return false;

    let calidad = 1;
    let calidadEncontrada = false;
    for (const parametro of parametros) {
      const texto = parametro.trim();
      const separador = texto.indexOf("=");
      const nombre = (separador === -1 ? texto : texto.slice(0, separador))
        .trim()
        .toLowerCase();
      if (nombre !== "q") continue;
      if (calidadEncontrada) return false;

      calidadEncontrada = true;
      const coincidencia = /^q=(.*)$/i.exec(texto);
      const valorCalidad = coincidencia?.[1] ?? "";
      if (!FORMATO_CALIDAD_HTTP.test(valorCalidad)) return false;
      calidad = Number(valorCalidad);
    }

    return calidad > 0;
  });
}

function coincideFetchMetadata(
  valor: string | null,
  esperado: "navigate" | "document",
): boolean {
  return valor?.trim().toLowerCase() === esperado;
}

export function debeContar(senales: SenalesConteo): boolean {
  if (senales.metodo !== "GET") return false;

  const userAgent = senales.userAgent?.trim() ?? "";
  if (!userAgent || AGENTE_NO_HUMANO.test(userAgent.slice(0, 1024))) {
    return false;
  }

  if (
    PROPOSITO_NO_NAVEGABLE.test(senales.purpose ?? "") ||
    PROPOSITO_NO_NAVEGABLE.test(senales.secPurpose ?? "")
  ) {
    return false;
  }

  return coincideFetchMetadata(senales.secFetchMode, "navigate") &&
    coincideFetchMetadata(senales.secFetchDest, "document") &&
    aceptaHtml(senales.accept);
}

function normalizarIpv4(valor: string): string | null {
  const partes = valor.split(".");
  if (partes.length !== 4) return null;

  const normalizadas: string[] = [];
  for (const parte of partes) {
    if (!/^\d{1,3}$/.test(parte)) return null;
    const numero = Number(parte);
    if (!Number.isInteger(numero) || numero < 0 || numero > 255) return null;
    normalizadas.push(String(numero));
  }
  return normalizadas.join(".");
}

function normalizarIp(valor: string | null): string | null {
  const ip = valor?.trim() ?? "";
  if (!ip || ip.length > 64) return null;

  const ipv4 = normalizarIpv4(ip);
  if (ipv4) return ipv4;
  if (!ip.includes(":") || !/^[0-9a-f:.]+$/i.test(ip)) return null;

  try {
    const hostname = new URL(`http://[${ip}]/`).hostname;
    const ipv6 = hostname.replace(/^\[/, "").replace(/\]$/, "");
    return ipv6.includes(":") ? ipv6.toLowerCase() : null;
  } catch {
    return null;
  }
}

/** Valida de forma cerrada la única cabecera de IP configurada. */
export function validarFuenteIp(valor: unknown): FuenteIp | null {
  return valor === "cf-connecting-ip" ||
      valor === "x-real-ip" ||
      valor === "x-forwarded-for"
    ? valor
    : null;
}

/** Normaliza únicamente la cabecera seleccionada; XFF usa solo el primer valor. */
export function obtenerIp(
  fuente: FuenteIp,
  valorCabecera: string | null,
): string | null {
  const candidato = fuente === "x-forwarded-for"
    ? valorCabecera?.split(",", 1)[0] ?? null
    : valorCabecera;
  return normalizarIp(candidato);
}

export function fechaColombia(fecha: Date): string {
  const partes = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Bogota",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(fecha);

  const valores = new Map(partes.map((parte) => [parte.type, parte.value]));
  const year = valores.get("year") ?? "";
  const month = valores.get("month") ?? "";
  const day = valores.get("day") ?? "";
  const salida = `${year}-${month}-${day}`;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(salida)) {
    throw new Error("P3_DATE_INVALID");
  }
  return salida;
}

export function esSecretoMaestroValido(
  valor: string | null | undefined,
): valor is string {
  if (!valor || valor.trim().length === 0) return false;
  return new TextEncoder().encode(valor).byteLength >=
    MINIMO_SECRETO_MAESTRO_BYTES;
}

/**
 * Deriva una llave diaria desde el secreto maestro y después calcula el HMAC
 * de la IP con separación de dominios. Ninguna llave sale de esta función.
 */
export async function crearHashIp(
  secretoMaestro: string,
  fecha: string,
  ip: string,
  subtle: SubtleCrypto,
): Promise<string> {
  const encoder = new TextEncoder();
  if (!esSecretoMaestroValido(secretoMaestro)) {
    throw new Error("P3_MASTER_SECRET_INVALID");
  }

  const llaveMaestra = await subtle.importKey(
    "raw",
    encoder.encode(secretoMaestro),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const materialLlaveDiaria = await subtle.sign(
    "HMAC",
    llaveMaestra,
    encoder.encode(`${PROPOSITO_LLAVE_DIARIA}|${fecha}`),
  );
  const bytesLlaveDiaria = new Uint8Array(materialLlaveDiaria);
  if (bytesLlaveDiaria.length !== 32) {
    throw new Error("P3_DAILY_KEY_INVALID");
  }

  const llaveDiaria = await subtle.importKey(
    "raw",
    bytesLlaveDiaria,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const firmaIp = await subtle.sign(
    "HMAC",
    llaveDiaria,
    encoder.encode(`${PROPOSITO_HASH_IP}|${ip}`),
  );
  const bytesHashIp = new Uint8Array(firmaIp);
  if (bytesHashIp.length !== 32) throw new Error("P3_IP_HASH_INVALID");
  return Array.from(
    bytesHashIp,
    (byte) => byte.toString(16).padStart(2, "0"),
  ).join("");
}

/** HTML fijo: nunca interpola código, URL, cabeceras ni detalles internos. */
export function paginaMagandhi(tipo: TipoPagina): string {
  const contenido = tipo === "servicio_no_disponible"
    ? {
      titulo: "Servicio temporalmente no disponible",
      mensaje:
        "No pudimos abrir este enlace en este momento. Inténtalo de nuevo más tarde.",
    }
    : tipo === "metodo_no_permitido"
    ? {
      titulo: "Solicitud no permitida",
      mensaje: "Esta solicitud no puede procesarse desde aquí.",
    }
    : {
      titulo: "Enlace no disponible",
      mensaje: "Este enlace no está disponible.",
    };

  return `<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="robots" content="noindex,nofollow">
  <title>${contenido.titulo} · MAGANDHI</title>
  <style>
    :root { color-scheme: light; }
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 24px; background: #efe7dd; color: #111111; font-family: Poppins, Arial, sans-serif; }
    main { width: min(100%, 560px); padding: 40px 32px; border-top: 5px solid #a6332e; background: #ffffff; box-shadow: 0 18px 50px rgba(17, 17, 17, .10); text-align: center; }
    .marca { margin: 0 0 24px; color: #a6332e; font-size: .82rem; font-weight: 700; letter-spacing: .18em; }
    h1 { margin: 0 0 12px; font-size: clamp(1.65rem, 5vw, 2.35rem); line-height: 1.15; }
    p { margin: 0; color: #4d433c; line-height: 1.65; }
    .acento { display: block; width: 44px; height: 3px; margin: 28px auto 0; background: #c28a3a; }
  </style>
</head>
<body>
  <main>
    <p class="marca">MAGANDHI</p>
    <h1>${contenido.titulo}</h1>
    <p>${contenido.mensaje}</p>
    <span class="acento" aria-hidden="true"></span>
  </main>
</body>
</html>`;
}
