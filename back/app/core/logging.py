"""Configuración mínima de logging para la aplicación.

Se configura un handler propio para el logger ``nerilum`` (el root no tiene
handlers bajo uvicorn), para que los errores no controlados queden visibles
tanto con ``python -m app`` como con ``uvicorn app.main:app``.
"""

import logging

LOGGER_NAME = "nerilum"


def configure_logging(level: int = logging.INFO) -> None:
    logger = logging.getLogger(LOGGER_NAME)
    if logger.handlers:
        return
    handler = logging.StreamHandler()
    handler.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s")
    )
    logger.addHandler(handler)
    logger.setLevel(level)
    # Evita duplicar el registro si otro componente configura el root logger.
    logger.propagate = False
