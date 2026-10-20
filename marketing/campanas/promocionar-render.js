// MAGANDHI · Promocionar P2 · renderer local de piezas y QR.
// No realiza peticiones de analítica ni envía el contenido a servicios QR.

import { FORMATOS } from './promocionar-core.js';

const COLORES = Object.freeze({
  marino: '#101C33', marino2: '#1B2A47', crema: '#F7F3EC',
  terracota: '#A6332E', dorado: '#C28A3A', carbon: '#2A2622',
  gris: '#777064', blanco: '#FFFFFF',
});

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
    imagen.crossOrigin = 'anonymous';
    imagen.decoding = 'async';
    imagen.onload = () => resolve(imagen);
    imagen.onerror = () => resolve(null);
    imagen.src = url;
  });
}

function dibujarCover(ctx, imagen, x, y, ancho, alto) {
  if (!imagen) {
    const gradiente = ctx.createLinearGradient(x, y, x + ancho, y + alto);
    gradiente.addColorStop(0, '#D9AE6E');
    gradiente.addColorStop(.48, '#A6332E');
    gradiente.addColorStop(1, '#101C33');
    ctx.fillStyle = gradiente;
    ctx.fillRect(x, y, ancho, alto);
    ctx.save();
    ctx.globalAlpha = .13;
    ctx.fillStyle = COLORES.blanco;
    ctx.beginPath(); ctx.arc(x + ancho * .78, y + alto * .18, ancho * .28, 0, Math.PI * 2); ctx.fill();
    ctx.beginPath(); ctx.arc(x + ancho * .12, y + alto * .86, ancho * .38, 0, Math.PI * 2); ctx.fill();
    ctx.restore();
    return;
  }
  const escala = Math.max(ancho / imagen.naturalWidth, alto / imagen.naturalHeight);
  const w = imagen.naturalWidth * escala;
  const h = imagen.naturalHeight * escala;
  ctx.drawImage(imagen, x + (ancho - w) / 2, y + (alto - h) / 2, w, h);
}

function fuente(ctx, peso, tamano) {
  ctx.font = `${peso} ${tamano}px Poppins, Arial, sans-serif`;
}

function lineas(ctx, texto, anchoMax, maxLineas = 4) {
  const palabras = String(texto || '').replace(/\s+/g, ' ').trim().split(' ').filter(Boolean);
  const salida = [];
  let actual = '';
  for (const palabra of palabras) {
    const candidato = actual ? `${actual} ${palabra}` : palabra;
    if (ctx.measureText(candidato).width <= anchoMax || !actual) {
      actual = candidato;
      continue;
    }
    salida.push(actual);
    actual = palabra;
    if (salida.length === maxLineas) break;
  }
  if (salida.length < maxLineas && actual) salida.push(actual);
  const usado = salida.join(' ').length;
  if (usado < palabras.join(' ').length && salida.length) {
    let ultima = salida[salida.length - 1];
    while (ultima && ctx.measureText(`${ultima}…`).width > anchoMax) ultima = ultima.slice(0, -1);
    salida[salida.length - 1] = `${ultima.replace(/[\s.,;:!?-]+$/, '')}…`;
  }
  return salida;
}

function bloqueTexto(ctx, texto, x, y, ancho, opciones = {}) {
  const tamano = opciones.tamano || 34;
  const interlinea = opciones.interlinea || Math.round(tamano * 1.35);
  fuente(ctx, opciones.peso || 500, tamano);
  ctx.fillStyle = opciones.color || COLORES.carbon;
  ctx.textAlign = opciones.alinear || 'left';
  ctx.textBaseline = 'alphabetic';
  const listado = lineas(ctx, texto, ancho, opciones.maxLineas || 4);
  listado.forEach((linea, indice) => ctx.fillText(linea, x, y + indice * interlinea));
  return y + Math.max(0, listado.length - 1) * interlinea;
}

function marca(ctx, x, y, color, tamano = 25) {
  ctx.fillStyle = COLORES.terracota;
  ctx.beginPath(); ctx.arc(x + tamano * .4, y - tamano * .28, tamano * .26, 0, Math.PI * 2); ctx.fill();
  fuente(ctx, 700, tamano);
  ctx.fillStyle = color;
  ctx.textAlign = 'left';
  ctx.fillText('MAGANDHI', x + tamano, y);
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
  ctx.fillStyle = opciones.fondo || COLORES.blanco;
  ctx.fillRect(inicioX, inicioY, real, real);
  ctx.fillStyle = opciones.color || COLORES.marino;
  for (let fila = 0; fila < modulos; fila += 1) {
    for (let columna = 0; columna < modulos; columna += 1) {
      if (qr.isDark(fila, columna)) {
        ctx.fillRect(inicioX + (columna + margen) * celda, inicioY + (fila + margen) * celda, celda, celda);
      }
    }
  }
  return real;
}

