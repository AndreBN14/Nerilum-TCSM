from dataclasses import dataclass

from app.core.config import Settings
from app.services.inference import InferenceStatus, UnavailableInference


@dataclass
class Services:
    """Punto de composición para inyectar futuros servicios/adaptadores."""

    inference: InferenceStatus


def create_services(settings: Settings) -> Services:
    # MODEL_PATH no implica que ya exista un runtime o un modelo validado.
    return Services(inference=UnavailableInference())
