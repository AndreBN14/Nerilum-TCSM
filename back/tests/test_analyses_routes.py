"""Pruebas de /api/v1/analyses (crear, historial paginado y detalle)."""

from __future__ import annotations

import logging
from io import BytesIO

import pytest
from conftest import (
    FakeInference,
    build_app,
    build_verifier,
    sign_token,
)
from fastapi.testclient import TestClient
from PIL import Image

from app.core.categories import Category
from app.core.errors import ApiException
from app.routes.analyses import MAX_DISPLAY_NAME_LENGTH, _clean_display_name


def _app(stub, *, inference=None, db_path=None, settings_overrides=None) -> TestClient:
    return TestClient(
        build_app(
            build_verifier(stub),
            inference=inference,
            db_path=db_path,
            settings_overrides=settings_overrides,
        )
    )


def _png_bytes(color=(120, 60, 30), size=(64, 64)) -> bytes:
    buffer = BytesIO()
    Image.new("RGB", size, color).save(buffer, format="PNG")
    return buffer.getvalue()


def _png_download(payload: bytes, name: str = "scan.png", form: dict | None = None):
    data = form or {}
    return {
        "file": (name, payload, "image/png"),
        **{k: (None, v) for k, v in data.items()},
    }


def _bearer(token):
    return {"Authorization": f"Bearer {token}"}


def test_create_requires_auth(stub):
    with _app(stub) as client:
        response = client.post(
            "/api/v1/analyses",
            files=_png_download(_png_bytes()),
        )
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "invalid_token"


def test_create_returns_503_when_model_not_ready(stub, keypair):
    payload = _png_bytes()
    token = sign_token(keypair)
    with _app(stub) as client:
        response = client.post(
            "/api/v1/analyses",
            headers=_bearer(token),
            files=_png_download(payload),
        )
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "model_unavailable"
    assert response.headers["retry-after"] == "5"


def test_create_503_retry_after_follows_setting(stub, keypair):
    payload = _png_bytes()
    token = sign_token(keypair)
    with _app(stub, settings_overrides={"retry_after_seconds": 7}) as client:
        response = client.post(
            "/api/v1/analyses",
            headers=_bearer(token),
            files=_png_download(payload),
        )
    assert response.status_code == 503
    assert response.headers["retry-after"] == "7"


def test_create_valid_png(stub, keypair):
    token = sign_token(keypair)
    inference = FakeInference()
    with _app(
        stub,
        inference=inference,
    ) as client:
        response = client.post(
            "/api/v1/analyses",
            headers=_bearer(token),
            files=_png_download(_png_bytes(), "mi_scan.png", {"display_name": "MRI 1"}),
        )
    body = response.json()
    assert response.status_code == 201
    assert body["category"] == "NonDemented"
    assert body["probability"] == 0.5
    assert body["scores"] == {
        "MildDemented": 0.1,
        "ModerateDemented": 0.2,
        "NonDemented": 0.5,
        "VeryMildDemented": 0.2,
    }
    assert body["display_name"] == "MRI 1"
    assert body["is_demo"] is False
    assert body["model"] == {"name": "fake-cls", "version": "test", "dataset": "ADNI"}
    assert body["id"].startswith("an_")
    assert body["created_at"]
    assert body["disclaimer"]


def test_rejects_text_body(stub, keypair):
    token = sign_token(keypair)
    with _app(stub, inference=FakeInference()) as client:
        response = client.post(
            "/api/v1/analyses",
            headers=_bearer(token),
            files=_png_download(b"hola mundo", "file.png"),
        )
    assert response.status_code == 415
    assert response.json()["error"]["code"] == "unsupported_media_type"


def test_create_trims_display_name(stub, keypair):
    token = sign_token(keypair)
    with _app(stub, inference=FakeInference()) as client:
        response = client.post(
            "/api/v1/analyses",
            headers=_bearer(token),
            files=_png_download(_png_bytes(), form={"display_name": "  MRI 1  "}),
        )
    assert response.status_code == 201
    assert response.json()["display_name"] == "MRI 1"


