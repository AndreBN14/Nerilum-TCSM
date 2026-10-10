from dataclasses import dataclass

import httpx

from app.core.config import Settings
from app.core.security import SupabaseJWTVerifier, TokenVerifier
from app.services.inference import InferenceStatus, UnavailableInference


@dataclass
class Services:
    """Punto de composición para inyectar servicios/adaptadores."""

    inference: InferenceStatus
    token_verifier: TokenVerifier

    async def aclose(self) -> None:
        closer = getattr(self.token_verifier, "aclose", None)
        if closer is not None:
            await closer()


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
    # MODEL_PATH no implica que exista un runtime o un modelo validado.
    return Services(inference=UnavailableInference(), token_verifier=verifier)
