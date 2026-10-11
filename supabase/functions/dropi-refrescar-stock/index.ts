// MAGANDHI · Edge Function · dropi-refrescar-stock (Dropshipping · D2c.1)
// ----------------------------------------------------------------------------
// El RELOJ del stock de proveedor. La invoca pg_cron a traves de pg_net cada
// minuto; no la llama ningun navegador.
//
// QUE HACE, en una vuelta:
//   1. ds_productos_por_refrescar() -> los N productos con el intento mas viejo
//   2. por cada uno: GET products/v2/{id} en Dropi (1 peticion)
//   3. ds_registrar_lectura_stock() -> guarda el stock o el error
//
// SOLO LECTURA contra Dropi. Nunca toca orders/, no crea pedidos ni reservas,
// no descarga imagenes y no envia ningun dato de cliente.
//
// POR QUE RODANTE Y NO UN LOTE
// MEDIDO el 10-oct-2026: Dropi responde 429 alrededor de la peticion 12-16 en
// rafaga. Refrescar un producto cuesta 1 peticion. Una tanda de 3 por minuto
// jamas se acerca al techo, y aun asi un catalogo de 15 productos queda
// completo cada 5 minutos: mas fresco que un lote cada 15. Y si Dropi devuelve
// 429, la vuelta se ABORTA en el acto en vez de insistir con los que faltan.
//
// AUTENTICACION (distinta a dropi-sonda, y a proposito)
// pg_net no trae sesion de usuario, asi que Verify JWT va APAGADO y la puerta
// es un secreto propio: DROPI_REFRESCO_SECRETO, en la cabecera
// x-refresco-secreto. Es de MINIMO PRIVILEGIO: su unico poder es pedir un
// refresco de stock. NO es la service_role, que nunca sale de aqui.
//
// Y si ese secreto se filtrara, el daño esta acotado por diseño: el AUTO-FRENO
// vive en la base (refresco_minimo_segundos), asi que mil invocaciones
// devuelven cero trabajo y cuestan cero peticiones a Dropi. No se puede leer
// nada, ni escribir nada, ni gastar nuestro presupuesto externo.
//
// LINEA ROJA: DROPI_TOKEN y SUPABASE_SERVICE_ROLE_KEY solo viven en el runtime.
// Nunca se devuelven ni se loguean.
// Diseño: docs/dropshipping-envios/DROPI.md §9 y PLANO.md §4.
// ============================================================================

