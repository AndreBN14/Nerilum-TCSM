from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

from app.schemas.error import ErrorDetail, ErrorResponse


def error_response(status: int, code: str, message: str) -> JSONResponse:
    body = ErrorResponse(error=ErrorDetail(code=code, message=message))
    return JSONResponse(status_code=status, content=body.model_dump())


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(RequestValidationError)
    async def validation_error(
        request: Request, exc: RequestValidationError
    ) -> JSONResponse:
        # No devolver el cuerpo original: podría contener datos sensibles.
        return error_response(422, "validation_error", "La solicitud no es válida.")

    @app.exception_handler(HTTPException)
    async def http_error(request: Request, exc: HTTPException) -> JSONResponse:
        codes = {
            401: "invalid_token",
            403: "forbidden",
            404: "not_found",
            405: "method_not_allowed",
            503: "service_unavailable",
        }
        response = error_response(
            exc.status_code,
            codes.get(exc.status_code, "http_error"),
            str(exc.detail),
        )
        if exc.headers:
            response.headers.update(exc.headers)
        return response
