// ============================================================
// MAGANDHI · Campañas · administración compartida de categorías
// ------------------------------------------------------------
// Una sola implementación para agregar.html, editar.html e index.html:
// - consulta la lista blanca de categorías planas activas/visibles;
// - pinta multiselección con una principal;
// - abre el diálogo accesible de alta mediante cm_crear_categoria;
// - muestra una banda HTML/CSS derivada de nombre, descripción e icono.
// No recibe archivos ni escribe tablas directamente.
// ============================================================

import { supabase } from '../marketing-core.js';

const svg = (trazos) =>
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
  trazos + '</svg>';

export const ICONOS_CATEGORIA = Object.freeze([
  Object.freeze({
    codigo: 'tecnologia',
    nombre: 'Tecnología',
    svg: svg('<rect x="6.5" y="2.5" width="11" height="19" rx="2.5"/><path d="M10 5.5h4M10.5 18.5h3"/>')
  }),
  Object.freeze({
    codigo: 'moda',
    nombre: 'Moda',
    svg: svg('<path d="M8.5 4 4 6.5l2.2 4L8 9.5V21h8V9.5l1.8 1 2.2-4L15.5 4A4 4 0 0 1 12 6a4 4 0 0 1-3.5-2Z"/>')
  }),
  Object.freeze({
    codigo: 'hogar',
    nombre: 'Hogar',
    svg: svg('<path d="M4 11h16v9H4z"/><path d="M7 11V8a5 5 0 0 1 10 0v3M7 15h10M7 20v2M17 20v2"/>')
  }),
  Object.freeze({
    codigo: 'deportes',
    nombre: 'Deportes',
    svg: svg('<circle cx="12" cy="12" r="9"/><path d="m12 7 3 2.2-1.1 3.5h-3.8L9 9.2 12 7Z"/><path d="M12 3v4M15 9.2l4-1.3M13.9 12.7l2.5 3.5M10.1 12.7l-2.5 3.5M9 9.2 5 7.9M7.6 16.2l-1 2.7M16.4 16.2l1 2.7"/>')
  }),
  Object.freeze({
    codigo: 'belleza',
    nombre: 'Belleza',
    svg: svg('<path d="M9 8h6l1 3v10H8V11l1-3Z"/><path d="M10 8V4h4v4M10 4h6M16 4v2M10 13h4M10 17h4"/>')
  }),
  Object.freeze({
    codigo: 'accesorios',
    nombre: 'Accesorios',
    svg: svg('<path d="m9 2-1 5h8l-1-5H9ZM9 22l-1-5h8l-1 5H9Z"/><rect x="6" y="7" width="12" height="10" rx="4"/><path d="M12 10v3l2 1"/>')
  }),
  Object.freeze({
    codigo: 'mascotas',
    nombre: 'Mascotas',
    svg: svg('<path d="M8.7 13.3c-2.7 1.7-3.1 5.4-.8 6.7 1.6.9 2.8-.5 4.1-.5s2.5 1.4 4.1.5c2.3-1.3 1.9-5-.8-6.7-2-1.3-4.6-1.3-6.6 0Z"/><ellipse cx="6" cy="8" rx="2" ry="2.7"/><ellipse cx="18" cy="8" rx="2" ry="2.7"/><ellipse cx="10" cy="5" rx="2" ry="2.7"/><ellipse cx="14" cy="5" rx="2" ry="2.7"/>')
  }),
  Object.freeze({
    codigo: 'jugueteria',
    nombre: 'Juguetería',
    svg: svg('<path d="M9 3a3 3 0 1 0 3 3v3h3a3 3 0 1 1 3 3h-3v3a3 3 0 1 1-3 3v-3H9a3 3 0 1 1-3-3h3V9H6a3 3 0 0 1 3-6Z"/>')
  }),
  Object.freeze({
    codigo: 'regalo',
    nombre: 'Regalos',
    svg: svg('<rect x="3" y="9" width="18" height="12" rx="2"/><path d="M12 9v12M3 13h18M7.5 9C5.6 9 4.5 8 4.5 6.5S5.6 4 7 4c2.4 0 5 5 5 5M16.5 9c1.9 0 3-1 3-2.5S18.4 4 17 4c-2.4 0-5 5-5 5"/>')
  }),
  Object.freeze({
    codigo: 'bienestar',
    nombre: 'Bienestar',
    svg: svg('<path d="M20.8 5.7c-2-2-5.1-1.9-7 .2L12 7.8l-1.8-1.9c-1.9-2.1-5-2.2-7-.2-2.1 2.1-2 5.5.1 7.6L12 22l8.7-8.7c2.1-2.1 2.2-5.5.1-7.6Z"/><path d="M8 12h2l1.2-2.5 1.7 5 1.2-2.5H17"/>')
  }),
  Object.freeze({
    codigo: 'oficina',
    nombre: 'Oficina',
    svg: svg('<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M8 7V4h8v3M3 12h18M10 12v2h4v-2"/>')
  }),
  Object.freeze({
    codigo: 'viaje',
    nombre: 'Viaje',
    svg: svg('<rect x="6" y="5" width="12" height="16" rx="3"/><path d="M9 5V3h6v2M9 10v6M15 10v6M9 21v1M15 21v1"/>')
  }),
  Object.freeze({
    codigo: 'bebes',
    nombre: 'Bebés',
    svg: svg('<circle cx="12" cy="12" r="8"/><path d="M12 4v8l5.7-5.7M9 15c.8.7 1.8 1 3 1s2.2-.3 3-1M9 11h.01M15 11h.01"/>')
  }),
  Object.freeze({
    codigo: 'alimentos',
    nombre: 'Alimentos',
    svg: svg('<path d="M5 9h14l-1 12H6Z"/><path d="M8 9c0-3 1.5-5 4-6 2.5 1 4 3 4 6M9 14h6"/>')
  }),
  Object.freeze({
    codigo: 'coleccion',
    nombre: 'Colección',
    svg: svg('<rect x="3" y="4" width="7" height="7" rx="2"/><rect x="14" y="4" width="7" height="7" rx="2"/><rect x="3" y="15" width="7" height="6" rx="2"/><rect x="14" y="15" width="7" height="6" rx="2"/>')
  })
]);

