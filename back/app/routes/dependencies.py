from typing import Annotated

from fastapi import Depends, Request, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.core.errors import ApiException
from app.core.security import (
    AuthenticatedUser,
    InvalidTokenError,
    JWKSUnavailableError,
)
from app.services.container import Services

_bearer_scheme = HTTPBearer(
    auto_error=False,
    bearerFormat="JWT",
    description=(
        "JWT de acceso emitido por Supabase Auth (ES256). "
        "Introduce solo el access_token; Swagger añade el prefijo 'Bearer '."
    ),
)


def get_services(request: Request) -> Services:
    return request.app.state.services


def _normalize_token(raw: str) -> str:
    """Limpia el valor recibido en ``Authorization``.

    Tolera errores frecuentes al probar con Swagger: espacios sobrantes, un
    segundo prefijo ``Bearer`` escrito a mano (Swagger ya lo añade) o comillas
    al copiar el token. Un token JWT nunca contiene comillas ni espacios, por lo
    que recortarlos no altera tokens válidos.
    """

    value = raw.strip()
    if value[:7].lower() == "bearer ":
        value = value[7:].strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1].strip()
    return value


async def get_current_user(
    credentials: Annotated[
        HTTPAuthorizationCredentials | None, Security(_bearer_scheme)
    ],
    services: Annotated[Services, Depends(get_services)],
) -> AuthenticatedUser:
    """Valida el Bearer token contra el verificador del contenedor de servicios."""

    if credentials is None or credentials.scheme.lower() != "bearer":
        raise ApiException(
            401,
            "invalid_token",
            "Token de acceso ausente o malformado.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    token = _normalize_token(credentials.credentials)
    if not token:
        raise ApiException(
            401,
            "invalid_token",
            "Token de acceso ausente o malformado.",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        return await services.token_verifier.verify(token)
    except InvalidTokenError as exc:
        raise ApiException(
            401,
            "invalid_token",
            "Token de acceso inválido.",
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    except JWKSUnavailableError as exc:
        raise ApiException(
            503,
            "service_unavailable",
            "No se pudo verificar el token en este momento.",
        ) from exc
