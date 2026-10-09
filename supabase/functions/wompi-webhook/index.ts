// ============================================================================
// MAGANDHI · Edge Function · wompi-webhook (Fase F · Tramo F2)
// ----------------------------------------------------------------------------
// Recibe los avisos de Wompi (evento transaction.updated), VERIFICA que sean
// autenticos y delega TODO el trabajo a la RPC pw_procesar_pago, que convierte
// un pago aprobado en pedido exactamente una vez.
//
// ============================================================================
// LINEA ROJA DE SEGURIDAD (orden permanente del dueno · NO negociable):
//   - El SECRETO DE EVENTOS vive SOLO como secret de la Edge Function en
//     Deno.env (WOMPI_EVENTS_SANDBOX / WOMPI_EVENTS_PROD). Nunca en el repo,
//     ni en una tabla, ni en el frontend, ni en los logs.
//   - El secreto de EVENTOS es DISTINTO del de INTEGRIDAD que usa
//     crear-intencion-pago, y distinto de las llaves publica/privada.
//   - Esta funcion NO escribe en tablas: solo llama la RPC security definer.
//   - Nunca se confia en el monto que llega: la RPC lo compara con el FIRMADO.
//
// ============================================================================
// COMO SE VALIDA LA FIRMA (doc oficial: docs.wompi.co/docs/colombia/eventos/)
//   checksum = SHA256( <valores de signature.properties, en orden>
//                      + <timestamp>
//                      + <secreto de eventos> )   -> hex
//   El checksum llega en el header X-Event-Checksum y en signature.checksum
//   (ambos sirven; aqui se acepta cualquiera de los dos y se comparan en
//   tiempo constante).
//
//   ⚠️ properties NO SE FIJA EN EL CODIGO. La propia documentacion advierte que
//   "los valores del campo properties pueden variar en el tiempo y en cada
//   evento", asi que se leen del evento y se resuelven como rutas sobre `data`
//   (ej. "transaction.id" -> data.transaction.id). Fijarlas seria una bomba de
//   tiempo: el dia que Wompi agregue una, toda firma fallaria.
//
// ============================================================================
// CODIGOS DE RESPUESTA (importan: si no recibe 200, Wompi REINTENTA hasta 3
// veces en 24 h — a los 30 min, a las 3 h y a las 24 h):
//   200  procesado, repetido, rechazado, ignorado, sin intencion... es decir,
//        todo lo que YA resolvimos. No tiene sentido que Wompi insista.
//   401  el checksum no valida (o no llega). Posible suplantacion.
//   400  cuerpo invalido.
//   413  cuerpo demasiado grande.
//   503  falta configuracion del servidor.
//   500  SOLO si el fallo es NUESTRO, para que Wompi reintente.
//
// ENTORNOS: Wompi exige una URL de eventos distinta para Sandbox y Produccion.
// El campo environment del evento ("test" | "prod") elige el secreto, de modo
// que un evento de sandbox nunca se valida con el secreto de produccion.
//
// F3: la RPC tambien registra el ASIENTO CONTABLE de la venta real (o lo deja
// pendiente en Finanzas, sin tumbar nunca la venta). Y, con el pedido creado,
// esta funcion pide a enviar-correo-pedido el correo «Recibido» del cliente
// (modo automatico). Ese correo jamas cambia la respuesta a Wompi.
// ============================================================================

const MAX_BYTES = 256 * 1024;
const enc = new TextEncoder();

const json = (b: unknown, s: number) =>
  new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json; charset=utf-8" } });

function hex(b: Uint8Array) {
  let s = "";
  for (const x of b) s += x.toString(16).padStart(2, "0");
  return s;
}

/** Comparacion en tiempo constante (no revela donde difieren). */
function igualesTiempoConstante(a: string, b: string) {
  const x = enc.encode(a), y = enc.encode(b);
  let d = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) d |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return d === 0;
}

/** Resuelve "transaction.id" sobre el objeto data. Devuelve "" si no existe. */
function porRuta(data: unknown, ruta: string): string {
  let actual: unknown = data;
  for (const parte of ruta.split(".")) {
    if (actual === null || typeof actual !== "object") return "";
    actual = (actual as Record<string, unknown>)[parte];
  }
  if (actual === null || actual === undefined) return "";
  if (typeof actual === "object") return "";
  return String(actual);
}

