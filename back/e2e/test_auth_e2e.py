import httpx


def test_auth_me_with_real_token(api):
    response = api.get("/auth/me")
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["account"]["id"]
    assert body["account"]["email"]


def test_auth_me_without_token(e2e_config):
    with httpx.Client(base_url=e2e_config.api_base_url, timeout=30) as client:
        response = client.get("/auth/me")
    assert response.status_code == 401, response.text
    assert response.json()["error"]["code"] == "invalid_token"


def test_auth_me_with_invalid_token(e2e_config):
    headers = {"Authorization": "Bearer token-invalido"}
    with httpx.Client(
        base_url=e2e_config.api_base_url,
        headers=headers,
        timeout=30,
    ) as client:
        response = client.get("/auth/me")
    assert response.status_code == 401, response.text
