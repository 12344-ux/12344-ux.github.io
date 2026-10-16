// ============================================================================
// MAGANDHI · Edge Function · crear-intencion-pago (Fase F · Tramo F1.2)
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
// ----------------------------------------------------------------------------
// D2c.2c · VERIFICACION EN VIVO contra Dropi antes de cobrar
// ----------------------------------------------------------------------------
// Para un producto PROPIO no hace nada: su candado es el libro de Inventario y
// lo aplica crear_pedido. Para uno de PROVEEDOR le pregunta a Dropi ahora.
//
// EL CRITERIO, que es la decision dificil de todo el tramo:
//   · Dropi responde que NO hay  -> se rechaza. Fallo cerrado, sin discusion.
//   · Dropi NO responde (caido, 429, lento) y la ultima lectura es FRESCA
//     -> se permite. Esa lectura ya paso la vigencia y el piso, y es la mejor
//     informacion disponible. Bloquear aqui convertiria cualquier hipo de Dropi
//     en una tienda caida, que es peor que el riesgo que evita.
//   · Dropi NO responde y la lectura YA ENVEJECIO -> se rechaza. Si no hay
//     forma de confirmar y la evidencia tiene tiempo, no se cobra.
//
// El umbral de frescura vive en dropshipping_config, no aqui.
// ----------------------------------------------------------------------------
const DROPI_BASE = (Deno.env.get("DROPI_API_BASE") ?? "https://api.dropi.co/integrations/")
  .replace(/\/*$/, "/");
const DROPI_UA = () =>
  (Deno.env.get("DROPI_USER_AGENT") ?? "MAGANDHI-Impulse/1.0 (+https://magandhi.com)").trim();

type Obj = Record<string, unknown>;
const esObjeto = (v: unknown): v is Obj => !!v && typeof v === "object" && !Array.isArray(v);

const sumarStockBodegas = (filas: unknown): number | null =>
  Array.isArray(filas)
    ? filas.reduce((s: number, w) => s + (esObjeto(w) ? Number(w.stock) || 0 : 0), 0)
    : null;

function stockDeVariacion(v: Obj): number | null {
  if (typeof v.stock === "number") return v.stock;
  if (Array.isArray(v.warehouse_product_variation)) {
    return sumarStockBodegas(v.warehouse_product_variation);
  }
  return null;
}

// Misma regla que dropi-refrescar-stock: si el registro tiene variante, el
// stock sale de ESA variante. Usar el total del producto venderia humo de una
// talla agotada porque otra tiene unidades.
function stockDeLaFicha(p: Obj, variacion: string | null): number | null {
  const variaciones = Array.isArray(p.variations) ? p.variations : [];
  if (variacion) {
    const v = variaciones.find((x) => esObjeto(x) && String(x.id) === variacion);
    // La variante desaparecio del catalogo: es exactamente «no hay».
    if (!esObjeto(v)) return 0;
    return stockDeVariacion(v) ?? 0;
  }
  if (String(p.type ?? "").toUpperCase() === "VARIABLE" && variaciones.length) {
    return variaciones.reduce(
      (s: number, v) => s + (esObjeto(v) ? (stockDeVariacion(v) ?? 0) : 0),
      0,
    );
  }
  if (typeof p.stock === "number") return p.stock;
  return sumarStockBodegas(p.warehouse_product);
}

async function verificarProveedorEnVivo(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  campanaId: string,
  cantidad: number,
  maxCatalogo: number,
): Promise<{ rechazar: boolean; maxComprable: number; log: Obj }> {
  let datos: Obj | null = null;
  try {
    const { data, error } = await supabase.rpc("ds_verificacion_checkout", {
      p_campana_id: campanaId,
    });
    if (error) {
      return {
        rechazar: true,
        maxComprable: 0,
        log: { motivo: "fallo ds_verificacion_checkout", codigo: error.code ?? null },
      };
    }
    datos = esObjeto(data) ? data : null;
  } catch (_) {
    datos = null;
  }

  // C1 depende de esta lectura autoritativa. Una RPC ausente o sin datos falla
  // cerrada; no se firma una intención que omitió una de sus reglas.
  if (!datos) {
    return {
      rechazar: true,
      maxComprable: 0,
      log: { motivo: "sin datos de verificacion" },
    };
  }
  if (datos.origen !== "proveedor") {
    return {
      rechazar: false,
      maxComprable: maxCatalogo,
      log: { origen: datos.origen },
    };
  }

  const dropiId = String(datos.dropi_id ?? "");
  const variante = datos.variante == null ? null : String(datos.variante);
  const piso = Number(datos.piso ?? 20);
  const reservadas = Number(datos.reservadas ?? 0);
  const disponibleLocal = Number(datos.disponible_local ?? 0);
  const minutos = datos.minutos_desde_lectura == null ? null : Number(datos.minutos_desde_lectura);
  const frescuraMax = Number(datos.frescura_max_min ?? 10);
  const token = (Deno.env.get("DROPI_TOKEN") ?? "").trim();
  const maxCache = Number.isFinite(disponibleLocal)
    ? Math.max(0, Math.min(20, maxCatalogo, Math.floor(disponibleLocal)))
    : 0;

  // Sin id externo no hay a quien preguntarle, y tampoco a quien pedirle.
  if (!/^\d{1,12}$/.test(dropiId)) {
    return {
      rechazar: true,
      maxComprable: 0,
      log: { motivo: "producto proveedor sin id de Dropi" },
    };
  }

  const lecturaFresca = minutos !== null && minutos <= frescuraMax;
  const cacheAlcanza = maxCache >= cantidad;

  if (!token) {
    const permitido = lecturaFresca && cacheAlcanza;
    return {
      rechazar: !permitido,
      maxComprable: permitido ? maxCache : 0,
      log: {
        motivo: "falta DROPI_TOKEN",
        lectura_min: minutos,
        disponible_local: disponibleLocal,
        cantidad,
        permitido,
      },
    };
  }

  let http = 0;
  let cuerpo: Obj | null = null;
  try {
    const ctrl = new AbortController();
    const t = setTimeout(() => ctrl.abort(), 6000);
    try {
      const r = await fetch(`${DROPI_BASE}products/v2/${encodeURIComponent(dropiId)}`, {
        method: "GET",
        headers: {
          "Content-Type": "application/json;charset=UTF-8",
          "dropi-integration-key": token,
          Accept: "application/json",
          "User-Agent": DROPI_UA(),
        },
        signal: ctrl.signal,
      });
      http = r.status;
      const texto = await r.text();
      try {
        const j = JSON.parse(texto);
        cuerpo = esObjeto(j?.objects) ? j.objects as Obj : null;
      } catch { /* no era JSON */ }
    } finally {
      clearTimeout(t);
    }
  } catch (_) {
    http = 0;
  }

  if (http !== 200 || !cuerpo) {
    const permitido = lecturaFresca && cacheAlcanza;
    return {
      rechazar: !permitido,
      maxComprable: permitido ? maxCache : 0,
      log: {
        motivo: "Dropi no confirmo",
        http,
        lectura_min: minutos,
        frescura_max: frescuraMax,
        disponible_local: disponibleLocal,
        cantidad,
        permitido,
      },
    };
  }

  const stock = stockDeLaFicha(cuerpo, variante);
  if (stock === null) {
    const permitido = lecturaFresca && cacheAlcanza;
    return {
      rechazar: !permitido,
      maxComprable: permitido ? maxCache : 0,
      log: {
        motivo: "ficha sin stock reconocible",
        disponible_local: disponibleLocal,
        cantidad,
        permitido,
      },
    };
  }

  // Dropi habló: stock - reservas - cantidad debe seguir por encima del piso.
  const maxVivo = Math.max(
    0,
    Math.min(20, maxCatalogo, Math.floor(stock - reservadas - piso)),
  );
  const remanente = stock - reservadas - cantidad;
  const alcanza = cantidad <= maxVivo && remanente >= piso;
  return {
    rechazar: !alcanza,
    maxComprable: maxVivo,
    log: { http, stock, reservadas, cantidad, remanente, piso, max_vivo: maxVivo, alcanza },
  };
}

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

  // C1 comercial: por defecto 1 para clientes existentes; si se envía, debe
  // ser un entero seguro dentro del techo técnico global 1..20. El máximo
  // efectivo de la campaña se valida después contra catalogo_publico y otra
  // vez dentro de pw_registrar_intencion.
  let cantidad = 1;
  if (body?.cantidad !== undefined && body?.cantidad !== null) {
    const n = body.cantidad;
    if (typeof n !== "number" || !Number.isSafeInteger(n) || n < 1 || n > 20) {
      return json(
        { error: "'cantidad' debe ser un entero entre 1 y 20." },
        400,
        cors,
      );
    }
    cantidad = n;
  }

  // IMPORTANTE (linea roja): a proposito NO se lee ningun campo de precio/monto
  // del body. El precio NUNCA sale del navegador; se relee de la BD mas abajo.

  // --- F2: datos del COMPRADOR y procedencia de la visita -------------------
  // Decision del dueno (8-oct-2026): el pedido web se crea con lo que el
  // comprador escribio EN LA TIENDA; de Wompi solo se usa la CONFIRMACION del
  // pago. Por eso estos campos se persisten en la intencion y el webhook los
  // usa tal cual.
  // Se recortan a longitudes sanas y se aceptan vacios: la intencion puede
  // existir sin ellos (el formulario los valida del lado de la tienda) y el
  // webhook cae a 'Comprador web' si faltara el nombre.
  const texto = (v: unknown, max: number) =>
    typeof v === "string" && v.trim() !== "" ? v.trim().slice(0, max) : null;
  const c = (body?.comprador ?? {}) as Record<string, unknown>;
  const comprador = {
    nombre: texto(c.nombre, 120),
    correo: texto(c.correo, 160),
    telefono: texto(c.telefono, 40),
    direccion: texto(c.direccion, 200),
    ciudad: texto(c.ciudad, 80),
    departamento: texto(c.departamento, 80),
    pais: texto(c.pais, 60),
  };
  // Procedencia: utm_campaign da ATRIBUCION EXACTA a las campanas de correo
  // (hoy es aproximada) y mg_vid es el id ALEATORIO de la analitica propia
  // (sin nombre ni correo) que Metricas esperaba para medir el embudo real
  // hasta la compra. Se validan con formato estricto: entran a la base.
  const utmBruto = texto(body?.utm_campaign, 60);
  const utm = utmBruto && /^[a-z0-9-]{1,60}$/.test(utmBruto) ? utmBruto : null;
  const vidBruto = texto(body?.mg_vid, 40);
  const mgVid = vidBruto && /^[A-Za-z0-9_-]{16,40}$/.test(vidBruto) ? vidBruto : null;

  // DIAGNOSTICO: marca de entrada para correlacionar la invocacion en los logs.
  // Solo datos no sensibles (que producto se pidio y cuantas unidades).
  console.log(
    "[crear-intencion-pago] Intencion solicitada:",
    JSON.stringify({ producto, cantidad }),
  );

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
  // catalogo_publico expone únicamente el máximo ya acotado por Campañas y
  // disponibilidad. Nunca revela stock, piso, reservas ni proveedor.
  const columna = pareceUuid(producto) ? "id" : "slug";
  const { data: fila, error: errorCatalogo } = await supabase
    .from("catalogo_publico")
    .select("id, slug, nombre, precio_venta, agotado, max_comprable")
    .eq(columna, producto)
    .maybeSingle();

  if (errorCatalogo) {
    // DIAGNOSTICO: detalle real del fallo de lectura del catalogo (sin secretos).
    console.error(
      "[crear-intencion-pago] Fallo lectura catalogo_publico:",
      JSON.stringify({
        message: errorCatalogo?.message ?? null,
        code: (errorCatalogo as { code?: string } | null)?.code ?? null,
        details: (errorCatalogo as { details?: string } | null)?.details ?? null,
        hint: (errorCatalogo as { hint?: string } | null)?.hint ?? null,
        columna,
      }),
    );
    return json(
      { error: "No se pudo consultar el catalogo." },
      500,
      cors,
    );
  }
  if (!fila) {
    // DIAGNOSTICO: que se busco y por que columna (el identificador no es secreto).
    console.error(
      "[crear-intencion-pago] Producto no encontrado:",
      JSON.stringify({ buscado: producto, columna }),
    );
    return json({ error: "Producto no encontrado." }, 404, cors);
  }

  // --- (2) Validar el máximo público efectivo ------------------------------
  const maxComprable = Number(fila.max_comprable);
  if (!Number.isInteger(maxComprable) || maxComprable < 0 || maxComprable > 20) {
    console.error(
      "[crear-intencion-pago] max_comprable invalido:",
      JSON.stringify({ campana_id: fila.id ?? null, max_comprable: fila.max_comprable ?? null }),
    );
    return json({ error: "No se pudo validar la disponibilidad." }, 500, cors);
  }
  if (cantidad > maxComprable) {
    return json(
      {
        error: "La cantidad solicitada supera el máximo disponible para este pedido.",
        codigo: "MAX_COMPRABLE",
        max_comprable: maxComprable,
      },
      409,
      cors,
    );
  }

  // Coherencia defensiva: agotado debe equivaler a max_comprable=0.
  if (fila.agotado === true || maxComprable === 0) {
    return json(
      {
        error: "Producto agotado.",
        codigo: "MAX_COMPRABLE",
        max_comprable: 0,
      },
      409,
      cors,
    );
  }

  // --- (2 bis) D2c.2c · VERIFICACION EN VIVO del producto de proveedor ------
  // El booleano `agotado` sale de una FOTOGRAFIA de Dropi, no del presente. Es
  // fresca (el reloj refresca cada minuto) pero no es ahora. Aqui, con el
  // cliente a un clic de pagar, se le pregunta a Dropi DIRECTAMENTE.
  //
  // Es el unico momento del flujo en que vale la pena gastar una peticion
  // externa: ocurre una vez por compra, no por visita, asi que no amenaza el
  // limite de Dropi (429 medido alrededor de la peticion 12-16 en rafaga).
  //
  // Va DESPUES del chequeo de agotado y ANTES de registrar la intencion: si
  // rechaza, no queda rastro de una intencion que nunca debio existir.
  const verificacion = await verificarProveedorEnVivo(
    supabase,
    String(fila.id),
    cantidad,
    maxComprable,
  );
  if (verificacion.rechazar) {
    console.log("[crear-intencion-pago] proveedor rechazado en vivo:", JSON.stringify(verificacion.log));
    return json(
      {
        error: "La disponibilidad cambió; ajusta la cantidad e intenta de nuevo.",
        codigo: "MAX_COMPRABLE",
        max_comprable: verificacion.maxComprable,
      },
      409,
      cors,
    );
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

  // --- (3) Leer la configuracion de pagos por RPC (NO por lectura directa) ---
  // Se lee entorno + llave publica del entorno activo a traves de la RPC
  // SECURITY DEFINER pagos_config_para_intencion(), NO leyendo la tabla
  // pagos_config directo por PostgREST. Por que: aunque este cliente usa la
  // SERVICE_ROLE_KEY, la peticion del navegador tambien lleva el header
  // apikey=anon (supabase-js lo adjunta) y PostgREST degrada el rol efectivo a
  // anon/authenticated; como pagos_config tiene RLS, la lectura directa de la
  // TABLA quedaba bloqueada (500). La RPC definer corre con los privilegios de
  // su dueno, sortea ese problema y devuelve SOLO datos publicos (entorno +
  // llave publica del entorno activo, nunca la fila completa ni secretos).
  const { data: configFilas, error: errorConfig } = await supabase.rpc(
    "pagos_config_para_intencion",
  );

  // La RPC devuelve una tabla (0..n filas); tomamos la primera (id=1).
  const config = Array.isArray(configFilas) ? configFilas[0] : configFilas;
  if (errorConfig || !config) {
    // DIAGNOSTICO: se loguea el detalle REAL del fallo para poder verlo en
    // Edge Functions > Logs. Sin esto el 500 no dice por que fallo (el mensaje
    // al navegador es generico a proposito). NUNCA se loguean secretos: solo
    // mensajes de error y metadatos no sensibles.
    console.error(
      "[crear-intencion-pago] Fallo RPC pagos_config_para_intencion:",
      JSON.stringify({
        message: errorConfig?.message ?? null,
        code: (errorConfig as { code?: string } | null)?.code ?? null,
        details: (errorConfig as { details?: string } | null)?.details ?? null,
        hint: (errorConfig as { hint?: string } | null)?.hint ?? null,
        tipoConfigFilas: typeof configFilas,
        esArray: Array.isArray(configFilas),
        largo: Array.isArray(configFilas) ? configFilas.length : null,
      }),
    );
    // Mismo mensaje y contrato que antes (no se cambia la respuesta al cliente).
    return json(
      { error: "No se pudo leer la configuracion de pagos." },
      500,
      cors,
    );
  }

  // La RPC ya resolvio la llave publica del entorno activo: se usa directamente.
  const entorno = config.entorno === "prod" ? "prod" : "sandbox";
  const llavePublica = config.llave_publica ?? "";
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
    // DIAGNOSTICO: se loguea SOLO EL NOMBRE de la variable que se busco, nunca
    // su valor (linea roja: el secreto jamas se escribe en un log).
    console.error(
      "[crear-intencion-pago] Secreto de integridad ausente. Variable esperada:",
      nombreSecreto,
      "| entorno:",
      entorno,
    );
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

  // --- F2: PERSISTIR LA INTENCION ANTES DE FIRMAR ---------------------------
  // Esta es la frontera que F2 cruza respecto a F1. Se guarda ANTES de firmar
  // porque la firma es el punto sin retorno: a partir de ahi el comprador puede
  // pagar, y si no existiera la fila el webhook recibiria un pago que no sabria
  // a que producto corresponde (dinero huerfano).
  //
  // Se guarda el MONTO FIRMADO para que el webhook lo compare con el que
  // informe Wompi y nunca confie en el monto que llega.
  //
  // Si esto falla, NO se firma: es preferible que el comprador reintente que
  // cobrarle sin poder convertirlo en pedido.
  const { data: intencion, error: errorIntencion } = await supabase.rpc(
    "pw_registrar_intencion",
    {
      p_referencia: referencia,
      p_campana_id: fila.id ?? null,
      p_slug: fila.slug ?? null,
      p_nombre: fila.nombre ?? null,
      p_cantidad: cantidad,
      p_precio_unitario: precioTexto,
      p_monto_centavos: montoEnCentavos,
      p_entorno: entorno === "prod" ? "prod" : "sandbox",
      p_comprador: comprador,
      p_utm_campaign: utm,
      p_mg_vid: mgVid,
      p_moneda: moneda,
    },
  );
  if (errorIntencion) {
    // Una baja entre la lectura pública y el lock autoritativo se informa con el
    // mismo contrato público 409, sin filtrar detalles internos.
    const maxEnError = /PW_MAX_COMPRABLE:(\d{1,2})/.exec(errorIntencion.message ?? "");
    if (maxEnError) {
      const maxActual = Math.max(0, Math.min(20, Number(maxEnError[1])));
      return json(
        {
          error: "La disponibilidad cambió; ajusta la cantidad e intenta de nuevo.",
          codigo: "MAX_COMPRABLE",
          max_comprable: maxActual,
        },
        409,
        cors,
      );
    }
    // Se loguea el motivo REAL de PostgREST (sin secretos).
    console.error(
      "[crear-intencion-pago] No se pudo persistir la intencion:",
      JSON.stringify({
        message: errorIntencion.message,
        code: (errorIntencion as { code?: string }).code,
        details: (errorIntencion as { details?: string }).details,
        hint: (errorIntencion as { hint?: string }).hint,
      }),
    );
    return json(
      { error: "No se pudo iniciar el pago. Intenta de nuevo." },
      500,
      cors,
    );
  }

  const intencionRegistrada = esObjeto(intencion) ? intencion : null;
  const montoFirmado = String(intencionRegistrada?.monto_centavos ?? "");
  const monedaFirmada = String(intencionRegistrada?.moneda ?? "");
  if (!/^\d+$/.test(montoFirmado) || montoFirmado !== montoEnCentavos || monedaFirmada !== moneda) {
    console.error("[crear-intencion-pago] Snapshot autoritativo inconsistente.");
    return json({ error: "No se pudo confirmar el monto del pago." }, 500, cors);
  }

  // --- Calcular la firma de integridad (server-side) ------------------------
  // Se firma el monto que devolvió la RPC después de repetir las reglas bajo
  // lock; nunca una cifra calculada solo desde la primera lectura pública.
  const firmaIntegridad = await calcularFirmaIntegridad(
    referencia,
    montoFirmado,
    monedaFirmada,
    secretoIntegridad,
  );

  // --- URL de redireccion tras el pago --------------------------------------
  // PROVISIONAL hasta F2.3 (pagina de gracias). Mientras no exista /gracias/,
  // redirigimos a la pagina del producto con la referencia como parametro, para
  // que el comprador vuelva a un lugar conocido de la tienda.
  const destinoProducto = fila.slug
    ? `slug=${encodeURIComponent(String(fila.slug))}`
    : `id=${encodeURIComponent(String(fila.id ?? ""))}`;
  const urlRedireccion =
    `https://magandhi.com/producto/?${destinoProducto}` +
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
      monto_en_centavos: montoFirmado,
      moneda: monedaFirmada,
      firma_integridad: firmaIntegridad,
      llave_publica: llavePublica,
      url_redireccion: urlRedireccion,
      nombre_producto: fila.nombre ?? "",
    },
    200,
    cors,
  );
});
