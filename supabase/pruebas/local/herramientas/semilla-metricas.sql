-- Datos realistas SOLO LOCALES para ver Metricas con vida.
select setseed(0.42);
update em_config set politica_publicada = true, politica_version = 'borrador-0', analitica_activa = true where id;
insert into campana_producto (slug, nombre, publicado, activo, product_id_ref)
select s, n, true, true, (select id from productos order by creado offset o limit 1)
  from (values ('grisi-gold', 'Shampoo Grisi Gold Manzanilla', 0), ('jabon-avena', 'Jabón de avena artesanal', 1), ('crema-karite', 'Crema de karité', 2), ('aceite-romero', 'Aceite de romero', 3), ('vela-lavanda', 'Vela de lavanda', 4)) v(s, n, o)
 where not exists (select 1 from campana_producto c where c.slug = v.s);
insert into clientes (nombre, correo, correo_norm, ciudad)
select 'Cliente ' || g, 'c' || g || '@demo.invalid', 'c' || g || '@demo.invalid', (array['Tunja','Tunja','Tunja','Bogotá','Duitama','Sogamoso','Medellín','Tunja'])[1 + (g % 8)]
  from generate_series(1, 60) g;
do $$
declare d int; k int; cli uuid; pid uuid; prod uuid; cant int; precio int; h int; dia date; v_ciudad text;
begin
  for d in 0..89 loop
    dia := (now() at time zone 'America/Bogota')::date - d;
    for k in 1..(case when random() < .25 then 0 else 1 + floor(random() * (2.5 + (89 - d) / 30.0))::int end) loop
      select c.id, initcap(c.ciudad) into cli, v_ciudad from clientes c where correo_norm like '%@demo.invalid' order by random() limit 1;
      h := (array[9,10,11,12,14,15,16,18,19,19,20,20,21,21,22])[1 + floor(random() * 15)::int];
      insert into pedidos (customer_id, fecha_orden, total, creado, ciudad, canal, estado)
      values (cli, dia, 0, (dia + make_time(h, floor(random() * 59)::int, 0)) at time zone 'America/Bogota', v_ciudad,
              case when random() < .3 then 'web' else 'manual' end, 'entregado')
      returning id into pid;
      select id, coalesce(precio_venta, 30000) into prod, precio from productos order by random() limit 1;
      cant := 1 + floor(random() * 2.4)::int;
      insert into pedido_items (pedido_id, product_id, cantidad, precio_unitario, subtotal) values (pid, prod, cant, precio, cant * precio);
      update pedidos set total = cant * precio where id = pid;
    end loop;
  end loop;
end $$;
-- Visitas de los ultimos 45 dias (+ unas en vivo)
do $$
declare d int; v int; vid text; sid text; t timestamptz; org text; dis text; s text; h int; utm text;
begin
  for d in 0..44 loop
    for v in 1..(20 + floor(random() * 25 + (44 - d) * 0.6))::int loop
      vid := 'demo-' || md5(d || '-' || v || random()::text);
      sid := 'ses-' || substr(md5(vid), 1, 14);
      h := (array[7,8,9,12,13,13,18,19,19,20,20,21,21,22,22,23])[1 + floor(random() * 16)::int];
      t := ((now() at time zone 'America/Bogota')::date - d + make_time(h, floor(random() * 59)::int, 0)) at time zone 'America/Bogota';
      if t > now() then t := now() - (random() * interval '3 hours'); end if;
      org := (array['directo','directo','instagram','instagram','instagram','email','whatsapp','buscador','facebook','otro_sitio'])[1 + floor(random() * 10)::int];
      dis := (array['movil','movil','movil','movil','pc','pc','tablet'])[1 + floor(random() * 7)::int];
      utm := case when org = 'email' then (select utm_campaign from em_campanas order by random() limit 1) end;
      s := (array['grisi-gold','grisi-gold','grisi-gold','jabon-avena','jabon-avena','crema-karite','aceite-romero','vela-lavanda'])[1 + floor(random() * 8)::int];
      insert into tienda_eventos (visitante, sesion, tipo, ruta, origen, entrada, utm_campaign, dispositivo, cuando) values (vid, sid, 'pagina_vista', '/', org, true, utm, dis, t);
      if random() < .62 then
        insert into tienda_eventos (visitante, sesion, tipo, ruta, dispositivo, cuando) values (vid, sid, 'pagina_vista', '/producto/', dis, t + interval '40 seconds');
        insert into tienda_eventos (visitante, sesion, tipo, ruta, slug, dispositivo, cuando) values (vid, sid, 'producto_visto', '/producto/', s, dis, t + interval '41 seconds');
        if random() < .32 then
          insert into tienda_eventos (visitante, sesion, tipo, ruta, slug, dispositivo, cuando) values (vid, sid, 'clic_comprar', '/producto/', s, dis, t + interval '2 minutes');
          if random() < .55 then insert into tienda_eventos (visitante, sesion, tipo, ruta, slug, dispositivo, cuando) values (vid, sid, 'checkout_iniciado', '/producto/', s, dis, t + interval '3 minutes'); end if;
        end if;
      end if;
      if random() < .08 then insert into tienda_eventos (visitante, sesion, tipo, ruta, dispositivo, cuando) values (vid, sid, 'pagina_vista', '/politicas/', dis, t + interval '5 minutes'); end if;
    end loop;
  end loop;
  for v in 1..4 loop
    vid := 'demo-vivo-' || v || 'xxxxxxxx'; sid := 'ses-vivo-' || v || 'xxx';
    insert into tienda_eventos (visitante, sesion, tipo, ruta, origen, entrada, dispositivo, cuando) values (vid, sid, 'pagina_vista', '/', 'instagram', true, 'movil', now() - (v || ' minutes')::interval);
    insert into tienda_eventos (visitante, sesion, tipo, ruta, slug, dispositivo, cuando) values (vid, sid, 'producto_visto', '/producto/', 'grisi-gold', 'movil', now() - (v || ' minutes')::interval + interval '20 seconds');
  end loop;
  insert into tienda_eventos (visitante, sesion, tipo, ruta, slug, dispositivo, cuando) values ('demo-vivo-1xxxxxxxx', 'ses-vivo-1xxx', 'clic_comprar', '/producto/', 'grisi-gold', 'movil', now() - interval '30 seconds');
