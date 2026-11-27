"""Schemas públicos del historial de análisis (contrato v1)."""

from __future__ import annotations

import re
from typing import Annotated

from pydantic import AfterValidator, BaseModel, ConfigDict, Field

from app.core.categories import Category
from app.services.inference import DISCLAIMER

__all__ = [
    "Category",
    "IsoTimestamp",
    "ModelMetadata",
    "Scores",
    "AnalysisOut",
    "AnalysisSummary",
    "AnalysisList",
]

_ISO_UTC = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")


def _validate_iso_timestamp(value: str) -> str:
    if not _ISO_UTC.match(value):
        raise ValueError(
            "created_at debe ser ISO-8601 UTC con segundos (YYYY-MM-DDTHH:MM:SSZ)."
        )
    return value


IsoTimestamp = Annotated[str, AfterValidator(_validate_iso_timestamp)]
Probability = Annotated[float, Field(ge=0, le=1, allow_inf_nan=False, strict=True)]


class ModelMetadata(BaseModel):
    name: str
    version: str
    dataset: str


class Scores(BaseModel):
    """Puntuaciones por clase.

    Los nombres de los campos son, a propósito, los valores de ``Category`` en
    PascalCase (el resto del JSON es snake_case). ``extra="forbid"`` hace
    visible cualquier desincronización con el modelo en vez de ignorarla en
    silencio. El orden de los campos sigue el del enum para que el JSON sea
    estable.
    """

    model_config = ConfigDict(extra="forbid")

    NonDemented: Probability
    VeryMildDemented: Probability
    MildDemented: Probability
    ModerateDemented: Probability


class AnalysisOut(BaseModel):
    id: str
    category: Category
    created_at: IsoTimestamp
    display_name: str | None = None
    probability: Probability
    scores: Scores
    is_demo: bool = False
    has_image: bool = False
    has_gradcam: bool = False
    model: ModelMetadata
    disclaimer: str = DISCLAIMER


class AnalysisSummary(BaseModel):
    id: str
    category: Category
    created_at: IsoTimestamp
    display_name: str | None = None
    probability: Probability
    scores: Scores
    is_demo: bool = False
    has_image: bool = False
    has_gradcam: bool = False
    model_name: str
    model_version: str  # formato "name@version"
    model_dataset: str


class AnalysisList(BaseModel):
    items: list[AnalysisSummary]
    total: int
    limit: int
    offset: int


class AnalysisPreview(BaseModel):
    preview_id: str
    category: Category
    created_at: IsoTimestamp
    expires_at: IsoTimestamp
    probability: Probability
    scores: Scores
    model: ModelMetadata
    save_proof: str
    # PNG (base64) del mapa (CAM desde el .onnx) de la clase predicha. La
    # previsualización no persiste nada; al confirmar, el backend guarda el PNG
    # en Storage y lo vincula al análisis (columnas grad_cam_*).
    gradcam_png: str | None = None
    disclaimer: str = DISCLAIMER


class SaveAnalysisRequest(BaseModel):
    save_proof: str = Field(min_length=1, max_length=8192)
    display_name: str | None = None
