"""Clases de diagnóstico soportadas por el modelo.

Fuente única de las clases: el enum ``Category``. Tanto la validación de la
metadata ONNX como los schemas HTTP lo derivan de aquí.
"""

from enum import Enum


class Category(str, Enum):
    NonDemented = "NonDemented"
    VeryMildDemented = "VeryMildDemented"
    MildDemented = "MildDemented"
    ModerateDemented = "ModerateDemented"
