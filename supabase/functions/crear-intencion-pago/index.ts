// ============================================================================
// Magandhi Corporation · Edge Function · crear-intencion-pago (Fase F · Tramo F1.2)
// ----------------------------------------------------------------------------
// PRIMERA Edge Function del proyecto. Recibe del navegador (tienda magandhi.com)
// un identificador de producto (slug o id de catalogo_publico) + una cantidad,
// RELEE el precio server-side desde la base (NUNCA confia en el precio del
// navegador), calcula el monto en centavos, genera una referencia unica y
// calcula la FIRMA DE INTEGRIDAD de Wompi server-side. Devuelve al navegador los
// datos publicos necesarios para abrir el checkout de Wompi.
//
// ============================================================================
// LINEA ROJA DE SEGURIDAD (orden permanente del dueno · NO negociable):
//   - El PRECIO nunca sale del navegador: se relee de catalogo_publico aqui.
//   - Los SECRETOS de Wompi (integridad) viven SOLO como secrets de la Edge
//     Function en Deno.env (WOMPI_INTEGRITY_SANDBOX / WOMPI_INTEGRITY_PROD),
//     NUNCA en el repo, ni en una tabla, ni en el frontend, ni en logs.
//   - La firma de integridad se calcula DENTRO de esta funcion (server-side).
//   - La SERVICE_ROLE_KEY la inyecta el runtime de Supabase en Deno.env; jamas
//     se hardcodea ni se devuelve al navegador.
//
// ============================================================================
// FRONTERA F1 / F2 (respetar · NO cruzar):
//   F1 SOLO crea la intencion de pago (firma + datos de pago). F1 NO llama a la
//   RPC crear_pedido, NO baja stock, y NO persiste la referencia en la tabla de
//   idempotencia pagos_wompi. Eso es F2 (webhook wompi-webhook): la verdad del
//   pago llega por el webhook transaction.updated y SOLO un pago APPROVED crea
//   el pedido (canal='web') y baja el stock. "El pago aun no crea pedido" es
//   correcto y esperado en F1. La regla dura del proyecto es "el stock baja solo
//   AL PAGAR".
//
// ============================================================================
// FIRMA DE INTEGRIDAD (confirmada con la doc oficial vigente de Wompi Colombia,
// docs.wompi.co/docs/colombia/widget-checkout-web):
//   firma = SHA-256 (hex, minusculas) de la concatenacion SIN separadores, en
//   este orden EXACTO:  <Referencia><MontoEnCentavos><Moneda><SecretoIntegridad>
//   Ejemplo oficial: 'sk8-438k4-xmxm392-sn2m' + '2490000' + 'COP' +
//                    'prod_integrity_...'  ->  sha256 hex.
//   Moneda = 'COP'. Monto en CENTAVOS (pesos x100).
//   DECISION F1 (documentada): NO se usa expiration-time en F1 (formula de 4
//   campos, sin fecha de expiracion; la verdad del pago llega por webhook en F2).
// ============================================================================

// supabase-js pineado a la version EXACTA del proyecto (@2.116.0), importado por
// URL desde esm.sh (regla B2: version fija, nunca flotante).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.116.0";

// ----------------------------------------------------------------------------
// CORS: la tienda publica magandhi.com invoca esta funcion desde el navegador.
// Se permiten los origenes de la tienda (con y sin www) y el subdominio de
// GitHub Pages usado durante el desarrollo. La cabecera 'apikey' y
// 'authorization' son necesarias porque la tienda llama con supabase.functions
// .invoke usando la publishable/anon key.
// ----------------------------------------------------------------------------
const ORIGENES_PERMITIDOS = new Set<string>([
  "https://magandhi.com",
  "https://www.magandhi.com",
  "https://12344-ux.github.io",
]);

