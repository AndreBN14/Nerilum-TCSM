"""Pruebas del manejo central de errores.

Cubren la envoltura única, el handler genérico (500 sin traza), el mapa de
códigos y la inyección de ``Retry-After`` en los 503.
"""

from __future__ import annotations

from fastapi.testclient import TestClient
from starlette.exceptions import HTTPException

from app.core.errors import ApiException
from conftest import build_app, build_verifier


def _client(stub, *, raise_server_exceptions: bool = True, settings_overrides=None):
    app = build_app(build_verifier(stub), settings_overrides=settings_overrides)
    return app, TestClient(app, raise_server_exceptions=raise_server_exceptions)


def test_generic_exception_returns_internal_error_without_traceback(stub) -> None:
    app, client = _client(stub, raise_server_exceptions=False)

    @app.get("/_boom")
    def boom() -> None:
        raise RuntimeError("secreto-de-servidor")

    with client:
        response = client.get("/_boom")
    assert response.status_code == 500
    assert response.json()["error"] == {
        "code": "internal_error",
        "message": "Error interno del servidor.",
    }
    assert "secreto-de-servidor" not in response.text
    assert "Traceback" not in response.text


def test_unmapped_status_falls_back_to_http_error(stub) -> None:
    app, client = _client(stub)

    @app.get("/_teapot")
    def teapot() -> None:
        raise HTTPException(status_code=418, detail="Soy una tetera.")

    with client:
        response = client.get("/_teapot")
    assert response.status_code == 418
    assert response.json()["error"]["code"] == "http_error"


def test_rate_limited_status_maps_to_code(stub) -> None:
    app, client = _client(stub)

    @app.get("/_limited")
    def limited() -> None:
        raise HTTPException(status_code=429, detail="Demasiadas peticiones.")

    with client:
        response = client.get("/_limited")
    assert response.status_code == 429
    assert response.json()["error"]["code"] == "rate_limited"


def test_forbidden_is_not_mapped(stub) -> None:
    app, client = _client(stub)

    @app.get("/_forbidden")
    def forbidden() -> None:
        raise HTTPException(status_code=403, detail="Prohibido.")

    with client:
        response = client.get("/_forbidden")
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "http_error"


def test_503_includes_default_retry_after(stub) -> None:
    app, client = _client(stub)

    @app.get("/_unavailable")
    def unavailable() -> None:
        raise ApiException(503, "service_unavailable", "No disponible.")

    with client:
        response = client.get("/_unavailable")
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "service_unavailable"
    assert response.headers["retry-after"] == "5"


def test_503_retry_after_follows_setting(stub) -> None:
    app, client = _client(stub, settings_overrides={"retry_after_seconds": 7})

    @app.get("/_unavailable")
    def unavailable() -> None:
        raise ApiException(503, "service_unavailable", "No disponible.")

    with client:
        response = client.get("/_unavailable")
    assert response.headers["retry-after"] == "7"


def test_503_keeps_existing_retry_after(stub) -> None:
    app, client = _client(stub)

    @app.get("/_unavailable")
    def unavailable() -> None:
        raise ApiException(
            503,
            "service_unavailable",
            "No disponible.",
            headers={"Retry-After": "30"},
        )

    with client:
        response = client.get("/_unavailable")
    assert response.headers.get_list("retry-after") == ["30"]


def test_503_retry_after_detection_is_case_insensitive(stub) -> None:
    app, client = _client(stub)

    @app.get("/_unavailable")
    def unavailable() -> None:
        raise ApiException(
            503,
            "service_unavailable",
            "No disponible.",
            headers={"retry-after": "45"},
        )

    with client:
        response = client.get("/_unavailable")
    assert response.headers.get_list("retry-after") == ["45"]
