// ============================================================
// CICLO COMPLETO de F2: la intencion que acabo de firmar la tienda se cobra
// por el webhook con una firma REAL de Wompi y debe convertirse en UN pedido.
// Lo lanza correr-intencion-f2.sh con REF_CICLO = la referencia real.
// ============================================================
const URL_FN = "http://localhost:8000";
const SECRETO = "test_events_SECRETOFALSOsandbox123456";
const enc = new TextEncoder();
const res: Array<[boolean, string]> = [];
const chk = (ok: boolean, q: string) => res.push([ok, q]);
const REF = Deno.env.get("REF_CICLO") ?? "";

function hex(b: Uint8Array) {
  let s = "";
  for (const x of b) s += x.toString(16).padStart(2, "0");
  return s;
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
async function avisar(estado: string, monto: number, txid: string) {
  const tx = {
    id: txid, amount_in_cents: monto, reference: REF,
    customer_email: "pagador@wompi.invalid", currency: "COP",
    payment_method_type: "BANCOLOMBIA_TRANSFER", status: estado,
  };
  const data = { transaction: tx };
  const ts = 1530291411;
  const props = ["transaction.id", "transaction.status", "transaction.amount_in_cents"];
  const cadena = props.map((p) => String((tx as Record<string, unknown>)[p.split(".")[1]])).join("") + String(ts) + SECRETO;
  const suma = hex(new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode(cadena))));
  const r = await fetch(URL_FN, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      event: "transaction.updated", data, environment: "test",
      signature: { properties: props, checksum: suma }, timestamp: ts,
      sent_at: new Date().toISOString(),
    }),
  });
  let j: Record<string, unknown> = {};
  try { j = await r.json(); } catch { /* vacio */ }
  return { status: r.status, cuerpo: j };
}

chk(REF !== "", "ciclo: se recibió la referencia real que firmó la tienda");

const stockAntes = Number(await sql("select existencias from stock_actual where product_id = 'b8000000-0000-4000-8000-000000000001'"));
const a = await avisar("APPROVED", 3000000, "TX-CICLO-1");
chk(a.status === 200 && a.cuerpo.estado === "procesado", "ciclo: el pago aprobado de ESA intención se procesa");

const datos = await sql(
  `select p.canal || '|' || p.total || '|' || coalesce(p.utm_campaign,'-') || '|' || c.nombre || '|' || coalesce(p.ciudad,'-')
     from pedidos p join clientes c on c.id = p.customer_id
    where p.id = (select pedido_id from pagos_intencion where referencia = '${REF}')`,
);
const [canal, total, utm, nombre, ciudad] = datos.split("|");
chk(canal === "web", "ciclo: el pedido queda canal=web");
chk(total === "30000", "ciclo: el total es el precio releído por el servidor");
chk(utm === "camp-octubre", "ciclo: el pedido hereda el utm_campaign (atribución EXACTA)");
chk(nombre === "Dora Compradora" && ciudad === "Tunja",
  "ciclo: el cliente es el que escribió en la TIENDA (Wompi solo confirmó el pago)");

const stockDespues = Number(await sql("select existencias from stock_actual where product_id = 'b8000000-0000-4000-8000-000000000001'"));
chk(stockDespues === stockAntes - 1, `ciclo: el stock bajó exactamente una unidad (${stockAntes} -> ${stockDespues})`);
chk((await sql(`select estado from pagos_intencion where referencia = '${REF}'`)) === "procesada",
  "ciclo: la intención queda procesada (terminal)");
chk((await sql("select count(*) from pedido_bitacora where accion = 'crear'")) !== "0",
  "ciclo: queda bitácora del pedido");

// Reintento de Wompi sobre el ciclo real
const b = await avisar("APPROVED", 3000000, "TX-CICLO-1");
chk(b.status === 200 && b.cuerpo.estado === "repetido", "ciclo: el reintento de Wompi devuelve repetido");
chk(Number(await sql("select existencias from stock_actual where product_id = 'b8000000-0000-4000-8000-000000000001'")) === stockDespues,
  "ciclo: el reintento NO vuelve a bajar el stock");
chk((await sql(`select count(*) from pedidos where id = (select pedido_id from pagos_intencion where referencia = '${REF}')`)) === "1",
  "ciclo: sigue existiendo UN SOLO pedido para esa referencia");

for (const [ok, q] of res) console.log((ok ? "pasa" : "FALLA") + " | " + q);
console.log(`RESUMEN CICLO | ${res.length} comprobaciones · ${res.filter(([o]) => !o).length} fallan`);
