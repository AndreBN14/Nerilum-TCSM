from typing import Literal

from pydantic import BaseModel


class HealthResponse(BaseModel):
    status: Literal["ok"] = "ok"
    model_ready: bool
    model_name: str | None = None
    model_version: str | None = None
