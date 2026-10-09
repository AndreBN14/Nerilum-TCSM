from typing import Protocol


class InferenceStatus(Protocol):
    """Contrato de disponibilidad; entradas/salidas de inferencia pendientes."""

    @property
    def ready(self) -> bool: ...


class UnavailableInference:
    """Estado real del prototipo: aún no hay modelo conectado."""

    @property
    def ready(self) -> bool:
        return False