def test_create_blank_display_name_becomes_null(stub, keypair):
    token = sign_token(keypair)
    with _app(stub, inference=FakeInference()) as client:
        response = client.post(
            "/api/v1/analyses",
            headers=_bearer(token),
            files=_png_download(_png_bytes(), form={"display_name": "   "}),
        )
    assert response.status_code == 201
    assert response.json()["display_name"] is None


def test_create_omitted_display_name_is_null(stub, keypair):
    token = sign_token(keypair)
    with _app(stub, inference=FakeInference()) as client:
        response = client.post(
            "/api/v1/analyses",
            headers=_bearer(token),
            files=_png_download(_png_bytes()),
        )
    assert response.status_code == 201
    assert response.json()["display_name"] is None


def test_create_measures_length_after_trim(stub, keypair):
    token = sign_token(keypair)
    name = "a" * MAX_DISPLAY_NAME_LENGTH
    with _app(stub, inference=FakeInference()) as client:
        response = client.post(
            "/api/v1/analyses",
            headers=_bearer(token),
            files=_png_download(_png_bytes(), form={"display_name": f"  {name}  "}),
        )
    assert response.status_code == 201
    assert response.json()["display_name"] == name


def test_create_rejects_overlong_display_name(stub, keypair):
    token = sign_token(keypair)
    with _app(stub, inference=FakeInference()) as client:
        response = client.post(
            "/api/v1/analyses",
            headers=_bearer(token),
            files=_png_download(
                _png_bytes(),
                form={"display_name": "a" * (MAX_DISPLAY_NAME_LENGTH + 1)},
            ),
        )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


@pytest.mark.parametrize("bad", ["MRI\x00", "MRI\x07", "MRI\n1"])
def test_create_rejects_control_chars_in_display_name(stub, keypair, bad):
    token = sign_token(keypair)
    with _app(stub, inference=FakeInference()) as client:
        response = client.post(
            "/api/v1/analyses",
            headers=_bearer(token),
            files=_png_download(_png_bytes(), form={"display_name": bad}),
        )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"


def test_clean_display_name_unit():
    assert _clean_display_name(None) is None
    assert _clean_display_name("   ") is None
    assert _clean_display_name("  MRI 1  ") == "MRI 1"
    with pytest.raises(ApiException):
        _clean_display_name("x" * (MAX_DISPLAY_NAME_LENGTH + 1))
    with pytest.raises(ApiException):
        _clean_display_name("MRI\x1f1")


def test_create_ignores_extension_and_content_type(stub, keypair):
    token = sign_token(keypair)
    buf = io.BytesIO()
    Image.new("RGB", (32, 32), (5, 5, 5)).save(buf, format="PNG")
    data = buf.getvalue()

    with _app(stub, inference=FakeInference()) as client:
        response = client.post(
            "/api/v1/analyses",
            data={"display_name": "Muestra"},
            files={"file": ("muestra.txt", data, "text/plain")},
            headers=_bearer(token),
        )
        assert response.status_code == 201


def test_create_rejects_truncated_image(stub, keypair):
    token = sign_token(keypair)
    fake_jpeg = b"\xff\xd8\xff\xe0" + b"\x00" * 64
    with _app(stub, inference=FakeInference()) as client:
        response = client.post(
            "/api/v1/analyses",
            headers=_bearer(token),
            files=_png_download(fake_jpeg, "scan.jpg"),
        )
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "invalid_image"


def test_create_rejects_oversized_upload(stub, keypair):
    token = sign_token(keypair)
    # Imagen con ruido para que el PNG no comprima bien y supere el límite.
    buffer = BytesIO()
    Image.effect_noise((256, 256), 128).convert("RGB").save(buffer, format="PNG")
    noisy = buffer.getvalue()
    with _app(
        stub,
        inference=FakeInference(),
        settings_overrides={"max_image_bytes": 10_000},
    ) as client:
        response = client.post(
            "/api/v1/analyses",
            headers=_bearer(token),
            files=_png_download(noisy, "scan.png"),
        )
    assert response.status_code == 413
    assert response.json()["error"]["code"] == "too_large"


