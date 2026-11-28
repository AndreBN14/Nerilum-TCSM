"""Fixtures compartidas de la Fase 1.

Todo se apoya en un par de claves EC P-256 generado exclusivamente para las
pruebas y en un JWKS simulado servido mediante ``httpx.MockTransport``. No se
usan tokens ni claves reales de Supabase.
"""

from __future__ import annotations

import base64
import tempfile
import time
from collections.abc import Callable
from pathlib import Path
from uuid import uuid4

import httpx
import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi import FastAPI

from app.core.categories import Category
from app.core.config import BACK_ROOT, Settings
from app.core.model_info import ModelInfo
from app.core.security import SupabaseJWTVerifier
from app.main import create_app
from app.services.analyses import SqliteAnalysisRepository
from app.services.container import Services
from app.services.inference import InferenceStatus, UnavailableInference

SUPABASE_URL = "https://test-project.supabase.co"
ISSUER = f"{SUPABASE_URL}/auth/v1"
KID = "test-kid-1"
OTHER_KID = "test-kid-2"
AUDIENCE = "authenticated"
SUBJECT = "11111111-1111-1111-1111-111111111111"
EMAIL = "user@example.com"


def _b64u(value: int) -> str:
    return base64.urlsafe_b64encode(value.to_bytes(32, "big")).rstrip(b"=").decode()


def make_keypair() -> ec.EllipticCurvePrivateKey:
    return ec.generate_private_key(ec.SECP256R1())


def public_jwk(private_key: ec.EllipticCurvePrivateKey, kid: str) -> dict[str, str]:
    numbers = private_key.public_key().public_numbers()
    return {
        "kty": "EC",
        "crv": "P-256",
        "x": _b64u(numbers.x),
        "y": _b64u(numbers.y),
        "kid": kid,
        "use": "sig",
        "alg": "ES256",
    }


def sign_token(
    private_key: ec.EllipticCurvePrivateKey,
    *,
    kid: str = KID,
    iss: str = ISSUER,
    aud: str = AUDIENCE,
    sub: str = SUBJECT,
    exp: int | None = None,
    nbf: int | None = None,
    email: str | None = EMAIL,
    omit: tuple[str, ...] = (),
) -> str:
    now = int(time.time())
    payload: dict[str, object] = {
        "iss": iss,
        "aud": aud,
        "sub": sub,
        "exp": now + 3600 if exp is None else exp,
        "iat": now,
    }
    if nbf is not None:
        payload["nbf"] = nbf
    if email is not None:
        payload["email"] = email
    for claim in omit:
        payload.pop(claim, None)
    return jwt.encode(
        payload, private_key, algorithm="ES256", headers={"kid": kid, "alg": "ES256"}
    )


class FakeClock:
    def __init__(self, start: float = 1000.0) -> None:
        self.now = start

    def __call__(self) -> float:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += seconds


class JWKSStub:
    """Servidor JWKS simulado con contador de peticiones y modos de fallo."""

    def __init__(self, keys: list[dict[str, str]]) -> None:
        self.keys = keys
        self.calls = 0
        self.status = 200
        self.raw: bytes | None = None

    def handler(self, request: httpx.Request) -> httpx.Response:
        self.calls += 1
        if self.status != 200:
            return httpx.Response(self.status)
        if self.raw is not None:
            return httpx.Response(200, content=self.raw)
        return httpx.Response(200, json={"keys": self.keys})

    def client(self) -> httpx.AsyncClient:
        return httpx.AsyncClient(transport=httpx.MockTransport(self.handler))


def build_verifier(
    stub: JWKSStub,
    *,
    leeway: int = 0,
    cache_ttl: int = 3600,
    min_refresh_interval: int = 0,
    clock: Callable[[], float] | None = None,
    supabase_url: str = SUPABASE_URL,
    issuer: str | None = ISSUER,
    client: httpx.AsyncClient | None = None,
) -> SupabaseJWTVerifier:
    options: dict[str, object] = {}
    if clock is not None:
        options["clock"] = clock
    return SupabaseJWTVerifier(
        supabase_url,
        audience=AUDIENCE,
        issuer=issuer,
        leeway=leeway,
        cache_ttl=cache_ttl,
        min_refresh_interval=min_refresh_interval,
        client=client if client is not None else stub.client(),
        **options,
    )


