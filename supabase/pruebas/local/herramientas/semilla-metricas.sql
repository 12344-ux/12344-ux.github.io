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
