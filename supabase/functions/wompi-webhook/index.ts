// ============================================================
// Stramont · Wompi — Webhook de eventos (confirmación de pago server-side)
//
// Wompi hace POST aquí cuando una transacción llega a estado final. Esta
// función es la ÚNICA fuente de verdad del "pagado": no confía en nada del
// navegador (no falsificable), aunque el cliente cierre la pestaña.
//
// SEGURIDAD (fail-closed): verifica la firma del evento (checksum) con el
// SECRETO DE EVENTOS de Wompi. Algoritmo oficial:
//   checksum = SHA256( <valores de signature.properties en orden> +
//                      <timestamp> + <WOMPI_EVENTS_SECRET> )
// Si el checksum no coincide -> 401 y se ignora (nadie puede simular un
// "APPROVED"). Las properties se leen DINÁMICAMENTE del evento (pueden variar).
//
// Al APROBARSE:
//   - marca el pedido: estado_pago='aprobado', wompi_transaction_id, monto,
//     moneda, pagado_en.  (Idempotente: si ya estaba aprobado, no repite.)
//   - dispara el Correo 1 (función "correo-confirmacion", idempotente) que
//     además incluye el Kit y sirve de comprobante por correo.
//
// Verify JWT: OFF (Wompi no manda JWT; la autenticidad la da el checksum).
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function resp(status: number, body: unknown = { ok: true }) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

async function sha256Hex(texto: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(texto));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function sb() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

// Navega un objeto por una ruta con puntos: "transaction.id" -> data.transaction.id
function porRuta(obj: any, ruta: string): unknown {
  return ruta.split(".").reduce((o, k) => (o == null ? undefined : o[k]), obj);
}