const ICONOS_POR_CODIGO = new Map(ICONOS_CATEGORIA.map((item) => [item.codigo, item]));
const ICONO_FALLBACK = svg('<path d="M12.6 2.6A2 2 0 0 0 11.2 2H4a2 2 0 0 0-2 2v7.2a2 2 0 0 0 .6 1.4l8.7 8.7a2.4 2.4 0 0 0 3.4 0l6.6-6.6a2.4 2.4 0 0 0 0-3.4Z"/><circle cx="7.5" cy="7.5" r="1.5"/>');
const CHECK_SVG = svg('<path d="M20 6 9 17l-5-5"/>');
let secuencia = 0;

export function iconoCategoria(codigo) {
  return ICONOS_POR_CODIGO.get(String(codigo || ''))?.svg || ICONO_FALLBACK;
}

function normalizarCategoria(fila) {
  if (!fila || !fila.codigo) return null;
  return {
    codigo: String(fila.codigo),
    nombre: String(fila.nombre || fila.codigo),
    icono_codigo: String(fila.icono_codigo || ''),
    descripcion: String(fila.descripcion || ''),
    orden: Number.isFinite(Number(fila.orden)) ? Number(fila.orden) : 0,
    es_oficial: fila.es_oficial === true
  };
}

function ordenarCategorias(lista) {
  return [...lista].sort((a, b) =>
    a.orden - b.orden || a.nombre.localeCompare(b.nombre, 'es', { sensitivity: 'base' })
  );
}

