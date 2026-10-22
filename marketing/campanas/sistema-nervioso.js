import {
  asegurarAcceso,
  montarHeader,
  ICONOS,
  supabase,
  BUCKET_CAMPANAS,
  urlPublicaImagen,
  soportaWebP
} from '../marketing-core.js';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_INTENCIONES = 12;
const TOLERANCIA_PROPORCION = 0.03;
const MAX_ARCHIVO_BYTES = 30 * 1024 * 1024;
const MAX_BORDE_GRANDE = 2200;
const MAX_BORDE_LIVIANO = 900;
const TIPOS_IMAGEN = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/avif']);
const TIPOS_RELACION = [
  ['complementa', 'Complementa'],
  ['sustituye', 'Sustituye'],
  ['continua', 'Continúa'],
  ['rutina', 'Rutina'],
  ['descubrimiento', 'Descubrimiento'],
  ['excluir', 'Excluir']
];
const TIPOS_RELACION_VALIDOS = new Set(TIPOS_RELACION.map(([valor]) => valor));
const ZONA_HORARIA_COLOMBIA = 'America/Bogota';
const OFFSET_COLOMBIA = '-05:00';
const FECHA_LOCAL_RE = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/;
const TEXTO_COMERCIAL_RE = /\b(?:precio|precios|price|stock|costo|costos|cost|proveedor|proveedora|proveedores|supplier|suppliers)\b|(?:\$|cop\b|usd\b|eur\b)\s*[\d.,]+/i;
const CORREO_RE = /\b[a-z0-9.!#$%&'*+\/?=^_`{|}~-]+@[a-z0-9-]+(?:\.[a-z0-9-]+)+\b/iu;
const DIGITOS_RE = /\d/g;
const UUID_EN_TEXTO_RE = /\b[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\b/iu;
const HANDLE_RE = /@[\p{L}\p{N}_][\p{L}\p{N}._-]{0,63}/u;
const FORMATEADOR_FECHA_INPUT_COLOMBIA = new Intl.DateTimeFormat('en-CA', {
  timeZone: ZONA_HORARIA_COLOMBIA,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23'
});

const ROLES = [
  {
    rol: 'cuadrado',
    nombre: 'Cuadrado',
    ancho: 1600,
    alto: 1600,
    proporcion: 1,
    proporcionTexto: '1:1',
    recomendado: true,
    transparente: false,
    layout: 'Tarjetas y rejillas',
    detalle: 'Habilita composiciones cuadradas para catálogo, búsqueda y módulos compactos.'
  },
  {
    rol: 'vertical',
    nombre: 'Vertical',
    ancho: 1600,
    alto: 2000,
    proporcion: 4 / 5,
    proporcionTexto: '4:5',
    recomendado: true,
    transparente: false,
    layout: 'Portadas verticales',
    detalle: 'Habilita resultados editoriales y superficies móviles en proporción 4:5.'
  },
  {
    rol: 'horizontal',
    nombre: 'Horizontal',
    ancho: 1920,
    alto: 1080,
    proporcion: 16 / 9,
    proporcionTexto: '16:9',
    recomendado: true,
    transparente: false,
    layout: 'Portadas horizontales',
    detalle: 'Habilita módulos anchos, recomendaciones y portadas en proporción 16:9.'
  },
  {
    rol: 'panoramico',
    nombre: 'Panorámico',
    ancho: 2000,
    alto: 1000,
    proporcion: 2,
    proporcionTexto: '2:1',
    recomendado: false,
    transparente: false,
    layout: 'Banners panorámicos',
    detalle: 'Habilita franjas editoriales y cabeceras amplias en proporción 2:1.'
  },
  {
    rol: 'recorte',
    nombre: 'Recorte',
    ancho: 2000,
    alto: 2000,
    proporcion: 1,
    proporcionTexto: '1:1',
    recomendado: false,
    transparente: true,
    layout: 'Composición con recorte',
    detalle: 'Habilita capas y composiciones sobre fondos variables; conserva transparencia.'
  }
];
const ROLES_POR_ID = new Map(ROLES.map((rol) => [rol.rol, rol]));
const ICONO_IMAGEN = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.5-3.5a2 2 0 0 0-2.8 0L4 22"/></svg>';
const ICONO_QUITAR = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M18 6 6 18M6 6l12 12"/></svg>';

const $ = (id) => document.getElementById(id);
const crear = (tag, clase, texto) => {
  const elemento = document.createElement(tag);
  if (clase) elemento.className = clase;
  if (texto !== undefined) elemento.textContent = texto;
  return elemento;
};
const limitar = (valor, minimo, maximo, respaldo) => {
  const numero = Number(valor);
  return Number.isFinite(numero) ? Math.min(maximo, Math.max(minimo, numero)) : respaldo;
};

let campanaId = '';
let detalleActual = null;
let candidatas = [];
let estadosAssets = new Map();
let contadorRelaciones = 0;
let secuenciaCarga = 0;
let controladorCarga = null;
let configuracionSucia = false;
let inicializado = false;

function errorUsuario(mensaje) {
  const error = new Error(mensaje);
  error.esUsuario = true;
  return error;
}

function textoError(error, contexto = 'lectura') {
  if (error?.esUsuario) return error.message;
  const bruto = String(error?.message || error || '');
  if (/AbortError|aborted/i.test(bruto)) return 'La operación anterior fue reemplazada.';
  if (/SN_CAMPANA_NO_(?:EXISTE|ENCONTRADA)|not found/i.test(bruto)) return 'La campaña no existe o no está disponible para esta cuenta.';
  if (/SN_CAMPANA_(?:INACTIVA|PLACEHOLDER)|SN_SOLO_CAMPANA_REAL/i.test(bruto)) return 'El sistema nervioso solo se edita en campañas reales y activas.';
  if (/permission denied|42501|SN_(?:SIN_)?ACCESO/i.test(bruto)) return 'Tu cuenta no tiene permiso para completar esta operación.';
  if (/SN_PRIORIDAD_INVALIDA/i.test(bruto)) return 'La prioridad debe ser un entero entre −20 y 20.';
  if (/SN_INTENCIONES/i.test(bruto)) return 'Las intenciones no cumplen el contrato semántico del servidor.';
  if (/SN_RELACION/i.test(bruto)) return 'Revisa destino, tipo, peso y combinaciones repetidas de las relaciones.';
  if (/SN_ASSET_DIMENSIONES/i.test(bruto)) return 'Las dimensiones o la proporción del activo no cumplen la guía de este rol.';
  if (/SN_ASSET_FOCO/i.test(bruto)) return 'El foco debe permanecer entre 0 y 100 en ambos ejes.';
  if (/SN_ASSET_ALT/i.test(bruto)) return 'El texto alternativo debe ser visual, tener entre 3 y 240 caracteres y no incluir contacto, identificadores ni datos comerciales.';
  if (/SN_ASSET_(?:PATH|EXTENSION|MIME|ROL|VERSION)/i.test(bruto)) return 'El registro del activo no coincide con el rol, formato o key inmutable esperados.';
  if (/PGRST202|function[^\n]*(?:not found|does not exist)/i.test(bruto)) return 'Las funciones SN1 todavía no están disponibles en Supabase.';
  if (/row-level security|unauthorized|jwt|session/i.test(bruto)) return 'La sesión no pudo autorizar la operación. Recarga la página e inténtalo de nuevo.';
  if (/payload|contrato|invalid/i.test(bruto)) return 'El servidor respondió con datos incompletos; no mostramos una configuración dudosa.';
  if (contexto === 'storage') return 'No se pudieron subir los archivos al almacenamiento de Campañas.';
  if (contexto === 'guardar') return 'No se pudo guardar. La configuración anterior se conserva completa.';
  if (contexto === 'retirar') return 'No se pudo retirar el activo. El archivo y su registro siguen sin cambios.';
  return 'No se pudo completar la lectura. Revisa la conexión e inténtalo de nuevo.';
}

function ocultarEstados() {
  $('sn-carga').hidden = true;
  $('sn-error').hidden = true;
  $('sn-contenido').hidden = true;
}

function mostrarCarga() {
  ocultarEstados();
  $('sn-flash').hidden = true;
  $('sn-carga').hidden = false;
  $('sn-carga').setAttribute('aria-busy', 'true');
}

function mostrarError(error) {
  ocultarEstados();
  $('sn-error-texto').textContent = textoError(error);
  $('sn-error').hidden = false;
  $('sn-error').focus();
}

function mostrarFlash(texto, tipo = 'ok', enfocar = false) {
  const flash = $('sn-flash');
  flash.textContent = texto;
  flash.className = 'sn-flash' + (tipo === 'ok' ? '' : ' ' + tipo);
  flash.hidden = false;
  if (enfocar) flash.focus();
}

function mostrarMensajeConfiguracion(texto, tipo = 'err', enfocar = true) {
  const mensaje = $('sn-config-mensaje');
  mensaje.textContent = texto;
  mensaje.className = 'cm-form-msg ' + tipo;
  mensaje.setAttribute('role', tipo === 'err' ? 'alert' : 'status');
  mensaje.hidden = false;
  if (enfocar) mensaje.focus();
}

function ocultarMensajeConfiguracion() {
  const mensaje = $('sn-config-mensaje');
  mensaje.hidden = true;
  mensaje.textContent = '';
}

function normalizarRol(valor) {
  return String(valor || '')
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .toLowerCase().trim().replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function normalizarIntenciones(valor) {
  const partes = Array.isArray(valor) ? valor : String(valor || '').split(/[\n,]+/);
  const unicas = new Map();
  partes.forEach((parte) => {
    const limpia = String(parte || '').normalize('NFKC').trim().replace(/\s+/g, ' ').toLocaleLowerCase('es');
    if (!limpia) return;
    const clave = limpia.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('es');
    if (!unicas.has(clave)) unicas.set(clave, limpia);
  });
  return [...unicas.values()];
}

function objetoDetalle(respuesta) {
  let valor = respuesta;
  if (Array.isArray(valor)) valor = valor[0] || null;
  if (valor && typeof valor === 'object' && valor.detalle && typeof valor.detalle === 'object') valor = valor.detalle;
  if (!valor || typeof valor !== 'object') throw errorUsuario('El servidor no devolvió el detalle de la campaña.');
  return valor;
}

function aLista(valor) {
  if (Array.isArray(valor)) return valor;
  if (!valor || typeof valor !== 'object') return [];
  return Object.entries(valor).map(([clave, item]) => {
    if (item && typeof item === 'object') return { ...item, rol: item.rol || clave };
    return null;
  }).filter(Boolean);
}

function normalizarRelacion(relacion) {
  const destino = relacion?.destino && typeof relacion.destino === 'object' ? relacion.destino : null;
  const destinoId = relacion?.campana_destino_id || relacion?.destino_campana_id ||
    relacion?.destino_campana_producto_id || relacion?.destino_id || destino?.id || relacion?.campana_id || '';
  const tipo = TIPOS_RELACION_VALIDOS.has(relacion?.tipo) ? relacion.tipo : 'complementa';
  const peso = Math.round(limitar(relacion?.peso, 1, 100, 50));
  return {
    destinoId: String(destinoId || ''),
    destinoNombre: String(relacion?.destino_nombre || destino?.nombre || ''),
    tipo,
    peso
  };
}

function normalizarFoco(valor) {
  const numero = Number(valor);
  if (!Number.isFinite(numero)) return 50;
  if (numero >= 0 && numero <= 1) return Math.round(numero * 100);
  return Math.round(limitar(numero, 0, 100, 50));
}

function normalizarAsset(asset) {
  const rol = normalizarRol(asset?.rol || asset?.tipo || asset?.asset_rol);
  if (!ROLES_POR_ID.has(rol)) return null;
  if (asset?.activo === false || asset?.retirado === true || asset?.retirado_en) return null;
  const storagePath = String(asset?.storage_path || asset?.path || asset?.storage_key || '');
  if (!storagePath) return null;
  return {
    id: String(asset?.asset_id || asset?.id || ''),
    rol,
    storagePath,
    mime: String(asset?.mime || asset?.content_type || 'image/webp'),
    ancho: Math.max(0, Math.round(Number(asset?.ancho || asset?.width) || 0)),
    alto: Math.max(0, Math.round(Number(asset?.alto || asset?.height) || 0)),
    focoX: normalizarFoco(asset?.foco_x ?? asset?.focoX),
    focoY: normalizarFoco(asset?.foco_y ?? asset?.focoY),
    alt: String(asset?.alt || asset?.texto_alt || ''),
    actualizadoEn: String(asset?.actualizado_en || asset?.creado_en || '')
  };
}

function normalizarDetalle(respuesta) {
  const raiz = objetoDetalle(respuesta);
  const campana = raiz.campana || raiz.campana_producto || raiz.producto || raiz;
  const configuracion = raiz.configuracion || raiz.config || raiz.semantica || raiz.sistema_nervioso || raiz;
  const id = String(campana?.id || campana?.campana_id || campana?.campana_producto_id || raiz.campana_id || configuracion?.campana_id || '');
  if (!UUID_RE.test(id) || id.toLowerCase() !== campanaId.toLowerCase()) {
    throw errorUsuario('La respuesta no corresponde a la campaña solicitada.');
  }

  const relacionesRaw = raiz.relaciones ?? configuracion.relaciones ?? [];
  const contenedorActivos = raiz.assets ?? raiz.activos ?? raiz.activos_por_rol ?? configuracion.assets ?? configuracion.activos ?? [];
  const activosRaw = Array.isArray(contenedorActivos)
    ? contenedorActivos
    : (contenedorActivos?.activos ?? contenedorActivos);
  const activos = new Map();
  aLista(activosRaw).forEach((item) => {
    const asset = normalizarAsset(item);
    if (!asset) return;
    const anterior = activos.get(asset.rol);
    if (!anterior || asset.actualizadoEn >= anterior.actualizadoEn) activos.set(asset.rol, asset);
  });

  const intencionesRaw = configuracion.intenciones ?? configuracion.casos_uso ?? [];
  const prioridadRaw = Number(configuracion.prioridad);
  return {
    campana: {
      id,
      nombre: String(campana?.nombre || 'Campaña sin nombre'),
      publicado: campana?.publicado === true || campana?.estado === 'publicada',
      activo: campana?.activo !== false && campana?.estado !== 'inactiva' && campana?.estado !== 'retirada',
      esPlaceholder: campana?.es_placeholder === true || campana?.placeholder === true
    },
    configuracion: {
      prioridad: Number.isInteger(prioridadRaw) ? Math.min(20, Math.max(-20, prioridadRaw)) : 0,
      intenciones: normalizarIntenciones(intencionesRaw),
      disponibleDesde: configuracion.disponible_desde || null,
      disponibleHasta: configuracion.disponible_hasta || null
    },
    relaciones: aLista(relacionesRaw)
      .filter((relacion) => relacion?.activo !== false && !relacion?.retirado_en)
      .map(normalizarRelacion).filter((relacion) => relacion.destinoId),
    activos
  };
}

function formatearFechaInputColombia(fecha) {
  const partes = {};
  FORMATEADOR_FECHA_INPUT_COLOMBIA.formatToParts(fecha).forEach(({ type, value }) => {
    if (type !== 'literal') partes[type] = value;
  });
  return `${partes.year}-${partes.month}-${partes.day}T${partes.hour}:${partes.minute}`;
}

function instanteDesdeFechaLocalColombia(valor) {
  if (!FECHA_LOCAL_RE.test(valor)) return null;
  const fecha = new Date(`${valor}:00${OFFSET_COLOMBIA}`);
  if (Number.isNaN(fecha.getTime())) return null;
  return formatearFechaInputColombia(fecha) === valor ? fecha : null;
}

function instanteDesdeServidor(valor) {
  if (!valor) return null;
  const texto = String(valor).trim().replace(/^(\d{4}-\d{2}-\d{2})\s/, '$1T');
  if (/^\d{4}-\d{2}-\d{2}$/.test(texto)) {
    return instanteDesdeFechaLocalColombia(`${texto}T00:00`);
  }
  if (FECHA_LOCAL_RE.test(texto)) return instanteDesdeFechaLocalColombia(texto);
  if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?$/.test(texto)) {
    const fechaColombia = new Date(`${texto}${OFFSET_COLOMBIA}`);
    return Number.isNaN(fechaColombia.getTime()) ? null : fechaColombia;
  }
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+-]\d{2}:?\d{2})$/i.test(texto)) {
    return null;
  }
  const fecha = new Date(texto);
  return Number.isNaN(fecha.getTime()) ? null : fecha;
}

