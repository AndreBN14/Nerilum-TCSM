"""Rutas de análisis (crear, historial paginado y detalle).

Todas requieren autenticación. El ``account_id`` se deriva exclusivamente del
``sub`` verificado del JWT; nunca del cliente. La inferencia real se ejecuta
solo si el modelo está cargado; si no, ``POST /analyses`` responde 503.
"""

from __future__ import annotations

import logging
import unicodedata
from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, Header, Query, UploadFile, status
from pydantic import ValidationError
from starlette.concurrency import run_in_threadpool

from app.core.config import Settings
from app.core.errors import ApiException
from app.core.history_sort import HistorySort
from app.core.idempotency import analysis_request_hash
from app.core.security import AuthenticatedUser
from app.routes.dependencies import get_app_settings, get_current_user, get_services
from app.schemas.analysis import (
    AnalysisList,
    AnalysisOut,
    AnalysisSummary,
    Category,
    ModelMetadata,
    Scores,
)
from app.schemas.error import ErrorResponse
from app.schemas.error import COMMON_ERRORS
from app.schemas.prediction import AnalysisPrediction
from app.services.analyses import AnalysisRecord
from app.services.images import too_large_error, validate_image
from app.services.inference import DISCLAIMER, InferenceError
from app.services.container import Services

logger = logging.getLogger("nerilum")

router = APIRouter(prefix="/analyses", tags=["analyses"])

MAX_LIMIT = 100
MAX_DISPLAY_NAME_LENGTH = 120


def _clean_display_name(value: str | None) -> str | None:
    """Normaliza el nombre opcional del análisis.

    Recorta los espacios; un valor vacío (o solo espacios) se guarda como
    ``None``; rechaza caracteres de control y limita a 120 caracteres ya
    recortados. Los valores inválidos responden 422 con el mismo código que el
    resto de validaciones del contrato.
    """

    if value is None:
        return None
    cleaned = value.strip()
    if not cleaned:
        return None
    if any(unicodedata.category(char) == "Cc" for char in cleaned):
        raise ApiException(
            422, "validation_error", "display_name no admite caracteres de control."
        )
    if len(cleaned) > MAX_DISPLAY_NAME_LENGTH:
        raise ApiException(
            422,
            "validation_error",
            f"display_name no puede superar {MAX_DISPLAY_NAME_LENGTH} caracteres.",
        )
    return cleaned


async def _read_upload(file: UploadFile, max_bytes: int) -> bytes:
    data = bytearray()
    while True:
        chunk = await file.read(8192)
        if not chunk:
            break
        data.extend(chunk)
        if len(data) > max_bytes:
            raise too_large_error(max_bytes)
    return bytes(data)


def _to_out(record: AnalysisRecord) -> AnalysisOut:
    try:
        category = Category(record.category)
        scores = Scores(**record.scores)
        return AnalysisOut(
            id=record.id,
            category=category,
            created_at=record.created_at,
            display_name=record.display_name,
            probability=record.probability,
            scores=scores,
            is_demo=record.is_demo,
            model=ModelMetadata(
                name=record.model_name,
                version=record.model_version,
                dataset=record.model_dataset,
            ),
            disclaimer=DISCLAIMER,
        )
    except (ValidationError, ValueError) as exc:
        # Fila inválida (p. ej. categoría fuera del enum): fallo visible, pero
        # el log solo registra el tipo de error y el id del análisis, nunca
        # datos de la cuenta ni el contenido de la fila.
        logger.warning(
            "Análisis con datos inválidos (id=%s, error=%s)",
            record.id,
            type(exc).__name__,
        )
        raise ApiException(
            500, "internal_error", "Error interno del servidor."
        ) from exc

def _summary_from_record(record: AnalysisRecord) -> AnalysisSummary:
    try:
        category = Category(record.category)
        scores = Scores(**record.scores)
    except (ValidationError, ValueError) as exc:
        logger.warning(
            "Análisis con datos inválidos (id=%s, error=%s)",
            record.id,
            type(exc).__name__,
        )
        raise ApiException(500, "internal_error", "Error interno del servidor.") from exc

    return AnalysisSummary(
        id=record.id,
        category=category,
        created_at=record.created_at,
        display_name=record.display_name,
        probability=record.probability,
        scores=scores,
        is_demo=record.is_demo,
        model_name=record.model_name,
        model_version=f"{record.model_name}@{record.model_version}",
        model_dataset=record.model_dataset,
    )


