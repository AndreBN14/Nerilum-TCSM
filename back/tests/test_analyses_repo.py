"""Prueba que un fallo de guardado responde 500 internal_error, no 409."""

from __future__ import annotations

import json
import re
import sqlite3

import pytest

from app.core.categories import Category
from app.core.errors import ApiException
from app.services import analyses as analyses_module
from app.services.analyses import AnalysisRecord, SqliteAnalysisRepository

CANONICAL_TS = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")


def _record(record_id: str = "an_fijo") -> AnalysisRecord:
    return AnalysisRecord(
        id=record_id,
        account_id="a",
        category="NonDemented",
        probability=0.9,
        scores={"NonDemented": 0.9},
        model_name="yolov8n-cls",
        model_version="v0.1",
        model_dataset="Alzheimer MRI Dataset (Kaggle)",
    )


def _full_record(record_id: str, created_at: str, account: str = "a") -> AnalysisRecord:
    return AnalysisRecord(
        id=record_id,
        account_id=account,
        category="NonDemented",
        probability=0.25,
        scores={category.value: 0.25 for category in Category},
        model_name="yolov8n-cls",
        model_version="v0.1",
        model_dataset="Alzheimer MRI Dataset (Kaggle)",
        created_at=created_at,
    )


def test_create_raises_internal_error_on_id_collision(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(analyses_module, "_new_id", lambda: "an_fijo")
    repo = SqliteAnalysisRepository(tmp_path / "n.db")

    repo.create(_record())

    with pytest.raises(ApiException) as exc:
        repo.create(_record())

    assert exc.value.status_code == 500
    assert exc.value.code == "internal_error"


def test_model_metadata_round_trips_per_row(tmp_path) -> None:
    repo = SqliteAnalysisRepository(tmp_path / "n.db")
    repo.create(_record())

    stored = repo.get_by_account("an_fijo", "a")
    assert stored is not None
    assert stored.model_name == "yolov8n-cls"
    assert stored.model_version == "v0.1"
    assert stored.model_dataset == "Alzheimer MRI Dataset (Kaggle)"


def test_created_at_is_canonical_utc_without_microseconds(tmp_path) -> None:
    repo = SqliteAnalysisRepository(tmp_path / "c.db")
    stored = repo.create(_record())

    assert CANONICAL_TS.match(stored.created_at)


def test_list_orders_by_created_at_desc_then_id_desc(tmp_path) -> None:
    repo = SqliteAnalysisRepository(tmp_path / "o.db")
    repo.create(_full_record("an_a", "2026-10-12T10:00:00Z"))
    repo.create(_full_record("an_b", "2026-10-12T10:00:00Z"))
    repo.create(_full_record("an_c", "2026-10-12T11:00:00Z"))

    items, total = repo.list_by_account("a", limit=10, offset=0)

    assert total == 3
    assert [item.id for item in items] == ["an_c", "an_b", "an_a"]


def test_legacy_microsecond_created_at_is_normalized_on_read(tmp_path) -> None:
    db = tmp_path / "legacy.db"
    repo = SqliteAnalysisRepository(db)
    with sqlite3.connect(db) as conn:
        conn.execute(
            """
            INSERT INTO analyses (
                id, account_id, category, probability, scores_json,
                display_name, is_demo, model_name, model_version,
                model_dataset, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                "an_legacy",
                "a",
                "NonDemented",
                0.25,
                json.dumps({category.value: 0.25 for category in Category}),
                None,
                0,
                "yolov8n-cls",
                "v0.1",
                "Alzheimer MRI Dataset (Kaggle)",
                "2026-10-12T10:00:00.123456Z",
            ),
        )

    stored = repo.get_by_account("an_legacy", "a")

    assert stored is not None
    assert stored.created_at == "2026-10-12T10:00:00Z"