function fechaInput(valor) {
  const fecha = instanteDesdeServidor(valor);
  return fecha ? formatearFechaInputColombia(fecha) : '';
}

function fechaLegible(valor) {
  if (!valor) return '';
  const fecha = instanteDesdeServidor(valor);
  if (!fecha) return String(valor);
  return new Intl.DateTimeFormat('es-CO', {
    dateStyle: 'medium', timeStyle: 'short', timeZone: ZONA_HORARIA_COLOMBIA
  }).format(fecha);
}

function ventanaLegible(configuracion) {
  const desde = configuracion.disponibleDesde;
  const hasta = configuracion.disponibleHasta;
  if (!desde && !hasta) return 'Siempre disponible';
  if (desde && hasta) return `${fechaLegible(desde)} — ${fechaLegible(hasta)}`;
  if (desde) return `Desde ${fechaLegible(desde)}`;
  return `Hasta ${fechaLegible(hasta)}`;
}

function agregarChip(contenedor, texto, clase) {
  const chip = crear('span', 'sn-chip ' + clase, texto);
  contenedor.appendChild(chip);
}

function actualizarResumen() {
  if (!detalleActual) return;
  const { campana, configuracion, relaciones, activos } = detalleActual;
  $('sn-resumen-titulo').textContent = campana.nombre;
  $('sn-campana-id').textContent = campana.id;
  const chips = $('sn-campana-chips');
  chips.replaceChildren();
  agregarChip(chips, campana.publicado ? 'Publicada' : 'Borrador', campana.publicado ? 'publicada' : 'borrador');
  agregarChip(chips, 'Activa', 'activa');

  const totalActivos = ROLES.filter((rol) => activos.has(rol.rol)).length;
  const recomendados = ROLES.filter((rol) => rol.recomendado && activos.has(rol.rol)).length;
  const tieneSemantica = configuracion.intenciones.length > 0;
  const puntos = 1 + (tieneSemantica ? 1 : 0) + recomendados;
  const porcentaje = Math.round((puntos / 5) * 100);
  let estado = 'En preparación';
  let detalle = 'Completa las intenciones y los tres formatos recomendados.';
  if (puntos === 1) {
    estado = 'Configuración inicial';
    detalle = 'La campaña está conectada; faltan señales semánticas y activos recomendados.';
  } else if (puntos === 5) {
    estado = 'Cobertura recomendada completa';
    detalle = 'Tiene intención editorial y los formatos cuadrado, vertical y horizontal.';
  }
  $('sn-preparacion-estado').textContent = estado;
  $('sn-preparacion-detalle').textContent = detalle;
  $('sn-preparacion-barra').style.width = porcentaje + '%';
  $('sn-resumen-intenciones').textContent = String(configuracion.intenciones.length);
  $('sn-resumen-relaciones').textContent = String(relaciones.length);
  $('sn-resumen-activos').textContent = totalActivos + '/5';
  $('sn-resumen-ventana').textContent = ventanaLegible(configuracion);

  const verificaciones = [
    { ok: campana.activo && !campana.esPlaceholder, texto: 'Campaña real y activa' },
    { ok: tieneSemantica, texto: tieneSemantica ? 'Intenciones normalizadas' : 'Falta al menos una intención' },
    { ok: recomendados === 3, texto: recomendados === 3 ? 'Cobertura recomendada 3/3' : `Cobertura recomendada ${recomendados}/3` }
  ];
  const lista = $('sn-checklist');
  lista.replaceChildren();
  verificaciones.forEach((item) => {
    const li = crear('li', item.ok ? 'ok' : 'pendiente');
    li.append(crear('span', 'marca', item.ok ? '✓' : '·'), document.createTextNode(item.texto));
    lista.appendChild(li);
  });
}

