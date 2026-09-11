-- ============================================================
-- Magandhi Corporation · GRANT de tabla (capa 1) para el rol authenticated
-- ------------------------------------------------------------------------
-- POR QUE EXISTE ESTE ARCHIVO (causa raiz del 403 "permission denied"):
--
-- El proyecto Supabase se creo con "auto-expose new tables" en OFF (correcto
-- por seguridad, ver INSTRUCCIONES.md paso 4). Como efecto colateral, las
-- tablas creadas por las migraciones NUNCA recibieron el GRANT base de tabla
-- para el rol `authenticated`. En Postgres el acceso se decide en DOS capas:
--
--   Capa 1 · GRANT de tabla: ¿el rol puede tocar el objeto en absoluto?
--   Capa 2 · RLS (policies):  ¿que FILAS de ese objeto puede ver/escribir?
--
-- Las policies RLS del modulo ya estan bien definidas (perfiles_lectura_propia,
-- tiene_modulo('finanzas'), etc.), pero sin el GRANT de la capa 1 Postgres
-- rechaza con "permission denied for table ..." ANTES de siquiera evaluar RLS.
-- Por eso el frontend (llave publishable, rol `authenticated`) recibia 403 al
-- leer `perfiles`, aunque la fila del usuario existe y su policy lo permitiria.
--
-- QUE HACE (y que NO hace) esta migracion:
--   - Otorga los GRANT MINIMOS que el CLIENTE ejecuta DIRECTAMENTE. Auditado
--     el frontend (auth-guard.js + finanzas/*.html + finanzas-core.js), el
--     cliente solo hace lecturas directas (.select) sobre las tablas/vistas de
--     abajo. TODA la escritura va por RPC security definer (guardar_asiento,
--     editar_asiento, anular_asiento, incrementar_uso_cuenta), que corren con
--     privilegios del dueno y por eso NO requieren GRANT para `authenticated`
--     sobre las tablas que tocan por dentro.
--   - Por lo anterior: SOLO se otorga SELECT. NO se otorga INSERT/UPDATE/DELETE
--     (el cliente nunca los hace directo), NO se usa GRANT ALL, y NO se otorga
--     nada al rol `anon` (todo el modulo es tras login = `authenticated`).
--   - NO toca ni duplica ninguna policy RLS existente. La defensa real sigue
--     siendo RLS + las RPC security definer; estos GRANT solo destraban la
--     capa 1 para que RLS pueda por fin evaluarse. Minimo privilegio.
--
-- SOBRE GRANT EXECUTE (decision documentada): NO se incluye. En Postgres las
-- funciones otorgan EXECUTE a PUBLIC por defecto al crearse, y ninguna
-- migracion de este repo hace `revoke ... from public` sobre ellas
-- (verificado por grep: cero `revoke`). Por tanto `authenticated` YA puede
-- ejecutar las RPC del modulo; anadir GRANT EXECUTE seria redundante. Si en el
-- futuro se revoca EXECUTE de PUBLIC, habra que otorgar EXECUTE explicito a
-- `authenticated` sobre guardar_asiento, editar_asiento, anular_asiento,
-- incrementar_uso_cuenta y tiene_modulo.
--
-- IDEMPOTENTE: `grant` es idempotente por naturaleza (re-otorgar no duplica ni
-- falla). Se puede re-ejecutar este archivo cuantas veces haga falta.
-- ============================================================

-- ------------------------------------------------------------
-- perfiles · lo lee auth-guard.js: .from('perfiles').select('rol, modulos')
-- RLS: perfiles_lectura_propia (auth.uid() = id) -> cada quien solo su fila.
-- ------------------------------------------------------------
grant select on table perfiles to authenticated;

-- ------------------------------------------------------------
-- puc_cuentas · catalogo PUC. Lo leen puc.html, nuevo-asiento.html,
-- editar-asiento.html y mayor.html (.select del catalogo imputable).
-- RLS: puc_cuentas_select_modulo (tiene_modulo('finanzas')).
-- Sin UPDATE: el contador "usos" solo lo toca incrementar_uso_cuenta() (RPC).
-- ------------------------------------------------------------
grant select on table puc_cuentas to authenticated;

-- ------------------------------------------------------------
-- asientos + asiento_lineas · los lee diario.html en una sola consulta con
-- embed: .from('asientos').select('..., asiento_lineas(...)'). La escritura
-- (crear/editar/anular) va SIEMPRE por RPC security definer -> sin
-- INSERT/UPDATE/DELETE aqui. RLS: *_select_modulo (tiene_modulo('finanzas')).
-- ------------------------------------------------------------
grant select on table asientos to authenticated;
grant select on table asiento_lineas to authenticated;

-- ------------------------------------------------------------
-- asiento_bitacora · la lee finanzas-core.js (cargarBitacora) y diario.html
-- (historial por asiento). Append-only: la escribe editar_asiento/trigger
-- (security definer) -> el cliente solo SELECT. RLS: *_select_modulo.
-- ------------------------------------------------------------
grant select on table asiento_bitacora to authenticated;

-- ------------------------------------------------------------
-- Vistas derivadas del Libro Mayor · las lee mayor.html directamente
-- (.from('movimientos_mayor') / .from('saldos_cuenta')). No son
-- security_definer: heredan la RLS de sus tablas base (asientos/
-- asiento_lineas/puc_cuentas), ya cubiertas por los GRANT de arriba. El
-- cliente necesita SELECT sobre el objeto-vista para que PostgREST lo exponga.
-- ------------------------------------------------------------
grant select on movimientos_mayor to authenticated;
grant select on saldos_cuenta to authenticated;
