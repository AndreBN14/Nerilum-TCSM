"""Grad-CAM opcional a partir del checkpoint PyTorch ``best.pt``.

El clasificador de producción usa el ``.onnx`` (solo inferencia). El ``.onnx``
no expone gradientes, así que para explicar la predicción se carga el ``.pt``
de YOLOv5-cls como **explicador opcional**. Si ``torch`` no está instalado o el
artefacto no se puede cargar, el servicio queda ``ready=False`` y la
clasificación sigue funcionando sin Grad-CAM.

El checkpoint es un pickle de PyTorch que referencia las clases del repositorio
oficial ``ultralytics/yolov5`` (``models.common.*`` y ``models.yolo``). En vez
de arrastrar ese repositorio completo, aquí se registran implementaciones
mínimas compatibles con la arquitectura ``yolov5n-cls``; solo se reutilizan al
deserializar. Como ``torch.load`` ejecuta el pickle, el archivo debe ser un
artefacto de confianza del pipeline de entrenamiento (nunca uno subido por el
usuario).

El preprocesado es el mismo del clasificador ONNX más la normalización
ImageNet que el modelo espera; así el mapa explica exactamente la misma
predicción que se muestra en la app.
"""

from __future__ import annotations

import logging
import sys
import threading
import types
from pathlib import Path
from typing import Any

from app.services.heatmap import overlay_png
from app.services.inference import preprocess_classification

logger = logging.getLogger("nerilum")

IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)


class GradCamError(Exception):
    """No se pudo generar el mapa de explicabilidad."""


def _install_yolov5_stubs() -> None:
    """Registra módulos mínimos para deserializar un checkpoint de YOLOv5-cls."""

    try:
        import models.common  # noqa: F401  (repositorio real disponible)

        return
    except Exception:
        pass

    import torch
    import torch.nn as nn

    class Conv(nn.Module):
        def forward(self, x):
            return self.act(self.bn(self.conv(x)))

    class Bottleneck(nn.Module):
        def forward(self, x):
            if getattr(self, "add", False):
                return x + self.cv2(self.cv1(x))
            return self.cv2(self.cv1(x))

    class C3(nn.Module):
        def forward(self, x):
            return self.cv3(torch.cat((self.m(self.cv1(x)), self.cv2(x)), 1))

    class SPPF(nn.Module):
        def forward(self, x):
            y1 = self.m[0](x)
            y2 = self.m[1](y1)
            y3 = self.m[2](y2)
            return self.cv2(torch.cat([x, y1, y2, y3], 1))

    class Classify(nn.Module):
        def forward(self, x):
            return self.linear(self.drop(self.pool(self.conv(x)).flatten(1)))

    class ClassificationModel(nn.Module):
        def forward(self, x):
            return self.model(x)

    package = types.ModuleType("models")
    package.__path__ = []  # type: ignore[attr-defined]
    common = types.ModuleType("models.common")
    common.__path__ = []  # type: ignore[attr-defined]
    yolo = types.ModuleType("models.yolo")
    yolo.__path__ = []  # type: ignore[attr-defined]

    for name, module in (
        ("Conv", Conv),
        ("Bottleneck", Bottleneck),
        ("C3", C3),
        ("SPPF", SPPF),
        ("Classify", Classify),
    ):
        setattr(common, name, module)
    yolo.ClassificationModel = ClassificationModel
    yolo.DetectionModel = ClassificationModel

    package.common = common
    package.yolo = yolo
    sys.modules["models"] = package
    sys.modules["models.common"] = common
    sys.modules["models.yolo"] = yolo


