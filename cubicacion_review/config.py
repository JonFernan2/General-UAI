"""Configuración de columnas y tolerancias para la revisión de cubicaciones."""
from __future__ import annotations

import unicodedata
from dataclasses import dataclass, field

# Alias comunes (en español) para cada columna que necesitamos identificar
# dentro de una hoja de cubicación. Las claves son los nombres "canónicos"
# que usa el resto del programa.
DEFAULT_COLUMN_ALIASES: dict[str, list[str]] = {
    "codigo": ["codigo", "cod", "cod.", "item", "n", "n.", "partida"],
    "descripcion": ["descripcion", "detalle", "concepto", "denominacion"],
    "unidad": ["unidad", "und", "un", "un.", "u.m.", "um"],
    "cantidad": ["cantidad", "cant", "cant.", "metrado"],
    "precio_unitario": [
        "precio unitario",
        "p.u.",
        "pu",
        "precio unit",
        "valor unitario",
        "vr unitario",
        "vr. unitario",
    ],
    "total": ["total", "valor total", "subtotal", "vr total", "vr. total"],
}

REQUIRED_COLUMNS = ["codigo", "descripcion", "unidad", "cantidad", "precio_unitario", "total"]


def normalizar_texto(texto: str) -> str:
    """Minúsculas, sin tildes ni espacios sobrantes, para comparar encabezados."""
    if texto is None:
        return ""
    texto = str(texto).strip().lower()
    texto = "".join(
        c for c in unicodedata.normalize("NFKD", texto) if not unicodedata.combining(c)
    )
    return " ".join(texto.split())


@dataclass
class Config:
    column_aliases: dict[str, list[str]] = field(
        default_factory=lambda: {k: list(v) for k, v in DEFAULT_COLUMN_ALIASES.items()}
    )
    tolerancia_absoluta: float = 0.5
    tolerancia_porcentual: float = 0.005  # 0.5%
    hojas_ignoradas: list[str] = field(default_factory=list)

    def alias_normalizados(self) -> dict[str, str]:
        """Mapa de encabezado normalizado -> nombre canónico de columna."""
        mapa: dict[str, str] = {}
        for canonico, alias in self.column_aliases.items():
            for a in alias + [canonico]:
                mapa[normalizar_texto(a)] = canonico
        return mapa


def load_config(path: str | None) -> Config:
    """Carga un config.yaml opcional que sobreescribe/agrega alias y tolerancias."""
    if not path:
        return Config()

    import yaml

    with open(path, encoding="utf-8") as fh:
        data = yaml.safe_load(fh) or {}

    cfg = Config()
    if "column_aliases" in data:
        for canonico, alias in data["column_aliases"].items():
            cfg.column_aliases.setdefault(canonico, [])
            cfg.column_aliases[canonico].extend(alias)
    if "tolerancia_absoluta" in data:
        cfg.tolerancia_absoluta = float(data["tolerancia_absoluta"])
    if "tolerancia_porcentual" in data:
        cfg.tolerancia_porcentual = float(data["tolerancia_porcentual"])
    if "hojas_ignoradas" in data:
        cfg.hojas_ignoradas = list(data["hojas_ignoradas"])
    return cfg
