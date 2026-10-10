from fastapi.testclient import TestClient

from app.core.config import Settings
from app.main import create_app


def test_health_route_is_public_and_reports_model_state() -> None:
    app = create_app(Settings(_env_file=None))
    with TestClient(app) as client:
        response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "model_ready": False}


def test_missing_route_uses_error_envelope() -> None:
    app = create_app(Settings(_env_file=None))
    with TestClient(app) as client:
        response = client.post("/api/v1/auth/login", json={})
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "not_found"


def test_openapi_exposes_expected_routes() -> None:
    schema = create_app(Settings(_env_file=None)).openapi()
    assert set(schema["paths"]) == {"/api/v1/health", "/api/v1/auth/me"}