def test_records_are_isolated_per_account(stub, keypair):
    alice = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    bob = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    with _app(stub, inference=FakeInference()) as client:
        response_a = client.post(
            "/api/v1/analyses",
            headers=_bearer(sign_token(keypair, sub=alice)),
            files=_png_download(_png_bytes()),
        )
        response_b = client.post(
            "/api/v1/analyses",
            headers=_bearer(sign_token(keypair, sub=bob)),
            files=_png_download(_png_bytes()),
        )
        analysis_id = response_a.json()["id"]

        list_b = client.get(
            "/api/v1/analyses",
            headers=_bearer(sign_token(keypair, sub=bob)),
        )
        detail_b = client.get(
            f"/api/v1/analyses/{analysis_id}",
            headers=_bearer(sign_token(keypair, sub=bob)),
        )
        detail_a = client.get(
            f"/api/v1/analyses/{analysis_id}",
            headers=_bearer(sign_token(keypair, sub=alice)),
        )

    assert response_a.status_code == 201
    assert response_b.status_code == 201
    assert list_b.json()["total"] == 1
    assert detail_b.status_code == 404
    assert detail_b.json()["error"]["code"] == "not_found"
    assert detail_a.status_code == 200
    assert detail_a.json()["id"] == analysis_id


def test_extra_form_fields_do_not_supplant_auth(stub, keypair):
    # El account_id SIEMPRE viene del token verificado, no del formulario.
    alice = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    bob = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    with _app(stub, inference=FakeInference()) as client:
        response = client.post(
            "/api/v1/analyses",
            headers=_bearer(sign_token(keypair, sub=alice)),
            files=_png_download(
                _png_bytes(),
                form={"account_id": bob, "display_name": "spoof"},
            ),
        )
        for_other = client.get(
            "/api/v1/analyses",
            headers=_bearer(sign_token(keypair, sub=bob)),
        )
    assert response.status_code == 201
    assert for_other.json()["total"] == 0


def test_list_empty_and_pagination(stub, keypair, tmp_path):
    token = sign_token(keypair)
    with _app(stub, inference=FakeInference(), db_path=tmp_path / "db.sqlite") as client:
        empty = client.get("/api/v1/analyses", headers=_bearer(token))
        assert empty.status_code == 200
        assert empty.json() == {"items": [], "total": 0, "limit": 50, "offset": 0}

        for color in [(255, 0, 0), (0, 255, 0), (0, 0, 255)]:
            client.post(
                "/api/v1/analyses",
                headers=_bearer(token),
                files=_png_download(_png_bytes(color=color)),
            )
        page1 = client.get(
            "/api/v1/analyses", headers=_bearer(token), params={"limit": 2, "offset": 0}
        )
        page2 = client.get(
            "/api/v1/analyses", headers=_bearer(token), params={"limit": 2, "offset": 2}
        )
        invalid = client.get(
            "/api/v1/analyses", headers=_bearer(token), params={"limit": 0}
        )

    assert page1.status_code == 200
    assert page1.json()["total"] == 3
    assert len(page1.json()["items"]) == 2
    page1_ids = [item["id"] for item in page1.json()["items"]]
    page2_ids = [item["id"] for item in page2.json()["items"]]
    assert len(set(page1_ids + page2_ids)) == 3
    assert page2.json()["total"] == 3
    assert invalid.status_code == 422
    assert invalid.json()["error"]["code"] == "validation_error"


def test_get_missing_analysis_returns_404(stub, keypair):
    token = sign_token(keypair)
    with _app(stub, inference=FakeInference()) as client:
        response = client.get(
            "/api/v1/analyses/no-such-id", headers=_bearer(token)
        )
    assert response.status_code == 404
    assert response.json()["error"]["code"] == "not_found"


