import {
  asegurarAcceso, montarHeader, ICONOS, supabase, urlPublicaImagen,
} from '../marketing-core.js';
import {
  CANALES, FORMATOS, PALETA_MARCA, PRESETS_MARCA,
  canonicalProducto, contentInicial, crearCampaign, crearUrlUtm,
  nombreArchivo, normalizarUtm, parecePII, resolverTema,
  textoInicial, textoParaCompartir, textoPiezaInicial, validarTema,
  validarTextoPromocional,
} from './promocionar-core.js?v=p2-3';
import { crearPieza, pintarQrPreview, publicarPieza } from './promocionar-render.js?v=p2-3';

const $ = (id) => document.getElementById(id);
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const LOGO_URL = new URL('../../logo-mark-terracota.png', import.meta.url).href;

const ROLES_COLOR = Object.freeze({
  panel: ['crema', 'blanco', 'negro', 'terracota'],
  pretitulo: ['terracota', 'terracotaOscuro', 'dorado', 'negro', 'crema', 'blanco'],
  titulo: ['negro', 'terracotaOscuro', 'terracota', 'crema', 'blanco', 'dorado'],
  descripcion: ['gris', 'negro', 'terracotaOscuro', 'crema', 'blanco'],
  acento: ['dorado', 'terracota', 'terracotaOscuro', 'negro', 'crema', 'blanco'],
  botonFondo: ['terracota', 'terracotaOscuro', 'dorado', 'negro', 'crema', 'blanco'],
  botonTexto: ['blanco', 'crema', 'negro', 'terracotaOscuro', 'terracota'],
});
const SUPERFICIES = Object.freeze({
  terracota: 'Terracota editorial', negro: 'Negro curaduría', negro_dorado: 'Negro + dorado',
});

const estado = {
  producto: null,
  canonical: '',
  url: '',
  canal: 'whatsapp',
  formato: 'cuadrado',
  imagenes: [],
  imagenId: 'marca',
  imagenLocalUrl: '',
  renderId: 0,
  renderTimer: null,
  utmValida: false,
  elegible: false,
  ocupado: false,
  disenoValido: false,
  mensajeValido: false,
  contenidoVisualValido: false,
  erroresVisuales: [],
  preset: 'negro',
  observadorPreview: null,
};