const BASE = (Deno.env.get("DROPI_API_BASE") ?? "https://api.dropi.co/integrations/").replace(/\/*$/, "/");
const ESPERA_MS = 15000;
// Pausa entre productos: convierte una rafaga en un goteo. Con 3 productos son
// ~1,2 s de vuelta, irrelevante para un cron de un minuto.
const PAUSA_MS = Number(Deno.env.get("DROPI_PAUSA_MS") ?? "600");

const ua = () => (Deno.env.get("DROPI_USER_AGENT") ?? "MAGANDHI-Impulse/1.0 (+https://magandhi.com)").trim();

type Obj = Record<string, unknown>;
const esObj = (v: unknown): v is Obj => !!v && typeof v === "object" && !Array.isArray(v);
const dormir = (ms: number) => new Promise((r) => setTimeout(r, ms));

const json = (b: unknown, s: number) =>
  new Response(JSON.stringify(b, null, 2), {
    status: s,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });

// Comparacion de secretos en tiempo constante: no filtra por cuanto tarda en
// fallar. Es barato y evita una clase entera de fuga.
function igualSeguro(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

// Suma de stock por bodega, igual que el plugin oficial y que dropi-sonda.
const sumarStock = (filas: unknown) =>
  Array.isArray(filas)
    ? filas.reduce((s: number, w) => s + (esObj(w) ? Number(w.stock) || 0 : 0), 0)
    : null;

function stockVariacion(v: Obj): number | null {
  if (typeof v.stock === "number") return v.stock;
  if (Array.isArray(v.warehouse_product_variation)) return sumarStock(v.warehouse_product_variation);
  return null;
}

// El stock que de verdad importa para ESTE registro.
//
// Clave: `producto_proveedor` guarda `variacion_externa_id` porque D2a crea un
// producto MAGANDHI por VARIANTE de Dropi. Si hay variante, el stock sale de
// ESA variante, no del producto entero; usar el total vendería humo de una
// talla agotada porque otra tiene unidades.
//
// Si la variante ya no esta en la ficha, se devuelve 0 (no un error): una
// variante que desaparecio del catalogo es exactamente «no hay», y registrar 0
// saca el producto de la vitrina de inmediato en vez de esperar a que la
// fotografia vieja venza.
function stockDeLaFicha(p: Obj, variacionId: string): { stock: number | null; nota: string | null } {
  const variaciones = Array.isArray(p.variations) ? p.variations : [];

  if (variacionId) {
    const v = variaciones.find((x) => esObj(x) && String(x.id) === variacionId);
    if (!esObj(v)) return { stock: 0, nota: "la variante ya no está en la ficha de Dropi" };
    return { stock: stockVariacion(v) ?? 0, nota: null };
  }

  // Producto VARIABLE sin variante fijada: el stock es la suma de sus variantes
  // (`warehouse_product` suele venir vacio y daria un falso «sin stock»).
  if (String(p.type ?? "").toUpperCase() === "VARIABLE" && variaciones.length) {
    return {
      stock: variaciones.reduce((s: number, v) => s + (esObj(v) ? (stockVariacion(v) ?? 0) : 0), 0),
      nota: null,
    };
  }

  if (typeof p.stock === "number") return { stock: p.stock, nota: null };
  return { stock: sumarStock(p.warehouse_product), nota: null };
}

async function leerFicha(id: string, token: string) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ESPERA_MS);
  try {
    const r = await fetch(`${BASE}products/v2/${encodeURIComponent(id)}`, {
      method: "GET",
      headers: {
        "Content-Type": "application/json;charset=UTF-8",
        "dropi-integration-key": token,
        Accept: "application/json",
        "User-Agent": ua(),
      },
      signal: ctrl.signal,
    });
    const texto = await r.text();
    let j: unknown = null;
    try { j = JSON.parse(texto); } catch { /* no era JSON */ }
    return { http: r.status, j: esObj(j) ? j : null };
  } catch (e) {
    const abortado = (e as Error)?.name === "AbortError";
    return { http: 0, j: null, fallo: abortado ? "Dropi no respondió a tiempo" : "No se pudo conectar con Dropi" };
  } finally {
    clearTimeout(t);
  }
}

