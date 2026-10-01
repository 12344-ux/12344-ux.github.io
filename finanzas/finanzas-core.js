// ============================================================
//  MAGANDHI · MODULO FINANZAS · Nucleo compartido (finanzas-core.js)
//  ------------------------------------------------------------
//  Utilidades reutilizadas por todas las paginas del area de Finanzas:
//    · Formateo COP con puntos de miles (1.200.000).
//    · Parseo de un monto escrito a ENTERO de pesos (bigint-safe).
//    · Verificacion de acceso al modulo (admin o modulos incluye 'finanzas').
//    · Montaje del header institucional (azul marino + AREA DE FINANZAS).
//
//  DECISION DE MONTOS (no negociable): en JS los montos se manejan como
//  ENTEROS de pesos COP (Number entero, sin centavos). El cuadre de la
//  partida doble se calcula SUMANDO/COMPARANDO enteros; NUNCA se usa
//  aritmetica de punto flotante para decidir si un asiento cuadra. El
//  formato con puntos de miles es solo de PRESENTACION.
//
//  Este modulo vive en finanzas/, asi que sube un nivel para importar el
//  cliente unico y el guardia compartidos (../supabase-config.js /
//  ../auth-guard.js). No crea otro cliente Supabase.
//
//  Recordatorio de seguridad: ocultar UI es solo comodidad de UX. El
//  candado real es RLS server-side (tiene_modulo('finanzas')).
// ============================================================

import { supabase } from '../supabase-config.js';
import { exigirSesion, obtenerPerfil } from '../auth-guard.js';

// Reexportamos para que las paginas importen todo desde un solo lugar.
export { supabase, exigirSesion, obtenerPerfil };

// ------------------------------------------------------------
// FORMATO / PARSEO DE MONTOS (enteros de pesos COP)
// ------------------------------------------------------------

/**
 * Formatea un ENTERO de pesos a COP con puntos de miles: 1200000 -> "1.200.000".
 * No agrega el simbolo $ (la UI decide si lo antepone). Sin decimales.
 * @param {number} entero pesos enteros
 * @returns {string}
 */
export function formatearCOP(entero) {
  const n = Math.trunc(Number(entero) || 0);
  const signo = n < 0 ? '-' : '';
  const abs = Math.abs(n).toString();
  // Inserta un punto cada 3 digitos desde la derecha.
  return signo + abs.replace(/\B(?=(\d{3})+(?!\d))/g, '.');
}

/**
 * Analiza lo que el usuario escribe en un campo de monto SIN tragarse los
 * centavos en silencio. Los montos son ENTEROS de pesos COP (sin centavos);
 * el punto es separador de MILES, la coma seria separador decimal.
 *
 * El bug historico (B1.1): un simple replace(/[^\d]/g,'') convertia "1.200,50"
 * en "120050" (borra la coma y pega los centavos), guardando un valor 100x
 * mayor sin avisar. Aqui, en cambio:
 *   · El punto se trata como separador de miles: "1.200.000" -> 1200000.
 *   · Si aparece una coma, o un punto que NO agrupa de a tres digitos (p.ej.
 *     "1.200,50" o el punto final de "1200.50"), se interpreta como parte
 *     DECIMAL: se descarta (el sistema no maneja centavos) y se avisa via
 *     `tieneDecimal` para que la UI lo advierta o lo rechace, nunca lo cuele.
 *   · TRAMO 0 (estricto): puntos mal agrupados ("12.34.567", "1234.567") NO se
 *     adivinan: se devuelve `invalido: true` y la UI debe rechazar el valor.
 *   · Campo vacio -> 0.
 * Para campos que se reformatean mientras se escribe, usar leerMontoTecleado.
 *
 * Devuelve el ENTERO de pesos (parte entera, ignorando cualquier decimal) y
 * banderas para que la capa de UX decida. El candado autoritativo del monto
 * sigue viviendo server-side en fz_validar_lineas; esto es solo la capa de UX.
 *
 * @param {string} texto
 * @returns {{ valor:number, tieneDecimal:boolean, invalido:boolean }}
 *   valor: entero de pesos (>= 0) con la parte decimal descartada.
 *   tieneDecimal: true si se detecto una parte decimal (coma o punto decimal).
 *   invalido: true si el texto tiene digitos pero no se pudo parsear a numero.
 */
