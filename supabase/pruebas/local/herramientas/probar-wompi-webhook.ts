// ============================================================
// Prueba de la Edge Function wompi-webhook con CHECKSUMS REALES.
// Calcula la firma igual que Wompi (SHA256 de properties + timestamp + secreto)
// y golpea la funcion, que a su vez ejecuta la RPC pw_procesar_pago de verdad
// contra el Postgres local (via simulador-v2.ts).
// Uso: herramientas/correr-wompi-webhook.sh
// ============================================================
const URL_FN = "http://localhost:8000";
const SECRETO_SANDBOX = "test_events_SECRETOFALSOsandbox123456";
const SECRETO_PROD = "prod_events_SECRETOFALSOprod123456789";
const enc = new TextEncoder();
const res: Array<[boolean, string]> = [];
const chk = (ok: boolean, q: string) => res.push([ok, q]);

function hex(b: Uint8Array) {
  let s = "";
  for (const x of b) s += x.toString(16).padStart(2, "0");
  return s;
}
function porRuta(data: unknown, ruta: string): string {
  let a: unknown = data;
  for (const p of ruta.split(".")) {
    if (a === null || typeof a !== "object") return "";
    a = (a as Record<string, unknown>)[p];
  }
  return a === null || a === undefined || typeof a === "object" ? "" : String(a);
}
async function checksum(props: string[], data: unknown, ts: number, secreto: string) {
  const cadena = props.map((p) => porRuta(data, p)).join("") + String(ts) + secreto;
  return hex(new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode(cadena))));
}

type Opc = {
  estado?: string; referencia?: string; monto?: number; txid?: string;
  ambiente?: string; evento?: string; props?: string[]; secreto?: string;
  romperChecksum?: boolean; sinChecksum?: boolean; porHeader?: boolean;
};

async function enviar(o: Opc = {}) {
  const tx = {
    id: o.txid ?? "TX-W-001",
    amount_in_cents: o.monto ?? 3000000,
    reference: o.referencia ?? "REF-W-0001",
    customer_email: "pagador@wompi.invalid",
    currency: "COP",
    payment_method_type: "NEQUI",
    status: o.estado ?? "APPROVED",
  };
  const data = { transaction: tx };
  const ts = 1530291411;
  const props = o.props ?? ["transaction.id", "transaction.status", "transaction.amount_in_cents"];
  const secreto = o.secreto ?? SECRETO_SANDBOX;
  let suma = await checksum(props, data, ts, secreto);
  if (o.romperChecksum) suma = suma.slice(0, -1) + (suma.endsWith("a") ? "b" : "a");
  const cuerpo: Record<string, unknown> = {
    event: o.evento ?? "transaction.updated",
    data,
    environment: o.ambiente ?? "test",
    signature: { properties: props, checksum: o.sinChecksum ? undefined : suma },
    timestamp: ts,
    sent_at: new Date().toISOString(),
  };
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (o.porHeader) {
    headers["X-Event-Checksum"] = suma.toUpperCase(); // Wompi lo envia en MAYUSCULAS
    (cuerpo.signature as Record<string, unknown>).checksum = undefined;
  }
  const r = await fetch(URL_FN, { method: "POST", headers, body: JSON.stringify(cuerpo) });
  let j: Record<string, unknown> = {};
  try { j = await r.json(); } catch { /* vacio */ }
  return { status: r.status, cuerpo: j };
}

async function sql(q: string): Promise<string> {
  const p = new Deno.Command("psql", {
    args: ["-tAqc", q, "-d", "impulse_pruebas"],
    env: { PGHOST: "/var/lib/pgdata", PGUSER: "postgres", PATH: "/usr/bin" },
    stdout: "piped", stderr: "piped",
  });
  const { stdout } = await p.output();
  return new TextDecoder().decode(stdout).trim();
}

// ---------- 1. Metodo y cuerpo ----------
{
  const r = await fetch(URL_FN, { method: "GET" });
  chk(r.status === 405, "solo acepta POST (405 en GET)");
  await r.body?.cancel();
}
{
  const r = await fetch(URL_FN, { method: "POST", headers: { "Content-Type": "application/json" }, body: "no-json" });
  chk(r.status === 400, "cuerpo que no es JSON: 400");
  await r.body?.cancel();
}

// ---------- 2. Seguridad de la firma ----------
chk((await enviar({ romperChecksum: true })).status === 401, "checksum alterado: 401 (posible suplantación)");
chk((await enviar({ sinChecksum: true })).status === 401, "evento sin checksum: 401");
chk((await enviar({ secreto: "secreto-equivocado" })).status === 401, "firmado con otro secreto: 401");
chk((await enviar({ ambiente: "prod" })).status === 401,
  "evento marcado prod firmado con el secreto de sandbox: 401 (no se mezclan ambientes)");