/** Calcula el checksum segun la doc de Wompi. */
async function calcularChecksum(
  propiedades: string[], data: unknown, timestamp: unknown, secreto: string,
): Promise<string> {
  const valores = propiedades.map((p) => porRuta(data, p)).join("");
  const cadena = `${valores}${String(timestamp)}${secreto}`;
  const hash = await crypto.subtle.digest("SHA-256", enc.encode(cadena));
  return hex(new Uint8Array(hash));
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Usa POST." }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const llaveServicio = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !llaveServicio) {
    console.error("[wompi-webhook] Falta SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY.");
    return json({ error: "Configuración incompleta." }, 503);
  }

  // --- Cuerpo (con tope de tamano) ------------------------------------------
  const largo = Number(req.headers.get("content-length") ?? "0");
  if (largo > MAX_BYTES) return json({ error: "Cuerpo demasiado grande." }, 413);
  const cuerpoTexto = await req.text();
  if (enc.encode(cuerpoTexto).length > MAX_BYTES) return json({ error: "Cuerpo demasiado grande." }, 413);

  let evento: Record<string, unknown>;
  try { evento = JSON.parse(cuerpoTexto); } catch { return json({ error: "JSON inválido." }, 400); }
  if (!evento || typeof evento !== "object" || Array.isArray(evento)) {
    return json({ error: "Evento inválido." }, 400);
  }

  // --- Secreto segun el ambiente del evento ---------------------------------
  // environment: "test" para Sandbox, "prod" para Produccion.
  const ambiente = String(evento.environment ?? "").toLowerCase();
  const esProd = ambiente === "prod" || ambiente === "production";
  const nombreSecreto = esProd ? "WOMPI_EVENTS_PROD" : "WOMPI_EVENTS_SANDBOX";
  const secreto = Deno.env.get(nombreSecreto);
  if (!secreto) {
    console.error(`[wompi-webhook] Falta el secret ${nombreSecreto}.`);
    return json({ error: "Configuración incompleta." }, 503);
  }

  // --- Verificacion del checksum --------------------------------------------
  const firma = (evento.signature ?? {}) as Record<string, unknown>;
  const propiedades = Array.isArray(firma.properties) ? (firma.properties as unknown[]).map(String) : null;
  const recibido = String(
    req.headers.get("x-event-checksum") ?? firma.checksum ?? "",
  ).trim().toLowerCase();

  if (!propiedades || !propiedades.length || !recibido) {
    console.error("[wompi-webhook] Evento sin properties o sin checksum.");
    return json({ error: "Firma ausente." }, 401);
  }
  if (evento.timestamp === undefined || evento.timestamp === null) {
    return json({ error: "Firma ausente." }, 401);
  }

  const esperado = await calcularChecksum(propiedades, evento.data, evento.timestamp, secreto);
  if (!igualesTiempoConstante(recibido, esperado)) {
    // No se loguea ningun checksum ni el secreto: solo el hecho.
    console.error("[wompi-webhook] Checksum inválido. Evento ignorado.");
    return json({ error: "Firma inválida." }, 401);
  }

  // --- Solo nos interesan las transacciones ---------------------------------
  const nombreEvento = String(evento.event ?? "");
  const data = (evento.data ?? {}) as Record<string, unknown>;
  const tx = (data.transaction ?? null) as Record<string, unknown> | null;

  if (nombreEvento !== "transaction.updated" || !tx) {
    // Firma valida pero no es un evento que nos toque (p. ej. tokens de Nequi).
    // Se responde 200 para que Wompi no reintente algo que no vamos a procesar.
    console.log(`[wompi-webhook] Evento '${nombreEvento}' sin transacción: ignorado.`);
    return json({ ok: true, estado: "ignorado" }, 200);
  }

  const transaccionId = String(tx.id ?? "").trim();
  const estado = String(tx.status ?? "").trim().toUpperCase();
  const referencia = String(tx.reference ?? "").trim();
  const montoBruto = tx.amount_in_cents;
  const monto = typeof montoBruto === "number"
    ? Math.trunc(montoBruto)
    : /^\d{1,18}$/.test(String(montoBruto ?? "")) ? Number(String(montoBruto)) : null;

  if (!transaccionId || !estado) return json({ error: "Transacción incompleta." }, 400);

  // --- Delegar a la RPC (idempotente, transaccional) ------------------------
  const r = await fetch(`${supabaseUrl}/rest/v1/rpc/pw_procesar_pago`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      // Lección de Wompi F1: enviar la llave de servicio en apikey Y en
      // Authorization, para que PostgREST no degrade el rol a anon.
      "apikey": llaveServicio,
      "Authorization": `Bearer ${llaveServicio}`,
    },
    body: JSON.stringify({
      p_transaccion_id: transaccionId,
      p_estado_wompi: estado,
      p_referencia: referencia,
      p_monto_centavos: monto,
      p_moneda: String(tx.currency ?? "COP"),
      p_evento: nombreEvento,
      p_checksum: recibido,
      p_cuerpo: evento,
      p_metodo_pago: tx.payment_method_type ? String(tx.payment_method_type) : null,
      p_correo_pagador: tx.customer_email ? String(tx.customer_email) : null,
    }),
  });

  const textoRpc = await r.text();
  if (!r.ok) {
    // Fallo NUESTRO: se devuelve 500 a proposito para que Wompi reintente.
    // Se loguea el motivo REAL de PostgREST (lección de F1: no depurar a ciegas).
    console.error(`[wompi-webhook] RPC pw_procesar_pago falló (${r.status}): ${textoRpc}`);
    return json({ error: "No se pudo procesar el pago." }, 500);
  }

  let resultado = "procesado";
  let pedidoId: string | null = null;
  let asiento: string | null = null;
  try {
    const d = JSON.parse(textoRpc);
    const fila = (Array.isArray(d) ? d[0] : d) as Record<string, unknown> | null;
    resultado = String(fila?.resultado ?? "procesado");
    pedidoId = fila?.pedido_id ? String(fila.pedido_id) : null;
    const a = fila?.asiento as Record<string, unknown> | undefined;
    asiento = a?.resultado ? String(a.resultado) : null;
  } catch { /* la RPC respondio algo no-JSON: ya quedo registrado en la base */ }

  // Todo lo que YA resolvimos responde 200: Wompi no debe insistir.
  // F3: el resultado del asiento contable (creado | omitido | pendiente) queda
  // en el log; el motivo de un pendiente se ve en Finanzas, no aqui.
  console.log(`[wompi-webhook] ${transaccionId} ${estado} -> ${resultado}` +
    (asiento ? ` · asiento ${asiento}` : ""));

  // --- F3 · correo «Recibido» automatico ------------------------------------
  // Se dispara con pedido creado y TAMBIEN en un reintento: si la primera vez
  // la funcion murio antes de enviarlo, el reintento de Wompi lo recupera. El
  // servidor garantiza que sale UNA sola vez (CORREO_YA_ENVIADO). Nunca cambia
  // la respuesta a Wompi.
  if (pedidoId && ["procesado", "repetido", "ya_procesada"].includes(resultado)) {
    const tarea = dispararCorreoRecibido(supabaseUrl, llaveServicio, pedidoId);
    const runtime = (globalThis as { EdgeRuntime?: { waitUntil(p: Promise<unknown>): void } }).EdgeRuntime;
    if (runtime?.waitUntil) runtime.waitUntil(tarea); // responde ya; el correo sigue en segundo plano
    else await tarea;                                 // fuera de Supabase (pruebas locales)
  }

  return json({ ok: true, estado: resultado }, 200);
});

