from dataclasses import dataclass
import logging
from pathlib import Path

import httpx

from app.core.config import BACK_ROOT, Settings
from app.core.security import SupabaseJWTVerifier, TokenVerifier
from app.services.analyses import AnalysisRepository, SqliteAnalysisRepository
from app.services.analyses_pg import PostgresAnalysisRepository
from app.services.cam import Explainer, OnnxCamExplainer
from app.services.inference import InferenceStatus, OnnxClassifier, UnavailableInference
from app.services.image_storage import ImageStorage, SupabaseImageStorage

logger = logging.getLogger("nerilum")


@dataclass
class Services:
    """Punto de composición para inyectar servicios/adaptadores."""

    inference: InferenceStatus
    token_verifier: TokenVerifier
    analyses: AnalysisRepository
    image_storage: ImageStorage | None = None
    explainer: Explainer | None = None

    async def aclose(self) -> None:
        closer = getattr(self.token_verifier, "aclose", None)
        if closer is not None:
            await closer()
        closer = getattr(self.analyses, "close", None)
        if closer is not None:
            closer()
        if self.image_storage is not None:
            self.image_storage.close()


def _resolve_model_dir(settings: Settings):
    if settings.model_dir is None:
        return None
    path = settings.model_dir
    if not path.is_absolute():
        path = BACK_ROOT / path
    return path


def _build_inference(settings: Settings) -> InferenceStatus:
    model_dir = _resolve_model_dir(settings)
    if model_dir is None:
        # MODEL_DIR no configurado: sin modelo conectado.
        return UnavailableInference()
    return OnnxClassifier(
        model_dir,
        resize_mode=settings.model_resize_mode,
        softmax=settings.model_softmax,
        input_size=settings.model_input_size,
    )


def _resolve_onnx_path(settings: Settings) -> Path | None:
    """Devuelve el único ``.onnx`` de ``MODEL_DIR`` (el mismo del clasificador)."""

    model_dir = _resolve_model_dir(settings)
    if model_dir is None or not model_dir.is_dir():
        return None
    candidates = sorted(model_dir.glob("*.onnx"))
    return candidates[0] if len(candidates) == 1 else None


def _build_explainer(settings: Settings) -> Explainer | None:
    """CAM derivado del mismo ``.onnx`` que usa el clasificador.

    No requiere torch ni checkpoint PyTorch: la activación de la última
    convolución se añade al grafo en memoria y se pondera con los pesos del
    clasificador. El ``.pt`` no interviene en ningún momento.
    """

    onnx_path = _resolve_onnx_path(settings)
    if onnx_path is None:
        return None
    return OnnxCamExplainer(
        onnx_path,
        resize_mode=settings.model_resize_mode,
        input_size=settings.model_input_size,
    )


def create_services(settings: Settings) -> Services:
    # Cliente creado en el arranque de la app (lifespan), nunca al importar.
    client = httpx.AsyncClient(timeout=settings.jwks_timeout_seconds)
    verifier = SupabaseJWTVerifier(
        settings.supabase_url,
        audience=settings.supabase_jwt_audience,
        issuer=settings.resolved_issuer,
        leeway=settings.jwt_leeway_seconds,
        cache_ttl=settings.jwks_cache_ttl_seconds,
        min_refresh_interval=settings.jwks_min_refresh_interval_seconds,
        timeout=settings.jwks_timeout_seconds,
        client=client,
    )

    inference = _build_inference(settings)
    if settings.use_postgres and settings.database_url:
        analyses = PostgresAnalysisRepository(settings.database_url)
        if settings.supabase_service_role_key:
            analyses.require_image_schema()
    else:
        analyses = SqliteAnalysisRepository(settings.database_path)

    image_storage = (
        SupabaseImageStorage(settings.supabase_url, settings.supabase_service_role_key,
                             settings.analysis_images_bucket)
        if settings.supabase_service_role_key else None
    )
    explainer = _build_explainer(settings)
    services = Services(inference=inference, token_verifier=verifier, analyses=analyses,
                        image_storage=image_storage, explainer=explainer)

    # Semilla de demostración: solo desarrollo, opcional e idempotente.
    if (
        settings.app_env == "development"
        and settings.seed_demo
        and settings.seed_demo_account_id is not None
    ):
        model_info = inference.model_info
        if model_info is None:
            logger.warning(
                "SEED_DEMO activo pero el modelo no está listo; no se siembran registros."
            )
        else:
            analyses.seed_demo(str(settings.seed_demo_account_id), model_info)

    return services