end $$;
select 'pedidos', count(*) from pedidos union all select 'eventos', count(*) from tienda_eventos;

-- ============================================================
-- M2 · datos para Email, Opiniones e Inventario
-- ============================================================

-- ----- INVENTARIO: entradas para que el stock sea positivo -----
-- (el seed de ventas registra pedido_items pero NO salidas de inventario; el
--  stock sale solo del libro de movimientos, asi que sembramos entradas.)
do $$
declare n int;
begin
  select count(*) into n from productos;
  insert into movimientos_inventario (product_id, tipo, cantidad, motivo, fecha)
  select id, 'entrada', 40 + floor(random() * 120)::int, 'Compra inicial (demo)', (now() at time zone 'America/Bogota')::date - 60
    from (select id, row_number() over (order by creado) rn from productos) p
   where p.rn < n;  -- el ultimo producto queda SIN entrada = agotado (estado honesto)
  -- un minimo alto para que el primer producto salga "bajo mínimo"
  update productos set stock_minimo = 200 where id = (select id from productos order by creado limit 1);
end $$;

-- ----- OPINIONES verificadas (excluye prueba y ocultas) -----
do $$
declare r record; est int;
begin
  for r in select p.id as pid, (select product_id from pedido_items where pedido_id = p.id limit 1) as prod, p.fecha_orden as f
             from pedidos p
            where p.estado = 'entregado' and not p.anulado
            order by random() limit 70 loop
    if r.prod is null then continue; end if;
    est := (array[5,5,5,5,4,4,4,3,5,2])[1 + floor(random() * 10)::int];
    insert into opiniones (pedido_id, product_id, estrellas, comentario, autor_nombre, creado, respuesta)
    values (r.pid, r.prod, est,
            case when random() < .6 then 'Muy buen producto, llegó rápido y bien empacado.' end,
            (array['Laura','Carlos','Mariana','Andrés','Sofía','Diego','Valentina','Juan'])[1 + floor(random() * 8)::int],
            (r.f + 1)::timestamptz + (floor(random() * 72) || ' hours')::interval,
            case when random() < .25 then 'Gracias por tu compra, nos alegra que te haya gustado.' end)
    on conflict (pedido_id, product_id) do nothing;
  end loop;
  -- una de PRUEBA y una OCULTA: deben quedar FUERA del promedio y el total
  insert into opiniones (pedido_id, product_id, estrellas, autor_nombre, es_prueba)
  select pid, prod, 1, 'Prueba', true from (
    select p.id pid, (select product_id from pedido_items where pedido_id = p.id limit 1) prod
      from pedidos p where p.estado = 'entregado'
       and not exists (select 1 from opiniones o where o.pedido_id = p.id) order by random() limit 1) q
  where q.prod is not null on conflict do nothing;
  insert into opiniones (pedido_id, product_id, estrellas, autor_nombre, oculta, oculta_motivo, oculta_en)
  select pid, prod, 1, 'Spam', true, 'spam', now() from (
    select p.id pid, (select product_id from pedido_items where pedido_id = p.id limit 1) prod
      from pedidos p where p.estado = 'entregado'
       and not exists (select 1 from opiniones o where o.pedido_id = p.id) order by random() limit 1) q
  where q.prod is not null on conflict do nothing;
