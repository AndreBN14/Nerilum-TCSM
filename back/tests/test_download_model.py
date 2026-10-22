"""Pruebas de ``scripts.download_model`` sin acceso a red.

Cubre los dos formatos de URL de Release soportados (``latest`` y etiqueta),
la URL inválida, un Release sin el asset solicitado, el camino público sin
token y la validación SHA-256 de ``main()``. ``urlopen`` y ``build_opener`` se
sustituyen por dobles: no se descarga ningún byte real.
"""

from __future__ import annotations

import hashlib
import io
import json
import urllib.error
import urllib.request

import pytest

from scripts import download_model as dm

ASSET_NAME = dm.DEFAULT_FILENAME
LATEST_URL = (
    "https://github.com/AndreBN14/Nerilum-TCSM/releases/latest/download/"
    f"{ASSET_NAME}"
)
TAG_URL = (
    "https://github.com/AndreBN14/Nerilum-TCSM/releases/download/v1.0.0/"
    f"{ASSET_NAME}"
)
INVALID_URL = "https://github.com/AndreBN14/Nerilum-TCSM/releases/download/v1.0.0"


class _Response(io.BytesIO):
    """Respuesta mínima compatible con ``with`` y ``copyfileobj``."""

    def __enter__(self) -> "_Response":
        return self

    def __exit__(self, *exc: object) -> bool:
        self.close()
        return False


class _FakeGitHub:
    """Doble de ``urlopen``/``build_opener`` que simula la API de Releases."""

    def __init__(
        self,
        release: dict[str, object] | None = None,
        *,
        release_status: int = 200,
        asset_body: bytes = b"ONNX-BYTES",
    ) -> None:
        self.release = release if release is not None else {"assets": []}
        self.release_status = release_status
        self.asset_body = asset_body
        self.requests: list[urllib.request.Request] = []

    def _dispatch(self, request: urllib.request.Request) -> _Response:
        self.requests.append(request)
        if "/releases/assets/" in request.full_url:
            return _Response(self.asset_body)
        if self.release_status != 200:
            raise urllib.error.HTTPError(
                request.full_url, self.release_status, "boom", {}, None
            )
        return _Response(json.dumps(self.release).encode("utf-8"))

    def urlopen(self, request, *args, **kwargs) -> _Response:
        if not isinstance(request, urllib.request.Request):
            request = urllib.request.Request(request)
        return self._dispatch(request)

    def opener(self):
        dispatch = self._dispatch

        class _Opener:
            def open(self, request, *args, **kwargs) -> _Response:
                return dispatch(request)

        return _Opener()


@pytest.fixture(autouse=True)
def _clean_token(monkeypatch) -> None:
    monkeypatch.delenv("MODEL_TOKEN", raising=False)
    monkeypatch.delenv("GITHUB_TOKEN", raising=False)


def _install(monkeypatch, fake: _FakeGitHub) -> None:
    monkeypatch.setattr(urllib.request, "urlopen", fake.urlopen)
    monkeypatch.setattr(urllib.request, "build_opener", lambda *handlers: fake.opener())


def test_parse_release_url_accepts_latest_and_tag() -> None:
    assert dm._parse_release_url(LATEST_URL) == (
        "AndreBN14",
        "Nerilum-TCSM",
        "latest",
        ASSET_NAME,
    )
    assert dm._parse_release_url(TAG_URL) == (
        "AndreBN14",
        "Nerilum-TCSM",
        "v1.0.0",
        ASSET_NAME,
    )


def test_parse_release_url_rejects_invalid() -> None:
    with pytest.raises(ValueError, match="URL de Release no reconocida"):
        dm._parse_release_url(INVALID_URL)


def test_latest_url_queries_latest_release_and_asset_api(monkeypatch) -> None:
    monkeypatch.setenv("MODEL_TOKEN", "secret")
    fake = _FakeGitHub({"assets": [{"name": ASSET_NAME, "id": 42}]})
    _install(monkeypatch, fake)

    with dm._download_stream(LATEST_URL) as response:
        assert response.read() == b"ONNX-BYTES"

    assert [req.full_url for req in fake.requests] == [
        "https://api.github.com/repos/AndreBN14/Nerilum-TCSM/releases/latest",
        "https://api.github.com/repos/AndreBN14/Nerilum-TCSM/releases/assets/42",
    ]
    assert fake.requests[0].get_header("Authorization") == "Bearer secret"
    assert fake.requests[1].get_header("Accept") == "application/octet-stream"


