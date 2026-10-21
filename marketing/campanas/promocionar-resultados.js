import { asegurarAcceso, montarHeader, supabase } from '../marketing-core.js';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ISO_RE = /^\d{4}-\d{2}-\d{2}$/;
const PERIODOS = new Set(['7', '30', '90', '365']);
const CAMPOS_SERIE = ['fecha', 'clics_aproximados', 'sesiones_consentidas', 'checkouts_consentidos', 'intenciones', 'pagos_approved_convertidos', 'pedidos_exactos', 'ingresos_exactos_cop'];
const CAMPOS_DESGLOSE = ['enlace_id', 'canal', 'source', 'medium', 'campaign', 'pieza', 'estado', 'clics_aproximados', 'sesiones_consentidas', 'checkouts_consentidos', 'intenciones', 'pagos_approved_convertidos', 'pedidos_exactos', 'ingresos_exactos_cop'];
const $ = (id) => document.getElementById(id);
const nf = new Intl.NumberFormat('es-CO', { maximumFractionDigits: 0 });
const pf = new Intl.NumberFormat('es-CO', { minimumFractionDigits: 0, maximumFractionDigits: 2 });

let campanaId = '';
let periodo = '30';
let datos = null;
let serieActiva = 'clics_aproximados';
let controlador = null;
let solicitudId = 0;

function hoyBogota() {
  const partes = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Bogota', year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(new Date());
  const valor = Object.fromEntries(partes.map((p) => [p.type, p.value]));
  return `${valor.year}-${valor.month}-${valor.day}`;
}

function menosDias(iso, dias) {
  const [y, m, d] = iso.split('-').map(Number);
  const fecha = new Date(Date.UTC(y, m - 1, d));
  fecha.setUTCDate(fecha.getUTCDate() - dias);
  return fecha.toISOString().slice(0, 10);
}

function rangoActual() {
  const hasta = hoyBogota();
  return { desde: menosDias(hasta, Number(periodo) - 1), hasta };
}

function esObjeto(v) { return !!v && typeof v === 'object' && !Array.isArray(v); }
function numero(v) { return typeof v === 'number' && Number.isFinite(v) && v >= 0; }
function textoONulo(v) { return v === null || typeof v === 'string'; }
function exigir(condicion, codigo) { if (!condicion) throw new Error('P5_PAYLOAD_INVALIDO_' + codigo); }
function validarNumeroCampos(obj, campos, codigo) { campos.forEach((k) => exigir(numero(obj[k]), codigo + '_' + k)); }

