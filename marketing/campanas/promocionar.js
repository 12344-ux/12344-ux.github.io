import {
  asegurarAcceso, montarHeader, ICONOS, supabase, urlPublicaImagen,
} from '../marketing-core.js';
import {
  CANALES, FORMATOS, canonicalProducto, contentInicial, crearCampaign,
  crearUrlUtm, nombreArchivo, normalizarUtm, parecePII, textoInicial,
  textoParaCompartir, textoPiezaInicial,
} from './promocionar-core.js';
import { crearPieza, pintarQrPreview, publicarPieza } from './promocionar-render.js';

const $ = (id) => document.getElementById(id);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const estado = {
  producto: null,
  canonical: '',
  url: '',
  canal: 'whatsapp',
  formato: 'cuadrado',
  imagenUrl: '',
  renderId: 0,
  renderTimer: null,
  utmValida: false,
  elegible: false,
  ocupado: false,
};

function canalActual() {
  return document.querySelector('input[name="pp-canal"]:checked')?.value || 'whatsapp';
}

function formatoActual() {
  return document.querySelector('input[name="pp-formato"]:checked')?.value || 'cuadrado';
}

function setFeedback(texto, error = false) {
  const el = $('pp-feedback');
  el.textContent = texto || '';
  el.classList.toggle('err', !!error);
}

function pintarIconos() {
  document.querySelectorAll('[data-ico]').forEach((el) => {
    el.innerHTML = ICONOS[el.dataset.ico] || '';
  });
}

function mostrarError(texto) {
  $('pp-carga').hidden = true;
  $('pp-estudio').hidden = true;
  $('pp-error-texto').textContent = texto;
  $('pp-error').hidden = false;
}

function textoEstado(producto) {
  if (producto.activo === false) return ['Retirado', 'retirado'];
  if (producto.es_placeholder) return ['Ejemplo', 'borrador'];
  return producto.publicado ? ['Publicado', 'publicado'] : ['Borrador', 'borrador'];
}

function imagenCampana(producto) {
  const galeria = Array.isArray(producto.imagenes)
    ? producto.imagenes.find((item) => typeof item === 'string' && item.trim())
    : '';
  return urlPublicaImagen(galeria || producto.imagen_banner_path || '');
}

function prepararCabecera(producto) {
  const [rotulo, clase] = textoEstado(producto);
  $('pp-estado').textContent = rotulo;
  $('pp-estado').className = `pp-estado ${clase}`;
  $('pp-categoria').textContent = producto.campana_categoria?.nombre || 'Sin categoría';
  $('pp-producto-nombre').textContent = producto.nombre;
  $('pp-producto-detalle').textContent = producto.caracteristica_adicional || producto.detalle_presentacion || 'Contenido aprobado de Campañas';

  estado.imagenUrl = imagenCampana(producto);
  if (estado.imagenUrl) {
    const foto = $('pp-producto-foto');
    foto.style.backgroundImage = `url("${estado.imagenUrl.replace(/"/g, '\\"')}")`;
    foto.classList.add('tiene-imagen');
  }

  if (estado.canonical) {
    $('pp-ficha-link').href = estado.canonical;
    $('pp-ficha-link').hidden = false;
  }
}

function evaluarElegibilidad() {
  const producto = estado.producto;
  estado.elegible = !!(
    producto && producto.activo !== false && !producto.es_placeholder &&
    producto.publicado && estado.canonical
  );
  const confirmar = $('pp-ficha-confirmada');
  confirmar.disabled = !estado.elegible;
  if (!estado.elegible) confirmar.checked = false;
  actualizarGate();
}

