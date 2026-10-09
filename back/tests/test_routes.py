from fastapi.testclient import TestClient

from app.core.config import Settings
from app.main import create_app


def test_health_reports_unavailable_model() -> None:
    with TestClient(create_app(Settings(_env_file=None))) as client:
        response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "model_ready": False}


def test_missing_routes_use_error_envelope() -> None:
    with TestClient(create_app(Settings(_env_file=None))) as client:
        response = client.post("/api/v1/auth/login", json={})
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "not_found"


def test_openapi_exposes_only_approved_health_route() -> None:
    schema = create_app(Settings(_env_file=None)).openapi()
    assert set(schema["paths"]) == {"/api/v1/health"}
