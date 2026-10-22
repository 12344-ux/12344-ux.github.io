import {
  asegurarAcceso, montarHeader, supabase, escaparHTML,
} from '../marketing-core.js';
import {
  ICONOS_CATEGORIA, cargarCategoriasAdmin, iconoCategoria,
  mensajeErrorCategoria, normalizarCategoria,
} from './categorias-admin.js?v=temporada-1';

const $ = (id) => document.getElementById(id);
const lista = $('ct-lista');
const resumen = $('ct-resumen');
const form = $('ct-form');
let categorias = [];
let editando = null;
let guardando = false;

function fechaLegible(valor) {
  const match = String(valor || '').match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return '—';
  return new Intl.DateTimeFormat('es-CO', {
    day: 'numeric', month: 'short', year: 'numeric', timeZone: 'America/Bogota',
  }).format(new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]), 12)));
}

function etiquetaEstado(categoria) {
  const nombres = {
    permanente: 'Permanente', programada: 'Programada', vigente: 'Vigente',
    finalizada: 'Finalizada', oculta: 'Oculta', inactiva: 'Inactiva',
  };
  return nombres[categoria.estado] || categoria.estado;
}

function mostrarMensaje(texto, tipo = 'err') {
  const mensaje = $('ct-msg');
  mensaje.textContent = texto;
  mensaje.className = `cm-form-msg ${tipo}`;
  mensaje.hidden = false;
}

function ocultarMensaje() {
  $('ct-msg').hidden = true;
  $('ct-msg').textContent = '';
}

function cambiarGuardando(valor) {
  guardando = valor;
  [...form.elements].forEach((control) => { control.disabled = valor; });
  if (!valor && editando?.es_oficial) $('ct-tipo').disabled = true;
  $('ct-guardar').textContent = valor
    ? 'Guardando…'
    : (editando ? 'Guardar cambios' : 'Crear categoría');
  form.toggleAttribute('aria-busy', valor);
}

function actualizarCamposTemporada() {
  const esTemporada = $('ct-tipo').value === 'temporada';
  $('ct-temporada').hidden = !esTemporada;
  $('ct-desde').required = esTemporada;
  $('ct-hasta').required = esTemporada;
  if (!esTemporada) {
    $('ct-desde').value = '';
    $('ct-hasta').value = '';
    $('ct-fijada').checked = false;
  }
}

function siguienteOrden() {
  return categorias.reduce((maximo, categoria) => Math.max(maximo, categoria.orden), 0) + 10;
}

function limpiarEditor() {
  editando = null;
  form.reset();
  $('ct-codigo').value = '';
  $('ct-orden').value = String(siguienteOrden() || 10);
  $('ct-activa').checked = true;
  $('ct-visible').checked = true;
  $('ct-tipo').disabled = false;
  $('ct-editor-title').textContent = 'Crear categoría';
  $('ct-editor-copy').textContent = 'Crea una categoría permanente o programa una temporada reutilizable.';
  $('ct-codigo-ayuda').textContent = 'El código estable se deriva en el servidor.';
  $('ct-guardar').textContent = 'Crear categoría';
  $('ct-cancelar').hidden = true;
  $('ct-contador').textContent = '0';
  ocultarMensaje();
  actualizarCamposTemporada();
}