export async function cargarCategoriasPublicas() {
  const { data, error } = await supabase
    .from('categorias_publicas')
    .select('codigo, nombre, icono_codigo, descripcion, orden, es_oficial')
    .order('orden', { ascending: true });

  return {
    data: ordenarCategorias((data || []).map(normalizarCategoria).filter(Boolean)),
    error
  };
}

export function mensajeErrorCategoria(error) {
  const bruto = String(error?.message || error || '').trim();
  if (!bruto) return 'No se pudo completar la operación con categorías.';
  if (bruto.startsWith('CM_CATEGORIAS_PUBLICACION_REQUERIDAS')) {
    return 'Elige y guarda al menos una categoría activa y visible, incluida una principal, antes de publicar.';
  }
  if (bruto.startsWith('CM_CATEGORIA_NO_PUBLICA')) {
    return 'Una categoría elegida ya no está activa o visible. Actualiza la selección e inténtalo de nuevo.';
  }
  return bruto.replace(/^CM_[A-Z_]+:\s*/, '');
}

export function crearSelectorCategorias({
  contenedor,
  estado,
  categorias = [],
  codigosIniciales = [],
  principalInicial = null,
  historicas = [],
  onChange = () => {}
}) {
  if (!contenedor || !estado) {
    throw new Error('El selector de categorías necesita contenedor y estado.');
  }

  const id = ++secuencia;
  const nombreRadio = 'cm-categoria-principal-' + id;
  let catalogo = ordenarCategorias(categorias.map(normalizarCategoria).filter(Boolean));
  let seleccion = new Set(codigosIniciales.map(String));
  let principal = principalInicial ? String(principalInicial) : null;
  let codigosHistoricos = [...new Set((historicas || []).map(String))];

  function categoria(codigo) {
    return catalogo.find((item) => item.codigo === codigo) || null;
  }

  function valor() {
    return {
      codigos: catalogo.filter((item) => seleccion.has(item.codigo)).map((item) => item.codigo),
      principal
    };
  }

  function anunciar() {
    const actual = valor();
    const nombrePrincipal = categoria(actual.principal)?.nombre || actual.principal;
    let texto = actual.codigos.length
      ? actual.codigos.length + (actual.codigos.length === 1 ? ' categoría elegida' : ' categorías elegidas') +
        (actual.principal ? ' · principal: ' + nombrePrincipal : ' · elige la principal')
      : 'Debes elegir al menos una categoría.';

    if (codigosHistoricos.length) {
      texto += ' · Clasificación histórica que se reemplazará al guardar: ' + codigosHistoricos.join(', ') + '.';
    }
    estado.textContent = texto;
    estado.classList.toggle(
      'err',
      !actual.codigos.length || !actual.principal || codigosHistoricos.length > 0
    );
  }

  function notificar() {
    anunciar();
    const actual = valor();
    onChange({
      ...actual,
      categoriaPrincipal: categoria(actual.principal),
      categorias: catalogo.map((item) => ({ ...item }))
    });
  }

  function sincronizarRadios() {
    contenedor.querySelectorAll('.cm-categoria-opcion').forEach((opcion) => {
      const check = opcion.querySelector('.cm-categoria-check input');
      const radio = opcion.querySelector('.cm-categoria-principal input');
      radio.disabled = !check.checked;
      radio.checked = check.checked && check.value === principal;
    });
  }

  function crearOpcion(item) {
    const opcion = document.createElement('div');
    opcion.className = 'cm-categoria-opcion';
    opcion.dataset.codigo = item.codigo;

    const checkLabel = document.createElement('label');
    checkLabel.className = 'cm-categoria-check';

    const check = document.createElement('input');
    check.type = 'checkbox';
    check.value = item.codigo;
    check.checked = seleccion.has(item.codigo);

    const marca = document.createElement('span');
    marca.className = 'cm-tag-check';
    marca.innerHTML = CHECK_SVG;
    marca.setAttribute('aria-hidden', 'true');

    const icono = document.createElement('span');
    icono.className = 'cm-categoria-icono';
    icono.innerHTML = iconoCategoria(item.icono_codigo);
    icono.setAttribute('aria-hidden', 'true');

    const identidad = document.createElement('span');
    identidad.className = 'cm-categoria-identidad';
    const nombre = document.createElement('span');
    nombre.className = 'cm-categoria-nombre';
    nombre.textContent = item.nombre;
    identidad.appendChild(nombre);
    if (item.es_oficial) {
      const oficial = document.createElement('span');
      oficial.className = 'cm-categoria-oficial';
      oficial.textContent = 'Oficial';
      identidad.appendChild(oficial);
    }

    checkLabel.append(check, marca, icono, identidad);

    const principalLabel = document.createElement('label');
    principalLabel.className = 'cm-categoria-principal';
    const radio = document.createElement('input');
    radio.type = 'radio';
    radio.name = nombreRadio;
    radio.value = item.codigo;
    radio.setAttribute('aria-label', 'Categoría principal: ' + item.nombre);
    radio.disabled = !check.checked;
    radio.checked = check.checked && principal === item.codigo;
    const principalTexto = document.createElement('span');
    principalTexto.textContent = 'Principal';
    principalLabel.append(radio, principalTexto);

    check.addEventListener('change', () => {
      if (check.checked) {
        seleccion.add(item.codigo);
        if (!principal) principal = item.codigo;
      } else {
        seleccion.delete(item.codigo);
        if (principal === item.codigo) principal = null;
      }
      sincronizarRadios();
      notificar();
    });

    radio.addEventListener('change', () => {
      if (radio.checked && seleccion.has(item.codigo)) principal = item.codigo;
      sincronizarRadios();
      notificar();
    });

    opcion.append(checkLabel, principalLabel);
    return opcion;
  }

  function pintar() {
    contenedor.replaceChildren();
    const disponibles = new Set(catalogo.map((item) => item.codigo));
    seleccion = new Set([...seleccion].filter((codigo) => disponibles.has(codigo)));
    if (!principal || !seleccion.has(principal)) principal = null;

    if (!catalogo.length) {
      const vacio = document.createElement('span');
      vacio.className = 'cm-campo-ayuda';
      vacio.textContent = 'No hay categorías activas y visibles disponibles.';
      contenedor.appendChild(vacio);
      notificar();
      return;
    }

    const fragmento = document.createDocumentFragment();
    catalogo.forEach((item) => fragmento.appendChild(crearOpcion(item)));
    contenedor.appendChild(fragmento);
    sincronizarRadios();
    notificar();
  }

  function seleccionar(codigos, codigoPrincipal, opciones = {}) {
    seleccion = new Set((codigos || []).map(String));
    principal = codigoPrincipal ? String(codigoPrincipal) : null;
    codigosHistoricos = [...new Set((opciones.historicas || []).map(String))];
    if ((!principal || !seleccion.has(principal)) && seleccion.size) {
      principal = catalogo.find((item) => seleccion.has(item.codigo))?.codigo || null;
    }
    pintar();
  }

  function agregarCategoria(fila, { seleccionarNueva = true } = {}) {
    const nueva = normalizarCategoria(fila);
    if (!nueva) return null;
    catalogo = ordenarCategorias([
      ...catalogo.filter((item) => item.codigo !== nueva.codigo),
      nueva
    ]);
    if (seleccionarNueva) seleccion.add(nueva.codigo);
    if (!principal && seleccionarNueva) principal = nueva.codigo;
    pintar();
    const control = [...contenedor.querySelectorAll('.cm-categoria-check input')]
      .find((input) => input.value === nueva.codigo);
    control?.focus();
    return nueva;
  }

  function validar() {
    const actual = valor();
    if (!actual.codigos.length) {
      return {
        ok: false,
        mensaje: 'Elige al menos una categoría para guardar la campaña.',
        elemento: contenedor.querySelector('input[type="checkbox"]')
      };
    }
    if (actual.codigos.length > 12) {
      return {
        ok: false,
        mensaje: 'Elige como máximo 12 categorías.',
        elemento: contenedor.querySelector('.cm-categoria-check input:checked')
      };
    }
    if (!actual.principal || !actual.codigos.includes(actual.principal)) {
      return {
        ok: false,
        mensaje: 'Marca una de las categorías elegidas como principal.',
        elemento: contenedor.querySelector('.cm-categoria-principal input:not(:disabled)')
      };
    }
    return { ok: true, ...actual };
  }

  pintar();

  return Object.freeze({
    valor,
    validar,
    seleccionar,
    agregarCategoria,
    categoria,
    lista: () => catalogo.map((item) => ({ ...item }))
  });
}