function validarPayload(raw, campana, rangoEsperado) {
  exigir(esObjeto(raw) && raw.contrato === 'promocionar_p5_resultados_v1', 'CONTRATO');
  exigir(esObjeto(raw.campana) && raw.campana.id === campanaId && campana.id === campanaId, 'CAMPANA');
  exigir(raw.campana.nombre === campana.nombre && typeof raw.campana.estado === 'string' && typeof raw.campana.publicado === 'boolean' && typeof raw.campana.activo === 'boolean', 'CAMPANA_DATOS');
  exigir(esObjeto(raw.periodo) && ISO_RE.test(raw.periodo.desde) && ISO_RE.test(raw.periodo.hasta), 'PERIODO');
  exigir(raw.periodo.desde === rangoEsperado.desde && raw.periodo.hasta === rangoEsperado.hasta, 'PERIODO_SOLICITADO');
  exigir(raw.periodo.zona_horaria === 'America/Bogota' && raw.periodo.moneda === 'COP', 'RELOJ_MONEDA');
  exigir(esObjeto(raw.totales), 'TOTALES');
  validarNumeroCampos(raw.totales, ['enlaces', 'clics_aproximados', 'sesiones_consentidas', 'eventos_consentidos', 'llegadas_consentidas', 'productos_vistos_consentidos', 'checkouts_consentidos', 'sesiones_con_checkout', 'intenciones', 'intenciones_no_aprobadas', 'intenciones_aprobadas_cohorte', 'pagos_approved_convertidos', 'pedidos_exactos', 'ingresos_exactos_cop', 'pedidos_exactos_anulados', 'ingresos_exactos_anulados_cop'], 'TOTAL');
  exigir(esObjeto(raw.tasas), 'TASAS');
  ['pedido_sobre_clic', 'checkout_sobre_sesion', 'pago_sobre_intencion'].forEach((k) => {
    const t = raw.tasas[k];
    exigir(esObjeto(t) && typeof t.disponible === 'boolean' && numero(t.numerador) && numero(t.denominador) && typeof t.denominador_etiqueta === 'string', 'TASA_' + k);
    exigir((t.disponible && numero(t.valor)) || (!t.disponible && t.valor === null), 'TASA_VALOR_' + k);
  });
  exigir(Array.isArray(raw.serie) && raw.serie.length === Number(periodo) && raw.serie.length <= 731, 'SERIE');
  raw.serie.forEach((fila, indice) => {
    exigir(esObjeto(fila) && ISO_RE.test(fila.fecha) && fila.fecha === menosDias(rangoEsperado.desde, -indice), 'SERIE_FILA');
    validarNumeroCampos(fila, CAMPOS_SERIE.slice(1), 'SERIE');
  });
  exigir(Array.isArray(raw.desglose), 'DESGLOSE');
  raw.desglose.forEach((fila) => {
    exigir(esObjeto(fila) && UUID_RE.test(fila.enlace_id), 'DESGLOSE_ID');
    CAMPOS_DESGLOSE.slice(1, 7).forEach((k) => exigir(textoONulo(fila[k]), 'DESGLOSE_TEXTO_' + k));
    exigir(['whatsapp','instagram','facebook','email','qr','anuncio_manual','otro_controlado'].includes(fila.canal), 'DESGLOSE_CANAL');
    exigir(['borrador','activo','desactivado'].includes(fila.estado), 'DESGLOSE_ESTADO');
    validarNumeroCampos(fila, CAMPOS_DESGLOSE.slice(7), 'DESGLOSE');
  });
  exigir(esObjeto(raw.cobertura) && ['completa', 'parcial'].includes(raw.cobertura.estado) && Array.isArray(raw.cobertura.razones) && raw.cobertura.razones.every((x) => ['detalle_p3_compactado','analitica_consentida_inactiva','sin_eventos_consentidos_periodo'].includes(x)), 'COBERTURA');
  exigir(typeof raw.cobertura.analitica_consentida_activa === 'boolean' && typeof raw.cobertura.periodo_detalle_p3_completo === 'boolean', 'COBERTURA_FLAGS');
  exigir(ISO_RE.test(raw.cobertura.detalle_p3_disponible_desde) &&
    (raw.cobertura.detalle_p3_disponible_hasta === null || ISO_RE.test(raw.cobertura.detalle_p3_disponible_hasta)), 'COBERTURA_DETALLE_P3');
  exigir(numero(raw.cobertura.clics_compactados_sin_fecha) && numero(raw.cobertura.clics_vitalicios_aproximados), 'COBERTURA_NUM');
  exigir(esObjeto(raw.frescura) && esObjeto(raw.formulas), 'META');
  return raw;
}

function ocultarEstados() {
  ['pr-carga', 'pr-error', 'pr-vacio-total', 'pr-vacio-periodo', 'pr-parcial', 'pr-contenido'].forEach((id) => { $(id).hidden = true; });
}

function mostrarCarga() {
  ocultarEstados();
  $('pr-carga').hidden = false;
  $('pr-carga').setAttribute('aria-busy', 'true');
}

function mostrarError(error) {
  ocultarEstados();
  $('pr-error-texto').textContent = mensajeError(error);
  $('pr-error').hidden = false;
}

