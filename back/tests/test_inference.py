"""Pruebas de la capa de inferencia ONNX (carga, preprocesado, softmax y mapeo).

El clasificador real solo se ejercita si hay un ``*.onnx`` en la carpeta del
modelo; si no, el resto de pruebas cubren el comportamiento sin modelo. El
nombre del artefacto no se fija aquí: se descubre el único ``*.onnx`` presente.
"""

from __future__ import annotations

import shutil

import numpy as np
import pytest
from PIL import Image

from app.core.config import BACK_ROOT
from app.services.inference import OnnxClassifier, UnavailableInference

MODEL_DIR = BACK_ROOT / "app" / "models"
# El nombre del artefacto no se fija: se usa el único *.onnx de MODEL_DIR
# (p. ej. nerilum-alzheimer-mri-classifier.onnx). Si no hay ninguno, MODEL es
# None y las pruebas que ejercitan el modelo se omiten.
MODEL = next(iter(sorted(MODEL_DIR.glob("*.onnx"))), None)
MODEL_AVAILABLE = MODEL is not None and MODEL.exists()
MISSING_DIR = MODEL_DIR / "does-not-exist"

EXPECTED_NAMES = [
    "MildDemented",
    "ModerateDemented",
    "NonDemented",
    "VeryMildDemented",
]


def test_unavailable_inference_reports_false() -> None:
    service = UnavailableInference()
    assert service.ready is False
    assert service.model_info is None


def test_classifier_missing_directory_is_not_ready() -> None:
    service = OnnxClassifier(MISSING_DIR)
    assert service.ready is False
    assert service.model_info is None


def test_softmax_normalizes_to_one() -> None:
    values = OnnxClassifier(MISSING_DIR)._softmax([1.0, 2.0, 3.0])
    assert sum(values) == pytest.approx(1.0)
    assert max(values) < 1.0 and min(values) > 0.0


def test_preprocess_shapes_for_every_resize_mode() -> None:
    image = Image.new("RGB", (200, 100), (128, 128, 128))
    for mode in ("stretch", "center_crop", "letterbox"):
        service = OnnxClassifier(MISSING_DIR, resize_mode=mode, input_size=224)
        batch = service._preprocess(image)
        assert batch.shape == (1, 3, 224, 224)
        assert batch.dtype.name == "float32"
        assert batch.min() >= 0.0 and batch.max() <= 1.0


def test_preprocess_default_resize_mode_is_center_crop() -> None:
    # Default: pipeline de inferencia de referencia de Ultralytics
    # (Resize del lado corto + CenterCrop), no letterbox.
    service = OnnxClassifier(MISSING_DIR)
    assert service._resize_mode == "center_crop"
    image = Image.new("RGB", (100, 200), (128, 128, 128))
    batch = service._preprocess(image)
    assert batch.shape == (1, 3, 224, 224)


def test_default_softmax_is_disabled() -> None:
    # El ONNX ya devuelve probabilidades normalizadas.
    assert OnnxClassifier(MISSING_DIR)._apply_softmax is False


def test_center_crop_matches_ultralytics_reference() -> None:
    # Referencia Ultralytics (inferencia): Resize del lado corto a size,
    # CenterCrop cuadrado, escala 0-1 (Normalize mean=0/std=1 es no-op),
    # formato NCHW float32.
    image = Image.new("RGB", (257, 193), (90, 140, 210))

    def reference(img: Image.Image, size: int) -> np.ndarray:
        rgb = img.convert("RGB")
        scale = size / min(rgb.size)
        resized = rgb.resize(
            (max(1, round(rgb.width * scale)), max(1, round(rgb.height * scale))),
            Image.BILINEAR,
        )
        left = (resized.width - size) // 2
        top = (resized.height - size) // 2
        cropped = resized.crop((left, top, left + size, top + size))
        arr = np.asarray(cropped, dtype=np.float32) / 255.0
        return np.transpose(arr, (2, 0, 1))[np.newaxis, :, :, :]

    batch = OnnxClassifier(MISSING_DIR, resize_mode="center_crop", input_size=224)._preprocess(image)
    assert np.array_equal(batch, reference(image, 224))


@pytest.mark.skipif(not MODEL_AVAILABLE, reason="modelo ONNX no disponible")
def test_card_absent_leaves_model_not_ready(tmp_path) -> None:
    shutil.copy(MODEL, tmp_path / MODEL.name)
    service = OnnxClassifier(tmp_path)
    assert service.ready is False
    assert service.model_info is None


