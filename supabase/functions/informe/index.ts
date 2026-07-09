// ============================================================
// Stramont · Informe interno (capacidad + trazabilidad + ventas)
// - NUNCA se llama con la llave pública desde el navegador: usa
//   SUPABASE_SERVICE_ROLE_KEY del lado del servidor, igual que la
//   función "entrega", y se protege con el mismo LINK_SECRET.
// - informe.html (uso interno, no enlazado en la navegación pública)
//   le pide este secreto al dueño y lo reenvía aquí.
//
// Por qué existe esta función y no se lee la tabla "pedidos" ni el
// bucket "apuntes" directo desde el navegador con la llave pública:
// esa llave YA es pública (queda visible en el código fuente de
// simulacion.html). Si le diéramos permiso de lectura sobre pedidos
// o listado completo del bucket, cualquier visitante podría enumerar
// correos y carpetas de todos los clientes. Eso rompe la línea
// ética del proyecto (nunca exponer datos de clientes).
//
// Modos (todos requieren ?key=LINK_SECRET):
//   GET  ?key=...
//     -> JSON con: uso de storage (bucket "apuntes"), lista de pedidos
//        (con su cuestionario/intake unido y flag es_prueba), alertas de
//        pedidos sin entregar hace >48h, y resumen de ventas 15/30 días.
//   POST ?delete=1&pedido_id=XXX&key=...
//     -> Borra un pedido, PERO SOLO si es de prueba (correo que empieza
//        por "prueba", o dominio example.com / .test). Un pedido REAL
//        nunca se puede borrar por aquí, aunque se tenga el secreto:
//        es un candado de seguridad para limitar el radio de daño.
//        Borra también sus archivos en Storage y su fila de intake.
//
// Variables (ya existen en el proyecto, compartidas con "entrega"):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, LINK_SECRET
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BUCKET_APUNTES = "apuntes";
const LIMITE_STORAGE_BYTES = 1024 * 1024 * 1024; // 1 GB (plan gratuito Supabase)
const HORAS_ALERTA = 48; // pedidos sin guia_entregada pasadas estas horas -> alerta
const LIMITE_PEDIDOS = 2000; // tope de la lista; la BD aguanta millones, esto es solo para la vista
const PRECIOS: Record<string, number> = {
  "Acceso 10 días": 3,
  "Acceso 30 días": 5,
};

const CORS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-allow-headers": "*",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { ...CORS, "content-type": "application/json; charset=utf-8" },
  });
}

function sb() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

// Correos de PRUEBA. Un pedido de prueba: (a) NO cuenta como venta en el
// resumen del tablero, (b) se marca con es_prueba (badge 🧪), (c) es
// borrable desde el tablero. Debe coincidir con la misma regla en
// simulacion.html. Correo dedicado + heurística.
// CANDADO DE SEGURIDAD: un pedido real NUNCA cumple esto, así que el
// borrado no lo puede tocar aunque se tenga el secreto.
const CORREOS_PRUEBA = ["pruebasmontaguth@gmail.com"];
function esCorreoPrueba(correo: string): boolean {
  const c = (correo || "").toLowerCase().trim();
  if (CORREOS_PRUEBA.includes(c)) return true;
  return c.startsWith("prueba") || c.endsWith("@example.com") || c.endsWith(".test");
}

// El bucket "apuntes" tiene estructura correo/pedidoId/archivo, así que
// list() de un solo nivel no basta: hay que recorrer subcarpetas.
async function sumarBucket(client: ReturnType<typeof sb>, bucket: string, prefijo = "", profundidadMax = 6): Promise<{ bytes: number; archivos: number }> {
  if (profundidadMax <= 0) return { bytes: 0, archivos: 0 };
  const { data, error } = await client.storage.from(bucket).list(prefijo, {
    limit: 1000,
    sortBy: { column: "name", order: "asc" },
  });
  if (error || !data) return { bytes: 0, archivos: 0 };

  let bytes = 0;
  let archivos = 0;
  for (const item of data) {
    const ruta = prefijo ? `${prefijo}/${item.name}` : item.name;
    // Un objeto real tiene id != null; una "carpeta" no tiene id ni metadata.
    if (item.id !== null && item.metadata) {
      bytes += item.metadata.size ?? 0;
      archivos += 1;
    } else {
      const sub = await sumarBucket(client, bucket, ruta, profundidadMax - 1);
      bytes += sub.bytes;
      archivos += sub.archivos;
    }
  }
  return { bytes, archivos };
}

