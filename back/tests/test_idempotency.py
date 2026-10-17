from concurrent.futures import ThreadPoolExecutor
from io import BytesIO
from threading import Barrier

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from conftest import FakeInference, build_app, build_verifier, sign_token
from app.core.idempotency import analysis_request_hash
from app.services.analyses import AnalysisRecord, SqliteAnalysisRepository


def _png(color="red"):
    buffer = BytesIO()
    Image.new("RGB", (32, 32), color).save(buffer, format="PNG")
    return buffer.getvalue()


def _headers(keypair, key="operation-1", account=None):
    token = sign_token(keypair, **({"sub": account} if account else {}))
    return {"Authorization": f"Bearer {token}", "Idempotency-Key": key}


def _post(client, headers, payload, name="MRI", filename="scan.png"):
    return client.post("/api/v1/analyses", headers=headers,
        files={"file": (filename, payload, "image/png")}, data={"display_name": name})


def test_replay_returns_original_even_if_model_is_now_unavailable(stub, keypair):
    class CountingInference(FakeInference):
        calls = 0

        def analyze(self, image):
            self.calls += 1
            return super().analyze(image)

    inference = CountingInference()
    app = build_app(build_verifier(stub), inference=inference)
    payload = _png()
    with TestClient(app) as client:
        headers = _headers(keypair)
        first = _post(client, headers, payload)
        inference.ready = False
        replay = _post(client, headers, payload, name="  MRI  ", filename="renamed.png")
        history = client.get("/api/v1/analyses", headers=headers)
    assert first.status_code == replay.status_code == 201
    assert first.json() == replay.json()
    assert inference.calls == 1
    assert history.json()["total"] == 1
    assert "idempotency_key" not in replay.json()
    assert "request_hash" not in replay.json()


@pytest.mark.parametrize("different_image", [False, True])
def test_key_with_other_content_returns_conflict(stub, keypair, different_image):
    with TestClient(build_app(build_verifier(stub), inference=FakeInference())) as client:
        headers = _headers(keypair)
        assert _post(client, headers, _png()).status_code == 201
        response = _post(client, headers,
            _png("blue") if different_image else _png(),
            name="MRI" if different_image else "Another name")
        history = client.get("/api/v1/analyses", headers=headers)
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "idempotency_conflict"
    assert history.json()["total"] == 1


def test_same_key_is_scoped_to_authenticated_account(stub, keypair):
    alice = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    bob = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    with TestClient(build_app(build_verifier(stub), inference=FakeInference())) as client:
        a_headers = _headers(keypair, account=alice)
        b_headers = _headers(keypair, account=bob)
        a = _post(client, a_headers, _png())
        b = _post(client, b_headers, _png("blue"))
        assert a.status_code == b.status_code == 201
        assert a.json()["id"] != b.json()["id"]
        for headers in (a_headers, b_headers):
            assert client.get("/api/v1/analyses", headers=headers).json()["total"] == 1


@pytest.mark.parametrize("key", ["", "with space", "bad/key", "x" * 129])
def test_invalid_key_is_rejected(stub, keypair, key):
    with TestClient(build_app(build_verifier(stub), inference=FakeInference())) as client:
        response = _post(client, _headers(keypair, key=key), _png())
    assert response.status_code == 422


def test_requests_without_key_keep_previous_behavior(stub, keypair):
    headers = _headers(keypair)
    del headers["Idempotency-Key"]
    with TestClient(build_app(build_verifier(stub), inference=FakeInference())) as client:
        first = _post(client, headers, _png())
        second = _post(client, headers, _png())
        history = client.get("/api/v1/analyses", headers=headers)
    assert first.status_code == second.status_code == 201
    assert first.json()["id"] != second.json()["id"]
    assert history.json()["total"] == 2


def test_failed_inference_does_not_consume_key(stub, keypair):
    inference = FakeInference(ready=False)
    app = build_app(build_verifier(stub), inference=inference)
    with TestClient(app) as client:
        headers = _headers(keypair)
        assert _post(client, headers, _png()).status_code == 503
        app.state.services.inference = FakeInference()
        assert _post(client, headers, _png()).status_code == 201
        assert client.get("/api/v1/analyses", headers=headers).json()["total"] == 1


@pytest.mark.parametrize("different_content", [False, True])
def test_concurrent_same_key_persists_only_one_record(stub, keypair, different_content):
    rendezvous = Barrier(2)

    class ConcurrentInference(FakeInference):
        def analyze(self, image):
            rendezvous.wait(timeout=10)
            return super().analyze(image)

    app = build_app(build_verifier(stub), inference=ConcurrentInference())
    with TestClient(app) as client:
        headers = _headers(keypair)
        with ThreadPoolExecutor(max_workers=2) as executor:
            first = executor.submit(_post, client, headers, _png())
            second = executor.submit(_post, client, headers,
                                     _png("blue") if different_content else _png())
            responses = [first.result(timeout=15), second.result(timeout=15)]
        history = client.get("/api/v1/analyses", headers=headers)
    assert history.json()["total"] == 1
    if different_content:
        assert sorted(response.status_code for response in responses) == [201, 409]
    else:
        assert all(response.status_code == 201 for response in responses)
        assert responses[0].json() == responses[1].json()


def test_replay_survives_sqlite_repository_restart(tmp_path):
    path = tmp_path / "history.db"
    repo = SqliteAnalysisRepository(path)
    record = AnalysisRecord(account_id="a", category="NonDemented", probability=0.5,
        scores={"NonDemented": 0.5}, model_name="test", model_version="1",
        model_dataset="test", idempotency_key="operation-1",
        request_hash=analysis_request_hash(b"bytes", None))
    repo.create(record)
    reopened = SqliteAnalysisRepository(path)
    assert reopened.get_by_idempotency_key("a", "operation-1", record.request_hash) == record


def test_existing_sqlite_history_is_preserved_during_schema_upgrade(tmp_path):
    path = tmp_path / "legacy.db"
    repo = SqliteAnalysisRepository(path)
    record = AnalysisRecord(account_id="a", category="NonDemented", probability=0.5,
        scores={"NonDemented": 0.5}, model_name="test", model_version="1", model_dataset="test")
    repo.create(record)
    with repo._connect() as conn:
        conn.execute("DROP INDEX idx_analyses_account_idempotency")
        conn.execute("ALTER TABLE analyses DROP COLUMN request_hash")
        conn.execute("ALTER TABLE analyses DROP COLUMN idempotency_key")
    reopened = SqliteAnalysisRepository(path)
    assert reopened.get_by_account(record.id, "a") == record


def test_cors_allows_idempotency_header_for_configured_web_origin(stub):
    app = build_app(build_verifier(stub), settings_overrides={
        "cors_origins": ["http://localhost:3000"],
    })
    with TestClient(app) as client:
        response = client.options("/api/v1/analyses", headers={
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "authorization,content-type,idempotency-key",
        })
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "http://localhost:3000"
