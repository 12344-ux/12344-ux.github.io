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
const CODIGO_CORTO_P3_RE = /^[0-9a-hjkmnp-tv-z]{16}$/;
const URL_CORTA_BASE_P3 = 'https://go.magandhi.com';
const URL_CORTA_P3_RE = /^https:\/\/go\.magandhi\.com\/([0-9a-hjkmnp-tv-z]{16})$/;
const CAMPAIGN_GENERADA_P3_RE = /^(.+)-[0-9]{6}-[0-9a-hjkmnp-tv-z]{4}$/;
const TIMESTAMP_P3_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?(?:Z|[+-]\d{2}:\d{2})$/;
const P3_CONFIG_TTL_MS = 45_000;
const P3_LISTA_TTL_MS = 45_000;
const P3_CONFIG_POLL_MS = 30_000;
const P3_TIMEOUT_DISTRIBUCION_MS = 3_000;
const P3_TIMEOUT_LECTURA_MS = 5_000;
const P3_TIMEOUT_MUTACION_MS = 12_000;
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
const RPC_P3 = Object.freeze({
  config: 'promocionar_p3_config',
  listar: 'promocionar_p3_listar',
  crear: 'promocionar_p3_crear_borrador',
  editar: 'promocionar_p3_editar_borrador',
  activar: 'promocionar_p3_activar',
  desactivar: 'promocionar_p3_desactivar',
  eliminar: 'promocionar_p3_eliminar_borrador',
});
const ESTADOS_ENLACE_P3 = Object.freeze({
  borrador: 'Borrador', activo: 'Activo', desactivado: 'Desactivado',
});
const TIPOS_DESTINO_P3 = Object.freeze({
  producto_v1: 'Ficha oficial de este producto',
  home_v1: 'Inicio de MAGANDHI',
});

const estado = {
  producto: null,
  canonical: '',
  urlLarga: '',
  urlDistribucion: '',
  enlaceP3: null,
  enlaceP3Snapshot: '',
  canal: 'whatsapp',
  formato: 'cuadrado',
  tipoDestino: 'producto_v1',
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
  p3: {
    config: null,
    historial: [],
    cargando: false,
    refrescandoConfig: false,
    configDisponible: false,
    configLeidaEn: 0,
    configPeticionId: 0,
    intervaloConfig: null,
    listaDisponible: false,
    listaLeidaEn: 0,
    listaPeticionId: 0,
    estadoPeticionId: 0,
    distribucionPeticionId: 0,
    ocupado: false,
    mensaje: '',
    mensajeError: false,
    reemplazaEnlaceId: null,
    conflictoEnlaceId: null,
    claveIdempotencia: '',
    firmaClave: '',
    peticionId: 0,
  },
};

function canalActual() {
  return document.querySelector('input[name="pp-canal"]:checked')?.value || 'whatsapp';
}
function formatoActual() {
  return document.querySelector('input[name="pp-formato"]:checked')?.value || 'cuadrado';
}
function tipoDestinoActual() {
  const valor = document.querySelector('input[name="pp-tipo-destino"]:checked')?.value || 'producto_v1';
  return TIPOS_DESTINO_P3[valor] ? valor : 'producto_v1';
}
function modoImagenActual() {
  return document.querySelector('input[name="pp-modo-imagen"]:checked')?.value || 'cover';
}
function setFeedback(texto, error = false) {
  const el = $('pp-feedback');
  el.textContent = texto || '';
  el.classList.toggle('err', !!error);
}

function textoAcotado(valor, maximo = 180) {
  return String(valor ?? '').replace(/\s+/g, ' ').trim().slice(0, maximo);
}

function parsearDatoRpcP3(valor) {
  if (typeof valor !== 'string') return valor;
  try { return JSON.parse(valor); } catch (_) { return valor; }
}

function objetoRpcP3(valor) {
  const dato = parsearDatoRpcP3(valor);
  if (Array.isArray(dato)) return dato.length === 1 && dato[0] && typeof dato[0] === 'object' ? dato[0] : null;
  if (dato && typeof dato === 'object') return dato.enlace && typeof dato.enlace === 'object' ? dato.enlace : dato;
  return null;
}

function listaRpcP3(valor) {
  const dato = parsearDatoRpcP3(valor);
  if (Array.isArray(dato)) return dato;
  if (dato && Array.isArray(dato.enlaces)) return dato.enlaces;
  throw new Error('P3_RESPUESTA_INVALIDA');
}

function textoErrorP3(error) {
  return [error?.code, error?.message, error?.details, error?.hint].filter(Boolean).join(' ').toUpperCase();
}

function esRpcAusenteP3(error) {
  const texto = textoErrorP3(error);
  return /PGRST202|42883|FUNCTION.+DOES NOT EXIST|COULD NOT FIND.+FUNCTION|SCHEMA CACHE/.test(texto);
}

function mensajeErrorP3(error, accion = 'completar esta acción') {
  const texto = textoErrorP3(error);
  if (esRpcAusenteP3(error) || /P3_CONFIG_(AUSENTE|MISSING)/.test(texto)) return 'La interfaz P3 ya está lista, pero sus funciones o configuración todavía no están desplegadas. P2 sigue disponible con el destino oficial largo.';
  if (/SIN_ACCESO|PERMISSION DENIED|42501|JWT|UNAUTHORIZED|401/.test(texto)) return 'Tu sesión no tiene permiso para administrar enlaces cortos. P2 sigue disponible con el destino oficial largo.';
  if (/CUOTA|RATE|429|LIMITE|LÍMITE|COLISIONES_AGOTADAS/.test(texto)) return 'P3 alcanzó un límite temporal. Espera antes de intentarlo de nuevo; el destino oficial largo sigue disponible.';
  if (/POLITICA|POLÍTICA|GATES_NO_AUTORIZAN/.test(texto)) return 'La política o los gates operativos todavía no autorizan activar P3. Puedes conservar el borrador y usar P2.';
  if (/ROUTING|RUTA|ENRUTAMIENTO/.test(texto)) return 'El enrutamiento del enlace corto aún no está verificado. Puedes conservar el borrador y usar P2.';
  if (/REDIRECT/.test(texto)) return 'El redirect P3 permanece apagado. Los enlaces cortos no se distribuyen y P2 continúa con el destino oficial largo.';
  if (/CONTEO|CONTADOR/.test(texto)) return 'El conteo de clics aproximados está pausado. Esto no apaga por sí solo el redirect de enlaces activos.';
  if (/ACTIVACION|ACTIVACIÓN|NO_ACTIV|REGISTRO/.test(texto)) return 'Las nuevas activaciones P3 están pausadas. Los enlaces ya activos dependen del gate de redirect y P2 sigue disponible.';
  if (/APAGAD|INACTIV/.test(texto)) return 'Un gate operativo P3 permanece apagado. P2 continúa disponible con el destino oficial largo.';
  if (/NO_EXISTE|NO_ENCONTRADO|DESTINO_INEXISTENTE|NOT FOUND|PGRST116|404/.test(texto)) return 'El enlace o la campaña ya no está disponible. Actualiza la página antes de continuar.';
  if (/REEMPLAZO_INVALIDO|AUTORREEMPLAZO/.test(texto)) return 'El enlace elegido no puede usarse como reemplazo. Desactiva primero el enlace activo y vuelve a preparar el reemplazo.';
  if (/P3_BORRADOR_VERSION_CONFLICTO/.test(texto)) return 'El borrador cambió en otra sesión. Refresca la página o vuelve a seleccionarlo en el historial antes de guardar tus cambios.';
  if (/NO_EDITABLE|SOLO_BORRADOR|BORRADOR_REQUERIDO|BORRADOR_NO|ESTADO_INVALIDO|TERMINAL|NO_REACTIV|ACTIVO_INMUTABLE|YA_ACTIV/.test(texto)) return 'Ese enlace ya no admite esta acción. Los enlaces activos no se editan ni los desactivados se reactivan.';
  if (/IDEMPOT|CONFLICT|23505|409/.test(texto)) return 'La solicitud ya fue registrada o entra en conflicto con otra versión. Revisa el historial antes de volver a guardar.';
  if (/P3_RESPUESTA_INVALIDA|P3_URL_CORTA_INVALIDA/.test(texto)) return 'P3 respondió sin los datos seguros esperados. P2 sigue disponible; actualiza la página antes de reintentar.';
  if (/CAMPANA_NO_PUBLICABLE/.test(texto)) return 'La ficha oficial debe estar publicada, activa y tener un slug válido antes de activar el enlace corto.';
  if (/CAMPAIGN|CAMPAÑA|CAMPANA|CONTENT|CONTENIDO|CANAL|SLUG|PII|TEXTO_CON|INVALID/.test(texto)) return 'Revisa el canal, la campaña y la pieza: deben ser identificadores válidos, descriptivos y sin datos personales.';
  if (/FAILED TO FETCH|NETWORK|TIMEOUT|ABORT/.test(texto)) return 'No pudimos comunicarnos con P3. Reintenta cuando tengas conexión; P2 continúa operativo.';
  return `No fue posible ${accion}. P2 sigue disponible con el destino oficial largo.`;
}

function crearClaveIdempotenciaP3() {
  const api = globalThis.crypto;
  if (typeof api?.randomUUID === 'function') return api.randomUUID();
  if (typeof api?.getRandomValues !== 'function') throw new Error('P3_UUID_NO_DISPONIBLE');
  const bytes = new Uint8Array(16);
  api.getRandomValues(bytes);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = [...bytes].map((byte) => byte.toString(16).padStart(2, '0'));
  return `${hex.slice(0, 4).join('')}-${hex.slice(4, 6).join('')}-${hex.slice(6, 8).join('')}-${hex.slice(8, 10).join('')}-${hex.slice(10).join('')}`;
}

function fechaIsoP3(valor, requerida = true) {
  if (valor === null || valor === undefined || valor === '') return requerida ? '' : null;
  if (typeof valor !== 'string') return '';
  const fecha = valor.trim();
  return fecha === valor && fecha.length <= 60 && TIMESTAMP_P3_RE.test(fecha) && Number.isFinite(Date.parse(fecha)) ? fecha : '';
}