class FakeInference:
    """Inferencia determinista para las rutas: no toca onnxruntime."""

    def __init__(
        self,
        scores: dict[str, float] | None = None,
        *,
        ready: bool = True,
        name: str = "fake-cls",
        version: str = "test",
        dataset: str = "ADNI",
    ) -> None:
        self._scores = scores or {
            "MildDemented": 0.1,
            "ModerateDemented": 0.2,
            "NonDemented": 0.5,
            "VeryMildDemented": 0.2,
        }
        self.ready = ready
        self.model_info = (
            ModelInfo(
                name=name,
                version=version,
                dataset=dataset,
                classes=[category.value for category in Category],
            )
            if ready
            else None
        )

    def analyze(self, image: object) -> dict[str, float]:
        return dict(self._scores)


def build_app(
    verifier: SupabaseJWTVerifier,
    *,
    inference: InferenceStatus | None = None,
    db_path: Path | None = None,
    settings_overrides: dict[str, object] | None = None,
    image_storage=None,
    explainer=None,
    auth_admin=None,
) -> FastAPI:
    overrides: dict[str, object] = {
        "supabase_url": SUPABASE_URL,
        "database_path": db_path or Path(tempfile.gettempdir()) / f"nrl-{uuid4().hex}.db",
    }
    if settings_overrides:
        overrides.update(settings_overrides)
    # model_dir=None a propósito: evita que un MODEL_DIR del entorno active
    # el modelo real en pruebas que no lo piden explícitamente.
    settings = Settings(_env_file=None, model_dir=None, **overrides)
    services = Services(
        inference=inference if inference is not None else UnavailableInference(),
        token_verifier=verifier,
        analyses=SqliteAnalysisRepository(settings.database_path),
        image_storage=image_storage,
        auth_admin=auth_admin,
        explainer=explainer,
    )
    return create_app(settings, services)


@pytest.fixture
def keypair() -> ec.EllipticCurvePrivateKey:
    return make_keypair()


@pytest.fixture
def other_keypair() -> ec.EllipticCurvePrivateKey:
    return make_keypair()


@pytest.fixture
def stub(keypair: ec.EllipticCurvePrivateKey) -> JWKSStub:
    return JWKSStub([public_jwk(keypair, KID)])


@pytest.fixture
async def make_verifier(stub: JWKSStub):
    created: list[SupabaseJWTVerifier] = []

    def make(*, _stub: JWKSStub | None = None, **kwargs) -> SupabaseJWTVerifier:
        verifier = build_verifier(_stub or stub, **kwargs)
        created.append(verifier)
        return verifier

    yield make
    for verifier in created:
        await verifier.aclose()


PROJECT_DB = BACK_ROOT / "data" / "nerilum.db"


def _db_state(path: Path) -> int | None:
    return path.stat().st_mtime_ns if path.exists() else None


def assert_project_db_untouched(before: int | None, after: int | None, path: Path) -> None:
    assert after == before, (
        "GUARDIA DE HIGIENE: la suite creó o modificó la base del proyecto "
        f"({path}). Los tests no deben usar la DB del proyecto; pasa "
        "database_path apuntando a tmp_path."
    )


@pytest.fixture(scope="session", autouse=True)
def _project_db_guard():
    # Guardia de higiene: la suite no debe crear/modificar back/data/nerilum.db.
    # mtime_ns detecta creación y modificación, de modo que no da falso positivo
    # si el desarrollador ya tenía un .db local y la suite no lo toca.
    # Nota: si se arranca la app a mano mientras corre la suite, la app
    # recrearía el .db y esta guardia fallaría (caso raro, aceptado).
    before = _db_state(PROJECT_DB)
    yield
    assert_project_db_untouched(before, _db_state(PROJECT_DB), PROJECT_DB)

