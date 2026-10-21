// MAGANDHI · Promocionar P3 · banco puro de reglas del enlace público.
// Ejecutar: deno test supabase/functions/enlace-promocional/core_test.ts

import {
  crearHashIp,
  debeContar,
  esSecretoMaestroValido,
  extraerCodigoRuta,
  fechaColombia,
  obtenerIp,
  type SenalesConteo,
  validarDestinoUrl,
  validarFuenteIp,
  validarResolucion,
} from "./core.ts";

function afirmar(condicion: unknown, mensaje: string): asserts condicion {
  if (!condicion) throw new Error(mensaje);
}

function afirmarIgual<T>(actual: T, esperado: T, mensaje: string): void {
  if (JSON.stringify(actual) !== JSON.stringify(esperado)) {
    throw new Error(
      `${mensaje}\nesperado: ${JSON.stringify(esperado)}\nactual:   ${
        JSON.stringify(actual)
      }`,
    );
  }
}

const CODIGO = "0123456789abcdef";
const DESTINO_HOME =
  "https://magandhi.com/?utm_source=whatsapp&utm_medium=mensajeria&utm_campaign=lanzamiento-uno";
const DESTINO_PRODUCTO =
  "https://magandhi.com/producto/jabon-avena/?utm_source=instagram&utm_medium=social&utm_campaign=lanzamiento-dos&utm_content=historia-uno";

Deno.test("rutas: solo admite los tres paths y el código Crockford exacto", () => {
  for (
    const ruta of [
      `/${CODIGO}`,
      `/enlace-promocional/${CODIGO}`,
      `/functions/v1/enlace-promocional/${CODIGO}`,
    ]
  ) {
    afirmarIgual(extraerCodigoRuta(ruta), CODIGO, `ruta válida: ${ruta}`);
  }

  for (
    const ruta of [
      "",
      "/",
      `/${CODIGO}/`,
      `/otro/${CODIGO}`,
      `/${CODIGO}?next=https://example.invalid`,
      "/0123456789abcde",
      "/0123456789abcdefg",
      "/0123456789abcdei",
      "/0123456789ABCDEf",
    ]
  ) {
    afirmarIgual(extraerCodigoRuta(ruta), null, `ruta cerrada: ${ruta}`);
  }
});

Deno.test("destino: acepta únicamente la lista blanca canónica MAGANDHI", () => {
  afirmarIgual(validarDestinoUrl(DESTINO_HOME), DESTINO_HOME, "home válida");
  afirmarIgual(
    validarDestinoUrl(DESTINO_PRODUCTO),
    DESTINO_PRODUCTO,
    "producto válido",
  );

  const rechazados: unknown[] = [
    null,
    7,
    "",
    ` ${DESTINO_HOME}`,
    "http://magandhi.com/?utm_source=whatsapp&utm_medium=mensajeria&utm_campaign=x",
    "https://evil.invalid/?utm_source=whatsapp&utm_medium=mensajeria&utm_campaign=x",
    "https://go.magandhi.com/?utm_source=whatsapp&utm_medium=mensajeria&utm_campaign=x",
    "https://usuario@magandhi.com/?utm_source=whatsapp&utm_medium=mensajeria&utm_campaign=x",
    "https://magandhi.com:444/?utm_source=whatsapp&utm_medium=mensajeria&utm_campaign=x",
    "https://magandhi.com/producto/jabon-avena?utm_source=instagram&utm_medium=social&utm_campaign=x",
    "https://magandhi.com/otra/?utm_source=instagram&utm_medium=social&utm_campaign=x",
    "https://magandhi.com/?utm_source=instagram&utm_medium=social&utm_campaign=x#fragmento",
    "https://magandhi.com/?utm_source=instagram&utm_medium=social&utm_campaign=x&next=https%3A%2F%2Fevil.invalid",
    "https://magandhi.com/?utm_source=instagram&utm_source=facebook&utm_medium=social&utm_campaign=x",
    "https://magandhi.com/?utm_source=instagram&utm_medium=email&utm_campaign=x",
    "https://magandhi.com/?utm_source=instagram&utm_medium=social",
    "https://magandhi.com/?utm_source=instagram&utm_medium=social&utm_campaign=No-normalizada",
  ];

  for (const destino of rechazados) {
    afirmarIgual(
      validarDestinoUrl(destino),
      null,
      `destino rechazado: ${destino}`,
    );
  }
});