end $$;

-- ----- EMAIL MARKETING: contactos + bitácora -----
do $$
declare g int; cid uuid; cli uuid; dia timestamptz; est text;
begin
  for g in 1..45 loop
    if exists (select 1 from em_contactos where correo_norm = 'c' || g || '@demo.invalid') then continue; end if;
    dia := now() - (floor(random() * 85) || ' days')::interval;
    est := case when random() < .82 then 'suscrito' when random() < .6 then 'pendiente_confirmacion' else 'baja' end;
    select id into cli from clientes where correo_norm = 'c' || g || '@demo.invalid';
    insert into em_contactos (correo, correo_norm, customer_id, estado, fuente, temas, consentimiento_en, consentimiento_texto, politica_version, confirmado_en)
    values ('c' || g || '@demo.invalid', 'c' || g || '@demo.invalid', case when random() < .7 then cli end, est, 'formulario_tienda',
            case when random() < .5 then array['novedades','ofertas'] else array['novedades'] end,
            dia, 'Acepto recibir correos de Magandhi', 'borrador-0', case when est <> 'pendiente_confirmacion' then dia end)
    returning id into cid;
    insert into em_consentimiento_bitacora (contacto_id, accion, estado_nuevo, cuando) values (cid, 'alta', est, dia);
    if est = 'baja' then insert into em_consentimiento_bitacora (contacto_id, accion, estado_nuevo, cuando) values (cid, 'baja', 'baja', dia + interval '6 days'); end if;
  end loop;
end $$;

-- ----- EMAIL MARKETING: campañas + eventos (entregado/clic) -----
do $$
declare j int; camp uuid; ut text; env timestamptz; ct record;
begin
  for j in 1..4 loop
    ut := 'camp-demo-' || j;
    env := now() - ((j * 12) || ' days')::interval;
    if exists (select 1 from em_campanas where utm_campaign = ut) then continue; end if;
    insert into em_campanas (nombre_interno, asunto, utm_campaign, estado, audiencia_n, enviada_en, resend_broadcast_id, resend_segment_id, tema)
    values ('Campaña demo ' || j,
            (array['Novedades de la semana','20% en cuidado capilar','Llegó algo nuevo','Gracias por acompañarnos'])[j],
            ut, 'enviada', 22, env, 'bc_demo_' || j, 'seg_demo_' || j, 'novedades')
    returning id into camp;
    for ct in select c.id, c.correo from em_contactos c where c.estado = 'suscrito' order by random() limit 22 loop
      insert into em_campana_destinatarios (campana_id, contacto_id, correo, estado, procesado_en)
      values (camp, ct.id, ct.correo, 'listo', env);
      insert into em_eventos (svix_id, evento, tipo, origen, campana_id, contacto_id, cuando, recibido)
      values ('svx_' || replace(camp::text, '-', '') || '_' || replace(ct.id::text, '-', '') || '_e', 'email.delivered', 'entregado', 'campana', camp, ct.id, env + interval '2 minutes', env + interval '2 minutes');
      if random() < .38 then
        insert into em_eventos (svix_id, evento, tipo, origen, campana_id, contacto_id, enlace, cuando, recibido)
        values ('svx_' || replace(camp::text, '-', '') || '_' || replace(ct.id::text, '-', '') || '_c', 'email.clicked', 'clic', 'campana', camp, ct.id, 'https://magandhi.com/?utm_campaign=' || ut, env + interval '1 hour', env + interval '1 hour');
      end if;
    end loop;
  end loop;
end $$;

-- ----- CORREOS del pedido (seguimiento + salud) -----
insert into correo_envios (pedido_id, etapa, destinatario, estado, creado)
select p.id, 'entregado', 'cliente@demo.invalid', 'enviado', p.fecha_orden::timestamptz
  from pedidos p where p.estado = 'entregado' and not p.anulado order by random() limit 30;

select 'opiniones', count(*) from opiniones union all select 'contactos', count(*) from em_contactos union all select 'campanas', count(*) from em_campanas union all select 'eventos_email', count(*) from em_eventos union all select 'movimientos_inv', count(*) from movimientos_inventario;
