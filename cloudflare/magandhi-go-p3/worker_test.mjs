// MAGANDHI · Promocionar P3 · banco aislado del Worker de go.magandhi.com.
// Ejecutar: node --experimental-vm-modules cloudflare/magandhi-go-p3/worker_test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import { pathToFileURL } from 'node:url';

const REPO = process.env.REPO || '/projects/sandbox/12344-ux.github.io';
const RUTA_WORKER = `${REPO}/cloudflare/magandhi-go-p3/worker.js`;
const ORIGEN_EDGE =
  'https://bxlzipwxyxdtffnuizbz.supabase.co/functions/v1/enlace-promocional';

let total = 0;
let fallan = 0;

async function prueba(nombre, ejecutar) {
  total += 1;
  try {
    await ejecutar();
    console.log(`pasa · ${nombre}`);
  } catch (error) {
    fallan += 1;
    console.error(`FALLA · ${nombre}`);
    console.error(error instanceof Error ? error.stack : error);
  }
}

async function cargarWorker(responder) {
  const llamadas = [];
  const contexto = vm.createContext({
    URL,
    Headers,
    Request,
    Response,
    fetch: async (url, opciones) => {
      llamadas.push({ url: String(url), opciones });
      return await responder(url, opciones);
    },
  });
  const modulo = new vm.SourceTextModule(fs.readFileSync(RUTA_WORKER, 'utf8'), {
    context: contexto,
    identifier: pathToFileURL(RUTA_WORKER).href,
  });
  await modulo.link(() => {
    throw new Error('El Worker no debe importar módulos ni abrir otra salida.');
  });
  await modulo.evaluate();
  return { worker: modulo.namespace.default, llamadas };
}

await prueba('fija el origen y conserva la query sin obedecer un destino inyectado', async () => {
  const cargado = await cargarWorker(async () => new Response(null, { status: 204 }));
  const query = '?url=https%3A%2F%2Fevil.invalid%2F&next=%2Fafuera&pieza=a%20b';
  await cargado.worker.fetch(new Request(`https://atacante.invalid/0123456789abcdef${query}`));

  assert.equal(cargado.llamadas.length, 1);
  assert.equal(
    cargado.llamadas[0].url,
    `${ORIGEN_EDGE}/0123456789abcdef${query}`,
  );
  assert.equal(new URL(cargado.llamadas[0].url).origin, new URL(ORIGEN_EDGE).origin);
});

await prueba('envía solo la lista blanca y reemplaza x-real-ip con CF-Connecting-IP', async () => {
  const cargado = await cargarWorker(async () => new Response(null, { status: 204 }));
  const permitidas = {
    accept: 'text/html',
    'accept-language': 'es-CO',
    'user-agent': 'Navegador de prueba',
    purpose: 'navigate',
    'sec-purpose': 'navigate',
    'sec-fetch-mode': 'navigate',
    'sec-fetch-dest': 'document',
    'sec-fetch-site': 'none',
    origin: 'https://go.magandhi.com',
    'access-control-request-method': 'GET',
    'access-control-request-headers': 'accept',
  };
  const request = new Request('https://go.magandhi.com/0123456789abcdef', {
    headers: {
      ...permitidas,
      'cf-connecting-ip': '203.0.113.7',
      'x-real-ip': '198.51.100.99',
      'x-forwarded-for': '198.51.100.98',
      authorization: 'Bearer no-reenviar',
      cookie: 'sesion=no-reenviar',
      host: 'evil.invalid',
    },
  });
  await cargado.worker.fetch(request);

  const headers = cargado.llamadas[0].opciones.headers;
  for (const [nombre, valor] of Object.entries(permitidas)) {
    assert.equal(headers.get(nombre), valor, nombre);
  }
  assert.equal(headers.get('x-real-ip'), '203.0.113.7');
  for (const nombre of ['cf-connecting-ip', 'x-forwarded-for', 'authorization', 'cookie', 'host']) {
    assert.equal(headers.get(nombre), null, nombre);
  }
});

await prueba('no acepta x-real-ip del visitante cuando falta la IP de Cloudflare', async () => {
  const cargado = await cargarWorker(async () => new Response(null, { status: 204 }));
  await cargado.worker.fetch(new Request('https://go.magandhi.com/0123456789abcdef', {
    headers: { 'x-real-ip': '198.51.100.99', 'x-forwarded-for': '198.51.100.98' },
  }));
  assert.equal(cargado.llamadas[0].opciones.headers.get('x-real-ip'), null);
});