function refrescarIntenciones() {
  const intenciones = normalizarIntenciones($('sn-intenciones').value);
  const contenedor = $('sn-intenciones-chips');
  contenedor.replaceChildren();
  if (!intenciones.length) {
    contenedor.appendChild(crear('span', 'sn-intenciones-vacio', 'Sin intenciones todavía'));
  } else {
    intenciones.forEach((intencion) => contenedor.appendChild(crear('span', 'sn-intencion', intencion)));
  }
  const excedido = intenciones.length > MAX_INTENCIONES;
  const contador = $('sn-intenciones-contador');
  contador.textContent = `${intenciones.length}/${MAX_INTENCIONES}`;
  contador.classList.toggle('excedido', excedido);
  $('sn-intenciones').setAttribute('aria-invalid', String(excedido));
  return intenciones;
}

function cargarFormulario() {
  const configuracion = detalleActual.configuracion;
  $('sn-prioridad').value = String(configuracion.prioridad);
  $('sn-intenciones').value = configuracion.intenciones.join('\n');
  $('sn-disponible-desde').value = fechaInput(configuracion.disponibleDesde);
  $('sn-disponible-hasta').value = fechaInput(configuracion.disponibleHasta);
  refrescarIntenciones();
  pintarRelaciones(detalleActual.relaciones);
  configuracionSucia = false;
  ocultarMensajeConfiguracion();
}

function opcion(texto, valor) {
  const elemento = document.createElement('option');
  elemento.value = valor;
  elemento.textContent = texto;
  return elemento;
}

function agregarRelacion(relacion = null, enfocar = false) {
  const paresUsados = new Set([...document.querySelectorAll('.sn-relacion')].map((fila) => {
    const destino = fila.querySelector('.sn-relacion-destino')?.value || '';
    const tipo = fila.querySelector('.sn-relacion-tipo')?.value || '';
    return `${destino}|${tipo}`;
  }));
  let tipoInicial = relacion?.tipo || 'complementa';
  let destinoInicial = relacion?.destinoId || '';
  if (!destinoInicial) {
    for (const [tipoDisponible] of TIPOS_RELACION) {
      const candidata = candidatas.find((item) => !paresUsados.has(`${item.id}|${tipoDisponible}`));
      if (candidata) {
        destinoInicial = candidata.id;
        tipoInicial = tipoDisponible;
        break;
      }
    }
  }
  const numero = ++contadorRelaciones;
  const fila = crear('div', 'sn-relacion');
  fila.dataset.relacion = String(numero);
  fila.setAttribute('role', 'group');
  fila.setAttribute('aria-label', `Relación ${numero}`);

  const destinoCampo = crear('div', 'sn-relacion-campo');
  const destinoLabel = crear('label', '', 'Campaña destino');
  const destino = document.createElement('select');
  destino.className = 'mk-select sn-relacion-destino';
  destino.id = `sn-relacion-destino-${numero}`;
  destino.required = true;
  destinoLabel.htmlFor = destino.id;
  destino.appendChild(opcion('Selecciona una campaña', ''));
  candidatas.forEach((candidata) => {
    const sufijo = candidata.publicado ? ' · publicada' : ' · borrador';
    destino.appendChild(opcion(candidata.nombre + sufijo, candidata.id));
  });
  if (destinoInicial && !candidatas.some((candidata) => candidata.id === destinoInicial)) {
    const noDisponible = opcion((relacion?.destinoNombre || 'Destino no disponible') + ' · inactiva o retirada', destinoInicial);
    noDisponible.disabled = true;
    destino.appendChild(noDisponible);
  }
  destino.value = destinoInicial;
  destinoCampo.append(destinoLabel, destino);

  const tipoCampo = crear('div', 'sn-relacion-campo');
  const tipoLabel = crear('label', '', 'Tipo');
  const tipo = document.createElement('select');
  tipo.className = 'mk-select sn-relacion-tipo';
  tipo.id = `sn-relacion-tipo-${numero}`;
  tipoLabel.htmlFor = tipo.id;
  TIPOS_RELACION.forEach(([valor, etiqueta]) => tipo.appendChild(opcion(etiqueta, valor)));
  tipo.value = tipoInicial;
  tipoCampo.append(tipoLabel, tipo);

  const pesoCampo = crear('div', 'sn-relacion-campo');
  const pesoLabel = crear('label', '', 'Peso');
  const peso = document.createElement('input');
  peso.className = 'mk-input sn-relacion-peso';
  peso.id = `sn-relacion-peso-${numero}`;
  peso.type = 'number';
  peso.min = '1';
  peso.max = '100';
  peso.step = '1';
  peso.inputMode = 'numeric';
  peso.required = true;
  peso.value = String(relacion?.peso || 50);
  pesoLabel.htmlFor = peso.id;
  pesoCampo.append(pesoLabel, peso);

  const quitar = crear('button', 'sn-relacion-quitar');
  quitar.type = 'button';
  quitar.setAttribute('aria-label', `Quitar relación ${numero}`);
  quitar.innerHTML = ICONO_QUITAR;
  quitar.addEventListener('click', () => {
    fila.remove();
    marcarConfiguracionSucia();
    actualizarRelacionesVacias();
    actualizarOpcionesRelaciones();
  });
  [destino, tipo, peso].forEach((control) => {
    control.addEventListener('change', () => {
      marcarConfiguracionSucia();
      if (control === destino || control === tipo) actualizarOpcionesRelaciones();
    });
    control.addEventListener('input', marcarConfiguracionSucia);
  });

  fila.append(destinoCampo, tipoCampo, pesoCampo, quitar);
  $('sn-relaciones').appendChild(fila);
  actualizarRelacionesVacias();
  actualizarOpcionesRelaciones();
  if (enfocar) destino.focus();
}

function pintarRelaciones(relaciones) {
  $('sn-relaciones').replaceChildren();
  contadorRelaciones = 0;
  relaciones.forEach((relacion) => agregarRelacion(relacion));
  actualizarRelacionesVacias();
  actualizarOpcionesRelaciones();
}

function actualizarRelacionesVacias() {
  const filas = $('sn-relaciones').children;
  if (!filas.length) {
    const vacio = $('sn-relaciones-vacio');
    vacio.textContent = candidatas.length
      ? 'Aún no hay relaciones. Son opcionales.'
      : 'No hay otras campañas reales y activas disponibles para relacionar.';
  }
  $('sn-relaciones-vacio').hidden = filas.length > 0;
}

function actualizarOpcionesRelaciones() {
  const filas = [...document.querySelectorAll('.sn-relacion')];
  filas.forEach((fila) => {
    const select = fila.querySelector('.sn-relacion-destino');
    const tipo = fila.querySelector('.sn-relacion-tipo')?.value || '';
    const paresAjenos = new Set(filas.filter((otra) => otra !== fila).map((otra) =>
      `${otra.querySelector('.sn-relacion-destino')?.value || ''}|${otra.querySelector('.sn-relacion-tipo')?.value || ''}`
    ));
    [...select.options].forEach((item) => {
      if (!item.value || !candidatas.some((candidata) => candidata.id === item.value)) return;
      item.disabled = paresAjenos.has(`${item.value}|${tipo}`);
    });
  });
  const maximo = Math.min(100, candidatas.length * TIPOS_RELACION.length);
  const boton = $('sn-relacion-agregar');
  boton.disabled = candidatas.length === 0 || filas.length >= maximo;
  boton.title = candidatas.length === 0
    ? 'No hay otras campañas reales y activas disponibles.'
    : (filas.length >= maximo ? 'Ya se usaron todas las combinaciones disponibles.' : '');
}

