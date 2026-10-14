from pydantic import BaseModel


class ErrorDetail(BaseModel):
    code: str
    message: str


class ErrorResponse(BaseModel):
    error: ErrorDetail


# Documentación OpenAPI de errores, definida una sola vez y reutilizada en los
# decoradores de las rutas.
AUTH_ERRORS: dict[int | str, dict] = {
    401: {
        "model": ErrorResponse,
        "description": "Token de acceso ausente, inválido o expirado.",
    },
}

SERVER_ERRORS: dict[int | str, dict] = {
    500: {"model": ErrorResponse, "description": "Error interno del servidor."},
}

SERVICE_ERRORS: dict[int | str, dict] = {
    503: {
        "model": ErrorResponse,
        "description": "Servicio no disponible temporalmente (incluye Retry-After).",
    },
}

COMMON_ERRORS: dict[int | str, dict] = {
    **AUTH_ERRORS,
    **SERVER_ERRORS,
    **SERVICE_ERRORS,
}
