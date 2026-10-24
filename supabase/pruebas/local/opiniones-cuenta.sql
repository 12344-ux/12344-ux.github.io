-- ============================================================================
-- MAGANDHI · Opiniones con cuenta (20261117000000)
-- Verifica nombre público, elegibilidad, una opinión por cuenta y producto,
-- edición con historial, retiro que devuelve la opción de opinar, moderación,
-- convivencia con el código de reseña y permisos. Todo se deshace al final.
-- ============================================================================
begin;

create temp table op_resultados (ok boolean, prueba text);
create or replace function pg_temp.chk(cond boolean, nombre text) returns void language plpgsql as $$
begin insert into op_resultados values (coalesce(cond, false), nombre); end $$;

create or replace function pg_temp.json_como(uid uuid, q text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    case when uid is null then json_build_object('role', 'authenticated')::text
         else json_build_object('sub', uid, 'role', 'authenticated')::text end, true);
  execute q into v;
  execute 'reset role';
  return v;
exception when others then
  execute 'reset role';
  return jsonb_build_object('error', sqlerrm);
end $$;

create or replace function pg_temp.error_como(uid uuid, q text) returns text language plpgsql as $$
begin
  execute 'set local role authenticated';
  perform set_config('request.jwt.claims',
    case when uid is null then json_build_object('role', 'authenticated')::text
         else json_build_object('sub', uid, 'role', 'authenticated')::text end, true);
  execute q;
  execute 'reset role';
  return 'SIN ERROR';
exception when others then
  execute 'reset role';
  return sqlerrm;
end $$;

create or replace function pg_temp.error_rol(rol text, q text) returns text language plpgsql as $$
begin
  execute format('set local role %I', rol);
  execute q;
  execute 'reset role';
  return 'SIN ERROR';
exception when others then
  execute 'reset role';
  return sqlerrm;
end $$;

create or replace function pg_temp.error_postgres(q text) returns text language plpgsql as $$
begin execute q; return 'SIN ERROR'; exception when others then return sqlerrm; end $$;

create or replace function pg_temp.producto_de(snap jsonb, campana uuid) returns jsonb language sql as $$
  select x from jsonb_array_elements(coalesce(snap->'productos', '[]'::jsonb)) x
   where x->>'campana_id' = campana::text limit 1
$$;

do $$
declare
  u_ana   constant uuid := '0c100000-0000-4000-8000-000000000001';
  u_beto  constant uuid := '0c100000-0000-4000-8000-000000000002';
  u_sin   constant uuid := '0c100000-0000-4000-8000-000000000003';
  u_raro  constant uuid := '0c100000-0000-4000-8000-000000000004';
  u_nuevo constant uuid := '0c100000-0000-4000-8000-000000000005';
  u_bloq  constant uuid := '0c100000-0000-4000-8000-000000000006';
  u_staff constant uuid := '0c100000-0000-4000-8000-000000000007';
  c_ana   constant uuid := '0c200000-0000-4000-8000-000000000001';
  c_beto  constant uuid := '0c200000-0000-4000-8000-000000000002';
  c_sin   constant uuid := '0c200000-0000-4000-8000-000000000003';
  c_bloq  constant uuid := '0c200000-0000-4000-8000-000000000006';
  c_inv   constant uuid := '0c200000-0000-4000-8000-000000000009';
  p1  constant uuid := '0c300000-0000-4000-8000-000000000001';
  p2  constant uuid := '0c300000-0000-4000-8000-000000000002';
  p3  constant uuid := '0c300000-0000-4000-8000-000000000003';
  p4  constant uuid := '0c300000-0000-4000-8000-000000000004';
  p5  constant uuid := '0c300000-0000-4000-8000-000000000005';
  p6  constant uuid := '0c300000-0000-4000-8000-000000000006';
  k1  constant uuid := '0c400000-0000-4000-8000-000000000001';
  k1b constant uuid := '0c400000-0000-4000-8000-000000000011';
  k2  constant uuid := '0c400000-0000-4000-8000-000000000002';
  k3  constant uuid := '0c400000-0000-4000-8000-000000000003';
  k4  constant uuid := '0c400000-0000-4000-8000-000000000004';
  k5  constant uuid := '0c400000-0000-4000-8000-000000000005';
  k6  constant uuid := '0c400000-0000-4000-8000-000000000006';
  o_ana_1 constant uuid := '0c500000-0000-4000-8000-000000000001';
  o_ana_2 constant uuid := '0c500000-0000-4000-8000-000000000002';
  o_ana_3 constant uuid := '0c500000-0000-4000-8000-000000000003';
  o_ana_4 constant uuid := '0c500000-0000-4000-8000-000000000004';
  o_ana_5 constant uuid := '0c500000-0000-4000-8000-000000000005';
  o_beto  constant uuid := '0c500000-0000-4000-8000-000000000006';
  o_sin   constant uuid := '0c500000-0000-4000-8000-000000000007';
  o_bloq  constant uuid := '0c500000-0000-4000-8000-000000000008';
  o_inv   constant uuid := '0c500000-0000-4000-8000-000000000009';
  snap jsonb;
  v_op uuid;
  v_op2 uuid;
  v_op_p2 uuid;
  v_op_beto uuid;
  v_n integer;
  v_txt text;
  v_codigo text;
