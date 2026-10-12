"""Pruebas unitarias de la validación de imágenes."""

from __future__ import annotations

from io import BytesIO

import pytest
from PIL import Image

from app.core.errors import ApiException
from app.services.images import validate_image


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
    image = validate_image(_png_bytes(), max_bytes=10_000, max_dimension=4096)
    assert image.mode == "RGB"
    assert image.size == (64, 64)


def test_valid_jpeg_image() -> None:
    image = validate_image(_jpeg_bytes(), max_bytes=10_000, max_dimension=4096)
    assert image.mode == "RGB"


def test_oversized_upload_is_413() -> None:
    with pytest.raises(ApiException) as excinfo:
        validate_image(_png_bytes(), max_bytes=64, max_dimension=4096)
    assert _error_code(excinfo.value) == "too_large"


def test_wrong_format_signature_is_415() -> None:
    with pytest.raises(ApiException) as excinfo:
        validate_image(b"hola mundo", max_bytes=10_000, max_dimension=4096)
    assert _error_code(excinfo.value) == "unsupported_media_type"


def test_truncated_image_is_400() -> None:
    fake_jpeg = b"\xff\xd8\xff\xe0" + b"\x00" * 64
    with pytest.raises(ApiException) as excinfo:
        validate_image(fake_jpeg, max_bytes=10_000, max_dimension=4096)
    assert _error_code(excinfo.value) == "invalid_image"


def test_dimensions_over_limit_is_400() -> None:
    with pytest.raises(ApiException) as excinfo:
        validate_image(_png_bytes(size=(64, 64)), max_bytes=10_000, max_dimension=16)
    assert _error_code(excinfo.value) == "invalid_image"


def test_error_envelope_fields() -> None:
    with pytest.raises(ApiException) as excinfo:
        validate_image(b"x" * 100, max_bytes=64, max_dimension=16)
    assert excinfo.value.status_code == 413
    assert excinfo.value.code == "too_large"