function recolectarRelaciones() {
  const filas = [...document.querySelectorAll('.sn-relacion')];
  const claves = new Set();
  return filas.map((fila, indice) => {
    const destino = fila.querySelector('.sn-relacion-destino');
    const tipo = fila.querySelector('.sn-relacion-tipo');
    const peso = fila.querySelector('.sn-relacion-peso');
    const destinoId = destino.value;
    if (!UUID_RE.test(destinoId) || destinoId.toLowerCase() === campanaId.toLowerCase() || !candidatas.some((candidata) => candidata.id === destinoId)) {
      destino.setAttribute('aria-invalid', 'true');
      destino.focus();
      throw errorUsuario(`Elige una campaña destino activa en la relación ${indice + 1}.`);
    }
    destino.removeAttribute('aria-invalid');
    if (!TIPOS_RELACION_VALIDOS.has(tipo.value)) {
      tipo.focus();
      throw errorUsuario(`El tipo de la relación ${indice + 1} no es válido.`);
    }
    const clave = `${destinoId}|${tipo.value}`;
    if (claves.has(clave)) {
      destino.setAttribute('aria-invalid', 'true');
      destino.focus();
      throw errorUsuario('No repitas la misma campaña destino con el mismo tipo de relación.');
    }
    claves.add(clave);
    const pesoNumero = Number(peso.value);
    if (!Number.isInteger(pesoNumero) || pesoNumero < 1 || pesoNumero > 100) {
      peso.setAttribute('aria-invalid', 'true');
      peso.focus();
      throw errorUsuario(`El peso de la relación ${indice + 1} debe ser un entero entre 1 y 100.`);
    }
    peso.removeAttribute('aria-invalid');
    return {
      destino_id: destinoId,
      tipo: tipo.value,
      peso: pesoNumero
    };
  });
}

function valorFecha(id) {
  const valor = $(id).value.trim();
  if (!valor) return null;
  const fecha = instanteDesdeFechaLocalColombia(valor);
  if (!fecha) {
    throw errorUsuario('Revisa las fechas de disponibilidad. Deben indicar una fecha y hora válidas de Colombia.');
  }
  return fecha.toISOString();
}

function marcarConfiguracionSucia() {
  configuracionSucia = true;
  const mensaje = $('sn-config-mensaje');
  if (!mensaje.hidden && mensaje.classList.contains('ok')) ocultarMensajeConfiguracion();
}

async function guardarConfiguracion(evento) {
  evento.preventDefault();
  ocultarMensajeConfiguracion();

  const prioridad = Number($('sn-prioridad').value);
  if (!Number.isInteger(prioridad) || prioridad < -20 || prioridad > 20) {
    mostrarMensajeConfiguracion('La prioridad debe ser un número entero entre −20 y 20.');
    $('sn-prioridad').focus();
    return;
  }

  const intenciones = refrescarIntenciones();
  if (intenciones.length > MAX_INTENCIONES) {
    mostrarMensajeConfiguracion(`Puedes guardar como máximo ${MAX_INTENCIONES} intenciones normalizadas.`);
    $('sn-intenciones').focus();
    return;
  }

  let disponibleDesde;
  let disponibleHasta;
  let relaciones;
  try {
    disponibleDesde = valorFecha('sn-disponible-desde');
    disponibleHasta = valorFecha('sn-disponible-hasta');
    if (disponibleDesde && disponibleHasta && new Date(disponibleDesde) >= new Date(disponibleHasta)) {
      throw errorUsuario('“Disponible hasta” debe ser posterior a “Disponible desde”.');
    }
    relaciones = recolectarRelaciones();
  } catch (error) {
    mostrarMensajeConfiguracion(textoError(error, 'guardar'));
    return;
  }

  $('sn-intenciones').value = intenciones.join('\n');
  const boton = $('sn-config-guardar');
  boton.disabled = true;
  $('sn-config-form').setAttribute('aria-busy', 'true');
  try {
    const { error } = await supabase.rpc('sn_guardar_campana_v1', {
      p_campana_id: campanaId,
      p_prioridad: prioridad,
      p_intenciones: intenciones,
      p_disponible_desde: disponibleDesde,
      p_disponible_hasta: disponibleHasta,
      p_relaciones: relaciones
    });
    if (error) throw error;
    detalleActual.configuracion = {
      prioridad,
      intenciones,
      disponibleDesde,
      disponibleHasta
    };
    detalleActual.relaciones = relaciones.map(normalizarRelacion);
    configuracionSucia = false;
    actualizarResumen();
    mostrarMensajeConfiguracion('Configuración semántica y relaciones guardadas juntas correctamente.', 'ok');
  } catch (error) {
    mostrarMensajeConfiguracion(textoError(error, 'guardar'));
  } finally {
    boton.disabled = false;
    $('sn-config-form').setAttribute('aria-busy', 'false');
  }
}

function keyLiviana(path) {
  const coincidencia = String(path || '').match(/^(.*)(\.[^.\/]+)$/);
  return coincidencia ? `${coincidencia[1]}-sm${coincidencia[2]}` : `${path}-sm`;
}

function urlAsset(asset, liviana = false) {
  if (!asset?.storagePath) return '';
  return urlPublicaImagen(liviana ? keyLiviana(asset.storagePath) : asset.storagePath);
}

function estadoInicialAsset(spec, asset) {
  return {
    spec,
    asset: asset || null,
    pending: null,
    dirty: false,
    busy: false,
    procesando: '',
    mensaje: '',
    mensajeTipo: 'ok',
    refs: null
  };
}

function limpiarPendientes() {
  estadosAssets.forEach((estado) => {
    if (estado.pending?.previewUrl) URL.revokeObjectURL(estado.pending.previewUrl);
  });
}

function pintarLayouts() {
  const contenedor = $('sn-layouts');
  contenedor.replaceChildren();
  let total = 0;
  ROLES.forEach((spec) => {
    const disponible = detalleActual.activos.has(spec.rol);
    if (disponible) total += 1;
    const item = crear('div', 'sn-layout' + (disponible ? ' disponible' : ' pendiente'));
    item.append(
      crear('b', '', spec.layout),
      crear('span', '', disponible ? `${spec.nombre} disponible` : `Requiere ${spec.nombre.toLowerCase()}`)
    );
    contenedor.appendChild(item);
  });
  $('sn-cobertura-valor').textContent = `${total}/5`;
  $('sn-cobertura-progreso').value = total;
  $('sn-cobertura-progreso').textContent = `${total} de 5`;
}

function pintarActivos() {
  limpiarPendientes();
  estadosAssets = new Map();
  const contenedor = $('sn-activos');
  contenedor.replaceChildren();
  ROLES.forEach((spec) => {
    const estado = estadoInicialAsset(spec, detalleActual.activos.get(spec.rol));
    estadosAssets.set(spec.rol, estado);
    contenedor.appendChild(crearTarjetaAsset(estado));
  });
  pintarLayouts();
}