function editarCategoria(codigo) {
  const categoria = categorias.find((item) => item.codigo === codigo);
  if (!categoria) return;
  editando = categoria;
  $('ct-codigo').value = categoria.codigo;
  $('ct-nombre').value = categoria.nombre;
  $('ct-descripcion').value = categoria.descripcion;
  $('ct-icono').value = categoria.icono_codigo;
  $('ct-orden').value = String(categoria.orden);
  $('ct-tipo').value = categoria.tipo;
  $('ct-tipo').disabled = categoria.es_oficial;
  $('ct-desde').value = categoria.visible_desde || '';
  $('ct-hasta').value = categoria.visible_hasta || '';
  $('ct-fijada').checked = categoria.fijada_primera;
  $('ct-activa').checked = categoria.activo;
  $('ct-visible').checked = categoria.visible_tienda;
  $('ct-razon').value = '';
  $('ct-contador').textContent = String(categoria.descripcion.length);
  $('ct-editor-title').textContent = `Editar ${categoria.nombre}`;
  $('ct-editor-copy').textContent = categoria.es_oficial
    ? 'La categoría oficial permanece permanente; puedes ajustar presentación, orden y controles.'
    : 'El código es estable. Cambiar tipo, fechas o visibilidad queda auditado.';
  $('ct-codigo-ayuda').textContent = `Código inmutable: ${categoria.codigo}`;
  $('ct-guardar').textContent = 'Guardar cambios';
  $('ct-cancelar').hidden = false;
  ocultarMensaje();
  actualizarCamposTemporada();
  $('ct-editor').scrollIntoView({ behavior: 'smooth', block: 'start' });
  requestAnimationFrame(() => $('ct-nombre').focus());
}

function tarjetaCategoria(categoria) {
  const temporada = categoria.tipo === 'temporada';
  const ventana = temporada
    ? `<span>${escaparHTML(fechaLegible(categoria.visible_desde))} – ${escaparHTML(fechaLegible(categoria.visible_hasta))}</span>`
    : '<span>Sin ventana: permanece disponible mientras esté habilitada.</span>';
  const uso = `${categoria.principales} principal${categoria.principales === 1 ? '' : 'es'} · ${categoria.secundarias} secundaria${categoria.secundarias === 1 ? '' : 's'}`;
  return `<article class="ct-card estado-${escaparHTML(categoria.estado)}" data-codigo="${escaparHTML(categoria.codigo)}">
    <div class="ct-card-cab">
      <span class="ct-card-icono" aria-hidden="true">${iconoCategoria(categoria.icono_codigo)}</span>
      <div class="ct-card-titulos">
        <strong>${escaparHTML(categoria.nombre)}</strong>
        <code>${escaparHTML(categoria.codigo)}</code>
      </div>
      <span class="ct-estado estado-${escaparHTML(categoria.estado)}">${escaparHTML(etiquetaEstado(categoria))}</span>
    </div>
    <p>${escaparHTML(categoria.descripcion)}</p>
    <div class="ct-card-meta">
      <span>${temporada ? 'Temporada · solo secundaria' : 'Categoría permanente'}</span>
      ${ventana}
      <span>Orden ${escaparHTML(String(categoria.orden))}${categoria.fijada_primera ? ' · fijada primera' : ''}</span>
      <span>${escaparHTML(uso)}</span>
    </div>
    <button class="cm-accion editar" type="button" data-editar="${escaparHTML(categoria.codigo)}">Editar</button>
  </article>`;
}

function pintar() {
  if (!categorias.length) {
    resumen.textContent = '0 categorías';
    lista.innerHTML = '<div class="cm-empty">Aún no hay categorías gestionables.</div>';
    return;
  }
  const vigentes = categorias.filter((c) => c.estado === 'vigente').length;
  const programadas = categorias.filter((c) => c.estado === 'programada').length;
  resumen.textContent = `${categorias.length} categorías · ${vigentes} temporadas vigentes · ${programadas} programadas`;
  lista.innerHTML = categorias.map(tarjetaCategoria).join('');
  lista.querySelectorAll('[data-editar]').forEach((boton) => {
    boton.addEventListener('click', () => editarCategoria(boton.dataset.editar));
  });
}

async function cargar() {
  lista.innerHTML = '<div class="cm-empty">Cargando categorías…</div>';
  const { data, error } = await cargarCategoriasAdmin();
  if (error) {
    lista.innerHTML = `<div class="cm-empty err"><strong>No pudimos cargar las categorías</strong>${escaparHTML(mensajeErrorCategoria(error))}</div>`;
    return false;
  }
  categorias = (data || []).map(normalizarCategoria).filter(Boolean);
  pintar();
  if (!editando) $('ct-orden').value = String(siguienteOrden() || 10);
  return true;
}