function cabecerasCors(origin: string | null): Record<string, string> {
  // Si el origin viene en la lista blanca lo reflejamos; si no, caemos al
  // dominio canonico de la tienda (no usamos '*' porque enviamos credenciales
  // como la apikey en las cabeceras).
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

// Respuesta JSON con las cabeceras de CORS ya puestas.
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
// Calcula la firma de integridad de Wompi: SHA-256 (hex minusculas) de la
// cadena  referencia + monto_en_centavos + moneda + secreto_integridad  (sin
// separadores). Usa la Web Crypto API (crypto.subtle), disponible en el runtime
// de Deno de Supabase.
// ----------------------------------------------------------------------------
async function calcularFirmaIntegridad(
  referencia: string,
  montoEnCentavos: string,
  moneda: string,
  secretoIntegridad: string,
): Promise<string> {
  const cadena = `${referencia}${montoEnCentavos}${moneda}${secretoIntegridad}`;
  const datos = new TextEncoder().encode(cadena);
  const hash = await crypto.subtle.digest("SHA-256", datos);
  // Convertir el ArrayBuffer a hex en minusculas.
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// ----------------------------------------------------------------------------
// Genera una referencia unica de transaccion. Formato alfanumerico valido para
// Wompi (letras/digitos y guiones): MAG-<idcorto>-<epochms>-<random>.
// NOTA F1/F2: F1 SOLO genera y devuelve esta referencia; su PERSISTENCIA e
// idempotencia (tabla pagos_wompi) son de F2. Aqui no se guarda en ninguna
// tabla.
// ----------------------------------------------------------------------------
function generarReferencia(idProducto: string): string {
  const idCorto = String(idProducto).replace(/[^a-zA-Z0-9]/g, "").slice(0, 8) ||
    "prod";
  const epochMs = Date.now();
  // Parte aleatoria a partir de un UUID (solo digitos hex, sin guiones).
  const aleatorio = crypto.randomUUID().replace(/-/g, "").slice(0, 12);
  return `MAG-${idCorto}-${epochMs}-${aleatorio}`;
}

// Detecta si un identificador de producto tiene forma de UUID (para decidir si
// se filtra por id o por slug en catalogo_publico).
function pareceUuid(valor: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    .test(valor);
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

  const producto = typeof body?.producto === "string"
    ? body.producto.trim()
    : "";
  if (!producto) {
    return json(
      { error: "Falta 'producto' (slug o id del catalogo)." },
      400,
      cors,
    );
  }

  // Cantidad: entero >= 1, por defecto 1 si falta. Se ignora cualquier valor no
  // entero o < 1.
  let cantidad = 1;
  if (body?.cantidad !== undefined && body?.cantidad !== null) {
    const n = Number(body.cantidad);
    if (!Number.isInteger(n) || n < 1) {
      return json(
        { error: "'cantidad' debe ser un entero mayor o igual a 1." },
        400,
        cors,
      );
    }
    cantidad = n;
  }

  // IMPORTANTE (linea roja): a proposito NO se lee ningun campo de precio/monto
  // del body. El precio NUNCA sale del navegador; se relee de la BD mas abajo.

  // --- Cliente Supabase server-side (SERVICE_ROLE, inyectada por el runtime) -
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    // No se filtra el valor; solo se informa que falta la configuracion.
    return json(
      { error: "Configuracion del servidor incompleta (Supabase)." },
      500,
      cors,
    );
  }
  // Se fuerza la SERVICE_ROLE en las cabeceras globales del cliente. Sin esto,
  // supabase-js hereda el JWT anon (publishable key) que llega en el header
  // Authorization de la peticion del navegador y lo usa en las consultas, de
  // modo que RLS bloquearia la lectura de pagos_config (solo authenticated con
  // tiene_modulo('finanzas'), sin grant a anon) y la funcion responderia 500.
  // Con la service_role en Authorization se salta RLS en TODAS las consultas.
  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${serviceRoleKey}` } },
  });

  // --- (1) Releer el producto de catalogo_publico server-side ---------------
  // catalogo_publico expone id, slug, nombre, precio_venta (pesos enteros) y
  // agotado (booleano derivado del stock real; NUNCA numeros). Se filtra por id
  // si parece UUID, si no por slug.
  const columna = pareceUuid(producto) ? "id" : "slug";
  const { data: fila, error: errorCatalogo } = await supabase
    .from("catalogo_publico")
    .select("id, slug, nombre, precio_venta, agotado")
    .eq(columna, producto)
    .maybeSingle();

  if (errorCatalogo) {
    return json(
      { error: "No se pudo consultar el catalogo." },
      500,
      cors,
    );
  }
  if (!fila) {
    return json({ error: "Producto no encontrado." }, 404, cors);
  }

  // --- (2) Rechazar producto agotado ----------------------------------------
  // Coherente con el boton Comprar deshabilitado en la tienda cuando agotado.
  if (fila.agotado === true) {
    return json({ error: "Producto agotado." }, 409, cors);
  }

  // --- Validar el precio (entero positivo) ----------------------------------
  // precio_venta puede llegar como number o como string desde PostgREST; se
  // parsea a entero de forma estricta.
  const precioTexto = String(fila.precio_venta ?? "").trim();
  if (!/^\d+$/.test(precioTexto) || precioTexto === "0") {
    return json(
      { error: "El producto no tiene un precio valido configurado." },
      422,
      cors,
    );
  }

  // --- (3) Leer pagos_config (id=1): entorno + llaves publicas ---------------
  const { data: config, error: errorConfig } = await supabase
    .from("pagos_config")
    .select("entorno, llave_publica_sandbox, llave_publica_prod")
    .eq("id", 1)
    .maybeSingle();

  if (errorConfig || !config) {
    return json(
      { error: "No se pudo leer la configuracion de pagos." },
      500,
      cors,
    );
  }

  const entorno = config.entorno === "prod" ? "prod" : "sandbox";
  const llavePublica = entorno === "prod"
    ? (config.llave_publica_prod ?? "")
    : (config.llave_publica_sandbox ?? "");
  if (!llavePublica) {
    return json(
      {
        error:
          `Llave publica no configurada para el entorno '${entorno}'. ` +
          `Pega la llave publica en pagos_config.`,
      },
      500,
      cors,
    );
  }

  // --- Leer el secreto de integridad de Deno.env segun el entorno -----------
  // Nombres EXACTOS de los secrets (se ponen en Edge Functions > Secrets):
  //   WOMPI_INTEGRITY_SANDBOX  y  WOMPI_INTEGRITY_PROD.
  // NUNCA se hardcodea ni se loguea el valor.
  const nombreSecreto = entorno === "prod"
    ? "WOMPI_INTEGRITY_PROD"
    : "WOMPI_INTEGRITY_SANDBOX";
  const secretoIntegridad = Deno.env.get(nombreSecreto);
  if (!secretoIntegridad) {
    // No se filtra el valor ni el nombre exacto al navegador.
    return json(
      { error: "Secreto de integridad no configurado en el servidor." },
      500,
      cors,
    );
  }

  // --- Calcular el monto en centavos server-side ----------------------------
  // Conversion pesos -> centavos: se multiplica por 100 (Wompi cobra en
  // CENTAVOS). Se usa BigInt para evitar cualquier problema de precision con
  // montos grandes.  monto_en_centavos = precio_venta (pesos) * cantidad * 100.
  const precioBig = BigInt(precioTexto); // pesos enteros
  const montoEnCentavosBig = precioBig * BigInt(cantidad) * 100n;
  const montoEnCentavos = montoEnCentavosBig.toString(); // entero como texto

  // --- Generar la referencia unica y la moneda ------------------------------
  const referencia = generarReferencia(fila.id ?? fila.slug ?? "prod");
  const moneda = "COP";

  // --- Calcular la firma de integridad (server-side) ------------------------
  const firmaIntegridad = await calcularFirmaIntegridad(
    referencia,
    montoEnCentavos,
    moneda,
    secretoIntegridad,
  );

  // --- URL de redireccion tras el pago --------------------------------------
  // PROVISIONAL hasta F2.3 (pagina de gracias). Mientras no exista /gracias/,
  // redirigimos a la pagina del producto con la referencia como parametro, para
  // que el comprador vuelva a un lugar conocido de la tienda.
  const urlRedireccion =
    `https://magandhi.com/producto/?slug=${encodeURIComponent(fila.slug ?? "")}` +
    `&ref=${encodeURIComponent(referencia)}`;

  // --- Respuesta 200: SOLO datos publicos -----------------------------------
  // NUNCA se incluye el secreto de integridad ni la service_role.
  // monto_en_centavos se devuelve como STRING: es EXACTAMENTE la misma cadena
  // sobre la que se calculo la firma (montoEnCentavosBig.toString()). Asi se
  // elimina toda asimetria entre lo firmado y lo enviado a Wompi: no pasa por
  // Number(), que podria redondear montos por encima de 2^53 centavos y hacer
  // que la firma que rehashea Wompi no coincida con la firmada aqui. Wompi
  // acepta amount-in-cents como texto.
  return json(
    {
      referencia,
      monto_en_centavos: montoEnCentavos,
      moneda,
      firma_integridad: firmaIntegridad,
      llave_publica: llavePublica,
      url_redireccion: urlRedireccion,
      nombre_producto: fila.nombre ?? "",
    },
    200,
    cors,
  );
});
