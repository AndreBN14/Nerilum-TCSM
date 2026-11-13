from dataclasses import dataclass
import logging
from pathlib import Path

import httpx

from app.core.config import BACK_ROOT, Settings
from app.core.security import SupabaseJWTVerifier, TokenVerifier
from app.services.analyses import AnalysisRepository, SqliteAnalysisRepository
from app.services.analyses_pg import PostgresAnalysisRepository
from app.services.inference import InferenceStatus, OnnxClassifier, UnavailableInference
from app.services.gradcam import GradCamExplainer
from app.services.image_storage import ImageStorage, SupabaseImageStorage

logger = logging.getLogger("nerilum")


@dataclass
class Services:
    """Punto de composición para inyectar servicios/adaptadores."""

    inference: InferenceStatus
    token_verifier: TokenVerifier
    analyses: AnalysisRepository
    image_storage: ImageStorage | None = None
    explainer: GradCamExplainer | None = None

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


def _resolve_explainer_path(settings: Settings) -> Path | None:
    """Devuelve el ``.pt`` configurado o el que acompaña a ``MODEL_DIR``."""

    configured = settings.explainer_model_path
    if configured is not None:
        path = configured if configured.is_absolute() else BACK_ROOT / configured
        if path.is_dir():
            candidates = sorted(path.glob("*.pt"))
            return candidates[0] if len(candidates) == 1 else None
        return path if path.is_file() else None

    model_dir = _resolve_model_dir(settings)
    if model_dir is None or not model_dir.is_dir():
        return None
    candidates = sorted(model_dir.glob("*.pt"))
    return candidates[0] if len(candidates) == 1 else None


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
    explainer_path = _resolve_explainer_path(settings)
    explainer = (
        GradCamExplainer(
            explainer_path,
            resize_mode=settings.model_resize_mode,
            input_size=settings.model_input_size,
        )
        if explainer_path is not None
        else None
    )
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
