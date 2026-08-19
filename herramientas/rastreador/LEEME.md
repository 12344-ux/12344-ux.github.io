# Rastreador de nichos · Montaguth

Herramienta de línea de comandos para **descartar rápido** productos malos y quedarnos con
los pocos que vale la pena investigar a mano. No es una bola de cristal: es un filtro.

## Qué mide (y qué no)

| Sí | No |
|---|---|
| Demanda real en Google Trends (Colombia, 12 meses) | Ventas privadas de otras tiendas |
| Si la demanda **sube o baja** (moda viva vs. moda muerta) | Precio o margen del proveedor |
| Estacionalidad (un pico al año vs. demanda todo el año) | Cuánta competencia hay exactamente |
| Descubrimiento de términos en alza a partir de categorías semilla | Si el producto es bueno o malo |
| Descarte automático por reglas de marca (marcas ajenas, salud, riesgo) | |

**El score mide demanda, no rentabilidad.** El margen del proveedor es el que decide, y eso
todavía se verifica a mano (por eso la primera tarea del dueño es tener cuenta de proveedor).

## Uso

```bash
pip install pytrends pandas

# 1) Descubrir candidatos a partir de categorías amplias
python3 rastreador.py --semillas "cocina,mascotas,escritorio" --tope 20

# 2) Evaluar una lista concreta de productos
python3 rastreador.py --candidatos "humidificador,silla ergonomica,cafetera electrica"

# 3) Otro mercado / otra ventana / más lento (si Google bloquea)
python3 rastreador.py --geo MX --meses 24 --pausa 15
```

Salidas en `salidas/`: un `.md` para leer y un `.csv` para filtrar en una hoja de cálculo.

## Google Trends bloquea (429): cómo lo manejamos

Trends limita fuerte las consultas sin API oficial. Por eso:

- **Pausa de 8 s por defecto** entre consultas (`--pausa` para subirla).
- **Reintentos con backoff** (4 intentos, esperas crecientes).
- **Caché en disco** (`salidas/.cache-trends.json`, no se versiona): cada término se consulta
  **una sola vez**. Si una corrida se interrumpe, la siguiente retoma donde quedó.

Si aun así se bloquea: espera unos minutos y vuelve a correr — lo ya medido sale del caché.

## Cómo se puntúa (0–100)

Los pesos están pensados para **nuestro** canal (video + anuncios), no para SEO:

| Peso | Factor | Por qué |
|---:|---|---|
| 40 | Volumen sostenido (media 12 m) | Sin demanda no hay landing que salvar |
| 35 | Crecimiento (últimos 3 m vs. 3 m previos) | Entrar a una moda que ya cayó es quemar plata |
| 15 | Estabilidad (penaliza lo hiperestacional) | Un pico al año no sostiene una tienda |
| 10 | Intención de compra en el término | "comprar X" ≠ "qué es X" |

Veredictos: **investigar** (≥65) · **vigilar** (45–64) · **descartar** (<45, o demanda < 5,
o caída ≥ 25 %, o estacionalidad > ×5).

## Lista negra (descarte sin discusión)

Se veta antes de gastar una sola consulta:

1. **Marcas de terceros y clones** (Nike, Apple, "réplica", "tipo Apple"…) → falsificación:
   cierra pasarelas de pago y quema el dominio en publicidad.
2. **Salud, suplementos y cosmética con promesas** → regulado (INVIMA) y prohibido/restringido
   por las políticas de anuncios.
3. **Riesgo o certificación** (drones, baterías de litio, artículos de bebé, cascos…) →
   devoluciones y responsabilidad por producto.
4. **Commodities** (cables, fundas, "audífonos baratos") → solo se compite por precio, y ahí
   pierde el que no compra por contenedor.

Editable en `LISTA_NEGRA`, dentro del script.

## El filtro manual que va DESPUÉS (obligatorio)

El rastreador te deja la lista corta. Antes de elegir un producto:

1. Ticket ≥ $80.000 COP y margen ≥ 50 % (o ≥ $40.000 absolutos).
2. Se demuestra en video en menos de 10 segundos.
3. Liviano y no frágil.
4. Sin tallas ni variantes complicadas.
5. Sin marcas de terceros, sin regulados.
6. Resuelve un problema o da estatus (no commodity).
7. Proveedor con entrega rápida disponible.
8. Con competencia, pero no saturado.

## Ejemplo real (corrida del 19-ago-2026, Colombia)

Lo que enseñó la primera corrida, para que se entienda el valor del filtro:

- **humidificador** (score 67,5) y **silla ergonómica** (69,5) → demanda alta y sostenida.
  Pero la silla **falla el filtro manual**: voluminosa y pesada, el flete se come el margen.
  El humidificador sí pasa a investigar.
- **masajeador de cuello**: −45,6 % de demanda. Fue un clásico del dropshipping y **ya murió**.
  Justo el tipo de producto que un tutorial viejo te haría anunciar.
- **cafetera eléctrica**: +40,9 % de crecimiento pero volumen bajo (11) → vigilar, no apostar.

Moraleja: el rastreador te ahorra semanas y plata, pero **no reemplaza el criterio**.