function normalizarConfigP3(valor) {
  const dato = objetoRpcP3(valor);
  if (!dato) return null;
  const booleanos = ['construido', 'activacion_habilitada', 'redirect_habilitado', 'conteo_habilitado', 'politica_publicada', 'routing_verificado'];
  if (booleanos.some((campo) => typeof dato[campo] !== 'boolean') || dato.url_corta_base !== URL_CORTA_BASE_P3) return null;
  const cuotaCruda = dato.cuota_hora;
  const cuota = cuotaCruda === null || cuotaCruda === undefined || cuotaCruda === '' ? Number.NaN : Number(cuotaCruda);
  return {
    construido: dato.construido,
    activacion_habilitada: dato.activacion_habilitada,
    redirect_habilitado: dato.redirect_habilitado,
    conteo_habilitado: dato.conteo_habilitado,
    politica_publicada: dato.politica_publicada,
    routing_verificado: dato.routing_verificado,
    politica_version: textoAcotado(dato.politica_version, 60),
    url_corta_base: dato.url_corta_base,
    cuota_hora: Number.isFinite(cuota) && cuota >= 0 ? cuota : null,
    razon_bloqueo: textoAcotado(dato.razon_bloqueo, 100),
    actualizado_en: fechaIsoP3(dato.actualizado_en, false),
  };
}

function urlCortaSeguraP3(valor, codigoEsperado = null) {
  if (typeof valor !== 'string') return '';
  const coincidencia = URL_CORTA_P3_RE.exec(valor);
  if (!coincidencia) return '';
  const codigo = coincidencia[1];
  if (codigoEsperado !== null && (!CODIGO_CORTO_P3_RE.test(codigoEsperado) || codigo !== codigoEsperado)) return '';
  try {
    const url = new URL(valor);
    if (url.href !== valor || url.protocol !== 'https:' || url.origin !== URL_CORTA_BASE_P3
      || url.host !== 'go.magandhi.com' || url.hostname !== 'go.magandhi.com' || url.port
      || url.username || url.password || url.pathname !== `/${codigo}` || url.search || url.hash) return '';
    return valor;
  } catch (_) { return ''; }
}

function normalizarEnlaceP3(valor) {
  if (!valor || typeof valor !== 'object' || Array.isArray(valor)) return null;
  const requeridas = [
    'id', 'campana_producto_id', 'codigo', 'url_corta', 'canal_promocion', 'source', 'medium',
    'campaign_base', 'campaign', 'content', 'tipo_destino', 'estado_enlace', 'reemplaza_enlace_id',
    'resoluble', 'total_aproximado', 'creado_en', 'actualizado_en', 'activado_en', 'desactivado_en',
  ];
  if (requeridas.some((clave) => !Object.prototype.hasOwnProperty.call(valor, clave))) return null;
  const id = typeof valor.id === 'string' ? valor.id : '';
  const campanaProductoId = typeof valor.campana_producto_id === 'string' ? valor.campana_producto_id : '';
  const estadoEnlace = typeof valor.estado_enlace === 'string' ? valor.estado_enlace : '';
  const canal = typeof valor.canal_promocion === 'string' ? valor.canal_promocion : '';
  const tipoDestino = typeof valor.tipo_destino === 'string' ? valor.tipo_destino : '';
  const campaignBase = typeof valor.campaign_base === 'string' ? valor.campaign_base : '';
  const campaign = typeof valor.campaign === 'string' ? valor.campaign : '';
  const content = valor.content === null ? '' : (typeof valor.content === 'string' ? valor.content : null);
  const actualizadoEn = fechaIsoP3(valor.actualizado_en);
  const creadoEn = fechaIsoP3(valor.creado_en);
  const totalAproximado = valor.total_aproximado === null ? null : valor.total_aproximado;
  const reemplazaEnlaceId = valor.reemplaza_enlace_id === null
    ? null
    : (typeof valor.reemplaza_enlace_id === 'string' && UUID_RE.test(valor.reemplaza_enlace_id) ? valor.reemplaza_enlace_id : '');
  const preset = CANALES[canal];
  const campaignGenerada = campaign.match(CAMPAIGN_GENERADA_P3_RE);
  if (!UUID_RE.test(id) || !UUID_RE.test(campanaProductoId) || !ESTADOS_ENLACE_P3[estadoEnlace]
    || !preset || !TIPOS_DESTINO_P3[tipoDestino] || reemplazaEnlaceId === ''
    || typeof valor.resoluble !== 'boolean'
    || valor.source !== preset.source || valor.medium !== preset.medium
    || !campaignBase || campaignBase !== normalizarUtm(campaignBase, 48)
    || !campaign || campaign !== normalizarUtm(campaign, 60) || campaignGenerada?.[1] !== campaignBase
    || content === null || content !== normalizarUtm(content, 60)
    || !actualizadoEn || !creadoEn || (totalAproximado !== null
      && (typeof totalAproximado !== 'number' || !Number.isFinite(totalAproximado) || totalAproximado < 0))) return null;

  const codigo = valor.codigo === null ? '' : (typeof valor.codigo === 'string' ? valor.codigo : '');
  const urlCorta = valor.url_corta === null ? '' : urlCortaSeguraP3(valor.url_corta, codigo);
  const activadoEn = fechaIsoP3(valor.activado_en, false);
  const desactivadoEn = fechaIsoP3(valor.desactivado_en, false);
  if (estadoEnlace === 'borrador') {
    if (valor.codigo !== null || valor.url_corta !== null || valor.activado_en !== null || valor.desactivado_en !== null) return null;
  } else if (!CODIGO_CORTO_P3_RE.test(codigo) || !urlCorta || !activadoEn) return null;
  if (estadoEnlace === 'activo' && valor.desactivado_en !== null) return null;
  if (estadoEnlace === 'desactivado' && !desactivadoEn) return null;

  return {
    id,
    campana_producto_id: campanaProductoId,
    codigo,
    url_corta: urlCorta,
    canal_promocion: canal,
    source: valor.source,
    medium: valor.medium,
    campaign_base: campaignBase,
    campaign,
    content,
    tipo_destino: tipoDestino,
    estado_enlace: estadoEnlace,
    reemplaza_enlace_id: reemplazaEnlaceId,
    resoluble: valor.resoluble,
    total_aproximado: totalAproximado,
    creado_en: creadoEn,
    actualizado_en: actualizadoEn,
    activado_en: activadoEn,
    desactivado_en: desactivadoEn,
    _formato: '',
  };
}

function valoresActualesP3() {
  return {
    canal: canalActual(),
    campaign: normalizarUtm($('pp-campaign')?.value || '', 60),
    content: normalizarUtm($('pp-content')?.value || '', 60),
    formato: formatoActual(),
    tipoDestino: tipoDestinoActual(),
  };
}

function firmaP3(valores = valoresActualesP3()) {
  return JSON.stringify([valores.canal, valores.campaign, valores.content, valores.formato, valores.tipoDestino]);
}

function snapshotEnlaceP3(enlace, valores = valoresActualesP3()) {
  if (!enlace?.id || !enlace.actualizado_en) return '';
  return JSON.stringify([firmaP3(valores), enlace.id, enlace.actualizado_en]);
}

function campaignBaseParaCrearP3(campaignCampo) {
  const campaign = normalizarUtm(campaignCampo, 60);
  const generado = campaign.match(CAMPAIGN_GENERADA_P3_RE);
  return normalizarUtm(generado?.[1] || campaign, 48);
}

function campaignBaseParaEditarP3(enlace, campaignCampo) {
  const campaign = normalizarUtm(campaignCampo, 60);
  const finalActual = normalizarUtm(enlace?.campaign, 60);
  if (enlace?.estado_enlace === 'borrador' && campaign === finalActual && enlace.campaign_base) {
    return normalizarUtm(enlace.campaign_base, 48);
  }
  return campaignBaseParaCrearP3(campaign);
}

function campaignFinalDevueltaP3(valor, campaignBase) {
  if (typeof valor !== 'string') throw new Error('P3_RESPUESTA_INVALIDA');
  const campaign = normalizarUtm(valor, 60);
  const base = normalizarUtm(campaignBase, 48);
  const generado = campaign.match(CAMPAIGN_GENERADA_P3_RE);
  if (!base || valor !== campaign || generado?.[1] !== base) throw new Error('P3_RESPUESTA_INVALIDA');
  return campaign;
}

function validarRespuestaEnlaceP3(datos, esperado = {}) {
  const respuesta = objetoRpcP3(datos);
  const enlace = normalizarEnlaceP3(respuesta);
  const campanaEsperada = esperado.campanaProductoId || estado.producto?.id;
  const estadosEsperados = Array.isArray(esperado.estados) ? esperado.estados : [esperado.estado].filter(Boolean);
  const tiene = (clave) => Object.prototype.hasOwnProperty.call(esperado, clave);
  if (!enlace || !campanaEsperada || enlace.campana_producto_id !== campanaEsperada
    || (estadosEsperados.length && !estadosEsperados.includes(enlace.estado_enlace))
    || (tiene('id') && enlace.id !== esperado.id)
    || (tiene('canal') && enlace.canal_promocion !== esperado.canal)
    || (tiene('campaignBase') && enlace.campaign_base !== esperado.campaignBase)
    || (tiene('campaign') && enlace.campaign !== esperado.campaign)
    || (tiene('content') && enlace.content !== esperado.content)
    || (tiene('tipoDestino') && enlace.tipo_destino !== esperado.tipoDestino)
    || (tiene('reemplazaEnlaceId') && enlace.reemplaza_enlace_id !== esperado.reemplazaEnlaceId)
    || (esperado.exigirVersionNueva && enlace.actualizado_en === esperado.actualizadoEnMinimo)
    || (esperado.actualizadoEnMinimo
      && Date.parse(enlace.actualizado_en) < Date.parse(esperado.actualizadoEnMinimo))) {
    throw new Error('P3_RESPUESTA_INVALIDA');
  }
  return enlace;
}

function enlaceCoincideP3(enlace, valores = valoresActualesP3(), exigirSnapshot = true) {
  if (!enlace || enlace.campana_producto_id !== estado.producto?.id) return false;
  const preset = CANALES[valores.canal];
  const coincide = enlace.canal_promocion === valores.canal
    && enlace.campaign === valores.campaign
    && enlace.content === valores.content
    && enlace.tipo_destino === valores.tipoDestino
    && enlace.source === preset?.source
    && enlace.medium === preset?.medium
    && (!enlace._formato || enlace._formato === valores.formato);
  return coincide && (!exigirSnapshot || estado.enlaceP3Snapshot === snapshotEnlaceP3(enlace, valores));
}

function configP3Fresca() {
  const edad = Date.now() - estado.p3.configLeidaEn;
  return estado.p3.configDisponible && !!estado.p3.config && edad >= 0 && edad <= P3_CONFIG_TTL_MS;
}

function listaP3Fresca() {
  const edad = Date.now() - estado.p3.listaLeidaEn;
  return estado.p3.listaDisponible && edad >= 0 && edad <= P3_LISTA_TTL_MS;
}

function enlaceP3PretendeCorto() {
  return estado.enlaceP3?.estado_enlace === 'activo'
    && enlaceCoincideP3(estado.enlaceP3)
    && !!urlCortaSeguraP3(estado.enlaceP3.url_corta, estado.enlaceP3.codigo);
}