function mensajeError(error) {
  const m = String(error?.message || error || 'Error desconocido.');
  if (/P5_DEADLINE_EXCEDIDO/.test(m)) return 'La consulta tardó más de 8 segundos. Puedes reintentarlo.';
  if (/AbortError|aborted/i.test(m)) return 'La consulta anterior fue reemplazada.';
  if (/P5_ACCESO|permission denied|42501/i.test(m)) return 'Tu cuenta no tiene permiso para leer estos resultados.';
  if (/PGRST202|promocionar_p5_resultados|function.*not found/i.test(m)) return 'La lectura P5 todavía no está desplegada en Supabase.';
  if (/P5_PAYLOAD_INVALIDO/.test(m)) return 'El servidor respondió con un contrato P5 incompleto. No mostramos cifras dudosas.';
  if (/P5_CAMPANA_NO_ENCONTRADA/.test(m)) return 'La campaña no existe o ya no está disponible para tu cuenta.';
  return 'No se pudo completar la lectura. Revisa la conexión e inténtalo de nuevo.';
}

function actualizarNavegacion() {
  const q = '?id=' + encodeURIComponent(campanaId);
  $('pr-tab-editor').href = 'promocionar.html' + q;
  $('pr-tab-resultados').href = 'promocionar-resultados.html' + q;
  history.replaceState(null, '', q + '&periodo=' + periodo);
}

function pintarPeriodos() {
  document.querySelectorAll('[data-periodo]').forEach((b) => b.setAttribute('aria-pressed', String(b.dataset.periodo === periodo)));
}

function fmt(n) { return nf.format(Number(n) || 0); }
function cop(n) { return '$' + nf.format(Number(n) || 0); }
function pct(t) { return t.disponible ? pf.format(t.valor) + '%' : 'No disponible'; }
function fecha(iso) {
  if (!iso) return 'Sin datos';
  const d = new Date(String(iso).slice(0, 10) + 'T12:00:00');
  return new Intl.DateTimeFormat('es-CO', { day: 'numeric', month: 'short', year: 'numeric' }).format(d);
}
function momento(iso) {
  if (!iso) return 'Sin datos';
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? 'Sin datos' : new Intl.DateTimeFormat('es-CO', { timeZone: 'America/Bogota', dateStyle: 'medium', timeStyle: 'short' }).format(d);
}
function etiquetaCanal(v) { return ({ whatsapp: 'WhatsApp', instagram: 'Instagram', facebook: 'Facebook', email: 'Email', qr: 'QR', anuncio_manual: 'Anuncio manual', otro_controlado: 'Otro controlado' })[v] || v || 'Canal sin nombre'; }

function crearKpi(k, v, ayuda) {
  const el = document.createElement('article'); el.className = 'pr-kpi';
  const ek = document.createElement('span'); ek.className = 'k'; ek.textContent = k;
  const ev = document.createElement('strong'); ev.className = 'v'; ev.textContent = v;
  const ea = document.createElement('small'); ea.textContent = ayuda;
  el.append(ek, ev, ea); return el;
}

function pintarKpis(d) {
  const t = d.totales;
  const frag = document.createDocumentFragment();
  frag.append(
    crearKpi('Ingresos exactos', cop(t.ingresos_exactos_cop), 'Pedidos no anulados con cadena P4 completa.'),
    crearKpi('Pedidos exactos', fmt(t.pedidos_exactos), 'Intención prod procesada + APPROVED + mismo pedido/FK.'),
    crearKpi('Pagos convertidos', fmt(t.pagos_approved_convertidos), 'APPROVED que sí produjeron pedido.'),
    crearKpi('Checkouts consentidos', fmt(t.checkouts_consentidos), 'Eventos; solo población con analítica aceptada.'),
    crearKpi('Clics aproximados', fmt(t.clics_aproximados), 'Navegaciones agregadas P3; no personas ni únicos.')
  );
  $('pr-kpis').replaceChildren(frag);
}

