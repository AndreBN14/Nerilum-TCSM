import uuid

from e2e.images import load_image


def test_legacy_analyze_idempotency(api, e2e_config, created_ids):
    image = load_image(e2e_config)
    key = "e2e-" + uuid.uuid4().hex

    def send(name):
        return api.post(
            "/analyses",
            headers={"Idempotency-Key": key},
            data={"display_name": name},
            files={"file": ("e2e-scan.png", image, "image/png")},
        )

    first = send("E2E idempotencia")
    assert first.status_code in (200, 201), first.text
    record = first.json()
    created_ids.append(record["id"])

    second = send("E2E idempotencia")
    assert second.status_code in (200, 201), second.text
    replay = second.json()
    assert replay["id"] == record["id"]
    assert replay["display_name"] == record["display_name"]
    assert replay["probability"] == record["probability"]

    conflict = send("E2E distinto")
    assert conflict.status_code == 409, conflict.text
    assert conflict.json()["error"]["code"] == "idempotency_conflict"
