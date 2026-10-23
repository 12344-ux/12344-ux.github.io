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
// FIRMA DE INTEGRIDAD C4 (documentación oficial Wompi, contenido resumido):
//   expiration-time es ISO8601 y, cuando se usa, la integridad concatena sin
//   separadores <Referencia><Monto><Moneda><ExpirationTime><Secreto>.
//   El servidor persiste y devuelve el mismo valor exacto que se firma.
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
    headers: {
      ...cors,
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
    },
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
  expirationTime?: string,
): Promise<string> {
  const cadena = `${referencia}${montoEnCentavos}${moneda}${
    expirationTime ?? ""
  }${secretoIntegridad}`;
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
const DROPI_BASE =
  (Deno.env.get("DROPI_API_BASE") ?? "https://api.dropi.co/integrations/")
    .replace(/\/*$/, "/");
const DROPI_UA = () =>
  (Deno.env.get("DROPI_USER_AGENT") ??
    "MAGANDHI-Impulse/1.0 (+https://magandhi.com)").trim();

type Obj = Record<string, unknown>;
const esObjeto = (v: unknown): v is Obj =>
  !!v && typeof v === "object" && !Array.isArray(v);
const FORMATO_CODIGO_ATRIBUCION = /^[0-9a-hjkmnp-tv-z]{16}$/;
const FORMATO_CAPACIDAD_REANUDACION = /^[A-Za-z0-9_-]{43}$/;
const FORMATO_UUID_AUTH =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

async function sha256Hex(valor: string): Promise<string> {
  const hash = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(valor),
  );
  return Array.from(new Uint8Array(hash))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

type AutenticacionOpcional = {
  uid: string | null;
  invalida: boolean;
};

async function autenticacionOpcional(
  req: Request,
  supabaseUrl: string,
  publicKey: string | null,
): Promise<AutenticacionOpcional> {
  const jwt = (req.headers.get("authorization") ?? "")
    .replace(/^Bearer\s+/i, "")
    .trim();
  const credencialPublica = (req.headers.get("apikey") ?? "").trim();
  if (
    !jwt || jwt === publicKey ||
    (credencialPublica && jwt === credencialPublica)
  ) {
    return { uid: null, invalida: false };
  }
  if (!publicKey) return { uid: null, invalida: true };
  const supabaseUsuario = createClient(supabaseUrl, publicKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const { data, error } = await supabaseUsuario.auth.getUser(jwt);
  const uid = data?.user?.id ?? "";
  if (error || !FORMATO_UUID_AUTH.test(uid)) {
    return { uid: null, invalida: true };
  }
  return { uid, invalida: false };
}

function codigoAtribucion(valor: unknown): string | null {
  if (typeof valor !== "string" || valor !== valor.trim()) return null;
  return FORMATO_CODIGO_ATRIBUCION.test(valor) ? valor : null;
}

function permiteFallbackP4(
  error: { code?: string; message?: string } | null,
): boolean {
  const codigo = String(error?.code ?? "");
  const mensaje = String(error?.message ?? "");
  return ["PGRST202", "PGRST204", "42883"].includes(codigo) ||
    /\bP4_[A-Z0-9_]+\b/.test(mensaje) ||
    /schema cache|failed to fetch|network|timeout|aborted/i.test(mensaje);
}

function registrarFallbackP4(
  operacion: "inmediata" | "carrito",
  error: { code?: string } | null,
): void {
  console.error(
    "[crear-intencion-pago] P4 degradó a registro histórico:",
    JSON.stringify({ operacion, code: error?.code ?? "SIN_CODIGO" }),
  );
}

const sumarStockBodegas = (filas: unknown): number | null =>
  Array.isArray(filas)
    ? filas.reduce(
      (s: number, w) => s + (esObjeto(w) ? Number(w.stock) || 0 : 0),
      0,
    )
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
    const v = variaciones.find((x) =>
      esObjeto(x) && String(x.id) === variacion
    );
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

async function leerDatosVerificacion(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  campanaId: string,
): Promise<{ datos: Obj | null; error: Obj | null }> {
  try {
    const { data, error } = await supabase.rpc("ds_verificacion_checkout", {
      p_campana_id: campanaId,
    });
    if (error) {
      return {
        datos: null,
        error: {
          motivo: "fallo ds_verificacion_checkout",
          codigo: error.code ?? null,
        },
      };
    }
    const datos = esObjeto(data) ? data : null;
    return {
      datos,
      error: datos ? null : { motivo: "sin datos de verificacion" },
    };
  } catch (_) {
    return { datos: null, error: { motivo: "fallo ds_verificacion_checkout" } };
  }
}

async function verificarProveedorEnVivo(
  datos: Obj | null,
  cantidad: number,
  maxCatalogo: number,
): Promise<{ rechazar: boolean; maxComprable: number; log: Obj }> {
  // La lectura interna se hace antes y fuera del helper. Así la ruta de carrito
  // puede agrupar por product_id y consultar Dropi una sola vez por producto.
  // Una RPC ausente o sin datos falla cerrada.
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
  const minutos = datos.minutos_desde_lectura == null
    ? null
    : Number(datos.minutos_desde_lectura);
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
      const r = await fetch(
        `${DROPI_BASE}products/v2/${encodeURIComponent(dropiId)}`,
        {
          method: "GET",
          headers: {
            "Content-Type": "application/json;charset=UTF-8",
            "dropi-integration-key": token,
            Accept: "application/json",
            "User-Agent": DROPI_UA(),
          },
          signal: ctrl.signal,
        },
      );
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
    log: {
      http,
      stock,
      reservadas,
      cantidad,
      remanente,
      piso,
      max_vivo: maxVivo,
      alcanza,
    },
  };
}

function pareceUuid(valor: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
    .test(valor);
}

function versionCarritoValida(valor: unknown): string | null {
  if (typeof valor === "number") {
    return Number.isSafeInteger(valor) && valor >= 0 ? String(valor) : null;
  }
  if (typeof valor !== "string" || !/^\d{1,18}$/.test(valor.trim())) {
    return null;
  }
  try {
    const version = BigInt(valor.trim());
    return version <= 9223372036854775807n ? version.toString() : null;
  } catch {
    return null;
  }
}

function compradorCarritoValido(valor: unknown): Obj | null {
  if (!esObjeto(valor)) return null;
  const limpiar = (campo: unknown) =>
    typeof campo === "string" ? campo.trim() : "";
  const nombre = limpiar(valor.nombre);
  const correo = limpiar(valor.correo).toLowerCase();
  const telefono = limpiar(valor.telefono);
  const direccion = limpiar(valor.direccion);
  const ciudad = limpiar(valor.ciudad);
  const departamento = limpiar(valor.departamento);
  const pais = limpiar(valor.pais).toUpperCase();
  if (
    nombre.length < 2 || nombre.length > 120 ||
    correo.length > 160 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(correo) ||
    !/^\d{10}$/.test(telefono) ||
    direccion.length < 3 || direccion.length > 220 ||
    ciudad.length < 2 || ciudad.length > 80 ||
    departamento.length < 1 || departamento.length > 80 || pais !== "CO"
  ) return null;
  return { nombre, correo, telefono, direccion, ciudad, departamento, pais };
}

function errorCarrito(
  mensaje: string,
  cors: Record<string, string>,
): Response | null {
  if (/PW_INTENCION_NO_REABRIBLE/.test(mensaje)) {
    return json(
      {
        error: "Esta compra ya existe. Revisa su estado en Mis compras.",
        codigo: "INTENCION_NO_REABRIBLE",
      },
      409,
      cors,
    );
  }
  if (/PW_CARRITO_YA_PROCESADO/.test(mensaje)) {
    return json(
      {
        error:
          "Esta versión del carrito ya fue procesada y no puede iniciar otro pago.",
        codigo: "CARRITO_YA_PROCESADO",
      },
      409,
      cors,
    );
  }

  if (/PW_VERSION_DESACTUALIZADA|CO_VERSION_DESACTUALIZADA/.test(mensaje)) {
    return json(
      {
        error: "El carrito cambió; actualízalo antes de pagar.",
        codigo: "VERSION_DESACTUALIZADA",
      },
      409,
      cors,
    );
  }

  const max = /(?:PW_|CO_)MAX_COMPRABLE:(\d{1,2})/.exec(mensaje);
  if (max) {
    const maxComprable = Math.max(0, Math.min(20, Number(max[1])));
    return json(
      {
        error:
          "La disponibilidad cambió; ajusta el carrito e intenta de nuevo.",
        codigo: "MAX_COMPRABLE",
        max_comprable: maxComprable,
      },
      409,
      cors,
    );
  }

  const monto = /PW_MONTO_MAXIMO(?::(\d{1,18}))?/.exec(mensaje);
  if (monto) {
    return json(
      {
        error: "El total del carrito supera el máximo permitido para un pago.",
        codigo: "MONTO_MAXIMO",
        max_monto_centavos: monto[1] ?? null,
      },
      409,
      cors,
    );
  }

  if (
    /PW_CARRITO_|PW_CUENTA_|PW_CAMPANA_NO_COMPRABLE|PW_MAX_LINEAS|PW_CANTIDAD_INVALIDA|CO_CARRITO_|CO_CAMPANA_|CO_MAX_LINEAS|CO_CUENTA_/
      .test(
        mensaje,
      )
  ) {
    return json(
      {
        error: "El carrito no está disponible para pago.",
        codigo: "CARRITO_NO_DISPONIBLE",
      },
      409,
      cors,
    );
  }
  return null;
}

async function responderDirectaC6(
  // deno-lint-ignore no-explicit-any
  supabase: any,
  snapshot: Obj,
  cors: Record<string, string>,
): Promise<Response> {
  const referencia = String(snapshot.referencia ?? "");
  const monto = String(snapshot.monto_centavos ?? "");
  const moneda = String(snapshot.moneda ?? "");
  const entorno = String(snapshot.entorno ?? "");
  const expiraEn = String(snapshot.expira_en ?? "");
  const campanaId = String(snapshot.campana_id ?? "");
  const cantidad = Number(snapshot.cantidad);
  const slug = typeof snapshot.slug === "string" ? snapshot.slug : "";
  const nombre = typeof snapshot.nombre === "string"
    ? snapshot.nombre
    : "Compra";
  const comprador = compradorCarritoValido(snapshot.comprador);
  const cuenta = typeof snapshot.auth_user_id === "string" &&
    FORMATO_UUID_AUTH.test(snapshot.auth_user_id);
  if (
    snapshot.tipo !== "directo" || snapshot.estado !== "creada" ||
    snapshot.tiene_transaccion !== false ||
    !/^[A-Za-z0-9_-]{6,64}$/.test(referencia) ||
    !/^(?!0)\d{1,18}$/.test(monto) || moneda !== "COP" ||
    !["sandbox", "prod"].includes(entorno) ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(expiraEn) ||
    !Number.isFinite(Date.parse(expiraEn)) ||
    Date.parse(expiraEn) <= Date.now() ||
    !pareceUuid(campanaId) || !Number.isSafeInteger(cantidad) ||
    cantidad < 1 || cantidad > 20 || !comprador
  ) {
    return json(
      {
        error: "No se pudo validar la intención de pago.",
        codigo: "ERROR_SERVIDOR",
      },
      500,
      cors,
    );
  }

  const { data: configFilas, error: errorConfig } = await supabase.rpc(
    "pagos_config_para_intencion",
  );
  const config = Array.isArray(configFilas) ? configFilas[0] : configFilas;
  const llavePublica = String(config?.llave_publica ?? "");
  const secreto = Deno.env.get(
    entorno === "prod" ? "WOMPI_INTEGRITY_PROD" : "WOMPI_INTEGRITY_SANDBOX",
  );
  if (
    errorConfig || !config || String(config.entorno ?? "") !== entorno ||
    !llavePublica || !secreto
  ) {
    return json(
      {
        error: "La configuración de pagos no está disponible.",
        codigo: "CONFIGURACION_PAGO",
      },
      500,
      cors,
    );
  }

  const destinoProducto = slug
    ? `slug=${encodeURIComponent(slug)}`
    : `id=${encodeURIComponent(campanaId)}`;
  const urlRedireccion = cuenta
    ? `https://magandhi.com/carrito/?ref=${
      encodeURIComponent(referencia)
    }&cuenta=compras`
    : `https://magandhi.com/producto/?${destinoProducto}&ref=${
      encodeURIComponent(referencia)
    }`;
  const firma = await calcularFirmaIntegridad(
    referencia,
    monto,
    moneda,
    secreto,
    expiraEn,
  );
  return json(
    {
      referencia,
      monto_en_centavos: monto,
      moneda,
      firma_integridad: firma,
      expira_en: expiraEn,
      llave_publica: llavePublica,
      url_redireccion: urlRedireccion,
      nombre_producto: nombre,
      comprador,
      checkout: {
        tipo: "compra",
        referencia,
        recargar: true,
        origen: "directo",
        gestion: cuenta ? "mis_compras" : "local",
      },
      recuperacion_cuenta: cuenta,
    },
    200,
    cors,
  );
}

async function procesarIntencion(
  req: Request,
  body: Record<string, unknown>,
  cors: Record<string, string>,
): Promise<Response> {
  const intencion = esObjeto(body.intencion) ? body.intencion : null;
  const referencia = typeof intencion?.referencia === "string"
    ? intencion.referencia.trim()
    : "";
  const capacidad = typeof intencion?.capacidad === "string"
    ? intencion.capacidad.trim()
    : "";
  if (
    !intencion || Object.keys(body).some((k) => k !== "intencion") ||
    Object.keys(intencion).some((k) =>
      !["referencia", "capacidad"].includes(k)
    ) ||
    !/^[A-Za-z0-9_-]{6,64}$/.test(referencia) ||
    (capacidad !== "" && !FORMATO_CAPACIDAD_REANUDACION.test(capacidad))
  ) {
    return json(
      {
        error: "La intención solicitada no es válida.",
        codigo: "INTENCION_INVALIDA",
      },
      400,
      cors,
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? req.headers.get("apikey");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !publicKey || !serviceRoleKey) {
    return json(
      {
        error: "Configuración del servidor incompleta.",
        codigo: "ERROR_SERVIDOR",
      },
      500,
      cors,
    );
  }

  const autenticacion = await autenticacionOpcional(
    req,
    supabaseUrl,
    publicKey,
  );
  if (autenticacion.invalida) {
    return json(
      { error: "Tu sesión no es válida.", codigo: "SESION_REQUERIDA" },
      401,
      cors,
    );
  }
  const authUserId = autenticacion.uid;
  if (!authUserId && !capacidad) {
    return json(
      {
        error:
          "Inicia sesión o vuelve desde el navegador donde empezaste la compra.",
        codigo: "SESION_REQUERIDA",
      },
      401,
      cors,
    );
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${serviceRoleKey}` } },
  });
  const capacidadHash = capacidad ? await sha256Hex(capacidad) : null;
  let { data: reaperturaBruta, error: errorReapertura } = await supabase.rpc(
    "mc_reabrir_intencion_c6",
    {
      p_referencia: referencia,
      p_auth_user_id: authUserId,
      p_capacidad_hash: capacidadHash,
    },
  );

  // Durante un despliegue Edge -> migración, C5 sigue reabriendo por su puerta
  // anterior. La compra directa invitada nunca degrada a posesión de referencia.
  if (
    errorReapertura && authUserId && !capacidad &&
    ["PGRST202", "42883"].includes(String(errorReapertura.code ?? ""))
  ) {
    const anterior = await supabase.rpc("mc_reabrir_intencion_c5", {
      p_referencia: referencia,
      p_auth_user_id: authUserId,
    });
    reaperturaBruta = anterior.data;
    errorReapertura = anterior.error;
  }

  if (errorReapertura) {
    const noReabrible = /MC_INTENCION_NO_(?:DISPONIBLE|REABRIBLE)/.test(
      errorReapertura.message ?? "",
    );
    return json(
      {
        error: noReabrible
          ? "Esta compra ya no se puede continuar; revisa su estado vigente."
          : "No se pudo continuar el pago.",
        codigo: noReabrible ? "INTENCION_NO_REABRIBLE" : "ERROR_SERVIDOR",
      },
      noReabrible ? 409 : 500,
      cors,
    );
  }
  const reapertura = esObjeto(reaperturaBruta) ? reaperturaBruta : null;

  const { data: configFilas, error: errorConfig } = await supabase.rpc(
    "pagos_config_para_intencion",
  );
  const config = Array.isArray(configFilas) ? configFilas[0] : configFilas;
  const entorno = String(reapertura?.entorno ?? "");
  const referenciaReapertura = String(reapertura?.referencia ?? "");
  const monto = String(reapertura?.monto_centavos ?? "");
  const moneda = String(reapertura?.moneda ?? "");
  const expiraEn = String(reapertura?.expira_en ?? "");
  const expiraMs = Date.parse(expiraEn);
  if (
    errorConfig || !config || String(config.entorno ?? "") !== entorno ||
    referenciaReapertura !== referencia ||
    !["sandbox", "prod"].includes(entorno) || !/^\d{1,18}$/.test(monto) ||
    monto === "0" || moneda !== "COP" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(expiraEn) ||
    !Number.isFinite(expiraMs) || expiraMs <= Date.now()
  ) {
    return json(
      {
        error: "No se pudo validar la intención de pago.",
        codigo: "ERROR_SERVIDOR",
      },
      500,
      cors,
    );
  }
  const llavePublica = String(config.llave_publica ?? "");
  const secreto = Deno.env.get(
    entorno === "prod" ? "WOMPI_INTEGRITY_PROD" : "WOMPI_INTEGRITY_SANDBOX",
  );
  if (!llavePublica || !secreto) {
    return json(
      {
        error: "La configuración de pagos no está disponible.",
        codigo: "CONFIGURACION_PAGO",
      },
      500,
      cors,
    );
  }

  const esDirecta = reapertura?.tipo === "directo";
  const gestion = reapertura?.gestion === "local" ? "local" : "mis_compras";
  const slug = typeof reapertura?.slug === "string" ? reapertura.slug : "";
  const destinoProducto = slug
    ? `slug=${encodeURIComponent(slug)}`
    : `id=${encodeURIComponent(String(reapertura?.campana_id ?? ""))}`;
  const urlRedireccion = esDirecta && gestion === "local"
    ? `https://magandhi.com/producto/?${destinoProducto}&ref=${
      encodeURIComponent(referencia)
    }`
    : `https://magandhi.com/carrito/?ref=${
      encodeURIComponent(referencia)
    }&cuenta=compras`;
  const firma = await calcularFirmaIntegridad(
    referencia,
    monto,
    moneda,
    secreto,
    expiraEn,
  );
  return json(
    {
      referencia,
      monto_en_centavos: monto,
      moneda,
      firma_integridad: firma,
      expira_en: expiraEn,
      llave_publica: llavePublica,
      url_redireccion: urlRedireccion,
      nombre_producto: typeof reapertura?.nombre_producto === "string"
        ? reapertura.nombre_producto
        : typeof reapertura?.nombre === "string"
        ? reapertura.nombre
        : "Compra",
      comprador: esObjeto(reapertura?.comprador) ? reapertura.comprador : {},
      checkout: {
        tipo: "compra",
        referencia,
        recargar: true,
        ...(esDirecta ? { origen: "directo", gestion } : {}),
      },
    },
    200,
    cors,
  );
}

async function procesarCarrito(
  req: Request,
  body: Record<string, unknown>,
  cors: Record<string, string>,
): Promise<Response> {
  const carrito = esObjeto(body.carrito) ? body.carrito : null;
  const idCarrito = typeof carrito?.id === "string" ? carrito.id.trim() : "";
  const versionEsperada = versionCarritoValida(carrito?.version);
  const clavesCarrito = carrito ? Object.keys(carrito) : [];
  const compradorCrudo = esObjeto(body.comprador) ? body.comprador : null;
  const compradorEntrada = compradorCarritoValido(compradorCrudo);
  const camposProhibidos = [
    "items",
    "precio",
    "precio_venta",
    "precio_unitario",
    "total",
    "monto",
    "monto_centavos",
    "monto_en_centavos",
    "amount_in_cents",
    "uid",
    "user_id",
    "auth_user_id",
    "cliente_id",
    "customer_id",
    "producto",
    "cantidad",
    "moneda",
    "atribucion_enlace_id",
  ];

  if (
    !carrito || !pareceUuid(idCarrito) || versionEsperada === null ||
    clavesCarrito.some((k) => !["id", "version"].includes(k)) ||
    camposProhibidos.some((k) =>
      Object.prototype.hasOwnProperty.call(body, k) ||
      (compradorCrudo !== null &&
        Object.prototype.hasOwnProperty.call(compradorCrudo, k))
    )
  ) {
    return json(
      {
        error: "La solicitud de carrito es inválida.",
        codigo: "CARRITO_INVALIDO",
      },
      400,
      cors,
    );
  }
  if (!compradorEntrada) {
    return json(
      {
        error: "Completa los datos del comprador con información válida.",
        codigo: "COMPRADOR_INVALIDO",
      },
      400,
      cors,
    );
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ??
    req.headers.get("apikey");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !publicKey || !serviceRoleKey) {
    return json(
      {
        error: "Configuracion del servidor incompleta (Supabase).",
        codigo: "ERROR_SERVIDOR",
      },
      500,
      cors,
    );
  }

  const jwt = (req.headers.get("authorization") ?? "")
    .replace(/^Bearer\s+/i, "")
    .trim();
  if (!jwt) {
    return json(
      {
        error: "Inicia sesión para pagar tu carrito.",
        codigo: "SESION_REQUERIDA",
      },
      401,
      cors,
    );
  }

  // La identidad se deriva con la llave pública y el JWT real del request.
  // Solo después se crea el cliente service_role que registra el snapshot.
  const supabaseUsuario = createClient(supabaseUrl, publicKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  });
  const { data: sesion, error: errorSesion } = await supabaseUsuario.auth
    .getUser(jwt);
  if (errorSesion || !sesion?.user) {
    return json(
      {
        error: "Tu sesión no es válida. Vuelve a iniciar sesión.",
        codigo: "SESION_REQUERIDA",
      },
      401,
      cors,
    );
  }

  const { data: snapshotBruto, error: errorSnapshot } = await supabaseUsuario
    .rpc(
      "co_carrito_listar",
    );
  if (errorSnapshot) {
    return errorCarrito(errorSnapshot.message ?? "", cors) ?? json(
      { error: "No se pudo validar el carrito.", codigo: "ERROR_SERVIDOR" },
      500,
      cors,
    );
  }
  const snapshot = esObjeto(snapshotBruto) ? snapshotBruto : null;
  if (!snapshot || String(snapshot.carrito_id ?? "") !== idCarrito) {
    return json(
      {
        error: "El carrito no está disponible para pago.",
        codigo: "CARRITO_NO_DISPONIBLE",
      },
      409,
      cors,
    );
  }
  if (String(snapshot.version ?? "") !== versionEsperada) {
    return json(
      {
        error: "El carrito cambió; actualízalo antes de pagar.",
        codigo: "VERSION_DESACTUALIZADA",
      },
      409,
      cors,
    );
  }

  const items = Array.isArray(snapshot.items) ? snapshot.items : [];
  if (items.length < 1 || items.length > 20) {
    return json(
      {
        error: "El carrito no está disponible para pago.",
        codigo: "CARRITO_NO_DISPONIBLE",
      },
      409,
      cors,
    );
  }

  const supabase = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { Authorization: `Bearer ${serviceRoleKey}` } },
  });

  // Valida primero cada línea pública. Las lecturas privadas se hacen de forma
  // secuencial y se agrupan por producto/proveedor; product_id nunca sale en la
  // respuesta al navegador.
  const grupos = new Map<string, {
    datos: Obj;
    proveedor: string;
    cantidad: number;
    campanas: string[];
  }>();

  for (const bruto of items) {
    const item = esObjeto(bruto) ? bruto : null;
    const campanaId = typeof item?.campana_id === "string"
      ? item.campana_id
      : "";
    const cantidad = Number(item?.cantidad);
    const maxComprable = Number(item?.max_comprable);
    if (
      !pareceUuid(campanaId) || !Number.isSafeInteger(cantidad) ||
      cantidad < 1 || cantidad > 20 ||
      !Number.isInteger(maxComprable) || maxComprable < 0 ||
      maxComprable > 20 ||
      item?.requiere_ajuste === true || cantidad > maxComprable
    ) {
      return json(
        {
          error:
            "La disponibilidad cambió; ajusta el carrito e intenta de nuevo.",
          codigo: "MAX_COMPRABLE",
          max_comprable: Number.isInteger(maxComprable)
            ? Math.max(0, Math.min(20, maxComprable))
            : 0,
        },
        409,
        cors,
      );
    }

    const lectura = await leerDatosVerificacion(supabase, campanaId);
    if (!lectura.datos) {
      console.error(
        "[crear-intencion-pago] Fallo lectura privada de proveedor:",
        JSON.stringify({ campana_id: campanaId, ...(lectura.error ?? {}) }),
      );
      return json(
        { error: "No se pudo validar el carrito.", codigo: "ERROR_SERVIDOR" },
        500,
        cors,
      );
    }

    const productId = typeof lectura.datos.product_id === "string"
      ? lectura.datos.product_id
      : "";
    if (!pareceUuid(productId)) {
      console.error(
        "[crear-intencion-pago] ds_verificacion_checkout sin product_id válido.",
      );
      return json(
        { error: "No se pudo validar el carrito.", codigo: "ERROR_SERVIDOR" },
        500,
        cors,
      );
    }

    const proveedor = JSON.stringify([
      lectura.datos.origen ?? null,
      lectura.datos.dropi_id ?? null,
      lectura.datos.variante ?? null,
    ]);
    const grupo = grupos.get(productId);
    if (grupo && grupo.proveedor !== proveedor) {
      console.error(
        "[crear-intencion-pago] Proveedor inconsistente para un mismo producto.",
      );
      return json(
        { error: "No se pudo validar el carrito.", codigo: "ERROR_SERVIDOR" },
        500,
        cors,
      );
    }
    if (grupo) {
      grupo.cantidad += cantidad;
      grupo.campanas.push(campanaId);
    } else {
      grupos.set(productId, {
        datos: lectura.datos,
        proveedor,
        cantidad,
        campanas: [campanaId],
      });
    }
  }

  // Una única consulta viva por grupo, también secuencial para evitar ráfagas a
  // Dropi. El techo de catálogo agregado sale de la disponibilidad del producto;
  // los máximos particulares de cada campaña ya se validaron arriba.
  for (const grupo of grupos.values()) {
    const disponibleLocal = Number(grupo.datos.disponible_local);
    const maxGrupo = Number.isFinite(disponibleLocal)
      ? Math.max(0, Math.min(20, Math.floor(disponibleLocal)))
      : 0;
    const verificacion = await verificarProveedorEnVivo(
      grupo.datos,
      grupo.cantidad,
      maxGrupo,
    );
    if (verificacion.rechazar) {
      console.log(
        "[crear-intencion-pago] grupo de proveedor rechazado en vivo:",
        JSON.stringify({ campanas: grupo.campanas, ...verificacion.log }),
      );
      return json(
        {
          error:
            "La disponibilidad cambió; ajusta el carrito e intenta de nuevo.",
          codigo: "MAX_COMPRABLE",
          max_comprable: verificacion.maxComprable,
        },
        409,
        cors,
      );
    }
  }

  const { data: configFilas, error: errorConfig } = await supabase.rpc(
    "pagos_config_para_intencion",
  );
  const config = Array.isArray(configFilas) ? configFilas[0] : configFilas;
  if (errorConfig || !config) {
    console.error(
      "[crear-intencion-pago] Fallo configuración de carrito:",
      JSON.stringify({ code: errorConfig?.code ?? null }),
    );
    return json(
      {
        error: "No se pudo leer la configuracion de pagos.",
        codigo: "CONFIGURACION_PAGO",
      },
      500,
      cors,
    );
  }

  const entornoConfig = String(config.entorno ?? "");
  if (!["sandbox", "prod"].includes(entornoConfig)) {
    console.error(
      "[crear-intencion-pago] Entorno de pagos inválido para carrito.",
    );
    return json(
      {
        error: "La configuracion de pagos no es válida.",
        codigo: "CONFIGURACION_PAGO",
      },
      500,
      cors,
    );
  }
  const entorno = entornoConfig;
  const llavePublica = String(config.llave_publica ?? "");
  if (!llavePublica) {
    return json(
      {
        error: "Llave publica no configurada para pagos.",
        codigo: "CONFIGURACION_PAGO",
      },
      500,
      cors,
    );
  }
  const nombreSecreto = entorno === "prod"
    ? "WOMPI_INTEGRITY_PROD"
    : "WOMPI_INTEGRITY_SANDBOX";
  const secretoIntegridad = Deno.env.get(nombreSecreto);
  if (!secretoIntegridad) {
    console.error(
      "[crear-intencion-pago] Secreto de integridad ausente para carrito:",
      nombreSecreto,
    );
    return json(
      {
        error: "Secreto de integridad no configurado en el servidor.",
        codigo: "CONFIGURACION_PAGO",
      },
      500,
      cors,
    );
  }

  const texto = (v: unknown, max: number) =>
    typeof v === "string" && v.trim() !== "" ? v.trim().slice(0, max) : null;
  const comprador = compradorEntrada;
  const utmBruto = texto(body.utm_campaign, 60);
  const utm = utmBruto && /^[a-z0-9-]{1,60}$/.test(utmBruto) ? utmBruto : null;
  const vidBruto = texto(body.mg_vid, 40);
  const mgVid = vidBruto && /^[A-Za-z0-9_-]{16,40}$/.test(vidBruto)
    ? vidBruto
    : null;
  const atribucionCodigo = codigoAtribucion(body.atribucion_codigo);
  const referencia = generarReferencia(idCarrito);

  let intencionBruta: unknown = null;
  let errorIntencion: { message?: string; code?: string } | null = null;
  let versionRegistro = versionEsperada;
  for (let intento = 0; intento < 2; intento += 1) {
    const argumentosBase = {
      p_referencia: referencia,
      p_auth_user_id: sesion.user.id,
      p_carrito_id: idCarrito,
      p_version_esperada: versionRegistro,
      p_entorno: entorno,
      p_comprador: comprador,
      p_utm_campaign: utm,
      p_mg_vid: mgVid,
      p_moneda: "COP",
    };
    let respuesta = await supabase.rpc(
      "pw_registrar_intencion_carrito_p4",
      { ...argumentosBase, p_atribucion_codigo: atribucionCodigo },
    );
    if (respuesta.error && permiteFallbackP4(respuesta.error)) {
      // Despliegue compatible y falla abierta: misma referencia/versión contra
      // la puerta C5 histórica. Nunca se crea una segunda intención por P4.
      registrarFallbackP4("carrito", respuesta.error);
      respuesta = await supabase.rpc(
        "pw_registrar_intencion_carrito",
        argumentosBase,
      );
    }
    errorIntencion = respuesta.error;
    if (errorIntencion) break;

    const resultado = esObjeto(respuesta.data) ? respuesta.data : null;
    const siguiente = versionCarritoValida(resultado?.reintentar_version);
    if (siguiente !== null && intento === 0) {
      versionRegistro = siguiente;
      continue;
    }
    intencionBruta = respuesta.data;
    break;
  }
  if (errorIntencion) {
    const publico = errorCarrito(errorIntencion.message ?? "", cors);
    if (publico) return publico;
    console.error(
      "[crear-intencion-pago] No se pudo congelar el carrito:",
      JSON.stringify({ code: errorIntencion.code ?? null }),
    );
    return json(
      {
        error: "No se pudo iniciar el pago. Intenta de nuevo.",
        codigo: "ERROR_SERVIDOR",
      },
      500,
      cors,
    );
  }

  const intencion = esObjeto(intencionBruta) ? intencionBruta : null;
  const referenciaFirmada = String(intencion?.referencia ?? "");
  const entornoFirmado = String(intencion?.entorno ?? "");
  const montoFirmado = String(intencion?.monto_centavos ?? "");
  const monedaFirmada = String(intencion?.moneda ?? "");
  const carritoIdFirmado = String(intencion?.carrito_id ?? "");
  const carritoVersionFuente = versionCarritoValida(
    intencion?.carrito_version_fuente,
  );
  const carritoVersionSucesora = versionCarritoValida(
    intencion?.carrito_version_sucesora,
  );
  const carritoVersionHistorica = versionCarritoValida(
    intencion?.carrito_version,
  );
  const carritoVersionHistoricaNumero = Number(carritoVersionHistorica);
  const contratoC5 = carritoVersionFuente !== null &&
    carritoVersionSucesora !== null &&
    intencion?.estado === "creada" &&
    carritoVersionFuente === versionRegistro &&
    BigInt(carritoVersionSucesora) === BigInt(carritoVersionFuente) + 1n;
  const contratoC4 = carritoVersionHistorica !== null &&
    carritoVersionHistorica === versionRegistro &&
    Number.isSafeInteger(carritoVersionHistoricaNumero) &&
    carritoVersionHistoricaNumero >= 0;
  const expiraEn = String(intencion?.expira_en ?? "");
  const expiraEnMs = Date.parse(expiraEn);
  const lineas = Array.isArray(intencion?.items) ? intencion.items : [];
  if (
    !/^[A-Za-z0-9_-]{6,64}$/.test(referenciaFirmada) ||
    !/^\d{1,18}$/.test(montoFirmado) || montoFirmado === "0" ||
    monedaFirmada !== "COP" || carritoIdFirmado !== idCarrito ||
    (!contratoC5 && !contratoC4) ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(expiraEn) ||
    !Number.isFinite(expiraEnMs) || expiraEnMs <= Date.now() || !lineas.length
  ) {
    console.error(
      "[crear-intencion-pago] Snapshot autoritativo de carrito inconsistente.",
    );
    return json(
      {
        error: "No se pudo confirmar el monto del pago.",
        codigo: "ERROR_SERVIDOR",
      },
      500,
      cors,
    );
  }
  if (entornoFirmado !== entorno) {
    console.error(
      "[crear-intencion-pago] La intención congelada pertenece a otro entorno de pagos.",
    );
    return json(
      {
        error: "La configuracion de pagos cambió; intenta más tarde.",
        codigo: "CONFIGURACION_PAGO",
      },
      500,
      cors,
    );
  }

  const firmaIntegridad = await calcularFirmaIntegridad(
    referenciaFirmada,
    montoFirmado,
    monedaFirmada,
    secretoIntegridad,
    expiraEn,
  );
  const resumenItems = lineas.map((bruto) => {
    const item = esObjeto(bruto) ? bruto : {};
    return {
      ordinal: item.ordinal ?? null,
      campana_id: item.campana_id ?? null,
      slug: item.slug ?? null,
      nombre: item.nombre ?? null,
      cantidad: item.cantidad ?? null,
      precio_unitario: item.precio_unitario == null
        ? null
        : String(item.precio_unitario),
      subtotal: item.subtotal == null ? null : String(item.subtotal),
    };
  });
  const cantidadLineas = Number(intencion?.cantidad_lineas ?? lineas.length);
  const nombreProducto = cantidadLineas === 1
    ? String((esObjeto(lineas[0]) ? lineas[0].nombre : "") ?? "")
    : `${cantidadLineas} productos`;

  return json(
    {
      referencia: referenciaFirmada,
      monto_en_centavos: montoFirmado,
      moneda: monedaFirmada,
      firma_integridad: firmaIntegridad,
      expira_en: expiraEn,
      llave_publica: llavePublica,
      url_redireccion: contratoC5
        ? `https://magandhi.com/carrito/?ref=${
          encodeURIComponent(referenciaFirmada)
        }&cuenta=compras`
        : `https://magandhi.com/carrito/?ref=${
          encodeURIComponent(referenciaFirmada)
        }`,
      nombre_producto: nombreProducto,
      checkout: contratoC5
        ? { tipo: "compra", referencia: referenciaFirmada, recargar: true }
        : {
          tipo: "carrito",
          id: carritoIdFirmado,
          version: carritoVersionHistoricaNumero,
          recargar: true,
        },
      carrito: contratoC5
        ? {
          id: carritoIdFirmado,
          version_fuente: carritoVersionFuente,
          version_sucesora: carritoVersionSucesora,
        }
        : undefined,
      resumen: {
        cantidad_lineas: intencion?.cantidad_lineas ?? lineas.length,
        cantidad_unidades: intencion?.cantidad_unidades ?? null,
        items: resumenItems,
      },
    },
    200,
    cors,
  );
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

  // C5 agrega una ruta inequívoca para volver a firmar una intención propia
  // vigente. Nunca crea otra intención ni cae a compra inmediata.
  if (Object.prototype.hasOwnProperty.call(body, "intencion")) {
    return await procesarIntencion(req, body, cors);
  }

  // C3/C5 conservan una ruta inequívoca de carrito sin tocar el contrato
  // escalar histórico.
  if (Object.prototype.hasOwnProperty.call(body, "carrito")) {
    return await procesarCarrito(req, body, cors);
  }

  if (Object.prototype.hasOwnProperty.call(body, "atribucion_enlace_id")) {
    return json(
      { error: "La solicitud contiene un campo de atribución no permitido." },
      400,
      cors,
    );
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
  // Procedencia descriptiva/legacy: utm_campaign se conserva para compatibilidad
  // de Email, pero nunca es autoridad exacta P4. mg_vid es el id ALEATORIO de
  // analítica propia y solo existe con consentimiento.
  const utmBruto = texto(body?.utm_campaign, 60);
  const utm = utmBruto && /^[a-z0-9-]{1,60}$/.test(utmBruto) ? utmBruto : null;
  const vidBruto = texto(body?.mg_vid, 40);
  const mgVid = vidBruto && /^[A-Za-z0-9_-]{16,40}$/.test(vidBruto)
    ? vidBruto
    : null;
  const atribucionCodigo = codigoAtribucion(body?.atribucion_codigo);
  const capacidadReanudacion = typeof body?.reanudacion === "string"
    ? body.reanudacion.trim()
    : "";
  if (
    Object.prototype.hasOwnProperty.call(body, "reanudacion") &&
    !FORMATO_CAPACIDAD_REANUDACION.test(capacidadReanudacion)
  ) {
    return json(
      {
        error: "La recuperación del pago no es válida.",
        codigo: "REANUDACION_INVALIDA",
      },
      400,
      cors,
    );
  }

  // DIAGNOSTICO: marca de entrada para correlacionar la invocacion en los logs.
  // Solo datos no sensibles (que producto se pidio y cuantas unidades).
  console.log(
    "[crear-intencion-pago] Intencion solicitada:",
    JSON.stringify({ producto, cantidad }),
  );

  // --- Cliente Supabase server-side (SERVICE_ROLE, inyectada por el runtime) -
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const publicKey = Deno.env.get("SUPABASE_ANON_KEY") ??
    Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? req.headers.get("apikey");
  if (!supabaseUrl || !serviceRoleKey || (capacidadReanudacion && !publicKey)) {
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
  const autenticacion = capacidadReanudacion
    ? await autenticacionOpcional(req, supabaseUrl, publicKey)
    : { uid: null, invalida: false };
  if (autenticacion.invalida) {
    return json(
      { error: "Tu sesión no es válida.", codigo: "SESION_REQUERIDA" },
      401,
      cors,
    );
  }
  const authUserId = autenticacion.uid;
  const capacidadHash = capacidadReanudacion
    ? await sha256Hex(capacidadReanudacion)
    : null;

  // La idempotencia se resuelve antes de catálogo, precio, Dropi o configuración
  // mutable. Si la primera respuesta se perdió, se vuelve a firmar el snapshot
  // ya persistido aunque la campaña haya cambiado después.
  if (capacidadHash) {
    const recuperada = await supabase.rpc("pw_recuperar_registro_directa_c6", {
      p_capacidad_hash: capacidadHash,
      p_auth_user_id: authUserId,
    });
    if (recuperada.error) {
      const codigo = String(recuperada.error.code ?? "");
      const mensaje = String(recuperada.error.message ?? "");
      if (["PGRST202", "42883"].includes(codigo)) {
        return json(
          {
            error: "La recuperación de pagos todavía no está disponible.",
            codigo: "RECUPERACION_NO_DISPONIBLE",
          },
          503,
          cors,
        );
      }
      if (/PW_DIRECTA_C6_(?:NO_REABRIBLE|NO_DISPONIBLE)/.test(mensaje)) {
        return json(
          {
            error: "Este intento ya no se puede continuar.",
            codigo: "INTENCION_NO_REABRIBLE",
          },
          409,
          cors,
        );
      }
      if (/PW_CUENTA_NO_DISPONIBLE/.test(mensaje)) {
        return json(
          {
            error: "Tu cuenta no está disponible.",
            codigo: "CUENTA_NO_DISPONIBLE",
          },
          409,
          cors,
        );
      }
      console.error(
        "[crear-intencion-pago] No se pudo resolver la idempotencia C6:",
        JSON.stringify({ code: codigo }),
      );
      return json(
        {
          error: "No se pudo recuperar el intento de pago.",
          codigo: "ERROR_SERVIDOR",
        },
        500,
        cors,
      );
    }
    const snapshotRecuperado = esObjeto(recuperada.data)
      ? recuperada.data
      : null;
    if (snapshotRecuperado) {
      const mismoProducto =
        String(snapshotRecuperado.campana_id ?? "") === producto ||
        String(snapshotRecuperado.slug ?? "") === producto;
      if (!mismoProducto || Number(snapshotRecuperado.cantidad) !== cantidad) {
        return json(
          {
            error: "La recuperación no corresponde a esta compra.",
            codigo: "REANUDACION_INVALIDA",
          },
          409,
          cors,
        );
      }
      return await responderDirectaC6(supabase, snapshotRecuperado, cors);
    }
  }

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
        details: (errorCatalogo as { details?: string } | null)?.details ??
          null,
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
  if (
    !Number.isInteger(maxComprable) || maxComprable < 0 || maxComprable > 20
  ) {
    console.error(
      "[crear-intencion-pago] max_comprable invalido:",
      JSON.stringify({
        campana_id: fila.id ?? null,
        max_comprable: fila.max_comprable ?? null,
      }),
    );
    return json({ error: "No se pudo validar la disponibilidad." }, 500, cors);
  }
  if (cantidad > maxComprable) {
    return json(
      {
        error:
          "La cantidad solicitada supera el máximo disponible para este pedido.",
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
  const lecturaProveedor = await leerDatosVerificacion(
    supabase,
    String(fila.id),
  );
  const verificacion = await verificarProveedorEnVivo(
    lecturaProveedor.datos,
    cantidad,
    maxComprable,
  );
  if (verificacion.rechazar) {
    console.log(
      "[crear-intencion-pago] proveedor rechazado en vivo:",
      JSON.stringify({
        ...(lecturaProveedor.error ?? {}),
        ...verificacion.log,
      }),
    );
    return json(
      {
        error:
          "La disponibilidad cambió; ajusta la cantidad e intenta de nuevo.",
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
        error: `Llave publica no configurada para el entorno '${entorno}'. ` +
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
  const argumentosIntencion = {
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
  };
  let respuestaIntencion;
  if (capacidadReanudacion) {
    respuestaIntencion = await supabase.rpc(
      "pw_registrar_intencion_directa_c6",
      {
        ...argumentosIntencion,
        p_atribucion_codigo: atribucionCodigo,
        p_auth_user_id: authUserId,
        p_capacidad_hash: capacidadHash,
      },
    );
    if (
      respuestaIntencion.error &&
      ["PGRST202", "42883"].includes(
        String(respuestaIntencion.error.code ?? ""),
      )
    ) {
      return json(
        {
          error: "La recuperación de pagos todavía no está disponible.",
          codigo: "RECUPERACION_NO_DISPONIBLE",
        },
        503,
        cors,
      );
    }
  } else {
    respuestaIntencion = await supabase.rpc(
      "pw_registrar_intencion_p4",
      { ...argumentosIntencion, p_atribucion_codigo: atribucionCodigo },
    );
    if (
      respuestaIntencion.error && permiteFallbackP4(respuestaIntencion.error)
    ) {
      // La puerta histórica conserva ventas durante despliegues parciales o una
      // falla P4. Reutiliza exactamente la misma referencia para ser idempotente.
      registrarFallbackP4("inmediata", respuestaIntencion.error);
      respuestaIntencion = await supabase.rpc(
        "pw_registrar_intencion",
        argumentosIntencion,
      );
    }
  }
  const { data: intencion, error: errorIntencion } = respuestaIntencion;
  if (errorIntencion) {
    // Una baja entre la lectura pública y el lock autoritativo se informa con el
    // mismo contrato público 409, sin filtrar detalles internos.
    const maxEnError = /PW_MAX_COMPRABLE:(\d{1,2})/.exec(
      errorIntencion.message ?? "",
    );
    if (maxEnError) {
      const maxActual = Math.max(0, Math.min(20, Number(maxEnError[1])));
      return json(
        {
          error:
            "La disponibilidad cambió; ajusta la cantidad e intenta de nuevo.",
          codigo: "MAX_COMPRABLE",
          max_comprable: maxActual,
        },
        409,
        cors,
      );
    }
    if (/PW_DIRECTA_C6_ACTIVA/.test(errorIntencion.message ?? "")) {
      return json(
        {
          error:
            "Ya tienes un pago de este producto en proceso. Revísalo en Mis compras.",
          codigo: "COMPRA_DIRECTA_EN_PROCESO",
        },
        409,
        cors,
      );
    }
    if (
      /PW_DIRECTA_C6_(?:NO_REABRIBLE|CAPACIDAD_REUTILIZADA)/.test(
        errorIntencion.message ?? "",
      )
    ) {
      return json(
        {
          error:
            "Este intento ya no se puede volver a abrir. Consulta su estado o inicia uno nuevo cuando termine.",
          codigo: "INTENCION_NO_REABRIBLE",
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
  const esDirectaC6 = intencionRegistrada?.tipo === "directo";
  const campanaFirmada = String(intencionRegistrada?.campana_id ?? "");
  const cantidadFirmada = Number(intencionRegistrada?.cantidad);
  const referenciaFirmada = esDirectaC6
    ? String(intencionRegistrada?.referencia ?? "")
    : referencia;
  const expiraEn = esDirectaC6
    ? String(intencionRegistrada?.expira_en ?? "")
    : "";
  const expiraMs = expiraEn ? Date.parse(expiraEn) : NaN;
  if (
    !/^(?!0)\d{1,18}$/.test(montoFirmado) ||
    (!esDirectaC6 && montoFirmado !== montoEnCentavos) ||
    monedaFirmada !== moneda ||
    !/^[A-Za-z0-9_-]{6,64}$/.test(referenciaFirmada) ||
    (!esDirectaC6 && referenciaFirmada !== referencia) ||
    (esDirectaC6 && (
      campanaFirmada !== String(fila.id ?? "") ||
      cantidadFirmada !== cantidad ||
      intencionRegistrada?.estado !== "creada" ||
      intencionRegistrada?.tiene_transaccion !== false ||
      !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(expiraEn) ||
      !Number.isFinite(expiraMs) || expiraMs <= Date.now()
    ))
  ) {
    console.error(
      "[crear-intencion-pago] Snapshot autoritativo inconsistente.",
    );
    return json(
      { error: "No se pudo confirmar el monto del pago." },
      500,
      cors,
    );
  }

  // C6 firma también el vencimiento exacto. Las respuestas históricas durante
  // una ventana de despliegue conservan la firma anterior sin expiration-time.
  const firmaIntegridad = await calcularFirmaIntegridad(
    referenciaFirmada,
    montoFirmado,
    monedaFirmada,
    secretoIntegridad,
    esDirectaC6 ? expiraEn : undefined,
  );

  const slugRetorno =
    esDirectaC6 && typeof intencionRegistrada?.slug === "string"
      ? intencionRegistrada.slug
      : String(fila.slug ?? "");
  const destinoProducto = slugRetorno
    ? `slug=${encodeURIComponent(slugRetorno)}`
    : `id=${encodeURIComponent(campanaFirmada || String(fila.id ?? ""))}`;
  const urlRedireccion = esDirectaC6 && authUserId
    ? `https://magandhi.com/carrito/?ref=${
      encodeURIComponent(referenciaFirmada)
    }&cuenta=compras`
    : `https://magandhi.com/producto/?${destinoProducto}&ref=${
      encodeURIComponent(referenciaFirmada)
    }`;

  // Respuesta pública: la capacidad nunca vuelve desde servidor. El navegador
  // conserva la que generó; la BD solo recibió su hash.
  return json(
    {
      referencia: referenciaFirmada,
      monto_en_centavos: montoFirmado,
      moneda: monedaFirmada,
      firma_integridad: firmaIntegridad,
      ...(esDirectaC6 ? { expira_en: expiraEn } : {}),
      llave_publica: llavePublica,
      url_redireccion: urlRedireccion,
      nombre_producto:
        esDirectaC6 && typeof intencionRegistrada?.nombre === "string"
          ? intencionRegistrada.nombre
          : fila.nombre ?? "",
      ...(esDirectaC6
        ? {
          checkout: {
            tipo: "compra",
            referencia: referenciaFirmada,
            recargar: true,
            origen: "directo",
            gestion: authUserId ? "mis_compras" : "local",
          },
          recuperacion_cuenta: !!authUserId,
          comprador: esObjeto(intencionRegistrada?.comprador)
            ? intencionRegistrada.comprador
            : {},
        }
        : {}),
    },
    200,
    cors,
  );
});
