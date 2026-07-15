"""CLI: revisar una cubicación de construcción entregada en Excel."""
from __future__ import annotations

import argparse
import sys

from .checks import revisar_libro
from .config import load_config
from .loader import cargar_libro
from .report import guardar_reporte_excel, resumen_texto


def construir_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Revisa una cubicación de construcción en Excel: estructura, "
        "cálculos aritméticos, duplicados y (opcionalmente) partidas faltantes "
        "frente a un presupuesto de referencia."
    )
    parser.add_argument("cubicacion", help="Ruta al archivo Excel de la cubicación a revisar.")
    parser.add_argument(
        "--referencia",
        help="Ruta a un Excel de presupuesto/metrado de referencia, para detectar partidas "
        "faltantes o no presupuestadas.",
    )
    parser.add_argument(
        "--config",
        help="Ruta a un config.yaml con alias de columnas y tolerancias personalizadas.",
    )
    parser.add_argument(
        "--salida",
        default="reporte_revision.xlsx",
        help="Ruta del reporte Excel de salida (default: reporte_revision.xlsx).",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = construir_parser().parse_args(argv)
    config = load_config(args.config)

    hojas_cubicacion = cargar_libro(args.cubicacion, config)
    hojas_referencia = cargar_libro(args.referencia, config) if args.referencia else None

    issues = revisar_libro(hojas_cubicacion, config, hojas_referencia)

    print(resumen_texto(issues))
    guardar_reporte_excel(issues, args.salida)
    print(f"\nReporte detallado guardado en: {args.salida}")

    return 1 if any(i.severidad == "error" for i in issues) else 0


if __name__ == "__main__":
    sys.exit(main())
