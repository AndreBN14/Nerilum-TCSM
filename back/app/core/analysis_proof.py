"""Comprobante firmado de inferencia, vinculado al usuario y sin imagen."""

import base64
import binascii
import hashlib
import hmac
import json
import secrets
from datetime import datetime, timedelta, timezone

from pydantic import ValidationError

from app.core.errors import ApiException
from app.schemas.analysis import ModelMetadata
from app.schemas.prediction import AnalysisPrediction

PROOF_LIFETIME = timedelta(minutes=30)


def _encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _decode(value: str) -> bytes:
    return base64.b64decode(value + "=" * (-len(value) % 4), altchars=b"-_", validate=True)


def require_secret(secret: str) -> bytes:
    if len(secret) < 32:
        raise ApiException(503, "service_unavailable", "La previsualización aún no está configurada.")
    return secret.encode("utf-8")


def issue_proof(*, user_id: str, prediction: AnalysisPrediction,
                model: ModelMetadata, secret: str) -> tuple[dict, str]:
    key = require_secret(secret)
    now = datetime.now(timezone.utc)
    issued_at = now.strftime("%Y-%m-%dT%H:%M:%SZ")
    expires_at = (now + PROOF_LIFETIME).strftime("%Y-%m-%dT%H:%M:%SZ")
    payload = {
        "v": 1,
        "user_id": user_id,
        "preview_id": f"an_{secrets.token_hex(16)}",
        "created_at": issued_at,
        "expires_at": expires_at,
        "category": prediction.category.value,
        "probability": prediction.probability,
        "scores": prediction.scores.model_dump(),
        "model": model.model_dump(),
    }
    encoded = _encode(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8"))
    signature = _encode(hmac.digest(key, encoded.encode("ascii"), "sha256"))
    return payload, f"{encoded}.{signature}"


def verify_proof(proof: str, *, user_id: str, secret: str) -> dict:
    key = require_secret(secret)
    if len(proof) > 8192:
        raise ApiException(422, "validation_error", "El comprobante de análisis no es válido.")
    try:
        encoded, signature = proof.split(".")
        if not hmac.compare_digest(
            hmac.digest(key, encoded.encode("ascii"), "sha256"), _decode(signature)
        ):
            raise ValueError("Firma incorrecta")
        payload = json.loads(_decode(encoded))
        if not isinstance(payload, dict) or payload.get("v") != 1 or payload.get("user_id") != user_id:
            raise ValueError("Usuario o versión incorrectos")
        preview_id = payload["preview_id"]
        if not isinstance(preview_id, str) or not preview_id.startswith("an_") or len(preview_id) != 35:
            raise ValueError("Identificador incorrecto")
        int(preview_id[3:], 16)
        prediction = AnalysisPrediction.model_validate({
            "category": payload["category"], "probability": payload["probability"],
            "scores": payload["scores"],
        })
        model = ModelMetadata.model_validate(payload["model"])
        created_at = datetime.fromisoformat(payload["created_at"].replace("Z", "+00:00"))
        expires_at = datetime.fromisoformat(payload["expires_at"].replace("Z", "+00:00"))
        if created_at.utcoffset() != timedelta(0) or expires_at.utcoffset() != timedelta(0):
            raise ValueError("Fechas sin UTC")
        if expires_at - created_at != PROOF_LIFETIME:
            raise ValueError("Vigencia incorrecta")
        payload["prediction"] = prediction
        payload["model_info"] = model
        payload["expiration"] = expires_at
        return payload
    except (ValueError, KeyError, TypeError, UnicodeError, binascii.Error, ValidationError) as exc:
        raise ApiException(422, "validation_error", "El comprobante de análisis no es válido.") from exc


def save_request_hash(preview_id: str, display_name: str | None) -> str:
    data = json.dumps([preview_id, display_name], ensure_ascii=False, separators=(",", ":"))
    return hashlib.sha256(data.encode("utf-8")).hexdigest()