@pytest.mark.skipif(not MODEL_AVAILABLE, reason="modelo ONNX no disponible")
def test_real_model_loads_info_from_card_and_metadata() -> None:
    service = OnnxClassifier(MODEL_DIR)
    assert service.ready is True
    assert service.model_info is not None
    assert service.model_info.name == "yolov5-cls"
    assert service.model_info.version == "v1.0"
    assert service.model_info.dataset == "Alzheimer MRI Dataset (Kaggle)"
    assert sorted(service.model_info.classes) == sorted(EXPECTED_NAMES)
    assert service._input_size == 224
    image = Image.new("RGB", (256, 256), (180, 180, 180))
    batch = service._preprocess(image)
    assert batch.shape == (1, 3, 224, 224)
    assert batch.dtype.name == "float32"


@pytest.mark.skipif(not MODEL_AVAILABLE, reason="modelo ONNX no disponible")
def test_names_order_matches_onnx_metadata() -> None:
    """Las clases del modelo coinciden con las categorías esperadas.

    El nuevo modelo no incluye 'names' en su custom_metadata ONNX; las clases
    se leen del model_card.json. Solo se verifica que el conjunto sea correcto.
    """
    service = OnnxClassifier(MODEL_DIR)
    assert sorted(service.model_info.classes) == sorted(EXPECTED_NAMES)


@pytest.mark.skipif(not MODEL_AVAILABLE, reason="modelo ONNX no disponible")
def test_real_model_output_is_already_normalized() -> None:
    # La salida cruda del ONNX ya es una distribución de probabilidad:
    # suma 1.0 y valores en (0, 1). No debe aplicarse softmax de nuevo.
    service = OnnxClassifier(MODEL_DIR)
    image = Image.new("RGB", (256, 256), (180, 180, 180))
    batch = service._preprocess(image)
    outputs = service._session.run(None, {"images": np.asarray(batch, dtype=np.float32)})
    scores = np.asarray(outputs[0]).reshape(-1)
    assert scores.shape == (4,)
    assert scores.min() > 0.0 and scores.max() < 1.0
    assert scores.sum() == pytest.approx(1.0, abs=1e-4)


@pytest.mark.skipif(not MODEL_AVAILABLE, reason="modelo ONNX no disponible")
def test_real_model_analyze_preserves_normalized_probabilities() -> None:
    service_raw = OnnxClassifier(MODEL_DIR, softmax=False)
    service_soft = OnnxClassifier(MODEL_DIR, softmax=True)
    image = Image.new("RGB", (256, 256), (180, 180, 180))

    raw = np.fromiter(service_raw.analyze(image).values(), dtype=np.float64)
    # Con softmax desactivado se conservan las probabilidades del ONNX.
    assert raw.sum() == pytest.approx(1.0, abs=1e-4)
    assert raw.min() > 0.0 and raw.max() < 1.0

    # Aplicar softmax de nuevo cambia los valores (doble softmax) aunque no
    # altera el argmax. Esto documenta por qué MODEL_SOFTMAX=false.
    soft = np.fromiter(service_soft.analyze(image).values(), dtype=np.float64)
    assert soft.sum() == pytest.approx(1.0, abs=1e-4)
    assert not np.allclose(raw, soft)
    assert int(np.argmax(raw)) == int(np.argmax(soft))


@pytest.mark.skipif(not MODEL_AVAILABLE, reason="modelo ONNX no disponible")
def test_real_model_class_mapping_and_argmax() -> None:
    service = OnnxClassifier(MODEL_DIR)
    image = Image.new("RGB", (256, 256), (180, 180, 180))
    scores = service.analyze(image)
    assert set(scores) == set(EXPECTED_NAMES)
    assert all(0.0 < v < 1.0 for v in scores.values())
    assert sum(scores.values()) == pytest.approx(1.0, abs=1e-4)
    category, probability = max(scores.items(), key=lambda item: item[1])
    # El argmax del dict debe coincidir con la clase de mayor probabilidad
    argmax_class = max(scores, key=lambda k: scores[k])
    assert category == argmax_class
    assert probability == max(scores.values())


def test_analyze_without_session_raises() -> None:
    with pytest.raises(Exception) as excinfo:
        OnnxClassifier(MISSING_DIR).analyze(Image.new("RGB", (8, 8)))
    assert "no está disponible" in str(excinfo.value)
