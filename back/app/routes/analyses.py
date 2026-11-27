"""Rutas de análisis (crear, historial paginado y detalle).

Todas requieren autenticación. El ``account_id`` se deriva exclusivamente del
``sub`` verificado del JWT; nunca del cliente. La inferencia real se ejecuta
solo si el modelo está cargado; si no, ``POST /analyses`` responde 503.
"""

from __future__ import annotations

import base64
import logging
import hashlib
import unicodedata
from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, File, Form, Header, Query, Response, UploadFile, status
from pydantic import ValidationError
from starlette.concurrency import run_in_threadpool

from app.core.config import Settings
from app.core.analysis_proof import issue_proof, require_secret, save_request_hash, verify_proof
from app.core.errors import ApiException
from app.core.history_sort import HistorySort
from app.core.idempotency import analysis_request_hash
from app.core.security import AuthenticatedUser
from app.routes.dependencies import get_app_settings, get_current_user, get_services
from app.schemas.analysis import (
    AnalysisList,
    AnalysisOut,
    AnalysisSummary,
    AnalysisPreview,
    Category,
    ModelMetadata,
    SaveAnalysisRequest,
    Scores,
)
from app.schemas.error import ErrorResponse
from app.schemas.error import COMMON_ERRORS
from app.schemas.prediction import AnalysisPrediction
from app.services.analyses import AnalysisRecord
from app.services.images import JPEG_MAGIC, PNG_MAGIC, too_large_error, validate_image
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
            has_image=record.image_path is not None,
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
        has_image=record.image_path is not None,
        model_name=record.model_name,
        model_version=f"{record.model_name}@{record.model_version}",
        model_dataset=record.model_dataset,
    )


async def _predict(data: bytes, services: Services, settings: Settings
                   ) -> tuple[AnalysisPrediction, ModelMetadata, object]:
    try:
        image = await run_in_threadpool(
            validate_image, data, max_bytes=settings.max_image_bytes,
            max_dimension=settings.max_image_dimension, max_pixels=settings.max_image_pixels,
        )
    except ApiException:
        raise
    except Exception:
        raise ApiException(400, "invalid_image", "El archivo no se puede decodificar como imagen.") from None

    if not services.inference.ready:
        raise ApiException(503, "model_unavailable", "El modelo de clasificación no está disponible en este momento.")
    try:
        scores = await run_in_threadpool(services.inference.analyze, image)
    except InferenceError as exc:
        raise ApiException(503, "model_unavailable", str(exc)) from exc
    try:
        prediction = AnalysisPrediction.from_scores(scores)
    except ValidationError as exc:
        logger.warning("Salida de clasificación inválida (error=%s)", type(exc).__name__)
        raise ApiException(503, "model_unavailable",
            "El modelo devolvió un resultado inválido. No se guardó ningún análisis.") from exc
    info = services.inference.model_info
    if info is None:
        raise ApiException(503, "model_unavailable", "El modelo de clasificación no está disponible en este momento.")
    try:
        model = ModelMetadata(name=info.name, version=info.version, dataset=info.dataset)
    except ValidationError as exc:
        logger.warning("Metadatos de modelo inválidos (error=%s)", type(exc).__name__)
        raise ApiException(500, "internal_error", "Error interno del servidor.") from exc
    return prediction, model, image