function actualizarGate() {
  const producto = estado.producto;
  const gate = $('pp-gate');
  let texto = '';
  if (!producto) texto = 'La campaña todavía no está disponible.';
  else if (producto.activo === false) texto = 'Una campaña retirada no puede producir material para compartir.';
  else if (producto.es_placeholder) texto = 'Los productos de ejemplo no se pueden promocionar.';
  else if (!producto.publicado) texto = 'Puedes preparar el diseño, pero debes publicar la campaña antes de compartir o descargar.';
  else if (!estado.canonical) texto = 'La campaña necesita un slug válido antes de compartir.';
  else if (!$('pp-ficha-confirmada').checked) texto = 'Abre la ficha oficial y confirma que el shell P1 ya está publicado.';
  else if (!estado.utmValida) texto = 'Completa identificadores UTM válidos para habilitar las acciones.';
  else if (!$('pp-utm-confirmada').checked) texto = 'Confirma que campaign y content no identifican personas ni audiencias.';
  else texto = 'Todo listo: la pieza se genera localmente y ya puedes exportarla.';
  const listo = listoParaSalir();
  gate.textContent = texto;
  gate.classList.toggle('listo', listo);
  actualizarBotones(listo);
}

function listoParaSalir() {
  return estado.elegible && $('pp-ficha-confirmada').checked &&
    $('pp-utm-confirmada').checked && estado.utmValida;
}

function actualizarBotones(listo) {
  const habilitado = listo && !estado.ocupado;
  ['pp-descargar', 'pp-copiar-url', 'pp-copiar-texto', 'pp-compartir', 'pp-copiar-url-mini'].forEach((id) => {
    $(id).disabled = !habilitado;
  });
}

function construirUrl() {
  const validacion = $('pp-validacion');
  estado.canal = canalActual();
  estado.formato = formatoActual();
  const preset = CANALES[estado.canal];
  $('pp-source').value = preset.source;
  $('pp-medium').value = preset.medium;
  try {
    if (parecePII($('pp-campaign').value) || parecePII($('pp-content').value)) {
      throw new Error('Campaña o pieza parece contener datos personales o una audiencia identificable. Usa únicamente descriptores internos.');
    }
    estado.url = crearUrlUtm(estado.canonical, {
      canal: estado.canal,
      campaign: $('pp-campaign').value,
      content: $('pp-content').value,
    });
    estado.utmValida = true;
    validacion.hidden = true;
    validacion.textContent = '';
    $('pp-url').textContent = estado.url;
    $('pp-url').title = estado.url;
  } catch (error) {
    estado.url = estado.canonical;
    estado.utmValida = false;
    validacion.textContent = error instanceof Error ? error.message : 'Revisa los identificadores del enlace.';
    validacion.hidden = false;
    $('pp-url').textContent = estado.canonical || 'Enlace no disponible';
  }
  actualizarGate();
}

function actualizarAlternativa() {
  const formato = FORMATOS[estado.formato];
  $('pp-dimensiones').textContent = `${formato.ancho} × ${formato.alto}`;
  $('pp-alternativa').textContent = `Pieza ${formato.etiqueta.toLowerCase()} para ${CANALES[estado.canal].etiqueta}: ${estado.producto.nombre}. Incluye el texto visual editado${$('pp-incluir-qr').checked ? ' y código QR' : ''}.`;
  $('pp-caracteres-pieza').textContent = String($('pp-texto-pieza').value.length);
  $('pp-caracteres').textContent = String($('pp-texto').value.length);
}

function modeloActual() {
  return {
    formato: estado.formato,
    producto: estado.producto,
    textoPieza: $('pp-texto-pieza').value,
    url: estado.url || estado.canonical,
    imagenUrl: estado.imagenUrl,
    incluirQr: $('pp-incluir-qr').checked,
  };
}

async function renderizar({ propagarError = false } = {}) {
  construirUrl();
  actualizarAlternativa();
  const miRender = ++estado.renderId;
  $('pp-renderizando').hidden = false;
  try {
    await document.fonts?.ready;
    if (miRender !== estado.renderId) return null;
    const resultado = await crearPieza(modeloActual());
    if (miRender !== estado.renderId) return null;
    publicarPieza($('pp-lienzo'), resultado);
    pintarQrPreview($('pp-qr'), estado.url || estado.canonical);
    if (!resultado.imagenDisponible && estado.imagenUrl) {
      setFeedback('La imagen no pudo cargarse para exportación; usamos el fondo de marca.', true);
    }
    return resultado;
  } catch (error) {
    if (miRender === estado.renderId) setFeedback(`No se pudo actualizar la pieza: ${error instanceof Error ? error.message : 'error inesperado.'}`, true);
    if (propagarError) throw error;
    return null;
  } finally {
    if (miRender === estado.renderId) $('pp-renderizando').hidden = true;
  }
}

