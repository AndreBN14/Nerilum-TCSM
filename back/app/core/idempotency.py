import hashlib
import json

from app.core.errors import ApiException


def analysis_request_hash(image: bytes, display_name: str | None) -> str:
    """Huella de bytes y nombre normalizado, sin persistir la imagen.

    No incluye filename, boundary multipart ni versión del modelo: un reintento
    de una operación ya completada debe recuperar su resultado original.
    """
    metadata = json.dumps(
        {"display_name": display_name}, ensure_ascii=False, separators=(",", ":")
    ).encode("utf-8")
    digest = hashlib.sha256(b"nerilum-analysis-v1\0")
    digest.update(len(metadata).to_bytes(8, "big"))
    digest.update(metadata)
    digest.update(image)
    return digest.hexdigest()


def require_same_request(stored_hash: str | None, request_hash: str) -> None:
    if stored_hash != request_hash:
        raise ApiException(
            409, "idempotency_conflict",
            "Esta clave de idempotencia ya se utilizó con otra solicitud.",
        )
