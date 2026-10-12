"""Rutas de análisis (crear, historial paginado y detalle).

Todas requieren autenticación. El ``account_id`` se deriva exclusivamente del
``sub`` verificado del JWT; nunca del cliente. La inferencia real se ejecuta
solo si el modelo está cargado; si no, ``POST /analyses`` responde 503.
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, Query, UploadFile

from app.core.config import Settings
from app.core.errors import ApiException
from app.core.security import AuthenticatedUser
from app.routes.dependencies import get_app_settings, get_current_user, get_services
from app.schemas.analysis import AnalysisList, AnalysisOut, ModelMetadata
from app.services.analyses import AnalysisRecord
from app.services.images import validate_image
from app.services.inference import DISCLAIMER, InferenceError
from app.services.container import Services

router = APIRouter(prefix="/analyses", tags=["analyses"])

MAX_LIMIT = 100


async def _read_upload(file: UploadFile, max_bytes: int) -> bytes:
    data = bytearray()
    while True:
        chunk = await file.read(8192)
        if not chunk:
            break
        data.extend(chunk)
        if len(data) > max_bytes:
            raise ApiException(
                413,
                "too_large",
                f"El archivo excede el tamaño máximo de {max_bytes} bytes.",
            )
    return bytes(data)


def _to_out(record: AnalysisRecord, settings: Settings) -> AnalysisOut:
    return AnalysisOut(
        id=record.id,
        category=record.category,
        created_at=record.created_at,
        display_name=record.display_name,
        probability=record.probability,
        scores=record.scores,
        is_demo=record.is_demo,
        model=ModelMetadata(
            name=record.model_name,
            version=record.model_version,
            dataset=settings.model_dataset,
        ),
        disclaimer=DISCLAIMER,
    )


@router.post("", response_model=AnalysisOut, status_code=201)
async def create_analysis(
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    services: Annotated[Services, Depends(get_services)],
    settings: Annotated[Settings, Depends(get_app_settings)],
    file: UploadFile = File(..., description="Imagen JPG/JPEG o PNG, máx. 10 MB"),
    display_name: str | None = Form(default=None, max_length=120),
) -> AnalysisOut:
    data = await _read_upload(file, settings.max_image_bytes)
    image = validate_image(
        data,
        max_bytes=settings.max_image_bytes,
        max_dimension=settings.max_image_dimension,
    )

    if not services.inference.ready:
        raise ApiException(
            503,
            "model_unavailable",
            "El modelo de clasificación no está disponible en este momento.",
        )

    try:
        scores = services.inference.analyze(image)
    except InferenceError as exc:
        raise ApiException(503, "model_unavailable", str(exc)) from exc

    category, probability = max(scores.items(), key=lambda item: item[1])

    record = AnalysisRecord(
        account_id=str(user.id),
        category=category,
        probability=round(float(probability), 6),
        scores=scores,
        display_name=display_name,
        model_name=services.inference.model_name or settings.model_name,
        model_version=services.inference.model_version or settings.model_version,
    )
    persisted = services.analyses.create(record)
    return _to_out(persisted, settings)


@router.get("", response_model=AnalysisList)
def list_analyses(
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    services: Annotated[Services, Depends(get_services)],
    settings: Annotated[Settings, Depends(get_app_settings)],
    limit: Annotated[int, Query(ge=1, le=MAX_LIMIT)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
) -> AnalysisList:
    items, total = services.analyses.list_by_account(
        str(user.id), limit=limit, offset=offset
    )
    return AnalysisList(
        items=[_to_out(item, settings) for item in items],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.get("/{analysis_id}", response_model=AnalysisOut)
def get_analysis(
    analysis_id: str,
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    services: Annotated[Services, Depends(get_services)],
    settings: Annotated[Settings, Depends(get_app_settings)],
) -> AnalysisOut:
    record = services.analyses.get_by_account(analysis_id, str(user.id))
    if record is None:
        raise ApiException(404, "not_found", "Análisis no encontrado.")
    return _to_out(record, settings)