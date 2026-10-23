import logging
from contextlib import asynccontextmanager
from collections.abc import AsyncIterator

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import Settings, get_settings, warn_legacy_model_env
from app.core.errors import register_error_handlers
from app.core.logging import configure_logging
from app.routes import analyses, auth, health
from app.services.container import Services, create_services


def create_app(
    settings: Settings | None = None, services: Services | None = None
) -> FastAPI:
    config = settings if settings is not None else get_settings()
    configure_logging(
        level=logging.DEBUG if config.app_env == "development" else logging.INFO
    )
    warn_legacy_model_env()

    @asynccontextmanager
    async def lifespan(app: FastAPI) -> AsyncIterator[None]:
        app.state.services = services if services is not None else create_services(config)
        try:
            yield
        finally:
            await app.state.services.aclose()

    app = FastAPI(title="Nerilum API", version="0.1.0", lifespan=lifespan)
    app.state.settings = config

    documentation_paths = {
        path for path in (app.docs_url, app.redoc_url, app.openapi_url) if path
    }

    @app.middleware("http")
    async def no_store_documentation(request: Request, call_next):
        """Evita que el navegador cachee /docs y /openapi.json obsoletos."""

        response = await call_next(request)
        if request.url.path in documentation_paths:
            response.headers["Cache-Control"] = "no-store"
        return response

    if config.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=config.cors_origins,
            allow_methods=["GET", "POST", "OPTIONS"],
            allow_headers=["Authorization", "Content-Type", "Idempotency-Key"],
        )
    register_error_handlers(app)
    app.include_router(health.router, prefix="/api/v1")
    app.include_router(auth.router, prefix="/api/v1")
    app.include_router(analyses.router, prefix="/api/v1")
    return app


app = create_app()
