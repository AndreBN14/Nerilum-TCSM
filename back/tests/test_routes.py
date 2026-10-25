from fastapi.testclient import TestClient

from app.core.config import Settings
from app.main import create_app


def test_health_route_is_public_and_reports_model_state(tmp_path) -> None:
    app = create_app(Settings(_env_file=None, model_dir=None, database_path=tmp_path / "h.db"))
    with TestClient(app) as client:
        response = client.get("/api/v1/health")
    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "model_ready": False,
        "model_name": None,
        "model_version": None,
    }


def test_missing_route_uses_error_envelope(tmp_path) -> None:
    app = create_app(Settings(_env_file=None, model_dir=None, database_path=tmp_path / "h.db"))
    with TestClient(app) as client:
        response = client.post("/api/v1/auth/login", json={})
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "not_found"


def test_method_not_allowed_uses_error_envelope(tmp_path) -> None:
    app = create_app(Settings(_env_file=None, model_dir=None, database_path=tmp_path / "h.db"))
    with TestClient(app) as client:
        response = client.delete("/api/v1/health")
    assert response.status_code == 405
    assert response.json()["error"]["code"] == "method_not_allowed"


def test_openapi_exposes_expected_routes(tmp_path) -> None:
    schema = create_app(
        Settings(_env_file=None, model_dir=None, database_path=tmp_path / "h.db")
    ).openapi()
    assert set(schema["paths"]) == {
        "/api/v1/health",
        "/api/v1/auth/me",
        "/api/v1/analyses",
        "/api/v1/analyses/preview",
        "/api/v1/analyses/save",
        "/api/v1/analyses/{analysis_id}",
    }