function enlaceP3Conectado() {
  return configP3Fresca()
    && listaP3Fresca()
    && estado.p3.config.redirect_habilitado === true
    && estado.enlaceP3?.resoluble === true
    && enlaceP3PretendeCorto();
}

function actualizarUrlsDistribucion() {
  const cortaConectada = enlaceP3Conectado()
    ? urlCortaSeguraP3(estado.enlaceP3.url_corta, estado.enlaceP3.codigo)
    : '';
  estado.urlDistribucion = cortaConectada || estado.urlLarga || estado.canonical;
  const larga = estado.urlLarga || estado.canonical || 'Enlace no disponible';
  const distribucion = estado.urlDistribucion || larga;
  const usaCorto = !!cortaConectada;
  if ($('pp-url-larga')) { $('pp-url-larga').textContent = larga; $('pp-url-larga').title = larga; }
  if ($('pp-url')) { $('pp-url').textContent = distribucion; $('pp-url').title = distribucion; }
  if ($('pp-url-resumen')) { $('pp-url-resumen').textContent = distribucion; $('pp-url-resumen').title = distribucion; }
  if ($('pp-url-etiqueta')) $('pp-url-etiqueta').textContent = usaCorto ? 'Enlace corto controlado en distribución' : 'Destino oficial largo en distribución';
  if ($('pp-url-resumen-tipo')) $('pp-url-resumen-tipo').textContent = usaCorto ? 'Enlace corto controlado P3' : 'Destino oficial largo MAGANDHI';
  if ($('pp-qr-descripcion')) $('pp-qr-descripcion').textContent = usaCorto
    ? 'Representa el enlace corto controlado; no se envía a un servicio de QR.'
    : 'Representa el destino oficial largo; no se envía a un servicio de QR.';
}

function invalidarClaveP3() {
  estado.p3.claveIdempotencia = '';
  estado.p3.firmaClave = '';
}

function registrarCambioP3() {
  invalidarClaveP3();
  estado.disenoValido = false;
  construirUrl();
  try { pintarQrPreview($('pp-qr'), estado.urlDistribucion || estado.urlLarga || estado.canonical); } catch (_) { /* El render programado reintentará el QR. */ }
}

function establecerMensajeP3(texto, error = false) {
  estado.p3.mensaje = texto || '';
  estado.p3.mensajeError = !!error;
  renderizarP3();
}

function servicioP3Disponible() {
  return configP3Fresca() && listaP3Fresca() && estado.p3.config.construido === true;
}

function utmListaParaBorradorP3() {
  const valores = valoresActualesP3();
  return !!estado.producto && !!estado.canonical && estado.utmValida
    && $('pp-utm-confirmada').checked && !!valores.campaign && !!valores.content
    && !parecePII($('pp-campaign').value) && !parecePII($('pp-content').value);
}

function razonBloqueoP3(razon) {
  const texto = textoAcotado(razon, 100).toUpperCase();
  if (/POLITICA|POLÍTICA/.test(texto)) return 'Falta publicar la política requerida.';
  if (/ROUTING|RUTA|ENRUTAMIENTO/.test(texto)) return 'Falta verificar el enrutamiento del dominio corto.';
  if (/CONSTRUID/.test(texto)) return 'La infraestructura P3 todavía no está construida.';
  if (/CUOTA|LIMITE|LÍMITE/.test(texto)) return 'La cuota temporal está bloqueando nuevas activaciones.';
  if (/CONTEO/.test(texto)) return 'El conteo de clics aproximados permanece pausado.';
  if (/REDIRECT/.test(texto)) return 'El redirect público permanece apagado.';
  if (/ACTIV|REGISTRO|MANUAL|APAGAD|INACTIV/.test(texto)) return 'Las nuevas activaciones permanecen pausadas.';
  return 'El gate operativo correspondiente permanece apagado.';
}

function resumenSistemaP3() {
  if (estado.p3.cargando || (estado.p3.refrescandoConfig && !configP3Fresca())) {
    return { badge: 'Consultando', clase: 'consultando', titulo: 'Consultando P3…', detalle: 'P2 continúa disponible durante la consulta.' };
  }
  if (!configP3Fresca() || !listaP3Fresca()) {
    return { badge: 'No confirmado', clase: 'no-disponible', titulo: 'Configuración o historial P3 sin vigencia', detalle: 'No se usará ningún enlace corto hasta confirmar de nuevo configuración e historial. P2 sigue disponible.' };
  }
  const cfg = estado.p3.config;
  const politica = cfg.politica_publicada ? `Política ${cfg.politica_version || 'registrada'}` : 'Política pendiente';
  const routing = cfg.routing_verificado ? 'routing verificado' : 'routing pendiente';
  const cuota = cfg.cuota_hora === null ? '' : ` · cuota ${cfg.cuota_hora}/h`;
  const activacion = cfg.activacion_habilitada ? 'activación habilitada' : 'nuevas activaciones pausadas';
  const conteo = cfg.conteo_habilitado ? 'conteo de clics aproximados habilitado' : 'conteo de clics aproximados pausado';
  const controles = `${politica} · ${routing}${cuota} · ${activacion}`;
  if (!cfg.construido) return { badge: 'Pendiente', clase: 'no-disponible', titulo: 'P3 no está construido', detalle: `${razonBloqueoP3(cfg.razon_bloqueo)} P2 sigue operativo; ${conteo}.` };
  if (cfg.redirect_habilitado && !cfg.conteo_habilitado) {
    return { badge: 'Redirect activo', clase: 'activo', titulo: 'Redirect activo · conteo pausado', detalle: `Los enlaces activos siguen funcionando y pueden distribuirse; el conteo de clics aproximados está pausado. ${controles}.` };
  }
  if (cfg.redirect_habilitado) return { badge: 'Activo', clase: 'activo', titulo: 'Redirect P3 activo', detalle: `${controles} · ${conteo}.` };
  return { badge: 'Preparación', clase: 'preparacion', titulo: 'Redirect P3 apagado', detalle: `${razonBloqueoP3(cfg.razon_bloqueo)} ${controles} · ${conteo}. P2 usa el destino largo.` };
}

function etiquetaEstadoEnlaceP3(estadoEnlace) {
  return ESTADOS_ENLACE_P3[estadoEnlace] || (estadoEnlace ? 'Otro estado' : 'Sin estado');
}

function fechaCortaP3(valor) {
  if (!valor) return 'sin fecha';
  const fecha = new Date(valor);
  if (Number.isNaN(fecha.getTime())) return 'fecha no disponible';
  try { return new Intl.DateTimeFormat('es-CO', { dateStyle: 'short', timeStyle: 'short' }).format(fecha); }
  catch (_) { return fecha.toLocaleString('es-CO'); }
}

function numeroP3(valor) {
  if (valor === null) return '—';
  try { return new Intl.NumberFormat('es-CO', { maximumFractionDigits: 0 }).format(valor); }
  catch (_) { return String(valor); }
}

function pintarHistorialP3() {
  const lista = $('pp-p3-historial');
  if (!lista) return;
  const focoId = document.activeElement?.dataset?.p3EnlaceId || '';
  lista.replaceChildren();
  if (estado.p3.cargando) {
    const item = document.createElement('li'); item.className = 'pp-p3-vacio'; item.textContent = 'Consultando enlaces… · — clics aproximados'; lista.appendChild(item); return;
  }
  if (!estado.p3.listaDisponible) {
    const item = document.createElement('li'); item.className = 'pp-p3-vacio'; item.textContent = 'Historial P3 no disponible · — clics aproximados'; lista.appendChild(item); return;
  }
  if (!estado.p3.historial.length) {
    const item = document.createElement('li'); item.className = 'pp-p3-vacio'; item.textContent = 'Aún no hay enlaces · 0 clics aproximados'; lista.appendChild(item); return;
  }
  estado.p3.historial.forEach((enlace) => {
    const item = document.createElement('li');
    const boton = document.createElement('button');
    boton.type = 'button'; boton.className = 'pp-p3-item'; boton.disabled = estado.p3.ocupado; boton.dataset.p3EnlaceId = enlace.id;
    boton.setAttribute('aria-pressed', String(estado.enlaceP3?.id === enlace.id));
    boton.setAttribute('aria-label', `Seleccionar enlace ${enlace.codigo || enlace.campaign || enlace.id}, ${etiquetaEstadoEnlaceP3(enlace.estado_enlace)}, destino ${TIPOS_DESTINO_P3[enlace.tipo_destino]}, ${numeroP3(enlace.total_aproximado)} clics aproximados`);
    const principal = document.createElement('span'); principal.className = 'pp-p3-item-principal'; principal.textContent = enlace.codigo || enlace.campaign || 'Enlace sin código';
    const badge = document.createElement('span'); badge.className = `pp-p3-item-estado ${ESTADOS_ENLACE_P3[enlace.estado_enlace] ? enlace.estado_enlace : ''}`; badge.textContent = etiquetaEstadoEnlaceP3(enlace.estado_enlace);
    const detalle = document.createElement('span'); detalle.className = 'pp-p3-item-detalle';
    detalle.textContent = `${CANALES[enlace.canal_promocion].etiqueta} · ${TIPOS_DESTINO_P3[enlace.tipo_destino]} · ${fechaCortaP3(enlace.creado_en)} · ${numeroP3(enlace.total_aproximado)} clics aproximados`;
    boton.append(principal, badge, detalle);
    boton.addEventListener('click', () => seleccionarEnlaceP3(enlace.id));
    item.appendChild(boton); lista.appendChild(item);
  });
  if (focoId) {
    const siguiente = [...lista.querySelectorAll('[data-p3-enlace-id]')].find((boton) => boton.dataset.p3EnlaceId === focoId);
    siguiente?.focus({ preventScroll: true });
  }
}

function actualizarBotonesP3() {
  if (!$('pp-p3-guardar')) return;
  const disponible = servicioP3Disponible() && !estado.p3.ocupado;
  const enlace = estado.enlaceP3;
  const sincronizado = enlaceCoincideP3(enlace);
  const esBorrador = enlace?.estado_enlace === 'borrador';
  $('pp-p3-guardar').disabled = !(disponible && !enlace && utmListaParaBorradorP3());
  $('pp-p3-actualizar').disabled = !(disponible && esBorrador && !sincronizado
    && estado.p3.conflictoEnlaceId !== enlace.id && utmListaParaBorradorP3());
  $('pp-p3-activar').disabled = !(disponible && estado.p3.config?.activacion_habilitada === true && esBorrador && sincronizado
    && listoEnlace() && listoContenido() && estado.disenoValido);
  $('pp-p3-desactivar').disabled = !(disponible && enlace?.estado_enlace === 'activo');
  $('pp-p3-eliminar').disabled = !(disponible && esBorrador);
  $('pp-p3-preparar').disabled = !disponible;
  $('pp-p3-activar').title = estado.p3.config?.activacion_habilitada !== true
    ? 'El gate de activación P3 debe estar habilitado para activar enlaces.'
    : 'Requiere gates P2 listos, contenido revisado y diseño válido.';
  $('pp-p3-guardar').title = 'Requiere campaña, slug e identificadores UTM válidos y confirmados.';
}

