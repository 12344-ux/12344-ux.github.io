// MAGANDHI · Promocionar P2 · renderer local de piezas y QR.
// Las tres geometrías son fijas; contenido, imagen y roles de marca son editables.

import { FORMATOS } from './promocionar-core.js?v=p2-3';

const NEGRO = '#111111';
const BLANCO = '#FFFFFF';
const CREMA = '#FAF6F1';
const TERRACOTA = '#A6332E';

function rutaRedondeada(ctx, x, y, ancho, alto, radio) {
  const r = Math.min(radio, ancho / 2, alto / 2);
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + ancho, y, x + ancho, y + alto, r);
  ctx.arcTo(x + ancho, y + alto, x, y + alto, r);
  ctx.arcTo(x, y + alto, x, y, r);
  ctx.arcTo(x, y, x + ancho, y, r);
  ctx.closePath();
}

function rectRedondeado(ctx, x, y, ancho, alto, radio, relleno) {
  rutaRedondeada(ctx, x, y, ancho, alto, radio);
  ctx.fillStyle = relleno;
  ctx.fill();
}

function cargarImagen(url) {
  if (!url) return Promise.resolve(null);
  return new Promise((resolve) => {
    const imagen = new Image();
    imagen.crossOrigin = url.startsWith('blob:') ? null : 'anonymous';
    imagen.decoding = 'async';
    imagen.onload = () => resolve(imagen);
    imagen.onerror = () => resolve(null);
    imagen.src = url;
  });
}

function gradienteSuperficie(ctx, tema, x, y, ancho, alto, vertical = false) {
  const gradiente = ctx.createLinearGradient(x, y, vertical ? x : x + ancho, vertical ? y + alto : y);
  gradiente.addColorStop(0, tema.superficieInicio);
  gradiente.addColorStop(1, tema.superficieFin);
  return gradiente;
}

function dibujarFondoMarca(ctx, tema, x, y, ancho, alto) {
  ctx.fillStyle = gradienteSuperficie(ctx, tema, x, y, ancho, alto, alto > ancho);
  ctx.fillRect(x, y, ancho, alto);
  ctx.save();
  ctx.globalAlpha = .12;
  ctx.fillStyle = tema.acento;
  ctx.beginPath(); ctx.arc(x + ancho * .82, y + alto * .18, ancho * .28, 0, Math.PI * 2); ctx.fill();
  ctx.fillStyle = CREMA;
  ctx.beginPath(); ctx.arc(x + ancho * .1, y + alto * .9, ancho * .34, 0, Math.PI * 2); ctx.fill();
  ctx.restore();
}

function dibujarImagen(ctx, imagen, caja, ajustes, tema) {
  const { x, y, ancho, alto } = caja;
  if (!imagen) {
    dibujarFondoMarca(ctx, tema, x, y, ancho, alto);
    return;
  }
  const modo = ajustes?.modo === 'contain' ? 'contain' : 'cover';
  const focoX = Math.max(0, Math.min(100, Number(ajustes?.focoX) || 50)) / 100;
  const focoY = Math.max(0, Math.min(100, Number(ajustes?.focoY) || 50)) / 100;
  const zoom = Math.max(1, Math.min(1.8, (Number(ajustes?.zoom) || 100) / 100));
  const base = modo === 'contain'
    ? Math.min(ancho / imagen.naturalWidth, alto / imagen.naturalHeight)
    : Math.max(ancho / imagen.naturalWidth, alto / imagen.naturalHeight);
  const escala = base * zoom;
  const w = imagen.naturalWidth * escala;
  const h = imagen.naturalHeight * escala;
  const dx = x + (ancho - w) * focoX;
  const dy = y + (alto - h) * focoY;

  ctx.save();
  ctx.beginPath(); ctx.rect(x, y, ancho, alto); ctx.clip();
  if (modo === 'contain') {
    ctx.fillStyle = BLANCO;
    ctx.fillRect(x, y, ancho, alto);
  } else {
    ctx.fillStyle = gradienteSuperficie(ctx, tema, x, y, ancho, alto);
    ctx.fillRect(x, y, ancho, alto);
  }
  ctx.drawImage(imagen, dx, dy, w, h);
  if (modo === 'cover') {
    ctx.globalAlpha = .11;
    ctx.fillStyle = tema.superficieFin;
    ctx.fillRect(x, y, ancho, alto);
    ctx.globalAlpha = 1;
  }
  ctx.restore();
}

function fuente(ctx, peso, tamano) {
  ctx.font = `${peso} ${tamano}px Poppins, Arial, sans-serif`;
}

