"""Validación de la identidad del modelo (model card + metadata ONNX)."""

from __future__ import annotations

import json

import pytest

from app.core.categories import Category
from app.core.model_info import ModelInfoError, load_model_info

VALID_CARD = {
    "name": "yolov8n-cls",
    "version": "v0.1",
    "dataset": "Alzheimer MRI Dataset (Kaggle)",
    "trained_at": "2026-10-11",
}

VALID_NAMES = (
    "{0: 'MildDemented', 1: 'ModerateDemented', "
    "2: 'NonDemented', 3: 'VeryMildDemented'}"
)


class _Meta:
    def __init__(self, metadata: dict[str, str]) -> None:
        self.custom_metadata_map = metadata


class _Session:
    def __init__(self, metadata: dict[str, str]) -> None:
        self._metadata = metadata

    def get_modelmeta(self) -> _Meta:
        return _Meta(self._metadata)


def _write_card(tmp_path, **overrides) -> object:
    card = {**VALID_CARD, **overrides}
    path = tmp_path / "model_card.json"
    path.write_text(json.dumps(card), encoding="utf-8")
    return path


def _session(task: str = "classify", names: str | None = VALID_NAMES) -> _Session:
    metadata: dict[str, str] = {"task": task}
    if names is not None:
        metadata["names"] = names
    return _Session(metadata)


def test_loads_valid_card_and_metadata(tmp_path) -> None:
    info = load_model_info(_session(), _write_card(tmp_path))
    assert info.name == "yolov8n-cls"
    assert info.version == "v0.1"
    assert info.dataset == "Alzheimer MRI Dataset (Kaggle)"
    # Las clases conservan el orden de índice del modelo (crítico para el argmax).
    assert info.classes == [
        "MildDemented",
        "ModerateDemented",
        "NonDemented",
        "VeryMildDemented",
    ]
    assert sorted(info.classes) == sorted(c.value for c in Category)


def test_missing_card_raises(tmp_path) -> None:
    with pytest.raises(ModelInfoError):
        load_model_info(_session(), tmp_path / "model_card.json")


def test_card_without_required_field_raises(tmp_path) -> None:
    card = {k: v for k, v in VALID_CARD.items() if k != "dataset"}
    path = tmp_path / "model_card.json"
    path.write_text(json.dumps(card), encoding="utf-8")
    with pytest.raises(ModelInfoError):
        load_model_info(_session(), path)


def test_missing_names_raises(tmp_path) -> None:
    with pytest.raises(ModelInfoError):
        load_model_info(_session(names=None), _write_card(tmp_path))


def test_non_classify_task_raises(tmp_path) -> None:
    with pytest.raises(ModelInfoError):
        load_model_info(_session(task="detect"), _write_card(tmp_path))


def test_classes_not_matching_category_raises(tmp_path) -> None:
    names = "{0: 'MildDemented', 1: 'ModerateDemented', 2: 'NonDemented', 3: 'Other'}"
    with pytest.raises(ModelInfoError):
        load_model_info(_session(names=names), _write_card(tmp_path))


def test_names_not_a_mapping_raises(tmp_path) -> None:
    with pytest.raises(ModelInfoError):
        load_model_info(_session(names="['a', 'b']"), _write_card(tmp_path))
