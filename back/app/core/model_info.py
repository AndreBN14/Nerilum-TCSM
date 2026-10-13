"""Identidad del modelo de inferencia (fuente única de verdad).

Los metadatos públicos del modelo (nombre, versión, dataset) se leen de
``model_card.json``; las clases, de la metadata ONNX (``names``) y se validan
contra el enum :class:`Category`. Si algo falta o no coincide, el modelo queda
no disponible; nunca se inventan metadatos.
"""

from __future__ import annotations

import ast
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from app.core.categories import Category


class ModelInfoError(Exception):
    """El model card o la metadata ONNX no permiten construir un ``ModelInfo``."""


@dataclass(frozen=True)
class ModelInfo:
    name: str
    version: str
    dataset: str
    classes: list[str]


def _read_card(card_path: Path) -> dict[str, Any]:
    if not card_path.exists():
        raise ModelInfoError(f"No existe el model card: {card_path}")
    try:
        data = json.loads(card_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ModelInfoError(f"No se pudo leer el model card: {exc}") from exc
    if not isinstance(data, dict):
        raise ModelInfoError("El model card no es un objeto JSON.")
    for key in ("name", "version", "dataset"):
        value = data.get(key)
        if not isinstance(value, str) or not value.strip():
            raise ModelInfoError(f"El model card no declara '{key}'.")
    return data


def _read_names(metadata: dict[str, str]) -> list[str]:
    raw = metadata.get("names")
    if not raw:
        raise ModelInfoError("El modelo no declara 'names' en su metadata ONNX.")
    try:
        parsed = ast.literal_eval(raw)
    except (ValueError, SyntaxError) as exc:
        raise ModelInfoError(
            "No se pudo interpretar 'names' de la metadata ONNX."
        ) from exc
    if not isinstance(parsed, dict):
        raise ModelInfoError("'names' debe ser un dict {índice: etiqueta}.")
    try:
        return [str(parsed[key]) for key in sorted(parsed, key=int)]
    except (TypeError, ValueError) as exc:
        raise ModelInfoError("Las claves de 'names' no son índices válidos.") from exc


def load_model_info(session: Any, card_path: Path) -> ModelInfo:
    """Construye el ``ModelInfo`` validando el card y la metadata ONNX.

    Lanza :class:`ModelInfoError` con un motivo claro si:
    - falta o es inválido el model card;
    - falta ``names`` o no se puede interpretar;
    - la tarea ONNX no es ``classify``;
    - las clases no coinciden con :class:`Category`.
    """

    card = _read_card(Path(card_path))

    metadata = session.get_modelmeta().custom_metadata_map
    if metadata.get("task") != "classify":
        raise ModelInfoError(
            f"La tarea del modelo no es 'classify': {metadata.get('task')!r}."
        )

    classes = _read_names(metadata)
    expected = [category.value for category in Category]
    if sorted(classes) != sorted(expected):
        raise ModelInfoError(
            "Las clases del modelo no coinciden con Category: "
            f"{classes} != {expected}."
        )

    return ModelInfo(
        name=str(card["name"]),
        version=str(card["version"]),
        dataset=str(card["dataset"]),
        classes=classes,
    )
