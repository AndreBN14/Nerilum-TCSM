import base64
import json
import uuid

import httpx
import pytest

from e2e.config import E2EConfig
from e2e.images import load_image


def decode_sub(token):
    payload = token.split(".")[1]
    payload += "=" * (-len(payload) % 4)
    return json.loads(base64.urlsafe_b64decode(payload).decode())["sub"]


def fetch_token(config, email, password):
    response = httpx.post(
        f"{config.supabase_url}/auth/v1/token",
        params={"grant_type": "password"},
        headers={"apikey": config.supabase_key, "Content-Type": "application/json"},
        json={"email": email, "password": password},
        timeout=30,
    )
    if response.status_code >= 400:
        pytest.fail(f"Supabase Auth E2E falló: {response.status_code} {response.text}")
    return response.json()["access_token"]


@pytest.fixture(scope="session")
def e2e_config():
    config = E2EConfig.from_env()
    missing = config.missing()
    if missing:
        pytest.skip("Faltan variables E2E: " + ", ".join(missing))
    return config


@pytest.fixture(scope="session")
def access_token(e2e_config):
    return fetch_token(e2e_config, e2e_config.email, e2e_config.password)


@pytest.fixture(scope="session")
def second_token(e2e_config):
    if not e2e_config.second_email or not e2e_config.second_password:
        pytest.skip("Configura E2E_SECOND_EMAIL y E2E_SECOND_PASSWORD")
    return fetch_token(e2e_config, e2e_config.second_email, e2e_config.second_password)


@pytest.fixture
def api(e2e_config, access_token):
    with httpx.Client(
        base_url=e2e_config.api_base_url,
        headers={
            "Authorization": f"Bearer {access_token}",
            "Accept": "application/json",
        },
        timeout=120,
    ) as client:
        yield client


@pytest.fixture
def created_ids(e2e_config, access_token):
    ids = []
    yield ids
    if not ids or not e2e_config.service_role_key:
        return
    headers = {
        "apikey": e2e_config.service_role_key,
        "Authorization": f"Bearer {e2e_config.service_role_key}",
        "Prefer": "return=minimal",
    }
    with httpx.Client(
        base_url=e2e_config.supabase_url,
        headers=headers,
        timeout=60,
    ) as client:
        client.delete(
            "/rest/v1/analyses",
            params={
                "id": "in.(" + ",".join(ids) + ")",
                "account_id": "eq." + decode_sub(access_token),
            },
        )


@pytest.fixture
def saved_analysis(api, e2e_config, created_ids):
    image = load_image(e2e_config)
    name = "E2E " + uuid.uuid4().hex[:8]
    preview = api.post(
        "/analyses/preview",
        files={"file": ("e2e-scan.png", image, "image/png")},
    )
    assert preview.status_code in (200, 201), preview.text
    proof = preview.json()["save_proof"]
    saved = api.post(
        "/analyses/save-with-image",
        data={"save_proof": proof, "display_name": name},
        files={"file": ("e2e-scan.png", image, "image/png")},
    )
    assert saved.status_code in (200, 201), saved.text
    record = saved.json()
    created_ids.append(record["id"])
    return record, name, image, proof