function resolverLineas(ctx, texto, anchoMax, maxLineas) {
  const completo = String(texto || '').replace(/\s+/g, ' ').trim();
  const palabras = completo.split(' ').filter(Boolean);
  const salida = [];
  let actual = '';
  let consumidas = 0;
  for (const palabra of palabras) {
    const candidato = actual ? `${actual} ${palabra}` : palabra;
    if (ctx.measureText(candidato).width <= anchoMax || !actual) {
      actual = candidato;
      consumidas += 1;
      continue;
    }
    salida.push(actual);
    if (salida.length === maxLineas) break;
    actual = palabra;
    consumidas += 1;
  }
  if (salida.length < maxLineas && actual) salida.push(actual);
  const truncado = consumidas < palabras.length || salida.some((linea) => ctx.measureText(linea).width > anchoMax);
  if (truncado && salida.length) {
    let ultima = salida[salida.length - 1];
    while (ultima && ctx.measureText(`${ultima}…`).width > anchoMax) ultima = ultima.slice(0, -1);
    salida[salida.length - 1] = `${ultima.replace(/[\s.,;:!?-]+$/, '')}…`;
  }
  return { salida, truncado };
}

function registrarDesborde(ctx, campo) {
  if (campo && !ctx.__desbordes.includes(campo)) ctx.__desbordes.push(campo);
}

function bloqueTexto(ctx, texto, x, y, ancho, opciones = {}) {
  const tamano = opciones.tamano || 34;
  const interlinea = opciones.interlinea || Math.round(tamano * 1.35);
  fuente(ctx, opciones.peso || 500, tamano);
  ctx.fillStyle = opciones.color || NEGRO;
  ctx.textAlign = opciones.alinear || 'left';
  ctx.textBaseline = 'alphabetic';
  const { salida, truncado } = resolverLineas(ctx, texto, ancho, opciones.maxLineas || 4);
  salida.forEach((linea, indice) => ctx.fillText(linea, x, y + indice * interlinea));
  if (truncado) registrarDesborde(ctx, opciones.campo);
  return y + Math.max(0, salida.length - 1) * interlinea;
}

function textoUnaLinea(ctx, texto, x, y, ancho, opciones = {}) {
  fuente(ctx, opciones.peso || 600, opciones.tamano || 20);
  ctx.fillStyle = opciones.color || NEGRO;
  ctx.textAlign = opciones.alinear || 'left';
  const limpio = String(texto || '').replace(/\s+/g, ' ').trim();
  let visible = limpio;
  if (ctx.measureText(limpio).width > ancho) {
    registrarDesborde(ctx, opciones.campo);
    while (visible && ctx.measureText(`${visible}…`).width > ancho) visible = visible.slice(0, -1);
    visible = `${visible.trimEnd()}…`;
  }
  ctx.fillText(visible, x, y);
}

function marca(ctx, logo, x, y, escala = 1) {
  const ancho = 202 * escala;
  const alto = 48 * escala;
  rectRedondeado(ctx, x, y, ancho, alto, 24 * escala, 'rgba(250,246,241,.94)');
  if (logo) ctx.drawImage(logo, x + 10 * escala, y + 8 * escala, 32 * escala, 32 * escala);
  else { ctx.fillStyle = TERRACOTA; ctx.beginPath(); ctx.arc(x + 26 * escala, y + 24 * escala, 8 * escala, 0, Math.PI * 2); ctx.fill(); }
  fuente(ctx, 700, 20 * escala);
  ctx.fillStyle = NEGRO;
  ctx.textAlign = 'left';
  ctx.fillText('MAGANDHI', x + 51 * escala, y + 31 * escala);
}

function crearQr(url) {
  const fabrica = globalThis.qrcode;
  if (typeof fabrica !== 'function') throw new Error('No se pudo iniciar el generador QR local.');
  const qr = fabrica(0, 'M');
  qr.addData(url, 'Byte');
  qr.make();
  return qr;
}

export function dibujarQr(ctx, url, x, y, tamano, opciones = {}) {
  const qr = crearQr(url);
  const modulos = qr.getModuleCount();
  const margen = 4;
  const celda = Math.floor(tamano / (modulos + margen * 2));
  if (celda < 2) throw new Error('El enlace es demasiado largo para producir un QR robusto en este formato. Acorta campaña o pieza.');
  const real = celda * (modulos + margen * 2);
  const inicioX = Math.round(x + (tamano - real) / 2);
  const inicioY = Math.round(y + (tamano - real) / 2);
  ctx.fillStyle = opciones.fondo || BLANCO;
  ctx.fillRect(inicioX, inicioY, real, real);
  ctx.fillStyle = opciones.color || NEGRO;
  for (let fila = 0; fila < modulos; fila += 1) {
    for (let columna = 0; columna < modulos; columna += 1) {
      if (qr.isDark(fila, columna)) ctx.fillRect(inicioX + (columna + margen) * celda, inicioY + (fila + margen) * celda, celda, celda);
    }
  }
  return real;
}