// Toda escritura pasa por RPC `security definer` que solo service_role puede
// ejecutar: el mismo patron de F2. La funcion no hace UPDATE directo a tablas.
async function rpc(nombre: string, cuerpo: Obj) {
  const url = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/+$/, "");
  const llave = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const r = await fetch(`${url}/rest/v1/rpc/${nombre}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      // Leccion de Wompi F1: la llave va en apikey Y en Authorization, o
      // PostgREST degrada el rol a anon y la RPC responde 403.
      "apikey": llave,
      "Authorization": `Bearer ${llave}`,
      Accept: "application/json",
    },
    body: JSON.stringify(cuerpo),
  });
  const texto = await r.text();
  let j: unknown = null;
  try { j = JSON.parse(texto); } catch { /* vacio o texto */ }
  return { ok: r.ok, http: r.status, j, crudo: texto.slice(0, 200) };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Usa POST." }, 405);

  // --- (1) La puerta: el secreto propio -------------------------------------
  // Se valida ANTES de cualquier otra cosa. Nada se lee ni se escribe hasta
  // aqui, asi que una llamada sin secreto no cuesta nada.
  const esperado = (Deno.env.get("DROPI_REFRESCO_SECRETO") ?? "").trim();
  if (!esperado) {
    return json({ error: "Falta el secreto DROPI_REFRESCO_SECRETO en Edge Functions." }, 500);
  }
  const recibido = (req.headers.get("x-refresco-secreto") ?? "").trim();
  if (!recibido || !igualSeguro(recibido, esperado)) {
    // Mensaje deliberadamente mudo: no se confirma si el secreto existe,
    // ni su longitud, ni nada que ayude a adivinarlo.
    return json({ error: "No autorizado." }, 401);
  }

  const token = (Deno.env.get("DROPI_TOKEN") ?? "").trim();
  if (!token) return json({ error: "Falta el secreto DROPI_TOKEN." }, 500);

  // --- (2) La cola, que ademas trae el auto-freno ---------------------------
  const cola = await rpc("ds_productos_por_refrescar", {});
  if (!cola.ok) {
    console.log("[dropi-refrescar-stock] cola falló", JSON.stringify({ http: cola.http }));
    return json({ error: "No se pudo leer la cola de refresco.", http: cola.http }, 500);
  }
  const pendientes = Array.isArray(cola.j) ? cola.j as Obj[] : [];
  if (pendientes.length === 0) {
    // Caso normal y sano: o no hay productos de proveedor, o el auto-freno
    // dijo «todavía no». No es un error.
    return json({ refrescados: 0, fallidos: 0, nota: "nada por refrescar en esta vuelta" }, 200);
  }

  // --- (3) Una peticion por producto, a goteo -------------------------------
  const detalle: Obj[] = [];
  let refrescados = 0, fallidos = 0, frenado = false;

  for (let i = 0; i < pendientes.length; i++) {
    const fila = pendientes[i];
    const productId = String(fila.product_id ?? "");
    const dropiId = String(fila.producto_externo_id ?? "");
    const variacion = String(fila.variacion_externa_id ?? "");
    if (!productId || !/^\d{1,12}$/.test(dropiId)) {
      detalle.push({ product_id: productId || null, resultado: "registro inválido, se omite" });
      continue;
    }

    if (i > 0) await dormir(PAUSA_MS);

    const r = await leerFicha(dropiId, token);

    // 429: Dropi nos frenó. Se ABORTA la vuelta entera. Insistir con los que
    // faltan solo alarga el castigo y no refresca nada.
    if (r.http === 429) {
      frenado = true;
      await rpc("ds_registrar_lectura_stock", {
        p_product_id: productId, p_stock: null, p_error: "429 · Dropi frenó por exceso de consultas",
      });
      fallidos++;
      detalle.push({ dropi_id: dropiId, resultado: "429 · vuelta abortada" });
      break;
    }

    const ficha = esObj(r.j?.objects) ? r.j!.objects as Obj : null;
    if (r.http !== 200 || !ficha) {
      const motivo = r.fallo ??
        `HTTP ${r.http}${typeof r.j?.message === "string" ? " · " + String(r.j.message).slice(0, 80) : ""}`;
      await rpc("ds_registrar_lectura_stock", { p_product_id: productId, p_stock: null, p_error: motivo });
      fallidos++;
      detalle.push({ dropi_id: dropiId, resultado: motivo });
      continue;
    }

    const { stock, nota } = stockDeLaFicha(ficha, variacion);
    if (stock === null) {
      await rpc("ds_registrar_lectura_stock", {
        p_product_id: productId, p_stock: null, p_error: "la ficha no trae stock reconocible",
      });
      fallidos++;
      detalle.push({ dropi_id: dropiId, resultado: "sin stock reconocible" });
      continue;
    }

    const w = await rpc("ds_registrar_lectura_stock", { p_product_id: productId, p_stock: stock });
    if (!w.ok) {
      fallidos++;
      detalle.push({ dropi_id: dropiId, resultado: `no se pudo guardar (HTTP ${w.http})` });
      continue;
    }
    refrescados++;
    detalle.push({
      dropi_id: dropiId,
      variante: variacion || null,
      stock,
      // Visible a proposito: una variante que desaparecio se registra como 0.
      nota: nota ?? undefined,
    });
  }

  // El log lleva CUENTAS, no datos: ni token, ni nombres, ni costos.
  console.log("[dropi-refrescar-stock]", JSON.stringify({
    pedidos: pendientes.length, refrescados, fallidos, frenado,
  }));

  return json({
    refrescados,
    fallidos,
    frenado_por_dropi: frenado,
    conclusion: frenado
      ? "Dropi frenó la vuelta (429). Se abortó el resto a propósito; la siguiente vuelta del reloj retoma por el producto más viejo."
      : `Vuelta completa: ${refrescados} refrescados, ${fallidos} con problema.`,
    detalle,
    corrida: new Date().toISOString(),
  }, 200);
});
