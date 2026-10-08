// ============================================================
// Prueba que crear-intencion-pago PERSISTE la intencion antes de firmar (F2)
// y que el ciclo completo funciona: intencion -> webhook -> pedido.
// Golpea la Edge Function real; la RPC corre de verdad contra Postgres local.
// Uso: herramientas/correr-intencion-f2.sh
// ============================================================
const URL_INTENCION = "http://localhost:8000";
const res: Array<[boolean, string]> = [];
const chk = (ok: boolean, q: string) => res.push([ok, q]);

async function sql(q: string): Promise<string> {
  const p = new Deno.Command("psql", {
    args: ["-tAqc", q, "-d", "impulse_pruebas"],
    env: { PGHOST: "/var/lib/pgdata", PGUSER: "postgres", PATH: "/usr/bin" },
    stdout: "piped", stderr: "piped",
  });
  const { stdout } = await p.output();
  return new TextDecoder().decode(stdout).trim();
}

async function pedir(cuerpo: Record<string, unknown>) {
  const r = await fetch(URL_INTENCION, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Origin": "https://magandhi.com" },
    body: JSON.stringify(cuerpo),
  });
  let j: Record<string, unknown> = {};
  try { j = await r.json(); } catch { /* vacio */ }
  return { status: r.status, cuerpo: j };
}

// ---------- 1. Camino feliz: se firma Y se persiste ----------
const r1 = await pedir({
  producto: "i-p1",
  cantidad: 1,
  comprador: {
    nombre: "Dora Compradora", correo: "dora@cliente.invalid", telefono: "3012223344",
    direccion: "Carrera 9 #10-20", ciudad: "Tunja", departamento: "Boyacá", pais: "CO",
  },
  utm_campaign: "camp-octubre",
  mg_vid: "vidABCDEFGH12345678",
});
chk(r1.status === 200 && typeof r1.cuerpo.firma_integridad === "string",
  `intención: responde 200 con la firma (recibido ${r1.status} ${JSON.stringify(r1.cuerpo).slice(0, 140)})`);
const ref = String(r1.cuerpo.referencia ?? "");
chk(/^[A-Za-z0-9_-]{6,64}$/.test(ref), "intención: devuelve una referencia con formato válido");

const fila = await sql(
  `select estado || '|' || monto_centavos || '|' || coalesce(comprador_nombre,'-') || '|' ||
          coalesce(comprador_ciudad,'-') || '|' || coalesce(utm_campaign,'-') || '|' ||
          coalesce(mg_vid,'-') || '|' || coalesce(product_id::text,'-') || '|' || entorno
     from pagos_intencion where referencia = '${ref}'`,
);
const [estado, monto, nombre, ciudad, utm, vid, prod, entorno] = fila.split("|");
chk(estado === "creada", "intención: queda PERSISTIDA en estado creada (antes de firmar)");
chk(monto === "3000000", "intención: guarda el monto firmado releído del servidor (30.000 x 100)");
chk(nombre === "Dora Compradora" && ciudad === "Tunja",
  "intención: guarda los datos que el comprador escribió EN LA TIENDA");
chk(utm === "camp-octubre", "intención: guarda el utm_campaign (atribución exacta de campañas)");
chk(vid === "vidABCDEFGH12345678", "intención: guarda el mg_vid de la analítica (enchufe de Métricas)");
chk(prod !== "-", "intención: resuelve el producto de Inventario desde la campaña");
chk(entorno === "sandbox", "intención: registra el entorno activo (sandbox)");
chk(typeof r1.cuerpo.monto_en_centavos === "string" && monto === String(BigInt(r1.cuerpo.monto_en_centavos)),
  "intención: el monto persistido es EXACTAMENTE el que se firmó y se envía a Wompi");

// ---------- 2. El precio NUNCA sale del navegador ----------
const r2 = await pedir({ producto: "i-p1", cantidad: 1, precio: 1, monto_en_centavos: 100 });
const ref2 = String(r2.cuerpo.referencia ?? "");
chk((await sql(`select monto_centavos from pagos_intencion where referencia = '${ref2}'`)) === "3000000",
  "seguridad: un precio enviado por el navegador se IGNORA (se relee del servidor)");

// ---------- 3. Campos basura no entran a la base ----------
const r3 = await pedir({
  producto: "i-p1", cantidad: 1,
  utm_campaign: "CAMPAÑA CON ESPACIOS; drop",
  mg_vid: "corto",
  comprador: { nombre: "x".repeat(400) },
});
const ref3 = String(r3.cuerpo.referencia ?? "");
const basura = await sql(
  `select coalesce(utm_campaign,'-') || '|' || coalesce(mg_vid,'-') || '|' || length(comprador_nombre)
     from pagos_intencion where referencia = '${ref3}'`,
);
chk(basura.split("|")[0] === "-", "saneado: un utm_campaign con formato inválido no entra");
chk(basura.split("|")[1] === "-", "saneado: un mg_vid con formato inválido no entra");
chk(Number(basura.split("|")[2]) <= 120, "saneado: el nombre se recorta a una longitud sana");

// ---------- 4. Cantidad distinta de 1 sigue rechazada (y no persiste) ----------
const r4 = await pedir({ producto: "i-p1", cantidad: 1000 });
chk(r4.status === 400, "seguridad: cantidad distinta de 1 se rechaza con 400");
chk((await sql("select count(*) from pagos_intencion where cantidad <> 1")) === "0",
  "seguridad: no queda ninguna intención con cantidad distinta de 1");

// ---------- 5. Producto inexistente: ni firma ni intención ----------
const antes = await sql("select count(*) from pagos_intencion");
const r5 = await pedir({ producto: "no-existe-este-slug", cantidad: 1 });
chk(r5.status >= 400, "producto inexistente: se rechaza");
chk((await sql("select count(*) from pagos_intencion")) === antes,
  "producto inexistente: no se crea ninguna intención");

// ---------- 6. Nada de secretos en la respuesta ----------
const txt = JSON.stringify(r1.cuerpo);
chk(!/integrity|service_role|eyJ|SECRETO/i.test(txt),
  "la respuesta no incluye secretos ni la llave de servicio");

for (const [ok, q] of res) console.log((ok ? "pasa" : "FALLA") + " | " + q);
console.log(`RESUMEN | ${res.length} comprobaciones · ${res.filter(([o]) => !o).length} fallan`);
// La referencia de la intencion feliz se deja para la prueba del ciclo completo.
await Deno.writeTextFile("/projects/sandbox/pruebas-em5/ref-intencion.txt", ref);