function renderizarP3() {
  const tarjeta = $('pp-p3');
  if (!tarjeta) return;
  const sistema = resumenSistemaP3();
  tarjeta.setAttribute('aria-busy', String(estado.p3.cargando || estado.p3.refrescandoConfig || estado.p3.ocupado));
  const badge = $('pp-p3-badge'); badge.textContent = estado.p3.ocupado ? 'Procesando' : sistema.badge; badge.className = `pp-p3-badge ${sistema.clase}`;
  $('pp-p3-sistema').textContent = sistema.titulo;
  $('pp-p3-sistema-detalle').textContent = sistema.detalle;

  const enlace = estado.enlaceP3;
  const sincronizado = enlaceCoincideP3(enlace);
  let titulo = 'Sin enlace seleccionado';
  let detalle = estado.p3.reemplazaEnlaceId
    ? 'El próximo borrador conservará la referencia al enlace que reemplaza.'
    : 'Puedes preparar un borrador cuando los identificadores UTM sean válidos.';
  if (enlace?.estado_enlace === 'borrador') {
    titulo = sincronizado ? 'Borrador al día' : 'Borrador desactualizado';
    detalle = sincronizado ? 'Puedes activarlo cuando todos los gates estén listos.' : 'Los cambios no se guardan solos. Usa “Actualizar borrador”.';
  } else if (enlace?.estado_enlace === 'activo') {
    if (enlace.resoluble !== true) {
      titulo = 'Activo, destino no resoluble';
      detalle = 'El producto ya no es resoluble públicamente. Este enlace corto no se distribuye y se usa el destino oficial largo P2.';
    } else if (!configP3Fresca() || !listaP3Fresca() || estado.p3.config.redirect_habilitado !== true) {
      titulo = configP3Fresca() && listaP3Fresca() ? 'Activo, con redirect pausado' : 'Activo, sin lectura autoritativa vigente';
      detalle = 'El enlace se conserva, pero sin confirmar configuración e historial se distribuye el destino oficial largo P2.';
    } else {
      titulo = enlaceP3Conectado() ? 'Activo y sincronizado' : 'Activo desprendido';
      detalle = enlaceP3Conectado()
        ? (estado.p3.config.conteo_habilitado
          ? 'Este enlace corto sustituye al destino largo en copia, texto, Share, QR y PNG; sus totales son clics aproximados.'
          : 'Este enlace corto se distribuye y el redirect funciona; el conteo de clics aproximados está pausado.')
        : 'Se usa el destino largo. Para reemplazarlo, primero desactívalo de forma explícita; el enlace activo nunca se edita.';
    }
  } else if (enlace) {
    titulo = `${etiquetaEstadoEnlaceP3(enlace.estado_enlace)} · estado terminal`;
    detalle = 'Este enlace no se reactiva. Prepara un reemplazo o uno nuevo.';
  }
  $('pp-p3-enlace-estado').textContent = titulo;
  $('pp-p3-enlace-detalle').textContent = detalle;
  const corta = enlace?.estado_enlace === 'borrador' ? '' : urlCortaSeguraP3(enlace?.url_corta, enlace?.codigo ?? null);
  $('pp-p3-url').textContent = corta || (enlace?.estado_enlace === 'borrador' ? 'Se asignará o confirmará al activar' : 'Aún no asignado');
  $('pp-p3-url').title = corta || '';
  const destinoSeleccionado = TIPOS_DESTINO_P3[tipoDestinoActual()];
  $('pp-p3-url-ayuda').textContent = enlaceP3Conectado()
    ? (estado.p3.config.conteo_habilitado
      ? `Está sincronizado con canal, campaign, content, formato y destino “${destinoSeleccionado}”; los clics mostrados son aproximados.`
      : `Está sincronizado con destino “${destinoSeleccionado}” y el redirect funciona; el conteo de clics aproximados está pausado.`)
    : 'Solo un enlace activo y sincronizado con destino y redirect confirmados sustituye al destino largo.';
  const mensaje = $('pp-p3-mensaje'); mensaje.textContent = estado.p3.mensaje; mensaje.classList.toggle('err', estado.p3.mensajeError); mensaje.setAttribute('role', estado.p3.mensajeError ? 'alert' : 'status'); mensaje.setAttribute('aria-live', estado.p3.mensajeError ? 'assertive' : 'polite');
  pintarHistorialP3();
  actualizarBotonesP3();
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
  const destino = enlaceP3Conectado() ? 'El enlace corto controlado' : 'El destino oficial largo';
  let texto = '';
  if (!producto) texto = 'La campaña todavía no está disponible.';
  else if (producto.activo === false) texto = 'Una campaña retirada no puede producir material para distribuir.';
  else if (producto.es_placeholder) texto = 'Los productos de ejemplo no se pueden promocionar.';
  else if (!producto.publicado) texto = 'Puedes preparar el diseño, pero debes publicar la campaña antes de distribuirlo.';
  else if (!estado.canonical) texto = 'La campaña necesita un slug válido.';
  else if (!$('pp-ficha-confirmada').checked) texto = 'Abre la ficha oficial y confirma que el producto ya está publicado.';
  else if (!estado.utmValida) texto = 'Completa identificadores UTM válidos.';
  else if (!$('pp-utm-confirmada').checked) texto = 'Confirma que campaign y content no identifican personas ni audiencias.';
  else if (!$('pp-contenido-confirmado').checked || !estado.mensajeValido || !estado.contenidoVisualValido) texto = `${destino} está listo para copiar; revisa y confirma el contenido antes de compartir el mensaje o descargar.`;
  else texto = estado.disenoValido ? `${destino} y la pieza están listos para distribuir.` : `${destino} está listo; corrige el diseño para poder descargar el PNG.`;
  gate.textContent = texto;
  gate.classList.toggle('listo', listoEnlace());
  actualizarBotones();
}

function actualizarBotones() {
  const enlaceListo = listoEnlace() && !estado.ocupado && !estado.p3.ocupado;
  ['pp-copiar-url', 'pp-copiar-url-mini'].forEach((id) => { $(id).disabled = !enlaceListo; });
  const contenidoListo = enlaceListo && listoContenido();
  ['pp-copiar-texto', 'pp-compartir'].forEach((id) => { $(id).disabled = !contenidoListo; });
  $('pp-descargar').disabled = !(contenidoListo && estado.disenoValido);
  actualizarBotonesP3();
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
    estado.urlLarga = crearUrlUtm(estado.canonical, { canal: estado.canal, campaign: $('pp-campaign').value, content: $('pp-content').value });
    estado.utmValida = true;
    validacion.hidden = true; validacion.textContent = '';
  } catch (error) {
    estado.urlLarga = estado.canonical;
    estado.utmValida = false;
    validacion.textContent = error instanceof Error ? error.message : 'Revisa los identificadores del enlace.';
    validacion.hidden = false;
  }
  actualizarUrlsDistribucion();
  renderizarP3();
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