export function analizarMonto(texto) {
  if (texto == null) return { valor: 0, tieneDecimal: false, invalido: false };
  // Quita todo lo que no sea digito, punto o coma (espacios, $, letras, signos).
  let limpio = String(texto).replace(/[^\d.,]/g, '');
  if (limpio === '') return { valor: 0, tieneDecimal: false, invalido: false };

  let tieneDecimal = false;

  // Una coma siempre marca la parte decimal (centavos): la separamos.
  const coma = limpio.indexOf(',');
  if (coma !== -1) {
    const decimales = limpio.slice(coma + 1).replace(/[.,]/g, '');
    if (decimales !== '') tieneDecimal = true;
    limpio = limpio.slice(0, coma);
  }

  // Ya sin coma: quedan solo digitos y puntos.
  if (limpio.indexOf('.') !== -1) {
    const grupos = limpio.split('.');
    // Un ultimo grupo de 1 o 2 digitos tras un punto ("1200.50", "12.5") es
    // una parte DECIMAL escrita al estilo anglosajon: se descarta y se avisa.
    const ultimo = grupos[grupos.length - 1];
    if (grupos.length > 1 && ultimo.length >= 1 && ultimo.length <= 2) {
      grupos.pop();
      tieneDecimal = true;
    }
    // TRAMO 0 · ESTRICTO: si aun quedan puntos, deben ser separadores de miles
    // BIEN FORMADOS: primer grupo de 1 a 3 digitos y todos los demas de
    // EXACTAMENTE 3. Cualquier otra forma ("12.34.567", "1234.567", "1.2345")
    // es ambigua: NO se adivina, se marca invalido para que la UI lo rechace.
    if (grupos.length > 1) {
      const [primero, ...resto] = grupos;
      const bienFormado = /^\d{1,3}$/.test(primero) && resto.every((g) => /^\d{3}$/.test(g));
      if (!bienFormado) return { valor: 0, tieneDecimal, invalido: true };
    }
    limpio = grupos.join('');
  }

  if (limpio === '') return { valor: 0, tieneDecimal, invalido: false };
  const n = parseInt(limpio, 10);
  if (!Number.isFinite(n)) return { valor: 0, tieneDecimal, invalido: true };
  return { valor: n, tieneDecimal, invalido: false };
}

/**
 * TRAMO 0 · Lectura de un campo de monto que se REFORMATEA MIENTRAS SE ESCRIBE
 * (Nuevo asiento / Editar asiento ponen los puntos de miles en cada tecla).
 *
 * El problema que corrige (verificado): en esos campos los puntos los pone el
 * PROPIO sistema. analizarMonto (pensado para un texto completo) los leia como
 * decimales al teclear o borrar:
 *   · escribir 1234567 digito a digito daba 167 ("1.234" + "5" = "1.2345");
 *   · borrar el ultimo digito de "24.900" dejaba 24 ("24.90" = decimal).
 * Era imposible capturar montos de 5 cifras o mas tecleando.
 *
 * Regla: si el cambio vino de TECLEAR o BORRAR, los puntos son nuestros y se
 * ignoran; solo la coma marca decimales (se descartan y se avisa). Un punto
 * tecleado a mano tambien se ignora y se avisa (no hay centavos). Si el cambio
 * vino de PEGAR o ARRASTRAR un texto, se analiza con la regla estricta de
 * analizarMonto (puede venir con decimales o con puntos mal puestos).
 *
 * @param {string} texto  valor actual del campo
 * @param {string} [tipoEntrada]  InputEvent.inputType (ej. 'insertText',
 *   'deleteContentBackward', 'insertFromPaste'). Si falta, se usa la regla estricta.
 * @param {string} [datoTecleado]  InputEvent.data (lo que se tecleo)
 * @returns {{ valor:number, tieneDecimal:boolean, invalido:boolean, puntoTecleado:boolean }}
 */