export function pintarQrPreview(canvas, url) {
  const ctx = canvas.getContext('2d');
  canvas.width = 240; canvas.height = 240;
  ctx.clearRect(0, 0, 240, 240);
  dibujarQr(ctx, url, 0, 0, 240, { fondo: BLANCO, color: NEGRO });
}

function dibujarBoton(ctx, texto, x, y, ancho, alto, tema, tamano, campo = 'CTA') {
  rectRedondeado(ctx, x, y, ancho, alto, alto / 2, tema.botonFondo);
  fuente(ctx, 600, tamano);
  ctx.fillStyle = tema.botonTexto;
  ctx.textAlign = 'center';
  const limpio = String(texto || '').replace(/\s+/g, ' ').trim();
  let visible = limpio;
  if (ctx.measureText(limpio).width > ancho - 42) {
    registrarDesborde(ctx, campo);
    while (visible && ctx.measureText(`${visible}…`).width > ancho - 42) visible = visible.slice(0, -1);
    visible = `${visible.trimEnd()}…`;
  }
  ctx.fillText(visible, x + ancho / 2, y + alto * .66);
  ctx.textAlign = 'left';
}

function dibujarCuadrado(ctx, modelo, imagen, logo) {
  const { editorial, url, tema, imagen: ajustes, visibilidad } = modelo;
  ctx.fillStyle = gradienteSuperficie(ctx, tema, 0, 0, 1080, 1080); ctx.fillRect(0, 0, 1080, 1080);
  dibujarImagen(ctx, imagen, { x: 0, y: 0, ancho: 1080, alto: 690 }, ajustes, tema);
  const velo = ctx.createLinearGradient(0, 260, 0, 710); velo.addColorStop(0, 'rgba(17,17,17,0)'); velo.addColorStop(1, 'rgba(17,17,17,.74)');
  ctx.fillStyle = velo; ctx.fillRect(0, 240, 1080, 480);
  marca(ctx, logo, 58, 48, 1);

  rectRedondeado(ctx, 58, 626, 964, 394, 34, tema.panel);
  ctx.fillStyle = tema.acento; ctx.fillRect(58, 626, 170, 8);
  if (visibilidad.pretitulo) textoUnaLinea(ctx, editorial.pretitulo, 102, 690, 620, { tamano: 22, peso: 600, color: tema.pretitulo, campo: 'Pretítulo' });
  const textoAncho = visibilidad.qr ? 620 : 850;
  bloqueTexto(ctx, editorial.titulo, 102, 756, textoAncho, { tamano: 52, interlinea: 62, peso: 700, color: tema.titulo, maxLineas: 2, campo: 'Título' });
  bloqueTexto(ctx, editorial.descripcion, 102, 875, textoAncho, { tamano: 25, interlinea: 35, peso: 400, color: tema.descripcion, maxLineas: 2, campo: 'Descripción' });
  if (visibilidad.cta) dibujarBoton(ctx, editorial.cta, 102, 934, 300, 52, tema, 20);
  if (visibilidad.qr) {
    rectRedondeado(ctx, 758, 724, 222, 246, 22, tema.qrFondo);
    dibujarQr(ctx, url, 775, 738, 188, { fondo: tema.qrFondo, color: tema.qrTinta });
    fuente(ctx, 600, 15); ctx.fillStyle = NEGRO; ctx.textAlign = 'center'; ctx.fillText('Escanea aquí', 869, 950); ctx.textAlign = 'left';
  }
}

function dibujarHistoria(ctx, modelo, imagen, logo) {
  const { editorial, url, tema, imagen: ajustes, visibilidad } = modelo;
  ctx.fillStyle = gradienteSuperficie(ctx, tema, 0, 0, 1080, 1920, true); ctx.fillRect(0, 0, 1080, 1920);
  dibujarImagen(ctx, imagen, { x: 0, y: 0, ancho: 1080, alto: 1120 }, ajustes, tema);
  const velo = ctx.createLinearGradient(0, 380, 0, 1160); velo.addColorStop(0, 'rgba(17,17,17,.02)'); velo.addColorStop(1, 'rgba(17,17,17,.9)');
  ctx.fillStyle = velo; ctx.fillRect(0, 320, 1080, 880);
  marca(ctx, logo, 68, 70, 1.08);

  rectRedondeado(ctx, 54, 1000, 972, 782, 42, tema.panel);
  ctx.fillStyle = tema.acento; ctx.fillRect(54, 1000, 210, 10);
  if (visibilidad.pretitulo) textoUnaLinea(ctx, editorial.pretitulo, 104, 1083, 760, { tamano: 23, peso: 600, color: tema.pretitulo, campo: 'Pretítulo' });
  bloqueTexto(ctx, editorial.titulo, 104, 1180, 872, { tamano: 66, interlinea: 78, peso: 700, color: tema.titulo, maxLineas: 3, campo: 'Título' });
  const descAncho = visibilidad.qr ? 570 : 872;
  bloqueTexto(ctx, editorial.descripcion, 104, 1422, descAncho, { tamano: 31, interlinea: 45, peso: 400, color: tema.descripcion, maxLineas: visibilidad.qr ? 3 : 4, campo: 'Descripción' });
  if (visibilidad.cta) dibujarBoton(ctx, editorial.cta, 104, 1660, visibilidad.qr ? 520 : 872, 76, tema, 27);
  if (visibilidad.qr) {
    rectRedondeado(ctx, 724, 1510, 224, 224, 24, tema.qrFondo);
    dibujarQr(ctx, url, 736, 1522, 200, { fondo: tema.qrFondo, color: tema.qrTinta });
  }
  fuente(ctx, 500, 20); ctx.fillStyle = tema.pieTexto; ctx.textAlign = 'center'; ctx.fillText('magandhi.com', 540, 1870); ctx.textAlign = 'left';
}

