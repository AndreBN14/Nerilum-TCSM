from contextlib import asynccontextmanager
from collections.abc import AsyncIterator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import Settings, get_settings
from app.core.errors import register_error_handlers
from app.routes import analyses, health
from app.services.container import Services, create_services


def create_app(
    settings: Settings | None = None, services: Services | None = None
) -> FastAPI:
    config = settings if settings is not None else get_settings()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        app.state.services = services if services is not None else create_services(config)
        yield

    app = FastAPI(title="Nerilum API", version="0.1.0", lifespan=lifespan)
    app.state.settings = config
    if config.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=config.cors_origins,
            allow_methods=["GET", "POST", "OPTIONS"],
            allow_headers=["Authorization", "Content-Type"],
        )
    register_error_handlers(app)
    app.include_router(health.router, prefix="/api/v1")
    app.include_router(analyses.router, prefix="/api/v1")
    return app


app = create_app()
