# Puente con la API de Dropi

Permite que la IA (y a futuro la tienda) lea el **catálogo del proveedor** — nombre, costo,
precio sugerido, utilidad, stock, bodega e imágenes — sin que nadie tenga que copiar datos a mano.

## Por qué existe (y por qué no es un atajo)

La API de Dropi se autentica con un **token de tu cuenta** (header `dropi-integration-key`).
Con ese token se ve tu catálogo, tus precios de proveedor y —cuando lo conectemos— se **crean
pedidos**. Por eso:

- El token vive **solo** en Supabase Secrets (`DROPI_TOKEN`). Nunca en el repo, nunca en el
  frontend, **nunca en un chat** (el historial queda guardado; ya pasó con las llaves de Wompi).
- Esta función usa un secreto **propio y distinto**, `DROPI_LINK_KEY`, en vez del `LINK_SECRET`
  del tablero. Es a propósito, por **menor privilegio**:

  | Llave | Qué abre |
  |---|---|
  | `LINK_SECRET` | **todos** los datos de clientes (pedidos, correos, opiniones) |
  | `DROPI_LINK_KEY` | solo lectura del catálogo del proveedor |

  Si algún día hay que rotarla, se rota sola sin tocar el resto del sistema.

## Puesta en marcha (3 pasos, los haces tú)

### 1) Genera el token en Dropi
En el panel de Dropi, busca **Integraciones / API / Token** (la sección donde se conectan tiendas
como Shopify o WooCommerce) y **crea un token**. Cópialo al portapapeles y **no lo pegues en el chat**.

### 2) Crea los secretos en Supabase
`Project Settings → Edge Functions → Secrets`:

| Secreto | Valor |
|---|---|
| `DROPI_TOKEN` | el token que acabas de generar en Dropi |
| `DROPI_LINK_KEY` | una clave larga y aleatoria que inventes (30+ caracteres, letras y números) |
| `DROPI_PAIS` | *(opcional)* `co` por defecto. Otros: `mx`, `pe`, `cl`, `ec`, `pa`, `es`, `py`, `ar`, `cr` |

### 3) Despliega la función
`Edge Functions → Deploy new function → dropi` → pega el contenido de `index.ts` →
**Verify JWT: OFF** (igual que las demás; la autorización la valida el propio código).

### 4) Compruébalo
Abre en el navegador (reemplaza la clave):

```
https://ifvnuvjvlzpdaimelmbm.supabase.co/functions/v1/dropi?selftest=1&key=TU_DROPI_LINK_KEY
```

Debe responder `"ok": true` con `"ping": "ok"`. Si dice `Dropi respondió 401: Access denied`,
el token está mal o venció.

**Lo único que me pasas a mí es el `DROPI_LINK_KEY`.** El `DROPI_TOKEN` no lo necesito ni lo quiero.

## Modos

| Llamada | Qué devuelve |
|---|---|
| `?selftest=1&key=` | si el token está configurado y si Dropi responde (no revela el token) |
| `?muestra=1&key=` | **un** producto con todos sus campos crudos + la lista de campos |
| `?catalogo=1&pagina=0&tam=50&key=` | catálogo paginado y normalizado |

Filtros del catálogo: `&buscar=humidificador` · `&categoria=<id>` · `&bodega=<id>` ·
`&con_stock=1` · `&con_descripcion=1` · `&verificados=1` · `&orden=asc|desc` · `&ordenar_por=id`

## Nota técnica

Dropi **no publica documentación** de su API. El endpoint, el header y los parámetros se
obtuvieron leyendo su **plugin oficial de WooCommerce**, que es código abierto
(`wordpress.org/plugins/wc-dropi-integration`), y se verificaron en vivo: sin token válido la API
responde `401 {"isSuccess":false,"message":"Access denied"}`.

Como el esquema de cada producto no está documentado, el normalizador acepta **varios alias** por
campo (`price` / `cost` / `provider_price`…). Por eso existe `?muestra=1`: con un producto real
descubrimos los nombres exactos y afinamos el normalizador con certeza en vez de suposiciones.