function programarRender() {
  clearTimeout(estado.renderTimer);
  estado.renderTimer = setTimeout(renderizar, 90);
}

function sugerirTexto() {
  $('pp-texto-pieza').value = textoPiezaInicial(estado.producto);
  $('pp-texto').value = textoInicial(estado.producto, estado.canal);
  $('pp-caracteres-pieza').textContent = String($('pp-texto-pieza').value.length);
  $('pp-caracteres').textContent = String($('pp-texto').value.length);
}

function cablearControles() {
  document.querySelectorAll('input[name="pp-canal"]').forEach((input) => {
    input.addEventListener('change', () => {
      estado.canal = canalActual();
      $('pp-content').value = contentInicial(estado.canal, estado.formato);
      $('pp-utm-confirmada').checked = false;
      sugerirTexto();
      setFeedback('Preset de canal aplicado. Puedes ajustar el mensaje.');
      programarRender();
    });
  });
  document.querySelectorAll('input[name="pp-formato"]').forEach((input) => {
    input.addEventListener('change', () => {
      estado.formato = formatoActual();
      $('pp-content').value = contentInicial(estado.canal, estado.formato);
      $('pp-utm-confirmada').checked = false;
      programarRender();
    });
  });
  ['pp-campaign', 'pp-content'].forEach((id) => {
    $(id).addEventListener('input', () => {
      $('pp-utm-confirmada').checked = false;
      programarRender();
    });
    $(id).addEventListener('blur', () => {
      $(id).value = normalizarUtm($(id).value, 60);
      programarRender();
    });
  });
  ['pp-texto-pieza', 'pp-texto'].forEach((id) => {
    $(id).addEventListener('input', () => {
      $('pp-caracteres-pieza').textContent = String($('pp-texto-pieza').value.length);
      $('pp-caracteres').textContent = String($('pp-texto').value.length);
      programarRender();
    });
  });
  $('pp-incluir-qr').addEventListener('change', programarRender);
  $('pp-ficha-confirmada').addEventListener('change', actualizarGate);
  $('pp-utm-confirmada').addEventListener('change', actualizarGate);
  $('pp-restaurar').addEventListener('click', () => {
    sugerirTexto();
    setFeedback('Restauramos el texto sugerido para este canal.');
    programarRender();
  });
  $('pp-copiar-url').addEventListener('click', () => copiar(estado.url, 'Enlace copiado.'));
  $('pp-copiar-url-mini').addEventListener('click', () => copiar(estado.url, 'Enlace copiado.'));
  $('pp-copiar-texto').addEventListener('click', () => copiar(textoParaCompartir($('pp-texto').value, estado.url), 'Texto y enlace copiados.'));
  $('pp-compartir').addEventListener('click', compartir);
  $('pp-descargar').addEventListener('click', descargar);
}

async function copiar(texto, mensaje) {
  if (!listoParaSalir()) return;
  try {
    if (navigator.clipboard?.writeText) await navigator.clipboard.writeText(texto);
    else {
      const area = document.createElement('textarea');
      area.value = texto; area.style.position = 'fixed'; area.style.opacity = '0';
      document.body.appendChild(area); area.select();
      if (!document.execCommand('copy')) throw new Error('copy no disponible');
      area.remove();
    }
    setFeedback(mensaje);
  } catch (_) {
    setFeedback('El navegador no permitió copiar. Selecciona el enlace mostrado y cópialo manualmente.', true);
  }
}

async function compartir() {
  if (!listoParaSalir()) return;
  const datos = { title: `${estado.producto.nombre} · MAGANDHI`, text: $('pp-texto').value.trim(), url: estado.url };
  if (!navigator.share) {
    await copiar(textoParaCompartir(datos.text, datos.url), 'Este navegador no tiene Web Share; copiamos texto y enlace.');
    return;
  }
  try {
    await navigator.share(datos);
    setFeedback('Contenido enviado al menú para compartir.');
  } catch (error) {
    if (error?.name !== 'AbortError') setFeedback('No fue posible abrir el menú para compartir. Puedes copiar el texto o el enlace.', true);
  }
}

