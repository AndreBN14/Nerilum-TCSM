"""Mapa de atención (CAM) calculado sobre el ONNX de clasificación.

El clasificador de producción solo expone ``probs``, pero su arquitectura
(YOLOv5-cls) termina en::

    Conv -> GlobalAveragePool -> Flatten -> Gemm -> Softmax

Esa es exactamente la estructura que asume CAM: la predicción es una
combinación lineal de las activaciones de la última convolución, así que

    cam_c = ReLU( sum_k W[c, k] * A_k )

explica la misma pasada que produjo la probabilidad, sin gradientes, sin
``torch`` y sin el checkpoint ``best.pt``.

Para obtener ``A`` se añade ese tensor como salida adicional del grafo **en
memoria** con ``onnx``; el archivo del modelo no se modifica y las
probabilidades son idénticas a las del clasificador. Este es el único explicador del backend: siempre se construye desde el ``.onnx``, sin ``torch`` y sin checkpoint ``best.pt``.
"""

from __future__ import annotations

import logging
import threading
from pathlib import Path
from typing import Any, Protocol

from app.services.heatmap import overlay_png
from app.services.inference import preprocess_classification

logger = logging.getLogger("nerilum")


class CamError(Exception):
    """No se pudo generar el mapa de atención."""


class Explainer(Protocol):
    """Contrato mínimo de un explicador de la predicción."""

    @property
    def ready(self) -> bool: ...

    def render(self, image, target_index: int) -> bytes: ...


def _is_spatial_reduce(node) -> bool:
    """``ReduceMean`` sobre los ejes espaciales equivale a un GAP."""

    if node.op_type != "ReduceMean":
        return False
    for attribute in node.attribute:
        if attribute.name == "axes" and list(attribute.ints) == [2, 3]:
            return True
    return False


def feature_tensor(graph) -> str:
    """Nombre del tensor con las activaciones de la última convolución."""

    pools = [
        node
        for node in graph.node
        if node.op_type == "GlobalAveragePool" or _is_spatial_reduce(node)
    ]
    if pools:
        return pools[-1].input[0]
    convs = [node for node in graph.node if node.op_type == "Conv"]
    if convs:
        return convs[-1].output[0]
    raise CamError("No se encontró una activación convolucional en el ONNX.")


def classification_weights(graph) -> Any:
    """Pesos de la capa lineal final, embebidos como inicializador."""

    import onnx

    nodes = [node for node in graph.node if node.op_type in ("Gemm", "MatMul")]
    if not nodes:
        raise CamError("No se encontró la capa de clasificación en el ONNX.")
    initializers = {initializer.name: initializer for initializer in graph.initializer}
    weight = initializers.get(nodes[-1].input[1])
    if weight is None:
        raise CamError("El peso del clasificador no está embebido en el ONNX.")
    return onnx.numpy_helper.to_array(weight)


def _orient_weights(weights, features: int) -> Any:
    """Deja los pesos como ``(clases, características)``.

    ``Gemm`` con ``transB=1`` los guarda así; ``MatMul``/``transB=0`` los guarda
    al revés. Se resuelve por la dimensión que coincide con los canales.
    """

    import numpy as np

    array = np.asarray(weights, dtype=np.float32)
    if array.ndim != 2:
        raise CamError("El peso del clasificador no es una matriz.")
    if array.shape[1] == features:
        return np.ascontiguousarray(array)
    if array.shape[0] == features:
        return np.ascontiguousarray(array.T)
    raise CamError(
        f"El peso del clasificador no coincide con {features} características."
    )


