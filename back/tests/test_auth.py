"""Pruebas de los endpoints /api/v1/health y /api/v1/auth/me."""

from __future__ import annotations

from conftest import (
    EMAIL,
    SUBJECT,
    build_app,
    build_verifier,
    sign_token,
)
from fastapi.testclient import TestClient

from app.core.config import Settings
from app.main import create_app


def _client(stub) -> TestClient:
    return TestClient(build_app(build_verifier(stub)))


def test_health_is_public_without_supabase_config(tmp_path):
    app = create_app(
        Settings(_env_file=None, model_dir=None, database_path=tmp_path / "h.db")
    )
    with TestClient(app) as client:
        response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "model_ready": False,
        "model_name": None,
        "model_version": None,
    }


def test_me_rejects_missing_credentials(stub):
    with _client(stub) as client:
        response = client.get("/api/v1/auth/me")
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "invalid_token"
    assert response.headers["www-authenticate"] == "Bearer"


def test_me_rejects_malformed_authorization_header(stub):
    with _client(stub) as client:
        response = client.get(
            "/api/v1/auth/me", headers={"Authorization": "Token abc"}
        )
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "invalid_token"


def test_me_rejects_raw_token_without_bearer_scheme(stub, keypair):
    # Swagger antepone "Bearer " a partir del esquema http/bearer; sin él, 401.
    token = sign_token(keypair)
    with _client(stub) as client:
        response = client.get(
            "/api/v1/auth/me", headers={"Authorization": token}
        )
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "invalid_token"


def test_me_rejects_invalid_token(stub):
    with _client(stub) as client:
        response = client.get(
            "/api/v1/auth/me", headers={"Authorization": "Bearer not.a.jwt"}
        )
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "invalid_token"


def test_me_tolerates_double_bearer_prefix(stub, keypair):
    # Swagger ya añade "Bearer "; si el usuario lo escribe también, se recorta.
    token = sign_token(keypair)
    with _client(stub) as client:
        response = client.get(
            "/api/v1/auth/me", headers={"Authorization": f"Bearer Bearer {token}"}
        )
    assert response.status_code == 200
    assert response.json()["account"]["id"] == SUBJECT


def test_me_tolerates_surrounding_whitespace(stub, keypair):
    token = sign_token(keypair)
    with _client(stub) as client:
        response = client.get(
            "/api/v1/auth/me", headers={"Authorization": f"Bearer   {token}  "}
        )
    assert response.status_code == 200


def test_me_tolerates_quoted_token(stub, keypair):
    token = sign_token(keypair)
    with _client(stub) as client:
        response = client.get(
            "/api/v1/auth/me", headers={"Authorization": f'Bearer "{token}"'}
        )
    assert response.status_code == 200


def test_me_rejects_blank_credentials(stub):
    with _client(stub) as client:
        response = client.get(
            "/api/v1/auth/me", headers={"Authorization": "Bearer    "}
        )
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "invalid_token"


def test_me_returns_validated_identity(stub, keypair):
    token = sign_token(keypair)
    with _client(stub) as client:
        response = client.get(
            "/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"}
        )
    assert response.status_code == 200
    assert response.json() == {"account": {"id": SUBJECT, "email": EMAIL}}


def test_me_email_is_null_when_absent(stub, keypair):
    token = sign_token(keypair, email=None)
    with _client(stub) as client:
        response = client.get(
            "/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"}
        )
    assert response.status_code == 200
    assert response.json()["account"] == {"id": SUBJECT, "email": None}


def test_me_returns_503_when_jwks_unavailable(stub, keypair):
    stub.status = 500
    token = sign_token(keypair)
    with _client(stub) as client:
        response = client.get(
            "/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"}
        )
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "service_unavailable"
    assert response.headers["retry-after"] == "5"


def test_me_owner_comes_from_sub_claim(stub, keypair):
    other_sub = "22222222-2222-2222-2222-222222222222"
    token = sign_token(keypair, sub=other_sub)
    with _client(stub) as client:
        response = client.get(
            "/api/v1/auth/me", headers={"Authorization": f"Bearer {token}"}
        )
    assert response.json()["account"]["id"] == other_sub
