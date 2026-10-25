"""Flujo v2: inferir sin insertar y guardar solo tras la decisión del usuario."""

import base64
import hmac
import json
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from io import BytesIO

from fastapi.testclient import TestClient
from PIL import Image

from conftest import FakeInference, build_app, build_verifier, sign_token

SECRET = "test-proof-secret-0123456789-at-least-32-chars"


def _png():
    buffer = BytesIO()
    Image.new("RGB", (16, 16), "grey").save(buffer, format="PNG")
    return buffer.getvalue()


def _app(stub, inference=None, secret=SECRET):
    return build_app(build_verifier(stub), inference=inference or FakeInference(),
                     settings_overrides={"analysis_proof_secret": secret})


def _headers(keypair, sub=None):
    return {"Authorization": f"Bearer {sign_token(keypair, **({'sub': sub} if sub else {}))}"}


def _preview(client, headers):
    return client.post("/api/v1/analyses/preview", headers=headers,
                       files={"file": ("scan.png", _png(), "image/png")})


def _save(client, headers, proof, name=" Control "):
    return client.post("/api/v1/analyses/save", headers=headers,
                       json={"save_proof": proof, "display_name": name})


def _resign(proof, changes):
    encoded = proof.split(".")[0]
    data = json.loads(base64.urlsafe_b64decode(encoded + "=" * (-len(encoded) % 4)))
    data.update(changes)
    text = base64.urlsafe_b64encode(
        json.dumps(data, sort_keys=True, separators=(",", ":")).encode()).rstrip(b"=").decode()
    signature = base64.urlsafe_b64encode(
        hmac.digest(SECRET.encode(), text.encode(), "sha256")).rstrip(b"=").decode()
    return f"{text}.{signature}"


def test_preview_then_discard_never_writes(stub, keypair):
    class CountingInference(FakeInference):
        calls = 0

        def analyze(self, image):
            self.calls += 1
            return super().analyze(image)

    inference = CountingInference()
    with TestClient(_app(stub, inference)) as client:
        headers = _headers(keypair)
        response = _preview(client, headers)
        history = client.get("/api/v1/analyses", headers=headers)
    assert response.status_code == 200
    data = response.json()
    assert data["preview_id"].startswith("an_")
    assert data["scores"][data["category"]] == data["probability"]
    assert data["save_proof"]
    assert inference.calls == 1
    assert history.json()["total"] == 0


def test_save_without_reinference_is_idempotent_and_can_rename_before_save(stub, keypair):
    class CountingInference(FakeInference):
        calls = 0

        def analyze(self, image):
            self.calls += 1
            return super().analyze(image)

    inference = CountingInference()
    with TestClient(_app(stub, inference)) as client:
        headers = _headers(keypair)
        preview = _preview(client, headers).json()
        first = _save(client, headers, preview["save_proof"])
        again = _save(client, headers, preview["save_proof"], "Control")
        other_name = _save(client, headers, preview["save_proof"], "Otro")
        history = client.get("/api/v1/analyses", headers=headers).json()
    assert first.status_code == 201
    assert again.status_code == 200
    assert first.json() == again.json()
    assert first.json()["id"] == preview["preview_id"]
    assert first.json()["created_at"] == preview["created_at"]
    assert first.json()["display_name"] == "Control"
    assert other_name.status_code == 409
    assert other_name.json()["error"]["code"] == "idempotency_conflict"
    assert history["total"] == 1
    assert inference.calls == 1


def test_proof_cannot_be_forged_or_used_by_another_account(stub, keypair):
    bob = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    with TestClient(_app(stub)) as client:
        alice_headers = _headers(keypair)
        proof = _preview(client, alice_headers).json()["save_proof"]
        modified = _resign(proof, {"probability": 0.99})
        modified = modified[:-1] + ("A" if modified[-1] != "A" else "B")
        forged = _save(client, alice_headers, modified)
        other_user = _save(client, _headers(keypair, bob), proof)
        count = client.get("/api/v1/analyses", headers=alice_headers).json()["total"]
    assert forged.status_code == other_user.status_code == 422
    assert count == 0


def test_expired_proof_cannot_create_but_can_replay_saved_result(stub, keypair):
    with TestClient(_app(stub)) as client:
        headers = _headers(keypair)
        proof = _preview(client, headers).json()["save_proof"]
        past = datetime.now(timezone.utc) - timedelta(hours=2)
        expired = _resign(proof, {
            "created_at": past.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "expires_at": (past + timedelta(minutes=30)).strftime("%Y-%m-%dT%H:%M:%SZ"),
        })
        rejected = _save(client, headers, expired)
        first = _save(client, headers, proof)
        replay = _save(client, headers, expired)
    assert rejected.status_code == 422
    assert first.status_code == 201
    assert replay.status_code == 200
    assert first.json() == replay.json()


def test_feature_without_secret_does_not_break_legacy_post(stub, keypair):
    with TestClient(_app(stub, secret="")) as client:
        headers = _headers(keypair)
        unavailable = _preview(client, headers)
        legacy = client.post("/api/v1/analyses", headers=headers,
                             files={"file": ("scan.png", _png(), "image/png")})
    assert unavailable.status_code == 503
    assert legacy.status_code == 201


def test_concurrent_save_of_same_proof_has_one_record(stub, keypair):
    with TestClient(_app(stub)) as client:
        headers = _headers(keypair)
        proof = _preview(client, headers).json()["save_proof"]
        with ThreadPoolExecutor(max_workers=2) as executor:
            first = executor.submit(_save, client, headers, proof)
            second = executor.submit(_save, client, headers, proof)
            results = [first.result(timeout=10), second.result(timeout=10)]
        count = client.get("/api/v1/analyses", headers=headers).json()["total"]
    assert sorted(r.status_code for r in results) == [200, 201]
    assert results[0].json() == results[1].json()
    assert count == 1