class OnnxCamExplainer:
    """Genera un PNG con el CAM de la clase indicada usando solo el ``.onnx``."""

    def __init__(
        self,
        model_path: str | Path,
        *,
        resize_mode: str = "center_crop",
        input_size: int | None = None,
    ) -> None:
        self._path = Path(model_path)
        self._resize_mode = resize_mode
        self._configured_input_size = input_size
        self._session: Any | None = None
        self._weights: Any | None = None
        self._feature_index = 1
        self._input_name = "images"
        self._input_size = int(input_size or 224)
        self._lock = threading.Lock()
        self._load()

    @property
    def ready(self) -> bool:
        return self._session is not None and self._weights is not None

    # -- Carga -----------------------------------------------------------

    def _load(self) -> None:
        try:
            import numpy as np
            import onnx
            import onnxruntime as ort
        except ImportError as exc:
            logger.warning(
                "Mapa de atención desactivado: falta '%s' (ver requirements.txt).",
                getattr(exc, "name", "onnx"),
            )
            return

        if not self._path.is_file():
            logger.warning(
                "Mapa de atención desactivado: no existe %s.", self._path.name
            )
            return

        try:
            model = onnx.load(str(self._path))
            feature = feature_tensor(model.graph)
            weights = classification_weights(model.graph)
            # Solo en memoria: el artefacto del disco queda intacto.
            if feature not in [output.name for output in model.graph.output]:
                model.graph.output.append(onnx.ValueInfoProto(name=feature))
            raw = model.SerializeToString()
            del model

            session = ort.InferenceSession(raw, providers=["CPUExecutionProvider"])
            del raw

            names = [output.name for output in session.get_outputs()]
            if feature not in names:
                raise CamError("El ONNX no expone las activaciones esperadas.")
            self._feature_index = names.index(feature)
            self._input_name = session.get_inputs()[0].name or "images"
            self._input_size = self._resolve_input_size(session)
            shape = self._feature_shape(session, np)
            self._weights = _orient_weights(weights, int(shape[1]))
        except Exception as exc:
            logger.warning(
                "Mapa de atención desactivado: no se pudo preparar el ONNX (%s: %s).",
                type(exc).__name__,
                exc,
            )
            self._session = None
            self._weights = None
            return

        self._session = session
        logger.info("Mapa de atención (CAM) listo con %s.", self._path.name)

    def _resolve_input_size(self, session) -> int:
        dims = list(getattr(session.get_inputs()[0], "shape", []) or [])
        if len(dims) >= 4 and isinstance(dims[2], int) and dims[2] > 0:
            return int(self._configured_input_size or dims[2])
        return int(self._configured_input_size or 224)

    def _feature_shape(self, session, np) -> list[int]:
        shape = list(session.get_outputs()[self._feature_index].shape or [])
        if len(shape) != 4 or not all(
            isinstance(dimension, int) and dimension > 0 for dimension in shape
        ):
            # Forma dinámica: una pasada con ceros solo para conocer las dimensiones.
            dummy = np.zeros(
                (1, 3, self._input_size, self._input_size), dtype=np.float32
            )
            outputs = session.run(None, {self._input_name: dummy})
            shape = list(np.asarray(outputs[self._feature_index]).shape)
        if len(shape) != 4 or shape[1] <= 0:
            raise CamError("La activación del ONNX no es un mapa 4D.")
        return [int(dimension) for dimension in shape]

    # -- Inferencia ------------------------------------------------------

    def render(self, image, target_index: int) -> bytes:
        """Devuelve el PNG con el CAM de la clase ``target_index``."""

        import numpy as np

        if not self.ready:
            raise CamError("El explicador no está disponible.")

        with self._lock:
            try:
                from PIL import Image

                batch, geometry = preprocess_classification(
                    image,
                    resize_mode=self._resize_mode,
                    input_size=self._input_size,
                )
                outputs = self._session.run(
                    None, {self._input_name: np.asarray(batch, dtype=np.float32)}
                )
                features = np.asarray(outputs[self._feature_index], dtype=np.float32)
                if features.ndim != 4:
                    raise CamError("No se capturaron activaciones del modelo.")

                index = int(target_index)
                if not 0 <= index < int(self._weights.shape[0]):
                    raise CamError("Índice de clase fuera de rango.")

                channels, height, width = features.shape[1:]
                activations = features[0].reshape(channels, height * width)
                cam = np.maximum(self._weights[index] @ activations, 0.0)
                cam = cam.reshape(height, width)
                maximum = float(cam.max())
                if not np.isfinite(maximum) or maximum <= 0.0:
                    raise CamError("El mapa de atención está vacío.")
                # Referencia robusta: un único pico no debe aplastar el resto.
                reference = max(float(np.percentile(cam, 99)), maximum * 0.4)
                heat = Image.fromarray(
                    np.uint8(np.clip(cam / reference, 0.0, 1.0) * 255.0)
                )
                heat = heat.resize((self._input_size, self._input_size), Image.BILINEAR)
                return overlay_png(image, heat, geometry)
            except CamError:
                raise
            except Exception as exc:
                raise CamError(f"Fallo al generar el mapa de atención: {exc}") from exc
