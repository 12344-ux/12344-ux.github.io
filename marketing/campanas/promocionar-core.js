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

// ------------------------------------------------------------
// IDENTIDAD EDITORIAL MAGANDHI
// ------------------------------------------------------------

export const PALETA_MARCA = Object.freeze({
  negro: { etiqueta: 'Negro MAGANDHI', hex: '#111111', oscuro: true },
  terracota: { etiqueta: 'Terracota', hex: '#A6332E', oscuro: true },
  terracotaOscuro: { etiqueta: 'Terracota profundo', hex: '#5C1F1C', oscuro: true },
  dorado: { etiqueta: 'Dorado', hex: '#C28A3A', oscuro: false },
  crema: { etiqueta: 'Crema', hex: '#FAF6F1', oscuro: false },
  arena: { etiqueta: 'Arena', hex: '#EFE7DD', oscuro: false },
  blanco: { etiqueta: 'Blanco', hex: '#FFFFFF', oscuro: false },
  gris: { etiqueta: 'Gris cálido', hex: '#6B6660', oscuro: true },
});

export const PRESETS_MARCA = Object.freeze({
  terracota: {
    etiqueta: 'Terracota editorial', detalle: 'Cercanía e identidad de marca',
    superficie: 'terracota', panel: 'crema', pretitulo: 'terracota', titulo: 'negro',
    descripcion: 'gris', acento: 'dorado', botonFondo: 'terracota', botonTexto: 'blanco',
  },
  negro: {
    etiqueta: 'Negro curaduría', detalle: 'Selección boutique y sobria',
    superficie: 'negro', panel: 'crema', pretitulo: 'terracota', titulo: 'negro',
    descripcion: 'gris', acento: 'dorado', botonFondo: 'terracota', botonTexto: 'blanco',
  },
  negro_dorado: {
    etiqueta: 'Negro + dorado', detalle: 'Edición especial y protagonista',
    superficie: 'negro_dorado', panel: 'negro', pretitulo: 'dorado', titulo: 'blanco',
    descripcion: 'crema', acento: 'dorado', botonFondo: 'dorado', botonTexto: 'negro',
  },
});

export function colorMarca(clave) {
  const color = PALETA_MARCA[clave];
  if (!color) throw new Error('Se intentó usar un color ajeno a la paleta MAGANDHI.');
  return color.hex;
}

export function resolverTema(valores) {
  const preset = PRESETS_MARCA[valores?.preset] || PRESETS_MARCA.negro;
  const claves = {
    superficie: valores?.superficie || preset.superficie,
    panel: valores?.panel || preset.panel,
    pretitulo: valores?.pretitulo || preset.pretitulo,
    titulo: valores?.titulo || preset.titulo,
    descripcion: valores?.descripcion || preset.descripcion,
    acento: valores?.acento || preset.acento,
    botonFondo: valores?.botonFondo || preset.botonFondo,
    botonTexto: valores?.botonTexto || preset.botonTexto,
  };
  const superficie = {
    terracota: { inicio: '#79211F', fin: colorMarca('terracota'), textoMarca: colorMarca('blanco') },
    negro: { inicio: colorMarca('negro'), fin: '#1D1D1D', textoMarca: colorMarca('blanco') },
    negro_dorado: { inicio: colorMarca('negro'), fin: colorMarca('dorado'), textoMarca: colorMarca('blanco') },
  }[claves.superficie];
  if (!superficie) throw new Error('Selecciona una superficie aprobada de MAGANDHI.');
  return {
    claves,
    superficieInicio: superficie.inicio,
    superficieFin: superficie.fin,
    marcaTexto: superficie.textoMarca,
    pieTexto: claves.superficie === 'negro_dorado' ? colorMarca('negro') : superficie.textoMarca,
    panel: colorMarca(claves.panel),
    pretitulo: colorMarca(claves.pretitulo),
    titulo: colorMarca(claves.titulo),
    descripcion: colorMarca(claves.descripcion),
    acento: colorMarca(claves.acento),
    botonFondo: colorMarca(claves.botonFondo),
    botonTexto: colorMarca(claves.botonTexto),
    qrFondo: colorMarca('blanco'),
    qrTinta: colorMarca('negro'),
  };
}

function luminancia(hex) {
  const limpio = String(hex).replace('#', '');
  const canales = [0, 2, 4].map((i) => parseInt(limpio.slice(i, i + 2), 16) / 255)
    .map((c) => c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
  return canales[0] * 0.2126 + canales[1] * 0.7152 + canales[2] * 0.0722;
}

export function contraste(colA, colB) {
  const a = luminancia(colA);
  const b = luminancia(colB);
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}

export function validarTema(tema) {
  const revisiones = [
    ['El pretítulo', tema.pretitulo, tema.panel, 4.5],
    ['El título', tema.titulo, tema.panel, 3],
    ['La descripción', tema.descripcion, tema.panel, 4.5],
    ['El botón', tema.botonTexto, tema.botonFondo, 4.5],
  ];
  return revisiones.flatMap(([nombre, frente, fondo, minimo]) => {
    const ratio = contraste(frente, fondo);
    return ratio >= minimo ? [] : [`${nombre} necesita más contraste (${ratio.toFixed(1)}:1; mínimo ${minimo}:1).`];
  });
}

// Reglas editoriales comunes para cualquier texto que pueda salir del estudio.
// La revisión humana sigue siendo necesaria para nombres o referencias que una
// expresión regular no puede interpretar con contexto.
export function validarTextoPromocional(valor, campo = 'El contenido') {
  const texto = String(valor || '').trim();
  const errores = [];
  if (/(?:https?:\/\/|www\.|\b[a-z0-9-]+\.(?:com|co|net|org|io)\b)/i.test(texto)) {
    errores.push(`${campo} no debe incluir otra URL; el sistema agrega el enlace protegido.`);
  }
  if (parecePII(texto)) errores.push(`${campo} parece contener datos personales o una audiencia identificable.`);
  if (/(?:\$|\bCOP\b|\bprecio\b|\bdescuento\b|\bstock\b|\bproveedor\b|\bcosto\b|\bDropi\b|\d+\s*%|\búltimas?\s+\d+|\b\d+\s+unidades?\b)/i.test(texto)) {
    errores.push(`${campo} no debe congelar precio, descuento, stock, proveedor o costo.`);
  }
  return errores;
}
