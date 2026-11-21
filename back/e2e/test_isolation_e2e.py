import httpx

from e2e.config import E2EConfig
from e2e.images import load_image


def test_other_account_cannot_read_analysis(
    e2e_config,
    second_token,
    saved_analysis,
):
    analysis_id = saved_analysis[0]["id"]
    headers = {"Authorization": f"Bearer {second_token}"}
    with httpx.Client(
        base_url=e2e_config.api_base_url,
        headers=headers,
        timeout=60,
    ) as client:
        response = client.get(f"/analyses/{analysis_id}")
    assert response.status_code == 404, response.text


def test_other_account_cannot_download_image(
    e2e_config,
    second_token,
    saved_analysis,
):
    analysis_id = saved_analysis[0]["id"]
    headers = {"Authorization": f"Bearer {second_token}"}
    with httpx.Client(
        base_url=e2e_config.api_base_url,
        headers=headers,
        timeout=60,
    ) as client:
        response = client.get(f"/analyses/{analysis_id}/image")
    assert response.status_code == 404, response.text