function dibujarHorizontal(ctx, modelo, imagen, logo) {
  const { editorial, url, tema, imagen: ajustes, visibilidad } = modelo;
  ctx.fillStyle = gradienteSuperficie(ctx, tema, 0, 0, 1200, 628); ctx.fillRect(0, 0, 1200, 628);
  dibujarImagen(ctx, imagen, { x: 0, y: 0, ancho: 710, alto: 628 }, ajustes, tema);
  const velo = ctx.createLinearGradient(250, 0, 730, 0); velo.addColorStop(0, 'rgba(17,17,17,0)'); velo.addColorStop(1, 'rgba(17,17,17,.66)');
  ctx.fillStyle = velo; ctx.fillRect(230, 0, 500, 628);
  ctx.fillStyle = tema.panel; ctx.beginPath(); ctx.moveTo(650, 0); ctx.lineTo(1200, 0); ctx.lineTo(1200, 628); ctx.lineTo(585, 628); ctx.closePath(); ctx.fill();
  ctx.fillStyle = tema.acento; ctx.fillRect(650, 0, 12, 628);
  marca(ctx, logo, 704, 30, .84);
  if (visibilidad.pretitulo) textoUnaLinea(ctx, editorial.pretitulo, 714, 132, 418, { tamano: 18, peso: 600, color: tema.pretitulo, campo: 'Pretítulo' });
  bloqueTexto(ctx, editorial.titulo, 714, 206, 418, { tamano: 42, interlinea: 51, peso: 700, color: tema.titulo, maxLineas: 3, campo: 'Título' });
  bloqueTexto(ctx, editorial.descripcion, 714, 378, 418, { tamano: 18, interlinea: 27, peso: 400, color: tema.descripcion, maxLineas: visibilidad.qr ? 2 : 3, campo: 'Descripción' });
  if (visibilidad.qr) {
    rectRedondeado(ctx, 958, 420, 204, 188, 18, tema.qrFondo);
    dibujarQr(ctx, url, 972, 426, 176, { fondo: tema.qrFondo, color: tema.qrTinta });
    if (visibilidad.cta) dibujarBoton(ctx, editorial.cta, 714, 510, 220, 58, tema, 18);
  } else if (visibilidad.cta) {
    dibujarBoton(ctx, editorial.cta, 714, 500, 418, 58, tema, 20);
  }
}

export async function crearPieza(modelo) {
  const formato = FORMATOS[modelo.formato];
  if (!formato) throw new Error('Formato de pieza no reconocido.');
  const canvas = document.createElement('canvas');
  canvas.width = formato.ancho; canvas.height = formato.alto;
  const ctx = canvas.getContext('2d', { alpha: false });
  ctx.imageSmoothingEnabled = true; ctx.imageSmoothingQuality = 'high'; ctx.__desbordes = [];
  const [imagen, logo] = await Promise.all([cargarImagen(modelo.imagen?.url), cargarImagen(modelo.logoUrl)]);
  if (modelo.formato === 'historia') dibujarHistoria(ctx, modelo, imagen, logo);
  else if (modelo.formato === 'horizontal') dibujarHorizontal(ctx, modelo, imagen, logo);
  else dibujarCuadrado(ctx, modelo, imagen, logo);
  return {
    canvas, imagenDisponible: !!imagen, logoDisponible: !!logo,
    ancho: formato.ancho, alto: formato.alto, desbordes: [...ctx.__desbordes],
  };
}

export function publicarPieza(destino, resultado) {
  destino.width = resultado.ancho; destino.height = resultado.alto;
  const ctx = destino.getContext('2d', { alpha: false });
  ctx.clearRect(0, 0, destino.width, destino.height);
  ctx.drawImage(resultado.canvas, 0, 0);
}
