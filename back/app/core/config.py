import logging
import os
from functools import lru_cache
from pathlib import Path
from typing import Literal
from uuid import UUID

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

BACK_ROOT = Path(__file__).resolve().parents[2]

logger = logging.getLogger("nerilum")

# Variables de modelo obsoletas: MODEL_DIR + model_card.json las sustituyen.
LEGACY_MODEL_ENV_VARS = ("MODEL_PATH", "MODEL_NAME", "MODEL_VERSION", "MODEL_DATASET")


def warn_legacy_model_env() -> None:
    """Avisa si el entorno aún define variables de modelo obsoletas.

    Una misconfiguración silenciosa (arrancar con ``MODEL_PATH`` y ver
    ``model_ready=false`` sin motivo aparente) es peligrosa en un sistema
    médico. Solo se registran los **nombres** de las variables presentes,
    nunca sus valores.
    """

    present = [name for name in LEGACY_MODEL_ENV_VARS if os.environ.get(name)]
    if present:
        logger.warning(
            "%s ya no se usa(n); usa MODEL_DIR (ver README).",
            ", ".join(present),
        )


class Settings(BaseSettings):
    """Lee back/.env y permite sobreescritura por variables del proceso."""

    model_config = SettingsConfigDict(
        env_file=BACK_ROOT / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_env: Literal["development", "test", "production"] = "development"
    host: str = "127.0.0.1"
    port: int = Field(default=8000, ge=1, le=65535)
    supabase_url: str = ""
    supabase_publishable_key: str = ""
    supabase_jwt_audience: str = "authenticated"
    supabase_jwt_issuer: str | None = None
    jwt_leeway_seconds: int = Field(default=0, ge=0)
    jwks_cache_ttl_seconds: int = Field(default=3600, ge=0)
    jwks_min_refresh_interval_seconds: int = Field(default=60, ge=0)
    jwks_timeout_seconds: float = Field(default=5.0, gt=0)
    cors_origins: list[str] = Field(default_factory=list)
    database_url: str | None = None
    database_path: Path = Field(default=BACK_ROOT / "data" / "nerilum.db")
    model_dir: Path | None = None
    model_input_size: int | None = Field(default=None, ge=32)
    model_resize_mode: Literal["letterbox", "center_crop", "stretch"] = "center_crop"
    model_softmax: bool = False
    max_image_bytes: int = Field(default=10 * 1024 * 1024, ge=1)
    max_image_dimension: int = Field(default=4096, ge=1)
    max_image_pixels: int = Field(default=16_777_216, ge=1)
    retry_after_seconds: int = Field(default=5, ge=1)
    seed_demo: bool = False
    seed_demo_account_id: UUID | None = None
    analysis_proof_secret: str = ""
    supabase_service_role_key: str = ""
    analysis_images_bucket: str = "analysis-images"

    @property
    def use_postgres(self) -> bool:
        return bool(self.database_url and str(self.database_url).strip())

    @property
    def resolved_issuer(self) -> str | None:
        """Emisor efectivo: el explícito o {SUPABASE_URL}/auth/v1."""

        if self.supabase_jwt_issuer:
            return self.supabase_jwt_issuer
        if self.supabase_url:
            return f"{self.supabase_url.rstrip('/')}/auth/v1"
        return None


@lru_cache
def get_settings() -> Settings:
    return Settings()
