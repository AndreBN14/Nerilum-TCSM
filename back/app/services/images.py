"""Validación de imágenes subidas antes de la inferencia.

Se valida por contenido (firma de archivo y decodificación), no por extensión
ni ``Content-Type``, con límites explícitos de tamaño, píxeles totales y
dimensión. Es el **único punto** que decodifica bytes de imagen: la inferencia
recibe la imagen ya cargada.

Los mensajes son fijos: nunca se incluyen nombres de archivo, bytes ni el texto
de las excepciones de Pillow (podría contener rutas o contenido).
"""

from __future__ import annotations

import io
import warnings
from contextlib import contextmanager

from PIL import Image, ImageFile

from app.core.errors import ApiException

JPEG_MAGIC = b"\xff\xd8\xff"
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
_ALLOWED_FORMATS = {"JPEG", "PNG"}

# Explícito (es el valor por defecto) para que un cambio ajeno no relaje la
# validación de imágenes truncadas sin que se note.
ImageFile.LOAD_TRUNCATED_IMAGES = False

_INVALID_IMAGE_MESSAGE = "El archivo no se puede decodificar como imagen."


class ImageValidationError(ApiException):
    """Imagen rechazada por tamaño, formato o decodificación."""


def too_large_error(max_bytes: int) -> ImageValidationError:
    """Error único de exceso de tamaño; mismo texto en toda la app."""

    return ImageValidationError(
        413, "too_large", f"El archivo excede el tamaño máximo de {max_bytes} bytes."
    )


def _decode_error() -> ImageValidationError:
    return ImageValidationError(400, "invalid_image", _INVALID_IMAGE_MESSAGE)


@contextmanager
def _bomb_warnings_as_errors():
    # Por defecto Pillow solo advierte por encima de ~89 MP; aquí la advertencia
    # se convierte en error para responder 400 de forma uniforme.
    with warnings.catch_warnings():
        warnings.simplefilter("error", Image.DecompressionBombWarning)
        yield


def _open(data: bytes) -> Image.Image:
    with _bomb_warnings_as_errors():
        try:
            # Image.open() solo lee la cabecera: no reserva los píxeles.
            return Image.open(io.BytesIO(data))
        except (Image.DecompressionBombError, Image.DecompressionBombWarning):
            raise _decode_error() from None
        except Exception:
            raise _decode_error() from None


def validate_image(
    data: bytes,
    *,
    max_bytes: int,
    max_dimension: int,
    max_pixels: int,
) -> Image.Image:
    """Valida bytes de imagen y devuelve la imagen decodificada (RGB)."""

    # 413: mismo error (y texto) que el corte por bloques de la ruta.
    if len(data) > max_bytes:
        raise too_large_error(max_bytes)

    # 415: formato por firma de archivo; se ignora extensión y Content-Type.
    if not (data.startswith(JPEG_MAGIC) or data.startswith(PNG_MAGIC)):
        raise ImageValidationError(
            415, "unsupported_media_type", "Solo se admiten imágenes JPG/JPEG o PNG."
        )

    image = _open(data)

    # Firma válida pero contenido incoherente (p. ej. cabecera JPEG con cuerpo
    # de otro tipo): 400 invalid_image, no 415.
    if image.format not in _ALLOWED_FORMATS:
        raise _decode_error()

    width, height = image.size

    # Píxeles primero: con w*h acotado, el chequeo de dimensión solo atrapa
    # casos degenerados (p. ej. 1×16M). Ambos se calculan solo con la cabecera.
    if width <= 0 or height <= 0 or width * height > max_pixels:
        raise ImageValidationError(
            400, "invalid_image", f"La imagen supera el máximo de {max_pixels} píxeles."
        )
    if width > max_dimension or height > max_dimension:
        raise ImageValidationError(
            400,
            "invalid_image",
            f"Las dimensiones deben estar entre 1 y {max_dimension} píxeles.",
        )

    with _bomb_warnings_as_errors():
        try:
            image.verify()
        except (Image.DecompressionBombError, Image.DecompressionBombWarning):
            raise _decode_error() from None
        except Exception:
            raise _decode_error() from None

    # verify() invalida el objeto y no detecta todos los truncamientos, así que
    # se reabre y se decodifica de verdad con load(). Para archivos de ≤10 MB la
    # doble decodificación es un costo aceptable.
    with _bomb_warnings_as_errors():
        try:
            image = Image.open(io.BytesIO(data))
            image.load()
        except (Image.DecompressionBombError, Image.DecompressionBombWarning):
            raise _decode_error() from None
        except (OSError, SyntaxError, Exception):
            # OSError (imágenes truncadas) y SyntaxError (algunos PNG) se listan
            # explícitos aunque Exception ya los cubra.
            raise _decode_error() from None

    return image.convert("RGB")