export function pintarQrPreview(canvas, url) {
  const ctx = canvas.getContext('2d');
  canvas.width = 240;
  canvas.height = 240;
  ctx.clearRect(0, 0, 240, 240);
  dibujarQr(ctx, url, 0, 0, 240);
}

function dibujarCuadrado(ctx, modelo, imagen) {
  const { producto, textoPieza, url, incluirQr } = modelo;
  ctx.fillStyle = COLORES.marino; ctx.fillRect(0, 0, 1080, 1080);
  dibujarCover(ctx, imagen, 0, 0, 1080, 690);
  const velo = ctx.createLinearGradient(0, 260, 0, 710);
  velo.addColorStop(0, 'rgba(16,28,51,0)'); velo.addColorStop(1, 'rgba(16,28,51,.74)');
  ctx.fillStyle = velo; ctx.fillRect(0, 240, 1080, 480);
  marca(ctx, 64, 76, COLORES.blanco, 25);

  rectRedondeado(ctx, 58, 626, 964, 394, 34, COLORES.crema);
  ctx.fillStyle = COLORES.dorado; ctx.fillRect(58, 626, 170, 8);
  fuente(ctx, 600, 22); ctx.fillStyle = COLORES.terracota; ctx.fillText('SELECCIÓN MAGANDHI', 102, 690);
  const tituloAncho = incluirQr ? 620 : 850;
  bloqueTexto(ctx, producto.nombre, 102, 756, tituloAncho, { tamano: 52, interlinea: 62, peso: 700, color: COLORES.marino, maxLineas: 2 });
  const resumen = String(textoPieza || '').replace(/\s+/g, ' ').trim() || producto.caracteristica_adicional || '';
  bloqueTexto(ctx, resumen, 102, 875, tituloAncho, { tamano: 25, interlinea: 35, peso: 400, color: COLORES.gris, maxLineas: 2 });
  rectRedondeado(ctx, 102, 934, 260, 52, 26, COLORES.terracota);
  fuente(ctx, 600, 21); ctx.fillStyle = COLORES.blanco; ctx.fillText('CONOCER PRODUCTO', 128, 968);
  if (incluirQr) {
    rectRedondeado(ctx, 758, 724, 222, 246, 22, COLORES.blanco);
    dibujarQr(ctx, url, 775, 738, 188);
    fuente(ctx, 600, 15); ctx.fillStyle = COLORES.marino; ctx.textAlign = 'center'; ctx.fillText('Escanea aquí', 869, 950); ctx.textAlign = 'left';
  }
}

function dibujarHistoria(ctx, modelo, imagen) {
  const { producto, textoPieza, url, incluirQr } = modelo;
  ctx.fillStyle = COLORES.marino; ctx.fillRect(0, 0, 1080, 1920);
  dibujarCover(ctx, imagen, 0, 0, 1080, 1120);
  const velo = ctx.createLinearGradient(0, 380, 0, 1160);
  velo.addColorStop(0, 'rgba(16,28,51,.02)'); velo.addColorStop(1, 'rgba(16,28,51,.9)');
  ctx.fillStyle = velo; ctx.fillRect(0, 320, 1080, 880);
  marca(ctx, 72, 118, COLORES.blanco, 27);

  rectRedondeado(ctx, 54, 1000, 972, 782, 42, COLORES.crema);
  ctx.fillStyle = COLORES.dorado; ctx.fillRect(54, 1000, 210, 10);
  fuente(ctx, 600, 23); ctx.fillStyle = COLORES.terracota; ctx.fillText('ELEGIDO CON CUIDADO', 104, 1083);
  bloqueTexto(ctx, producto.nombre, 104, 1180, 872, { tamano: 66, interlinea: 78, peso: 700, color: COLORES.marino, maxLineas: 3 });
  const resumen = String(textoPieza || '').replace(/\s+/g, ' ').trim() || producto.caracteristica_adicional || '';
  const resumenAncho = incluirQr ? 570 : 872;
  const resumenLineas = incluirQr ? 3 : 4;
  bloqueTexto(ctx, resumen, 104, 1422, resumenAncho, { tamano: 31, interlinea: 45, peso: 400, color: COLORES.gris, maxLineas: resumenLineas });
  rectRedondeado(ctx, 104, 1660, incluirQr ? 520 : 872, 76, 38, COLORES.terracota);
  fuente(ctx, 600, 27); ctx.fillStyle = COLORES.blanco; ctx.fillText('DESCUBRE MÁS EN MAGANDHI', 148, 1708);
  if (incluirQr) {
    rectRedondeado(ctx, 724, 1510, 224, 224, 24, COLORES.blanco);
    dibujarQr(ctx, url, 736, 1522, 200);
  }
  fuente(ctx, 500, 20); ctx.fillStyle = '#C9D1E0'; ctx.textAlign = 'center'; ctx.fillText('magandhi.com', 540, 1870); ctx.textAlign = 'left';
}

