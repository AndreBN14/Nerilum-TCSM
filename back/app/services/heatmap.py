"""Render del mapa de explicabilidad (compartido por Grad-CAM y CAM).

Ambos explicadores producen un mapa de atención cuadrado (``L``) del tamaño de
la entrada del modelo y necesitan proyectarlo sobre la imagen original
respetando el modo de redimensionado (``center_crop``, ``letterbox`` o
``stretch``) y superponerlo con el mismo colormap. Este módulo concentra esa
lógica para que el resultado sea idéntico venga de donde venga el mapa.
"""

from __future__ import annotations

import io
from typing import Any


def jet(heat) -> Any:
    """Aproximación del colormap 'jet' sin depender de OpenCV."""

    import numpy as np

    x = np.clip(heat, 0.0, 1.0) * 4.0
    red = np.clip(1.5 - np.abs(x - 3.0), 0.0, 1.0)
    green = np.clip(1.5 - np.abs(x - 2.0), 0.0, 1.0)
    blue = np.clip(1.5 - np.abs(x - 1.0), 0.0, 1.0)
    return np.stack([red, green, blue], axis=-1)


def heatmap_to_original(heat, geometry: dict[str, Any], size: tuple[int, int]):
    """Proyecta el mapa cuadrado del recorte de vuelta al tamaño original."""

    from PIL import Image

    width, height = size
    mode = geometry.get("mode")

    if mode == "center_crop":
        scaled_w, scaled_h = geometry["scaled"]
        left, top = geometry["crop_offset"]
        canvas = Image.new("L", (scaled_w, scaled_h), 0)
        canvas.paste(heat, (left, top))
        return canvas.resize((width, height), Image.BILINEAR)

    if mode == "letterbox":
        side = geometry["side"]
        content_w, content_h = geometry["content_size"]
        offset_x, offset_y = geometry["offset"]
        square = heat.resize((side, side), Image.BILINEAR)
        content = square.crop(
            (offset_x, offset_y, offset_x + content_w, offset_y + content_h)
        )
        return content.resize((width, height), Image.BILINEAR)

    return heat.resize((width, height), Image.BILINEAR)


def overlay_png(image, heat, geometry: dict[str, Any]) -> bytes:
    """Superpone ``heat`` (ya escalado a la entrada) y devuelve un PNG.

    El mapa se normaliza por su pico, así que casi toda la imagen cae en valores
    bajos. La raíz (gamma < 1) levanta la señal intermedia y mantiene un tinte
    suave en el resto de la imagen: un heatmap también comunica "aquí hay poca
    atención". La opacidad máxima (0.58) conserva la IRM original visible.
    """

    import numpy as np
    from PIL import Image

    full = heatmap_to_original(heat, geometry, image.size)
    original = image.convert("RGB")
    base = np.asarray(original, dtype=np.float32) / 255.0
    mask = np.clip(np.asarray(full, dtype=np.float32) / 255.0, 0.0, 1.0)
    mask = mask**0.65
    color = jet(mask)
    alpha = (0.58 * mask)[..., None]
    blended = base * (1.0 - alpha) + color * alpha
    overlay = Image.fromarray(np.uint8(np.clip(blended, 0.0, 1.0) * 255.0))

    buffer = io.BytesIO()
    overlay.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()
