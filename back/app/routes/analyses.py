"""Router reservado para el contrato de análisis aún pendiente.

No se publican endpoints ni se inventan schemas/resultados hasta aprobar
entradas, salidas, propiedad y almacenamiento. Las rutas futuras usarán
dependencias de servicios, no acceso a datos/modelo dentro del handler.
"""

from fastapi import APIRouter

router = APIRouter(prefix="/analyses", tags=["analyses"])
