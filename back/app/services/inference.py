"""Inferencia de clasificación con el modelo ONNX exportado de YOLOv8n-cls.

El backend no emite predicciones simuladas: si el artefacto (o su model card) no
existe, no se puede cargar o su metadata no es válida, el servicio se reporta
como ``ready=False`` (``model_info=None``) y ``POST /analyses`` responde
``503 model_unavailable``. La identidad del modelo sale de ``ModelInfo``; no hay
constantes sueltas con el nombre del modelo.
"""

from __future__ import annotations

import logging
from collections.abc import Callable
from pathlib import Path
from typing import Any, Protocol

from app.core.model_info import ModelInfo, ModelInfoError, load_model_info

logger = logging.getLogger("nerilum")

DISCLAIMER = "Resultado orientativo. No constituye un diagnóstico médico."


class InferenceError(Exception):
    """Error al preprocesar o ejecutar el modelo."""


class InferenceStatus(Protocol):
    """Estado de disponibilidad y metadatos del modelo de inferencia."""

    @property
    def ready(self) -> bool: ...

    @property
    def model_info(self) -> ModelInfo | None: ...

    def analyze(self, image) -> dict[str, float]: ...


class UnavailableInference:
    """Estado sin modelo conectado: nada que inferir ni metadatos."""

    @property
    def ready(self) -> bool:
        return False

    @property
    def model_info(self) -> None:
        return None

    def analyze(self, image) -> dict[str, float]:
        raise InferenceError("El modelo no está disponible.")


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
        model_dir: str | Path,
        *,
        resize_mode: str = "center_crop",
        softmax: bool = False,
        input_size: int | None = None,
        session_factory: Callable[[Path], Any] | None = None,
    ) -> None:
        self._model_dir = Path(model_dir)
        self._resize_mode = resize_mode
        self._apply_softmax = softmax
        self._configured_input_size = input_size
        self._session_factory = session_factory
        self._session: Any | None = None
        self._model_info: ModelInfo | None = None
        self._input_name = "images"
        self._input_size = input_size
        try:
            self._load()
        except InferenceError as exc:
            logger.warning("Modelo no disponible: %s", exc)
            self._session = None
            self._model_info = None

    # -- Estado ----------------------------------------------------------

    @property
    def ready(self) -> bool:
        return self._session is not None and self._model_info is not None

    @property
    def model_info(self) -> ModelInfo | None:
        return self._model_info

    # -- Carga del artefacto ---------------------------------------------

    def _find_artifact(self) -> Path:
        if not self._model_dir.is_dir():
            raise InferenceError(f"No existe la carpeta del modelo: {self._model_dir}")
        candidates = sorted(self._model_dir.glob("*.onnx"))
        if not candidates:
            raise InferenceError(f"No hay ningún '.onnx' en {self._model_dir}")
        if len(candidates) > 1:
            raise InferenceError(
                f"Se esperaba un único '.onnx' en {self._model_dir}; "
                f"se encontraron {len(candidates)}."
            )
        return candidates[0]

    def _create_session(self, onnx_path: Path) -> Any:
        if self._session_factory is not None:
            return self._session_factory(onnx_path)
        try:
            import onnxruntime as ort
        except ImportError as exc:  # pragma: no cover - entorno mínimo
            raise InferenceError("onnxruntime no está instalado.") from exc
        return ort.InferenceSession(
            str(onnx_path), providers=["CPUExecutionProvider"]
        )

    def _load(self) -> None:
        onnx_path = self._find_artifact()
        try:
            session = self._create_session(onnx_path)
        except InferenceError:
            raise
        except Exception as exc:
            raise InferenceError(f"No se pudo cargar el modelo: {exc}") from exc

        self._session = session
        try:
            self._model_info = load_model_info(session, self._model_dir / "model_card.json")
        except ModelInfoError as exc:
            raise InferenceError(str(exc)) from exc
        self._read_input()

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

    # -- Inferencia ------------------------------------------------------

    def analyze(self, image) -> dict[str, float]:
        """Clasifica una imagen ya validada y devuelve las puntuaciones."""
        if self._session is None or self._model_info is None:
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

        classes = self._model_info.classes
        if len(scores) != len(classes):
            raise InferenceError(
                f"Salida de {len(scores)} puntuaciones vs {len(classes)} etiquetas."
            )

        result: dict[str, float] = {
            label: float(score) for label, score in zip(classes, scores)
        }
        return result

    def _softmax(self, logits) -> object:
        import numpy as np

        logits = np.asarray(logits, dtype=np.float64)
        shifted = logits - np.max(logits)
        exp = np.exp(shifted)
        return exp / np.sum(exp)

    def _preprocess(self, image):
        batch, _ = preprocess_classification(
            image,
            resize_mode=self._resize_mode,
            input_size=int(self._input_size or 224),
        )
        return batch


def preprocess_classification(
    image, *, resize_mode: str, input_size: int
) -> tuple[Any, dict[str, Any]]:
    """Preprocesado compartido por el clasificador ONNX y el Grad-CAM.

    Devuelve ``(batch, geometria)``. ``batch`` es un ``float32`` NCHW en
    ``[0, 1]`` RGB (lo que espera tanto el ``.onnx`` como el ``.pt``). La
    geometría describe cómo proyectar un mapa de tamaño ``input_size`` de vuelta
    sobre la imagen original, para que el Grad-CAM no quede desplazado cuando
    el modo es ``center_crop`` o ``letterbox``.
    """

    import numpy as np
    from PIL import Image

    img = image.convert("RGB")
    size = int(input_size or 224)
    geometry: dict[str, Any]

    if resize_mode == "stretch":
        img = img.resize((size, size), Image.BILINEAR)
        geometry = {"mode": "stretch"}
    elif resize_mode == "center_crop":
        # Referencia Ultralytics: Resize del lado corto a `size` + recorte central.
        scale = size / min(img.size)
        scaled_size = (
            max(1, round(img.width * scale)),
            max(1, round(img.height * scale)),
        )
        img = img.resize(scaled_size, Image.BILINEAR)
        left = (img.width - size) // 2
        top = (img.height - size) // 2
        img = img.crop((left, top, left + size, top + size))
        geometry = {
            "mode": "center_crop",
            "scaled": scaled_size,
            "crop_offset": (left, top),
        }
    else:  # letterbox (SquarePad): conserva proporción y rellena a cuadrado
        side = max(img.size)
        canvas = Image.new("RGB", (side, side), (114, 114, 114))
        offset = ((side - img.width) // 2, (side - img.height) // 2)
        content_size = img.size
        canvas.paste(img, offset)
        img = canvas.resize((size, size), Image.BILINEAR)
        geometry = {
            "mode": "letterbox",
            "side": side,
            "content_size": content_size,
            "offset": offset,
        }

    arr = np.asarray(img, dtype=np.float32) / 255.0
    arr = np.transpose(arr, (2, 0, 1))
    return arr[np.newaxis, :, :, :], geometry