Deno.serve(async (req) => {
  const url = new URL(req.url);

  // Autoprueba del motor SHA-256 (hex) con un vector OFICIAL de Wompi (el de la
  // firma de integridad, que sí es reproducible). Confirma que el hashing es
  // correcto; la verificación real del webhook aplica el MISMO SHA-256 sobre
  // (signature.properties + timestamp + WOMPI_EVENTS_SECRET) de cada evento.
  // (Nota: el hash de ejemplo del apartado "eventos" en la doc de Wompi NO es
  // reproducible —es un valor mal impreso en su documentación—, por eso NO se
  // usa como vector de prueba.)
  //   GET ?selftest=1
  if (req.method === "GET" && url.searchParams.get("selftest") === "1") {
    const calc = await sha256Hex("sk8-438k4-xmxm392-sn2m2490000COPprod_integrity_Z5mMke9x0k8gpErbDqwrJXMqsI6SFli6");
    const ok = calc === "37c8407747e595535433ef8f6a811d853cd943046624a0ec04662b17bbf33bf5";
    return resp(200, {
      ok,
      nota: "Verifica el motor SHA-256. La autenticacion real usa signature.properties + timestamp + WOMPI_EVENTS_SECRET sobre cada evento.",
    });
  }

  if (req.method !== "POST") return resp(405, { error: "Usa POST." });

  const EVENTS_SECRET = Deno.env.get("WOMPI_EVENTS_SECRET");
  if (!EVENTS_SECRET) return resp(500, { error: "Falta configurar WOMPI_EVENTS_SECRET." });

  let evento: any;
  try { evento = await req.json(); } catch { return resp(400, { error: "JSON inválido." }); }

  const firma = evento?.signature;
  const props: string[] = Array.isArray(firma?.properties) ? firma.properties : [];
  const checksumRecibido = String(firma?.checksum || req.headers.get("x-event-checksum") || "");
  const timestamp = evento?.timestamp;
  if (!props.length || !checksumRecibido || timestamp === undefined) {
    return resp(400, { error: "Evento sin firma/propiedades/timestamp." });
  }

  // Reconstruir la cadena: valores de las properties (en orden) + timestamp + secreto.
  let cadena = "";
  for (const p of props) {
    const v = porRuta(evento?.data, p);
    cadena += (v === null || v === undefined) ? "" : String(v);
  }
  cadena += String(timestamp) + EVENTS_SECRET;
  const checksumCalc = await sha256Hex(cadena);

  // FAIL-CLOSED: si no coincide, se rechaza. Nadie puede simular un pago.
  if (checksumCalc.toLowerCase() !== checksumRecibido.toLowerCase()) {
    return resp(401, { error: "Firma inválida." });
  }

  // Solo nos interesan transacciones. Otros eventos se aceptan (200) sin hacer nada.
  const tx = evento?.data?.transaction;
  if (!tx || evento?.event !== "transaction.updated") return resp(200, { ok: true, ignorado: true });

  const estado = String(tx.status || "");
  const referencia = String(tx.reference || "").trim(); // = pedido_id
  const txId = String(tx.id || "").trim();

  const client = sb();

  // Si NO está aprobada, hay DOS situaciones distintas (ojo, no son lo mismo):
  //
  //  (1) PRIMER estado final y NO fue aprobado (el pedido sigue 'pendiente'):
  //      es un rechazo/error normal. Se registra sin disparar correos. El
  //      filtro .eq('estado_pago','pendiente') evita que un evento fuera de
  //      orden pise un pago que ya quedó bueno.
  //
  //  (2) REVERSA de un pago YA APROBADO (anulación/reembolso/contracargo): la
  //      MISMA transacción que se aprobó llega ahora como VOIDED/ERROR. Antes
  //      esto se IGNORABA en silencio (el filtro 'pendiente' no lo tocaba), así
  //      que un pago devuelto seguía contando como venta y entregable. Ahora se
  //      degrada a 'reversado' para que (a) deje de contar como venta/cliente y
  //      (b) quede VISIBLE en el tablero con alerta (el dueño pudo haber
  //      entregado ya y debe revocar el acceso). El match por txId garantiza
  //      que solo la transacción aprobada puede revertir su propio pago (un
  //      evento viejo de otro intento no puede tumbar el pago bueno).
  if (estado !== "APPROVED") {
    if (referencia) {
      const { data: cur } = await client
        .from("pedidos").select("estado_pago, wompi_transaction_id")
        .eq("pedido_id", referencia).maybeSingle();
      if (cur) {
        if (cur.estado_pago === "pendiente") {
          await client.from("pedidos")
            .update({ estado_pago: estado === "DECLINED" || estado === "VOIDED" ? "rechazado" : "error", wompi_transaction_id: txId })
            .eq("pedido_id", referencia).eq("estado_pago", "pendiente");
        } else if (
          cur.estado_pago === "aprobado" &&
          (estado === "VOIDED" || estado === "ERROR") &&
          txId && txId === cur.wompi_transaction_id
        ) {
          await client.from("pedidos")
            .update({ estado_pago: "reversado" })
            .eq("pedido_id", referencia).eq("estado_pago", "aprobado");
          return resp(200, { ok: true, estado, reversado: true });
        }
      }
    }
    return resp(200, { ok: true, estado });
  }

  if (!referencia) return resp(200, { ok: true, sinReferencia: true });

  const { data: pedido, error: errRow } = await client
    .from("pedidos").select("pedido_id, estado_pago, correo").eq("pedido_id", referencia).maybeSingle();
  if (errRow) return resp(500, { error: "Error leyendo el pedido: " + errRow.message });
  if (!pedido) return resp(200, { ok: true, pedidoNoEncontrado: true }); // 200 para que Wompi no reintente en bucle

  // IDEMPOTENCIA: si ya estaba aprobado, no repetir nada (Wompi puede reenviar el evento).
  if (pedido.estado_pago === "aprobado") return resp(200, { ok: true, yaAprobado: true });

  const { error: errUpd } = await client.from("pedidos").update({
    estado_pago: "aprobado",
    wompi_transaction_id: txId,
    monto_cents: tx.amount_in_cents ?? null,
    moneda: tx.currency ?? null,
    pagado_en: new Date().toISOString(),
  }).eq("pedido_id", referencia);
  if (errUpd) return resp(500, { error: "Error actualizando el pedido: " + errUpd.message });

  // Dispara el Correo 1 (idempotente por correo_confirmacion_enviado). Incluye el
  // Kit y sirve de comprobante por correo. No bloquea el 200 si el correo falla
  // (es idempotente: un reintento de Wompi o el tablero lo pueden re-disparar).
  try {
    const base = Deno.env.get("SUPABASE_URL");
    await fetch(`${base}/functions/v1/correo-confirmacion`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ pedido_id: referencia }),
    });
  } catch (_e) { /* no bloqueante */ }

  return resp(200, { ok: true, pedido_id: referencia, aprobado: true });
});