function crearTarjetaAsset(estado) {
  const { spec } = estado;
  const tarjeta = crear('article', `sn-activo ${spec.recomendado ? 'recomendado' : 'opcional'}`);
  tarjeta.dataset.rol = spec.rol;

  const cabecera = crear('div', 'sn-activo-cab');
  const identidad = crear('div', 'sn-activo-identidad');
  const icono = crear('span', 'sn-activo-icono');
  icono.innerHTML = ICONO_IMAGEN;
  const tituloGrupo = crear('div');
  const titulo = crear('h3', '', spec.nombre);
  const guia = crear('span', 'sn-activo-guia', `${spec.ancho} × ${spec.alto} · ${spec.proporcionTexto}`);
  tituloGrupo.append(titulo, guia);
  identidad.append(icono, tituloGrupo);
  const badge = crear('span', `sn-activo-badge ${spec.recomendado ? 'recomendado' : 'opcional'}`, spec.recomendado ? 'Recomendado' : 'Opcional');
  cabecera.append(identidad, badge);

  const detalle = crear('p', 'sn-activo-layout', spec.detalle);
  const preview = crear('div', 'sn-activo-preview' + (spec.transparente ? ' transparente' : ''));
  preview.style.aspectRatio = `${spec.ancho} / ${spec.alto}`;
  const imagen = document.createElement('img');
  imagen.hidden = true;
  const vacio = crear('span', 'sn-activo-vacio', spec.transparente ? 'Sin recorte registrado. Este rol puede conservar fondo transparente.' : 'Sin activo registrado para este formato.');
  const focoMarca = crear('span', 'sn-foco-marca');
  focoMarca.setAttribute('aria-hidden', 'true');
  focoMarca.hidden = true;
  preview.append(imagen, vacio, focoMarca);

  const estadoFila = crear('div', 'sn-activo-estado');
  const estadoTexto = crear('strong', '', 'Pendiente');
  const dimensiones = crear('span', '', `Mínimo ${spec.ancho} × ${spec.alto}`);
  estadoFila.append(estadoTexto, dimensiones);

  const form = crear('div', 'sn-activo-form');
  const fileLabel = crear('label', 'cm-elegir sn-file-label');
  fileLabel.setAttribute('for', `sn-file-${spec.rol}`);
  const fileIcon = crear('span');
  fileIcon.innerHTML = ICONOS.upload || ICONO_IMAGEN;
  fileIcon.setAttribute('aria-hidden', 'true');
  const fileTexto = crear('span', '', 'Elegir archivo');
  const file = document.createElement('input');
  file.id = `sn-file-${spec.rol}`;
  file.type = 'file';
  file.accept = 'image/jpeg,image/png,image/webp,image/avif';
  fileLabel.append(fileIcon, fileTexto, file);
  const info = crear('p', 'sn-activo-info', `Mínimo ${spec.ancho} × ${spec.alto}; tolerancia de proporción ±3%. Se generarán WebP de hasta ~2200 px y ~900 px.`);

  const altGrupo = crear('div', 'sn-activo-alt');
  const altLabel = crear('label', '', 'Texto alternativo *');
  const alt = document.createElement('input');
  alt.className = 'mk-input';
  alt.id = `sn-alt-${spec.rol}`;
  alt.type = 'text';
  alt.maxLength = 240;
  alt.autocomplete = 'off';
  alt.required = true;
  alt.placeholder = 'Describe solamente lo que se ve en la imagen';
  altLabel.htmlFor = alt.id;
  altGrupo.append(altLabel, alt);

  const focos = crear('div', 'sn-focos');
  const focoX = crearControlFoco(spec, 'x', 'Foco horizontal');
  const focoY = crearControlFoco(spec, 'y', 'Foco vertical');
  focos.append(focoX.grupo, focoY.grupo);

  const acciones = crear('div', 'sn-activo-acciones');
  const guardar = crear('button', 'cm-btn-primario sn-activo-guardar', 'Subir y registrar');
  guardar.type = 'button';
  const descartar = crear('button', 'sn-activo-descartar', 'Descartar selección');
  descartar.type = 'button';
  descartar.hidden = true;
  const retirar = crear('button', 'sn-activo-retirar', 'Retirar');
  retirar.type = 'button';
  retirar.hidden = true;
  acciones.append(guardar, descartar, retirar);

  const mensaje = crear('p', 'sn-activo-mensaje');
  mensaje.setAttribute('role', 'status');
  mensaje.setAttribute('aria-live', 'polite');
  mensaje.tabIndex = -1;
  mensaje.hidden = true;

  form.append(fileLabel, info, altGrupo, focos, acciones, mensaje);
  tarjeta.append(cabecera, detalle, preview, estadoFila, form);
  estado.refs = {
    tarjeta, preview, imagen, vacio, focoMarca, estadoTexto, dimensiones,
    fileLabel, fileTexto, file, info, alt, focoX, focoY, guardar, descartar, retirar, mensaje
  };

  const asset = estado.asset;
  alt.value = asset?.alt || '';
  focoX.input.value = String(asset?.focoX ?? 50);
  focoY.input.value = String(asset?.focoY ?? 50);

  file.addEventListener('change', () => {
    const seleccionado = file.files?.[0];
    if (seleccionado) prepararArchivo(estado, seleccionado);
    file.value = '';
  });
  [alt, focoX.input, focoY.input].forEach((control) => control.addEventListener('input', () => {
    estado.dirty = estado.pending !== null || metadatosCambiaron(estado);
    actualizarTarjetaAsset(estado);
  }));
  guardar.addEventListener('click', () => guardarAsset(estado));
  retirar.addEventListener('click', () => retirarAsset(estado));
  descartar.addEventListener('click', () => descartarSeleccion(estado));

  actualizarTarjetaAsset(estado);
  return tarjeta;
}

function crearControlFoco(spec, eje, etiqueta) {
  const grupo = crear('div', 'sn-foco-control');
  const label = crear('label');
  const output = document.createElement('output');
  output.id = `sn-foco-${eje}-valor-${spec.rol}`;
  output.textContent = '50%';
  label.htmlFor = `sn-foco-${eje}-${spec.rol}`;
  label.append(document.createTextNode(etiqueta), output);
  const input = document.createElement('input');
  input.id = `sn-foco-${eje}-${spec.rol}`;
  input.type = 'range';
  input.min = '0';
  input.max = '100';
  input.step = '1';
  input.value = '50';
  input.setAttribute('aria-describedby', output.id);
  grupo.append(label, input);
  return { grupo, input, output };
}

function metadatosCambiaron(estado) {
  if (!estado.asset) {
    return Boolean(estado.refs.alt.value.trim()) || Number(estado.refs.focoX.input.value) !== 50 ||
      Number(estado.refs.focoY.input.value) !== 50;
  }
  return estado.refs.alt.value.trim().replace(/\s+/g, ' ') !== estado.asset.alt.trim().replace(/\s+/g, ' ') ||
    Number(estado.refs.focoX.input.value) !== estado.asset.focoX ||
    Number(estado.refs.focoY.input.value) !== estado.asset.focoY;
}

function aplicarFuenteImagen(estado, fuente, fuenteGrande, alt) {
  const { imagen } = estado.refs;
  if (!fuente) {
    imagen.hidden = true;
    imagen.removeAttribute('src');
    imagen.dataset.fuente = '';
    return;
  }
  if (imagen.dataset.fuente !== fuente) {
    imagen.dataset.fuente = fuente;
    let usoFallback = false;
    imagen.onerror = () => {
      if (!usoFallback && fuenteGrande && fuenteGrande !== fuente) {
        usoFallback = true;
        imagen.src = fuenteGrande;
      }
    };
    imagen.src = fuente;
  }
  imagen.alt = alt;
  imagen.hidden = false;
}

function actualizarTarjetaAsset(estado) {
  const { refs, spec, asset, pending } = estado;
  refs.tarjeta.setAttribute('aria-busy', String(estado.busy));
  const tieneFuente = Boolean(pending || asset);
  let fuente = '';
  let fuenteGrande = '';
  if (pending) {
    fuente = pending.previewUrl;
    fuenteGrande = pending.previewUrl;
  } else if (asset) {
    fuente = urlAsset(asset, true);
    fuenteGrande = urlAsset(asset, false);
  }
  aplicarFuenteImagen(estado, fuente || fuenteGrande, fuenteGrande, refs.alt.value.trim());
  refs.vacio.hidden = tieneFuente;
  refs.focoMarca.hidden = !tieneFuente;

  const focoX = Math.round(limitar(refs.focoX.input.value, 0, 100, 50));
  const focoY = Math.round(limitar(refs.focoY.input.value, 0, 100, 50));
  refs.focoX.output.textContent = `${focoX}%`;
  refs.focoY.output.textContent = `${focoY}%`;
  refs.imagen.style.objectPosition = `${focoX}% ${focoY}%`;
  refs.focoMarca.style.left = `${focoX}%`;
  refs.focoMarca.style.top = `${focoY}%`;

  if (estado.procesando) {
    refs.estadoTexto.textContent = estado.procesando;
  } else if (pending) {
    refs.estadoTexto.textContent = asset ? 'Reemplazo listo' : 'Archivo listo';
  } else if (asset) {
    refs.estadoTexto.textContent = asset.alt ? 'Registrado' : 'Requiere texto alternativo';
  } else {
    refs.estadoTexto.textContent = 'Pendiente';
  }

  if (pending) {
    refs.dimensiones.textContent = `${pending.grande.ancho} × ${pending.grande.alto} WebP · original ${pending.originalAncho} × ${pending.originalAlto}`;
  } else if (asset?.ancho && asset?.alto) {
    refs.dimensiones.textContent = `${asset.ancho} × ${asset.alto} · ${asset.mime.replace('image/', '').toUpperCase()}`;
  } else {
    refs.dimensiones.textContent = `Mínimo ${spec.ancho} × ${spec.alto}`;
  }

  refs.fileTexto.textContent = pending ? 'Cambiar selección' : (asset ? 'Elegir reemplazo' : 'Elegir archivo');
  refs.info.textContent = asset && !pending
    ? `Activo vigente. Para cambiar texto alternativo o foco, elige un reemplazo que cumpla ${spec.ancho} × ${spec.alto} y ${spec.proporcionTexto}.`
    : `Mínimo ${spec.ancho} × ${spec.alto}; tolerancia de proporción ±3%. Se generarán WebP de hasta ~2200 px y ~900 px.`;
  refs.descartar.hidden = !pending;
  refs.retirar.hidden = !asset;
  refs.retirar.disabled = estado.busy || !asset?.id;
  refs.retirar.title = asset && !asset.id ? 'El detalle no incluyó la identidad necesaria para retirar este activo.' : '';
  refs.guardar.textContent = pending ? (asset ? 'Subir reemplazo' : 'Subir y registrar') : (asset ? 'Selecciona un reemplazo' : 'Selecciona un archivo');
  refs.guardar.disabled = estado.busy || !pending;
  refs.file.disabled = estado.busy;
  refs.alt.disabled = estado.busy || Boolean(asset && !pending);
  refs.focoX.input.disabled = estado.busy || Boolean(asset && !pending);
  refs.focoY.input.disabled = estado.busy || Boolean(asset && !pending);
  refs.descartar.disabled = estado.busy;

  refs.mensaje.hidden = !estado.mensaje;
  refs.mensaje.textContent = estado.mensaje;
  refs.mensaje.className = `sn-activo-mensaje ${estado.mensajeTipo || 'ok'}`;
  refs.mensaje.setAttribute('role', estado.mensajeTipo === 'err' ? 'alert' : 'status');
}