function canalActual() {
  return document.querySelector('input[name="pp-canal"]:checked')?.value || 'whatsapp';
}
function formatoActual() {
  return document.querySelector('input[name="pp-formato"]:checked')?.value || 'cuadrado';
}
function modoImagenActual() {
  return document.querySelector('input[name="pp-modo-imagen"]:checked')?.value || 'cover';
}
function setFeedback(texto, error = false) {
  const el = $('pp-feedback');
  el.textContent = texto || '';
  el.classList.toggle('err', !!error);
}
function pintarIconos() {
  document.querySelectorAll('[data-ico]').forEach((el) => { el.innerHTML = ICONOS[el.dataset.ico] || ''; });
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

function rutasImagen(producto) {
  const paths = [];
  if (Array.isArray(producto.imagenes)) {
    producto.imagenes.forEach((path) => {
      if (typeof path === 'string' && path.trim() && !paths.includes(path.trim())) paths.push(path.trim());
    });
  }
  if (producto.imagen_banner_path && !paths.includes(producto.imagen_banner_path)) paths.push(producto.imagen_banner_path);
  return paths;
}

function prepararCabecera(producto) {
  const [rotulo, clase] = textoEstado(producto);
  $('pp-estado').textContent = rotulo;
  $('pp-estado').className = `pp-estado ${clase}`;
  $('pp-categoria').textContent = producto.campana_categoria?.nombre || 'Sin categoría';
  $('pp-producto-nombre').textContent = producto.nombre;
  $('pp-producto-detalle').textContent = producto.caracteristica_adicional || producto.detalle_presentacion || 'Contenido aprobado de Campañas';
  const primera = rutasImagen(producto)[0];
  if (primera) {
    const foto = $('pp-producto-foto');
    foto.style.backgroundImage = `url("${urlPublicaImagen(primera).replace(/"/g, '\\"')}")`;
    foto.classList.add('tiene-imagen');
  }
  if (estado.canonical) {
    $('pp-ficha-link').href = estado.canonical;
    $('pp-ficha-link').hidden = false;
  }
}

function prepararImagenes(producto) {
  estado.imagenes = [{ id: 'marca', etiqueta: 'Fondo de marca', url: '', origen: 'marca' }];
  rutasImagen(producto).forEach((path, indice) => {
    estado.imagenes.push({ id: `campana-${indice}`, etiqueta: indice === 0 ? 'Principal' : `Galería ${indice + 1}`, url: urlPublicaImagen(path), origen: 'campana' });
  });
  estado.imagenId = estado.imagenes.length > 1 ? estado.imagenes[1].id : 'marca';
  pintarSelectorImagenes();
}

function pintarSelectorImagenes() {
  const cont = $('pp-imagenes');
  cont.replaceChildren();
  estado.imagenes.forEach((item) => {
    const label = document.createElement('label');
    label.className = 'pp-imagen-opcion';
    const input = document.createElement('input');
    input.type = 'radio'; input.name = 'pp-imagen'; input.value = item.id; input.checked = item.id === estado.imagenId;
    const mini = document.createElement('span');
    mini.className = `pp-imagen-mini${item.origen === 'marca' ? ' pp-imagen-mini--marca' : ''}`;
    if (item.url) mini.style.backgroundImage = `url("${item.url.replace(/"/g, '\\"')}")`;
    const texto = document.createElement('small'); texto.textContent = item.etiqueta;
    label.append(input, mini, texto);
    input.addEventListener('change', () => { estado.imagenId = item.id; programarRender(); });
    cont.appendChild(label);
  });
}

function imagenSeleccionada() {
  return estado.imagenes.find((item) => item.id === estado.imagenId) || estado.imagenes[0];
}

function evaluarElegibilidad() {
  const producto = estado.producto;
  estado.elegible = !!(producto && producto.activo !== false && !producto.es_placeholder && producto.publicado && estado.canonical);
  const confirmar = $('pp-ficha-confirmada');
  confirmar.disabled = !estado.elegible;
  if (!estado.elegible) confirmar.checked = false;
  actualizarGate();
}

function listoEnlace() {
  return estado.elegible && $('pp-ficha-confirmada').checked && $('pp-utm-confirmada').checked && estado.utmValida;
}

function listoContenido() {
  return $('pp-contenido-confirmado').checked && estado.mensajeValido && estado.contenidoVisualValido;
}

function actualizarGate() {
  const producto = estado.producto;
  const gate = $('pp-gate');
  let texto = '';
  if (!producto) texto = 'La campaña todavía no está disponible.';
  else if (producto.activo === false) texto = 'Una campaña retirada no puede producir material para distribuir.';
  else if (producto.es_placeholder) texto = 'Los productos de ejemplo no se pueden promocionar.';
  else if (!producto.publicado) texto = 'Puedes preparar el diseño, pero debes publicar la campaña antes de distribuirlo.';
  else if (!estado.canonical) texto = 'La campaña necesita un slug válido.';
  else if (!$('pp-ficha-confirmada').checked) texto = 'Abre la ficha oficial y confirma que el producto ya está publicado.';
  else if (!estado.utmValida) texto = 'Completa identificadores UTM válidos.';
  else if (!$('pp-utm-confirmada').checked) texto = 'Confirma que campaign y content no identifican personas ni audiencias.';
  else if (!$('pp-contenido-confirmado').checked || !estado.mensajeValido || !estado.contenidoVisualValido) texto = 'El enlace está listo para copiar; revisa y confirma el contenido antes de compartir el mensaje o descargar.';
  else texto = estado.disenoValido ? 'Enlace y pieza listos para distribuir.' : 'El enlace está listo; corrige el diseño para poder descargar el PNG.';
  gate.textContent = texto;
  gate.classList.toggle('listo', listoEnlace());
  actualizarBotones();
}

function actualizarBotones() {
  const enlaceListo = listoEnlace() && !estado.ocupado;
  ['pp-copiar-url', 'pp-copiar-url-mini'].forEach((id) => { $(id).disabled = !enlaceListo; });
  const contenidoListo = enlaceListo && listoContenido();
  ['pp-copiar-texto', 'pp-compartir'].forEach((id) => { $(id).disabled = !contenidoListo; });
  $('pp-descargar').disabled = !(contenidoListo && estado.disenoValido);
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
      throw new Error('Campaña o pieza parece contener datos personales o una audiencia identificable. Usa descriptores internos.');
    }
    estado.url = crearUrlUtm(estado.canonical, { canal: estado.canal, campaign: $('pp-campaign').value, content: $('pp-content').value });
    estado.utmValida = true;
    validacion.hidden = true; validacion.textContent = '';
    $('pp-url').textContent = estado.url; $('pp-url').title = estado.url;
    $('pp-url-resumen').textContent = estado.url; $('pp-url-resumen').title = estado.url;
  } catch (error) {
    estado.url = estado.canonical;
    estado.utmValida = false;
    validacion.textContent = error instanceof Error ? error.message : 'Revisa los identificadores del enlace.';
    validacion.hidden = false;
    $('pp-url').textContent = estado.canonical || 'Enlace no disponible';
    $('pp-url-resumen').textContent = estado.canonical || 'Enlace no disponible';
  }
  actualizarGate();
}