await prueba('entrega el 302 manual sin cuerpo, cookies ni caché', async () => {
  const cargado = await cargarWorker(async () => new Response('cuerpo que no debe salir', {
    status: 302,
    statusText: 'Found',
    headers: {
      location: 'https://magandhi.com/producto/jabon-avena/',
      'set-cookie': 'sesion=no',
      'set-cookie2': 'legado=no',
      'cache-control': 'public, max-age=3600',
      'content-length': '23',
      'content-encoding': 'gzip',
      'x-edge-controlado': 'si',
    },
  }));
  const respuesta = await cargado.worker.fetch(
    new Request('https://go.magandhi.com/0123456789abcdef'),
  );

  assert.equal(cargado.llamadas.length, 1, 'no sigue el redirect');
  assert.equal(cargado.llamadas[0].opciones.redirect, 'manual');
  assert.equal(cargado.llamadas[0].opciones.cache, 'no-store');
  assert.equal(respuesta.status, 302);
  assert.equal(respuesta.statusText, 'Found');
  assert.equal(respuesta.headers.get('location'), 'https://magandhi.com/producto/jabon-avena/');
  assert.equal(respuesta.headers.get('set-cookie'), null);
  assert.equal(respuesta.headers.get('set-cookie2'), null);
  assert.equal(respuesta.headers.get('cache-control'), 'no-store');
  assert.equal(respuesta.headers.get('content-length'), null);
  assert.equal(respuesta.headers.get('content-encoding'), null);
  assert.equal(respuesta.headers.get('referrer-policy'), 'no-referrer');
  assert.equal(respuesta.headers.get('x-content-type-options'), 'nosniff');
  assert.equal(await respuesta.text(), '');
});

await prueba('reenvía GET, HEAD y OPTIONS con su método y suprime cuerpos prohibidos', async () => {
  const cargado = await cargarWorker(async (_url, opciones) => {
    if (opciones.method === 'OPTIONS') return new Response(null, { status: 204 });
    return new Response('respuesta Edge', { status: 200 });
  });

  for (const metodo of ['GET', 'HEAD', 'OPTIONS']) {
    const respuesta = await cargado.worker.fetch(
      new Request('https://go.magandhi.com/0123456789abcdef', { method: metodo }),
    );
    assert.equal(cargado.llamadas.at(-1).opciones.method, metodo);
    if (metodo !== 'GET') assert.equal(await respuesta.text(), '');
  }
  assert.deepEqual(cargado.llamadas.map((x) => x.opciones.method), ['GET', 'HEAD', 'OPTIONS']);
});

await prueba('rechaza otros métodos antes de fetch', async () => {
  const cargado = await cargarWorker(async () => {
    throw new Error('No debía llamar fetch');
  });

  for (const metodo of ['POST', 'PUT', 'PATCH', 'DELETE']) {
    const respuesta = await cargado.worker.fetch(
      new Request('https://go.magandhi.com/0123456789abcdef', { method: metodo }),
    );
    assert.equal(respuesta.status, 405, metodo);
    assert.equal(respuesta.headers.get('allow'), 'GET, HEAD, OPTIONS');
    assert.equal(respuesta.headers.get('cache-control'), 'no-store');
    assert.equal(await respuesta.text(), '');
  }
  assert.equal(cargado.llamadas.length, 0);
});

await prueba('falla cerrada si el único origen no responde', async () => {
  const cargado = await cargarWorker(async () => {
    throw new Error('red simulada caída');
  });
  const respuesta = await cargado.worker.fetch(
    new Request('https://go.magandhi.com/0123456789abcdef'),
  );

  assert.equal(cargado.llamadas.length, 1);
  assert.equal(respuesta.status, 503);
  assert.equal(respuesta.headers.get('location'), null);
  assert.equal(respuesta.headers.get('cache-control'), 'no-store');
  assert.equal(respuesta.headers.get('referrer-policy'), 'no-referrer');
  assert.equal(respuesta.headers.get('x-content-type-options'), 'nosniff');
  assert.equal(await respuesta.text(), '');
});

console.log(`RESUMEN P3 Worker | ${total} comprobaciones · ${fallan} fallan`);
process.exitCode = fallan === 0 ? 0 : 1;
