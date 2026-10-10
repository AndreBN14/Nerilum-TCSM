from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

BACK_ROOT = Path(__file__).resolve().parents[2]


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
    model_path: Path | None = None

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