function llenarSelect(select, claves) {
  select.replaceChildren();
  claves.forEach((clave) => {
    const opcion = document.createElement('option');
    opcion.value = clave;
    opcion.textContent = PALETA_MARCA[clave].etiqueta;
    select.appendChild(opcion);
  });
}

function prepararControlesMarca() {
  const superficie = $('pp-color-superficie');
  superficie.replaceChildren();
  Object.entries(SUPERFICIES).forEach(([valor, etiqueta]) => {
    const opcion = document.createElement('option'); opcion.value = valor; opcion.textContent = etiqueta; superficie.appendChild(opcion);
  });
  Object.entries(ROLES_COLOR).forEach(([rol, colores]) => llenarSelect($(`pp-color-${rol.replace(/[A-Z]/g, (m) => `-${m.toLowerCase()}`)}`), colores));
  aplicarPreset('negro', false);
}

function idControlRol(rol) {
  return `pp-color-${rol.replace(/[A-Z]/g, (m) => `-${m.toLowerCase()}`)}`;
}

function valoresTema() {
  return {
    preset: estado.preset,
    superficie: $('pp-color-superficie').value,
    panel: $('pp-color-panel').value,
    pretitulo: $('pp-color-pretitulo').value,
    titulo: $('pp-color-titulo').value,
    descripcion: $('pp-color-descripcion').value,
    acento: $('pp-color-acento').value,
    botonFondo: $('pp-color-boton-fondo').value,
    botonTexto: $('pp-color-boton-texto').value,
  };
}

function aplicarPreset(nombre, render = true) {
  const preset = PRESETS_MARCA[nombre];
  if (!preset) return;
  estado.preset = nombre;
  $('pp-color-superficie').value = preset.superficie;
  ['panel', 'pretitulo', 'titulo', 'descripcion', 'acento', 'botonFondo', 'botonTexto'].forEach((rol) => { $(idControlRol(rol)).value = preset[rol]; });
  const radio = document.querySelector(`input[name="pp-preset"][value="${nombre}"]`);
  if (radio) radio.checked = true;
  $('pp-estilo-estado').textContent = `Preset ${preset.etiqueta}`;
  actualizarMuestrasColor();
  if (render) programarRender();
}

