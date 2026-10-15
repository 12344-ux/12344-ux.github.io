// C1 · Prueba conductual de la frontera Auth cliente/personal en el back-office.
// Ejecutar: node --experimental-vm-modules probar-auth-guard.mjs
import fs from 'node:fs';
import vm from 'node:vm';
import { pathToFileURL } from 'node:url';

const REPO = process.env.REPO || '/projects/sandbox/12344-ux.github.io';
let total = 0;
let fallan = 0;
function chk(cond, nombre) {
  total++;
  if (!cond) fallan++;
  console.log(`${cond ? 'pasa' : 'FALLA'} · ${nombre}`);
}
const esperar = () => new Promise((resolve) => setTimeout(resolve, 0));

async function cargarAcceso(session) {
  const visto = { salidas: [] };
  const contexto = vm.createContext({ console });
  const supabaseMod = new vm.SyntheticModule(['supabase'], function () {
    this.setExport('supabase', {
      auth: {
        getSession: async () => ({ data: { session }, error: null }),
        signOut: async (opciones) => { visto.salidas.push(opciones); return { error: null }; },
      },
      from: () => { throw new Error('Esta prueba no consulta perfiles.'); },
    });
  }, { context: contexto });
  const ruta = `${REPO}/acceso-interno.js`;
  const modulo = new vm.SourceTextModule(fs.readFileSync(ruta, 'utf8'), {
    context: contexto,
    identifier: pathToFileURL(ruta).href,
  });
  await modulo.link(() => supabaseMod);
  await modulo.evaluate();
  return { api: modulo.namespace, visto };
}

async function probarCierreLocal() {
  const sesion = { user: { id: 'cliente' } };
  let cargado = await cargarAcceso(sesion);
  const cerro = await cargado.api.cerrarSesionLocal('cliente');
  chk(cerro && cargado.visto.salidas[0]?.scope === 'local', 'cierre: usa scope local de verdad');

  cargado = await cargarAcceso(sesion);
  const cerroAjena = await cargado.api.cerrarSesionLocal('otra-identidad');
  chk(!cerroAjena && cargado.visto.salidas.length === 0, 'cierre: una promesa vieja no cierra una sesion nueva');
}

async function probarGuardia(nombre, session, profile, esperado) {
  const visto = { cierres: 0, redirecciones: [] };
  const contexto = vm.createContext({
    console,
    URL,
    window: { location: { replace: (url) => visto.redirecciones.push(url) } },
  });
  const supabaseMod = new vm.SyntheticModule(['supabase'], function () {
    this.setExport('supabase', {
      auth: { getSession: async () => ({ data: { session }, error: null }) },
    });
  }, { context: contexto });
  const accesoMod = new vm.SyntheticModule(
    ['obtenerPerfilInterno', 'cerrarSesionLocal'],
    function () {
      this.setExport('obtenerPerfilInterno', async () => {
        if (profile instanceof Error) throw profile;
        return profile;
      });
      this.setExport('cerrarSesionLocal', async () => { visto.cierres++; });
    },
    { context: contexto },
  );
  const ruta = `${REPO}/auth-guard.js`;
  const id = pathToFileURL(ruta).href;
  const modulo = new vm.SourceTextModule(fs.readFileSync(ruta, 'utf8'), {
    context: contexto,
    identifier: id,
    initializeImportMeta(meta) { meta.url = id; },
  });
  await modulo.link((specifier) => (
    specifier === './supabase-config.js' ? supabaseMod : accesoMod
  ));
  await modulo.evaluate();
  await esperar();
  chk(
    visto.cierres === esperado.cierres
      && visto.redirecciones.length === esperado.redirecciones,
    nombre,
  );
}

async function probarLogin(nombre, { existente = null, ingreso, perfil, esperado }) {
  const visto = { cierres: 0, redirecciones: [], submit: null };
  const form = {
    email: { value: 'persona@example.invalid' },
    password: { value: 'clave-segura' },
    addEventListener(tipo, fn) { if (tipo === 'submit') visto.submit = fn; },
  };
  const submit = { disabled: false };
  const msg = { textContent: '' };
  const contexto = vm.createContext({
    console,
    document: {
      getElementById(id) {
        return { 'mg-login': form, 'mg-submit': submit, 'mg-msg': msg }[id];
      },
    },
    window: { location: { replace: (url) => visto.redirecciones.push(url) } },
  });
  const supabaseMod = new vm.SyntheticModule(['supabase'], function () {
    this.setExport('supabase', {
      auth: {
        getSession: async () => ({ data: { session: existente }, error: null }),
        signInWithPassword: async () => ingreso,
      },
    });
  }, { context: contexto });
  const accesoMod = new vm.SyntheticModule(
    ['obtenerPerfilInterno', 'cerrarSesionLocal'],
    function () {
      this.setExport('obtenerPerfilInterno', async () => {
        if (perfil instanceof Error) throw perfil;
        return perfil;
      });
      this.setExport('cerrarSesionLocal', async () => { visto.cierres++; });
    },
    { context: contexto },
  );
  const html = fs.readFileSync(`${REPO}/index.html`, 'utf8');
  const fuente = html.match(/<script type="module">([\s\S]*?)<\/script>/)?.[1];
  if (!fuente) throw new Error('No se encontro el modulo del login interno.');
  const id = pathToFileURL(`${REPO}/index.html`).href;
  const modulo = new vm.SourceTextModule(fuente, { context: contexto, identifier: id });
  await modulo.link((specifier) => (
    specifier === './supabase-config.js' ? supabaseMod : accesoMod
  ));
  await modulo.evaluate();
  await esperar();
  if (ingreso) {
    await visto.submit({ preventDefault() {} });
    await esperar();
  }
  chk(
    visto.cierres === esperado.cierres
      && visto.redirecciones.join('|') === esperado.redirecciones.join('|')
      && (esperado.mensaje ? msg.textContent.includes(esperado.mensaje) : true),
    nombre,
  );
}