export function leerMontoTecleado(texto, tipoEntrada, datoTecleado) {
  const tecleado = typeof tipoEntrada === 'string'
    && (tipoEntrada.startsWith('insert') || tipoEntrada.startsWith('delete'))
    && !/^insertFrom(Paste|Drop|PasteAsQuotation)$/.test(tipoEntrada)
    && tipoEntrada !== 'insertReplacementText';
  if (!tecleado) return { ...analizarMonto(texto), puntoTecleado: false };

  const puntoTecleado = typeof datoTecleado === 'string' && datoTecleado.indexOf('.') !== -1;
  let limpio = String(texto == null ? '' : texto).replace(/[^\d,]/g, '');
  let tieneDecimal = false;
  const coma = limpio.indexOf(',');
  if (coma !== -1) {
    if (limpio.slice(coma + 1).replace(/,/g, '') !== '') tieneDecimal = true;
    limpio = limpio.slice(0, coma);
  }
  if (limpio === '') return { valor: 0, tieneDecimal, invalido: false, puntoTecleado };
  const n = parseInt(limpio, 10);
  if (!Number.isFinite(n)) return { valor: 0, tieneDecimal, invalido: true, puntoTecleado };
  return { valor: n, tieneDecimal, invalido: false, puntoTecleado };
}

/**
 * Convierte lo que el usuario escribe en un campo de monto a un ENTERO de
 * pesos (los montos son enteros de pesos, sin centavos). El punto es separador
 * de miles ("1.200.000" -> 1200000); cualquier parte decimal se DESCARTA (no
 * se pega a los pesos como hacia el bug historico). Un campo vacio -> 0.
 *
 * Devuelve solo el entero (firma retrocompatible). Para AVISARLE al usuario que
 * escribio un decimal, usa `analizarMonto`, que expone la bandera `tieneDecimal`.
 * @param {string} texto
 * @returns {number} entero de pesos (>= 0)
 */
export function parsearMonto(texto) {
  return analizarMonto(texto).valor;
}

/**
 * TOPE DE MONTO POR LINEA (no negociable, ver 20250201000600_finanzas_funciones.sql).
 *
 * El cuadre en JS suma con Number entero. Number es exacto solo por debajo de
 * 2^53 (Number.MAX_SAFE_INTEGER = 9.007.199.254.740.991). Por encima de ese
 * techo dos importes distintos pueden parecer iguales y colar un asiento que
 * en realidad no cuadra. Para que el candado real cubra el rango, fijamos un
 * tope por linea de 1.000.000.000.000 (un billon de pesos COP), muy por encima
 * de cualquier operacion real de un comercio como MAGANDHI y con margen de
 * sobra bajo 2^53 (incluso sumando cientos de lineas al tope, el total sigue
 * siendo exacto). El MISMO tope se impone server-side en fz_validar_lineas, que
 * es el candado autoritativo; esta constante es solo la validacion espejo de UX.
 */
export const TOPE_MONTO_LINEA = 1000000000000;

/**
 * Escapa texto para insertarlo de forma segura via innerHTML. Evita XSS
 * almacenado cuando se pinta contenido que escribio el operador (descripcion,
 * nombre de cuenta, detalle, etc.). Compartido por diario/mayor/editar-asiento
 * para no duplicar la funcion en cada pagina.
 * @param {*} s
 * @returns {string}
 */
