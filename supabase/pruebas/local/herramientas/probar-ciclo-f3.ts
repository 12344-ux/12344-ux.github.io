// ============================================================
// CICLO COMPLETO de F3 con las Edge Functions REALES y Wompi en PRODUCCION
// simulada: la tienda firma, Wompi avisa con firma real de produccion, y deben
// quedar el pedido, el ASIENTO al peso y UN solo correo «Recibido».
// Lo lanza correr-ciclo-f3.sh (llaves y secretos falsos, base local).
// ============================================================
const URL_INTENCION = "http://localhost:8002";
const URL_CORREO = "http://localhost:8001";
const URL_WEBHOOK = "http://localhost:8000";
const URL_RESEND = "http://localhost:54322";
const SECRETO_PROD = "prod_events_SECRETOFALSOprod123456789";
const LLAVE = Deno.env.get("LLAVE_SERVICIO") ?? "";
const PRODUCTO = "b4000000-0000-4000-8000-000000000001";
const enc = new TextEncoder();
const res: Array<[boolean, string]> = [];
const chk = (ok: boolean, q: string) => res.push([ok, q]);

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
  const { stdout, stderr } = await p.output();
  const e = new TextDecoder().decode(stderr).trim();
  if (e) console.error("psql:", e);
  return new TextDecoder().decode(stdout).trim();
}
async function post(url: string, cuerpo: unknown, cabeceras: Record<string, string> = {}) {
  const r = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...cabeceras },
    body: JSON.stringify(cuerpo),
  });
  let j: Record<string, unknown> = {};
  try { j = await r.json(); } catch { /* vacio */ }
  return { status: r.status, cuerpo: j };
}
// Cada comprador con su propio telefono: crear_pedido une clientes por correo
// y, si no, por telefono (regla de Ventas).
async function comprar(nombre: string, correo: string, telefono: string) {
  const r = await post(URL_INTENCION, {
    producto: "c3-p1", cantidad: 1,
    comprador: { nombre, correo, telefono, direccion: "Calle 20 #9-15", ciudad: "Tunja",
                 departamento: "Boyacá", pais: "CO" },
  }, { "Origin": "https://magandhi.com" });
  return { status: r.status, ref: String(r.cuerpo.referencia ?? ""), monto: String(r.cuerpo.monto_en_centavos ?? "") };
}
async function avisar(ref: string, estado: string, monto: number, txid: string) {
  const tx = { id: txid, amount_in_cents: monto, reference: ref, customer_email: "pagador@wompi.invalid",
               currency: "COP", payment_method_type: "CARD", status: estado };
  const ts = 1760000000;
  const props = ["transaction.id", "transaction.status", "transaction.amount_in_cents"];
  const cadena = `${tx.id}${tx.status}${tx.amount_in_cents}${ts}${SECRETO_PROD}`;
  const suma = hex(new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode(cadena))));
  return await post(URL_WEBHOOK, {
    event: "transaction.updated", data: { transaction: tx }, environment: "prod",
    signature: { properties: props, checksum: suma }, timestamp: ts, sent_at: new Date().toISOString(),
  });
}
const correos = async () => (await (await fetch(`${URL_RESEND}/__correos`)).json()) as Array<Record<string, unknown>>;
const pedidoDe = (ref: string) => sql(`select pedido_id from pagos_intencion where referencia = '${ref}'`);

// ---------- 1. La tienda firma en PRODUCCION ----------
const eva = await comprar("Eva Compradora", "eva@cliente.invalid", "3015550001");
chk(eva.status === 200 && /^[A-Za-z0-9_-]{6,64}$/.test(eva.ref), "tienda: la intención se firma (200) con referencia válida");
chk((await sql(`select entorno from pagos_intencion where referencia = '${eva.ref}'`)) === "prod",
  "tienda: la intención queda registrada como dinero REAL (entorno prod)");

// ---------- 2. Wompi aprueba: pedido + asiento + correo ----------
const a1 = await avisar(eva.ref, "APPROVED", Number(eva.monto), "TX-C3-EVA");
chk(a1.status === 200 && a1.cuerpo.estado === "procesado", "webhook: el pago aprobado se procesa (200)");
const pEva = await pedidoDe(eva.ref);
chk((await sql(`select canal || '|' || total || '|' || (fecha_orden = (creado at time zone 'America/Bogota')::date)
                  from pedidos where id = '${pEva}'`)) === "web|69900|true",
  "pedido: canal web, total 69.900 y fecha de COLOMBIA");
