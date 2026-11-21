from e2e.images import load_image


def test_invalid_image_is_rejected(api, e2e_config):
    response = api.post(
        "/analyses/preview",
        files={"file": ("roto.png", b"no es una imagen", "image/png")},
    )
    assert response.status_code in (400, 415, 422), response.text
    assert "error" in response.json()


def test_preview_does_not_persist(api, e2e_config):
    image = load_image(e2e_config)
    before = api.get("/analyses", params={"limit": 100, "offset": 0}).json()["total"]
    preview = api.post(
        "/analyses/preview",
        files={"file": ("e2e-scan.png", image, "image/png")},
    )
    assert preview.status_code in (200, 201), preview.text
    after = api.get("/analyses", params={"limit": 100, "offset": 0}).json()["total"]
    assert after == before