function paso(nombre, valor, detalle) {
  const el = document.createElement('div'); el.className = 'pr-paso';
  const n = document.createElement('span'); n.textContent = nombre;
  const v = document.createElement('b'); v.textContent = valor;
  const d = document.createElement('small'); d.textContent = detalle;
  el.append(n, v, d); return el;
}

function poblacion(clase, titulo, intro, pasos, tasa) {
  const el = document.createElement('article'); el.className = 'pr-poblacion ' + clase;
  const h = document.createElement('h3'); h.textContent = titulo;
  const p = document.createElement('p'); p.textContent = intro;
  el.append(h, p, ...pasos);
  if (tasa) { const t = document.createElement('p'); t.className = 'pr-tasa'; const b = document.createElement('b'); b.textContent = tasa.valor; t.append(b, document.createElement('br'), document.createTextNode(tasa.texto)); el.append(t); }
  return el;
}

function pintarPoblaciones(d) {
  const t = d.totales, ta = d.tasas;
  $('pr-poblaciones').replaceChildren(
    poblacion('aproximada', 'Población aproximada', 'P3 cuenta aperturas agregadas; no identifica personas ni sesiones.', [
      paso('Clics aproximados', fmt(t.clics_aproximados), 'Detalle diario retenido del periodo'),
      paso('Histórico sin fecha', fmt(d.cobertura.clics_compactados_sin_fecha), 'No se reparte ni se fuerza dentro de la ventana')
    ], { valor: pct(ta.pedido_sobre_clic), texto: 'Pedidos exactos ÷ ' + ta.pedido_sobre_clic.denominador_etiqueta + '.' }),
    poblacion('consentida', 'Población consentida', 'Solo navegadores que aceptaron la analítica propia MAGANDHI.', [
      paso('Sesiones', fmt(t.sesiones_consentidas), 'Sesiones con UTM propia de este enlace'),
      paso('Producto visto', fmt(t.productos_vistos_consentidos), 'Eventos consentidos'),
      paso('Checkout iniciado', fmt(t.checkouts_consentidos), 'Eventos consentidos; no pagos')
    ], { valor: pct(ta.checkout_sobre_sesion), texto: 'Sesiones con checkout ÷ ' + ta.checkout_sobre_sesion.denominador_etiqueta + '.' }),
    poblacion('transaccional', 'Población transaccional', 'La autoridad exacta vive en intención, Wompi y pedido; no en la analítica.', [
      paso('Intenciones', fmt(t.intenciones), 'Incluye no aprobadas'),
      paso('Pagos APPROVED convertidos', fmt(t.pagos_approved_convertidos), 'Entorno prod con pedido creado'),
      paso('Pedidos exactos vigentes', fmt(t.pedidos_exactos), cop(t.ingresos_exactos_cop) + ' COP')
    ], { valor: pct(ta.pago_sobre_intencion), texto: 'Intenciones del cohorte que terminaron APPROVED ÷ ' + ta.pago_sobre_intencion.denominador_etiqueta + '.' })
  );
}

