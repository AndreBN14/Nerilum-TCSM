from typing import Annotated

from fastapi import APIRouter, Depends

from app.routes.dependencies import get_services
from app.schemas.health import HealthResponse
from app.services.container import Services

router = APIRouter(tags=["health"])


@router.get("/health", response_model=HealthResponse)
def health(services: Annotated[Services, Depends(get_services)]) -> HealthResponse:
    return HealthResponse(model_ready=services.inference.ready)
