// MAGANDHI · Promocionar P2 · reglas puras de canales, UTM y copys.
// Este módulo no lee Supabase, no persiste datos y no registra actividad.

export const ORIGEN_TIENDA = 'https://magandhi.com';
const SLUG_RE = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

export const CANALES = Object.freeze({
  whatsapp: { etiqueta: 'WhatsApp', detalle: 'Conversación directa', source: 'whatsapp', medium: 'mensajeria' },
  instagram: { etiqueta: 'Instagram', detalle: 'Publicación o historia', source: 'instagram', medium: 'social' },
  facebook: { etiqueta: 'Facebook', detalle: 'Publicación de la página', source: 'facebook', medium: 'social' },
  email: { etiqueta: 'Email', detalle: 'Mensaje o boletín', source: 'email', medium: 'email' },
  qr: { etiqueta: 'Código QR', detalle: 'Pieza física o impresa', source: 'qr', medium: 'offline' },
  anuncio_manual: { etiqueta: 'Anuncio manual', detalle: 'Pauta cargada manualmente', source: 'anuncio-manual', medium: 'paid-manual' },
  otro_controlado: { etiqueta: 'Otro controlado', detalle: 'Colocación identificada', source: 'otro-controlado', medium: 'referral' },
});

export const FORMATOS = Object.freeze({
  cuadrado: { etiqueta: 'Cuadrado', corto: 'Feed', ancho: 1080, alto: 1080 },
  historia: { etiqueta: 'Historia', corto: 'Story', ancho: 1080, alto: 1920 },
  horizontal: { etiqueta: 'Horizontal', corto: 'Enlace', ancho: 1200, alto: 628 },
});

const LIMITES = Object.freeze({ source: 32, medium: 32, campaign: 60, content: 60 });

export function normalizarUtm(valor, limite = 60) {
  return String(valor ?? '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '')
    .slice(0, Math.max(1, limite))
    .replace(/-$/g, '');
}

export function fechaColombia(fecha = new Date()) {
  const partes = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Bogota', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(fecha).reduce((acc, item) => ({ ...acc, [item.type]: item.value }), {});
  return `${String(partes.year).slice(-2)}${partes.month}${partes.day}`;
}

function sufijoAleatorio() {
  const alfabeto = '0123456789abcdefghjkmnpqrstvwxyz';
  const bytes = new Uint8Array(3);
  globalThis.crypto?.getRandomValues?.(bytes);
  if (!bytes[0] && !bytes[1] && !bytes[2]) {
    const fallback = Math.floor(Math.random() * 1048576);
    bytes[0] = fallback >> 16;
    bytes[1] = (fallback >> 8) & 255;
    bytes[2] = fallback & 255;
  }
  let valor = ((bytes[0] << 16) | (bytes[1] << 8) | bytes[2]) & 0xfffff;
  let salida = '';
  for (let i = 0; i < 4; i += 1) {
    salida = alfabeto[valor & 31] + salida;
    valor >>>= 5;
  }
  return salida;
}

export function crearCampaign(base, fecha = new Date()) {
  const nombre = normalizarUtm(base, 48) || 'producto';
  return normalizarUtm(`${nombre}-${fechaColombia(fecha)}-${sufijoAleatorio()}`, LIMITES.campaign);
}

export function canonicalProducto(slug) {
  const limpio = String(slug ?? '').trim().toLowerCase();
  if (!SLUG_RE.test(limpio)) throw new Error('La campaña no tiene un slug válido para construir su ficha oficial.');
  return `${ORIGEN_TIENDA}/producto/${limpio}/`;
}

export function contentInicial(canal, formato) {
  if (!CANALES[canal] || !FORMATOS[formato]) throw new Error('Canal o formato no reconocido.');
  return normalizarUtm(`${canal}-${formato}`, LIMITES.content);
}

export function crearUrlUtm(canonical, valores) {
  const destino = new URL(canonical);
  if (destino.origin !== ORIGEN_TIENDA || !destino.pathname.startsWith('/producto/')) {
    throw new Error('El destino promocional debe pertenecer a una ficha de producto de MAGANDHI.');
  }
  const canal = CANALES[valores.canal];
  if (!canal) throw new Error('Selecciona un canal controlado.');
  const campaign = normalizarUtm(valores.campaign, LIMITES.campaign);
  const content = normalizarUtm(valores.content, LIMITES.content);
  if (!campaign || !content) throw new Error('Campaña y pieza deben tener un identificador descriptivo.');
  destino.search = '';
  destino.searchParams.set('utm_source', normalizarUtm(canal.source, LIMITES.source));
  destino.searchParams.set('utm_medium', normalizarUtm(canal.medium, LIMITES.medium));
  destino.searchParams.set('utm_campaign', campaign);
  destino.searchParams.set('utm_content', content);
  return destino.toString();
}

function textoBase(producto) {
  return String(producto.hook_largo || producto.caracteristica_adicional || producto.detalle_presentacion || '')
    .replace(/\s+/g, ' ')
    .trim();
}

export function textoPiezaInicial(producto) {
  return textoBase(producto) || 'Una elección preparada con cuidado por el equipo de MAGANDHI.';
}

export function textoInicial(producto, canal) {
  const nombre = String(producto.nombre || 'Producto MAGANDHI').trim();
  const propuesta = textoPiezaInicial(producto);
  const textos = {
    whatsapp: `${nombre}\n\n${propuesta}\n\nConócelo en MAGANDHI:`,
    instagram: `${nombre}\n\n${propuesta}\n\nDescúbrelo en MAGANDHI.`,
    facebook: `${nombre}\n\n${propuesta}\n\nMira todos los detalles en MAGANDHI:`,
    email: `${nombre}\n\n${propuesta}\n\nConoce la selección completa en MAGANDHI:`,
    qr: `${nombre}\n\n${propuesta}\n\nEscanea y conoce más.`,
    anuncio_manual: `${nombre}\n\n${propuesta}\n\nDescúbrelo en MAGANDHI.`,
    otro_controlado: `${nombre}\n\n${propuesta}\n\nConoce más en MAGANDHI:`,
  };
  return textos[canal] || textos.otro_controlado;
}

export function textoParaCompartir(texto, url) {
  const limpio = String(texto || '').trim();
  return `${limpio}${limpio ? '\n\n' : ''}${url}`;
}

export function parecePII(valor) {
  const texto = String(valor || '').trim();
  const normalizado = normalizarUtm(texto, 200);
  return /[\w.+-]+@[\w.-]+\.[a-z]{2,}/i.test(texto) ||
    /(?:\+?57\s*)?(?:3\d{2})[\s.-]?\d{3}[\s.-]?\d{4}/.test(texto) ||
    /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i.test(texto) ||
    /(?:gmail|hotmail|outlook|yahoo)-com/.test(normalizado) ||
    /(?:^|-)(?:audiencia|segmento|persona|contacto)(?:-|$)/.test(normalizado) ||
    /(?:cliente|customer|usuario|audiencia|segmento|telefono|celular|correo|email|uid|uuid)-?(?:id|[0-9])/.test(normalizado) ||
    /\d{9,}/.test(normalizado.replace(/-/g, ''));
}

export function nombreArchivo(producto, formato, canal) {
  const slug = normalizarUtm(producto.slug || producto.nombre, 80) || 'producto';
  const formatoSeguro = FORMATOS[formato] ? formato : 'pieza';
  const canalSeguro = CANALES[canal] ? normalizarUtm(canal, 32) : 'canal';
  return `magandhi-${slug}-${canalSeguro}-${formatoSeguro}.png`;
}
