import pytest
from pydantic import ValidationError

from app.schemas.prediction import AnalysisPrediction


def test_prediction_preserves_real_argmax_when_rounding_creates_tie():
    prediction = AnalysisPrediction.from_scores({
        "NonDemented": 0.4000001,
        "VeryMildDemented": 0.4000002,
        "MildDemented": 0.1,
        "ModerateDemented": 0.0999997,
    })
    assert prediction.category.value == "VeryMildDemented"
    assert prediction.probability == prediction.scores.VeryMildDemented == 0.4


@pytest.mark.parametrize("category,probability", [
    ("NonDemented", 0.4),  # No coincide con scores[category].
    ("MildDemented", 0.2),  # Coincide, pero no es la puntuación máxima.
])
def test_prediction_rejects_incoherent_category_or_probability(category, probability):
    with pytest.raises(ValidationError):
        AnalysisPrediction(
            category=category, probability=probability,
            scores={"NonDemented": 0.5, "VeryMildDemented": 0.2,
                    "MildDemented": 0.2, "ModerateDemented": 0.1},
        )


def test_prediction_tolerates_normal_float32_normalization_error():
    prediction = AnalysisPrediction.from_scores({
        "NonDemented": 0.10000000149011612,
        "VeryMildDemented": 0.20000000298023224,
        "MildDemented": 0.30000001192092896,
        "ModerateDemented": 0.4000000059604645,
    })
    assert prediction.probability == 0.4
    assert sum(prediction.scores.model_dump().values()) == 1.0