function pintarGrafica() {
  const filas = datos.serie;
  const cont = $('pr-grafica'); cont.replaceChildren();
  // El viewBox sigue el ancho real: en móvil la gráfica conserva altura y
  // legibilidad en vez de reducir un lienzo desktop completo a una miniatura.
  const ancho = Math.max(320, Math.min(920, Math.round(cont.clientWidth || 920)));
  const movil = ancho < 560;
  const alto = movil ? 220 : 260;
  const izq = movil ? 42 : 48, der = movil ? 10 : 16, arriba = 18, abajo = 36;
  const valores = filas.map((x) => Number(x[serieActiva]) || 0);
  const max = Math.max(1, ...valores);
  const x = (i) => izq + (filas.length === 1 ? 0 : i * (ancho - izq - der) / (filas.length - 1));
  const y = (v) => arriba + (alto - arriba - abajo) * (1 - v / max);
  const ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg'); svg.setAttribute('viewBox', `0 0 ${ancho} ${alto}`); svg.setAttribute('role', 'img');
  const titulo = document.createElementNS(ns, 'title'); titulo.textContent = `Serie diaria de ${serieActiva.replaceAll('_', ' ')} entre ${datos.periodo.desde} y ${datos.periodo.hasta}`; svg.append(titulo);
  for (let i = 0; i <= 4; i += 1) {
    const gy = arriba + i * (alto - arriba - abajo) / 4;
    const l = document.createElementNS(ns, 'line'); l.classList.add('grid'); l.setAttribute('x1', izq); l.setAttribute('x2', ancho - der); l.setAttribute('y1', gy); l.setAttribute('y2', gy); svg.append(l);
    const tx = document.createElementNS(ns, 'text'); tx.setAttribute('x', izq - 8); tx.setAttribute('y', gy + 3); tx.setAttribute('text-anchor', 'end'); tx.textContent = fmt(max * (4 - i) / 4); svg.append(tx);
  }
  const puntos = filas.map((f, i) => `${x(i)},${y(valores[i])}`);
  const area = document.createElementNS(ns, 'path'); area.classList.add('area'); area.setAttribute('d', `M${x(0)},${alto - abajo} L${puntos.join(' L')} L${x(filas.length - 1)},${alto - abajo} Z`); svg.append(area);
  const linea = document.createElementNS(ns, 'polyline'); linea.classList.add('line'); linea.setAttribute('points', puntos.join(' ')); svg.append(linea);
  const maxEtiquetas = Math.max(2, Math.floor((ancho - izq - der) / (movil ? 92 : 70)));
  const salto = Math.max(1, Math.ceil(filas.length / maxEtiquetas));
  filas.forEach((f, i) => {
    const c = document.createElementNS(ns, 'circle'); c.classList.add('point'); c.setAttribute('cx', x(i)); c.setAttribute('cy', y(valores[i])); c.setAttribute('r', filas.length > 100 ? 1.5 : 3);
    const ct = document.createElementNS(ns, 'title'); ct.textContent = `${f.fecha}: ${fmt(valores[i])}`; c.append(ct); svg.append(c);
    if (i % salto === 0 || i === filas.length - 1) { const tx = document.createElementNS(ns, 'text'); tx.setAttribute('x', x(i)); tx.setAttribute('y', alto - 12); tx.setAttribute('text-anchor', i === 0 ? 'start' : i === filas.length - 1 ? 'end' : 'middle'); tx.textContent = fecha(f.fecha).replace(/ de /g, ' '); svg.append(tx); }
  });
  cont.append(svg);
}

function pintarTablaSerie(d) {
  const frag = document.createDocumentFragment();
  d.serie.forEach((f) => { const tr = document.createElement('tr'); CAMPOS_SERIE.forEach((k) => { const td = document.createElement('td'); td.textContent = k === 'fecha' ? fecha(f[k]) : k === 'ingresos_exactos_cop' ? cop(f[k]) : fmt(f[k]); tr.append(td); }); frag.append(tr); });
  $('pr-serie-tabla').replaceChildren(frag);
}