function mensajeAsset(estado, texto, tipo = 'ok', enfocar = false) {
  estado.mensaje = texto;
  estado.mensajeTipo = tipo;
  actualizarTarjetaAsset(estado);
  if (enfocar) estado.refs.mensaje.focus();
}

function descartarSeleccion(estado) {
  if (estado.pending?.previewUrl) URL.revokeObjectURL(estado.pending.previewUrl);
  estado.pending = null;
  if (estado.asset) {
    estado.refs.alt.value = estado.asset.alt;
    estado.refs.focoX.input.value = String(estado.asset.focoX);
    estado.refs.focoY.input.value = String(estado.asset.focoY);
  }
  estado.dirty = metadatosCambiaron(estado);
  estado.mensaje = estado.asset ? 'Se descartó el reemplazo; el activo registrado no cambió.' : '';
  estado.mensajeTipo = 'ok';
  actualizarTarjetaAsset(estado);
}

async function decodificarImagen(archivo) {
  if (typeof createImageBitmap === 'function') {
    try {
      return await createImageBitmap(archivo, { imageOrientation: 'from-image' });
    } catch (_) {
      try { return await createImageBitmap(archivo); } catch (_) { /* usar Image */ }
    }
  }
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(archivo);
    const imagen = new Image();
    imagen.onload = () => {
      URL.revokeObjectURL(url);
      resolve(imagen);
    };
    imagen.onerror = () => {
      URL.revokeObjectURL(url);
      reject(errorUsuario('No pudimos leer esta imagen. Prueba con un JPEG, PNG, WebP o AVIF válido.'));
    };
    imagen.src = url;
  });
}

function validarDimensiones(spec, ancho, alto) {
  if (ancho < spec.ancho || alto < spec.alto) {
    throw errorUsuario(`${spec.nombre} necesita al menos ${spec.ancho} × ${spec.alto} px. El archivo elegido mide ${ancho} × ${alto} px.`);
  }
  const proporcion = ancho / alto;
  const diferencia = Math.abs(proporcion - spec.proporcion) / spec.proporcion;
  if (diferencia > TOLERANCIA_PROPORCION) {
    throw errorUsuario(`${spec.nombre} debe respetar ${spec.proporcionTexto} con tolerancia ±3%. La imagen elegida tiene proporción ${proporcion.toFixed(3)}.`);
  }
}

async function generarWebP(imagen, maxBorde, calidad, transparencia) {
  const anchoOriginal = imagen.width || imagen.naturalWidth;
  const altoOriginal = imagen.height || imagen.naturalHeight;
  const escala = Math.min(1, maxBorde / Math.max(anchoOriginal, altoOriginal));
  const ancho = Math.max(1, Math.round(anchoOriginal * escala));
  const alto = Math.max(1, Math.round(altoOriginal * escala));
  const canvas = document.createElement('canvas');
  canvas.width = ancho;
  canvas.height = alto;
  const contexto = canvas.getContext('2d', { alpha: transparencia });
  if (!contexto) throw errorUsuario('El navegador no pudo preparar el lienzo de imagen.');
  if (!transparencia) {
    contexto.fillStyle = '#ffffff';
    contexto.fillRect(0, 0, ancho, alto);
  }
  contexto.imageSmoothingEnabled = true;
  contexto.imageSmoothingQuality = 'high';
  contexto.drawImage(imagen, 0, 0, ancho, alto);
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/webp', calidad));
  canvas.width = 1;
  canvas.height = 1;
  if (!blob || blob.type !== 'image/webp') throw errorUsuario('Este navegador no pudo generar WebP. Actualízalo antes de subir activos.');
  return { blob, ancho, alto, mime: 'image/webp' };
}

async function procesarArchivo(archivo, spec) {
  if (!TIPOS_IMAGEN.has(String(archivo.type || '').toLowerCase())) {
    throw errorUsuario('Usa un archivo JPEG, PNG, WebP o AVIF. Otros formatos no se publican.');
  }
  if (archivo.size > MAX_ARCHIVO_BYTES) {
    throw errorUsuario('El archivo supera 30 MB. Exporta una copia más liviana sin reducir las dimensiones mínimas.');
  }
  if (!soportaWebP()) throw errorUsuario('Este navegador no puede generar WebP. Actualízalo antes de subir activos.');

  const imagen = await decodificarImagen(archivo);
  const ancho = imagen.width || imagen.naturalWidth;
  const alto = imagen.height || imagen.naturalHeight;
  try {
    validarDimensiones(spec, ancho, alto);
    const grande = await generarWebP(imagen, MAX_BORDE_GRANDE, 0.9, spec.transparente);
    const liviana = await generarWebP(imagen, MAX_BORDE_LIVIANO, 0.84, spec.transparente);
    return {
      grande,
      liviana,
      originalAncho: ancho,
      originalAlto: alto,
      previewUrl: URL.createObjectURL(grande.blob)
    };
  } finally {
    if (typeof imagen.close === 'function') imagen.close();
  }
}

async function prepararArchivo(estado, archivo) {
  estado.busy = true;
  estado.procesando = 'Validando y optimizando…';
  estado.mensaje = '';
  actualizarTarjetaAsset(estado);
  try {
    const preparado = await procesarArchivo(archivo, estado.spec);
    if (estado.pending?.previewUrl) URL.revokeObjectURL(estado.pending.previewUrl);
    estado.pending = preparado;
    estado.dirty = true;
    estado.mensaje = estado.spec.transparente
      ? 'Archivo listo. Se conservará la transparencia en ambos WebP.'
      : 'Archivo listo. Revisa el texto alternativo y el punto de foco antes de subir.';
    estado.mensajeTipo = 'ok';
  } catch (error) {
    mensajeAsset(estado, textoError(error, 'storage'), 'err', true);
  } finally {
    estado.busy = false;
    estado.procesando = '';
    actualizarTarjetaAsset(estado);
  }
}

function textoAltValido(valor) {
  const limpio = String(valor || '').normalize('NFKC').trim().replace(/\s+/g, ' ');
  if (!limpio) throw errorUsuario('El texto alternativo es obligatorio antes de registrar el activo.');
  if (limpio.length < 3) throw errorUsuario('El texto alternativo debe tener al menos 3 caracteres.');
  if (limpio.length > 240) throw errorUsuario('El texto alternativo puede tener máximo 240 caracteres.');
  if (TEXTO_COMERCIAL_RE.test(limpio)) {
    throw errorUsuario('El texto alternativo debe describir solo la imagen; retira datos comerciales u operativos.');
  }
  const demasiadosDigitos = (limpio.match(DIGITOS_RE) || []).length >= 7;
  if (CORREO_RE.test(limpio) || demasiadosDigitos || UUID_EN_TEXTO_RE.test(limpio) || HANDLE_RE.test(limpio)) {
    throw errorUsuario('El texto alternativo no puede incluir correos, teléfonos, series numéricas largas, UUID ni usuarios con @.');
  }
  return limpio;
}

function aleatorioSeguro() {
  try {
    const bytes = new Uint8Array(8);
    window.crypto.getRandomValues(bytes);
    return [...bytes].map((byte) => byte.toString(16).padStart(2, '0')).join('');
  } catch (_) {
    return Math.random().toString(36).slice(2, 14);
  }
}

function baseInmutable(rol) {
  const instante = new Date().toISOString().replace(/[-:.TZ]/g, '').slice(0, 17);
  return `sistema-nervioso/${campanaId}/${rol}-${instante}-${aleatorioSeguro()}`;
}

async function limpiarSubidas(keys) {
  if (!keys.length) return null;
  try {
    const { error } = await supabase.storage.from(BUCKET_CAMPANAS).remove(keys);
    return error || null;
  } catch (error) {
    return error;
  }
}

async function reconciliarRegistroAsset(storagePath, rolEsperado) {
  try {
    const { data, error } = await supabase
      .from('sn_asset')
      .select('id, campana_producto_id, rol, storage_path, activo, retirado_en')
      .eq('storage_path', storagePath)
      .limit(2);
    if (error) return { estado: 'indeterminado', error };
    if (!Array.isArray(data)) {
      return { estado: 'indeterminado', error: new Error('Respuesta de reconciliación incompleta.') };
    }
    if (data.length === 0) return { estado: 'ausente' };
    if (data.length !== 1) return { estado: 'divergente', filas: data };

    const fila = data[0];
    const coincide = String(fila?.storage_path || '') === storagePath &&
      String(fila?.campana_producto_id || '').toLowerCase() === campanaId.toLowerCase() &&
      normalizarRol(fila?.rol) === rolEsperado;
    if (coincide && fila?.activo === true) return { estado: 'activa_coincidente', fila };
    if (coincide && fila?.activo === false) return { estado: 'historica', fila };
    return { estado: 'divergente', fila };
  } catch (error) {
    return { estado: 'indeterminado', error };
  }
}

