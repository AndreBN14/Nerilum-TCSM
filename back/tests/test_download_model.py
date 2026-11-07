"""Pruebas de ``scripts.download_model`` sin acceso a red.

Cubre la descarga directa desde una URL pública (sin token), la validación
SHA-256 de ``main()`` y los casos de error HTTP. ``urlopen`` se sustituye por
dobles: no se descarga ningún byte real.
"""

from __future__ import annotations

import hashlib
import io
import urllib.error
import urllib.request

import pytest

from scripts import download_model as dm

ASSET_NAME = dm.DEFAULT_FILENAME
PUBLIC_URL = dm.DEFAULT_URL
OTHER_URL = "https://example.com/other/path/model.onnx"


class _Response(io.BytesIO):
    """Respuesta mínima compatible con ``with`` y ``copyfileobj``."""

    def __enter__(self) -> "_Response":
        return self

    def __exit__(self, *exc: object) -> bool:
        self.close()
        return False


class _FakeHTTP:
    """Doble de ``urlopen`` que simula una descarga directa."""

    def __init__(self, body: bytes = b"ONNX-BYTES", status: int = 200) -> None:
        self.body = body
        self.status = status
        self.requests: list[urllib.request.Request] = []

    def urlopen(self, request, *args, **kwargs) -> _Response:
        if not isinstance(request, urllib.request.Request):
            request = urllib.request.Request(request)
        self.requests.append(request)
        if self.status != 200:
            raise urllib.error.HTTPError(
                request.full_url, self.status, "error", {}, None
            )
        return _Response(self.body)


@pytest.fixture(autouse=True)
def _clean_env(monkeypatch) -> None:
    monkeypatch.delenv("MODEL_TOKEN", raising=False)
    monkeypatch.delenv("GITHUB_TOKEN", raising=False)


def _install(monkeypatch, fake: _FakeHTTP) -> None:
    monkeypatch.setattr(urllib.request, "urlopen", fake.urlopen)


# ---------------------------------------------------------------------------
# _download_stream
# ---------------------------------------------------------------------------

def test_download_stream_fetches_url_directly(monkeypatch) -> None:
    fake = _FakeHTTP()
    _install(monkeypatch, fake)

    with dm._download_stream(PUBLIC_URL) as response:
        data = response.read()

    assert data == b"ONNX-BYTES"
    assert len(fake.requests) == 1
    assert fake.requests[0].full_url == PUBLIC_URL


def test_download_stream_sends_user_agent(monkeypatch) -> None:
    fake = _FakeHTTP()
    _install(monkeypatch, fake)

    dm._download_stream(PUBLIC_URL)

    assert fake.requests[0].get_header("User-agent") == "Nerilum-TCSM"


def test_download_stream_no_auth_header(monkeypatch) -> None:
    """La descarga pública no debe enviar ningún token de autorización."""
    fake = _FakeHTTP()
    _install(monkeypatch, fake)

    dm._download_stream(PUBLIC_URL)

    assert fake.requests[0].get_header("Authorization") is None


def test_download_stream_works_with_any_url(monkeypatch) -> None:
    fake = _FakeHTTP()
    _install(monkeypatch, fake)

    with dm._download_stream(OTHER_URL) as response:
        response.read()

    assert fake.requests[0].full_url == OTHER_URL


def test_download_stream_raises_url_error_on_http_error(monkeypatch) -> None:
    fake = _FakeHTTP(status=404)
    _install(monkeypatch, fake)

    with pytest.raises(urllib.error.URLError, match="404"):
        dm._download_stream(PUBLIC_URL)


# ---------------------------------------------------------------------------
# _filename
# ---------------------------------------------------------------------------

def test_filename_uses_env_override(monkeypatch) -> None:
    monkeypatch.setenv("MODEL_FILENAME", "custom.onnx")
    assert dm._filename(PUBLIC_URL) == "custom.onnx"


def test_filename_derived_from_url(monkeypatch) -> None:
    monkeypatch.delenv("MODEL_FILENAME", raising=False)
    assert dm._filename(PUBLIC_URL) == "best.onnx"


def test_filename_derived_from_other_url(monkeypatch) -> None:
    monkeypatch.delenv("MODEL_FILENAME", raising=False)
    assert dm._filename("https://example.com/weights/model_v2.onnx") == "model_v2.onnx"


# ---------------------------------------------------------------------------
# main(): descarga + SHA-256
# ---------------------------------------------------------------------------

def test_main_downloads_file(monkeypatch, tmp_path) -> None:
    body = b"MODEL-CONTENT"
    fake = _FakeHTTP(body=body)
    _install(monkeypatch, fake)
    monkeypatch.setenv("MODEL_URL", PUBLIC_URL)
    monkeypatch.setenv("MODEL_DIR", str(tmp_path))

    assert dm.main() == 0
    assert (tmp_path / ASSET_NAME).read_bytes() == body


def test_main_downloads_and_validates_sha(monkeypatch, tmp_path) -> None:
    body = b"MODEL-CONTENT"
    fake = _FakeHTTP(body=body)
    _install(monkeypatch, fake)
    monkeypatch.setenv("MODEL_URL", PUBLIC_URL)
    monkeypatch.setenv("MODEL_DIR", str(tmp_path))
    monkeypatch.setenv("MODEL_SHA256", hashlib.sha256(body).hexdigest())

    assert dm.main() == 0
    assert (tmp_path / ASSET_NAME).read_bytes() == body


def test_main_rejects_sha_mismatch(monkeypatch, tmp_path) -> None:
    fake = _FakeHTTP(body=b"ONNX-BYTES")
    _install(monkeypatch, fake)
    monkeypatch.setenv("MODEL_URL", PUBLIC_URL)
    monkeypatch.setenv("MODEL_DIR", str(tmp_path))
    monkeypatch.setenv("MODEL_SHA256", "0" * 64)

    assert dm.main() == 1
    assert not (tmp_path / ASSET_NAME).exists()


def test_main_returns_1_on_http_error(monkeypatch, tmp_path) -> None:
    fake = _FakeHTTP(status=404)
    _install(monkeypatch, fake)
    monkeypatch.setenv("MODEL_URL", PUBLIC_URL)
    monkeypatch.setenv("MODEL_DIR", str(tmp_path))

    assert dm.main() == 1