function marcarPersonalizado() {
  estado.preset = 'personalizado';
  document.querySelectorAll('input[name="pp-preset"]').forEach((radio) => { radio.checked = false; });
  $('pp-estilo-estado').textContent = 'Ajuste personalizado con colores MAGANDHI';
  actualizarMuestrasColor();
  programarRender();
}

function actualizarMuestrasColor() {
  const valores = valoresTema();
  const superficie = $('pp-muestra-superficie');
  superficie.style.background = valores.superficie === 'terracota'
    ? 'linear-gradient(135deg,#79211F,#A6332E)'
    : valores.superficie === 'negro_dorado'
      ? 'linear-gradient(135deg,#111111 35%,#C28A3A)'
      : 'linear-gradient(135deg,#111111,#1D1D1D)';
  ['panel', 'pretitulo', 'titulo', 'descripcion', 'acento', 'botonFondo', 'botonTexto'].forEach((rol) => {
    $(`pp-muestra-${rol.replace(/[A-Z]/g, (m) => `-${m.toLowerCase()}`)}`).style.background = PALETA_MARCA[valores[rol]].hex;
  });
}

function modeloActual() {
  const seleccion = imagenSeleccionada();
  return {
    formato: estado.formato,
    url: estado.url || estado.canonical,
    logoUrl: LOGO_URL,
    editorial: {
      pretitulo: $('pp-pretitulo').value.trim(),
      titulo: $('pp-titulo').value.trim(),
      descripcion: $('pp-texto-pieza').value.trim(),
      cta: $('pp-cta').value.trim(),
    },
    tema: resolverTema(valoresTema()),
    imagen: {
      url: seleccion?.url || '', origen: seleccion?.origen || 'marca',
      modo: modoImagenActual(), focoX: Number($('pp-foco-x').value),
      focoY: Number($('pp-foco-y').value), zoom: Number($('pp-zoom').value),
    },
    visibilidad: {
      pretitulo: $('pp-mostrar-pretitulo').checked,
      cta: $('pp-mostrar-cta').checked,
      qr: $('pp-incluir-qr').checked,
    },
  };
}

function validarContenidoEditorial(modelo) {
  const visuales = [];
  if (modelo.visibilidad.pretitulo) visuales.push(...validarTextoPromocional(modelo.editorial.pretitulo, 'El pretítulo'));
  visuales.push(...validarTextoPromocional(modelo.editorial.titulo, 'El título'));
  visuales.push(...validarTextoPromocional(modelo.editorial.descripcion, 'La descripción'));
  if (modelo.visibilidad.cta) visuales.push(...validarTextoPromocional(modelo.editorial.cta, 'El CTA'));
  const mensaje = validarTextoPromocional($('pp-texto').value, 'El mensaje para compartir');
  estado.erroresVisuales = [...new Set(visuales)];
  estado.contenidoVisualValido = estado.erroresVisuales.length === 0;
  estado.mensajeValido = mensaje.length === 0;
  const todos = [...new Set([...estado.erroresVisuales, ...mensaje])];
  const el = $('pp-contenido-validacion');
  el.hidden = todos.length === 0;
  el.textContent = todos.join(' ');
  el.setAttribute('role', todos.length ? 'alert' : 'status');
  if (todos.length) $('pp-contenido-confirmado').checked = false;
  return estado.erroresVisuales;
}

function erroresDiseno(modelo, resultado) {
  const erroresContraste = validarTema(modelo.tema).filter((mensaje) => {
    if (!modelo.visibilidad.pretitulo && mensaje.startsWith('El pretítulo')) return false;
    if (!modelo.visibilidad.cta && mensaje.startsWith('El botón')) return false;
    return true;
  });
  const errores = [...erroresContraste, ...estado.erroresVisuales];
  if (!modelo.editorial.titulo) errores.push('Escribe un título para la pieza.');
  if (!modelo.editorial.descripcion) errores.push('Escribe una descripción para la pieza.');
  if (modelo.visibilidad.pretitulo && !modelo.editorial.pretitulo) errores.push('Escribe el pretítulo o apágalo.');
  if (modelo.visibilidad.cta && !modelo.editorial.cta) errores.push('Escribe el CTA o apágalo.');
  if (modelo.imagen.origen !== 'marca' && !resultado.imagenDisponible) errores.push('La imagen elegida no pudo cargarse; selecciona otra o usa Fondo de marca.');
  if (!resultado.logoDisponible) errores.push('No se pudo cargar el distintivo oficial MAGANDHI.');
  if (resultado.desbordes.length) errores.push(`Acorta ${resultado.desbordes.join(', ')} para que no se corte en este formato.`);
  return [...new Set(errores)];
}