class GradCamExplainer:
    """Carga ``best.pt`` y genera un PNG con el Grad-CAM superpuesto."""

    def __init__(
        self,
        model_path: str | Path,
        *,
        resize_mode: str = "center_crop",
        input_size: int | None = None,
    ) -> None:
        self._path = Path(model_path)
        self._resize_mode = resize_mode
        self._input_size = int(input_size or 224)
        self._net: Any | None = None
        self._target_layer: Any | None = None
        self._features: Any | None = None
        self._grads: Any | None = None
        self._lock = threading.Lock()
        self._load()

    @property
    def ready(self) -> bool:
        return self._net is not None and self._target_layer is not None

    # -- Carga -----------------------------------------------------------

    def _load(self) -> None:
        try:
            import torch
            import torch.nn as nn
        except ImportError:
            logger.warning(
                "Grad-CAM desactivado: torch no está instalado "
                "(ver requirements-explain.txt)."
            )
            return

        if not self._path.is_file():
            logger.warning("Grad-CAM desactivado: no existe %s.", self._path.name)
            return

        try:
            _install_yolov5_stubs()
            checkpoint = torch.load(
                str(self._path), map_location="cpu", weights_only=False
            )
            net = checkpoint.get("model") if isinstance(checkpoint, dict) else checkpoint
            if net is None:
                raise GradCamError("El checkpoint no contiene 'model'.")
            net = net.float().eval()
            # El checkpoint de inferencia guarda los pesos con requires_grad=False;
            # Grad-CAM necesita gradientes respecto de las activaciones.
            net.requires_grad_(True)

            target = None
            for module in net.modules():
                if isinstance(module, nn.Conv2d):
                    target = module
            if target is None:
                raise GradCamError("No se encontró una capa convolucional.")
            target.register_forward_hook(self._capture)
        except Exception as exc:
            logger.warning(
                "Grad-CAM desactivado: no se pudo cargar el checkpoint (%s).",
                type(exc).__name__,
            )
            self._net = None
            return

        self._net = net
        self._target_layer = target
        logger.info("Grad-CAM listo con %s.", self._path.name)

    # -- Hooks -----------------------------------------------------------

    def _capture(self, _module, _inputs, output):
        self._features = output
        output.register_hook(self._capture_grad)

    def _capture_grad(self, grad):
        self._grads = grad.detach()

    # -- Inferencia ------------------------------------------------------

    def render(self, image, target_index: int) -> bytes:
        """Devuelve el PNG con el Grad-CAM de la clase ``target_index``."""

        if not self.ready:
            raise GradCamError("El explicador no está disponible.")

        with self._lock:
            try:
                import numpy as np
                import torch
                from PIL import Image

                batch, geometry = preprocess_classification(
                    image,
                    resize_mode=self._resize_mode,
                    input_size=self._input_size,
                )
                mean = np.asarray(IMAGENET_MEAN, dtype=np.float32).reshape(1, 3, 1, 1)
                std = np.asarray(IMAGENET_STD, dtype=np.float32).reshape(1, 3, 1, 1)
                normalized = torch.from_numpy((batch - mean) / std)

                self._features = None
                self._grads = None
                self._net.zero_grad(set_to_none=True)

                logits = self._net(normalized)
                if isinstance(logits, (tuple, list)):
                    logits = logits[0]
                logits = logits.float().reshape(-1)
                if not 0 <= int(target_index) < int(logits.numel()):
                    raise GradCamError("Índice de clase fuera de rango.")

                logits[int(target_index)].backward()

                features = self._features
                grads = self._grads
                if features is None or grads is None or features.ndim != 4:
                    raise GradCamError("No se capturaron activaciones del modelo.")

                weights = grads.mean(dim=(2, 3))[0]
                cam = torch.relu((weights[:, None, None] * features[0]).sum(dim=0))
                cam = cam.detach().cpu().numpy()
                maximum = float(cam.max())
                if maximum <= 0:
                    raise GradCamError("El mapa de atención está vacío.")
                reference = max(float(np.percentile(cam, 99)), maximum * 0.4)
                heat = Image.fromarray(
                    np.uint8(np.clip(cam / reference, 0.0, 1.0) * 255.0)
                )
                heat = heat.resize((self._input_size, self._input_size), Image.BILINEAR)
                return overlay_png(image, heat, geometry)
            except GradCamError:
                raise
            except Exception as exc:
                raise GradCamError(f"Fallo al generar el Grad-CAM: {exc}") from exc
            finally:
                self._features = None
                self._grads = None
