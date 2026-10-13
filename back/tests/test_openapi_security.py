"""Pruebas del esquema HTTP Bearer expuesto en OpenAPI para Swagger UI.

Comprueban que `/docs` puede mostrar el botón `Authorize` (esquema declarado),
que `/api/v1/auth/me` lo referencia como requisito, y que el esquema es
`http`/`bearer`, lo que hace que Swagger anteponga `Bearer ` automáticamente.
"""

from pathlib import Path

from fastapi.testclient import TestClient

from app.core.categories import Category
from app.core.config import Settings
from app.main import create_app

SCHEME = "HTTPBearer"
ME_PATH = "/api/v1/auth/me"


def _app(tmp_path: Path):
    # database_path temporal: la suite nunca debe escribir en back/data/.
    return create_app(
        Settings(
            _env_file=None,
            model_dir=None,
            database_path=tmp_path / "openapi.db",
        )
    )


def test_http_bearer_scheme_is_declared_in_openapi(tmp_path):
    schema = _app(tmp_path).openapi()
    scheme = schema["components"]["securitySchemes"][SCHEME]
    assert scheme["type"] == "http"
    assert scheme["scheme"] == "bearer"
    assert scheme["bearerFormat"] == "JWT"


def test_auth_me_references_bearer_security(tmp_path):
    schema = _app(tmp_path).openapi()
    operation = schema["paths"][ME_PATH]["get"]
    assert operation["security"] == [{SCHEME: []}]


def test_served_openapi_declares_scheme_and_reference(tmp_path):
    with TestClient(_app(tmp_path)) as client:
        schema = client.get("/openapi.json").json()
    assert schema["components"]["securitySchemes"][SCHEME]["scheme"] == "bearer"
    assert schema["paths"][ME_PATH]["get"]["security"] == [{SCHEME: []}]


def test_documentation_responses_are_not_cached(tmp_path):
    with TestClient(_app(tmp_path)) as client:
        openapi_response = client.get("/openapi.json")
        docs_response = client.get("/docs")
    assert openapi_response.headers["cache-control"] == "no-store"
    assert docs_response.headers["cache-control"] == "no-store"


def test_business_endpoints_are_not_marked_no_store(tmp_path):
    with TestClient(_app(tmp_path)) as client:
        response = client.get("/api/v1/health")
    assert "cache-control" not in response.headers


def test_openapi_exposes_category_enum_and_scores_properties(tmp_path):
    schema = _app(tmp_path).openapi()
    schemas = schema["components"]["schemas"]

    expected = [category.value for category in Category]
    assert schemas["Category"]["enum"] == expected

    scores = schemas["Scores"]
    assert set(scores["properties"]) == set(expected)
    assert set(scores["required"]) == set(expected)