function pintarDesglose(d) {
  const cont = $('pr-desglose'); cont.replaceChildren();
  if (!d.desglose.length) { const p = document.createElement('p'); p.className = 'pr-desglose-vacio'; p.textContent = 'Aún no hay enlaces para desglosar. El Editor permite preparar el primero.'; cont.append(p); return; }
  const table = document.createElement('table');
  const head = document.createElement('thead'); const hr = document.createElement('tr');
  ['Canal / pieza', 'Estado', 'Clics aprox.', 'Sesiones', 'Checkouts', 'Intenciones', 'Pagos', 'Pedidos', 'Ingresos COP'].forEach((v) => { const th = document.createElement('th'); th.textContent = v; hr.append(th); }); head.append(hr);
  const body = document.createElement('tbody');
  d.desglose.forEach((f) => {
    const tr = document.createElement('tr');
    const td0 = document.createElement('td'); td0.className = 'pr-pieza'; const a = document.createElement('span'); a.className = 'pr-link-principal'; a.textContent = etiquetaCanal(f.canal) + (f.pieza ? ' · ' + f.pieza : ''); const s = document.createElement('span'); s.className = 'pr-link-sub'; s.textContent = f.source + ' / ' + f.medium + ' · ' + f.campaign; td0.append(a, s); tr.append(td0);
    const st = document.createElement('td'); const badge = document.createElement('span'); badge.className = 'pr-badge ' + f.estado; badge.textContent = f.estado; st.append(badge); tr.append(st);
    [f.clics_aproximados, f.sesiones_consentidas, f.checkouts_consentidos, f.intenciones, f.pagos_approved_convertidos, f.pedidos_exactos].forEach((n) => { const td = document.createElement('td'); td.textContent = fmt(n); tr.append(td); });
    const ing = document.createElement('td'); ing.textContent = cop(f.ingresos_exactos_cop); tr.append(ing); body.append(tr);
  });
  table.append(head, body); cont.append(table);
}

function calidadDato(dt, dd) { const div = document.createElement('div'); const t = document.createElement('dt'); t.textContent = dt; const d = document.createElement('dd'); d.textContent = dd; div.append(t, d); return div; }
function pintarCalidad(d) {
  const c = d.cobertura, f = d.frescura;
  $('pr-calidad-datos').replaceChildren(
    calidadDato('Detalle P3', c.periodo_detalle_p3_completo ? 'Completo para el periodo' : 'Parcial desde ' + fecha(c.detalle_p3_disponible_desde)),
    calidadDato('Analítica consentida', c.analitica_consentida_activa ? 'Activa; solo incluye quien aceptó' : 'Inactiva o sin política; no se completan huecos'),
    calidadDato('Último clic aproximado', f.ultimo_clic_fecha_colombia ? fecha(f.ultimo_clic_fecha_colombia) : 'Sin clics retenidos'),
    calidadDato('Último evento consentido', momento(f.ultimo_evento_consentido)),
    calidadDato('Último pago convertido', momento(f.ultimo_pago_convertido)),
    calidadDato('Intención sintética P4', 'No identificable por esquema; queda entre no aprobadas, nunca en pedidos/ingresos')
  );
}

function sumaActividad(t) { return t.clics_aproximados + t.eventos_consentidos + t.intenciones + t.pedidos_exactos + t.pedidos_exactos_anulados; }
function pintar(d) {
  ocultarEstados(); datos = d;
  $('pr-campana-nombre').textContent = d.campana.nombre;
  $('pr-campana-meta').textContent = `${d.campana.estado} · ${d.totales.enlaces} ${d.totales.enlaces === 1 ? 'enlace' : 'enlaces'} · zona America/Bogota`;
  $('pr-rango').textContent = fecha(d.periodo.desde) + ' — ' + fecha(d.periodo.hasta);
  const actividad = sumaActividad(d.totales);
  if (d.totales.enlaces === 0 && actividad === 0 && d.cobertura.clics_vitalicios_aproximados === 0) { $('pr-vacio-total').hidden = false; return; }
  if (actividad === 0) { $('pr-vacio-periodo').hidden = false; return; }
  if (d.cobertura.estado === 'parcial') {
    const textos = {
      detalle_p3_compactado: 'el detalle diario P3 anterior al corte fue compactado sin fecha',
      analitica_consentida_inactiva: 'la analítica consentida está inactiva',
      sin_eventos_consentidos_periodo: 'no hay eventos consentidos atribuibles en la ventana'
    };
    const razones = d.cobertura.razones.map((x) => textos[x]);
    $('pr-parcial-texto').textContent = (razones.join('; ') || 'alguna fuente no cubre toda la ventana') + '. Las cifras disponibles se muestran sin completar huecos.';
    $('pr-parcial').hidden = false;
  }
  $('pr-contenido').hidden = false;
  pintarKpis(d); pintarPoblaciones(d); pintarGrafica(); pintarTablaSerie(d); pintarDesglose(d); pintarCalidad(d);
}

