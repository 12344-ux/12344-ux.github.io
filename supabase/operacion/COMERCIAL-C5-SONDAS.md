# Comercial C5 · sondas reproducibles sin dinero

Estas sondas validan las Edge C5 sin crear intenciones, abrir Wompi ni usar datos reales. Ejecutarlas primero tras desplegar las Edge compatibles sobre C4 y repetirlas después de instalar C5. Mantener la configuración de gateway/Verify JWT existente.

## Preparación local

Definir en una terminal privada; no guardar valores en el repositorio ni pegarlos en evidencias:

```bash
export SUPABASE_FUNCTIONS_URL="https://<project-ref>.supabase.co/functions/v1"
export SUPABASE_PUBLIC_KEY="<publishable-o-anon-publica>"
export SUPABASE_GATEWAY_BEARER="<anon-jwt-publico-aceptado-por-el-gateway>"
```

`SUPABASE_GATEWAY_BEARER` es una credencial **pública** capaz de atravesar el gateway, no un access token de usuario ni `service_role`. Si el proyecto acepta la misma llave pública como bearer, puede tener el mismo valor que `SUPABASE_PUBLIC_KEY`. Nunca usar `service_role` desde estas sondas.

Los tres orígenes admitidos por el código son `https://magandhi.com`, `https://www.magandhi.com` y `https://12344-ux.github.io`. Para un origen ajeno la Edge responde con el origen canónico, no refleja el origen atacante; por ello el navegador debe bloquear la lectura.

## Sondas comunes previas y posteriores a C5

### 1. Preflight CORS permitido

```bash
curl -si -X OPTIONS "$SUPABASE_FUNCTIONS_URL/estado-pago" \
  -H 'Origin: https://magandhi.com' \
  -H 'Access-Control-Request-Method: POST' \
  -H 'Access-Control-Request-Headers: authorization,apikey,content-type'
```

Esperado: HTTP `204`, `Access-Control-Allow-Origin: https://magandhi.com`, métodos `POST, OPTIONS`, `Vary: Origin` y sin body.

Repetir contra `crear-intencion-pago` y, por separado, con los otros dos orígenes permitidos.

### 2. Origen no permitido

```bash
curl -si -X OPTIONS "$SUPABASE_FUNCTIONS_URL/estado-pago" \
  -H 'Origin: https://ejemplo-invalido.test' \
  -H 'Access-Control-Request-Method: POST'
```

Esperado: HTTP `204`, pero `Access-Control-Allow-Origin` **no** puede ser `https://ejemplo-invalido.test`; actualmente debe ser `https://magandhi.com`. Repetir contra la otra Edge.

### 3. Método no permitido

```bash
curl -si "$SUPABASE_FUNCTIONS_URL/estado-pago" \
  -H 'Origin: https://magandhi.com' \
  -H "apikey: $SUPABASE_PUBLIC_KEY" \
  -H "Authorization: Bearer $SUPABASE_GATEWAY_BEARER"
```

Esperado: HTTP `405` y JSON con `error`, sin datos internos. Repetir contra `crear-intencion-pago`.

### 4. JSON inválido

```bash
curl -si -X POST "$SUPABASE_FUNCTIONS_URL/estado-pago" \
  -H 'Origin: https://magandhi.com' \
  -H "apikey: $SUPABASE_PUBLIC_KEY" \
  -H "Authorization: Bearer $SUPABASE_GATEWAY_BEARER" \
  -H 'Content-Type: application/json' \
  --data-binary '{'
```

Esperado: HTTP `400` y el error público de body inválido. Repetir contra `crear-intencion-pago`.

### 5. Referencia inexistente en estado

```bash
curl -si -X POST "$SUPABASE_FUNCTIONS_URL/estado-pago" \
  -H 'Origin: https://magandhi.com' \
  -H "apikey: $SUPABASE_PUBLIC_KEY" \
  -H "Authorization: Bearer $SUPABASE_GATEWAY_BEARER" \
  -H 'Content-Type: application/json' \
  --data '{"referencia":"C5-SONDA-INEXISTENTE"}'
```