def test_seed_demo_is_idempotent_and_route_never_marks_demo(stub, keypair, tmp_path):
    from app.core.categories import Category
    from app.core.model_info import ModelInfo
    from app.services.analyses import SqliteAnalysisRepository

    db = tmp_path / "seed.db"
    repo = SqliteAnalysisRepository(db)
    demo_account = "99999999-9999-9999-9999-999999999999"
    model_info = ModelInfo(
        name="yolov8n-cls",
        version="v0.1",
        dataset="Alzheimer MRI Dataset (Kaggle)",
        classes=[category.value for category in Category],
    )
    repo.seed_demo(demo_account, model_info)
    repo.seed_demo(demo_account, model_info)
    items, total = repo.list_by_account(demo_account, limit=100, offset=0)
    assert total == 4
    assert all(item.is_demo for item in items)
    assert all(item.model_dataset == "Alzheimer MRI Dataset (Kaggle)" for item in items)

    # Un análisis creado por la API nunca lleva is_demo=true.
    token = sign_token(keypair, sub=demo_account)
    with _app(stub, inference=FakeInference(), db_path=db) as client:
        created = client.post(
            "/api/v1/analyses",
            headers=_bearer(token),
            files=_png_download(_png_bytes()),
        )
    assert created.status_code == 201
    assert created.json()["is_demo"] is False


def test_health_reports_model_metadata_when_loaded(stub):
    with TestClient(
        build_app(build_verifier(stub), inference=FakeInference())
    ) as client:
        response = client.get("/api/v1/health")
    assert response.json() == {
        "status": "ok",
        "model_ready": True,
        "model_name": "fake-cls",
        "model_version": "test",
    }


def test_scores_and_probability_coherence_in_serialized_json(stub, keypair):
    token = sign_token(keypair)
    with _app(stub, inference=FakeInference()) as client:
        created = client.post(
            "/api/v1/analyses",
            headers=_bearer(token),
            files=_png_download(_png_bytes()),
        ).json()
        detail = client.get(
            f"/api/v1/analyses/{created['id']}", headers=_bearer(token)
        ).json()

    for payload in (created, detail):
        assert payload["category"] == max(
            payload["scores"], key=payload["scores"].get
        )
        assert payload["probability"] == payload["scores"][payload["category"]]


def test_invalid_category_row_returns_500_without_leaking(
    stub, keypair, tmp_path, caplog
):
    from app.services.analyses import AnalysisRecord, SqliteAnalysisRepository

    db = tmp_path / "bad.db"
    repo = SqliteAnalysisRepository(db)
    account = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    stored = repo.create(
        AnalysisRecord(
            account_id=account,
            category="NotAClass",
            probability=0.25,
            scores={category.value: 0.25 for category in Category},
            display_name="Paciente Secreto",
            model_name="yolov8n-cls",
            model_version="v0.1",
            model_dataset="Alzheimer MRI Dataset (Kaggle)",
        )
    )

    token = sign_token(keypair, sub=account)
    logger = logging.getLogger("nerilum")
    caplog.set_level(logging.WARNING, logger="nerilum")
    logger.addHandler(caplog.handler)
    try:
        with _app(stub, inference=FakeInference(), db_path=db) as client:
            response = client.get(
                f"/api/v1/analyses/{stored.id}", headers=_bearer(token)
            )
    finally:
        logger.removeHandler(caplog.handler)

    assert response.status_code == 500
    assert response.json() == {
        "error": {
            "code": "internal_error",
            "message": "Error interno del servidor.",
        }
    }
    assert stored.id in caplog.text
    assert "ValueError" in caplog.text
    assert account not in caplog.text
    assert "Paciente Secreto" not in caplog.text

def test_create_ignores_extension_and_content_type(auth_token, client):
    buf = io.BytesIO()
    Image.new("RGB", (32, 32), (5, 5, 5)).save(buf, format="PNG")
    data = buf.getvalue()

    response = client.post(
        "/api/v1/analyses",
        data={"display_name": "Muestra"},
        files={"file": ("muestra.txt", data, "text/plain")},
        headers=auth_token,
    )
    assert response.status_code == 201
