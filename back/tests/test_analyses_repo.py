"""Prueba que un fallo de guardado responde 500 internal_error, no 409."""

from __future__ import annotations

import pytest

from app.core.errors import ApiException
from app.services import analyses as analyses_module
from app.services.analyses import AnalysisRecord, SqliteAnalysisRepository


def test_create_raises_internal_error_on_id_collision(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(analyses_module, "_new_id", lambda: "an_fijo")
    repo = SqliteAnalysisRepository(tmp_path / "n.db")

    first = AnalysisRecord(
        id="an_fijo",
        account_id="a",
        category="NonDemented",
        probability=0.9,
        scores={"NonDemented": 0.9},
    )
    repo.create(first)

    second = AnalysisRecord(
        id="an_fijo",
        account_id="a",
        category="NonDemented",
        probability=0.9,
        scores={"NonDemented": 0.9},
    )
    with pytest.raises(ApiException) as exc:
        repo.create(second)

    assert exc.value.status_code == 500
    assert exc.value.code == "internal_error"
