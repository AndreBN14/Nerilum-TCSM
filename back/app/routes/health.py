from typing import Annotated

from fastapi import APIRouter, Depends

from app.routes.dependencies import get_services
from app.schemas.error import SERVER_ERRORS
from app.schemas.health import HealthResponse
from app.services.container import Services

router = APIRouter(tags=["health"])


@router.get("/health", response_model=HealthResponse, responses=SERVER_ERRORS)
def health(services: Annotated[Services, Depends(get_services)]) -> HealthResponse:
    model_info = services.inference.model_info
    return HealthResponse(
        model_ready=services.inference.ready,
        model_name=model_info.name if model_info else None,
        model_version=model_info.version if model_info else None,
    )
