// MAGANDHI · Cloudflare Worker · go.magandhi.com (Promocionar P3)
// Proxy cerrado: conserva la ruta/query, fija el único origen y no sigue el 302.

const ORIGEN_EDGE =
  "https://bxlzipwxyxdtffnuizbz.supabase.co/functions/v1/enlace-promocional";
const METODOS_PERMITIDOS = new Set(["GET", "HEAD", "OPTIONS"]);
const CABECERAS_PERMITIDAS = [
  "accept",
  "accept-language",
  "user-agent",
  "purpose",
  "sec-purpose",
  "sec-fetch-mode",
  "sec-fetch-dest",
  "sec-fetch-site",
  "origin",
  "access-control-request-method",
  "access-control-request-headers",
];

function cabecerasHaciaEdge(request) {
  const cabeceras = new Headers();

  for (const nombre of CABECERAS_PERMITIDAS) {
    const valor = request.headers.get(nombre);
    if (valor !== null) cabeceras.set(nombre, valor);
  }

  // Cloudflare establece CF-Connecting-IP antes de ejecutar el Worker. Nunca
  // propagamos x-real-ip/XFF aportados por el visitante: escribimos uno nuevo.
  const ipCloudflare = request.headers.get("cf-connecting-ip");
  if (ipCloudflare) cabeceras.set("x-real-ip", ipCloudflare);

  return cabeceras;
}

function cabecerasHaciaVisitante(origen) {
  const cabeceras = new Headers(origen);
  cabeceras.delete("set-cookie");
  cabeceras.delete("set-cookie2");
  cabeceras.set("cache-control", "no-store");
  cabeceras.set("referrer-policy", "no-referrer");
  cabeceras.set("x-content-type-options", "nosniff");
  return cabeceras;
}

function respuestaSinCuerpo(status, adicionales = {}) {
  return new Response(null, {
    status,
    headers: {
      "cache-control": "no-store",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
      ...adicionales,
    },
  });
}

export default {
  async fetch(request) {
    if (!METODOS_PERMITIDOS.has(request.method)) {
      return respuestaSinCuerpo(405, { Allow: "GET, HEAD, OPTIONS" });
    }

    const entrada = new URL(request.url);
    const destino = new URL(`${ORIGEN_EDGE}${entrada.pathname}`);
    destino.search = entrada.search;

    try {
      const respuestaEdge = await fetch(destino, {
        method: request.method,
        headers: cabecerasHaciaEdge(request),
        redirect: "manual",
        cache: "no-store",
      });
      const sinCuerpo = request.method === "HEAD" ||
        [204, 205, 304].includes(respuestaEdge.status);

      return new Response(sinCuerpo ? null : respuestaEdge.body, {
        status: respuestaEdge.status,
        statusText: respuestaEdge.statusText,
        headers: cabecerasHaciaVisitante(respuestaEdge.headers),
      });
    } catch {
      // Falla cerrada: nunca intenta otro origen ni fabrica un destino.
      return respuestaSinCuerpo(503);
    }
  },
};
