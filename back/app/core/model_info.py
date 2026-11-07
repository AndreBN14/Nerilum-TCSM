"""Identidad del modelo de inferencia (fuente única de verdad).

Los metadatos públicos del modelo (nombre, versión, dataset, task y clases) se
leen de ``model_card.json``. Si el artefacto ONNX incluye ``task`` y ``names``
en su custom_metadata, se usan y se validan contra el card; si no los trae
(modelos exportados sin esos campos), el card actúa como fuente completa.
Si algo falta o no coincide, el modelo queda no disponible; nunca se inventan
metadatos.
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


def _read_names_from_onnx(metadata: dict[str, str]) -> list[str] | None:
    """Lee ``names`` de la metadata ONNX. Devuelve ``None`` si no está presente."""
    raw = metadata.get("names")
    if not raw:
        return None
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


def _read_classes_from_card(card: dict[str, Any]) -> list[str]:
    """Lee ``classes`` del model card como lista de strings."""
    raw = card.get("classes")
    if not raw:
        raise ModelInfoError(
            "El modelo no trae 'names' en su metadata ONNX y el model card "
            "tampoco declara 'classes'. Agrégalos al model_card.json."
        )
    if not isinstance(raw, list) or not all(isinstance(c, str) for c in raw):
        raise ModelInfoError("'classes' en el model card debe ser una lista de strings.")
    if not raw:
        raise ModelInfoError("'classes' en el model card está vacío.")
    return raw


def load_model_info(session: Any, card_path: Path) -> ModelInfo:
    """Construye el ``ModelInfo`` validando el card y la metadata ONNX.

    - ``task`` y ``names`` se leen del ONNX si están presentes; si no, se
      leen de ``model_card.json`` (campos ``task`` y ``classes``).
    - Las clases obtenidas siempre se validan contra :class:`Category`.
    - Lanza :class:`ModelInfoError` con un motivo claro ante cualquier
      inconsistencia o dato faltante.
    """

    card = _read_card(Path(card_path))
    metadata = session.get_modelmeta().custom_metadata_map

    # -- Validar tarea (classify) ----------------------------------------
    onnx_task = metadata.get("task")
    if onnx_task:
        # El ONNX declara la tarea: debe ser "classify".
        if onnx_task != "classify":
            raise ModelInfoError(
                f"La tarea del modelo no es 'classify': {onnx_task!r}."
            )
    else:
        # Sin tarea en el ONNX: leer del card (opcional, se asume classify).
        card_task = card.get("task", "classify")
        if card_task != "classify":
            raise ModelInfoError(
                f"El model card declara task={card_task!r}; se esperaba 'classify'."
            )

    # -- Obtener clases --------------------------------------------------
    onnx_classes = _read_names_from_onnx(metadata)
    if onnx_classes is not None:
        classes = onnx_classes
    else:
        classes = _read_classes_from_card(card)

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