function modeloActual(urlDistribucion = estado.urlDistribucion || estado.urlLarga || estado.canonical) {
  const seleccion = imagenSeleccionada();
  return {
    formato: estado.formato,
    url: urlDistribucion,
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
  const tipoDestino = enlaceP3Conectado() ? 'enlace corto controlado P3' : 'destino oficial largo P2';
  $('pp-alternativa').textContent = `Pieza ${formato.etiqueta.toLowerCase()} para ${CANALES[estado.canal].etiqueta}. Imagen: ${imagen}. Estilo: ${$('pp-estilo-estado').textContent}. Pretítulo: ${pretitulo}. Título: ${$('pp-titulo').value || 'vacío'}. Descripción: ${$('pp-texto-pieza').value || 'vacía'}; CTA: ${cta}. ${$('pp-incluir-qr').checked ? `Incluye el QR del ${tipoDestino}.` : 'No incluye QR.'}`;
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
    pintarQrPreview($('pp-qr'), estado.urlDistribucion || estado.urlLarga || estado.canonical);
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
    registrarCambioP3();
    setFeedback('Preset de canal aplicado. La pieza no se publicó.');
    programarRender();
  }));
  document.querySelectorAll('input[name="pp-formato"]').forEach((input) => input.addEventListener('change', () => {
    estado.formato = formatoActual();
    $('pp-content').value = contentInicial(estado.canal, estado.formato);
    $('pp-utm-confirmada').checked = false;
    registrarCambioP3();
    programarRender();
  }));
  document.querySelectorAll('input[name="pp-tipo-destino"]').forEach((input) => input.addEventListener('change', () => {
    estado.tipoDestino = tipoDestinoActual();
    const enlace = estado.enlaceP3;
    registrarCambioP3();
    if (enlace?.estado_enlace === 'borrador') {
      estado.p3.mensaje = 'Destino cambiado. El borrador quedó desactualizado; usa “Actualizar borrador” para guardarlo con control de versión.';
    } else if (enlace?.estado_enlace === 'activo') {
      estado.p3.mensaje = 'Destino cambiado solo en el formulario. El enlace activo quedó desprendido y no se modificó; prepara un reemplazo para corregirlo.';
    } else {
      estado.p3.mensaje = 'Destino P3 actualizado en el formulario. Se conservará la asociación con esta campaña al guardar.';
    }
    estado.p3.mensajeError = false;
    renderizarP3();
    setFeedback('Destino del enlace corto ajustado. P2 conserva la ficha oficial larga.');
    programarRender();
  }));
  ['pp-campaign', 'pp-content'].forEach((id) => {
    $(id).addEventListener('input', () => { $('pp-utm-confirmada').checked = false; registrarCambioP3(); programarRender(); });
    $(id).addEventListener('blur', () => {
      const anterior = $(id).value;
      $(id).value = normalizarUtm(anterior, 60);
      if ($(id).value !== anterior) registrarCambioP3();
      programarRender();
    });
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
  $('pp-p3-guardar').addEventListener('click', guardarBorradorP3);
  $('pp-p3-actualizar').addEventListener('click', actualizarBorradorP3);
  $('pp-p3-activar').addEventListener('click', activarEnlaceP3);
  $('pp-p3-desactivar').addEventListener('click', desactivarEnlaceP3);
  $('pp-p3-eliminar').addEventListener('click', eliminarBorradorP3);
  $('pp-p3-preparar').addEventListener('click', prepararNuevoEnlaceP3);
  $('pp-copiar-url').addEventListener('click', copiarUrlDistribucion);
  $('pp-copiar-url-mini').addEventListener('click', copiarUrlDistribucion);
  $('pp-copiar-texto').addEventListener('click', copiarTextoDistribucion);
  $('pp-compartir').addEventListener('click', compartir);
  $('pp-descargar').addEventListener('click', descargar);
  document.addEventListener('visibilitychange', manejarVisibilidadP3);
  window.addEventListener('pagehide', () => {
    detenerPollingConfigP3();
    cancelarRpcP3();
  });
  window.addEventListener('pageshow', () => {
    if (document.visibilityState === 'visible') manejarVisibilidadP3();
  });
  window.addEventListener('beforeunload', () => {
    detenerPollingConfigP3();
    cancelarRpcP3();
    estado.observadorPreview?.disconnect();
    clearTimeout(estado.renderTimer);
    if (estado.imagenLocalUrl) URL.revokeObjectURL(estado.imagenLocalUrl);
  });
}

async function escribirPortapapeles(texto, mensaje) {
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

async function copiarUrlDistribucion() {
  if (!listoEnlace()) return;
  const distribucion = await asegurarConfigDistribucionP3();
  if (!listoEnlace()) return;
  await escribirPortapapeles(distribucion.url, 'Enlace de distribución copiado.');
}

async function copiarTextoDistribucion() {
  if (!listoEnlace() || !listoContenido()) return;
  const distribucion = await asegurarConfigDistribucionP3();
  if (!listoEnlace() || !listoContenido()) return;
  await escribirPortapapeles(
    textoParaCompartir($('pp-texto').value, distribucion.url),
    'Mensaje y enlace copiados.',
  );
}

async function compartir() {
  if (!listoEnlace() || !listoContenido()) return;
  const distribucion = await asegurarConfigDistribucionP3();
  if (!listoEnlace() || !listoContenido()) return;
  const datos = { title: `${estado.producto.nombre} · MAGANDHI`, text: $('pp-texto').value.trim(), url: distribucion.url };
  if (!navigator.share) {
    await escribirPortapapeles(textoParaCompartir(datos.text, datos.url), 'Web Share no está disponible; copiamos mensaje y enlace.');
    return;
  }
  try { await navigator.share(datos); setFeedback('Contenido enviado al menú para compartir.'); }
  catch (error) { if (error?.name !== 'AbortError') setFeedback('No fue posible abrir el menú. Puedes copiar el texto o el enlace.', true); }
}

async function descargar() {
  if (!listoEnlace() || !listoContenido() || !estado.disenoValido || estado.ocupado || estado.p3.ocupado) return;
  const distribucion = await asegurarConfigDistribucionP3();
  if (!listoEnlace() || !listoContenido() || !estado.disenoValido || estado.ocupado || estado.p3.ocupado) return;
  clearTimeout(estado.renderTimer);
  estado.ocupado = true; estado.renderId += 1; construirUrl(); actualizarBotones();
  const boton = $('pp-descargar'); boton.querySelector('span').textContent = 'Preparando PNG…';
  const formatoExportado = estado.formato; const canalExportado = estado.canal; const modelo = modeloActual(distribucion.url);
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
    setFeedback(`PNG descargado en ${resultado.ancho} × ${resultado.alto}. Ahora adjúntalo y pega el enlace de distribución.`);
  } catch (error) {
    setFeedback(`No se pudo descargar: ${error instanceof Error ? error.message : 'error inesperado.'}`, true);
  } finally {
    estado.ocupado = false; boton.querySelector('span').textContent = 'Descargar PNG'; actualizarBotones(); programarRender();
  }
}

const controladoresRpcP3 = new Set();

function crearErrorTimeoutP3(nombre, timeoutMs) {
  const error = new Error(`P3_TIMEOUT_${nombre.toUpperCase()}_${timeoutMs}`);
  error.name = 'P3TimeoutError';
  error.code = 'P3_TIMEOUT';
  error.timeoutMs = timeoutMs;
  return error;
}

function esTimeoutP3(error) {
  return error?.code === 'P3_TIMEOUT' || error?.name === 'P3TimeoutError';
}

async function invocarRpcP3(nombre, argumentos, { timeoutMs = P3_TIMEOUT_LECTURA_MS } = {}) {
  const controlador = new AbortController();
  const iniciadoEn = Date.now();
  const errorTimeout = crearErrorTimeoutP3(nombre, timeoutMs);
  let temporizador = null;
  let vencido = false;
  const limite = new Promise((_, reject) => {
    temporizador = window.setTimeout(() => {
      vencido = true;
      controlador.abort(errorTimeout);
      reject(errorTimeout);
    }, timeoutMs);
  });
  controladoresRpcP3.add(controlador);
  try {
    const consulta = supabase.rpc(nombre, argumentos).abortSignal(controlador.signal);
    const { data, error } = await Promise.race([Promise.resolve(consulta), limite]);
    if (Date.now() - iniciadoEn >= timeoutMs) {
      vencido = true;
      controlador.abort(errorTimeout);
      throw errorTimeout;
    }
    if (error) throw error;
    return data;
  } catch (error) {
    if (vencido || error === errorTimeout) throw errorTimeout;
    throw error;
  } finally {
    if (temporizador !== null) clearTimeout(temporizador);
    controladoresRpcP3.delete(controlador);
  }
}

function cancelarRpcP3() {
  controladoresRpcP3.forEach((controlador) => {
    if (!controlador.signal.aborted) controlador.abort();
  });
  controladoresRpcP3.clear();
}

function actualizarVistaConfigP3(urlAnterior = estado.urlDistribucion) {
  actualizarUrlsDistribucion();
  renderizarP3();
  actualizarGate();
  if (estado.urlDistribucion !== urlAnterior) {
    estado.renderId += 1;
    try { pintarQrPreview($('pp-qr'), estado.urlDistribucion || estado.urlLarga || estado.canonical); } catch (_) { /* El render programado reintentará el QR. */ }
    actualizarAlternativa();
    programarRender();
  }
}

function invalidarConfigP3() {
  estado.p3.configDisponible = false;
  estado.p3.configLeidaEn = 0;
}

function invalidarListaP3() {
  estado.p3.listaDisponible = false;
  estado.p3.listaLeidaEn = 0;
}

async function leerConfigP3({ timeoutMs = P3_TIMEOUT_LECTURA_MS } = {}) {
  const peticionId = ++estado.p3.configPeticionId;
  try {
    const datos = await invocarRpcP3(RPC_P3.config, {}, { timeoutMs });
    const config = normalizarConfigP3(datos);
    if (!config) throw new Error('P3_RESPUESTA_INVALIDA');
    if (peticionId !== estado.p3.configPeticionId) {
      return { ok: false, superada: true, error: new Error('P3_CONFIG_LECTURA_SUPERADA') };
    }
    estado.p3.config = config;
    estado.p3.configDisponible = true;
    estado.p3.configLeidaEn = Date.now();
    return { ok: true, config, peticionId };
  } catch (error) {
    if (peticionId === estado.p3.configPeticionId) invalidarConfigP3();
    return { ok: false, error, peticionId, superada: peticionId !== estado.p3.configPeticionId };
  }
}

async function leerListaP3({ timeoutMs = P3_TIMEOUT_LECTURA_MS } = {}) {
  const productoId = estado.producto?.id;
  const peticionId = ++estado.p3.listaPeticionId;
  if (!productoId) {
    const error = new Error('P3_LISTA_AUSENTE');
    if (peticionId === estado.p3.listaPeticionId) invalidarListaP3();
    return { ok: false, error, peticionId };
  }
  try {
    const datos = await invocarRpcP3(
      RPC_P3.listar,
      { p_campana_producto_id: productoId },
      { timeoutMs },
    );
    if (peticionId !== estado.p3.listaPeticionId || estado.producto?.id !== productoId) {
      return { ok: false, superada: true, error: new Error('P3_LISTA_LECTURA_SUPERADA') };
    }
    reemplazarHistorialP3(datos);
    estado.p3.listaDisponible = true;
    estado.p3.listaLeidaEn = Date.now();
    return { ok: true, historial: estado.p3.historial, peticionId };
  } catch (error) {
    const superada = peticionId !== estado.p3.listaPeticionId || estado.producto?.id !== productoId;
    if (!superada) invalidarListaP3();
    return { ok: false, error, peticionId, superada };
  }
}

function mensajeCambioAutoritativoP3(seleccionAnterior, configAnterior) {
  if (seleccionAnterior?.id) {
    const remoto = estado.p3.historial.find((enlace) => enlace.id === seleccionAnterior.id);
    if (!remoto) return 'El enlace seleccionado desapareció del historial autoritativo. La distribución cambió explícitamente al destino largo P2.';
    if (seleccionAnterior.estado === 'activo' && remoto.estado_enlace !== 'activo') {
      return 'El enlace seleccionado fue desactivado en otra sesión. La distribución cambió explícitamente al destino largo P2.';
    }
    if (seleccionAnterior.resoluble === true && remoto.resoluble === false) {
      return 'El producto dejó de estar publicado o resoluble. El enlace corto no se distribuye y se usa el destino largo P2.';
    }
  }
  if (configAnterior && configAnterior.redirect_habilitado !== estado.p3.config?.redirect_habilitado) {
    return estado.p3.config?.redirect_habilitado
      ? 'Configuración P3 actualizada. El redirect volvió a estar disponible para enlaces activos, resolubles y sincronizados.'
      : 'Configuración P3 actualizada: el redirect está apagado y la distribución usa el destino largo P2.';
  }
  return '';
}

async function refrescarEstadoP3({ motivo = 'polling', timeoutMs = P3_TIMEOUT_LECTURA_MS } = {}) {
  if (!estado.producto) {
    invalidarConfigP3();
    invalidarListaP3();
    return { ok: false, error: new Error('P3_CONFIG_AUSENTE') };
  }
  const peticionId = ++estado.p3.estadoPeticionId;
  const urlAnterior = estado.urlDistribucion;
  const configAnterior = estado.p3.config;
  const seleccionAnterior = estado.enlaceP3 ? {
    id: estado.enlaceP3.id,
    estado: estado.enlaceP3.estado_enlace,
    resoluble: estado.enlaceP3.resoluble,
  } : null;
  estado.p3.refrescandoConfig = true;
  if (!configP3Fresca() || !listaP3Fresca()) actualizarVistaConfigP3(urlAnterior);
  else renderizarP3();
  const [configResultado, listaResultado] = await Promise.all([
    leerConfigP3({ timeoutMs }),
    leerListaP3({ timeoutMs }),
  ]);
  if (peticionId !== estado.p3.estadoPeticionId) {
    return { ok: false, superada: true, configResultado, listaResultado };
  }
  estado.p3.refrescandoConfig = false;
  const ok = configResultado.ok && listaResultado.ok;
  if (!ok) {
    const error = configResultado.error || listaResultado.error || new Error('P3_RESPUESTA_INVALIDA');
    estado.p3.mensaje = mensajeErrorP3(error, 'confirmar configuración e historial P3');
    estado.p3.mensajeError = true;
  } else if (motivo === 'polling' || motivo === 'visibilidad') {
    const mensaje = mensajeCambioAutoritativoP3(seleccionAnterior, configAnterior);
    if (mensaje) {
      estado.p3.mensaje = mensaje;
      estado.p3.mensajeError = false;
    }
  }
  actualizarVistaConfigP3(urlAnterior);
  return { ok, configResultado, listaResultado, peticionId };
}

async function asegurarConfigDistribucionP3() {
  const peticionId = ++estado.p3.distribucionPeticionId;
  const enlaceId = estado.enlaceP3?.id || '';
  const snapshot = estado.enlaceP3Snapshot;
  const resultado = await refrescarEstadoP3({
    motivo: 'distribucion',
    timeoutMs: P3_TIMEOUT_DISTRIBUCION_MS,
  });
  const urlP2 = estado.urlLarga || estado.canonical || '';
  const vigente = peticionId === estado.p3.distribucionPeticionId;
  const remoto = enlaceId ? estado.p3.historial.find((enlace) => enlace.id === enlaceId) : null;
  let usoCorto = false;
  let mensaje = '';
  let errorMensaje = false;

  if (!vigente || resultado.superada) {
    mensaje = 'Otra revalidación P3 más reciente sustituyó esta lectura. Esta acción continuará con el destino oficial largo P2.';
  } else if (!resultado.ok) {
    const errores = [resultado.configResultado?.error, resultado.listaResultado?.error].filter(Boolean);
    mensaje = errores.some(esTimeoutP3)
      ? 'La revalidación de configuración e historial P3 agotó el límite de 3 segundos. Esta acción continuará con el destino oficial largo P2.'
      : 'No fue posible validar en paralelo configuración e historial P3. Esta acción continuará con el destino oficial largo P2.';
    errorMensaje = true;
  } else if (enlaceId && !remoto) {
    mensaje = 'El enlace seleccionado ya no aparece en el historial remoto. Esta acción continuará con el destino oficial largo P2.';
  } else if (remoto?.estado_enlace !== 'activo' && enlaceId) {
    mensaje = remoto?.estado_enlace === 'desactivado'
      ? 'El enlace fue desactivado en otra sesión. Esta acción continuará con el destino oficial largo P2.'
      : 'El enlace ya no está activo. Esta acción continuará con el destino oficial largo P2.';
  } else if (remoto?.resoluble === false) {
    mensaje = 'El producto dejó de estar publicado o resoluble. Esta acción continuará con el destino oficial largo P2.';
  } else if (estado.p3.config?.redirect_habilitado !== true) {
    mensaje = 'El redirect P3 está apagado. Esta acción continuará con el destino oficial largo P2.';
  } else if (enlaceId && (estado.enlaceP3?.id !== enlaceId || estado.enlaceP3Snapshot !== snapshot)) {
    mensaje = 'La selección o su versión cambió durante la revalidación. Esta acción continuará con el destino oficial largo P2.';
  } else if (enlaceId && enlaceP3Conectado()) {
    usoCorto = true;
  } else if (enlaceId) {
    mensaje = 'El enlace corto ya no coincide con el formulario confirmado. Esta acción continuará con el destino oficial largo P2.';
  }

  if (vigente && mensaje) {
    estado.p3.mensaje = mensaje;
    estado.p3.mensajeError = errorMensaje;
  }
  actualizarUrlsDistribucion();
  renderizarP3();
  actualizarGate();
  const url = usoCorto
    ? urlCortaSeguraP3(estado.enlaceP3?.url_corta, estado.enlaceP3?.codigo ?? null)
    : urlP2;
  return { ok: vigente && resultado.ok, usoCorto: !!url && usoCorto, url: url || urlP2 };
}

function detenerPollingConfigP3() {
  if (estado.p3.intervaloConfig !== null) {
    clearInterval(estado.p3.intervaloConfig);
    estado.p3.intervaloConfig = null;
  }
}

function iniciarPollingConfigP3() {
  detenerPollingConfigP3();
  if (document.visibilityState !== 'visible' || !estado.producto) return;
  estado.p3.intervaloConfig = window.setInterval(() => {
    if (document.visibilityState === 'visible' && !estado.p3.ocupado) {
      void refrescarEstadoP3({ motivo: 'polling', timeoutMs: P3_TIMEOUT_LECTURA_MS });
    }
  }, P3_CONFIG_POLL_MS);
}

function manejarVisibilidadP3() {
  if (document.visibilityState === 'visible') {
    iniciarPollingConfigP3();
    if (!estado.p3.ocupado) void refrescarEstadoP3({ motivo: 'visibilidad', timeoutMs: P3_TIMEOUT_LECTURA_MS });
  } else detenerPollingConfigP3();
}

function ordenarHistorialP3(enlaces) {
  return [...enlaces].sort((a, b) => {
    const fechaA = Date.parse(a.creado_en) || 0;
    const fechaB = Date.parse(b.creado_en) || 0;
    return fechaB - fechaA;
  });
}

function reemplazarHistorialP3(datos) {
  const anteriores = new Map(estado.p3.historial.map((enlace) => [enlace.id, enlace]));
  if (estado.enlaceP3) anteriores.set(estado.enlaceP3.id, estado.enlaceP3);
  const ids = new Set();
  const enlaces = listaRpcP3(datos).map((dato) => {
    const enlace = normalizarEnlaceP3(dato);
    if (!enlace || enlace.campana_producto_id !== estado.producto?.id || ids.has(enlace.id)) {
      throw new Error('P3_RESPUESTA_INVALIDA');
    }
    ids.add(enlace.id);
    const previo = anteriores.get(enlace.id);
    return { ...enlace, _formato: previo?._formato || '' };
  });
  estado.p3.historial = ordenarHistorialP3(enlaces);
  if (estado.enlaceP3) {
    const actualizado = estado.p3.historial.find((enlace) => enlace.id === estado.enlaceP3.id);
    if (actualizado) estado.enlaceP3 = actualizado;
    else {
      estado.enlaceP3 = null;
      estado.enlaceP3Snapshot = '';
    }
  }
}

function guardarEnHistorialP3(enlace) {
  if (!enlace) return;
  const indice = estado.p3.historial.findIndex((item) => item.id === enlace.id);
  if (indice >= 0) estado.p3.historial.splice(indice, 1, enlace);
  else estado.p3.historial.push(enlace);
  estado.p3.historial = ordenarHistorialP3(estado.p3.historial);
}

async function refrescarHistorialP3Silencioso({ timeoutMs = P3_TIMEOUT_LECTURA_MS } = {}) {
  const urlAnterior = estado.urlDistribucion;
  const resultado = await leerListaP3({ timeoutMs });
  if (!resultado.superada) actualizarVistaConfigP3(urlAnterior);
  return resultado.ok;
}

function aplicarEnlaceActualP3(enlace, { actualizarCampos = false, formato = formatoActual() } = {}) {
  const actual = { ...enlace, _formato: formato };
  if (actualizarCampos) {
    const canalAnterior = canalActual();
    const tipoDestinoAnterior = tipoDestinoActual();
    const campaignAnterior = $('pp-campaign').value;
    const contentAnterior = $('pp-content').value;
    const radioCanal = document.querySelector(`input[name="pp-canal"][value="${actual.canal_promocion}"]`);
    if (radioCanal) radioCanal.checked = true;
    estado.canal = actual.canal_promocion;
    const radioDestino = document.querySelector(`input[name="pp-tipo-destino"][value="${actual.tipo_destino}"]`);
    if (radioDestino) radioDestino.checked = true;
    estado.tipoDestino = actual.tipo_destino;
    const campaignSiguiente = actual.campaign;
    const contentSiguiente = actual.content;
    $('pp-campaign').value = campaignSiguiente;
    $('pp-content').value = contentSiguiente;
    if (canalActual() !== canalAnterior || tipoDestinoActual() !== tipoDestinoAnterior
      || campaignSiguiente !== campaignAnterior || contentSiguiente !== contentAnterior) {
      $('pp-utm-confirmada').checked = false;
    }
  }
  estado.enlaceP3 = actual;
  estado.enlaceP3Snapshot = snapshotEnlaceP3(actual);
  if (estado.p3.conflictoEnlaceId === actual.id) estado.p3.conflictoEnlaceId = null;
  estado.p3.reemplazaEnlaceId = actual.reemplaza_enlace_id;
  guardarEnHistorialP3(actual);
  if (actualizarCampos) {
    estado.disenoValido = false;
    construirUrl();
  } else {
    actualizarUrlsDistribucion();
    renderizarP3();
  }
}

function seleccionarEnlaceP3(id) {
  if (estado.p3.ocupado) return;
  const enlace = estado.p3.historial.find((item) => item.id === id);
  if (!enlace) return;
  const canalAnterior = canalActual();
  const radioCanal = document.querySelector(`input[name="pp-canal"][value="${enlace.canal_promocion}"]`);
  if (radioCanal) radioCanal.checked = true;
  estado.canal = enlace.canal_promocion;
  const radioDestino = document.querySelector(`input[name="pp-tipo-destino"][value="${enlace.tipo_destino}"]`);
  if (radioDestino) radioDestino.checked = true;
  estado.tipoDestino = enlace.tipo_destino;
  $('pp-campaign').value = enlace.campaign;
  $('pp-content').value = enlace.content;
  $('pp-utm-confirmada').checked = false;
  if (canalAnterior !== estado.canal) {
    $('pp-texto').value = textoInicial(estado.producto, estado.canal);
    $('pp-contenido-confirmado').checked = false;
  }
  invalidarClaveP3();
  aplicarEnlaceActualP3(enlace, { formato: enlace._formato || formatoActual() });
  estado.disenoValido = false;
  construirUrl();
  try { pintarQrPreview($('pp-qr'), estado.urlDistribucion || estado.urlLarga || estado.canonical); } catch (_) { /* El render programado reintentará el QR. */ }
  estado.p3.mensaje = enlace.estado_enlace === 'activo'
    ? 'Enlace activo seleccionado. Confirma otra vez las UTM antes de distribuir.'
    : 'Enlace seleccionado. Sus identificadores se cargaron sin crear ni modificar filas.';
  estado.p3.mensajeError = false;
  renderizarP3();
  programarRender();
}

function prepararNuevoEnlaceP3() {
  if (!servicioP3Disponible() || estado.p3.ocupado) return;
  const actual = estado.enlaceP3;
  estado.p3.reemplazaEnlaceId = actual?.estado_enlace === 'borrador'
    ? actual.reemplaza_enlace_id
    : (actual?.estado_enlace === 'desactivado' ? actual.id : null);
  estado.enlaceP3 = null;
  estado.enlaceP3Snapshot = '';
  estado.p3.conflictoEnlaceId = null;
  invalidarClaveP3();
  estado.disenoValido = false;
  actualizarUrlsDistribucion();
  try { pintarQrPreview($('pp-qr'), estado.urlDistribucion || estado.urlLarga || estado.canonical); } catch (_) { /* El render programado reintentará el QR. */ }
  actualizarGate();
  if (estado.p3.reemplazaEnlaceId) {
    estado.p3.mensaje = 'Modo reemplazo preparado. “Guardar borrador” conservará la referencia al enlace desactivado; nunca lo reactivará.';
  } else if (actual?.estado_enlace === 'activo') {
    estado.p3.mensaje = 'Modo nuevo preparado sin reemplazo. Para reemplazar el enlace activo, selecciónalo, desactívalo de forma explícita y vuelve a preparar el reemplazo.';
  } else {
    estado.p3.mensaje = 'Modo nuevo preparado. Ajusta y confirma las UTM antes de guardar el borrador.';
  }
  estado.p3.mensajeError = false;
  renderizarP3();
  programarRender();
}

function prepararValoresAccionP3() {
  construirUrl();
  const campaign = normalizarUtm($('pp-campaign').value, 60);
  const content = normalizarUtm($('pp-content').value, 60);
  if ($('pp-campaign').value !== campaign || $('pp-content').value !== content) {
    $('pp-campaign').value = campaign;
    $('pp-content').value = content;
    $('pp-utm-confirmada').checked = false;
    registrarCambioP3();
    estado.disenoValido = false;
    programarRender();
    establecerMensajeP3('Normalizamos campaign y content. Revísalos y vuelve a confirmar que no describen personas.', true);
    return null;
  }
  construirUrl();
  if (!utmListaParaBorradorP3()) {
    establecerMensajeP3('Para guardar, completa campaign y content válidos, confirma que no describen personas y usa una campaña con slug publicable.', true);
    return null;
  }
  return { canal: canalActual(), campaign, content, formato: formatoActual(), tipoDestino: tipoDestinoActual() };
}

function mutacionP3Incierta(error) {
  return esTimeoutP3(error)
    || /ABORT|FAILED TO FETCH|NETWORK|P3_RESPUESTA_INVALIDA|P3_URL_CORTA_INVALIDA/.test(textoErrorP3(error));
}

async function manejarErrorMutacionP3(error, accion) {
  if (!mutacionP3Incierta(error)) {
    estado.p3.mensaje = mensajeErrorP3(error, accion);
    estado.p3.mensajeError = true;
    return;
  }
  const historialRefrescado = await refrescarHistorialP3Silencioso();
  const respuestaInvalida = /P3_RESPUESTA_INVALIDA|P3_URL_CORTA_INVALIDA/.test(textoErrorP3(error));
  const causa = esTimeoutP3(error)
    ? `La operación para ${accion} superó el límite de ${P3_TIMEOUT_MUTACION_MS / 1000} segundos`
    : respuestaInvalida
      ? `P3 devolvió una respuesta que no pudo validarse al intentar ${accion}`
      : `La conexión se interrumpió al intentar ${accion}`;
  estado.p3.mensaje = `${causa} y el resultado es incierto: pudo haberse confirmado en el servidor. ${historialRefrescado
    ? 'Actualizamos el historial autoritativo; revísalo antes de reintentar.'
    : 'Tampoco pudimos confirmar el historial; no repitas la operación sin volver a consultarlo.'}`;
  estado.p3.mensajeError = true;
}

function iniciarOperacionP3(mensaje) {
  if (estado.p3.ocupado) return null;
  estado.p3.ocupado = true;
  estado.p3.peticionId += 1;
  estado.p3.estadoPeticionId += 1;
  estado.p3.configPeticionId += 1;
  estado.p3.listaPeticionId += 1;
  estado.p3.distribucionPeticionId += 1;
  estado.p3.refrescandoConfig = false;
  estado.p3.mensaje = mensaje;
  estado.p3.mensajeError = false;
  renderizarP3();
  actualizarBotones();
  return estado.p3.peticionId;
}

function terminarOperacionP3(id) {
  if (id !== estado.p3.peticionId) return;
  estado.p3.ocupado = false;
  actualizarUrlsDistribucion();
  renderizarP3();
  actualizarGate();
}

async function guardarBorradorP3() {
  if (!servicioP3Disponible() || estado.enlaceP3 || estado.p3.ocupado) return;
  const valores = prepararValoresAccionP3();
  if (!valores) return;
  const campaignBase = campaignBaseParaCrearP3(valores.campaign);
  if (!campaignBase) {
    establecerMensajeP3('No fue posible derivar una base válida para campaign. Revisa el identificador y vuelve a intentarlo.', true);
    return;
  }
  const firmaSolicitud = firmaP3(valores);
  const firmaClave = `${firmaSolicitud}|${campaignBase}|${estado.p3.reemplazaEnlaceId || ''}`;
  try {
    if (!estado.p3.claveIdempotencia || estado.p3.firmaClave !== firmaClave) {
      estado.p3.claveIdempotencia = crearClaveIdempotenciaP3();
      estado.p3.firmaClave = firmaClave;
    }
  } catch (_) {
    establecerMensajeP3('Este navegador no ofrece generación criptográfica segura. Usa P2 o actualiza el navegador antes de crear un borrador.', true);
    return;
  }
  const reemplazaId = estado.p3.reemplazaEnlaceId;
  const idOperacion = iniciarOperacionP3('Guardando borrador P3…');
  if (!idOperacion) return;
  try {
    const datos = await invocarRpcP3(RPC_P3.crear, {
      p_campana_producto_id: estado.producto.id,
      p_tipo_destino: valores.tipoDestino,
      p_canal_promocion: valores.canal,
      p_campaign_base: campaignBase,
      p_content: valores.content,
      p_clave_idempotencia: estado.p3.claveIdempotencia,
      p_reemplaza_enlace_id: reemplazaId,
    }, { timeoutMs: P3_TIMEOUT_MUTACION_MS });
    const enlace = validarRespuestaEnlaceP3(datos, {
      estado: 'borrador',
      canal: valores.canal,
      campaignBase,
      content: valores.content,
      tipoDestino: valores.tipoDestino,
      reemplazaEnlaceId: reemplazaId,
    });
    const campaignFinal = campaignFinalDevueltaP3(enlace.campaign, campaignBase);
    enlace._formato = valores.formato;
    guardarEnHistorialP3(enlace);
    if (firmaP3() === firmaSolicitud) aplicarEnlaceActualP3(enlace, { actualizarCampos: true, formato: valores.formato });
    else {
      estado.enlaceP3 = null; estado.enlaceP3Snapshot = ''; actualizarUrlsDistribucion();
    }
    invalidarClaveP3();
    await refrescarHistorialP3Silencioso();
    estado.p3.mensaje = estado.enlaceP3?.id === enlace.id && enlaceCoincideP3(estado.enlaceP3)
      ? `Borrador guardado. Campaign final: “${campaignFinal}”.`
      : 'Borrador guardado, pero el formulario cambió durante la operación. Selecciónalo en el historial para revisarlo.';
    estado.p3.mensajeError = false;
    await renderizar();
  } catch (error) {
    await manejarErrorMutacionP3(error, 'guardar el borrador');
  } finally { terminarOperacionP3(idOperacion); }
}

async function actualizarBorradorP3() {
  const previo = estado.enlaceP3;
  if (!servicioP3Disponible() || previo?.estado_enlace !== 'borrador' || estado.p3.ocupado) return;
  if (estado.p3.conflictoEnlaceId === previo.id) {
    establecerMensajeP3('El historial ya se refrescó tras un conflicto. Vuelve a seleccionar el borrador antes de guardar para no sobrescribir otra versión.', true);
    return;
  }
  const valores = prepararValoresAccionP3();
  if (!valores) return;
  if (enlaceCoincideP3(previo)) {
    establecerMensajeP3('El borrador ya coincide con los identificadores actuales; no hay cambios por actualizar.');
    return;
  }
  const firmaSolicitud = firmaP3(valores);
  const campaignBase = campaignBaseParaEditarP3(previo, valores.campaign);
  const idOperacion = iniciarOperacionP3('Actualizando el borrador P3…');
  if (!idOperacion) return;
  try {
    const datos = await invocarRpcP3(RPC_P3.editar, {
      p_enlace_id: previo.id,
      p_actualizado_en_esperado: previo.actualizado_en,
      p_tipo_destino: valores.tipoDestino,
      p_canal_promocion: valores.canal,
      p_campaign_base: campaignBase,
      p_content: valores.content,
    }, { timeoutMs: P3_TIMEOUT_MUTACION_MS });
    const enlace = validarRespuestaEnlaceP3(datos, {
      id: previo.id,
      estado: 'borrador',
      canal: valores.canal,
      campaignBase,
      ...(campaignBase === previo.campaign_base ? { campaign: previo.campaign } : {}),
      content: valores.content,
      tipoDestino: valores.tipoDestino,
      reemplazaEnlaceId: previo.reemplaza_enlace_id,
      actualizadoEnMinimo: previo.actualizado_en,
      exigirVersionNueva: true,
    });
    const campaignFinal = campaignFinalDevueltaP3(enlace.campaign, campaignBase);
    enlace._formato = valores.formato;
    guardarEnHistorialP3(enlace);
    if (firmaP3() === firmaSolicitud) aplicarEnlaceActualP3(enlace, { actualizarCampos: true, formato: valores.formato });
    else {
      estado.enlaceP3 = { ...enlace, _formato: valores.formato };
      estado.enlaceP3Snapshot = snapshotEnlaceP3(estado.enlaceP3, valores);
      actualizarUrlsDistribucion();
    }
    await refrescarHistorialP3Silencioso();
    estado.p3.mensaje = enlaceCoincideP3(estado.enlaceP3)
      ? `Borrador actualizado. Campaign final: “${campaignFinal}”.`
      : 'Borrador actualizado, pero hay cambios posteriores aún sin guardar.';
    estado.p3.mensajeError = false;
    await renderizar();
  } catch (error) {
    if (/P3_BORRADOR_VERSION_CONFLICTO/.test(textoErrorP3(error))) {
      estado.p3.conflictoEnlaceId = previo.id;
      await refrescarHistorialP3Silencioso();
      actualizarUrlsDistribucion();
      programarRender();
      estado.p3.mensaje = mensajeErrorP3(error, 'actualizar el borrador');
      estado.p3.mensajeError = true;
    } else {
      await manejarErrorMutacionP3(error, 'actualizar el borrador');
    }
  } finally { terminarOperacionP3(idOperacion); }
}

async function activarEnlaceP3() {
  if (estado.p3.ocupado) return;
  const configResultado = await refrescarEstadoP3({ motivo: 'activacion', timeoutMs: P3_TIMEOUT_LECTURA_MS });
  const previo = estado.enlaceP3;
  construirUrl();
  if (!configResultado.ok || !servicioP3Disponible() || estado.p3.config.activacion_habilitada !== true || previo?.estado_enlace !== 'borrador'
    || !enlaceCoincideP3(previo) || !listoEnlace() || !listoContenido() || !estado.disenoValido || estado.p3.ocupado) {
    establecerMensajeP3('Para activar, el gate de activación P3 debe estar habilitado y el borrador debe coincidir con UTM confirmadas, contenido revisado, ficha confirmada y diseño válido.', true);
    return;
  }
  const valoresSolicitud = valoresActualesP3();
  const firmaSolicitud = firmaP3(valoresSolicitud);
  const formatoSolicitud = valoresSolicitud.formato;
  const idOperacion = iniciarOperacionP3('Activando el enlace corto…');
  if (!idOperacion) return;
  try {
    const datos = await invocarRpcP3(
      RPC_P3.activar,
      { p_enlace_id: previo.id },
      { timeoutMs: P3_TIMEOUT_MUTACION_MS },
    );
    const enlace = validarRespuestaEnlaceP3(datos, {
      id: previo.id,
      estados: ['activo'],
      canal: previo.canal_promocion,
      campaignBase: previo.campaign_base,
      campaign: previo.campaign,
      content: previo.content,
      tipoDestino: previo.tipo_destino,
      reemplazaEnlaceId: previo.reemplaza_enlace_id,
      actualizadoEnMinimo: previo.actualizado_en,
    });
    enlace._formato = formatoSolicitud;
    if (!urlCortaSeguraP3(enlace.url_corta, enlace.codigo)) throw new Error('P3_URL_CORTA_INVALIDA');
    guardarEnHistorialP3(enlace);
    if (firmaP3() === firmaSolicitud) aplicarEnlaceActualP3(enlace, { actualizarCampos: true, formato: formatoSolicitud });
    else {
      estado.enlaceP3 = { ...enlace, _formato: formatoSolicitud };
      estado.enlaceP3Snapshot = snapshotEnlaceP3(estado.enlaceP3, valoresSolicitud);
      actualizarUrlsDistribucion();
    }
    await refrescarHistorialP3Silencioso();
    if (enlaceP3Conectado()) {
      estado.p3.mensaje = estado.p3.config.conteo_habilitado
        ? 'Enlace activado. La URL corta devuelta por P3 ahora se usa en copia, texto, Share, QR y PNG; los totales son clics aproximados.'
        : 'Enlace activado y en distribución. El redirect funciona; el conteo de clics aproximados está pausado.';
    } else if (!enlaceCoincideP3(estado.enlaceP3)) {
      estado.p3.mensaje = 'Enlace activado, pero el formulario cambió: quedó desprendido y se mantiene el destino largo.';
    } else if (estado.enlaceP3?.resoluble !== true) {
      estado.p3.mensaje = 'Enlace activado, pero el producto dejó de estar publicado o resoluble. Se mantiene el destino largo P2.';
    } else {
      estado.p3.mensaje = 'Enlace activado. El redirect o el historial no tienen confirmación vigente, por lo que se mantiene el destino largo P2.';
    }
    estado.p3.mensajeError = false;
    await renderizar();
  } catch (error) {
    await manejarErrorMutacionP3(error, 'activar el enlace');
  } finally { terminarOperacionP3(idOperacion); }
}

async function desactivarEnlaceP3() {
  const previo = estado.enlaceP3;
  if (!servicioP3Disponible() || previo?.estado_enlace !== 'activo' || estado.p3.ocupado) return;
  const confirmado = window.confirm('¿Desactivar este enlace corto? La desactivación es terminal: nunca podrá reactivarse. Para continuar tendrás que preparar un reemplazo o uno nuevo.');
  if (!confirmado) return;
  const idOperacion = iniciarOperacionP3('Desactivando el enlace corto…');
  if (!idOperacion) return;
  try {
    const datos = await invocarRpcP3(
      RPC_P3.desactivar,
      { p_enlace_id: previo.id },
      { timeoutMs: P3_TIMEOUT_MUTACION_MS },
    );
    const enlace = validarRespuestaEnlaceP3(datos, {
      id: previo.id,
      estado: 'desactivado',
      canal: previo.canal_promocion,
      campaignBase: previo.campaign_base,
      campaign: previo.campaign,
      content: previo.content,
      tipoDestino: previo.tipo_destino,
      reemplazaEnlaceId: previo.reemplaza_enlace_id,
      actualizadoEnMinimo: previo.actualizado_en,
    });
    enlace._formato = previo._formato;
    estado.enlaceP3 = enlace;
    estado.enlaceP3Snapshot = '';
    guardarEnHistorialP3(enlace);
    actualizarUrlsDistribucion();
    await refrescarHistorialP3Silencioso();
    estado.p3.mensaje = 'Enlace desactivado de forma terminal. P2 vuelve a usar el destino oficial largo; prepara un reemplazo para continuar con P3.';
    estado.p3.mensajeError = false;
    await renderizar();
  } catch (error) {
    await manejarErrorMutacionP3(error, 'desactivar el enlace');
  } finally { terminarOperacionP3(idOperacion); }
}

async function eliminarBorradorP3() {
  const previo = estado.enlaceP3;
  if (!servicioP3Disponible() || previo?.estado_enlace !== 'borrador' || estado.p3.ocupado) return;
  if (!window.confirm('¿Eliminar este borrador de enlace corto? Esta acción no afecta el destino oficial largo P2.')) return;
  const idOperacion = iniciarOperacionP3('Eliminando el borrador P3…');
  if (!idOperacion) return;
  try {
    const eliminado = await invocarRpcP3(
      RPC_P3.eliminar,
      { p_enlace_id: previo.id },
      { timeoutMs: P3_TIMEOUT_MUTACION_MS },
    );
    if (eliminado !== true) throw new Error('P3_RESPUESTA_INVALIDA');
    estado.p3.historial = estado.p3.historial.filter((enlace) => enlace.id !== previo.id);
    estado.p3.reemplazaEnlaceId = previo.reemplaza_enlace_id;
    estado.enlaceP3 = null;
    estado.enlaceP3Snapshot = '';
    invalidarClaveP3();
    actualizarUrlsDistribucion();
    await refrescarHistorialP3Silencioso();
    estado.p3.mensaje = previo.reemplaza_enlace_id
      ? 'Borrador eliminado. Se conservó el objetivo de reemplazo para el próximo borrador.'
      : 'Borrador eliminado. Puedes preparar uno nuevo; P2 continúa operativo.';
    estado.p3.mensajeError = false;
    programarRender();
  } catch (error) {
    await manejarErrorMutacionP3(error, 'eliminar el borrador');
  } finally { terminarOperacionP3(idOperacion); }
}

async function cargarP3() {
  estado.p3.cargando = true;
  estado.p3.mensaje = 'Consultando configuración e historial P3…';
  estado.p3.mensajeError = false;
  renderizarP3();
  const resultado = await refrescarEstadoP3({ motivo: 'inicial', timeoutMs: P3_TIMEOUT_LECTURA_MS });
  estado.p3.cargando = false;
  if (resultado.ok) {
    const valores = valoresActualesP3();
    const coincidente = estado.p3.historial.find((enlace) => enlace.estado_enlace === 'activo' && enlaceCoincideP3(enlace, valores, false))
      || estado.p3.historial.find((enlace) => enlace.estado_enlace === 'borrador' && enlaceCoincideP3(enlace, valores, false));
    if (coincidente) aplicarEnlaceActualP3(coincidente, { formato: valores.formato });
    const activacion = estado.p3.config.activacion_habilitada
      ? 'La activación de nuevos enlaces está habilitada.'
      : 'La activación de nuevos enlaces está pausada.';
    estado.p3.mensaje = !estado.p3.config.construido
      ? 'La configuración P3 existe, pero la infraestructura aún no está construida. P2 seguirá distribuyendo el destino oficial largo.'
      : estado.p3.config.redirect_habilitado
        ? (estado.p3.config.conteo_habilitado
          ? `El redirect P3 está disponible. ${activacion} Los totales visibles son clics aproximados.`
          : `El redirect P3 está disponible y los enlaces activos resolubles pueden distribuirse. El conteo de clics aproximados está pausado. ${activacion}`)
        : `El redirect P3 está apagado. ${activacion} P2 seguirá distribuyendo el destino oficial largo; el conteo visible se rotula siempre como clics aproximados.`;
    estado.p3.mensajeError = false;
  } else {
    const errorP3 = resultado.configResultado?.error || resultado.listaResultado?.error || resultado.error;
    estado.p3.mensaje = mensajeErrorP3(errorP3, 'consultar P3');
    estado.p3.mensajeError = true;
  }
  actualizarUrlsDistribucion();
  renderizarP3();
  actualizarGate();
  if (enlaceP3Conectado()) await renderizar();
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
    lead: 'Diseña la pieza, prepara su mensaje y distribuye el destino oficial largo o un enlace corto controlado. Tú decides qué sale: nada se publica automáticamente.',
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
    estado.canal = canalActual(); estado.formato = formatoActual(); estado.tipoDestino = tipoDestinoActual();
    $('pp-campaign').value = crearCampaign(estado.producto.slug || estado.producto.nombre);
    $('pp-content').value = contentInicial(estado.canal, estado.formato);
    sugerirTextos(); actualizarSliders(); cablearControles(); evaluarElegibilidad();
    $('pp-carga').hidden = true; $('pp-estudio').hidden = false;
    montarAccesoPreview();
    await renderizar();
    try { await cargarP3(); }
    catch (_) {
      estado.p3.cargando = false;
      estado.p3.refrescandoConfig = false;
      invalidarConfigP3();
      invalidarListaP3();
      estado.p3.mensaje = 'P3 no pudo iniciarse. P2 continúa operativo con el destino oficial largo.';
      estado.p3.mensajeError = true;
      actualizarUrlsDistribucion();
      renderizarP3();
      actualizarGate();
    }
    iniciarPollingConfigP3();
  } catch (error) {
    mostrarError(error instanceof Error ? error.message : 'Ocurrió un error al preparar la campaña.');
  }
})();
