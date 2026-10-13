"""Contrato de los schemas de análisis: ``Scores`` ↔ ``Category`` y JSON."""

from __future__ import annotations

import pytest
from pydantic import TypeAdapter, ValidationError

from app.core.categories import Category
from app.schemas.analysis import AnalysisOut, IsoTimestamp, ModelMetadata, Scores

_TIMESTAMP = TypeAdapter(IsoTimestamp)


def test_iso_timestamp_accepts_canonical_utc() -> None:
    assert _TIMESTAMP.validate_python("2026-10-12T10:00:00Z") == "2026-10-12T10:00:00Z"


@pytest.mark.parametrize(
    "bad",
    [
        "2026-10-12T10:00:00.123456Z",
        "2026-10-12T10:00:00",
        "2026-10-12 10:00:00Z",
        "2026-10-12T10:00:00+00:00",
    ],
)
def test_iso_timestamp_rejects_non_canonical(bad: str) -> None:
    with pytest.raises(ValidationError):
        _TIMESTAMP.validate_python(bad)


def test_scores_fields_match_category_exactly() -> None:
    expected = {category.value for category in Category}
    actual = set(Scores.model_fields)
    missing = expected - actual
    extra = actual - expected
    assert not missing and not extra, (
        "Scores desincronizado con Category: "
        f"faltan={sorted(missing)} sobran={sorted(extra)}"
    )


def test_scores_field_order_follows_category() -> None:
    expected = [category.value for category in Category]
    assert list(Scores.model_fields) == expected


def test_scores_serializes_to_exact_pascal_case_keys() -> None:
    scores = Scores(
        NonDemented=0.1,
        VeryMildDemented=0.2,
        MildDemented=0.3,
        ModerateDemented=0.4,
    )
    dumped = scores.model_dump()
    assert list(dumped) == [category.value for category in Category]
    assert all(isinstance(value, float) for value in dumped.values())


def test_scores_forbids_unknown_keys() -> None:
    with pytest.raises(ValidationError):
        Scores(
            NonDemented=0.1,
            VeryMildDemented=0.2,
            MildDemented=0.3,
            ModerateDemented=0.4,
            Other=0.0,
        )


def test_analysis_out_rejects_category_outside_enum() -> None:
    with pytest.raises(ValidationError):
        AnalysisOut(
            id="an_x",
            category="NotAClass",
            created_at="2026-10-12T00:00:00Z",
            probability=0.5,
            scores=Scores(
                NonDemented=0.5,
                VeryMildDemented=0.2,
                MildDemented=0.2,
                ModerateDemented=0.1,
            ),
            model=ModelMetadata(name="m", version="v", dataset="d"),
        )