function errorSubidaConContexto(error, parejaSubida) {
  const fallo = new Error(String(error?.message || error || 'Falló la subida del activo.'));
  fallo.causa = error;
  fallo.parejaSubida = parejaSubida;
  return fallo;
}

async function subirPareja(estado) {
  const base = baseInmutable(estado.spec.rol);
  const keyGrande = `${base}.webp`;
  const keyLiviana = `${base}-sm.webp`;
  const subidas = [];
  try {
    const { error: errorGrande } = await supabase.storage.from(BUCKET_CAMPANAS).upload(
      keyGrande,
      estado.pending.grande.blob,
      { contentType: 'image/webp', cacheControl: '31536000', upsert: false }
    );
    if (errorGrande) throw errorGrande;
    subidas.push(keyGrande);

    const { error: errorLiviana } = await supabase.storage.from(BUCKET_CAMPANAS).upload(
      keyLiviana,
      estado.pending.liviana.blob,
      { contentType: 'image/webp', cacheControl: '31536000', upsert: false }
    );
    if (errorLiviana) throw errorLiviana;
    subidas.push(keyLiviana);
    return { keyGrande, keyLiviana, subidas };
  } catch (error) {
    // La decisión de compensar se toma fuera y solo después de consultar sn_asset.
    throw errorSubidaConContexto(error, { keyGrande, keyLiviana, subidas: [...subidas] });
  }
}

async function guardarAsset(estado) {
  $('sn-flash').hidden = true;
  let alt;
  try {
    alt = textoAltValido(estado.refs.alt.value);
    estado.refs.alt.removeAttribute('aria-invalid');
  } catch (error) {
    estado.refs.alt.setAttribute('aria-invalid', 'true');
    estado.refs.alt.focus();
    mensajeAsset(estado, textoError(error, 'guardar'), 'err', false);
    return;
  }

  if (!estado.pending) {
    mensajeAsset(
      estado,
      estado.asset
        ? 'El activo es inmutable. Elige un archivo para registrar una versión de reemplazo.'
        : 'Selecciona y valida un archivo antes de registrarlo.',
      'err',
      true
    );
    estado.refs.file.focus();
    return;
  }

  const focoX = Math.round(limitar(estado.refs.focoX.input.value, 0, 100, 50));
  const focoY = Math.round(limitar(estado.refs.focoY.input.value, 0, 100, 50));
  estado.busy = true;
  estado.procesando = 'Subiendo dos tamaños…';
  estado.mensaje = '';
  actualizarTarjetaAsset(estado);

  let pareja = null;
  let registroIntentado = false;
  let registroConfirmado = false;
  let etapa = 'storage';
  try {
    pareja = await subirPareja(estado);
    const fuente = estado.pending.grande;
    const storagePath = pareja.keyGrande;
    const mime = 'image/webp';
    const ancho = Number(fuente.ancho) || estado.refs.imagen.naturalWidth || 0;
    const alto = Number(fuente.alto) || estado.refs.imagen.naturalHeight || 0;
    if (!ancho || !alto) throw errorUsuario('No pudimos confirmar las dimensiones. Elige el archivo de nuevo para reemplazar este activo.');

    etapa = 'guardar';
    estado.procesando = 'Registrando activo…';
    actualizarTarjetaAsset(estado);
    registroIntentado = true;
    const { error } = await supabase.rpc('sn_registrar_asset_v1', {
      p_campana_id: campanaId,
      p_rol: estado.spec.rol,
      p_storage_path: storagePath,
      p_mime: mime,
      p_ancho: Math.round(ancho),
      p_alto: Math.round(alto),
      p_foco_x: focoX / 100,
      p_foco_y: focoY / 100,
      p_alt: alt
    });
    if (error) throw error;

    registroConfirmado = true;
    etapa = 'refrescar';
    estado.procesando = 'Refrescando activo…';
    actualizarTarjetaAsset(estado);
    await refrescarActivoDesdeServidor(
      estado.spec.rol,
      `${estado.spec.nombre} se subió en tamaño grande y liviano y quedó registrado.`,
      storagePath
    );
  } catch (error) {
    const parejaPendiente = pareja || error?.parejaSubida || null;
    let mensaje = textoError(error, etapa);
    let requiereAviso = false;

    if (registroConfirmado) {
      mensaje = error?.esUsuario
        ? error.message
        : 'El registro quedó confirmado, pero no se pudo refrescar la vista desde el servidor. No se borró ningún objeto; recarga y revisa el activo antes de reintentar.';
      requiereAviso = true;
    } else if (parejaPendiente?.subidas?.length) {
      estado.procesando = 'Reconciliando registro…';
      actualizarTarjetaAsset(estado);
      const reconciliacion = await reconciliarRegistroAsset(
        parejaPendiente.keyGrande,
        estado.spec.rol
      );

      if (registroIntentado && reconciliacion.estado === 'activa_coincidente') {
        registroConfirmado = true;
        estado.procesando = 'Refrescando registro reconciliado…';
        actualizarTarjetaAsset(estado);
        try {
          await refrescarActivoDesdeServidor(
            estado.spec.rol,
            `${estado.spec.nombre} quedó registrado. La respuesta inicial fue ambigua, pero se confirmó el registro activo y se refrescó desde el servidor.`,
            parejaPendiente.keyGrande
          );
          return;
        } catch (errorRefresco) {
          mensaje = errorRefresco?.esUsuario
            ? errorRefresco.message
            : 'El registro activo se confirmó al reconciliar, pero no se pudo refrescar la vista. No se borró ningún objeto; recarga y revisa el activo antes de reintentar.';
          requiereAviso = true;
        }
      } else if (reconciliacion.estado === 'historica') {
        mensaje = 'La respuesta del registro fue ambigua y se encontró una fila histórica para este path. Se conservaron ambos objetos; revisa el historial antes de reintentar.';
        requiereAviso = true;
      } else if (reconciliacion.estado === 'divergente' || reconciliacion.estado === 'activa_coincidente') {
        mensaje = 'Se encontró una fila para este path, pero no es el registro activo coincidente esperado para esta campaña y rol. Se conservaron los objetos; se requiere revisión antes de reintentar.';
        requiereAviso = true;
      } else if (reconciliacion.estado === 'ausente') {
        const errorLimpieza = await limpiarSubidas(parejaPendiente.subidas);
        const parejaCompleta = parejaPendiente.subidas.length === 2;
        const contextoFallo = registroIntentado ? 'El registro falló' : 'La subida no se completó';
        if (errorLimpieza) {
          mensaje = `${contextoFallo} y se confirmó que no existe una fila para este path, pero no se pudo completar la limpieza de ${parejaCompleta ? 'los dos objetos' : 'el objeto subido'}. Revisa Storage antes de reintentar.`;
          requiereAviso = true;
        } else {
          mensaje = `${contextoFallo}. Se confirmó que no existe una fila para este path y se compensaron ${parejaCompleta ? 'los dos objetos subidos' : 'el objeto subido'} de forma segura.`;
        }
      } else {
        mensaje = 'La operación falló y la consulta de reconciliación no pudo confirmar la ausencia de un registro. Por seguridad no se borró ningún objeto; recarga y revisa el historial antes de reintentar.';
        requiereAviso = true;
      }
    }

    if (estadosAssets.get(estado.spec.rol) === estado) {
      mensajeAsset(estado, mensaje, 'err', true);
      if (requiereAviso) mostrarFlash(mensaje, 'aviso');
    }
  } finally {
    if (estadosAssets.get(estado.spec.rol) === estado) {
      estado.busy = false;
      estado.procesando = '';
      actualizarTarjetaAsset(estado);
    }
  }
}

async function retirarAsset(estado) {
  if (!estado.asset?.id) {
    mensajeAsset(estado, 'No se recibió la identidad necesaria para retirar este activo.', 'err', true);
    return;
  }
  const confirmar = window.confirm(
    `Retirar el activo ${estado.spec.nombre}.\n\n` +
    'La baja es lógica: deja de estar vigente, pero no borra sus objetos de Storage. ¿Continuar?'
  );
  if (!confirmar) return;

  estado.busy = true;
  estado.procesando = 'Retirando registro…';
  estado.mensaje = '';
  actualizarTarjetaAsset(estado);
  try {
    // Baja lógica exclusivamente por RPC. No se elimina ningún objeto de Storage.
    const { error } = await supabase.rpc('sn_retirar_asset_v1', {
      p_asset_id: estado.asset.id
    });
    if (error) throw error;
    await refrescarActivoDesdeServidor(
      estado.spec.rol,
      `${estado.spec.nombre} fue retirado lógicamente. Sus archivos no se borraron de Storage.`
    );
  } catch (error) {
    if (estadosAssets.get(estado.spec.rol) === estado) {
      mensajeAsset(estado, textoError(error, 'retirar'), 'err', true);
    }
  } finally {
    if (estadosAssets.get(estado.spec.rol) === estado) {
      estado.busy = false;
      estado.procesando = '';
      actualizarTarjetaAsset(estado);
    }
  }
}