export function escaparHTML(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/**
 * TRAMO 0 · Pinta la lista de sugerencias de cuentas PUC con NODOS DOM y
 * textContent (nunca innerHTML con datos de la base). Antes Nuevo asiento y
 * Editar asiento concatenaban el nombre de la cuenta dentro de innerHTML: un
 * nombre con marcado (<img onerror=...>) se ejecutaba en la sesion de quien
 * abria el buscador (XSS almacenado). Compartido por ambas pantallas.
 * @param {HTMLElement} sug  contenedor de la lista
 * @param {Array<{codigo:string, nombre?:string}>} cuentas
 * @param {(cuenta:object) => void} alElegir  se llama al elegir una cuenta
 */
export function pintarSugerenciasCuentas(sug, cuentas, alElegir) {
  sug.replaceChildren();
  if (!cuentas || !cuentas.length) {
    const vacio = document.createElement('div');
    vacio.className = 'fz-sug-item';
    const txt = document.createElement('span');
    txt.className = 'fz-sug-nombre';
    txt.textContent = 'Sin resultados';
    vacio.append(txt);
    sug.append(vacio);
    sug.classList.add('open');
    return;
  }
  for (const c of cuentas) {
    const item = document.createElement('div');
    item.className = 'fz-sug-item';
    item.dataset.codigo = String(c.codigo == null ? '' : c.codigo);
    const badge = document.createElement('span');
    badge.className = 'fz-badge';
    badge.textContent = String(c.codigo == null ? '' : c.codigo);
    const nombre = document.createElement('span');
    nombre.className = 'fz-sug-nombre';
    nombre.textContent = String(c.nombre == null ? '' : c.nombre);
    item.append(badge, nombre);
    item.addEventListener('mousedown', (e) => {
      e.preventDefault();
      alElegir(c);
      sug.classList.remove('open');
    });
    sug.append(item);
  }
  sug.classList.add('open');
}

/**
 * TRAMO 0 · Aplica la lectura de un campo de monto (de leerMontoTecleado):
 *   · Si es ILEGIBLE: conserva el texto tal cual, lo marca aria-invalid (se ve
 *     en rojo) y explica por que. Nunca lo convierte en otro numero.
 *   · Si es legible: lo reescribe formateado y avisa si se descarto un decimal
 *     o si se tecleo un punto a mano.
 * El aviso de "ilegible" lo limpia recalcular() cuando ya no queda ninguno
 * (ver hayMontoInvalido). Devuelve el entero de pesos (0 si es ilegible).
 * @param {HTMLInputElement} el
 * @param {{valor:number, tieneDecimal:boolean, invalido:boolean, puntoTecleado?:boolean}} lectura
 * @param {HTMLElement} msgEl
 * @returns {number}
 */
export function aplicarLecturaMonto(el, lectura, msgEl) {
  if (lectura.invalido) {
    el.setAttribute('aria-invalid', 'true');
    msgEl.className = 'fz-msg err';
    msgEl.textContent = 'No pudimos leer "' + el.value + '" como monto: los puntos no estan cada tres cifras. ' +
      'Escribe solo las cifras (los puntos de miles los pone el sistema).';
    msgEl.dataset.aviso = 'invalido';
    return 0;
  }
  el.removeAttribute('aria-invalid');
  el.value = lectura.valor > 0 ? formatearCOP(lectura.valor) : '';
  if (lectura.tieneDecimal) {
    msgEl.className = 'fz-msg err';
    msgEl.textContent = 'Los montos son pesos enteros, sin centavos. Se detecto un decimal y se ignoro: revisa el valor (quedo en ' + formatearCOP(lectura.valor) + ').';
    msgEl.dataset.aviso = 'decimal';
  } else if (lectura.puntoTecleado) {
    msgEl.className = 'fz-msg err';
    msgEl.textContent = 'No hace falta escribir puntos: el sistema los pone solo. Los montos son pesos enteros, sin centavos.';
    msgEl.dataset.aviso = 'punto';
  } else if (msgEl.dataset.aviso === 'decimal' || msgEl.dataset.aviso === 'punto') {
    msgEl.textContent = ''; msgEl.className = 'fz-msg'; msgEl.dataset.aviso = '';
  }
  return lectura.valor;
}

/**
 * TRAMO 0 · true si algun campo de monto del contenedor quedo ILEGIBLE.
 * @param {HTMLElement} contenedor
 * @returns {boolean}
 */
export function hayMontoInvalido(contenedor) {
  return !!contenedor.querySelector('.fz-debe[aria-invalid="true"], .fz-haber[aria-invalid="true"]');
}

// ------------------------------------------------------------
// ACCESO AL MODULO
// ------------------------------------------------------------

/**
 * True si el perfil puede usar el modulo finanzas: admin ve todo; otros
 * solo si 'finanzas' esta en su lista de modulos. El candado real es RLS;
 * esto es comodidad de UX.
 * @param {{rol?:string, modulos?:string[]}|null} perfil
 * @returns {boolean}
 */
export function tieneAccesoFinanzas(perfil) {
  if (!perfil) return false;
  if (perfil.rol === 'admin') return true;
  const modulos = Array.isArray(perfil.modulos) ? perfil.modulos : [];
  return modulos.includes('finanzas');
}

/**
 * Asegura sesion + acceso al modulo. Si no hay sesion, exigirSesion ya
 * redirige al login. Si hay sesion pero no acceso, pinta el aviso de
 * acceso denegado dentro de `contenedor` (si se pasa) y devuelve null.
 * Devuelve { sesion, perfil } cuando el acceso es correcto.
 * @param {HTMLElement} [contenedor] donde mostrar el aviso de denegado
 * @returns {Promise<{sesion:object, perfil:object}|null>}
 */
export async function asegurarAcceso(contenedor) {
  const sesion = await exigirSesion();
  if (!sesion) return null; // auth-guard ya redirige al login

  let perfil = null;
  try {
    perfil = await obtenerPerfil();
  } catch (_) {
    perfil = null;
  }

  if (!tieneAccesoFinanzas(perfil)) {
    if (contenedor) {
      contenedor.innerHTML =
        '<div class="fz-denegado">' +
          '<h2>Acceso restringido</h2>' +
          '<p>Tu cuenta no tiene habilitado el <strong>Área de Finanzas</strong>. ' +
          'Solicita el acceso a un administrador.</p>' +
          '<p style="margin-top:14px"><a href="../panel.html">Volver al panel</a></p>' +
        '</div>';
    }
    return null;
  }

  return { sesion, perfil };
}

// ------------------------------------------------------------
// ICONOS (SVG inline consistentes: lupa, +, x, check, etc.)
// ------------------------------------------------------------
export const ICONOS = {
  lupa: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg>',
  mas: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v14M5 12h14"/></svg>',
  equis: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18M6 6l12 12"/></svg>',
  check: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg>',
  libro: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2Z"/></svg>',
  lista: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01"/></svg>',
  balanza: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v18M7 7h10M7 21h10"/><path d="M7 7 4 14a3 3 0 0 0 6 0L7 7ZM17 7l-3 7a3 3 0 0 0 6 0l-3-7Z"/></svg>',
  nuevo: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6M12 12v6M9 15h6"/></svg>',
  info: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/></svg>',
  // Icono de informe/documento con lineas: distingue el Balance de comprobacion
  // (a fecha de corte) del Libro Mayor, que ya usa 'balanza'.
  informe: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><path d="M14 2v6h6"/><path d="M8 13h8M8 17h8M8 9h2"/></svg>'
};

// ------------------------------------------------------------
// HEADER INSTITUCIONAL
// ------------------------------------------------------------

// Iconos extra para navegacion / perfil (flecha de retroceso, salir).
ICONOS.flecha = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m15 18-6-6 6-6"/></svg>';
ICONOS.salir = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5M21 12H9"/></svg>';

// Icono de tendencia (linea ascendente): marca el Estado de resultados
// (informe POR PERIODO, ingresos menos costos y gastos = utilidad/perdida).
// Se distingue de 'informe' (balance de comprobacion) y 'balanza' (mayor).
ICONOS.tendencia = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 3v18h18"/><path d="m7 15 4-4 3 3 5-6"/><path d="M19 8h-3M19 8v3"/></svg>';

// Icono de columnas/edificio (fachada clasica con frontispicio): marca el
// Balance general (FOTO a fecha de corte, Activo = Pasivo + Patrimonio +
// Resultado del ejercicio). Se distingue de 'balanza' (mayor), 'informe'
// (balance de comprobacion) y 'tendencia' (estado de resultados).
ICONOS.edificio = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 21h18"/><path d="M4 9h16"/><path d="m12 3 8 4H4l8-4Z"/><path d="M6 9v10M10 9v10M14 9v10M18 9v10"/></svg>';

/**
 * Monta el header institucional fijo (azul marino) al inicio de <body>,
 * seguido del encabezado editorial de la pantalla (titulo + kicker).
 *
 * Incluye:
 *  · Navegacion de retroceso (izquierda, junto a la marca) con destino
 *    EXPLICITO (nunca history.back()): volverHref/volverTexto. Por defecto
 *    vuelve al home del area (index.html); cada pagina puede sobreescribir.
 *  · Avatar circular clickeable a la derecha que abre un menu de perfil
 *    con el correo del usuario y un boton "Cerrar sesion" (mismo signOut
 *    que usa panel.html). Sin subida de foto (fuera de alcance).
 *
 * @param {object} opts
 * @param {string} opts.titulo   Titulo editorial de la pantalla.
 * @param {string} opts.kicker   Kicker en terracota (mayusculas).
 * @param {string} [opts.lead]   Parrafo introductorio opcional.
 * @param {object} [opts.sesion] Sesion (para la inicial del avatar y el correo).
 * @param {string} [opts.buscarHref] href del icono de buscar (default puc.html).
 * @param {string} [opts.volverHref] destino explicito del boton volver (default index.html).
 * @param {string} [opts.volverTexto] etiqueta del boton volver (default 'Finanzas').
 */
export function montarHeader(opts) {
  const { titulo, kicker, lead, sesion, buscarHref, volverHref, volverTexto } = opts || {};
  const email = sesion?.user?.email || '';
  const inicial = (email.trim()[0] || 'F').toUpperCase();
  const hrefBuscar = buscarHref || 'puc.html';
  const hrefVolver = volverHref || 'index.html';
  const txtVolver = volverTexto || 'Finanzas';

  const header = document.createElement('header');
  header.className = 'fz-header';
  header.innerHTML =
    '<div class="fz-header-left">' +
      '<a class="fz-volver" href="' + hrefVolver + '" aria-label="Volver a ' + escaparHTML(txtVolver) + '">' +
        ICONOS.flecha +
        '<span>' + escaparHTML(txtVolver) + '</span>' +
      '</a>' +
      '<span class="fz-sep" aria-hidden="true"></span>' +
      '<img class="fz-logo" src="../logo-mark-terracota.png" alt="Magandhi">' +
      '<span class="fz-word">MAGANDHI</span>' +
      '<span class="fz-sep" aria-hidden="true"></span>' +
      '<span class="fz-area">ÁREA DE FINANZAS</span>' +
    '</div>' +
    '<div class="fz-header-right">' +
      '<a class="fz-icon-btn" href="' + hrefBuscar + '" title="Buscar en el catalogo PUC" aria-label="Buscar">' +
        ICONOS.lupa +
      '</a>' +
      '<div class="fz-perfil">' +
        '<button class="fz-avatar" id="fz-avatar" type="button" ' +
          'aria-haspopup="menu" aria-expanded="false" aria-controls="fz-perfil-menu" ' +
          'title="' + escaparHTML(email) + '" aria-label="Menu de perfil">' + escaparHTML(inicial) + '</button>' +
        '<div class="fz-perfil-menu" id="fz-perfil-menu" role="menu" aria-label="Perfil" hidden>' +
          '<div class="fz-perfil-info">' +
            '<span class="fz-perfil-lbl">Sesion iniciada como</span>' +
            '<span class="fz-perfil-email">' + escaparHTML(email || 'usuario interno') + '</span>' +
          '</div>' +
          '<button class="fz-perfil-salir" id="fz-perfil-salir" type="button" role="menuitem">' +
            ICONOS.salir + '<span>Cerrar sesion</span>' +
          '</button>' +
        '</div>' +
      '</div>' +
    '</div>';

  const screenHead = document.createElement('div');
  screenHead.className = 'fz-screen-head';
  screenHead.innerHTML =
    '<p class="fz-kicker">' + (kicker || '') + '</p>' +
    '<h1 class="fz-title">' + (titulo || '') + '</h1>' +
    (lead ? '<p class="fz-lead">' + lead + '</p>' : '');

  document.body.insertBefore(screenHead, document.body.firstChild);
  document.body.insertBefore(header, document.body.firstChild);

  montarMenuPerfil(header);
  montarSelloImpulse();
}

/**
 * Cablea el comportamiento del menu de perfil del avatar: abrir/cerrar,
 * cerrar al hacer clic afuera o con Escape, accesibilidad (aria-expanded,
 * foco) y el boton "Cerrar sesion" (mismo patron que panel.html:
 * supabase.auth.signOut() + redirect al login de la raiz).
 * @param {HTMLElement} header
 */
function montarMenuPerfil(header) {
  const avatar = header.querySelector('#fz-avatar');
  const menu = header.querySelector('#fz-perfil-menu');
  const salir = header.querySelector('#fz-perfil-salir');
  if (!avatar || !menu) return;

  const abrir = () => {
    menu.hidden = false;
    avatar.setAttribute('aria-expanded', 'true');
    salir?.focus();
  };
  const cerrar = (devolverFoco) => {
    menu.hidden = true;
    avatar.setAttribute('aria-expanded', 'false');
    if (devolverFoco) avatar.focus();
  };
  const estaAbierto = () => avatar.getAttribute('aria-expanded') === 'true';

  avatar.addEventListener('click', (e) => {
    e.stopPropagation();
    estaAbierto() ? cerrar(false) : abrir();
  });

  // Clic afuera cierra el menu.
  document.addEventListener('click', (e) => {
    if (estaAbierto() && !menu.contains(e.target) && e.target !== avatar) cerrar(false);
  });

  // Escape cierra y devuelve el foco al avatar.
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && estaAbierto()) cerrar(true);
  });

  salir?.addEventListener('click', async () => {
    try { await supabase.auth.signOut(); } catch (_) { /* ignorar */ }
    // finanzas/ vive un nivel bajo la raiz: el login esta en ../index.html.
    window.location.replace('../index.html');
  });
}

