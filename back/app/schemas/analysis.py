"""Schemas públicos del historial de análisis (contrato v1)."""

from __future__ import annotations

from pydantic import BaseModel

from app.services.inference import DISCLAIMER


class ModelMetadata(BaseModel):
    name: str
    version: str
    dataset: str


class AnalysisOut(BaseModel):
    id: str
    category: str
    created_at: str
    display_name: str | None = None
    probability: float
    scores: dict[str, float]
    is_demo: bool = False
    model: ModelMetadata
    disclaimer: str = DISCLAIMER


class AnalysisList(BaseModel):
    items: list[AnalysisOut]
    total: int
    limit: int
    offset: int