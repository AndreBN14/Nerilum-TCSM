"""Validación de imágenes subidas antes de la inferencia.

Se valida por contenido (firma de archivo y decodificación), no solo por la
extensión, con límites explícitos de tamaño y dimensión.
"""

from __future__ import annotations

import io

from PIL import Image

from app.core.errors import ApiException

JPEG_MAGIC = b"\xff\xd8\xff"
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
_ALLOWED_FORMATS = {"JPEG", "PNG"}


class ImageValidationError(ApiException):
    """Imagen rechazada por tamaño, formato o decodificación."""


def validate_image(
    data: bytes,
    *,
    max_bytes: int,
    max_dimension: int,
) -> Image.Image:
    """Valida bytes de imagen y devuelve la imagen decodificada (RGB)."""
    # Tamaño máximo (413 too_large).
    if len(data) > max_bytes:
        raise ImageValidationError(
            413, "too_large", f"El archivo excede el tamaño máximo de {max_bytes} bytes."
        )

    # Formato admitido por firma de archivo (415 unsupported_media_type).
    if not (data.startswith(JPEG_MAGIC) or data.startswith(PNG_MAGIC)):
        raise ImageValidationError(
            415, "unsupported_media_type", "Solo se admiten imágenes JPG/JPEG o PNG."
        )

    # Decodificación (400 invalid_image).
    try:
        image = Image.open(io.BytesIO(data))
        image.load()
    except Exception as exc:
        raise ImageValidationError(
            400, "invalid_image", "El archivo no se puede decodificar como imagen."
        ) from exc

    if image.format not in _ALLOWED_FORMATS:
        raise ImageValidationError(
            415, "unsupported_media_type", "Solo se admiten imágenes JPG/JPEG o PNG."
        )

    width, height = image.size
    if width <= 0 or height <= 0 or width > max_dimension or height > max_dimension:
        raise ImageValidationError(
            400,
            "invalid_image",
            f"Las dimensiones deben estar entre 1 y {max_dimension} píxeles.",
        )

    return image.convert("RGB")