Deno.test("resolución: diferencia ausencia, dato inválido y destino confiable", () => {
  afirmarIgual(validarResolucion(null), { tipo: "no_encontrado" }, "ausencia");
  afirmarIgual(validarResolucion([]), { tipo: "invalido" }, "arreglo inválido");
  afirmarIgual(
    validarResolucion({ enlace_id: "no-es-uuid", destino_url: DESTINO_HOME }),
    { tipo: "invalido" },
    "UUID inválido",
  );
  afirmarIgual(
    validarResolucion({
      enlace_id: "12345678-1234-4234-8234-123456789abc",
      destino_url: "https://evil.invalid/",
    }),
    { tipo: "invalido" },
    "open redirect rechazado",
  );
  afirmarIgual(
    validarResolucion({
      enlace_id: "12345678-1234-4234-8234-123456789abc",
      destino_url: DESTINO_PRODUCTO,
    }),
    {
      tipo: "encontrado",
      enlaceId: "12345678-1234-4234-8234-123456789abc",
      destinoUrl: DESTINO_PRODUCTO,
    },
    "resolución válida",
  );
});

const SENAL_POSITIVA: SenalesConteo = {
  metodo: "GET",
  userAgent:
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/130 Safari/537.36",
  purpose: null,
  secPurpose: null,
  secFetchMode: "navigate",
  secFetchDest: "document",
  accept: "text/html",
};

Deno.test("Accept: respeta calidad HTTP y media range exacto", () => {
  const aceptados = [
    "text/html",
    "text/html;q=1",
    "application/json, text/html;level=1;q=0.001",
    "text/html;q=0, text/html;q=0.5",
    "text/html; q=1.000",
  ];
  const rechazados = [
    null,
    "*/*",
    "application/xhtml+xml",
    "text/html;q=0",
    "text/html;q=0.000",
    "text/html;q=.5",
    "text/html;q=1.001",
    "text/html;q=0.1234",
    'text/html;q="0.5"',
    "text/html;q=0.5;q=1",
    'text/html;nota="sin-cierre',
  ];

  for (const accept of aceptados) {
    afirmar(
      debeContar({ ...SENAL_POSITIVA, accept }),
      `debía aceptar: ${accept}`,
    );
  }
  for (const accept of rechazados) {
    afirmar(
      !debeContar({ ...SENAL_POSITIVA, accept }),
      `debía rechazar: ${accept}`,
    );
  }
});

Deno.test("conteo: exige todas las señales positivas de navegación", () => {
  afirmar(debeContar(SENAL_POSITIVA), "navegación humana completa");

  const negativas: Array<[string, Partial<SenalesConteo>]> = [
    ["método HEAD", { metodo: "HEAD" }],
    ["sin user agent", { userAgent: null }],
    ["sin mode", { secFetchMode: null }],
    ["mode distinto", { secFetchMode: "cors" }],
    ["sin dest", { secFetchDest: null }],
    ["dest distinto", { secFetchDest: "empty" }],
    ["prefetch", { purpose: "prefetch" }],
    ["preview", { secPurpose: "preview" }],
  ];
  for (const [nombre, cambio] of negativas) {
    afirmar(!debeContar({ ...SENAL_POSITIVA, ...cambio }), nombre);
  }
});

Deno.test("conteo: excluye robots, previews y clientes HTTP", () => {
  for (
    const userAgent of [
      "facebookexternalhit/1.1",
      "Twitterbot/1.0",
      "TelegramBot",
      "WhatsApp/2.24",
      "Mozilla/5.0 HeadlessChrome/130",
      "Lighthouse",
      "curl/8.10.1",
      "undici",
      "python-requests/2.32",
    ]
  ) {
    afirmar(
      !debeContar({ ...SENAL_POSITIVA, userAgent }),
      `agente automático: ${userAgent}`,
    );
  }

  afirmar(
    debeContar({ ...SENAL_POSITIVA, userAgent: "FBAN/FBIOS; Mobile Safari" }),
    "una app integrada sin firma bot no se excluye por nombre",
  );
});

