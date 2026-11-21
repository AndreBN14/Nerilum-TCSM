from urllib.parse import urlsplit

from e2e.config import E2EConfig


def test_missing_configuration_is_reported():
    config = E2EConfig.from_env()
    assert isinstance(config.missing(), list)


def test_health(api):
    response = api.get("/health")
    assert response.status_code == 200, response.text
    body = response.json()
    assert isinstance(body["model_ready"], bool)


def test_openapi_exposes_required_routes(api, e2e_config):
    parsed = urlsplit(e2e_config.api_base_url)
    root = f"{parsed.scheme}://{parsed.netloc}"
    response = api.get(f"{root}/openapi.json")
    assert response.status_code == 200, response.text
    paths = response.json()["paths"]
    required = [
        "/api/v1/analyses/preview",
        "/api/v1/analyses/save",
        "/api/v1/analyses/save-with-image",
        "/api/v1/analyses/{analysis_id}/image",
    ]
    for path in required:
        assert path in paths, path