// Lista recursivamente todas las rutas de archivo bajo un prefijo (carpeta).
async function listarArchivos(client: ReturnType<typeof sb>, bucket: string, prefijo: string, profundidadMax = 6): Promise<string[]> {
  if (profundidadMax <= 0 || !prefijo) return [];
  const { data, error } = await client.storage.from(bucket).list(prefijo, { limit: 1000 });
  if (error || !data) return [];
  let paths: string[] = [];
  for (const item of data) {
    const ruta = `${prefijo}/${item.name}`;
    if (item.id !== null && item.metadata) paths.push(ruta);
    else paths = paths.concat(await listarArchivos(client, bucket, ruta, profundidadMax - 1));
  }
  return paths;
}

async function borrarCarpeta(client: ReturnType<typeof sb>, bucket: string, prefijo: string): Promise<number> {
  const paths = await listarArchivos(client, bucket, prefijo);
  if (paths.length) await client.storage.from(bucket).remove(paths);
  return paths.length;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const url = new URL(req.url);
  const SECRET = Deno.env.get("LINK_SECRET") || "";
  if (!SECRET) return json({ error: "Falta configurar LINK_SECRET." }, 500);
  if (url.searchParams.get("key") !== SECRET) return json({ error: "No autorizado." }, 403);

  const client = sb();

  // ---------- MODO MATERIAL (todo lo necesario para construir la guía) ----------
  // Con solo el pedido_id, devuelve en UNA llamada: datos del cliente, su
  // cuestionario, la nota interna del dueño, y enlaces de descarga FIRMADOS
  // (cortos, 1h) de cada apunte. Así la IA que arma la guía baja y lee los
  // apuntes sola, sin fricción. Protegido por LINK_SECRET (datos sensibles).
  //   GET ?material=1&pedido_id=XXX&key=...
  if (url.searchParams.get("material") === "1") {
    const pedidoId = url.searchParams.get("pedido_id") || "";
    if (!pedidoId) return json({ error: "Falta pedido_id." }, 400);

    const { data: row, error: errRow } = await client
      .from("pedidos").select("*").eq("pedido_id", pedidoId).maybeSingle();
    if (errRow) return json({ error: "Error buscando el pedido: " + errRow.message }, 500);
    if (!row) return json({ error: "Pedido no encontrado." }, 404);

    const { data: intakeRows } = await client
      .from("pedido_intake").select("*").eq("pedido_id", pedidoId)
      .order("creado", { ascending: false }).limit(1);
    const it = intakeRows && intakeRows[0] ? intakeRows[0] : null;

    // Apuntes: listar la carpeta del pedido y firmar cada archivo (1h).
    const carpeta = row.carpeta_storage || "";
    const apuntes: Array<{ nombre: string; bytes: number | null; url: string | null }> = [];
    if (carpeta) {
      const { data: files } = await client.storage.from(BUCKET_APUNTES).list(carpeta, { limit: 1000 });
      for (const fobj of (files || [])) {
        if (fobj.id !== null && fobj.metadata) {
          const path = `${carpeta}/${fobj.name}`;
          const { data: signed } = await client.storage.from(BUCKET_APUNTES).createSignedUrl(path, 3600);
          apuntes.push({ nombre: fobj.name, bytes: fobj.metadata?.size ?? null, url: signed?.signedUrl || null });
        }
      }
    }

    return json({
      pedido: {
        pedido_id: row.pedido_id, correo: row.correo, nombre: row.nombre,
        plan: row.plan, dias_acceso: row.dias_acceso, tema: row.tema,
        fecha_compra: row.fecha_compra, guia_entregada: row.guia_entregada,
        guia_archivo: row.guia_archivo, carpeta_storage: carpeta,
        es_prueba: esCorreoPrueba(row.correo), apuntes_borrados: row.apuntes_borrados,
      },
      cuestionario: it ? { uso: it.uso, cuesta: it.cuesta, extra: it.extra } : null,
      nota_interna: row.nota_interna || null,
      apuntes,
    });
  }

  // ---------- MODO GUARDAR NOTA INTERNA (del dueño, para la IA) ----------
  //   POST ?guardar_nota=1&pedido_id=XXX&key=...   body: { nota }
  if (url.searchParams.get("guardar_nota") === "1") {
    if (req.method !== "POST") return json({ error: "Requiere POST." }, 405);
    const pedidoId = url.searchParams.get("pedido_id") || "";
    if (!pedidoId) return json({ error: "Falta pedido_id." }, 400);
    let body: any = {};
    try { body = await req.json(); } catch { /* nota vacía permitida (para borrarla) */ }
    const nota = (body && typeof body.nota === "string") ? body.nota : "";
    const { error: errUpd } = await client.from("pedidos")
      .update({ nota_interna: nota || null }).eq("pedido_id", pedidoId);
    if (errUpd) return json({ error: "Error guardando la nota: " + errUpd.message }, 500);
    return json({ ok: true, pedido_id: pedidoId });
  }

  // ---------- MODO MARCAR ENTREGADA / PENDIENTE ----------
  // Así el dueño le dice al tablero que ya entregó la guía (o deshace el
  // cambio). Funciona en cualquier pedido (real o prueba); no es destructivo.
  //   POST ?entregada=1&pedido_id=XXX  -> marca entregada (pone fecha_entrega)
  //   POST ?entregada=0&pedido_id=XXX  -> vuelve a pendiente (borra fecha_entrega)
  if (url.searchParams.get("entregada") !== null) {
    if (req.method !== "POST") return json({ error: "Requiere POST." }, 405);
    const pedidoId = url.searchParams.get("pedido_id") || "";
    if (!pedidoId) return json({ error: "Falta pedido_id." }, 400);
    const marcar = url.searchParams.get("entregada") === "1";
    const { error: errUpd } = await client.from("pedidos")
      .update({ guia_entregada: marcar, fecha_entrega: marcar ? new Date().toISOString() : null })
      .eq("pedido_id", pedidoId);
    if (errUpd) return json({ error: "Error actualizando: " + errUpd.message }, 500);
    return json({ ok: true, pedido_id: pedidoId, guia_entregada: marcar });
  }

  // ---------- MODO LIBERAR APUNTES (borra SOLO archivos de Storage) ----------
  // Borra los apuntes crudos de ESTE pedido (su subcarpeta correo/pedidoId),
  // conservando el registro, su cuestionario y las ventas. Sirve para
  // cualquier pedido (real o prueba): liberar espacio desde el tablero sin
  // ir a Supabase. Candados de seguridad:
  //   1) Solo si la guía ya está marcada como ENTREGADA (así nunca se borran
  //      apuntes que no se han procesado todavía).
  //   2) Solo la subcarpeta del pedido: carpeta_storage debe incluir "/"
  //      (correo/pedidoId), nunca la carpeta completa de una persona.
  //   POST ?liberar=1&pedido_id=XXX&key=...
  if (url.searchParams.get("liberar") === "1") {
    if (req.method !== "POST") return json({ error: "Requiere POST." }, 405);
    const pedidoId = url.searchParams.get("pedido_id") || "";
    if (!pedidoId) return json({ error: "Falta pedido_id." }, 400);

    const { data: row, error: errRow } = await client
      .from("pedidos").select("*").eq("pedido_id", pedidoId).maybeSingle();
    if (errRow) return json({ error: "Error buscando el pedido: " + errRow.message }, 500);
    if (!row) return json({ error: "Pedido no encontrado." }, 404);

    // Candado 1: no liberar apuntes de un pedido sin entregar.
    if (!row.guia_entregada) {
      return json({ error: "Marca la guía como entregada antes de liberar los apuntes (así no borras algo sin procesar)." }, 409);
    }
    // Candado 2: nunca una carpeta de persona completa; debe ser correo/pedidoId.
    const carpeta = row.carpeta_storage || "";
    if (!carpeta.includes("/")) {
      return json({ error: "Ruta de carpeta inválida; se cancela por seguridad." }, 400);
    }

    let archivosBorrados = 0;
    try { archivosBorrados = await borrarCarpeta(client, BUCKET_APUNTES, carpeta); }
    catch (e) { return json({ error: "Error borrando archivos: " + (e as Error).message }, 500); }

    await client.from("pedidos").update({ apuntes_borrados: new Date().toISOString() }).eq("pedido_id", pedidoId);
    return json({ ok: true, pedido_id: pedidoId, archivos_borrados: archivosBorrados });
  }

  // ---------- MODO BORRADO (solo pedidos de prueba) ----------
  if (url.searchParams.get("delete") === "1") {
    if (req.method !== "POST") return json({ error: "El borrado requiere POST." }, 405);
    const pedidoId = url.searchParams.get("pedido_id") || "";
    if (!pedidoId) return json({ error: "Falta pedido_id." }, 400);

    const { data: row, error: errRow } = await client
      .from("pedidos").select("*").eq("pedido_id", pedidoId).maybeSingle();
    if (errRow) return json({ error: "Error buscando el pedido: " + errRow.message }, 500);
    if (!row) return json({ error: "Pedido no encontrado." }, 404);

    // CANDADO: jamás borrar un pedido real desde aquí, aunque se tenga el secreto.
    if (!esCorreoPrueba(row.correo)) {
      return json({ error: "Por seguridad, solo se pueden borrar pedidos de PRUEBA (correo que empiece por 'prueba'). Este pedido es real." }, 403);
    }

    let archivosBorrados = 0;
    if (row.carpeta_storage) {
      try { archivosBorrados = await borrarCarpeta(client, BUCKET_APUNTES, row.carpeta_storage); }
      catch (_e) { /* si falla el storage, igual seguimos borrando los registros */ }
    }
    await client.from("pedido_intake").delete().eq("pedido_id", pedidoId);
    const { error: errDel } = await client.from("pedidos").delete().eq("pedido_id", pedidoId);
    if (errDel) return json({ error: "Error borrando el pedido: " + errDel.message }, 500);

    return json({ ok: true, pedido_id: pedidoId, archivos_borrados: archivosBorrados });
  }

  // ---------- MODO LECTURA (informe) ----------
  if (req.method !== "GET") return json({ error: "Usa GET." }, 405);

  // Capacidad de Storage (bucket "apuntes")
  const uso = await sumarBucket(client, BUCKET_APUNTES);
  const storage = {
    bytesUsados: uso.bytes,
    archivos: uso.archivos,
    limiteBytes: LIMITE_STORAGE_BYTES,
    porcentaje: Math.round((uso.bytes / LIMITE_STORAGE_BYTES) * 1000) / 10,
  };

  // Pedidos
  const { data: pedidosRaw, error: errPedidos } = await client
    .from("pedidos").select("*")
    .order("fecha_compra", { ascending: false })
    .limit(LIMITE_PEDIDOS);
  if (errPedidos) return json({ error: "Error leyendo pedidos: " + errPedidos.message }, 500);

  // Cuestionario (intake): traemos y armamos un índice por pedido_id
  // (nos quedamos con el más reciente si hubiera más de uno).
  const { data: intakeRaw } = await client
    .from("pedido_intake").select("*")
    .order("creado", { ascending: false })
    .limit(LIMITE_PEDIDOS * 2);
  const intakePorPedido: Record<string, any> = {};
  for (const it of (intakeRaw || [])) {
    if (!intakePorPedido[it.pedido_id]) intakePorPedido[it.pedido_id] = it;
  }

  const ahora = Date.now();
  const pedidos = (pedidosRaw || []).map((p: any) => {
    const horasDesdeCompra = p.fecha_compra ? (ahora - new Date(p.fecha_compra).getTime()) / 3_600_000 : 0;
    const it = intakePorPedido[p.pedido_id] || null;
    return {
      ...p,
      es_prueba: esCorreoPrueba(p.correo),
      alerta_pendiente: !p.guia_entregada && horasDesdeCompra >= HORAS_ALERTA,
      horas_desde_compra: Math.round(horasDesdeCompra),
      intake: it ? { uso: it.uso, cuesta: it.cuesta, extra: it.extra } : null,
    };
  });

  // Resumen de ventas (15 y 30 días). EXCLUYE los pedidos de prueba:
  // el tablero debe reflejar ventas REALES, no ruido de pruebas.
  function resumen(dias: number) {
    const desde = ahora - dias * 86_400_000;
    const enRango = (pedidosRaw || []).filter((p: any) =>
      p.fecha_compra &&
      new Date(p.fecha_compra).getTime() >= desde &&
      !esCorreoPrueba(p.correo)
    );
    const porPlan: Record<string, number> = {};
    let ingreso = 0;
    for (const p of enRango) {
      const plan = p.plan || "(sin plan)";
      porPlan[plan] = (porPlan[plan] || 0) + 1;
      ingreso += PRECIOS[plan] ?? 0;
    }
    return { dias, total: enRango.length, porPlan, ingresoEstimadoUSD: ingreso };
  }

  const ventas = { ultimos15: resumen(15), ultimos30: resumen(30) };
  const pedidosPrueba = (pedidosRaw || []).filter((p: any) => esCorreoPrueba(p.correo)).length;

  return json({ storage, pedidos, ventas, pedidosPrueba, generadoEn: new Date().toISOString() });
});