async function cargar() {
  const id = ++solicitudId;
  if (controlador) controlador.abort();
  const control = new AbortController();
  controlador = control;
  let vencio = false;
  const deadline = window.setTimeout(() => {
    vencio = true;
    control.abort();
  }, 8000);
  mostrarCarga(); pintarPeriodos(); actualizarNavegacion();
  const r = rangoActual();
  try {
    const campanaQ = supabase.from('campana_producto').select('id,nombre,categoria_codigo,slug,publicado,activo,es_placeholder').eq('id', campanaId).maybeSingle().abortSignal(control.signal);
    const p5Q = supabase.rpc('promocionar_p5_resultados', { p_campana_producto_id: campanaId, p_desde: r.desde, p_hasta: r.hasta }).abortSignal(control.signal);
    const [campanaR, p5R] = await Promise.all([campanaQ, p5Q]);
    if (id !== solicitudId) return;
    if (campanaR.error) throw campanaR.error;
    if (!campanaR.data) throw new Error('P5_CAMPANA_NO_ENCONTRADA');
    if (p5R.error) throw p5R.error;
    pintar(validarPayload(p5R.data, campanaR.data, r));
  } catch (error) {
    if (id !== solicitudId) return;
    if (vencio) mostrarError(new Error('P5_DEADLINE_EXCEDIDO'));
    else if (!control.signal.aborted) mostrarError(error);
  } finally {
    window.clearTimeout(deadline);
    if (!control.signal.aborted) control.abort();
    if (id === solicitudId) {
      $('pr-carga').setAttribute('aria-busy', 'false');
      if (controlador === control) controlador = null;
    }
  }
}

document.querySelectorAll('[data-periodo]').forEach((b) => b.addEventListener('click', () => { if (PERIODOS.has(b.dataset.periodo) && b.dataset.periodo !== periodo) { periodo = b.dataset.periodo; cargar(); } }));
document.querySelectorAll('[data-serie]').forEach((b) => b.addEventListener('click', () => { serieActiva = b.dataset.serie; document.querySelectorAll('[data-serie]').forEach((x) => x.setAttribute('aria-pressed', String(x === b))); if (datos) pintarGrafica(); }));
$('pr-reintentar').addEventListener('click', cargar);
window.addEventListener('resize', () => { if (datos && !$('pr-contenido').hidden) pintarGrafica(); }, { passive: true });

(async () => {
  const params = new URLSearchParams(location.search);
  campanaId = params.get('id') || '';
  const p = params.get('periodo'); periodo = PERIODOS.has(p) ? p : '30';
  const acceso = await asegurarAcceso(document.body, '../index.html');
  if (!acceso) return;
  montarHeader({ titulo: 'Resultados de promoción', kicker: 'PROMOCIONAR · LECTURA COMERCIAL', lead: 'Señales aproximadas, actividad consentida y ventas exactas, cada una con su autoridad y denominador.', sesion: acceso.sesion, areaLabel: 'ESTUDIO DE MARCA', volverHref: 'index.html', volverTexto: 'Campañas' });
  document.querySelector('.mk-sello')?.remove();
  const foot = document.createElement('footer'); foot.className = 'mk-sello'; foot.innerHTML = 'Comunicación de marca · <span class="mk-sello-marca">MAGANDHI</span>'; document.body.append(foot);
  $('pr-main').hidden = false;
  if (!UUID_RE.test(campanaId)) { mostrarError(new Error('El enlace no contiene un UUID de campaña válido.')); return; }
  actualizarNavegacion(); pintarPeriodos(); await cargar();
})();