begin
  -- ---------------------------------------------------------------- semilla
  insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
    (u_ana, 'ana-op@local.invalid', now(),
      '{"full_name":"Ana María Pérez Gómez","name":"Ana María Pérez Gómez","given_name":"Ana María","family_name":"Pérez Gómez"}'),
    (u_beto, 'beto-op@local.invalid', now(), '{"full_name":"beto ramírez"}'),
    (u_sin, 'sin-op@local.invalid', now(), null),
    (u_raro, 'raro-op@local.invalid', now(), '{"full_name":"x9 @@ 😀"}'),
    (u_nuevo, 'nuevo-op@local.invalid', now(), '{"full_name":"Nueva Cuenta"}'),
    (u_bloq, 'bloq-op@local.invalid', now(), '{"full_name":"Bloqueada Prueba"}'),
    (u_staff, 'staff-op@local.invalid', now(), null);
  insert into perfiles (id, rol, modulos) values (u_staff, 'prueba', '{opiniones}');

  insert into clientes (id, nombre, correo) values
    (c_ana, 'Ana', 'ana-op@local.invalid'),
    (c_beto, 'Beto', 'beto-op@local.invalid'),
    (c_sin, 'Sin nombre', 'sin-op@local.invalid'),
    (c_bloq, 'Bloqueada', 'bloq-op@local.invalid'),
    (c_inv, 'Invitado', 'invitado-op@local.invalid');
  insert into cuentas_cliente (auth_user_id, customer_id, vinculado_en, estado) values
    (u_ana, c_ana, now(), 'activa'),
    (u_beto, c_beto, now(), 'activa'),
    (u_sin, c_sin, now(), 'activa'),
    (u_raro, null, null, 'activa'),
    (u_nuevo, null, null, 'activa'),
    (u_bloq, c_bloq, now(), 'bloqueada');

  insert into productos (id, sku, nombre, activo) values
    (p1, 'OP-P1', 'Producto uno', true),
    (p2, 'OP-P2', 'Producto dos', true),
    (p3, 'OP-P3', 'Producto inactivo', false),
    (p4, 'OP-P4', 'Producto sin publicar', true),
    (p5, 'OP-P5', 'Producto en camino', true),
    (p6, 'OP-P6', 'Producto anulado', true);
  insert into campana_producto (id, nombre, slug, precio_venta, product_id_ref, publicado, activo) values
    (k1, 'Campaña uno', 'op-k1', 10000, p1, true, true),
    (k1b, 'Campaña uno bis', 'op-k1b', 10000, p1, true, true),
    (k2, 'Campaña dos', 'op-k2', 20000, p2, true, true),
    (k3, 'Campaña inactiva', 'op-k3', 30000, p3, true, true),
    (k4, 'Campaña sin publicar', 'op-k4', 40000, p4, false, true),
    (k5, 'Campaña en camino', 'op-k5', 50000, p5, true, true),
    (k6, 'Campaña anulada', 'op-k6', 60000, p6, true, true);

  insert into pedidos (id, customer_id, total, estado, anulado, creado) values
    (o_ana_1, c_ana, 30000, 'entregado', false, now() - interval '10 days'),
    (o_ana_2, c_ana, 10000, 'entregado', false, now() - interval '2 days'),
    (o_ana_3, c_ana, 50000, 'preparando', false, now() - interval '1 day'),
    (o_ana_4, c_ana, 60000, 'entregado', true, now() - interval '3 days'),
    (o_ana_5, c_ana, 30000, 'entregado', false, now() - interval '4 days'),
    (o_beto, c_beto, 10000, 'entregado', false, now() - interval '5 days'),
    (o_sin, c_sin, 20000, 'entregado', false, now() - interval '6 days'),
    (o_bloq, c_bloq, 10000, 'entregado', false, now() - interval '7 days'),
    (o_inv, c_inv, 20000, 'entregado', false, now() - interval '8 days');
  insert into pedido_items (pedido_id, product_id, cantidad, precio_unitario, subtotal) values
    (o_ana_1, p1, 1, 10000, 10000),
    (o_ana_1, p2, 1, 20000, 20000),
    (o_ana_2, p1, 1, 10000, 10000),
    (o_ana_3, p5, 1, 50000, 50000),
    (o_ana_4, p6, 1, 60000, 60000),
    (o_ana_5, p3, 1, 30000, 30000),
    (o_ana_5, p4, 1, 40000, 40000),
    (o_beto, p1, 1, 10000, 10000),
    (o_sin, p2, 1, 20000, 20000),
    (o_bloq, p1, 1, 10000, 10000),
    (o_inv, p2, 1, 20000, 20000);

  -- ---------------------------------------------------------------- nombre público
  perform pg_temp.chk(public.op__nombre_publico('maicol rios') = 'Maicol R.', 'minúsculas se corrigen: «maicol rios» → «Maicol R.»');
  perform pg_temp.chk(public.op__nombre_publico('María José Pérez') = 'María J.', 'nombre con tildes conserva su forma');
  perform pg_temp.chk(public.op__nombre_publico('Juan de la Cruz') = 'Juan C.', 'las partículas «de la» no dan la inicial');
  perform pg_temp.chk(public.op__nombre_publico('LAURA') = 'Laura', 'un solo nombre en mayúsculas se publica sin inicial');
  perform pg_temp.chk(public.op__nombre_publico('Ana María', 'Pérez Gómez') = 'Ana P.', 'nombre y apellido separados usan la inicial del apellido');
  perform pg_temp.chk(public.op__nombre_publico('D''Angelo Rossi') = 'D''Angelo R.', 'el apóstrofo es válido');
  perform pg_temp.chk(public.op__nombre_publico('María Ñúñez') = 'María Ñ.', 'la eñe y las tildes son letras válidas');
  perform pg_temp.chk(public.op__nombre_publico('  Pedro   Páramo  ') = 'Pedro P.', 'se recortan y colapsan los espacios');
  perform pg_temp.chk(public.op__nombre_publico('J. Pérez') = 'J. P.', 'una inicial de nombre conserva su punto');
  perform pg_temp.chk(public.op__nombre_publico('x9 @@') is null, 'símbolos y dígitos no son un nombre');
  perform pg_temp.chk(public.op__nombre_publico('Ana 😀') is null, 'un emoji no es un nombre');
  perform pg_temp.chk(public.op__nombre_publico('a') is null, 'una letra sola no es un nombre');
  perform pg_temp.chk(public.op__nombre_publico(repeat('a', 81)) is null, 'más de 80 caracteres no es un nombre');
  perform pg_temp.chk(public.op__nombre_publico(null) is null, 'sin nombre no hay forma pública');
  perform pg_temp.chk(public.op__nombre_publico_cuenta(u_ana) = 'Ana P.', 'Google: given_name + family_name');
  perform pg_temp.chk(public.op__nombre_publico_cuenta(u_beto) = 'Beto R.', 'registro: full_name «Nombre y apellido»');
  perform pg_temp.chk(public.op__nombre_publico_cuenta(u_sin) = 'Cliente MAGANDHI', 'cuenta sin nombre usa «Cliente MAGANDHI»');
  perform pg_temp.chk(public.op__nombre_publico_cuenta(u_raro) = 'Cliente MAGANDHI', 'un nombre inválido usa «Cliente MAGANDHI»');

  -- ---------------------------------------------------------------- permisos
  perform pg_temp.chk(pg_temp.error_rol('anon', 'select public.op_cuenta_opiniones()') like 'permission denied%', 'anon no lista opiniones de cuenta');
  perform pg_temp.chk(pg_temp.error_rol('anon', format('select public.op_cuenta_opinar(%L, 5, null)', k1)) like 'permission denied%', 'anon no opina con cuenta');
  perform pg_temp.chk(pg_temp.error_rol('anon', format('select public.op_cuenta_retirar_opinion(%L)', k1)) like 'permission denied%', 'anon no retira opiniones');
  perform pg_temp.chk(pg_temp.error_como(u_ana, 'select count(*) from public.opiniones_historial') like 'permission denied%', 'una cuenta no lee el historial');
  perform pg_temp.chk(pg_temp.error_rol('service_role', 'select count(*) from public.opiniones_historial') like 'permission denied%', 'service_role no lee el historial');
  perform pg_temp.chk(pg_temp.error_como(u_ana, $q$select public.op__nombre_publico_cuenta('0c100000-0000-4000-8000-000000000002')$q$) like 'permission denied%', 'el nombre de otra cuenta no se consulta por API');
  perform pg_temp.chk(pg_temp.error_como(u_ana, format('select public.op__retirar_opinion(%L, null, null)', k1)) like 'permission denied%', 'el retiro privado no se alcanza por API');
  perform pg_temp.chk(pg_temp.error_como(u_ana, $q$select public.op_registrar_opinion('X', 'op-k1', 5, null, 'Ana', false)$q$) like 'permission denied%', 'una cuenta no usa la puerta del código');
  perform pg_temp.chk(pg_temp.error_como(u_ana, 'insert into public.opiniones (pedido_id, product_id, estrellas, autor_nombre) select id, null, 5, ''x'' from pedidos limit 1') like 'permission denied%', 'una cuenta no escribe opiniones directo');
  perform pg_temp.chk(pg_temp.error_como(null, 'select public.op_cuenta_opiniones()') = 'OP_SESION_REQUERIDA', 'sin sesión no hay snapshot');
  perform pg_temp.chk(pg_temp.error_como(u_staff, 'select public.op_cuenta_opiniones()') = 'OP_CUENTA_NO_DISPONIBLE', 'personal interno no es cuenta cliente');
  perform pg_temp.chk(pg_temp.error_como(u_bloq, 'select public.op_cuenta_opiniones()') = 'OP_CUENTA_NO_DISPONIBLE', 'cuenta bloqueada no opina');
  perform pg_temp.chk(pg_temp.error_como(u_bloq, format('select public.op_cuenta_opinar(%L, 5, null)', k1)) = 'OP_CUENTA_NO_DISPONIBLE', 'cuenta bloqueada no crea opiniones');

  -- ---------------------------------------------------------------- snapshot inicial
  snap := pg_temp.json_como(u_ana, 'select public.op_cuenta_opiniones()');
  perform pg_temp.chk(snap ? 'nombre_publico' and snap ? 'opiniones' and snap ? 'productos' and (select count(*) from jsonb_object_keys(snap)) = 3, 'snapshot con exactamente nombre_publico, opiniones y productos');
  perform pg_temp.chk(snap->>'nombre_publico' = 'Ana P.', 'el snapshot trae el nombre con que aparecerá');
  perform pg_temp.chk(jsonb_array_length(snap->'opiniones') = 0, 'sin opiniones todavía');
  perform pg_temp.chk(pg_temp.producto_de(snap, k1)->>'estado' = 'pendiente' and pg_temp.producto_de(snap, k1b)->>'estado' = 'pendiente', 'producto entregado: todas sus campañas publicadas quedan pendientes');
  perform pg_temp.chk(pg_temp.producto_de(snap, k2)->>'estado' = 'pendiente', 'cada producto de un pedido con varios productos se puede opinar');
  perform pg_temp.chk(pg_temp.producto_de(snap, k5) is null, 'pedido sin entregar no habilita opinar');
  perform pg_temp.chk(pg_temp.producto_de(snap, k6) is null, 'pedido anulado no habilita opinar');
  perform pg_temp.chk(pg_temp.producto_de(snap, k3) is null, 'producto inactivo no aparece pendiente');
  perform pg_temp.chk(pg_temp.producto_de(snap, k4) is null, 'campaña sin publicar no aparece');
  perform pg_temp.chk((select bool_and((select count(*) from jsonb_object_keys(x)) = 6 and x ? 'campana_id' and x ? 'slug' and x ? 'nombre' and x ? 'imagen' and x ? 'estado' and x ? 'opinion_id') from jsonb_array_elements(snap->'productos') x), 'cada producto trae exactamente seis claves públicas');
  perform pg_temp.chk((select count(*) from jsonb_array_elements(pg_temp.json_como(u_beto, 'select public.op_cuenta_opiniones()')->'productos') x where x->>'campana_id' in (k2::text)) = 0, 'otra cuenta no ve los productos ajenos');
  perform pg_temp.chk(jsonb_array_length(pg_temp.json_como(u_nuevo, 'select public.op_cuenta_opiniones()')->'productos') = 0, 'una cuenta sin compras no tiene productos por opinar');

  -- ---------------------------------------------------------------- validaciones
  perform pg_temp.chk(pg_temp.error_como(u_ana, format('select public.op_cuenta_opinar(%L, 0, null)', k1)) = 'OP_ESTRELLAS_INVALIDAS', 'cero estrellas se rechaza');
  perform pg_temp.chk(pg_temp.error_como(u_ana, format('select public.op_cuenta_opinar(%L, 6, null)', k1)) = 'OP_ESTRELLAS_INVALIDAS', 'seis estrellas se rechaza');
  perform pg_temp.chk(pg_temp.error_como(u_ana, 'select public.op_cuenta_opinar(null, 5, null)') = 'OP_SOLICITUD_INVALIDA', 'sin campaña se rechaza');
  perform pg_temp.chk(pg_temp.error_como(u_ana, format('select public.op_cuenta_opinar(%L, 5, %L)', k1, repeat('x', 1001))) = 'OP_COMENTARIO_INVALIDO', 'más de 1000 caracteres se rechaza');
  perform pg_temp.chk(pg_temp.error_como(u_ana, format('select public.op_cuenta_opinar(%L, 5, null)', k4)) = 'OP_PRODUCTO_NO_DISPONIBLE', 'campaña sin publicar se rechaza');
  perform pg_temp.chk(pg_temp.error_como(u_ana, format('select public.op_cuenta_opinar(%L, 5, null)', k3)) = 'OP_PRODUCTO_NO_DISPONIBLE', 'producto inactivo se rechaza');
  perform pg_temp.chk(pg_temp.error_como(u_ana, format('select public.op_cuenta_opinar(%L, 5, null)', k5)) = 'OP_NO_ELEGIBLE', 'producto sin entregar se rechaza');
  perform pg_temp.chk(pg_temp.error_como(u_ana, format('select public.op_cuenta_opinar(%L, 5, null)', k6)) = 'OP_NO_ELEGIBLE', 'producto de pedido anulado se rechaza');
  perform pg_temp.chk(pg_temp.error_como(u_ana, $q$select public.op_cuenta_opinar('0c4fffff-0000-4000-8000-000000000000', 5, null)$q$) = 'OP_PRODUCTO_NO_DISPONIBLE', 'campaña inexistente se rechaza');
  perform pg_temp.chk(pg_temp.error_como(u_nuevo, format('select public.op_cuenta_opinar(%L, 5, null)', k1)) = 'OP_NO_ELEGIBLE', 'cuenta sin compras no opina');
  perform pg_temp.chk(not exists (select 1 from public.opiniones where product_id in (p1, p2, p3, p4, p5, p6)), 'ningún rechazo escribió opiniones');

  -- ---------------------------------------------------------------- crear
  snap := pg_temp.json_como(u_ana, format('select public.op_cuenta_opinar(%L, 5, %L)', k1, '  Excelente producto  '));
  perform pg_temp.chk(snap ? 'opiniones' and jsonb_array_length(snap->'opiniones') = 1, 'crear devuelve el snapshot con la opinión nueva');
  select o.id into v_op from public.opiniones o where o.auth_user_id = u_ana and o.product_id = p1;
  perform pg_temp.chk(v_op is not null, 'la opinión queda ligada a la cuenta');
  perform pg_temp.chk((select origen = 'cuenta' and pedido_id = o_ana_2 and estrellas = 5 and comentario = 'Excelente producto'
                              and autor_nombre = 'Ana P.' and editado_en is null and not oculta and not es_prueba and creado_por = u_ana
                         from public.opiniones where id = v_op), 'se guarda con el pedido entregado más reciente, el nombre público y el texto recortado');
  perform pg_temp.chk((select bool_and((select count(*) from jsonb_object_keys(x)) = 15) from jsonb_array_elements(snap->'opiniones') x), 'cada opinión del snapshot trae exactamente quince claves');
  perform pg_temp.chk((snap->'opiniones'->0->>'campana_id') = k1::text or (snap->'opiniones'->0->>'campana_id') = k1b::text, 'la tarjeta propia trae una campaña publicada del producto');
  perform pg_temp.chk((snap->'opiniones'->0->>'puede_editar')::boolean and (snap->'opiniones'->0->>'puede_eliminar')::boolean, 'la opinión propia se puede editar y eliminar');
  perform pg_temp.chk(pg_temp.producto_de(snap, k1)->>'estado' = 'opinada' and pg_temp.producto_de(snap, k1b)->>'estado' = 'opinada'
                      and pg_temp.producto_de(snap, k1)->>'opinion_id' = v_op::text, 'el producto opinado cambia a «opinada» en todas sus campañas');
  perform pg_temp.chk((select count(*) from public.opiniones_publicas where slug = 'op-k1' and autor_nombre = 'Ana P.' and estrellas = 5 and not editada) = 1, 'la tienda la publica al instante como «Ana P.»');
  perform pg_temp.chk((select total from public.producto_rating_publico where slug = 'op-k1') = 1, 'cuenta en el promedio público');

  -- ---------------------------------------------------------------- una por producto: segunda vez = edición
  snap := pg_temp.json_como(u_ana, format('select public.op_cuenta_opinar(%L, 3, %L)', k1b, 'Cambié de opinión'));
  perform pg_temp.chk((select count(*) from public.opiniones where auth_user_id = u_ana and product_id = p1) = 1, 'opinar otra vez sobre el mismo producto no crea otra opinión');
  perform pg_temp.chk((select estrellas = 3 and comentario = 'Cambié de opinión' and editado_en is not null and id = v_op from public.opiniones where auth_user_id = u_ana and product_id = p1), 'la segunda vez edita la misma opinión');
  perform pg_temp.chk((select count(*) from public.opiniones_historial h where h.opinion_id = v_op and h.evento = 'edicion' and (h.datos->>'estrellas')::int = 5 and h.datos->>'comentario' = 'Excelente producto' and h.actor = u_ana) = 1, 'la versión anterior queda en el historial');
  perform pg_temp.chk((select editada from public.opiniones_publicas where slug = 'op-k1' and autor_nombre = 'Ana P.'), 'la tienda la marca como editada');
  perform pg_temp.chk(snap->'opiniones'->0->>'editado_en' is not null, 'el snapshot informa la edición');
  snap := pg_temp.json_como(u_ana, format('select public.op_cuenta_opinar(%L, 3, %L)', k1, 'Cambié de opinión'));
  perform pg_temp.chk((select count(*) from public.opiniones_historial h where h.opinion_id = v_op) = 1, 'repetir la misma opinión no agrega historial');

  -- ---------------------------------------------------------------- otro producto del mismo pedido
  snap := pg_temp.json_como(u_ana, format('select public.op_cuenta_opinar(%L, 4, null)', k2));
  select o.id into v_op_p2 from public.opiniones o where o.auth_user_id = u_ana and o.product_id = p2;
  perform pg_temp.chk(v_op_p2 is not null and (select pedido_id = o_ana_1 and comentario is null from public.opiniones where id = v_op_p2), 'el otro producto del pedido con varios productos se opina aparte, sin texto');
  perform pg_temp.chk(jsonb_array_length(snap->'opiniones') = 2, 'el snapshot lista ambas opiniones');

  -- ---------------------------------------------------------------- otra cuenta
  perform pg_temp.chk(pg_temp.error_como(u_beto, format('select public.op_cuenta_retirar_opinion(%L)', v_op)) = 'OP_OPINION_NO_ENCONTRADA', 'otra cuenta no retira una opinión ajena');
  snap := pg_temp.json_como(u_beto, format('select public.op_cuenta_opinar(%L, 5, %L)', k1, 'Me encantó'));
  select o.id into v_op_beto from public.opiniones o where o.auth_user_id = u_beto and o.product_id = p1;
  perform pg_temp.chk(v_op_beto is not null and (select autor_nombre = 'Beto R.' from public.opiniones where id = v_op_beto), 'otra cuenta opina con su propio nombre');
  perform pg_temp.chk(jsonb_array_length(snap->'opiniones') = 1, 'cada cuenta ve solo sus opiniones');
  perform pg_temp.chk((select count(*) from public.opiniones_publicas where slug = 'op-k1') = 2, 'la ficha muestra las dos opiniones');

  -- ---------------------------------------------------------------- moderación
  perform pg_temp.chk(pg_temp.error_como(u_staff, format('select public.op_responder_opinion(%L, %L)', v_op_p2, 'Gracias por tu compra')) = 'SIN ERROR', 'el panel responde opiniones con cuenta');
  perform pg_temp.chk(pg_temp.error_como(u_staff, format('select public.op_ocultar_opinion(%L, true, %L)', v_op_p2, 'spam')) = 'SIN ERROR', 'el panel oculta opiniones con cuenta');
  snap := pg_temp.json_como(u_ana, 'select public.op_cuenta_opiniones()');
  perform pg_temp.chk((select (x->>'oculta')::boolean and not (x->>'puede_editar')::boolean and not (x->>'puede_eliminar')::boolean and x->>'respuesta' = 'Gracias por tu compra'
                         from jsonb_array_elements(snap->'opiniones') x where x->>'id' = v_op_p2::text), 'la cuenta ve su opinión oculta, sin editar ni eliminar, con la respuesta');
  perform pg_temp.chk(pg_temp.producto_de(snap, k2)->>'estado' = 'oculta', 'el producto con opinión oculta no vuelve a pendiente');
  perform pg_temp.chk(pg_temp.error_como(u_ana, format('select public.op_cuenta_opinar(%L, 5, null)', k2)) = 'OP_OPINION_OCULTA', 'una opinión oculta no se edita');
  perform pg_temp.chk(pg_temp.error_como(u_ana, format('select public.op_cuenta_retirar_opinion(%L)', v_op_p2)) = 'OP_OPINION_OCULTA', 'una opinión oculta no se elimina desde la cuenta');
  perform pg_temp.chk((select count(*) from public.opiniones_publicas where slug = 'op-k2') = 0, 'la opinión oculta no sale en la tienda');

  -- ---------------------------------------------------------------- retirar
  snap := pg_temp.json_como(u_ana, format('select public.op_cuenta_retirar_opinion(%L)', v_op));
  perform pg_temp.chk(not exists (select 1 from public.opiniones where id = v_op), 'retirar quita la opinión de la tabla');
  perform pg_temp.chk((select count(*) from public.opiniones_historial h where h.opinion_id = v_op and h.evento = 'retiro' and h.motivo = 'cliente' and h.actor = u_ana and h.datos->>'id' = v_op::text) = 1, 'la fila completa queda en el historial');
  perform pg_temp.chk((select count(*) from public.opiniones_publicas where slug = 'op-k1' and autor_nombre = 'Ana P.') = 0, 'la retirada sale de la tienda');
  perform pg_temp.chk((select total from public.producto_rating_publico where slug = 'op-k1') = 1, 'la retirada sale del promedio');
  perform pg_temp.chk(pg_temp.producto_de(snap, k1)->>'estado' = 'pendiente', 'retirar devuelve la opción de opinar');
  perform pg_temp.chk(not exists (select 1 from jsonb_array_elements(snap->'opiniones') x where x->>'id' = v_op::text), 'la retirada sale de Mis opiniones');
  snap := pg_temp.json_como(u_ana, format('select public.op_cuenta_retirar_opinion(%L)', v_op));
  perform pg_temp.chk(not snap ? 'error' and (select count(*) from public.opiniones_historial h where h.opinion_id = v_op and h.evento = 'retiro') = 1, 'repetir el retiro es idempotente');
  snap := pg_temp.json_como(u_ana, format('select public.op_cuenta_opinar(%L, 4, %L)', k1, 'Volví a opinar'));
  select o.id into v_op2 from public.opiniones o where o.auth_user_id = u_ana and o.product_id = p1;
  perform pg_temp.chk(v_op2 is not null and v_op2 <> v_op and (select editado_en is null from public.opiniones where id = v_op2), 'después de retirar puede opinar de nuevo');

  -- ---------------------------------------------------------------- historial inmutable
  perform pg_temp.chk(pg_temp.error_postgres('update public.opiniones_historial set motivo = ''x''') = 'OP_HISTORIAL_INMUTABLE', 'el historial no se edita');
  perform pg_temp.chk(pg_temp.error_postgres('delete from public.opiniones_historial') = 'OP_HISTORIAL_INMUTABLE', 'el historial no se borra');
  perform pg_temp.chk(pg_temp.error_postgres('truncate public.opiniones_historial') = 'OP_HISTORIAL_INMUTABLE', 'el historial no se vacía');

  -- ---------------------------------------------------------------- convivencia con el código de reseña
  select codigo_resena into v_codigo from public.pedidos where id = o_sin;
  perform pg_temp.chk(public.op_registrar_opinion(v_codigo, 'op-k2', 4, 'Llegó bien', 'Invitado', false) is not null, 'el código del correo sigue funcionando');
  perform pg_temp.chk((select origen = 'codigo' and auth_user_id is null from public.opiniones where pedido_id = o_sin and product_id = p2), 'la opinión con código queda con origen código');
  perform pg_temp.chk(pg_temp.producto_de(pg_temp.json_como(u_sin, 'select public.op_cuenta_opiniones()'), k2) is null, 'una opinión con código de la misma persona bloquea la de cuenta');
  perform pg_temp.chk(pg_temp.error_como(u_sin, format('select public.op_cuenta_opinar(%L, 5, null)', k2)) = 'OP_YA_OPINADO', 'la cuenta no duplica una opinión hecha con código');
  perform pg_temp.chk(pg_temp.error_postgres(format($q$select public.op_registrar_opinion(%L, 'op-k2', 5, null, 'Otra', false)$q$, v_codigo)) = 'OPINION_YA_REGISTRADA', 'el mismo código no opina dos veces');
  select codigo_resena into v_codigo from public.pedidos where id = o_ana_1;
  perform pg_temp.chk(pg_temp.error_postgres(format($q$select public.op_registrar_opinion(%L, 'op-k1', 5, null, 'Ana', false)$q$, v_codigo)) = 'OPINION_YA_REGISTRADA', 'el código de otro pedido no duplica la opinión de la cuenta');
  select codigo_resena into v_codigo from public.pedidos where id = o_inv;
  perform pg_temp.chk(public.op_registrar_opinion(v_codigo, 'op-k2', 5, null, 'Invitada', false) is not null, 'un invitado distinto sigue opinando con su código');
  select codigo_resena into v_codigo from public.pedidos where id = o_beto;
  perform pg_temp.chk(pg_temp.error_postgres(format($q$select public.op_registrar_opinion(%L, 'op-k1', 5, null, 'Beto', false)$q$, v_codigo)) = 'OPINION_YA_REGISTRADA', 'el código del mismo pedido no duplica la opinión de cuenta');

  -- ---------------------------------------------------------------- cuenta eliminada
  delete from auth.users where id = u_beto;
  perform pg_temp.chk((select origen = 'cuenta' and auth_user_id is null from public.opiniones where id = v_op_beto), 'si la cuenta se elimina, la opinión verificada queda sin cuenta');
  perform pg_temp.chk((select count(*) from public.opiniones_publicas where slug = 'op-k1') = 2, 'la opinión de una cuenta eliminada sigue publicada');

  -- ---------------------------------------------------------------- superficie
  perform pg_temp.chk(has_table_privilege('anon', 'public.opiniones_publicas', 'select') and not has_table_privilege('anon', 'public.opiniones', 'select'), 'anon lee la vista pública y no la tabla');
  perform pg_temp.chk(not exists (select 1 from information_schema.columns where table_name = 'opiniones_publicas' and column_name in ('auth_user_id', 'origen', 'pedido_id', 'id')), 'la vista pública no expone cuenta, origen, pedido ni id');
end $$;

select 'RESUMEN' as tipo, count(*) || ' comprobaciones' as prueba,
       count(*) filter (where not ok) || ' fallan' as resultado
  from op_resultados
union all
select case when ok then 'pasa' else 'FALLA' end, prueba, case when ok then 'ok' else 'FALLA' end
  from op_resultados
order by 1, 2;

do $$ begin
  if exists (select 1 from op_resultados where not ok) then
    raise exception 'FALLA opiniones con cuenta';
  end if;
end $$;

rollback;
