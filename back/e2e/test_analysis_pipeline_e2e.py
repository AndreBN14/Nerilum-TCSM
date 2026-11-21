def test_preview_save_image_history_and_pdf_data(api, saved_analysis):
    record, name, image, proof = saved_analysis
    analysis_id = record["id"]
    assert record["has_image"] is True
    assert record["display_name"] == name

    detail = api.get(f"/analyses/{analysis_id}")
    assert detail.status_code == 200, detail.text
    assert detail.json()["has_image"] is True

    history = api.get("/analyses", params={"limit": 100, "offset": 0})
    assert history.status_code == 200, history.text
    items = history.json()["items"]
    match = next(item for item in items if item["id"] == analysis_id)
    assert match["has_image"] is True
    assert match["display_name"] == name

    downloaded = api.get(f"/analyses/{analysis_id}/image")
    assert downloaded.status_code == 200, downloaded.text
    assert downloaded.headers["content-type"].startswith("image/png")
    assert downloaded.content.startswith(b"\x89PNG")
    assert downloaded.content == image

    replay = api.post(
        "/analyses/save-with-image",
        data={"save_proof": proof, "display_name": name},
        files={"file": ("e2e-scan.png", image, "image/png")},
    )
    assert replay.status_code == 200, replay.text
    assert replay.json()["id"] == analysis_id
