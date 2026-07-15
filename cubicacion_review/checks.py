"""Reglas de revisión: estructura, aritmética, duplicados y comparación con referencia."""
from __future__ import annotations

from dataclasses import dataclass

from .config import Config, normalizar_texto
from .loader import Fila, Hoja


@dataclass
class Issue:
    hoja: str
    categoria: str  # estructura | aritmetica | duplicado | faltante | no_presupuestado
    severidad: str  # error | advertencia
    mensaje: str
    fila_excel: int | None = None
    codigo: str | None = None


def _a_numero(valor: object) -> float | None:
    if valor is None:
        return None
    if isinstance(valor, (int, float)):
        return float(valor)
    texto = str(valor).strip().replace(",", ".")
    if texto == "":
        return None
    try:
        return float(texto)
    except ValueError:
        return None


def check_estructura(hoja: Hoja) -> list[Issue]:
    issues: list[Issue] = []
    if not hoja.encabezado_encontrado:
        issues.append(
            Issue(
                hoja=hoja.nombre,
                categoria="estructura",
                severidad="error",
                mensaje=(
                    "No se pudo identificar una fila de encabezado con las columnas "
                    "esperadas (código, descripción, unidad, cantidad, precio unitario, total)."
                ),
            )
        )
        return issues

    for columna in hoja.columnas_faltantes:
        issues.append(
            Issue(
                hoja=hoja.nombre,
                categoria="estructura",
                severidad="error",
                mensaje=f"Falta la columna requerida '{columna}'.",
            )
        )
    return issues


def check_aritmetica(hoja: Hoja, config: Config) -> list[Issue]:
    issues: list[Issue] = []
    if hoja.columnas_faltantes:
        return issues  # sin columnas completas no se puede validar aritmética

    for fila in hoja.filas:
        cantidad = _a_numero(fila.valores.get("cantidad"))
        precio = _a_numero(fila.valores.get("precio_unitario"))
        total = _a_numero(fila.valores.get("total"))

        if cantidad is None or precio is None or total is None:
            continue  # posible fila de sección/subtotal, no se valida

        esperado = cantidad * precio
        tolerancia = max(config.tolerancia_absoluta, config.tolerancia_porcentual * abs(esperado))
        diferencia = total - esperado

        if abs(diferencia) > tolerancia:
            codigo = fila.valores.get("codigo")
            issues.append(
                Issue(
                    hoja=hoja.nombre,
                    categoria="aritmetica",
                    severidad="error",
                    fila_excel=fila.fila_excel,
                    codigo=str(codigo) if codigo is not None else None,
                    mensaje=(
                        f"Cantidad ({cantidad}) x Precio unitario ({precio}) = {esperado:.2f}, "
                        f"pero el total indicado es {total:.2f} "
                        f"(diferencia de {diferencia:.2f})."
                    ),
                )
            )
    return issues


def check_duplicados(hoja: Hoja) -> list[Issue]:
    issues: list[Issue] = []
    if "codigo" not in hoja.columnas:
        return issues

    vistos: dict[str, list[Fila]] = {}
    for fila in hoja.filas:
        codigo = fila.valores.get("codigo")
        if codigo is None or str(codigo).strip() == "":
            continue
        clave = normalizar_texto(codigo)
        vistos.setdefault(clave, []).append(fila)

    for clave, filas in vistos.items():
        if len(filas) > 1:
            numeros_fila = ", ".join(str(f.fila_excel) for f in filas)
            codigo_original = filas[0].valores.get("codigo")
            issues.append(
                Issue(
                    hoja=hoja.nombre,
                    categoria="duplicado",
                    severidad="error",
                    codigo=str(codigo_original),
                    mensaje=f"El código '{codigo_original}' aparece repetido en las filas {numeros_fila}.",
                )
            )
    return issues


def _codigos_de_libro(hojas: list[Hoja]) -> dict[str, list[str]]:
    """Mapa de código normalizado -> lista de hojas donde aparece."""
    codigos: dict[str, list[str]] = {}
    for hoja in hojas:
        if "codigo" not in hoja.columnas:
            continue
        for fila in hoja.filas:
            codigo = fila.valores.get("codigo")
            if codigo is None or str(codigo).strip() == "":
                continue
            clave = normalizar_texto(codigo)
            codigos.setdefault(clave, []).append(hoja.nombre)
    return codigos


def check_referencia(hojas_cubicacion: list[Hoja], hojas_referencia: list[Hoja]) -> list[Issue]:
    """Compara los códigos de la cubicación contra un presupuesto/metrado de referencia."""
    issues: list[Issue] = []

    codigos_cub = _codigos_de_libro(hojas_cubicacion)
    codigos_ref = _codigos_de_libro(hojas_referencia)

    faltantes = sorted(set(codigos_ref) - set(codigos_cub))
    for clave in faltantes:
        issues.append(
            Issue(
                hoja=", ".join(codigos_ref[clave]),
                categoria="faltante",
                severidad="error",
                codigo=clave,
                mensaje=f"La partida '{clave}' está en la referencia pero no aparece en la cubicación entregada.",
            )
        )

    extras = sorted(set(codigos_cub) - set(codigos_ref))
    for clave in extras:
        issues.append(
            Issue(
                hoja=", ".join(codigos_cub[clave]),
                categoria="no_presupuestado",
                severidad="advertencia",
                codigo=clave,
                mensaje=f"La partida '{clave}' aparece en la cubicación pero no está en la referencia.",
            )
        )
    return issues


def revisar_libro(
    hojas_cubicacion: list[Hoja],
    config: Config,
    hojas_referencia: list[Hoja] | None = None,
) -> list[Issue]:
    issues: list[Issue] = []
    for hoja in hojas_cubicacion:
        issues.extend(check_estructura(hoja))
        issues.extend(check_aritmetica(hoja, config))
        issues.extend(check_duplicados(hoja))

    if hojas_referencia is not None:
        issues.extend(check_referencia(hojas_cubicacion, hojas_referencia))

    return issues