function dibujarHorizontal(ctx, modelo, imagen) {
  const { producto, textoPieza, url, incluirQr } = modelo;
  ctx.fillStyle = COLORES.crema; ctx.fillRect(0, 0, 1200, 628);
  dibujarCover(ctx, imagen, 0, 0, 710, 628);
  const velo = ctx.createLinearGradient(250, 0, 730, 0);
  velo.addColorStop(0, 'rgba(16,28,51,0)'); velo.addColorStop(1, 'rgba(16,28,51,.72)');
  ctx.fillStyle = velo; ctx.fillRect(230, 0, 500, 628);
  ctx.fillStyle = COLORES.marino; ctx.beginPath(); ctx.moveTo(650, 0); ctx.lineTo(1200, 0); ctx.lineTo(1200, 628); ctx.lineTo(585, 628); ctx.closePath(); ctx.fill();
  ctx.fillStyle = COLORES.dorado; ctx.fillRect(650, 0, 12, 628);
  marca(ctx, 714, 68, COLORES.blanco, 22);
  fuente(ctx, 600, 18); ctx.fillStyle = '#D9AE6E'; ctx.fillText('SELECCIÓN MAGANDHI', 714, 132);
  bloqueTexto(ctx, producto.nombre, 714, 206, 418, { tamano: 42, interlinea: 51, peso: 700, color: COLORES.blanco, maxLineas: 3 });
  const resumen = String(textoPieza || '').replace(/\s+/g, ' ').trim() || producto.caracteristica_adicional || '';
  const resumenHorizontalLineas = incluirQr ? 2 : 3;
  bloqueTexto(ctx, resumen, 714, 378, 418, { tamano: 22, interlinea: 31, peso: 400, color: '#D6DCE8', maxLineas: resumenHorizontalLineas });
  if (incluirQr) {
    rectRedondeado(ctx, 958, 420, 204, 188, 18, COLORES.blanco);
    dibujarQr(ctx, url, 972, 426, 176);
    rectRedondeado(ctx, 714, 510, 220, 58, 29, COLORES.terracota);
    fuente(ctx, 600, 18); ctx.fillStyle = COLORES.blanco; ctx.fillText('CONOCER PRODUCTO', 733, 547);
  } else {
    rectRedondeado(ctx, 714, 500, 418, 58, 29, COLORES.terracota);
    fuente(ctx, 600, 20); ctx.fillStyle = COLORES.blanco; ctx.fillText('CONOCER PRODUCTO', 824, 537);
  }
}

export async function crearPieza(modelo) {
  const formato = FORMATOS[modelo.formato];
  if (!formato) throw new Error('Formato de pieza no reconocido.');
  const canvas = document.createElement('canvas');
  canvas.width = formato.ancho;
  canvas.height = formato.alto;
  const ctx = canvas.getContext('2d', { alpha: false });
  ctx.imageSmoothingEnabled = true;
  ctx.imageSmoothingQuality = 'high';
  const imagen = await cargarImagen(modelo.imagenUrl);
  if (modelo.formato === 'historia') dibujarHistoria(ctx, modelo, imagen);
  else if (modelo.formato === 'horizontal') dibujarHorizontal(ctx, modelo, imagen);
  else dibujarCuadrado(ctx, modelo, imagen);
  return { canvas, imagenDisponible: !!imagen, ancho: formato.ancho, alto: formato.alto };
}

export function publicarPieza(destino, resultado) {
  destino.width = resultado.ancho;
  destino.height = resultado.alto;
  const ctx = destino.getContext('2d', { alpha: false });
  ctx.clearRect(0, 0, destino.width, destino.height);
  ctx.drawImage(resultado.canvas, 0, 0);
}
