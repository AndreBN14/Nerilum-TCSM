"""Inferencia de clasificación con el modelo ONNX exportado de YOLOv8n-cls.

El backend no emite predicciones simuladas: si el artefacto no existe o no se
puede cargar, el servicio se reporta como ``ready=False`` y ``POST /analyses``
responde ``503 model_unavailable``.
"""

from __future__ import annotations

import ast
from pathlib import Path
from typing import Protocol

from app.core.config import DEFAULT_CLASSES

DISCLAIMER = "Resultado orientativo. No constituye un diagnóstico médico."


class InferenceError(Exception):
    """Error al preprocesar o ejecutar el modelo."""


class InferenceStatus(Protocol):
    """Estado de disponibilidad y metadatos del modelo de inferencia."""

    @property
    def ready(self) -> bool: ...

    @property
    def model_name(self) -> str | None: ...

    @property
    def model_version(self) -> str | None: ...


class UnavailableInference:
    """Estado sin modelo conectado: nada que inferir ni metadatos."""

    @property
    def ready(self) -> bool:
        return False

    @property
    def model_name(self) -> None:
        return None

    @property
    def model_version(self) -> None:
        return None


class OnnxClassifier:
    """Clasificador ONNX (YOLOv8n-cls) con preprocesado configurable.

    El preprocesado por defecto reproduce el pipeline de inferencia de
    referencia de Ultralytics para clasificación (clase ``ClassificationPredictor``):
    ``Resize`` del lado corto a ``imgsz`` -> ``CenterCrop`` cuadrado ->
    ``ToTensor`` (escala 0-1, NCHW) -> ``Normalize(mean=0, std=1)``. Los
    argumentos exactos del entrenamiento no están disponibles en el repositorio,
    por lo que la equivalencia completa con el pipeline de entrenamiento aún no
    está demostrada; ``letterbox`` y ``stretch`` quedan como alternativas.

    La salida ONNX de este artefacto ya está normalizada (softmax integrado en
    el head de clasificación), por lo que ``softmax`` es ``False`` por defecto:
    aplicarlo de nuevo distorsionaría las probabilidades.
    """

    def __init__(
        self,
        model_path: str | Path,
        *,
        resize_mode: str = "center_crop",
        softmax: bool = False,
        input_size: int | None = None,
        model_name: str = "yolov8n-cls",
        model_version: str = "v0.1",
    ) -> None:
        self._model_path = Path(model_path)
        self._resize_mode = resize_mode
        self._apply_softmax = softmax
        self._configured_input_size = input_size
        self._model_name = model_name
        self._model_version = model_version
        self._session = None
        self._input_name = "images"
        self._input_size = input_size
        self._names: list[str] = list(DEFAULT_CLASSES)
        try:
            self._load()
        except InferenceError:
            self._session = None

    # -- Estado ----------------------------------------------------------

    @property
    def ready(self) -> bool:
        return self._session is not None

    @property
    def model_name(self) -> str:
        return self._model_name

    @property
    def model_version(self) -> str:
        return self._model_version

    # -- Carga del artefacto ---------------------------------------------

    def _load(self) -> None:
        if not self._model_path.exists():
            self._dispose()
            raise InferenceError(f"No existe el artefacto: {self._model_path}")

        try:
            import onnxruntime as ort
        except ImportError as exc:  # pragma: no cover - entorno mínimo
            self._dispose()
            raise InferenceError("onnxruntime no está instalado.") from exc

        try:
            self._session = ort.InferenceSession(
                str(self._model_path),
                providers=["CPUExecutionProvider"],
            )
        except Exception as exc:
            self._dispose()
            raise InferenceError(f"No se pudo cargar el modelo: {exc}") from exc

        self._read_input()
        self._read_names()

    def _dispose(self) -> None:
        self._session = None

    def _read_input(self) -> None:
        try:
            inputs = self._session.get_inputs()
            if not inputs:
                raise InferenceError("El modelo no declara entradas.")
            input_meta = inputs[0]
            self._input_name = input_meta.name or "images"
            dims = list(getattr(input_meta, "shape", []))
            if len(dims) >= 4 and all(isinstance(d, int) and d > 0 for d in dims[2:4]):
                self._input_size = int(
                    self._configured_input_size if self._configured_input_size else dims[2]
                )
            else:
                self._input_size = self._configured_input_size
        except InferenceError:
            raise
        except Exception:
            self._input_size = self._configured_input_size

    def _read_names(self) -> None:
        try:
            raw = self._session.get_modelmeta().custom_metadata_map.get("names")
            if raw:
                parsed = ast.literal_eval(raw)
                if isinstance(parsed, dict):
                    ordered = [parsed[k] for k in sorted(parsed, key=int)]
                    if ordered:
                        self._names = [str(n) for n in ordered]
        except (ValueError, SyntaxError, TypeError, KeyError):
            # Si los nombres no se pueden leer, se conservan los del contrato.
            self._names = list(DEFAULT_CLASSES)

    # -- Inferencia ------------------------------------------------------

    def analyze(self, image) -> dict[str, float]:
        """Clasifica una imagen ya validada y devuelve las puntuaciones."""
        if self._session is None:
            raise InferenceError("El modelo no está disponible.")

        try:
            import numpy as np

            batch = self._preprocess(image)
            outputs = self._session.run(
                None, {self._input_name: np.asarray(batch, dtype=np.float32)}
            )
            scores = np.asarray(outputs[0]).reshape(-1)
        except Exception as exc:
            raise InferenceError(f"Fallo al ejecutar la inferencia: {exc}") from exc

        if self._apply_softmax:
            scores = self._softmax(scores)

        if len(scores) != len(self._names):
            raise InferenceError(
                f"Salida de {len(scores)} puntuaciones vs {len(self._names)} etiquetas."
            )

        result: dict[str, float] = {
            label: float(score) for label, score in zip(self._names, scores)
        }
        return result

    def _softmax(self, logits) -> object:
        import numpy as np

        logits = np.asarray(logits, dtype=np.float64)
        shifted = logits - np.max(logits)
        exp = np.exp(shifted)
        return exp / np.sum(exp)

    def _preprocess(self, image):
        import numpy as np
        from PIL import Image

        img = image.convert("RGB")
        size = int(self._input_size or 224)

        if self._resize_mode == "stretch":
            img = img.resize((size, size), Image.BILINEAR)
        elif self._resize_mode == "center_crop":
            # Referencia Ultralytics: Resize del lado corto a `size` + recorte central.
            scale = size / min(img.size)
            img = img.resize(
                (max(1, round(img.width * scale)), max(1, round(img.height * scale))),
                Image.BILINEAR,
            )
            left = (img.width - size) // 2
            top = (img.height - size) // 2
            img = img.crop((left, top, left + size, top + size))
        else:  # letterbox (SquarePad): conserva proporción y rellena a cuadrado
            side = max(img.size)
            canvas = Image.new("RGB", (side, side), (114, 114, 114))
            offset = ((side - img.width) // 2, (side - img.height) // 2)
            canvas.paste(img, offset)
            img = canvas.resize((size, size), Image.BILINEAR)

        arr = np.asarray(img, dtype=np.float32) / 255.0
        arr = np.transpose(arr, (2, 0, 1))
        return arr[np.newaxis, :, :, :]