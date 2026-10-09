# Banco de pruebas local (Impulse / MAGANDHI)

La forma de dar **evidencia real** antes de que el dueño pegue SQL o despliegue funciones. Nada toca Supabase ni Resend reales.

## Armarlo (una vez por sandbox)

```bash
bash supabase/pruebas/local/herramientas/preparar.sh
```

Copia todo a `/projects/sandbox/pruebas-em5/` (fuera del repo) e instala PostgreSQL 15, Deno, Playwright y Pillow.

## Piezas

| Archivo | Para qué |
|---|---|
| `pg.sh [extra.sql …]` | Arranca Postgres, recrea `impulse_pruebas` con `supabase-simulado.sql` + `storage-minimo.sql` + **todas** las migraciones + la matriz, y corre los SQL extra. Imprime el RESUMEN de la matriz. |
| `simulador-v2.ts` | PostgREST mínimo **genérico**: ejecuta cualquier RPC de verdad contra el Postgres local, como `service_role` (llave falsa) o como el admin si `SIM_PANEL_UID` está definido. Incluye un Resend falso en `:54322` (`/emails`, `/__correos`, `/__falla?v=1`). |
| `simulador-postgrest.ts` | Versión anterior, solo para `em_webhook_registrar` (la usa `correr-webhook.sh`). |
| `correr-webhook.sh` | Prueba `em-webhook` con firmas Svix reales (incluida la librería oficial `npm:svix`). |
| `correr-suscripcion.sh` | Prueba `em-suscripcion` (EM6). |
| `correr-eventos.sh` | Prueba `tienda-eventos` (EM7). |
| `correr-ui-em6.sh` | Formulario de la tienda → función real → base → correo falso → enlace → confirmación (Chromium). |
| `correr-analitica.sh` | Aviso de cookies y eventos de la tienda de punta a punta (Chromium). |
| `correr-ui-metricas.sh [--capturas]` | Área Métricas con `semilla-metricas.sql` (datos realistas) y las RPC reales. `--capturas` guarda PNG de 1280×900 y 390×900 para revisar el diseño. |
| `probar-ui*.py` | Pantallas del back-office con Supabase interceptado (fixtures). |
| `correr-diagnostico.sh` | Prueba `../../diagnostico-produccion.sql` (el diagnóstico de solo lectura que el dueño pega en SQL Editor) en una base con F2 y otra «como producción» sin F2, dentro de una transacción `READ ONLY`. |

## Sin internet en el sandbox: GitHub Actions

`.github/workflows/banco-pruebas.yml` corre este mismo banco (PostgreSQL 15 + Deno, Edge Functions reales, secretos falsos) en cada push a una rama que no sea `main` y toque `supabase/**`. Reproduce las rutas `/projects/sandbox/...`, así que los scripts se usan tal cual. Sirve cuando el sandbox de Kiro no puede instalar Postgres. Resultado: pestaña **Actions** del repo, paso «Veredicto».

Las pruebas SQL de cada tramo están un nivel arriba: `../em5-resultados.sql`, `../em5-1-respuesta-email.sql`, `../em6-captura.sql`, `../metricas-m1.sql`.

## Lecciones del sandbox

- Los procesos en segundo plano **no sobreviven** entre llamadas a la herramienta: Postgres, simuladores y pruebas tienen que ir en **una sola invocación** (por eso existen los `correr-*.sh`).
- El sandbox bloquea `python -m http.server` lanzado desde bash. El servidor estático para Chromium se levanta **dentro** del script de Python (`ThreadingHTTPServer`).
- Si el comando de bash contiene el texto que busca `pkill -f`, el `pkill` se mata a sí mismo. No uses `pkill -f`.
- `deno run` necesita `-A` (o `--allow-run` completo) para lanzar `psql`, porque el entorno define `LD_LIBRARY_PATH`.
- Al comparar textos en Playwright usa `text_content` y no `inner_text`: hay títulos en MAYÚSCULAS por CSS.
- Capturas: siempre con `clip` y por debajo de 2000 px en ambos lados (regla del dueño). Revisa el tamaño antes de abrirlas.
