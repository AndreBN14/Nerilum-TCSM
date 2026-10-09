from dataclasses import dataclass
from typing import Protocol
from uuid import UUID


@dataclass(frozen=True)
class AuthenticatedUser:
    """Identidad obtenida de un token validado, nunca del cuerpo HTTP."""

    id: UUID


class TokenVerifier(Protocol):
    """Puerto para la futura validación de tokens Supabase.

    La implementación deberá verificar firma, issuer, audience y expiración
    según las claves de firma del proyecto antes de entregar el claim sub.
    No hay emisión de tokens ni autenticación por contraseña en FastAPI.
    """

    async def verify(self, access_token: str) -> AuthenticatedUser: ...