async def _gradcam_base64(
    services: Services, image: object, prediction: AnalysisPrediction
) -> str | None:
    """Genera el mapa de explicabilidad (Grad-CAM o CAM) si está disponible.

    El mapa se deriva siempre del ``.onnx`` de clasificación (CAM), sin
    ``torch`` ni ``best.pt``. Un fallo del explicador nunca tumba la
    clasificación: se registra el tipo de error (sin datos de la imagen) y la
    respuesta viaja con ``gradcam_png=None``.
    """

    explainer = services.explainer
    info = services.inference.model_info
    if explainer is None or not explainer.ready or info is None:
        return None
    try:
        # El orden de ``classes`` es el orden de salida del clasificador.
        index = info.classes.index(prediction.category.value)
        png = await run_in_threadpool(explainer.render, image, index)
        return base64.b64encode(png).decode("ascii")
    except Exception as exc:
        logger.warning("Grad-CAM no disponible (error=%s)", type(exc).__name__)
        return None


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
    prediction, model_info, _image = await _predict(data, services, settings)

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
    if services.image_storage is not None:
        mime = "image/jpeg" if data.startswith(JPEG_MAGIC) else "image/png"
        extension = "jpg" if mime == "image/jpeg" else "png"
        record.image_path = f"{user.id}/{record.id}.{extension}"
        record.image_sha256 = hashlib.sha256(data).hexdigest()
        record.image_mime_type = mime
        record.fixed_id = True
        await run_in_threadpool(services.image_storage.put, record.image_path, data, mime)
    # Validar también el registro completo antes de cualquier INSERT.
    _to_out(record)
    persisted = await run_in_threadpool(services.analyses.create, record)
    return _to_out(persisted)


@router.post("/preview", response_model=AnalysisPreview, responses=COMMON_ERRORS)
async def preview_analysis(
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    services: Annotated[Services, Depends(get_services)],
    settings: Annotated[Settings, Depends(get_app_settings)],
    file: UploadFile = File(..., description="Imagen JPG/JPEG/PNG de hasta 10 MB"),
) -> AnalysisPreview:
    require_secret(settings.analysis_proof_secret)
    data = await _read_upload(file, settings.max_image_bytes)
    prediction, model, image = await _predict(data, services, settings)
    gradcam = await _gradcam_base64(services, image, prediction)
    payload, proof = issue_proof(user_id=str(user.id), prediction=prediction,
                                 model=model, secret=settings.analysis_proof_secret,
                                 image_sha256=hashlib.sha256(data).hexdigest())
    return AnalysisPreview(
        preview_id=payload["preview_id"], category=prediction.category,
        probability=prediction.probability, scores=prediction.scores,
        created_at=payload["created_at"], expires_at=payload["expires_at"],
        save_proof=proof, model=model, gradcam_png=gradcam,
    )


@router.post("/save", response_model=AnalysisOut, status_code=201, responses={
    **COMMON_ERRORS,
    409: {"model": ErrorResponse, "description": "Comprobante ya guardado con otro nombre."},
})
async def save_analysis(
    payload: SaveAnalysisRequest,
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    services: Annotated[Services, Depends(get_services)],
    settings: Annotated[Settings, Depends(get_app_settings)],
    response: Response,
) -> AnalysisOut:
    name = _clean_display_name(payload.display_name)
    receipt = verify_proof(payload.save_proof, user_id=str(user.id),
                           secret=settings.analysis_proof_secret)
    operation_id = receipt["preview_id"]
    request_hash = save_request_hash(operation_id, name)
    existing = await run_in_threadpool(services.analyses.get_by_idempotency_key,
        str(user.id), operation_id, request_hash)
    if existing is not None:
        response.status_code = 200
        return _to_out(existing)
    if datetime.now(timezone.utc) > receipt["expiration"]:
        raise ApiException(422, "validation_error", "La previsualización expiró. Analiza la imagen de nuevo.")

    prediction = receipt["prediction"]
    model = receipt["model_info"]
    record = AnalysisRecord(
        id=operation_id, account_id=str(user.id), category=prediction.category.value,
        probability=prediction.probability, scores=prediction.scores.model_dump(),
        display_name=name, created_at=receipt["created_at"],
        model_name=model.name, model_version=model.version, model_dataset=model.dataset,
        idempotency_key=operation_id, request_hash=request_hash,
        fixed_id=True,
    )
    _to_out(record)
    saved = await run_in_threadpool(services.analyses.create, record)
    if saved is not record:
        response.status_code = 200
    return _to_out(saved)