def test_tag_url_queries_release_by_tag(monkeypatch) -> None:
    monkeypatch.setenv("MODEL_TOKEN", "secret")
    fake = _FakeGitHub({"assets": [{"name": ASSET_NAME, "id": 7}]})
    _install(monkeypatch, fake)

    dm._download_stream(TAG_URL)

    assert fake.requests[0].full_url == (
        "https://api.github.com/repos/AndreBN14/Nerilum-TCSM/releases/tags/v1.0.0"
    )
    assert fake.requests[1].full_url.endswith("/releases/assets/7")


def test_github_token_is_used_as_fallback(monkeypatch) -> None:
    monkeypatch.setenv("GITHUB_TOKEN", "gh-secret")
    fake = _FakeGitHub({"assets": [{"name": ASSET_NAME, "id": 1}]})
    _install(monkeypatch, fake)

    dm._download_stream(LATEST_URL)

    assert fake.requests[0].get_header("Authorization") == "Bearer gh-secret"


def test_invalid_url_raises_value_error(monkeypatch) -> None:
    monkeypatch.setenv("MODEL_TOKEN", "secret")
    fake = _FakeGitHub({"assets": [{"name": ASSET_NAME, "id": 1}]})
    _install(monkeypatch, fake)

    with pytest.raises(ValueError, match="URL de Release no reconocida"):
        dm._download_stream(INVALID_URL)
    assert fake.requests == []


def test_release_without_asset_raises_file_not_found(monkeypatch) -> None:
    monkeypatch.setenv("MODEL_TOKEN", "secret")
    fake = _FakeGitHub({"assets": [{"name": "otro.onnx", "id": 9}]})
    _install(monkeypatch, fake)

    with pytest.raises(FileNotFoundError, match="No se encontró"):
        dm._download_stream(LATEST_URL)


def test_without_token_downloads_direct_url(monkeypatch) -> None:
    fake = _FakeGitHub()
    _install(monkeypatch, fake)

    with dm._download_stream(LATEST_URL) as response:
        response.read()

    assert [req.full_url for req in fake.requests] == [LATEST_URL]


def test_auth_redirect_handler_strips_token_across_hosts() -> None:
    handler = dm._AuthRedirectHandler()
    request = urllib.request.Request(
        "https://api.github.com/repos/o/r/releases/assets/1",
        headers={"Authorization": "Bearer secret"},
    )

    redirected = handler.redirect_request(
        request, None, 302, "Found", {}, "https://objects.example.com/signed"
    )

    assert redirected is not None
    assert redirected.get_header("Authorization") is None


def test_auth_redirect_handler_keeps_token_same_host() -> None:
    handler = dm._AuthRedirectHandler()
    request = urllib.request.Request(
        "https://api.github.com/repos/o/r/releases/assets/1",
        headers={"Authorization": "Bearer secret"},
    )

    redirected = handler.redirect_request(
        request, None, 302, "Found", {}, "https://api.github.com/releases/assets/1"
    )

    assert redirected is not None
    assert redirected.get_header("Authorization") == "Bearer secret"


def test_main_downloads_and_validates_sha(monkeypatch, tmp_path) -> None:
    monkeypatch.setenv("MODEL_TOKEN", "secret")
    body = b"MODEL-CONTENT"
    fake = _FakeGitHub({"assets": [{"name": ASSET_NAME, "id": 42}]}, asset_body=body)
    _install(monkeypatch, fake)
    monkeypatch.setenv("MODEL_URL", LATEST_URL)
    monkeypatch.setenv("MODEL_DIR", str(tmp_path))
    monkeypatch.setenv("MODEL_SHA256", hashlib.sha256(body).hexdigest())

    assert dm.main() == 0
    assert (tmp_path / ASSET_NAME).read_bytes() == body


def test_main_rejects_sha_mismatch(monkeypatch, tmp_path) -> None:
    monkeypatch.setenv("MODEL_TOKEN", "secret")
    fake = _FakeGitHub({"assets": [{"name": ASSET_NAME, "id": 42}]})
    _install(monkeypatch, fake)
    monkeypatch.setenv("MODEL_URL", TAG_URL)
    monkeypatch.setenv("MODEL_DIR", str(tmp_path))
    monkeypatch.setenv("MODEL_SHA256", "0" * 64)

    assert dm.main() == 1
    assert not (tmp_path / ASSET_NAME).exists()
