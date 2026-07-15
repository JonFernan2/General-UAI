from cubicacion_review.checks import revisar_libro
from cubicacion_review.config import Config
from cubicacion_review.loader import cargar_libro

from .conftest import ENCABEZADO_ESTANDAR


def test_detecta_error_aritmetico(crear_libro):
    path = crear_libro(
        "cub.xlsx",
        {
            "Hoja1": [
                ENCABEZADO_ESTANDAR,
                ["001", "Excavación", "m3", 10, 5, 999],  # debería ser 50
            ]
        },
    )
    hojas = cargar_libro(path, Config())
    issues = revisar_libro(hojas, Config())
    aritmeticos = [i for i in issues if i.categoria == "aritmetica"]
    assert len(aritmeticos) == 1
    assert aritmeticos[0].codigo == "001"
    assert aritmeticos[0].fila_excel == 2


def test_tolerancia_evita_falso_positivo(crear_libro):
    path = crear_libro(
        "cub.xlsx",
        {
            "Hoja1": [
                ENCABEZADO_ESTANDAR,
                ["001", "Excavación", "m3", 10, 5.001, 50],  # redondeo mínimo
            ]
        },
    )
    hojas = cargar_libro(path, Config())
    issues = revisar_libro(hojas, Config())
    assert not [i for i in issues if i.categoria == "aritmetica"]


def test_detecta_codigo_duplicado(crear_libro):
    path = crear_libro(
        "cub.xlsx",
        {
            "Hoja1": [
                ENCABEZADO_ESTANDAR,
                ["001", "Excavación", "m3", 10, 5, 50],
                ["001", "Excavación (repetido)", "m3", 3, 5, 15],
            ]
        },
    )
    hojas = cargar_libro(path, Config())
    issues = revisar_libro(hojas, Config())
    duplicados = [i for i in issues if i.categoria == "duplicado"]
    assert len(duplicados) == 1
    assert duplicados[0].codigo == "001"


def test_detecta_columna_faltante_como_error_estructura(crear_libro):
    encabezado_incompleto = ["Código", "Descripción", "Unidad", "Cantidad", "Total"]
    path = crear_libro(
        "cub.xlsx",
        {"Hoja1": [encabezado_incompleto, ["001", "Excavación", "m3", 10, 50]]},
    )
    hojas = cargar_libro(path, Config())
    issues = revisar_libro(hojas, Config())
    estructura = [i for i in issues if i.categoria == "estructura"]
    assert len(estructura) == 1
    assert "precio_unitario" in estructura[0].mensaje


def test_detecta_partidas_faltantes_y_no_presupuestadas(crear_libro):
    path_cub = crear_libro(
        "cub.xlsx",
        {
            "Hoja1": [
                ENCABEZADO_ESTANDAR,
                ["001", "Excavación", "m3", 10, 5, 50],
                ["003", "Partida extra", "m3", 1, 1, 1],
            ]
        },
    )
    path_ref = crear_libro(
        "ref.xlsx",
        {
            "Hoja1": [
                ENCABEZADO_ESTANDAR,
                ["001", "Excavación", "m3", 10, 5, 50],
                ["002", "Hormigón", "m3", 2, 100, 200],
            ]
        },
    )
    hojas_cub = cargar_libro(path_cub, Config())
    hojas_ref = cargar_libro(path_ref, Config())
    issues = revisar_libro(hojas_cub, Config(), hojas_ref)

    faltantes = [i for i in issues if i.categoria == "faltante"]
    extras = [i for i in issues if i.categoria == "no_presupuestado"]

    assert {i.codigo for i in faltantes} == {"002"}
    assert {i.codigo for i in extras} == {"003"}
