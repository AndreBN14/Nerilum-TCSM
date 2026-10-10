"""Verificación de tokens de Supabase Auth y contrato de identidad.

FastAPI no emite ni renueva tokens: solo verifica la firma ES256 y las claims
de los JWT emitidos por Supabase usando las claves públicas de JWKS.
"""

from __future__ import annotations

import asyncio
import json
import time
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any, Protocol
from uuid import UUID

import httpx
import jwt
from jwt.algorithms import ECAlgorithm


@dataclass(frozen=True)
class AuthenticatedUser:
    """Identidad obtenida de un token validado, nunca del cuerpo HTTP."""

    id: UUID
    email: str | None = None


class InvalidTokenError(Exception):
    """Token ausente, malformado, con firma o claims no válidos."""


class JWKSUnavailableError(Exception):
    """No se pudo obtener ni reutilizar una clave pública para verificar."""


class TokenVerifier(Protocol):
    """Puerto de verificación de tokens Supabase."""

    async def verify(self, access_token: str) -> AuthenticatedUser: ...


class SupabaseJWTVerifier:
    """Verificador ES256 con caché de JWKS y rotación de claves.

    Política de caché y errores (documentada y verificada por pruebas):

    - Una clave cacheada se usa mientras el JWKS siga dentro del TTL.
    - Si el ``kid`` no está en caché y el intervalo mínimo de refresco lo
      permite, se descarga ``{SUPABASE_URL}/auth/v1/.well-known/jwks.json``.
    - Si el proveedor responde correctamente y el ``kid`` sigue ausente o su
      clave no sirve para ES256, el token es inválido (401).
    - Si el ``kid`` es desconocido y el intervalo mínimo impide refrescar, se
      responde con indisponibilidad temporal (503); nunca se marca el token
      como inválido de forma definitiva sin una descarga concluyente.
    - Si el proveedor no responde y no hay una clave utilizable, es 503.
    - Una clave caducada no se reutiliza indefinidamente.
    """

    ALGORITHM = "ES256"
    JWKS_PATH = "/auth/v1/.well-known/jwks.json"

    def __init__(
        self,
        supabase_url: str,
        *,
        audience: str = "authenticated",
        issuer: str | None = None,
        leeway: int = 0,
        cache_ttl: int = 3600,
        min_refresh_interval: int = 60,
        timeout: float = 5.0,
        client: httpx.AsyncClient | None = None,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        base = (supabase_url or "").rstrip("/")
        self._base_url = base
        self._issuer = issuer or (f"{base}/auth/v1" if base else None)
        self._audience = audience
        self._leeway = leeway
        self._cache_ttl = cache_ttl
        self._min_refresh_interval = min_refresh_interval
        self._timeout = timeout
        self._client = client
        self._clock = clock
        self._keys: dict[str, Any] = {}
        self._fetched_at: float | None = None
        self._last_attempt: float | None = None
        self._lock = asyncio.Lock()

    async def aclose(self) -> None:
        if self._client is not None:
            await self._client.aclose()

    async def verify(self, access_token: str) -> AuthenticatedUser:
        if not access_token:
            raise InvalidTokenError("Token ausente.")
        if not self._base_url or not self._issuer:
            raise JWKSUnavailableError("Verificación de tokens no configurada.")

        try:
            header = jwt.get_unverified_header(access_token)
        except jwt.PyJWTError as exc:
            raise InvalidTokenError("Token malformado.") from exc

        if header.get("alg") != self.ALGORITHM:
            raise InvalidTokenError("Algoritmo no permitido.")

        kid = header.get("kid")
        if not isinstance(kid, str) or not kid:
            raise InvalidTokenError("Token sin identificador de clave.")

        key = await self._resolve_key(kid)

        try:
            claims = jwt.decode(
                access_token,
                key=key,
                algorithms=[self.ALGORITHM],
                audience=self._audience,
                issuer=self._issuer,
                leeway=self._leeway,
                options={"require": ["exp", "iss", "aud", "sub"]},
            )
        except jwt.PyJWTError as exc:
            raise InvalidTokenError("Token inválido.") from exc

        try:
            user_id = UUID(str(claims.get("sub")))
        except (TypeError, ValueError) as exc:
            raise InvalidTokenError("Identificador de usuario inválido.") from exc

        email = claims.get("email")
        if not isinstance(email, str):
            email = None

        return AuthenticatedUser(id=user_id, email=email)

    async def _resolve_key(self, kid: str) -> Any:
        now = self._clock()
        if kid in self._keys and self._cache_valid(now):
            return self._keys[kid]

        if not self._can_refresh(now):
            raise JWKSUnavailableError("Claves no disponibles temporalmente.")

        async with self._lock:
            now = self._clock()
            if kid in self._keys and self._cache_valid(now):
                return self._keys[kid]
            if not self._can_refresh(now):
                raise JWKSUnavailableError("Claves no disponibles temporalmente.")

            await self._fetch_keys()

            if kid in self._keys:
                return self._keys[kid]
            raise InvalidTokenError("Token firmado con una clave desconocida.")

    def _cache_valid(self, now: float) -> bool:
        if self._fetched_at is None:
            return False
        return (now - self._fetched_at) < self._cache_ttl

    def _can_refresh(self, now: float) -> bool:
        if self._last_attempt is None:
            return True
        return (now - self._last_attempt) >= self._min_refresh_interval

    async def _fetch_keys(self) -> None:
        self._last_attempt = self._clock()
        url = f"{self._base_url}{self.JWKS_PATH}"

        if self._client is not None:
            data = await self._request(self._client, url)
        else:
            async with httpx.AsyncClient(timeout=self._timeout) as client:
                data = await self._request(client, url)

        self._keys = self._parse_jwks(data)
        self._fetched_at = self._clock()

    async def _request(self, client: httpx.AsyncClient, url: str) -> dict[str, Any]:
        try:
            response = await client.get(url, timeout=self._timeout)
        except httpx.HTTPError as exc:
            raise JWKSUnavailableError(
                "No se pudo contactar el proveedor de claves."
            ) from exc

        if response.status_code != 200:
            raise JWKSUnavailableError(
                "Respuesta inválida del proveedor de claves."
            )

        try:
            data = response.json()
        except (json.JSONDecodeError, ValueError) as exc:
            raise JWKSUnavailableError(
                "Respuesta ilegible del proveedor de claves."
            ) from exc

        if not isinstance(data, dict) or not isinstance(data.get("keys"), list):
            raise JWKSUnavailableError("Estructura JWKS inválida.")
        if not data["keys"]:
            raise JWKSUnavailableError("El proveedor no expone claves.")
        return data

    def _parse_jwks(self, data: dict[str, Any]) -> dict[str, Any]:
        keys: dict[str, Any] = {}
        for jwk in data["keys"]:
            if not isinstance(jwk, dict):
                continue
            if jwk.get("kty") != "EC" or jwk.get("crv") != "P-256":
                continue
            kid = jwk.get("kid")
            if not isinstance(kid, str) or not kid:
                continue
            try:
                keys[kid] = ECAlgorithm.from_jwk(json.dumps(jwk))
            except (jwt.PyJWTError, ValueError, KeyError, TypeError):
                continue
        return keys