const asiento = await sql(`select string_agg(l.cuenta_codigo || ':' || l.debe || ':' || l.haber, ',' order by l.orden)
                             from asientos a join asiento_lineas l on l.asiento_id = a.id
                            where a.origen = 'venta_web' and a.origen_ref = '${pEva}'`);
chk(asiento === "138095:69900:0,413505:0:69900,613505:25000:0,143505:0:25000",
  `asiento: entró SOLO y al peso (${asiento})`);
chk((await sql(`select (a.fecha = p.fecha_orden)::text from asientos a join pedidos p on p.id = a.origen_ref
                 where a.origen = 'venta_web' and a.origen_ref = '${pEva}'`)) === "true",
  "asiento: con la misma fecha del pedido");

let c = await correos();
const deEva = c.filter((x) => JSON.stringify(x.to) === JSON.stringify(["eva@cliente.invalid"]));
chk(deEva.length === 1, `correo: salió UN «Recibido» a la compradora (salieron ${deEva.length})`);
const m = deEva[0] ?? {};
chk(/Recibimos tu pedido #[0-9A-F]{8}/.test(String(m.subject ?? "")), `correo: asunto de la plantilla «Recibido» (${m.subject})`);
chk(String(m.html ?? "").includes("$69.900") && String(m.html ?? "").includes("Shampoo ciclo F3"),
  "correo: lleva el producto y el total del pedido");
chk(JSON.stringify(m.tags ?? []).includes('"recibido"') && !String(m.html ?? "").includes("código de reseña"),
  "correo: es la etapa recibido (sin código de reseña)");
const envio = await sql(`select estado || '|' || (creado_por is null) || '|' || coalesce(proveedor_id, '-') || '|' || id
                           from correo_envios where pedido_id = '${pEva}' and etapa = 'recibido'`);
const [estEnvio, sistema, proveedor, envioId] = envio.split("|");
chk(estEnvio === "enviado" && sistema === "true" && proveedor !== "-",
  "bitácora de correos: «Recibido» enviado por el SISTEMA, con el id del proveedor");
chk(m._idem === envioId, "correo: viaja con Idempotency-Key = envío (Resend no lo duplica)");

// ---------- 3. Wompi reintenta: nada se duplica ----------
const a2 = await avisar(eva.ref, "APPROVED", Number(eva.monto), "TX-C3-EVA");
chk(a2.status === 200 && a2.cuerpo.estado === "repetido", "reintento: 200 repetido");
chk((await sql(`select count(*) from asientos where origen_ref = '${pEva}'`)) === "1", "reintento: sigue habiendo UN asiento");
c = await correos();
chk(c.filter((x) => JSON.stringify(x.to) === JSON.stringify(["eva@cliente.invalid"])).length === 1,
  "reintento: sigue habiendo UN correo (el servidor responde «ya enviado»)");
chk((await sql(`select count(*) from correo_envios where pedido_id = '${pEva}'`)) === "1",
  "reintento: la bitácora de correos no crece");

// ---------- 4. Resend caído: la venta y el asiento no se pierden ----------
await fetch(`${URL_RESEND}/__falla?v=1`);
const fede = await comprar("Fede Comprador", "fede@cliente.invalid", "3015550002");
const b1 = await avisar(fede.ref, "APPROVED", Number(fede.monto), "TX-C3-FEDE");
const pFede = await pedidoDe(fede.ref);
chk(b1.status === 200 && b1.cuerpo.estado === "procesado" && pFede !== "",
  "Resend caído: Wompi recibe 200 y el pedido existe igual");
chk((await sql(`select count(*) from asientos where origen = 'venta_web' and origen_ref = '${pFede}'`)) === "1",
  "Resend caído: el asiento existe igual");
chk((await sql(`select estado from correo_envios where pedido_id = '${pFede}'`)) === "fallido",
  "Resend caído: el correo queda «fallido» a la vista en Seguimiento (para reenviar)");
await fetch(`${URL_RESEND}/__falla?v=0`);
const b2 = await avisar(fede.ref, "APPROVED", Number(fede.monto), "TX-C3-FEDE");
c = await correos();
const nFede = c.filter((x) => JSON.stringify(x.to) === JSON.stringify(["fede@cliente.invalid"])).length;
chk(b2.cuerpo.estado === "repetido" && nFede === 1,
  `Resend de vuelta: el siguiente aviso de Wompi recupera el correo, una sola vez (aviso ${b2.cuerpo.estado}, correos ${nFede})`);
chk((await sql(`select string_agg(estado, ',' order by creado) from correo_envios where pedido_id = '${pFede}'`)) === "fallido,enviado",
  "Resend de vuelta: la bitácora guarda el intento fallido y el envío bueno");

// ---------- 5. Pago rechazado: nada de nada ----------
const gina = await comprar("Gina Compradora", "gina@cliente.invalid", "3015550003");
const antes = await sql("select count(*) from asientos");
const g1 = await avisar(gina.ref, "DECLINED", Number(gina.monto), "TX-C3-GINA");
c = await correos();
chk(g1.status === 200 && (await pedidoDe(gina.ref)) === "" && (await sql("select count(*) from asientos")) === antes &&
    !c.some((x) => JSON.stringify(x.to).includes("gina@")),
  "rechazado: sin pedido, sin asiento y sin correo");

// ---------- 6. La puerta automática solo abre con la llave de servicio ----------
const s1 = await post(URL_CORREO, { modo: "automatico", pedido_id: pEva });
chk(s1.status === 401, `puerta: sin credencial se rechaza (${s1.status})`);
const s2 = await post(URL_CORREO, { modo: "automatico", pedido_id: pEva },
  { Authorization: "Bearer eyJhbGciOiJIUzI1NiJ9.e30.falso", apikey: "sb_publishable_falsa" });
chk(s2.status === 401 || s2.status === 400, `puerta: con un JWT cualquiera no entra al modo automático (${s2.status})`);
const s3 = await post(URL_CORREO, { modo: "pedido", pedido_id: pEva, etapa: "en_camino" },
  { Authorization: `Bearer ${LLAVE}`, apikey: LLAVE });
chk(s3.status === 400, "puerta: la llave de servicio no sirve para enviar otras etapas");
const manual = await sql(`select set_config('request.jwt.claims', '{"sub":"89e5028d-8c17-4deb-89c3-59acbd0ee2f2","role":"authenticated"}', false) is not null;
  set role authenticated;
  select crear_pedido(p_nombre => 'Mostrador', p_correo => 'mostrador@cliente.invalid', p_canal => 'manual',
    p_items => '[{"product_id":"${PRODUCTO}","cantidad":1,"precio_unitario":69900}]'::jsonb)->>'pedido_id';`);
const pManual = manual.split("\n").pop() ?? "";
const s4 = await post(URL_CORREO, { modo: "automatico", pedido_id: pManual },
  { Authorization: `Bearer ${LLAVE}`, apikey: LLAVE });
chk(s4.status === 409, `puerta: un pedido manual no recibe correo automático (${s4.status})`);

// ---------- 7. Finanzas cuadra y la anulación lo deja en cero ----------
const neto = (cta: string) => sql(`select coalesce(sum(l.debe - l.haber), 0) from asiento_lineas l
  join asientos a on a.id = l.asiento_id where a.estado = 'activo' and l.cuenta_codigo = '${cta}'`);
chk((await neto("138095")) === "139800", "Finanzas: Wompi debe consignar 139.800 (dos ventas reales)");
await sql(`select set_config('request.jwt.claims', '{"sub":"89e5028d-8c17-4deb-89c3-59acbd0ee2f2","role":"authenticated"}', false) is not null;
  set role authenticated; select anular_pedido('${pEva}', 'prueba del ciclo');`);
chk((await sql(`select count(*) from asientos where origen = 'reverso_venta_web' and origen_ref = '${pEva}'`)) === "1",
  "anular en Ventas: se registra el contraasiento");
chk((await neto("138095")) === "69900" && (await neto("413505")) === "-69900",
  "anular en Ventas: queda solo la venta vigente (69.900)");

for (const [ok, q] of res) console.log((ok ? "pasa" : "FALLA") + " | " + q);
console.log(`RESUMEN CICLO F3 | ${res.length} comprobaciones · ${res.filter(([o]) => !o).length} fallan`);