// ------------------------------------------------------------
// SELLO DE PROVEEDOR ("Con tecnologia Impulse")
// ------------------------------------------------------------

/**
 * Inserta el sello discreto de proveedor "Con tecnologia Impulse" al final
 * del <body>. Firma sobria de proveedor: gris tenue, "Impulse" con un peso
 * ligeramente destacado. Idempotente (no duplica si ya existe). Solo para el
 * back-office interno (montaguth.institute); nunca la tienda publica.
 */
export function montarSelloImpulse() {
  if (document.querySelector('.fz-sello')) return;
  const foot = document.createElement('footer');
  foot.className = 'fz-sello';
  foot.innerHTML = 'Con tecnología <span class="fz-sello-marca">Impulse</span>';
  document.body.appendChild(foot);
}

/**
 * Fecha de hoy en formato YYYY-MM-DD (zona local) para inputs date y kickers.
 * @returns {string}
 */
export function hoyISO() {
  const d = new Date();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${d.getFullYear()}-${mm}-${dd}`;
}

/**
 * Formatea una fecha ISO (YYYY-MM-DD) a un texto legible en espanol corto,
 * evitando desfases de zona (se interpreta como fecha local, no UTC).
 * @param {string} iso
 * @returns {string}
 */
export function formatearFecha(iso) {
  if (!iso) return '';
  const [y, m, d] = String(iso).slice(0, 10).split('-').map(Number);
  if (!y || !m || !d) return String(iso);
  const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  return `${String(d).padStart(2, '0')} ${meses[m - 1]} ${y}`;
}

/**
 * Formatea un timestamptz (ISO con hora, p.ej. de asiento_bitacora.cuando) a
 * un texto legible en espanol corto con hora local: "05 feb 2025, 14:03".
 * @param {string} iso
 * @returns {string}
 */
export function formatearMomento(iso) {
  if (!iso) return '';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return String(iso);
  const meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
  const hh = String(d.getHours()).padStart(2, '0');
  const mm = String(d.getMinutes()).padStart(2, '0');
  return `${String(d.getDate()).padStart(2, '0')} ${meses[d.getMonth()]} ${d.getFullYear()}, ${hh}:${mm}`;
}

// ------------------------------------------------------------
// TRAZABILIDAD (bitacora de correcciones · modelo punto medio)
// ------------------------------------------------------------

/**
 * Metadatos de presentacion para cada accion de la bitacora
 * (crear | editar | anular): etiqueta legible y clase de color.
 * La UI nunca expone borrado fisico; solo estas tres acciones existen.
 */
export const ACCIONES_BITACORA = {
  crear:  { etiqueta: 'Creado',  clase: 'crear' },
  editar: { etiqueta: 'Editado', clase: 'editar' },
  anular: { etiqueta: 'Anulado', clase: 'anular' }
};

/**
 * Lee el historial de correcciones de un asiento desde asiento_bitacora,
 * ordenado cronologicamente (mas reciente primero). Solo lectura; nada se
 * borra en silencio (el trigger server-side alimenta esta tabla).
 * @param {string} asientoId uuid del asiento
 * @returns {Promise<Array<{accion:string, cuando:string, actor:string, detalle_cambio:object}>>}
 */
export async function cargarBitacora(asientoId) {
  const { data, error } = await supabase
    .from('asiento_bitacora')
    .select('accion, cuando, actor, detalle_cambio')
    .eq('asiento_id', asientoId)
    .order('cuando', { ascending: false });
  if (error) throw error;
  return data || [];
}

// ------------------------------------------------------------
// DESCARGA DE ARCHIVOS (helper compartido para exportaciones)
// ------------------------------------------------------------

/**
 * Dispara la descarga de un Blob con un nombre de archivo dado, usando el
 * patron estandar de navegador: URL.createObjectURL + un <a download>
 * sintetico + revoke del objeto URL. Compartido por las exportaciones
 * (CSV/PDF) del area para no duplicar la fontaneria de descarga.
 * @param {string} nombre nombre de archivo sugerido (p.ej. 'balance.csv')
 * @param {Blob} blob contenido a descargar
 */
export function descargarArchivo(nombre, blob) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = nombre;
  document.body.appendChild(a);
  a.click();
  a.remove();
  // Libera el objeto URL tras un tick para no cancelar la descarga.
  setTimeout(() => URL.revokeObjectURL(url), 0);
}
