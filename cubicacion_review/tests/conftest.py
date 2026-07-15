import openpyxl
import pytest


def _crear_libro(path, hojas: dict[str, list[list]]):
    wb = openpyxl.Workbook()
    wb.remove(wb.active)
    for nombre, filas in hojas.items():
        ws = wb.create_sheet(nombre)
        for fila in filas:
            ws.append(fila)
    wb.save(path)
    return path


@pytest.fixture
def crear_libro(tmp_path):
    def _fabrica(nombre_archivo: str, hojas: dict[str, list[list]]):
        return str(_crear_libro(tmp_path / nombre_archivo, hojas))

    return _fabrica


ENCABEZADO_ESTANDAR = ["Código", "Descripción", "Unidad", "Cantidad", "Precio Unitario", "Total"]
