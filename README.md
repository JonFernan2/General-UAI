# Revisor de Cubicaciones de Construcción

Herramienta de línea de comandos para revisar cubicaciones (metrados) de
construcción entregadas en Excel. Detecta:

- **Estructura**: columnas requeridas ausentes (código, descripción, unidad,
  cantidad, precio unitario, total) o encabezado no identificable.
- **Aritmética**: filas donde `cantidad × precio unitario ≠ total` (con
  tolerancia configurable).
- **Duplicados**: códigos de partida repetidos dentro de una misma hoja.
- **Partidas faltantes / no presupuestadas** (opcional): comparación de
  códigos contra un presupuesto o metrado de referencia.

## Instalación

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Uso

```bash
python -m cubicacion_review.cli cubicacion.xlsx --salida reporte_revision.xlsx
```

Con presupuesto de referencia (para detectar partidas faltantes o extra):

```bash
python -m cubicacion_review.cli cubicacion.xlsx \
  --referencia presupuesto.xlsx \
  --salida reporte_revision.xlsx
```

El comando imprime un resumen en consola y genera un Excel (`reporte_revision.xlsx`
por defecto) con dos hojas:

- **Resumen**: conteo de observaciones por categoría.
- **Detalle**: cada observación con hoja, fila, código, categoría, severidad y mensaje.

El código de salida es `1` si se detectaron errores y `0` si la cubicación pasó
todas las validaciones (útil para integrarlo en un pipeline de revisión).

## Cómo detecta las columnas

El programa busca, en las primeras filas de cada hoja, la fila que mejor calza
con encabezados conocidos (p. ej. "Código", "Cod.", "Ítem"; "Cantidad",
"Metrado"; "Precio Unitario", "P.U.", etc.). Si tus archivos usan encabezados
distintos, agrégalos en un `config.yaml` (ver `config.example.yaml`):

```bash
cp config.example.yaml config.yaml
# edita config.yaml con tus alias/tolerancias
python -m cubicacion_review.cli cubicacion.xlsx --config config.yaml
```

## Ejecutar las pruebas

```bash
python -m pytest cubicacion_review/tests -v
```

## Limitaciones conocidas (v1)

- La comparación contra el presupuesto de referencia agrupa los códigos de
  todas las hojas del libro (no valida hoja por hoja), así que si dos libros
  organizan las mismas partidas en hojas con nombres distintos, igual se
  comparan correctamente por código.
- No valida subtotales ni el total general del documento, solo el cálculo
  fila a fila (`cantidad × precio unitario = total`).
- Los códigos se comparan de forma case-insensitive y sin tildes/espacios
  extra, pero deben coincidir exactamente en el resto del texto.
