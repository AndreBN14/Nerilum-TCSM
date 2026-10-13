from dataclasses import dataclass
import logging

import httpx

from app.core.config import BACK_ROOT, Settings
from app.core.security import SupabaseJWTVerifier, TokenVerifier
from app.services.analyses import AnalysisRepository, SqliteAnalysisRepository
from app.services.inference import InferenceStatus, OnnxClassifier, UnavailableInference

logger = logging.getLogger("nerilum")


@dataclass
class Services:
    """Punto de composición para inyectar servicios/adaptadores."""

    inference: InferenceStatus
    token_verifier: TokenVerifier
    analyses: AnalysisRepository

    async def aclose(self) -> None:
        closer = getattr(self.token_verifier, "aclose", None)
        if closer is not None:
            await closer()
        closer = getattr(self.analyses, "close", None)
        if closer is not None:
            closer()


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
    analyses = SqliteAnalysisRepository(settings.database_path)

    services = Services(inference=inference, token_verifier=verifier, analyses=analyses)

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