@router.post("/save-with-image", response_model=AnalysisOut, status_code=201, responses=COMMON_ERRORS)
async def save_analysis_with_image(
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    services: Annotated[Services, Depends(get_services)],
    settings: Annotated[Settings, Depends(get_app_settings)],
    response: Response,
    file: UploadFile = File(..., description="Imagen original JPG/JPEG/PNG"),
    save_proof: str = Form(...),
    display_name: str | None = Form(default=None),
) -> AnalysisOut:
    name = _clean_display_name(display_name)
    receipt = verify_proof(save_proof, user_id=str(user.id),
                           secret=settings.analysis_proof_secret)
    if receipt["v"] != 2:
        raise ApiException(422, "validation_error", "Vuelve a previsualizar la imagen antes de guardarla.")
    if services.image_storage is None:
        raise ApiException(503, "storage_unavailable", "El almacenamiento de imágenes no está configurado.")
    data = await _read_upload(file, settings.max_image_bytes)
    digest = hashlib.sha256(data).hexdigest()
    if digest != receipt["image_sha256"]:
        raise ApiException(422, "validation_error", "La imagen no corresponde al resultado previsualizado.")
    operation_id = receipt["preview_id"]
    request_hash = save_request_hash(operation_id, name, digest)
    existing = await run_in_threadpool(services.analyses.get_by_idempotency_key,
                                      str(user.id), operation_id, request_hash)
    if existing is not None:
        if existing.image_path is None:
            raise ApiException(409, "idempotency_conflict", "El resultado existente no tiene imagen asociada.")
        try:
            stored_image = await run_in_threadpool(services.image_storage.get, existing.image_path)
        except ApiException as exc:
            if exc.status_code != 404:
                raise
            await run_in_threadpool(services.image_storage.put, existing.image_path,
                                    data, existing.image_mime_type)
            stored_image = data
        if hashlib.sha256(stored_image).hexdigest() != digest:
            raise ApiException(503, "storage_unavailable", "La imagen almacenada no coincide con el análisis.")
        response.status_code = 200
        return _to_out(existing)
    if datetime.now(timezone.utc) > receipt["expiration"]:
        raise ApiException(422, "validation_error", "La previsualización expiró. Analiza la imagen de nuevo.")
    await run_in_threadpool(validate_image, data, max_bytes=settings.max_image_bytes,
                            max_dimension=settings.max_image_dimension,
                            max_pixels=settings.max_image_pixels)
    mime = "image/jpeg" if data.startswith(JPEG_MAGIC) else "image/png"
    extension = "jpg" if mime == "image/jpeg" else "png"
    path = f"{user.id}/{operation_id}.{extension}"
    await run_in_threadpool(services.image_storage.put, path, data, mime)
    prediction = receipt["prediction"]
    model = receipt["model_info"]
    record = AnalysisRecord(
        id=operation_id, account_id=str(user.id), category=prediction.category.value,
        probability=prediction.probability, scores=prediction.scores.model_dump(),
        display_name=name, created_at=receipt["created_at"],
        model_name=model.name, model_version=model.version, model_dataset=model.dataset,
        idempotency_key=operation_id, request_hash=request_hash, fixed_id=True,
        image_path=path, image_sha256=digest, image_mime_type=mime,
    )
    _to_out(record)
    saved = await run_in_threadpool(services.analyses.create, record)
    if saved is not record:
        response.status_code = 200
    return _to_out(saved)


@router.get("/{analysis_id}/image", responses=COMMON_ERRORS)
async def get_analysis_image(
    analysis_id: str,
    user: Annotated[AuthenticatedUser, Depends(get_current_user)],
    services: Annotated[Services, Depends(get_services)],
) -> Response:
    record = await run_in_threadpool(services.analyses.get_by_account, analysis_id, str(user.id))
    if record is None or record.image_path is None:
        raise ApiException(404, "not_found", "Imagen no encontrada.")
    if services.image_storage is None:
        raise ApiException(503, "storage_unavailable", "El almacenamiento de imágenes no está disponible.")
    content = await run_in_threadpool(services.image_storage.get, record.image_path)
    if hashlib.sha256(content).hexdigest() != record.image_sha256:
        raise ApiException(503, "storage_unavailable", "La imagen almacenada no coincide con el análisis.")
    return Response(content=content, media_type=record.image_mime_type,
                    headers={"Cache-Control": "private, no-store"})


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