export function crearDialogoCategoria({ botonAbrir = null, onCreada = () => {} } = {}) {
  const id = ++secuencia;
  const tituloId = 'cm-categoria-dialogo-titulo-' + id;
  const ayudaId = 'cm-categoria-dialogo-ayuda-' + id;
  const nombreIconos = 'cm-categoria-icono-' + id;
  let guardando = false;

  const dialogo = document.createElement('dialog');
  dialogo.className = 'cm-categoria-dialogo';
  dialogo.setAttribute('aria-labelledby', tituloId);
  dialogo.setAttribute('aria-describedby', ayudaId);

  const formulario = document.createElement('form');
  formulario.className = 'cm-categoria-dialogo-form';
  formulario.noValidate = true;

  const cabecera = document.createElement('div');
  cabecera.className = 'cm-categoria-dialogo-cab';
  const titulos = document.createElement('div');
  const kicker = document.createElement('span');
  kicker.className = 'cm-categoria-dialogo-kicker';
  kicker.textContent = 'CATÁLOGO PÚBLICO';
  const titulo = document.createElement('h2');
  titulo.id = tituloId;
  titulo.textContent = 'Crear nueva categoría';
  const ayuda = document.createElement('p');
  ayuda.id = ayudaId;
  ayuda.textContent = 'Quedará activa y visible de inmediato. El código web se deriva de forma segura en el servidor.';
  titulos.append(kicker, titulo, ayuda);

  const cerrar = document.createElement('button');
  cerrar.type = 'button';
  cerrar.className = 'cm-categoria-dialogo-cerrar';
  cerrar.setAttribute('aria-label', 'Cerrar diálogo');
  cerrar.innerHTML = '<span aria-hidden="true">×</span>';
  cabecera.append(titulos, cerrar);

  const cuerpo = document.createElement('div');
  cuerpo.className = 'cm-categoria-dialogo-cuerpo';

  const campos = document.createElement('div');
  campos.className = 'cm-categoria-dialogo-campos';

  const campoNombre = document.createElement('label');
  campoNombre.className = 'cm-campo';
  const etiquetaNombre = document.createElement('span');
  etiquetaNombre.className = 'cm-campo-lbl';
  etiquetaNombre.textContent = 'Nombre *';
  const inputNombre = document.createElement('input');
  inputNombre.className = 'mk-input';
  inputNombre.type = 'text';
  inputNombre.minLength = 2;
  inputNombre.maxLength = 80;
  inputNombre.required = true;
  inputNombre.autocomplete = 'off';
  inputNombre.placeholder = 'Ej. Papelería creativa';
  campoNombre.append(etiquetaNombre, inputNombre);

  const campoDescripcion = document.createElement('label');
  campoDescripcion.className = 'cm-campo';
  const etiquetaDescripcion = document.createElement('span');
  etiquetaDescripcion.className = 'cm-campo-lbl';
  etiquetaDescripcion.textContent = 'Descripción para la banda pública *';
  const inputDescripcion = document.createElement('textarea');
  inputDescripcion.className = 'mk-input';
  inputDescripcion.maxLength = 240;
  inputDescripcion.required = true;
  inputDescripcion.rows = 4;
  inputDescripcion.placeholder = 'Una frase breve que ayude a entender qué reúne esta categoría.';
  const contador = document.createElement('span');
  contador.className = 'cm-categoria-contador';
  contador.textContent = '0 / 240';
  campoDescripcion.append(etiquetaDescripcion, inputDescripcion, contador);

  const iconosFieldset = document.createElement('fieldset');
  iconosFieldset.className = 'cm-categoria-iconos-fieldset';
  const iconosLegend = document.createElement('legend');
  iconosLegend.className = 'cm-campo-lbl';
  iconosLegend.textContent = 'Ícono *';
  const iconosAyuda = document.createElement('span');
  iconosAyuda.className = 'cm-campo-ayuda';
  iconosAyuda.textContent = 'Elige uno de los íconos controlados de MAGANDHI.';
  const iconosGrid = document.createElement('div');
  iconosGrid.className = 'cm-categoria-iconos';

  ICONOS_CATEGORIA.forEach((item, indice) => {
    const label = document.createElement('label');
    label.className = 'cm-categoria-icono-opcion';
    const radio = document.createElement('input');
    radio.type = 'radio';
    radio.name = nombreIconos;
    radio.value = item.codigo;
    radio.defaultChecked = indice === 0;
    radio.checked = indice === 0;
    const dibujo = document.createElement('span');
    dibujo.className = 'cm-categoria-icono-dibujo';
    dibujo.innerHTML = item.svg;
    dibujo.setAttribute('aria-hidden', 'true');
    const texto = document.createElement('span');
    texto.textContent = item.nombre;
    label.append(radio, dibujo, texto);
    iconosGrid.appendChild(label);
  });
  iconosFieldset.append(iconosLegend, iconosAyuda, iconosGrid);
  campos.append(campoNombre, campoDescripcion, iconosFieldset);

  const previewCol = document.createElement('div');
  previewCol.className = 'cm-categoria-alta-preview-col';
  const previewLabel = document.createElement('span');
  previewLabel.className = 'cm-preview-lbl';
  previewLabel.textContent = 'Vista previa de la banda pública';
  const preview = document.createElement('div');
  preview.className = 'cm-categoria-alta-preview';
  const previewIcono = document.createElement('span');
  previewIcono.className = 'cm-categoria-alta-preview-icono';
  previewIcono.setAttribute('aria-hidden', 'true');
  const previewTexto = document.createElement('div');
  const previewNombre = document.createElement('strong');
  const previewDescripcion = document.createElement('span');
  previewTexto.append(previewNombre, previewDescripcion);
  preview.append(previewIcono, previewTexto);
  previewCol.append(previewLabel, preview);

  cuerpo.append(campos, previewCol);

  const mensaje = document.createElement('p');
  mensaje.className = 'cm-form-msg err cm-categoria-dialogo-msg';
  mensaje.setAttribute('role', 'alert');
  mensaje.hidden = true;

  const acciones = document.createElement('div');
  acciones.className = 'cm-categoria-dialogo-acciones';
  const cancelar = document.createElement('button');
  cancelar.type = 'button';
  cancelar.className = 'cm-btn-secundario';
  cancelar.textContent = 'Cancelar';
  const guardar = document.createElement('button');
  guardar.type = 'submit';
  guardar.className = 'cm-btn-primario';
  guardar.textContent = 'Crear categoría';
  acciones.append(cancelar, guardar);

  formulario.append(cabecera, cuerpo, mensaje, acciones);
  dialogo.appendChild(formulario);
  document.body.appendChild(dialogo);

  function iconoElegido() {
    return formulario.querySelector('input[name="' + nombreIconos + '"]:checked')?.value || '';
  }

  function actualizarPreview() {
    const codigoIcono = iconoElegido() || ICONOS_CATEGORIA[0].codigo;
    previewIcono.innerHTML = iconoCategoria(codigoIcono);
    previewNombre.textContent = inputNombre.value.trim() || 'Nombre de la categoría';
    previewDescripcion.textContent = inputDescripcion.value.trim() ||
      'La descripción aparecerá aquí como apoyo para explorar la tienda.';
    contador.textContent = inputDescripcion.value.length + ' / 240';
  }

  function mostrarError(texto) {
    mensaje.textContent = texto;
    mensaje.hidden = false;
  }

  function cambiarGuardando(activo) {
    guardando = activo;
    guardar.disabled = activo;
    cancelar.disabled = activo;
    cerrar.disabled = activo;
    guardar.textContent = activo ? 'Creando categoría…' : 'Crear categoría';
    if (activo) formulario.setAttribute('aria-busy', 'true');
    else formulario.removeAttribute('aria-busy');
  }

  function abrir() {
    if (dialogo.open || dialogo.hasAttribute('open')) return;
    formulario.reset();
    mensaje.hidden = true;
    mensaje.textContent = '';
    cambiarGuardando(false);
    actualizarPreview();
    if (typeof dialogo.showModal === 'function') dialogo.showModal();
    else dialogo.setAttribute('open', '');
    requestAnimationFrame(() => inputNombre.focus());
  }

  function cerrarDialogo() {
    if (guardando) return;
    if (typeof dialogo.close === 'function') dialogo.close();
    else dialogo.removeAttribute('open');
  }

  inputNombre.addEventListener('input', actualizarPreview);
  inputDescripcion.addEventListener('input', actualizarPreview);
  iconosGrid.addEventListener('change', actualizarPreview);
  cerrar.addEventListener('click', cerrarDialogo);
  cancelar.addEventListener('click', cerrarDialogo);
  botonAbrir?.addEventListener('click', abrir);
  dialogo.addEventListener('click', (event) => {
    if (event.target === dialogo) cerrarDialogo();
  });
  dialogo.addEventListener('cancel', (event) => {
    if (guardando) event.preventDefault();
  });

  formulario.addEventListener('submit', async (event) => {
    event.preventDefault();
    mensaje.hidden = true;
    mensaje.textContent = '';

    const nombre = inputNombre.value.trim();
    const descripcion = inputDescripcion.value.trim();
    const icono_codigo = iconoElegido();

    if (nombre.length < 2 || nombre.length > 80) {
      mostrarError('El nombre debe tener entre 2 y 80 caracteres.');
      inputNombre.focus();
      return;
    }
    if (!descripcion || descripcion.length > 240) {
      mostrarError('Escribe una descripción de hasta 240 caracteres.');
      inputDescripcion.focus();
      return;
    }
    if (!ICONOS_POR_CODIGO.has(icono_codigo)) {
      mostrarError('Elige uno de los íconos disponibles.');
      iconosGrid.querySelector('input')?.focus();
      return;
    }

    cambiarGuardando(true);
    let data;
    let error;
    try {
      ({ data, error } = await supabase.rpc('cm_crear_categoria', {
        nombre,
        descripcion,
        icono_codigo
      }));
    } catch (fallo) {
      error = fallo;
    }
    cambiarGuardando(false);

    if (error) {
      mostrarError(mensajeErrorCategoria(error));
      return;
    }

    const fila = normalizarCategoria(Array.isArray(data) ? data[0] : data);
    if (!fila) {
      mostrarError('La categoría se creó, pero no se recibió su fila pública. Recarga la página.');
      return;
    }

    cerrarDialogo();
    onCreada(fila);
  });

  actualizarPreview();

  return Object.freeze({
    abrir,
    cerrar: cerrarDialogo,
    destruir: () => {
      botonAbrir?.removeEventListener('click', abrir);
      dialogo.remove();
    }
  });
}
