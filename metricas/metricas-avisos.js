// MAGANDHI · Metricas · aviso + interruptor de la analitica de la tienda (EM7).
// Solo un admin la enciende o apaga, y solo con la politica registrada (el
// servidor lo exige en mt_config_analitica).
import { supabase, ICONOS, esc, mensajeError } from './metricas-core.js';

export function avisoAnalitica(activa, esAdmin) {
  if (activa) return '';
  setTimeout(cablear, 0);
  return '<div class="mt-aviso" id="an-aviso">' + ICONOS.escudo + '<div><strong>La analítica de la tienda está apagada</strong>' +
    '<p>Sin ella no se miden visitas, productos vistos ni el embudo de compra. Las ventas sí se ven. Al encenderla, la tienda muestra el aviso de cookies y solo mide a quien acepta.</p>' +
    '<p class="mt-msg" id="an-msg" hidden></p></div>' +
    (esAdmin ? '<div class="acc"><button type="button" class="mt-btn" id="an-encender">Encender analítica</button></div>' : '') + '</div>';
}

export function interruptorAnalitica(activa, esAdmin) {
  if (!esAdmin) return '<span class="mt-rango">Analítica ' + (activa ? 'encendida' : 'apagada') + '</span>';
  setTimeout(cablear, 0);
  return '<label class="mt-interruptor" title="Mostrar el aviso de cookies y medir a quien acepte"><input type="checkbox" id="an-interruptor"' + (activa ? ' checked' : '') + '>Analítica de la tienda</label>';
}

function cablear() {
  const b = document.getElementById('an-encender');
  if (b && !b.dataset.ok) { b.dataset.ok = '1'; b.addEventListener('click', () => cambiar(true, b)); }
  const s = document.getElementById('an-interruptor');
  if (s && !s.dataset.ok) { s.dataset.ok = '1'; s.addEventListener('change', () => cambiar(s.checked, s)); }
}

async function cambiar(activar, el) {
  if (!window.confirm(activar
    ? 'La tienda empezará a mostrar el aviso de cookies y medirá solo a quien acepte. ¿Encender?'
    : 'La tienda dejará de medir visitas y ocultará el aviso. ¿Apagar?')) { if (el.type === 'checkbox') el.checked = !activar; return; }
  el.disabled = true;
  const { error } = await supabase.rpc('mt_config_analitica', { p_activa: activar });
  el.disabled = false;
  if (error) {
    if (el.type === 'checkbox') el.checked = !activar;
    const m = document.getElementById('an-msg');
    if (m) { m.hidden = false; m.className = 'mt-msg err'; m.textContent = mensajeError(error); } else window.alert(mensajeError(error));
    return;
  }
  document.dispatchEvent(new CustomEvent('mt:analitica', { detail: { activa: activar } }));
}

export { esc };
