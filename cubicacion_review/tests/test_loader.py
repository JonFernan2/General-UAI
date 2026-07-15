from cubicacion_review.config import Config
from cubicacion_review.loader import cargar_libro

from .conftest import ENCABEZADO_ESTANDAR


def test_detecta_encabezado_y_filas(crear_libro):
    path = crear_libro(
        "cub.xlsx",
        {
            "Hoja1": [
                ENCABEZADO_ESTANDAR,
                ["001", "Excavación", "m3", 10, 5, 50],
                ["002", "Hormigón", "m3", 2, 100, 200],
            ]
        },
    )
    hojas = cargar_libro(path, Config())
    assert len(hojas) == 1
    hoja = hojas[0]
    assert hoja.encabezado_encontrado
    assert not hoja.columnas_faltantes
    assert len(hoja.filas) == 2
    assert hoja.filas[0].valores["codigo"] == "001"
    assert hoja.filas[0].fila_excel == 2


def test_columna_faltante_se_reporta(crear_libro):
    encabezado_incompleto = ["Código", "Descripción", "Unidad", "Cantidad", "Total"]
    path = crear_libro(
        "cub_incompleta.xlsx",
        {"Hoja1": [encabezado_incompleto, ["001", "Excavación", "m3", 10, 50]]},
    )
    hojas = cargar_libro(path, Config())
    hoja = hojas[0]
    assert hoja.encabezado_encontrado
    assert hoja.columnas_faltantes == ["precio_unitario"]


def test_ignora_filas_vacias(crear_libro):
    path = crear_libro(
        "cub_filas_vacias.xlsx",
        {
            "Hoja1": [
                ENCABEZADO_ESTANDAR,
                ["001", "Excavación", "m3", 10, 5, 50],
                [None, None, None, None, None, None],
                ["002", "Hormigón", "m3", 2, 100, 200],
            ]
        },
    )
    hojas = cargar_libro(path, Config())
    assert len(hojas[0].filas) == 2
