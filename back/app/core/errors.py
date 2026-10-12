import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

from app.schemas.error import ErrorDetail, ErrorResponse

logger = logging.getLogger("nerilum")

# Códigos por defecto para las HTTPException que no traen uno explícito.
# 403 no se usa en v1: si apareciera cae a "http_error".
_CODE_BY_STATUS = {
    401: "invalid_token",
    404: "not_found",
    405: "method_not_allowed",
    429: "rate_limited",
    500: "internal_error",
    503: "service_unavailable",
}


class ApiException(HTTPException):
    """HTTPException con un código de error explícito del contrato."""

    def __init__(
        self,
        status_code: int,
        code: str,
        message: str,
        headers: dict[str, str] | None = None,
    ) -> None:
        super().__init__(status_code=status_code, detail=message, headers=headers)
        self.code = code


def error_response(
    status: int,
    code: str,
    message: str,
    headers: dict[str, str] | None = None,
) -> JSONResponse:
    body = ErrorResponse(error=ErrorDetail(code=code, message=message))
    response = JSONResponse(status_code=status, content=body.model_dump())
    if headers:
        response.headers.update(headers)
    return response


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(RequestValidationError)
    async def validation_error(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        # No devolver el cuerpo original: podría contener datos sensibles.
        return error_response(422, "validation_error", "La solicitud no es válida.")

    # Registrar sobre la HTTPException de Starlette (que FastAPI hereda) para
    # cubrir también los 404/405 que genera Starlette por su cuenta.
    @app.exception_handler(HTTPException)
    async def http_error(request: Request, exc: HTTPException) -> JSONResponse:
        headers = dict(exc.headers or {})
        if exc.status_code == 503 and not any(
            key.lower() == "retry-after" for key in headers
        ):
            settings = getattr(request.app.state, "settings", None)
            retry = settings.retry_after_seconds if settings else 5
            headers["Retry-After"] = str(retry)
        return error_response(
            exc.status_code,
            getattr(exc, "code", None) or _CODE_BY_STATUS.get(exc.status_code, "http_error"),
            str(exc.detail),
            headers=headers,
        )

    @app.exception_handler(Exception)
    async def unhandled_error(request: Request, exc: Exception) -> JSONResponse:
        # La traza queda solo en el servidor; el cliente recibe un mensaje fijo.
        logger.exception(
            "Error no controlado en %s %s", request.method, request.url.path
        )
        return error_response(500, "internal_error", "Error interno del servidor.")