function mostrarValidacionDiseno(errores) {
  const el = $('pp-diseno-validacion');
  estado.disenoValido = errores.length === 0;
  el.hidden = false;
  el.classList.toggle('ok', estado.disenoValido);
  el.setAttribute('role', estado.disenoValido ? 'status' : 'alert');
  el.textContent = estado.disenoValido
    ? 'Diseño válido: colores legibles y contenido dentro de la estructura.'
    : errores.join(' ');
  actualizarGate();
}

function actualizarAlternativa() {
  const formato = FORMATOS[estado.formato];
  $('pp-dimensiones').textContent = `${formato.ancho} × ${formato.alto}`;
  const pretitulo = $('pp-mostrar-pretitulo').checked ? ($('pp-pretitulo').value || 'vacío') : 'oculto';
  const cta = $('pp-mostrar-cta').checked ? ($('pp-cta').value || 'vacío') : 'oculto';
  const imagen = imagenSeleccionada()?.etiqueta || 'Fondo de marca';
  $('pp-alternativa').textContent = `Pieza ${formato.etiqueta.toLowerCase()} para ${CANALES[estado.canal].etiqueta}. Imagen: ${imagen}. Estilo: ${$('pp-estilo-estado').textContent}. Pretítulo: ${pretitulo}. Título: ${$('pp-titulo').value || 'vacío'}. Descripción: ${$('pp-texto-pieza').value || 'vacía'}; CTA: ${cta}. ${$('pp-incluir-qr').checked ? 'Incluye el QR del enlace protegido.' : 'No incluye QR.'}`;
  $('pp-caracteres-titulo').textContent = String($('pp-titulo').value.length);
  $('pp-caracteres-pieza').textContent = String($('pp-texto-pieza').value.length);
  $('pp-caracteres').textContent = String($('pp-texto').value.length);
}