/**
 * F3 · pide a enviar-correo-pedido (modo automatico, servidor a servidor) el
 * correo «Recibido» del pedido web. Autentica con la llave de servicio, que ya
 * vive en el entorno de las dos funciones. Solo registra el estado: nunca el
 * correo del cliente ni la llave.
 */
async function dispararCorreoRecibido(supabaseUrl: string, llave: string, pedidoId: string) {
  const url = Deno.env.get("CORREO_FUNCION_URL") ??
    `${supabaseUrl}/functions/v1/enviar-correo-pedido`;
  try {
    const r = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", "apikey": llave, "Authorization": `Bearer ${llave}` },
      body: JSON.stringify({ modo: "automatico", pedido_id: pedidoId }),
      signal: AbortSignal.timeout(20000),
    });
    let estadoCorreo = r.ok ? "enviado" : `HTTP ${r.status}`;
    try {
      const j = await r.json();
      if (j && typeof j.estado === "string") estadoCorreo = j.estado;
    } catch { /* sin cuerpo JSON (p. ej. la funcion aun no tiene el modo automatico) */ }
    console.log(`[wompi-webhook] correo Recibido: ${estadoCorreo}`);
  } catch (e) {
    console.error(`[wompi-webhook] correo Recibido: sin respuesta de enviar-correo-pedido (${String(e).slice(0, 120)})`);
  }
}
