"""Pruebas unitarias de la validación de imágenes."""

from __future__ import annotations

from io import BytesIO

import pytest
from PIL import Image, ImageFile

from app.core.errors import ApiException
from app.services.images import validate_image

MAX_PIX = 16_777_216
MAX_DIM = 4096


def _png_bytes(size=(64, 64)) -> bytes:
    buffer = BytesIO()
    Image.new("RGB", size, (10, 20, 30)).save(buffer, format="PNG")
    return buffer.getvalue()


def _jpeg_bytes(size=(64, 64)) -> bytes:
    buffer = BytesIO()
    Image.new("RGB", size, (200, 100, 50)).save(buffer, format="JPEG")
    return buffer.getvalue()


def _error_code(exc: ApiException) -> str:
    return exc.code


def test_valid_png_image() -> None:
    image = validate_image(_png_bytes(), max_bytes=10_000, max_dimension=MAX_DIM, max_pixels=MAX_PIX)
    assert image.mode == "RGB"
    assert image.size == (64, 64)


def test_valid_jpeg_image() -> None:
    image = validate_image(_jpeg_bytes(), max_bytes=10_000, max_dimension=MAX_DIM, max_pixels=MAX_PIX)
    assert image.mode == "RGB"


def test_oversized_upload_is_413() -> None:
    with pytest.raises(ApiException) as excinfo:
        validate_image(_png_bytes(), max_bytes=64, max_dimension=MAX_DIM, max_pixels=MAX_PIX)
    assert _error_code(excinfo.value) == "too_large"


def test_wrong_format_signature_is_415() -> None:
    with pytest.raises(ApiException) as excinfo:
        validate_image(b"hola mundo", max_bytes=10_000, max_dimension=MAX_DIM, max_pixels=MAX_PIX)
    assert _error_code(excinfo.value) == "unsupported_media_type"


def test_truncated_image_is_400() -> None:
    fake_jpeg = b"\xff\xd8\xff\xe0" + b"\x00" * 64
    with pytest.raises(ApiException) as excinfo:
        validate_image(fake_jpeg, max_bytes=10_000, max_dimension=MAX_DIM, max_pixels=MAX_PIX)
    assert _error_code(excinfo.value) == "invalid_image"


def test_dimensions_over_limit_is_400() -> None:
    with pytest.raises(ApiException) as excinfo:
        validate_image(_png_bytes(size=(64, 64)), max_bytes=10_000, max_dimension=16, max_pixels=MAX_PIX)
    assert _error_code(excinfo.value) == "invalid_image"


def test_error_envelope_fields() -> None:
    with pytest.raises(ApiException) as excinfo:
        validate_image(b"x" * 100, max_bytes=64, max_dimension=16, max_pixels=MAX_PIX)
    assert excinfo.value.status_code == 413
    assert excinfo.value.code == "too_large"


def test_pixels_over_limit_explicit_is_400() -> None:
    # 64*64=4096 > 1024
    with pytest.raises(ApiException) as excinfo:
        validate_image(_png_bytes(size=(64, 64)), max_bytes=10_000, max_dimension=4096, max_pixels=1024)
    assert excinfo.value.status_code == 400
    assert excinfo.value.code == "invalid_image"


def test_signature_valid_but_incoherent_format_is_400(monkeypatch) -> None:
    # Firma PNG válida; forzamos formato incoherente
    original_open = Image.open

    class Stub:
        format = "GIF"
        size = (10, 10)

        def verify(self) -> None:
            return

        def load(self) -> None:
            return

        def convert(self, mode: str):
            img = Image.new(mode, self.size)
            return img

    def _fake_open(_):
        return Stub()

    monkeypatch.setattr(Image, "open", _fake_open)
    try:
        with pytest.raises(ApiException) as excinfo:
            validate_image(PNG_MAGIC + b"data", max_bytes=10_000, max_dimension=4096, max_pixels=MAX_PIX)
        assert excinfo.value.status_code == 400
        assert excinfo.value.code == "invalid_image"
    finally:
        monkeypatch.setattr(Image, "open", original_open)


def test_decompression_bomb_error_is_400(monkeypatch) -> None:
    def _bomb_open(_):
        from PIL import Image

        raise Image.DecompressionBombError("bomb")

    monkeypatch.setattr(Image, "open", _bomb_open)
    with pytest.raises(ApiException) as excinfo:
        validate_image(PNG_MAGIC + b"data", max_bytes=10_000, max_dimension=4096, max_pixels=1000)
    assert excinfo.value.status_code == 400
    assert excinfo.value.code == "invalid_image"
    assert "PIL" not in excinfo.value.detail
    assert "bomb" not in excinfo.value.detail


def test_decompression_bomb_warning_converted_to_400(monkeypatch) -> None:
    def _warn_open(_):
        from PIL import Image

        raise Image.DecompressionBombWarning("warn")

    monkeypatch.setattr(Image, "open", _warn_open)
    with pytest.raises(ApiException) as excinfo:
        validate_image(PNG_MAGIC + b"data", max_bytes=10_000, max_dimension=4096, max_pixels=3000)
    assert excinfo.value.status_code == 400
    assert excinfo.value.code == "invalid_image"
    assert "warn" not in excinfo.value.detail


def test_bomb_message_fixed_no_sensitive_data() -> None:
    fake = PNG_MAGIC + b"\x00" * 32
    with pytest.raises(ApiException) as excinfo:
        validate_image(fake, max_bytes=10_000, max_dimension=4096, max_pixels=100)
    assert excinfo.value.code == "invalid_image"
    assert excinfo.value.detail == "El archivo no se puede decodificar como imagen."
from app.services.images import JPEG_MAGIC, PNG_MAGIC