Esperado: HTTP `404`, `Cache-Control: no-store` y `{"error":"Referencia no encontrada."}`. `estado-pago` acepta un JWT de usuario de forma opcional para preservar consultas históricas por posesión; para una intención v2/C5 la RPC exige el UID propietario y devuelve el mismo 404 cuando falta o no coincide.

### 6. Carrito válido en forma, sin sesión de usuario

```bash
curl -si -X POST "$SUPABASE_FUNCTIONS_URL/crear-intencion-pago" \
  -H 'Origin: https://magandhi.com' \
  -H "apikey: $SUPABASE_PUBLIC_KEY" \
  -H "Authorization: Bearer $SUPABASE_GATEWAY_BEARER" \
  -H 'Content-Type: application/json' \
  --data '{"carrito":{"id":"11111111-1111-4111-8111-111111111111","version":0},"comprador":{"nombre":"Persona Prueba","correo":"prueba@example.com","telefono":"3000000000","direccion":"Dirección de prueba","ciudad":"Bogotá","departamento":"Bogotá D.C.","pais":"CO"}}'
```

Esperado: HTTP `401`, código público `SESION_REQUERIDA` y cero intenciones nuevas. Los datos son ficticios y solo permiten alcanzar el gate de sesión; no reutilizar información personal real.

Si el gateway rechaza antes de entrar a la Edge, registrar ese 401 como **gate de gateway**, no como evidencia del gate de aplicación. Para validar el 401 de aplicación se necesita un bearer público aceptado por el gateway que no sea sesión de usuario.

## Sonda exclusiva de la Edge C5 antes de migrar

### 7. Router de reapertura C5, body deliberadamente inválido

Esta llamada identifica la revisión C5 sin invocar la RPC C5 ni crear datos:

```bash
curl -si -X POST "$SUPABASE_FUNCTIONS_URL/crear-intencion-pago" \
  -H 'Origin: https://magandhi.com' \
  -H "apikey: $SUPABASE_PUBLIC_KEY" \
  -H "Authorization: Bearer $SUPABASE_GATEWAY_BEARER" \
  -H 'Content-Type: application/json' \
  --data '{"intencion":{}}'
```

Esperado exclusivamente en la Edge C5: HTTP `400` y código `INTENCION_INVALIDA`. La validación ocurre antes de sesión y antes de llamar `mc_reabrir_intencion_c5`, así que es segura mientras la base continúa en C4.

## Sondas exclusivas después de instalar C5

No probar una referencia de reapertura con forma válida mientras el backend siga en C4: la RPC C5 todavía no existe y un 500 sería esperado, no una falla de compatibilidad.

### 8. Reapertura inexistente con sesión propia

En una terminal privada definir un access token vigente de una cuenta propia controlada:

```bash
export SUPABASE_USER_ACCESS_TOKEN="<access-token-cuenta-propia>"
curl -si -X POST "$SUPABASE_FUNCTIONS_URL/crear-intencion-pago" \
  -H 'Origin: https://magandhi.com' \
  -H "apikey: $SUPABASE_PUBLIC_KEY" \
  -H "Authorization: Bearer $SUPABASE_USER_ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  --data '{"intencion":{"referencia":"C5-SONDA-INEXISTENTE"}}'
```

Esperado: HTTP `409`, código `INTENCION_NO_REABRIBLE`, sin firma, monto, comprador ni confirmación de existencia.

La reapertura ajena se comprueba únicamente con dos cuentas propias y una intención sin dinero creada durante la ventana ON. Cuenta B debe recibir la misma respuesta pública que una referencia inexistente. No guardar la referencia ni los tokens en documentos o logs.

## Evidencia y criterio

Registrar únicamente fecha/hora, commit Edge desplegado, sonda, HTTP, código público y aprobado/fallido. No registrar headers de autorización ni bodies con correladores. Confirmar mediante `comercial-c5-estado.sql` que las sondas 1–8 no crearon intenciones.

Si falla una sonda, ejecutar `comercial-c5-desactivar.sql`, exigir `apagado_confirmado=true` y detener la ventana. Wompi permanece en `prod`; ninguna sonda abre o autoriza cobros.