// ---------- 3. properties variables (la doc advierte que pueden cambiar) ----------
{
  const r = await enviar({
    txid: "TX-W-PROPS", referencia: "REF-W-PROPS",
    props: ["transaction.id", "transaction.status", "transaction.amount_in_cents", "transaction.currency"],
  });
  chk(r.status === 200, "properties con un campo EXTRA: la firma sigue validando (no están fijas en el código)");
}

// ---------- 4. Camino feliz: pago aprobado crea el pedido ----------
{
  const r = await enviar();
  chk(r.status === 200 && r.cuerpo.estado === "procesado", "pago aprobado: 200 y procesado");
  const pedido = await sql("select pedido_id is not null from pagos_intencion where referencia = 'REF-W-0001'");
  chk(pedido === "t", "pago aprobado: la intención quedó con su pedido");
  chk((await sql("select canal from pedidos where id = (select pedido_id from pagos_intencion where referencia = 'REF-W-0001')")) === "web",
    "pago aprobado: el pedido quedó canal=web");
  // Arranca en 5. La prueba de properties (punto 3) ya aprobó un pago y
  // consumió 1, asi que tras este quedan 3. Se asserta el numero EXACTO.
  chk((await sql("select existencias from stock_actual where product_id = 'b7000000-0000-4000-8000-000000000001'")) === "3",
    "pago aprobado: el stock bajó una unidad (5 -> 4 con properties, -> 3 aquí)");
}

// ---------- 5. EL MISMO AVISO DOS VECES (Wompi reintenta) ----------
{
  const r = await enviar();
  chk(r.status === 200 && r.cuerpo.estado === "repetido", "reintento del mismo aviso: 200 y repetido (no reprocesa)");
  chk((await sql("select count(*) from pedidos where notas like '%REF-W-0001%'")) === "1",
    "reintento: sigue habiendo UN SOLO pedido");
  chk((await sql("select existencias from stock_actual where product_id = 'b7000000-0000-4000-8000-000000000001'")) === "3",
    "reintento: el stock NO bajó otra vez (sigue en 3)");
}

// ---------- 6. Checksum por header y en MAYUSCULAS ----------
{
  const r = await enviar({ txid: "TX-W-HDR", referencia: "REF-W-0002", porHeader: true });
  chk(r.status === 200, "checksum en el header X-Event-Checksum y en mayúsculas: válido");
}

// ---------- 7. Rechazado y eventos ajenos ----------
{
  const r = await enviar({ txid: "TX-W-DEC", referencia: "REF-W-0003", estado: "DECLINED" });
  chk(r.status === 200 && r.cuerpo.estado === "rechazado", "pago rechazado: 200 y rechazado");
  chk((await sql("select estado from pagos_intencion where referencia = 'REF-W-0003'")) === "rechazada",
    "pago rechazado: la intención queda rechazada, sin pedido");
}
{
  const r = await enviar({ txid: "TX-W-NEQ", evento: "nequi_token.updated" });
  chk(r.status === 200 && r.cuerpo.estado === "ignorado",
    "evento que no nos toca (nequi_token.updated): 200 ignorado, Wompi no reintenta");
}

// ---------- 8. Monto que no coincide y pago sin intención ----------
{
  const r = await enviar({ txid: "TX-W-MONTO", referencia: "REF-W-0004", monto: 100 });
  chk(r.status === 200 && r.cuerpo.estado === "monto_no_coincide",
    "monto distinto al firmado: no crea pedido");
}
{
  const r = await enviar({ txid: "TX-W-HUERF", referencia: "REF-QUE-NO-EXISTE" });
  chk(r.status === 200 && r.cuerpo.estado === "sin_intencion",
    "pago sin intención nuestra: no se inventa un pedido");
}

// ---------- 9. Nada de secretos en la respuesta ----------
{
  const r = await enviar({ txid: "TX-W-SEC", referencia: "REF-W-0005" });
  const txt = JSON.stringify(r.cuerpo);
  chk(!txt.includes(SECRETO_SANDBOX) && !txt.includes(SECRETO_PROD) && !/events_/.test(txt),
    "la respuesta nunca incluye el secreto de eventos");
}

for (const [ok, q] of res) console.log((ok ? "pasa" : "FALLA") + " | " + q);
console.log(`RESUMEN | ${res.length} comprobaciones · ${res.filter(([o]) => !o).length} fallan`);
