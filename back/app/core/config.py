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
    cors_origins: list[str] = Field(default_factory=list)
    model_path: Path | None = None


@lru_cache
def get_settings() -> Settings:
    return Settings()
