"""Pruebas del mapa de atención (CAM) derivado del propio ONNX.

No requieren ``torch`` ni ``best.pt``: los casos base construyen un ONNX mínimo
con la misma estructura que el clasificador real (Conv -> GlobalAveragePool ->
Flatten -> Gemm -> Softmax). El artefacto de producción solo se ejercita si está
presente en ``app/models``.
"""

from __future__ import annotations

import numpy as np
import pytest
from PIL import Image

from app.core.config import BACK_ROOT
from app.services.cam import (
    CamError,
    OnnxCamExplainer,
    classification_weights,
    feature_tensor,
)

MODEL_DIR = BACK_ROOT / "app" / "models"
MODEL = next(iter(sorted(MODEL_DIR.glob("*.onnx"))), None)
MODEL_AVAILABLE = MODEL is not None and MODEL.exists()
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def _tiny_model(path, *, transposed: bool = True):
    """Conv 1x1 -> GAP -> Gemm con pesos conocidos (3 clases, 2 características)."""

    import onnx
    from onnx import TensorProto, helper, numpy_helper

    features, classes = 2, 3
    conv_w = np.zeros((features, 3, 3, 3), dtype=np.float32)
    conv_w[0, 0, 1, 1] = 1.0
    conv_w[1, 1, 1, 1] = 1.0
    # Clase 2 con pesos negativos: su CAM queda vacío tras ReLU.
    class_w = np.array([[1.0, 0.0], [0.0, 1.0], [-1.0, -1.0]], dtype=np.float32)
    if not transposed:
        class_w = class_w.T

    nodes = [
        helper.make_node("Conv", ["images", "conv_w"], ["features"], pads=[1, 1, 1, 1]),
        helper.make_node("GlobalAveragePool", ["features"], ["pooled"]),
        helper.make_node("Flatten", ["pooled"], ["flat"]),
        helper.make_node(
            "Gemm", ["flat", "class_w"], ["logits"], transB=1 if transposed else 0
        ),
        helper.make_node("Softmax", ["logits"], ["probs"], axis=1),
    ]
    graph = helper.make_graph(
        nodes,
        "tiny-cls",
        [helper.make_tensor_value_info("images", TensorProto.FLOAT, [1, 3, 8, 8])],
        [helper.make_tensor_value_info("probs", TensorProto.FLOAT, [1, classes])],
        [
            numpy_helper.from_array(conv_w, "conv_w"),
            numpy_helper.from_array(class_w, "class_w"),
        ],
    )
    model = helper.make_model(graph, opset_imports=[helper.make_opsetid("", 12)])
    model.ir_version = 7
    onnx.save(model, str(path))
    return model


def test_feature_tensor_is_the_pooling_input(tmp_path) -> None:
    model = _tiny_model(tmp_path / "tiny.onnx")
    assert feature_tensor(model.graph) == "features"


def test_classification_weights_reads_embedded_matrix(tmp_path) -> None:
    model = _tiny_model(tmp_path / "tiny.onnx")
    assert classification_weights(model.graph).shape == (3, 2)


def test_explainer_renders_png(tmp_path) -> None:
    path = tmp_path / "tiny.onnx"
    _tiny_model(path)
    explainer = OnnxCamExplainer(path)

    assert explainer.ready is True
    assert explainer._input_size == 8
    png = explainer.render(Image.new("RGB", (32, 32), (120, 120, 120)), 0)
    assert png.startswith(PNG_MAGIC)
    assert png.endswith(b"IEND\xaeB`\x82")


def test_explainer_accepts_matmul_weight_layout(tmp_path) -> None:
    path = tmp_path / "tiny.onnx"
    _tiny_model(path, transposed=False)
    explainer = OnnxCamExplainer(path)

    assert explainer.ready is True
    assert explainer._weights.shape == (3, 2)
    assert explainer.render(Image.new("RGB", (16, 16), (90, 90, 90)), 1).startswith(
        PNG_MAGIC
    )


def test_render_rejects_out_of_range_class(tmp_path) -> None:
    path = tmp_path / "tiny.onnx"
    _tiny_model(path)
    explainer = OnnxCamExplainer(path)

    with pytest.raises(CamError):
        explainer.render(Image.new("RGB", (16, 16), (90, 90, 90)), 3)


def test_render_reports_empty_map(tmp_path) -> None:
    path = tmp_path / "tiny.onnx"
    _tiny_model(path)
    explainer = OnnxCamExplainer(path)

    with pytest.raises(CamError):
        explainer.render(Image.new("RGB", (16, 16), (90, 90, 90)), 2)


def test_missing_artifact_is_not_ready(tmp_path) -> None:
    explainer = OnnxCamExplainer(tmp_path / "does-not-exist.onnx")

    assert explainer.ready is False
    with pytest.raises(CamError):
        explainer.render(Image.new("RGB", (16, 16), (0, 0, 0)), 0)


@pytest.mark.skipif(not MODEL_AVAILABLE, reason="modelo ONNX no disponible")
def test_real_model_produces_deterministic_map() -> None:
    explainer = OnnxCamExplainer(MODEL)

    assert explainer.ready is True
    image = Image.new("RGB", (224, 224), (110, 110, 110))
    first = explainer.render(image, 0)
    second = explainer.render(image, 0)
    assert first.startswith(PNG_MAGIC)
    assert first == second