async function renderizar({ propagarError = false } = {}) {
  construirUrl();
  actualizarAlternativa();
  const miRender = ++estado.renderId;
  estado.disenoValido = false;
  actualizarBotones();
  $('pp-renderizando').hidden = false;
  try {
    await document.fonts?.ready;
    if (miRender !== estado.renderId) return null;
    const modelo = modeloActual();
    validarContenidoEditorial(modelo);
    const resultado = await crearPieza(modelo);
    if (miRender !== estado.renderId) return null;
    publicarPieza($('pp-lienzo'), resultado);
    pintarQrPreview($('pp-qr'), estado.url || estado.canonical);
    mostrarValidacionDiseno(erroresDiseno(modelo, resultado));
    return resultado;
  } catch (error) {
    if (miRender === estado.renderId) {
      estado.disenoValido = false;
      mostrarValidacionDiseno([error instanceof Error ? error.message : 'No se pudo actualizar la pieza.']);
      setFeedback('No se pudo actualizar el diseño.', true);
    }
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

function sugerirTextos() {
  $('pp-pretitulo').value = 'SELECCIÓN MAGANDHI';
  $('pp-titulo').value = estado.producto.nombre || '';
  $('pp-texto-pieza').value = textoPiezaInicial(estado.producto);
  $('pp-cta').value = 'COMPRAR AHORA';
  $('pp-texto').value = textoInicial(estado.producto, estado.canal);
  actualizarAlternativa();
}

function restablecerDiseno() {
  aplicarPreset('negro', false);
  $('pp-mostrar-pretitulo').checked = true;
  $('pp-mostrar-cta').checked = true;
  $('pp-contenido-confirmado').checked = false;
  $('pp-incluir-qr').checked = true;
  $('pp-foco-x').value = '50'; $('pp-foco-y').value = '50'; $('pp-zoom').value = '100';
  document.querySelector('input[name="pp-modo-imagen"][value="cover"]').checked = true;
  actualizarSliders();
  setFeedback('Restauramos encuadre, visibilidad y distintivos MAGANDHI. Tus textos se conservaron.');
  programarRender();
}

function actualizarSliders() {
  $('pp-foco-x-valor').textContent = `${$('pp-foco-x').value}%`;
  $('pp-foco-y-valor').textContent = `${$('pp-foco-y').value}%`;
  $('pp-zoom-valor').textContent = `${$('pp-zoom').value}%`;
}

function cablearControles() {
  document.querySelectorAll('input[name="pp-canal"]').forEach((input) => input.addEventListener('change', () => {
    estado.canal = canalActual();
    $('pp-content').value = contentInicial(estado.canal, estado.formato);
    $('pp-utm-confirmada').checked = false;
    $('pp-texto').value = textoInicial(estado.producto, estado.canal);
    $('pp-contenido-confirmado').checked = false;
    setFeedback('Preset de canal aplicado. La pieza no se publicó.');
    programarRender();
  }));
  document.querySelectorAll('input[name="pp-formato"]').forEach((input) => input.addEventListener('change', () => {
    estado.formato = formatoActual();
    $('pp-content').value = contentInicial(estado.canal, estado.formato);
    $('pp-utm-confirmada').checked = false;
    programarRender();
  }));
  ['pp-campaign', 'pp-content'].forEach((id) => {
    $(id).addEventListener('input', () => { $('pp-utm-confirmada').checked = false; programarRender(); });
    $(id).addEventListener('blur', () => { $(id).value = normalizarUtm($(id).value, 60); programarRender(); });
  });
  ['pp-pretitulo', 'pp-titulo', 'pp-texto-pieza', 'pp-cta', 'pp-texto'].forEach((id) => $(id).addEventListener('input', () => {
    $('pp-contenido-confirmado').checked = false;
    programarRender();
  }));
  ['pp-mostrar-pretitulo', 'pp-mostrar-cta', 'pp-incluir-qr'].forEach((id) => $(id).addEventListener('change', () => {
    if (id !== 'pp-incluir-qr') $('pp-contenido-confirmado').checked = false;
    programarRender();
  }));
  document.querySelectorAll('input[name="pp-modo-imagen"]').forEach((input) => input.addEventListener('change', programarRender));
  ['pp-foco-x', 'pp-foco-y', 'pp-zoom'].forEach((id) => $(id).addEventListener('input', () => { actualizarSliders(); programarRender(); }));

  $('pp-elegir-imagen').addEventListener('click', () => $('pp-imagen-local').click());
  $('pp-imagen-local').addEventListener('change', () => {
    const archivo = $('pp-imagen-local').files?.[0];
    if (!archivo) return;
    if (!['image/png', 'image/jpeg', 'image/webp'].includes(archivo.type) || archivo.size > 15 * 1024 * 1024) {
      setFeedback('Elige una imagen PNG, JPG o WebP de máximo 15 MB.', true);
      $('pp-imagen-local').value = '';
      return;
    }
    if (estado.imagenLocalUrl) URL.revokeObjectURL(estado.imagenLocalUrl);
    estado.imagenLocalUrl = URL.createObjectURL(archivo);
    estado.imagenes = estado.imagenes.filter((item) => item.origen !== 'local');
    estado.imagenes.push({ id: 'local', etiqueta: archivo.name, url: estado.imagenLocalUrl, origen: 'local' });
    estado.imagenId = 'local';
    pintarSelectorImagenes();
    setFeedback('Imagen temporal añadida. No se guardará en Campañas.');
    programarRender();
  });

  document.querySelectorAll('input[name="pp-preset"]').forEach((input) => input.addEventListener('change', () => aplicarPreset(input.value)));
  $('pp-color-superficie').addEventListener('change', marcarPersonalizado);
  ['panel', 'pretitulo', 'titulo', 'descripcion', 'acento', 'botonFondo', 'botonTexto'].forEach((rol) => $(idControlRol(rol)).addEventListener('change', marcarPersonalizado));

  $('pp-ficha-confirmada').addEventListener('change', actualizarGate);
  $('pp-utm-confirmada').addEventListener('change', () => { construirUrl(); actualizarGate(); });
  $('pp-contenido-confirmado').addEventListener('change', () => { validarContenidoEditorial(modeloActual()); actualizarGate(); });
  $('pp-restaurar').addEventListener('click', () => { sugerirTextos(); $('pp-contenido-confirmado').checked = false; setFeedback('Restauramos los textos sugeridos.'); programarRender(); });
  $('pp-restaurar-diseno').addEventListener('click', restablecerDiseno);
  $('pp-copiar-url').addEventListener('click', () => copiar(estado.url, 'Enlace protegido copiado.'));
  $('pp-copiar-url-mini').addEventListener('click', () => copiar(estado.url, 'Enlace protegido copiado.'));
  $('pp-copiar-texto').addEventListener('click', () => copiar(textoParaCompartir($('pp-texto').value, estado.url), 'Mensaje y enlace copiados.', true));
  $('pp-compartir').addEventListener('click', compartir);
  $('pp-descargar').addEventListener('click', descargar);
  window.addEventListener('beforeunload', () => { if (estado.imagenLocalUrl) URL.revokeObjectURL(estado.imagenLocalUrl); });
}

async function copiar(texto, mensaje, requiereContenido = false) {
  if (!listoEnlace() || (requiereContenido && !listoContenido())) return;
  try {
    if (navigator.clipboard?.writeText) await navigator.clipboard.writeText(texto);
    else {
      const area = document.createElement('textarea'); area.value = texto; area.style.position = 'fixed'; area.style.opacity = '0';
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
  if (!listoEnlace() || !listoContenido()) return;
  const datos = { title: `${estado.producto.nombre} · MAGANDHI`, text: $('pp-texto').value.trim(), url: estado.url };
  if (!navigator.share) {
    await copiar(textoParaCompartir(datos.text, datos.url), 'Web Share no está disponible; copiamos mensaje y enlace.');
    return;
  }
  try { await navigator.share(datos); setFeedback('Contenido enviado al menú para compartir.'); }
  catch (error) { if (error?.name !== 'AbortError') setFeedback('No fue posible abrir el menú. Puedes copiar el texto o el enlace.', true); }
}

async function descargar() {
  if (!listoEnlace() || !listoContenido() || !estado.disenoValido || estado.ocupado) return;
  clearTimeout(estado.renderTimer);
  estado.ocupado = true; estado.renderId += 1; construirUrl(); actualizarBotones();
  const boton = $('pp-descargar'); boton.querySelector('span').textContent = 'Preparando PNG…';
  const formatoExportado = estado.formato; const canalExportado = estado.canal; const modelo = modeloActual();
  setFeedback('Renderizando el archivo en resolución completa…');
  try {
    await document.fonts?.ready;
    validarContenidoEditorial(modelo);
    if (!listoContenido()) throw new Error('Revisa y confirma el contenido antes de descargar.');
    const resultado = await crearPieza(modelo);
    const errores = erroresDiseno(modelo, resultado);
    if (errores.length) throw new Error(errores.join(' '));
    const blob = await new Promise((resolve, reject) => {
      try { resultado.canvas.toBlob((valor) => valor ? resolve(valor) : reject(new Error('El navegador no generó el archivo.')), 'image/png'); }
      catch (error) { reject(error); }
    });
    const href = URL.createObjectURL(blob); const enlace = document.createElement('a');
    enlace.href = href; enlace.download = nombreArchivo(estado.producto, formatoExportado, canalExportado);
    document.body.appendChild(enlace); enlace.click(); enlace.remove(); setTimeout(() => URL.revokeObjectURL(href), 1000);
    setFeedback(`PNG descargado en ${resultado.ancho} × ${resultado.alto}. Ahora adjúntalo y pega el enlace protegido.`);
  } catch (error) {
    setFeedback(`No se pudo descargar: ${error instanceof Error ? error.message : 'error inesperado.'}`, true);
  } finally {
    estado.ocupado = false; boton.querySelector('span').textContent = 'Descargar PNG'; actualizarBotones(); programarRender();
  }
}

function montarAccesoPreview() {
  const boton = $('pp-preview-flotante');
  const preview = $('pp-preview-col');
  if (!boton || !preview || typeof IntersectionObserver !== 'function') return;
  estado.observadorPreview?.disconnect();
  estado.observadorPreview = new IntersectionObserver(([entrada]) => {
    boton.hidden = entrada.isIntersecting;
  }, { threshold: 0.08 });
  estado.observadorPreview.observe(preview);
}

async function cargarProducto(id) {
  const { data, error } = await supabase.from('campana_producto')
    .select('id, nombre, slug, categoria_codigo, detalle_presentacion, caracteristica_adicional, hook_largo, por_que_magandhi, sobre_este_producto, imagen_banner_path, imagenes, publicado, activo, es_placeholder, campana_categoria ( nombre )')
    .eq('id', id).maybeSingle();
  if (error) throw new Error(error.message || 'No fue posible consultar la campaña.');
  if (!data) throw new Error('La campaña no existe o tu cuenta no tiene acceso a ella.');
  return data;
}

(async () => {
  const acceso = await asegurarAcceso(document.body, '../index.html');
  if (!acceso) return;
  montarHeader({
    titulo: 'Estudio Promocionar', kicker: 'COMUNICACIÓN MAGANDHI',
    lead: 'Diseña la pieza, prepara su mensaje y distribuye un enlace de compra protegido. Tú decides qué sale: nada se publica automáticamente.',
    sesion: acceso.sesion, areaLabel: 'ESTUDIO DE MARCA', volverHref: 'index.html', volverTexto: 'Campañas',
  });
  const sello = document.querySelector('.mk-sello');
  if (sello) sello.innerHTML = 'Comunicación de marca · <span class="mk-sello-marca">MAGANDHI</span>';
  const guia = $('pp-guia');
  try {
    if (localStorage.getItem('magandhi-promocionar-guia-leida') === '1') guia.open = false;
    guia.addEventListener('toggle', () => { if (!guia.open) localStorage.setItem('magandhi-promocionar-guia-leida', '1'); });
  } catch (_) { /* La guía sigue disponible aunque el navegador bloquee storage. */ }
  pintarIconos();
  $('pp-main').hidden = false;
  const id = new URLSearchParams(location.search).get('id') || '';
  if (!UUID_RE.test(id)) { mostrarError('Falta un identificador de campaña válido. Abre el estudio desde Campañas.'); return; }
  try {
    estado.producto = await cargarProducto(id);
    try { estado.canonical = canonicalProducto(estado.producto.slug); } catch (_) { estado.canonical = ''; }
    prepararCabecera(estado.producto);
    prepararControlesMarca();
    prepararImagenes(estado.producto);
    estado.canal = canalActual(); estado.formato = formatoActual();
    $('pp-campaign').value = crearCampaign(estado.producto.slug || estado.producto.nombre);
    $('pp-content').value = contentInicial(estado.canal, estado.formato);
    sugerirTextos(); actualizarSliders(); cablearControles(); evaluarElegibilidad();
    $('pp-carga').hidden = true; $('pp-estudio').hidden = false;
    montarAccesoPreview();
    await renderizar();
  } catch (error) {
    mostrarError(error instanceof Error ? error.message : 'Ocurrió un error al preparar la campaña.');
  }
})();