Deno.test("IP: fuente cerrada, IPv4 normalizada, IPv6 y primer XFF", () => {
  for (
    const fuente of [
      "cf-connecting-ip",
      "x-real-ip",
      "x-forwarded-for",
    ] as const
  ) {
    afirmarIgual(validarFuenteIp(fuente), fuente, `fuente ${fuente}`);
  }
  for (const fuente of [null, "", "forwarded", "X-Real-IP"]) {
    afirmarIgual(validarFuenteIp(fuente), null, `fuente inválida ${fuente}`);
  }

  afirmarIgual(
    obtenerIp("x-real-ip", " 203.000.113.007 "),
    "203.0.113.7",
    "IPv4",
  );
  afirmarIgual(
    obtenerIp("cf-connecting-ip", "2001:0db8:0:0:0:0:0:1"),
    "2001:db8::1",
    "IPv6",
  );
  afirmarIgual(
    obtenerIp("x-forwarded-for", " 198.51.100.8, 203.0.113.9"),
    "198.51.100.8",
    "primer XFF",
  );
  for (
    const valor of [
      null,
      "",
      "256.1.1.1",
      "1.2.3",
      "1.2.3.4, 5.6.7.8",
      "[2001:db8::1]",
      "fe80::1%eth0",
    ]
  ) {
    afirmarIgual(obtenerIp("x-real-ip", valor), null, `IP inválida ${valor}`);
  }
});

Deno.test("fecha Colombia: cambia a medianoche UTC-5 incluso entre años", () => {
  afirmarIgual(
    fechaColombia(new Date("2026-01-01T04:59:59.999Z")),
    "2025-12-31",
    "antes de medianoche",
  );
  afirmarIgual(
    fechaColombia(new Date("2026-01-01T05:00:00.000Z")),
    "2026-01-01",
    "desde medianoche",
  );
});

Deno.test("HMAC diario: secreto mínimo, vector fijo y separación por día/IP", async () => {
  afirmar(!esSecretoMaestroValido("x".repeat(31)), "31 bytes no bastan");
  afirmar(esSecretoMaestroValido("x".repeat(32)), "32 bytes bastan");
  afirmar(
    esSecretoMaestroValido("á".repeat(16)),
    "el mínimo se mide en bytes UTF-8",
  );
  afirmar(
    !esSecretoMaestroValido(" ".repeat(40)),
    "solo espacios no es secreto",
  );

  const secreto = "secreto-maestro-de-prueba-1234567890";
  const hash = await crearHashIp(
    secreto,
    "2026-01-01",
    "203.0.113.7",
    crypto.subtle,
  );
  afirmarIgual(
    hash,
    "df2246470aa18b895991e800d1dc787dd5f775b7f6272fd61807bf9e2864ac6c",
    "vector HMAC independiente",
  );
  afirmarIgual(
    await crearHashIp(secreto, "2026-01-01", "203.0.113.7", crypto.subtle),
    hash,
    "determinismo",
  );
  afirmar(
    await crearHashIp(secreto, "2026-01-02", "203.0.113.7", crypto.subtle) !==
      hash,
    "rota por fecha",
  );
  afirmar(
    await crearHashIp(secreto, "2026-01-01", "203.0.113.8", crypto.subtle) !==
      hash,
    "separa IP",
  );

  let rechazo = "";
  try {
    await crearHashIp("débil", "2026-01-01", "203.0.113.7", crypto.subtle);
  } catch (error) {
    rechazo = error instanceof Error ? error.message : String(error);
  }
  afirmarIgual(
    rechazo,
    "P3_MASTER_SECRET_INVALID",
    "secreto débil falla cerrado",
  );
});
