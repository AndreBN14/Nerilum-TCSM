"""Validación de salida del clasificador antes de construir un registro."""

from math import isclose
from typing import Self

from pydantic import BaseModel, model_validator

from app.schemas.analysis import Category, Probability, Scores


class AnalysisPrediction(BaseModel):
    category: Category
    probability: Probability
    scores: Scores

    @model_validator(mode="after")
    def validate_distribution(self) -> Self:
        values = self.scores.model_dump()
        # El contrato actual recibe probabilidades normalizadas (no logits).
        # Se tolera únicamente error numérico, no se aplica softmax ni se corrige
        # una distribución inválida silenciosamente.
        if not isclose(sum(values.values()), 1.0, rel_tol=0, abs_tol=1e-5):
            raise ValueError("Las puntuaciones deben sumar aproximadamente uno.")
        if self.probability != values[self.category.value]:
            raise ValueError("La probabilidad no coincide con la categoría.")
        if self.probability != max(values.values()):
            raise ValueError("La categoría no tiene la puntuación máxima.")
        return self

    @classmethod
    def from_scores(cls, raw_scores: object) -> Self:
        # Validar ANTES de redondear: un negativo pequeño no se convierte en 0.
        scores = Scores.model_validate(raw_scores)
        values = scores.model_dump()
        category = max(values, key=values.__getitem__)
        prediction = cls(
            category=category, probability=values[category], scores=scores
        )
        rounded = {name: round(value, 6) for name, value in values.items()}
        # Seleccionar con valores originales evita cambiar el argmax por empate
        # artificial al redondear. La puntuación almacenada conserva la igualdad.
        return cls(
            category=prediction.category,
            probability=rounded[category],
            scores=Scores.model_validate(rounded),
        )