async function refrescarActivoDesdeServidor(rol, mensaje, storagePathEsperado = '') {
  const { data, error } = await supabase.rpc('sn_campana_detalle_v1', {
    p_campana_id: campanaId
  });
  if (error) throw error;
  const nuevoDetalle = normalizarDetalle(data);
  if (!nuevoDetalle.campana.activo || nuevoDetalle.campana.esPlaceholder) {
    throw errorUsuario('La campaña dejó de estar activa y ya no puede editar sus activos.');
  }

  const activoServidor = nuevoDetalle.activos.get(rol) || null;
  const activoEsperadoConfirmado = !storagePathEsperado || activoServidor?.storagePath === storagePathEsperado;
  detalleActual.campana = {
    ...detalleActual.campana,
    nombre: nuevoDetalle.campana.nombre || detalleActual.campana.nombre
  };
  detalleActual.activos = nuevoDetalle.activos;
  const estado = estadosAssets.get(rol);
  if (estado) {
    if (estado.pending?.previewUrl) URL.revokeObjectURL(estado.pending.previewUrl);
    estado.pending = null;
    estado.asset = activoServidor;
    estado.dirty = false;
    estado.mensaje = '';
    estado.refs.alt.value = estado.asset?.alt || '';
    estado.refs.focoX.input.value = String(estado.asset?.focoX ?? 50);
    estado.refs.focoY.input.value = String(estado.asset?.focoY ?? 50);
    actualizarTarjetaAsset(estado);
  }
  actualizarResumen();
  pintarLayouts();

  if (!activoEsperadoConfirmado) {
    throw errorUsuario('El registro se confirmó, pero el servidor no devolvió ese path como activo para la campaña y el rol esperados. No se mostró un éxito; revisa el historial antes de reintentar.');
  }
  mostrarFlash(mensaje, 'ok', true);
}

function aplicarDetalle(detalle, candidatasLeidas, campanaLeida) {
  if (!campanaLeida || String(campanaLeida.id || '').toLowerCase() !== campanaId.toLowerCase()) {
    throw errorUsuario('La campaña no existe o no está disponible para esta cuenta.');
  }
  detalle.campana = {
    id: campanaId,
    nombre: String(campanaLeida.nombre || detalle.campana.nombre || 'Campaña sin nombre'),
    publicado: campanaLeida.publicado === true,
    activo: campanaLeida.activo === true,
    esPlaceholder: campanaLeida.es_placeholder === true
  };
  if (!detalle.campana.activo || detalle.campana.esPlaceholder) {
    throw errorUsuario('El sistema nervioso solo está disponible para campañas reales y activas.');
  }
  detalleActual = detalle;
  candidatas = (candidatasLeidas || [])
    .filter((campana) => UUID_RE.test(String(campana.id || '')) && String(campana.id).toLowerCase() !== campanaId.toLowerCase() && campana.activo === true && campana.es_placeholder !== true)
    .map((campana) => ({
      id: String(campana.id),
      nombre: String(campana.nombre || 'Campaña sin nombre'),
      publicado: campana.publicado === true
    }))
    .sort((a, b) => a.nombre.localeCompare(b.nombre, 'es', { sensitivity: 'base' }));
  actualizarResumen();
  cargarFormulario();
  pintarActivos();
}

async function cargar({ mensaje = '' } = {}) {
  if (!UUID_RE.test(campanaId)) {
    mostrarError(errorUsuario('El enlace no contiene un UUID de campaña válido.'));
    return;
  }
  const secuencia = ++secuenciaCarga;
  if (controladorCarga) controladorCarga.abort();
  const controlador = new AbortController();
  controladorCarga = controlador;
  mostrarCarga();

  const temporizador = window.setTimeout(() => controlador.abort(), 12000);
  try {
    const detalleConsulta = supabase
      .rpc('sn_campana_detalle_v1', { p_campana_id: campanaId })
      .abortSignal(controlador.signal);
    const campanaConsulta = supabase
      .from('campana_producto')
      .select('id, nombre, publicado, activo, es_placeholder')
      .eq('id', campanaId)
      .maybeSingle()
      .abortSignal(controlador.signal);
    // Las candidatas se leen por el SELECT interno permitido por RLS.
    const candidatasConsulta = supabase
      .from('campana_producto')
      .select('id, nombre, publicado, activo, es_placeholder')
      .eq('activo', true)
      .eq('es_placeholder', false)
      .neq('id', campanaId)
      .order('nombre', { ascending: true })
      .abortSignal(controlador.signal);
    const [detalleRespuesta, campanaRespuesta, candidatasRespuesta] = await Promise.all([
      detalleConsulta,
      campanaConsulta,
      candidatasConsulta
    ]);
    if (secuencia !== secuenciaCarga) return;
    if (detalleRespuesta.error) throw detalleRespuesta.error;
    if (campanaRespuesta.error) throw campanaRespuesta.error;
    if (candidatasRespuesta.error) throw candidatasRespuesta.error;

    const detalle = normalizarDetalle(detalleRespuesta.data);
    limpiarPendientes();
    aplicarDetalle(detalle, candidatasRespuesta.data || [], campanaRespuesta.data);
    ocultarEstados();
    $('sn-contenido').hidden = false;
    if (mensaje) mostrarFlash(mensaje, 'ok', true);
  } catch (error) {
    if (secuencia !== secuenciaCarga || (controlador.signal.aborted && controladorCarga !== controlador)) return;
    if (controlador.signal.aborted) mostrarError(errorUsuario('La consulta tardó demasiado. Puedes reintentarlo.'));
    else mostrarError(error);
  } finally {
    window.clearTimeout(temporizador);
    if (secuencia === secuenciaCarga) $('sn-carga').setAttribute('aria-busy', 'false');
    if (controladorCarga === controlador) controladorCarga = null;
  }
}

function aclararZonaHorariaColombia() {
  [
    ['sn-disponible-desde', 'Disponible desde · hora de Colombia (opcional)', 'Vacío significa sin inicio programado. Se interpreta en hora de Colombia (UTC−5).'],
    ['sn-disponible-hasta', 'Disponible hasta · hora de Colombia (opcional)', 'Vacío significa sin cierre programado. Se interpreta en hora de Colombia (UTC−5).']
  ].forEach(([id, etiqueta, ayuda]) => {
    const input = $(id);
    const label = document.querySelector(`label[for="${id}"]`);
    if (label) label.textContent = etiqueta;
    if (input) {
      input.title = 'Hora de Colombia (America/Bogota, UTC−5)';
      const ayudaElemento = input.nextElementSibling;
      if (ayudaElemento?.classList.contains('cm-campo-ayuda')) ayudaElemento.textContent = ayuda;
    }
  });
}

function cablearPagina() {
  if (inicializado) return;
  inicializado = true;
  aclararZonaHorariaColombia();
  $('sn-reintentar').addEventListener('click', () => cargar());
  $('sn-config-form').addEventListener('submit', guardarConfiguracion);
  $('sn-relacion-agregar').addEventListener('click', () => {
    agregarRelacion(null, true);
    marcarConfiguracionSucia();
  });
  ['sn-prioridad', 'sn-disponible-desde', 'sn-disponible-hasta'].forEach((id) => {
    $(id).addEventListener('input', marcarConfiguracionSucia);
    $(id).addEventListener('change', marcarConfiguracionSucia);
  });
  $('sn-intenciones').addEventListener('input', () => {
    marcarConfiguracionSucia();
    refrescarIntenciones();
  });
  $('sn-intenciones').addEventListener('blur', () => {
    const intenciones = normalizarIntenciones($('sn-intenciones').value);
    $('sn-intenciones').value = intenciones.join('\n');
    refrescarIntenciones();
  });
  window.addEventListener('beforeunload', (evento) => {
    const hayPendientes = [...estadosAssets.values()].some((estado) => estado.pending || estado.busy || estado.dirty);
    if (!configuracionSucia && !hayPendientes) return;
    evento.preventDefault();
    evento.returnValue = '';
  });
  window.addEventListener('pagehide', limpiarPendientes);
}

(async () => {
  campanaId = new URLSearchParams(window.location.search).get('id') || '';
  const acceso = await asegurarAcceso(document.body, '../index.html');
  if (!acceso) return;

  montarHeader({
    titulo: 'Sistema nervioso',
    kicker: 'CAMPAÑAS · COMPOSICIÓN EDITORIAL',
    lead: 'Configura intención, relaciones y cobertura visual sin crear una segunda activación del producto.',
    sesion: acceso.sesion,
    areaLabel: 'ÁREA DE MARKETING',
    volverHref: 'index.html',
    volverTexto: 'Campañas'
  });
  document.querySelectorAll('[data-ico]').forEach((elemento) => {
    elemento.innerHTML = ICONOS[elemento.dataset.ico] || '';
  });

  cablearPagina();
  $('sn-admin').hidden = false;
  if (!UUID_RE.test(campanaId)) {
    mostrarError(errorUsuario('El enlace no contiene un UUID de campaña válido.'));
    return;
  }
  await cargar();
})();