form.addEventListener('submit', async (evento) => {
  evento.preventDefault();
  if (guardando) return;
  ocultarMensaje();

  const nombre = $('ct-nombre').value.trim();
  const descripcion = $('ct-descripcion').value.trim();
  const icono = $('ct-icono').value;
  const tipo = $('ct-tipo').value;
  const desde = $('ct-desde').value || null;
  const hasta = $('ct-hasta').value || null;
  const orden = Math.trunc(Number($('ct-orden').value));
  const razon = $('ct-razon').value.trim();

  if (nombre.length < 2 || nombre.length > 80) return mostrarMensaje('El nombre debe tener entre 2 y 80 caracteres.');
  if (!descripcion || descripcion.length > 240) return mostrarMensaje('Escribe una descripción de hasta 240 caracteres.');
  if (!ICONOS_CATEGORIA.some((item) => item.codigo === icono)) return mostrarMensaje('Elige un ícono válido.');
  if (!Number.isInteger(orden) || orden < -1000 || orden > 1000000) return mostrarMensaje('El orden debe ser un entero entre -1000 y 1000000.');
  if (tipo === 'temporada' && (!desde || !hasta || hasta < desde)) return mostrarMensaje('Elige un inicio y final válidos para la temporada.');
  if (razon.length < 3 || razon.length > 240) return mostrarMensaje('Escribe una razón de 3 a 240 caracteres.');

  cambiarGuardando(true);
  let data;
  let error;
  try {
    ({ data, error } = await supabase.rpc('cm_guardar_categoria_v1', {
      p_codigo: editando?.codigo || null,
      p_nombre: nombre,
      p_descripcion: descripcion,
      p_icono_codigo: icono,
      p_orden: orden,
      p_tipo: tipo,
      p_visible_desde: tipo === 'temporada' ? desde : null,
      p_visible_hasta: tipo === 'temporada' ? hasta : null,
      p_fijada_primera: tipo === 'temporada' && $('ct-fijada').checked,
      p_activo: $('ct-activa').checked,
      p_visible_tienda: $('ct-visible').checked,
      p_razon: razon,
    }));
  } catch (fallo) {
    error = fallo;
  }
  cambiarGuardando(false);

  if (error) return mostrarMensaje(mensajeErrorCategoria(error));
  const guardada = normalizarCategoria(data);
  const recargada = await cargar();
  limpiarEditor();
  mostrarMensaje(
    recargada
      ? `Categoría «${guardada?.nombre || nombre}» guardada correctamente.`
      : `Categoría «${guardada?.nombre || nombre}» guardada, pero no pudimos recargar la lista. Recarga la página.`,
    recargada ? 'ok' : 'err'
  );
});

$('ct-tipo').addEventListener('change', actualizarCamposTemporada);
$('ct-descripcion').addEventListener('input', () => {
  $('ct-contador').textContent = String($('ct-descripcion').value.length);
});
$('ct-cancelar').addEventListener('click', limpiarEditor);

(async () => {
  ICONOS_CATEGORIA.forEach((item) => {
    const opcion = document.createElement('option');
    opcion.value = item.codigo;
    opcion.textContent = item.nombre;
    $('ct-icono').appendChild(opcion);
  });

  const acceso = await asegurarAcceso(document.body, '../index.html');
  if (!acceso) return;
  montarHeader({
    titulo: 'Categorías',
    kicker: 'CAMPAÑAS · CLASIFICACIÓN PÚBLICA',
    lead: 'Mantén estable la navegación y programa temporadas que aparecen y terminan sin retirar productos.',
    sesion: acceso.sesion,
    areaLabel: 'ÁREA DE MARKETING',
    volverHref: 'index.html',
    volverTexto: 'Campañas',
  });
  $('ct-main').hidden = false;
  limpiarEditor();
  await cargar();
})();
