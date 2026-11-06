"""Contrato HTTP hacia Storage: original privado, sin sobrescribir reintentos."""

import httpx
import pytest

from app.core.errors import ApiException
from app.services.image_storage import SupabaseImageStorage


def test_private_bucket_upload_download_and_identical_retry():
    objects = {}
    requests = []

    def handler(request):
        requests.append(request)
        path = request.url.path
        if request.method == "POST":
            if path in objects:
                return httpx.Response(409)
            objects[path] = request.content
            return httpx.Response(200, json={"Key": path})
        if request.method == "GET" and path in objects:
            return httpx.Response(200, content=objects[path])
        return httpx.Response(404)

    client = httpx.Client(transport=httpx.MockTransport(handler))
    storage = SupabaseImageStorage("https://example.supabase.co", "test-server-key", client=client)
    path = "owner/an_abc.png"
    storage.put(path, b"first", "image/png")
    storage.put(path, b"first", "image/png")
    assert storage.get(path) == b"first"
    assert requests[0].headers["content-type"] == "image/png"
    assert requests[0].headers["x-upsert"] == "false"
    assert all(request.headers["authorization"] == "Bearer test-server-key" for request in requests)
    assert all(request.url.path.startswith("/storage/v1/object/analysis-images/") for request in requests)
    with pytest.raises(ApiException) as error:
        storage.put(path, b"different", "image/png")
    assert error.value.status_code == 409
    storage.close()


def test_storage_failure_does_not_accept_upload():
    client = httpx.Client(transport=httpx.MockTransport(lambda _: httpx.Response(503)))
    storage = SupabaseImageStorage("https://example.supabase.co", "test-server-key", client=client)
    with pytest.raises(ApiException) as error:
        storage.put("owner/an_abc.png", b"image", "image/png")
    assert error.value.status_code == 503
    storage.close()