@router.post("", response_model=AnalysisOut, status_code=201, responses={
    **COMMON_ERRORS,
    409: {"model": ErrorResponse, "description": "Clave reutilizada con otro contenido."},
})
async def create_analysis(
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    services: Annotated[Services, Depends(get_services)],
    settings: Annotated[Settings, Depends(get_app_settings)],
    idempotency_key: Annotated[str | None, Header(
        alias="Idempotency-Key", min_length=1, max_length=128,
        pattern=r"^[A-Za-z0-9._:-]+$",
        description="Clave única por operación y usuario. Conservarla al reintentar.",
    )] = None,
    file: UploadFile = File(..., description="Imagen JPG/JPEG o PNG, máx. 10 MB"),
    display_name: str | None = Form(
        default=None,
        description="Nombre opcional (máx. 120 caracteres; se recorta).",
    ),
) -> AnalysisOut:
    display_name = _clean_display_name(display_name)

    data = await _read_upload(file, settings.max_image_bytes)
    request_hash = None
    if idempotency_key is not None:
        request_hash = await run_in_threadpool(analysis_request_hash, data, display_name)
        previous = await run_in_threadpool(
            services.analyses.get_by_idempotency_key,
            str(user.id), idempotency_key, request_hash,
        )
        if previous is not None:
            # Recuperar una operación completada incluso si el modelo ahora no está disponible.
            return _to_out(previous)
    try:
        image = await run_in_threadpool(
            validate_image,
            data,
            max_bytes=settings.max_image_bytes,
            max_dimension=settings.max_image_dimension,
            max_pixels=settings.max_image_pixels,
        )
    except ApiException:
        raise
    except Exception:  # pragma: no cover - no esperado
        raise ApiException(400, "invalid_image", "El archivo no se puede decodificar como imagen.")

    if not services.inference.ready:
        raise ApiException(
            503,
            "model_unavailable",
            "El modelo de clasificación no está disponible en este momento.",
        )

    # ONNXRuntime y los repositorios son síncronos: no bloquear el event loop.
    try:
        scores = await run_in_threadpool(services.inference.analyze, image)
    except InferenceError as exc:
        raise ApiException(503, "model_unavailable", str(exc)) from exc

    try:
        prediction = AnalysisPrediction.from_scores(scores)
    except ValidationError as exc:
        # No registrar las puntuaciones ni el contenido de la salida fallida.
        logger.warning("Salida de clasificación inválida (error=%s)", type(exc).__name__)
        raise ApiException(
            503, "model_unavailable",
            "El modelo devolvió un resultado inválido. No se guardó ningún análisis.",
        ) from exc

    model_info = services.inference.model_info
    if model_info is None:
        raise ApiException(
            503,
            "model_unavailable",
            "El modelo de clasificación no está disponible en este momento.",
        )

    record = AnalysisRecord(
        account_id=str(user.id),
        category=prediction.category.value,
        probability=prediction.probability,
        scores=prediction.scores.model_dump(),
        display_name=display_name,
        model_name=model_info.name,
        model_version=model_info.version,
        model_dataset=model_info.dataset,
        idempotency_key=idempotency_key,
        request_hash=request_hash,
    )
    # Validar también el registro completo antes de cualquier INSERT.
    _to_out(record)
    persisted = await run_in_threadpool(services.analyses.create, record)
    return _to_out(persisted)


@router.get("", response_model=AnalysisList, responses=COMMON_ERRORS)
def list_analyses(
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    services: Annotated[Services, Depends(get_services)],
    limit: Annotated[int, Query(ge=1, le=MAX_LIMIT)] = 50,
    offset: Annotated[int, Query(ge=0)] = 0,
    sort: Annotated[HistorySort, Query(
        description="newest, oldest, nameAZ o probability; se aplica antes de paginar."
    )] = HistorySort.newest,
) -> AnalysisList:
    items, total = services.analyses.list_by_account(
        str(user.id), limit=limit, offset=offset, sort=sort
    )
    return AnalysisList(
        items=[_summary_from_record(item) for item in items],
        total=total,
        limit=limit,
        offset=offset,
    )


@router.get("/{analysis_id}", response_model=AnalysisOut, responses=COMMON_ERRORS)
def get_analysis(
    analysis_id: str,
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    services: Annotated[Services, Depends(get_services)],
) -> AnalysisOut:
    record = services.analyses.get_by_account(analysis_id, str(user.id))
    if record is None:
        raise ApiException(404, "not_found", "Análisis no encontrado.")
    return _to_out(record)