async function descargar() {
  if (!listoParaSalir() || estado.ocupado) return;
  clearTimeout(estado.renderTimer);
  estado.ocupado = true;
  estado.renderId += 1;
  construirUrl();
  actualizarGate();
  const boton = $('pp-descargar');
  boton.querySelector('span').textContent = 'Preparando PNG…';
  const formatoExportado = estado.formato;
  const canalExportado = estado.canal;
  const modelo = modeloActual();
  setFeedback('Renderizando el archivo en resolución completa…');
  try {
    await document.fonts?.ready;
    const resultado = await crearPieza(modelo);
    const blob = await new Promise((resolve, reject) => {
      try { resultado.canvas.toBlob((valor) => valor ? resolve(valor) : reject(new Error('El navegador no generó el archivo.')), 'image/png'); }
      catch (error) { reject(error); }
    });
    const href = URL.createObjectURL(blob);
    const enlace = document.createElement('a');
    enlace.href = href;
    enlace.download = nombreArchivo(estado.producto, formatoExportado, canalExportado);
    document.body.appendChild(enlace);
    enlace.click();
    enlace.remove();
    setTimeout(() => URL.revokeObjectURL(href), 1000);
    setFeedback(`PNG descargado en ${resultado.ancho} × ${resultado.alto}.`);
  } catch (error) {
    setFeedback(`No se pudo descargar la pieza: ${error instanceof Error ? error.message : 'error inesperado.'}`, true);
  } finally {
    estado.ocupado = false;
    boton.querySelector('span').textContent = 'Descargar PNG';
    actualizarGate();
    programarRender();
  }
}

async function cargarProducto(id) {
  const { data, error } = await supabase
    .from('campana_producto')
    .select('id, nombre, slug, categoria_codigo, detalle_presentacion, caracteristica_adicional, hook_largo, por_que_magandhi, sobre_este_producto, imagen_banner_path, imagenes, publicado, activo, es_placeholder, campana_categoria ( nombre )')
    .eq('id', id)
    .maybeSingle();
  if (error) throw new Error(error.message || 'No fue posible consultar la campaña.');
  if (!data) throw new Error('La campaña no existe o tu cuenta no tiene acceso a ella.');
  return data;
}

(async () => {
  const acceso = await asegurarAcceso(document.body, '../index.html');
  if (!acceso) return;
  montarHeader({
    titulo: 'Estudio Promocionar',
    kicker: 'PIEZAS DE CAMPAÑA',
    lead: 'Convierte el contenido aprobado de una campaña en enlaces, mensajes y piezas listas para descargar. Nada se publica automáticamente.',
    sesion: acceso.sesion,
    areaLabel: 'ÁREA DE MARKETING',
    volverHref: 'index.html',
    volverTexto: 'Campañas',
  });
  pintarIconos();
  $('pp-main').hidden = false;

  const id = new URLSearchParams(location.search).get('id') || '';
  if (!UUID_RE.test(id)) {
    mostrarError('Falta un identificador de campaña válido. Abre el estudio desde la lista de Campañas.');
    return;
  }
  try {
    estado.producto = await cargarProducto(id);
    try { estado.canonical = canonicalProducto(estado.producto.slug); } catch (_) { estado.canonical = ''; }
    prepararCabecera(estado.producto);
    estado.canal = canalActual();
    estado.formato = formatoActual();
    $('pp-campaign').value = crearCampaign(estado.producto.slug || estado.producto.nombre);
    $('pp-content').value = contentInicial(estado.canal, estado.formato);
    sugerirTexto();
    cablearControles();
    evaluarElegibilidad();
    $('pp-carga').hidden = true;
    $('pp-estudio').hidden = false;
    await renderizar();
  } catch (error) {
    mostrarError(error instanceof Error ? error.message : 'Ocurrió un error al preparar la campaña.');
  }
})();