async function probarCarreraLogin() {
  const eventos = [];
  let sesionActual = { user: { id: 'cliente-anterior' } };
  let liberarPerfil;
  const perfilRetenido = new Promise((resolve) => { liberarPerfil = resolve; });
  let manejarSubmit;
  const form = {
    email: { value: 'personal@example.invalid' },
    password: { value: 'clave-segura' },
    addEventListener(tipo, fn) { if (tipo === 'submit') manejarSubmit = fn; },
  };
  const submit = { disabled: false };
  const msg = { textContent: '' };
  const contexto = vm.createContext({
    console,
    document: { getElementById: (id) => ({ 'mg-login': form, 'mg-submit': submit, 'mg-msg': msg })[id] },
    window: { location: { replace: (url) => eventos.push(`redirigir:${url}`) } },
  });
  const supabaseMod = new vm.SyntheticModule(['supabase'], function () {
    this.setExport('supabase', {
      auth: {
        getSession: async () => ({ data: { session: sesionActual }, error: null }),
        signInWithPassword: async () => {
          eventos.push('iniciar:personal');
          sesionActual = { user: { id: 'personal-nuevo' } };
          return { data: { session: sesionActual }, error: null };
        },
      },
    });
  }, { context: contexto });
  const accesoMod = new vm.SyntheticModule(
    ['obtenerPerfilInterno', 'cerrarSesionLocal'],
    function () {
      this.setExport('obtenerPerfilInterno', async (sesion) => {
        if (sesion.user.id === 'cliente-anterior') {
          eventos.push('comprobar:cliente');
          await perfilRetenido;
          return null;
        }
        eventos.push('comprobar:personal');
        return { rol: 'admin', modulos: [] };
      });
      this.setExport('cerrarSesionLocal', async (uid) => {
        eventos.push(`cerrar:${uid}`);
        if (sesionActual?.user?.id === uid) sesionActual = null;
        return true;
      });
    },
    { context: contexto },
  );
  const html = fs.readFileSync(`${REPO}/index.html`, 'utf8');
  const fuente = html.match(/<script type="module">([\s\S]*?)<\/script>/)?.[1];
  const id = pathToFileURL(`${REPO}/index.html`).href;
  const modulo = new vm.SourceTextModule(fuente, { context: contexto, identifier: id });
  await modulo.link((specifier) => (
    specifier === './supabase-config.js' ? supabaseMod : accesoMod
  ));
  await modulo.evaluate();

  // Se envia mientras la comprobacion de la sesion anterior sigue retenida.
  const solicitud = manejarSubmit({ preventDefault() {} });
  await esperar();
  chk(!eventos.includes('iniciar:personal'), 'login: submit espera a que termine el bootstrap');
  liberarPerfil();
  await solicitud;
  await esperar();
  chk(
    eventos.indexOf('cerrar:cliente-anterior') < eventos.indexOf('iniciar:personal')
      && sesionActual?.user?.id === 'personal-nuevo'
      && eventos.includes('redirigir:panel.html'),
    'login: bootstrap viejo nunca cierra la sesion nueva de personal',
  );
}

await probarCierreLocal();
await probarGuardia(
  'guardia: cliente autenticado sin perfil es expulsado',
  { user: { id: 'cliente' } }, null, { cierres: 1, redirecciones: 1 },
);
await probarGuardia(
  'guardia: personal con perfil permanece',
  { user: { id: 'personal' } }, { rol: 'admin', modulos: [] },
  { cierres: 0, redirecciones: 0 },
);
await probarGuardia(
  'guardia: error transitorio cierra el panel pero conserva la sesion',
  { user: { id: 'personal' } }, new Error('red temporal'),
  { cierres: 0, redirecciones: 1 },
);
await probarGuardia(
  'guardia: visitante sin sesion vuelve al login',
  null, null, { cierres: 0, redirecciones: 1 },
);
await probarLogin('login: una sesion cliente guardada no entra al panel', {
  existente: { user: { id: 'cliente' } },
  ingreso: null,
  perfil: null,
  esperado: { cierres: 1, redirecciones: [] },
});
await probarLogin('login: credenciales cliente se cierran sin revelar por que', {
  ingreso: { data: { session: { user: { id: 'cliente' } } }, error: null },
  perfil: null,
  esperado: { cierres: 1, redirecciones: [], mensaje: 'No pudimos verificar' },
});
await probarLogin('login: credenciales del personal si abren el panel', {
  ingreso: { data: { session: { user: { id: 'personal' } } }, error: null },
  perfil: { rol: 'admin', modulos: [] },
  esperado: { cierres: 0, redirecciones: ['panel.html'] },
});
await probarLogin('login: error al comprobar perfil no destruye la sesion', {
  existente: { user: { id: 'personal' } },
  ingreso: null,
  perfil: new Error('red temporal'),
  esperado: { cierres: 0, redirecciones: [] },
});
await probarCarreraLogin();

console.log(`RESUMEN · ${total} comprobaciones · ${fallan} fallan`);
if (fallan) process.exit(1);
